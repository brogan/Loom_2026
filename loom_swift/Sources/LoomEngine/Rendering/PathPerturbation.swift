import Foundation

// MARK: - PerturbedPath

/// A perturbed version of one `BrushEdge`, stored as Catmull-Rom sample points.
///
/// `evaluate(t:)` returns `(position, tangentAngle, scaleEnvelope)` at parameter
/// `t ∈ [0,1]` along the perturbed path.
struct PerturbedPath {
    private let pts:      [Vector2D]   // n+1 sample points
    private let scaleEnv: [Double]     // scale envelope at each sample
    let length: Double

    init(pts: [Vector2D], scaleEnv: [Double], length: Double) {
        self.pts      = pts
        self.scaleEnv = scaleEnv
        self.length   = length
    }

    private var n: Int { pts.count - 1 }

    func evaluate(t: Double) -> (position: Vector2D, angle: Double, scale: Double) {
        let tc  = max(0.0, min(1.0, t))
        let pos = tc * Double(n)
        let seg = min(Int(pos), n - 1)
        let lt  = pos - Double(seg)

        let p0 = pts[max(0, seg - 1)]
        let p1 = pts[seg]
        let p2 = pts[seg + 1]
        let p3 = pts[min(n, seg + 2)]

        let position = crPoint(p0, p1, p2, p3, lt)
        let tangent  = crTangent(p0, p1, p2, p3, lt)
        let angle    = atan2(tangent.y, tangent.x)

        let sA    = scaleEnv[seg]
        let sB    = scaleEnv[seg + 1]
        let scale = sA + (sB - sA) * lt

        return (position, angle, scale)
    }

    private func crPoint(_ p0: Vector2D, _ p1: Vector2D, _ p2: Vector2D, _ p3: Vector2D, _ t: Double) -> Vector2D {
        let t2 = t*t, t3 = t2*t
        let x = 0.5*((2*p1.x)+(-p0.x+p2.x)*t+(2*p0.x-5*p1.x+4*p2.x-p3.x)*t2+(-p0.x+3*p1.x-3*p2.x+p3.x)*t3)
        let y = 0.5*((2*p1.y)+(-p0.y+p2.y)*t+(2*p0.y-5*p1.y+4*p2.y-p3.y)*t2+(-p0.y+3*p1.y-3*p2.y+p3.y)*t3)
        return Vector2D(x: x, y: y)
    }

    private func crTangent(_ p0: Vector2D, _ p1: Vector2D, _ p2: Vector2D, _ p3: Vector2D, _ t: Double) -> Vector2D {
        let t2 = t*t
        let dx = 0.5*((-p0.x+p2.x)+2*(2*p0.x-5*p1.x+4*p2.x-p3.x)*t+3*(-p0.x+3*p1.x-3*p2.x+p3.x)*t2)
        let dy = 0.5*((-p0.y+p2.y)+2*(2*p0.y-5*p1.y+4*p2.y-p3.y)*t+3*(-p0.y+3*p1.y-3*p2.y+p3.y)*t2)
        let len = sqrt(dx*dx + dy*dy)
        return len < 1e-9 ? Vector2D(x: 1, y: 0) : Vector2D(x: dx/len, y: dy/len)
    }
}

// MARK: - PathPerturbation

/// Computes a `PerturbedPath` for one `BrushEdge` using `MeanderConfig`.
enum PathPerturbation {

