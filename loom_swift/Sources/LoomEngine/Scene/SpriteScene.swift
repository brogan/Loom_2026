import CoreGraphics
import Foundation

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
public struct SpriteScene: Sendable {

    /// All resolved sprite instances, in declaration order from `sprites.xml`.
    public var instances: [SpriteInstance]

    /// Pixel-space multiplier; all per-instance pixel distances are scaled by this factor.
    private let qualityMultiple: Int

    // MARK: - Convenience (testing)

    /// Directly construct a scene from pre-built instances.
    ///
    /// Intended for unit tests that want to bypass file loading.
    internal init(instances: [SpriteInstance]) {
        self.instances      = instances
        self.qualityMultiple = 1
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
        for sprite in config.spriteConfig.library.allSprites {
            let instance = try SpriteScene.makeInstance(
                sprite: sprite,
                config: config,
                projectDirectory: projectDirectory
            )
            result.append(instance)
        }
        self.instances       = result
        self.qualityMultiple = max(1, config.globalConfig.qualityMultiple)
    }

    private static func makeInstance(
        sprite: SpriteDef,
        config: ProjectConfig,
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
        let morphTargetPolygons: [[Polygon2D]] = sprite.animation.morphTargets.map { ref in
            let url = projectDirectory
                .appendingPathComponent("morphTargets")
                .appendingPathComponent(ref.file)
            return (try? XMLPolygonLoader.load(url: url)) ?? []
        }

        // ── 4. Resolve renderer set ──────────────────────────────────────────
        let rendererSet = config.renderingConfig.library
            .rendererSet(named: sprite.rendererSetName)
            ?? RendererSet(name: sprite.rendererSetName,
                           renderers: [Renderer(name: "default")])

        // ── 5. Resolve subdivision params ────────────────────────────────────
        let paramsName = shapeDef?.subdivisionParamsSetName ?? ""
        let subdivParams: [SubdivisionParams]
        if paramsName.isEmpty || paramsName.caseInsensitiveCompare("none") == .orderedSame {
            subdivParams = []
        } else {
            subdivParams = config.subdivisionConfig.paramsSet(named: paramsName)?.params ?? []
        }

        return SpriteInstance(
            def:                  sprite,
            basePolygons:         basePolygons,
            morphTargetPolygons:  morphTargetPolygons,
            rendererSet:          rendererSet,
            subdivisionParams:    subdivParams,
            state:                SpriteState.initial(for: rendererSet)
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
    public mutating func advance<RNG: RandomNumberGenerator>(
        deltaTime: Double,
        targetFPS: Double,
        using rng: inout RNG
    ) {
        for i in instances.indices {
            SpriteScene.advanceInstance(&instances[i], deltaTime: deltaTime, targetFPS: targetFPS, using: &rng)
        }
    }

    private static func advanceInstance<RNG: RandomNumberGenerator>(
        _ instance: inout SpriteInstance,
        deltaTime: Double,
        targetFPS: Double,
        using rng: inout RNG
    ) {
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
            let elapsedFrames = instance.state.elapsedTime * max(1.0, targetFPS)
            instance.state.transform = TransformAnimator.transform(
                for:           animation,
                elapsedFrames: elapsedFrames,
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
        guard framesToAdvance > 0 else { return }
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
    public func render<RNG: RandomNumberGenerator>(
        into context: CGContext,
        viewTransform: ViewTransform,
        brushImages: [String: CGImage] = [:],
        stampImages: [String: CGImage] = [:],
        elapsedFrames: Double = 0,
        using rng: inout RNG
    ) {
        for instance in instances {
            renderInstance(instance, into: context, viewTransform: viewTransform,
                           brushImages: brushImages, stampImages: stampImages,
                           elapsedFrames: elapsedFrames, using: &rng)
        }
    }

    private func renderInstance<RNG: RandomNumberGenerator>(
        _ instance: SpriteInstance,
        into context: CGContext,
        viewTransform: ViewTransform,
        brushImages: [String: CGImage],
        stampImages: [String: CGImage],
        elapsedFrames: Double,
        using rng: inout RNG
    ) {
        guard !instance.basePolygons.isEmpty else { return }

        // Stop drawing once the per-sprite draw-cycle limit is reached —
        // matching Scala's Sprite2D.draw() check on spriteTotalDraws.
        // totalDraws == 0 means draw indefinitely.
        let anim = instance.def.animation
        guard anim.totalDraws == 0 || instance.state.drawCycle < anim.totalDraws else { return }

        // 1. Morph interpolation
        let morphed = MorphInterpolator.interpolate(
            base:        instance.basePolygons,
            targets:     instance.morphTargetPolygons,
            morphAmount: instance.state.transform.morphAmount
        )

        // 2. Subdivision
        let subdivided: [Polygon2D]
        if instance.subdivisionParams.isEmpty {
            subdivided = morphed
        } else {
            subdivided = SubdivisionEngine.process(
                polygons:  morphed,
                paramSet:  instance.subdivisionParams,
                rng:       &rng
            )
        }

        // 3. Apply the sprite transform (scale → rotate → translate → pixels)
        let transformed = subdivided.map { applyTransform($0, to: instance, canvasSize: viewTransform.canvasSize) }

        // 4. Determine which renderers to apply
        let activeRenderers = resolveActiveRenderers(for: instance)

        // 5. Draw
        for renderer in activeRenderers {
            let resolved = resolveRendererChanges(renderer, instance: instance)

            if resolved.mode == .brushed, let brushCfg = resolved.brushConfig {
                // Brush mode: stamp images along perturbed edge paths.
                let scaledBrush = qualityMultiple > 1
                    ? brushCfg.scaled(by: Double(qualityMultiple)) : brushCfg
                let edges = BrushEdge.extractEdges(from: transformed, viewTransform: viewTransform)
                BrushStampEngine.drawFullPath(
                    edges:         edges,
                    config:        scaledBrush,
                    color:         resolved.strokeColor,
                    context:       context,
                    elapsedFrames: elapsedFrames,
                    brushImages:   brushImages
                )
            } else if (resolved.mode == .stamped || resolved.mode == .stenciled),
                      let stencilCfg = resolved.stencilConfig {
                // Stamp mode: place stamp images at each discrete point position.
                // Look up the per-renderer stencil opacity animation state so
                // StampEngine can use the stepped palette index for SEQ/PING_PONG.
                let scaledStencil = qualityMultiple > 1
                    ? stencilCfg.scaled(by: Double(qualityMultiple)) : stencilCfg
                let activeIdx    = min(instance.state.activeRendererIndex,
                                       instance.rendererSet.renderers.count - 1)
                let opacityState = activeIdx < instance.state.rendererAnimationStates.count
                    ? instance.state.rendererAnimationStates[activeIdx].stencilOpacityState
                    : nil
                for polygon in transformed {
                    StampEngine.draw(
                        polygon:       polygon,
                        config:        scaledStencil,
                        context:       context,
                        viewTransform: viewTransform,
                        stampImages:   stampImages,
                        opacityState:  opacityState,
                        using:         &rng
                    )
                }
            } else {
                for polygon in transformed {
                    RenderEngine.draw(polygon,
                                      renderer:  resolved,
                                      into:      context,
                                      transform: viewTransform)
                }
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
    ///   Dividing by 100 and multiplying by canvas half-size converts to pixels.
    ///
    /// ### Pipeline
    /// 1. Scale point by `2.0 × sprite_scale` in normalised world space.
    /// 2. Rotate (in normalised space so rotation is undistorted on square canvases).
    /// 3. Multiply by canvas half-size to get pixel offsets from canvas centre.
    /// 4. Add pixel-space position (raw_pos / 100 × canvas_half).
    ///
    /// The caller (`renderInstance`) then passes the resulting pixel-space polygon to
    /// `RenderEngine.draw`, whose `ViewTransform.worldToScreen` adds the canvas-centre
    /// offset to produce final screen coordinates.
    private func applyTransform(_ polygon: Polygon2D,
                                 to instance: SpriteInstance,
                                 canvasSize: CGSize) -> Polygon2D {
        let def  = instance.def
        let anim = instance.state.transform

        let hw = canvasSize.width  / 2.0
        let hh = canvasSize.height / 2.0

        // Loom geometry scale: ×2 for canvas convention (polygon coords in [−0.5, 0.5]
        // map to world [−1, 1]), combined with the sprite's own scale multiplier.
        let sx = def.scale.x * anim.scale.x * 2.0
        let sy = def.scale.y * anim.scale.y * 2.0

        // Rotation: sprite base + animation delta (degrees → radians), applied in
        // normalised world space before canvas scaling so it isn't distorted.
        let rotRad = (def.rotation + anim.rotation) * Double.pi / 180.0
        let cosR   = cos(rotRad)
        let sinR   = sin(rotRad)

        // Position in pixels: raw position unit = 1/100 of canvas half-size.
        let tx = (def.position.x + anim.positionOffset.x) / 100.0 * hw
        let ty = (def.position.y + anim.positionOffset.y) / 100.0 * hh

        let pts = polygon.points.map { pt -> Vector2D in
            // 1. Scale in world space.
            var wx = pt.x * sx
            var wy = pt.y * sy

            // 2. Rotate in world space.
            if rotRad != 0 {
                let rx = wx * cosR - wy * sinR
                let ry = wx * sinR + wy * cosR
                wx = rx; wy = ry
            }

            // 3. World → pixels, then add sprite position.
            return Vector2D(x: wx * hw + tx, y: wy * hh + ty)
        }
        return Polygon2D(points: pts, type: polygon.type,
                         pressures: polygon.pressures, visible: polygon.visible)
    }

    // MARK: - Renderer-set helpers

    private func resolveActiveRenderers(for instance: SpriteInstance) -> [Renderer] {
        let set = instance.rendererSet
        guard !set.renderers.isEmpty else { return [] }

        switch set.playbackConfig.mode {
        case .all:
            return set.renderers
        default:
            let idx = min(instance.state.activeRendererIndex, set.renderers.count - 1)
            return [set.renderers[idx]]
        }
    }

    private func resolveRendererChanges(_ renderer: Renderer, instance: SpriteInstance) -> Renderer {
        let idx    = min(instance.state.activeRendererIndex,
                         instance.rendererSet.renderers.count - 1)
        let states = instance.state.rendererAnimationStates
        guard idx < states.count else { return renderer }

        return RenderStateEngine.resolve(
            renderer: renderer,
            state:    states[idx],
            changes:  renderer.changes
        )
    }
}
