package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * ECHO subdivision for spline (bezier) polygons.
 * Scales all points (anchors + control points) toward the polygon center using insetTransform.
 * Produces 1 output polygon.
 *
 * When useAbsoluteCenter is false (ECHO): center is computed from this polygon's own anchor points.
 * When useAbsoluteCenter is true (ECHO_ABS_CENTER): center is the 'middle' parameter (absolute center
 * of the original pre-subdivision polygon), and scaling is done via Transform2D.scale (no offset).
 */
class SplineEcho(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int, useAbsoluteCenter: Boolean = false) {

	val totNewPolys: Int = 1
	val numSidesPerPoly: Int = subdivObj.sidesTotal // same side count as original

	def getPolys(): Array[Polygon2D] = {

		val scaledPoints: List[Vector2D] = getScaledSplinePoints()

		val polyArray: Array[Polygon2D] = new Array[Polygon2D](totNewPolys)
		polyArray(0) = new Polygon2D(scaledPoints, PolygonType.SPLINE_POLYGON)

		// centreIndex = 0 for a single polygon (echo produces one poly)
		val centreIndex: Int = 0

		if (subP.polysTransform) {
			if (subP.polysTransformPoints) {
				PointsTransform.transformPoints(polyArray, subP, centreIndex, subdivObj.sidesTotal, numSidesPerPoly)
			}
			if (subP.polysTranformWhole) {
				PolysTransform.transform(polyArray, subdivObj, subP)
			}
		}

		makePolysVisible(polyArray)

		polyArray
	}

	/**
	 * Scale all points toward the appropriate center.
	 * ECHO: center from this polygon's anchor points (every 4th point), scale using transformAroundOffset.
	 * ECHO_ABS_CENTER: scale around origin using Transform2D.scale (matching lineEchoAbsCenter behaviour).
	 */
	private def getScaledSplinePoints(): List[Vector2D] = {
		if (useAbsoluteCenter) {
			// ECHO_ABS_CENTER: scale each point around the origin (absolute scaling)
			val pts = new Array[Vector2D](subdivObj.points.length)
			for (i <- 0 until pts.length) {
				pts(i) = subdivObj.points(i).clone
				pts(i) = Transform2D.scale(pts(i), subP.insetTransform.scale)
			}
			pts.toList
		} else {
			// ECHO: scale each point around the spline center (computed from anchors only)
			val center: Vector2D = Subdivision.getCenterSpline(subdivObj.points)
			val pts = new Array[Vector2D](subdivObj.points.length)
			for (i <- 0 until pts.length) {
				pts(i) = subdivObj.points(i).clone
				pts(i).transformAroundOffset(subP.insetTransform, center)
			}
			pts.toList
		}
	}

	private def makePolysVisible(polyArray: Array[Polygon2D]): Unit = {
		for (i <- 0 until totNewPolys) {
			Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
		}
	}

}
