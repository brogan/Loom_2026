import Foundation

// MARK: - RanMiddleMode

/// Controls how the subdivision centre jitter behaves when `ranMiddle` is enabled.
public enum RanMiddleMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// Picks a completely new random centre on every frame (original behaviour).
    case jitter
    /// Computes a new target centre once per `ranMiddlePeriod` frames and smoothly
    /// interpolates toward it — gives a slow, organic drift rather than per-frame noise.
    case lazy
}

// MARK: - Subdivision Drivers

/// Continuous/keyframed drivers that animate `SubdivisionParams` fields at runtime.
///
/// **Generation-level drivers** (lineRatio, cpRatio, cpNormalOffset, insetScale,
/// insetRotation, ranDiv) are evaluated once per frame using the sprite's own index
/// and override the corresponding static fields on `SubdivisionParams` before the
/// subdivision algorithm runs.
///
/// **Per-polygon PTW drivers** (ptwTranslateX/Y, ptwScale, ptwRotation) are
/// evaluated per output polygon, using the polygon's index as the phase seed so
/// each polygon gets a smoothly staggered, coherent trajectory rather than
/// frame-to-frame random jitter. Displacement is normalised to the polygon's own
/// bounding box so identical driver values produce proportionally equivalent motion
/// at every subdivision depth.
public struct SubdivisionDrivers: Equatable, Codable, Sendable {

    // MARK: Generation-level

    /// Overrides `lineRatios.x` and `.y` symmetrically (0–1 split position).
    public var lineRatio:      DoubleDriver = .zero
    /// Overrides `controlPointRatios` symmetrically: x = v, y = 1−v.
    public var cpRatio:        DoubleDriver = .zero
    /// Overrides `cpNormalOffsets.x` and `.y` (bow magnitude on internal connectors).
    public var cpNormalOffset: DoubleDriver = .zero
    /// Overrides both axes of `insetTransform.scale`. 1.0 = no change.
    public var insetScale:     DoubleDriver = .one
    /// Overrides `insetTransform.rotation` in radians.
    public var insetRotation:  DoubleDriver = .zero
    /// Overrides `ranDiv`. Higher value = less centre jitter.
    public var ranDiv:         DoubleDriver = .zero

    // MARK: Per-polygon PTW

    /// Per-polygon X displacement as a fraction of the polygon's bounding-box width.
    public var ptwTranslateX:  DoubleDriver = .zero
    /// Per-polygon Y displacement as a fraction of the polygon's bounding-box height.
    public var ptwTranslateY:  DoubleDriver = .zero
    /// Per-polygon uniform scale multiplier around the polygon centroid. 1.0 = no change.
    public var ptwScale:       DoubleDriver = .one
    /// Per-polygon rotation in radians around the polygon centroid.
    public var ptwRotation:    DoubleDriver = .zero
    /// Phase mode for ptwTranslateX — how phase offset is derived from polygon index.
    public var ptwTranslateXPhase: PTWPhaseMode = .sequential
    /// Phase mode for ptwTranslateY — how phase offset is derived from polygon index.
    public var ptwTranslateYPhase: PTWPhaseMode = .sequential
    /// Phase mode for ptwScale — how phase offset is derived from polygon index.
    public var ptwScalePhase:      PTWPhaseMode = .sequential
    /// Phase mode for ptwRotation — how phase offset is derived from polygon index.
    public var ptwRotationPhase:   PTWPhaseMode = .sequential

