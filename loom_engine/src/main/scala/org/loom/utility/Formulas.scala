/**
Formulas - some useful formulas
*/

package org.loom.utility

import org.loom.geometry._

object Formulas {

   /**
   Converts radians to degrees.
   @param radians
   @return degrees
   */
   def radiansToDegrees(radians: Double): Double = radians * (180/math.Pi)
   /**
   Converts degrees to radians.
   @param radians
   @return degrees
   */
   def degreesToRadians(degrees: Double): Double = degrees * (math.Pi/180)
   /**
   Calculates the distance between two 2D points
   @param startX the first point x coordinate
   @param startY the first point y coordinate
   @param destX the second point x coordinate
   @param destY the second point y coordinate
   @return the distance between the two points
   */
   def hypotenuse(startX: Double, startY: Double, destX: Double, destY: Double): Double = {
      val diffX: Double = math.abs(destX-startX)
      val diffY: Double = math.abs(destY-startY)
      math.sqrt((diffX*diffX)+(diffY*diffY))
   }
   /**
   Calculates the distance between two 2D points
   @param start the position of the first point expressed as Vector2D
   @param dest the position of the second point expressed as Vector2D
   @return the distance between the two points
   */
   def hypotenuse(start: Vector2D, dest: Vector2D): Double = {
      val diffX: Double = math.abs(dest.x-start.x)
      val diffY: Double = math.abs(dest.y-start.y)
      math.sqrt((diffX*diffX)+(diffY*diffY))
   }
       /**
        * This need elimination - should be dest - start
   Calculates the distance between two 2D points as a Vector2D
   @param start the position of the first point expressed as Vector2D
   @param dest the position of the second point expressed as Vector2D
   @return the difference between the two points expressed as a signed Vector2D
   */
   def hypotenuseVector2DSigned(start: Vector2D, dest: Vector2D): Vector2D = {
      val diffX: Double = start.x-dest.x
      val diffY: Double = start.y-dest.y
      new Vector2D(diffX, diffY)
   }
   /**
    * this is the correct version for calculating vector between two points
    */
   def differenceBetweenTwoVectors(a: Vector2D, b: Vector2D): Vector2D = {
     val x = b.x-a.x
     val y = b.y-a.y
     new Vector2D(x,y)
   }
    /**
   Calculates the distance between two 2D points as a Vector2D as an Absolute number 
   @param start the position of the first point expressed as Vector2D
   @param dest the position of the second point expressed as Vector2D
   @return the difference between the two points expressed as an Absolute Vector2D
   */
   def hypotenuseVector2D(start: Vector2D, dest: Vector2D): Vector2D = {
      val diffX: Double = math.abs(dest.x-start.x)
      val diffY: Double = math.abs(dest.y-start.y)
      new Vector2D(diffX, diffY)
   }
   /**
   Calculates the distance between two 3D points.
   NEEDS TESTING.
   @param start the position of the first point expressed as Vector3D
   @param dest the position of the second point expressed as Vector3D
   @return the distance between the two points
   */
   def hypotenuse(start: Vector3D, dest: Vector3D): Double = {
      val diffX: Double = math.abs(dest.x-start.x)
      val diffY: Double = math.abs(dest.y-start.y)
      val diffZ: Double = math.abs(dest.z-start.z)
      math.sqrt((diffX*diffX)+(diffY*diffY)+(diffZ*diffZ))
   }

   /**
    * Calculates whether values in a vector and positive
    * and returns an array of two Booleans, with false indicating less than 0 (negative)
    * and true indicating greater than zero (positive)
    * @param the vector to assess
    */
   def getVectorSigns(v: Vector2D): Array[Boolean] = {
      val s: Array[Boolean] = new Array[Boolean](2)
      if (v.x < 0) {
         s(0) = false
      } else {
         s(0) = true
      }
      if (v.y < 0) {
         s(1) = false
      } else {
         s(1) = true
      }
      s
   }

   /**
    * perpendicular vector that accords with an orientation (see Vector2D)
    * works with shifting outside control points in terms of an orientation that is calculated from poly centre to middle of outside line
    * the difference between the middle and the control points is then converted to a perpendicular vector and cps are shifted accordingly
    * bulging/puffing follows this vector, contracting/pinching follows the reverse vector
    * @param v the vector to be converted to perpendicular vector and the orientation
    */


