import Foundation

public enum EvolutionOperationType: String, Codable, CaseIterable, Equatable, Sendable {
    case momentumDrift       = "Momentum Drift"
    case convergencePressure = "Convergence Pressure"
    /// Structural mutation across generations (artificial life) — see
    /// Specs/GeometricLifecycle.md §4.4. Unlike the other two, this operates on
    /// materialized `[Polygon2D]` geometry, not `SubdivisionParams` fields, so it
    /// is a no-op in `EvolutionEngine.apply` and is instead dispatched by
    /// `GenerationalEvolutionEngine` at its own point in the render pipeline
    /// (after Extension, before Dissolution — see `SpriteScene.swift`).
    case generational        = "Generational"
}

public enum DriftTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case lineRatioX    = "Line Ratio X"
    case lineRatioY    = "Line Ratio Y"
    case lineRatioXY   = "Line Ratio XY"
    case cpNormalX     = "CP Normal X"
    case cpNormalY     = "CP Normal Y"
    case insetScale    = "Inset Scale"
    case insetRotation = "Inset Rotation"

    /// Added 2026-07-10 — closes the gap where Momentum Drift had no effect on
    /// open curves (it only ever wrote to `SubdivisionParams` fields, which
    /// `SubdivisionEngine` bypasses entirely for `.openSpline`; see the design-note
    /// update in Specs/GeometricLifecycle.md §4.4). These three target
    /// `CurveRefinementParams`' base scalar fields instead — the open-curve
    /// analogue of the closed-polygon targets above.
    case curveDisplacement   = "Curve Displacement"
    case curveCPNormalOffset = "Curve CP Normal Offset"
    case curvePressure       = "Curve Pressure"

    /// True for the three curve-refinement targets above. `EvolutionEngine` uses
    /// this to route a Momentum Drift pass to `CurveRefinementParams` instead of
    /// `SubdivisionParams` — each pass still targets exactly one field, on
    /// whichever of the two arrays that field belongs to.
    public var isCurveTarget: Bool {
        switch self {
        case .curveDisplacement, .curveCPNormalOffset, .curvePressure: return true
        case .lineRatioX, .lineRatioY, .lineRatioXY, .cpNormalX, .cpNormalY, .insetScale, .insetRotation: return false
        }
    }
}

public enum ConvergenceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case hold      = "Hold"
    case oscillate = "Oscillate"
    case loop      = "Loop"
}

/// Specs/GeometricLifecycle.md §4.4.8.3 — how a Graft primitive's chosen
/// attachment site is placed against the parent polygon. `.wholeEdge`
/// (§4.4.8.6 step 2) and `.singlePoint` (step 3) match the parent's edge or a
/// single point exactly; `.partialEdge` (step 4) matches a sub-span of the
/// edge instead — see `graftPartialPositionMin/Max`/`graftPartialSpanMin/Max`.
public enum GraftAttachmentMode: String, Codable, CaseIterable, Equatable, Sendable {
    case wholeEdge   = "Whole Edge"
    case singlePoint = "Single Point"
    case partialEdge = "Partial Edge"
}

/// Specs/GeometricLifecycle.md §4.4.8.3 — where `.singlePoint` attachment's
/// shared coordinate comes from. `.existingVertex` is non-destructive to the
/// parent's topology (matches Extension's Branch/§4.4.7's curve-grafting
/// sketch); `.newlyInsertedPoint` splits the parent edge first (reusing
/// `splitPositionMin/Max`'s RPSR-position convention directly, matching
/// Split's own existing behavior) and attaches from the new anchor.
public enum GraftPointSource: String, Codable, CaseIterable, Equatable, Sendable {
    case existingVertex     = "Existing Vertex"
    case newlyInsertedPoint = "Newly Inserted Point"
}

/// Specs/GeometricLifecycle.md §4.4.8.4 — how a Graft edge's articulation
/// joints are displaced. `.jitter` is independent RPSR sign+magnitude per
/// joint; `.zigzag` alternates sign deterministically joint-to-joint (the
/// "zig zag" case from the original proposal) with RPSR-sampled magnitude
/// only. A small dedicated enum rather than extending `CurveDisplacementMode`
/// — that enum's `.lazy` (periodic-hold jitter) is close to but not the same
/// as a deterministic alternation, and the call site (one Graft edge, not a
/// whole `.openSpline` polygon) is different enough that sharing the enum
/// risked implying more code-sharing than actually exists.
public enum GraftArticulationPattern: String, Codable, CaseIterable, Equatable, Sendable {
    case jitter = "Jitter"
    case zigzag = "Zig Zag"
}

/// Where a Graft primitive's base shape comes from (2026-07-12). `.generated`
/// (default) is the original behavior — an RPSR-sampled n-gon/line from
/// `AssemblyPrimitiveKit`, unchanged. `.customSet` instead pulls a user-drawn
/// shape from the project's existing polygon/curve set library (the same
/// storage a sprite's own base geometry uses) — see `graftCustomShapes`.
public enum GraftPrimitiveSource: String, Codable, CaseIterable, Equatable, Sendable {
    case generated = "Generated"
    case customSet = "Custom Set"
}

