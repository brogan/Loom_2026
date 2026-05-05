import Foundation
import LoomEngine

enum FreehandCurveFitter {
    private struct P {
        var x: Double
        var y: Double

        var vector: Vector2D { Vector2D(x: x / 1000.0, y: y / 1000.0) }
    }

    static func fit(_ points: [Vector2D], errorThreshold: Double) -> [Vector2D]? {
        var samples = removeDuplicates(points.map { P(x: $0.x * 1000.0, y: $0.y * 1000.0) })
        guard samples.count >= 2 else { return nil }
        samples = douglasPeucker(samples, epsilon: max(errorThreshold, 2.0))
        guard samples.count >= 2 else { return nil }

        let errorSquared = errorThreshold * errorThreshold
        var segments: [[P]] = []
        if samples.count == 2 {
            let p0 = samples[0]
            let p1 = samples[1]
            segments.append([
                p0,
                P(x: p0.x + (p1.x - p0.x) / 3.0, y: p0.y + (p1.y - p0.y) / 3.0),
                P(x: p0.x + 2.0 * (p1.x - p0.x) / 3.0, y: p0.y + 2.0 * (p1.y - p0.y) / 3.0),
                p1
            ])
        } else {
            fitCubic(
                samples,
                first: 0,
                last: samples.count - 1,
                leftTangent: leftTangent(samples, at: 0),
                rightTangent: rightTangent(samples, at: samples.count - 1),
                errorSquared: errorSquared,
                result: &segments
            )
        }
        return segments.flatMap { $0.map(\.vector) }
    }

    private static func distance(_ a: P, _ b: P) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func subtract(_ a: P, _ b: P) -> P {
        P(x: a.x - b.x, y: a.y - b.y)
    }

    private static func normalize(_ p: P) -> P {
        let length = hypot(p.x, p.y)
        guard length > 1e-10 else { return P(x: 1, y: 0) }
        return P(x: p.x / length, y: p.y / length)
    }

    private static func removeDuplicates(_ points: [P]) -> [P] {
        var result: [P] = []
        for point in points where result.last.map({ distance($0, point) > 0.01 }) ?? true {
            result.append(point)
        }
        return result
    }

