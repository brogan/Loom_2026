package org.loom.scene

import org.loom.geometry.{PolygonType, Vector2D}
import org.loom.utility.{Easing, Formulas, Randomise}

import java.awt.{AlphaComposite, Color, Graphics2D}
import java.awt.geom.AffineTransform
import java.awt.image.BufferedImage

/**
 * Core engine for drawing brush stamps along edges.
 * Supports both full-path (all stamps per frame) and progressive reveal modes.
 */
object BrushStampEngine {

  /**
   * Draw an entire edge with brush stamps (FULL_PATH mode).
   * When perturbedPath is Some, stamps follow the perturbed path geometry.
   */
  def drawFullEdge(
    g2D: Graphics2D,
    edge: BrushEdge,
    perturbedPath: Option[PerturbedPath],
    config: BrushConfig,
    brushes: Array[BufferedImage],
    strokeColor: Color
  ): Unit = {
    val effectiveLength = perturbedPath.map(_.length).getOrElse(edge.length)
    if (brushes.isEmpty || effectiveLength <= 0) return

    // Values are pre-scaled by Renderer.scalePixelValues during setup — use directly
    val spacing = math.max(1.0, config.stampSpacing)
    val numStamps = math.max(1, (effectiveLength / spacing).toInt)
    val perpMin = config.perpendicularJitterMin
    val perpMax = config.perpendicularJitterMax

    for (i <- 0 to numStamps) {
      val t = if (numStamps == 0) 0.5
              else Easing.ease(i.toDouble, 0.0, 1.0, numStamps.toDouble, config.spacingEasing)

      val tClamped = math.max(0.0, math.min(1.0, t))

      val (position, tangentAngle, pathScale) = perturbedPath match {
        case Some(pp) =>
          val (pos, angle, sc) = pp.evaluate(tClamped)
          (pos, angle, sc)
        case None =>
          val (pos, angle) = getPositionAndTangent(edge, tClamped)
          (pos, angle, -1.0)
      }

      val pressure = edge.pressureStart + (edge.pressureEnd - edge.pressureStart) * tClamped
      val brush = brushes(Randomise.range(0, brushes.length - 1))
      val tintedBrush = BrushLibrary.getTintedBrush(brush, strokeColor)
      val baseScale = if (pathScale >= 0 && config.meanderConfig.scaleAlongPath) pathScale
                      else Randomise.range(config.scaleMin, config.scaleMax)
      val stampScale = baseScale * (1.0 - config.pressureSizeInfluence + pressure * config.pressureSizeInfluence)
      val baseOpacity = Randomise.range(config.opacityMin, config.opacityMax)
      val opacity = (baseOpacity * (1.0 - config.pressureAlphaInfluence + pressure * config.pressureAlphaInfluence)).toFloat
      val perpJitter = Randomise.range(perpMin, perpMax)

      stampBrush(g2D, tintedBrush, position, tangentAngle, stampScale, opacity, perpJitter, config.followTangent)
    }
  }

  /**
   * Draw progressive stamps for a single agent advancing along its assigned edges.
   * When perturbedPaths(edgeIdx) is Some, stamps follow the perturbed path geometry.
   * Returns the number of stamps actually drawn.
   */
  def drawProgressiveStamps(
    g2D: Graphics2D,
    edges: Array[BrushEdge],
    perturbedPaths: Array[Option[PerturbedPath]],
    agent: BrushAgent,
    config: BrushConfig,
    brushes: Array[BufferedImage],
    strokeColor: Color,
    stampsToPlace: Int
  ): Int = {
    if (brushes.isEmpty || agent.completed) return 0

    var stampsDrawn = 0
    // Values are pre-scaled by Renderer.scalePixelValues during setup — use directly
    val spacing = math.max(1.0, config.stampSpacing)
    val perpMin = config.perpendicularJitterMin
    val perpMax = config.perpendicularJitterMax

    while (stampsDrawn < stampsToPlace && !agent.completed) {
      val edgeIdx = agent.currentEdgeIndex
      if (edgeIdx < 0 || edgeIdx >= edges.length) {
        agent.completed = true
        return stampsDrawn
      }

      val edge = edges(edgeIdx)
      val pp   = if (edgeIdx < perturbedPaths.length) perturbedPaths(edgeIdx) else None
      val effectiveLength = pp.map(_.length).getOrElse(edge.length)
      val numStampsOnEdge = math.max(1, (effectiveLength / spacing).toInt)
      val tStep = 1.0 / numStampsOnEdge

      val t = agent.currentStampT
      val tClamped = math.max(0.0, math.min(1.0, t))

      val (position, tangentAngle, pathScale) = pp match {
        case Some(p) =>
          val (pos, angle, sc) = p.evaluate(tClamped)
          (pos, angle, sc)
        case None =>
          val (pos, angle) = getPositionAndTangent(edge, tClamped)
          (pos, angle, -1.0)
      }

      val pressure = edge.pressureStart + (edge.pressureEnd - edge.pressureStart) * tClamped
      val brush = brushes(Randomise.range(0, brushes.length - 1))
      val tintedBrush = BrushLibrary.getTintedBrush(brush, strokeColor)
      val baseScale = if (pathScale >= 0 && config.meanderConfig.scaleAlongPath) pathScale
                      else Randomise.range(config.scaleMin, config.scaleMax)
      val stampScale = baseScale * (1.0 - config.pressureSizeInfluence + pressure * config.pressureSizeInfluence)
      val baseOpacity = Randomise.range(config.opacityMin, config.opacityMax)
      val opacity = (baseOpacity * (1.0 - config.pressureAlphaInfluence + pressure * config.pressureAlphaInfluence)).toFloat
      val perpJitter = Randomise.range(perpMin, perpMax)

      stampBrush(g2D, tintedBrush, position, tangentAngle, stampScale, opacity, perpJitter, config.followTangent)
      stampsDrawn += 1

      // Advance along edge
      if (agent.direction == 1) {
        agent.currentStampT += tStep
        if (agent.currentStampT > 1.0) {
          agent.currentStampT = 0.0
          agent.currentEdgeIndex += 1
          if (agent.currentEdgeIndex > agent.edgeEndIndex) {
            agent.completed = true
          }
        }
      } else {
        agent.currentStampT -= tStep
        if (agent.currentStampT < 0.0) {
          agent.currentStampT = 1.0
          agent.currentEdgeIndex -= 1
          if (agent.currentEdgeIndex < agent.edgeStartIndex) {
            agent.completed = true
          }
        }
      }
    }

    stampsDrawn
  }

