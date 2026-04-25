import Foundation

/// Configuration for one generation of polygon subdivision.
///
/// A named, ordered list of `SubdivisionParams` (one per generation) constitutes
/// a `SubdivisionParamSet` — the full subdivision recipe for a sprite.
public struct SubdivisionParams: Equatable, Codable, Sendable {

    public var name: String

    // MARK: - Algorithm selection

    public var subdivisionType: SubdivisionType
    /// Edge split positions. x = even-indexed edges; y = odd-indexed edges.
    public var lineRatios: Vector2D
    /// Bézier control point positions along each new internal line.
    public var controlPointRatios: Vector2D
    /// When `lineRatios.x ≠ lineRatios.y`, enforces shared split points on
    /// adjacent edges so the mesh is seamless. Has no effect when ratios are equal.
    public var continuous: Bool
    /// Applied to scale/rotate all points to create inset polygons (ECHO, BORD variants).
    public var insetTransform: InsetTransform

    // MARK: - Randomisation

    /// Jitter the polygon centre before computing child positions.
    public var ranMiddle: Bool
    /// Jitter magnitude divisor. Lower = more randomisation.
    public var ranDiv: Double

    // MARK: - Visibility

    public var visibilityRule: VisibilityRule

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

    // MARK: - Init

    public init(
        name: String                         = "",
        subdivisionType: SubdivisionType      = .quad,
        lineRatios: Vector2D                  = Vector2D(x: 0.5, y: 0.5),
        controlPointRatios: Vector2D          = Vector2D(x: 0.25, y: 0.75),
        continuous: Bool                      = true,
        insetTransform: InsetTransform        = .default,
        ranMiddle: Bool                       = false,
        ranDiv: Double                        = 100,
        visibilityRule: VisibilityRule        = .all,
        polysTransform: Bool                  = true,
        polysTranformWhole: Bool              = false,
        pTW_probability: Double               = 100,
        pTW_commonCentre: Bool                = false,
        pTW_randomTranslation: Bool           = false,
        pTW_randomScale: Bool                 = false,
        pTW_randomRotation: Bool              = false,
        pTW_transform: InsetTransform         = .default,
        pTW_randomCentreDivisor: Double       = 100,
        pTW_randomTranslationRange: VectorRange = .zero,
        pTW_randomScaleRange: VectorRange     = .one,
        pTW_randomRotationRange: FloatRange   = .zero,
        polysTransformPoints: Bool            = false,
        pTP_probability: Double               = 100,
        ptpTransformSet: PTPTransformSet?     = nil
    ) {
        self.name                       = name
        self.subdivisionType            = subdivisionType
        self.lineRatios                 = lineRatios
        self.controlPointRatios         = controlPointRatios
        self.continuous                 = continuous
        self.insetTransform             = insetTransform
        self.ranMiddle                  = ranMiddle
        self.ranDiv                     = ranDiv
        self.visibilityRule             = visibilityRule
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

    // MARK: - Convenience

    /// The effective split ratio for side `index`, respecting `continuous` mode.
    public func splitRatio(forSideIndex index: Int) -> Double {
        if continuous && index % 2 != 0 { return lineRatios.y }
        return lineRatios.x
    }
}
