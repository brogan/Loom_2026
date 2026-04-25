import Foundation

/// 1-D smooth noise in `[-1, 1]`.
///
/// Uses Catmull-Rom interpolation between `numCtrl` uniformly-spaced random
/// control values seeded by `seed`.  `phase` shifts the sampling window so
/// the same seed animates smoothly frame-to-frame.
///
/// Direct port of the Scala `SmoothNoise` object.
enum SmoothNoise {

    static func sample(x: Double, numCtrl: Int, seed: UInt64, phase: Double) -> Double {
        let n = max(2, numCtrl)

        // Generate control values deterministically from seed.
        var v = [Double](repeating: 0, count: n)
        var rng = SeedRNG(seed: seed)
        for i in 0..<n { v[i] = rng.next() * 2.0 - 1.0 }

        let xw  = ((x + phase).truncatingRemainder(dividingBy: 1.0) + 1.0)
                  .truncatingRemainder(dividingBy: 1.0)
        let pos = xw * Double(n - 1)
        let i0  = min(Int(pos), n - 2)
        let t   = pos - Double(i0)

        let va = v[max(0,     i0 - 1)]
        let vb = v[i0]
        let vc = v[i0 + 1]
        let vd = v[min(n - 1, i0 + 2)]

        let t2 = t * t, t3 = t2 * t
        let r  = 0.5 * ((2*vb) + (-va+vc)*t + (2*va-5*vb+4*vc-vd)*t2 + (-va+3*vb-3*vc+vd)*t3)
        return max(-1.0, min(1.0, r))
    }
}

// MARK: - Minimal seeded RNG (LCG — matches Scala's scala.util.Random seed behaviour)

private struct SeedRNG {
    private var state: UInt64

    init(seed: UInt64) {
        // Match Scala Random: seed is XOR-mixed with a constant before use.
        state = seed ^ 0x5DEECE66D
    }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let bits = UInt32(state >> 33)
        return Double(bits) / Double(UInt32.max)
    }
}
