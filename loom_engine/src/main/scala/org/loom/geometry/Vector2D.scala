/**
Vector2D represents a 2D coordinate or a trajectory.  You can see it as an x and a y coordinate or as speed, size, scaling factor, etc. - anything that has an x and a y component.
*/

package org.loom.geometry

import org.loom.utility._

class Vector2D(var x: Double, var y: Double) {

   override def toString(): String = "\n point x: " + (x*100).toInt + "   y: " + (y*100).toInt
   /**
   Translate the Vector2D by an x and y vector (Vector2D)
   @param trans the translation vector expressed as a Vector2D
   */
   def translate(trans: Vector2D): Unit = {
     //println("Vector2D, translate: " + trans)
      val t: Vector2D = Transform2D.translate(this, trans)
      this.x = t.x
      this.y = t.y
   }
   /**
   Scale the Vector2D by an x and y scaling factor (Vector2D)
   @param scale the scaling factor expressed as a Vector2D
   */
   def scale(scale: Vector2D): Unit = {
      val s: Vector2D = Transform2D.scale(this, scale)
      this.x = s.x
      this.y = s.y
   }
   /**
   Transform the Vector2D by an x and y scaling factor (Vector2D) around an offset
   a designated center (the offset point)
   @param transform the scale, translation and rotation in a Transform2D
   @offset the point to scale around
   */
   def transformAroundOffset(transform: Transform2D, offset: Vector2D): Unit = {
     translate(new Vector2D(-(offset.x), -(offset.y)))
      val s: Vector2D = Transform2D.scale(this, transform.scale)
      val r: Vector2D = Transform2D.rotate(s, transform.rotation.x)
      val t: Vector2D = Transform2D.translate(r, transform.translation)
      this.x = t.x
      this.y = t.y
      translate(new Vector2D(offset.x, offset.y))
   }
   /**
   Rotate the Vector2D by an angle
   @param angle the amount to rotate
   */
   def rotate(angle: Double): Unit = {
      val r: Vector2D = Transform2D.rotate(this, angle)
      this.x = r.x
      this.y = r.y
   }
   /**
   Clone the Vector2D.
   @return independent copy of this Vector2D
   */
   override def clone(): Vector2D = {
      new Vector2D(x, y)
   }

}


object Vector2D {

   val ORIENTATION_POSX_POSY = 0 //(north east)
   val ORIENTATION_POSX_NEGY = 1 //(south east)
   val ORIENTATION_NEGX_NEGY = 2 //(south west)
   val ORIENTATION_NEGX_POSY = 3 //(north west)

   def getVectorOrientation(v: Vector2D): Int = {

      var orientation: Int = 5//null (error) value

      if ((v.x >= 0) && (v.y >= 0)) {
         orientation = ORIENTATION_POSX_POSY 
      } else if ((v.x >= 0) && (v.y <= 0)) {
         orientation = ORIENTATION_POSX_NEGY
      } else if ((v.x <= 0) && (v.y <= 0)) {
         orientation = ORIENTATION_NEGX_NEGY
      } else if ((v.x <= 0) && (v.y >= 0)) {
         orientation = ORIENTATION_NEGX_POSY
      } 

      orientation

   }

   /**
   Tests if two Vector2Ds are equal.
   @param vA the first Vector2D
   @param vB the second Vector2D
   @return Boolean
   */
   def equals(vA: Vector2D, vB: Vector2D): Boolean = {
      if (vA.x == vB.x && vA.y == vB.y) true else false
   }
   /**
   Invert the values of input Vector2D.
   Positive values become negative. Negative values become positive.
   @param vector the Vector3D to be inverted
   @return inverted Vector2D
   */
   def invert(vector: Vector2D): Vector2D = {
      new Vector2D(-(vector.x), -(vector.y))
   }
   /**
   Get the difference between two Vecto2Ds.
   Subtract child vector from parent vector.
   @param child vector (Vector2D)
   @param parent vector (Vector2D)
   @return difference Vector2D
   */
   def difference(child: Vector2D, parent: Vector2D): Vector2D = {
      new Vector2D(parent.x - child.x, parent.y - child.y)
   }
   /**
   Convert a Vector2D to a Vector3D
   @param twoD vector (Vector2D)
   @param z depth value (Double)
   */
   def to3D (twoD: Vector2D, z: Double): Vector3D = {
     new Vector3D (twoD.x, twoD.y, z)
   }
   /**
   Add two vectors
   Creates a new Vector2D - use translate if you are not after this
   @param original vector
   @param additional vector
   */
   def add(origVector: Vector2D, addVector: Vector2D): Vector2D = {
      val newV: Vector2D = new Vector2D(0,0)
      newV.x = origVector.x + addVector.x
      newV.y = origVector.y + addVector.y
      newV
   }
   /**
   Multiplies two vectors
   @param original vector
   @param vector multiplier
   */
   def multiply(origVector: Vector2D, multiplyVector: Vector2D): Vector2D = {
      val newV: Vector2D = new Vector2D(0,0)
      newV.x = origVector.x * multiplyVector.x
      newV.y = origVector.y * multiplyVector.y
      newV
   }
   /**
   Multiplies by factor
   @param original vector
   @param vector multiplier
   */
   def multiply(origVector: Vector2D, factor: Double): Vector2D = {
      val newV: Vector2D = new Vector2D(0,0)
      newV.x = origVector.x * factor
      newV.y = origVector.y * factor
      newV
   }
   /**
   Copies x, y values of a model vector into the copy
   @param model - original vector
   @param copy - the vector to take the values
   */
   def copyValues(model: Vector2D, copy: Vector2D): Unit = {
      copy.x = model.x
      copy.y = model.y
   }

}
