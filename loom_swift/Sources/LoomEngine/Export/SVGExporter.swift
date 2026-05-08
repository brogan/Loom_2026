import Foundation

// MARK: - SVGExporter

/// Exports the current engine geometry as an SVG file.
///
/// The export captures geometry at the current frame state (no animation advance).
/// Each sprite's polygons are morphed, subdivided, and transformed exactly as they
/// would be rendered — then written as SVG path elements.
public enum SVGExporter {

    /// Write an SVG representation of the current engine frame to `url`.
    ///
    /// - Throws: `SVGExporterError.writeFailed` when the file cannot be written.
    public static func exportSVG(engine: Engine, to url: URL) throws {
        let cs = engine.canvasSize
        let w  = Int(cs.width), h = Int(cs.height)

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">")

        var rng = SystemRandomNumberGenerator()

        for inst in engine.spriteInstances {
            let polygons = processedPolygons(for: inst, canvasSize: cs, rng: &rng)
            let renderer = inst.rendererSet.renderers.first(where: { $0.enabled })
            let sc = renderer?.strokeColor ?? .black
            let fc = renderer?.fillColor   ?? .black
            let sw = renderer?.strokeWidth ?? 1.0

            for poly in polygons {
                guard poly.visible else { continue }
                switch poly.type {
                case .line:
                    if let d = linePath(poly.points, cs: cs) {
                        lines.append("  <path d=\"\(d)\" \(attrs(sc, fc, sw))/>")
                    }
                case .spline:
                    if let d = splinePath(poly.points, cs: cs, closed: true) {
                        lines.append("  <path d=\"\(d)\" \(attrs(sc, fc, sw))/>")
                    }
                case .openSpline:
                    if let d = splinePath(poly.points, cs: cs, closed: false) {
                        lines.append("  <path d=\"\(d)\" stroke=\"\(css(sc))\" stroke-opacity=\"\(n(sc.aF))\" fill=\"none\" stroke-width=\"\(n(sw))\"/>")
                    }
                case .oval:
                    if let e = ovalElem(poly.points, cs: cs, sc: sc, fc: fc, sw: sw) {
                        lines.append("  \(e)")
                    }
                case .point:
                    if let pt = poly.points.first {
                        let s = scr(pt, cs: cs)
                        lines.append("  <circle cx=\"\(n(s.x))\" cy=\"\(n(s.y))\" r=\"\(n(max(sw / 2, 1)))\" fill=\"\(css(sc))\" fill-opacity=\"\(n(sc.aF))\"/>")
                    }
                }
            }
        }

        lines.append("</svg>")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw SVGExporterError.writeFailed
        }
    }

    // MARK: - Pipeline

    private static func processedPolygons<RNG: RandomNumberGenerator>(
        for inst: SpriteInstance,
        canvasSize: CGSize,
        rng: inout RNG
    ) -> [Polygon2D] {
        let morphed = MorphInterpolator.interpolate(
            base:        inst.basePolygons,
            targets:     inst.morphTargetPolygons,
            morphAmount: inst.state.transform.morphAmount
        )
        let subdivided = inst.subdivisionParams.isEmpty ? morphed :
            SubdivisionEngine.process(polygons: morphed, paramSet: inst.subdivisionParams, rng: &rng)
        return subdivided.map { applyTransform($0, inst: inst, canvasSize: canvasSize) }
    }

    private static func applyTransform(
        _ polygon: Polygon2D,
        inst: SpriteInstance,
        canvasSize: CGSize
    ) -> Polygon2D {
        let hw = canvasSize.width  / 2.0
        let hh = canvasSize.height / 2.0
        let def  = inst.def
        let anim = inst.state.transform
        let sx = def.scale.x * anim.scale.x * 2.0
        let sy = def.scale.y * anim.scale.y * 2.0
        let rotRad = (def.rotation + anim.rotation) * .pi / 180.0
        let cosR   = cos(rotRad), sinR = sin(rotRad)
        let tx = (def.position.x + anim.positionOffset.x) / 100.0 * hw
        let ty = (def.position.y + anim.positionOffset.y) / 100.0 * hh
        let pts = polygon.points.map { pt -> Vector2D in
            var wx = pt.x * sx, wy = pt.y * sy
            if rotRad != 0 {
                (wx, wy) = (wx * cosR - wy * sinR, wx * sinR + wy * cosR)
            }
            return Vector2D(x: wx * hw + tx, y: wy * hh + ty)
        }
        return Polygon2D(points: pts, type: polygon.type,
                         pressures: polygon.pressures, visible: polygon.visible)
    }

    // MARK: - Path builders

    /// World-space pixel offset → SVG screen coordinate (top-left origin, Y-down).
    private static func scr(_ v: Vector2D, cs: CGSize) -> (x: Double, y: Double) {
        (cs.width / 2 + v.x, cs.height / 2 - v.y)
    }

    private static func linePath(_ pts: [Vector2D], cs: CGSize) -> String? {
        guard !pts.isEmpty else { return nil }
        var d = ""
        for (i, pt) in pts.enumerated() {
            let s = scr(pt, cs: cs)
            d += i == 0 ? "M \(n(s.x)) \(n(s.y))" : " L \(n(s.x)) \(n(s.y))"
        }
        return d + " Z"
    }

    private static func splinePath(_ pts: [Vector2D], cs: CGSize, closed: Bool) -> String? {
        guard pts.count >= 4 else { return nil }
        let s0 = scr(pts[0], cs: cs)
        var d  = "M \(n(s0.x)) \(n(s0.y))"
        for i in 0..<(pts.count / 4) {
            let b   = i * 4
            let to  = scr(pts[b + 3], cs: cs)
            let cp1 = scr(pts[b + 1], cs: cs)
            let cp2 = scr(pts[b + 2], cs: cs)
            d += " C \(n(cp1.x)) \(n(cp1.y)) \(n(cp2.x)) \(n(cp2.y)) \(n(to.x)) \(n(to.y))"
        }
        if closed { d += " Z" }
        return d
    }

    private static func ovalElem(
        _ pts: [Vector2D], cs: CGSize,
        sc: LoomColor, fc: LoomColor, sw: Double
    ) -> String? {
        guard pts.count >= 2 else { return nil }
        let ctr = scr(pts[0], cs: cs)
        let rpt = scr(pts[1], cs: cs)
        let rx  = abs(rpt.x - ctr.x), ry = abs(rpt.y - ctr.y)
        return "<ellipse cx=\"\(n(ctr.x))\" cy=\"\(n(ctr.y))\" rx=\"\(n(rx))\" ry=\"\(n(ry))\" \(attrs(sc, fc, sw))/>"
    }

    // MARK: - Formatting helpers

    private static func attrs(_ sc: LoomColor, _ fc: LoomColor, _ sw: Double) -> String {
        "stroke=\"\(css(sc))\" stroke-opacity=\"\(n(sc.aF))\" fill=\"\(css(fc))\" fill-opacity=\"\(n(fc.aF))\" stroke-width=\"\(n(sw))\""
    }

    private static func css(_ c: LoomColor) -> String {
        String(format: "rgb(%d,%d,%d)", c.r, c.g, c.b)
    }

    private static func n(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".")    { s.removeLast() }
        }
        return s
    }
}

// MARK: - SVGExporterError

public enum SVGExporterError: Error, Equatable {
    /// The SVG string could not be written to disk.
    case writeFailed
}
