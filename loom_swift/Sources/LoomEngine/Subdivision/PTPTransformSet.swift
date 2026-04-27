/// Per-point transform data structures for subdivision post-processing.
///
/// These implement the `PolysTransformPoints` (PTP) system from the Loom XML spec:
/// - `ExteriorAnchorsTransform`: spikes exterior anchor pairs away from/toward a reference point
/// - `CentralAnchorsTransform`: tears central anchor pairs toward an outside reference
public struct ExteriorAnchorsTransform: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var probability: Double
    /// Signed lerp factor: negative moves anchor away from centrePoint (outward spike).
    public var spikeFactor: Double
    /// Which anchors to spike: "ALL", "CORNERS", "MIDDLES"
    public var whichSpike: String
    /// "SYMMETRICAL", "RIGHT", "LEFT", "RANDOM"
    public var spikeType: String
    /// "XY", "X", "Y"
    public var spikeAxis: String
    public var randomSpike: Bool
    public var randomSpikeFactor: FloatRange
    public var cpsFollow: Bool
    public var cpsFollowMultiplier: Double
    public var randomCpsFollow: Bool
    public var randomCpsFollowRange: FloatRange
    public var cpsSqueeze: Bool
    public var cpsSqueezeFactor: Double
    public var randomCpsSqueeze: Bool
    public var randomCpsSqueezeRange: FloatRange

    public init(
        enabled: Bool                     = false,
        probability: Double               = 100,
        spikeFactor: Double               = -0.3,
        whichSpike: String                = "ALL",
        spikeType: String                 = "SYMMETRICAL",
        spikeAxis: String                 = "XY",
        randomSpike: Bool                 = false,
        randomSpikeFactor: FloatRange     = FloatRange(min: -0.2, max: 0.2),
        cpsFollow: Bool                   = false,
        cpsFollowMultiplier: Double       = 2.0,
        randomCpsFollow: Bool             = false,
        randomCpsFollowRange: FloatRange  = FloatRange(min: -1.5, max: 1.5),
        cpsSqueeze: Bool                  = false,
        cpsSqueezeFactor: Double          = -0.2,
        randomCpsSqueeze: Bool            = false,
        randomCpsSqueezeRange: FloatRange = FloatRange(min: -0.5, max: 0.5)
    ) {
        self.enabled              = enabled
        self.probability          = probability
        self.spikeFactor          = spikeFactor
        self.whichSpike           = whichSpike
        self.spikeType            = spikeType
        self.spikeAxis            = spikeAxis
        self.randomSpike          = randomSpike
        self.randomSpikeFactor    = randomSpikeFactor
        self.cpsFollow            = cpsFollow
        self.cpsFollowMultiplier  = cpsFollowMultiplier
        self.randomCpsFollow      = randomCpsFollow
        self.randomCpsFollowRange = randomCpsFollowRange
        self.cpsSqueeze           = cpsSqueeze
        self.cpsSqueezeFactor     = cpsSqueezeFactor
        self.randomCpsSqueeze     = randomCpsSqueeze
        self.randomCpsSqueezeRange = randomCpsSqueezeRange
    }
}

public struct CentralAnchorsTransform: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var probability: Double
    /// Lerp factor toward the outside reference point.
    public var tearFactor: Double
    /// "XY", "X", "Y", "RANDOM"
    public var tearAxis: String
    /// "DIAGONAL", "LEFT", "RIGHT", "RANDOM"
    public var tearDirection: String
    public var randomTear: Bool
    public var randomTearFactor: FloatRange
    public var cpsFollow: Bool
    public var cpsFollowMultiplier: Double
    public var randomCpsFollow: Bool
    public var randomCpsFollowRange: FloatRange
    public var allPointsFollow: Bool
    public var invertedFollow: Bool

    public init(
        enabled: Bool                    = false,
        probability: Double              = 100,
        tearFactor: Double               = 0.2,
        tearAxis: String                 = "XY",
        tearDirection: String            = "DIAGONAL",
        randomTear: Bool                 = false,
        randomTearFactor: FloatRange     = FloatRange(min: -0.2, max: 0.2),
        cpsFollow: Bool                  = false,
        cpsFollowMultiplier: Double      = -7.0,
        randomCpsFollow: Bool            = false,
        randomCpsFollowRange: FloatRange = FloatRange(min: -1.5, max: 1.5),
        allPointsFollow: Bool            = false,
        invertedFollow: Bool             = false
    ) {
        self.enabled              = enabled
        self.probability          = probability
        self.tearFactor           = tearFactor
        self.tearAxis             = tearAxis
        self.tearDirection        = tearDirection
        self.randomTear           = randomTear
        self.randomTearFactor     = randomTearFactor
        self.cpsFollow            = cpsFollow
        self.cpsFollowMultiplier  = cpsFollowMultiplier
        self.randomCpsFollow      = randomCpsFollow
        self.randomCpsFollowRange = randomCpsFollowRange
        self.allPointsFollow      = allPointsFollow
        self.invertedFollow       = invertedFollow
    }
}

