package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._

/**
 * SPLIT_DIAG subdivision for spline (bezier) polygons.
 * Geometry-aware: finds the pair of opposite vertices (even) or vertex-to-midpoint (odd)
 * whose connecting line is most diagonal (~45 degrees), regardless of side numbering.
 * Even-sided: splits vertex-to-vertex, no bezier splitting needed.
 * Odd-sided: splits through side N/2 at midpoint.
 * Produces 2 output polygons.
 */
class SplineSplitDiag(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

	val numPointsPerPolySide: Int = 4

	def getPolys(): Array[Polygon2D] = {

		val rotation = findBestRotation()
		val workingPoints = rotateSplinePoints(subdivObj.points, rotation)
		val sides: Array[Array[Vector2D]] = extractSides(workingPoints)
		val polyArray: Array[Polygon2D] = splitPolygon(sides)

		for (i <- 0 until polyArray.length) {
			Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
		}

		polyArray
	}

	/**
	 * Find the rotation that produces the most diagonal split line.
	 * "Diagonal" means closest to 45 degrees: min(|dx|,|dy|) / max(|dx|,|dy|) → 1.0.
	 * Even N: evaluates vertex-to-vertex lines for each pair of opposite anchors.
	 * Odd N: evaluates vertex-to-opposite-side-midpoint lines.
	 */
	private def findBestRotation(): Int = {
		val N = subdivObj.sidesTotal
		if (N < 3) return 0
		val half = N / 2
		val sides = extractSides(subdivObj.points)

		if (N % 2 == 0) {
			var bestIdx = 0
			var bestScore = -1.0
			for (i <- 0 until half) {
				val anchor_i = sides(i)(0)
				val anchor_h = sides(i + half)(0)
				val dx = Math.abs(anchor_i.x - anchor_h.x)
				val dy = Math.abs(anchor_i.y - anchor_h.y)
				val diagonalness = Math.min(dx, dy) / (Math.max(dx, dy) + 0.001)
				if (diagonalness > bestScore) {
					bestScore = diagonalness
					bestIdx = i
				}
			}
			bestIdx
		} else {
			var bestIdx = 0
			var bestScore = -1.0
			for (k <- 0 until N) {
				val anchor = sides(k)(0)
				val oppSide = sides((k + half) % N)
				val midX = (oppSide(0).x + oppSide(3).x) / 2.0
				val midY = (oppSide(0).y + oppSide(3).y) / 2.0
				val dx = Math.abs(anchor.x - midX)
				val dy = Math.abs(anchor.y - midY)
				val diagonalness = Math.min(dx, dy) / (Math.max(dx, dy) + 0.001)
				if (diagonalness > bestScore) {
					bestScore = diagonalness
					bestIdx = k
				}
			}
			bestIdx
		}
	}

	private def rotateSplinePoints(pts: List[Vector2D], sideOffset: Int): List[Vector2D] = {
		if (sideOffset == 0) return pts
		val shift = sideOffset * numPointsPerPolySide
		pts.drop(shift) ++ pts.take(shift)
	}

	private def extractSides(pts: List[Vector2D]): Array[Array[Vector2D]] = {
		val polySides: Array[Array[Vector2D]] = new Array[Array[Vector2D]](subdivObj.sidesTotal)
		for (i <- 0 until subdivObj.sidesTotal) {
			val side: Array[Vector2D] = new Array[Vector2D](numPointsPerPolySide)
			for (j <- 0 until numPointsPerPolySide) {
				side(j) = pts((numPointsPerPolySide * i) + j)
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

	private def cloneSide(side: Array[Vector2D]): Array[Vector2D] = {
		Array(side(0).clone(), side(1).clone(), side(2).clone(), side(3).clone())
	}

	private def splitPolygon(sides: Array[Array[Vector2D]]): Array[Polygon2D] = {
		val N = subdivObj.sidesTotal
		val half = N / 2

		if (N % 2 == 0) {
			splitEvenDiag(sides, N, half)
		} else {
			splitOdd(sides, N, half)
		}
	}

	/**
	 * Even case: diagonal split from anchor 0 to anchor N/2.
	 * No bezier splitting needed — just a connector between two existing anchors.
	 * Poly 1: sides 0..half-1, connector(anchor[half] → anchor[0])
	 * Poly 2: sides half..N-1, connector(anchor[0] → anchor[half])
	 */
	private def splitEvenDiag(sides: Array[Array[Vector2D]], N: Int, half: Int): Array[Polygon2D] = {
		val anchor0: Vector2D = sides(0)(0)
		val anchorH: Vector2D = sides(half)(0)

		val numSides1 = half + 1 // half full sides + 1 connector
		val pts1 = new Array[Vector2D](numSides1 * 4)
		var idx = 0
		for (s <- 0 until half) {
			val cs = cloneSide(sides(s)); for (p <- cs) { pts1(idx) = p; idx += 1 }
		}
		val conn1 = makeConnector(anchorH, anchor0); for (p <- conn1) { pts1(idx) = p; idx += 1 }

		val numSides2 = half + 1
		val pts2 = new Array[Vector2D](numSides2 * 4)
		idx = 0
		for (s <- half until N) {
			val cs = cloneSide(sides(s)); for (p <- cs) { pts2(idx) = p; idx += 1 }
		}
		val conn2 = makeConnector(anchor0, anchorH); for (p <- conn2) { pts2(idx) = p; idx += 1 }

		Array(
			new Polygon2D(pts1.toList, PolygonType.SPLINE_POLYGON),
			new Polygon2D(pts2.toList, PolygonType.SPLINE_POLYGON)
		)
	}

	/**
	 * Odd case: split side N/2 at midpoint.
	 * Poly 1: sides 0..half-1, leftHalfH, connector(midH → anchor0)
	 * Poly 2: rightHalfH, sides half+1..N-1, connector(anchor0 → midH)
	 */
	private def splitOdd(sides: Array[Array[Vector2D]], N: Int, half: Int): Array[Polygon2D] = {
		val tH: Double = subP.lineRatios.x

		val (leftH, rightH) = splitBezierAt(sides(half), tH)
		val midH: Vector2D = leftH(3)
		val anchor0: Vector2D = sides(0)(0)

		val numSides1 = half + 2
		val pts1 = new Array[Vector2D](numSides1 * 4)
		var idx = 0
		for (s <- 0 until half) {
			val cs = cloneSide(sides(s)); for (p <- cs) { pts1(idx) = p; idx += 1 }
		}
		val lH = cloneSide(leftH); for (p <- lH) { pts1(idx) = p; idx += 1 }
		val conn1 = makeConnector(midH, anchor0); for (p <- conn1) { pts1(idx) = p; idx += 1 }

		val numSides2 = (N - half) + 1
		val pts2 = new Array[Vector2D](numSides2 * 4)
		idx = 0
		val rH = cloneSide(rightH); for (p <- rH) { pts2(idx) = p; idx += 1 }
		for (s <- half + 1 until N) {
			val cs = cloneSide(sides(s)); for (p <- cs) { pts2(idx) = p; idx += 1 }
		}
		val conn2 = makeConnector(anchor0, midH); for (p <- conn2) { pts2(idx) = p; idx += 1 }

		Array(
			new Polygon2D(pts1.toList, PolygonType.SPLINE_POLYGON),
			new Polygon2D(pts2.toList, PolygonType.SPLINE_POLYGON)
		)
	}

}
