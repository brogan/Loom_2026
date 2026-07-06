import Foundation

public enum EntropyTarget: String, Codable, CaseIterable, Equatable, Sendable {
    case centroid = "centroid"
    case smoothed = "smoothed"
    case circle   = "circle"
}

public enum CollapseMode: String, Codable, CaseIterable, Equatable, Sendable {
    case instant = "instant"
    case brief   = "brief"
}

public enum CollapseTriggerType: String, Codable, CaseIterable, Equatable, Sendable {
    case frameCount  = "frameCount"
    case probability = "probability"
}

public enum CollapseEndMode: String, Codable, CaseIterable, Equatable, Sendable {
    case remove  = "remove"
    case loop    = "loop"
    case respawn = "respawn"
}

public struct DissolutionParams: Equatable, Codable, Sendable {

    public var name:    String = ""
    public var enabled: Bool   = true

    // Entropy
    public var entropyEnabled: Bool          = false
    public var entropyRate:    Double        = 0.005
    public var entropyTarget:  EntropyTarget = .smoothed
    public var entropyNoise:   Double        = 0.0
    public var entropySeed:    Int           = 0

    // Collapse
    public var collapseEnabled:            Bool                = false
    public var collapseMode:               CollapseMode        = .instant
    public var collapseBriefDuration:      Int                 = 6
    public var collapseTriggerType:        CollapseTriggerType = .frameCount
    public var collapseTriggerFrameCount:  Int                 = 120
    public var collapseTriggerProbability: Double              = 0.01
    public var collapseEndMode:            CollapseEndMode     = .loop

    public init(name: String = "") {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled
        case entropyEnabled, entropyRate, entropyTarget, entropyNoise, entropySeed
        case collapseEnabled, collapseMode, collapseBriefDuration
        case collapseTriggerType, collapseTriggerFrameCount, collapseTriggerProbability
        case collapseEndMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name    = (try? c.decodeIfPresent(String.self,  forKey: .name))    ?? ""
        enabled = (try? c.decodeIfPresent(Bool.self,    forKey: .enabled)) ?? true

        entropyEnabled = (try? c.decodeIfPresent(Bool.self,          forKey: .entropyEnabled)) ?? false
        entropyRate    = (try? c.decodeIfPresent(Double.self,         forKey: .entropyRate))    ?? 0.005
        entropyTarget  = (try? c.decodeIfPresent(EntropyTarget.self,  forKey: .entropyTarget))  ?? .smoothed
        entropyNoise   = (try? c.decodeIfPresent(Double.self,         forKey: .entropyNoise))   ?? 0.0
        entropySeed    = (try? c.decodeIfPresent(Int.self,            forKey: .entropySeed))    ?? 0

        collapseEnabled            = (try? c.decodeIfPresent(Bool.self,                 forKey: .collapseEnabled))            ?? false
        collapseMode               = (try? c.decodeIfPresent(CollapseMode.self,         forKey: .collapseMode))               ?? .instant
        collapseBriefDuration      = (try? c.decodeIfPresent(Int.self,                  forKey: .collapseBriefDuration))      ?? 6
        collapseTriggerType        = (try? c.decodeIfPresent(CollapseTriggerType.self,  forKey: .collapseTriggerType))        ?? .frameCount
        collapseTriggerFrameCount  = (try? c.decodeIfPresent(Int.self,                  forKey: .collapseTriggerFrameCount))  ?? 120
        collapseTriggerProbability = (try? c.decodeIfPresent(Double.self,               forKey: .collapseTriggerProbability)) ?? 0.01
        collapseEndMode            = (try? c.decodeIfPresent(CollapseEndMode.self,      forKey: .collapseEndMode))            ?? .loop
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,    forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(entropyEnabled, forKey: .entropyEnabled)
        try c.encode(entropyRate,    forKey: .entropyRate)
        try c.encode(entropyTarget,  forKey: .entropyTarget)
        try c.encode(entropyNoise,   forKey: .entropyNoise)
        try c.encode(entropySeed,    forKey: .entropySeed)
        try c.encode(collapseEnabled,            forKey: .collapseEnabled)
        try c.encode(collapseMode,               forKey: .collapseMode)
        try c.encode(collapseBriefDuration,      forKey: .collapseBriefDuration)
        try c.encode(collapseTriggerType,        forKey: .collapseTriggerType)
        try c.encode(collapseTriggerFrameCount,  forKey: .collapseTriggerFrameCount)
        try c.encode(collapseTriggerProbability, forKey: .collapseTriggerProbability)
        try c.encode(collapseEndMode,            forKey: .collapseEndMode)
    }
}
