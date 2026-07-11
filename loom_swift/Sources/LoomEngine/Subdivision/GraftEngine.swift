import Foundation

/// The n-gon Graft operator (Specs/GeometricLifecycle.md §4.4.8) — a generalization
/// of Generational Evolution's Extrude/Split operators, parameterized by the number
/// of sides of the primitive being grafted rather than two separately hand-built
/// shapes. `generatePrimitive` builds one freestanding piece (n-gon generation,
/// distortion, overall scale) in its own local frame — attachment to the parent
/// happens afterward, in `GenerationalEvolutionEngine`'s three `applyGraft*`
/// functions.
///
/// Deliberately reuses Assembly Fulguration's existing machinery (§5.12) rather
/// than re-deriving it — `AssemblyPrimitiveKit.plainPolygon(sides:)` (relaxed from
/// `private` to internal for this) already generates an arbitrary-sided plain
/// polygon, and `.deformed` already applies the independent x/y "stretch and
/// squash" this needs. The only new logic here is the n≤2→line degeneracy and the
/// RPSR sampling of `n`, distortion, and overall scale from `EvolutionParams`.
enum GraftEngine {

    /// One generated Graft primitive, before any attachment: the piece itself (in
    /// its own local frame, centered on the origin) and the side count actually
    /// used (after n≤2 degeneracy), useful for callers/tests that need to know
    /// which primitive kind was rolled without re-deriving it from the geometry.
    struct GeneratedPrimitive: Equatable {
        var piece: Polygon2D
        var sides: Int
    }

    /// Generates one primitive: `n` is RPSR-sampled from `graftSidesMin/Max`, then
    /// independently x/y-distorted from `graftDistortionMin/Max`.
    ///
    /// `n≤2` degenerates to `AssemblyPrimitiveKit`'s `.line` primitive — there is
    /// no meaningful closed 2-sided polygon, so both n=1 (the deliberate base case,
    /// per §4.4.8.1: "the most basic type is not a polygon but a line") and n=2
    /// (which would otherwise be a degenerate sliver) resolve to the same open
    /// straight segment. `n≥3` calls `AssemblyPrimitiveKit.plainPolygon(sides:)`
    /// directly, which is not limited to the fixed `AssemblyPrimitiveKind` cases
    /// (square/triangle/pentagon) the way Assembly Fulguration's own callers are —
    /// any `n` is reachable.
    ///
    /// `seed`/`rollBase` follow the same "distinct roll-index namespace per caller"
    /// convention already used throughout this engine (e.g. `AssemblyFulgurationEngine
    /// .assemble`'s `cycleIndex * rollStride`) — three small fixed offsets
    /// (`rollBase + 0/1/2`) are all this needs, since it doesn't yet need to
    /// interoperate with `GenerationalEvolutionEngine.applyGeneration`'s own
    /// `cycleBase` numbering (that wiring is step 2, once there's an attachment
    /// mode to place the result with).
    static func generatePrimitive(
        seed:     Int,
        rollBase: Int,
        params:   EvolutionParams
    ) -> GeneratedPrimitive {
        let sidesLo = min(params.graftSidesMin, params.graftSidesMax)
        let sidesHi = max(params.graftSidesMin, params.graftSidesMax)
        let sidesRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 0)
        let sides = max(1, sidesLo + Int(sidesRoll * Double(sidesHi - sidesLo + 1)))

        let base: Polygon2D = sides <= 2
            ? AssemblyPrimitiveKit.generate(.line)
            : AssemblyPrimitiveKit.plainPolygon(sides: sides)

        let distLo = min(params.graftDistortionMin, params.graftDistortionMax)
        let distHi = max(params.graftDistortionMin, params.graftDistortionMax)
        let sxRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 1)
        let syRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 2)
        let sx = distLo + sxRoll * (distHi - distLo)
        let sy = distLo + syRoll * (distHi - distLo)

        // Uniform overall-size multiplier, independent of the per-axis distortion
        // above — `plainPolygon`/`straightLine` are generated at a fixed unit size
        // regardless of the target geometry's own scale, so without this a graft
        // has no way to be sized down (or up) to match. Own salted seed rather than
        // a fourth `rollBase+N` slot: `rollBase` is reused as the *cycle* argument
        // on this distinct seed, so it can't collide with the sides/distortion
        // rolls above (same `seed`, different cycles) or with any of the three
        // attachment functions' own `cycleBase+6/7/8` rolls (same `graftSeed`
        // passed in as this function's `seed`, but those are different cycles on
        // it too, and this is a wholly different seed regardless).
        let scaleLo = min(params.graftScaleMin, params.graftScaleMax)
        let scaleHi = max(params.graftScaleMin, params.graftScaleMax)
        let scaleSeed = seed &+ 812_374_601
        let scaleRoll = SubdivisionEngine.centreHash(seed: scaleSeed, cycle: rollBase)
        let scale = scaleLo + scaleRoll * (scaleHi - scaleLo)

        let piece = AssemblyPrimitiveKit.deformed(base, scaleX: scale * sx, scaleY: scale * sy)
        return GeneratedPrimitive(piece: piece, sides: sides)
    }
}
