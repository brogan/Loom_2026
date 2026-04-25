import Foundation

/// Loads `Polygon2D` arrays from Bezier-editor polygon XML files.
///
/// ### Normalisation transform
/// The Bezier editor and Loom use different coordinate conventions.
/// `load(data:normalise:)` applies a Y-flip `(x, y) → (x, -y)` by default,
/// which is equivalent to Scala's `standShapesUpright` (180° rotation) followed
/// by `reverseShapesHorizontally` (flip X).
///
/// ### File format
/// ```xml
/// <polygonSet>
///   <polygon>
///     <curve>
///       <point x="double" y="double" pressure="double"/>  <!-- anchor + pressure -->
///       <point x="double" y="double"/>                    <!-- control out -->
///       <point x="double" y="double"/>                    <!-- control in -->
///       <point x="double" y="double"/>                    <!-- anchor -->
///     </curve>
///     <!-- additional <curve> elements -->
///   </polygon>
///   <!-- additional <polygon> elements -->
/// </polygonSet>
/// ```
public enum XMLPolygonLoader {

    // MARK: - Public entry points — polygon sets

    public static func load(url: URL, normalise: Bool = true) throws -> [Polygon2D] {
        let data = try Data(contentsOf: url)
        return try load(data: data, normalise: normalise)
    }

    public static func load(data: Data, normalise: Bool = true) throws -> [Polygon2D] {
        let root = try parseXML(data: data)
        return parsePolygonSet(root, normalise: normalise)
    }

    // MARK: - Public entry points — open curve sets

    /// Load an `<openCurveSet>` XML file.
    ///
    /// Each `<openCurve>` element (a sequence of connected Bézier curves) becomes
    /// one `Polygon2D` with type `.openSpline`.  The same Y-flip normalisation as
    /// closed polygon loading is applied by default.
    public static func loadOpenCurveSet(url: URL, normalise: Bool = true) throws -> [Polygon2D] {
        let data = try Data(contentsOf: url)
        return try loadOpenCurveSet(data: data, normalise: normalise)
    }

    public static func loadOpenCurveSet(data: Data, normalise: Bool = true) throws -> [Polygon2D] {
        let root = try parseXML(data: data)
        return parseOpenCurveSet(root, normalise: normalise)
    }

    // MARK: - Public entry points — point sets

    /// Load a `<pointSet>` XML file.
    ///
    /// Each `<point x y>` element becomes a `Vector2D` in a single `.point`
    /// `Polygon2D`.  The set-level transform (`<scaleX/Y>`, `<rotationAngle>`,
    /// `<transX/Y>`) is applied to every point before returning.
    /// Y values are negated to convert from Loom's Y-up to the engine's Y-down
    /// world space (matching the convention used for polygon and curve loading).
    public static func loadPointSet(url: URL) throws -> [Polygon2D] {
        let data = try Data(contentsOf: url)
        return try loadPointSet(data: data)
    }

    public static func loadPointSet(data: Data) throws -> [Polygon2D] {
        let root = try parseXML(data: data)
        return parsePointSet(root)
    }

    // MARK: - Point set parsing

    private static func parsePointSet(_ root: XMLNode) -> [Polygon2D] {
        let setNode = root.name == "pointSet" ? root : (root.child(named: "pointSet") ?? root)

        // Each <point> becomes its own single-point Polygon2D — matches Scala PointSetLoader.
        // The XML root-level transform fields (scaleX/Y, rotationAngle, transX/Y) are editor
        // metadata and are NOT applied at load time (confirmed from Scala source).
        // Y is negated to match the Loom Y-up → engine Y-down convention used by all other loaders.
        return setNode.children(named: "point").map { pt in
            let x =  pt.doubleAttr("x")
            let y = -pt.doubleAttr("y")
            return Polygon2D(points: [Vector2D(x: x, y: y)], type: .point)
        }
    }

    // MARK: - Public entry points — oval sets

    /// Load an `<ovalSet>` XML file.
    ///
    /// Each `<oval cx cy rx ry>` element becomes one `Polygon2D` with type `.oval`
    /// containing two points: `[centre, (cx+rx, cy+ry)]`.  The renderer derives
    /// screen radii from the difference between these two world-space points.
    /// No Y-flip is applied (ovals are defined by centre and radii, not traced paths).
    public static func loadOvalSet(url: URL) throws -> [Polygon2D] {
        let data = try Data(contentsOf: url)
        return try loadOvalSet(data: data)
    }

    public static func loadOvalSet(data: Data) throws -> [Polygon2D] {
        let root = try parseXML(data: data)
        return parseOvalSet(root)
    }

    // MARK: - Oval set parsing

    private static func parseOvalSet(_ root: XMLNode) -> [Polygon2D] {
        let setNode = root.name == "ovalSet" ? root : (root.child(named: "ovalSet") ?? root)
        return setNode.children(named: "oval").map { parseOval($0) }
    }