    public init(
        lineRatio:         DoubleDriver = .zero,
        cpRatio:           DoubleDriver = .zero,
        cpNormalOffset:    DoubleDriver = .zero,
        insetScale:        DoubleDriver = .one,
        insetRotation:     DoubleDriver = .zero,
        ranDiv:            DoubleDriver = .zero,
        ptwTranslateX:     DoubleDriver = .zero,
        ptwTranslateY:     DoubleDriver = .zero,
        ptwScale:          DoubleDriver = .one,
        ptwRotation:       DoubleDriver = .zero,
        ptwTranslateXPhase: PTWPhaseMode = .sequential,
        ptwTranslateYPhase: PTWPhaseMode = .sequential,
        ptwScalePhase:      PTWPhaseMode = .sequential,
        ptwRotationPhase:   PTWPhaseMode = .sequential
    ) {
        self.lineRatio          = lineRatio
        self.cpRatio            = cpRatio
        self.cpNormalOffset     = cpNormalOffset
        self.insetScale         = insetScale
        self.insetRotation      = insetRotation
        self.ranDiv             = ranDiv
        self.ptwTranslateX      = ptwTranslateX
        self.ptwTranslateY      = ptwTranslateY
        self.ptwScale           = ptwScale
        self.ptwRotation        = ptwRotation
        self.ptwTranslateXPhase = ptwTranslateXPhase
        self.ptwTranslateYPhase = ptwTranslateYPhase
        self.ptwScalePhase      = ptwScalePhase
        self.ptwRotationPhase   = ptwRotationPhase
    }

    private enum CodingKeys: String, CodingKey {
        case lineRatio, cpRatio, cpNormalOffset, insetScale, insetRotation, ranDiv
        case ptwTranslateX, ptwTranslateY, ptwScale, ptwRotation
        case ptwTranslateXPhase, ptwTranslateYPhase, ptwScalePhase, ptwRotationPhase
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineRatio          = try c.decodeIfPresent(DoubleDriver.self, forKey: .lineRatio)          ?? .zero
        cpRatio            = try c.decodeIfPresent(DoubleDriver.self, forKey: .cpRatio)            ?? .zero
        cpNormalOffset     = try c.decodeIfPresent(DoubleDriver.self, forKey: .cpNormalOffset)     ?? .zero
        insetScale         = try c.decodeIfPresent(DoubleDriver.self, forKey: .insetScale)         ?? .one
        insetRotation      = try c.decodeIfPresent(DoubleDriver.self, forKey: .insetRotation)      ?? .zero
        ranDiv             = try c.decodeIfPresent(DoubleDriver.self, forKey: .ranDiv)             ?? .zero
        ptwTranslateX      = try c.decodeIfPresent(DoubleDriver.self, forKey: .ptwTranslateX)      ?? .zero
        ptwTranslateY      = try c.decodeIfPresent(DoubleDriver.self, forKey: .ptwTranslateY)      ?? .zero
        ptwScale           = try c.decodeIfPresent(DoubleDriver.self, forKey: .ptwScale)           ?? .one
        ptwRotation        = try c.decodeIfPresent(DoubleDriver.self, forKey: .ptwRotation)        ?? .zero
        ptwTranslateXPhase = try c.decodeIfPresent(PTWPhaseMode.self, forKey: .ptwTranslateXPhase) ?? .sequential
        ptwTranslateYPhase = try c.decodeIfPresent(PTWPhaseMode.self, forKey: .ptwTranslateYPhase) ?? .sequential
        ptwScalePhase      = try c.decodeIfPresent(PTWPhaseMode.self, forKey: .ptwScalePhase)      ?? .sequential
        ptwRotationPhase   = try c.decodeIfPresent(PTWPhaseMode.self, forKey: .ptwRotationPhase)   ?? .sequential
    }
}

// MARK: - PTW Phase Mode

public enum PTWPhaseMode: String, Codable, CaseIterable, Sendable {
    /// All polygons receive the same phase — they move in unison.
    case all        = "All"
    /// Phase increments linearly with polygon index — produces wave-like propagation.
    case sequential = "Sequential"
    /// Phase is scrambled per polygon within [0, max] — produces independent, non-repeating motion.
    case random     = "Random"
}

public enum PressureSubdivisionMode: String, CaseIterable, Codable, Sendable {
    case none
    case spatial
    case inheritPath
    case random

    public var label: String {
        switch self {
        case .none:        return "None"
        case .spatial:     return "Spatial"
        case .inheritPath: return "Inherit Path"
        case .random:      return "Random"
        }
    }
}

/// Configuration for one generation of polygon subdivision.
///
/// A named, ordered list of `SubdivisionParams` (one per generation) constitutes
/// a `SubdivisionParamSet` — the full subdivision recipe for a sprite.
public struct SubdivisionParams: Equatable, Codable, Sendable {