/// Curves the two outer control points on each exterior edge of a subdivided polygon.
///
/// Mirrors Scala `OuterControlPoints`.  Two modes:
/// - `PERPENDICULAR`: perpendicular offset based on the midpoint-to-control-point vector.
/// - `FROM_CENTRE`: offset toward/away from the absolute centre of all exterior anchors.
public struct OuterControlPointsTransform: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var probability: Double
    /// Lerp ratio for the first control point along the outer edge.
    public var lineRatioX: Double
    /// Lerp ratio for the second control point along the outer edge.
    public var lineRatioY: Double
    public var randomLineRatio: Bool
    /// Random range for the first (inner-side) ratio when `randomLineRatio` is true.
    public var randomLineRatioInner: FloatRange
    /// Random range for the second (outer-side) ratio when `randomLineRatio` is true.
    public var randomLineRatioOuter: FloatRange
    /// "PERPENDICULAR" or "FROM_CENTRE"
    public var curveMode: String
    /// "PUFF" | "PINCH" | "PUFF_PINCH_PUFF_PINCH" | "PUFF_PINCH_PINCH_PUFF" |
    /// "PINCH_PUFF_PUFF_PINCH" | "PINCH_PUFF_PINCH_PUFF"
    public var curveType: String
    /// Multiplier applied to the first control point's perpendicular offset.
    public var curveMultiplierMin: Double
    /// Multiplier applied to the second control point's perpendicular offset.
    public var curveMultiplierMax: Double
    public var randomMultiplier: Bool
    public var randomCurveMultiplier: FloatRange
    /// FROM_CENTRE ratio for the first control point.
    public var curveFromCentreRatioX: Double
    /// FROM_CENTRE ratio for the second control point.
    public var curveFromCentreRatioY: Double
    public var randomFromCentre: Bool
    public var randomFromCentreA: FloatRange
    public var randomFromCentreB: FloatRange

    public init(
        enabled: Bool                       = false,
        probability: Double                 = 100,
        lineRatioX: Double                  = 0.33,
        lineRatioY: Double                  = 0.66,
        randomLineRatio: Bool               = false,
        randomLineRatioInner: FloatRange    = FloatRange(min: 0.1, max: 0.5),
        randomLineRatioOuter: FloatRange    = FloatRange(min: 0.5, max: 0.9),
        curveMode: String                   = "PERPENDICULAR",
        curveType: String                   = "PUFF",
        curveMultiplierMin: Double          = 1.0,
        curveMultiplierMax: Double          = 3.0,
        randomMultiplier: Bool              = false,
        randomCurveMultiplier: FloatRange   = FloatRange(min: 0.5, max: 3.0),
        curveFromCentreRatioX: Double       = 0.2,
        curveFromCentreRatioY: Double       = -0.5,
        randomFromCentre: Bool              = false,
        randomFromCentreA: FloatRange       = FloatRange(min: -1.0, max: 1.0),
        randomFromCentreB: FloatRange       = FloatRange(min: -1.0, max: 1.0)
    ) {
        self.enabled               = enabled
        self.probability           = probability
        self.lineRatioX            = lineRatioX
        self.lineRatioY            = lineRatioY
        self.randomLineRatio       = randomLineRatio
        self.randomLineRatioInner  = randomLineRatioInner
        self.randomLineRatioOuter  = randomLineRatioOuter
        self.curveMode             = curveMode
        self.curveType             = curveType
        self.curveMultiplierMin    = curveMultiplierMin
        self.curveMultiplierMax    = curveMultiplierMax
        self.randomMultiplier      = randomMultiplier
        self.randomCurveMultiplier = randomCurveMultiplier
        self.curveFromCentreRatioX = curveFromCentreRatioX
        self.curveFromCentreRatioY = curveFromCentreRatioY
        self.randomFromCentre      = randomFromCentre
        self.randomFromCentreA     = randomFromCentreA
        self.randomFromCentreB     = randomFromCentreB
    }
}