/// §4.4.8.3 orientation control (2026-07-13) — which of a Graft piece's own
/// attachment sites is used as the connector to the parent. `.random`
/// (default) reproduces the original RPSR-uniform pick exactly. `.lowestPoint`
/// deterministically picks whichever site sits lowest (min Y, this engine's
/// Y-up convention) in the piece's own authored/local frame — the piece's
/// "bottom" as drawn in the geometry editor becomes the part that connects to
/// the parent, rather than an arbitrary edge/endpoint.
public enum GraftConnectorSelection: String, Codable, CaseIterable, Equatable, Sendable {
    case random      = "Random"
    case lowestPoint = "Lowest Point"
}

/// One shape entry in `graftCustomShapes` (2026-07-13) — a saved polygon/curve
/// set name, plus a relative selection weight used for a weighted-random draw
/// when `graftPrimitiveSource == .customSet` and multiple entries are present.
/// Named "probability" in the UI since values are meant to sit in [0, 1], but
/// these are relative weights, not independent per-shape odds — they need not
/// sum to 1 (two entries both at 1.0 split the roll 50/50, same as before this
/// existed; a weight of 0 excludes that entry from ever being picked while its
/// siblings remain eligible). `probability: 1.0` default reproduces the old
/// plain-`[String]` uniform pick exactly for any list where every entry is
/// left at its default.
public struct GraftCustomShapeEntry: Codable, Equatable, Sendable {
    public var name: String
    public var probability: Double

    public init(name: String, probability: Double = 1.0) {
        self.name = name
        self.probability = probability
    }
}

public struct EvolutionParams: Equatable, Codable, Sendable {
    public var name:          String
    public var enabled:       Bool
    public var operationType: EvolutionOperationType

    // Momentum drift (operationType == .momentumDrift)
    public var driftTarget:         DriftTarget
    public var driftMomentum:       Double   // 0–1; higher = smoother/slower changing drift
    public var driftNoiseStrength:  Double   // peak displacement amplitude
    public var driftNoiseFrequency: Double   // temporal noise rate (cycles per frame)
    public var driftSeed:           Int

    // Convergence pressure (operationType == .convergencePressure)
    public var convergenceTargetSetName: String
    public var convergencePressure:      DoubleDriver   // 0 = no effect, 1 = fully converged
    public var convergenceMode:          ConvergenceMode
    public var convergenceDuration:      Double         // frames for one oscillate/loop cycle

    // Generational (operationType == .generational) — see GenerationalEvolutionEngine.
    // Randomness (operator choice, target polygon, run length, distance) is drawn from
    // SubdivisionEngine.centreHash(seed:cycle:) keyed on generationSeed — deliberately
    // not DoubleDriver, which is a per-frame animation primitive; generation index is
    // a structural axis, not playback time.
    public var generationCount:       Int      // how many generations to run
    public var extrudeWeight:         Double   // relative selection weight; 0 excludes the operator
    public var splitWeight:           Double
    public var extrudeRunLengthMin:   Int      // contiguous edges extruded together, RPSR
    public var extrudeRunLengthMax:   Int
    public var extrudeDistanceMin:    Double   // RPSR outward distance
    public var extrudeDistanceMax:    Double

    /// false (default): both corners of an extruded edge are offset by the same
    /// sampled distance — a rectangular quad, original/unchanged behavior. true:
    /// each corner is independently RPSR-scaled from that distance (see
    /// `GenerationalEvolutionEngine.applyExtrude`'s asymmetry range), producing a
    /// tapered/wedge-shaped quad instead. Sampled per extruded edge, not once per
    /// run, so a multi-edge run doesn't lean uniformly one way.
    public var extrudeAsymmetricSides: Bool
    /// false (default): extrusion direction is exactly the edge's outward normal
    /// (perpendicular), original/unchanged behavior. true: direction is RPSR-tilted
    /// up to ±45° from perpendicular (45°–135° measured from the edge itself),
    /// sampled per extruded edge.
    public var extrudeAngleRandomized: Bool

    /// false (default): every operator's target pool is closed polygons (`.spline`)
    /// only, original/unchanged behavior. true: `.openSpline` polygons also become
    /// eligible targets for Extrude, Split, *and* Graft alike (Specs/
    /// GeometricLifecycle.md §4.4.6) — a general, pass-wide toggle, not an
    /// Extrude-specific one (renamed from `extrudeIncludeOpenCurves` when Split/Graft
    /// gained the same support; the old JSON key is still accepted on decode, see
    /// `init(from:)`, so existing saved projects keep working unchanged).
    /// `ExtensionEngine.outwardNormal` needs no change to support this — its
    /// rotate-90°-of-edge-direction formula never actually depended on the polygon
    /// having an interior; it's just no longer principled as "outward" for a curve,
    /// only as "one of its two sides" (see `GenerationalEvolutionEngine
    /// .openCurveSafeOutward`, which all three operators now route through for
    /// `.openSpline` targets).
    public var includeOpenCurves: Bool

    /// false (default): every eligible polygon (per `includeOpenCurves`'s type
    /// filter) is a valid target for Extrude/Split/Graft each generation, exactly
    /// as before this existed — including polygons a *previous* generation in
    /// this same pass appended (only Graft appends; Extrude/Split both mutate
    /// their target in place at its existing index, so a polygon present at the
    /// start of the pass is always targetable regardless of how many times it's
    /// since been extruded/split, whichever this is set to). true: targets are
    /// restricted to the polygons present when this pass started — a grafted
    /// piece, or anything appended by an earlier generation, can never itself
    /// become a target (2026-07-13). Motivating case: a grove of trees Graft-
    /// attached to a subdivided ground plane, where later generations should
    /// keep landing on the ground rather than occasionally grafting onto an
    /// already-placed tree. Chained evolution passes each treat their own
    /// starting geometry as "original" — this is a per-pass toggle, not a
    /// sprite-wide one.
    public var restrictTargetsToOriginalGeometry: Bool