    def perpendicularVectorMatchOrientation(v: Vector2D, orientation: Int): Vector2D = {

        val nV: Vector2D = Formulas.inverseVector(v)

        if (orientation == Vector2D.ORIENTATION_POSX_POSY) {

           if (nV.x < 0) {
              nV.x = nV.x * (-1)
           }
           if (nV.y < 0) {
             nV.y = nV.y * (-1)
           }

        } else if (orientation == Vector2D.ORIENTATION_POSX_NEGY) {

           if (nV.x < 0) {
              nV.x = nV.x * (-1)
           }
           if (nV.y > 0) {
             nV.y = nV.y * (-1)
           }

        } else if (orientation == Vector2D.ORIENTATION_NEGX_NEGY) {

           if (nV.x > 0) {
              nV.x = nV.x * (-1)
           }
           if (nV.y > 0) {
             nV.y = nV.y * (-1)
           }

        } else if (orientation == Vector2D.ORIENTATION_NEGX_POSY) {

           if (nV.x > 0) {
              nV.x = nV.x * (-1)
           }
           if (nV.y < 0) {
             nV.y = nV.y * (-1)
           }

        }

        nV
    }


   /**
    * 
    * reverses a vector
    * just inverts the sign of each value
    * convenience method - calls inverSignOfVector below
    */
   def reverseVector(v: Vector2D): Vector2D = {
      invertSignOfVector(v)
   }
   def invertSignOfVector(v: Vector2D): Vector2D = {
      val invertX: Double = -1* v.x
      val invertY: Double = -1* v.y
      new Vector2D(invertX, invertY)
   }
      /**
    * 
    * adds one vector to another
    */
   def addVector2Ds (a: Vector2D, b:Vector2D): Vector2D = {
       new Vector2D((a.x+b.x),(a.y+b.y))
    }

   /**
     * checks if a vector's x and y values are both positive or both negative
     * returns true if they are
     * 
     */
   def isVectorAllPositiveOrAllNegative(v: Vector2D): Boolean = {
      var common: Boolean = false
      val nV: Vector2D = new Vector2D((v.x*100).toInt, (v.y*100).toInt) 
      println("isVectorAllPositiveOrAllNegative: " + v.toString() + "    "+ v.x + "   " + v.y)
      if (((nV.x <= 0) && (nV.y <= 0)) || ((nV.x >= 0) && (nV.y >= 0))) {
         common = true
         println("COMMON")
      } else {
         println("NOT COMMON: " + nV.x + "   " + nV.y)
      }
      common
   }
   /**
    * inverts x and y in a vector
    */
   def inverseVector(v: Vector2D): Vector2D = {
      val nV: Vector2D = new Vector2D(0,0)
      nV.x = v.y
      nV.y = v.x
      nV
   }
       /**
     * checks if two vectors have common signs
     * returns true if they do 
     * 
     */

    def isCommonVectorSigns(v1: Vector2D, v2: Vector2D): Boolean = {
      var common: Boolean = false
      if ((v1.x <= 0) && (v2.x <= 0) || ((v1.x >= 0) && (v2.x >= 0))) {
         if ((v1.y <= 0) && (v2.y <= 0) || ((v1.y >= 0) && (v2.y >= 0))) {
            common = true
         }
      }
      common
    }
        /**
     * checks for inverse vector signs
     * returns true if they are inverse, counting (0,0) vectors as (positive, positive)
     * 
     */

    def isInverseVectorSigns(v1: Vector2D, v2: Vector2D): Boolean = {
      var inverse: Boolean = false
      if ((v1.x < 0) && (v2.x >= 0) || ((v1.x >= 0) && (v2.x < 0))) {
         if ((v1.y < 0) && (v2.y >= 0) || ((v1.y >= 0) && (v2.y < 0))) {
            inverse = true
         }
      }
      inverse
    }
   /**
   Calculates opposite side when hypotenuse and angle are known
   @param hypo the length of the hypotenuse
   @param angle the angle
   @return the length of the opposite side
   */
   def opposite(hypo: Double, angle: Double): Double = {
      math.sin(angle.toRadians) * hypo
   }
   /**
   Calculates adjacent side when hypotenuse and angle are known
   @param hypo the length of the hypotenuse
   @param angle the angle
   @return the length of the opposite side
   */
   def adjacent(hypo: Double, angle: Double): Double = {
      math.cos(angle.toRadians) * hypo
   }

