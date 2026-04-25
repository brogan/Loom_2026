/// A closed numeric range [min, max].
///
/// Used for jitter animation bounds, subdivision random ranges, and similar
/// min/max parameter pairs throughout the Loom config system.
public struct FloatRange: Equatable, Codable, Sendable {
    public var min: Double
    public var max: Double

    public init(min: Double = 0, max: Double = 0) {
        self.min = min; self.max = max
    }

    /// Zero range: min == max == 0.
    public static let zero = FloatRange(min: 0, max: 0)
    /// Unit scale range: min == max == 1.
    public static let one  = FloatRange(min: 1, max: 1)
}

/// Independent X- and Y-axis float ranges, used for 2D jitter and transform bounds.
public struct VectorRange: Equatable, Codable, Sendable {
    public var x: FloatRange
    public var y: FloatRange

    public init(x: FloatRange = .zero, y: FloatRange = .zero) {
        self.x = x; self.y = y
    }

    /// Both axes zero.
    public static let zero = VectorRange(x: .zero, y: .zero)
    /// Both axes at unit scale (min == max == 1).
    public static let one  = VectorRange(x: .one, y: .one)
}
