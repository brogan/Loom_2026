package org.loom.scene

import org.loom.geometry.{PolygonType, Vector2D}
import org.loom.utility.{Easing, Formulas, Randomise}

import java.awt.{AlphaComposite, Graphics2D, RenderingHints}
import java.awt.geom.AffineTransform
import java.awt.image.BufferedImage

/**
 * Core engine for stamping full-RGBA stencil images along edges and at points.
 * Unlike BrushStampEngine, there is no colour tinting — the PNG is composited as-is.
 * Opacity comes from StencilConfig.currentOpacity (updated by RenderTransform).
 */
object StencilStampEngine {

  /**
   * Draw an entire edge with stencil stamps (FULL_PATH mode).
   */
  def drawFullEdge(
    g2D: Graphics2D,
    edge: BrushEdge,
    config: StencilConfig,
    stencils: Array[BufferedImage],
    opacity: Float
  ): Unit = {
    if (stencils.isEmpty || edge.length <= 0) return

    val spacing = math.max(1.0, config.stampSpacing)
    val numStamps = math.max(1, (edge.length / spacing).toInt)
    val perpMin = config.perpendicularJitterMin
    val perpMax = config.perpendicularJitterMax

    for (i <- 0 to numStamps) {
      val t = if (numStamps == 0) 0.5
              else Easing.ease(i.toDouble, 0.0, 1.0, numStamps.toDouble, config.spacingEasing)
      val tClamped = math.max(0.0, math.min(1.0, t))

      val (position, tangentAngle) = getPositionAndTangent(edge, tClamped)
      val stencil = stencils(Randomise.range(0, stencils.length - 1))
      val stampScale = Randomise.range(config.scaleMin, config.scaleMax)
      val perpJitter = Randomise.range(perpMin, perpMax)

      stampStencil(g2D, stencil, position, tangentAngle, stampScale, opacity, perpJitter, config.followTangent)
    }
  }

  /**
   * Draw progressive stamps for a single agent advancing along its assigned edges.
   * Returns the number of stamps actually drawn.
   */
  def drawProgressiveStamps(
    g2D: Graphics2D,
    edges: Array[BrushEdge],
    agent: BrushAgent,
    config: StencilConfig,
    stencils: Array[BufferedImage],
    opacity: Float,
    stampsToPlace: Int
  ): Int = {
    if (stencils.isEmpty || agent.completed) return 0

    var stampsDrawn = 0
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
      val numStampsOnEdge = math.max(1, (edge.length / spacing).toInt)
      val tStep = 1.0 / numStampsOnEdge

      val t = agent.currentStampT
      val tClamped = math.max(0.0, math.min(1.0, t))

      val (position, tangentAngle) = getPositionAndTangent(edge, tClamped)
      val stencil = stencils(Randomise.range(0, stencils.length - 1))
      val stampScale = Randomise.range(config.scaleMin, config.scaleMax)
      val perpJitter = Randomise.range(perpMin, perpMax)

      stampStencil(g2D, stencil, position, tangentAngle, stampScale, opacity, perpJitter, config.followTangent)
      stampsDrawn += 1

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
   * Stamp a single stencil at a discrete point position.
   */
  def stampAtPoint(
    g2D: Graphics2D,
    position: Vector2D,
    config: StencilConfig,
    stencils: Array[BufferedImage],
    opacity: Float
  ): Unit = {
    if (stencils.isEmpty) return
    val stencil = stencils(Randomise.range(0, stencils.length - 1))
    val stampScale = Randomise.range(config.scaleMin, config.scaleMax)
    val perpJitter = Randomise.range(config.perpendicularJitterMin, config.perpendicularJitterMax)
    stampStencil(g2D, stencil, position, 0.0, stampScale, opacity, perpJitter, false)
  }

  /**
   * Stamp a single stencil image at the given position with full RGBA compositing.
   * No tinting — the image's own colour channels are preserved.
   */
  private def stampStencil(
    g2D: Graphics2D,
    stencil: BufferedImage,
    position: Vector2D,
    tangentAngle: Double,
    scale: Double,
    opacity: Float,
    perpJitter: Double,
    followTangent: Boolean
  ): Unit = {
    if (stencil == null) return

    val halfW = stencil.getWidth / 2.0
    val halfH = stencil.getHeight / 2.0

    val normalAngle = tangentAngle + math.Pi / 2.0
    val px = position.x + perpJitter * math.cos(normalAngle)
    val py = position.y + perpJitter * math.sin(normalAngle)

    val savedComposite = g2D.getComposite
    g2D.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                         RenderingHints.VALUE_INTERPOLATION_BILINEAR)
    g2D.setComposite(AlphaComposite.getInstance(AlphaComposite.SRC_OVER,
                       math.max(0f, math.min(1f, opacity))))

    val tx = new AffineTransform()
    tx.translate(px, py)
    if (followTangent) tx.rotate(tangentAngle)
    tx.scale(scale, scale)
    tx.translate(-halfW, -halfH)

    g2D.drawImage(stencil, tx, null)

    g2D.setComposite(savedComposite)
  }

  private def getPositionAndTangent(edge: BrushEdge, t: Double): (Vector2D, Double) = {
    if (edge.edgeType == PolygonType.LINE_POLYGON) {
      val p1 = edge.points(0)
      val p2 = edge.points(1)
      val pos = Formulas.lerp(p1, p2, t)
      val angle = math.atan2(p2.y - p1.y, p2.x - p1.x)
      (pos, angle)
    } else {
      val a1 = edge.points(0)
      val c1 = edge.points(1)
      val c2 = edge.points(2)
      val a2 = edge.points(3)
      val pos = Formulas.bezierPoint(a1, c1, c2, a2, t)
      val angle = bezierTangentAngle(a1, c1, c2, a2, t)
      (pos, angle)
    }
  }

  private def bezierTangentAngle(a1: Vector2D, c1: Vector2D, c2: Vector2D, a2: Vector2D, t: Double): Double = {
    val mt = 1.0 - t
    val dx = 3.0 * mt * mt * (c1.x - a1.x) + 6.0 * mt * t * (c2.x - c1.x) + 3.0 * t * t * (a2.x - c2.x)
    val dy = 3.0 * mt * mt * (c1.y - a1.y) + 6.0 * mt * t * (c2.y - c1.y) + 3.0 * t * t * (a2.y - c2.y)
    math.atan2(dy, dx)
  }
}
