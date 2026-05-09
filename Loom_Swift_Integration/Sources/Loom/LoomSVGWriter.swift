import Foundation
import LoomEngine

enum LoomSVGWriter {

    // MARK: - Write to named file in directory

    @discardableResult
    static func writeSVG(
        polygons: [Polygon2D],
        stem: String,
        canvasSize: (width: Double, height: Double),
        to directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = uniqueFilename(stem: safeStem(stem), in: directory)
        let url = directory.appendingPathComponent(filename)
        try writeSVG(polygons: polygons, canvasSize: canvasSize, to: url)
        return url
    }

    // MARK: - Write to explicit URL

    static func writeSVG(
        polygons: [Polygon2D],
        canvasSize: (width: Double, height: Double),
        to url: URL
    ) throws {
        let w = canvasSize.width
        let h = canvasSize.height
        let hw = w / 2
        let hh = h / 2

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" " +
            "width=\"\(Int(w))\" height=\"\(Int(h))\" " +
            "viewBox=\"0 0 \(Int(w)) \(Int(h))\">"
        )

        for poly in polygons where poly.visible {
            switch poly.type {
            case .spline:
                appendSplineElements(&lines, poly: poly, hw: hw, hh: hh, closed: true)
            case .openSpline:
                appendSplineElements(&lines, poly: poly, hw: hw, hh: hh, closed: false)
            case .line:
                if let d = linePath(poly.points, hw: hw, hh: hh) {
                    lines.append("  <path d=\"\(d)\" fill=\"none\" stroke=\"#000000\" stroke-width=\"1\"/>")
                }
            case .oval:
                if let e = ovalElem(poly.points, hw: hw, hh: hh) {
                    lines.append("  \(e)")
                }
            case .point:
                if let pt = poly.points.first {
                    let s = scr(pt, hw: hw, hh: hh)
                    lines.append("  <circle cx=\"\(fmt(s.x))\" cy=\"\(fmt(s.y))\" r=\"1\" fill=\"#000000\"/>")
                }
            }
        }

        lines.append("</svg>")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Filename helpers

    static func uniqueFilename(stem: String, in directory: URL) -> String {
        let base = stem.isEmpty ? "geometry" : stem
        var candidate = "\(base).svg"
        var counter = 2
        while FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(candidate).path
        ) {
            candidate = "\(base)_\(counter).svg"
            counter += 1
        }
        return candidate
    }

    static func safeStem(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "geometry" : trimmed.replacingOccurrences(of: " ", with: "_")
    }

    // MARK: - Path builders

    // Emit per-segment paths so stroke width can vary with pressure data.
    private static func appendSplineElements(
        _ lines: inout [String],
        poly: Polygon2D,
        hw: Double,
        hh: Double,
        closed: Bool
    ) {
        let pts = poly.points
        guard pts.count >= 4 else { return }
        let segCount = pts.count / 4

        if poly.pressures.isEmpty {
            if let d = splinePath(pts, hw: hw, hh: hh, closed: closed) {
                lines.append("  <path d=\"\(d)\" fill=\"none\" stroke=\"#000000\" stroke-width=\"1\"/>")
            }
            return
        }

        for i in 0..<segCount {
            let base = i * 4
            let pressure = Swift.max(0, Swift.min(1, i < poly.pressures.count ? poly.pressures[i] : 1.0))
            let sw = 0.3 + pressure * 1.7
            let s0  = scr(pts[base],     hw: hw, hh: hh)
            let cp1 = scr(pts[base + 1], hw: hw, hh: hh)
            let cp2 = scr(pts[base + 2], hw: hw, hh: hh)
            let s3  = scr(pts[base + 3], hw: hw, hh: hh)
            let d = "M \(fmt(s0.x)) \(fmt(s0.y)) C \(fmt(cp1.x)) \(fmt(cp1.y)) \(fmt(cp2.x)) \(fmt(cp2.y)) \(fmt(s3.x)) \(fmt(s3.y))"
            lines.append("  <path d=\"\(d)\" fill=\"none\" stroke=\"#000000\" stroke-width=\"\(fmt(sw))\"/>")
        }
    }

    private static func splinePath(_ pts: [Vector2D], hw: Double, hh: Double, closed: Bool) -> String? {
        guard pts.count >= 4 else { return nil }
        let s0 = scr(pts[0], hw: hw, hh: hh)
        var d = "M \(fmt(s0.x)) \(fmt(s0.y))"
        for i in 0..<(pts.count / 4) {
            let b   = i * 4
            let to  = scr(pts[b + 3], hw: hw, hh: hh)
            let cp1 = scr(pts[b + 1], hw: hw, hh: hh)
            let cp2 = scr(pts[b + 2], hw: hw, hh: hh)
            d += " C \(fmt(cp1.x)) \(fmt(cp1.y)) \(fmt(cp2.x)) \(fmt(cp2.y)) \(fmt(to.x)) \(fmt(to.y))"
        }
        if closed { d += " Z" }
        return d
    }

    private static func linePath(_ pts: [Vector2D], hw: Double, hh: Double) -> String? {
        guard !pts.isEmpty else { return nil }
        var d = ""
        for (i, pt) in pts.enumerated() {
            let s = scr(pt, hw: hw, hh: hh)
            d += i == 0 ? "M \(fmt(s.x)) \(fmt(s.y))" : " L \(fmt(s.x)) \(fmt(s.y))"
        }
        return d + " Z"
    }

    private static func ovalElem(_ pts: [Vector2D], hw: Double, hh: Double) -> String? {
        guard pts.count >= 2 else { return nil }
        let ctr = scr(pts[0], hw: hw, hh: hh)
        let rpt = scr(pts[1], hw: hw, hh: hh)
        let rx = abs(rpt.x - ctr.x), ry = abs(rpt.y - ctr.y)
        return "<ellipse cx=\"\(fmt(ctr.x))\" cy=\"\(fmt(ctr.y))\" rx=\"\(fmt(rx))\" ry=\"\(fmt(ry))\" fill=\"none\" stroke=\"#000000\" stroke-width=\"1\"/>"
    }

    // MARK: - Coordinate mapping

    /// World-space (Y-up, origin at canvas centre) → SVG screen coords (Y-down, origin top-left).
    /// Applies the default sprite scale: world ±0.5 maps to ±half the canvas dimensions.
    private static func scr(_ v: Vector2D, hw: Double, hh: Double) -> (x: Double, y: Double) {
        (hw + v.x * hw, hh - v.y * hh)
    }

    // MARK: - Number formatting

    private static func fmt(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
