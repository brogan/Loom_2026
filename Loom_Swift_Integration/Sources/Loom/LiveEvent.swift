import Foundation
import LoomEngine

/// One recorded Live-tab interaction — the event-log schema from
/// `SessionWorkflow.md` §3.2. `t` is a project frame number (matching
/// `DoubleKeyframe.frame`/`VectorKeyframe.frame` and the unit
/// `VideoExporter` steps in), not a wall-clock second — see that section
/// for why. Every case only carries the fields that kind actually needs,
/// rather than one struct with a pile of optionals.
enum LiveEvent {
    case spriteShow(t: Int, instanceName: String, spriteSetName: String, spriteName: String,
                     position: Vector2D, scale: Vector2D, rotation: Double)
    case spriteHide(t: Int, instanceName: String)
    case poseUpdate(t: Int, instanceName: String, position: Vector2D, scale: Vector2D, rotation: Double)
    case rendererSetAssign(t: Int, instanceName: String, rendererSetName: String)
    case transformSetAssign(t: Int, instanceName: String, subdivisionSetName: String)
    case driverEnabledToggle(t: Int, instanceName: String, target: LiveDriverTarget, enabled: Bool)
    /// The continuous counterpart — one point per coalesced slider commit,
    /// not one per raw drag tick. Consecutive points sharing
    /// `(instanceName, target, quantity, axis)` form a curve when grouped
    /// at replay time; there's no separate "curve" object in the log.
    case driverAutomationPoint(t: Int, instanceName: String, target: LiveDriverTarget,
                                quantity: String, axis: String?, value: Double)
    /// BPM/time-signature changed — `LoomLiveV1Scope.md` §2.6.
    case bpmSet(t: Int, bpm: Double, beatsPerBar: Int)
    /// The user tapped the downbeat button, aligning the musical clock's
    /// bar-1 reference to this frame.
    case tapSync(t: Int, referenceFrame: Int)
    /// A driver's Rate was switched to (non-nil multiplier, cycles/bar) or
    /// away from (nil) BPM-linked musical mode.
    case driverMusicalRateAssign(t: Int, instanceName: String, target: LiveDriverTarget, multiplier: Double?)

    var t: Int {
        switch self {
        case .spriteShow(let t, _, _, _, _, _, _):           return t
        case .spriteHide(let t, _):                          return t
        case .poseUpdate(let t, _, _, _, _):                 return t
        case .rendererSetAssign(let t, _, _):                return t
        case .transformSetAssign(let t, _, _):                return t
        case .driverEnabledToggle(let t, _, _, _):           return t
        case .driverAutomationPoint(let t, _, _, _, _, _):   return t
        case .bpmSet(let t, _, _):                           return t
        case .tapSync(let t, _):                             return t
        case .driverMusicalRateAssign(let t, _, _, _):       return t
        }
    }

    /// Returns a copy of this event with `t` replaced — used to rebase
    /// recorded frame numbers to "frames since recording started" rather
    /// than "frames since the Live tab's engine was created" (the engine
    /// keeps ticking from when the tab was opened, not from when the user
    /// pressed Start; see `LiveSessionController.recordEvent`).
    func withT(_ newT: Int) -> LiveEvent {
        switch self {
        case .spriteShow(_, let instanceName, let spriteSetName, let spriteName, let position, let scale, let rotation):
            return .spriteShow(t: newT, instanceName: instanceName, spriteSetName: spriteSetName, spriteName: spriteName,
                               position: position, scale: scale, rotation: rotation)
        case .spriteHide(_, let instanceName):
            return .spriteHide(t: newT, instanceName: instanceName)
        case .poseUpdate(_, let instanceName, let position, let scale, let rotation):
            return .poseUpdate(t: newT, instanceName: instanceName, position: position, scale: scale, rotation: rotation)
        case .rendererSetAssign(_, let instanceName, let rendererSetName):
            return .rendererSetAssign(t: newT, instanceName: instanceName, rendererSetName: rendererSetName)
        case .transformSetAssign(_, let instanceName, let subdivisionSetName):
            return .transformSetAssign(t: newT, instanceName: instanceName, subdivisionSetName: subdivisionSetName)
        case .driverEnabledToggle(_, let instanceName, let target, let enabled):
            return .driverEnabledToggle(t: newT, instanceName: instanceName, target: target, enabled: enabled)
        case .driverAutomationPoint(_, let instanceName, let target, let quantity, let axis, let value):
            return .driverAutomationPoint(t: newT, instanceName: instanceName, target: target, quantity: quantity, axis: axis, value: value)
        case .bpmSet(_, let bpm, let beatsPerBar):
            return .bpmSet(t: newT, bpm: bpm, beatsPerBar: beatsPerBar)
        case .tapSync(_, let referenceFrame):
            return .tapSync(t: newT, referenceFrame: referenceFrame)
        case .driverMusicalRateAssign(_, let instanceName, let target, let multiplier):
            return .driverMusicalRateAssign(t: newT, instanceName: instanceName, target: target, multiplier: multiplier)
        }
    }
}

// MARK: - Codable
//
// Manual implementation keyed on a "type" string — the same pattern already
// used throughout LoomEngine for every other mode-tagged config type
// (DoubleDriver, ColorDriver, and so on), producing the flat
// `{"t": 0, "type": "...", ...}` JSON shape documented in `SessionWorkflow.md` §3.2.

