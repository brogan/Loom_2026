import Foundation

// MARK: - TransformDrivers
//
// Per-property animation drivers for one sprite.  When a sprite's
// `SpriteAnimation.drivers` is non-nil this struct is used instead of the
// legacy flat AnimationType path.

public struct TransformDrivers: Codable, Equatable, Sendable {

    /// Position offset (world-space units — same convention as `SpriteDef.position`).
    public var position: VectorDriver = .zero
    /// Scale multiplier on top of `SpriteDef.scale`.  Identity = (1, 1).
    public var scale:    VectorDriver = .identity
    /// Rotation in degrees, added to `SpriteDef.rotation`.
    public var rotation: DoubleDriver = .zero
    /// Morph blend amount (same encoding as legacy `morphAmount` — integer part
    /// selects morph target index (1-based), fractional part blends toward next).
    public var morph:    DoubleDriver = .zero
    /// Whole-sprite alpha multiplier. 1 = fully opaque, 0 = invisible.
    public var opacity:  DoubleDriver = .one
    /// Sprite-replacement index.  Step-evaluated integer selects the active
    /// variant: 0 = self (base sprite), 1+ = spriteVariants[index−1].
    /// Defaults to loopMode .once so sequences don't wrap back to 0.
    public var shape:    DoubleDriver = DoubleDriver(mode: .constant, base: 0, loopMode: .once)

    public init(
        position: VectorDriver = .zero,
        scale:    VectorDriver = .identity,
        rotation: DoubleDriver = .zero,
        morph:    DoubleDriver = .zero,
        opacity:  DoubleDriver = .one,
        shape:    DoubleDriver = DoubleDriver(mode: .constant, base: 0, loopMode: .once)
    ) {
        self.position = position
        self.scale    = scale
        self.rotation = rotation
        self.morph    = morph
        self.opacity  = opacity
        self.shape    = shape
    }

    /// All drivers at constant identity — no animation.
    public static let identity = TransformDrivers()

    // Custom decoder: decodeIfPresent for all fields so projects saved before
    // any given field was added continue to load with safe defaults.
    public init(from decoder: Decoder) throws {
        let c        = try decoder.container(keyedBy: CodingKeys.self)
        position     = try c.decodeIfPresent(VectorDriver.self, forKey: .position) ?? .zero
        scale        = try c.decodeIfPresent(VectorDriver.self, forKey: .scale)    ?? .identity
        rotation     = try c.decodeIfPresent(DoubleDriver.self, forKey: .rotation) ?? .zero
        morph        = try c.decodeIfPresent(DoubleDriver.self, forKey: .morph)    ?? .zero
        opacity      = try c.decodeIfPresent(DoubleDriver.self, forKey: .opacity)  ?? .one
        shape        = try c.decodeIfPresent(DoubleDriver.self, forKey: .shape)    ?? DoubleDriver(mode: .constant, base: 0, loopMode: .once)
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