    /// false (default): each eligible curve edge extrudes on exactly one RPSR-chosen
    /// side (§4.4.6 step 2 — a per-edge coin-flip between the edge's two
    /// perpendiculars). true: a *second*, independent per-edge roll additionally
    /// decides whether that edge extrudes on one side or both — "one or more sides"
    /// per §4.4.6's original framing. Extrude-specific (Split/Graft have no "both
    /// sides" analogue — Split makes one point, Graft attaches one piece). Has no
    /// effect on closed-polygon targets or when `includeOpenCurves` is off.
    public var extrudeOpenCurveBothSides: Bool

    /// Where along the target edge the split occurs (de Casteljau t-parameter,
    /// 0–1), RPSR-sampled per generation. 0.5–0.5 (default) = always the exact
    /// midpoint, original behavior unchanged. Clamped to [0.05, 0.95] regardless
    /// of the configured range so a degenerate near-zero-length sub-segment can't
    /// result from an extreme setting.
    public var splitPositionMin: Double
    public var splitPositionMax: Double

    public var splitDisplacementMin:  Double   // RPSR outward displacement of the new split anchor
    public var splitDisplacementMax:  Double

    /// Additional RPSR range (canvas-normalized units, independent of
    /// splitDisplacement above) applied to the two control points flanking a
    /// split's new anchor: positive pulls them *toward* the shape's centre
    /// relative to their un-displaced split position, which is what actually
    /// bulges the curve into a fuller, flared, rounder base; negative pushes them
    /// *away* from centre (toward/past the displaced anchor), straightening the
    /// sides into a sharper point/pinch. 0–0 (default) = original behavior,
    /// unchanged — the flanking control points stay exactly where
    /// `BezierMath.split` placed them. Sign verified 2026-07-10 by rendering both
    /// directions — see Specs/GeometricLifecycle.md §4.4.2's design-note update.
    public var splitBulgePinchMin: Double
    public var splitBulgePinchMax: Double

    // Graft (Specs/GeometricLifecycle.md §4.4.8) — step 1 (n-gon generation +
    // distortion) and step 2 (`.wholeEdge` attachment only) done so far. Wired
    // into `applyGeneration`'s operator selection alongside Extrude/Split via
    // `graftWeight`, defaulting to 0 so existing presets are unaffected until a
    // user opts in.

    /// RPSR-sampled side count `n` per Graft primitive. 1–4 (default) spans
    /// AssemblyPrimitiveKit's `.line` kind (n≤2, no meaningful 2-sided closed
    /// polygon so n=2 degenerates to the same line as n=1) through a plain
    /// quadrilateral. Widen past 4 for pentagons and beyond — `n` isn't limited to
    /// AssemblyPrimitiveKind's fixed cases the way Assembly Fulguration's own kit
    /// is, since Graft calls `AssemblyPrimitiveKit.plainPolygon(sides:)` directly.
    public var graftSidesMin: Int
    public var graftSidesMax: Int

    /// Independent per-axis RPSR scale range applied to each Graft primitive
    /// before attachment — the same `AssemblyPrimitiveKit.deformed` "stretch and
    /// squash" Assembly Fulguration's own pieces already use. 1–1 (default) = no
    /// distortion.
    public var graftDistortionMin: Double
    public var graftDistortionMax: Double

    /// Uniform RPSR scale multiplier applied to each Graft primitive, on top of
    /// (multiplied together with) the independent-axis Distortion above — Scale
    /// controls overall size, Distortion controls aspect ratio, independently.
    /// `AssemblyPrimitiveKit.plainPolygon`'s primitives are generated at a fixed
    /// unit size (~radius 0.5) regardless of the target geometry's own scale, so
    /// without this a graft can dwarf a small target shape with no way to correct
    /// it. 1–1 (default) = unit size, unchanged from before this field existed
    /// (equal min/max = a fixed, non-random scale).
    public var graftScaleMin: Double
    public var graftScaleMax: Double

    /// `.generated` (default) reproduces the original n-gon/line behavior
    /// exactly, unaffected by `graftCustomShapes` below. `.customSet` uses a
    /// user-drawn shape instead — see `graftCustomShapes`.
    public var graftPrimitiveSource: GraftPrimitiveSource

    /// Saved polygon/curve sets (the same library a sprite's own base geometry
    /// is drawn from) eligible as Graft's base shape when `graftPrimitiveSource
    /// == .customSet`. One entry always uses that shape; several give each
    /// graft instance a rotating cast, weighted-RPSR-picked per instance by
    /// each entry's `probability` (2026-07-13 — a plain `[String]` before,
    /// renamed when per-shape weighting was added; still an exact uniform pick
    /// when every entry is left at its default `probability`, same as before).
    /// A name with no matching saved set (typo, deleted shape), or a
    /// `probability` of exactly 0, is simply skipped in the roll — falls back
    /// to `.generated` if none resolve. Empty (default) = no effect, same as
    /// `.generated`.
    public var graftCustomShapes: [GraftCustomShapeEntry]

