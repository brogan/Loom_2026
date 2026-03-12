package org.loom.scene

/**
 * Common interface for sprite animation strategies.
 * Implemented by Animator2D (random jitter) and KeyframeAnimator (keyframe interpolation).
 */
trait SpriteAnimator {
  var animating: Boolean
  def update(sprite: Sprite2D): Unit
  def cloneAnimator(): SpriteAnimator
}
