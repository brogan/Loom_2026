package org.loom.subdivide

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._

/**
 * SPLIT_VERT subdivision for spline (bezier) polygons.
 * Geometry-aware: finds the most horizontal pair of opposite sides and cuts through them,
 * producing a vertical split line regardless of the polygon's internal side numbering.
 * Produces 2 output polygons.
 */
class SplineSplitVert(subdivObj: Subdivision, @unused middle: Vector2D, subP: SubdivisionParams, @unused polyType: Int) {

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
	 * Find the rotation that produces the most vertical split line.
	 * Even N: find the most horizontal pair of opposite sides — cutting them produces a vertical split.
	 * Odd N: find the vertex-to-opposite-side-midpoint line that is most vertical.
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
				val dx_i = Math.abs(sides(i)(3).x - sides(i)(0).x)
				val dy_i = Math.abs(sides(i)(3).y - sides(i)(0).y)
				val dx_h = Math.abs(sides(i + half)(3).x - sides(i + half)(0).x)
				val dy_h = Math.abs(sides(i + half)(3).y - sides(i + half)(0).y)
				val horizontalness = (dx_i + dx_h) / (dy_i + dy_h + 0.001)
				if (horizontalness > bestScore) {
					bestScore = horizontalness
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
				val verticalness = dy / (dx + 0.001)
				if (verticalness > bestScore) {
					bestScore = verticalness
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
			splitEven(sides, N, half)
		} else {
			splitOdd(sides, N, half)
		}
	}

	/**
	 * Even case: split sides 0 and N/2 at parameter t.
	 * Poly 1: rightHalf0, sides 1..half-1, leftHalfH, connector back
	 * Poly 2: rightHalfH, sides half+1..N-1, leftHalf0, connector back
	 */
	private def splitEven(sides: Array[Array[Vector2D]], N: Int, half: Int): Array[Polygon2D] = {
		val t0: Double = subP.lineRatios.x
		val tH: Double = if (subP.continuous) subP.lineRatios.y else subP.lineRatios.x

		val (left0, right0) = splitBezierAt(sides(0), t0)
		val (leftH, rightH) = splitBezierAt(sides(half), tH)

		val mid0: Vector2D = left0(3)
		val midH: Vector2D = leftH(3)

		val numSides1 = half + 2
		val pts1 = new Array[Vector2D](numSides1 * 4)

		var idx = 0
		val r0 = cloneSide(right0); for (p <- r0) { pts1(idx) = p; idx += 1 }
		for (s <- 1 until half) {
			val cs = cloneSide(sides(s)); for (p <- cs) { pts1(idx) = p; idx += 1 }
		}
		val lH = cloneSide(leftH); for (p <- lH) { pts1(idx) = p; idx += 1 }
		val conn1 = makeConnector(midH, mid0); for (p <- conn1) { pts1(idx) = p; idx += 1 }

		val numSides2 = half + 2
		val pts2 = new Array[Vector2D](numSides2 * 4)

		idx = 0
		val rH = cloneSide(rightH); for (p <- rH) { pts2(idx) = p; idx += 1 }
		for (s <- half + 1 until N) {
			val cs = cloneSide(sides(s)); for (p <- cs) { pts2(idx) = p; idx += 1 }
		}
		val l0 = cloneSide(left0); for (p <- l0) { pts2(idx) = p; idx += 1 }
		val conn2 = makeConnector(mid0, midH); for (p <- conn2) { pts2(idx) = p; idx += 1 }

		Array(
			new Polygon2D(pts1.toList, PolygonType.SPLINE_POLYGON),
			new Polygon2D(pts2.toList, PolygonType.SPLINE_POLYGON)
		)
	}

	/**
	 * Odd case: split side N/2 at parameter t. Poly 1 starts from anchor 0.
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