    /// Relative selection weight alongside `extrudeWeight`/`splitWeight` (same
    /// three-way roll, widened from two). 0 (default) excludes Graft from
    /// selection entirely — every existing preset with no opinion on Graft
    /// behaves exactly as before this field existed.
    public var graftWeight: Double

    /// `.wholeEdge` attachment only so far (§4.4.8.3 step 2): the primitive's
    /// chosen edge site is rigid-placed onto the parent's target edge via
    /// `AssemblyFulgurationEngine.place`, reusing its existing
    /// `.preserveSize`/`.matchLength` edge-length toggle directly rather than
    /// inventing a parallel one. A rolled primitive that degenerates to `n≤2`
    /// (a line, with only point-type attachment sites, no edge-type one) is
    /// skipped for this generation — `.singlePoint` attachment (§4.4.8.3 step 3)
    /// is what will make those primitives placeable too.
    public var graftEdgeMatching: AssemblyEdgeMatching

    /// §4.4.8.3 step 3: which of the two attachment modes Graft uses.
    /// `.wholeEdge` (default) preserves step 2's behavior exactly — this field
    /// existing at all has no effect on any preset that doesn't set it.
    public var graftAttachmentMode: GraftAttachmentMode

    /// `.singlePoint` only: RPSR-sampled departure angle (radians), relative to
    /// the parent edge's own outward normal at the chosen point — 0 rotation
    /// means the grafted piece departs exactly outward, the same undeviated
    /// direction Split's own displacement already uses by default. 0–0
    /// (default) = always exactly outward, no randomization.
    public var graftDepartureAngleMin: Double
    public var graftDepartureAngleMax: Double

    /// `.singlePoint` only: where the shared coordinate comes from.
    /// `.existingVertex` (default) touches nothing on the parent; `.newlyInsertedPoint`
    /// splits the chosen edge first (reusing `splitPositionMin/Max` directly —
    /// same RPSR position, same [0.05, 0.95] clamp, no separate field needed).
    public var graftPointSource: GraftPointSource

    /// `.partialEdge` only (§4.4.8.3 step 4): where the sub-span starts, as a
    /// t-parameter along the parent edge — 0 is the edge's own start, 1 its
    /// end. Same RPSR-range idiom as `splitPositionMin/Max` but its own field
    /// (not shared with Split — semantically this is Graft's own start
    /// position, not a split point, and unlike Split there's no parent-topology
    /// zero-length risk to clamp away from, so this isn't restricted to
    /// [0.05, 0.95]). 0–0 (default) = always starts exactly at the edge's own
    /// start.
    public var graftPartialPositionMin: Double
    public var graftPartialPositionMax: Double

    /// `.partialEdge` only: what fraction (0–1) of the edge's *remaining*
    /// length beyond the sampled start position the attachment span covers —
    /// span 1.0 from position 0.0 covers the whole edge, the same target
    /// `.wholeEdge` would use. 1–1 (default) = always covers the full
    /// remainder, so `.partialEdge` with untouched defaults reproduces
    /// `.wholeEdge`'s target span exactly; narrowing either range is what
    /// actually makes the attachment partial.
    public var graftPartialSpanMin: Double
    public var graftPartialSpanMax: Double

    /// §4.4.8.4: per-free-edge RPSR chance (0–1) of becoming curved instead of
    /// staying straight. 0 (default) = never curved — the placed piece's
    /// `.line`/`.openSpline` encoding is left completely untouched (not even
    /// converted to `.spline`) whenever this and articulation are both off,
    /// so existing wholeEdge/singlePoint/partialEdge behavior is unaffected.
    public var graftEdgeCurvatureProbability: Double

    /// Bow magnitude when an edge is curved, as a fraction of that edge's own
    /// length — same units `ExtensionEngine.extrudeSegment`'s existing
    /// `extrusionCurvature` already uses for Extrude's outer face. 0–0
    /// (default) = no effect even if probability is nonzero.
    public var graftEdgeCurvatureAmountMin: Double
    public var graftEdgeCurvatureAmountMax: Double

    /// §4.4.8.4: how many extra joints a free edge is subdivided into. 0–0
    /// (default) = no articulation. Rolled once per free edge (not per-joint),
    /// same "per-eligible-thing, not per-generation" granularity
    /// `extrudeAsymmetricSides`'s corner rolls already use.
    public var graftArticulationCountMin: Int
    public var graftArticulationCountMax: Int

    public var graftArticulationPattern: GraftArticulationPattern

    /// Displacement magnitude per joint, as a fraction of the edge's own
    /// length (same edge-relative convention `graftEdgeCurvatureAmountMin/Max`
    /// above uses, not an absolute canvas-scale unit), perpendicular to the
    /// edge's own local (chord) direction — so it shrinks along with a piece
    /// scaled down via `graftScaleMin/Max` rather than staying fixed-size
    /// regardless of the piece's own scale. 0–0 (default) = no effect even if
    /// the articulation count range is nonzero.
    public var graftArticulationAmountMin: Double
    public var graftArticulationAmountMax: Double

    /// §4.4.8.3 orientation control (2026-07-13). See `GraftConnectorSelection`.
    public var graftConnectorSelection: GraftConnectorSelection

