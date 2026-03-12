package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * QUAD_BORD subdivision for spline (bezier) polygons.
 * Creates N border quads between the original polygon's outer sides and an inset (scaled) copy,
 * producing N output polygons (one per original side).
 *
 * Each border quad has 4 spline sides (16 points):
 *   Side 1: outer side (from original polygon)
 *   Side 2: right connector (bezier from outer end to inner end)
 *   Side 3: inner side (reversed inset side)
 *   Side 4: left connector (bezier from inner start to outer start)
 */
class SplineQuadBord(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totNewPolys: Int = subdivObj.sidesTotal
	val numSidesPerPoly: Int = 4
	val numPointsPerPolySide: Int = 4 // 2 anchor points and 2 control points

	def getPolys(): Array[Polygon2D] = {

		val outerSides: Array[Array[Vector2D]] = getArrayOfOldSides()
		val scaledPoints: List[Vector2D] = getScaledSplinePoints()
		val innerSides: Array[Array[Vector2D]] = getArrayOfInsetSides(scaledPoints)

		val polyArray: Array[Polygon2D] = makePolys(outerSides, innerSides)

		// centreIndex is 8 for each new quad poly (midpoint of 16-point polygon)
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

	/**
	 * Extract the N sides from the original polygon.
	 * Each side is 4 points: anchor, control, control, anchor.
	 */
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
	 * Scale all points toward the spline center (anchors only) using insetTransform.
	 */
	private def getScaledSplinePoints(): List[Vector2D] = {
		val center: Vector2D = Subdivision.getCenterSpline(subdivObj.points)
		val pts = new Array[Vector2D](subdivObj.points.length)
		for (i <- 0 until pts.length) {
			pts(i) = subdivObj.points(i).clone
			pts(i).transformAroundOffset(subP.insetTransform, center)
		}
		pts.toList
	}

	/**
	 * Extract the N sides from the inset (scaled) polygon.
	 * Same indexing as getArrayOfOldSides but on the scaled points.
	 */
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
	 * Assemble N border quad polygons, each with 4 spline sides (16 points).
	 * For each side i:
	 *   Side 1 (outer): outerSide[i] points 0-3
	 *   Side 2 (right connector): bezier from outer end to inner end
	 *   Side 3 (inner, reversed): reversed inset side i
	 *   Side 4 (left connector): bezier from inner start to outer start
	 */
	private def makePolys(outerSides: Array[Array[Vector2D]], innerSides: Array[Array[Vector2D]]): Array[Polygon2D] = {
		val polyArray: Array[Polygon2D] = new Array[Polygon2D](totNewPolys)
		val cpRatio: Vector2D = subP.controlPointRatios // default (.25, .75)

		for (i <- 0 until totNewPolys) {
			val ptArray: Array[Vector2D] = new Array[Vector2D](numSidesPerPoly * numPointsPerPolySide) // 16

			val outer: Array[Vector2D] = outerSides(i)
			val inner: Array[Vector2D] = innerSides(i)

			// Side 1 (outer): the original side, points 0-3
			ptArray(0) = outer(0).clone()
			ptArray(1) = outer(1).clone()
			ptArray(2) = outer(2).clone()
			ptArray(3) = outer(3).clone()

			// Side 2 (right connector): bezier from outer end to inner end
			ptArray(4) = outer(3).clone()
			ptArray(5) = Formulas.lerp(outer(3), inner(3), cpRatio.x)
			ptArray(6) = Formulas.lerp(outer(3), inner(3), cpRatio.y)
			ptArray(7) = inner(3).clone()

			// Side 3 (inner, reversed): reversed inset side i
			val reversedInner: Array[Vector2D] = reversePointsOfSide(inner)
			ptArray(8) = reversedInner(0).clone()
			ptArray(9) = reversedInner(1).clone()
			ptArray(10) = reversedInner(2).clone()
			ptArray(11) = reversedInner(3).clone()

			// Side 4 (left connector): bezier from inner start to outer start
			ptArray(12) = inner(0).clone()
			ptArray(13) = Formulas.lerp(inner(0), outer(0), cpRatio.x)
			ptArray(14) = Formulas.lerp(inner(0), outer(0), cpRatio.y)
			ptArray(15) = outer(0).clone()

			polyArray(i) = new Polygon2D(ptArray.toList, PolygonType.SPLINE_POLYGON)
		}
		polyArray
	}

	/**
	 * Reverse the points of a 4-point spline side.
	 */
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
