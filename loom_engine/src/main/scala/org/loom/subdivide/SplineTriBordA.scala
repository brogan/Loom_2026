package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * TRI_BORD_A subdivision for spline (bezier) polygons.
 * Creates N triangles, one per original corner. Each triangle spans the corner vertex
 * and the midpoints of its two adjacent outer bezier sides.
 * No inset polygon is used — midpoints are taken directly from the outer spline sides.
 * Produces N output polygons.
 *
 * For corner i:
 *   Side 1: connector (corner[i]       → outerMid[i])
 *   Side 2: connector (outerMid[i]     → outerMid[i-1])
 *   Side 3: connector (outerMid[i-1]   → corner[i])
 */
class SplineTriBordA(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totNewPolys: Int = subdivObj.sidesTotal
	val numSidesPerPoly: Int = 3
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val outerMidPoints: Array[Vector2D] = getOuterMidPoints(outerSides)

		val polyArray: Array[Polygon2D] = makePolys(outerSides, outerMidPoints)

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

	/**
	 * Compute the midpoint on each outer bezier side via bezierPoint at t = lineRatios.x
	 * (or .y for odd sides when continuous mode is on), matching the line version's
	 * getPolyMidPoints behaviour but applied to the outer sides without any inset scaling.
	 */
	private def getOuterMidPoints(outerSides: Array[Array[Vector2D]]): Array[Vector2D] = {
		val midPoints = new Array[Vector2D](subdivObj.sidesTotal)
		for (i <- 0 until subdivObj.sidesTotal) {
			val t: Double = if (subP.continuous && (i % 2 != 0)) subP.lineRatios.y else subP.lineRatios.x
			midPoints(i) = Formulas.bezierPoint(outerSides(i)(0), outerSides(i)(1), outerSides(i)(2), outerSides(i)(3), t)
		}
		midPoints
	}

	private def makeConnector(from: Vector2D, to: Vector2D): Array[Vector2D] = {
		val cpRatio: Vector2D = subP.controlPointRatios
		Array(from.clone(), Formulas.lerp(from, to, cpRatio.x), Formulas.lerp(from, to, cpRatio.y), to.clone())
	}

	private def makePolys(outerSides: Array[Array[Vector2D]], outerMidPoints: Array[Vector2D]): Array[Polygon2D] = {
		val polyArray = new Array[Polygon2D](totNewPolys)

		for (i <- 0 until totNewPolys) {
			val ptArray = new Array[Vector2D](12)
			val prevIdx: Int = (i - 1 + subdivObj.sidesTotal) % subdivObj.sidesTotal

			val cornerI: Vector2D    = outerSides(i)(0)
			val outerMidI: Vector2D  = outerMidPoints(i)
			val outerMidPrev: Vector2D = outerMidPoints(prevIdx)

			// Side 1: corner[i] → outerMid[i]
			val conn1 = makeConnector(cornerI, outerMidI)
			ptArray(0) = conn1(0); ptArray(1) = conn1(1); ptArray(2) = conn1(2); ptArray(3) = conn1(3)

			// Side 2: outerMid[i] → outerMid[i-1]
			val conn2 = makeConnector(outerMidI, outerMidPrev)
			ptArray(4) = conn2(0); ptArray(5) = conn2(1); ptArray(6) = conn2(2); ptArray(7) = conn2(3)

			// Side 3: outerMid[i-1] → corner[i]
			val conn3 = makeConnector(outerMidPrev, cornerI)
			ptArray(8) = conn3(0); ptArray(9) = conn3(1); ptArray(10) = conn3(2); ptArray(11) = conn3(3)

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
