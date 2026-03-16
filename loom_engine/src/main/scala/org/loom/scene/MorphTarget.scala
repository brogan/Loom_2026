package org.loom.scene

import org.loom.geometry.{Shape2D, Vector2D}

/**
 * Holds a chain of snapshot arrays enabling multi-target morphing:
 *   snapshots(0) = base shape
 *   snapshots(1) = morph target 1
 *   snapshots(2) = morph target 2
 *   ...
 *
 * morphAmount (0..N) is interpreted as a continuous position through the chain:
 *   0.0       → base
 *   1.0       → mt1
 *   2.0       → mt2
 *   k .. k+1  → lerp(snapshots(k), snapshots(k+1), position − k)
 *
 * Single-target sprites (N=1) with morphAmount in [0,1] behave identically to
 * the original two-array implementation.
 *
 * All shapes in the chain must share the same topology (polygon count, vertex
 * count per polygon, polygon types).
 */
class MorphTarget(val snapshots: Array[Array[Array[Vector2D]]]) {

  /**
   * Apply morph at the given position (0.0 .. N) to the shape.
   * Writes directly into shape.polys[pi].points[vi] (overwrite, not delta).
   */
  def applyMorph(shape: Shape2D, position: Double): Unit = {
    val n = snapshots.length - 1
    if (n < 1) return
    val clamped = math.max(0.0, math.min(position, n.toDouble))
    val seg = math.min(clamped.toInt, n - 1)
    val t = clamped - seg
    val from = snapshots(seg)
    val to   = snapshots(seg + 1)
    val polys = shape.polys
    var pi = 0
    while (pi < polys.length && pi < from.length) {
      val pts   = polys(pi).points
      val bPts  = from(pi)
      val tPts  = to(pi)
      var vi = 0
      while (vi < pts.length && vi < bPts.length) {
        pts(vi).x = bPts(vi).x + (tPts(vi).x - bPts(vi).x) * t
        pts(vi).y = bPts(vi).y + (tPts(vi).y - bPts(vi).y) * t
        vi += 1
      }
      pi += 1
    }
  }

  override def clone(): MorphTarget = {
    val copy = snapshots.map(snap => MorphTarget.deepCopyPoints(snap))
    MorphTarget(copy)
  }
}

object MorphTarget {

  /**
   * Deep-copy all polygon point positions from a shape.
   * Returns Array[polyIndex][pointIndex] of cloned Vector2Ds.
   */
  def snapshot(shape: Shape2D): Array[Array[Vector2D]] = {
    val polys = shape.polys
    val result = new Array[Array[Vector2D]](polys.length)
    var i = 0
    for (poly <- polys) {
      val pts = new Array[Vector2D](poly.points.length)
      var j = 0
      for (p <- poly.points) {
        pts(j) = p.clone()
        j += 1
      }
      result(i) = pts
      i += 1
    }
    result
  }

  /**
   * Validate that two shapes have matching topology for morphing:
   * same polygon count, same vertex count per polygon, same polygon types.
   */
  def validate(base: Shape2D, target: Shape2D): Boolean = {
    if (base.polys.length != target.polys.length) {
      println(s"MorphTarget validation failed: polygon count mismatch (base=${base.polys.length}, target=${target.polys.length})")
      return false
    }
    for (i <- 0 until base.polys.length) {
      val bp = base.polys(i)
      val tp = target.polys(i)
      if (bp.points.length != tp.points.length) {
        println(s"MorphTarget validation failed: polygon $i vertex count mismatch (base=${bp.points.length}, target=${tp.points.length})")
        return false
      }
      if (bp.polyType != tp.polyType) {
        println(s"MorphTarget validation failed: polygon $i type mismatch (base=${bp.polyType}, target=${tp.polyType})")
        return false
      }
    }
    true
  }

  private def deepCopyPoints(points: Array[Array[Vector2D]]): Array[Array[Vector2D]] = {
    val result = new Array[Array[Vector2D]](points.length)
    for (i <- points.indices) {
      val src = points(i)
      val dst = new Array[Vector2D](src.length)
      for (j <- src.indices) {
        dst(j) = src(j).clone()
      }
      result(i) = dst
    }
    result
  }
}