    /// §4.4.8.3 orientation control (2026-07-13): extra rotation applied to a
    /// placed graft piece around its own anchor point, on top of `place()`'s
    /// own mechanical outward-normal-to-outward-normal alignment — a signed
    /// fraction of a full turn, resampled per graft (RPSR). 0–0 (default) adds
    /// no rotation at all, reproducing the original "perpendicular" placement
    /// exactly; ±1 is a full ±360° turn. Applies uniformly regardless of
    /// `graftAttachmentMode` or `graftConnectorSelection`.
    public var graftOrientationAmountMin: Double
    public var graftOrientationAmountMax: Double

    public var generationSeed:        Int
    public var maxVertexBudget:       Int      // hard cap on total vertex count; required, not optional

    /// Restricts which edges the extrude/split operators may target by outward-
    /// normal direction (Specs/GeometricLifecycle.md §14) — e.g. "only the top
    /// edge(s)". Disabled by default: every edge is eligible, unchanged from
    /// before this existed. See `GenerationalEvolutionEngine.eligibleSegments`.
    public var directionalSelector: DirectionalSelector

    /// Optional per-frame animation of the reveal: maps playback time to a
    /// continuous position in [0, generationCount] via the standard DoubleDriver
    /// machinery (unlike the operator randomness above, this genuinely is playback
    /// time, so DoubleDriver is the right tool here). When `enabled` is false
    /// (the default), the full `generationCount` is always applied statically —
    /// existing behavior is unchanged. When enabled, the integer part of the
    /// evaluated value is how many generations are fully applied; the fractional
    /// part scales the in-progress generation's extrude/split magnitude from 0 to
    /// its full sampled distance, tweening that generation's mutation into view
    /// rather than having it pop in. See GenerationalEvolutionEngine.
    public var generationPhase: DoubleDriver

    /// When true and `generationPhase` is enabled, each full cycle of the reveal
    /// (each time it returns to generation 0 and climbs again) uses a different
    /// effective seed — derived from `generationSeed` combined with a cycle index,
    /// not `generationSeed` itself, which is left untouched. Has no effect when
    /// `generationPhase` is disabled (no cycles exist to vary between). See
    /// `GenerationalEvolutionEngine.revealCycleIndex`/`combineSeed`.
    public var varySeedPerCycle: Bool

