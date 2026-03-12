package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * TRI_BORD_C_ECHO subdivision for spline (bezier) polygons.
 * Same as SplineTriBordC but also includes the inset (echo) polygon as the last element.
 * Produces 3N+1 output polygons: 3N triangles + 1 echo.
 */
class SplineTriBordCEcho(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totTriPolys: Int = subdivObj.sidesTotal * 3
	val totNewPolys: Int = totTriPolys + 1
	val numSidesPerPoly: Int = 3
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val scaledPoints: List[Vector2D] = getScaledSplinePoints()
		val innerSides: Array[Array[Vector2D]] = getArrayOfInsetSides(scaledPoints)

		// 3N triangle polys
		val triPolys: Array[Polygon2D] = makeTriPolys(outerSides, innerSides)

		// 1 echo poly
		val echoPolys: Array[Polygon2D] = new Array[Polygon2D](1)
		echoPolys(0) = new Polygon2D(scaledPoints, PolygonType.SPLINE_POLYGON)

		// Combine
		val polyArray: Array[Polygon2D] = triPolys ++ echoPolys

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

	private def makeConnector(from: Vector2D, to: Vector2D): Array[Vector2D] = {
		val cpRatio: Vector2D = subP.controlPointRatios
		Array(from.clone(), Formulas.lerp(from, to, cpRatio.x), Formulas.lerp(from, to, cpRatio.y), to.clone())
	}

	private def makeTriPolys(outerSides: Array[Array[Vector2D]], innerSides: Array[Array[Vector2D]]): Array[Polygon2D] = {
		val polyArray = new Array[Polygon2D](totTriPolys)

		for (i <- 0 until subdivObj.sidesTotal) {
			val t: Double = if (subP.continuous && (i % 2 != 0)) subP.lineRatios.y else subP.lineRatios.x

			val (leftHalf, rightHalf) = splitBezierAt(outerSides(i), t)
			val midpoint: Vector2D = leftHalf(3)

			val scaledI: Vector2D = innerSides(i)(0)
			val scaledI1: Vector2D = innerSides(i)(3)

			// Tri 1 (left): outer[i] → midpoint → scaled[i]
			val tri1 = new Array[Vector2D](12)
			tri1(0) = leftHalf(0).clone(); tri1(1) = leftHalf(1).clone()
			tri1(2) = leftHalf(2).clone(); tri1(3) = leftHalf(3).clone()
			val conn1 = makeConnector(midpoint, scaledI)
			tri1(4) = conn1(0); tri1(5) = conn1(1); tri1(6) = conn1(2); tri1(7) = conn1(3)
			val conn2 = makeConnector(scaledI, outerSides(i)(0))
			tri1(8) = conn2(0); tri1(9) = conn2(1); tri1(10) = conn2(2); tri1(11) = conn2(3)

			// Tri 2 (center): midpoint → scaled[i+1] → scaled[i]
			val tri2 = new Array[Vector2D](12)
			val conn3 = makeConnector(midpoint, scaledI1)
			tri2(0) = conn3(0); tri2(1) = conn3(1); tri2(2) = conn3(2); tri2(3) = conn3(3)
			val revInner = reversePointsOfSide(innerSides(i))
			tri2(4) = revInner(0).clone(); tri2(5) = revInner(1).clone()
			tri2(6) = revInner(2).clone(); tri2(7) = revInner(3).clone()
			val conn4 = makeConnector(scaledI, midpoint)
			tri2(8) = conn4(0); tri2(9) = conn4(1); tri2(10) = conn4(2); tri2(11) = conn4(3)

			// Tri 3 (right): midpoint → outer[i+1] → scaled[i+1]
			val tri3 = new Array[Vector2D](12)
			tri3(0) = rightHalf(0).clone(); tri3(1) = rightHalf(1).clone()
			tri3(2) = rightHalf(2).clone(); tri3(3) = rightHalf(3).clone()
			val conn5 = makeConnector(outerSides(i)(3), scaledI1)
			tri3(4) = conn5(0); tri3(5) = conn5(1); tri3(6) = conn5(2); tri3(7) = conn5(3)
			val conn6 = makeConnector(scaledI1, midpoint)
			tri3(8) = conn6(0); tri3(9) = conn6(1); tri3(10) = conn6(2); tri3(11) = conn6(3)

			polyArray(i * 3) = new Polygon2D(tri1.toList, PolygonType.SPLINE_POLYGON)
			polyArray((i * 3) + 1) = new Polygon2D(tri2.toList, PolygonType.SPLINE_POLYGON)
			polyArray((i * 3) + 2) = new Polygon2D(tri3.toList, PolygonType.SPLINE_POLYGON)
		}
		polyArray
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

	private def makePolysVisible(polyArray: Array[Polygon2D]): Unit = {
		for (i <- 0 until totNewPolys) {
			Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
		}
	}

}