  /**
   * Stamp a single brush at a discrete point position (for POINT_POLYGON entries).
   * Uses random brush/scale/opacity from config, tangent angle 0, no tangent following.
   */
  def stampAtPoint(
    g2D: Graphics2D,
    position: Vector2D,
    config: BrushConfig,
    brushes: Array[BufferedImage],
    strokeColor: Color,
    pressure: Float = 1.0f
  ): Unit = {
    if (brushes.isEmpty) return
    val brush = brushes(Randomise.range(0, brushes.length - 1))
    val tintedBrush = BrushLibrary.getTintedBrush(brush, strokeColor)
    val baseScale = Randomise.range(config.scaleMin, config.scaleMax)
    val stampScale = baseScale * (1.0 - config.pressureSizeInfluence + pressure * config.pressureSizeInfluence)
    val baseOpacity = Randomise.range(config.opacityMin, config.opacityMax)
    val opacity = (baseOpacity * (1.0 - config.pressureAlphaInfluence + pressure * config.pressureAlphaInfluence)).toFloat
    val perpJitter = Randomise.range(config.perpendicularJitterMin, config.perpendicularJitterMax)
    stampBrush(g2D, tintedBrush, position, 0.0, stampScale, opacity, perpJitter, false)
  }

  /**
   * Stamp a single brush image at the given position.
   */
  private def stampBrush(
    g2D: Graphics2D,
    brush: BufferedImage,
    position: Vector2D,
    tangentAngle: Double,
    scale: Double,
    opacity: Float,
    perpJitter: Double,
    followTangent: Boolean
  ): Unit = {
    if (brush == null) return

    val halfW = brush.getWidth / 2.0
    val halfH = brush.getHeight / 2.0

    // Apply perpendicular jitter (offset along normal = tangent + 90 degrees)
    val normalAngle = tangentAngle + math.Pi / 2.0
    val px = position.x + perpJitter * math.cos(normalAngle)
    val py = position.y + perpJitter * math.sin(normalAngle)

    // Save composite and set opacity
    val savedComposite = g2D.getComposite
    g2D.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER, math.max(0f, math.min(1f, opacity))))

    // Build transform: translate to position, optionally rotate, scale, center brush
    val tx = new AffineTransform()
    tx.translate(px, py)
    if (followTangent) {
      tx.rotate(tangentAngle)
    }
    tx.scale(scale, scale)
    tx.translate(-halfW, -halfH)

    g2D.drawImage(brush, tx, null)

    // Restore composite
    g2D.setComposite(savedComposite)
  }

  /**
   * Get position and tangent angle at parameter t along an edge.
   */
  private def getPositionAndTangent(edge: BrushEdge, t: Double): (Vector2D, Double) = {
    if (edge.edgeType == PolygonType.LINE_POLYGON) {
      val p1 = edge.points(0)
      val p2 = edge.points(1)
      val pos = Formulas.lerp(p1, p2, t)
      val angle = math.atan2(p2.y - p1.y, p2.x - p1.x)
      (pos, angle)
    } else {
      // Spline: cubic bezier
      val a1 = edge.points(0)
      val c1 = edge.points(1)
      val c2 = edge.points(2)
      val a2 = edge.points(3)
      val pos = Formulas.bezierPoint(a1, c1, c2, a2, t)
      val angle = bezierTangentAngle(a1, c1, c2, a2, t)
      (pos, angle)
    }
  }

  /**
   * Compute tangent angle of cubic bezier at parameter t.
   * Derivative: B'(t) = 3(1-t)^2(c1-a1) + 6(1-t)t(c2-c1) + 3t^2(a2-c2)
   */
  private def bezierTangentAngle(a1: Vector2D, c1: Vector2D, c2: Vector2D, a2: Vector2D, t: Double): Double = {
    val mt = 1.0 - t
    val dx = 3.0 * mt * mt * (c1.x - a1.x) + 6.0 * mt * t * (c2.x - c1.x) + 3.0 * t * t * (a2.x - c2.x)
    val dy = 3.0 * mt * mt * (c1.y - a1.y) + 6.0 * mt * t * (c2.y - c1.y) + 3.0 * t * t * (a2.y - c2.y)
    math.atan2(dy, dx)
  }
}
