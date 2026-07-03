import AppKit
import SwiftUI
import LoomEngine

// Canvas-drag pose editor for SpriteCycles.
//
// Pivot positions use / 200.0 (not / 100.0) because SpriteWireframeView applies
// * 2.0 to polygon points before drawing; pivots were set by dragging in that
// 2x-scaled view, so they live in the same "2x geometry" coordinate space.
// Dividing by 200 instead of 100 brings them back to the unscaled polygon space
// used in this canvas.

struct CyclePoseCanvas: View {
    @EnvironmentObject var controller: AppController
    let cycleIdx: Int
    @Binding var selectedStateIndex: Int?

    @State private var selectedSpriteName: String? = nil
    @State private var dragMode: DragMode = .none
    @State private var dragStartAngle: Double   = 0
    @State private var dragStartRotation: Double = 0
    @State private var dragPivotScreen: CGPoint  = .zero
    @State private var dragStartWorldPos: CGPoint = .zero
    @State private var dragStartScreenLoc: CGPoint = .zero
    @State private var spritePolygons: [String: [Polygon2D]] = [:]
    @State private var gScaleMultiplier: CGFloat = 0.78
    @AppStorage("cycleEditor.showRefLines") private var showRefLines: Bool = true

    private enum DragMode { case none, rotating, translating }
    private let ringRadius:     CGFloat = 44
    private let ringHitWidth:   CGFloat = 14
    private let pivotHitRadius: CGFloat = 18
    private let centerHitRadius: CGFloat = 9

