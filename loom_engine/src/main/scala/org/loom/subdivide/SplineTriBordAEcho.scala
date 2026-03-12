package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * TRI_BORD_A_ECHO subdivision for spline (bezier) polygons.
 * Same as SplineTriBordA but also includes a star-shaped echo polygon.
 * The star alternates between outer corner anchors and outer side midpoints:
 *   corner[0] → outerMid[0] → corner[1] → outerMid[1] → ...
 * Produces N+1 output polygons: N corner triangles + 1 star echo.
 */
class SplineTriBordAEcho(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totTriPolys: Int = subdivObj.sidesTotal
	val totNewPolys: Int = totTriPolys + 1
	val numSidesPerPoly: Int = 3
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val outerMidPoints: Array[Vector2D] = getOuterMidPoints(outerSides)

		val triPolys: Array[Polygon2D] = makeTriPolys(outerSides, outerMidPoints)
		val starPoly: Polygon2D        = makeStarPoly(outerSides, outerMidPoints)

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

	private def makeTriPolys(outerSides: Array[Array[Vector2D]], outerMidPoints: Array[Vector2D]): Array[Polygon2D] = {
		val polyArray = new Array[Polygon2D](totTriPolys)

		for (i <- 0 until totTriPolys) {
			val ptArray = new Array[Vector2D](12)
			val prevIdx: Int = (i - 1 + subdivObj.sidesTotal) % subdivObj.sidesTotal

			val cornerI: Vector2D      = outerSides(i)(0)
			val outerMidI: Vector2D    = outerMidPoints(i)
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

	/**
	 * Build the star-shaped echo polygon.
	 * Alternates outer corner anchors and outer side midpoints:
	 *   corner[0] → outerMid[0] → corner[1] → outerMid[1] → ...
	 * Each leg is a bezier connector using controlPointRatios.
	 * Total: 2N sides × 4 points = 8N points.
	 */
	private def makeStarPoly(outerSides: Array[Array[Vector2D]], outerMidPoints: Array[Vector2D]): Polygon2D = {
		val numStarSides: Int = subdivObj.sidesTotal * 2
		val starPts = new Array[Vector2D](numStarSides * 4)
		val cpRatio: Vector2D = subP.controlPointRatios

		for (i <- 0 until subdivObj.sidesTotal) {
			val cornerI: Vector2D    = outerSides(i)(0)
			val outerMidI: Vector2D  = outerMidPoints(i)
			val nextIdx              = (i + 1) % subdivObj.sidesTotal
			val nextCorner: Vector2D = outerSides(nextIdx)(0)

			// Side 2i:   corner[i] → outerMid[i]
			val baseIdx1 = (i * 2) * 4
			starPts(baseIdx1)     = cornerI.clone()
			starPts(baseIdx1 + 1) = Formulas.lerp(cornerI, outerMidI, cpRatio.x)
			starPts(baseIdx1 + 2) = Formulas.lerp(cornerI, outerMidI, cpRatio.y)
			starPts(baseIdx1 + 3) = outerMidI.clone()

			// Side 2i+1: outerMid[i] → corner[i+1]
			val baseIdx2 = ((i * 2) + 1) * 4
			starPts(baseIdx2)     = outerMidI.clone()
			starPts(baseIdx2 + 1) = Formulas.lerp(outerMidI, nextCorner, cpRatio.x)
			starPts(baseIdx2 + 2) = Formulas.lerp(outerMidI, nextCorner, cpRatio.y)
			starPts(baseIdx2 + 3) = nextCorner.clone()
		}

		new Polygon2D(starPts.toList, PolygonType.SPLINE_POLYGON)
	}

	private def makePolysVisible(polyArray: Array[Polygon2D]): Unit = {
		for (i <- 0 until totNewPolys) {
			Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
		}
	}

}
