package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * TRI_BORD_B_ECHO subdivision for spline (bezier) polygons.
 * Same as SplineTriBordB but also includes a star-shaped echo polygon.
 * The star alternates between outer anchor points and inset midpoints.
 * Produces N+1 output polygons: N triangles + 1 star echo.
 */
class SplineTriBordBEcho(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totTriPolys: Int = subdivObj.sidesTotal
	val totNewPolys: Int = totTriPolys + 1
	val numSidesPerPoly: Int = 3
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val scaledPoints: List[Vector2D] = getScaledSplinePoints()
		val innerSides: Array[Array[Vector2D]] = getArrayOfInsetSides(scaledPoints)
		val insetMidPoints: Array[Vector2D] = getInsetMidPoints(innerSides)

		// N triangle polys
		val triPolys: Array[Polygon2D] = makeTriPolys(outerSides, insetMidPoints)

		// 1 star-shaped echo polygon: 2N spline sides alternating outer anchors and inset midpoints
		val starPoly: Polygon2D = makeStarPoly(outerSides, insetMidPoints)

		// Combine
		val polyArray: Array[Polygon2D] = triPolys :+ starPoly

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

	private def makeTriPolys(outerSides: Array[Array[Vector2D]], insetMidPoints: Array[Vector2D]): Array[Polygon2D] = {
		val polyArray = new Array[Polygon2D](totTriPolys)

		for (i <- 0 until totTriPolys) {
			val ptArray = new Array[Vector2D](12)

			// Side 1: outer bezier side
			ptArray(0) = outerSides(i)(0).clone()
			ptArray(1) = outerSides(i)(1).clone()
			ptArray(2) = outerSides(i)(2).clone()
			ptArray(3) = outerSides(i)(3).clone()

			// Side 2: outer[i+1] → insetMid[i]
			val conn1 = makeConnector(outerSides(i)(3), insetMidPoints(i))
			ptArray(4) = conn1(0); ptArray(5) = conn1(1); ptArray(6) = conn1(2); ptArray(7) = conn1(3)

			// Side 3: insetMid[i] → outer[i]
			val conn2 = makeConnector(insetMidPoints(i), outerSides(i)(0))
			ptArray(8) = conn2(0); ptArray(9) = conn2(1); ptArray(10) = conn2(2); ptArray(11) = conn2(3)

			polyArray(i) = new Polygon2D(ptArray.toList, PolygonType.SPLINE_POLYGON)
		}
		polyArray
	}

	/**
	 * Build the star-shaped echo polygon.
	 * Line version alternates outer vertices and inset midpoints: (outer[0], insetMid[0], outer[1], insetMid[1], ...)
	 * Spline version: 2N bezier sides connecting these points, each with cpRatio control points.
	 * Total points = 2N * 4 = 8N.
	 */
	private def makeStarPoly(outerSides: Array[Array[Vector2D]], insetMidPoints: Array[Vector2D]): Polygon2D = {
		val numStarSides: Int = subdivObj.sidesTotal * 2
		val starPts = new Array[Vector2D](numStarSides * 4)
		val cpRatio: Vector2D = subP.controlPointRatios

		for (i <- 0 until subdivObj.sidesTotal) {
			val outerAnchor: Vector2D = outerSides(i)(0) // outer anchor i
			val insetMid: Vector2D = insetMidPoints(i)
			val nextIdx = (i + 1) % subdivObj.sidesTotal
			val nextOuterAnchor: Vector2D = outerSides(nextIdx)(0) // outer anchor i+1

			// Side 2i: outer[i] → insetMid[i]
			val baseIdx1 = (i * 2) * 4
			starPts(baseIdx1) = outerAnchor.clone()
			starPts(baseIdx1 + 1) = Formulas.lerp(outerAnchor, insetMid, cpRatio.x)
			starPts(baseIdx1 + 2) = Formulas.lerp(outerAnchor, insetMid, cpRatio.y)
			starPts(baseIdx1 + 3) = insetMid.clone()

			// Side 2i+1: insetMid[i] → outer[i+1]
			val baseIdx2 = ((i * 2) + 1) * 4
			starPts(baseIdx2) = insetMid.clone()
			starPts(baseIdx2 + 1) = Formulas.lerp(insetMid, nextOuterAnchor, cpRatio.x)
			starPts(baseIdx2 + 2) = Formulas.lerp(insetMid, nextOuterAnchor, cpRatio.y)
			starPts(baseIdx2 + 3) = nextOuterAnchor.clone()
		}

		new Polygon2D(starPts.toList, PolygonType.SPLINE_POLYGON)
	}

	private def makePolysVisible(polyArray: Array[Polygon2D]): Unit = {
		for (i <- 0 until totNewPolys) {
			Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
		}
	}

}
