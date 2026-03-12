/**
Animator2D

Supports two modes:
- Cumulative (jitter = false): scale/rotation/speed accumulate each frame (original behavior).
- Jitter (jitter = true): each frame's transform is undone before applying the next,
  so the sprite oscillates around its home position rather than drifting.
*/

package org.loom.scene

import org.loom.geometry._
import org.loom.utility._
import scala.collection.mutable

class Animator2D(var animating: Boolean, var scale: Vector2D, var rotation: Double, var speed: Vector2D) extends SpriteAnimator {

   var jitter: Boolean = false

   private val currentScale: Vector2D = scale
   private var currentRotation: Double = rotation
   private val currentSpeed: Vector2D = speed

   // Track last-applied values for jitter mode (to undo previous frame)
   private var lastAppliedScale: Vector2D = Vector2D(1.0, 1.0)
   private var lastAppliedRotation: Double = 0.0
   private var lastAppliedSpeed: Vector2D = Vector2D(0.0, 0.0)

   private val randomFeatures: mutable.Map[String, Boolean] = mutable.Map("scale" -> false,"rotation" -> false, "speed" -> false)
   private val randomScaleParams: mutable.Map[String, Array[Double]] = mutable.Map("x" -> Array(0,.0), "y" -> Array(0,0))
   private val randomRotationParams: mutable.Map[String, Array[Double]] = mutable.Map("x" -> Array(0,0))
   private val randomSpeedParams: mutable.Map[String, Array[Double]] = mutable.Map("x" -> Array(0,0), "y" -> Array(0,0))

   /**
   Update sprite scale, rotation and translation.
   In jitter mode, undo the previous frame's transforms before applying new ones.
   */
   def update(sprite: Sprite2D): Unit = {
      if (animating) {
         process()
         if (jitter) {
            // Undo previous frame's transforms (reverse order)
            if (randomFeatures("speed")) {
               sprite.translate(Vector2D(-lastAppliedSpeed.x, -lastAppliedSpeed.y))
            }
            if (randomFeatures("rotation")) {
               sprite.rotate(-lastAppliedRotation)
            }
            if (randomFeatures("scale") && lastAppliedScale.x != 0 && lastAppliedScale.y != 0) {
               sprite.scale(Vector2D(1.0 / lastAppliedScale.x, 1.0 / lastAppliedScale.y))
            }
            // Apply new transforms
            if (randomFeatures("scale")) {
               sprite.scale(currentScale)
               lastAppliedScale = Vector2D(currentScale.x, currentScale.y)
            }
            if (randomFeatures("rotation")) {
               sprite.rotate(currentRotation)
               lastAppliedRotation = currentRotation
            }
            if (randomFeatures("speed")) {
               sprite.translate(currentSpeed)
               lastAppliedSpeed = Vector2D(currentSpeed.x, currentSpeed.y)
            }
         } else {
            // Original cumulative mode
            if (randomFeatures("scale")) sprite.scale(currentScale)
            if (randomFeatures("rotation")) sprite.rotate(currentRotation)
            if (randomFeatures("speed")) sprite.translate(currentSpeed)
         }
      }
   }

   def setRandomScale (params: mutable.Map[String,Array[Double]]): Unit = {
      randomFeatures ("scale") = true
      randomScaleParams("x")(0) = params ("x")(0)
      randomScaleParams("x")(1) = params ("x")(1)
      randomScaleParams("y")(0) = params ("y")(0)
      randomScaleParams("y")(1) = params ("y")(1)
   }
   def setRandomRotation (params: mutable.Map[String,Array[Double]]): Unit = {
      randomFeatures ("rotation") = true
      randomRotationParams("x")(0) = params ("x")(0)
      randomRotationParams("x")(1) = params ("x")(1)
   }
   def setRandomSpeed (params: mutable.Map[String,Array[Double]]): Unit = {
      randomFeatures("speed") = true
      randomSpeedParams("x")(0) = params ("x")(0)
      randomSpeedParams("x")(1) = params ("x")(1)
      randomSpeedParams("y")(0) = params ("y")(0)
      randomSpeedParams("y")(1) = params ("y")(1)
   }

   def process(): Unit = {
      if (jitter) {
         // Jitter mode: random offset around the base value each frame (no accumulation)
         if (randomFeatures("scale")) {
            currentScale.x = scale.x + Randomise.range(randomScaleParams("x")(0), randomScaleParams("x")(1))
            currentScale.y = scale.y + Randomise.range(randomScaleParams("y")(0), randomScaleParams("y")(1))
         }
         if (randomFeatures("rotation")) {
            currentRotation = rotation + Randomise.range(randomRotationParams("x")(0), randomRotationParams("x")(1))
         }
         if (randomFeatures("speed")) {
            currentSpeed.x = Randomise.range(randomSpeedParams("x")(0), randomSpeedParams("x")(1))
            currentSpeed.y = Randomise.range(randomSpeedParams("y")(0), randomSpeedParams("y")(1))
         }
      } else {
         // Original cumulative mode
         if (randomFeatures("scale")) {
            currentScale.x = scale.x + Randomise.range(randomScaleParams("x")(0), randomScaleParams("x")(1))
            currentScale.y = scale.y + Randomise.range(randomScaleParams("y")(0), randomScaleParams("y")(1))
         }
         if (randomFeatures("rotation")) {
            currentRotation = currentRotation + Randomise.range(randomRotationParams("x")(0), randomRotationParams("x")(1))
         }
         if (randomFeatures("speed")) {
            currentSpeed.x = speed.x + Randomise.range(randomSpeedParams("x")(0), randomSpeedParams("x")(1))
            currentSpeed.y = speed.y + Randomise.range(randomSpeedParams("y")(0), randomSpeedParams("y")(1))
         }
      }
   }

   /**
   Clone the Animator2D.  Produces an independent copy.
   @return Animator2D
   */
   override def clone(): Animator2D = {
      val sc: Vector2D = scale.clone()
      val sp: Vector2D = speed.clone()
      val cloned = new Animator2D(animating, sc, rotation, sp)
      cloned.jitter = jitter
      cloned
   }
   def cloneAnimator(): SpriteAnimator = clone()

   override def toString(): String = "Animator2D animating: (" + animating + ", scale: " + scale.x + ",  rotation: " +
      rotation + ", speed: " + speed.x + ", " + speed.y + ", jitter: " + jitter
}
