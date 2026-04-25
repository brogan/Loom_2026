/// The geometric role of a Polygon2D — determines how it is rendered
/// and whether it participates in subdivision.
public enum PolygonType: Int, Codable, CaseIterable, Equatable, Sendable {

    /// Straight-edged polygon: points are connected by line segments.
    case line = 0

    /// Closed cubic Bézier spline.
    /// Points are stored in groups of 4: [anchor, controlOut, controlIn, anchor].
    /// point.count is always a multiple of 4.
    case spline = 1

    /// Open cubic Bézier spline (same encoding as .spline, not closed).
    case openSpline = 2

    /// A single point marker. points.count == 1.
    case point = 3

    /// An axis-aligned ellipse. points == [centre, Vector2D(cx+rx, cy+ry)].
    case oval = 4

    /// Bypass types pass through every subdivision pass unchanged.
    public var isBypassType: Bool {
        self == .openSpline || self == .point || self == .oval
    }
}
