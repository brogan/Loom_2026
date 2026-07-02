import AppKit
import SwiftUI
import LoomEngine

// Canvas-drag pose editor for SpriteCycles.
//
// All Knight sprites have position (0,0): their visual position is baked into
// their polygon geometry.  Posing means rotating each part around its pivot.
// Parent-child hierarchy propagates rotation; pivot positions are computed
// correctly in geometry space after ancestor transforms.

struct CyclePoseCanvas: View {
    @EnvironmentObject var controller: AppController
    let cycleIdx: Int
    @Binding var selectedStateIndex: Int?

    @State private var selectedSpriteName: String? = nil
    @State private var dragMode: DragMode = .none
    @State private var dragStartAngle: Double  = 0
    @State private var dragStartRotation: Double = 0
    @State private var dragPivotScreen: CGPoint  = .zero
    @State private var spritePolygons: [String: [Polygon2D]] = [:]
    @State private var gScaleMultiplier: CGFloat = 0.78

    private enum DragMode { case none, rotating }
    private let ringRadius:   CGFloat = 44
    private let ringHitWidth: CGFloat = 14
    private let pivotHitRadius: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                Color(white: 0.06)

                Canvas { ctx, size in
                    drawScene(ctx: ctx, size: size)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in onDragChange(v, size: geo.size) }
                        .onEnded   { _ in dragMode = .none }
                )

                // Scale slider + hint
                VStack(alignment: .leading, spacing: 2) {
                    if let name = selectedSpriteName {
                        let rot = (currentOverrides[name]?.rotation ?? allSprites.first(where: { $0.name == name })?.rotation ?? 0)
                        Text("\(name)  \(rot, specifier: "%.1f")°")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Click a pivot · drag ring to rotate")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Slider(value: $gScaleMultiplier, in: 0.3...1.4)
                            .frame(width: 70)
                            .controlSize(.mini)
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }
        }
        .onAppear { loadPolygons() }
        .onChange(of: controller.projectConfig?.spriteConfig.library.spriteSets.count) { _, _ in loadPolygons() }
    }

    // MARK: - Drawing

    private func drawScene(ctx: GraphicsContext, size: CGSize) {
        let sprites  = allSprites
        let overrides = currentOverrides
        let cx = size.width  / 2
        let cy = size.height / 2
        let gScale = min(size.width, size.height) * gScaleMultiplier

        // Centre cross
        var cross = Path()
        cross.move(to: CGPoint(x: cx - 6, y: cy)); cross.addLine(to: CGPoint(x: cx + 6, y: cy))
        cross.move(to: CGPoint(x: cx, y: cy - 6)); cross.addLine(to: CGPoint(x: cx, y: cy + 6))
        ctx.stroke(cross, with: .color(.white.opacity(0.07)), lineWidth: 0.5)

        // Polygon outlines for every sprite
        for sp in sprites {
            guard let polys = spritePolygons[sp.name] else { continue }
            let isSelected  = sp.name == selectedSpriteName
            let hasPoseOver = overrides[sp.name] != nil
            let color: Color = isSelected ? .orange
                : hasPoseOver ? Color(red: 0.35, green: 0.88, blue: 0.52)
                : .white
            let alpha: Double = isSelected ? 0.90 : hasPoseOver ? 0.72 : 0.30
            let lw: CGFloat   = isSelected ? 1.4  : 0.85

            for poly in polys where poly.visible {
                guard !poly.points.isEmpty else { continue }
                let pts = poly.points.map { p -> CGPoint in
                    let wpt = transformPoint(CGPoint(x: p.x, y: p.y),
                                             sprite: sp, sprites: sprites, overrides: overrides)
                    return CGPoint(x: cx + wpt.x * gScale, y: cy - wpt.y * gScale)
                }
                ctx.stroke(buildPath(pts, type: poly.type),
                           with: .color(color.opacity(alpha)), lineWidth: lw)
            }
        }

        // Pivot dots and rotation ring
        for sp in sprites {
            let isSelected  = sp.name == selectedSpriteName
            let hasPoseOver = overrides[sp.name] != nil
            let color: Color = isSelected ? .orange
                : hasPoseOver ? Color(red: 0.35, green: 0.88, blue: 0.52)
                : .white

            let wPiv = worldPivot(sp, sprites: sprites, overrides: overrides)
            let pivScreen = CGPoint(x: cx + wPiv.x * gScale, y: cy - wPiv.y * gScale)

            // Pivot dot
            let pr: CGFloat = isSelected ? 5.5 : 3.5
            ctx.fill(Path(ellipseIn: CGRect(x: pivScreen.x - pr, y: pivScreen.y - pr,
                                            width: pr * 2, height: pr * 2)),
                     with: .color(color.opacity(isSelected ? 1.0 : 0.65)))

            // Small label
            ctx.draw(
                Text(sp.name)
                    .font(.system(size: 8))
                    .foregroundStyle(color.opacity(isSelected ? 0.9 : 0.45)),
                at: CGPoint(x: pivScreen.x + 6, y: pivScreen.y - 6),
                anchor: .bottomLeading
            )

            // Rotation ring (selected only)
            if isSelected {
                let ring = Path(ellipseIn: CGRect(x: pivScreen.x - ringRadius,
                                                   y: pivScreen.y - ringRadius,
                                                   width: ringRadius * 2,
                                                   height: ringRadius * 2))
                ctx.stroke(ring, with: .color(Color.orange.opacity(0.55)),
                            style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))

                // Handle dot on ring at current local rotation angle (Y-flip for screen)
                let localRot = overrides[sp.name]?.rotation ?? sp.rotation
                let handleRad = CGFloat(localRot * .pi / 180.0)
                let handlePt = CGPoint(x: pivScreen.x + ringRadius * cos(handleRad),
                                       y: pivScreen.y - ringRadius * sin(handleRad))
                ctx.fill(Path(ellipseIn: CGRect(x: handlePt.x - 5.5, y: handlePt.y - 5.5,
                                                width: 11, height: 11)),
                         with: .color(.orange))

                // Zero-line (showing 0° direction)
                var zeroLine = Path()
                zeroLine.move(to: pivScreen)
                zeroLine.addLine(to: CGPoint(x: pivScreen.x + ringRadius * 0.7, y: pivScreen.y))
                ctx.stroke(zeroLine, with: .color(.orange.opacity(0.25)), lineWidth: 0.7)
            }
        }

        // No sprites hint
        if sprites.isEmpty {
            ctx.draw(Text("No sprites in project")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary),
                at: CGPoint(x: cx, y: cy), anchor: .center)
        } else if selectedStateIndex == nil {
            ctx.draw(Text("Select a state to pose")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary.opacity(0.5)),
                at: CGPoint(x: cx, y: cy - size.height * 0.4), anchor: .center)
        }
    }

    // MARK: - Interaction

    private func onDragChange(_ v: DragGesture.Value, size: CGSize) {
        let loc = v.location
        let cx  = size.width  / 2
        let cy  = size.height / 2
        let gScale = min(size.width, size.height) * gScaleMultiplier
        let sprites  = allSprites
        let overrides = currentOverrides

        if dragMode == .none {
            // Check rotation ring of already-selected sprite first
            if let selName = selectedSpriteName,
               let selSp = sprites.first(where: { $0.name == selName }) {
                let wPiv = worldPivot(selSp, sprites: sprites, overrides: overrides)
                let piv  = CGPoint(x: cx + wPiv.x * gScale, y: cy - wPiv.y * gScale)
                if abs(hypot(loc.x - piv.x, loc.y - piv.y) - ringRadius) < ringHitWidth {
                    beginRotation(name: selName, sprite: selSp, pivScreen: piv, loc: loc, overrides: overrides)
                    return
                }
            }

            // Hit-test all pivot dots
            var bestDist = pivotHitRadius
            var bestName: String? = nil
            for sp in sprites {
                let wPiv = worldPivot(sp, sprites: sprites, overrides: overrides)
                let piv  = CGPoint(x: cx + wPiv.x * gScale, y: cy - wPiv.y * gScale)
                let d    = hypot(loc.x - piv.x, loc.y - piv.y)
                if d < bestDist { bestDist = d; bestName = sp.name }
            }
            if let name = bestName, let sp = sprites.first(where: { $0.name == name }) {
                selectedSpriteName = name
                let wPiv = worldPivot(sp, sprites: sprites, overrides: overrides)
                let piv  = CGPoint(x: cx + wPiv.x * gScale, y: cy - wPiv.y * gScale)
                beginRotation(name: name, sprite: sp, pivScreen: piv, loc: loc, overrides: overrides)
            }

        } else if dragMode == .rotating {
            guard let selName = selectedSpriteName,
                  let si = selectedStateIndex else { return }
            let piv = dragPivotScreen
            let currentAngle = atan2(-(loc.y - piv.y), loc.x - piv.x) * 180.0 / .pi
            var delta = currentAngle - dragStartAngle
            while delta >  180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            let newRot = dragStartRotation + delta
            controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(si) else { return }
                if cfg.cycles[cycleIdx].states[si].poseOverrides[selName] != nil {
                    cfg.cycles[cycleIdx].states[si].poseOverrides[selName]!.rotation = newRot
                }
            }
        }
    }

    private func beginRotation(name: String, sprite: SpriteDef, pivScreen: CGPoint,
                                loc: CGPoint, overrides: [String: SpritePoseOverride]) {
        guard let si = selectedStateIndex else { return }
        ensurePoseOverride(name: name, sprite: sprite, stateIdx: si)
        dragMode = .rotating
        dragPivotScreen  = pivScreen
        dragStartAngle   = atan2(-(loc.y - pivScreen.y), loc.x - pivScreen.x) * 180.0 / .pi
        dragStartRotation = overrides[name]?.rotation ?? sprite.rotation
    }

    // MARK: - Geometry helpers (all-zero-position sprites)

    // Apply a sequence of (world_pivot, local_rotation_deg) pairs to a point.
    // worldPivots and rotations are parallel arrays, root first.
    private func applyChain(_ point: CGPoint, worldPivots: [CGPoint], rotations: [Double]) -> CGPoint {
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

    // Build the ancestor chain [root, …, sprite] and precompute each sprite's
    // world pivot (the position of that sprite's pivot after all ancestor rotations).
    private func buildChain(_ sprite: SpriteDef, sprites: [SpriteDef]) -> [SpriteDef] {
        var chain: [SpriteDef] = []
        var cur: SpriteDef? = sprite
        while let s = cur {
            chain.insert(s, at: 0)
            cur = s.parentName.flatMap { n in sprites.first { $0.name == n } }
        }
        return chain
    }

    private func buildWorldPivots(chain: [SpriteDef], overrides: [String: SpritePoseOverride]) -> [CGPoint] {
        var wPivots = [CGPoint]()
        var rots    = [Double]()
        for sp in chain {
            let restPiv = CGPoint(x: sp.pivotOffset.x / 100.0, y: sp.pivotOffset.y / 100.0)
            let wp = applyChain(restPiv, worldPivots: wPivots, rotations: rots)
            wPivots.append(wp)
            rots.append(overrides[sp.name]?.rotation ?? sp.rotation)
        }
        return wPivots
    }

    // World pivot of a sprite — its rest pivot rotated by all PARENT transforms.
    // (This is where the pivot dot should appear on screen.)
    private func worldPivot(_ sp: SpriteDef, sprites: [SpriteDef],
                             overrides: [String: SpritePoseOverride]) -> CGPoint {
        let chain = buildChain(sp, sprites: sprites)
        // Build world pivots for all ancestors (exclude self — we want the position
        // of sp's pivot BEFORE sp's own rotation is applied).
        var wPivots = [CGPoint]()
        var rots    = [Double]()
        for anc in chain.dropLast() {   // all except sp itself
            let restPiv = CGPoint(x: anc.pivotOffset.x / 100.0, y: anc.pivotOffset.y / 100.0)
            let wp = applyChain(restPiv, worldPivots: wPivots, rotations: rots)
            wPivots.append(wp)
            rots.append(overrides[anc.name]?.rotation ?? anc.rotation)
        }
        let spRestPiv = CGPoint(x: sp.pivotOffset.x / 100.0, y: sp.pivotOffset.y / 100.0)
        return applyChain(spRestPiv, worldPivots: wPivots, rotations: rots)
    }

    // Transform a polygon point (geometry Y-up space) through the full chain
    // including sp's own rotation.
    private func transformPoint(_ p: CGPoint, sprite: SpriteDef, sprites: [SpriteDef],
                                 overrides: [String: SpritePoseOverride]) -> CGPoint {
        let chain   = buildChain(sprite, sprites: sprites)
        let wPivots = buildWorldPivots(chain: chain, overrides: overrides)
        let rots    = chain.map { overrides[$0.name]?.rotation ?? $0.rotation }
        return applyChain(p, worldPivots: wPivots, rotations: rots)
    }

    // MARK: - Path builder (mirrors CyclePreviewPanel)

    private func buildPath(_ pts: [CGPoint], type: PolygonType) -> Path {
        guard !pts.isEmpty else { return Path() }
        var p = Path()
        switch type {
        case .spline:
            guard pts.count >= 4 else { return p }
            p.move(to: pts[0])
            for i in 0..<(pts.count / 4) {
                let b = i * 4
                p.addCurve(to: pts[b+3], control1: pts[b+1], control2: pts[b+2])
            }
            p.closeSubpath()
        case .openSpline:
            guard pts.count >= 4 else { return p }
            p.move(to: pts[0])
            for i in 0..<(pts.count / 4) {
                let b = i * 4
                p.addCurve(to: pts[b+3], control1: pts[b+1], control2: pts[b+2])
            }
        case .point:
            for pt in pts { p.addEllipse(in: CGRect(x: pt.x-2, y: pt.y-2, width: 4, height: 4)) }
        case .oval:
            if pts.count >= 2 {
                let ox = pts[0].x, oy = pts[0].y
                let rx = abs(pts[1].x - ox), ry = abs(pts[1].y - oy)
                p.addEllipse(in: CGRect(x: ox-rx, y: oy-ry, width: rx*2, height: ry*2))
            }
        default:
            guard pts.count >= 2 else { return p }
            p.move(to: pts[0])
            pts.dropFirst().forEach { p.addLine(to: $0) }
            p.closeSubpath()
        }
        return p
    }

    // MARK: - Data access

    private var allSprites: [SpriteDef] {
        controller.projectConfig?.spriteConfig.library.spriteSets.flatMap { $0.sprites } ?? []
    }

    private var currentOverrides: [String: SpritePoseOverride] {
        guard let si = selectedStateIndex else { return [:] }
        return controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: si]?.poseOverrides ?? [:]
    }

    private func ensurePoseOverride(name: String, sprite: SpriteDef, stateIdx: Int) {
        guard controller.projectConfig?.cycles[safe: cycleIdx]?
                .states[safe: stateIdx]?.poseOverrides[name] == nil else { return }
        let init_ = SpritePoseOverride(position: sprite.position,
                                       rotation: sprite.rotation,
                                       scale: sprite.scale)
        controller.updateProjectConfig { cfg in
            guard cfg.cycles.indices.contains(cycleIdx),
                  cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
            cfg.cycles[cycleIdx].states[stateIdx].poseOverrides[name] = init_
        }
    }

    // MARK: - Polygon loading

    private func loadPolygons() {
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
