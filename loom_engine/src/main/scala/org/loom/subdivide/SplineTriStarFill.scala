package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

/**
 * TRI_STAR_FILL subdivision for spline (bezier) polygons.
 * Same geometry as TriStar but also includes fill triangles between the star triangles,
 * completely tiling the border region. Produces 2N+1 output polygons:
 * N star triangles + N fill triangles + 1 inner polygon.
 *
 * Matches the line version's behaviour of reversing the point list before computing.
 *
 * For each index i (on reversed points):
 *   Star tri:  revOuter[i] → revInsetMid[i] → revInsetMid[i-1]
 *   Fill tri:  revOuter[i] → revOuter[i+1] → revInsetMid[i]
 */
class SplineTriStarFill(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val totNewPolys: Int = (subdivObj.sidesTotal * 2) + 1
	val numSidesPerPoly: Int = 3
	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		// Reverse point list to match line version behaviour
		val reversedPoints: List[Vector2D] = subdivObj.points.reverse

		val outerSides: Array[Array[Vector2D]] = extractSides(reversedPoints)
		val scaledPoints: List[Vector2D] = scaleSplinePoints(reversedPoints)
		val innerSides: Array[Array[Vector2D]] = extractSides(scaledPoints)
		val insetMidPoints: Array[Vector2D] = computeInsetMidPoints(innerSides)

		val polyArray: Array[Polygon2D] = makeAllPolys(outerSides, insetMidPoints)

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

	private def extractSides(pts: List[Vector2D]): Array[Array[Vector2D]] = {
		val polySides: Array[Array[Vector2D]] = new Array[Array[Vector2D]](subdivObj.sidesTotal)
		for (i <- 0 until subdivObj.sidesTotal) {
			val side: Array[Vector2D] = new Array[Vector2D](numPointsPerPolySide)
			for (j <- 0 until numPointsPerPolySide) {
				val ptIndex: Int = (numPointsPerPolySide * i) + j
				side(j) = pts(ptIndex)
			}
			polySides(i) = side
		}
		polySides
	}

	private def scaleSplinePoints(pts: List[Vector2D]): List[Vector2D] = {
		val center: Vector2D = Subdivision.getCenterSpline(pts)
		val scaled = new Array[Vector2D](pts.length)
		for (i <- 0 until pts.length) {
			scaled(i) = pts(i).clone
			scaled(i).transformAroundOffset(subP.insetTransform, center)
		}
		scaled.toList
	}

	private def computeInsetMidPoints(innerSides: Array[Array[Vector2D]]): Array[Vector2D] = {
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

	private def makeAllPolys(outerSides: Array[Array[Vector2D]], insetMidPoints: Array[Vector2D]): Array[Polygon2D] = {
		val polyArray = new Array[Polygon2D](totNewPolys)
		val N = subdivObj.sidesTotal

		for (i <- 0 until N) {
			val outerAnchor: Vector2D = outerSides(i)(0) // anchor of (reversed) side i
			val currMid: Vector2D = insetMidPoints(i)
			val prevMidIdx: Int = (i + N - 1) % N
			val prevMid: Vector2D = insetMidPoints(prevMidIdx)

			// Star triangle: revOuter[i] → revInsetMid[i] → revInsetMid[i-1]
			val starTri = new Array[Vector2D](12)
			// Side 1: outer[i] → insetMid[i]
			val sc1 = makeConnector(outerAnchor, currMid)
			starTri(0) = sc1(0); starTri(1) = sc1(1); starTri(2) = sc1(2); starTri(3) = sc1(3)
			// Side 2: insetMid[i] → insetMid[i-1]
			val sc2 = makeConnector(currMid, prevMid)
			starTri(4) = sc2(0); starTri(5) = sc2(1); starTri(6) = sc2(2); starTri(7) = sc2(3)
			// Side 3: insetMid[i-1] → outer[i]
			val sc3 = makeConnector(prevMid, outerAnchor)
			starTri(8) = sc3(0); starTri(9) = sc3(1); starTri(10) = sc3(2); starTri(11) = sc3(3)

			polyArray(i * 2) = new Polygon2D(starTri.toList, PolygonType.SPLINE_POLYGON)

			// Fill triangle: revOuter[i] → revOuter[i+1] → revInsetMid[i]
			val fillTri = new Array[Vector2D](12)
			// Side 1: outer bezier side i (outer[i] → outer[i+1])
			fillTri(0) = outerSides(i)(0).clone()
			fillTri(1) = outerSides(i)(1).clone()
			fillTri(2) = outerSides(i)(2).clone()
			fillTri(3) = outerSides(i)(3).clone()
			// Side 2: outer[i+1] → insetMid[i]
			val fc1 = makeConnector(outerSides(i)(3), currMid)
			fillTri(4) = fc1(0); fillTri(5) = fc1(1); fillTri(6) = fc1(2); fillTri(7) = fc1(3)
			// Side 3: insetMid[i] → outer[i]
			val fc2 = makeConnector(currMid, outerAnchor)
			fillTri(8) = fc2(0); fillTri(9) = fc2(1); fillTri(10) = fc2(2); fillTri(11) = fc2(3)

			polyArray((i * 2) + 1) = new Polygon2D(fillTri.toList, PolygonType.SPLINE_POLYGON)
		}

		// Inner polygon connecting all inset midpoints
		polyArray(totNewPolys - 1) = makeInnerPoly(insetMidPoints)

		polyArray
	}

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
