/// One sprite definition loaded from `sprites.xml`.
///
/// Describes which shape and renderer set to use, the initial transform, and
/// the full animation specification. Scene assembly resolves name references
/// into live objects.
public struct SpriteDef: Codable, Sendable {
    public var name: String
    public var enabled: Bool
    /// Which shape set the shape lives in.
    public var shapeSetName: String
    /// Name of the shape within that set.
    public var shapeName: String
    /// Name of the `RendererSet` to use.
    public var rendererSetName: String
    public var position: Vector2D
    public var scale: Vector2D
    public var rotation: Double
    /// Full animation specification. `animation.enabled` is `false` for static sprites.
    public var animation: SpriteAnimation

    // MARK: Hierarchy

    /// Name of the parent sprite (must appear earlier in the same SpriteSet).
    /// `nil` means this sprite is a root (world-space transform).
    public var parentName:   String?
    /// Which transform components are inherited from the parent.
    public var inheritMask:  InheritMask

    // MARK: Shape sequencing (legacy — superseded by spriteVariants + shape driver)

    /// When non-nil, the active polygon set cycles through this sequence over
    /// draw cycles instead of using `shapeSetName` permanently.
    public var shapeSequence: ShapeSequence?

    // MARK: Sprite replacement

    /// Ordered list of sprite names (same SpriteSet) available for replacement.
    /// Index 0 is always "self" (implicit); spriteVariants[0] corresponds to shape index 1.
    public var spriteVariants: [String] = []

    // MARK: Gate

    /// First global frame this sprite is visible.  0 = no constraint.
    public var gateStart: Int = 0
    /// Last global frame this sprite is visible.  0 = no constraint.
    public var gateEnd: Int = 0

    // MARK: Morph targets

    /// Ordered list of shape names (same ShapeSet as this sprite's `shapeSetName`)
    /// used as morph target blend destinations.  Index 0 maps to morph amount 1.0,
    /// index 1 to 2.0, etc.  All referenced shapes must have the same point count
    /// as the base shape — mismatched targets are skipped at load time.
    public var morphTargetNames: [String] = []

    // MARK: Depth (2.5D)

    /// Depth in the virtual z-axis. 0 = focal plane (no parallax effect). Positive = farther away;
    /// negative = closer. Requires `CameraConfig.perspectiveStrength > 0` to have any visual effect.
    public var depth: Double = 0

    // MARK: SVG sprite

    /// Filename of an SVG file in the project's `svg_sprites/` subdirectory.
    /// When set, this sprite renders the SVG image using all standard transform drivers
    /// (position, scale, rotation, opacity, depth/parallax, camera, hierarchy, gate).
    /// The shape/renderer pipeline is bypassed.
    public var svgFilename: String?

    // MARK: SpriteCycle

    /// Name of a `SpriteCycle` in `ProjectConfig.cycles`.
    /// When set, the cycle drives shape/renderer selection and overrides shapeSequence.
    public var cycleName: String?

    public init(
        name: String               = "",
        enabled: Bool              = true,
        shapeSetName: String       = "",
        shapeName: String          = "",
        rendererSetName: String    = "",
        position: Vector2D         = .zero,
        scale: Vector2D            = Vector2D(x: 1, y: 1),
        rotation: Double           = 0,
        animation: SpriteAnimation = .disabled,
        parentName: String?        = nil,
        inheritMask: InheritMask   = .positionAndRotation,
        shapeSequence: ShapeSequence? = nil,
        spriteVariants: [String]   = [],
        gateStart: Int             = 0,
        gateEnd: Int               = 0,
        morphTargetNames: [String] = [],
        depth: Double              = 0,
        svgFilename: String?       = nil,
        cycleName: String?         = nil
    ) {
        self.name = name; self.enabled = enabled
        self.shapeSetName = shapeSetName
        self.shapeName = shapeName; self.rendererSetName = rendererSetName
        self.position = position; self.scale = scale
        self.rotation = rotation; self.animation = animation
        self.parentName       = parentName
        self.inheritMask      = inheritMask
        self.shapeSequence    = shapeSequence
        self.spriteVariants   = spriteVariants
        self.gateStart        = gateStart
        self.gateEnd          = gateEnd
        self.morphTargetNames = morphTargetNames
        self.depth            = depth
        self.svgFilename      = svgFilename
        self.cycleName        = cycleName
    }

    // Custom decoder: decodeIfPresent for all fields so existing projects
    // load cleanly when new fields are absent from the saved JSON.
    public init(from decoder: Decoder) throws {
        let c           = try decoder.container(keyedBy: CodingKeys.self)
        name            = try c.decodeIfPresent(String.self,           forKey: .name)            ?? ""
        enabled         = try c.decodeIfPresent(Bool.self,             forKey: .enabled)         ?? true
        shapeSetName    = try c.decodeIfPresent(String.self,           forKey: .shapeSetName)    ?? ""
        shapeName       = try c.decodeIfPresent(String.self,           forKey: .shapeName)       ?? ""
        rendererSetName = try c.decodeIfPresent(String.self,           forKey: .rendererSetName) ?? ""
        position        = try c.decodeIfPresent(Vector2D.self,         forKey: .position)        ?? .zero
        scale           = try c.decodeIfPresent(Vector2D.self,         forKey: .scale)           ?? Vector2D(x: 1, y: 1)
        rotation        = try c.decodeIfPresent(Double.self,           forKey: .rotation)        ?? 0
        animation       = try c.decodeIfPresent(SpriteAnimation.self,  forKey: .animation)       ?? .disabled
        parentName      = try c.decodeIfPresent(String.self,           forKey: .parentName)
        inheritMask     = try c.decodeIfPresent(InheritMask.self,      forKey: .inheritMask)     ?? .positionAndRotation
        shapeSequence   = try c.decodeIfPresent(ShapeSequence.self,    forKey: .shapeSequence)
        spriteVariants    = try c.decodeIfPresent([String].self,         forKey: .spriteVariants)    ?? []
        gateStart         = try c.decodeIfPresent(Int.self,              forKey: .gateStart)         ?? 0
        gateEnd           = try c.decodeIfPresent(Int.self,              forKey: .gateEnd)           ?? 0
        morphTargetNames  = try c.decodeIfPresent([String].self,         forKey: .morphTargetNames)  ?? []
        depth             = try c.decodeIfPresent(Double.self,            forKey: .depth)             ?? 0
        svgFilename       = try c.decodeIfPresent(String.self,           forKey: .svgFilename)
        cycleName         = try c.decodeIfPresent(String.self,           forKey: .cycleName)
    }
}

/// A named group of sprite definitions.
public struct SpriteSet: Codable, Sendable {
    public var name: String
    public var sprites: [SpriteDef]

    public init(name: String, sprites: [SpriteDef] = []) {
        self.name = name; self.sprites = sprites
    }
}

/// All sprite sets loaded from `sprites.xml`.
public struct SpriteLibrary: Codable, Sendable {
    public var name: String
    public var spriteSets: [SpriteSet]

    public init(name: String = "", spriteSets: [SpriteSet] = []) {
        self.name = name; self.spriteSets = spriteSets
    }

    /// Flat list of all sprites across all sets, in declaration order.
    public var allSprites: [SpriteDef] { spriteSets.flatMap { $0.sprites } }
}

/// Root wrapper matching the `<SpriteConfig>` element.
public struct SpriteConfig: Codable, Sendable {
    public var library: SpriteLibrary

    public init(library: SpriteLibrary = SpriteLibrary()) {
        self.library = library
    }
}