   /**
   Calculates a percentage based on a score and a total
   @param score 
   @param total
   @return the percentage the score is of the total
   */
   def percentage(score: Double, total: Double): Double = (score/total) * 100
   /**
   Scales a Vector3D on the basis of a specified view distance.
   @param point the position of the point expressed as Vector3D
   @param viewDist the view distance from the point
   @return the perspective scaled point for rendering on a 2D surface
   */
   def getPerspective(point: Vector3D, viewDist: Double): Vector3D = {
      val p: Double = viewDist/(point.z + viewDist)
      new Vector3D(point.x * p, point.y * p, 0)
   }
   /**
   Scales a translation Vector3D (speed, etc.) on the basis of a specified view distance.
   Warning: Deprecated (may no longer be necessary)
   @param point the position of the point expressed as Vector3D
   @param viewDist the view distance from the point
   @return the scaled translation (Vector3D)
   */
   def getZScaledTranslation(point: Vector3D, viewDist: Double): Vector3D = {
      val p: Double = viewDist/(point.z + viewDist)
      new Vector3D(point.x * p, point.y * p, point.z)
   }
   /**
   Converts a signed Byte value to an Int.
   Signed Bytes go from 0 to 127 and then from -128 (128) to -1 (255).
   We want to get an unsigned Byte value between 0 and 255 which is then
   return as an Int.
   @param b the signed Byte value
   */
   def signedByteToInt(b: Byte): Int = b & 0xFF

   /**
   Inverts an Int that is restricted to Byte values (0-255).
   Useful for creating an inverse relation between sensor readings
   and program parameters.
   @param b the signed Byte value to invert
   */
   def invertByteRestrictedIntValue(b: Int): Int = math.abs(b-255)
   /**
   Inverts an array of Ints tha are restricted to Byte values (0-255).
   Useful for creating an inverse relation between sensor readings
   and program parameters.
   @param b the signed Byte value to invert
   */
   def invertByteRestrictedIntValues(bA: Array[Int]): Array[Int] = {
      val aA: Array[Int] = new Array[Int](bA.length)
      for(i <- 0 until bA.length) aA(i) = invertByteRestrictedIntValue(bA(i))
      aA
   }
   /**
   Gets the least value in an Int array
   and returns the index.  Least must be less
   than 900000 as currently implemented.
   */
   def getLeastValueIndex(myArray: Array[Int]): Int = {
      var least: Int = 900000
      var index: Int = -1
      var count: Int = 0
      for (item <- myArray) {
         if (item < least) { least = item; index = count }
         count += 1
      }
      index
   } 

   /**
   Gets the greatest value in an Int array
   and returns the index.  Greatest must be greater
   than -900000 as currently implemented.
   */
   def getGreatestValueIndex(myArray: Array[Int]): Int = {
      var greatest: Int = -900000
      var index: Int = -1
      var count: Int = 0
      for (item <- myArray) {
         if (item > greatest) { greatest = item; index = count }
         count += 1
      }
      index
   }
   /**
    * Gets a circular index, so say you have triangle and you
    * need to move back to the final point from point 2 by adding 1, this will produce 3
    * and an index out of bounds error.  This formula enables you to get
    * 0 (the circular starting point) by providing the number and a total
    * @param n number (Int)
    * @param tot total in set (Int)
    * @return circular index
    */
   def circularIndex(n: Int, tot: Int): Int = {
	   var r: Int = n
	   if (n > tot-1) {
	  	   r = n % tot//get the modulus remainder
	   } else if (n < 0) {
	  	   r = tot - (math.abs(n) % tot)
	   }
	   r
   }
   /**
    * Gets average of two Vector2Ds
    */

   def average(a: Vector2D, b:Vector2D): Vector2D = {
     val av: Vector2D = new Vector2D(0,0)
     av.x = (a.x + b.x)/2
     av.y = (a.y + b.y)/2
     av
   }
   /**
    * Gets average of a list of Vector2D values
    */
   def average(points: List[Vector2D]): Vector2D = {
	   val p: Vector2D = new Vector2D(0,0)
	   for (point <- points) {
	  	   p.x += point.x
	  	   p.y += point.y
	   }
	   p.x = p.x/points.length
	   p.y = p.y/points.length
	   p
   }
      /**
    * Gets average of a list of Vector3D values
    */
   def average(points: List[Vector3D]): Vector3D = {
	   val p: Vector3D = new Vector3D(0,0,0)
	   for (point <- points) {
	  	   p.x += point.x
	  	   p.y += point.y
	  	   p.z += point.z
	   }
	   p.x = p.x/points.length
	   p.y = p.y/points.length
	   p.z = p.z/points.length
	   p
   }
   /**
    * Linear Interpolation 2D
    * @param a first point
    * @param b second point
    * @param t linear interpolation value (.75 is 75% along line that connects a and b)
    */
   def lerp(a: Vector2D, b: Vector2D, t: Double): Vector2D = {
	   val destX: Double = a.x + ((b.x - a.x) * t)
	   val destY: Double = a.y + ((b.y - a.y) * t)
	   new Vector2D(destX, destY)
   }
   /**
    * Get interpolated point on a bezier curve
    * Get interpolated point between anchor 1 and control point 1 (M1)
    * and then between control point 1 and control point 2 (M2)and then finally between
    * control point 2 and anchor point 2. (M3)
    * Now calculate the interpolated points between these three new points.(M1-M2) = M4, (M2-M3)= M5
    * Finally calculate the interpolated point between these two points and this
    * gives you the point on the curve (M6).
    * t is typically.5 because halfway points are needed, but may not be if midpoints randomised, so can be any value (usually between 0-1)
    * see: http://www.cubic.org/docs/bezier.htm
    */
   def bezierPoint(a1: Vector2D, c1: Vector2D, c2: Vector2D, a2: Vector2D, t: Double): Vector2D = {
      val M1: Vector2D = lerp(a1, c1, t)//M1 - point between anchor point 1 and control point 1
      val M2: Vector2D = lerp(c1, c2, t)//M2 - point between control point 1 and control point 2 
      val M3: Vector2D = lerp(c2, a2, t)//M3 - point between control point 2 and anchor point 2
      val M4: Vector2D = lerp(M1, M2, t)//M4 - point between M1 & M2
      val M5: Vector2D = lerp(M2, M3, t)//M5 - point between M2 & M3
      lerp(M4, M5, t)//M6 - point between M4 & M5, which should intersect with curve
   }
  
