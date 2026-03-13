/**
Shape2D represents a 2D shape composed of multiple Polygon2Ds.
Each Polygon2D hold its own set of Vector2Ds.
*/

package org.loom.geometry
import org.loom.utility._
import scala.collection.mutable.ListBuffer

class Shape2D(val polys: List[Polygon2D], val subdivisionParamsSet: SubdivisionParamsSet) extends AbstractShape {

   val polysTotal: Int = polys.length
   override def toString(): String = "Shape2D polysTotal: " + polysTotal + "   polys(0): " + polys(0)
   def print(): Unit = { println("\n" + this.toString()); for (poly <- polys) println(poly) }

   /**
    * Get number of Polygon2Ds in the shape
    */
   def getSize(): Int = {
     polysTotal
   }
   /**
    * Turn a 2D shape into a separate 3D shape
    */
   def to3D(): Shape3D = {
     val depthPolys: Array[Polygon3D] = new Array[Polygon3D](polysTotal)
     val depthPoints: ListBuffer[Vector3D] = new ListBuffer[Vector3D]()
     var i: Int = 0
     for (poly <- polys) {
       depthPolys(i) = (new Polygon3D( (poly.to3D()).points,poly.polyType))
         for(point <- depthPolys(i).points) {
           depthPoints += (point)
         }
       i += 1
     }
     val polyList = depthPolys.toList
     val pointList = depthPoints.toList
     new Shape3D(pointList, polyList)
   }
   /**
   Translate the Shape2D by an x and y (Vector2D).  Goes through all the polygons in the shape and translates them.
   @param trans the translation vector expressed as a Vector2D
   */
   def translate(trans: Vector2D): Unit = {
     //println("Shape2D, translate: " + trans)
      for (poly <- polys) {
        if (poly != null) {
          poly.translate(trans)
        } else {
          println ("poly is NULL")
        }
      }
   }

   /**
   Scale the Shape2D by an x and y scaling factor (Vector2D).  Goes through all the polygons in the shape and scales them.
   @param scale the scaling factor expressed as a Vector2D
   */
   def scale(scale: Vector2D): Unit = {
      for (poly <- polys)poly.scale(scale)
   }

