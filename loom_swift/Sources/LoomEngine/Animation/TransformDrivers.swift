import Foundation

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

    public init(
        position:      VectorDriver = VectorDriver(mode: .constant, base: .zero,                 loopMode: .once),
        scale:         VectorDriver = VectorDriver(mode: .constant, base: Vector2D(x: 1, y: 1), loopMode: .once),
        rotation:      DoubleDriver = DoubleDriver(mode: .constant, base: 0,                    loopMode: .once),
        morph:         DoubleDriver = .zero,
        opacity:       DoubleDriver = DoubleDriver(mode: .constant, base: 1, loopMode: .once),
        shape:         DoubleDriver = DoubleDriver(mode: .constant, base: 0, loopMode: .once),
        subdivisionSet: NameDriver  = .disabled,
        rendererSet:    NameDriver  = .disabled,
        cycleName:      NameDriver  = .disabled
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
