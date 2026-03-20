package org.loom.scene

import org.loom.geometry.Vector2D
import org.loom.utility.Easing
import org.loom.scaffold.Config

/**
 * Loop mode constants for keyframe animation.
 */
object LoopMode {
  val NONE = "NONE"
  val LOOP = "LOOP"
  val PING_PONG = "PING_PONG"

  def valueOf(name: String): String = name
}

/**
 * A single keyframe defining sprite state at a specific draw cycle.
 * The easing function controls the transition FROM the previous keyframe TO this one.
 */
case class Keyframe(
  drawCycle: Int,
  posX: Double,
  posY: Double,
  scaleX: Double,
  scaleY: Double,
  rotation: Double,
  easing: String
)

/**
 * Animates a sprite by interpolating between keyframes using easing functions.
 *
 * Since Sprite2D.translate/scale/rotate are cumulative (they modify underlying
 * polygon points in-place), this animator tracks the last-applied state and
 * computes deltas each frame.
 */
class KeyframeAnimator(
  var animating: Boolean,
  val keyframes: Array[Keyframe],
  val loopMode: String
) extends SpriteAnimator {

  private var drawCount: Int = 0
  private var direction: Int = 1
  private var lastPosX: Double = 0.0
  private var lastPosY: Double = 0.0
  private var lastScaleX: Double = 1.0
  private var lastScaleY: Double = 1.0
  private var lastRotation: Double = 0.0
  private var initialized: Boolean = false
  private var finished: Boolean = false

  def update(sprite: Sprite2D): Unit = {
    if (!animating || keyframes.length < 2 || finished) return

    if (!initialized) {
      initializeFromFirstKeyframe()
      initialized = true
    }

    val (kf1, kf2) = findBracketingKeyframes()
    val duration = (kf2.drawCycle - kf1.drawCycle).toDouble
    val t = (drawCount - kf1.drawCycle).toDouble

    val easedPosX = Easing.ease(t, kf1.posX, kf2.posX - kf1.posX, duration, kf2.easing)
    val easedPosY = Easing.ease(t, kf1.posY, kf2.posY - kf1.posY, duration, kf2.easing)
    val easedScaleX = Easing.ease(t, kf1.scaleX, kf2.scaleX - kf1.scaleX, duration, kf2.easing)
    val easedScaleY = Easing.ease(t, kf1.scaleY, kf2.scaleY - kf1.scaleY, duration, kf2.easing)
    val easedRotation = Easing.ease(t, kf1.rotation, kf2.rotation - kf1.rotation, duration, kf2.easing)

    val canvasW = (Config.width * Config.qualityMultiple).toDouble
    val canvasH = (Config.height * Config.qualityMultiple).toDouble

    // Translate: posX/posY are in [-200,200] normalised units (100 = half-canvas).
    // Convert to view-space pixels: delta * canvas / 200.
    val deltaX_px = (easedPosX - lastPosX) * canvasW / 200.0
    val deltaY_px = (easedPosY - lastPosY) * canvasH / 200.0

    val scaleRatioX = if (lastScaleX != 0) easedScaleX / lastScaleX else 1.0
    val scaleRatioY = if (lastScaleY != 0) easedScaleY / lastScaleY else 1.0
    val deltaRotation = easedRotation - lastRotation

    if (deltaX_px != 0 || deltaY_px != 0) sprite.translate(Vector2D(deltaX_px, deltaY_px))

    // Scale around the sprite's current centre to prevent position drift.
    if (scaleRatioX != 1.0 || scaleRatioY != 1.0) {
      val cx = easedPosX * canvasW / 200.0
      val cy = easedPosY * canvasH / 200.0
      sprite.translate(Vector2D(-cx, -cy))
      sprite.scale(Vector2D(scaleRatioX, scaleRatioY))
      sprite.translate(Vector2D(cx, cy))
    }

    // Rotate around the sprite's current centre to prevent position drift.
    if (deltaRotation != 0) {
      val cx = easedPosX * canvasW / 200.0
      val cy = easedPosY * canvasH / 200.0
      sprite.translate(Vector2D(-cx, -cy))
      sprite.rotate(deltaRotation)
      sprite.translate(Vector2D(cx, cy))
    }

    lastPosX = easedPosX
    lastPosY = easedPosY
    lastScaleX = easedScaleX
    lastScaleY = easedScaleY
    lastRotation = easedRotation

    drawCount += direction

    val lastCycle = keyframes.last.drawCycle
    val firstCycle = keyframes.head.drawCycle

    if (direction == 1 && drawCount > lastCycle) {
      loopMode match {
        case "LOOP" =>
          resetToFirstKeyframe(sprite)
          drawCount = firstCycle
        case "PING_PONG" =>
          drawCount = lastCycle
          direction = -1
        case _ => // NONE or unknown
          finished = true
      }
    } else if (direction == -1 && drawCount < firstCycle) {
      loopMode match {
        case "LOOP" =>
          drawCount = firstCycle
          direction = 1
        case "PING_PONG" =>
          drawCount = firstCycle
          direction = 1
        case _ => // NONE or unknown
          finished = true
      }
    }
  }

  private def initializeFromFirstKeyframe(): Unit = {
    if (keyframes.nonEmpty) {
      val kf = keyframes.head
      lastPosX = kf.posX
      lastPosY = kf.posY
      lastScaleX = kf.scaleX
      lastScaleY = kf.scaleY
      lastRotation = kf.rotation
    }
  }

  private def resetToFirstKeyframe(sprite: Sprite2D): Unit = {
    val kf = keyframes.head
    val canvasW = (Config.width * Config.qualityMultiple).toDouble
    val canvasH = (Config.height * Config.qualityMultiple).toDouble

    val deltaX_px = (kf.posX - lastPosX) * canvasW / 200.0
    val deltaY_px = (kf.posY - lastPosY) * canvasH / 200.0
    val scaleRatioX = if (lastScaleX != 0) kf.scaleX / lastScaleX else 1.0
    val scaleRatioY = if (lastScaleY != 0) kf.scaleY / lastScaleY else 1.0
    val deltaRotation = kf.rotation - lastRotation

    if (deltaX_px != 0 || deltaY_px != 0) sprite.translate(Vector2D(deltaX_px, deltaY_px))

    if (scaleRatioX != 1.0 || scaleRatioY != 1.0) {
      val cx = kf.posX * canvasW / 200.0
      val cy = kf.posY * canvasH / 200.0
      sprite.translate(Vector2D(-cx, -cy))
      sprite.scale(Vector2D(scaleRatioX, scaleRatioY))
      sprite.translate(Vector2D(cx, cy))
    }

    if (deltaRotation != 0) {
      val cx = kf.posX * canvasW / 200.0
      val cy = kf.posY * canvasH / 200.0
      sprite.translate(Vector2D(-cx, -cy))
      sprite.rotate(deltaRotation)
      sprite.translate(Vector2D(cx, cy))
    }

    lastPosX = kf.posX
    lastPosY = kf.posY
    lastScaleX = kf.scaleX
    lastScaleY = kf.scaleY
    lastRotation = kf.rotation
  }

  private def findBracketingKeyframes(): (Keyframe, Keyframe) = {
    var i = 0
    while (i < keyframes.length - 1) {
      if (drawCount >= keyframes(i).drawCycle && drawCount <= keyframes(i + 1).drawCycle) {
        return (keyframes(i), keyframes(i + 1))
      }
      i += 1
    }
    (keyframes(keyframes.length - 2), keyframes(keyframes.length - 1))
  }

  def cloneAnimator(): SpriteAnimator = clone()

  override def clone(): KeyframeAnimator = {
    val cloned = KeyframeAnimator(animating, keyframes.clone(), loopMode)
    cloned.drawCount = drawCount
    cloned.direction = direction
    cloned.lastPosX = lastPosX
    cloned.lastPosY = lastPosY
    cloned.lastScaleX = lastScaleX
    cloned.lastScaleY = lastScaleY
    cloned.lastRotation = lastRotation
    cloned.initialized = initialized
    cloned.finished = finished
    cloned
  }
}