    public var name: String
    public var enabled: Bool

    // MARK: - Algorithm selection

    public var subdivisionType: SubdivisionType
    /// Edge split positions. x = even-indexed edges; y = odd-indexed edges.
    public var lineRatios: Vector2D
    /// Bézier control point positions along each new internal line.
    public var controlPointRatios: Vector2D
    /// Perpendicular offset for each control point on internal connector edges,
    /// as a fraction of segment length. Zero = straight line (pure tangential).
    public var cpNormalOffsets: Vector2D
    /// When true, positive offsets point away from the polygon centroid;
    /// when false, positive is the left-perpendicular of the from→to direction.
    public var cpNormalizeTowardsCentre: Bool
    /// When `lineRatios.x ≠ lineRatios.y`, enforces shared split points on
    /// adjacent edges so the mesh is seamless. Has no effect when ratios are equal.
    public var continuous: Bool
    /// When true, outer-edge split points are placed on the Bézier curve (de Casteljau).
    /// When false (default), split points land at the linear interpolation of the two
    /// anchor positions, matching the original Scala behaviour and avoiding cumulative
    /// drift at higher subdivision levels. Applies to Quad-family algorithms only.
    public var curveAwareSplit: Bool
    /// When true, the control points on internal connector edges are shifted to
    /// mirror the curvature of the adjacent outer edge.  Applies to all
    /// subdivision algorithms (Quad, Tri, Split, Bord variants, Custom).
    public var mirrorOuterCurvature: Bool
    /// Inverts the mirrored curvature direction on internal edges.
    /// Only meaningful when `mirrorOuterCurvature` is true.
    public var invertCurvature: Bool
    /// Controls which internal edges receive curvature mirroring.
    /// "ALL"       — every internal edge mirrors its adjacent outer edge.
    /// "EVEN"      — even-indexed edges mirror; odd-indexed stay straight.
    /// "ODD"       — odd-indexed edges mirror; even-indexed stay straight.
    /// "ALTERNATE" — even edges mirror, odd edges mirror inverted (pinwheel).
    public var curvatureSync: String
    /// Applied to scale/rotate all points to create inset polygons (ECHO, BORD variants).
    public var insetTransform: InsetTransform

    // MARK: - Randomisation

    /// Jitter the polygon centre before computing child positions.
    public var ranMiddle: Bool
    /// Jitter magnitude divisor. Lower = more randomisation. Clamped to ≥ 1 at runtime.
    public var ranDiv: Double
    /// How the centre jitter behaves: per-frame random (`.jitter`) or slow-drift tween (`.lazy`).
    public var ranMiddleMode: RanMiddleMode
    /// Lazy mode: frames between new target-centre samples. Matches `DoubleDriver.period` conventions.
    public var ranMiddlePeriod: Int
    /// Lazy mode: deterministic seed so each polygon gets a unique trajectory.
    public var ranMiddleSeed: Int

    // MARK: - Visibility

    public var visibilityRule: VisibilityRule

    // MARK: - Pressure sensitivity

    /// How pressure-sensitive source geometry is carried into subdivided children.
    public var pressureSubdivisionMode: PressureSubdivisionMode
    /// Random pressure library groups 1...5. Used only when `pressureSubdivisionMode == .random`.
    public var pressureRandomGroups: [Bool]

    // MARK: - Whole-polygon transform (Phase 3+)

    /// Master enable for any polygon-level transforms.
    public var polysTransform: Bool
    /// Enable whole-polygon translate / scale / rotate.
    public var polysTranformWhole: Bool
    /// % chance any given polygon is transformed (0–100).
    public var pTW_probability: Double
    /// All polygons share one pivot; if false each uses its own centroid.
    public var pTW_commonCentre: Bool

    // MARK: - Whole-polygon random transform parameters

