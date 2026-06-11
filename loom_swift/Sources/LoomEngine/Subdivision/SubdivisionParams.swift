import Foundation

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
    /// Applied to scale/rotate all points to create inset polygons (ECHO, BORD variants).
    public var insetTransform: InsetTransform

    // MARK: - Randomisation

    /// Jitter the polygon centre before computing child positions.
    public var ranMiddle: Bool
    /// Jitter magnitude divisor. Lower = more randomisation.
    public var ranDiv: Double

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
        insetTransform: InsetTransform        = .default,
        ranMiddle: Bool                       = false,
        ranDiv: Double                        = 100,
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
        ptpTransformSet: PTPTransformSet?     = nil
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
        self.insetTransform             = insetTransform
        self.ranMiddle                  = ranMiddle
        self.ranDiv                     = ranDiv
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
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled, subdivisionType, customAlgorithm
        case lineRatios, controlPointRatios, cpNormalOffsets, cpNormalizeTowardsCentre, continuous, curveAwareSplit, insetTransform
        case ranMiddle, ranDiv, visibilityRule
        case pressureSubdivisionMode, pressureRandomGroups
        case polysTransform, polysTranformWhole, pTW_probability, pTW_commonCentre
        case pTW_randomTranslation, pTW_randomScale, pTW_randomRotation, pTW_transform
        case pTW_randomCentreDivisor, pTW_randomTranslationRange, pTW_randomScaleRange, pTW_randomRotationRange
        case polysTransformPoints, pTP_probability, ptpTransformSet
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
            insetTransform: try c.decodeIfPresent(InsetTransform.self, forKey: .insetTransform) ?? defaults.insetTransform,
            ranMiddle: try c.decodeIfPresent(Bool.self, forKey: .ranMiddle) ?? defaults.ranMiddle,
            ranDiv: try c.decodeIfPresent(Double.self, forKey: .ranDiv) ?? defaults.ranDiv,
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
            ptpTransformSet: try c.decodeIfPresent(PTPTransformSet.self, forKey: .ptpTransformSet) ?? defaults.ptpTransformSet
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
        try c.encode(insetTransform, forKey: .insetTransform)
        try c.encode(ranMiddle, forKey: .ranMiddle)
        try c.encode(ranDiv, forKey: .ranDiv)
        try c.encode(visibilityRule, forKey: .visibilityRule)
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

    public static func normalizedPressureRandomGroups(_ groups: [Bool]) -> [Bool] {
        let padded = groups + Array(repeating: false, count: max(0, 5 - groups.count))
        let firstFive = Array(padded.prefix(5))
        return firstFive.contains(true) ? firstFive : [true, true, true, true, true]
    }
}
