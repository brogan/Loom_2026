package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * TRI_BORD_B subdivision for spline (bezier) polygons.
 * Creates N triangles, one per original side. Each triangle connects the outer bezier side
 * to a point on the corresponding inset bezier curve (the "inset midpoint").
 * Produces N output polygons.
 *
 * For side i:
 *   Side 1: outer bezier side (outer[i] → outer[i+1])
 *   Side 2: connector (outer[i+1] → insetMid[i])
 *   Side 3: connector (insetMid[i] → outer[i])
 */
class SplineTriBordB(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totNewPolys: Int = subdivObj.sidesTotal
	val numSidesPerPoly: Int = 3
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val scaledPoints: List[Vector2D] = getScaledSplinePoints()
		val innerSides: Array[Array[Vector2D]] = getArrayOfInsetSides(scaledPoints)
		val insetMidPoints: Array[Vector2D] = getInsetMidPoints(innerSides)

		val polyArray: Array[Polygon2D] = makePolys(outerSides, insetMidPoints)

		val centreIndex: Int = 4

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

	private def getArrayOfOldSides(): Array[Array[Vector2D]] = {
		val polySides: Array[Array[Vector2D]] = new Array[Array[Vector2D]](subdivObj.sidesTotal)
		for (i <- 0 until subdivObj.sidesTotal) {
			val side: Array[Vector2D] = new Array[Vector2D](numPointsPerPolySide)
			for (j <- 0 until numPointsPerPolySide) {
				val ptIndex: Int = (numPointsPerPolySide * i) + j
				side(j) = subdivObj.points(ptIndex)
			}
			polySides(i) = side
		}
		polySides
	}

	private def getScaledSplinePoints(): List[Vector2D] = {
		val center: Vector2D = Subdivision.getCenterSpline(subdivObj.points)
		val pts = new Array[Vector2D](subdivObj.points.length)
		for (i <- 0 until pts.length) {
			pts(i) = subdivObj.points(i).clone
			pts(i).transformAroundOffset(subP.insetTransform, center)
		}
		pts.toList
	}

	private def getArrayOfInsetSides(scaledPoints: List[Vector2D]): Array[Array[Vector2D]] = {
		val polySides: Array[Array[Vector2D]] = new Array[Array[Vector2D]](subdivObj.sidesTotal)
		for (i <- 0 until subdivObj.sidesTotal) {
			val side: Array[Vector2D] = new Array[Vector2D](numPointsPerPolySide)
			for (j <- 0 until numPointsPerPolySide) {
				val ptIndex: Int = (numPointsPerPolySide * i) + j
				side(j) = scaledPoints(ptIndex)
			}
			polySides(i) = side
		}
		polySides
	}

	/**
	 * Compute the midpoint on each inset bezier side using bezierPoint.
	 * Uses lineRatios with continuous mode, matching the line version's getPolyMidPoints behaviour.
	 */
	private def getInsetMidPoints(innerSides: Array[Array[Vector2D]]): Array[Vector2D] = {
		val midPoints = new Array[Vector2D](subdivObj.sidesTotal)
		for (i <- 0 until subdivObj.sidesTotal) {
			val t: Double = if (subP.continuous && (i % 2 != 0)) subP.lineRatios.y else subP.lineRatios.x
			midPoints(i) = Formulas.bezierPoint(innerSides(i)(0), innerSides(i)(1), innerSides(i)(2), innerSides(i)(3), t)
		}
		midPoints
	}

	private def makeConnector(from: Vector2D, to: Vector2D): Array[Vector2D] = {
		val cpRatio: Vector2D = subP.controlPointRatios
		Array(from.clone(), Formulas.lerp(from, to, cpRatio.x), Formulas.lerp(from, to, cpRatio.y), to.clone())
	}

	private def makePolys(outerSides: Array[Array[Vector2D]], insetMidPoints: Array[Vector2D]): Array[Polygon2D] = {
		val polyArray = new Array[Polygon2D](totNewPolys)

		for (i <- 0 until totNewPolys) {
			val ptArray = new Array[Vector2D](12)

			// Side 1: outer bezier side (outer[i] → outer[i+1])
			ptArray(0) = outerSides(i)(0).clone()
			ptArray(1) = outerSides(i)(1).clone()
			ptArray(2) = outerSides(i)(2).clone()
			ptArray(3) = outerSides(i)(3).clone()

			// Side 2: connector (outer[i+1] → insetMid[i])
			val conn1 = makeConnector(outerSides(i)(3), insetMidPoints(i))
			ptArray(4) = conn1(0); ptArray(5) = conn1(1); ptArray(6) = conn1(2); ptArray(7) = conn1(3)

			// Side 3: connector (insetMid[i] → outer[i])
			val conn2 = makeConnector(insetMidPoints(i), outerSides(i)(0))
			ptArray(8) = conn2(0); ptArray(9) = conn2(1); ptArray(10) = conn2(2); ptArray(11) = conn2(3)

			polyArray(i) = new Polygon2D(ptArray.toList, PolygonType.SPLINE_POLYGON)
		}
		polyArray
	}

	private def makePolysVisible(polyArray: Array[Polygon2D]): Unit = {
		for (i <- 0 until totNewPolys) {
			Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
		}
	}

}
