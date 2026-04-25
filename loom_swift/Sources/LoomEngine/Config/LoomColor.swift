/// RGBA colour used throughout Loom config structs.
///
/// Integer components in [0, 255], matching the XML `r`/`g`/`b`/`a` attribute
/// convention used by `GlobalConfig`, `Renderer`, and `SubdivisionParams`.
public struct LoomColor: Equatable, Hashable, Codable, Sendable {

    public var r: Int
    public var g: Int
    public var b: Int
    public var a: Int

    public init(r: Int, g: Int, b: Int, a: Int = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    // MARK: - Convenience constants

    public static let black = LoomColor(r: 0,   g: 0,   b: 0,   a: 255)
    public static let white = LoomColor(r: 255, g: 255, b: 255, a: 255)
    public static let clear = LoomColor(r: 0,   g: 0,   b: 0,   a: 0)

    // MARK: - Normalized (0.0–1.0)

    public var rF: Double { Double(r) / 255.0 }
    public var gF: Double { Double(g) / 255.0 }
    public var bF: Double { Double(b) / 255.0 }
    public var aF: Double { Double(a) / 255.0 }
}