    /// Parse one `<oval cx cy rx ry>` into a `.oval` `Polygon2D` with two points:
    ///   pts[0] = centre (cx, cy)
    ///   pts[1] = radius endpoint (cx + rx, cy + ry)
    /// The renderer uses the screen-space difference to determine the ellipse rect.
    private static func parseOval(_ node: XMLNode) -> Polygon2D {
        let cx = node.doubleAttr("cx")
        let cy = node.doubleAttr("cy")
        let rx = node.doubleAttr("rx")
        let ry = node.doubleAttr("ry")
        let centre       = Vector2D(x: cx, y: cy)
        let radiusPoint  = Vector2D(x: cx + rx, y: cy + ry)
        return Polygon2D(points: [centre, radiusPoint], type: .oval)
    }

    // MARK: - Open curve parsing

    private static func parseOpenCurveSet(_ root: XMLNode, normalise: Bool) -> [Polygon2D] {
        let setNode = root.name == "openCurveSet"
            ? root : (root.child(named: "openCurveSet") ?? root)
        return setNode.children(named: "openCurve").map { parseOpenCurve($0, normalise: normalise) }
    }

    /// Parse one `<openCurve>` element — a sequence of Bézier `<curve>` segments
    /// that form a single open path — into one `.openSpline` `Polygon2D`.
    ///
    /// Each `<curve>` has four `<point>` children in the order
    /// [anchor-start, ctrl-out, ctrl-in, anchor-end].  Pressure is stored only on
    /// anchor points (indices 0 and 3).  For chained curves the start anchor of
    /// curve N is the same world point as the end anchor of curve N-1 — it is
    /// skipped from `points` to avoid duplicates, but its pressure value is
    /// already captured as the end of the previous segment.
    ///
    /// Result: `pressures` contains one entry per anchor point (N+1 values for N
    /// segments), matching the indexing expected by `BrushEdge.extractEdges`.
    private static func parseOpenCurve(_ node: XMLNode, normalise: Bool) -> Polygon2D {
        var points:    [Vector2D] = []
        var pressures: [Double]   = []
        var isFirstCurve = true

        for curve in node.children(named: "curve") {
            let pts = curve.children(named: "point")
            guard pts.count == 4 else { continue }

            // Store all 4 points [anchor_start, ctrl_out, ctrl_in, anchor_end].
            // The start anchor of curve N equals the end anchor of curve N-1
            // in world space, but we keep the duplicate so the flat array uses a
            // clean 4-stride layout — identical to closed polygon storage.
            // buildSplinePath and BrushEdge.extractEdges both expect this layout:
            // segmentCount = points.count / 4, segment i starts at i*4.
            for pt in pts {
                let x = pt.doubleAttr("x")
                let y = pt.doubleAttr("y")
                points.append(Vector2D(x: x, y: normalise ? -y : y))
            }

            // Pressure: N+1 values for N curves — one per anchor in the open chain.
            // Record the start anchor's pressure only for the first curve (subsequent
            // curves share the start anchor with the previous end, whose pressure was
            // already appended).  Always record the end anchor (idx=3).
            if isFirstCurve {
                pressures.append(pts[0].doubleAttr("pressure", default: 1.0))
            }
            pressures.append(pts[3].doubleAttr("pressure", default: 1.0))

            isFirstCurve = false
        }

        return Polygon2D(points: points, type: .openSpline, pressures: pressures)
    }

    // MARK: - Polygon set parsing

    private static func parsePolygonSet(_ root: XMLNode, normalise: Bool) -> [Polygon2D] {
        // Root may be <polygonSet> directly, or the root is a wrapper
        let polygonSetNode = root.name == "polygonSet" ? root : (root.child(named: "polygonSet") ?? root)
        return polygonSetNode.children(named: "polygon").map { parsePolygon($0, normalise: normalise) }
    }

    private static func parsePolygon(_ node: XMLNode, normalise: Bool) -> Polygon2D {
        // Determine type: default to closed (.spline); respect isClosed if present
        let isClosed = node.boolAttr("isClosed", default: true)
        let polyType: PolygonType = isClosed ? .spline : .openSpline

        var points: [Vector2D] = []
        var pressures: [Double] = []
        var isFirstCurve = true

        for curve in node.children(named: "curve") {
            let pts = curve.children(named: "point")
            guard pts.count == 4 else { continue }

            for (idx, pt) in pts.enumerated() {
                let x = pt.doubleAttr("x")
                let y = pt.doubleAttr("y")
                points.append(Vector2D(x: x, y: normalise ? -y : y))
                // Pressure is on anchor points (index 0) only
                if idx == 0 && isFirstCurve {
                    pressures.append(pt.doubleAttr("pressure", default: 1.0))
                } else if idx == 0 {
                    pressures.append(pt.doubleAttr("pressure", default: 1.0))
                }
            }
            isFirstCurve = false
        }

        return Polygon2D(points: points, type: polyType, pressures: pressures)
    }
}
