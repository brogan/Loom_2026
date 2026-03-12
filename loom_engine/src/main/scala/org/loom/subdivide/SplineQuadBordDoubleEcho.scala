package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * QUAD_BORD_DOUBLE_ECHO subdivision for spline (bezier) polygons.
 * Same as SplineQuadBordDouble but also includes the inset (echo) polygon as the last element.
 * Produces 2N+1 output polygons: 2N border quads + 1 echo.
 */
class SplineQuadBordDoubleEcho(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totBorderPolys: Int = subdivObj.sidesTotal * 2
	val totNewPolys: Int = totBorderPolys + 1
	val numSidesPerPoly: Int = 4
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val scaledPoints: List[Vector2D] = getScaledSplinePoints()
		val innerSides: Array[Array[Vector2D]] = getArrayOfInsetSides(scaledPoints)

		val borderPolys: Array[Polygon2D] = makeBorderPolys(outerSides, innerSides)
		val echoPolys: Array[Polygon2D] = new Array[Polygon2D](1)
		echoPolys(0) = new Polygon2D(scaledPoints, PolygonType.SPLINE_POLYGON)

		val polyArray: Array[Polygon2D] = borderPolys ++ echoPolys

		val centreIndex: Int = (polyArray(0).points.length / 2)

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

	private def splitBezierAt(side: Array[Vector2D], t: Double): (Array[Vector2D], Array[Vector2D]) = {
		val P0 = side(0); val P1 = side(1); val P2 = side(2); val P3 = side(3)
		val M1 = Formulas.lerp(P0, P1, t)
		val M2 = Formulas.lerp(P1, P2, t)
		val M3 = Formulas.lerp(P2, P3, t)
		val M4 = Formulas.lerp(M1, M2, t)
		val M5 = Formulas.lerp(M2, M3, t)
		val M  = Formulas.lerp(M4, M5, t)
		(Array(P0, M1, M4, M), Array(M.clone(), M5, M3, P3))
	}

	private def reversePointsOfSide(side: Array[Vector2D]): Array[Vector2D] = {
		val reverse: Array[Vector2D] = new Array[Vector2D](side.length)
		var count: Int = 0
		for (i <- (numPointsPerPolySide - 1) to 0 by -1) {
			reverse(count) = side(i)
			count = count + 1
		}
		reverse
	}

	private def makeBorderPolys(outerSides: Array[Array[Vector2D]], innerSides: Array[Array[Vector2D]]): Array[Polygon2D] = {
		val polyArray = new Array[Polygon2D](totBorderPolys)
		val cpRatio: Vector2D = subP.controlPointRatios

		for (i <- 0 until subdivObj.sidesTotal) {
			val t: Double = if (subP.continuous && (i % 2 != 0)) subP.lineRatios.y else subP.lineRatios.x

			val (outerLeft, outerRight) = splitBezierAt(outerSides(i), t)
			val (innerLeft, innerRight) = splitBezierAt(innerSides(i), t)

			val outerMid: Vector2D = outerLeft(3)
			val innerMid: Vector2D = innerLeft(3)

			// Quad 1 (left)
			val q1 = new Array[Vector2D](16)
			q1(0) = outerLeft(0).clone(); q1(1) = outerLeft(1).clone()
			q1(2) = outerLeft(2).clone(); q1(3) = outerLeft(3).clone()
			q1(4) = outerMid.clone()
			q1(5) = Formulas.lerp(outerMid, innerMid, cpRatio.x)
			q1(6) = Formulas.lerp(outerMid, innerMid, cpRatio.y)
			q1(7) = innerMid.clone()
			val revInnerLeft = reversePointsOfSide(innerLeft)
			q1(8) = revInnerLeft(0).clone(); q1(9) = revInnerLeft(1).clone()
			q1(10) = revInnerLeft(2).clone(); q1(11) = revInnerLeft(3).clone()
			q1(12) = innerSides(i)(0).clone()
			q1(13) = Formulas.lerp(innerSides(i)(0), outerSides(i)(0), cpRatio.x)
			q1(14) = Formulas.lerp(innerSides(i)(0), outerSides(i)(0), cpRatio.y)
			q1(15) = outerSides(i)(0).clone()

			// Quad 2 (right)
			val q2 = new Array[Vector2D](16)
			q2(0) = outerRight(0).clone(); q2(1) = outerRight(1).clone()
			q2(2) = outerRight(2).clone(); q2(3) = outerRight(3).clone()
			q2(4) = outerSides(i)(3).clone()
			q2(5) = Formulas.lerp(outerSides(i)(3), innerSides(i)(3), cpRatio.x)
			q2(6) = Formulas.lerp(outerSides(i)(3), innerSides(i)(3), cpRatio.y)
			q2(7) = innerSides(i)(3).clone()
			val revInnerRight = reversePointsOfSide(innerRight)
			q2(8) = revInnerRight(0).clone(); q2(9) = revInnerRight(1).clone()
			q2(10) = revInnerRight(2).clone(); q2(11) = revInnerRight(3).clone()
			q2(12) = innerMid.clone()
			q2(13) = Formulas.lerp(innerMid, outerMid, cpRatio.x)
			q2(14) = Formulas.lerp(innerMid, outerMid, cpRatio.y)
			q2(15) = outerMid.clone()

			polyArray(i * 2) = new Polygon2D(q1.toList, PolygonType.SPLINE_POLYGON)
			polyArray((i * 2) + 1) = new Polygon2D(q2.toList, PolygonType.SPLINE_POLYGON)
		}
		polyArray
	}

	private def makePolysVisible(polyArray: Array[Polygon2D]): Unit = {
		for (i <- 0 until totNewPolys) {
			Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
		}
	}

}