    /// Enable random translation for whole-polygon transforms.
    public var pTW_randomTranslation: Bool
    /// Enable random scale for whole-polygon transforms.
    public var pTW_randomScale: Bool
    /// Enable random rotation for whole-polygon transforms.
    public var pTW_randomRotation: Bool
    /// Deterministic transform applied to whole polygons (translation, scale, rotation).
    public var pTW_transform: InsetTransform
    /// Divisor controlling the magnitude of random centre jitter.
    public var pTW_randomCentreDivisor: Double
    /// Per-axis translation jitter range for whole-polygon transforms.
    public var pTW_randomTranslationRange: VectorRange
    /// Per-axis scale jitter range for whole-polygon transforms.
    public var pTW_randomScaleRange: VectorRange
    /// Rotation jitter range (radians) for whole-polygon transforms.
    public var pTW_randomRotationRange: FloatRange

    // MARK: - Per-point transforms (Phase 3+)

    /// Enable per-point transforms.
    public var polysTransformPoints: Bool
    /// % chance any given polygon has its points transformed.
    public var pTP_probability: Double
    /// Structured anchor transforms (ExteriorAnchors + CentralAnchors).
    /// When non-nil, used in place of the legacy random-translation PTP path.
    public var ptpTransformSet: PTPTransformSet?

    // MARK: - Custom algorithm

    /// User-defined algorithm. Only used when `subdivisionType == .custom`.
    public var customAlgorithm: CustomSubdivisionAlgorithm?

    // MARK: - Drivers

    /// Optional continuous/keyframed drivers for generation-level and per-polygon PTW animation.
    public var drivers: SubdivisionDrivers?

    // MARK: - Init

    public init(
        name: String                         = "",
        enabled: Bool                         = true,
        subdivisionType: SubdivisionType      = .quad,
        customAlgorithm: CustomSubdivisionAlgorithm? = nil,
        lineRatios: Vector2D                  = Vector2D(x: 0.5, y: 0.5),
        controlPointRatios: Vector2D          = Vector2D(x: 0.25, y: 0.75),
        cpNormalOffsets: Vector2D             = .zero,
        cpNormalizeTowardsCentre: Bool        = false,
        continuous: Bool                      = true,
        curveAwareSplit: Bool                 = false,
        mirrorOuterCurvature: Bool            = false,
        invertCurvature: Bool                 = false,
        curvatureSync: String                 = "ALL",
        insetTransform: InsetTransform        = .default,
        ranMiddle: Bool                       = false,
        ranDiv: Double                        = 100,
        ranMiddleMode: RanMiddleMode          = .jitter,
        ranMiddlePeriod: Int                  = 30,
        ranMiddleSeed: Int                    = 0,
        visibilityRule: VisibilityRule        = .all,
        pressureSubdivisionMode: PressureSubdivisionMode = .spatial,
        pressureRandomGroups: [Bool]          = [true, true, true, true, true],
        polysTransform: Bool                  = true,
        polysTranformWhole: Bool              = false,
        pTW_probability: Double               = 100,
        pTW_commonCentre: Bool                = false,
        pTW_randomTranslation: Bool           = false,
        pTW_randomScale: Bool                 = false,
        pTW_randomRotation: Bool              = false,
        pTW_transform: InsetTransform         = .identity,
        pTW_randomCentreDivisor: Double       = 100,
        pTW_randomTranslationRange: VectorRange = .zero,
        pTW_randomScaleRange: VectorRange     = .one,
        pTW_randomRotationRange: FloatRange   = .zero,
        polysTransformPoints: Bool            = false,
        pTP_probability: Double               = 100,
        ptpTransformSet: PTPTransformSet?     = nil,
        drivers: SubdivisionDrivers?          = nil
    ) {
        self.name                       = name
        self.enabled                    = enabled
        self.subdivisionType            = subdivisionType
        self.customAlgorithm            = customAlgorithm
        self.lineRatios                 = lineRatios
        self.controlPointRatios         = controlPointRatios
        self.cpNormalOffsets            = cpNormalOffsets
        self.cpNormalizeTowardsCentre   = cpNormalizeTowardsCentre
        self.continuous                 = continuous
        self.curveAwareSplit            = curveAwareSplit
        self.mirrorOuterCurvature       = mirrorOuterCurvature
        self.invertCurvature            = invertCurvature
        self.curvatureSync              = curvatureSync
        self.insetTransform             = insetTransform
        self.ranMiddle                  = ranMiddle
        self.ranDiv                     = ranDiv
        self.ranMiddleMode              = ranMiddleMode
        self.ranMiddlePeriod            = ranMiddlePeriod
        self.ranMiddleSeed              = ranMiddleSeed
        self.visibilityRule             = visibilityRule
        self.pressureSubdivisionMode    = pressureSubdivisionMode
        self.pressureRandomGroups       = Self.normalizedPressureRandomGroups(pressureRandomGroups)
        self.polysTransform             = polysTransform
        self.polysTranformWhole         = polysTranformWhole
        self.pTW_probability            = pTW_probability
        self.pTW_commonCentre           = pTW_commonCentre
        self.pTW_randomTranslation      = pTW_randomTranslation
        self.pTW_randomScale            = pTW_randomScale
        self.pTW_randomRotation         = pTW_randomRotation
        self.pTW_transform              = pTW_transform
        self.pTW_randomCentreDivisor    = pTW_randomCentreDivisor
        self.pTW_randomTranslationRange = pTW_randomTranslationRange
        self.pTW_randomScaleRange       = pTW_randomScaleRange
        self.pTW_randomRotationRange    = pTW_randomRotationRange
        self.polysTransformPoints       = polysTransformPoints
        self.pTP_probability            = pTP_probability
        self.ptpTransformSet            = ptpTransformSet
        self.drivers                    = drivers
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled, subdivisionType, customAlgorithm
        case lineRatios, controlPointRatios, cpNormalOffsets, cpNormalizeTowardsCentre, continuous, curveAwareSplit
        case mirrorOuterCurvature, invertCurvature, curvatureSync
        case insetTransform
        case ranMiddle, ranDiv, ranMiddleMode, ranMiddlePeriod, ranMiddleSeed
        case visibilityRule
        case pressureSubdivisionMode, pressureRandomGroups
        case polysTransform, polysTranformWhole, pTW_probability, pTW_commonCentre
        case pTW_randomTranslation, pTW_randomScale, pTW_randomRotation, pTW_transform
        case pTW_randomCentreDivisor, pTW_randomTranslationRange, pTW_randomScaleRange, pTW_randomRotationRange
        case polysTransformPoints, pTP_probability, ptpTransformSet
        case drivers
    }

