/// One sprite definition loaded from `sprites.xml`.
///
/// Describes which shape and renderer set to use, the initial transform, and
/// the full animation specification. Scene assembly resolves name references
/// into live objects.
public struct SpriteDef: Codable, Sendable {
    public var name: String
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

    public init(
        name: String              = "",
        shapeSetName: String      = "",
        shapeName: String         = "",
        rendererSetName: String   = "",
        position: Vector2D        = .zero,
        scale: Vector2D           = Vector2D(x: 1, y: 1),
        rotation: Double          = 0,
        animation: SpriteAnimation = .disabled
    ) {
        self.name = name; self.shapeSetName = shapeSetName
        self.shapeName = shapeName; self.rendererSetName = rendererSetName
        self.position = position; self.scale = scale
        self.rotation = rotation; self.animation = animation
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