    var body: some View {
        HStack(spacing: 0) {
            spriteHierarchyPanel
                .frame(width: 170)
            Divider()
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    Color(white: 0.06)
                    Canvas { ctx, size in drawScene(ctx: ctx, size: size) }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in onDragChange(v, size: geo.size) }
                                .onEnded   { _ in dragMode = .none }
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        statusLine
                        HStack(spacing: 4) {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                            Slider(value: $gScaleMultiplier, in: 0.3...1.4)
                                .frame(width: 70).controlSize(.mini)
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                }
            }
        }
        .onAppear { loadPolygons() }
        .onChange(of: controller.projectConfig?.spriteConfig.library.spriteSets.count) { _, _ in
            loadPolygons()
        }
    }

    // MARK: - Hierarchy list panel

    private var spriteHierarchyPanel: some View {
        let sprites   = allSprites
        let overrides = currentOverrides
        let roles     = controller.projectConfig?.cycles[safe: cycleIdx]?.spriteLayerRoles ?? [:]
        let roots     = sprites.filter { $0.parentName == nil }
        return VStack(spacing: 0) {
            Text("SPRITES")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(roots, id: \.name) { root in
                        spriteRow(root, depth: 0, sprites: sprites, overrides: overrides, roles: roles)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func spriteRow(_ sp: SpriteDef, depth: Int, sprites: [SpriteDef],
                            overrides: [String: SpritePoseOverride],
                            roles: [String: SpriteLayerRole]) -> AnyView {
        let children    = sprites.filter { $0.parentName == sp.name }
        let isSelected  = selectedSpriteName == sp.name
        let hasOverride = overrides[sp.name] != nil
        let role        = roles[sp.name]

        let dotColor: Color = isSelected ? .orange
            : role == .back  ? Color(red: 0.35, green: 0.60, blue: 1.0)
            : role == .front ? Color(red: 0.25, green: 0.75, blue: 0.40)
            : hasOverride    ? Color(red: 0.25, green: 0.75, blue: 0.40)
            :                  Color(NSColor.tertiaryLabelColor)

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Button { selectedSpriteName = sp.name } label: {
                    HStack(spacing: 6) {
                        Spacer().frame(width: CGFloat(depth * 14 + 4))
                        Circle()
                            .fill(dotColor)
                            .frame(width: 6, height: 6)
                        Text(sp.name)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected
                                             ? Color.orange
                                             : Color(NSColor.labelColor))
                            .lineLimit(1)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .padding(.horizontal, 4)
                    .background(isSelected
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { setLayerRole(.front, forSprite: sp.name) } label: {
                        Label("Front", systemImage: "circle.fill")
                    }
                    Button { setLayerRole(.back, forSprite: sp.name) } label: {
                        Label("Back", systemImage: "circle.fill")
                    }
                    if role != nil {
                        Divider()
                        Button("Clear role") { clearLayerRole(forSprite: sp.name) }
                    }
                }

                ForEach(children, id: \.name) { child in
                    self.spriteRow(child, depth: depth + 1, sprites: sprites,
                                   overrides: overrides, roles: roles)
                }
            }
        )
    }

    private var statusLine: some View {
        Group {
            if let name = selectedSpriteName {
                let over = currentOverrides[name]
                let sp   = allSprites.first { $0.name == name }
                let rot  = over?.rotation ?? sp?.rotation ?? 0
                let posX = over?.position.x ?? sp?.position.x ?? 0
                let posY = over?.position.y ?? sp?.position.y ?? 0
                if over != nil {
                    Text("\(name)  \(rot, specifier: "%.1f")°  (\(posX, specifier: "%.1f"), \(posY, specifier: "%.1f"))")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                } else {
                    Text(name).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
            } else {
                Text("Click sprite · drag ring = rotate · drag dot = move")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Drawing

    private func drawScene(ctx: GraphicsContext, size: CGSize) {
        let sprites   = allSprites
        let overrides = currentOverrides
        let cx = size.width  / 2
        let cy = size.height / 2
        let gScale = min(size.width, size.height) * gScaleMultiplier

        var cross = Path()
        cross.move(to: CGPoint(x: cx - 6, y: cy)); cross.addLine(to: CGPoint(x: cx + 6, y: cy))
        cross.move(to: CGPoint(x: cx, y: cy - 6)); cross.addLine(to: CGPoint(x: cx, y: cy + 6))
        ctx.stroke(cross, with: .color(.white.opacity(0.07)), lineWidth: 0.5)

        // Reference lines
        if showRefLines {
            let refLines = controller.projectConfig?.cycles[safe: cycleIdx]?.referenceLines ?? []
            for line in refLines {
                let pos = CGFloat(line.position)
                var lp = Path()
                let labelPt: CGPoint
                switch line.axis {
                case .horizontal:
                    let sy = cy - pos * gScale
                    lp.move(to: CGPoint(x: 0, y: sy))
                    lp.addLine(to: CGPoint(x: size.width, y: sy))
                    labelPt = CGPoint(x: 4, y: sy - 12)
                case .vertical:
                    let sx = cx + pos * gScale
                    lp.move(to: CGPoint(x: sx, y: 0))
                    lp.addLine(to: CGPoint(x: sx, y: size.height))
                    labelPt = CGPoint(x: sx + 3, y: 4)
                }
                ctx.stroke(lp, with: .color(Color.yellow.opacity(0.40)),
                           style: StrokeStyle(lineWidth: 1.0, dash: [6, 4]))
                if !line.label.isEmpty {
                    ctx.draw(Text(line.label)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.yellow.opacity(0.60)),
                        at: labelPt, anchor: .topLeading)
                }
            }
        }

        let roles = controller.projectConfig?.cycles[safe: cycleIdx]?.spriteLayerRoles ?? [:]

        for sp in sprites {
            guard let polys = spritePolygons[sp.name] else { continue }
            let isSelected  = sp.name == selectedSpriteName
            let hasPoseOver = overrides[sp.name] != nil
            let role        = roles[sp.name]
            let color: Color = isSelected ? .orange
                : role == .back  ? Color(red: 0.40, green: 0.65, blue: 1.0)
                : role == .front ? Color(red: 0.35, green: 0.88, blue: 0.52)
                : hasPoseOver    ? Color(red: 0.35, green: 0.88, blue: 0.52)
                : .white
            let alpha: Double = isSelected ? 0.90 : (hasPoseOver || role != nil) ? 0.72 : 0.28
            let lw: CGFloat   = isSelected ? 1.4  : 0.85

            // Position override in /200 geometry space (matches pivot convention)
            let posOvr = overrides[sp.name]?.position ?? sp.position
            let posOffX = posOvr.x / 200.0
            let posOffY = posOvr.y / 200.0

            for poly in polys where poly.visible {
                guard !poly.points.isEmpty else { continue }
                let pts = poly.points.map { p -> CGPoint in
                    var wpt = transformPoint(CGPoint(x: p.x, y: p.y),
                                             sprite: sp, sprites: sprites, overrides: overrides)
                    wpt.x += posOffX
                    wpt.y += posOffY
                    return CGPoint(x: cx + wpt.x * gScale, y: cy - wpt.y * gScale)
                }
                ctx.stroke(buildPath(pts, type: poly.type),
                           with: .color(color.opacity(alpha)), lineWidth: lw)
            }
        }

        // Pivot dots + rotation ring for each sprite
        for sp in sprites {
            let isSelected  = sp.name == selectedSpriteName
            let hasPoseOver = overrides[sp.name] != nil
            let role        = roles[sp.name]
            let color: Color = isSelected ? .orange
                : role == .back  ? Color(red: 0.40, green: 0.65, blue: 1.0)
                : role == .front ? Color(red: 0.35, green: 0.88, blue: 0.52)
                : hasPoseOver    ? Color(red: 0.35, green: 0.88, blue: 0.52)
                : .white

            var wPiv = worldPivot(sp, sprites: sprites, overrides: overrides)
            let posOvr = overrides[sp.name]?.position ?? sp.position
            wPiv.x += posOvr.x / 200.0
            wPiv.y += posOvr.y / 200.0
            let pivScreen = CGPoint(x: cx + wPiv.x * gScale, y: cy - wPiv.y * gScale)

            let pr: CGFloat = isSelected ? 5.5 : 3.5
            ctx.fill(Path(ellipseIn: CGRect(x: pivScreen.x - pr, y: pivScreen.y - pr,
                                            width: pr * 2, height: pr * 2)),
                     with: .color(color.opacity(isSelected ? 1.0 : 0.65)))

            if isSelected {
                let ring = Path(ellipseIn: CGRect(x: pivScreen.x - ringRadius,
                                                   y: pivScreen.y - ringRadius,
                                                   width: ringRadius * 2,
                                                   height: ringRadius * 2))
                ctx.stroke(ring, with: .color(Color.orange.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))

                let localRot = overrides[sp.name]?.rotation ?? sp.rotation
                let handleRad = CGFloat(localRot * .pi / 180.0)
                let handlePt  = CGPoint(x: pivScreen.x + ringRadius * cos(handleRad),
                                        y: pivScreen.y - ringRadius * sin(handleRad))
                ctx.fill(Path(ellipseIn: CGRect(x: handlePt.x - 5.5, y: handlePt.y - 5.5,
                                                width: 11, height: 11)),
                         with: .color(.orange))

                var zeroLine = Path()
                zeroLine.move(to: pivScreen)
                zeroLine.addLine(to: CGPoint(x: pivScreen.x + ringRadius * 0.7, y: pivScreen.y))
                ctx.stroke(zeroLine, with: .color(.orange.opacity(0.25)), lineWidth: 0.7)

                // Translation handle: small diamond at pivot centre
                let d: CGFloat = 5
                var diamond = Path()
                diamond.move(to:    CGPoint(x: pivScreen.x,     y: pivScreen.y - d))
                diamond.addLine(to: CGPoint(x: pivScreen.x + d, y: pivScreen.y))
                diamond.addLine(to: CGPoint(x: pivScreen.x,     y: pivScreen.y + d))
                diamond.addLine(to: CGPoint(x: pivScreen.x - d, y: pivScreen.y))
                diamond.closeSubpath()
                ctx.fill(diamond, with: .color(Color.cyan.opacity(0.85)))
            }
        }

        if sprites.isEmpty {
            ctx.draw(Text("No sprites in project")
                .font(.system(size: 11)).foregroundStyle(Color.secondary),
                at: CGPoint(x: cx, y: cy), anchor: .center)
        } else if selectedStateIndex == nil {
            ctx.draw(Text("Select a state to pose")
                .font(.system(size: 10)).foregroundStyle(Color.secondary.opacity(0.5)),
                at: CGPoint(x: cx, y: cy - size.height * 0.4), anchor: .center)
        }
    }

    // MARK: - Interaction

    private func onDragChange(_ v: DragGesture.Value, size: CGSize) {
        let loc = v.location
        let cx  = size.width  / 2
        let cy  = size.height / 2
        let gScale   = min(size.width, size.height) * gScaleMultiplier
        let sprites  = allSprites
        let overrides = currentOverrides

        if dragMode == .none {
            // Check interactions on the already-selected sprite first
            if let selName = selectedSpriteName,
               let selSp = sprites.first(where: { $0.name == selName }) {
                var wPiv = worldPivot(selSp, sprites: sprites, overrides: overrides)
                let posOvr = overrides[selName]?.position ?? selSp.position
                wPiv.x += posOvr.x / 200.0
                wPiv.y += posOvr.y / 200.0
                let piv  = CGPoint(x: cx + wPiv.x * gScale, y: cy - wPiv.y * gScale)
                let dist = hypot(loc.x - piv.x, loc.y - piv.y)

                if dist < centerHitRadius {
                    beginTranslation(name: selName, sprite: selSp, loc: loc, overrides: overrides)
                    return
                }
                if abs(dist - ringRadius) < ringHitWidth {
                    beginRotation(name: selName, sprite: selSp, pivScreen: piv,
                                  loc: loc, overrides: overrides)
                    return
                }
            }

            // Hit-test all pivot dots to select a new sprite
            var bestDist = pivotHitRadius
            var bestName: String? = nil
            for sp in sprites {
                var wPiv = worldPivot(sp, sprites: sprites, overrides: overrides)
                let posOvr = overrides[sp.name]?.position ?? sp.position
                wPiv.x += posOvr.x / 200.0; wPiv.y += posOvr.y / 200.0
                let piv = CGPoint(x: cx + wPiv.x * gScale, y: cy - wPiv.y * gScale)
                let d   = hypot(loc.x - piv.x, loc.y - piv.y)
                if d < bestDist { bestDist = d; bestName = sp.name }
            }
            if let name = bestName, let sp = sprites.first(where: { $0.name == name }) {
                selectedSpriteName = name
                var wPiv = worldPivot(sp, sprites: sprites, overrides: overrides)
                let posOvr = overrides[name]?.position ?? sp.position
                wPiv.x += posOvr.x / 200.0; wPiv.y += posOvr.y / 200.0
                let piv  = CGPoint(x: cx + wPiv.x * gScale, y: cy - wPiv.y * gScale)
                let dist = hypot(loc.x - piv.x, loc.y - piv.y)
                if dist < centerHitRadius {
                    beginTranslation(name: name, sprite: sp, loc: loc, overrides: overrides)
                } else if abs(dist - ringRadius) < ringHitWidth {
                    beginRotation(name: name, sprite: sp, pivScreen: piv,
                                  loc: loc, overrides: overrides)
                }
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

        } else if dragMode == .translating {
            guard let selName = selectedSpriteName,
                  let si = selectedStateIndex else { return }
            let screenDx = loc.x - dragStartScreenLoc.x
            let screenDy = loc.y - dragStartScreenLoc.y
            // /200.0 factor: 1 world unit = gScale/200 screen pixels (matches pivot convention)
            let worldDx =  screenDx / gScale * 200.0
            let worldDy = -screenDy / gScale * 200.0
            let newPosX = dragStartWorldPos.x + worldDx
            let newPosY = dragStartWorldPos.y + worldDy
            controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(si) else { return }
                if cfg.cycles[cycleIdx].states[si].poseOverrides[selName] != nil {
                    cfg.cycles[cycleIdx].states[si].poseOverrides[selName]!.position.x = newPosX
                    cfg.cycles[cycleIdx].states[si].poseOverrides[selName]!.position.y = newPosY
                }
            }
        }
    }

    private func beginRotation(name: String, sprite: SpriteDef, pivScreen: CGPoint,
                                loc: CGPoint, overrides: [String: SpritePoseOverride]) {
        guard let si = selectedStateIndex else { return }
        ensurePoseOverride(name: name, sprite: sprite, stateIdx: si)
        dragMode         = .rotating
        dragPivotScreen  = pivScreen
        dragStartAngle   = atan2(-(loc.y - pivScreen.y), loc.x - pivScreen.x) * 180.0 / .pi
        dragStartRotation = overrides[name]?.rotation ?? sprite.rotation
    }

    private func beginTranslation(name: String, sprite: SpriteDef,
                                   loc: CGPoint, overrides: [String: SpritePoseOverride]) {
        guard let si = selectedStateIndex else { return }
        ensurePoseOverride(name: name, sprite: sprite, stateIdx: si)
        dragMode          = .translating
        dragStartScreenLoc = loc
        let posOvr = overrides[name]?.position ?? sprite.position
        dragStartWorldPos = CGPoint(x: posOvr.x, y: posOvr.y)
    }

    // MARK: - Geometry helpers

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

    private func buildChain(_ sprite: SpriteDef, sprites: [SpriteDef]) -> [SpriteDef] {
        var chain: [SpriteDef] = []
        var cur: SpriteDef? = sprite
        while let s = cur {
            chain.insert(s, at: 0)
            cur = s.parentName.flatMap { n in sprites.first { $0.name == n } }
        }
        return chain
    }

    private func buildWorldPivots(chain: [SpriteDef],
                                   overrides: [String: SpritePoseOverride]) -> [CGPoint] {
        var wPivots = [CGPoint]()
        var rots    = [Double]()
        for sp in chain {
            // /200.0: pivot is in the 2x-scaled geometry space set by SpriteWireframeView
            let restPiv = CGPoint(x: sp.pivotOffset.x / 200.0, y: sp.pivotOffset.y / 200.0)
            let wp = applyChain(restPiv, worldPivots: wPivots, rotations: rots)
            wPivots.append(wp)
            rots.append(overrides[sp.name]?.rotation ?? sp.rotation)
        }
        return wPivots
    }

    private func worldPivot(_ sp: SpriteDef, sprites: [SpriteDef],
                             overrides: [String: SpritePoseOverride]) -> CGPoint {
        let chain = buildChain(sp, sprites: sprites)
        var wPivots = [CGPoint]()
        var rots    = [Double]()
        for anc in chain.dropLast() {
            let restPiv = CGPoint(x: anc.pivotOffset.x / 200.0, y: anc.pivotOffset.y / 200.0)
            let wp = applyChain(restPiv, worldPivots: wPivots, rotations: rots)
            wPivots.append(wp)
            rots.append(overrides[anc.name]?.rotation ?? anc.rotation)
        }
        let spRestPiv = CGPoint(x: sp.pivotOffset.x / 200.0, y: sp.pivotOffset.y / 200.0)
        return applyChain(spRestPiv, worldPivots: wPivots, rotations: rots)
    }

    private func transformPoint(_ p: CGPoint, sprite: SpriteDef, sprites: [SpriteDef],
                                 overrides: [String: SpritePoseOverride]) -> CGPoint {
        let chain   = buildChain(sprite, sprites: sprites)
        let wPivots = buildWorldPivots(chain: chain, overrides: overrides)
        let rots    = chain.map { overrides[$0.name]?.rotation ?? $0.rotation }
        return applyChain(p, worldPivots: wPivots, rotations: rots)
    }

    // MARK: - Path builder

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

    // MARK: - Data access

    private var allSprites: [SpriteDef] {
        controller.projectConfig?.spriteConfig.library.spriteSets.flatMap { $0.sprites } ?? []
    }

    private var currentOverrides: [String: SpritePoseOverride] {
        guard let si = selectedStateIndex else { return [:] }
        return controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: si]?.poseOverrides ?? [:]
    }

    private func setLayerRole(_ role: SpriteLayerRole, forSprite name: String) {
        controller.updateProjectConfig { cfg in
            guard cfg.cycles.indices.contains(cycleIdx) else { return }
            cfg.cycles[cycleIdx].spriteLayerRoles[name] = role
        }
    }

    private func clearLayerRole(forSprite name: String) {
        controller.updateProjectConfig { cfg in
            guard cfg.cycles.indices.contains(cycleIdx) else { return }
            cfg.cycles[cycleIdx].spriteLayerRoles.removeValue(forKey: name)
        }
    }

    private func ensurePoseOverride(name: String, sprite: SpriteDef, stateIdx: Int) {
        guard controller.projectConfig?.cycles[safe: cycleIdx]?
                .states[safe: stateIdx]?.poseOverrides[name] == nil else { return }
        let init_ = SpritePoseOverride(position: sprite.position,
                                       rotation: sprite.rotation,
                                       scale:    sprite.scale)
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
