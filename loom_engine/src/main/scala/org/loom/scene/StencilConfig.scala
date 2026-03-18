package org.loom.scene

/**
 * Configuration for stencil-based rendering (STENCILED mode).
 * Stamps full-RGBA PNGs along geometry edges or at point positions.
 * Unlike BrushConfig, there is no per-stamp tinting — images are composited as-is.
 * Opacity is animated separately via a RenderTransform (STENCIL_OPACITY slot).
 */
class StencilConfig(
  var stencilNames: Array[String],
  var drawMode: Int,
  var stampSpacing: Double,
  var spacingEasing: String,
  var followTangent: Boolean,
  var perpendicularJitterMin: Double,
  var perpendicularJitterMax: Double,
  var scaleMin: Double,
  var scaleMax: Double,
  var stampsPerFrame: Int,
  var agentCount: Int,
  var postCompletionMode: Int
) {
  /** Updated each frame by RenderTransform STENCIL_OPACITY slot. */
  var currentOpacity: Float = 1.0f

  def scalePixelValues(factor: Double): Unit = {
    stampSpacing = stampSpacing * factor
    perpendicularJitterMin = perpendicularJitterMin * factor
    perpendicularJitterMax = perpendicularJitterMax * factor
    stampsPerFrame = math.max(1, (stampsPerFrame * factor).round.toInt)
  }

  override def toString: String =
    s"StencilConfig(stencils=${stencilNames.mkString(",")}, mode=$drawMode, spacing=$stampSpacing)"
}

object StencilConfig {
  // Draw modes
  val FULL_PATH: Int   = 0
  val PROGRESSIVE: Int = 1

  // Post-completion modes (for progressive reveal)
  val HOLD: Int      = 0
  val LOOP: Int      = 1
  val PING_PONG: Int = 2

  def default(): StencilConfig = new StencilConfig(
    stencilNames          = Array.empty,
    drawMode              = FULL_PATH,
    stampSpacing          = 4.0,
    spacingEasing         = "LINEAR",
    followTangent         = true,
    perpendicularJitterMin = -2.0,
    perpendicularJitterMax =  2.0,
    scaleMin              = 0.8,
    scaleMax              = 1.2,
    stampsPerFrame        = 10,
    agentCount            = 1,
    postCompletionMode    = HOLD
  )
}