    static func perturb(
        edge:          BrushEdge,
        config:        MeanderConfig,
        edgeIndex:     Int,
        elapsedFrames: Double,
        scaleMin:      Double,
        scaleMax:      Double
    ) -> PerturbedPath {
        // When meander is disabled return a straight path sampled directly from
        // the edge geometry — no noise displacement, uniform scale envelope.
        guard config.enabled else {
            return straightPath(edge: edge, scaleMin: scaleMin, scaleMax: scaleMax)
        }

        let n = max(4, config.samples)

        let baseSeed: UInt64 = config.seed == 0
            ? UInt64(bitPattern: Int64(edgeIndex) &* 2_654_435_761)
            : UInt64(bitPattern: Int64(config.seed + edgeIndex) &* 2_654_435_761)

        let phase = config.animated ? (elapsedFrames * config.animSpeed).truncatingRemainder(dividingBy: 1.0) : 0.0

        let numNoise = max(2, Int(config.frequency * edge.length))
        let numScale = max(2, Int(config.scaleAlongPathFrequency * edge.length))

        var pts      = [Vector2D](repeating: .zero, count: n + 1)
        var scaleEnv = [Double](repeating: 0, count: n + 1)

        for i in 0...n {
            let t = Double(i) / Double(n)
            let (origPos, origAngle) = sampleEdge(edge, t: t)

            let taper    = sin(.pi * t)
            let noise    = SmoothNoise.sample(x: t, numCtrl: numNoise, seed: baseSeed, phase: phase)
            let disp     = config.amplitude * noise * taper

            let normalAngle = origAngle + .pi / 2.0
            pts[i] = Vector2D(
                x: origPos.x + disp * cos(normalAngle),
                y: origPos.y + disp * sin(normalAngle)
            )

            let sNoise      = SmoothNoise.sample(x: t, numCtrl: numScale, seed: baseSeed &+ 1, phase: 0.0)
            let envelope    = (sNoise + 1.0) / 2.0
            let scaleCenter = (scaleMin + scaleMax) / 2.0
            let halfRange   = (scaleMax - scaleMin) * config.scaleAlongPathRange / 2.0
            scaleEnv[i] = max(scaleMin, min(scaleMax, scaleCenter + (envelope - 0.5) * 2.0 * halfRange))
        }

        var totalLen = 0.0
        for i in 0..<n {
            let d = pts[i + 1] - pts[i]
            totalLen += sqrt(d.x*d.x + d.y*d.y)
        }

        return PerturbedPath(pts: pts, scaleEnv: scaleEnv, length: max(totalLen, 0.1))
    }

    // MARK: - Straight (unperturbed) path

    /// Returns a `PerturbedPath` that exactly follows the raw edge geometry with
    /// no noise displacement and a flat scale envelope at the midpoint of
    /// [scaleMin, scaleMax].  Used when `MeanderConfig.enabled == false`.
    private static func straightPath(
        edge:     BrushEdge,
        scaleMin: Double,
        scaleMax: Double
    ) -> PerturbedPath {
        let n = 16   // enough samples for smooth tangent interpolation
        let midScale = (scaleMin + scaleMax) / 2.0
        var pts      = [Vector2D](repeating: .zero, count: n + 1)
        var scaleEnv = [Double](repeating: midScale, count: n + 1)
        for i in 0...n {
            let t = Double(i) / Double(n)
            let (pos, _) = sampleEdge(edge, t: t)
            pts[i] = pos
        }
        var totalLen = 0.0
        for i in 0..<n {
            let d = pts[i + 1] - pts[i]
            totalLen += sqrt(d.x * d.x + d.y * d.y)
        }
        return PerturbedPath(pts: pts, scaleEnv: scaleEnv, length: max(totalLen, 0.1))
    }

    // MARK: - Edge sampling

    static func sampleEdge(_ edge: BrushEdge, t: Double) -> (Vector2D, Double) {
        switch edge.kind {
        case .line:
            let p0 = edge.points[0], p1 = edge.points[1]
            let pos = Vector2D(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t)
            return (pos, atan2(p1.y - p0.y, p1.x - p0.x))
        case .spline:
            let a0 = edge.points[0], c0 = edge.points[1]
            let c1 = edge.points[2], a1 = edge.points[3]
            return (bezierPoint(a0, c0, c1, a1, t), bezierAngle(a0, c0, c1, a1, t))
        }
    }

    private static func bezierPoint(_ a0: Vector2D, _ c0: Vector2D, _ c1: Vector2D, _ a1: Vector2D, _ t: Double) -> Vector2D {
        let mt = 1.0 - t
        return Vector2D(
            x: mt*mt*mt*a0.x + 3*mt*mt*t*c0.x + 3*mt*t*t*c1.x + t*t*t*a1.x,
            y: mt*mt*mt*a0.y + 3*mt*mt*t*c0.y + 3*mt*t*t*c1.y + t*t*t*a1.y
        )
    }

    private static func bezierAngle(_ a0: Vector2D, _ c0: Vector2D, _ c1: Vector2D, _ a1: Vector2D, _ t: Double) -> Double {
        let mt = 1.0 - t
        let dx = 3*mt*mt*(c0.x-a0.x) + 6*mt*t*(c1.x-c0.x) + 3*t*t*(a1.x-c1.x)
        let dy = 3*mt*mt*(c0.y-a0.y) + 6*mt*t*(c1.y-c0.y) + 3*t*t*(a1.y-c1.y)
        return atan2(dy, dx)
    }
}
