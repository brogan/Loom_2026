import SwiftUI
import LoomEngine

struct SpriteWireframeView: View {

    var parallaxMode: Bool = false

    @EnvironmentObject private var controller: AppController

    // MARK: - Drag state

    @State private var activeDragHandle: HandleID?   = nil
    @State private var dragStartPos:     CGPoint     = .zero
    @State private var dragStartDef:     SpriteDef?  = nil
    @State private var liveTransform:    LiveTransform? = nil
    @State private var capturedViewSize: CGSize      = .zero

    // MARK: - Canvas controls

    @State private var gridSizePct:           Double = 10.0
    @State private var snapToGrid:            Bool   = false
    @State private var selectedKeyframeIndex: Int    = 0    // 0 = base params, 1..N = KF
    @State private var editKeyframe:          Bool   = true
    @State private var zoomLevel:             Double = 1.0  // 1.0 = 100 %
    @State private var parallaxCameraX:       Double = 0.0  // position units (% of canvas half)
    @State private var parallaxCameraY:       Double = 0.0
    @State private var parallaxZoom:          Double = 1.0  // multiplier, same as camera zoom driver

    private static let zoomSteps: [Double] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Canvas { ctx, size in
                    let cRect = canvasRect(viewSize: size)
                    guard cRect.width > 0, cRect.height > 0 else { return }
                    // Render area background (dark blue-grey) — black shows outside
                    ctx.fill(Path(cRect), with: .color(Color(red: 0.08, green: 0.08, blue: 0.12)))
                    drawGrid(ctx: ctx, rect: cRect)
                    drawSprites(ctx: ctx, rect: cRect)
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard activeDragHandle == nil else { return }
                    selectSprite(at: location, viewSize: geo.size)
                }
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            if activeDragHandle == nil {
                                capturedViewSize = geo.size
                                beginDrag(at: value.startLocation, viewSize: geo.size)
                            }
                            guard activeDragHandle != nil else { return }
                            updateDrag(to: value.location, viewSize: capturedViewSize)
                        }
                        .onEnded { _ in commitDrag() }
                )
            }
            .background(Color.black)

            Divider()
            controlStrip
        }
        .onChange(of: controller.selectedSpriteID) { _, _ in
            selectedKeyframeIndex = 0
        }
        .onChange(of: controller.selectedTimelineKF) { _, kf in
            guard let kf,
                  kf.lane == .position || kf.lane == .scale || kf.lane == .rotation,
                  let cfg = controller.projectConfig,
                  kf.setIdx < cfg.spriteConfig.library.spriteSets.count,
                  kf.spriteIdx < cfg.spriteConfig.library.spriteSets[kf.setIdx].sprites.count
            else { return }
            let name = cfg.spriteConfig.library.spriteSets[kf.setIdx].sprites[kf.spriteIdx].name
            controller.selectedSpriteID = name
            selectedKeyframeIndex = 0
        }
    }

    // MARK: - Control strip

    private var controlStrip: some View {
        HStack(spacing: 10) {
            Text("Grid:")
                .font(.system(size: 11))
                .foregroundStyle(controlTextSecondary)
            Picker("", selection: $gridSizePct) {
                Text("5%").tag(5.0)
                Text("10%").tag(10.0)
                Text("25%").tag(25.0)
                Text("50%").tag(50.0)
            }
            .labelsHidden()
            .frame(width: 68)
            .pickerStyle(.menu)

            Toggle("Snap", isOn: $snapToGrid)
                .font(.system(size: 11))
                .toggleStyle(.checkbox)

            if keyframeEnabled {
                Divider().frame(height: 16)

                Text("KF:")
                    .font(.system(size: 11))
                    .foregroundStyle(controlTextSecondary)

                Picker("", selection: $selectedKeyframeIndex) {
                    Text("—").tag(0)
                    let kfs = sortedKeyframes
                    ForEach(kfs.indices, id: \.self) { i in
                        Text("\(i + 1)").tag(i + 1)
                    }
                }
                .labelsHidden()
                .frame(width: 58)
                .pickerStyle(.menu)

                Toggle("Edit KF", isOn: $editKeyframe)
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)
                    .disabled(selectedKeyframeIndex == 0)
            }

            Spacer()

            zoomControls

            if parallaxMode {
                Divider().frame(height: 16)

                cameraSlider("Pan X", value: $parallaxCameraX, range: -100...100,
                             format: "%.0f")
                cameraSlider("Pan Y", value: $parallaxCameraY, range: -100...100,
                             format: "%.0f")
                cameraSlider("Zoom",  value: $parallaxZoom,    range: 0.25...4.0,
                             format: "%.2f×")

                let isNeutral = abs(parallaxCameraX) < 0.5 &&
                                abs(parallaxCameraY) < 0.5 &&
                                abs(parallaxZoom - 1.0) < 0.01
                Button {
                    parallaxCameraX = 0; parallaxCameraY = 0; parallaxZoom = 1.0
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 11))
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isNeutral ? controlTextDisabled : controlTextPrimary)
                .disabled(isNeutral)
                .help("Reset camera to neutral")
            }

            if let tkf = activeTimelineKF {
                Text("Timeline KF · \(tkf.lane.label)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.45, green: 0.3, blue: 0.0).opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if !transformText.isEmpty {
                Text(transformText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(red: 0.0, green: 0.87, blue: 0.0))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(white: 0.11))
        .colorScheme(.dark)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Divider().frame(height: 16)

            zoomButton("-", tooltip: "Zoom out", disabled: isMinZoom) {
                if let prev = Self.zoomSteps.last(where: { $0 < zoomLevel - 1e-9 }) {
                    zoomLevel = prev
                }
            }

            Button { zoomLevel = 1.0 } label: {
                Text("\(Int((zoomLevel * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 42, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isDefaultZoom ? controlTextSecondary : controlTextPrimary)
            .contentShape(Rectangle())
            .help("Reset to 100%")

            zoomButton("+", tooltip: "Zoom in", disabled: isMaxZoom) {
                if let next = Self.zoomSteps.first(where: { $0 > zoomLevel + 1e-9 }) {
                    zoomLevel = next
                }
            }
        }
    }

    private var isDefaultZoom: Bool { abs(zoomLevel - 1.0) < 1e-9 }
    private var isMinZoom: Bool { zoomLevel <= Self.zoomSteps.first! + 1e-9 }
    private var isMaxZoom: Bool { zoomLevel >= Self.zoomSteps.last! - 1e-9 }
    private var controlTextPrimary: Color { Color(white: 0.92) }
    private var controlTextSecondary: Color { Color(white: 0.68) }
    private var controlTextDisabled: Color { Color(white: 0.42) }

    private func zoomButton(
        _ title: String,
        tooltip: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? controlTextDisabled : controlTextPrimary)
        .contentShape(Rectangle())
        .disabled(disabled)
        .help(tooltip)
    }

    private func cameraSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(controlTextSecondary)
                .frame(width: 38, alignment: .trailing)
            Slider(value: value, in: range)
                .frame(width: 80)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(controlTextPrimary)
                .frame(width: 38, alignment: .leading)
        }
    }

    // MARK: - Types

    enum HandleID: Equatable {
        case tl, t, tr, l, r, bl, b, br, interior
        var isRotate: Bool { self == .tr || self == .bl }
    }

    struct LiveTransform {
        var posX, posY, scaleX, scaleY, rotation: Double
        init(_ d: SpriteDef) {
            posX = d.position.x; posY = d.position.y
            scaleX = d.scale.x;  scaleY = d.scale.y
            rotation = d.rotation
        }
    }

    // MARK: - Keyframe helpers

    private var keyframeEnabled: Bool {
        guard let id = controller.selectedSpriteID,
              let sprite = controller.projectConfig?.spriteConfig.library.allSprites
                  .first(where: { $0.name == id })
        else { return false }
        let t = sprite.animation.type
        return (t == .keyframe || t == .keyframeMorph) && !sprite.animation.keyframes.isEmpty
    }

    private var sortedKeyframes: [Keyframe] {
        guard let id = controller.selectedSpriteID,
              let sprite = controller.projectConfig?.spriteConfig.library.allSprites
                  .first(where: { $0.name == id })
        else { return [] }
        return sprite.animation.keyframes.sorted { $0.drawCycle < $1.drawCycle }
    }

    // MARK: - Transform text

    private var transformText: String {
        guard let id = controller.selectedSpriteID,
              let sprite = controller.projectConfig?.spriteConfig.library.allSprites
                  .first(where: { $0.name == id })
        else { return "" }
        let eff = resolvedDef(sprite)
        return String(format: "p %.1f, %.1f  s %.3g, %.3g  r %.1f°",
                      eff.position.x, eff.position.y,
                      eff.scale.x, eff.scale.y,
                      eff.rotation)
    }

    // MARK: - Canvas rect (letterboxed to canvas aspect ratio, scaled by zoom)

    private func canvasRect(viewSize: CGSize) -> CGRect {
        let cSize   = controller.engineCanvasSize
        guard viewSize.width.isFinite, viewSize.height.isFinite,
              cSize.width.isFinite, cSize.height.isFinite,
              viewSize.width > 0, viewSize.height > 0,
              cSize.width > 0, cSize.height > 0,
              zoomLevel.isFinite, zoomLevel > 0
        else { return .zero }

        let cAspect = cSize.width / cSize.height
        let vAspect = viewSize.width / viewSize.height

        // 100% letterboxed rect
        let base: CGRect
        if cAspect > vAspect {
            let h = viewSize.width / cAspect
            base = CGRect(x: 0, y: (viewSize.height - h) / 2, width: viewSize.width, height: h)
        } else {
            let w = viewSize.height * cAspect
            base = CGRect(x: (viewSize.width - w) / 2, y: 0, width: w, height: viewSize.height)
        }

        // Scale around the centre of the 100% rect
        let zw = base.width  * zoomLevel
        let zh = base.height * zoomLevel
        return CGRect(x: base.midX - zw / 2, y: base.midY - zh / 2, width: zw, height: zh)
    }

    // MARK: - Coordinate conversions

    private func screenToWorld(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: (p.x - rect.minX) / rect.width  * 2.0 - 1.0,
            y: 1.0 - (p.y - rect.minY) / rect.height * 2.0
        )
    }

    private func positionToScreen(_ pos: Vector2D, rect: CGRect) -> CGPoint {
        let normX = pos.x / 100.0
        let normY = pos.y / 100.0
        return CGPoint(
            x: rect.minX + (normX + 1.0) / 2.0 * rect.width,
            y: rect.minY + (1.0 - normY) / 2.0 * rect.height
        )
    }

    private func geometryBasis(_ rect: CGRect) -> CGFloat {
        min(rect.width, rect.height) / 2.0
    }

    // MARK: - Grid

    private func drawGrid(ctx: GraphicsContext, rect: CGRect) {
        let gridWorld = gridSizePct / 200.0  // fraction of normalised [-1, 1] space
        guard gridWorld > 1e-9 else { return }
        let faint = Color(white: 0.22)
        let axis  = Color(white: 0.32)
        let n = Int(ceil(1.0 / gridWorld)) + 1
        for step in -n...n {
            let t = Double(step) * gridWorld
            if t < -1.0 - 1e-9 || t > 1.0 + 1e-9 { continue }
            let isCentre = step == 0
            let clr = isCentre ? axis : faint
            let lw: CGFloat = isCentre ? 0.8 : 0.4
            let sx = rect.minX + (t + 1.0) / 2.0 * rect.width
            let sy = rect.minY + (1.0 - t) / 2.0 * rect.height
            var v = Path(); v.move(to: CGPoint(x: sx, y: rect.minY)); v.addLine(to: CGPoint(x: sx, y: rect.maxY))
            var h = Path(); h.move(to: CGPoint(x: rect.minX, y: sy)); h.addLine(to: CGPoint(x: rect.maxX, y: sy))
            ctx.stroke(v, with: .color(clr), lineWidth: lw)
            ctx.stroke(h, with: .color(clr), lineWidth: lw)
        }
    }

    // MARK: - Sprite drawing

    private func drawSprites(ctx: GraphicsContext, rect: CGRect) {
        guard let cfg = controller.projectConfig else { return }
        let sprites     = cfg.spriteConfig.library.allSprites
        let instanceMap = makeInstanceMap()
        let liveOffsets = computeLiveChildOffsets(sprites: sprites)
        let wireWorlds  = buildWireWorlds(sprites: sprites, liveOffsets: liveOffsets)

        for sprite in sprites {
            let isSelected = controller.selectedSpriteID == sprite.name
            guard let world = wireWorlds[sprite.name] else { continue }

            let strokeColor: Color = isSelected
                ? Color(red: 0.31, green: 0.78, blue: 0.47)
                : Color(white: 0.45)
            let lineWidth: CGFloat = isSelected ? 1.5 : 0.75

            if let instance = instanceMap[sprite.name] {
                for polygon in instance.basePolygons where polygon.visible {
                    let pts = polygon.points.map {
                        transformPointWithWorld($0, world: world, depth: sprite.depth, rect: rect)
                    }
                    ctx.stroke(buildPath(pts, type: polygon.type), with: .color(strokeColor), lineWidth: lineWidth)
                }
                if isSelected {
                    let allPts = instance.basePolygons.flatMap { $0.points }
                        .map { transformPointWithWorld($0, world: world, depth: sprite.depth, rect: rect) }
                    if !allPts.isEmpty {
                        drawBBoxAndHandles(ctx: ctx, screenPoints: allPts)
                    }
                }
            } else {
                // Placeholder cross for sprites with no engine instance
                let centre = parallaxAdjustedScreen(Vector2D(x: world.posX, y: world.posY),
                                                    depth: sprite.depth, rect: rect)
                drawPlaceholder(ctx: ctx, centre: centre, color: strokeColor)
                if isSelected {
                    let pad: CGFloat = 12
                    drawBBoxAndHandles(ctx: ctx, screenPoints: [
                        CGPoint(x: centre.x - pad, y: centre.y - pad),
                        CGPoint(x: centre.x + pad, y: centre.y - pad),
                        CGPoint(x: centre.x + pad, y: centre.y + pad),
                        CGPoint(x: centre.x - pad, y: centre.y + pad)
                    ])
                }
            }
        }
    }

    // Compute position deltas that children should apply during a live drag of their parent.
    private func computeLiveChildOffsets(sprites: [SpriteDef]) -> [String: Vector2D] {
        guard activeDragHandle != nil,
              let draggedID = controller.selectedSpriteID,
              let live = liveTransform,
              let draggedSprite = sprites.first(where: { $0.name == draggedID })
        else { return [:] }
        let dx = live.posX - draggedSprite.position.x
        let dy = live.posY - draggedSprite.position.y
        guard dx != 0 || dy != 0 else { return [:] }
        var offsets: [String: Vector2D] = [:]
        collectChildOffsets(parentName: draggedID, dx: dx, dy: dy, sprites: sprites, offsets: &offsets)
        return offsets
    }

    private func collectChildOffsets(parentName: String, dx: Double, dy: Double,
                                     sprites: [SpriteDef], offsets: inout [String: Vector2D]) {
        for sprite in sprites where sprite.parentName == parentName {
            if sprite.inheritMask.position {
                let cur = offsets[sprite.name] ?? .zero
                offsets[sprite.name] = Vector2D(x: cur.x + dx, y: cur.y + dy)
            }
            collectChildOffsets(parentName: sprite.name, dx: dx, dy: dy, sprites: sprites, offsets: &offsets)
        }
    }

    private func drawPlaceholder(ctx: GraphicsContext, centre: CGPoint, color: Color) {
        let s: CGFloat = 9
        var p = Path()
        p.move(to: CGPoint(x: centre.x - s, y: centre.y))
        p.addLine(to: CGPoint(x: centre.x + s, y: centre.y))
        p.move(to: CGPoint(x: centre.x, y: centre.y - s))
        p.addLine(to: CGPoint(x: centre.x, y: centre.y + s))
        ctx.stroke(p, with: .color(color), lineWidth: 1.3)
    }

    // MARK: - Bounding box + 8 handles

    private func drawBBoxAndHandles(ctx: GraphicsContext, screenPoints: [CGPoint]) {
        guard let bb = bbox(screenPoints) else { return }
        let pad: CGFloat = 5
        let box = CGRect(x: bb.minX - pad, y: bb.minY - pad,
                         width: bb.maxX - bb.minX + pad * 2,
                         height: bb.maxY - bb.minY + pad * 2)

        ctx.stroke(Path(box),
                   with: .color(Color(white: 0.78).opacity(0.85)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

        let hs: CGFloat = 8, half: CGFloat = 4
        for (id, pos) in handlePositions(for: box) {
            let fill: Color = id.isRotate ? Color(red: 1.0, green: 0.86, blue: 0.0) : .white
            let hr = CGRect(x: pos.x - half, y: pos.y - half, width: hs, height: hs)
            ctx.fill(Path(hr), with: .color(fill))
            ctx.stroke(Path(hr), with: .color(Color(white: 0.55)), lineWidth: 0.7)
        }
    }

    private func handlePositions(for box: CGRect) -> [(HandleID, CGPoint)] {
        let cx = box.midX, cy = box.midY
        return [
            (.tl, CGPoint(x: box.minX, y: box.minY)),
            (.t,  CGPoint(x: cx,       y: box.minY)),
            (.tr, CGPoint(x: box.maxX, y: box.minY)),
            (.l,  CGPoint(x: box.minX, y: cy)),
            (.r,  CGPoint(x: box.maxX, y: cy)),
            (.bl, CGPoint(x: box.minX, y: box.maxY)),
            (.b,  CGPoint(x: cx,       y: box.maxY)),
            (.br, CGPoint(x: box.maxX, y: box.maxY)),
        ]
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
            for pt in pts { p.addEllipse(in: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)) }
        case .oval:
            if pts.count >= 2 {
                let cx = pts[0].x, cy = pts[0].y
                let rx = abs(pts[1].x - cx), ry = abs(pts[1].y - cy)
                p.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            }
        default:
            guard pts.count >= 2 else { return p }
            p.move(to: pts[0])
            pts.dropFirst().forEach { p.addLine(to: $0) }
            p.closeSubpath()
        }
        return p
    }

    // MARK: - Coordinate transform (polygon point → screen)

    /// Depth factor for a sprite: f = 1/(1 + depth×strength). Returns 1 outside parallax mode.
    private func parallaxDepthFactor(for depth: Double) -> Double {
        guard parallaxMode else { return 1.0 }
        let strength = controller.projectConfig?.globalConfig.camera.perspectiveStrength ?? 0
        guard strength > 0 else { return 1.0 }
        return 1.0 / (1.0 + depth * strength)
    }

    /// Position → screen applying zoom, pan X/Y, and depth factor when in parallax mode.
    /// Formula mirrors the engine: visual = (worldPos × zoom + pan) × f(depth).
    private func parallaxAdjustedScreen(_ pos: Vector2D, depth: Double, rect: CGRect) -> CGPoint {
        if parallaxMode {
            let f = parallaxDepthFactor(for: depth)
            let adjX = (pos.x * parallaxZoom + parallaxCameraX) * f
            let adjY = (pos.y * parallaxZoom + parallaxCameraY) * f
            return CGPoint(
                x: rect.minX + (adjX / 100.0 + 1.0) / 2.0 * rect.width,
                y: rect.minY + (1.0 - adjY / 100.0) / 2.0 * rect.height
            )
        }
        return positionToScreen(pos, rect: rect)
    }

    private func transformPoint(_ pt: Vector2D, def: SpriteDef, rect: CGRect) -> CGPoint {
        // In parallax mode, sprite size also scales with zoom × f so far sprites appear smaller.
        let scaleBoost = parallaxMode ? parallaxZoom * parallaxDepthFactor(for: def.depth) : 1.0
        let sx = def.scale.x * 2.0 * scaleBoost
        let sy = def.scale.y * 2.0 * scaleBoost
        let rotRad = def.rotation * .pi / 180.0
        let cosR = cos(rotRad), sinR = sin(rotRad)
        var wx = pt.x * sx, wy = pt.y * sy
        if rotRad != 0 {
            let rx = wx * cosR - wy * sinR
            let ry = wx * sinR + wy * cosR
            wx = rx; wy = ry
        }
        let centre = parallaxAdjustedScreen(def.position, depth: def.depth, rect: rect)
        let basis = geometryBasis(rect)
        return CGPoint(
            x: centre.x + CGFloat(wx) * basis,
            y: centre.y - CGFloat(wy) * basis
        )
    }

    // MARK: - Wireframe parent-world hierarchy

    /// Resolved world transform for one sprite in wireframe space (percent units).
    /// Mirrors the engine's ParentWorld / computeParentWorld, but operates in
    /// percent-unit position space rather than pixel space.
    private struct WireWorld {
        var posX, posY:         Double  // animated world position (percent units)
        var basePosX, basePosY: Double  // base world position (no animation)
        var rotDeg:             Double  // animated world rotation (degrees)
        var baseRotDeg:         Double
        var scaleX, scaleY:     Double  // combined world scale (without ×2)
    }

    /// Build WireWorld for every sprite in declaration order so children can
    /// look up their parent's already-resolved world.
    private func buildWireWorlds(sprites: [SpriteDef],
                                 liveOffsets: [String: Vector2D]) -> [String: WireWorld] {
        var worlds: [String: WireWorld] = [:]
        for sprite in sprites {
            var eff = resolvedDef(sprite)
            if let off = liveOffsets[sprite.name] {
                eff.position.x += off.x
                eff.position.y += off.y
            }
            let parent = sprite.parentName.flatMap { worlds[$0] }
            worlds[sprite.name] = computeWireWorld(raw: sprite, eff: eff, parent: parent)
        }
        return worlds
    }

    private func computeWireWorld(raw: SpriteDef, eff: SpriteDef,
                                  parent: WireWorld?) -> WireWorld {
        var posX     = eff.position.x
        var posY     = eff.position.y
        var basePosX = raw.position.x
        var basePosY = raw.position.y
        var rotDeg   = eff.rotation
        var baseRotDeg = raw.rotation
        var scaleX   = eff.scale.x
        var scaleY   = eff.scale.y

        if let p = parent {
            let mask = raw.inheritMask
            if mask.scale {
                scaleX *= p.scaleX
                scaleY *= p.scaleY
            }
            if mask.rotation {
                rotDeg    += p.rotDeg
                baseRotDeg += p.baseRotDeg
            }
            if mask.position {
                let rad  = p.rotDeg * .pi / 180.0
                let cosR = cos(rad), sinR = sin(rad)
                var relX = posX - p.basePosX
                var relY = posY - p.basePosY
                if mask.scale {
                    relX *= p.scaleX
                    relY *= p.scaleY
                }
                posX = p.posX + relX * cosR - relY * sinR
                posY = p.posY + relX * sinR + relY * cosR

                let baseRad = p.baseRotDeg * .pi / 180.0
                let cosB = cos(baseRad), sinB = sin(baseRad)
                var relBaseX = basePosX - p.basePosX
                var relBaseY = basePosY - p.basePosY
                if mask.scale {
                    relBaseX *= p.scaleX
                    relBaseY *= p.scaleY
                }
                basePosX = p.basePosX + relBaseX * cosB - relBaseY * sinB
                basePosY = p.basePosY + relBaseX * sinB + relBaseY * cosB
            }
        }

        return WireWorld(posX: posX, posY: posY,
                         basePosX: basePosX, basePosY: basePosY,
                         rotDeg: rotDeg, baseRotDeg: baseRotDeg,
                         scaleX: scaleX, scaleY: scaleY)
    }

    private func transformPointWithWorld(_ pt: Vector2D, world: WireWorld,
                                         depth: Double, rect: CGRect) -> CGPoint {
        let scaleBoost = parallaxMode ? parallaxZoom * parallaxDepthFactor(for: depth) : 1.0
        let sx = world.scaleX * 2.0 * scaleBoost
        let sy = world.scaleY * 2.0 * scaleBoost
        let rotRad = world.rotDeg * .pi / 180.0
        let cosR = cos(rotRad), sinR = sin(rotRad)
        var wx = pt.x * sx, wy = pt.y * sy
        if rotRad != 0 {
            let rx = wx * cosR - wy * sinR
            let ry = wx * sinR + wy * cosR
            wx = rx; wy = ry
        }
        let centre = parallaxAdjustedScreen(Vector2D(x: world.posX, y: world.posY),
                                            depth: depth, rect: rect)
        let basis = geometryBasis(rect)
        return CGPoint(
            x: centre.x + CGFloat(wx) * basis,
            y: centre.y - CGFloat(wy) * basis
        )
    }

    // MARK: - Active timeline KF (driver-based)

    /// Non-nil when the timeline has a position/scale/rotation KF selected for the current sprite.
    private var activeTimelineKF: TimelineKFSelection? {
        guard let kf = controller.selectedTimelineKF,
              kf.lane == .position || kf.lane == .scale || kf.lane == .rotation,
              let cfg = controller.projectConfig,
              kf.setIdx < cfg.spriteConfig.library.spriteSets.count,
              kf.spriteIdx < cfg.spriteConfig.library.spriteSets[kf.setIdx].sprites.count
        else { return nil }
        let sprite = cfg.spriteConfig.library.spriteSets[kf.setIdx].sprites[kf.spriteIdx]
        guard sprite.name == controller.selectedSpriteID,
              let drivers = sprite.animation.drivers
        else { return nil }
        switch kf.lane {
        case .position: guard kf.keyframeIdx < drivers.position.keyframes.count else { return nil }
        case .scale:    guard kf.keyframeIdx < drivers.scale.keyframes.count    else { return nil }
        case .rotation: guard kf.keyframeIdx < drivers.rotation.keyframes.count else { return nil }
        default: return nil
        }
        return kf
    }

    // MARK: - Resolved def (live drag > timeline driver KF > legacy KF offset > base params)

    private func resolvedDef(_ sprite: SpriteDef) -> SpriteDef {
        guard sprite.name == controller.selectedSpriteID else { return sprite }

        // Active drag overrides everything
        if let live = liveTransform {
            var d = sprite
            d.position.x = live.posX;  d.position.y = live.posY
            d.scale.x    = live.scaleX; d.scale.y   = live.scaleY
            d.rotation   = live.rotation
            return d
        }

        // Timeline driver KF mode: evaluate ALL enabled driver lanes at the selected KF's
        // frame so position, scale, and rotation are seen together as a single consistent pose.
        if let tkf = activeTimelineKF, let drivers = sprite.animation.drivers {
            let targetFrame: Int
            switch tkf.lane {
            case .position: targetFrame = drivers.position.keyframes[tkf.keyframeIdx].frame
            case .scale:    targetFrame = drivers.scale.keyframes[tkf.keyframeIdx].frame
            case .rotation: targetFrame = drivers.rotation.keyframes[tkf.keyframeIdx].frame
            default:        return sprite
            }
            let elapsed = Double(targetFrame)
            let fps = controller.projectConfig?.globalConfig.targetFPS ?? 30.0
            var d = sprite
            if drivers.position.enabled {
                let v = DriverEvaluator.evaluate(drivers.position, globalElapsed: elapsed,
                                                 targetFPS: fps, spriteIndex: tkf.spriteIdx)
                d.position.x += v.x
                d.position.y += v.y
            }
            if drivers.scale.enabled {
                let v = DriverEvaluator.evaluate(drivers.scale, globalElapsed: elapsed,
                                                 targetFPS: fps, spriteIndex: tkf.spriteIdx)
                d.scale.x *= v.x
                d.scale.y *= v.y
            }
            if drivers.rotation.enabled {
                d.rotation += DriverEvaluator.evaluate(drivers.rotation, globalElapsed: elapsed,
                                                       targetFPS: fps, spriteIndex: tkf.spriteIdx)
            }
            return d
        }

        // Apply selected legacy keyframe offset (KF values are absolute offsets from base)
        if selectedKeyframeIndex > 0 && keyframeEnabled {
            let kfs = sprite.animation.keyframes.sorted { $0.drawCycle < $1.drawCycle }
            let kfIdx = selectedKeyframeIndex - 1
            if kfIdx < kfs.count {
                let kf = kfs[kfIdx]
                var d = sprite
                d.position.x += kf.position.x
                d.position.y += kf.position.y
                d.scale.x    *= kf.scale.x
                d.scale.y    *= kf.scale.y
                d.rotation   += kf.rotation
                return d
            }
        }

        return sprite
    }

    // MARK: - Helpers

    private func makeInstanceMap() -> [String: SpriteInstance] {
        let instances = controller.engine?.spriteInstances ?? []
        return Dictionary(instances.map { ($0.def.name, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func bbox(_ pts: [CGPoint]) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? {
        guard !pts.isEmpty else { return nil }
        return (pts.map(\.x).min()!, pts.map(\.x).max()!, pts.map(\.y).min()!, pts.map(\.y).max()!)
    }

    private func spriteLocation(named name: String, in cfg: ProjectConfig) -> (Int, Int)? {
        for (si, set) in cfg.spriteConfig.library.spriteSets.enumerated() {
            if let pi = set.sprites.firstIndex(where: { $0.name == name }) { return (si, pi) }
        }
        return nil
    }

    // MARK: - Selection (tap)

    private func selectSprite(at location: CGPoint, viewSize: CGSize) {
        guard let cfg = controller.projectConfig else { return }
        let rect        = canvasRect(viewSize: viewSize)
        let instanceMap = makeInstanceMap()
        let sprites     = cfg.spriteConfig.library.allSprites
        let wireWorlds  = buildWireWorlds(sprites: sprites, liveOffsets: [:])

        // Try engine-instance sprites first (precise bbox hit)
        for sprite in sprites.reversed() {
            guard let instance = instanceMap[sprite.name],
                  let world = wireWorlds[sprite.name] else { continue }
            let pts = instance.basePolygons.flatMap { $0.points }
                .map { transformPointWithWorld($0, world: world, depth: sprite.depth, rect: rect) }
            guard !pts.isEmpty, let bb = bbox(pts) else { continue }
            let hitRect = CGRect(x: bb.minX - 5, y: bb.minY - 5,
                                 width: bb.maxX - bb.minX + 10, height: bb.maxY - bb.minY + 10)
            if hitRect.contains(location) {
                controller.selectedSpriteID = sprite.name
                return
            }
        }

        // Fall back to placeholder sprites (no engine instance)
        for sprite in cfg.spriteConfig.library.allSprites.reversed() {
            guard instanceMap[sprite.name] == nil else { continue }
            let centre = parallaxAdjustedScreen(sprite.position, depth: sprite.depth, rect: rect)
            let hitRect = CGRect(x: centre.x - 14, y: centre.y - 14, width: 28, height: 28)
            if hitRect.contains(location) {
                controller.selectedSpriteID = sprite.name
                return
            }
        }

        controller.selectedSpriteID = nil
    }

    // MARK: - Drag begin

    private func beginDrag(at startLoc: CGPoint, viewSize: CGSize) {
        guard let spriteID = controller.selectedSpriteID,
              let cfg = controller.projectConfig,
              let sprite = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID })
        else { return }

        let rect           = canvasRect(viewSize: viewSize)
        let instanceMap    = makeInstanceMap()
        let resolvedSprite = resolvedDef(sprite)
        let sprites        = cfg.spriteConfig.library.allSprites
        let wireWorlds     = buildWireWorlds(sprites: sprites, liveOffsets: [:])
        let world          = wireWorlds[spriteID]

        // Compute screen bbox from engine geometry or placeholder
        var screenPoints: [CGPoint]
        if let instance = instanceMap[spriteID], let world = world {
            screenPoints = instance.basePolygons.flatMap { $0.points }
                .map { transformPointWithWorld($0, world: world, depth: sprite.depth, rect: rect) }
        } else {
            let centre = positionToScreen(resolvedSprite.position, rect: rect)
            let pad: CGFloat = 12
            screenPoints = [
                CGPoint(x: centre.x - pad, y: centre.y - pad),
                CGPoint(x: centre.x + pad, y: centre.y - pad),
                CGPoint(x: centre.x + pad, y: centre.y + pad),
                CGPoint(x: centre.x - pad, y: centre.y + pad)
            ]
        }
        guard !screenPoints.isEmpty, let bb = bbox(screenPoints) else { return }

        let pad: CGFloat = 5
        let box = CGRect(x: bb.minX - pad, y: bb.minY - pad,
                         width: bb.maxX - bb.minX + pad * 2,
                         height: bb.maxY - bb.minY + pad * 2)

        // Hit-test handles first (8 px radius)
        for (id, pos) in handlePositions(for: box) {
            if hypot(startLoc.x - pos.x, startLoc.y - pos.y) <= 8 {
                activeDragHandle = id
                dragStartPos     = startLoc
                dragStartDef     = resolvedSprite
                liveTransform    = LiveTransform(resolvedSprite)
                return
            }
        }

        // Interior drag → move
        if box.contains(startLoc) {
            activeDragHandle = .interior
            dragStartPos     = startLoc
            dragStartDef     = resolvedSprite
            liveTransform    = LiveTransform(resolvedSprite)
        }
    }

    // MARK: - Drag update (live preview)

    private func updateDrag(to currentLoc: CGPoint, viewSize: CGSize) {
        guard let handle   = activeDragHandle,
              let startDef = dragStartDef else { return }

        let rect     = canvasRect(viewSize: viewSize)
        let startW   = screenToWorld(dragStartPos, in: rect)
        let currW    = screenToWorld(currentLoc,   in: rect)
        let centreScreen = parallaxAdjustedScreen(startDef.position, depth: startDef.depth, rect: rect)
        var live = LiveTransform(startDef)

        switch handle {

        case .interior:
            var newX = startDef.position.x + (currW.x - startW.x) * 100.0
            var newY = startDef.position.y + (currW.y - startW.y) * 100.0
            if snapToGrid && gridSizePct > 0 {
                newX = (newX / gridSizePct).rounded() * gridSizePct
                newY = (newY / gridSizePct).rounded() * gridSizePct
            }
            live.posX = newX.clamped(-200, 200)
            live.posY = newY.clamped(-200, 200)

        case .tl, .br:  // uniform scale (radial distance from centre)
            let d0 = hypot(dragStartPos.x - centreScreen.x, dragStartPos.y - centreScreen.y)
            let d1 = hypot(currentLoc.x - centreScreen.x, currentLoc.y - centreScreen.y)
            guard d0 > 1e-8 else { break }
            let ratio = d1 / d0
            live.scaleX = (startDef.scale.x * ratio).clamped(0.001, 10)
            live.scaleY = (startDef.scale.y * ratio).clamped(0.001, 10)

        case .l, .r:    // scale X only
            let dx0 = abs(dragStartPos.x - centreScreen.x)
            let dx1 = abs(currentLoc.x - centreScreen.x)
            guard dx0 > 1e-8 else { break }
            live.scaleX = (startDef.scale.x * dx1 / dx0).clamped(0.001, 10)

        case .t, .b:    // scale Y only
            let dy0 = abs(dragStartPos.y - centreScreen.y)
            let dy1 = abs(currentLoc.y - centreScreen.y)
            guard dy0 > 1e-8 else { break }
            live.scaleY = (startDef.scale.y * dy1 / dy0).clamped(0.001, 10)

        case .tr, .bl:  // rotate
            let a0 = atan2(centreScreen.y - dragStartPos.y, dragStartPos.x - centreScreen.x)
            let a1 = atan2(centreScreen.y - currentLoc.y, currentLoc.x - centreScreen.x)
            let delta = (a1 - a0) * 180.0 / .pi
            live.rotation = (startDef.rotation + delta).truncatingRemainder(dividingBy: 360)
        }

        liveTransform = live
    }

    // MARK: - Drag commit

    private func commitDrag() {
        defer {
            activeDragHandle = nil
            dragStartPos     = .zero
            dragStartDef     = nil
            liveTransform    = nil
        }
        guard let live    = liveTransform,
              let spriteID = controller.selectedSpriteID,
              let cfg      = controller.projectConfig,
              let (si, pi) = spriteLocation(named: spriteID, in: cfg)
        else { return }

        // Timeline driver KF mode: write the drag result back to the selected driver keyframe.
        if let tkf = activeTimelineKF {
            controller.updateProjectConfig { config in
                let base = config.spriteConfig.library.spriteSets[si].sprites[pi]
                withDrivers(in: &config, si: si, pi: pi) { drivers in
                    switch tkf.lane {
                    case .position:
                        guard tkf.keyframeIdx < drivers.position.keyframes.count else { return }
                        drivers.position.keyframes[tkf.keyframeIdx].value = Vector2D(
                            x: live.posX - base.position.x,
                            y: live.posY - base.position.y
                        )
                    case .scale:
                        guard tkf.keyframeIdx < drivers.scale.keyframes.count else { return }
                        let bsx = base.scale.x != 0 ? base.scale.x : 1.0
                        let bsy = base.scale.y != 0 ? base.scale.y : 1.0
                        drivers.scale.keyframes[tkf.keyframeIdx].value = Vector2D(
                            x: live.scaleX / bsx,
                            y: live.scaleY / bsy
                        )
                    case .rotation:
                        guard tkf.keyframeIdx < drivers.rotation.keyframes.count else { return }
                        drivers.rotation.keyframes[tkf.keyframeIdx].value = live.rotation - base.rotation
                    default: break
                    }
                }
            }
            return
        }

        // Editing a legacy keyframe: write back offsets relative to the base sprite params
        if editKeyframe && selectedKeyframeIndex > 0 && keyframeEnabled {
            let sprite = cfg.spriteConfig.library.spriteSets[si].sprites[pi]
            let kfs = sprite.animation.keyframes.sorted { $0.drawCycle < $1.drawCycle }
            let kfIdx = selectedKeyframeIndex - 1
            guard kfIdx < kfs.count else { return }
            let targetCycle = kfs[kfIdx].drawCycle
            guard let rawKFIdx = sprite.animation.keyframes.firstIndex(where: { $0.drawCycle == targetCycle })
            else { return }

            controller.updateProjectConfig { config in
                let base = config.spriteConfig.library.spriteSets[si].sprites[pi]
                let baseScaleX = base.scale.x != 0 ? base.scale.x : 1.0
                let baseScaleY = base.scale.y != 0 ? base.scale.y : 1.0
                config.spriteConfig.library.spriteSets[si].sprites[pi]
                    .animation.keyframes[rawKFIdx].position.x = live.posX - base.position.x
                config.spriteConfig.library.spriteSets[si].sprites[pi]
                    .animation.keyframes[rawKFIdx].position.y = live.posY - base.position.y
                config.spriteConfig.library.spriteSets[si].sprites[pi]
                    .animation.keyframes[rawKFIdx].scale.x = live.scaleX / baseScaleX
                config.spriteConfig.library.spriteSets[si].sprites[pi]
                    .animation.keyframes[rawKFIdx].scale.y = live.scaleY / baseScaleY
                config.spriteConfig.library.spriteSets[si].sprites[pi]
                    .animation.keyframes[rawKFIdx].rotation = live.rotation - base.rotation
            }
            return
        }

        // Default: write back to sprite base params and propagate to children
        let oldPosX = cfg.spriteConfig.library.spriteSets[si].sprites[pi].position.x
        let oldPosY = cfg.spriteConfig.library.spriteSets[si].sprites[pi].position.y
        let oldRot  = cfg.spriteConfig.library.spriteSets[si].sprites[pi].rotation
        controller.updateProjectConfig { config in
            config.spriteConfig.library.spriteSets[si].sprites[pi].position.x = live.posX
            config.spriteConfig.library.spriteSets[si].sprites[pi].position.y = live.posY
            config.spriteConfig.library.spriteSets[si].sprites[pi].scale.x    = live.scaleX
            config.spriteConfig.library.spriteSets[si].sprites[pi].scale.y    = live.scaleY
            config.spriteConfig.library.spriteSets[si].sprites[pi].rotation   = live.rotation
            let dx = live.posX - oldPosX
            let dy = live.posY - oldPosY
            if dx != 0 || dy != 0 {
                SpritesInspector.propagatePosition(dx: dx, dy: dy, from: spriteID, in: &config, setIdx: si)
            }
            let dRot = live.rotation - oldRot
            if dRot != 0 {
                SpritesInspector.propagateRotation(dRot: dRot, pivotX: live.posX, pivotY: live.posY,
                                                   from: spriteID, in: &config, setIdx: si)
            }
        }
    }
}

// MARK: - Numeric helpers

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, self)) }
}
