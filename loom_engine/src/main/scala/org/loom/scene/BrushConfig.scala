package org.loom.scene

/**
 * Configuration for brush-based rendering (BRUSHED mode).
 * Holds all parameters controlling how brush stamps are placed along polygon edges.
 */
class BrushConfig(
  var brushNames: Array[String],
  var drawMode: Int,
  var stampSpacing: Double,
  var spacingEasing: String,
  var followTangent: Boolean,
  var perpendicularJitterMin: Double,
  var perpendicularJitterMax: Double,
  var scaleMin: Double,
  var scaleMax: Double,
  var opacityMin: Double,
  var opacityMax: Double,
  var stampsPerFrame: Int,
  var agentCount: Int,
  var postCompletionMode: Int,
  var blurRadius: Int
) {

  /**
   * Scale all pixel-based values by the given factor (for quality scaling).
   * Called once during setup when quality > 1; BrushStampEngine then uses
   * the pre-scaled values directly without any further multiplication.
   */
  def scalePixelValues(factor: Double): Unit = {
    stampSpacing = stampSpacing * factor
    perpendicularJitterMin = perpendicularJitterMin * factor
    perpendicularJitterMax = perpendicularJitterMax * factor
    blurRadius = (blurRadius * factor).round.toInt
    stampsPerFrame = math.max(1, (stampsPerFrame * factor).round.toInt)
  }

  override def toString: String = {
    s"BrushConfig(brushes=${brushNames.mkString(",")}, mode=$drawMode, spacing=$stampSpacing)"
  }
}

object BrushConfig {
  // Draw modes
  val FULL_PATH: Int = 0
  val PROGRESSIVE: Int = 1

  // Post-completion modes (for progressive reveal)
  val HOLD: Int = 0
  val LOOP: Int = 1
  val PING_PONG: Int = 2

  def default(): BrushConfig = {
    BrushConfig(
      brushNames = Array("default.png"),
      drawMode = FULL_PATH,
      stampSpacing = 4.0,
      spacingEasing = "LINEAR",
      followTangent = true,
      perpendicularJitterMin = -2.0,
      perpendicularJitterMax = 2.0,
      scaleMin = 0.8,
      scaleMax = 1.2,
      opacityMin = 0.6,
      opacityMax = 1.0,
      stampsPerFrame = 10,
      agentCount = 1,
      postCompletionMode = HOLD,
      blurRadius = 0
    )
  }

  def apply(
    brushNames: Array[String],
    drawMode: Int,
    stampSpacing: Double,
    spacingEasing: String,
    followTangent: Boolean,
    perpendicularJitterMin: Double,
    perpendicularJitterMax: Double,
    scaleMin: Double,
    scaleMax: Double,
    opacityMin: Double,
    opacityMax: Double,
    stampsPerFrame: Int,
    agentCount: Int,
    postCompletionMode: Int,
    blurRadius: Int
  ): BrushConfig = {
    new BrushConfig(
      brushNames, drawMode, stampSpacing, spacingEasing, followTangent,
      perpendicularJitterMin, perpendicularJitterMax,
      scaleMin, scaleMax, opacityMin, opacityMax,
      stampsPerFrame, agentCount, postCompletionMode, blurRadius
    )
  }
}
