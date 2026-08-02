import Foundation

// MARK: - DriverLaneSegment
//
// A named, time-bounded override of one of TransformDrivers' lanes. Where a
// segment's [startFrame, endFrame) range covers the current frame, its own
// driver value is used for that lane instead of the base field; outside any
// segment (or with none defined) the base field applies exactly as before
// segments existed — this mirrors CameraSegment's fallback semantics, but
// per-lane rather than bundling all lanes into one segment, since sprite
// drivers (unlike camera's 4 tightly-coupled fields) are already evaluated
// independently of one another and plausibly need independently-timed
// overrides (e.g. Position keyframed 0-100, Rotation oscillating 100-500).
//
// `laneRawValue` matches the app-side `TimelineLane.rawValue` (0=position,
// 1=scale, 2=rotation, 3=morph, 4=opacity for v1) — stored as a plain Int
// rather than a shared enum type since `TimelineLane` lives in the app
// target, not this engine package; the engine only needs to know which
// numbered lane a segment overrides, not the UI's lane names.
public enum DriverSegmentValue: Codable, Equatable, Sendable {
    case vector(VectorDriver)
    case double(DoubleDriver)
}

public struct DriverLaneSegment: Codable, Equatable, Sendable, Identifiable {
    public var id:   UUID   = UUID()
    public var name: String = ""
    public var laneRawValue: Int
    public var startFrame: Int
    public var endFrame:   Int
    public var value: DriverSegmentValue

    public init(
        id:           UUID   = UUID(),
        name:         String = "",
        laneRawValue: Int,
        startFrame:   Int,
        endFrame:     Int,
        value:        DriverSegmentValue
    ) {
        self.id           = id
        self.name         = name
        self.laneRawValue = laneRawValue
        self.startFrame   = startFrame
        self.endFrame     = endFrame
        self.value        = value
    }
}

// MARK: - TransformDrivers
//
// Per-property animation drivers for one sprite.  When a sprite's
// `SpriteAnimation.drivers` is non-nil this struct is used instead of the
// legacy flat AnimationType path.

public struct TransformDrivers: Codable, Equatable, Sendable {

    /// Position offset (world-space units — same convention as `SpriteDef.position`).
    /// Uses loopMode .once so keyframe motion reaches its end value and stays there.
    public var position: VectorDriver = VectorDriver(mode: .constant, base: .zero,                    loopMode: .once)
    /// Scale multiplier on top of `SpriteDef.scale`.  Identity = (1, 1).
    /// Uses loopMode .once so keyframe scaling reaches its end value and stays there.
    public var scale:    VectorDriver = VectorDriver(mode: .constant, base: Vector2D(x: 1, y: 1),    loopMode: .once)
    /// Rotation in degrees, added to `SpriteDef.rotation`.
    /// Uses loopMode .once so keyframe rotation reaches its end value and stays there.
    public var rotation: DoubleDriver = DoubleDriver(mode: .constant, base: 0,                        loopMode: .once)
    /// Morph blend amount (same encoding as legacy `morphAmount` — integer part
    /// selects morph target index (1-based), fractional part blends toward next).
    public var morph:    DoubleDriver = .zero
    /// Whole-sprite alpha multiplier. 1 = fully opaque, 0 = invisible.
    /// Uses loopMode .once so keyframe fades reach their end value and stay there.
    public var opacity:  DoubleDriver = DoubleDriver(mode: .constant, base: 1, loopMode: .once)
    /// Sprite-replacement index.  Step-evaluated integer selects the active
    /// variant: 0 = self (base sprite), 1+ = spriteVariants[index−1].
    /// Defaults to loopMode .once so sequences don't wrap back to 0.
    public var shape:          DoubleDriver = DoubleDriver(mode: .constant, base: 0, loopMode: .once)
    /// Overrides which subdivision-params set is applied to the sprite's geometry each frame.
    /// Disabled (default) leaves the static shape-set assignment in effect.
    public var subdivisionSet: NameDriver   = .disabled
    /// Overrides which renderer set draws the sprite each frame.
    /// Disabled (default) leaves the static renderer-set assignment in effect.
    public var rendererSet:    NameDriver   = .disabled
    /// Overrides which SpriteCycle runs on this sprite each frame.
    /// Disabled (default) leaves the static cycleName assignment in effect.
    public var cycleName:      NameDriver   = .disabled
    /// Named, time-bounded per-lane overrides — see `DriverLaneSegment`.
    /// Empty by default, reproducing pre-segment behaviour exactly.
    public var segments: [DriverLaneSegment] = []

