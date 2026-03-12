package org.loom.scene

import org.loom.utility.Randomise

/**
 * Animator that morphs sprite vertices between base shape and a morph target
 * by a random percentage each draw cycle.
 *
 * Each frame: picks a random amount in [morphMin, morphMax], then overwrites
 * polygon points to the lerped position between base and target.
 * No cumulative state — each frame is independent.
 */
class JitterMorphAnimator(
  var animating: Boolean,
  val morphTarget: MorphTarget,
  val morphMin: Double,
  val morphMax: Double
) extends SpriteAnimator {

  def update(sprite: Sprite2D): Unit = {
    if (!animating) return
    val amount = Randomise.range(morphMin, morphMax)
    morphTarget.applyMorph(sprite.shape, amount)
  }

  def cloneAnimator(): SpriteAnimator = {
    JitterMorphAnimator(animating, morphTarget.clone(), morphMin, morphMax)
  }
}