    public init(from decoder: Decoder) throws {
        let defaults = SubdivisionParams()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? defaults.name,
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
            subdivisionType: try c.decodeIfPresent(SubdivisionType.self, forKey: .subdivisionType) ?? defaults.subdivisionType,
            customAlgorithm: try c.decodeIfPresent(CustomSubdivisionAlgorithm.self, forKey: .customAlgorithm),
            lineRatios: try c.decodeIfPresent(Vector2D.self, forKey: .lineRatios) ?? defaults.lineRatios,
            controlPointRatios: try c.decodeIfPresent(Vector2D.self, forKey: .controlPointRatios) ?? defaults.controlPointRatios,
            cpNormalOffsets: try c.decodeIfPresent(Vector2D.self, forKey: .cpNormalOffsets) ?? defaults.cpNormalOffsets,
            cpNormalizeTowardsCentre: try c.decodeIfPresent(Bool.self, forKey: .cpNormalizeTowardsCentre) ?? defaults.cpNormalizeTowardsCentre,
            continuous: try c.decodeIfPresent(Bool.self, forKey: .continuous) ?? defaults.continuous,
            curveAwareSplit: try c.decodeIfPresent(Bool.self, forKey: .curveAwareSplit) ?? defaults.curveAwareSplit,
            mirrorOuterCurvature: try c.decodeIfPresent(Bool.self, forKey: .mirrorOuterCurvature) ?? defaults.mirrorOuterCurvature,
            invertCurvature: try c.decodeIfPresent(Bool.self, forKey: .invertCurvature) ?? defaults.invertCurvature,
            curvatureSync: try c.decodeIfPresent(String.self, forKey: .curvatureSync) ?? defaults.curvatureSync,
            insetTransform: try c.decodeIfPresent(InsetTransform.self, forKey: .insetTransform) ?? defaults.insetTransform,
            ranMiddle: try c.decodeIfPresent(Bool.self, forKey: .ranMiddle) ?? defaults.ranMiddle,
            ranDiv: try c.decodeIfPresent(Double.self, forKey: .ranDiv) ?? defaults.ranDiv,
            ranMiddleMode: try c.decodeIfPresent(RanMiddleMode.self, forKey: .ranMiddleMode) ?? defaults.ranMiddleMode,
            ranMiddlePeriod: try c.decodeIfPresent(Int.self, forKey: .ranMiddlePeriod) ?? defaults.ranMiddlePeriod,
            ranMiddleSeed: try c.decodeIfPresent(Int.self, forKey: .ranMiddleSeed) ?? defaults.ranMiddleSeed,
            visibilityRule: try c.decodeIfPresent(VisibilityRule.self, forKey: .visibilityRule) ?? defaults.visibilityRule,
            pressureSubdivisionMode: try c.decodeIfPresent(PressureSubdivisionMode.self, forKey: .pressureSubdivisionMode) ?? defaults.pressureSubdivisionMode,
            pressureRandomGroups: try c.decodeIfPresent([Bool].self, forKey: .pressureRandomGroups) ?? defaults.pressureRandomGroups,
            polysTransform: try c.decodeIfPresent(Bool.self, forKey: .polysTransform) ?? defaults.polysTransform,
            polysTranformWhole: try c.decodeIfPresent(Bool.self, forKey: .polysTranformWhole) ?? defaults.polysTranformWhole,
            pTW_probability: try c.decodeIfPresent(Double.self, forKey: .pTW_probability) ?? defaults.pTW_probability,
            pTW_commonCentre: try c.decodeIfPresent(Bool.self, forKey: .pTW_commonCentre) ?? defaults.pTW_commonCentre,
            pTW_randomTranslation: try c.decodeIfPresent(Bool.self, forKey: .pTW_randomTranslation) ?? defaults.pTW_randomTranslation,
            pTW_randomScale: try c.decodeIfPresent(Bool.self, forKey: .pTW_randomScale) ?? defaults.pTW_randomScale,
            pTW_randomRotation: try c.decodeIfPresent(Bool.self, forKey: .pTW_randomRotation) ?? defaults.pTW_randomRotation,
            pTW_transform: try c.decodeIfPresent(InsetTransform.self, forKey: .pTW_transform) ?? defaults.pTW_transform,
            pTW_randomCentreDivisor: try c.decodeIfPresent(Double.self, forKey: .pTW_randomCentreDivisor) ?? defaults.pTW_randomCentreDivisor,
            pTW_randomTranslationRange: try c.decodeIfPresent(VectorRange.self, forKey: .pTW_randomTranslationRange) ?? defaults.pTW_randomTranslationRange,
            pTW_randomScaleRange: try c.decodeIfPresent(VectorRange.self, forKey: .pTW_randomScaleRange) ?? defaults.pTW_randomScaleRange,
            pTW_randomRotationRange: try c.decodeIfPresent(FloatRange.self, forKey: .pTW_randomRotationRange) ?? defaults.pTW_randomRotationRange,
            polysTransformPoints: try c.decodeIfPresent(Bool.self, forKey: .polysTransformPoints) ?? defaults.polysTransformPoints,
            pTP_probability: try c.decodeIfPresent(Double.self, forKey: .pTP_probability) ?? defaults.pTP_probability,
            ptpTransformSet: try c.decodeIfPresent(PTPTransformSet.self, forKey: .ptpTransformSet) ?? defaults.ptpTransformSet,
            drivers: try c.decodeIfPresent(SubdivisionDrivers.self, forKey: .drivers)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(subdivisionType, forKey: .subdivisionType)
        try c.encodeIfPresent(customAlgorithm, forKey: .customAlgorithm)
        try c.encode(lineRatios, forKey: .lineRatios)
        try c.encode(controlPointRatios, forKey: .controlPointRatios)
        try c.encode(cpNormalOffsets, forKey: .cpNormalOffsets)
        try c.encode(cpNormalizeTowardsCentre, forKey: .cpNormalizeTowardsCentre)
        try c.encode(continuous, forKey: .continuous)
        try c.encode(curveAwareSplit, forKey: .curveAwareSplit)
        try c.encode(mirrorOuterCurvature, forKey: .mirrorOuterCurvature)
        try c.encode(invertCurvature, forKey: .invertCurvature)
        try c.encode(curvatureSync, forKey: .curvatureSync)
        try c.encode(insetTransform, forKey: .insetTransform)
        try c.encode(ranMiddle,       forKey: .ranMiddle)
        try c.encode(ranDiv,          forKey: .ranDiv)
        try c.encode(ranMiddleMode,   forKey: .ranMiddleMode)
        try c.encode(ranMiddlePeriod, forKey: .ranMiddlePeriod)
        try c.encode(ranMiddleSeed,   forKey: .ranMiddleSeed)
        try c.encode(visibilityRule,  forKey: .visibilityRule)
        try c.encode(pressureSubdivisionMode, forKey: .pressureSubdivisionMode)
        try c.encode(pressureRandomGroups, forKey: .pressureRandomGroups)
        try c.encode(polysTransform, forKey: .polysTransform)
        try c.encode(polysTranformWhole, forKey: .polysTranformWhole)
        try c.encode(pTW_probability, forKey: .pTW_probability)
        try c.encode(pTW_commonCentre, forKey: .pTW_commonCentre)
        try c.encode(pTW_randomTranslation, forKey: .pTW_randomTranslation)
        try c.encode(pTW_randomScale, forKey: .pTW_randomScale)
        try c.encode(pTW_randomRotation, forKey: .pTW_randomRotation)
        try c.encode(pTW_transform, forKey: .pTW_transform)
        try c.encode(pTW_randomCentreDivisor, forKey: .pTW_randomCentreDivisor)
        try c.encode(pTW_randomTranslationRange, forKey: .pTW_randomTranslationRange)
        try c.encode(pTW_randomScaleRange, forKey: .pTW_randomScaleRange)
        try c.encode(pTW_randomRotationRange, forKey: .pTW_randomRotationRange)
        try c.encode(polysTransformPoints, forKey: .polysTransformPoints)
        try c.encode(pTP_probability, forKey: .pTP_probability)
        try c.encodeIfPresent(ptpTransformSet, forKey: .ptpTransformSet)
        try c.encodeIfPresent(drivers, forKey: .drivers)
    }

