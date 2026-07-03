import AppKit
import SwiftUI
import LoomEngine

struct CyclePreviewPanel: View {
    @EnvironmentObject private var controller: AppController
    let cycle: SpriteCycle
    @Binding var selectedStateIndex: Int?

    @State private var allPolygons: [Int: [Polygon2D]] = [:]
    @State private var allSVGImages: [Int: NSImage] = [:]
    /// Per-sprite polygons for pose-mode cycles (blank shapeSetName in states).
    @State private var spritePolygons: [String: [Polygon2D]] = [:]
    @State private var isPlaying = false
    @State private var playFrame = 0
    @AppStorage("cyclePreview.bgBrightness") private var bgBrightness: Double = 0.08

    private let previewFPS = 24.0

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 8) {
                Text("PREVIEW")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Image(systemName: "sun.min")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Slider(value: $bgBrightness, in: 0...1)
                    .frame(width: 64)
                    .controlSize(.mini)
                Spacer()
                legend
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Canvas
            Canvas { ctx, size in
                drawBackground(ctx: ctx, size: size)
                if !allPolygons.isEmpty || !allSVGImages.isEmpty || !spritePolygons.isEmpty {
                    drawShapes(ctx: ctx, size: size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: bgBrightness))
            .overlay(
                Group {
                    if cycle.states.isEmpty {
                        Text("Add states to preview")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else if allPolygons.isEmpty && allSVGImages.isEmpty && spritePolygons.isEmpty {
                        Text("No geometry")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            )

            Divider()

            // Playback controls
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("Frame \(playFrame + 1) / \(max(1, cycle.totalCycleFrames))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let si = currentStateIndex {
                        Text("State \(si + 1)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 14) {
                    Button(action: stepBack) {
                        Image(systemName: "backward.frame.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Previous frame (stops playback)")

                    Button(action: togglePlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15))
                            .frame(width: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isPlaying ? "Pause" : "Play cycle")

                    Button(action: stepForward) {
                        Image(systemName: "forward.frame.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Next frame (stops playback)")

                    Spacer()

                    Button(action: rewind) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Reset to frame 1")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            loadAllPolygons()
            loadSpritePolygons()
            syncFrameToSelection()
        }
        .onChange(of: cycle) { _, _ in
            loadAllPolygons()
            loadSpritePolygons()
        }
        .onChange(of: selectedStateIndex) { _, _ in
            guard !isPlaying else { return }
            syncFrameToSelection()
        }
        .onReceive(
            Timer.publish(every: 1.0 / previewFPS, on: .main, in: .common).autoconnect()
        ) { _ in
            guard isPlaying else { return }
            let total = max(1, cycle.totalCycleFrames)
            playFrame = (playFrame + 1) % total
            if let si = currentStateIndex, selectedStateIndex != si {
                selectedStateIndex = si
            }
        }
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.7))
                .frame(width: 5, height: 5)
            Text("prev")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Circle()
                .fill(Color(red: 0.36, green: 0.82, blue: 0.50))
                .frame(width: 5, height: 5)
            Text("cur")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Circle()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.7))
                .frame(width: 5, height: 5)
            Text("next")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Drawing

    private func drawBackground(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(white: bgBrightness)))
        let cx = size.width / 2, cy = size.height / 2
        var cross = Path()
        cross.move(to: CGPoint(x: cx - 10, y: cy)); cross.addLine(to: CGPoint(x: cx + 10, y: cy))
        cross.move(to: CGPoint(x: cx, y: cy - 10)); cross.addLine(to: CGPoint(x: cx, y: cy + 10))
        ctx.stroke(cross, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5)
    }

    private func drawShapes(ctx: GraphicsContext, size: CGSize) {
        guard !cycle.states.isEmpty else { return }
        let count = cycle.states.count

        // Sprite-pose mode: cycle states have no geometry, use per-sprite polygons with poses.
        if allPolygons.isEmpty && allSVGImages.isEmpty && !spritePolygons.isEmpty {
            drawSpritePose(ctx: ctx, size: size)
            return
        }

        // Shape mode: cycle states carry their own geometry (legacy / non-rig cycles).
        let currentIdx = currentStateIndex ?? 0

        if count > 1 {
            let prevIdx = (currentIdx - 1 + count) % count
            if let polys = allPolygons[prevIdx] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 0.35, green: 0.55, blue: 1.0).opacity(0.28),
                     lineWidth: 1.0)
            } else if let img = allSVGImages[prevIdx] {
                drawSVGImage(img, ctx: ctx, size: size, alpha: 0.28)
            }
        }

        if count > 2 {
            let nextIdx = (currentIdx + 1) % count
            if let polys = allPolygons[nextIdx] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 1.0, green: 0.55, blue: 0.25).opacity(0.28),
                     lineWidth: 1.0)
            } else if let img = allSVGImages[nextIdx] {
                drawSVGImage(img, ctx: ctx, size: size, alpha: 0.28)
            }
        }

        for layer in cycle.renderLayers(atFrame: playFrame) {
            if let polys = allPolygons[layer.stateIndex] {
                draw(polys, in: ctx, size: size,
                     color: Color(red: 0.36, green: 0.82, blue: 0.50).opacity(layer.alpha * 0.92),
                     lineWidth: 1.3)
            } else if let img = allSVGImages[layer.stateIndex] {
                drawSVGImage(img, ctx: ctx, size: size, alpha: layer.alpha * 0.92)
            }
        }
    }

    // MARK: Sprite-pose drawing

    /// Draws all sprites with their hierarchically-composed cycle pose for the current playFrame.
    /// Ghost outlines for the previous and next states are drawn for context.
    private func drawSpritePose(ctx: GraphicsContext, size: CGSize) {
        guard !cycle.states.isEmpty else { return }
        let count    = cycle.states.count
        let curIdx   = currentStateIndex ?? 0
        let sprites  = allSpritesList

        // Ghost: previous state
        if count > 1 {
            let prevIdx  = (curIdx - 1 + count) % count
            let overrides = stateOverrides(stateIdx: prevIdx, sprites: sprites)
            drawPosedSprites(ctx: ctx, size: size, sprites: sprites, overrides: overrides,
                             color: Color(red: 0.35, green: 0.55, blue: 1.0), alpha: 0.22)
        }
        // Ghost: next state
        if count > 2 {
            let nextIdx   = (curIdx + 1) % count
            let overrides = stateOverrides(stateIdx: nextIdx, sprites: sprites)
            drawPosedSprites(ctx: ctx, size: size, sprites: sprites, overrides: overrides,
                             color: Color(red: 1.0, green: 0.55, blue: 0.25), alpha: 0.22)
        }
        // Current animated pose (blended across transitions)
        let overrides = blendedOverrides(atFrame: playFrame, sprites: sprites)
        drawPosedSprites(ctx: ctx, size: size, sprites: sprites, overrides: overrides,
                         color: Color(red: 0.36, green: 0.82, blue: 0.50), alpha: 0.90)
    }

    /// Effective overrides for a single static state (no interpolation).
    private func stateOverrides(stateIdx: Int, sprites: [SpriteDef]) -> [String: SpritePoseOverride] {
        guard cycle.states.indices.contains(stateIdx) else { return [:] }
        var result: [String: SpritePoseOverride] = [:]
        let stateOvr = cycle.states[stateIdx].poseOverrides
        // Mirror chainTransformPolygons: fall back to base state overrides before def values
        // so sparse states don't collapse to the rest pose in the preview.
        let baseOvr: [String: SpritePoseOverride]? = cycle.baseStateIndex.flatMap { bi in
            guard bi < cycle.states.count, bi != stateIdx else { return nil }
            return cycle.states[bi].poseOverrides
        }
        for sp in sprites {
            let defPose = SpritePoseOverride(position: sp.position, rotation: sp.rotation, scale: sp.scale)
            result[sp.name] = stateOvr[sp.name] ?? baseOvr?[sp.name] ?? defPose
        }
        return result
    }

    /// Pose overrides blended between the outgoing and incoming states for `frame`.
    private func blendedOverrides(atFrame frame: Int, sprites: [SpriteDef]) -> [String: SpritePoseOverride] {
        let layers = cycle.renderLayers(atFrame: frame)
        guard !layers.isEmpty else { return stateOverrides(stateIdx: 0, sprites: sprites) }
        if layers.count == 1 {
            return stateOverrides(stateIdx: layers[0].stateIndex, sprites: sprites)
        }
        let outIdx = layers[0].stateIndex
        let inIdx  = layers[1].stateIndex
        let t      = layers[1].alpha
        var result: [String: SpritePoseOverride] = [:]
        // Base-state fallback: matches chainTransformPolygons logic so preview is consistent
        // with the actual render when states use sparse overrides.
        let baseOvr: [String: SpritePoseOverride]? = cycle.baseStateIndex.flatMap { bi in
            guard bi < cycle.states.count, bi != outIdx, bi != inIdx else { return nil }
            return cycle.states[bi].poseOverrides
        }
        for sp in sprites {
            let defPose = SpritePoseOverride(position: sp.position, rotation: sp.rotation, scale: sp.scale)
            let fallback = baseOvr?[sp.name] ?? defPose
            let outOvr = (outIdx < cycle.states.count ? cycle.states[outIdx].poseOverrides[sp.name] : nil) ?? fallback
            let inOvr  = (inIdx  < cycle.states.count ? cycle.states[inIdx].poseOverrides[sp.name]  : nil) ?? fallback
            var delta  = inOvr.rotation - outOvr.rotation
            while delta >  180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            result[sp.name] = SpritePoseOverride(
                position: Vector2D(x: outOvr.position.x + (inOvr.position.x - outOvr.position.x) * t,
                                   y: outOvr.position.y + (inOvr.position.y - outOvr.position.y) * t),
                rotation: outOvr.rotation + delta * t,
                scale:    Vector2D(x: outOvr.scale.x + (inOvr.scale.x - outOvr.scale.x) * t,
                                   y: outOvr.scale.y + (inOvr.scale.y - outOvr.scale.y) * t)
            )
        }
        return result
    }

    private func drawPosedSprites(ctx: GraphicsContext, size: CGSize,
                                   sprites: [SpriteDef],
                                   overrides: [String: SpritePoseOverride],
                                   color: Color, alpha: Double) {
        let gScale = min(size.width, size.height) * 0.80
        let cx = size.width / 2, cy = size.height / 2

        for sp in sprites {
            guard let polys = spritePolygons[sp.name] else { continue }
            let posOvr   = overrides[sp.name]?.position ?? sp.position
            let posOffX  = posOvr.x / 200.0
            let posOffY  = posOvr.y / 200.0
            for poly in polys where poly.visible {
                guard !poly.points.isEmpty else { continue }
                let pts = poly.points.map { p -> CGPoint in
                    var wpt = poseTransformPoint(CGPoint(x: p.x, y: p.y),
                                                 sprite: sp, sprites: sprites, overrides: overrides)
                    wpt.x += posOffX; wpt.y += posOffY
                    return CGPoint(x: cx + wpt.x * gScale, y: cy - wpt.y * gScale)
                }
                ctx.stroke(buildPath(pts, type: poly.type),
                           with: .color(color.opacity(alpha)), lineWidth: 1.0)
            }
        }
    }

    // MARK: Hierarchy geometry helpers (mirrors CyclePoseCanvas, pivot /200 for 2x-scale match)

    private var allSpritesList: [SpriteDef] {
        controller.projectConfig?.spriteConfig.library.spriteSets.flatMap { $0.sprites } ?? []
    }

    private func poseApplyChain(_ point: CGPoint,
                                 worldPivots: [CGPoint], rotations: [Double]) -> CGPoint {
        var pt = point
        for (piv, rot) in zip(worldPivots, rotations) {
            let rad  = rot * .pi / 180.0
            let cosR = cos(rad), sinR = sin(rad)
            let relX = pt.x - piv.x, relY = pt.y - piv.y
            pt = CGPoint(x: cosR * relX - sinR * relY + piv.x,
                         y: sinR * relX + cosR * relY + piv.y)
        }
        return pt
    }

    private func poseBuildChain(_ sprite: SpriteDef, sprites: [SpriteDef]) -> [SpriteDef] {
        var chain: [SpriteDef] = []
        var cur: SpriteDef? = sprite
        while let s = cur {
            chain.insert(s, at: 0)
            cur = s.parentName.flatMap { n in sprites.first { $0.name == n } }
        }
        return chain
    }

    private func poseBuildWorldPivots(chain: [SpriteDef],
                                       overrides: [String: SpritePoseOverride]) -> [CGPoint] {
        var wPivots = [CGPoint]()
        var rots    = [Double]()
        for sp in chain {
            let restPiv = CGPoint(x: sp.pivotOffset.x / 200.0, y: sp.pivotOffset.y / 200.0)
            let wp = poseApplyChain(restPiv, worldPivots: wPivots, rotations: rots)
            wPivots.append(wp)
            rots.append(overrides[sp.name]?.rotation ?? sp.rotation)
        }
        return wPivots
    }

    private func poseTransformPoint(_ p: CGPoint, sprite: SpriteDef, sprites: [SpriteDef],
                                     overrides: [String: SpritePoseOverride]) -> CGPoint {
        let chain   = poseBuildChain(sprite, sprites: sprites)
        let wPivots = poseBuildWorldPivots(chain: chain, overrides: overrides)
        let rots    = chain.map { overrides[$0.name]?.rotation ?? $0.rotation }
        return poseApplyChain(p, worldPivots: wPivots, rotations: rots)
    }

    private func drawSVGImage(_ nsImage: NSImage, ctx: GraphicsContext, size: CGSize, alpha: Double) {
        let maxDim = min(size.width, size.height) * 0.80
        let imgSize = nsImage.size
        let aspect: CGFloat = (imgSize.width > 0 && imgSize.height > 0)
            ? imgSize.width / imgSize.height : 1.0
        let drawW = aspect >= 1.0 ? maxDim : maxDim * aspect
        let drawH = aspect >= 1.0 ? maxDim / aspect : maxDim
        let rect = CGRect(x: (size.width - drawW) / 2, y: (size.height - drawH) / 2,
                          width: drawW, height: drawH)
        var gctx = ctx
        gctx.opacity = alpha
        gctx.draw(Image(nsImage: nsImage), in: rect)
    }

    private func draw(_ polygons: [Polygon2D], in ctx: GraphicsContext, size: CGSize,
                      color: Color, lineWidth: CGFloat) {
        let scale = min(size.width, size.height) * 0.80
        let cx = size.width / 2
        let cy = size.height / 2
        for polygon in polygons where polygon.visible {
            guard !polygon.points.isEmpty else { continue }
            let pts = polygon.points.map { p in
                CGPoint(x: cx + p.x * scale, y: cy - p.y * scale)
            }
            ctx.stroke(buildPath(pts, type: polygon.type), with: .color(color), lineWidth: lineWidth)
        }
    }

    private func buildPath(_ pts: [CGPoint], type: PolygonType) -> Path {
        guard !pts.isEmpty else { return Path() }
        var p = Path()
        switch type {
        case .spline:
            guard pts.count >= 4 else { return p }
            p.move(to: pts[0])
            for i in 0..<(pts.count / 4) {
                let b = i * 4
                p.addCurve(to: pts[b + 3], control1: pts[b + 1], control2: pts[b + 2])
            }
            p.closeSubpath()
        case .openSpline:
            guard pts.count >= 4 else { return p }
            p.move(to: pts[0])
            for i in 0..<(pts.count / 4) {
                let b = i * 4
                p.addCurve(to: pts[b + 3], control1: pts[b + 1], control2: pts[b + 2])
            }
        case .point:
            for pt in pts {
                p.addEllipse(in: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4))
            }
        case .oval:
            if pts.count >= 2 {
                let ox = pts[0].x, oy = pts[0].y
                let rx = abs(pts[1].x - ox), ry = abs(pts[1].y - oy)
                p.addEllipse(in: CGRect(x: ox - rx, y: oy - ry, width: rx * 2, height: ry * 2))
            }
        default:
            guard pts.count >= 2 else { return p }
            p.move(to: pts[0])
            pts.dropFirst().forEach { p.addLine(to: $0) }
            p.closeSubpath()
        }
        return p
    }

    // MARK: State tracking

    private var currentStateIndex: Int? {
        cycle.renderLayers(atFrame: playFrame).first?.stateIndex
    }

    private func firstFrame(ofState stateIdx: Int) -> Int {
        var f = 0
        for i in 0..<stateIdx where i < cycle.states.count {
            f += max(1, cycle.states[i].holdFrames) + max(0, cycle.states[i].transitionFrames)
        }
        return f
    }

    private func syncFrameToSelection() {
        if let si = selectedStateIndex {
            playFrame = firstFrame(ofState: si)
        }
    }

    // MARK: Playback

    private func togglePlay() { isPlaying.toggle() }

    private func stepBack() {
        isPlaying = false
        let total = max(1, cycle.totalCycleFrames)
        playFrame = (playFrame - 1 + total) % total
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    private func stepForward() {
        isPlaying = false
        let total = max(1, cycle.totalCycleFrames)
        playFrame = (playFrame + 1) % total
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    private func rewind() {
        isPlaying = false
        playFrame = 0
        if let si = currentStateIndex { selectedStateIndex = si }
    }

    // MARK: Geometry loading

    private func loadAllPolygons() {
        guard let cfg = controller.projectConfig,
              let projectURL = controller.projectURL
        else { return }
        var polyResult: [Int: [Polygon2D]] = [:]
        var svgResult:  [Int: NSImage]     = [:]
        for (i, state) in cycle.states.enumerated() {
            if let svgFile = state.svgFilename {
                // Image-mode state: never load polygons, even when no file is chosen yet.
                if !svgFile.isEmpty {
                    let url = projectURL
                        .appendingPathComponent("svgs/sprites")
                        .appendingPathComponent(svgFile)
                    if let img = NSImage(contentsOf: url) { svgResult[i] = img }
                }
            } else {
                let polys = loadPolygons(for: state, config: cfg, projectURL: projectURL)
                if !polys.isEmpty { polyResult[i] = polys }
            }
        }
        allPolygons  = polyResult
        allSVGImages = svgResult
    }

    private func loadPolygons(for state: SpriteCycleState,
                              config: ProjectConfig,
                              projectURL: URL) -> [Polygon2D] {
        guard !state.shapeSetName.isEmpty else { return [] }
        guard let shapeDef = config.shapeConfig.library.shapeSets
            .first(where: { $0.name == state.shapeSetName })?
            .shapes.first(where: { $0.name == state.shapeName })
        else { return [] }

        switch shapeDef.sourceType {

        case .regularPolygon:
            let sides = shapeDef.regularPolygonSides
            guard sides >= 3 else { return [] }
            let angInc = 2.0 * .pi / Double(sides)
            var pts = [Vector2D]()
            for i in 0..<sides {
                let angle = Double(i) * angInc - .pi / 2
                pts.append(Vector2D(x: 0.5 * cos(angle), y: 0.5 * sin(angle)))
            }
            return [Polygon2D(points: pts, type: .line)]

        case .polygonSet:
            guard !shapeDef.polygonSetName.isEmpty,
                  let polyDef = config.polygonConfig.library.polygonSets
                      .first(where: { $0.name == shapeDef.polygonSetName })
            else { return [] }

            if let rp = polyDef.regularParams {
                return [RegularPolygonGenerator.generate(params: rp)]
            }

            let folder = (polyDef.folder == "polygonSet" || polyDef.folder.isEmpty)
                ? "polygonSets" : polyDef.folder
            let url = projectURL
                .appendingPathComponent(folder)
                .appendingPathComponent(polyDef.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }

            if polyDef.filename.lowercased().hasSuffix(".json") {
                return (try? EditableGeometryJSONLoader.load(url: url).runtimePolygons(
                    targetLayerID: polyDef.editableLayerID,
                    targetLayerName: polyDef.editableLayerName
                )) ?? []
            }
            return (try? XMLPolygonLoader.load(url: url)) ?? []

        default:
            return []
        }
    }

    /// Loads per-sprite polygon geometry for pose-mode cycle rendering.
    /// Called when cycle states have blank shapeSetName (pose-only cycle).
    private func loadSpritePolygons() {
        guard let cfg = controller.projectConfig,
              let projectURL = controller.projectURL else { return }
        var result = [String: [Polygon2D]]()
        for ss in cfg.spriteConfig.library.spriteSets {
            for sprite in ss.sprites {
                guard let shapeDef = cfg.shapeConfig.library.shapeSets
                    .first(where: { $0.name == sprite.shapeSetName })?
                    .shapes.first(where: { $0.name == sprite.shapeName }),
                      shapeDef.sourceType == .polygonSet,
                      !shapeDef.polygonSetName.isEmpty,
                      let polyDef = cfg.polygonConfig.library.polygonSets
                          .first(where: { $0.name == shapeDef.polygonSetName })
                else { continue }
                let folder = (polyDef.folder == "polygonSet" || polyDef.folder.isEmpty)
                    ? "polygonSets" : polyDef.folder
                let url = projectURL
                    .appendingPathComponent(folder)
                    .appendingPathComponent(polyDef.filename)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                if polyDef.filename.lowercased().hasSuffix(".json") {
                    if let polys = try? EditableGeometryJSONLoader.load(url: url)
                        .runtimePolygons(targetLayerID: polyDef.editableLayerID,
                                         targetLayerName: polyDef.editableLayerName) {
                        result[sprite.name] = polys
                    }
                } else {
                    if let polys = try? XMLPolygonLoader.load(url: url) {
                        result[sprite.name] = polys
                    }
                }
            }
        }
        spritePolygons = result
    }
}
