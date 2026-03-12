package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * QUAD_BORD_ECHO subdivision for spline (bezier) polygons.
 * Same as SplineQuadBord but also includes the inset (echo) polygon as the last element.
 * Produces N+1 output polygons: N border quads + 1 echo.
 */
class SplineQuadBordEcho(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totBorderPolys: Int = subdivObj.sidesTotal
	val totNewPolys: Int = totBorderPolys + 1
	val numSidesPerPoly: Int = 4
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val scaledPoints: List[Vector2D] = getScaledSplinePoints()
		val innerSides: Array[Array[Vector2D]] = getArrayOfInsetSides(scaledPoints)

		// First N polys: border quads
		val borderPolys: Array[Polygon2D] = makeBorderPolys(outerSides, innerSides)

		// Last poly: the echo (inset polygon)
		val echoPolys: Array[Polygon2D] = new Array[Polygon2D](1)
		echoPolys(0) = new Polygon2D(scaledPoints, PolygonType.SPLINE_POLYGON)

		// Combine into single array
		val polyArray: Array[Polygon2D] = borderPolys ++ echoPolys

		// Apply transforms across all N+1 polys
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

	private def makeBorderPolys(outerSides: Array[Array[Vector2D]], innerSides: Array[Array[Vector2D]]): Array[Polygon2D] = {
		val polyArray: Array[Polygon2D] = new Array[Polygon2D](totBorderPolys)
		val cpRatio: Vector2D = subP.controlPointRatios

		for (i <- 0 until totBorderPolys) {
			val ptArray: Array[Vector2D] = new Array[Vector2D](numSidesPerPoly * numPointsPerPolySide) // 16

			val outer: Array[Vector2D] = outerSides(i)
			val inner: Array[Vector2D] = innerSides(i)

			// Side 1 (outer)
			ptArray(0) = outer(0).clone()
			ptArray(1) = outer(1).clone()
			ptArray(2) = outer(2).clone()
			ptArray(3) = outer(3).clone()

			// Side 2 (right connector)
			ptArray(4) = outer(3).clone()
			ptArray(5) = Formulas.lerp(outer(3), inner(3), cpRatio.x)
			ptArray(6) = Formulas.lerp(outer(3), inner(3), cpRatio.y)
			ptArray(7) = inner(3).clone()

			// Side 3 (inner, reversed)
			val reversedInner: Array[Vector2D] = reversePointsOfSide(inner)
			ptArray(8) = reversedInner(0).clone()
			ptArray(9) = reversedInner(1).clone()
			ptArray(10) = reversedInner(2).clone()
			ptArray(11) = reversedInner(3).clone()

			// Side 4 (left connector)
			ptArray(12) = inner(0).clone()
			ptArray(13) = Formulas.lerp(inner(0), outer(0), cpRatio.x)
			ptArray(14) = Formulas.lerp(inner(0), outer(0), cpRatio.y)
			ptArray(15) = outer(0).clone()

			polyArray(i) = new Polygon2D(ptArray.toList, PolygonType.SPLINE_POLYGON)
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
