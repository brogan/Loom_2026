package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * TRI_STAR subdivision for spline (bezier) polygons.
 * Creates N "star" triangles pointing inward from each outer vertex to two adjacent
 * inset midpoints, plus 1 inner polygon connecting all inset midpoints.
 * Produces N+1 output polygons.
 *
 * For vertex i:
 *   Side 1: connector outer[i] → insetMid[i-1]
 *   Side 2: connector insetMid[i-1] → insetMid[i]
 *   Side 3: connector insetMid[i] → outer[i]
 */
class SplineTriStar(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totTriPolys: Int = subdivObj.sidesTotal
	val totNewPolys: Int = totTriPolys + 1
	val numSidesPerPoly: Int = 3
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val scaledPoints: List[Vector2D] = getScaledSplinePoints()
		val innerSides: Array[Array[Vector2D]] = getArrayOfInsetSides(scaledPoints)
		val insetMidPoints: Array[Vector2D] = getInsetMidPoints(innerSides)

		// N star triangles
		val triPolys: Array[Polygon2D] = makeStarTriPolys(outerSides, insetMidPoints)

		// 1 inner polygon connecting all inset midpoints
		val innerPoly: Polygon2D = makeInnerPoly(insetMidPoints)

		// Combine
		val polyArray: Array[Polygon2D] = triPolys :+ innerPoly

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

	private def makeStarTriPolys(outerSides: Array[Array[Vector2D]], insetMidPoints: Array[Vector2D]): Array[Polygon2D] = {
		val polyArray = new Array[Polygon2D](totTriPolys)

		for (i <- 0 until totTriPolys) {
			val ptArray = new Array[Vector2D](12)

			val outerAnchor: Vector2D = outerSides(i)(0) // outer anchor i
			val prevMidIdx: Int = (i + subdivObj.sidesTotal - 1) % subdivObj.sidesTotal
			val prevMid: Vector2D = insetMidPoints(prevMidIdx) // insetMid[i-1]
			val currMid: Vector2D = insetMidPoints(i)          // insetMid[i]

			// Side 1: outer[i] → insetMid[i-1]
			val conn1 = makeConnector(outerAnchor, prevMid)
			ptArray(0) = conn1(0); ptArray(1) = conn1(1); ptArray(2) = conn1(2); ptArray(3) = conn1(3)

			// Side 2: insetMid[i-1] → insetMid[i]
			val conn2 = makeConnector(prevMid, currMid)
			ptArray(4) = conn2(0); ptArray(5) = conn2(1); ptArray(6) = conn2(2); ptArray(7) = conn2(3)

			// Side 3: insetMid[i] → outer[i]
			val conn3 = makeConnector(currMid, outerAnchor)
			ptArray(8) = conn3(0); ptArray(9) = conn3(1); ptArray(10) = conn3(2); ptArray(11) = conn3(3)

			polyArray(i) = new Polygon2D(ptArray.toList, PolygonType.SPLINE_POLYGON)
		}
		polyArray
	}

	/**
	 * Build the inner polygon connecting all inset midpoints.
	 * N sides, each a bezier connector between consecutive midpoints. Total = 4N points.
	 */
	private def makeInnerPoly(insetMidPoints: Array[Vector2D]): Polygon2D = {
		val numSides: Int = subdivObj.sidesTotal
		val pts = new Array[Vector2D](numSides * 4)
		val cpRatio: Vector2D = subP.controlPointRatios

		for (i <- 0 until numSides) {
			val nextIdx: Int = (i + 1) % numSides
			val from: Vector2D = insetMidPoints(i)
			val to: Vector2D = insetMidPoints(nextIdx)
			val baseIdx: Int = i * 4
			pts(baseIdx) = from.clone()
			pts(baseIdx + 1) = Formulas.lerp(from, to, cpRatio.x)
			pts(baseIdx + 2) = Formulas.lerp(from, to, cpRatio.y)
			pts(baseIdx + 3) = to.clone()
		}

		new Polygon2D(pts.toList, PolygonType.SPLINE_POLYGON)
	}

	private def makePolysVisible(polyArray: Array[Polygon2D]): Unit = {
		for (i <- 0 until totNewPolys) {
			Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
		}
	}

}