    public init(
        name:                     String                  = "",
        enabled:                  Bool                    = true,
        operationType:            EvolutionOperationType  = .momentumDrift,
        driftTarget:              DriftTarget             = .lineRatioXY,
        driftMomentum:            Double                  = 0.85,
        driftNoiseStrength:       Double                  = 0.1,
        driftNoiseFrequency:      Double                  = 0.02,
        driftSeed:                Int                     = 0,
        convergenceTargetSetName: String                  = "",
        convergencePressure:      DoubleDriver            = .constant(0.5),
        convergenceMode:          ConvergenceMode         = .hold,
        convergenceDuration:      Double                  = 120.0,
        generationCount:          Int                     = 5,
        extrudeWeight:            Double                  = 1.0,
        splitWeight:              Double                  = 1.0,
        extrudeRunLengthMin:      Int                     = 1,
        extrudeRunLengthMax:      Int                     = 2,
        extrudeDistanceMin:       Double                  = 0.05,
        extrudeDistanceMax:       Double                  = 0.2,
        extrudeAsymmetricSides:   Bool                    = false,
        extrudeAngleRandomized:   Bool                    = false,
        includeOpenCurves:        Bool                    = false,
        restrictTargetsToOriginalGeometry: Bool            = false,
        extrudeOpenCurveBothSides: Bool                   = false,
        splitPositionMin:         Double                  = 0.5,
        splitPositionMax:         Double                  = 0.5,
        splitDisplacementMin:     Double                  = 0.05,
        splitDisplacementMax:     Double                  = 0.2,
        splitBulgePinchMin:       Double                  = 0.0,
        splitBulgePinchMax:       Double                  = 0.0,
        graftSidesMin:            Int                     = 1,
        graftSidesMax:            Int                     = 4,
        graftDistortionMin:       Double                  = 1.0,
        graftDistortionMax:       Double                  = 1.0,
        graftScaleMin:            Double                  = 1.0,
        graftScaleMax:            Double                  = 1.0,
        graftPrimitiveSource:     GraftPrimitiveSource    = .generated,
        graftCustomShapes:        [GraftCustomShapeEntry] = [],
        graftWeight:              Double                  = 0.0,
        graftEdgeMatching:        AssemblyEdgeMatching    = .preserveSize,
        graftAttachmentMode:      GraftAttachmentMode     = .wholeEdge,
        graftDepartureAngleMin:   Double                  = 0.0,
        graftDepartureAngleMax:   Double                  = 0.0,
        graftPointSource:         GraftPointSource        = .existingVertex,
        graftPartialPositionMin:  Double                  = 0.0,
        graftPartialPositionMax:  Double                  = 0.0,
        graftPartialSpanMin:      Double                  = 1.0,
        graftPartialSpanMax:      Double                  = 1.0,
        graftEdgeCurvatureProbability: Double             = 0.0,
        graftEdgeCurvatureAmountMin:   Double             = 0.0,
        graftEdgeCurvatureAmountMax:   Double             = 0.0,
        graftArticulationCountMin:     Int                = 0,
        graftArticulationCountMax:     Int                = 0,
        graftArticulationPattern:      GraftArticulationPattern = .jitter,
        graftArticulationAmountMin:    Double             = 0.0,
        graftArticulationAmountMax:    Double             = 0.0,
        graftConnectorSelection:  GraftConnectorSelection = .random,
        graftOrientationAmountMin: Double                 = 0.0,
        graftOrientationAmountMax: Double                 = 0.0,
        generationSeed:           Int                     = 0,
        maxVertexBudget:          Int                     = 512,
        generationPhase:          DoubleDriver            = DoubleDriver(),
        varySeedPerCycle:         Bool                    = false,
        directionalSelector:      DirectionalSelector     = DirectionalSelector()
    ) {
        self.name                     = name
        self.enabled                  = enabled
        self.operationType            = operationType
        self.driftTarget              = driftTarget
        self.driftMomentum            = driftMomentum
        self.driftNoiseStrength       = driftNoiseStrength
        self.driftNoiseFrequency      = driftNoiseFrequency
        self.driftSeed                = driftSeed
        self.convergenceTargetSetName = convergenceTargetSetName
        self.convergencePressure      = convergencePressure
        self.convergenceMode          = convergenceMode
        self.convergenceDuration      = convergenceDuration
        self.generationCount          = generationCount
        self.extrudeWeight            = extrudeWeight
        self.splitWeight              = splitWeight
        self.extrudeRunLengthMin      = extrudeRunLengthMin
        self.extrudeRunLengthMax      = extrudeRunLengthMax
        self.extrudeDistanceMin       = extrudeDistanceMin
        self.extrudeDistanceMax       = extrudeDistanceMax
        self.extrudeAsymmetricSides   = extrudeAsymmetricSides
        self.extrudeAngleRandomized   = extrudeAngleRandomized
        self.includeOpenCurves        = includeOpenCurves
        self.restrictTargetsToOriginalGeometry = restrictTargetsToOriginalGeometry
        self.extrudeOpenCurveBothSides = extrudeOpenCurveBothSides
        self.splitPositionMin         = splitPositionMin
        self.splitPositionMax         = splitPositionMax
        self.splitDisplacementMin     = splitDisplacementMin
        self.splitDisplacementMax     = splitDisplacementMax
        self.splitBulgePinchMin       = splitBulgePinchMin
        self.splitBulgePinchMax       = splitBulgePinchMax
        self.graftSidesMin            = graftSidesMin
        self.graftSidesMax            = graftSidesMax
        self.graftDistortionMin       = graftDistortionMin
        self.graftDistortionMax       = graftDistortionMax
        self.graftScaleMin            = graftScaleMin
        self.graftScaleMax            = graftScaleMax
        self.graftPrimitiveSource     = graftPrimitiveSource
        self.graftCustomShapes        = graftCustomShapes
        self.graftWeight              = graftWeight
        self.graftEdgeMatching        = graftEdgeMatching
        self.graftAttachmentMode      = graftAttachmentMode
        self.graftDepartureAngleMin   = graftDepartureAngleMin
        self.graftDepartureAngleMax   = graftDepartureAngleMax
        self.graftPointSource         = graftPointSource
        self.graftPartialPositionMin  = graftPartialPositionMin
        self.graftPartialPositionMax  = graftPartialPositionMax
        self.graftPartialSpanMin      = graftPartialSpanMin
        self.graftPartialSpanMax      = graftPartialSpanMax
        self.graftEdgeCurvatureProbability = graftEdgeCurvatureProbability
        self.graftEdgeCurvatureAmountMin   = graftEdgeCurvatureAmountMin
        self.graftEdgeCurvatureAmountMax   = graftEdgeCurvatureAmountMax
        self.graftArticulationCountMin     = graftArticulationCountMin
        self.graftArticulationCountMax     = graftArticulationCountMax
        self.graftArticulationPattern      = graftArticulationPattern
        self.graftArticulationAmountMin    = graftArticulationAmountMin
        self.graftArticulationAmountMax    = graftArticulationAmountMax
        self.graftConnectorSelection       = graftConnectorSelection
        self.graftOrientationAmountMin     = graftOrientationAmountMin
        self.graftOrientationAmountMax     = graftOrientationAmountMax
        self.generationSeed           = generationSeed
        self.maxVertexBudget          = maxVertexBudget
        self.generationPhase          = generationPhase
        self.varySeedPerCycle         = varySeedPerCycle
        self.directionalSelector      = directionalSelector
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name, enabled, operationType
        case driftTarget, driftMomentum, driftNoiseStrength, driftNoiseFrequency, driftSeed
        case convergenceTargetSetName, convergencePressure, convergenceMode, convergenceDuration
        case generationCount, extrudeWeight, splitWeight
        case extrudeRunLengthMin, extrudeRunLengthMax, extrudeDistanceMin, extrudeDistanceMax
        case extrudeAsymmetricSides, extrudeAngleRandomized
        case includeOpenCurves
        case restrictTargetsToOriginalGeometry
        case extrudeOpenCurveBothSides
        case splitPositionMin, splitPositionMax
        case splitDisplacementMin, splitDisplacementMax, generationSeed, maxVertexBudget
        case splitBulgePinchMin, splitBulgePinchMax
        case graftSidesMin, graftSidesMax, graftDistortionMin, graftDistortionMax
        case graftScaleMin, graftScaleMax
        case graftPrimitiveSource, graftCustomShapes
        case graftWeight, graftEdgeMatching
        case graftAttachmentMode, graftDepartureAngleMin, graftDepartureAngleMax, graftPointSource
        case graftPartialPositionMin, graftPartialPositionMax, graftPartialSpanMin, graftPartialSpanMax
        case graftEdgeCurvatureProbability, graftEdgeCurvatureAmountMin, graftEdgeCurvatureAmountMax
        case graftArticulationCountMin, graftArticulationCountMax, graftArticulationPattern
        case graftArticulationAmountMin, graftArticulationAmountMax
        case graftConnectorSelection, graftOrientationAmountMin, graftOrientationAmountMax
        case generationPhase, varySeedPerCycle, directionalSelector
    }

