package org.loom.geometry

/**
 * PolygonType
 * either straight line based or spline based 
 * @author brogan
 *
 */

object PolygonType {
	 val LINE_POLYGON: Int = 0
	 val SPLINE_POLYGON: Int = 1
	 val OPEN_SPLINE_POLYGON: Int = 2  // open cubic spline: no closing edge, no fill, no subdivision
	 val POINT_POLYGON: Int = 3        // discrete point: single Vector2D, rendered as a dot
	 val OVAL_POLYGON: Int = 4         // axis-aligned ellipse: Vector2D(cx,cy) + Vector2D(cx+rx, cy+ry)
}