    public init(
        position:      VectorDriver = VectorDriver(mode: .constant, base: .zero,                 loopMode: .once),
        scale:         VectorDriver = VectorDriver(mode: .constant, base: Vector2D(x: 1, y: 1), loopMode: .once),
        rotation:      DoubleDriver = DoubleDriver(mode: .constant, base: 0,                    loopMode: .once),
        morph:         DoubleDriver = .zero,
        opacity:       DoubleDriver = DoubleDriver(mode: .constant, base: 1, loopMode: .once),
        shape:         DoubleDriver = DoubleDriver(mode: .constant, base: 0, loopMode: .once),
        subdivisionSet: NameDriver  = .disabled,
        rendererSet:    NameDriver  = .disabled,
        cycleName:      NameDriver  = .disabled,
        segments:       [DriverLaneSegment] = []
    ) {
        self.position      = position
        self.scale         = scale
        self.rotation      = rotation
        self.morph         = morph
        self.opacity       = opacity
        self.shape         = shape
        self.subdivisionSet = subdivisionSet
        self.rendererSet    = rendererSet
        self.cycleName      = cycleName
        self.segments       = segments
    }

    /// All drivers at constant identity — no animation.
    public static let identity = TransformDrivers()

    // Custom decoder: decodeIfPresent for all fields so projects saved before
    // any given field was added continue to load with safe defaults.
    public init(from decoder: Decoder) throws {
        let c           = try decoder.container(keyedBy: CodingKeys.self)
        position        = try c.decodeIfPresent(VectorDriver.self, forKey: .position)      ?? VectorDriver(mode: .constant, base: .zero,                 loopMode: .once)
        scale           = try c.decodeIfPresent(VectorDriver.self, forKey: .scale)         ?? VectorDriver(mode: .constant, base: Vector2D(x: 1, y: 1), loopMode: .once)
        rotation        = try c.decodeIfPresent(DoubleDriver.self, forKey: .rotation)      ?? DoubleDriver(mode: .constant, base: 0,                    loopMode: .once)
        morph           = try c.decodeIfPresent(DoubleDriver.self, forKey: .morph)         ?? .zero
        opacity         = try c.decodeIfPresent(DoubleDriver.self, forKey: .opacity)       ?? DoubleDriver(mode: .constant, base: 1, loopMode: .once)
        shape           = try c.decodeIfPresent(DoubleDriver.self, forKey: .shape)         ?? DoubleDriver(mode: .constant, base: 0, loopMode: .once)
        subdivisionSet  = try c.decodeIfPresent(NameDriver.self,   forKey: .subdivisionSet) ?? .disabled
        rendererSet     = try c.decodeIfPresent(NameDriver.self,   forKey: .rendererSet)    ?? .disabled
        cycleName       = try c.decodeIfPresent(NameDriver.self,   forKey: .cycleName)      ?? .disabled
        segments        = try c.decodeIfPresent([DriverLaneSegment].self, forKey: .segments) ?? []
    }

    // MARK: - Segment resolution

    /// The lane's active driver at `frame`: the first segment for
    /// `laneRawValue` whose range covers it, or `base` if none does.
    public func activeVectorDriver(laneRawValue: Int, base: VectorDriver, at frame: Int) -> VectorDriver {
        guard let segment = segments.first(where: {
            $0.laneRawValue == laneRawValue && frame >= $0.startFrame && frame < $0.endFrame
        }), case .vector(let v) = segment.value else { return base }
        return v
    }

    public func activeDoubleDriver(laneRawValue: Int, base: DoubleDriver, at frame: Int) -> DoubleDriver {
        guard let segment = segments.first(where: {
            $0.laneRawValue == laneRawValue && frame >= $0.startFrame && frame < $0.endFrame
        }), case .double(let d) = segment.value else { return base }
        return d
    }
}

// MARK: - InheritMask
//
// Controls which transform components a child sprite inherits from its parent.
// Default: inherit position and rotation but not scale.

public struct InheritMask: Codable, Equatable, Sendable {
    public var position: Bool = true
    public var rotation: Bool = true
    /// When false (default), the child's scale is absolute (canvas-relative),
    /// not multiplied by the parent's scale.
    public var scale:    Bool = false

    public init(position: Bool = true, rotation: Bool = true, scale: Bool = false) {
        self.position = position
        self.rotation = rotation
        self.scale    = scale
    }

    public static let positionAndRotation = InheritMask(position: true, rotation: true, scale: false)
    public static let positionOnly        = InheritMask(position: true, rotation: false, scale: false)
    public static let all                 = InheritMask(position: true, rotation: true, scale: true)
    public static let none                = InheritMask(position: false, rotation: false, scale: false)
}

// MARK: - ShapeSequence
//
// Cycles the sprite's active polygon set through a list over draw cycles,
// enabling sprite-replacement animation without a separate sprite definition.

public struct ShapeSequence: Codable, Equatable, Sendable {
    /// Ordered list of polygon-set names.  Each name resolves the same way as
    /// `SpriteDef.shapeSetName` at scene load time.
    public var shapeSetNames: [String]
    /// Virtual frames (draw cycles) each shape is held before advancing.
    public var frameDuration: Int
    public var mode:          LoopMode
    /// When true, a shape is picked randomly each step rather than in order.
    public var randomize:     Bool

    public init(
        shapeSetNames: [String]  = [],
        frameDuration: Int       = 1,
        mode:          LoopMode  = .loop,
        randomize:     Bool      = false
    ) {
        self.shapeSetNames = shapeSetNames
        self.frameDuration = frameDuration
        self.mode          = mode
        self.randomize     = randomize
    }
}
