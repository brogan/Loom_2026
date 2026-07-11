import Foundation

/// The n-gon Graft operator (Specs/GeometricLifecycle.md §4.4.8) — a generalization
/// of Generational Evolution's Extrude/Split operators, parameterized by the number
/// of sides of the primitive being grafted rather than two separately hand-built
/// shapes. **Step 1 only** (§4.4.8.6): n-gon generation + distortion, proven in
/// isolation. No attachment yet — `generatePrimitive` returns a freestanding piece
/// in its own local frame, not yet placed against any parent geometry, and this
/// isn't called from `GenerationalEvolutionEngine.applyGeneration` yet.
///
/// Deliberately reuses Assembly Fulguration's existing machinery (§5.12) rather
/// than re-deriving it — `AssemblyPrimitiveKit.plainPolygon(sides:)` (relaxed from
/// `private` to internal for this) already generates an arbitrary-sided plain
/// polygon, and `.deformed` already applies the independent x/y "stretch and
/// squash" this needs. The only new logic here is the n≤2→line degeneracy and the
/// RPSR sampling of `n` and distortion from `EvolutionParams`.
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

        let piece = AssemblyPrimitiveKit.deformed(base, scaleX: sx, scaleY: sy)
        return GeneratedPrimitive(piece: piece, sides: sides)
    }
}