   /**
   Rotate the Shape2D by an angle.  Goes through all the polygons in the shape and rotates them.
   @param rotation the rotation angle
   */
   def rotate(angle: Double): Unit = {
      //println("Shape2D, trying to rotate, angle: " + angle + "   polys: " + polys)//SOMEHOW POLYS ARE NULL AFTER TRI SUBDIVISION????????????????????????????
      for (poly <- polys) poly.rotate(angle)
   }
   /**
   This creates a deep clone of the Shape2D.
   @return Shape2D (independent copy)
   */
   override def clone(): Shape2D = {
      val copy: Array[Polygon2D] = new Array[Polygon2D](polysTotal)
      //println("polysTotal: " + polysTotal)
      var i: Int = 0
      //for (poly <- polys) { println ("Shape2D, clone i: " + i); i += 1 }
      for (poly <- polys) { 
        if (poly != null) {
    	    //println ("Shape2D, clone i: " + i)
    	    val c = poly.clone()
    	    copy(i) = c
    	    i += 1
        } else {
          //println ("poly is NULL")
        }
      }
      new Shape2D(copy.toList, subdivisionParamsSet)
   }
   /**
    * get the total number of polygon sides in the overall shape
    * this is actually the same as the overall number of points
    * with LINE_POLYGONs
    * @return
    */
   def getNumberOfSides(): Int = {
	   var tot: Int = 0
	   for (i <- 0 until polys.length) tot += polys(i).sidesTotal
	   tot
   }
   /*
    * alignPolys
    * Polys are built in a circular fashion when subdividing.
    * This means are not in vertical alignment - this function
    * returns quad subdivided polygons to vertical alignment
    */
   def alignPolys(): Unit = {
	   for (i <- 0 until polysTotal) {
	  	   if (i % 2 == 0) {
	  	  	  val shifted: List[Vector2D] = Formulas.shiftVector2DList(polys(i).points, -1)
	  	  	  for (j <- 0 until shifted.length) { polys(i).points(j).x = shifted(j).x; polys(i).points(j).y = shifted(j).y }
	  	   } 
	   }
   }
   def alignQuadSubdivisionShape(shape: Shape2D): Shape2D = {
	   println("aligning")
	   val adjustedPolys: Array[Polygon2D] = new Array[Polygon2D](shape.polysTotal)
	   var p: Polygon2D = new Polygon2D(List(new Vector2D(0,0), new Vector2D(0,0)), PolygonType.LINE_POLYGON)//dummy
	   for (i <- 0 until shape.polysTotal) {
	  	   if (i % 2 == 0) {
	  	  	  val shifted: List[Vector2D] = Formulas.shiftVector2DList(polys(i).points, -1)
	  	  	  p = new Polygon2D(shifted, PolygonType.LINE_POLYGON)
	  	   } else {
	  	  	  p = polys(i).clone
	  	   }
	  	   adjustedPolys(i) = p.clone
	   }
	   new Shape2D(adjustedPolys.toList, subdivisionParamsSet)
   }
   /**
    * Calls subdivide a set number of times and returns the final set of polygons (as a new shape)
    * @param subs list of SubdivisionParams
    * @polyType line or bezier curve
    * @shape input Shape2D
    */
   def recursiveSubdivide(subs: List[SubdivisionParams]): Shape2D  = {
     // Separate bypass polygons (open curves, discrete points) from closed polygons.
     val bypassPolys = polys.filter(p => p.polyType == PolygonType.OPEN_SPLINE_POLYGON || p.polyType == PolygonType.POINT_POLYGON)
     val closedPolys = polys.filter(p => p.polyType != PolygonType.OPEN_SPLINE_POLYGON && p.polyType != PolygonType.POINT_POLYGON)

     println(s"[Loom] Subdivision: ${subs.length} pass(es), input: ${closedPolys.length} closed + ${bypassPolys.length} bypass polygon(s)")

     if (closedPolys.isEmpty) {
       // Nothing to subdivide — return bypass polys cloned into a fresh shape.
       return new Shape2D(bypassPolys.map(_.clone()), subdivisionParamsSet)
     }

     var oldShape: Shape2D = new Shape2D(closedPolys, subdivisionParamsSet)
     var newShape: Shape2D = null
     for (i <- 0 until subs.length) {
       val sType = Subdivision.getType(subs(i).subdivisionType)
       println(s"[Loom]   Pass ${i + 1}/${subs.length}: $sType — in: ${oldShape.polys.length}")
       newShape = oldShape.subdivide(subs(i))
       // Filter out invisible polys so they are not subdivided in the next iteration.
       // Clone remaining visible polys as input for the next level.
       val visiblePolys = newShape.polys.filter(_.visible).map(_.clone()).toList
       oldShape = new Shape2D(visiblePolys, newShape.subdivisionParamsSet)
     }

     // Recombine subdivided closed polys with unchanged bypass polys.
     val finalPolys = newShape.polys ++ bypassPolys.map(_.clone())
     println(s"[Loom] Subdivision complete — output: ${finalPolys.length} polygon(s) (${newShape.polys.length} closed + ${bypassPolys.length} bypass)")
     new Shape2D(finalPolys, subdivisionParamsSet)
   }
   /**
   This subdivides a shape either as quads or triangles
   Can only subdivide as quads if all of the polygons are quads!!!!!!!!
   @param subdivisionType
   */
   def subdivide(subP: SubdivisionParams): Shape2D = {
	   val numSides: Int = polys(0).sidesTotal
	   var newPolys: Array[Polygon2D] = null
	   if (subP.subdivisionType == Subdivision.QUAD || subP.subdivisionType == Subdivision.TRI || subP.subdivisionType == Subdivision.TRI_BORD_A || subP.subdivisionType == Subdivision.TRI_BORD_B) {
	  	   newPolys = new Array[Polygon2D](getNumberOfSides())
	  	   var polyCount: Int = 0
	  	   for (i <- 0 until polys.length) {
	  	       val sub: List[Polygon2D] = polys(i).subdivide(subP)
	  	       for(n <- 0 until polys(i).sidesTotal) { newPolys(polyCount) = sub(n); polyCount += 1 }
	       }
	   } else if (subP.subdivisionType == Subdivision.SPLIT_VERT || subP.subdivisionType == Subdivision.SPLIT_HORIZ || subP.subdivisionType == Subdivision.SPLIT_DIAG) {
	  	   newPolys = new Array[Polygon2D](polys.length * 2)
	  	   for (i <- 0 until polys.length) {
	  	       val sub: List[Polygon2D] = polys(i).subdivide(subP)
	  	       for(n <- 0 until 2) newPolys((i * 2)+n) = sub(n)
	  	   }
	   } else if (subP.subdivisionType == Subdivision.ECHO || subP.subdivisionType == Subdivision.ECHO_ABS_CENTER) {
	  	   newPolys = new Array[Polygon2D](polys.length * 2)
	  	   for (i <- 0 until polys.length) {
	  	  	   newPolys(i) = polys(i)
               newPolys(i + polys.length) = polys(i).subdivide(subP)(0)
	       }
	   } else if (subP.subdivisionType == Subdivision.QUAD_BORD) {
	  	   newPolys = new Array[Polygon2D](polys.length * numSides)
	  	   for (i <- 0 until polys.length) {
	  	       val sub: List[Polygon2D] = polys(i).subdivide(subP)
	  	       for(n <- 0 until polys(i).sidesTotal) newPolys((i * polys(i).sidesTotal)+n) = sub(n)
	       }
	   } else if (subP.subdivisionType == Subdivision.QUAD_BORD_ECHO || subP.subdivisionType == Subdivision.TRI_BORD_A_ECHO || subP.subdivisionType == Subdivision.TRI_BORD_B_ECHO || subP.subdivisionType == Subdivision.TRI_STAR) {
	  	   newPolys = new Array[Polygon2D]((getNumberOfSides()) + polys.length)
	  	   var polyCount: Int = 0
	  	   for (i <- 0 until polys.length) {
	  	       val sub: List[Polygon2D] = polys(i).subdivide(subP)
	  	       for (n <- 0 until sub.length) { newPolys(polyCount) = sub(n); polyCount += 1 }
	       }
	   } else if (subP.subdivisionType == Subdivision.QUAD_BORD_DOUBLE) {
	  	   newPolys = new Array[Polygon2D](polys.length * (numSides*2))
	  	   for (i <- 0 until polys.length) {
	  	       val sub: List[Polygon2D] = polys(i).subdivide(subP)
	  	       for(n <- 0 until (polys(i).sidesTotal*2)) newPolys(((i * polys(i).sidesTotal)*2)+n) = sub(n)
	       }
	   } else if (subP.subdivisionType == Subdivision.QUAD_BORD_DOUBLE_ECHO || subP.subdivisionType == Subdivision.TRI_STAR_FILL) {
	  	   val totPolys: Int = ((getNumberOfSides()*2))+polys.length
	  	   newPolys = new Array[Polygon2D](totPolys)
	  	   var polyCount: Int = 0
	  	   for (i <- 0 until polys.length) {
	  	       val sub: List[Polygon2D] = polys(i).subdivide(subP)
	  	       for(n <- 0 until sub.length) { newPolys(polyCount) = sub(n); polyCount += 1 }
	       }
	   } else if (subP.subdivisionType == Subdivision.TRI_BORD_C) {
	  	   newPolys = new Array[Polygon2D](polys.length * (numSides*3))
	  	   for (i <- 0 until polys.length) {
	  	       val sub: List[Polygon2D] = polys(i).subdivide(subP)
	  	       for(n <- 0 until (polys(i).sidesTotal*3)) newPolys(((i * polys(i).sidesTotal)*3)+n) = sub(n)
	       }
	   } else if (subP.subdivisionType == Subdivision.TRI_BORD_C_ECHO) {
	  	   val totPolys: Int = (getNumberOfSides()*3)+polys.length
	  	   newPolys = new Array[Polygon2D](totPolys)
	  	   var polyCount: Int = 0
	  	   for (i <- 0 until polys.length) {
	  	       val sub: List[Polygon2D] = polys(i).subdivide(subP)
	  	       for(n <- 0 until (polys(i).sidesTotal*3)+1) { newPolys(polyCount) = sub(n); polyCount += 1 }
	       }
	   }
       new Shape2D(newPolys.toList, subdivisionParamsSet)
       
   }

}