      /**
Just testing - get rid of this: effort to replace lerp
   def bezierPoint(a1: Vector2D, c1: Vector2D, c2: Vector2D, a2: Vector2D, t: Double): Vector2D = {
      val M1: Vector2D = average(List(a1, c1))//M1 - point between anchor point 1 and control point 1
      val M2: Vector2D = average(List(c1, c2))//M2 - point between control point 1 and control point 2 
      val M3: Vector2D = average(List(c2, a2))//M3 - point between control point 2 and anchor point 2
      val M4: Vector2D = average(List(M1, M2))//M4 - point between M1 & M2
      val M5: Vector2D = average(List(M2, M3))//M5 - point between M2 & M3
      average(List(M4, M5))//M6 - point between M4 & M5, which should intersect with curve
   }
   */

   /**
    * shifts the positions of Vector2Ds in a list by an offset value,
    * called from Shape2D subdivide in split operations
    * should be rewritten as generic
    * @param list of Vector2D
    * @param offset the amount to offset the index positions in the list
    * @return the new list
    */
   def shiftVector2DList(list: List[Vector2D], offset: Int): List[Vector2D] = {
	   val shifted: Array[Vector2D] = new Array[Vector2D](list.length)
	   for (i <- 0 until list.length) {
	  	   shifted(i) = list(Formulas.circularIndex(i+offset, list.length)).clone
	   }
	   shifted.toList
   }
   /**
    * Switches direction of sequence of points - the point order.  If going
    * clockwise then switched to counter-clockwise and vice versa
    * @param list of points (Vector2D)val
    * @return reversed list
    */
   def switchPointOrder(points: List[Vector2D]): List[Vector2D] = {
	   val switched: Array[Vector2D] = new Array[Vector2D](points.length)
	   //switch order of all but the first point
	   //get all points but the first
	   var allButFirst: Array[Vector2D] = new Array[Vector2D](points.length-1)
	   for (i <- 0 until allButFirst.length) { 
	  	   allButFirst(i) = points(i+1)
	   }
	   allButFirst = allButFirst.reverse//reverse the array
	   switched(0) = points(0).clone//keep the first point from original list
	   for (i <- 0 until allButFirst.length) { 
	  	   switched(i + 1) = allButFirst(i)//fill in from the reversed list
	   }
	   switched.toList	   
   }
   
   def slopeDifferenceBetweenTwoLinesAsAngle(A1: Vector2D, A2: Vector2D, B1: Vector2D, B2: Vector2D): Double = {
     val A_slope = slope(A1, A2)
     val B_slope = slope(B1, B2)
     val Diff_slope = B_slope-A_slope
     val Diff_radians = slopeToRadians(Diff_slope)
     radiansToDegrees(Diff_radians)
   }
   
   def slope(A1: Vector2D, A2: Vector2D): Double = {
     val rise = A2.y-A1.y
     val run = A2.x-A1.x
     rise/run
   }
   
   def slopeToRadians (slope: Double): Double = {
     math.atan(slope)
   }

   /**
    * tests for equality between contents of two Int arrays
    * @param a
    * @param b
    * @return
    */
   def arraysAreEqual(a: Array[Int], b: Array[Int]): Boolean = {
      var e: Boolean = true
      if (a.length == b.length) {
         for (i <- 0 until a.length) {
            if (a(i) != b(i)) {
               e = false
            }
         }
      } else {
         e = false
      }
      e
   }

}

