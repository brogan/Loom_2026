import CoreGraphics
import CoreImage
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Error

public enum SpriteSceneError: Error, LocalizedError {
    case polygonFileNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .polygonFileNotFound(let url):
            return "Polygon file not found: \(url.path)"
        }
    }
}

// MARK: - SpriteScene

/// An assembled, runnable scene built from a `ProjectConfig`.
///
/// ### Lifecycle
/// ```swift
/// var scene = try SpriteScene(config: config, projectDirectory: projectDir)
/// var rng   = SystemRandomNumberGenerator()
/// scene.advance(using: &rng)          // step one frame
/// scene.render(into: ctx,
///              viewTransform: vt,
///              using: &rng)            // draw the current frame
/// ```
///
/// ### Coordinate conventions
/// Polygon geometry is in world space (origin at canvas centre, Y-up).
/// `render` expects the caller to have applied a Y-flip transform to the
/// `CGContext` before the call (matching the contract of `RenderEngine`).
public struct SpriteScene: @unchecked Sendable {

    // Shared CIContext for per-renderer Gaussian blur. CIContext is internally
    // thread-safe for createCGImage calls.
    private nonisolated(unsafe) static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// All resolved sprite instances, in declaration order from `sprites.xml`.
    public var instances: [SpriteInstance]

    /// SVG images for SVG-sprite rendering, keyed by filename. Set by `LoomEngine` at init.
    /// Sprites with a matching `def.svgFilename` bypass the polygon pipeline and draw the image.
#if canImport(AppKit)
    public var svgImages: [String: NSImage] = [:]
#endif

    /// Pixel-space multiplier; all per-instance pixel distances are scaled by this factor.
    private let qualityMultiple: Int

    /// When false, pixel-based style values (stroke width, point size, brush/stencil sizes)
    /// are used at their raw logical-pixel values regardless of `qualityMultiple`.
    /// When true (the default), they are scaled by `qualityMultiple` so the rendered output
    /// looks the same after a `qualityMultiple`-fold downscale.
    private let scaleImage: Bool

    /// Frame rate for driver evaluation (oscillator / noise modes).
    private let targetFPS: Double

    /// All renderer sets keyed by name, for fast lookup by the rendererSet driver.
    private let allRendererSets: [String: RendererSet]

    /// All subdivision-params sets keyed by name, for fast lookup by the subdivisionSet driver.
    private let allSubdivisionSets: [String: [SubdivisionParams]]

    /// Compositing layers from project config.  Empty = legacy flat depth-sort path.
    var layers: [LoomLayer] = []

    /// Persistent offscreen buffers for `.once` and `.accumulate` layers, keyed by layer UUID.
    /// Created on first use; retained across frames. Cleared by the invalidation helpers below.
    var layerBuffers: [UUID: CGContext] = [:]

    /// Theatrical lighting configuration. Synced from `ProjectConfig.lightingConfig`.
    var lightingConfig: LightingConfig = LightingConfig()

    /// Per-layer cached light maps.  Keyed by layer ID; recomputed when the full
    /// lighting config or the elapsed frame changes for that layer's entry.
    private var lightMapCache: [UUID: (config: LightingConfig, elapsed: Double, image: CGImage)] = [:]

    /// Named sprite cycles keyed by name for O(1) lookup during render.
    private let allCycles: [String: SpriteCycle]

    // MARK: - Convenience (testing)

    /// Directly construct a scene from pre-built instances.
    ///
    /// Intended for unit tests that want to bypass file loading.
    internal init(instances: [SpriteInstance]) {
        self.instances         = instances
        self.qualityMultiple   = 1
        self.scaleImage        = true
        self.targetFPS         = 30
        self.allRendererSets   = [:]
        self.allSubdivisionSets = [:]
        self.allCycles         = [:]
    }

    // MARK: - Assembly

