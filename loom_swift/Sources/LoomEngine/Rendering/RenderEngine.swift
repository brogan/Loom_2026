import CoreGraphics

/// Draws `Polygon2D` values into a `CGContext`.
///
/// ## Coordinate system contract
///
/// `RenderEngine` uses `ViewTransform.worldToScreen(_:)` to convert world
/// coordinates to screen coordinates. `worldToScreen` returns points with the
/// origin at the **top-left** of the canvas, Y increasing downward.
///
/// `CGContext` bitmaps default to bottom-left origin, Y-up. Callers must apply
/// a Y-flip transform to the context before calling `draw` so that screen
/// coordinates land in the correct pixels:
///
/// ```swift
/// context.translateBy(x: 0, y: CGFloat(height))
/// context.scaleBy(x: 1, y: -1)
/// ```
///
/// ## Static rendering
///
/// Phase 4 renders a single static frame. `Renderer` supplies all style
/// parameters. Animated parameter variation (`RenderTransform`) is Phase 5.
public enum RenderEngine {

    /// Draws `polygon` into `context` using the given `renderer`.
    ///
    /// - Parameters:
    ///   - polygon:   Polygon in world space. Invisible polygons are skipped.
    ///   - renderer:  Style to apply.
    ///   - context:   CoreGraphics drawing context configured with a Y-flip
    ///                transform (see type-level docs).
    ///   - transform: Maps world coordinates to screen coordinates.
    public static func draw(
        _ polygon: Polygon2D,
        renderer: Renderer,
        into context: CGContext,
        transform: ViewTransform
    ) {
        guard polygon.visible, !polygon.points.isEmpty else { return }

        switch renderer.mode {
        case .points:
            drawPoints(polygon, renderer: renderer, context: context, transform: transform)
        case .stroked:
            let path = buildPath(polygon, transform: transform)
            applyStroke(path, renderer: renderer, context: context)
        case .filled:
            let path = buildPath(polygon, transform: transform)
            applyFill(path, renderer: renderer, context: context)
        case .filledStroked:
            let path = buildPath(polygon, transform: transform)
            applyFill(path, renderer: renderer, context: context)
            applyStroke(path, renderer: renderer, context: context)
        case .brushed, .stenciled, .stamped:
            break  // Handled upstream in SpriteScene.renderInstance
        }
    }

    // MARK: - Path building

    private static func buildPath(
        _ polygon: Polygon2D,
        transform: ViewTransform
    ) -> CGPath {
        let pts  = polygon.points
        let path = CGMutablePath()

        switch polygon.type {
        case .spline:
            buildSplinePath(pts, path: path, transform: transform, closed: true)
        case .openSpline:
            buildSplinePath(pts, path: path, transform: transform, closed: false)
        case .line:
            buildLinePath(pts, path: path, transform: transform)
        case .oval:
            buildOvalPath(pts, path: path, transform: transform)
        case .point:
            break  // Handled separately in .points draw mode
        }

        return path
    }

    /// Builds a closed cubic Bézier path from spline-encoded points.
    ///
    /// Points are grouped in fours: `[anchor_i, cp_out_i, cp_in_{i+1}, anchor_{i+1}]`.
    private static func buildSplinePath(
        _ pts: [Vector2D],
        path: CGMutablePath,
        transform: ViewTransform,
        closed: Bool
    ) {
        guard pts.count >= 4 else { return }
        let segments = pts.count / 4

        path.move(to: transform.worldToScreen(pts[0]))
        for i in 0..<segments {
            let base = i * 4
            path.addCurve(
                to:       transform.worldToScreen(pts[base + 3]),
                control1: transform.worldToScreen(pts[base + 1]),
                control2: transform.worldToScreen(pts[base + 2])
            )
        }
        if closed { path.closeSubpath() }
    }

    /// Builds a closed straight-line path through all points.
    private static func buildLinePath(
        _ pts: [Vector2D],
        path: CGMutablePath,
        transform: ViewTransform
    ) {
        guard !pts.isEmpty else { return }
        path.move(to: transform.worldToScreen(pts[0]))
        for pt in pts.dropFirst() {
            path.addLine(to: transform.worldToScreen(pt))
        }
        path.closeSubpath()
    }

    /// Builds an ellipse path from `[centre, radiusEndpoint]`.
    ///
    /// `pts[0]` is the centre in world space; `pts[1]` defines the radii:
    /// `rx = |pts[1].x − pts[0].x|`, `ry = |pts[1].y − pts[0].y|` in screen pixels.
    private static func buildOvalPath(
        _ pts: [Vector2D],
        path: CGMutablePath,
        transform: ViewTransform
    ) {
        guard pts.count >= 2 else { return }
        let centre  = transform.worldToScreen(pts[0])
        let radiusPt = transform.worldToScreen(pts[1])
        let rx = abs(radiusPt.x - centre.x)
        let ry = abs(radiusPt.y - centre.y)
        path.addEllipse(in: CGRect(x: centre.x - rx, y: centre.y - ry,
                                   width: rx * 2, height: ry * 2))
    }

    // MARK: - Draw primitives

    private static func applyStroke(
        _ path: CGPath,
        renderer: Renderer,
        context: CGContext
    ) {
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(renderer.strokeColor.cgColor)
        context.setLineWidth(CGFloat(renderer.strokeWidth))
        context.strokePath()
        context.restoreGState()
    }

    private static func applyFill(
        _ path: CGPath,
        renderer: Renderer,
        context: CGContext
    ) {
        context.saveGState()
        context.addPath(path)
        context.setFillColor(renderer.fillColor.cgColor)
        context.fillPath()
        context.restoreGState()
    }

    /// Draws small filled circles at anchor positions.
    ///
    /// For spline/openSpline polygons, anchors are every 4th point (index 0, 4, 8, …).
    /// For all other types every point is treated as an anchor.
    private static func drawPoints(
        _ polygon: Polygon2D,
        renderer: Renderer,
        context: CGContext,
        transform: ViewTransform
    ) {
        let pts = polygon.points
        let r   = CGFloat(renderer.pointSize) / 2.0

        let anchors: [Vector2D]
        switch polygon.type {
        case .spline, .openSpline:
            anchors = stride(from: 0, to: pts.count, by: 4).map { pts[$0] }
        default:
            anchors = pts
        }

        context.saveGState()
        context.setFillColor(renderer.strokeColor.cgColor)
        for pt in anchors {
            let sp   = transform.worldToScreen(pt)
            let rect = CGRect(x: sp.x - r, y: sp.y - r, width: r * 2, height: r * 2)
            context.fillEllipse(in: rect)
        }
        context.restoreGState()
    }
}
