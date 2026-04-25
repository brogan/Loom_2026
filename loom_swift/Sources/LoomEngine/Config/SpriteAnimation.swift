import Foundation

// MARK: - Enumerations

/// The animation behaviour applied to a sprite each draw cycle.
public enum AnimationType: String, Codable, Sendable, CaseIterable {
    case keyframe      = "keyframe"
    case random        = "random"          // jitter — random translation/scale/rotation
    case keyframeMorph = "keyframe_morph"  // keyframe with morph target interpolation
    case jitterMorph   = "jitter_morph"    // random morph amount between targets
}

/// How a keyframe sequence repeats at the end.
public enum LoopMode: String, Codable, Sendable, CaseIterable {
    case loop     = "LOOP"
    case pingPong = "PING_PONG"
    case once     = "ONCE"
}

/// Easing function applied between two keyframes.
public enum EasingType: String, Codable, Sendable, CaseIterable {
    case linear          = "LINEAR"
    case easeInOutQuad   = "EASE_IN_OUT_QUAD"
    case easeInQuad      = "EASE_IN_QUAD"
    case easeOutQuad     = "EASE_OUT_QUAD"
    case easeInOutCubic  = "EASE_IN_OUT_CUBIC"
    case easeInCubic     = "EASE_IN_CUBIC"
    case easeOutCubic    = "EASE_OUT_CUBIC"
}

// MARK: - Keyframe

/// One keyframe in a sprite animation sequence.
///
/// `drawCycle` is the frame index at which this keyframe applies.
/// The engine interpolates between consecutive keyframes using `easing`.
/// `morphAmount` is meaningful only for `keyframe_morph` animation:
/// integer part selects the target (1 = first `MorphTarget`, 2 = second, …),
/// fractional part controls blend toward the next integer target.
public struct Keyframe: Equatable, Codable, Sendable {
    public var drawCycle:   Int
    public var position:    Vector2D
    public var scale:       Vector2D
    public var rotation:    Double      // degrees
    public var easing:      EasingType
    public var morphAmount: Double      // 0 for non-morph animations

    public init(
        drawCycle:   Int        = 0,
        position:    Vector2D   = .zero,
        scale:       Vector2D   = Vector2D(x: 1, y: 1),
        rotation:    Double     = 0,
        easing:      EasingType = .linear,
        morphAmount: Double     = 0
    ) {
        self.drawCycle   = drawCycle
        self.position    = position
        self.scale       = scale
        self.rotation    = rotation
        self.easing      = easing
        self.morphAmount = morphAmount
    }
}

// MARK: - MorphTargetRef

/// Reference to a morph target polygon file.
///
/// `file` is a bare filename (e.g. `"saw_mt_1.poly.xml"`) resolved
/// relative to the project's `morphTargets/` directory at load time.
public struct MorphTargetRef: Equatable, Codable, Sendable {
    public var file: String

    public init(file: String = "") {
        self.file = file
    }
}

// MARK: - SpriteAnimation

/// Full animation specification for one sprite, parsed from `<Animation>` in `sprites.xml`.
///
/// ### Transform animation
/// All four types share `translationRange`, `scaleRange`, and `rotationRange`.
/// For `random` (jitter), these supply the per-frame random bounds.
/// For `keyframe` and morph variants, keyframes override the ranges — the
/// ranges serve as a fallback / editor hint only.
///
/// ### Morph animation
/// `keyframe_morph` keyframes carry a `morphAmount` value:
/// integer part selects the morph target (1-based); fractional part blends toward
/// the next integer target.
/// `jitter_morph` picks a random value in [`morphMin`, `morphMax`] each frame.
public struct SpriteAnimation: Equatable, Codable, Sendable {

    public var enabled:          Bool
    public var type:             AnimationType
    public var loopMode:         LoopMode
    /// 0 = draw indefinitely.
    public var totalDraws:       Int
    public var translationRange: VectorRange
    public var scaleRange:       VectorRange
    public var rotationRange:    FloatRange
    public var keyframes:        [Keyframe]
    public var morphTargets:     [MorphTargetRef]
    /// Minimum morph amount for `jitter_morph` (applied to `morphTargets` array).
    public var morphMin:         Double
    /// Maximum morph amount for `jitter_morph`.
    public var morphMax:         Double

    public init(
        enabled:          Bool          = false,
        type:             AnimationType = .random,
        loopMode:         LoopMode      = .loop,
        totalDraws:       Int           = 0,
        translationRange: VectorRange   = .zero,
        scaleRange:       VectorRange   = .zero,
        rotationRange:    FloatRange    = .zero,
        keyframes:        [Keyframe]    = [],
        morphTargets:     [MorphTargetRef] = [],
        morphMin:         Double        = 0,
        morphMax:         Double        = 0
    ) {
        self.enabled          = enabled
        self.type             = type
        self.loopMode         = loopMode
        self.totalDraws       = totalDraws
        self.translationRange = translationRange
        self.scaleRange       = scaleRange
        self.rotationRange    = rotationRange
        self.keyframes        = keyframes
        self.morphTargets     = morphTargets
        self.morphMin         = morphMin
        self.morphMax         = morphMax
    }

    /// Disabled animation with all defaults — used for non-animated sprites.
    public static let disabled = SpriteAnimation()
}
