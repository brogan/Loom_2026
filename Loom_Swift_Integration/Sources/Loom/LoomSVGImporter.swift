import CoreGraphics
import Foundation

/// Converts SVG path geometry to Loom's XML polygon-set format.
///
/// All styling (colour, stroke, fill, opacity) is discarded.  Only Bézier
/// geometry is imported.  Each SVG subpath (between consecutive `M` commands
/// or path elements) becomes one `<polygon>` in the output XML.  Subpaths
/// ending with `Z` are marked `isClosed="true"`; all others are `isClosed="false"`.
///
/// ### Coordinate conventions
/// SVG uses Y-down with origin at the top-left of the viewBox.
/// The output XML stores coordinates in the same Y direction; `XMLPolygonLoader`
/// negates Y on load to produce Loom's Y-up world space — so no Y-flip is
/// needed here.  Coordinates are normalised so the larger SVG dimension spans
/// the Loom geometry range [−0.5, 0.5]; aspect ratio is preserved.
///
/// ### Supported SVG path commands
/// M m L l H h V v C c S s Q q T t A a Z z
enum LoomSVGImporter {

    // MARK: - Public API

    /// Parse an SVG file and return a `<polygonSet>` XML string.
    ///
    /// - Throws: `LoomSVGImportError` when the file cannot be read or is not valid SVG.
    static func importPolygonSetXML(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let _ = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw LoomSVGImportError.unreadable
        }
        let parsed = try SVGDocumentParser.parse(data: data)
        let normalizer = CoordinateNormalizer(viewBox: parsed.viewBox)
        let polygons = extractPolygons(from: parsed.paths, normalizer: normalizer)
        return buildXML(from: polygons)
    }

    // MARK: - Internal types

    private typealias Pt = CGPoint

    private struct BezierSeg {
        var p0, p1, p2, p3: Pt   // anchor, cp-out, cp-in, anchor
    }

    private struct SubPath {
        var segments: [BezierSeg]
        var isClosed: Bool
    }

    // MARK: - Polygon extraction

    private static func extractPolygons(
        from rawPaths: [(d: String, transform: CGAffineTransform)],
        normalizer: CoordinateNormalizer
    ) -> [SubPath] {
        var result: [SubPath] = []
        for (d, xform) in rawPaths {
            let subpaths = PathParser.parse(d: d)
            for sp in subpaths {
                guard !sp.segments.isEmpty else { continue }
                // Apply element transform then normalise coordinates.
                let transformed = sp.segments.map { seg in
                    BezierSeg(
                        p0: normalizer.normalise(seg.p0.applying(xform)),
                        p1: normalizer.normalise(seg.p1.applying(xform)),
                        p2: normalizer.normalise(seg.p2.applying(xform)),
                        p3: normalizer.normalise(seg.p3.applying(xform))
                    )
                }
                result.append(SubPath(segments: transformed, isClosed: sp.isClosed))
            }
        }
        return result
    }

    // MARK: - XML generation

    private static func buildXML(from polygons: [SubPath]) -> String {
        var lines = ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<polygonSet>"]
        for poly in polygons {
            let closed = poly.isClosed ? "true" : "false"
            lines.append("  <polygon isClosed=\"\(closed)\">")
            for seg in poly.segments {
                lines.append("    <curve>")
                lines.append("      \(ptTag(seg.p0, pressure: 1.0))")
                lines.append("      \(ptTag(seg.p1))")
                lines.append("      \(ptTag(seg.p2))")
                lines.append("      \(ptTag(seg.p3))")
                lines.append("    </curve>")
            }
            lines.append("  </polygon>")
        }
        lines.append("</polygonSet>")
        return lines.joined(separator: "\n")
    }

    private static func ptTag(_ p: Pt, pressure: Double? = nil) -> String {
        let xs = fmt(Double(p.x))
        let ys = fmt(Double(p.y))
        if let pr = pressure {
            return "<point x=\"\(xs)\" y=\"\(ys)\" pressure=\"\(fmt(pr))\"/>"
        }
        return "<point x=\"\(xs)\" y=\"\(ys)\"/>"
    }

    private static func fmt(_ v: Double) -> String {
        var s = String(format: "%.5f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    // MARK: - Coordinate normaliser

    private struct CoordinateNormalizer {
        let midX, midY, scale: Double

        init(viewBox: CGRect) {
            midX  = Double(viewBox.midX)
            midY  = Double(viewBox.midY)
            scale = max(Double(viewBox.width), Double(viewBox.height))
        }

        func normalise(_ p: Pt) -> Pt {
            guard scale > 0 else { return .zero }
            return CGPoint(
                x: (Double(p.x) - midX) / scale,
                y: (Double(p.y) - midY) / scale
            )
        }
    }

    // MARK: - SVG document parser (SAX)

    private struct ParsedDocument {
        var viewBox: CGRect
        var paths:   [(d: String, transform: CGAffineTransform)]
    }

    private final class SVGDocumentParser: NSObject, XMLParserDelegate {

        private var viewBox:   CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        private var paths:     [(d: String, transform: CGAffineTransform)] = []
        private var xformStack: [CGAffineTransform] = [.identity]
        private var error:     Error?

        static func parse(data: Data) throws -> ParsedDocument {
            let delegate = SVGDocumentParser()
            let parser   = XMLParser(data: data)
            parser.delegate = delegate
            parser.parse()
            if let e = delegate.error ?? parser.parserError { throw e }
            return ParsedDocument(viewBox: delegate.viewBox, paths: delegate.paths)
        }

        func parser(_ parser: XMLParser,
                    didStartElement element: String,
                    namespaceURI: String?,
                    qualifiedName: String?,
                    attributes attrs: [String: String]) {
            let localXform = parseTransform(attrs["transform"] ?? "")
            let parentXform = xformStack.last ?? .identity
            let effective   = localXform.concatenating(parentXform)

            switch element.lowercased() {
            case "svg":
                if let vb = parseViewBox(attrs["viewBox"] ?? attrs["viewbox"] ?? "") {
                    viewBox = vb
                } else {
                    let w = Double(attrs["width"]  ?? "100") ?? 100
                    let h = Double(attrs["height"] ?? "100") ?? 100
                    viewBox = CGRect(x: 0, y: 0, width: w, height: h)
                }
                xformStack.append(effective)
            case "g", "a", "symbol", "use":
                xformStack.append(effective)
            case "path":
                if let d = attrs["d"], !d.trimmingCharacters(in: .whitespaces).isEmpty {
                    paths.append((d: d, transform: effective))
                }
                // Paths are leaf elements — don't push to stack
            default:
                xformStack.append(effective)
            }
        }

        func parser(_ parser: XMLParser,
                    didEndElement element: String,
                    namespaceURI: String?,
                    qualifiedName: String?) {
            let lower = element.lowercased()
            // Pop for all elements that pushed (everything except <path> and similar leaves)
            switch lower {
            case "path", "circle", "ellipse", "rect", "line", "polyline", "polygon", "image", "text",
                 "tspan", "use", "defs", "style", "title", "desc", "metadata",
                 "linearGradient", "radialGradient", "stop", "filter":
                break
            default:
                if xformStack.count > 1 { xformStack.removeLast() }
            }
        }

        private func parseViewBox(_ s: String) -> CGRect? {
            let nums = s.components(separatedBy: .init(charactersIn: ", \t\n"))
                        .compactMap { Double($0) }
            guard nums.count == 4 else { return nil }
            return CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
        }

        // MARK: Transform parsing

        private func parseTransform(_ s: String) -> CGAffineTransform {
            var result = CGAffineTransform.identity
            var remaining = s.trimmingCharacters(in: .whitespaces)
            while !remaining.isEmpty {
                if let (xform, rest) = consumeTransform(remaining) {
                    result = result.concatenating(xform)
                    remaining = rest.trimmingCharacters(in: .init(charactersIn: ", \t\n"))
                } else {
                    break
                }
            }
            return result
        }

        private func consumeTransform(_ s: String) -> (CGAffineTransform, String)? {
            let s = s.trimmingCharacters(in: .whitespaces)
            guard let parenOpen = s.firstIndex(of: "("),
                  let parenClose = s.firstIndex(of: ")") else { return nil }
            let funcName = String(s[s.startIndex..<parenOpen])
                           .trimmingCharacters(in: .whitespaces).lowercased()
            let argStr   = String(s[s.index(after: parenOpen)..<parenClose])
            let rest     = String(s[s.index(after: parenClose)...])
            let nums     = argStr.components(separatedBy: .init(charactersIn: ", \t\n"))
                                 .compactMap { Double($0) }

            var xform = CGAffineTransform.identity
            switch funcName {
            case "translate":
                let tx = nums[safe: 0] ?? 0
                let ty = nums[safe: 1] ?? 0
                xform = CGAffineTransform(translationX: tx, y: ty)
            case "scale":
                let sx = nums[safe: 0] ?? 1
                let sy = nums[safe: 1] ?? sx
                xform = CGAffineTransform(scaleX: sx, y: sy)
            case "rotate":
                let deg = nums[safe: 0] ?? 0
                let cx  = nums[safe: 1] ?? 0
                let cy  = nums[safe: 2] ?? 0
                let rad = deg * .pi / 180.0
                if cx != 0 || cy != 0 {
                    xform = CGAffineTransform(translationX: cx, y: cy)
                        .rotated(by: rad)
                        .translatedBy(x: -cx, y: -cy)
                } else {
                    xform = CGAffineTransform(rotationAngle: rad)
                }
            case "skewx":
                let rad = (nums[safe: 0] ?? 0) * .pi / 180.0
                xform = CGAffineTransform(a: 1, b: 0, c: tan(rad), d: 1, tx: 0, ty: 0)
            case "skewy":
                let rad = (nums[safe: 0] ?? 0) * .pi / 180.0
                xform = CGAffineTransform(a: 1, b: tan(rad), c: 0, d: 1, tx: 0, ty: 0)
            case "matrix":
                if nums.count >= 6 {
                    xform = CGAffineTransform(a:  nums[0], b:  nums[1],
                                              c:  nums[2], d:  nums[3],
                                              tx: nums[4], ty: nums[5])
                }
            default:
                break
            }
            return (xform, rest)
        }
    }

    // MARK: - SVG path command parser

    private enum PathParser {

        static func parse(d: String) -> [SubPath] {
            let tokens = tokenize(d)
            return interpret(tokens)
        }

        // MARK: Tokenizer

        private enum Token {
            case cmd(Character)
            case num(Double)
            case flag(Bool)   // for arc large-arc and sweep flags
        }

        private static func tokenize(_ d: String) -> [Token] {
            var tokens: [Token] = []
            var i = d.startIndex
            while i < d.endIndex {
                let c = d[i]
                if c.isLetter {
                    tokens.append(.cmd(c))
                    i = d.index(after: i)
                } else if c == "-" || c == "+" || c == "." || c.isNumber {
                    // Scan a number
                    var end = i
                    var hasDot = false
                    var hasE   = false
                    if d[end] == "-" || d[end] == "+" { end = d.index(after: end) }
                    while end < d.endIndex {
                        let ch = d[end]
                        if ch.isNumber {
                            end = d.index(after: end)
                        } else if ch == "." && !hasDot {
                            hasDot = true
                            end = d.index(after: end)
                        } else if (ch == "e" || ch == "E") && !hasE {
                            hasE = true
                            end = d.index(after: end)
                            if end < d.endIndex && (d[end] == "+" || d[end] == "-") {
                                end = d.index(after: end)
                            }
                        } else {
                            break
                        }
                    }
                    if let v = Double(d[i..<end]) {
                        tokens.append(.num(v))
                    }
                    i = end
                } else if c == "," || c.isWhitespace {
                    i = d.index(after: i)
                } else {
                    i = d.index(after: i)
                }
            }
            return tokens
        }

        // MARK: Interpreter

        private static func interpret(_ tokens: [Token]) -> [SubPath] {
            var subpaths: [SubPath] = []
            var current: [BezierSeg] = []
            var startPt  = CGPoint.zero
            var curPt    = CGPoint.zero
            var lastCP2  = CGPoint.zero   // for S/s (reflection of previous C cp2)
            var lastQCP  = CGPoint.zero   // for T/t (reflection of previous Q control)
            var lastCmd: Character = "M"

            var idx = 0
            var cmd: Character = "M"
            var relative = false

            func nextNum() -> Double {
                while idx < tokens.count {
                    if case .num(let v) = tokens[idx] { idx += 1; return v }
                    if case .flag(let b) = tokens[idx] { idx += 1; return b ? 1 : 0 }
                    break
                }
                return 0
            }
            func nextFlag() -> Bool {
                while idx < tokens.count {
                    if case .flag(let b) = tokens[idx] { idx += 1; return b }
                    if case .num(let v) = tokens[idx] { idx += 1; return v != 0 }
                    break
                }
                return false
            }
            func abs(_ p: CGPoint) -> CGPoint {
                relative ? CGPoint(x: curPt.x + p.x, y: curPt.y + p.y) : p
            }
            func finishSubpath(close: Bool) {
                if !current.isEmpty {
                    subpaths.append(SubPath(segments: current, isClosed: close))
                    current = []
                }
            }
            // Append a cubic bezier segment [curPt → ep] via cp1, cp2.
            func cubicTo(_ cp1: CGPoint, _ cp2: CGPoint, _ ep: CGPoint) {
                current.append(BezierSeg(p0: curPt, p1: cp1, p2: cp2, p3: ep))
                lastCP2 = cp2
                lastQCP = ep
                curPt   = ep
            }

            while idx < tokens.count {
                if case .cmd(let c) = tokens[idx] {
                    cmd = c
                    relative = c.isLowercase
                    idx += 1
                }

                switch cmd {

                case "M", "m":
                    finishSubpath(close: false)
                    let x = nextNum(), y = nextNum()
                    curPt   = abs(CGPoint(x: x, y: y))
                    startPt = curPt
                    // Subsequent coordinate pairs after M are implicit L commands.
                    cmd = relative ? "l" : "L"

                case "Z", "z":
                    if curPt != startPt {
                        let cp1 = lerp(curPt, startPt, t: 1.0/3.0)
                        let cp2 = lerp(curPt, startPt, t: 2.0/3.0)
                        cubicTo(cp1, cp2, startPt)
                    }
                    finishSubpath(close: true)
                    curPt = startPt
                    // Z does not update cmd; next iteration continues

                case "L", "l":
                    let ep = abs(CGPoint(x: nextNum(), y: nextNum()))
                    let cp1 = lerp(curPt, ep, t: 1.0/3.0)
                    let cp2 = lerp(curPt, ep, t: 2.0/3.0)
                    cubicTo(cp1, cp2, ep)

                case "H", "h":
                    let x  = relative ? curPt.x + nextNum() : nextNum()
                    let ep = CGPoint(x: x, y: curPt.y)
                    let cp1 = lerp(curPt, ep, t: 1.0/3.0)
                    let cp2 = lerp(curPt, ep, t: 2.0/3.0)
                    cubicTo(cp1, cp2, ep)

                case "V", "v":
                    let y  = relative ? curPt.y + nextNum() : nextNum()
                    let ep = CGPoint(x: curPt.x, y: y)
                    let cp1 = lerp(curPt, ep, t: 1.0/3.0)
                    let cp2 = lerp(curPt, ep, t: 2.0/3.0)
                    cubicTo(cp1, cp2, ep)

                case "C", "c":
                    let cp1 = abs(CGPoint(x: nextNum(), y: nextNum()))
                    let cp2 = abs(CGPoint(x: nextNum(), y: nextNum()))
                    let ep  = abs(CGPoint(x: nextNum(), y: nextNum()))
                    cubicTo(cp1, cp2, ep)

                case "S", "s":
                    // Smooth cubic: cp1 is reflection of previous cp2.
                    let prevCP2Reflected = CGPoint(x: 2*curPt.x - lastCP2.x,
                                                   y: 2*curPt.y - lastCP2.y)
                    let cp2 = abs(CGPoint(x: nextNum(), y: nextNum()))
                    let ep  = abs(CGPoint(x: nextNum(), y: nextNum()))
                    cubicTo(prevCP2Reflected, cp2, ep)

                case "Q", "q":
                    // Quadratic → cubic degree elevation.
                    let qcp = abs(CGPoint(x: nextNum(), y: nextNum()))
                    let ep  = abs(CGPoint(x: nextNum(), y: nextNum()))
                    let cp1 = lerp(curPt, qcp, t: 2.0/3.0)
                    let cp2 = lerp(ep,    qcp, t: 2.0/3.0)
                    lastQCP = qcp
                    cubicTo(cp1, cp2, ep)

                case "T", "t":
                    // Smooth quadratic: control is reflection of previous Q control.
                    let qcp: CGPoint
                    if "QqTt".contains(lastCmd) {
                        qcp = CGPoint(x: 2*curPt.x - lastQCP.x, y: 2*curPt.y - lastQCP.y)
                    } else {
                        qcp = curPt
                    }
                    let ep  = abs(CGPoint(x: nextNum(), y: nextNum()))
                    let cp1 = lerp(curPt, qcp, t: 2.0/3.0)
                    let cp2 = lerp(ep,    qcp, t: 2.0/3.0)
                    lastQCP = qcp
                    cubicTo(cp1, cp2, ep)

                case "A", "a":
                    let rx = Swift.abs(nextNum())
                    let ry = Swift.abs(nextNum())
                    let xRot     = nextNum()
                    let largeArc = nextFlag()
                    let sweep    = nextFlag()
                    let ep       = abs(CGPoint(x: nextNum(), y: nextNum()))
                    let segs = arcToCubics(from: curPt, to: ep,
                                           rx: rx, ry: ry, xRot: xRot,
                                           largeArc: largeArc, sweep: sweep)
                    for s in segs { cubicTo(s.p1, s.p2, s.p3) }

                default:
                    // Unknown command — skip one number to avoid infinite loops.
                    idx += 1
                }

                lastCmd = cmd
            }

            finishSubpath(close: false)
            return subpaths
        }

        // MARK: - Arc to cubic approximation
        //
        // Implements the W3C SVG 1.1 spec Appendix F.6 endpoint-to-centre conversion,
        // then approximates each ≤90° arc segment with a cubic Bézier.

        private static func arcToCubics(
            from p1: CGPoint, to p2: CGPoint,
            rx rxIn: Double, ry ryIn: Double, xRot: Double,
            largeArc: Bool, sweep: Bool
        ) -> [BezierSeg] {
            // Degenerate: endpoints coincide or zero radii → straight line.
            if p1 == p2 { return [] }
            var rx = rxIn, ry = ryIn
            if rx == 0 || ry == 0 {
                let cp1 = lerp(p1, p2, t: 1.0/3.0)
                let cp2 = lerp(p1, p2, t: 2.0/3.0)
                return [BezierSeg(p0: p1, p1: cp1, p2: cp2, p3: p2)]
            }

            let phi = xRot * .pi / 180.0
            let cosPhi = cos(phi), sinPhi = sin(phi)

            // Step 1: compute (x1', y1') — midpoint rotated
            let dx = (Double(p1.x) - Double(p2.x)) / 2
            let dy = (Double(p1.y) - Double(p2.y)) / 2
            let x1p =  cosPhi * dx + sinPhi * dy
            let y1p = -sinPhi * dx + cosPhi * dy

            // Ensure radii are large enough (scale up if needed).
            let x1pSq = x1p * x1p, y1pSq = y1p * y1p
            let rxSq  = rx * rx,   rySq  = ry * ry
            let lambda = x1pSq / rxSq + y1pSq / rySq
            if lambda > 1 {
                let sqrtL = sqrt(lambda)
                rx *= sqrtL; ry *= sqrtL
            }
            let rxSq2 = rx*rx, rySq2 = ry*ry

            // Step 2: compute (cx', cy')
            let num = rxSq2 * rySq2 - rxSq2 * y1pSq - rySq2 * x1pSq
            let den = rxSq2 * y1pSq + rySq2 * x1pSq
            let sq  = den == 0 ? 0 : sqrt(Swift.max(0, num / den))
            let sign: Double = (largeArc == sweep) ? -1 : 1
            let cxp =  sign * sq * rx * y1p / ry
            let cyp = -sign * sq * ry * x1p / rx

            // Step 3: (cx, cy) in original coords
            let midX = (Double(p1.x) + Double(p2.x)) / 2
            let midY = (Double(p1.y) + Double(p2.y)) / 2
            let cx = cosPhi * cxp - sinPhi * cyp + midX
            let cy = sinPhi * cxp + cosPhi * cyp + midY

            // Step 4: compute θ1 and dθ
            func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
                let dot  = ux*vx + uy*vy
                let len  = sqrt(ux*ux + uy*uy) * sqrt(vx*vx + vy*vy)
                var a    = acos(Swift.max(-1, Swift.min(1, len > 0 ? dot/len : 0)))
                if ux*vy - uy*vx < 0 { a = -a }
                return a
            }

            let theta1 = angle(1, 0, (x1p - cxp)/rx, (y1p - cyp)/ry)
            var dTheta = angle((x1p - cxp)/rx, (y1p - cyp)/ry,
                               (-x1p - cxp)/rx, (-y1p - cyp)/ry)
            if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
            if  sweep && dTheta < 0 { dTheta += 2 * .pi }

            // Split into segments of at most 90°.
            let nSegs = Swift.max(1, Int(ceil(Swift.abs(dTheta) / (.pi / 2))))
            let dt    = dTheta / Double(nSegs)

            var segments: [BezierSeg] = []
            var prevPt = p1
            for i in 0..<nSegs {
                let t0 = theta1 + dt * Double(i)
                let t1 = t0 + dt
                // Cubic Bézier magic factor for circular arc approximation.
                let k   = (4.0/3.0) * tan(dt / 4.0)
                // Points on the ellipse at t0 and t1 (in ellipse local space).
                let cos0 = cos(t0), sin0 = sin(t0)
                let cos1 = cos(t1), sin1 = sin(t1)

                func ellipsePt(_ cosT: Double, _ sinT: Double) -> CGPoint {
                    let ex = rx * cosT
                    let ey = ry * sinT
                    let x  = cosPhi*ex - sinPhi*ey + cx
                    let y  = sinPhi*ex + cosPhi*ey + cy
                    return CGPoint(x: x, y: y)
                }
                func ellipseTan(_ cosT: Double, _ sinT: Double) -> CGPoint {
                    // Tangent direction (unscaled) at this angle.
                    let tx = -rx * sinT
                    let ty =  ry * cosT
                    let x  = cosPhi*tx - sinPhi*ty
                    let y  = sinPhi*tx + cosPhi*ty
                    return CGPoint(x: x, y: y)
                }

                let ep0  = prevPt
                let ep3  = ellipsePt(cos1, sin1)
                let tan0 = ellipseTan(cos0, sin0)
                let tan1 = ellipseTan(cos1, sin1)
                let ep1  = CGPoint(x: ep0.x + CGFloat(k) * tan0.x,
                                   y: ep0.y + CGFloat(k) * tan0.y)
                let ep2  = CGPoint(x: ep3.x - CGFloat(k) * tan1.x,
                                   y: ep3.y - CGFloat(k) * tan1.y)

                segments.append(BezierSeg(p0: ep0, p1: ep1, p2: ep2, p3: ep3))
                prevPt = ep3
            }
            return segments
        }

        // MARK: Helpers

        private static func lerp(_ a: CGPoint, _ b: CGPoint, t: Double) -> CGPoint {
            CGPoint(x: a.x + CGFloat(t) * (b.x - a.x),
                    y: a.y + CGFloat(t) * (b.y - a.y))
        }
    }
}

// MARK: - Error

enum LoomSVGImportError: LocalizedError {
    case unreadable
    case noPathsFound

    var errorDescription: String? {
        switch self {
        case .unreadable:    return "The SVG file could not be read."
        case .noPathsFound:  return "No path data found in the SVG file. Make sure text has been converted to paths in Inkscape (Object > Object to Path) before exporting."
        }
    }
}

