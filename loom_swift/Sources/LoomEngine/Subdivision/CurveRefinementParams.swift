import Foundation

// MARK: - CurveDistributionMode

public enum CurveDistributionMode: String, Codable, CaseIterable, Equatable, Sendable {
    case linear      = "Linear"
    case exponential = "Exponential"
    case random      = "Random"
}

// MARK: - CurveDisplacementMode

public enum CurveDisplacementMode: String, Codable, CaseIterable, Equatable, Sendable {
    case jitter = "Jitter"
    case lazy   = "Lazy"
}

// MARK: - CurveRefinementCPMode

public enum CurveRefinementCPMode: String, Codable, CaseIterable, Equatable, Sendable {
    case smooth   = "Smooth"
    case straight = "Straight"
    case bowed    = "Bowed"
}

// MARK: - CurvePressureMode

public enum CurvePressureMode: String, Codable, CaseIterable, Equatable, Sendable {
    case constant   = "Constant"
    case increasing = "Increasing"
    case decreasing = "Decreasing"
    case wave       = "Wave"
}

// MARK: - CurveRefinementDrivers

public struct CurveRefinementDrivers: Equatable, Codable, Sendable {
    public var displacement:   DoubleDriver = .zero
    public var cpNormalOffset: DoubleDriver = .zero

    public init(
        displacement:   DoubleDriver = .zero,
        cpNormalOffset: DoubleDriver = .zero
    ) {
        self.displacement   = displacement
        self.cpNormalOffset = cpNormalOffset
    }
}

// MARK: - CurveRefinementParams

/// Configuration for one pass of open-curve refinement.
///
/// A list of these on a `SubdivisionParamsSet` constitutes the full
/// curve-refinement recipe for sprites that contain `.openSpline` polygons.
/// Each pass is applied sequentially by `CurveRefinementEngine`.
public struct CurveRefinementParams: Equatable, Codable, Sendable {

    public var name:    String
    public var enabled: Bool

    // MARK: Insertion
    public var insertionCount:       Int
    public var distributionMode:     CurveDistributionMode
    public var distributionExponent: Double
    public var distributionReverse:  Bool
    public var distributionSeed:     Int

    // MARK: Displacement
    public var displacement:     Double
    public var displacementMode: CurveDisplacementMode
    public var lazyPeriod:       Int
    public var lazySeed:         Int

    // MARK: Control points
    public var cpMode:         CurveRefinementCPMode
    public var cpNormalOffset: Double

    // MARK: Pressure
    public var pressureMode:  CurvePressureMode
    public var pressureValue: Double

    // MARK: Drivers
    public var drivers: CurveRefinementDrivers?

    public init(
        name:                String                  = "",
        enabled:             Bool                    = true,
        insertionCount:      Int                     = 2,
        distributionMode:    CurveDistributionMode   = .linear,
        distributionExponent: Double                 = 2.0,
        distributionReverse: Bool                    = false,
        distributionSeed:    Int                     = 0,
        displacement:        Double                  = 0,
        displacementMode:    CurveDisplacementMode   = .lazy,
        lazyPeriod:          Int                     = 30,
        lazySeed:            Int                     = 0,
        cpMode:              CurveRefinementCPMode   = .smooth,
        cpNormalOffset:      Double                  = 0,
        pressureMode:        CurvePressureMode       = .constant,
        pressureValue:       Double                  = 1.0,
        drivers:             CurveRefinementDrivers? = nil
    ) {
        self.name                 = name
        self.enabled              = enabled
        self.insertionCount       = insertionCount
        self.distributionMode     = distributionMode
        self.distributionExponent = distributionExponent
        self.distributionReverse  = distributionReverse
        self.distributionSeed     = distributionSeed
        self.displacement         = displacement
        self.displacementMode     = displacementMode
        self.lazyPeriod           = lazyPeriod
        self.lazySeed             = lazySeed
        self.cpMode               = cpMode
        self.cpNormalOffset       = cpNormalOffset
        self.pressureMode         = pressureMode
        self.pressureValue        = pressureValue
        self.drivers              = drivers
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled
        case insertionCount, distributionMode, distributionExponent, distributionReverse, distributionSeed
        case displacement, displacementMode, lazyPeriod, lazySeed
        case cpMode, cpNormalOffset
        case pressureMode, pressureValue
        case drivers
    }

    public init(from decoder: Decoder) throws {
        let d = CurveRefinementParams()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name:                try c.decodeIfPresent(String.self,                 forKey: .name)                ?? d.name,
            enabled:             try c.decodeIfPresent(Bool.self,                   forKey: .enabled)             ?? d.enabled,
            insertionCount:      try c.decodeIfPresent(Int.self,                    forKey: .insertionCount)      ?? d.insertionCount,
            distributionMode:    try c.decodeIfPresent(CurveDistributionMode.self,  forKey: .distributionMode)    ?? d.distributionMode,
            distributionExponent: try c.decodeIfPresent(Double.self,               forKey: .distributionExponent) ?? d.distributionExponent,
            distributionReverse: try c.decodeIfPresent(Bool.self,                   forKey: .distributionReverse) ?? d.distributionReverse,
            distributionSeed:    try c.decodeIfPresent(Int.self,                    forKey: .distributionSeed)    ?? d.distributionSeed,
            displacement:        try c.decodeIfPresent(Double.self,                 forKey: .displacement)        ?? d.displacement,
            displacementMode:    try c.decodeIfPresent(CurveDisplacementMode.self,  forKey: .displacementMode)    ?? d.displacementMode,
            lazyPeriod:          try c.decodeIfPresent(Int.self,                    forKey: .lazyPeriod)          ?? d.lazyPeriod,
            lazySeed:            try c.decodeIfPresent(Int.self,                    forKey: .lazySeed)            ?? d.lazySeed,
            cpMode:              try c.decodeIfPresent(CurveRefinementCPMode.self,  forKey: .cpMode)              ?? d.cpMode,
            cpNormalOffset:      try c.decodeIfPresent(Double.self,                 forKey: .cpNormalOffset)      ?? d.cpNormalOffset,
            pressureMode:        try c.decodeIfPresent(CurvePressureMode.self,      forKey: .pressureMode)        ?? d.pressureMode,
            pressureValue:       try c.decodeIfPresent(Double.self,                 forKey: .pressureValue)       ?? d.pressureValue,
            drivers:             try c.decodeIfPresent(CurveRefinementDrivers.self, forKey: .drivers)
        )
    }
}