    /// Build a scene from `config`, loading polygon and morph-target files from
    /// `projectDirectory`.
    ///
    /// - Throws: `SpriteSceneError.polygonFileNotFound` if a required polygon
    ///   file is missing.  Morph-target files that are absent are silently
    ///   replaced with empty arrays so a bad reference doesn't block the whole
    ///   load.
    public init(config: ProjectConfig, projectDirectory: URL) throws {
        var result: [SpriteInstance] = []
        for spriteSet in config.spriteConfig.library.spriteSets {
            for sprite in spriteSet.sprites where sprite.enabled {
                var instance = try SpriteScene.makeInstance(
                    sprite:          sprite,
                    sameSetSprites:  spriteSet.sprites,
                    config:          config,
                    projectDirectory: projectDirectory
                )
                instance.spriteSetName = spriteSet.name
                result.append(instance)
            }
        }
        // ── Propagate container cycle to descendants ─────────────────────────
        // A no-geometry sprite (no shapeSetName/shapeName) with a cycleName is
        // a rig root. Walk each sprite's parent chain; if an ancestor is such a
        // container, inherit its cycle so only the root needs cycleName set.
        let nameToIdx: [String: Int] = Dictionary(
            result.enumerated().map { ($0.element.def.name, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        for i in result.indices {
            guard result[i].def.cycleName == nil else { continue }
            var cur = result[i].def.parentName
            while let parentName = cur {
                guard let pi = nameToIdx[parentName] else { break }
                let parent = result[pi]
                if parent.def.shapeSetName.isEmpty && parent.def.shapeName.isEmpty,
                   let inherited = parent.def.cycleName {
                    result[i].def.cycleName = inherited
                    break
                }
                cur = parent.def.parentName
            }
        }

        self.instances        = result
        self.qualityMultiple  = max(1, config.globalConfig.qualityMultiple)
        self.scaleImage       = config.globalConfig.scaleImage
        self.targetFPS        = max(1, config.globalConfig.targetFPS)
        self.allRendererSets  = Dictionary(
            config.renderingConfig.library.rendererSets.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.allSubdivisionSets = Dictionary(
            config.subdivisionConfig.paramsSets.map { ($0.name, $0.params) },
            uniquingKeysWith: { first, _ in first }
        )
        self.allCycles = Dictionary(
            config.cycles.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.layers         = config.layers
        self.lightingConfig = config.lightingConfig
    }

    private static func makeInstance(
        sprite:          SpriteDef,
        sameSetSprites:  [SpriteDef] = [],
        config:          ProjectConfig,
        projectDirectory: URL
    ) throws -> SpriteInstance {

        // ── 1. Resolve the ShapeDef ──────────────────────────────────────────
        let shapeDef = config.shapeConfig.library.shapeSets
            .first(where: { $0.name == sprite.shapeSetName })?
            .shapes.first(where: { $0.name == sprite.shapeName })

        // ── 2. Load base polygons ────────────────────────────────────────────
        let basePolygons: [Polygon2D]
        if let sd = shapeDef {
            basePolygons = try loadBasePolygons(
                shapeDef: sd,
                config: config,
                projectDirectory: projectDirectory
            )
        } else {
            basePolygons = []
        }

        // ── 3. Load morph targets ────────────────────────────────────────────
        // Priority 1: shape name in the same shapeset.
        // Priority 2: layer name in the base shape's own polygon file (for
        //             multi-layer editable geometry documents where the user
        //             names layers "base", "drift", etc.).
        // Legacy fallback: load from morphTargets/ subdirectory.
        let morphTargetPolygons: [[Polygon2D]]
        if !sprite.morphTargetNames.isEmpty {
            let shapeSet = config.shapeConfig.library.shapeSets
                .first(where: { $0.name == sprite.shapeSetName })

            // Pre-resolve the base shape's polygon file URL for layer-name fallback.
            let basePolyURL: URL? = {
                guard let sd = shapeDef,
                      sd.sourceType == .polygonSet,
                      let polyDef = config.polygonConfig.library.polygonSets
                          .first(where: { $0.name == sd.polygonSetName }),
                      polyDef.filename.lowercased().hasSuffix(".json")
                else { return nil }
                let folder = (polyDef.folder == "polygonSet" || polyDef.folder.isEmpty)
                    ? "polygonSets" : polyDef.folder
                return projectDirectory.appendingPathComponent(folder)
                                       .appendingPathComponent(polyDef.filename)
            }()

            morphTargetPolygons = sprite.morphTargetNames.compactMap { targetName in
                guard !targetName.isEmpty else { return nil }

                // Priority 1: shape name lookup.
                if let sd = shapeSet?.shapes.first(where: { $0.name == targetName }),
                   let polys = try? loadBasePolygons(shapeDef: sd, config: config,
                                                     projectDirectory: projectDirectory) {
                    guard polys.count == basePolygons.count,
                          zip(polys, basePolygons).allSatisfy({ $0.points.count == $1.points.count })
                    else {
                        print("[Morph] shape '\(targetName)' skipped: point count mismatch")
                        return nil
                    }
                    return polys
                }

                // Priority 2: layer name in the base geometry file.
                if let url = basePolyURL,
                   let polys = try? EditableGeometryJSONLoader.load(url: url)
                       .runtimePolygons(targetLayerName: targetName),
                   !polys.isEmpty {
                    guard polys.count == basePolygons.count,
                          zip(polys, basePolygons).allSatisfy({ $0.points.count == $1.points.count })
                    else {
                        print("[Morph] layer '\(targetName)' skipped: point count mismatch")
                        return nil
                    }
                    return polys
                }

                print("[Morph] '\(targetName)': no matching shape or layer found")
                return nil
            }
        } else {
            // Legacy: load from morphTargets/ subdirectory.
            morphTargetPolygons = sprite.animation.morphTargets.map { ref in
                let url = projectDirectory
                    .appendingPathComponent("morphTargets")
                    .appendingPathComponent(ref.file)
                return (try? XMLPolygonLoader.load(url: url)) ?? []
            }
        }

        // ── 4. Resolve renderer set ──────────────────────────────────────────
        let rendererSet = config.renderingConfig.library
            .rendererSet(named: sprite.rendererSetName)
            ?? RendererSet(name: sprite.rendererSetName,
                           renderers: [Renderer(name: "default")])

        // ── 5. Resolve subdivision params ────────────────────────────────────
        let paramsName = shapeDef?.subdivisionParamsSetName ?? ""
        let subdivParams: [SubdivisionParams]
        let curveRefinementParams:   [CurveRefinementParams]
        let segmentExtractionParams: [SegmentExtractionParams]
        if paramsName.isEmpty || paramsName.caseInsensitiveCompare("none") == .orderedSame {
            subdivParams             = []
            curveRefinementParams    = []
            segmentExtractionParams  = []
        } else {
            let resolvedSet          = config.subdivisionConfig.paramsSet(named: paramsName)
            subdivParams             = resolvedSet?.params ?? []
            curveRefinementParams    = resolvedSet?.curveRefinement ?? []
            segmentExtractionParams  = resolvedSet?.segmentExtraction ?? []
        }

        // ── 6. Load shape-sequence polygon sets ─────────────────────────────
        let sequencePolygons: [[Polygon2D]]
        if let seq = sprite.shapeSequence, !seq.shapeSetNames.isEmpty {
            sequencePolygons = seq.shapeSetNames.compactMap { setName in
                guard let sd = config.shapeConfig.library.shapeSets
                    .first(where: { $0.name == setName })?
                    .shapes.first(where: { $0.name == sprite.shapeName })
                else { return nil }
                return try? loadBasePolygons(shapeDef: sd, config: config, projectDirectory: projectDirectory)
            }
        } else {
            sequencePolygons = []
        }

        // ── 7. Load sprite-replacement variants ─────────────────────────────
        var variantPolygons:       [[Polygon2D]] = []
        var variantRendererSets:   [RendererSet] = []
        var variantImageFilenames: [String?]     = []
        for entry in sprite.spriteVariants {
            guard let variantDef = sameSetSprites.first(where: { $0.name == entry.spriteName }) else { continue }
            let vShapeDef = config.shapeConfig.library.shapeSets
                .first(where: { $0.name == variantDef.shapeSetName })?
                .shapes.first(where: { $0.name == variantDef.shapeName })
            let vPolygons = vShapeDef.flatMap { try? loadBasePolygons(shapeDef: $0, config: config, projectDirectory: projectDirectory) } ?? []
            let vRendererSet = config.renderingConfig.library
                .rendererSet(named: variantDef.rendererSetName)
                ?? RendererSet(name: variantDef.rendererSetName, renderers: [Renderer(name: "default")])
            variantPolygons.append(vPolygons)
            variantRendererSets.append(vRendererSet)
            variantImageFilenames.append(entry.imageFilename)
        }

        // ── 8. Load SpriteCycle state polygons ──────────────────────────────
        var cycleStatePolygons:     [[Polygon2D]]  = []
        var cycleStateRendererSets: [RendererSet?] = []
        if let cycleName = sprite.cycleName,
           let cycle = config.cycles.first(where: { $0.name == cycleName }) {
            for state in cycle.states {
                let stateShapeDef = config.shapeConfig.library.shapeSets
                    .first(where: { $0.name == state.shapeSetName })?
                    .shapes.first(where: { $0.name == state.shapeName })
                let polys = stateShapeDef.flatMap {
                    try? loadBasePolygons(shapeDef: $0, config: config, projectDirectory: projectDirectory)
                } ?? []
                cycleStatePolygons.append(polys)
                let overrideSet = state.rendererSetName.flatMap {
                    config.renderingConfig.library.rendererSet(named: $0)
                }
                cycleStateRendererSets.append(overrideSet)
            }
        }

        // ── 9. Pre-load cycle geometry for cycleNameDriver references ────────
        var driverCycleData: [String: CycleRenderData] = [:]
        if let drivers = sprite.animation.drivers, drivers.cycleName.enabled {
            let referencedNames = Set(
                ([drivers.cycleName.base] + drivers.cycleName.keyframes.map(\.value) + drivers.cycleName.jitterPool)
                    .filter { !$0.isEmpty }
            )
            for name in referencedNames {
                guard driverCycleData[name] == nil,
                      let cycle = config.cycles.first(where: { $0.name == name })
                else { continue }
                var polys: [[Polygon2D]] = []
                var sets:  [RendererSet?] = []
                for state in cycle.states {
                    let shapeDef = config.shapeConfig.library.shapeSets
                        .first(where: { $0.name == state.shapeSetName })?
                        .shapes.first(where: { $0.name == state.shapeName })
                    polys.append(shapeDef.flatMap {
                        try? loadBasePolygons(shapeDef: $0, config: config, projectDirectory: projectDirectory)
                    } ?? [])
                    sets.append(state.rendererSetName.flatMap {
                        config.renderingConfig.library.rendererSet(named: $0)
                    })
                }
                driverCycleData[name] = CycleRenderData(statePolygons: polys, stateRendererSets: sets)
            }
        }

        return SpriteInstance(
            def:                    sprite,
            basePolygons:           basePolygons,
            morphTargetPolygons:    morphTargetPolygons,
            rendererSet:            rendererSet,
            subdivisionParams:      subdivParams,
            curveRefinementParams:   curveRefinementParams,
            segmentExtractionParams: segmentExtractionParams,
            sequencePolygons:        sequencePolygons,
            variantPolygons:        variantPolygons,
            variantRendererSets:    variantRendererSets,
            variantImageFilenames:  variantImageFilenames,
            cycleStatePolygons:     cycleStatePolygons,
            cycleStateRendererSets: cycleStateRendererSets,
            driverCycleData:        driverCycleData,
            state:                  SpriteState.initial(for: rendererSet)
        )
    }

    // MARK: - Geometry loading

    /// Dispatch to the correct loader based on `shapeDef.sourceType`.
    private static func loadBasePolygons(
        shapeDef sd: ShapeDef,
        config: ProjectConfig,
        projectDirectory: URL
    ) throws -> [Polygon2D] {

        switch sd.sourceType {

        case .regularPolygon:
            // Matches Scala MySketch: PolygonCreator.makePolygon2D(sides, 1.0, 1.0)
            // — simple convex N-gon at radius 0.5, starting at top (0, -0.5).
            let sides = sd.regularPolygonSides
            guard sides >= 3 else { return [] }
            let radius  = 0.5
            let angInc  = 2.0 * .pi / Double(sides)
            var pts = [Vector2D]()
            pts.reserveCapacity(sides)
            for i in 0..<sides {
                let angle = Double(i) * angInc - .pi / 2   // start at 12 o'clock
                pts.append(Vector2D(x: radius * cos(angle), y: radius * sin(angle)))
            }
            return [Polygon2D(points: pts, type: .line)]

        case .polygonSet:
            guard !sd.polygonSetName.isEmpty,
                  let polyDef = config.polygonConfig.library.polygonSets
                      .first(where: { $0.name == sd.polygonSetName })
            else { return [] }

            // Regular polygon — generated algorithmically, no file needed.
            if let rp = polyDef.regularParams {
                return [RegularPolygonGenerator.generate(params: rp)]
            }

            // File-backed polygon set.
            // The XML Folder element defaults to "polygonSet" (singular) — Scala's
            // loader maps that sentinel to the canonical "polygonSets/" directory.
            // Any other folder value is used as-is relative to the project root.
            let resolvedFolder = (polyDef.folder == "polygonSet" || polyDef.folder.isEmpty)
                ? "polygonSets" : polyDef.folder
            let url = projectDirectory
                .appendingPathComponent(resolvedFolder)
                .appendingPathComponent(polyDef.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SpriteSceneError.polygonFileNotFound(url)
            }
            if polyDef.filename.lowercased().hasSuffix(".json") {
                return try EditableGeometryJSONLoader.load(url: url).runtimePolygons(
                    targetLayerID: polyDef.editableLayerID,
                    targetLayerName: polyDef.editableLayerName
                )
            }
            return try XMLPolygonLoader.load(url: url)

        case .openCurveSet:
            guard !sd.openCurveSetName.isEmpty,
                  let curveDef = config.curveConfig.library.curveSets
                      .first(where: { $0.name == sd.openCurveSetName })
            else { return [] }

            let url = projectDirectory
                .appendingPathComponent(curveDef.folder)
                .appendingPathComponent(curveDef.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SpriteSceneError.polygonFileNotFound(url)
            }
            return try XMLPolygonLoader.loadOpenCurveSet(url: url)

        case .ovalSet:
            guard !sd.ovalSetName.isEmpty,
                  let ovalDef = config.ovalConfig.library.ovalSets
                      .first(where: { $0.name == sd.ovalSetName })
            else { return [] }

            let url = projectDirectory
                .appendingPathComponent(ovalDef.folder)
                .appendingPathComponent(ovalDef.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SpriteSceneError.polygonFileNotFound(url)
            }
            return try XMLPolygonLoader.loadOvalSet(url: url)

        case .pointSet:
            guard !sd.pointSetName.isEmpty,
                  let pointDef = config.pointConfig.library.pointSets
                      .first(where: { $0.name == sd.pointSetName })
            else { return [] }

            let url = projectDirectory
                .appendingPathComponent(pointDef.folder)
                .appendingPathComponent(pointDef.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SpriteSceneError.polygonFileNotFound(url)
            }
            return try XMLPolygonLoader.loadPointSet(url: url)

        default:
            return []
        }
    }

    // MARK: - Advance

    /// Step every sprite one frame forward.
    ///
    /// - Parameters:
    ///   - deltaTime: Wall-clock seconds since the previous `advance` call.
    ///                Used to accumulate `SpriteState.elapsedTime` for time-based
    ///                keyframe interpolation.  Pass `1.0 / targetFPS` for fixed-rate export.
    ///   - targetFPS: The frame rate assumption used to convert keyframe `drawCycle`
    ///                integers to seconds.  Matches `GlobalConfig.targetFPS`.
    ///
    /// For each instance:
    /// 1. Accumulates `elapsedTime` and computes the `SpriteTransform` for the current time.
    /// 2. Advances the active renderer index according to the playback mode.
    /// 3. Steps the active renderer's palette states when `modifyInternalParameters` is `true`.
    /// 4. Increments `drawCycle`.
    /// Returns `true` if at least one sprite crossed a virtual-frame boundary this call.
    /// The caller uses this to gate accumulation-canvas sprite renders, preventing
    /// the 60 fps display timer from writing more layers than the virtual frame rate.
    @discardableResult
    public mutating func advance<RNG: RandomNumberGenerator>(
        deltaTime:     Double,
        targetFPS:     Double,
        globalElapsed: Double = 0,
        using rng: inout RNG
    ) -> Bool {
        var anyAdvanced = false
        for (i, _) in instances.enumerated() {
            if SpriteScene.advanceInstance(
                &instances[i],
                deltaTime:     deltaTime,
                targetFPS:     targetFPS,
                globalElapsed: globalElapsed,
                spriteIndex:   i,
                using:         &rng
            ) { anyAdvanced = true }
        }
        return anyAdvanced
    }

    /// Returns `true` if this instance crossed at least one virtual-frame boundary.
    private static func advanceInstance<RNG: RandomNumberGenerator>(
        _ instance:    inout SpriteInstance,
        deltaTime:     Double,
        targetFPS:     Double,
        globalElapsed: Double,
        spriteIndex:   Int,
        using rng: inout RNG
    ) -> Bool {
        // ── Continuous: update elapsed time and recompute the transform ────────
        // Gate on the per-sprite draw-cycle limit (totalDraws > 0 = hard stop after
        // that many virtual frames).  When the limit is reached the transform is frozen
        // at the last computed value — matching Scala's Sprite2D.update() which skips
        // animator.update() once spriteDrawCount >= spriteTotalDraws.
        // totalDraws == 0 means "animate indefinitely".
        let animation = instance.def.animation
        let withinLimit = animation.totalDraws == 0
            || instance.state.drawCycle < animation.totalDraws
        if withinLimit {
            instance.state.elapsedTime += deltaTime
            let perSpriteElapsed = instance.state.elapsedTime * max(1.0, targetFPS)
            instance.state.transform = TransformAnimator.transform(
                for:           animation,
                elapsedFrames: perSpriteElapsed,
                globalElapsed: globalElapsed,
                targetFPS:     targetFPS,
                spriteIndex:   spriteIndex,
                using:         &rng
            )
        }

        // ── Discrete: renderer switching, palette stepping, drawCycle ──────────
        // These are frame-count-based events (hold lengths, pauseMax values in XML
        // are all integers at targetFPS).  We accumulate real time and only fire
        // when we cross a virtual frame boundary (1/targetFPS seconds).
        let frameStep = 1.0 / max(1.0, targetFPS)
        instance.state.frameTimeAccumulator += deltaTime
        let framesToAdvance = Int(instance.state.frameTimeAccumulator / frameStep)
        guard framesToAdvance > 0 else { return false }
        instance.state.frameTimeAccumulator -= Double(framesToAdvance) * frameStep

        let renderers = instance.rendererSet.renderers
        let count     = renderers.count

        for _ in 0..<framesToAdvance {
            // 1. Advance renderer-set playback (hold length is in virtual frames).
            if count > 0 {
                SpriteScene.advanceRendererIndex(&instance.state,
                                                 rendererSet: instance.rendererSet,
                                                 using: &rng)
            }

            // 2. Advance palette state for the active renderer (if enabled).
            //    pauseMax values in XML are also virtual frame counts.
            let idx = instance.state.activeRendererIndex
            if count > 0,
               idx < count,
               instance.rendererSet.playbackConfig.modifyInternalParameters,
               idx < instance.state.rendererAnimationStates.count {
                let renderer = renderers[idx]
                instance.state.rendererAnimationStates[idx] = RenderStateEngine.advance(
                    state:         instance.state.rendererAnimationStates[idx],
                    changes:       renderer.changes,
                    stencilConfig: renderer.stencilConfig,
                    using:         &rng
                )
            }

            // 3. Increment the virtual frame counter.
            instance.state.drawCycle += 1
        }
        return true
    }

    private static func advanceRendererIndex<RNG: RandomNumberGenerator>(
        _ state: inout SpriteState,
        rendererSet: RendererSet,
        using rng: inout RNG
    ) {
        let count    = rendererSet.renderers.count
        let playback = rendererSet.playbackConfig
        guard count > 0 else { return }

        switch playback.mode {
        case .static, .all:
            break  // index never changes

        case .sequential:
            state.holdFramesRemaining -= 1
            if state.holdFramesRemaining <= 0 {
                state.activeRendererIndex = (state.activeRendererIndex + 1) % count
                state.holdFramesRemaining = rendererSet.renderers[state.activeRendererIndex].holdLength
            }

        case .random:
            let usePreferred = !playback.preferredRenderer.isEmpty &&
                Double.random(in: 0..<100, using: &rng) < playback.preferredProbability
            if usePreferred,
               let preferredIdx = rendererSet.renderers.firstIndex(where: {
                   $0.name == playback.preferredRenderer
               }) {
                state.activeRendererIndex = preferredIdx
            } else {
                state.activeRendererIndex = Int.random(in: 0..<count, using: &rng)
            }
        }
    }

    // MARK: - Render

    /// Draw the current frame into `context`.
    ///
    /// The caller must have applied a Y-flip transform to `context` so that
    /// `worldToScreen` coordinates land in the correct pixels (see `RenderEngine`).
    ///
    /// `rng` is used by `SubdivisionEngine` for any random visibility or centre
    /// jitter; pass a seeded generator for deterministic output.
    ///
    /// - Parameters:
    ///   - brushImages:    CGImages keyed by filename, used for `RendererMode.brushed` sprites.
    ///   - elapsedFrames:  Accumulated fractional frame count (= elapsed seconds × targetFPS),
    ///                     forwarded to the brush meander phase for frame-rate-independent animation.
    mutating func render<RNG: RandomNumberGenerator>(
        into context: CGContext,
        viewTransform: ViewTransform,
        brushImages: [String: CGImage] = [:],
        stampImages: [String: CGImage] = [:],
        elapsedFrames: Double = 0,
        perspectiveStrength: Double = 0,
        backgroundColor: CGColor = CGColor(gray: 0, alpha: 1),
        progressiveBrushStates: inout [String: BrushProgressiveState],
        progressiveBrushEnabled: Bool = false,
        using rng: inout RNG
    ) {
        if !layers.isEmpty {
            renderLayered(
                into: context,
                viewTransform: viewTransform,
                brushImages: brushImages,
                stampImages: stampImages,
                elapsedFrames: elapsedFrames,
                perspectiveStrength: perspectiveStrength,
                backgroundColor: backgroundColor,
                progressiveBrushStates: &progressiveBrushStates,
                progressiveBrushEnabled: progressiveBrushEnabled,
                using: &rng
            )
            return
        }

        // Legacy flat depth-sort path (no layers defined).
        var parentWorlds: [String: ParentWorld] = [:]
        for instance in cycleAdjustedInstances(elapsedFrames: elapsedFrames) {
            parentWorlds[instance.def.name] = computeParentWorld(
                instance, parentWorlds: parentWorlds, canvasSize: viewTransform.canvasSize
            )
        }

        let drawOrder = instances.indices.sorted { instances[$0].def.depth > instances[$1].def.depth }

        for i in drawOrder {
            let instance = instances[i]
            let parentWorld = instance.def.parentName.flatMap { parentWorlds[$0] }
            let spriteTransform = depthAdjustedTransform(viewTransform,
                                                         depth: instance.def.depth,
                                                         perspectiveStrength: perspectiveStrength)
            renderInstance(instance, spriteIndex: i, parentWorld: parentWorld,
                           into: context, viewTransform: spriteTransform,
                           brushImages: brushImages, stampImages: stampImages,
                           elapsedFrames: elapsedFrames,
                           progressiveBrushStates: &progressiveBrushStates,
                           progressiveBrushEnabled: progressiveBrushEnabled,
                           using: &rng)
        }
    }

    // MARK: - Layered rendering

    private mutating func renderLayered<RNG: RandomNumberGenerator>(
        into context: CGContext,
        viewTransform: ViewTransform,
        brushImages: [String: CGImage],
        stampImages: [String: CGImage],
        elapsedFrames: Double,
        perspectiveStrength: Double,
        backgroundColor: CGColor,
        progressiveBrushStates: inout [String: BrushProgressiveState],
        progressiveBrushEnabled: Bool,
        using rng: inout RNG
    ) {
        // Pre-compute parent worlds once for ALL instances across all layers.
        // Use cycle-adjusted instances so children inherit animated parent poses.
        var parentWorlds: [String: ParentWorld] = [:]
        for instance in cycleAdjustedInstances(elapsedFrames: elapsedFrames) {
            parentWorlds[instance.def.name] = computeParentWorld(
                instance, parentWorlds: parentWorlds, canvasSize: viewTransform.canvasSize
            )
        }

        // Collect set names claimed by any layer.
        let allLayeredNames = Set(layers.flatMap { $0.spriteSetNames })

        // Sprites not in any layer render directly to main context (legacy fallback).
        let unassigned = instances.indices.filter { !allLayeredNames.contains(instances[$0].spriteSetName) }
        let unassignedOrder = unassigned.sorted { instances[$0].def.depth > instances[$1].def.depth }
        for i in unassignedOrder {
            let instance = instances[i]
            let parentWorld = instance.def.parentName.flatMap { parentWorlds[$0] }
            let spriteTransform = depthAdjustedTransform(viewTransform,
                                                         depth: instance.def.depth,
                                                         perspectiveStrength: perspectiveStrength)
            renderInstance(instance, spriteIndex: i, parentWorld: parentWorld,
                           into: context, viewTransform: spriteTransform,
                           brushImages: brushImages, stampImages: stampImages,
                           elapsedFrames: elapsedFrames,
                           progressiveBrushStates: &progressiveBrushStates,
                           progressiveBrushEnabled: progressiveBrushEnabled,
                           using: &rng)
        }

        // Render each layer bottom-to-top.
        for (layerIndex, layer) in layers.enumerated() {
            guard layer.isVisible else {
                if layer.redrawMode != .full { layerBuffers.removeValue(forKey: layer.id) }
                continue
            }

            let lt = layerViewTransform(viewTransform, parallaxFactor: layer.parallaxFactor)
            let layerIndices = instances.indices.filter { layer.spriteSetNames.contains(instances[$0].spriteSetName) }
            let drawOrder    = layerIndices.sorted { instances[$0].def.depth > instances[$1].def.depth }

            let opacity = max(0, min(1, DriverEvaluator.evaluate(
                layer.opacityDriver, globalElapsed: elapsedFrames,
                targetFPS: targetFPS, spriteIndex: layerIndex
            )))
            let blurRadius = max(0, DriverEvaluator.evaluate(
                layer.blurDriver, globalElapsed: elapsedFrames,
                targetFPS: targetFPS, spriteIndex: layerIndex
            )) * Double(qualityMultiple)

            let shouldLight = lightingConfig.isEnabled && layer.receivesLighting
                          && lightingConfig.lights.contains { $0.isEnabled }

            switch layer.redrawMode {

            case .full:
                // Discard any persistent buffer left from a previous mode.
                layerBuffers.removeValue(forKey: layer.id)
                guard let offscreen = makeOffscreenContext(size: viewTransform.canvasSize) else { continue }
                for i in drawOrder {
                    let instance = instances[i]
                    let parentWorld = instance.def.parentName.flatMap { parentWorlds[$0] }
                    let st = depthAdjustedTransform(lt, depth: instance.def.depth,
                                                    perspectiveStrength: perspectiveStrength)
                    renderInstance(instance, spriteIndex: i, parentWorld: parentWorld,
                                   into: offscreen, viewTransform: st,
                                   brushImages: brushImages, stampImages: stampImages,
                                   elapsedFrames: elapsedFrames,
                                   progressiveBrushStates: &progressiveBrushStates,
                                   progressiveBrushEnabled: progressiveBrushEnabled,
                                   using: &rng)
                }
                if shouldLight {
                    applyLightMap(to: offscreen, layerID: layer.id,
                                  canvasSize: viewTransform.canvasSize,
                                  elapsedFrames: elapsedFrames)
                }
                applyLayerComposite(from: offscreen, blurRadius: blurRadius, opacity: opacity,
                                    blendMode: layer.blendMode, into: context,
                                    canvasSize: viewTransform.canvasSize)

            case .once:
                if layerBuffers[layer.id] == nil {
                    guard let fresh = makeOffscreenContext(size: viewTransform.canvasSize) else { continue }
                    for i in drawOrder {
                        let instance = instances[i]
                        let parentWorld = instance.def.parentName.flatMap { parentWorlds[$0] }
                        let st = depthAdjustedTransform(lt, depth: instance.def.depth,
                                                        perspectiveStrength: perspectiveStrength)
                        renderInstance(instance, spriteIndex: i, parentWorld: parentWorld,
                                       into: fresh, viewTransform: st,
                                       brushImages: brushImages, stampImages: stampImages,
                                       elapsedFrames: elapsedFrames,
                                       progressiveBrushStates: &progressiveBrushStates,
                                       progressiveBrushEnabled: progressiveBrushEnabled,
                                       using: &rng)
                    }
                    layerBuffers[layer.id] = fresh
                }
                guard let buffer = layerBuffers[layer.id] else { continue }
                if shouldLight,
                   let img = buffer.makeImage(),
                   let temp = makeOffscreenContext(size: viewTransform.canvasSize) {
                    // Don't bake lighting into the stored buffer — use a temp composite.
                    temp.saveGState()
                    temp.concatenate(temp.ctm.inverted())
                    temp.draw(img, in: CGRect(origin: .zero, size: viewTransform.canvasSize))
                    temp.restoreGState()
                    applyLightMap(to: temp, layerID: layer.id,
                                  canvasSize: viewTransform.canvasSize,
                                  elapsedFrames: elapsedFrames)
                    applyLayerComposite(from: temp, blurRadius: blurRadius, opacity: opacity,
                                        blendMode: layer.blendMode, into: context,
                                        canvasSize: viewTransform.canvasSize)
                } else {
                    applyLayerComposite(from: buffer, blurRadius: blurRadius, opacity: opacity,
                                        blendMode: layer.blendMode, into: context,
                                        canvasSize: viewTransform.canvasSize)
                }

            case .accumulate:
                if layerBuffers[layer.id] == nil {
                    guard let fresh = makeOffscreenContext(size: viewTransform.canvasSize) else { continue }
                    layerBuffers[layer.id] = fresh
                }
                guard let buffer = layerBuffers[layer.id] else { continue }
                // Fade step: blend background colour over existing content at (1-accumulateFade) opacity,
                // so old content drifts toward the background rather than persisting indefinitely.
                let fadeAlpha = CGFloat(1.0 - layer.accumulateFade)
                if fadeAlpha > 0 {
                    buffer.saveGState()
                    let fadeColor = backgroundColor.copy(alpha: fadeAlpha)
                               ?? CGColor(gray: 0, alpha: fadeAlpha)
                    buffer.setFillColor(fadeColor)
                    buffer.fill(CGRect(origin: .zero, size: viewTransform.canvasSize))
                    buffer.restoreGState()
                }
                for i in drawOrder {
                    let instance = instances[i]
                    let parentWorld = instance.def.parentName.flatMap { parentWorlds[$0] }
                    let st = depthAdjustedTransform(lt, depth: instance.def.depth,
                                                    perspectiveStrength: perspectiveStrength)
                    renderInstance(instance, spriteIndex: i, parentWorld: parentWorld,
                                   into: buffer, viewTransform: st,
                                   brushImages: brushImages, stampImages: stampImages,
                                   elapsedFrames: elapsedFrames,
                                   progressiveBrushStates: &progressiveBrushStates,
                                   progressiveBrushEnabled: progressiveBrushEnabled,
                                   using: &rng)
                }
                if shouldLight,
                   let img = buffer.makeImage(),
                   let temp = makeOffscreenContext(size: viewTransform.canvasSize) {
                    temp.saveGState()
                    temp.concatenate(temp.ctm.inverted())
                    temp.draw(img, in: CGRect(origin: .zero, size: viewTransform.canvasSize))
                    temp.restoreGState()
                    applyLightMap(to: temp, layerID: layer.id,
                                  canvasSize: viewTransform.canvasSize,
                                  elapsedFrames: elapsedFrames)
                    applyLayerComposite(from: temp, blurRadius: blurRadius, opacity: opacity,
                                        blendMode: layer.blendMode, into: context,
                                        canvasSize: viewTransform.canvasSize)
                } else {
                    applyLayerComposite(from: buffer, blurRadius: blurRadius, opacity: opacity,
                                        blendMode: layer.blendMode, into: context,
                                        canvasSize: viewTransform.canvasSize)
                }
            }
        }
    }

    // MARK: - Layer buffer invalidation

    /// Clears all cached light maps. Call on seek so maps are recomputed at the new frame.
    mutating func invalidateLightMap() {
        lightMapCache = [:]
    }

    // MARK: - Light map helpers

    private mutating func getOrComputeLightMap(
        layerID: UUID,
        canvasSize: CGSize,
        elapsedFrames: Double
    ) -> CGImage? {
        if let cached = lightMapCache[layerID],
           cached.config == lightingConfig,
           cached.elapsed == elapsedFrames {
            return cached.image
        }
        // Build a config containing only lights that affect this layer.
        // A light with an empty affectedLayerIDs list affects every layer.
        let eligible = lightingConfig.lights.filter {
            $0.isEnabled && ($0.affectedLayerIDs.isEmpty || $0.affectedLayerIDs.contains(layerID))
        }
        guard !eligible.isEmpty else { return nil }
        let filteredConfig = LightingConfig(isEnabled: true, lights: eligible)
        guard let img = LightMapRenderer.render(
            config: filteredConfig,
            canvasSize: canvasSize,
            elapsedFrames: elapsedFrames,
            targetFPS: targetFPS
        ) else { return nil }
        lightMapCache[layerID] = (config: lightingConfig, elapsed: elapsedFrames, image: img)
        return img
    }

    private mutating func applyLightMap(
        to ctx: CGContext,
        layerID: UUID,
        canvasSize: CGSize,
        elapsedFrames: Double
    ) {
        guard let map = getOrComputeLightMap(layerID: layerID, canvasSize: canvasSize, elapsedFrames: elapsedFrames)
        else { return }
        // Snapshot the layer so we can clip the multiply to pixels that already
        // have content.  CGBlendMode.multiply computes
        // result_alpha = src_a + dst_a − src_a×dst_a.  The light map is always
        // fully opaque (alpha=1), so without a clip every transparent pixel gets
        // result_alpha = 1, turning it opaque and blocking layers behind.
        // clip(to:mask:) uses the CGImage alpha channel as the mask, so pixels
        // where the layer is transparent are excluded from the multiply draw.
        guard let layerMask = ctx.makeImage() else { return }
        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        ctx.clip(to: CGRect(origin: .zero, size: canvasSize), mask: layerMask)
        ctx.setBlendMode(.multiply)
        ctx.draw(map, in: CGRect(origin: .zero, size: canvasSize))
        ctx.restoreGState()
    }

    /// Clears persistent buffers for `.accumulate` layers only.
    /// Call on seek so ghost trails restart from the new playhead position.
    /// `.once` buffers are preserved — they are time-independent.
    mutating func invalidateAccumulateBuffers() {
        for layer in layers where layer.redrawMode == .accumulate {
            layerBuffers.removeValue(forKey: layer.id)
        }
    }

    /// Clears all persistent layer buffers (`.once` and `.accumulate`).
    /// Call when canvas size changes or on full project reload.
    mutating func invalidateAllLayerBuffers() {
        layerBuffers.removeAll()
    }

    /// Returns a ViewTransform with the camera offset scaled by `parallaxFactor`.
    /// parallaxFactor=1 → moves fully with camera; parallaxFactor=0 → fully fixed.
    private func layerViewTransform(_ base: ViewTransform, parallaxFactor: Double) -> ViewTransform {
        guard parallaxFactor != 1.0 else { return base }
        return ViewTransform(
            canvasSize: base.canvasSize,
            offset:     Vector2D(x: base.offset.x * parallaxFactor,
                                 y: base.offset.y * parallaxFactor),
            zoom:       base.zoom,
            rotation:   base.rotation
        )
    }

    private func applyLayerComposite(from offscreen: CGContext, blurRadius: Double,
                                     opacity: Double, blendMode: LayerBlendMode,
                                     into context: CGContext, canvasSize: CGSize) {
        guard let img = offscreen.makeImage() else { return }
        let compositeImg: CGImage
        if blurRadius > 0.5 {
            let ciImg = CIImage(cgImage: img)
            // clampedToExtent() extends edge pixels to infinity so the blur kernel
            // at canvas boundaries blends edge colour with itself rather than with
            // transparent, eliminating the halo that otherwise appears at the edges
            // of blurred foreground/background layers.
            let clamped = ciImg.clampedToExtent()
            if let filter = CIFilter(name: "CIGaussianBlur",
                                     parameters: [kCIInputImageKey: clamped,
                                                  kCIInputRadiusKey: blurRadius]),
               let output = filter.outputImage,
               let blurred = SpriteScene.ciContext.createCGImage(
                   output.cropped(to: ciImg.extent), from: ciImg.extent) {
                compositeImg = blurred
            } else {
                compositeImg = img
            }
        } else {
            compositeImg = img
        }
        context.saveGState()
        context.concatenate(context.ctm.inverted())
        context.setAlpha(CGFloat(opacity))
        context.setBlendMode(blendMode.cgBlendMode)
        context.draw(compositeImg, in: CGRect(x: 0, y: 0,
                                              width: canvasSize.width, height: canvasSize.height))
        context.restoreGState()
    }

    /// Returns a ViewTransform scaled by the parallax factor for a sprite at the given depth.
    /// depth=0 or perspectiveStrength=0 returns the transform unchanged.
    private func depthAdjustedTransform(_ base: ViewTransform, depth: Double, perspectiveStrength: Double) -> ViewTransform {
        guard perspectiveStrength > 0, depth != 0 else { return base }
        let f = 1.0 / (1.0 + depth * perspectiveStrength)
        return ViewTransform(
            canvasSize: base.canvasSize,
            offset:     Vector2D(x: base.offset.x * f, y: base.offset.y * f),
            zoom:       base.zoom * f,
            rotation:   base.rotation
        )
    }

    public mutating func render<RNG: RandomNumberGenerator>(
        into context: CGContext,
        viewTransform: ViewTransform,
        brushImages: [String: CGImage] = [:],
        stampImages: [String: CGImage] = [:],
        elapsedFrames: Double = 0,
        using rng: inout RNG
    ) {
        var progressiveBrushStates: [String: BrushProgressiveState] = [:]
        render(
            into: context,
            viewTransform: viewTransform,
            brushImages: brushImages,
            stampImages: stampImages,
            elapsedFrames: elapsedFrames,
            progressiveBrushStates: &progressiveBrushStates,
            progressiveBrushEnabled: false,
            using: &rng
        )
    }

    // MARK: - Parent-child world transform

    /// Encapsulates the resolved world-space transform of one sprite.
    /// Children inherit selected components of their parent's ParentWorld.
    private struct ParentWorld {
        /// Animated world position in pixels from canvas centre.
        var positionPx:     Vector2D
        /// World position with no animation applied (def.position composed through hierarchy).
        var basePositionPx: Vector2D
        /// Raw stored position in pixels (def.position only, never modified by ancestor
        /// transforms). Used by children as their local-space origin when computing offsets,
        /// so that grandparent scaling does not corrupt grandchild positions.
        var storedPositionPx: Vector2D
        /// Combined animated rotation in degrees.
        var rotationDeg:    Double
        /// Combined base rotation in degrees (def.rotation only, no animation).
        var baseRotationDeg: Double
        /// Combined scale (WITHOUT the ×2 coordinate convention).
        var scale:          Vector2D
    }

    // Returns a copy of `instances` with cycle-blended position/rotation/scale
    // written into each def, so that computeParentWorld sees the animated
    // pose for the current frame rather than the static base def values.
    // Children with no poseOverride of their own will still inherit the correct
    // parent rotation because the parent's def is updated here.
    private func cycleAdjustedInstances(elapsedFrames: Double) -> [SpriteInstance] {
        var adjusted = instances
        for i in adjusted.indices {
            let inst = adjusted[i]
            guard let cycleName = inst.def.cycleName,
                  let cycle     = allCycles[cycleName] else { continue }
            let layers = cycle.renderLayers(atFrame: Int(elapsedFrames))
            guard !layers.isEmpty else { continue }
            let outIdx  = layers[0].stateIndex
            let inIdx   = layers.count > 1 ? layers[1].stateIndex : outIdx
            let t       = layers.count > 1 ? layers[1].alpha : 0.0
            let name    = inst.def.name
            let outPose = outIdx < cycle.states.count ? cycle.states[outIdx].poseOverrides[name] : nil
            let inPose  = inIdx  < cycle.states.count ? cycle.states[inIdx].poseOverrides[name]  : nil
            guard outPose != nil || inPose != nil else { continue }
            let base = SpritePoseOverride(position: inst.def.position,
                                          rotation: inst.def.rotation,
                                          scale:    inst.def.scale)
            let from = outPose ?? base
            let to   = inPose  ?? base
            adjusted[i].def.position = Vector2D.lerp(from.position, to.position, t: t)
            adjusted[i].def.rotation = lerpAngle(from.rotation, to.rotation, t: t)
            adjusted[i].def.scale    = Vector2D.lerp(from.scale,    to.scale,    t: t)
        }
        return adjusted
    }

    // Apply a sequential scale-rotate-translate chain to `pt`.
    // Each step: scale about pivot, rotate about pivot, translate.
    // `scales` and `translations` default to identity / zero when shorter than `pivots`.
    private func cgApplyChain(_ pt: CGPoint, pivots: [CGPoint], rots: [Double],
                               scales: [CGPoint] = [], translations: [CGPoint] = []) -> CGPoint {
        var p = pt
        for i in pivots.indices {
            let piv = pivots[i]
            let sc  = i < scales.count       ? scales[i]         : CGPoint(x: 1, y: 1)
            let tx  = i < translations.count ? translations[i].x : 0.0
            let ty  = i < translations.count ? translations[i].y : 0.0
            let rad = rots[i] * .pi / 180.0
            let c   = cos(rad), s = sin(rad)
            let rx  = p.x - piv.x, ry = p.y - piv.y
            p = CGPoint(x: sc.x * (c * rx - s * ry) + piv.x + tx,
                        y: sc.y * (s * rx + c * ry) + piv.y + ty)
        }
        return p
    }

    /// Pre-transforms polygon points through the full ancestor kinematic chain (SRT per joint)
    /// so that scale, rotation, and translation from all ancestors — including cycle pose
    /// overrides AND animation-driver values — propagate correctly down to each child.
    ///
    /// This enables a scene-level container sprite (no geometry, just transforms/drivers)
    /// to move, rotate, and scale the entire figure hierarchy as a unit.
    ///
    /// Points are returned in 2×-scaled geometry space; set `def.scale = (0.5, 0.5)` on
    /// the rendered instance so the built-in 2× factor in `applyTransform` cancels out.
    private func chainTransformPolygons(
        _ polys: [Polygon2D],
        instance: SpriteInstance,
        cycle: SpriteCycle,
        elapsedFrames: Double
    ) -> [Polygon2D] {
        let layers = cycle.renderLayers(atFrame: Int(elapsedFrames))
        guard !layers.isEmpty else { return polys }
        let outIdx = layers[0].stateIndex
        let inIdx  = layers.count > 1 ? layers[1].stateIndex : outIdx
        let t      = layers.count > 1 ? layers[1].alpha      : 0.0

        // Build ancestor chain [root, …, self].
        var chain: [SpriteInstance] = []
        var cur: SpriteInstance? = instance
        while let s = cur {
            chain.insert(s, at: 0)
            cur = s.def.parentName.flatMap { n in self.instances.first { $0.def.name == n } }
        }

        // Accumulate per-ancestor world pivot, rotation, scale, translation.
        // All coordinates are in 2×-geometry-space (pivot = pivotOffset / 100.0).
        var wPivots: [CGPoint] = []
        var rots:    [Double]  = []
        var scales:  [CGPoint] = []
        var trans:   [CGPoint] = []

        for sp in chain {
            let restPiv = CGPoint(x: sp.def.pivotOffset.x / 100.0,
                                  y: sp.def.pivotOffset.y / 100.0)
            // World pivot inherits all ancestor SRTs.
            let wPiv = cgApplyChain(restPiv, pivots: wPivots, rots: rots,
                                    scales: scales, translations: trans)
            wPivots.append(wPiv)

            let name   = sp.def.name
            // Current-frame animation-driver state for this sprite.
            let animSt = self.instances.first { $0.def.name == name }?.state.transform
                         ?? .identity

            // Base-state fallback: when a state has no override for this sprite, use the
            // designated base state's override rather than def.rotation/position/scale = 0.
            // This lets sparse states (e.g. "left leg forward") only specify joints that
            // actually change, with everything else inheriting from the neutral base state.
            let basePose: SpritePoseOverride? = cycle.baseStateIndex.flatMap { bi in
                guard bi < cycle.states.count, bi != outIdx, bi != inIdx else { return nil }
                return cycle.states[bi].poseOverrides[name]
            }
            let defPose = SpritePoseOverride(position: sp.def.position,
                                             rotation: sp.def.rotation,
                                             scale:    sp.def.scale)

            // Rotation: cycle pose blend + animation driver.
            let outPose = outIdx < cycle.states.count ? cycle.states[outIdx].poseOverrides[name] : nil
            let inPose  = inIdx  < cycle.states.count ? cycle.states[inIdx].poseOverrides[name]  : nil
            let fallback = basePose ?? defPose
            let cycleRot = lerpAngle((outPose ?? fallback).rotation,
                                     (inPose  ?? fallback).rotation, t: t)
            rots.append(cycleRot + animSt.rotation)

            // Scale: cycle pose blend × animation driver (per axis).
            let fromSc  = (outPose ?? fallback).scale
            let toSc    = (inPose  ?? fallback).scale
            let cycleScX = fromSc.x + (toSc.x - fromSc.x) * t
            let cycleScY = fromSc.y + (toSc.y - fromSc.y) * t
            scales.append(CGPoint(x: cycleScX * animSt.scale.x,
                                  y: cycleScY * animSt.scale.y))

            // Translation: cycle pose blend + animation driver (in 2×-geometry-space).
            // Non-root chain elements (sprites with a parent) that have no explicit
            // poseOverride in either the outgoing or incoming state contribute zero
            // positional displacement.  Their geometry is already baked at world-space
            // coordinates; using def.position as the fallback would accumulate one extra
            // –position/100 offset per hierarchy level, displacing the whole rig.
            // The root sprite (no parentName) still uses its full fallback position so
            // the animation driver can move the entire rig.
            let isChainRoot = sp.def.parentName == nil
            let hasExplicitPos = outPose != nil || inPose != nil || basePose != nil
            let fromPos: Vector2D
            let toPos:   Vector2D
            if isChainRoot || hasExplicitPos {
                fromPos = (outPose ?? fallback).position
                toPos   = (inPose  ?? fallback).position
            } else {
                fromPos = .zero
                toPos   = .zero
            }
            let cyclePosX = fromPos.x + (toPos.x - fromPos.x) * t
            let cyclePosY = fromPos.y + (toPos.y - fromPos.y) * t
            trans.append(CGPoint(
                x: (cyclePosX + animSt.positionOffset.x) / 100.0,
                y: (cyclePosY + animSt.positionOffset.y) / 100.0
            ))
        }

        // Apply the full SRT chain to each polygon point.
        // Points start at 2× base scale (matching applyTransform's convention).
        return polys.map { poly in
            let newPts = poly.points.map { pt -> Vector2D in
                let scaled = CGPoint(x: pt.x * 2.0, y: pt.y * 2.0)
                let tf     = cgApplyChain(scaled, pivots: wPivots, rots: rots,
                                          scales: scales, translations: trans)
                return Vector2D(x: tf.x, y: tf.y)
            }
            return Polygon2D(points: newPts, type: poly.type,
                             pressures: poly.pressures,
                             pressureProfiles: poly.pressureProfiles,
                             visible: poly.visible)
        }
    }

    private func computeParentWorld(
        _ instance: SpriteInstance,
        parentWorlds: [String: ParentWorld],
        canvasSize: CGSize
    ) -> ParentWorld {
        let hw = canvasSize.width  / 2.0
        let hh = canvasSize.height / 2.0
        let def  = instance.def
        let anim = instance.state.transform

        var sx      = def.scale.x * anim.scale.x
        var sy      = def.scale.y * anim.scale.y
        var rotDeg  = def.rotation + anim.rotation

        // Animated position (base def + driver offset).
        let localTx = (def.position.x + anim.positionOffset.x) / 100.0 * hw
        let localTy = (def.position.y + anim.positionOffset.y) / 100.0 * hh
        var txPx    = localTx
        var tyPx    = localTy

        // Base position (def only, no animation) — used by children to compute their offset.
        let baseTx   = def.position.x / 100.0 * hw
        let baseTy   = def.position.y / 100.0 * hh
        var baseTxPx = baseTx
        var baseTyPx = baseTy
        var baseRotDeg = def.rotation

        if let parent = def.parentName.flatMap({ parentWorlds[$0] }) {
            let mask = def.inheritMask
            if mask.scale {
                sx *= parent.scale.x
                sy *= parent.scale.y
            }
            if mask.rotation {
                rotDeg    += parent.rotationDeg
                baseRotDeg += parent.baseRotationDeg
            }
            if mask.position {
                // Child position relative to parent's stored (raw) position, then scaled,
                // rotated by parent's animated rotation, and translated to parent's animated
                // position. storedPositionPx is used (not basePositionPx) because basePositionPx
                // is the world position after ancestor scaling — a different coordinate space
                // from the child's raw stored position, causing wrong grandchild offsets.
                let rad  = parent.rotationDeg * .pi / 180.0
                let cosR = cos(rad), sinR = sin(rad)
                var relTx = localTx - parent.storedPositionPx.x
                var relTy = localTy - parent.storedPositionPx.y
                if mask.scale {
                    relTx *= parent.scale.x
                    relTy *= parent.scale.y
                }
                txPx = parent.positionPx.x + relTx * cosR - relTy * sinR
                tyPx = parent.positionPx.y + relTx * sinR + relTy * cosR

                let baseRad  = parent.baseRotationDeg * .pi / 180.0
                let cosB = cos(baseRad), sinB = sin(baseRad)
                var relBaseTx = baseTx - parent.storedPositionPx.x
                var relBaseTy = baseTy - parent.storedPositionPx.y
                if mask.scale {
                    relBaseTx *= parent.scale.x
                    relBaseTy *= parent.scale.y
                }
                baseTxPx = parent.basePositionPx.x + relBaseTx * cosB - relBaseTy * sinB
                baseTyPx = parent.basePositionPx.y + relBaseTx * sinB + relBaseTy * cosB
            }
        }

        return ParentWorld(
            positionPx:      Vector2D(x: txPx,    y: tyPx),
            basePositionPx:  Vector2D(x: baseTxPx, y: baseTyPx),
            storedPositionPx: Vector2D(x: baseTx,  y: baseTy),
            rotationDeg:     rotDeg,
            baseRotationDeg: baseRotDeg,
            scale:           Vector2D(x: sx, y: sy)
        )
    }

    private func renderInstance<RNG: RandomNumberGenerator>(
        _ instance: SpriteInstance,
        spriteIndex: Int,
        parentWorld: ParentWorld?,
        into context: CGContext,
        viewTransform: ViewTransform,
        brushImages: [String: CGImage],
        stampImages: [String: CGImage],
        elapsedFrames: Double,
        progressiveBrushStates: inout [String: BrushProgressiveState],
        progressiveBrushEnabled: Bool,
        using rng: inout RNG
    ) {
        // ── Gate check ───────────────────────────────────────────────────────
        let globalFrame = Int(elapsedFrames)
        let gs = instance.def.gateStart, ge = instance.def.gateEnd
        if (gs > 0 && globalFrame < gs) || (ge > 0 && globalFrame > ge) { return }

        // Stop drawing once the per-sprite draw-cycle limit is reached.
        let anim = instance.def.animation
        guard anim.totalDraws == 0 || instance.state.drawCycle < anim.totalDraws else { return }

        // ── SVG sprite: bypass polygon pipeline ──────────────────────────────
#if canImport(AppKit)
        if let filename = instance.def.svgFilename {
            if let nsImage = svgImages[filename] {
                renderSVGInstance(instance, nsImage: nsImage, parentWorld: parentWorld,
                                  into: context, viewTransform: viewTransform,
                                  spriteIndex: spriteIndex, elapsedFrames: elapsedFrames)
            }
            return
        }
#endif

        // ── Cycle-name driver: override the active cycle at runtime ──────────
        if let drv = instance.def.animation.drivers?.cycleName, drv.enabled,
           let overrideName = DriverEvaluator.evaluateName(drv, globalElapsed: elapsedFrames,
                                                           spriteIndex: spriteIndex),
           let overrideCycle = allCycles[overrideName] {
            var cycleInstance = instance
            cycleInstance.def.cycleName = overrideName
            if let cached = instance.driverCycleData[overrideName] {
                cycleInstance.cycleStatePolygons     = cached.statePolygons
                cycleInstance.cycleStateRendererSets = cached.stateRendererSets
            }
            renderCycleInstance(cycleInstance, spriteIndex: spriteIndex, parentWorld: parentWorld,
                                cycle: overrideCycle, into: context, viewTransform: viewTransform,
                                brushImages: brushImages, stampImages: stampImages,
                                elapsedFrames: elapsedFrames,
                                progressiveBrushStates: &progressiveBrushStates,
                                progressiveBrushEnabled: progressiveBrushEnabled,
                                using: &rng)
            return
        }

        // ── SpriteCycle: static cycle assignment ──────────────────────────────
        if let cycleName = instance.def.cycleName,
           let cycle = allCycles[cycleName] {
            renderCycleInstance(instance, spriteIndex: spriteIndex, parentWorld: parentWorld,
                                cycle: cycle, into: context, viewTransform: viewTransform,
                                brushImages: brushImages, stampImages: stampImages,
                                elapsedFrames: elapsedFrames,
                                progressiveBrushStates: &progressiveBrushStates,
                                progressiveBrushEnabled: progressiveBrushEnabled,
                                using: &rng)
            return
        }

        // ── Shape driver: select active geometry and renderer set ────────────
        // Step-evaluated: snaps to last keyframe at or before elapsed — no interpolation.
        let shapeIdx = instance.def.animation.drivers.map {
            $0.shape.enabled ? DriverEvaluator.evaluateShapeIndex($0.shape, globalElapsed: elapsedFrames) : 0
        } ?? 0

        var activeInstance = instance
        if shapeIdx > 0,
           shapeIdx - 1 < instance.variantPolygons.count,
           shapeIdx - 1 < instance.variantRendererSets.count {
            activeInstance.basePolygons = instance.variantPolygons[shapeIdx - 1]
            activeInstance.rendererSet  = instance.variantRendererSets[shapeIdx - 1]
            // Clamp renderer state index to new set size.
            let maxIdx = max(0, activeInstance.rendererSet.renderers.count - 1)
            activeInstance.state.activeRendererIndex = min(activeInstance.state.activeRendererIndex, maxIdx)
        }

        // ── Variant image override: render image instead of geometry when set ──
#if canImport(AppKit)
        if shapeIdx > 0,
           shapeIdx - 1 < instance.variantImageFilenames.count,
           let imgName = instance.variantImageFilenames[shapeIdx - 1],
           let nsImage = svgImages[imgName] {
            renderSVGInstance(activeInstance, nsImage: nsImage, parentWorld: parentWorld,
                              into: context, viewTransform: viewTransform,
                              spriteIndex: spriteIndex, elapsedFrames: elapsedFrames)
            return
        }
#endif

        // Renderer-set driver overrides the shape-driver's set selection when active.
        if let drv = activeInstance.def.animation.drivers?.rendererSet, drv.enabled,
           let name = DriverEvaluator.evaluateName(drv, globalElapsed: elapsedFrames, spriteIndex: spriteIndex),
           let overrideSet = allRendererSets[name] {
            activeInstance.rendererSet = overrideSet
            let maxIdx = max(0, activeInstance.rendererSet.renderers.count - 1)
            activeInstance.state.activeRendererIndex = min(activeInstance.state.activeRendererIndex, maxIdx)
        }

        // Select active polygon set (legacy shape-sequence overrides basePolygons when no shape driver).
        let activePolygons: [Polygon2D]
        if shapeIdx == 0, let seq = activeInstance.def.shapeSequence, !activeInstance.sequencePolygons.isEmpty {
            let step = activeInstance.state.drawCycle / max(1, seq.frameDuration)
            let idx  = sequenceIndex(step: step,
                                     count: activeInstance.sequencePolygons.count,
                                     mode: seq.mode)
            activePolygons = activeInstance.sequencePolygons[idx]
        } else {
            activePolygons = activeInstance.basePolygons
        }
        guard !activePolygons.isEmpty else { return }

        // 1. Morph interpolation
        // Driver path takes precedence over legacy state.transform.morphAmount.
        let morphAmount: Double
        if let drivers = activeInstance.def.animation.drivers {
            morphAmount = drivers.morph.enabled
                ? DriverEvaluator.evaluate(drivers.morph, globalElapsed: elapsedFrames,
                                           targetFPS: targetFPS, spriteIndex: spriteIndex)
                : 0.0
        } else {
            morphAmount = activeInstance.state.transform.morphAmount
        }
        let morphed = MorphInterpolator.interpolate(
            base:        activePolygons,
            targets:     activeInstance.morphTargetPolygons,
            morphAmount: morphAmount
        )

        // Subdivision-set driver overrides the instance's baked params.
        if let drv = activeInstance.def.animation.drivers?.subdivisionSet, drv.enabled,
           let name = DriverEvaluator.evaluateName(drv, globalElapsed: elapsedFrames, spriteIndex: spriteIndex),
           let overrideParams = allSubdivisionSets[name] {
            activeInstance.subdivisionParams = overrideParams
        }

        // 2. Subdivision
        var subdivided: [Polygon2D]
        if activeInstance.subdivisionParams.isEmpty {
            subdivided = morphed
        } else {
            subdivided = SubdivisionEngine.process(
                polygons:      morphed,
                paramSet:      activeInstance.subdivisionParams,
                elapsedFrames: elapsedFrames,
                targetFPS:     targetFPS,
                spriteIndex:   spriteIndex,
                rng:           &rng
            )
        }

        // 2b. Curve refinement (open-curve involution)
        if !activeInstance.curveRefinementParams.isEmpty {
            subdivided = CurveRefinementEngine.process(
                polygons:      subdivided,
                paramSet:      activeInstance.curveRefinementParams,
                elapsedFrames: elapsedFrames,
                targetFPS:     targetFPS,
                spriteIndex:   spriteIndex
            )
        }

        // 2c. Segment extraction (open-curve involution — break curve into sub-curves)
        if !activeInstance.segmentExtractionParams.isEmpty {
            subdivided = SegmentExtractionEngine.process(
                polygons:      subdivided,
                paramSet:      activeInstance.segmentExtractionParams,
                elapsedFrames: elapsedFrames,
                targetFPS:     targetFPS,
                spriteIndex:   spriteIndex
            )
        }

        // 3. Apply the sprite transform (scale → rotate → translate → pixels)
        // When a parentWorld is supplied the child transform is composed with it.
        let transformed = subdivided.map {
            applyTransform($0, to: activeInstance, parentWorld: parentWorld, canvasSize: viewTransform.canvasSize)
        }

        // 4. Determine which renderers to apply
        let activeRenderers = resolveActiveRenderers(for: activeInstance)
        let spriteOpacity = max(0, min(1, activeInstance.state.transform.opacity))
        guard spriteOpacity > 0 else { return }

        // 5. Draw
        // When scaleImage is false, pixel-valued style properties (stroke widths,
        // point sizes, brush/stencil pixel metrics) are kept at their logical-pixel
        // values rather than being scaled up by the quality multiple.
        let effectiveQuality = scaleImage ? qualityMultiple : 1
        context.saveGState()
        defer { context.restoreGState() }

        for (rendererIndex, renderer) in activeRenderers {
            let changed = resolveRendererChanges(renderer, rendererIndex: rendererIndex, instance: activeInstance,
                                                 scales: [.sprite, .global])
            let resolved = resolveRendererDrivers(changed, spriteIndex: spriteIndex, elapsedFrames: elapsedFrames)
            let rendererOpacity = resolveRendererOpacity(changed, spriteIndex: spriteIndex, elapsedFrames: elapsedFrames)
            let effectiveOpacity = rendererOpacity * spriteOpacity
            guard rendererOpacity > 0 else { continue }
            var elementState = rendererAnimationState(for: activeInstance, rendererIndex: rendererIndex)

            // Determine whether to use an offscreen context for per-renderer Gaussian blur.
            let scaledBlur = max(0, resolved.blurRadius) * Double(effectiveQuality)
            let offscreen: CGContext? = scaledBlur > 0 ? makeOffscreenContext(size: viewTransform.canvasSize) : nil
            let drawTarget = offscreen ?? context

            if resolved.mode == .brushed, let brushCfg = resolved.brushConfig {
                // Brush mode: stamp images along perturbed edge paths.
                let scaledBrush = effectiveQuality > 1
                    ? brushCfg.scaled(by: Double(effectiveQuality)) : brushCfg
                let edges = BrushEdge.extractEdges(from: transformed, viewTransform: viewTransform)
                if scaledBrush.drawMode == .progressive && progressiveBrushEnabled {
                    let key = "\(activeInstance.def.name)|\(renderer.name)"
                    if progressiveBrushStates[key] == nil || activeInstance.state.drawCycle == 0 {
                        progressiveBrushStates[key] = BrushProgressiveState(
                            edges: edges,
                            agentCount: scaledBrush.agentCount,
                            config: scaledBrush,
                            elapsedFrames: elapsedFrames
                        )
                    }
                    if var state = progressiveBrushStates[key] {
                        for agentIndex in state.agents.indices {
                            BrushStampEngine.drawProgressiveStamps(
                                agentIndex: agentIndex,
                                state: &state,
                                config: scaledBrush,
                                color: resolved.strokeColor,
                                context: drawTarget,
                                brushImages: brushImages,
                                opacityMultiplier: effectiveOpacity
                            )
                        }
                        state.checkCompletion(mode: scaledBrush.postCompletionMode)
                        progressiveBrushStates[key] = state
                    }
                } else {
                    BrushStampEngine.drawFullPath(
                        edges:         edges,
                        config:        scaledBrush,
                        color:         resolved.strokeColor,
                        context:       drawTarget,
                        elapsedFrames: elapsedFrames,
                        brushImages:   brushImages,
                        opacityMultiplier: effectiveOpacity
                    )
                }
            } else if (resolved.mode == .stamped || resolved.mode == .stenciled),
                      let stencilCfg = resolved.stencilConfig {
                // Stamp mode: place stamp images at each discrete point position.
                // Look up the per-renderer stencil opacity animation state so
                // StampEngine can use the stepped palette index for SEQ/PING_PONG.
                let scaledStencil = effectiveQuality > 1
                    ? stencilCfg.scaled(by: Double(effectiveQuality)) : stencilCfg
                let activeIdx    = min(activeInstance.state.activeRendererIndex,
                                       activeInstance.rendererSet.renderers.count - 1)
                let opacityState = activeIdx < activeInstance.state.rendererAnimationStates.count
                    ? activeInstance.state.rendererAnimationStates[activeIdx].stencilOpacityState
                    : nil
                for polygon in transformed {
                    StampEngine.draw(
                        polygon:       polygon,
                        config:        scaledStencil,
                        context:       drawTarget,
                        viewTransform: viewTransform,
                        stampImages:   stampImages,
                        opacityState:  opacityState,
                        opacityMultiplier: effectiveOpacity,
                        using:         &rng
                    )
                }
            } else {
                for polygon in transformed {
                    let polyResolved = RenderStateEngine.resolve(
                        renderer: resolved,
                        state:    elementState,
                        changes:  renderer.changes,
                        scales:   [.poly]
                    )
                    let drivenPolyResolved = resolveRendererDrivers(polyResolved,
                                                                    spriteIndex: spriteIndex,
                                                                    elapsedFrames: elapsedFrames)
                    if drivenPolyResolved.mode == .points {
                        drawPointsWithElementChanges(
                            polygon,
                            renderer:        drivenPolyResolved,
                            baseChanges:     renderer.changes,
                            state:           elementState,
                            into:            drawTarget,
                            transform:       viewTransform,
                            qualityMultiple: effectiveQuality,
                            opacityMultiplier: effectiveOpacity,
                            spriteIndex:      spriteIndex,
                            elapsedFrames:    elapsedFrames,
                            using:           &rng
                        )
                    } else {
                        RenderEngine.draw(polygon,
                                          renderer:        drivenPolyResolved,
                                          into:            drawTarget,
                                          transform:       viewTransform,
                                          qualityMultiple: effectiveQuality,
                                          opacityMultiplier: effectiveOpacity)
                    }
                    elementState = RenderStateEngine.advance(
                        state:   elementState,
                        changes: renderer.changes,
                        scales:  [.poly],
                        using:   &rng
                    )
                }
            }

            // Composite blurred offscreen back onto the main context.
            if let offscreen = offscreen {
                applyRendererBlur(from: offscreen, blurRadius: scaledBlur,
                                  into: context, canvasSize: viewTransform.canvasSize)
            }
        }
    }

    // MARK: - Cycle rendering

    private func renderCycleInstance<RNG: RandomNumberGenerator>(
        _ instance: SpriteInstance,
        spriteIndex: Int,
        parentWorld: ParentWorld?,
        cycle: SpriteCycle,
        into context: CGContext,
        viewTransform: ViewTransform,
        brushImages: [String: CGImage],
        stampImages: [String: CGImage],
        elapsedFrames: Double,
        progressiveBrushStates: inout [String: BrushProgressiveState],
        progressiveBrushEnabled: Bool,
        using rng: inout RNG
    ) {
        let cycleLayers = cycle.renderLayers(atFrame: Int(elapsedFrames))
        guard !cycleLayers.isEmpty else { return }

        let spriteOpacity = max(0, min(1, instance.state.transform.opacity))
        guard spriteOpacity > 0 else { return }

        let needsOffscreen = cycleLayers.count > 1

        // ── Pose override interpolation ───────────────────────────────────────
        // If either the outgoing or incoming cycle state defines a pose override
        // for this sprite, compute a blended pose for the current transition
        // progress and apply it to every layer instance before rendering.
        // This keeps geometry cross-fades intact while smoothly moving the rig.
        let blendedPose: SpritePoseOverride? = {
            let outIdx  = cycleLayers[0].stateIndex
            let inIdx   = cycleLayers.count > 1 ? cycleLayers[1].stateIndex : outIdx
            let t       = cycleLayers.count > 1 ? cycleLayers[1].alpha : 0.0
            let name    = instance.def.name
            let outPose = outIdx < cycle.states.count ? cycle.states[outIdx].poseOverrides[name] : nil
            let inPose  = inIdx  < cycle.states.count ? cycle.states[inIdx].poseOverrides[name]  : nil
            guard outPose != nil || inPose != nil else { return nil }
            // Use the sprite's base def values as the identity pose when a state has no override.
            let base    = SpritePoseOverride(position: instance.def.position,
                                             rotation: instance.def.rotation,
                                             scale:    instance.def.scale)
            let from    = outPose ?? base
            let to      = inPose  ?? base
            return SpritePoseOverride(
                position: Vector2D.lerp(from.position, to.position, t: t),
                rotation: lerpAngle(from.rotation, to.rotation, t: t),
                scale:    Vector2D.lerp(from.scale,    to.scale,    t: t)
            )
        }()

        for layer in cycleLayers {
            // Image cycle state: bypass polygon pipeline entirely.
            // The `continue` is unconditional once svgFilename is set — we never fall
            // through to the polygon path even when the image is absent (empty filename
            // or not yet loaded), mirroring the SpriteDef SVG path at line ~908.
#if canImport(AppKit)
            if cycle.states.indices.contains(layer.stateIndex),
               let svgFile = cycle.states[layer.stateIndex].svgFilename {
                if !svgFile.isEmpty, let nsImage = svgImages[svgFile] {
                    var svgInstance = instance
                    if let pose = blendedPose {
                        svgInstance.def.position = pose.position
                        svgInstance.def.rotation = pose.rotation
                        svgInstance.def.scale    = pose.scale
                    }
                    if needsOffscreen {
                        guard let offscreen = makeOffscreenContext(size: viewTransform.canvasSize) else { continue }
                        svgInstance.state.transform.opacity = 1.0
                        renderSVGInstance(svgInstance, nsImage: nsImage, parentWorld: parentWorld,
                                          into: offscreen, viewTransform: viewTransform,
                                          spriteIndex: spriteIndex, elapsedFrames: elapsedFrames)
                        guard let img = offscreen.makeImage() else { continue }
                        context.saveGState()
                        context.concatenate(context.ctm.inverted())
                        context.setAlpha(CGFloat(layer.alpha * spriteOpacity))
                        let sz = viewTransform.canvasSize
                        context.draw(img, in: CGRect(x: 0, y: 0, width: sz.width, height: sz.height))
                        context.restoreGState()
                    } else {
                        svgInstance.state.transform.opacity = spriteOpacity
                        renderSVGInstance(svgInstance, nsImage: nsImage, parentWorld: parentWorld,
                                          into: context, viewTransform: viewTransform,
                                          spriteIndex: spriteIndex, elapsedFrames: elapsedFrames)
                    }
                }
                continue  // always skip polygon pipeline for image-mode states
            }
#endif
            // Pose-only cycle states have no shapeSetName so cycleStatePolygons may be
            // entirely empty or shorter than the state count. Fall back to basePolygons.
            let layerPolys: [Polygon2D] = instance.cycleStatePolygons.indices.contains(layer.stateIndex)
                ? instance.cycleStatePolygons[layer.stateIndex]
                : []
            let effectivePolys = layerPolys.isEmpty ? instance.basePolygons : layerPolys
            guard !effectivePolys.isEmpty else { continue }

            // Build a modified instance for this layer: override polygons, renderer, cycleName, opacity.
            var layerInstance = instance
            layerInstance.def.cycleName = nil      // prevent recursion
            layerInstance.basePolygons  = effectivePolys
            if layer.stateIndex < instance.cycleStateRendererSets.count,
               let overrideSet = instance.cycleStateRendererSets[layer.stateIndex] {
                layerInstance.rendererSet = overrideSet
            }
            // For baked-geometry rigs (sprites with a pivot offset or a parent), always
            // pre-transform the polygon using the full kinematic chain so each child
            // joint rotates around its animated world-space pivot rather than the fixed
            // rest-pose pivot. This must fire for ALL rig sprites, even those with no
            // pose override in the current state — without it, children follow parent
            // rotations via applyTransform's broken single-pivot accumulation.
            // parentWorld is set to nil so applyTransform does not re-apply the
            // hierarchy on top of the already-baked polygon.
            var chainParentWorld: ParentWorld? = parentWorld
            let isRig = instance.def.pivotOffset != .zero || instance.def.parentName != nil
            if isRig {
                layerInstance.basePolygons  = chainTransformPolygons(
                    effectivePolys, instance: instance, cycle: cycle, elapsedFrames: elapsedFrames)
                layerInstance.def.rotation    = 0
                layerInstance.def.pivotOffset = .zero
                layerInstance.def.position    = .zero
                // 0.5 × 2.0 = 1.0 in applyTransform, cancelling the built-in 2× scale factor.
                // Chain already baked def.scale and anim.scale for every ancestor.
                layerInstance.def.scale                          = Vector2D(x: 0.5, y: 0.5)
                // Zero out driver values already baked into the chain to prevent double-apply.
                layerInstance.state.transform.rotation           = 0
                layerInstance.state.transform.positionOffset     = .zero
                layerInstance.state.transform.scale              = Vector2D(x: 1, y: 1)
                chainParentWorld = nil
            } else if let pose = blendedPose {
                layerInstance.def.position = pose.position
                layerInstance.def.rotation = pose.rotation
                layerInstance.def.scale    = pose.scale
            }

            if needsOffscreen {
                // Render layer at full opacity into offscreen, then composite at layer.alpha * spriteOpacity.
                guard let offscreen = makeOffscreenContext(size: viewTransform.canvasSize) else { continue }
                layerInstance.state.transform.opacity = 1.0
                renderInstance(layerInstance, spriteIndex: spriteIndex, parentWorld: chainParentWorld,
                               into: offscreen, viewTransform: viewTransform,
                               brushImages: brushImages, stampImages: stampImages,
                               elapsedFrames: elapsedFrames,
                               progressiveBrushStates: &progressiveBrushStates,
                               progressiveBrushEnabled: progressiveBrushEnabled,
                               using: &rng)
                guard let img = offscreen.makeImage() else { continue }
                let compositeAlpha = CGFloat(layer.alpha * spriteOpacity)
                context.saveGState()
                context.concatenate(context.ctm.inverted())
                context.setAlpha(compositeAlpha)
                let sz = viewTransform.canvasSize
                context.draw(img, in: CGRect(x: 0, y: 0, width: sz.width, height: sz.height))
                context.restoreGState()
            } else {
                // Hard cut: opacity already correct from the instance.
                layerInstance.state.transform.opacity = spriteOpacity
                renderInstance(layerInstance, spriteIndex: spriteIndex, parentWorld: chainParentWorld,
                               into: context, viewTransform: viewTransform,
                               brushImages: brushImages, stampImages: stampImages,
                               elapsedFrames: elapsedFrames,
                               progressiveBrushStates: &progressiveBrushStates,
                               progressiveBrushEnabled: progressiveBrushEnabled,
                               using: &rng)
            }
        }
    }

#if canImport(AppKit)
    /// Draw an NSImage SVG sprite, applying all transform drivers and the full parent hierarchy.
    ///
    /// The context is expected to have the Y-flip applied by `LoomEngine.renderImpl`.
    /// This method counters that flip locally so the image draws right-side-up.
    private func renderSVGInstance(
        _ instance: SpriteInstance,
        nsImage: NSImage,
        parentWorld: ParentWorld?,
        into context: CGContext,
        viewTransform: ViewTransform,
        spriteIndex: Int,
        elapsedFrames: Double
    ) {
        let def  = instance.def
        let anim = instance.state.transform

        let hw            = viewTransform.canvasSize.width  / 2.0
        let hh            = viewTransform.canvasSize.height / 2.0
        let geometryBasis = min(viewTransform.canvasSize.width, viewTransform.canvasSize.height) / 2.0

        // Scale (×2 matches the polygon coordinate convention).
        var sx = def.scale.x * anim.scale.x * 2.0
        var sy = def.scale.y * anim.scale.y * 2.0

        // Rotation in degrees (CCW positive in world Y-up space).
        var rotDeg = def.rotation + anim.rotation
        if let c = def.pivotConstraint { rotDeg = max(c.minAngle, min(c.maxAngle, rotDeg)) }

        // World position in pixels from canvas centre.
        let localTx = (def.position.x + anim.positionOffset.x) / 100.0 * hw
        let localTy = (def.position.y + anim.positionOffset.y) / 100.0 * hh
        var txPx = localTx
        var tyPx = localTy

        // Compose with parent hierarchy.
        if let parent = parentWorld {
            let mask = def.inheritMask
            if mask.scale    { sx *= parent.scale.x; sy *= parent.scale.y }
            if mask.rotation { rotDeg += parent.rotationDeg }
            if mask.position {
                let rad  = parent.rotationDeg * .pi / 180.0
                let cosP = cos(rad), sinP = sin(rad)
                var relTx = localTx - parent.storedPositionPx.x
                var relTy = localTy - parent.storedPositionPx.y
                if mask.scale {
                    relTx *= parent.scale.x
                    relTy *= parent.scale.y
                }
                txPx = parent.positionPx.x + relTx * cosP - relTy * sinP
                tyPx = parent.positionPx.y + relTx * sinP + relTy * cosP
            }
        }

        let spriteOpacity = max(0, min(1, anim.opacity))
        guard spriteOpacity > 0 else { return }

        // Screen size: sprite scale × geometry basis × camera zoom.
        let screenW = CGFloat(sx * geometryBasis * viewTransform.zoom)
        let screenH = CGFloat(sy * geometryBasis * viewTransform.zoom)
        guard screenW > 0, screenH > 0 else { return }

        // Pivot: the image body rotates around position + pivotOffset; compute effective centre.
        let pivotPxX = def.pivotOffset.x / 100.0 * hw
        let pivotPxY = def.pivotOffset.y / 100.0 * hh
        let effectiveTxPx: Double
        let effectiveTyPx: Double
        if pivotPxX != 0 || pivotPxY != 0 {
            let rotR = rotDeg * .pi / 180.0
            let cosR = cos(rotR), sinR = sin(rotR)
            let relX = -pivotPxX, relY = -pivotPxY
            effectiveTxPx = txPx + pivotPxX + relX * cosR - relY * sinR
            effectiveTyPx = tyPx + pivotPxY + relX * sinR + relY * cosR
        } else {
            effectiveTxPx = txPx
            effectiveTyPx = tyPx
        }

        // Screen centre position (camera rotation and pan already baked into viewTransform).
        let centre = viewTransform.worldToScreen(Vector2D(x: effectiveTxPx, y: effectiveTyPx))

        // Total rotation: sprite + camera (CCW positive in Y-up / screen CCW).
        let rotRad = CGFloat((rotDeg + viewTransform.rotation) * .pi / 180.0)

        context.saveGState()
        context.setAlpha(CGFloat(spriteOpacity))
        // Translate to the sprite's screen position, counter the LoomEngine Y-flip,
        // then rotate so the image orientation matches polygon sprites.
        context.translateBy(x: centre.x, y: centre.y)
        context.scaleBy(x: 1, y: -1)
        context.rotate(by: rotRad)

        let drawRect = CGRect(x: -screenW / 2, y: -screenH / 2, width: screenW, height: screenH)
        let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        nsImage.draw(in: drawRect)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }
#endif

    private func drawPointsWithElementChanges<RNG: RandomNumberGenerator>(
        _ polygon: Polygon2D,
        renderer: Renderer,
        baseChanges: RendererChanges,
        state: RendererAnimationState,
        into context: CGContext,
        transform: ViewTransform,
        qualityMultiple: Int,
        opacityMultiplier: Double,
        spriteIndex: Int,
        elapsedFrames: Double,
        using rng: inout RNG
    ) {
        var pointState = state
        for anchor in pointAnchors(in: polygon) {
            let pointRenderer = RenderStateEngine.resolve(
                renderer: renderer,
                state: pointState,
                changes: baseChanges,
                scales: [.point]
            )
            let drivenPointRenderer = resolveRendererDrivers(
                pointRenderer,
                spriteIndex: spriteIndex,
                elapsedFrames: elapsedFrames
            )
            RenderEngine.draw(
                Polygon2D(points: [anchor.point], type: .point, pressures: [anchor.pressure], visible: polygon.visible),
                renderer: drivenPointRenderer,
                into: context,
                transform: transform,
                qualityMultiple: qualityMultiple,
                opacityMultiplier: opacityMultiplier
            )
            pointState = RenderStateEngine.advance(
                state: pointState,
                changes: baseChanges,
                scales: [.point],
                using: &rng
            )
        }
    }

    private func pointAnchors(in polygon: Polygon2D) -> [(point: Vector2D, pressure: Double)] {
        switch polygon.type {
        case .spline, .openSpline:
            return stride(from: 0, to: polygon.points.count, by: 4).enumerated().map { anchorIndex, pointIndex in
                let pressure = anchorIndex < polygon.pressures.count ? polygon.pressures[anchorIndex] : 1.0
                return (polygon.points[pointIndex], pressure)
            }
        default:
            return polygon.points.enumerated().map { index, point in
                let pressure = index < polygon.pressures.count ? polygon.pressures[index] : 1.0
                return (point, pressure)
            }
        }
    }

    // MARK: - Transform helpers

    /// Convert a polygon from Loom world coordinates to screen pixel coordinates.
    ///
    /// ### Loom coordinate conventions
    /// The Loom project format uses three distinct coordinate scales that must all be
    /// resolved before `RenderEngine` can draw in pixel space:
    ///
    /// - **Polygon points** are stored in normalised geometry space (typically ±0.5).
    ///   Multiplying by `2.0` fills the canonical world range `[−1, 1]`.
    /// - **Sprite scale** (`def.scale`) is an additional multiplier applied on top of
    ///   the ×2 geometry factor.
    /// - **Sprite position** is in units of 1/100 of the canvas half-size.
    ///   Dividing by 100 and multiplying by each axis' canvas half-size converts
    ///   to pixels, so placement still follows the canvas aspect ratio.
    /// - **Sprite geometry** uses the shorter canvas dimension as a uniform
    ///   pixel basis, so shapes keep their proportions on non-square canvases.
    ///
    /// ### Pipeline
    /// 1. Scale point by `2.0 × sprite_scale` in normalised world space.
    /// 2. Rotate (in normalised space so rotation is undistorted on square canvases).
    /// 3. Multiply both axes by the shorter canvas half-size to get pixel
    ///    offsets from canvas centre without aspect stretching.
    /// 4. Add pixel-space position (raw_pos / 100 × per-axis canvas_half).
    ///
    /// The caller (`renderInstance`) then passes the resulting pixel-space polygon to
    /// `RenderEngine.draw`, whose `ViewTransform.worldToScreen` adds the canvas-centre
    /// offset to produce final screen coordinates.
    private func applyTransform(
        _ polygon: Polygon2D,
        to instance: SpriteInstance,
        parentWorld: ParentWorld?,
        canvasSize: CGSize
    ) -> Polygon2D {
        let def  = instance.def
        let anim = instance.state.transform

        let hw = canvasSize.width  / 2.0
        let hh = canvasSize.height / 2.0
        let geometryBasis = min(canvasSize.width, canvasSize.height) / 2.0

        // Local scale (×2 for coord convention: polygon coords in [−0.5, 0.5]).
        var sx = def.scale.x * anim.scale.x * 2.0
        var sy = def.scale.y * anim.scale.y * 2.0

        // Local rotation in degrees.
        var rotDeg = def.rotation + anim.rotation
        if let c = def.pivotConstraint { rotDeg = max(c.minAngle, min(c.maxAngle, rotDeg)) }

        // Local position in pixels (1/100 of canvas half-size per unit).
        let localTx = (def.position.x + anim.positionOffset.x) / 100.0 * hw
        let localTy = (def.position.y + anim.positionOffset.y) / 100.0 * hh
        var txPx    = localTx
        var tyPx    = localTy

        // Compose with parent world transform according to the inherit mask.
        if let parent = parentWorld {
            let mask = def.inheritMask
            if mask.scale {
                sx *= parent.scale.x
                sy *= parent.scale.y
            }
            if mask.rotation {
                rotDeg += parent.rotationDeg
            }
            if mask.position {
                let rad  = parent.rotationDeg * .pi / 180.0
                let cosP = cos(rad), sinP = sin(rad)
                var relTx = localTx - parent.storedPositionPx.x
                var relTy = localTy - parent.storedPositionPx.y
                if mask.scale {
                    relTx *= parent.scale.x
                    relTy *= parent.scale.y
                }
                txPx = parent.positionPx.x + relTx * cosP - relTy * sinP
                tyPx = parent.positionPx.y + relTx * sinP + relTy * cosP
            }
        }

        let rotRad = rotDeg * .pi / 180.0
        let cosR   = cos(rotRad)
        let sinR   = sin(rotRad)

        // Pivot offset: rotate around position + pivotOffset rather than position.
        // Express pivot in geometry space (same space as the scaled, pre-translated points).
        let pivotGX = def.pivotOffset.x / 100.0 * hw / geometryBasis
        let pivotGY = def.pivotOffset.y / 100.0 * hh / geometryBasis
        let hasPivot = (pivotGX != 0 || pivotGY != 0) && rotRad != 0

        let pts = polygon.points.map { pt -> Vector2D in
            var wx = pt.x * sx
            var wy = pt.y * sy
            if rotRad != 0 {
                if hasPivot {
                    wx -= pivotGX; wy -= pivotGY
                    let rx = wx * cosR - wy * sinR
                    let ry = wx * sinR + wy * cosR
                    wx = rx + pivotGX; wy = ry + pivotGY
                } else {
                    let rx = wx * cosR - wy * sinR
                    let ry = wx * sinR + wy * cosR
                    wx = rx; wy = ry
                }
            }
            return Vector2D(x: wx * geometryBasis + txPx,
                            y: wy * geometryBasis + tyPx)
        }
        return Polygon2D(points: pts, type: polygon.type,
                         pressures: polygon.pressures,
                         pressureProfiles: polygon.pressureProfiles,
                         visible: polygon.visible)
    }

    /// Resolve a step index into a shape-sequence array position, applying loop / once / ping-pong.
    private func sequenceIndex(step: Int, count: Int, mode: LoopMode) -> Int {
        guard count > 0 else { return 0 }
        switch mode {
        case .loop:
            return step % count
        case .once:
            return min(step, count - 1)
        case .pingPong:
            let period = max(1, (count - 1) * 2)
            let n      = step % period
            return n < count ? n : period - n
        }
    }

    // MARK: - Pose interpolation helpers

    /// Interpolates between two angles (degrees) taking the shortest arc.
    /// Wraps the delta into (−180, 180] before applying, preventing 350° → 10° from
    /// spinning backwards through 340°.
    private func lerpAngle(_ a: Double, _ b: Double, t: Double) -> Double {
        var delta = b - a
        while delta >  180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return a + delta * t
    }

    // MARK: - Renderer-set helpers

    private func resolveActiveRenderers(for instance: SpriteInstance) -> [(index: Int, renderer: Renderer)] {
        let set = instance.rendererSet
        guard !set.renderers.isEmpty else { return [] }

        switch set.playbackConfig.mode {
        case .all:
            return set.renderers.enumerated().compactMap { idx, renderer in
                renderer.enabled ? (idx, renderer) : nil
            }
        default:
            let idx = min(instance.state.activeRendererIndex, set.renderers.count - 1)
            let r = set.renderers[idx]
            return r.enabled ? [(idx, r)] : []
        }
    }

    private func rendererAnimationState(for instance: SpriteInstance, rendererIndex: Int? = nil) -> RendererAnimationState {
        guard !instance.rendererSet.renderers.isEmpty else { return RendererAnimationState() }
        let requestedIndex = rendererIndex ?? instance.state.activeRendererIndex
        let idx    = min(max(requestedIndex, 0), instance.rendererSet.renderers.count - 1)
        let states = instance.state.rendererAnimationStates
        guard idx < states.count else { return RendererAnimationState() }
        return states[idx]
    }

    private func resolveRendererChanges(_ renderer: Renderer,
                                        rendererIndex: Int? = nil,
                                        instance: SpriteInstance,
                                        scales: Set<ChangeScale>? = nil) -> Renderer {
        return RenderStateEngine.resolve(
            renderer: renderer,
            state:    rendererAnimationState(for: instance, rendererIndex: rendererIndex),
            changes:  renderer.changes,
            scales:   scales
        )
    }

    private func resolveRendererDrivers(_ renderer: Renderer,
                                        spriteIndex: Int,
                                        elapsedFrames: Double) -> Renderer {
        guard let drivers = renderer.drivers else { return renderer }
        var resolved = renderer
        if let fillColor = drivers.fillColor, fillColor.enabled {
            resolved.fillColor = DriverEvaluator.evaluate(fillColor, globalElapsed: elapsedFrames,
                                                          targetFPS: targetFPS, spriteIndex: spriteIndex)
        }
        if let strokeColor = drivers.strokeColor, strokeColor.enabled {
            resolved.strokeColor = DriverEvaluator.evaluate(strokeColor, globalElapsed: elapsedFrames,
                                                             targetFPS: targetFPS, spriteIndex: spriteIndex)
        }
        if drivers.strokeWidth.enabled {
            resolved.strokeWidth = max(0, DriverEvaluator.evaluate(drivers.strokeWidth,
                                                                    globalElapsed: elapsedFrames,
                                                                    targetFPS: targetFPS,
                                                                    spriteIndex: spriteIndex))
        }
        if drivers.blur.enabled {
            resolved.blurRadius = max(0, DriverEvaluator.evaluate(drivers.blur,
                                                                   globalElapsed: elapsedFrames,
                                                                   targetFPS: targetFPS,
                                                                   spriteIndex: spriteIndex))
        }
        if drivers.gradientBlend.enabled,
           let gradA = resolved.gradientConfig,
           let gradB = resolved.gradientConfigB {
            let t = max(0, min(1, DriverEvaluator.evaluate(drivers.gradientBlend,
                                                           globalElapsed: elapsedFrames,
                                                           targetFPS: targetFPS,
                                                           spriteIndex: spriteIndex)))
            resolved.gradientConfig = gradA.lerped(to: gradB, t: t)
        }
        return resolved
    }

    private func resolveRendererOpacity(_ renderer: Renderer,
                                        spriteIndex: Int,
                                        elapsedFrames: Double) -> Double {
        guard let drivers = renderer.drivers, drivers.opacity.enabled else { return 1.0 }
        return max(0, min(1, DriverEvaluator.evaluate(drivers.opacity, globalElapsed: elapsedFrames,
                                                      targetFPS: targetFPS, spriteIndex: spriteIndex)))
    }

    // MARK: - Per-renderer Gaussian blur

    private func applyRendererBlur(from offscreen: CGContext, blurRadius: Double,
                                   into context: CGContext, canvasSize: CGSize) {
        guard let img = offscreen.makeImage() else { return }
        let ciImg = CIImage(cgImage: img)
        guard let filter = CIFilter(name: "CIGaussianBlur",
                                    parameters: [kCIInputImageKey: ciImg,
                                                 kCIInputRadiusKey: blurRadius]),
              let output = filter.outputImage
        else { return }
        let cropped = output.cropped(to: ciImg.extent)
        guard let blurred = SpriteScene.ciContext.createCGImage(cropped, from: ciImg.extent)
        else { return }
        // Draw in CGContext native space (0,0 bottom-left), undoing the Y-flip in the main context.
        context.saveGState()
        context.concatenate(context.ctm.inverted())
        context.draw(blurred, in: CGRect(x: 0, y: 0,
                                         width: canvasSize.width, height: canvasSize.height))
        context.restoreGState()
    }

    private func makeOffscreenContext(size: CGSize) -> CGContext? {
        let w = Int(size.width); let h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        // Apply the same Y-flip used by LoomEngine so all draw code works identically.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        return ctx
    }
}