    // MARK: - Convenience

    /// Build a Bézier connector segment applying this param's CP ratios and normal offsets.
    public func connector(from: Vector2D, to: Vector2D, centre: Vector2D) -> [Vector2D] {
        BezierMath.connector(from: from, to: to,
                             cpRatios: controlPointRatios,
                             cpNormalOffsets: cpNormalOffsets,
                             normalizeToCentre: cpNormalizeTowardsCentre,
                             centre: centre)
    }

    /// The effective split ratio for side `index`, respecting `continuous` mode.
    public func splitRatio(forSideIndex index: Int) -> Double {
        if continuous && index % 2 != 0 { return lineRatios.y }
        return lineRatios.x
    }

    /// The curvature mirror sign for an internal edge at index `i`.
    /// Returns 0 if `mirrorOuterCurvature` is off or this edge is gated by `curvatureSync`.
    public func curvatureSign(forIndex i: Int) -> Double {
        guard mirrorOuterCurvature else { return 0.0 }
        let base: Double = invertCurvature ? -1.0 : 1.0
        switch curvatureSync {
        case "EVEN":      return i % 2 == 0 ? base : 0.0
        case "ODD":       return i % 2 == 1 ? base : 0.0
        case "ALTERNATE": return i % 2 == 0 ? base : -base
        default:          return base
        }
    }

    public static func normalizedPressureRandomGroups(_ groups: [Bool]) -> [Bool] {
        let padded = groups + Array(repeating: false, count: max(0, 5 - groups.count))
        let firstFive = Array(padded.prefix(5))
        return firstFive.contains(true) ? firstFive : [true, true, true, true, true]
    }
}