extension LiveEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case t, type, instanceName, spriteSetName, spriteName, position, scale, rotation,
             rendererSetName, subdivisionSetName, target, enabled, quantity, axis, value,
             bpm, beatsPerBar, referenceFrame, multiplier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(Int.self, forKey: .t)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "spriteShow":
            self = .spriteShow(
                t: t,
                instanceName: try c.decode(String.self, forKey: .instanceName),
                spriteSetName: try c.decode(String.self, forKey: .spriteSetName),
                spriteName: try c.decode(String.self, forKey: .spriteName),
                position: try c.decode(Vector2D.self, forKey: .position),
                scale: try c.decode(Vector2D.self, forKey: .scale),
                rotation: try c.decode(Double.self, forKey: .rotation)
            )
        case "spriteHide":
            self = .spriteHide(t: t, instanceName: try c.decode(String.self, forKey: .instanceName))
        case "poseUpdate":
            self = .poseUpdate(
                t: t,
                instanceName: try c.decode(String.self, forKey: .instanceName),
                position: try c.decode(Vector2D.self, forKey: .position),
                scale: try c.decode(Vector2D.self, forKey: .scale),
                rotation: try c.decode(Double.self, forKey: .rotation)
            )
        case "rendererSetAssign":
            self = .rendererSetAssign(
                t: t,
                instanceName: try c.decode(String.self, forKey: .instanceName),
                rendererSetName: try c.decode(String.self, forKey: .rendererSetName)
            )
        case "transformSetAssign":
            self = .transformSetAssign(
                t: t,
                instanceName: try c.decode(String.self, forKey: .instanceName),
                subdivisionSetName: try c.decode(String.self, forKey: .subdivisionSetName)
            )
        case "driverEnabledToggle":
            self = .driverEnabledToggle(
                t: t,
                instanceName: try c.decode(String.self, forKey: .instanceName),
                target: try c.decode(LiveDriverTarget.self, forKey: .target),
                enabled: try c.decode(Bool.self, forKey: .enabled)
            )
        case "driverAutomationPoint":
            self = .driverAutomationPoint(
                t: t,
                instanceName: try c.decode(String.self, forKey: .instanceName),
                target: try c.decode(LiveDriverTarget.self, forKey: .target),
                quantity: try c.decode(String.self, forKey: .quantity),
                axis: try c.decodeIfPresent(String.self, forKey: .axis),
                value: try c.decode(Double.self, forKey: .value)
            )
        case "bpmSet":
            self = .bpmSet(
                t: t,
                bpm: try c.decode(Double.self, forKey: .bpm),
                beatsPerBar: try c.decode(Int.self, forKey: .beatsPerBar)
            )
        case "tapSync":
            self = .tapSync(t: t, referenceFrame: try c.decode(Int.self, forKey: .referenceFrame))
        case "driverMusicalRateAssign":
            self = .driverMusicalRateAssign(
                t: t,
                instanceName: try c.decode(String.self, forKey: .instanceName),
                target: try c.decode(LiveDriverTarget.self, forKey: .target),
                multiplier: try c.decodeIfPresent(Double.self, forKey: .multiplier)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown LiveEvent type '\(type)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t)
        switch self {
        case .spriteShow(_, let instanceName, let spriteSetName, let spriteName, let position, let scale, let rotation):
            try c.encode("spriteShow", forKey: .type)
            try c.encode(instanceName, forKey: .instanceName)
            try c.encode(spriteSetName, forKey: .spriteSetName)
            try c.encode(spriteName, forKey: .spriteName)
            try c.encode(position, forKey: .position)
            try c.encode(scale, forKey: .scale)
            try c.encode(rotation, forKey: .rotation)
        case .spriteHide(_, let instanceName):
            try c.encode("spriteHide", forKey: .type)
            try c.encode(instanceName, forKey: .instanceName)
        case .poseUpdate(_, let instanceName, let position, let scale, let rotation):
            try c.encode("poseUpdate", forKey: .type)
            try c.encode(instanceName, forKey: .instanceName)
            try c.encode(position, forKey: .position)
            try c.encode(scale, forKey: .scale)
            try c.encode(rotation, forKey: .rotation)
        case .rendererSetAssign(_, let instanceName, let rendererSetName):
            try c.encode("rendererSetAssign", forKey: .type)
            try c.encode(instanceName, forKey: .instanceName)
            try c.encode(rendererSetName, forKey: .rendererSetName)
        case .transformSetAssign(_, let instanceName, let subdivisionSetName):
            try c.encode("transformSetAssign", forKey: .type)
            try c.encode(instanceName, forKey: .instanceName)
            try c.encode(subdivisionSetName, forKey: .subdivisionSetName)
        case .driverEnabledToggle(_, let instanceName, let target, let enabled):
            try c.encode("driverEnabledToggle", forKey: .type)
            try c.encode(instanceName, forKey: .instanceName)
            try c.encode(target, forKey: .target)
            try c.encode(enabled, forKey: .enabled)
        case .driverAutomationPoint(_, let instanceName, let target, let quantity, let axis, let value):
            try c.encode("driverAutomationPoint", forKey: .type)
            try c.encode(instanceName, forKey: .instanceName)
            try c.encode(target, forKey: .target)
            try c.encode(quantity, forKey: .quantity)
            try c.encodeIfPresent(axis, forKey: .axis)
            try c.encode(value, forKey: .value)
        case .bpmSet(_, let bpm, let beatsPerBar):
            try c.encode("bpmSet", forKey: .type)
            try c.encode(bpm, forKey: .bpm)
            try c.encode(beatsPerBar, forKey: .beatsPerBar)
        case .tapSync(_, let referenceFrame):
            try c.encode("tapSync", forKey: .type)
            try c.encode(referenceFrame, forKey: .referenceFrame)
        case .driverMusicalRateAssign(_, let instanceName, let target, let multiplier):
            try c.encode("driverMusicalRateAssign", forKey: .type)
            try c.encode(instanceName, forKey: .instanceName)
            try c.encode(target, forKey: .target)
            try c.encodeIfPresent(multiplier, forKey: .multiplier)
        }
    }
}