    private static func pointToLineDistance(_ p: P, _ a: P, _ b: P) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-12 else { return distance(p, a) }
        let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
        let cx = a.x + t * dx
        let cy = a.y + t * dy
        return hypot(p.x - cx, p.y - cy)
    }

    private static func douglasPeucker(_ points: [P], epsilon: Double) -> [P] {
        guard points.count > 2 else { return points }
        var maxDistance = 0.0
        var maxIndex = 1
        for index in 1..<(points.count - 1) {
            let d = pointToLineDistance(points[index], points[0], points[points.count - 1])
            if d > maxDistance {
                maxDistance = d
                maxIndex = index
            }
        }
        guard maxDistance > epsilon else { return [points[0], points[points.count - 1]] }
        let left = douglasPeucker(Array(points[0...maxIndex]), epsilon: epsilon)
        let right = douglasPeucker(Array(points[maxIndex..<points.count]), epsilon: epsilon)
        return left + right.dropFirst()
    }

    private static func chordLengthParameters(_ points: [P], first: Int, last: Int) -> [Double] {
        var values = Array(repeating: 0.0, count: last - first + 1)
        for index in 1..<values.count {
            values[index] = values[index - 1] + distance(points[first + index - 1], points[first + index])
        }
        let total = values.last ?? 0
        if total > 0 {
            values = values.map { $0 / total }
        }
        values[values.count - 1] = 1.0
        return values
    }

    private static func generateBezier(_ points: [P], first: Int, last: Int, parameters: [Double], leftTangent: P, rightTangent: P) -> [P] {
        let p0 = points[first]
        let p3 = points[last]
        var c00 = 0.0
        var c01 = 0.0
        var c11 = 0.0
        var x0 = 0.0
        var x1 = 0.0

        for i in parameters.indices {
            let t = parameters[i]
            let b0 = basis0(t)
            let b1 = basis1(t)
            let b2 = basis2(t)
            let b3 = basis3(t)
            let a1 = P(x: leftTangent.x * b1, y: leftTangent.y * b1)
            let a2 = P(x: rightTangent.x * b2, y: rightTangent.y * b2)
            c00 += a1.x * a1.x + a1.y * a1.y
            c01 += a1.x * a2.x + a1.y * a2.y
            c11 += a2.x * a2.x + a2.y * a2.y
            let point = points[first + i]
            let tx = point.x - (b0 * p0.x + b3 * p3.x)
            let ty = point.y - (b0 * p0.y + b3 * p3.y)
            x0 += a1.x * tx + a1.y * ty
            x1 += a2.x * tx + a2.y * ty
        }

        let determinant = c00 * c11 - c01 * c01
        let alpha1: Double
        let alpha2: Double
        if abs(determinant) > 1e-12 {
            alpha1 = (x0 * c11 - c01 * x1) / determinant
            alpha2 = (c00 * x1 - x0 * c01) / determinant
        } else {
            alpha1 = distance(p0, p3) / 3.0
            alpha2 = alpha1
        }

        let fallback = distance(p0, p3) / 3.0
        let a1 = alpha1 < 1e-6 ? fallback : alpha1
        let a2 = alpha2 < 1e-6 ? fallback : alpha2
        return [
            p0,
            P(x: p0.x + leftTangent.x * a1, y: p0.y + leftTangent.y * a1),
            P(x: p3.x + rightTangent.x * a2, y: p3.y + rightTangent.y * a2),
            p3
        ]
    }

    private static func maxError(_ points: [P], first: Int, last: Int, bezier: [P], parameters: [Double]) -> (Double, Int) {
        var maxDistance = 0.0
        var split = (first + last) / 2
        for index in (first + 1)..<last {
            let point = bezierPoint(bezier, t: parameters[index - first])
            let dx = point.x - points[index].x
            let dy = point.y - points[index].y
            let d = dx * dx + dy * dy
            if d > maxDistance {
                maxDistance = d
                split = index
            }
        }
        return (maxDistance, split)
    }

    private static func fitCubic(_ points: [P], first: Int, last: Int, leftTangent: P, rightTangent: P, errorSquared: Double, result: inout [[P]]) {
        if last - first == 1 {
            let p0 = points[first]
            let p1 = points[last]
            let dist = distance(p0, p1) / 3.0
            result.append([
                p0,
                P(x: p0.x + leftTangent.x * dist, y: p0.y + leftTangent.y * dist),
                P(x: p1.x + rightTangent.x * dist, y: p1.y + rightTangent.y * dist),
                p1
            ])
            return
        }

        let parameters = chordLengthParameters(points, first: first, last: last)
        let bezier = generateBezier(points, first: first, last: last, parameters: parameters, leftTangent: leftTangent, rightTangent: rightTangent)
        var (maxDistance, split) = maxError(points, first: first, last: last, bezier: bezier, parameters: parameters)
        if maxDistance < errorSquared, !wouldLoop(bezier) {
            result.append(bezier)
            return
        }

        if !wouldLoop(bezier), maxDistance < errorSquared * 4.0 {
            let reparameterized = parameters.enumerated().map { index, t in
                newtonRaphson(bezier: bezier, point: points[first + index], t: t)
            }
            let bezier2 = generateBezier(points, first: first, last: last, parameters: reparameterized, leftTangent: leftTangent, rightTangent: rightTangent)
            let second = maxError(points, first: first, last: last, bezier: bezier2, parameters: reparameterized)
            maxDistance = second.0
            split = second.1
            if maxDistance < errorSquared, !wouldLoop(bezier2) {
                result.append(bezier2)
                return
            }
        }

        let centre = centerTangent(points, at: split)
        fitCubic(points, first: first, last: split, leftTangent: leftTangent, rightTangent: centre, errorSquared: errorSquared, result: &result)
        fitCubic(points, first: split, last: last, leftTangent: P(x: -centre.x, y: -centre.y), rightTangent: rightTangent, errorSquared: errorSquared, result: &result)
    }

    private static func leftTangent(_ points: [P], at index: Int) -> P {
        normalize(subtract(points[index + 1], points[index]))
    }

    private static func rightTangent(_ points: [P], at index: Int) -> P {
        normalize(subtract(points[index - 1], points[index]))
    }

    private static func centerTangent(_ points: [P], at index: Int) -> P {
        normalize(subtract(points[index - 1], points[index + 1]))
    }

    private static func wouldLoop(_ bezier: [P]) -> Bool {
        let arm1 = distance(bezier[0], bezier[1])
        let arm2 = distance(bezier[3], bezier[2])
        let chord = distance(bezier[0], bezier[3])
        return chord > 1.0 && (arm1 + arm2) > chord
    }

    private static func newtonRaphson(bezier: [P], point: P, t: Double) -> Double {
        let q = bezierPoint(bezier, t: t)
        let q1 = bezierTangent(bezier, t: t)
        let q2 = bezierSecondDerivative(bezier, t: t)
        let numerator = (q.x - point.x) * q1.x + (q.y - point.y) * q1.y
        let denominator = q1.x * q1.x + q1.y * q1.y + (q.x - point.x) * q2.x + (q.y - point.y) * q2.y
        guard abs(denominator) > 1e-12 else { return t }
        return min(max(t - numerator / denominator, 0), 1)
    }

    private static func bezierPoint(_ b: [P], t: Double) -> P {
        let b0 = basis0(t), b1 = basis1(t), b2 = basis2(t), b3 = basis3(t)
        return P(
            x: b0 * b[0].x + b1 * b[1].x + b2 * b[2].x + b3 * b[3].x,
            y: b0 * b[0].y + b1 * b[1].y + b2 * b[2].y + b3 * b[3].y
        )
    }

    private static func bezierTangent(_ b: [P], t: Double) -> P {
        let mt = 1.0 - t
        let k0 = 3.0 * mt * mt
        let k1 = 6.0 * mt * t
        let k2 = 3.0 * t * t
        return P(
            x: k0 * (b[1].x - b[0].x) + k1 * (b[2].x - b[1].x) + k2 * (b[3].x - b[2].x),
            y: k0 * (b[1].y - b[0].y) + k1 * (b[2].y - b[1].y) + k2 * (b[3].y - b[2].y)
        )
    }

    private static func bezierSecondDerivative(_ b: [P], t: Double) -> P {
        let mt = 1.0 - t
        return P(
            x: 6.0 * mt * (b[2].x - 2.0 * b[1].x + b[0].x) + 6.0 * t * (b[3].x - 2.0 * b[2].x + b[1].x),
            y: 6.0 * mt * (b[2].y - 2.0 * b[1].y + b[0].y) + 6.0 * t * (b[3].y - 2.0 * b[2].y + b[1].y)
        )
    }

    private static func basis0(_ t: Double) -> Double { let mt = 1.0 - t; return mt * mt * mt }
    private static func basis1(_ t: Double) -> Double { let mt = 1.0 - t; return 3.0 * mt * mt * t }
    private static func basis2(_ t: Double) -> Double { let mt = 1.0 - t; return 3.0 * mt * t * t }
    private static func basis3(_ t: Double) -> Double { t * t * t }
}
