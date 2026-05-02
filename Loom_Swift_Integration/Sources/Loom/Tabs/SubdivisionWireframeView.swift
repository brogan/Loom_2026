import SwiftUI
import LoomEngine

struct SubdivisionWireframeView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12)

            GeometryReader { geo in
                Canvas { ctx, size in
                    let cRect = canvasRect(viewSize: size)
                    drawSprites(ctx: ctx, rect: cRect)
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    selectSprite(at: location, viewSize: geo.size)
                }
            }

            if controller.subdivSelectedSpriteID == nil {
                Text("Select a polygon-set sprite above to preview subdivision")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Canvas rect (letterboxed)

    private func canvasRect(viewSize: CGSize) -> CGRect {
        let cSize   = controller.engine?.canvasSize ?? CGSize(width: 1, height: 1)
        let cAspect = cSize.width / cSize.height
        let vAspect = viewSize.width / viewSize.height
        if cAspect > vAspect {
            let h = viewSize.width / cAspect
            return CGRect(x: 0, y: (viewSize.height - h) / 2, width: viewSize.width, height: h)
        } else {
            let w = viewSize.height * cAspect
            return CGRect(x: (viewSize.width - w) / 2, y: 0, width: w, height: viewSize.height)
        }
    }

    // MARK: - Drawing

    private func drawSprites(ctx: GraphicsContext, rect: CGRect) {
        guard let cfg = controller.projectConfig else { return }
        let instanceMap = makeInstanceMap()
        let relevant    = polygonSetSprites(in: cfg)

        for sprite in relevant {
            let isSelected = controller.subdivSelectedSpriteID == sprite.name

            if let instance = instanceMap[sprite.name] {
                if isSelected {
                    // Base polygon outline (faint reference)
                    for polygon in instance.basePolygons where polygon.visible {
                        let pts = polygon.points.map { transformPoint($0, def: sprite, rect: rect) }
                        ctx.stroke(buildPath(pts, type: polygon.type),
                                   with: .color(Color(white: 0.32)), lineWidth: 0.5)
                    }
                    // Subdivided result (highlighted)
                    let subdivided = computeSubdivision(basePolygons: instance.basePolygons)
                    for polygon in subdivided where polygon.visible {
                        let pts = polygon.points.map { transformPoint($0, def: sprite, rect: rect) }
                        ctx.stroke(buildPath(pts, type: polygon.type),
                                   with: .color(Color(red: 0.31, green: 0.78, blue: 0.47).opacity(0.85)),
                                   lineWidth: 1.0)
                    }
                } else {
                    for polygon in instance.basePolygons where polygon.visible {
                        let pts = polygon.points.map { transformPoint($0, def: sprite, rect: rect) }
                        ctx.stroke(buildPath(pts, type: polygon.type),
                                   with: .color(Color(white: 0.20)), lineWidth: 0.4)
                    }
                }
            } else {
                // Placeholder cross
                let centre = positionToScreen(sprite.position, rect: rect)
                let color: Color = isSelected ? Color(white: 0.55) : Color(white: 0.22)
                drawPlaceholder(ctx: ctx, centre: centre, color: color)
            }
        }
    }

    private func computeSubdivision(basePolygons: [Polygon2D]) -> [Polygon2D] {
        guard let setName = controller.subdivPreviewSetName, !setName.isEmpty,
              let paramSet = controller.projectConfig?.subdivisionConfig.paramsSet(named: setName),
              !paramSet.params.isEmpty
        else { return basePolygons }
        var rng = SeededRNG()
        return SubdivisionEngine.process(polygons: basePolygons, paramSet: paramSet.params, rng: &rng)
    }

    // MARK: - Tap-to-select

    private func selectSprite(at location: CGPoint, viewSize: CGSize) {
        guard let cfg = controller.projectConfig else { return }
        let rect    = canvasRect(viewSize: viewSize)
        let instMap = makeInstanceMap()

        for sprite in polygonSetSprites(in: cfg).reversed() {
            if let inst = instMap[sprite.name] {
                let pts = inst.basePolygons.flatMap { $0.points }
                    .map { transformPoint($0, def: sprite, rect: rect) }
                guard !pts.isEmpty else { continue }
                let bb = bbox(pts)
                let hit = CGRect(x: bb.minX - 8, y: bb.minY - 8,
                                 width: bb.maxX - bb.minX + 16, height: bb.maxY - bb.minY + 16)
                if hit.contains(location) { applySelection(sprite, cfg: cfg); return }
            } else {
                let centre = positionToScreen(sprite.position, rect: rect)
                let hit = CGRect(x: centre.x - 14, y: centre.y - 14, width: 28, height: 28)
                if hit.contains(location) { applySelection(sprite, cfg: cfg); return }
            }
        }
    }

    private func applySelection(_ sprite: SpriteDef, cfg: ProjectConfig) {
        controller.subdivSelectedSpriteID = sprite.name
        let assigned = assignedSetName(sprite: sprite, cfg: cfg)
        controller.subdivPreviewSetName   = assigned
        if let assigned,
           let idx = cfg.subdivisionConfig.paramsSets.firstIndex(where: { $0.name == assigned }) {
            controller.selectedSubdivisionIndex = idx
        } else {
            controller.selectedSubdivisionIndex = nil
        }
        controller.selectedSubdivisionParamIndex = nil
    }

    // MARK: - Helpers

    private func makeInstanceMap() -> [String: SpriteInstance] {
        let instances = controller.engine?.spriteInstances ?? []
        return Dictionary(instances.map { ($0.def.name, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func polygonSetSprites(in cfg: ProjectConfig) -> [SpriteDef] {
        cfg.spriteConfig.library.allSprites.filter { isPolygonSetSprite($0, in: cfg) }
    }

    func isPolygonSetSprite(_ sprite: SpriteDef, in cfg: ProjectConfig) -> Bool {
        guard let shape = cfg.shapeConfig.library.shapeSets
            .first(where: { $0.name == sprite.shapeSetName })?
            .shapes.first(where: { $0.name == sprite.shapeName })
        else { return false }
        return shape.sourceType == .polygonSet || shape.sourceType == .regularPolygon
    }

    func assignedSetName(sprite: SpriteDef, cfg: ProjectConfig) -> String? {
        cfg.shapeConfig.library.shapeSets
            .first(where: { $0.name == sprite.shapeSetName })?
            .shapes.first(where: { $0.name == sprite.shapeName })?
            .subdivisionParamsSetName.nonEmpty
    }

    private func positionToScreen(_ pos: Vector2D, rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (pos.x / 100.0 + 1.0) / 2.0 * rect.width,
            y: rect.minY + (1.0 - pos.y / 100.0) / 2.0 * rect.height
        )
    }

    private func transformPoint(_ pt: Vector2D, def: SpriteDef, rect: CGRect) -> CGPoint {
        let sx = def.scale.x * 2.0, sy = def.scale.y * 2.0
        let rotRad = def.rotation * .pi / 180.0
        let cosR = cos(rotRad), sinR = sin(rotRad)
        var wx = pt.x * sx, wy = pt.y * sy
        if rotRad != 0 {
            let rx = wx * cosR - wy * sinR
            let ry = wx * sinR + wy * cosR
            wx = rx; wy = ry
        }
        let normX = wx + def.position.x / 100.0
        let normY = wy + def.position.y / 100.0
        return CGPoint(
            x: rect.minX + (normX + 1.0) / 2.0 * rect.width,
            y: rect.minY + (1.0 - normY) / 2.0 * rect.height
        )
    }

    private func buildPath(_ pts: [CGPoint], type: PolygonType) -> Path {
        guard !pts.isEmpty else { return Path() }
        var p = Path()
        switch type {
        case .spline:
            p.move(to: pts[0])
            var i = 0
            while i + 3 < pts.count {
                p.addCurve(to: pts[i + 3], control1: pts[i + 1], control2: pts[i + 2]); i += 3
            }
            p.closeSubpath()
        case .openSpline:
            p.move(to: pts[0])
            var i = 0
            while i + 3 < pts.count {
                p.addCurve(to: pts[i + 3], control1: pts[i + 1], control2: pts[i + 2]); i += 3
            }
        case .point:
            for pt in pts { p.addEllipse(in: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)) }
        case .oval:
            if pts.count >= 2 {
                let cx = pts[0].x, cy = pts[0].y
                let rx = abs(pts[1].x - cx), ry = abs(pts[1].y - cy)
                p.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
            }
        default:
            guard pts.count >= 2 else { return p }
            p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }
            p.closeSubpath()
        }
        return p
    }

    private func drawPlaceholder(ctx: GraphicsContext, centre: CGPoint, color: Color) {
        let s: CGFloat = 8
        var p = Path()
        p.move(to: CGPoint(x: centre.x - s, y: centre.y)); p.addLine(to: CGPoint(x: centre.x + s, y: centre.y))
        p.move(to: CGPoint(x: centre.x, y: centre.y - s)); p.addLine(to: CGPoint(x: centre.x, y: centre.y + s))
        ctx.stroke(p, with: .color(color), lineWidth: 1.2)
    }

    private func bbox(_ pts: [CGPoint]) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        (pts.map(\.x).min()!, pts.map(\.x).max()!, pts.map(\.y).min()!, pts.map(\.y).max()!)
    }
}

// MARK: - Deterministic RNG for stable subdivision preview

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64 = 42) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
