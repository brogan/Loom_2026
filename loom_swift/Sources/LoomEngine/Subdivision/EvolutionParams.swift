import Foundation

public enum EvolutionOperationType: String, Codable, CaseIterable, Equatable, Sendable {
    case momentumDrift       = "Momentum Drift"
    case convergencePressure = "Convergence Pressure"
}

public enum DriftTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case lineRatioX    = "Line Ratio X"
    case lineRatioY    = "Line Ratio Y"
    case lineRatioXY   = "Line Ratio XY"
    case cpNormalX     = "CP Normal X"
    case cpNormalY     = "CP Normal Y"
    case insetScale    = "Inset Scale"
    case insetRotation = "Inset Rotation"
}

public enum ConvergenceMode: String, Codable, CaseIterable, Equatable, Sendable {
    case hold      = "Hold"
    case oscillate = "Oscillate"
    case loop      = "Loop"
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
        convergenceDuration:      Double                  = 120.0
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
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name, enabled, operationType
        case driftTarget, driftMomentum, driftNoiseStrength, driftNoiseFrequency, driftSeed
        case convergenceTargetSetName, convergencePressure, convergenceMode, convergenceDuration
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
    }
}
