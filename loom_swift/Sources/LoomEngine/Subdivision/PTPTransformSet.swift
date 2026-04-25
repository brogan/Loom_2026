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

/// Container for both exterior-anchor and central-anchor point transforms.
public struct PTPTransformSet: Equatable, Codable, Sendable {
    public var exteriorAnchors: ExteriorAnchorsTransform
    public var centralAnchors: CentralAnchorsTransform

    public init(
        exteriorAnchors: ExteriorAnchorsTransform = ExteriorAnchorsTransform(),
        centralAnchors: CentralAnchorsTransform   = CentralAnchorsTransform()
    ) {
        self.exteriorAnchors = exteriorAnchors
        self.centralAnchors  = centralAnchors
    }

    public var hasAnyEnabled: Bool {
        exteriorAnchors.enabled || centralAnchors.enabled
    }
}
