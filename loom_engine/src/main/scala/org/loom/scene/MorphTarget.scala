package org.loom.scene

import org.loom.geometry.{Shape2D, Vector2D}

/**
 * Holds snapshot point positions for base and target shapes,
 * enabling vertex-level morphing between the two.
 *
 * Both shapes must have identical topology: same polygon count,
 * same vertex count per polygon, same polygon types (line/spline).
 *
 * Usage:
 *   1. Construct sprite with base shape (constructor applies position/scale/rotation)
 *   2. Snapshot base points
 *   3. Load and subdivide morph target, apply same transforms, snapshot target points
 *   4. Each frame: call applyMorph(shape, amount) to lerp between base and target
 */
class MorphTarget(
  val basePoints: Array[Array[Vector2D]],
  val targetPoints: Array[Array[Vector2D]]
) {

  /**
   * Lerp all polygon points between base and target by the given amount.
   * amount = 0.0 → base shape, amount = 1.0 → full morph target.
   * Writes directly into the shape's polygon points (overwrite, not delta).
   */
  def applyMorph(shape: Shape2D, amount: Double): Unit = {
    val clampedAmount = math.max(0.0, math.min(1.0, amount))
    val polys = shape.polys
    var polyIdx = 0
    while (polyIdx < polys.length && polyIdx < basePoints.length) {
      val poly = polys(polyIdx)
      val base = basePoints(polyIdx)
      val target = targetPoints(polyIdx)
      val points = poly.points
      var ptIdx = 0
      while (ptIdx < points.length && ptIdx < base.length) {
        points(ptIdx).x = base(ptIdx).x + (target(ptIdx).x - base(ptIdx).x) * clampedAmount
        points(ptIdx).y = base(ptIdx).y + (target(ptIdx).y - base(ptIdx).y) * clampedAmount
        ptIdx += 1
      }
      polyIdx += 1
    }
  }

  override def clone(): MorphTarget = {
    MorphTarget(MorphTarget.deepCopyPoints(basePoints), MorphTarget.deepCopyPoints(targetPoints))
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