    /// Not part of `CodingKeys` — a case here with no matching stored property
    /// would break the compiler's automatic `Encodable` synthesis. Read via its
    /// own separate keyed container over the same decoder, only as a decode-time
    /// fallback for `includeOpenCurves`/`graftCustomShapes` (see `init(from:)`);
    /// never written.
    private enum LegacyCodingKeys: String, CodingKey {
        case extrudeIncludeOpenCurves
        case graftCustomSetNames
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name                     = try c.decodeIfPresent(String.self,                  forKey: .name)                     ?? ""
        enabled                  = try c.decodeIfPresent(Bool.self,                    forKey: .enabled)                  ?? true
        operationType            = try c.decodeIfPresent(EvolutionOperationType.self,  forKey: .operationType)            ?? .momentumDrift
        driftTarget              = try c.decodeIfPresent(DriftTarget.self,             forKey: .driftTarget)              ?? .lineRatioXY
        driftMomentum            = try c.decodeIfPresent(Double.self,                  forKey: .driftMomentum)            ?? 0.85
        driftNoiseStrength       = try c.decodeIfPresent(Double.self,                  forKey: .driftNoiseStrength)       ?? 0.1
        driftNoiseFrequency      = try c.decodeIfPresent(Double.self,                  forKey: .driftNoiseFrequency)      ?? 0.02
        driftSeed                = try c.decodeIfPresent(Int.self,                     forKey: .driftSeed)                ?? 0
        convergenceTargetSetName = try c.decodeIfPresent(String.self,                  forKey: .convergenceTargetSetName) ?? ""
        convergencePressure      = try c.decodeIfPresent(DoubleDriver.self,            forKey: .convergencePressure)      ?? .constant(0.5)
        convergenceMode          = try c.decodeIfPresent(ConvergenceMode.self,         forKey: .convergenceMode)          ?? .hold
        convergenceDuration      = try c.decodeIfPresent(Double.self,                  forKey: .convergenceDuration)      ?? 120.0
        generationCount          = try c.decodeIfPresent(Int.self,                     forKey: .generationCount)          ?? 5
        extrudeWeight            = try c.decodeIfPresent(Double.self,                  forKey: .extrudeWeight)            ?? 1.0
        splitWeight              = try c.decodeIfPresent(Double.self,                  forKey: .splitWeight)              ?? 1.0
        extrudeRunLengthMin      = try c.decodeIfPresent(Int.self,                     forKey: .extrudeRunLengthMin)      ?? 1
        extrudeRunLengthMax      = try c.decodeIfPresent(Int.self,                     forKey: .extrudeRunLengthMax)      ?? 2
        extrudeDistanceMin       = try c.decodeIfPresent(Double.self,                  forKey: .extrudeDistanceMin)       ?? 0.05
        extrudeDistanceMax       = try c.decodeIfPresent(Double.self,                  forKey: .extrudeDistanceMax)       ?? 0.2
        extrudeAsymmetricSides   = try c.decodeIfPresent(Bool.self,                    forKey: .extrudeAsymmetricSides)   ?? false
        extrudeAngleRandomized   = try c.decodeIfPresent(Bool.self,                    forKey: .extrudeAngleRandomized)   ?? false
        // New key first; fall back to the pre-rename legacy key (via a separate
        // keyed container — it isn't a case of the main CodingKeys, since a case
        // with no matching stored property would break Encodable synthesis) so
        // existing saved projects (which only ever wrote "extrudeIncludeOpenCurves")
        // keep loading with open-curve support enabled, not silently reset to false.
        if let v = try c.decodeIfPresent(Bool.self, forKey: .includeOpenCurves) {
            includeOpenCurves = v
        } else if let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self),
                  let v = try legacy.decodeIfPresent(Bool.self, forKey: .extrudeIncludeOpenCurves) {
            includeOpenCurves = v
        } else {
            includeOpenCurves = false
        }
        restrictTargetsToOriginalGeometry = try c.decodeIfPresent(Bool.self, forKey: .restrictTargetsToOriginalGeometry) ?? false
        extrudeOpenCurveBothSides = try c.decodeIfPresent(Bool.self,                   forKey: .extrudeOpenCurveBothSides) ?? false
        splitPositionMin         = try c.decodeIfPresent(Double.self,                  forKey: .splitPositionMin)         ?? 0.5
        splitPositionMax         = try c.decodeIfPresent(Double.self,                  forKey: .splitPositionMax)         ?? 0.5
        splitDisplacementMin     = try c.decodeIfPresent(Double.self,                  forKey: .splitDisplacementMin)     ?? 0.05
        splitDisplacementMax     = try c.decodeIfPresent(Double.self,                  forKey: .splitDisplacementMax)     ?? 0.2
        splitBulgePinchMin       = try c.decodeIfPresent(Double.self,                  forKey: .splitBulgePinchMin)       ?? 0.0
        splitBulgePinchMax       = try c.decodeIfPresent(Double.self,                  forKey: .splitBulgePinchMax)       ?? 0.0
        graftSidesMin            = try c.decodeIfPresent(Int.self,                     forKey: .graftSidesMin)            ?? 1
        graftSidesMax            = try c.decodeIfPresent(Int.self,                     forKey: .graftSidesMax)            ?? 4
        graftDistortionMin       = try c.decodeIfPresent(Double.self,                  forKey: .graftDistortionMin)       ?? 1.0
        graftDistortionMax       = try c.decodeIfPresent(Double.self,                  forKey: .graftDistortionMax)       ?? 1.0
        graftScaleMin            = try c.decodeIfPresent(Double.self,                  forKey: .graftScaleMin)            ?? 1.0
        graftScaleMax            = try c.decodeIfPresent(Double.self,                  forKey: .graftScaleMax)            ?? 1.0
        graftPrimitiveSource     = try c.decodeIfPresent(GraftPrimitiveSource.self,     forKey: .graftPrimitiveSource)     ?? .generated
        // New key first; fall back to the pre-rename legacy key (plain [String],
        // one entry per name, uniform pick) so existing saved projects keep
        // loading with the exact same custom shapes and uniform-pick behavior,
        // not silently reset to empty.
        if let entries = try c.decodeIfPresent([GraftCustomShapeEntry].self, forKey: .graftCustomShapes) {
            graftCustomShapes = entries
        } else if let legacy = try? decoder.container(keyedBy: LegacyCodingKeys.self),
                  let names = try legacy.decodeIfPresent([String].self, forKey: .graftCustomSetNames) {
            graftCustomShapes = names.map { GraftCustomShapeEntry(name: $0) }
        } else {
            graftCustomShapes = []
        }
        graftWeight              = try c.decodeIfPresent(Double.self,                  forKey: .graftWeight)              ?? 0.0
        graftEdgeMatching        = try c.decodeIfPresent(AssemblyEdgeMatching.self,     forKey: .graftEdgeMatching)        ?? .preserveSize
        graftAttachmentMode      = try c.decodeIfPresent(GraftAttachmentMode.self,      forKey: .graftAttachmentMode)      ?? .wholeEdge
        graftDepartureAngleMin   = try c.decodeIfPresent(Double.self,                  forKey: .graftDepartureAngleMin)   ?? 0.0
        graftDepartureAngleMax   = try c.decodeIfPresent(Double.self,                  forKey: .graftDepartureAngleMax)   ?? 0.0
        graftPointSource         = try c.decodeIfPresent(GraftPointSource.self,        forKey: .graftPointSource)         ?? .existingVertex
        graftPartialPositionMin  = try c.decodeIfPresent(Double.self,                  forKey: .graftPartialPositionMin)  ?? 0.0
        graftPartialPositionMax  = try c.decodeIfPresent(Double.self,                  forKey: .graftPartialPositionMax)  ?? 0.0
        graftPartialSpanMin      = try c.decodeIfPresent(Double.self,                  forKey: .graftPartialSpanMin)      ?? 1.0
        graftPartialSpanMax      = try c.decodeIfPresent(Double.self,                  forKey: .graftPartialSpanMax)      ?? 1.0
        graftEdgeCurvatureProbability = try c.decodeIfPresent(Double.self,             forKey: .graftEdgeCurvatureProbability) ?? 0.0
        graftEdgeCurvatureAmountMin   = try c.decodeIfPresent(Double.self,             forKey: .graftEdgeCurvatureAmountMin)   ?? 0.0
        graftEdgeCurvatureAmountMax   = try c.decodeIfPresent(Double.self,             forKey: .graftEdgeCurvatureAmountMax)   ?? 0.0
        graftArticulationCountMin     = try c.decodeIfPresent(Int.self,                forKey: .graftArticulationCountMin)     ?? 0
        graftArticulationCountMax     = try c.decodeIfPresent(Int.self,                forKey: .graftArticulationCountMax)     ?? 0
        graftArticulationPattern      = try c.decodeIfPresent(GraftArticulationPattern.self, forKey: .graftArticulationPattern) ?? .jitter
        graftArticulationAmountMin    = try c.decodeIfPresent(Double.self,             forKey: .graftArticulationAmountMin)    ?? 0.0
        graftArticulationAmountMax    = try c.decodeIfPresent(Double.self,             forKey: .graftArticulationAmountMax)    ?? 0.0
        graftConnectorSelection      = try c.decodeIfPresent(GraftConnectorSelection.self, forKey: .graftConnectorSelection)   ?? .random
        graftOrientationAmountMin    = try c.decodeIfPresent(Double.self,             forKey: .graftOrientationAmountMin)     ?? 0.0
        graftOrientationAmountMax    = try c.decodeIfPresent(Double.self,             forKey: .graftOrientationAmountMax)     ?? 0.0
        generationSeed           = try c.decodeIfPresent(Int.self,                     forKey: .generationSeed)           ?? 0
        maxVertexBudget          = try c.decodeIfPresent(Int.self,                     forKey: .maxVertexBudget)          ?? 512
        generationPhase          = try c.decodeIfPresent(DoubleDriver.self,            forKey: .generationPhase)          ?? DoubleDriver()
        varySeedPerCycle         = try c.decodeIfPresent(Bool.self,                    forKey: .varySeedPerCycle)         ?? false
        directionalSelector      = try c.decodeIfPresent(DirectionalSelector.self,     forKey: .directionalSelector)      ?? DirectionalSelector()
    }
}
