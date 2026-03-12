/**
Polygon2D represents a 2D polygon composed of any number of sides.  The Polygon2D is represented as a set of Vector2D coordinates.
When creating Polygon2D objects, it is typically best to do so with the center at 0,0.  This makes things like rotating the polygon
around its center much easier.
*/

package org.loom.geometry

import scala.collection.mutable.ArrayBuffer
import org.loom.utility.{Formulas, Randomise, Transform2D}

class Polygon2D(val points: List[Vector2D], val polyType: Int) {
  
   var visible: Boolean = true

   var sidesTotal: Int = 0
   if(polyType == PolygonType.LINE_POLYGON) {
       sidesTotal = points.length
       //println(">>Polygon2D,INIT LINE POLYGON, sidesTotal: " + sidesTotal + "  points.length: " + points.length)
       //for(p <- points) { println("point: x:" + p.x + "  y:" + p.y) }
   } else if (polyType == PolygonType.SPLINE_POLYGON) {
       sidesTotal = points.length/4//because there are 4 points in any spline side
       //println("!!Polygon2D, INIT SPLINE POLYGON, sidesTotal: " + sidesTotal + "  points.length: " + points.length)
   }
   override def toString(): String = "Polygon2D sidesTotal: " + sidesTotal
   def print(): Unit = {
     println("\n" + this.toString())
     println()
     for (point <- points) println(point)
    }

   def transform(t: Transform2D): Unit = {
       translate(t.translation)
       scale(t.scale)
       rotate(t.rotation.x)
   }

         /**
          * NOT WORKING
   Transform the Vector2D by an x and y scaling factor (Vector2D) around an offset
   a designated center (the offset point)
   @param transform the scale, translation and rotation in a Transform2D
   @offset the point to scale around
   */

   def transformAroundOffset (transform: Transform2D, offset: Vector2D): Unit = {

      for (point <- points) {
          point.transformAroundOffset(transform, offset)
       }
   }

   /**
   Translate the Polygon2D by an x and y vector(Vector2D).  Goes through all the points in the polygon and translates them.
   @param trans the translation vector expressed as a Vector2D
   */
   def translate(trans: Vector2D): Unit = {
     //println("Polygon2D, translate: " + trans)
      for (point <- points)point.translate(trans)
   }
   /**
   Scale the Polygon2D by an x and y scaling factor (Vector2D).  Goes through all the points in the polygon and scales them.
   @param scale the scaling factor expressed as a Vector2D
   */
   def scale(scale: Vector2D): Unit = {
    //val alreadyTransformed: ListBuffer[Vector2D] = new ListBuffer[Vector2D]()
       for (point <- points)point.scale(scale)
   }
   /**
   Rotate the Vector2D by an angle.
   @param angle the amount to rotate
   */
   def rotate(angle: Double): Unit = {
      for (point <- points)point.rotate(angle)
   }
   /**
   Clone the Polygon2D.
   @return independent copy of this Polygon2D
   */
   override def clone(): Polygon2D = {
     //println("Polygon2D, clone, sidesTotal: " + sidesTotal + "  points.length: " + points.length)
     //println("Polygon2D, clone pt 4: " + points(4))
     //val tGrid: TextGrid = new TextGrid(40,40,new Vector2D(1,1))
     //tGrid.show(points)
      val copy: Array[Vector2D] = new Array[Vector2D](points.length)//CHANGED FROM sidesTotal
      var i: Int = 0
      //println("Polygon2D copy index: " + i + "     points.length: " + points.length)
      for (point <- points) { copy(i) = point.clone(); i += 1 }
      val p = new Polygon2D(copy.toList, polyType)
      p.visible = this.visible
      p
   }
   
   def randomiseMiddle(mid: Vector2D, vert: Vector2D, div: Double): Vector2D = {
     val dist: Double = Formulas.hypotenuse(mid, vert)
     val dist_fraction: Double = dist/div
     val ranX: Double = (Randomise.range(0, dist_fraction*2)-dist_fraction) + mid.x
     val ranY: Double = (Randomise.range(0, dist_fraction*2)-dist_fraction) + mid.y
     new Vector2D(ranX, ranY)
   }
   /**
    * Return a subdivision surface version of this polygon
    * @param subdivisionType - QUAD or TRIANGLE
    */
   def subdivide(subP: SubdivisionParams):List[Polygon2D] = {
     val subdivide: Subdivision = new Subdivision(points, sidesTotal)//create a new Subdivision
     subdivide.subdivide(subP, polyType)
   }
   /**
   Turn a 2D polygon into a separate 3D polygon
   with depth values set to default zero value
   */
   def to3D(): Polygon3D = {
      val copy: Array[Vector3D] = new Array[Vector3D](points.length)//CHANGED FROM sidesTotal
      var i: Int = 0
      for (point <- points) { copy(i) = (Vector2D.to3D(point, 0)).clone(); i += 1 }
      new Polygon3D(copy.toList, polyType)
   }

   /**
    * Get the anchor points in the spline poly
    */

   def getSplinePolyAnchorPoints(): Array[Vector2D] = {
      val anchors: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]
      for (i <- 0 until sidesTotal) {
        for (j <- 0 until 4) {
          val index: Int = (i*j)+j
           if (j == 0 || j == 3) {
             anchors += points(index)
           }
        }
      }
      anchors.toArray
    }

    /**
    * Get the control points in the spline poly
    */

   def getSplinePolyControlPoints(): Array[Vector2D] = {
      val controlPoints: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]
      for (i <- 0 until sidesTotal) {
        for (j <- 0 until 4) {
          val index: Int = (i*j)+j
           if (j == 1 || j == 2) {
             controlPoints += points(index)
           }
        }
      }
      controlPoints.toArray
    }

    def getCentreAnchorsAndControlPoints(): Array[Vector2D] = {
      val centresAndCPs: Array[Vector2D] = new Array(4)
      if (sidesTotal == 3) {//TRI - side 0 and 1
        centresAndCPs(0) = points(2)//ACP
        centresAndCPs(1) = points(3)//Centre A
        centresAndCPs(0) = points(4)//Centre B
        centresAndCPs(0) = points(5)//BCP

      } else if (sidesTotal == 4) {//QUAD - side 1 and 2
        centresAndCPs(0) = points(6)
        centresAndCPs(1) = points(7)
        centresAndCPs(0) = points(8)
        centresAndCPs(0) = points(9)
      }
      centresAndCPs
    }

    def getActualCentreFromAnchors(): Vector2D = {
      val anchors: Array[Vector2D] = getSplinePolyAnchorPoints()
      Formulas.average(anchors.toList)
    }

    def getActualCentreFromAnchorsAndControlPoints(): Vector2D = {
      Formulas.average(points)
    }

}
