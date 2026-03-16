package org.loom.scene

import org.loom.geometry.Vector2D
import org.loom.utility.Easing

/**
 * A keyframe with an additional morphAmount field.
 * morphAmount is a continuous chain position: 0.0 = base, 1.0 = mt1, 2.0 = mt2, etc.
 * Fractional values interpolate between adjacent targets (e.g. 1.5 = midpoint mt1→mt2).
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
 *   2. Apply morph — overwrites polygon points with lerped base/target positions
 *   3. Apply keyframe position/scale/rotation transforms on top
 *
 * IMPORTANT: applyMorph resets all shape point positions every frame, so the
 * standard delta-tracking approach (used by KeyframeAnimator) breaks: after a
 * morph reset, the only transform applied would be the tiny per-frame delta,
 * not the full accumulated transform.
 *
 * Fix: after each applyMorph, re-apply the FULL current keyframe transform as
 * an absolute offset from the first keyframe (kf0) baseline:
 *   translate by (easedPos - kf0.pos)
 *   scale    by (easedScale / kf0.scale)
 *   rotate   by (easedRotation - kf0.rotation)
 * This produces the correct result because applyMorph restores the "home" state
 * (the morph-lerped snapshot with the sprite's own base transforms baked in),
 * and we then move/scale/rotate from that home state each frame.
 */
class KeyframeMorphAnimator(
  var animating: Boolean,
  val keyframes: Array[MorphKeyframe],
  val loopMode: String,
  val morphTarget: MorphTarget
) extends SpriteAnimator {

  private var drawCount: Int = 0
  private var direction: Int = 1
  private var finished: Boolean = false

  def update(sprite: Sprite2D): Unit = {
    if (!animating || keyframes.length < 2 || finished) return

    val (kf1, kf2) = findBracketingKeyframes()
    val duration = (kf2.drawCycle - kf1.drawCycle).toDouble
    val t = (drawCount - kf1.drawCycle).toDouble

    // Apply morph — resets shape points to lerped snapshot state
    val easedMorph = Easing.ease(t, kf1.morphAmount, kf2.morphAmount - kf1.morphAmount, duration, kf2.easing)
    morphTarget.applyMorph(sprite.shape, easedMorph)

    // Re-apply full current transforms as absolute offsets from kf0 baseline.
    // (Cannot use deltas: applyMorph above has already discarded the previous frame's transform.)
    val kf0 = keyframes.head
    val easedPosX     = Easing.ease(t, kf1.posX,     kf2.posX     - kf1.posX,     duration, kf2.easing)
    val easedPosY     = Easing.ease(t, kf1.posY,     kf2.posY     - kf1.posY,     duration, kf2.easing)
    val easedScaleX   = Easing.ease(t, kf1.scaleX,   kf2.scaleX   - kf1.scaleX,   duration, kf2.easing)
    val easedScaleY   = Easing.ease(t, kf1.scaleY,   kf2.scaleY   - kf1.scaleY,   duration, kf2.easing)
    val easedRotation = Easing.ease(t, kf1.rotation, kf2.rotation - kf1.rotation, duration, kf2.easing)

    val dx = easedPosX - kf0.posX
    val dy = easedPosY - kf0.posY
    val sx = if (kf0.scaleX != 0) easedScaleX / kf0.scaleX else 1.0
    val sy = if (kf0.scaleY != 0) easedScaleY / kf0.scaleY else 1.0
    val dr = easedRotation - kf0.rotation

    if (dx != 0 || dy != 0) sprite.translate(Vector2D(dx, dy))
    if (sx != 1.0 || sy != 1.0) sprite.scale(Vector2D(sx, sy))
    if (dr != 0) sprite.rotate(dr)

    drawCount += direction

    val lastCycle  = keyframes.last.drawCycle
    val firstCycle = keyframes.head.drawCycle

    if (direction == 1 && drawCount > lastCycle) {
      loopMode match {
        case "LOOP"      => drawCount = firstCycle
        case "PING_PONG" => drawCount = lastCycle; direction = -1
        case _           => finished = true
      }
    } else if (direction == -1 && drawCount < firstCycle) {
      loopMode match {
        case "LOOP"      => drawCount = firstCycle; direction = 1
        case "PING_PONG" => drawCount = firstCycle; direction = 1
        case _           => finished = true
      }
    }
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
    cloned.finished  = finished
    cloned
  }
}
