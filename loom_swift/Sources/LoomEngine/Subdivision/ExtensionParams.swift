import Foundation

public enum ExtensionOperationType: String, Codable, CaseIterable, Equatable, Sendable {
    case branch  = "Branch"
    case extrude = "Extrude"
}

public enum ExtrusionTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case allEdges    = "All Edges"
    case longestEdge = "Longest Edge"
}

public struct ExtensionParams: Equatable, Codable, Sendable {
    public var name:          String
    public var enabled:       Bool
    public var operationType: ExtensionOperationType

    // Branch settings (operationType == .branch)
    public var branchAngle:       DoubleDriver  // degrees from endpoint tangent
    public var branchAngleJitter: Double        // max random perturbation, degrees
    public var branchScaleRatio:  Double        // scale factor per depth level
    public var branchDepth:       Int           // recursion depth (engine caps at 8)
    public var branchCount:       Int           // branches per endpoint
    public var branchProbability: Double        // 0.0–1.0 spawn probability
    public var branchSeed:        Int           // deterministic seed

    // Extrusion settings (operationType == .extrude)
    public var extrusionDistance:    DoubleDriver
    public var extrusionWidth:       Double      // 1.0 = parallel, <1 = taper, >1 = flare
    public var extrusionCurvature:   Double      // bow on outer edge (fraction of edge length)
    public var extrusionGenerations: Int         // recursive outer-face extrusion levels
    public var extrusionTarget:      ExtrusionTarget

    public init(
        name:                String              = "",
        enabled:             Bool                = true,
        operationType:       ExtensionOperationType = .branch,
        branchAngle:         DoubleDriver        = .constant(45.0),
        branchAngleJitter:   Double              = 0.0,
        branchScaleRatio:    Double              = 0.6,
        branchDepth:         Int                 = 2,
        branchCount:         Int                 = 2,
        branchProbability:   Double              = 1.0,
        branchSeed:          Int                 = 0,
        extrusionDistance:   DoubleDriver        = .constant(0.1),
        extrusionWidth:      Double              = 1.0,
        extrusionCurvature:  Double              = 0.0,
        extrusionGenerations: Int               = 1,
        extrusionTarget:     ExtrusionTarget     = .allEdges
    ) {
        self.name                = name
        self.enabled             = enabled
        self.operationType       = operationType
        self.branchAngle         = branchAngle
        self.branchAngleJitter   = branchAngleJitter
        self.branchScaleRatio    = branchScaleRatio
        self.branchDepth         = branchDepth
        self.branchCount         = branchCount
        self.branchProbability   = branchProbability
        self.branchSeed          = branchSeed
        self.extrusionDistance   = extrusionDistance
        self.extrusionWidth      = extrusionWidth
        self.extrusionCurvature  = extrusionCurvature
        self.extrusionGenerations = extrusionGenerations
        self.extrusionTarget     = extrusionTarget
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name, enabled, operationType
        case branchAngle, branchAngleJitter, branchScaleRatio
        case branchDepth, branchCount, branchProbability, branchSeed
        case extrusionDistance, extrusionWidth, extrusionCurvature
        case extrusionGenerations, extrusionTarget
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name               = try c.decodeIfPresent(String.self,                 forKey: .name)               ?? ""
        enabled            = try c.decodeIfPresent(Bool.self,                   forKey: .enabled)            ?? true
        operationType      = try c.decodeIfPresent(ExtensionOperationType.self, forKey: .operationType)      ?? .branch
        branchAngle        = try c.decodeIfPresent(DoubleDriver.self,           forKey: .branchAngle)        ?? .constant(45.0)
        branchAngleJitter  = try c.decodeIfPresent(Double.self,                 forKey: .branchAngleJitter)  ?? 0.0
        branchScaleRatio   = try c.decodeIfPresent(Double.self,                 forKey: .branchScaleRatio)   ?? 0.6
        branchDepth        = try c.decodeIfPresent(Int.self,                    forKey: .branchDepth)        ?? 2
        branchCount        = try c.decodeIfPresent(Int.self,                    forKey: .branchCount)        ?? 2
        branchProbability  = try c.decodeIfPresent(Double.self,                 forKey: .branchProbability)  ?? 1.0
        branchSeed         = try c.decodeIfPresent(Int.self,                    forKey: .branchSeed)         ?? 0
        extrusionDistance    = try c.decodeIfPresent(DoubleDriver.self,    forKey: .extrusionDistance)    ?? .constant(0.1)
        extrusionWidth       = try c.decodeIfPresent(Double.self,          forKey: .extrusionWidth)       ?? 1.0
        extrusionCurvature   = try c.decodeIfPresent(Double.self,          forKey: .extrusionCurvature)   ?? 0.0
        extrusionGenerations = try c.decodeIfPresent(Int.self,             forKey: .extrusionGenerations) ?? 1
        extrusionTarget      = try c.decodeIfPresent(ExtrusionTarget.self, forKey: .extrusionTarget)      ?? .allEdges
    }
}
