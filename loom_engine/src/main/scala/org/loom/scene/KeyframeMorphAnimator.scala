package org.loom.scene

import org.loom.geometry.Vector2D
import org.loom.utility.Easing

/**
 * A keyframe with an additional morphAmount field.
 * morphAmount: 0.0 = base shape, 1.0 = full morph target.
 */
case class MorphKeyframe(
  drawCycle: Int,
  posX: Double,
  posY: Double,
  scaleX: Double,
  scaleY: Double,
  rotation: Double,
  morphAmount: Double,
  easing: String
)

/**
 * Animates a sprite using keyframe interpolation with morph target support.
 *
 * Each frame:
 *   1. Interpolate morphAmount from bracketing keyframes
 *   2. Apply morph (overwrites polygon points to lerped base/target)
 *   3. Apply accumulated transform deltas (translate/scale/rotate) on top
 *
 * Since morph resets point positions each frame, transforms are tracked as
 * total accumulated values from the first keyframe.
 */
class KeyframeMorphAnimator(
  var animating: Boolean,
  val keyframes: Array[MorphKeyframe],
  val loopMode: String,
  val morphTarget: MorphTarget
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

    // Interpolate morph amount and apply morph first (resets points)
    val easedMorph = Easing.ease(t, kf1.morphAmount, kf2.morphAmount - kf1.morphAmount, duration, kf2.easing)
    morphTarget.applyMorph(sprite.shape, easedMorph)

    // Interpolate transform values
    val easedPosX = Easing.ease(t, kf1.posX, kf2.posX - kf1.posX, duration, kf2.easing)
    val easedPosY = Easing.ease(t, kf1.posY, kf2.posY - kf1.posY, duration, kf2.easing)
    val easedScaleX = Easing.ease(t, kf1.scaleX, kf2.scaleX - kf1.scaleX, duration, kf2.easing)
    val easedScaleY = Easing.ease(t, kf1.scaleY, kf2.scaleY - kf1.scaleY, duration, kf2.easing)
    val easedRotation = Easing.ease(t, kf1.rotation, kf2.rotation - kf1.rotation, duration, kf2.easing)

    // Compute deltas from last applied state
    val deltaX = easedPosX - lastPosX
    val deltaY = easedPosY - lastPosY
    val scaleRatioX = if (lastScaleX != 0) easedScaleX / lastScaleX else 1.0
    val scaleRatioY = if (lastScaleY != 0) easedScaleY / lastScaleY else 1.0
    val deltaRotation = easedRotation - lastRotation

    // Apply transforms on top of the morphed points
    if (deltaX != 0 || deltaY != 0) sprite.translate(Vector2D(deltaX, deltaY))
    if (scaleRatioX != 1.0 || scaleRatioY != 1.0) sprite.scale(Vector2D(scaleRatioX, scaleRatioY))
    if (deltaRotation != 0) sprite.rotate(deltaRotation)

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
        case _ =>
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
        case _ =>
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
    val deltaX = kf.posX - lastPosX
    val deltaY = kf.posY - lastPosY
    val scaleRatioX = if (lastScaleX != 0) kf.scaleX / lastScaleX else 1.0
    val scaleRatioY = if (lastScaleY != 0) kf.scaleY / lastScaleY else 1.0
    val deltaRotation = kf.rotation - lastRotation

    if (deltaX != 0 || deltaY != 0) sprite.translate(Vector2D(deltaX, deltaY))
    if (scaleRatioX != 1.0 || scaleRatioY != 1.0) sprite.scale(Vector2D(scaleRatioX, scaleRatioY))
    if (deltaRotation != 0) sprite.rotate(deltaRotation)

    lastPosX = kf.posX
    lastPosY = kf.posY
    lastScaleX = kf.scaleX
    lastScaleY = kf.scaleY
    lastRotation = kf.rotation
  }

  private def findBracketingKeyframes(): (MorphKeyframe, MorphKeyframe) = {
    var i = 0
    while (i < keyframes.length - 1) {
      if (drawCount >= keyframes(i).drawCycle && drawCount <= keyframes(i + 1).drawCycle) {
        return (keyframes(i), keyframes(i + 1))
      }
      i += 1
    }
    (keyframes(keyframes.length - 2), keyframes(keyframes.length - 1))
  }

  def cloneAnimator(): SpriteAnimator = {
    val cloned = KeyframeMorphAnimator(animating, keyframes.clone(), loopMode, morphTarget.clone())
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
