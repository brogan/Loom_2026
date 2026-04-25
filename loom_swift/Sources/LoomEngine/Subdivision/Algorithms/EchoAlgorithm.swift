/// ECHO: produce 1 inset polygon scaled toward its own anchor centre.
/// ECHO_ABS_CENTER: produce 1 polygon scaled toward the absolute origin.
func subdivideEcho(
    points: [Vector2D],
    params: SubdivisionParams
) -> [Polygon2D] {
    let centre = BezierMath.centreSpline(points)
    let inset  = BezierMath.insetPoints(points, transform: params.insetTransform, centre: centre)
    return [Polygon2D(points: inset, type: .spline)]
}

func subdivideEchoAbsCenter(
    points: [Vector2D],
    params: SubdivisionParams
) -> [Polygon2D] {
    let inset = points.map { params.insetTransform.applyAbsolute(to: $0) }
    return [Polygon2D(points: inset, type: .spline)]
}