/// Tears the two side-anchor pairs (pts[3,4] and pts[11,12] for QUAD) toward a reference point.
///
/// Mirrors Scala `AnchorsLinkedToCentre`.
public struct AnchorsLinkedToCentreTransform: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var probability: Double
    /// Lerp factor toward the reference (positive → moves toward it).
    public var tearFactor: Double
    /// "TOWARDS_OUTSIDE_CORNER" | "TOWARDS_OPPOSITE_CORNER" | "TOWARDS_CENTRE" | "RANDOM"
    public var tearType: String
    public var randomTear: Bool
    public var randomTearFactor: FloatRange
    /// Whether adjacent control points follow the anchor movement.
    public var cpsFollow: Bool
    public var cpsFollowMultiplier: Double
    public var randomCpsFollow: Bool
    public var randomCpsFollowRange: FloatRange

    public init(
        enabled: Bool                    = false,
        probability: Double              = 100,
        tearFactor: Double               = 0.45,
        tearType: String                 = "TOWARDS_OUTSIDE_CORNER",
        randomTear: Bool                 = false,
        randomTearFactor: FloatRange     = FloatRange(min: -0.2, max: 0.2),
        cpsFollow: Bool                  = true,
        cpsFollowMultiplier: Double      = 1.0,
        randomCpsFollow: Bool            = false,
        randomCpsFollowRange: FloatRange = FloatRange(min: -1.5, max: 1.5)
    ) {
        self.enabled              = enabled
        self.probability          = probability
        self.tearFactor           = tearFactor
        self.tearType             = tearType
        self.randomTear           = randomTear
        self.randomTearFactor     = randomTearFactor
        self.cpsFollow            = cpsFollow
        self.cpsFollowMultiplier  = cpsFollowMultiplier
        self.randomCpsFollow      = randomCpsFollow
        self.randomCpsFollowRange = randomCpsFollowRange
    }
}

/// Curves the inner control points (pts[5,6,9,10] for QUAD) on the internal subdivision lines.
///
/// Mirrors Scala `InnerControlPoints`.  Operates on the full polygon array
/// because adjacent polygons share internal lines.
public struct InnerControlPointsTransform: Equatable, Codable, Sendable {
    public var enabled: Bool
    public var probability: Double
    /// Relationship to the outer (exterior) control points.
    /// "NONE" | "FOLLOW" | "EXAGGERATE" | "COUNTER"
    public var referToOuter: String
    public var innerMultiplierX: Double
    public var innerMultiplierY: Double
    public var outerMultiplierX: Double
    public var outerMultiplierY: Double
    /// Lerp ratio for outer inner control points (TRI; also QUAD non-referToOuter).
    public var innerRatio: Double
    /// Lerp ratio for inner inner control points (TRI).
    public var outerRatio: Double
    public var randomRatio: Bool
    public var randomInnerRatio: FloatRange
    public var randomOuterRatio: FloatRange
    /// How adjoining control points on shared internal lines are positioned.
    /// "EVEN" | "ODD" | "RANDOM" | "NONE"
    public var commonLine: String

    public init(
        enabled: Bool                    = false,
        probability: Double              = 100,
        referToOuter: String             = "NONE",
        innerMultiplierX: Double         = 1.0,
        innerMultiplierY: Double         = 1.0,
        outerMultiplierX: Double         = 1.0,
        outerMultiplierY: Double         = 1.0,
        innerRatio: Double               = -0.15,
        outerRatio: Double               = 1.1,
        randomRatio: Bool                = false,
        randomInnerRatio: FloatRange     = FloatRange(min: -0.5, max: 0.5),
        randomOuterRatio: FloatRange     = FloatRange(min: -0.5, max: 0.5),
        commonLine: String               = "EVEN"
    ) {
        self.enabled           = enabled
        self.probability       = probability
        self.referToOuter      = referToOuter
        self.innerMultiplierX  = innerMultiplierX
        self.innerMultiplierY  = innerMultiplierY
        self.outerMultiplierX  = outerMultiplierX
        self.outerMultiplierY  = outerMultiplierY
        self.innerRatio        = innerRatio
        self.outerRatio        = outerRatio
        self.randomRatio       = randomRatio
        self.randomInnerRatio  = randomInnerRatio
        self.randomOuterRatio  = randomOuterRatio
        self.commonLine        = commonLine
    }
}

/// Container for all five PTP point transforms.
public struct PTPTransformSet: Equatable, Codable, Sendable {
    public var exteriorAnchors:      ExteriorAnchorsTransform
    public var centralAnchors:       CentralAnchorsTransform
    public var outerControlPoints:   OuterControlPointsTransform
    public var anchorsLinkedToCentre: AnchorsLinkedToCentreTransform
    public var innerControlPoints:   InnerControlPointsTransform

    public init(
        exteriorAnchors:       ExteriorAnchorsTransform       = ExteriorAnchorsTransform(),
        centralAnchors:        CentralAnchorsTransform        = CentralAnchorsTransform(),
        outerControlPoints:    OuterControlPointsTransform    = OuterControlPointsTransform(),
        anchorsLinkedToCentre: AnchorsLinkedToCentreTransform = AnchorsLinkedToCentreTransform(),
        innerControlPoints:    InnerControlPointsTransform    = InnerControlPointsTransform()
    ) {
        self.exteriorAnchors       = exteriorAnchors
        self.centralAnchors        = centralAnchors
        self.outerControlPoints    = outerControlPoints
        self.anchorsLinkedToCentre = anchorsLinkedToCentre
        self.innerControlPoints    = innerControlPoints
    }

    public var hasAnyEnabled: Bool {
        exteriorAnchors.enabled      ||
        centralAnchors.enabled       ||
        outerControlPoints.enabled   ||
        anchorsLinkedToCentre.enabled ||
        innerControlPoints.enabled
    }
}
