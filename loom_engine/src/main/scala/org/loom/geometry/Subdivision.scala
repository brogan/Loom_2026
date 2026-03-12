package org.loom.geometry

import scala.annotation.unused

import org.loom.utility._
import org.loom.subdivide._
import org.loom.transform.PolysTransform

class Subdivision(val points: List[Vector2D], val sidesTotal: Int) {
	
	def randomiseMiddle(mid: Vector2D, vert: Vector2D, div: Double): Vector2D = {
	   val dist: Double = Formulas.hypotenuse(mid, vert)
	   val third: Double = dist/div
	   val ranX: Double = (Randomise.range(0, third*2)-third) + mid.x
	   val ranY: Double = (Randomise.range(0, third*2)-third) + mid.y
	   new Vector2D(ranX, ranY)
   }

   /**
    * Return a subdivision surface version of this polygon
    * @param subdivisionType - QUAD or TRIANGLE
    * @param ranMiddle - randomise middles (only works with Quad & Triangle subdivision)
    * @param ranDiv - randomise divisor (higher values produce less randomisation range)
    * @param lineRatios - when intermediate points on lines need to be calculated (say for QUAD subdivision), first ratio is distance along first line (.4 works well) and second ratio is distance along second line (.6 for instance).  More extreme values create other effects (try .75 for both).
    * @param continuous - links mid-points on adjacent quads (at this stage) if true
    * @param polyType - LINE_POLYGON or SPLINE_POLYGON
    */
   def subdivide(subP: SubdivisionParams, polyType: Int):List[Polygon2D] = {
	   /**
	   val p: Array[Vector2D] = new Array[Vector2D](points.length)
	   for(i <- 0 until points.length) {
	     println("Subdivision: " + i + " x: " + p(i).x)
	     println("Subdivision: " + i + " y: " + p(i).y)
	   }
	  */
	   var newPolys: Array[Polygon2D] = null
	   
	   if (polyType == PolygonType.LINE_POLYGON) {
	     
	     var middle: Vector2D = Subdivision.getCenter(points)//calculated from all corner points
	     //NOTE RANDOMISE MIDDLE
	     //uses first point to work out outer limit of randomisation (inner limit is the center point)
	     if (subP.ranMiddle) {
	         middle = randomiseMiddle(middle, points(0), subP.ranDiv)
	     }
	     
	  	   subP.subdivisionType match {
	  	  	   case Subdivision.QUAD => newPolys = Subdivision.lineQuad(this, middle, subP, polyType)
	  	  	   case Subdivision.QUAD_BORD => newPolys = Subdivision.lineQuadBord(this, middle, subP, polyType)
	  	  	   case Subdivision.QUAD_BORD_ECHO => newPolys = Subdivision.lineQuadBordEcho(this, middle, subP, polyType)
	  	  	   case Subdivision.QUAD_BORD_DOUBLE => newPolys = Subdivision.lineQuadBordDouble(this, middle, subP, polyType)
	  	  	   case Subdivision.QUAD_BORD_DOUBLE_ECHO => newPolys = Subdivision.lineQuadBordDoubleEcho(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI => newPolys = Subdivision.lineTri(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI_BORD_A => newPolys = Subdivision.lineTriBordA(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI_BORD_A_ECHO => newPolys = Subdivision.lineTriBordAEcho(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI_BORD_B => newPolys = Subdivision.lineTriBordB(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI_BORD_B_ECHO => newPolys = Subdivision.lineTriBordBEcho(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI_STAR => newPolys = Subdivision.lineTriStar(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI_STAR_FILL => newPolys = Subdivision.lineTriStarFill(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI_BORD_C => newPolys = Subdivision.lineTriBordC(this, middle, subP, polyType)
	  	  	   case Subdivision.TRI_BORD_C_ECHO => newPolys = Subdivision.lineTriBordCEcho(this, middle, subP, polyType)
	  	  	   case Subdivision.SPLIT_VERT => newPolys = Subdivision.lineSplitVert(this, middle, subP, polyType)
	  	  	   case Subdivision.SPLIT_HORIZ => newPolys = Subdivision.lineSplitHoriz(this, middle, subP, polyType)
	  	  	   case Subdivision.SPLIT_DIAG => newPolys = Subdivision.lineSplitDiag(this, middle, subP, polyType)
	  	  	   case Subdivision.ECHO => newPolys = Subdivision.lineEcho(this, middle, subP, polyType)
	  	  	   case Subdivision.ECHO_ABS_CENTER => newPolys = Subdivision.lineEchoAbsCenter(this, middle, subP, polyType)
	  	   }

	  	   // Apply whole polygon transforms for line subdivisions
	  	   if (newPolys != null && subP.polysTransform && subP.polysTranformWhole) {
	  	       PolysTransform.transform(newPolys, this, subP)
	  	   }

	   } else if (polyType == PolygonType.SPLINE_POLYGON) {
	     
	     var middle: Vector2D = Subdivision.getCenterSpline(points)
	     //NOTE RANDOMISE MIDDLE
	     //uses first point to work out outer limit of randomisation (inner limit is the center point)
	     if (subP.ranMiddle) {
	         middle = randomiseMiddle(middle, points(0), subP.ranDiv)
	     }
	  	   subP.subdivisionType match {

	  	       case Subdivision.QUAD => newPolys = (new SplineQuad(this, middle, subP, polyType).getPolys())
	  	       //case Subdivision.QUAD => newPolys = Subdivision.splineQuad(this, middle, subP, polyType)

	  	  	   case Subdivision.QUAD_BORD => newPolys = (new SplineQuadBord(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.QUAD_BORD_ECHO => newPolys = (new SplineQuadBordEcho(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.QUAD_BORD_DOUBLE => newPolys = (new SplineQuadBordDouble(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.QUAD_BORD_DOUBLE_ECHO => newPolys = (new SplineQuadBordDoubleEcho(this, middle, subP, polyType)).getPolys()

	  	  	   case Subdivision.TRI => newPolys = (new SplineTri(this, middle, subP, polyType).getPolys())
	  	  	   //case Subdivision.TRI => newPolys = Subdivision.splineTri(this, middle, subP, polyType)

	  	  	   case Subdivision.TRI_BORD_A => newPolys = (new SplineTriBordA(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.TRI_BORD_A_ECHO => newPolys = (new SplineTriBordAEcho(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.TRI_BORD_B => newPolys = (new SplineTriBordB(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.TRI_BORD_B_ECHO => newPolys = (new SplineTriBordBEcho(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.TRI_STAR => newPolys = (new SplineTriStar(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.TRI_STAR_FILL => newPolys = (new SplineTriStarFill(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.TRI_BORD_C => newPolys = (new SplineTriBordC(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.TRI_BORD_C_ECHO => newPolys = (new SplineTriBordCEcho(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.SPLIT_VERT => newPolys = (new SplineSplitVert(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.SPLIT_HORIZ => newPolys = (new SplineSplitHoriz(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.SPLIT_DIAG => newPolys = (new SplineSplitDiag(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.ECHO => newPolys = (new SplineEcho(this, middle, subP, polyType)).getPolys()
	  	  	   case Subdivision.ECHO_ABS_CENTER => newPolys = (new SplineEcho(this, middle, subP, polyType, true)).getPolys()
	  	   }
	   } else {
	  	   println("***Subdivision, subdivide error: not an approptiate polygon type: " + polyType)
	   }
	   //val tGrid: TextGrid = new TextGrid(40,40, new Vector2D(1,1))
	   //tGrid.show(newPolys(0).points)
	   newPolys.toList
   }
  
   
}


object Subdivision {
	
	val QUAD = 0//calculates center of polygon and then builds up quads from existing points, interpellated mid-points and the center point
	val QUAD_BORD = 1
	val QUAD_BORD_ECHO = 2
	val QUAD_BORD_DOUBLE = 3
	val QUAD_BORD_DOUBLE_ECHO = 4
	val TRI = 5//calculates center of polygon and then builds up triangles from existing points to center point in sequence 
	val TRI_BORD_A = 6
	val TRI_BORD_A_ECHO = 7
	val TRI_BORD_B = 8
	val TRI_BORD_B_ECHO = 18
  val TRI_STAR = 9
  val TRI_STAR_FILL = 19
	val TRI_BORD_C = 10
	val TRI_BORD_C_ECHO = 11
	val SPLIT_VERT = 12
	val SPLIT_HORIZ = 13
	val SPLIT_DIAG = 14
	val ECHO = 16//makes an identical polygon in relation to existing polygon (within or around)
	val ECHO_ABS_CENTER = 17////makes an identical polygon in relation to existing polygon (within or around) but orients center to overall original polygon

	
	
	
	def getType(num: Int): String = {
		var s: String = "not a subdivision type"
		num match {
			case 0 => s = "QUAD"
		    case 1 => s = "QUAD_BORD"
		    case 2 => s = "QUAD_BORD_ECHO"
		    case 3 => s = "QUAD_BORD_DOUBLE"
		    case 4 => s = "QUAD_BORD_DOUBLE_ECHO"
		    case 5 => s = "TRI"
		    case 6 => s = "TRI_BORD_A"
		    case 7 => s = "TRI_BORD_A_ECHO"
		    case 8 => s = "TRI_BORD_B"
		    case 9 => s = "TRI_STAR"
		    case 10 => s = "TRI_BORD_C"
		    case 11 => s = "TRI_BORD_C_ECHO"
		    case 12 => s = "SPLIT_VERT"
		    case 13 => s = "SPLIT_HORIZ"
		    case 14 => s = "SPLIT_DIAG"
		    case 16 => s = "ECHO"
		    case 17 => s = "ECHO_ABS_CENTER"
		    case 18 => s = "TRI_BORD_B_ECHO"
		    case 19 => s = "TRI_STAR_FILL"
		}
		s
	}
	
	//visibility rules (which polys to make visible after subdivision)
	val ALL = 0
	val QUADS = 1
	val TRIS = 2
	val ALL_BUT_LAST = 3
	val ALTERNATE_ODD = 4
	val ALTERNATE_EVEN = 5
	val FIRST_HALF = 6
	val SECOND_HALF = 7
	val EVERY_THIRD = 8
	val EVERY_FOURTH = 9
	val EVERY_FIFTH = 10
	val RANDOM_1_2 = 11
	val RANDOM_1_3 = 12
	val RANDOM_1_5 = 13
	val RANDOM_1_7 = 14
	val RANDOM_1_10 = 15
	
	def getVisibilityRule(num: Int): String = {
		var s: String = "not a visibility rule"
		num match {
			case 0 => s = "ALL"
		    case 1 => s = "QUADS"
		    case 2 => s = "TRIS"
		    case 3 => s = "ALL_BUT_LAST"
		    case 4 => s = "ALTERNATE_ODD"
		    case 5 => s = "ALTERNATE_EVEN"
		    case 6 => s = "FIRST_HALF"
		    case 7 => s = "SECOND_HALF"
		    case 8 => s = "EVERY_THIRD"
		    case 9 => s = "EVERY_FOURTH"
		    case 10 => s = "EVERY_FIFTH"
		    case 11 => s = "RANDOM_1_2"
		    case 12 => s = "RANDOM_1_3"
		    case 13 => s = "RANDOM_1_5"
		    case 14 => s = "RANDOM_1_7"
		    case 15 => s = "RANDOM_1_10"
		}
		s
	}
	
	 /**
    * Gets the average of a set of points (the center with all regular polygon shapes)
    * @param pts the list of Vector2Ds to average
    * @return Vector2D
    */
   def getCenter(pts: List[Vector2D]):Vector2D = Formulas.average(pts)
   
   /**
    * This assumes that Splines should calculate center from anchor points, ignoring control points
    * needs more thought (2022)
    */
   def getCenterSpline(pts: List[Vector2D]):Vector2D = {
     val numSides: Int = pts.length/4
     val anchorPoints: Array[Vector2D] = new Array[Vector2D](numSides)
     for(i <- 0 until pts.length) {
       val c: Int = i/4
        if (i%4 == 0) {
          anchorPoints(c)= pts(i)
        }
     }
     Formulas.average(anchorPoints.toList)
   }
   
   
   /**
    * Gets the mid-points between anchor points on a polygon
    * @param pts the list of anchor Vector2Ds
    * @ratio 
    * @return list of mid-point Vector2Ds
    */
   def getPolyMidPoints(pts: List[Vector2D], ratio: Vector2D, continuous: Boolean): List[Vector2D] = {
	   val p: Array[Vector2D] = new Array[Vector2D](pts.length)
	   for(i <- 0 until pts.length) {
	  	   val destIndex: Int = Formulas.circularIndex(i+1, pts.length)
	  	   if (continuous) {//this connects the mid-points on adjacent polygons
	  	       if (i % 2 == 0) {
                  p(i) = Formulas.lerp(pts(i), pts(destIndex), ratio.x)
	           } else {
                  p(i) = Formulas.lerp(pts(i), pts(destIndex), ratio.y)
	           }    
	  	    } else {
               p(i) = Formulas.lerp(pts(i), pts(destIndex), ratio.x)

	  	    } 
	   }
	   p.toList
   }
   
   /**
    * Scales existing poly according to Vector2D x, y ratio
    * and then returns list of new points
    * @param pts the list of anchor Vector2Ds
    * @ratio the scaling ratio - (.5 is half)
    * @return list of scaled Vector2Ds
    */
   def getScaledPolyPoints(pts: List[Vector2D], insetTransform:  Transform2D): List[Vector2D] = {
	   val middle: Vector2D = getCenter(pts)
	   val p: Array[Vector2D] = new Array[Vector2D](pts.length)
	   for(i <- 0 until pts.length) {
	  	   p(i) = pts(i).clone
	  	   p(i).transformAroundOffset(insetTransform, middle)
	   }
	   p.toList
   }

   def setVisible(poly: Polygon2D, index: Int, newPolyTotal: Int, visibilityRule: Int): Unit = {
	   visibilityRule match {
	  	   case Subdivision.ALL => poly.visible = true
	  	   case Subdivision.QUADS => if (poly.sidesTotal == 4) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.TRIS => if (poly.sidesTotal == 3) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.ALL_BUT_LAST => if (index < newPolyTotal-1) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.ALTERNATE_ODD => if (index % 2 != 0) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.ALTERNATE_EVEN => if (index % 2 == 0) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.FIRST_HALF => if (index < newPolyTotal/2) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.SECOND_HALF => if (index > newPolyTotal/2) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.EVERY_THIRD => if (index % 3 == 0) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.EVERY_FOURTH => if (index % 4 == 0) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.EVERY_FIFTH => if (index % 5 == 0) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.RANDOM_1_2 => if (Randomise.range(0, 2) == 1) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.RANDOM_1_3 => if (Randomise.range(0, 3) == 1) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.RANDOM_1_5 => if (Randomise.range(0, 5) == 1) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.RANDOM_1_7 => if (Randomise.range(0, 7) == 1) { poly.visible = true } else { poly.visible = false }
	  	   case Subdivision.RANDOM_1_10 => if (Randomise.range(0, 10) == 1) { poly.visible = true } else { poly.visible = false }
	   }
   }




//TEST

   def testQuad(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {

      val polys: Array[Polygon2D] = new Array[Polygon2D](4)

    	val polyA: Polygon2D = new Polygon2D(subdivObj.points, _polyType)
    	val polyB: Polygon2D = polyA.clone()
    	val polyC: Polygon2D = polyB.clone()
    	val polyD: Polygon2D = polyC.clone()


    	polys(0) = polyA
    	polys(1) = polyB
    	polys(2) = polyC
    	polys(3) = polyD

    	Subdivision.setVisible(polys(0), 0, polys.length, subP.visibilityRule)
    	Subdivision.setVisible(polys(1), 1, polys.length, subP.visibilityRule)
    	Subdivision.setVisible(polys(2), 2, polys.length, subP.visibilityRule)
    	Subdivision.setVisible(polys(3), 3, polys.length, subP.visibilityRule)

      polys


   }

	
	
	//(middle: Vector2D, lineRatios: Vector2D, insetRatios: Vector2D, continuous: Boolean, polyType: Int)
	
	/**
	 * QUAD subdivision for straight lines
	 */
	def lineQuad(subdivObj: Subdivision, middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal)//CREATE EMPTY ARRAY OF NEW POLYGONS - ONE FOR EACH SIDE IN THE CURRENT POLYGON
	  	val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
	  	for (i <- 0 until newPolys.length) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = midPoints(i).clone
	  	    val pC: Vector2D = middle.clone
	  	    val pD: Vector2D = midPoints(Formulas.circularIndex((i + (subdivObj.points.length-1)), subdivObj.points.length)).clone
	  	    		       
	  	    newPolys(i) = new Polygon2D(List(pA, pB, pC, pD), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys
	}


	
	/**
	 * QUAD_BORD subdivision for straight lines
	 * Subdivide into a set of four sided border polygons equal to the total number of original sides
	 */
	def lineQuadBord(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal)
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		for (i <- 0 until newPolys.length) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC: Vector2D = scaledPolyPoints(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pD: Vector2D = scaledPolyPoints(i).clone
	  	    		       
	  	    newPolys(i) = new Polygon2D(List(pA, pB, pC, pD), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys
	}
	
	
	/**
	 * QUAD_BORD_ECHO subdivision for straight lines
	 * Same as Quad_Bord but also includes echoed centre polygon
	 */
	def lineQuadBordEcho(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D]((subdivObj.sidesTotal)+1)
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		for (i <- 0 until (newPolys.length)-1) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC: Vector2D = scaledPolyPoints(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pD: Vector2D = scaledPolyPoints(i).clone
	  	    		       
	  	    newPolys(i) = new Polygon2D(List(pA, pB, pC, pD), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys(newPolys.length-1) = new Polygon2D(scaledPolyPoints, PolygonType.LINE_POLYGON)
		setVisible(newPolys(newPolys.length-1), newPolys.length-1, newPolys.length, subP.visibilityRule)
		newPolys
	}
	
	
	/**
	 * QUAD_BORD_DOUBLE subdivision for straight lines
	 * Subdivide into a set four sided polygons equal to double the total number of original sides
	 */
	def lineQuadBordDouble(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal*2)
		val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		val insetMidPoints: List[Vector2D] = getPolyMidPoints(scaledPolyPoints, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		for (i <- 0 until subdivObj.sidesTotal) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = midPoints(i).clone
	  	    val pC: Vector2D = insetMidPoints(i).clone
	  	    val pD: Vector2D = scaledPolyPoints(i).clone
	  	    
	  	    
	  	    val pA2: Vector2D = midPoints(i).clone
	  	    val pB2: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC2: Vector2D = scaledPolyPoints(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pD2: Vector2D = insetMidPoints(i).clone
	  	    		       
	  	    newPolys(i*2) = new Polygon2D(List(pA, pB, pC, pD), PolygonType.LINE_POLYGON)
	  	    newPolys((i*2)+1) = new Polygon2D(List(pA2, pB2, pC2, pD2), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i*2), i, newPolys.length, subP.visibilityRule)
	  	    setVisible(newPolys((i*2)+1), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys
	}
	
	
	/**
	 * QUAD_BORD_DOUBLE_ECHO subdivision for straight lines
	 * Same as Quad_Bord_Double but also includes echoed centre polygon
	 */
	def lineQuadBordDoubleEcho(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D]((subdivObj.sidesTotal*2)+1)
		val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		val insetMidPoints: List[Vector2D] = getPolyMidPoints(scaledPolyPoints, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		for (i <- 0 until subdivObj.sidesTotal) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = midPoints(i).clone
	  	    val pC: Vector2D = insetMidPoints(i).clone
	  	    val pD: Vector2D = scaledPolyPoints(i).clone
	  	    
	  	    
	  	    val pA2: Vector2D = midPoints(i).clone
	  	    val pB2: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC2: Vector2D = scaledPolyPoints(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pD2: Vector2D = insetMidPoints(i).clone
	  	    		       
	  	    newPolys(i*2) = new Polygon2D(List(pA, pB, pC, pD), PolygonType.LINE_POLYGON)
	  	    newPolys((i*2)+1) = new Polygon2D(List(pA2, pB2, pC2, pD2), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i*2), i, newPolys.length, subP.visibilityRule)
	  	    setVisible(newPolys((i*2)+1), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys(newPolys.length-1) = new Polygon2D(scaledPolyPoints, PolygonType.LINE_POLYGON)
		setVisible(newPolys(newPolys.length-1), newPolys.length-1, newPolys.length, subP.visibilityRule)
		newPolys
	}
	
	
	/**
	 * TRI subdivision for straight lines
	 * Subdivide into a set triangular polygons equal to the total number of original sides (built from centre and corners)
	 */
	def lineTri(subdivObj: Subdivision, middle: Vector2D,  subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal)
		for (i <- 0 until subdivObj.sidesTotal) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC: Vector2D = middle.clone
	  	    		       
	  	    newPolys(i) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys
	}
	
	
	
	/**
	 * TRI_BORD_A subdivision for straight lines
	 * Subdivide into a set triangular polygons equal to the total number of original sides (built from line mid-points and corners)
	 */
	def lineTriBordA(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal)
	  	val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
	  	for (i <- 0 until newPolys.length) {

	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = midPoints(i).clone
	  	    val pC: Vector2D = midPoints(Formulas.circularIndex((i + (subdivObj.points.length-1)), subdivObj.points.length)).clone
	  	    		       
	  	    newPolys(i) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys
	}
	
	
	
	/**
	 * TRI_BORD_A echo subdivision for straight lines
	 * Same as TRI_BORD_A but also includes an echo polygon alternating corners and outer midpoints
	 */
	def lineTriBordAEcho(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal + 1)
		val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)
		for (i <- 0 until newPolys.length - 1) {
			val pA: Vector2D = subdivObj.points(i).clone
			val pB: Vector2D = midPoints(i).clone
			val pC: Vector2D = midPoints(Formulas.circularIndex((i + (subdivObj.points.length-1)), subdivObj.points.length)).clone
			newPolys(i) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
			setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
		}
		val echoPoints: Array[Vector2D] = new Array[Vector2D](subdivObj.sidesTotal * 2)
		for (i <- 0 until subdivObj.sidesTotal) {
			echoPoints(i*2)     = subdivObj.points(i).clone
			echoPoints((i*2)+1) = midPoints(i).clone
		}
		newPolys(newPolys.length-1) = new Polygon2D(echoPoints.toList, PolygonType.LINE_POLYGON)
		setVisible(newPolys(newPolys.length-1), newPolys.length-1, newPolys.length, subP.visibilityRule)
		newPolys
	}


	/**
	 * TRI_BORD_B subdivision for straight lines
	 * Subdivide into a set triangular polygons equal to the total number of original sides (built from the corners of a rotated internal echo and the original corner points)
	 */
	def lineTriBordB(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal)
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		val insetMidPoints: List[Vector2D] = getPolyMidPoints(scaledPolyPoints, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		for (i <- 0 until subdivObj.sidesTotal) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = insetMidPoints(i).clone
	  	    val pC: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    		       
	  	    newPolys(i) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys
	}
	
	
	/**
	 * TRI_BORD_B echo subdivision for straight lines
	 * Same as Tri_Bord_B but also includes echoed centre polygon
	 */
	def lineTriBordBEcho(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal + 1)
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		val insetMidPoints: List[Vector2D] = getPolyMidPoints(scaledPolyPoints, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		for (i <- 0 until newPolys.length - 1) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = insetMidPoints(i).clone
	  	    val pC: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    		       
	  	    newPolys(i) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
	    }
		val echoPoints: Array[Vector2D] = new Array[Vector2D](subdivObj.sidesTotal * 2 )
		for (i <- 0 until subdivObj.sidesTotal) {
			echoPoints(i*2) = subdivObj.points(i).clone
			echoPoints((i*2)+1) = insetMidPoints(i).clone
		}
		newPolys(newPolys.length-1) = new Polygon2D(echoPoints.toList, PolygonType.LINE_POLYGON)
		setVisible(newPolys(newPolys.length-1), newPolys.length-1, newPolys.length, subP.visibilityRule)
		newPolys
	}
	
	
	/**
	 * TRI_STAR subdivision for straight lines
	 * Similar to Tri_Bord_B but builds internal triangles rather than borders.
	 */
	def lineTriStar(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal + 1)
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		val insetMidPoints: List[Vector2D] = getPolyMidPoints(scaledPolyPoints, subP.lineRatios, subP.continuous)
		for (i <- 0 until newPolys.length - 1) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = insetMidPoints(Formulas.circularIndex((i - 1), subdivObj.points.length)).clone
	  	    val pC: Vector2D = insetMidPoints(i).clone
	  	    		       
	  	    newPolys(i) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys(newPolys.length-1) = new Polygon2D(insetMidPoints, PolygonType.LINE_POLYGON)
		setVisible(newPolys(newPolys.length-1), newPolys.length-1, newPolys.length, subP.visibilityRule)
		newPolys
	}
	
	
	/**
	 * TRI_STAR_FILL subdivision for straight lines
	 * Same as Tri_Star but also includes border polygons
	 */
	def lineTriStarFill(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D]((subdivObj.sidesTotal *2) + 1)
		val points: List[Vector2D] = subdivObj.points.reverse//LIST NEEDS TO BE REVERSED - UNCERTAIN WHY???????????????
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(points, subP.insetTransform)
		val insetMidPoints: List[Vector2D] = getPolyMidPoints(scaledPolyPoints, subP.lineRatios, subP.continuous)
		for (i <- 0 until subdivObj.sidesTotal) {
	  	    //just to initialise 4 anchor points in new poly
	  	    val pA: Vector2D = points(i).clone
	  	    val pB: Vector2D = insetMidPoints(i).clone
	  	    val pC: Vector2D = insetMidPoints(Formulas.circularIndex((i - 1), points.length)).clone
	  	    
	  	    val pA2: Vector2D = points(i).clone
	  	    val pB2: Vector2D = points(Formulas.circularIndex((i + 1), points.length)).clone
	  	    val pC2: Vector2D = insetMidPoints(i).clone
	  	    		       
	  	    newPolys(i*2) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i*2), i, newPolys.length, subP.visibilityRule)
	  	    newPolys((i*2)+1) = new Polygon2D(List(pA2, pB2, pC2), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys((i*2)+1), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys(newPolys.length-1) = new Polygon2D(insetMidPoints, PolygonType.LINE_POLYGON)
		setVisible(newPolys(newPolys.length-1), newPolys.length-1, newPolys.length, subP.visibilityRule)
		newPolys
	
	}
	
	
	/**
	 * TRI_BORD_C subdivision for straight lines
	 * Similar to Tri_Star and Tri_Bord_B but calculates three triangular subdivision for each original side
	 */
	def lineTriBordC(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](subdivObj.sidesTotal * 3)
		val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		for (i <- 0 until subdivObj.sidesTotal) {
	  	    
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = midPoints(i).clone
	  	    val pC: Vector2D = scaledPolyPoints(i).clone
	  	    
	  	    val pA2: Vector2D = midPoints(i).clone
	  	    val pB2: Vector2D = scaledPolyPoints(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC2: Vector2D = scaledPolyPoints(i).clone
	  	    
	  	    val pA3: Vector2D = midPoints(i).clone
	  	    val pB3: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC3: Vector2D = scaledPolyPoints(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    		       
	  	    newPolys(i*3) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
	  	    newPolys((i*3)+1) = new Polygon2D(List(pA2, pB2, pC2), PolygonType.LINE_POLYGON)
	  	    newPolys((i*3)+2) = new Polygon2D(List(pA3, pB3, pC3), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i*3), i, newPolys.length, subP.visibilityRule)
	  	    setVisible(newPolys((i*3)+1), i, newPolys.length, subP.visibilityRule)
	  	    setVisible(newPolys((i*3)+2), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys
	}
	
	
	/**
	 * TRI_BORD_C_ECHO subdivision for straight lines
	 * Same as Tri_Bord_C but also includes echoed centre polygon
	 */
	def lineTriBordCEcho(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D]((subdivObj.sidesTotal * 3)+1)
		val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		for (i <- 0 until subdivObj.sidesTotal ) {
	  	    val pA: Vector2D = subdivObj.points(i).clone
	  	    val pB: Vector2D = midPoints(i).clone
	  	    val pC: Vector2D = scaledPolyPoints(i).clone
	  	    
	  	    val pA2: Vector2D = midPoints(i).clone
	  	    val pB2: Vector2D = scaledPolyPoints(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC2: Vector2D = scaledPolyPoints(i).clone
	  	    
	  	    val pA3: Vector2D = midPoints(i).clone
	  	    val pB3: Vector2D = subdivObj.points(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    val pC3: Vector2D = scaledPolyPoints(Formulas.circularIndex((i + 1), subdivObj.points.length)).clone
	  	    		       
	  	    newPolys(i*3) = new Polygon2D(List(pA, pB, pC), PolygonType.LINE_POLYGON)
	  	    newPolys((i*3)+1) = new Polygon2D(List(pA2, pB2, pC2), PolygonType.LINE_POLYGON)
	  	    newPolys((i*3)+2) = new Polygon2D(List(pA3, pB3, pC3), PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(i*3), i, newPolys.length, subP.visibilityRule)
	  	    setVisible(newPolys((i*3)+1), i, newPolys.length, subP.visibilityRule)
	  	    setVisible(newPolys((i*3)+2), i, newPolys.length, subP.visibilityRule)
	    }
		newPolys(newPolys.length-1) = new Polygon2D(scaledPolyPoints, PolygonType.LINE_POLYGON)
		setVisible(newPolys(newPolys.length-1), newPolys.length-1, newPolys.length, subP.visibilityRule)
		newPolys
	}
	
	
	/**
	 * SPLIT_VERT subdivision for straight lines
	 * Splits the shape into two polygons that have the same number of sides as the original shape
	 */
	def lineSplitVert(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](2)
		val numSides: Int = (subdivObj.sidesTotal/2) + 2
		val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		val pts1: Array[Vector2D] = new Array[Vector2D](numSides)
		val pts2: Array[Vector2D] = new Array[Vector2D](numSides)
		for (_ <- 0 until 2) {
			if (subdivObj.sidesTotal % 2 == 0) {//even number
				val pts2IndexOffset = subdivObj.sidesTotal/2
				pts1(0) = midPoints(0).clone
				pts2(0) = midPoints(subdivObj.sidesTotal/2).clone
				for (j <- 1 until numSides-1) {
					pts1(j) = subdivObj.points(j).clone
					pts2(j) = subdivObj.points(Formulas.circularIndex((j + pts2IndexOffset), subdivObj.points.length)).clone
				}
				pts1(numSides-1) = midPoints(subdivObj.sidesTotal/2).clone
				pts2(numSides-1) = midPoints(0).clone
				
			} else {//odd number sided polygons
				val pts2IndexOffset = (subdivObj.sidesTotal/2) + 1
				for (j <- 0 until numSides-1) {
					pts1(j) = subdivObj.points(j).clone
					pts2(j) = subdivObj.points(Formulas.circularIndex((j + pts2IndexOffset), subdivObj.points.length)).clone
				}
				pts1(numSides-1) = midPoints(subdivObj.sidesTotal/2).clone
				pts2(numSides-1) = midPoints(subdivObj.sidesTotal/2).clone
			}
	  	    		       
	  	    newPolys(0) = new Polygon2D(pts1.toList, PolygonType.LINE_POLYGON)
	  	    newPolys(1) = new Polygon2D(pts2.toList, PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(0), 0, newPolys.length, subP.visibilityRule)
	  	    setVisible(newPolys(1), 1, newPolys.length, subP.visibilityRule)

	    }
		newPolys

	}
	
	
	/**
	 * SPLIT_HORIZ subdivision for straight lines
	 * Splits a polygon horizontally.  Only implemented for squares at this stage.
	 */
	def lineSplitHoriz(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		//for (i <- 0 until subdivObj.points.length) println(s"split horiz Point  + $i"  + subdivObj.points(i))
		val ps: List[Vector2D] = Formulas.switchPointOrder(subdivObj.points)
		//for (i <- 0 until ps.length) println(s"reverse split horiz Point  + $i " + ps(i))
		val newPolys = new Array[Polygon2D](2)
		val numSides: Int = (subdivObj.sidesTotal/2) + 2
		val midPoints: List[Vector2D] = getPolyMidPoints(ps, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		//for (i <- 0 until midPoints.length) println(s"midPoints split horiz Point  + $i" + midPoints(i))
		val pts1: Array[Vector2D] = new Array[Vector2D](numSides)
		val pts2: Array[Vector2D] = new Array[Vector2D](numSides)
		if(subdivObj.sidesTotal % 2 == 0) {//even numbered polygon
			val pts2IndexOffset = subdivObj.sidesTotal/2
			val halfSide = pts2IndexOffset/2
			//println("halfSide: " + halfSide)
			//PTS1
			var ptCount:Int = 0
		    for (i <- 0 until halfSide) {
			    pts1(i) = ps(i).clone
				ptCount = i
			}
			ptCount = ptCount + 1
			if (pts2IndexOffset % 2 == 0) {//even half
				pts1(ptCount) = midPoints(ptCount-1).clone
				pts1(ptCount+1) = midPoints(ptCount+pts2IndexOffset-1).clone
			} else {
				pts1(ptCount) = ps(ptCount+1)
				pts1(ptCount+1) = midPoints(ptCount+pts2IndexOffset)	
			}
			ptCount = ptCount+2
			for (i <- ptCount until pts1.length) {
				//println(i + "  ptCount: " + ptCount)
				if (ps.length > numSides) {
				    pts1(ptCount) = ps(i + halfSide).clone//PROBLEMS WITH HIGHER SUBDIVISIONS!!!!!!!!!!!!!!!!!!!!!!
				} else {
					pts1(ptCount) = ps(i).clone
				}
				ptCount += 1
			}
			//for (i <- 0 until pts1.length) println(s"pts1 " + $i + "  " + pts1(i))
			//PTS2   
			ptCount = 0
			if (pts2IndexOffset % 2 == 0) {//even half
				pts2(ptCount) = midPoints(halfSide-1)
				ptCount += 1
				for (i <- ptCount until (ptCount+(pts2IndexOffset))) {
					 pts2(i) = ps(i).clone
					 ptCount = i
				}
				ptCount += 1
				pts2(ptCount) = midPoints(ptCount-1)
		    } else {
			    ptCount += 1
				pts2(ptCount) = ps(halfSide)
				ptCount += 1
				for (i <- ptCount to (halfSide + pts2IndexOffset)) {
					pts2(i) = ps(i).clone
					ptCount = i
				}
		    }
	    } else {//odd number sided polygons
			val pts2IndexOffset = (subdivObj.sidesTotal/2) + 1
			for (j <- 0 until numSides-1) {
				pts1(j) = ps(j).clone
				pts2(j) = ps(Formulas.circularIndex((j + pts2IndexOffset), ps.length)).clone
			}
			pts1(numSides-1) = midPoints(subdivObj.sidesTotal/2).clone
			pts2(numSides-1) = midPoints(subdivObj.sidesTotal/2).clone
		}
		
	  	    		       
	  	newPolys(0) = new Polygon2D(pts1.toList, PolygonType.LINE_POLYGON)
	  	newPolys(1) = new Polygon2D(pts2.toList, PolygonType.LINE_POLYGON)

	  	setVisible(newPolys(0), 0, newPolys.length, subP.visibilityRule)
	  	setVisible(newPolys(1), 1, newPolys.length, subP.visibilityRule)

		newPolys
	}
	
	
	/**
	 * SPLIT_DIAG subdivision for straight lines
	 * Only implemented for even sided polygons at this stage, odd sided polygons just return a Split_Vert.
	 */
	def lineSplitDiag(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](2)
		var numSides: Int = 0
		if (subdivObj.sidesTotal % 2 == 0) {
			numSides = (subdivObj.sidesTotal/2) + 1
		} else {
			numSides = (subdivObj.sidesTotal/2) + 2
		}
		val midPoints: List[Vector2D] = getPolyMidPoints(subdivObj.points, subP.lineRatios, subP.continuous)//midpoints between original anchor points with lineRatios
		val pts1: Array[Vector2D] = new Array[Vector2D](numSides)
		val pts2: Array[Vector2D] = new Array[Vector2D](numSides)
		for (_ <- 0 until 2) {
			//println(s"Subdivison, lineSplitDiag, newPolys:  + $i")
			if (subdivObj.sidesTotal % 2 == 0) {//even numbered polygo
				pts1(0) = subdivObj.points(0).clone
				pts2(0) = subdivObj.points(subdivObj.sidesTotal/2).clone
				for (j <- 1 until numSides-1) {
					pts1(j) = subdivObj.points(j).clone
					pts2(j) = subdivObj.points(Formulas.circularIndex((j + (subdivObj.sidesTotal/2)), subdivObj.points.length)).clone
				}
				pts1(numSides-1) = subdivObj.points(subdivObj.sidesTotal/2).clone
				pts2(numSides-1) = subdivObj.points(0).clone
				
			} else {//odd number sided polygons
				val pts2IndexOffset = (subdivObj.sidesTotal/2) + 1
				for (j <- 0 until numSides-1) {
					pts1(j) = subdivObj.points(j).clone
					pts2(j) = subdivObj.points(Formulas.circularIndex((j + pts2IndexOffset), subdivObj.points.length)).clone
				}
				pts1(numSides-1) = midPoints(subdivObj.sidesTotal/2).clone
				pts2(numSides-1) = midPoints(subdivObj.sidesTotal/2).clone
			}
	  	    		       
	  	    newPolys(0) = new Polygon2D(pts1.toList, PolygonType.LINE_POLYGON)
	  	    newPolys(1) = new Polygon2D(pts2.toList, PolygonType.LINE_POLYGON)
	  	    setVisible(newPolys(0), 0, newPolys.length, subP.visibilityRule)
	  	    setVisible(newPolys(1), 1, newPolys.length, subP.visibilityRule)

	    }
		newPolys
	}
	
	
	
	/**
	 * ECHO subdivision for straight lines
	 * Scales the original shape.  Returns both the original shape and the echoed shape.  Centre is calculated relative to this shape. Central image shows Quad subdivision followed by Echo subdivision.

	 */
	def lineEcho(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](1)
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		newPolys(0) = new Polygon2D(scaledPolyPoints, PolygonType.LINE_POLYGON)
		setVisible(newPolys(0), 0, newPolys.length, subP.visibilityRule)
		newPolys
	}
	
	/**
	 * ECHO subdivision for bezier curves
	 * Scales the original shape.  Returns both the original shape and the echoed shape.  Centre is calculated relative to this shape. Central image shows Quad subdivision followed by Echo subdivision.
	 */
	def splineEcho(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](1)
		val scaledPolyPoints: List[Vector2D] = getScaledPolyPoints(subdivObj.points, subP.insetTransform)
		newPolys(0) = new Polygon2D(scaledPolyPoints, PolygonType.SPLINE_POLYGON)
		setVisible(newPolys(0), 0, newPolys.length, subP.visibilityRule)
		newPolys
	}
	
	/**
	 * ECHO_ABS_CENTER subdivision for straight lines
	 * Same as above but center calculated relative to the whole image. Central image shows Quad subdivision followed by Echo_Abs_Centre subdivision.
	 */
	def lineEchoAbsCenter(subdivObj: Subdivision, @unused _middle: Vector2D, subP: SubdivisionParams, @unused _polyType: Int):Array[Polygon2D] = {
		val newPolys = new Array[Polygon2D](1)
		val pts: Array[Vector2D] = new Array[Vector2D](subdivObj.points.length)
		for (i <- 0 until pts.length) {
			pts(i) = subdivObj.points(i).clone
			pts(i) = Transform2D.scale(pts(i), subP.insetTransform.scale)
		}
		newPolys(0) = new Polygon2D(pts.toList, PolygonType.LINE_POLYGON)
		setVisible(newPolys(0), 0, newPolys.length, subP.visibilityRule)
		newPolys
	}
	
	
	
	
	
	  /**
	   if (subdivisionType==Subdivision.QUAD) {//make quad subdivisions

	  	    newPolys = new Array[Polygon2D](sidesTotal)
	  	    val midPointsX: List[Vector2D] = getPolyMidPoints(points, lineRatios.x)//midpoints between original anchor points with x lineRatios value
	  	    val midPointsY: List[Vector2D] = getPolyMidPoints(points, lineRatios.y)//midpoints between original anchor points with y lineRatios value
	  	    
	  	    for (i <- 0 until points.length) {
	  	    	println("points: " + points(i))
	  	    	println("mids: " + midPointsX(i))
	        }
	  	    
	  	    
	  	    for (i <- 0 until newPolys.length) {
	  	    	println("Subdivison, newPolys: " + i)
	  	    	//just to initialise 4 anchor points in new poly
	  	    	var pA: Vector2D = new Vector2D(0,0)
	  	    	var pB: Vector2D = new Vector2D(0,0)
	  	        var pC: Vector2D = new Vector2D(0,0)
	  	        var pD: Vector2D = new Vector2D(0,0)
	  	    	if (polyType == PolygonType.LINE_POLYGON) {
	  	    		
	  	    		if (continuous) {//this connects the mid-points on adjacent polygons
	  	    		
	                    if (i % 2 == 0) {
	                	    println("even: " + i)
	  	    		        pA = points(i).clone
	  	    	            pB = midPointsX(i).clone
	  	                    pC = middle.clone
	  	                    println("i: " + i + "   pD index: " + (points.length - (i+1)))
	  	                    pD = midPointsY(Formulas.circularIndex((i + (points.length-1)), points.length)).clone
	                    } else {
	                	    println("odd: " + i)
	                	    pA = points(i).clone
	  	    	            pB = midPointsY(i).clone
	  	                    pC = middle.clone
	  	                    println("i: " + i + "   pD index: " + (points.length - (i+1)))
	  	                    pD = midPointsX(Formulas.circularIndex((i + (points.length-1)), points.length)).clone
	                    }
	                
	  	    		} else {
	  	    			pA = points(i).clone
	  	    	        pB = midPointsX(i).clone
	  	                pC = middle.clone
	  	                println("i: " + i + "   pD index: " + (points.length - (i+1)))
	  	                pD = midPointsY(Formulas.circularIndex((i + (points.length-1)), points.length)).clone
	  	    		}

	  	    		/**
	  	    	    val pA: Vector2D = points(i).clone
	  	    	    //val pB: Vector2D = Formulas.average(List(points(i), points(Formulas.circularIndex(i+1, newPolys.length))))
	  	    	    val pB: Vector2D = Formulas.lerp(points(i), points(Formulas.circularIndex(i+1, newPolys.length)),lineRatios.x)
	  	            val pC: Vector2D = middle.clone
	  	            //val pD: Vector2D = Formulas.average(List(points(i), points(Formulas.circularIndex(i+(newPolys.length-1), newPolys.length))))
	  	            val pD: Vector2D = Formulas.lerp(points(i), points(Formulas.circularIndex(i+(newPolys.length-1), newPolys.length)),lineRatios.y)
	  	            */
	  	            
	  	            newPolys(i) = new Polygon2D(List(pA, pB, pC, pD), PolygonType.LINE_POLYGON)
	  	    		
	  	    	} else {//spline_polygon
	  	    		println("spline: " + i)
	  	    		//some values to make straight bezier lines into visual curves
	  	            //val rX = Randomise.range(0,.05)-.05//translation value
	  	            val rX = 0
	  	            //val rR = Randomise.range(0, 10)-10//rotation value
	  	            val rR = 0
	  	    		
	  	    		//calculate new anchor points on the quad
	  	    		val pA: Vector2D = points(i*4).clone
	  	    	    val pB: Vector2D = Formulas.bezierPoint(points(i*4), points(Formulas.circularIndex((i*4)+1, points.length)), points(Formulas.circularIndex((i*4)+2, points.length)), points(Formulas.circularIndex((i*4)+3, points.length)), lineRatios.x)
	  	            val pC: Vector2D = middle.clone
	  	            val pD: Vector2D = Formulas.bezierPoint(points(Formulas.circularIndex((i*4)+(points.length-4), points.length)), points(Formulas.circularIndex((i*4)+(points.length-3), points.length)), points(Formulas.circularIndex((i*4)+(points.length-2), points.length)), points((i*4)), lineRatios.y)

	  	            //calculate control points
	  	            //the ones that lie on an existing bezier curve are easy to calculate:
	  	            //simply halve the distance between the new anchor point and the relevant old control point
	  	            //Not so easy with lines that are drawn to or from the new middle (no existing bezier reference)
	  	            //so just treat as straight lines and calculate control points at .25 and .75 along lines
	  	            //they can be rotated later
	  	            
	  	            //calculate half way between anchor one and control point 1
	  	    		val pAc1: Vector2D = Formulas.average(List(pA, points((i*4)+1)))
	  	    		//calculate half way between anchor two and control point 1
	  	    		val pAc2: Vector2D = Formulas.average(List(pB, points((i*4)+1)))
	  	    		
	  	    		
	  	    		val pBc1: Vector2D = Formulas.lerp(pB, middle, .25)
	  	    		pBc1.translate(new Vector2D(-rX, 0))
	  	    		pBc1.rotate(-rR)
	  	    		val pBc2: Vector2D = Formulas.lerp(pB, middle, .75)
	  	    		pBc2.translate(new Vector2D(rX, 0))
	  	    		pBc2.rotate(rR)
	  	    		
	  	    		
	  	    		val pCc1: Vector2D = Formulas.lerp(middle, pD, .25)
	  	    		pCc1.translate(new Vector2D(rX, 0))
	  	    		pCc1.rotate(rR)
	  	    		val pCc2: Vector2D = Formulas.lerp(middle, pD, .75)
	  	    		pCc2.translate(new Vector2D(-rX, 0))
	  	    		pCc2.rotate(-rR)
	  	    		
	  	    		val pDc1: Vector2D = Formulas.average(List(pD, points(Formulas.circularIndex((i*4)+(points.length-2), points.length))))
	  	    		val pDc2: Vector2D = Formulas.average(List(pA, points(Formulas.circularIndex((i*4)+(points.length-2), points.length))))
	  	    		
	  	    		println("??????????")
	  	    		println("pA: " + pA)
	  	    		println("pAc1: " + pAc1)
	  	    		println("pAc2: " + pAc2)
	  	    		println("pB: " + pB)
	  	    		println("pBc1: " + pBc1)
	  	    		println("pBc2: " + pBc2)
	  	    		println("pC: " + pC)
	  	    		println("pCc1: " + pCc1)
	  	    		println("pCc2: " + pCc2)
	  	    		println("pD: " + pD)
	  	    		println("pDc1: " + pDc1)
	  	    		println("pDc2: " + pDc2)
	  	    		println("??????????")
	  	    		
	  	    		newPolys(i) = new Polygon2D(List(pA, pAc1, pAc2, pB, pB.clone, pBc1, pBc2, pC, pC.clone, pCc1, pCc2, pD, pD.clone, pDc1, pDc2, pA.clone), PolygonType.SPLINE_POLYGON)
	  	    		//newPolys(i) = new Polygon2D(List(pA, pAc1, pAc2, pB, pBc1, pBc2, pC, pCc1, pCc2, pD, pDc1, pDc2), PolygonType.SPLINE_POLYGON)
	  	    		println("subdivided spline polygon")
	  	    	}
	        }
	  	    
	   } else if (subdivisionType==Subdivision.TRIANGLE) {//make triangle subdivisions
	  	    
	  	    newPolys = new Array[Polygon2D](sidesTotal)
	  	    for (i <- 0 until newPolys.length) {
	  	    	if (polyType == PolygonType.LINE_POLYGON) {
	  	    		println("LINE")
	  	            newPolys(i) = new Polygon2D(List(points(i).clone, middle.clone, points(Formulas.circularIndex(i+(newPolys.length-1), newPolys.length)).clone), PolygonType.LINE_POLYGON)
	  	            //println("poly: " + i)
	  	            //newPolys(i).print()
	  	    	} else {//spline
	  	    		println("SPLINE")
	  	    		
	  	    		//some values to make straight bezier lines into visual curves
	  	            //val rX = Randomise.range(0,.05)-.05//translation value
	  	            val rX = 0
	  	            //val rR = Randomise.range(0, 10)-10//rotation value
	  	            val rR = 0
	  	            
	  	    		val pA: Vector2D = points(i*4).clone
	  	    		//println("pA index: " + i)
	  	    		val pB: Vector2D = points(Formulas.circularIndex(((i+1)*4), points.length)).clone
	  	    		//println("pB index: " + Formulas.circularIndex(((i+1)*4), points.length))
	  	    	    val pC: Vector2D = middle.clone
	  	    	    
	  	    	    val pAc1: Vector2D = points((i*4)+1).clone
	  	    	    val pAc2: Vector2D = points((i*4)+2).clone
	  	    		
	  	    		val pBc1: Vector2D = Formulas.lerp(pB, middle, .25)
	  	    		pBc1.translate(new Vector2D(-rX, 0))
	  	    		pBc1.rotate(-rR)
	  	    		val pBc2: Vector2D = Formulas.lerp(pB, middle, .75)
	  	    		pBc2.translate(new Vector2D(rX, 0))
	  	    		pBc2.rotate(rR)
	  	    		
	  	    		val pCc1: Vector2D = Formulas.lerp(middle, pA, .25)
	  	    		pCc1.translate(new Vector2D(rX, 0))
	  	    		pCc1.rotate(rR)
	  	    		val pCc2: Vector2D = Formulas.lerp(middle, pA, .75)
	  	    		pCc2.translate(new Vector2D(-rX, 0))
	  	    		pCc2.rotate(-rR)
	  	    		
	  	    		newPolys(i) = new Polygon2D(List(pA, pAc1, pAc2, pB, pB.clone, pBc1, pBc2, pC, pC.clone, pCc1, pCc2, pA.clone), PolygonType.SPLINE_POLYGON)
	  	    		
	  	    	}
	        }
	  	    
	   } else if (subdivisionType==Subdivision.BISECT_VERTICAL) {//bisect polygon vertically
	  	   newPolys = new Array[Polygon2D](2)
	  	   val numSides: Int = (sidesTotal/2) + 2
	  	   //println("numSides: " + numSides)
	  	   for (i <- 0 until newPolys.length) {
	  	  	   val pts: Array[Vector2D] = new Array[Vector2D](numSides)
	  	  	   if (i == 0) {
	  	  	  	   if (sidesTotal % 2 == 0) {
	  	  	  	  	   pts(0) = points(0).clone
	  	  	  	  	   pts(1) = Formulas.lerp(points(i), points(i+1),lineRatios.x)
	  	  	  	       //pts(1) = Formulas.average(List(points(i), points(i+1)))
	  	  	  	  	   pts(2) = Formulas.lerp(points(sidesTotal/2), points((sidesTotal/2)+1),lineRatios.y)
	  	  	  	       //pts(2) = Formulas.average(List(points(sidesTotal/2), points((sidesTotal/2)+1)))
	  	  	  	       for (n <- ((sidesTotal/2)+1) until sidesTotal) {
	  	  	      	       println("Polygon2D subdivide, n: " + n)
	  	                   pts(n - (sidesTotal - numSides)) = points(n).clone
	  	  	           }
	  	  	  	   } else {
	  	  	  	  	   pts(0) = points(points.length-1).clone
	  	  	  	  	   pts(1) = points(0).clone
	  	  	  	  	   pts(2) = Formulas.lerp(points(sidesTotal/2), points((sidesTotal/2)+1),lineRatios.x)
	  	  	  	  	   //pts(2) = Formulas.average(List(points(sidesTotal/2), points((sidesTotal/2)+1)))
	  	  	  	  	   var count: Int = 3
	  	  	  	  	   for (n <- ((sidesTotal/2)+1) until sidesTotal-1) {
	  	  	      	       println("Polygon2D subdivide, n: " + n)
	  	  	      	       if (n > 2) {
	  	                       pts(count) = points(n).clone
	  	  	      	       }
	  	  	      	       count += 1
	  	  	           }
	  	  	  	   }
	  	  	       
	  	  	   } else {
	  	  	  	   if (sidesTotal % 2 == 0) {
	  	  	  	  	   pts(0) = Formulas.lerp(points(i-1), points(i),lineRatios.x)
	  	  	  	  	   //pts(0) = Formulas.average(List(points(i-1), points(i)))
	  	  	           for (n <- 1 to sidesTotal/2) {
	  	                    pts(n) = points(n).clone
	  	  	           }
	  	  	  	  	   pts(pts.length-1) = Formulas.lerp(points(sidesTotal/2), points((sidesTotal/2)+1), lineRatios.y)
	  	  	  	       //pts(pts.length-1) = Formulas.average(List(points(sidesTotal/2), points((sidesTotal/2)+1)))
	  	  	  	       //pts(pts.length-1) = Formulas.average(List(points(i), points(i-1)))
	  	  	  	   } else {
	  	  	  	  	   pts(0) = Formulas.lerp(points(sidesTotal/2), points((sidesTotal/2)+1), lineRatios.x)
	  	  	  	  	   //pts(0) = Formulas.average(List(points(sidesTotal/2), points((sidesTotal/2)+1)))
	  	  	  	  	   pts(1) = points(0).clone
	  	  	  	  	   var count: Int = 2
	  	  	  	  	   for (n <- 1 to sidesTotal/2) {
	  	  	  	  	  	    println("Polygon2D subdivide second, n: " + n)
	  	                    pts(count) = points(n).clone
	  	                    count += 1
	  	  	           }
	  	  	  	  	   //pts(pts.length-1) = points(points.length-1).clone
	  	  	  	   }
	  	  	   }
	  	  	   newPolys(i) = new Polygon2D(pts.toList, PolygonType.LINE_POLYGON)
	  	  	   //println("polyanna: " + i)
	  	       //newPolys(i).print()
	      	   
	       }
	   } else if (subdivisionType==Subdivision.ECHO) {//echoes relative to current polygon (not overall shape)
	  	   newPolys = new Array[Polygon2D](1)
	  	   val pts: Array[Vector2D] = new Array[Vector2D](points.length)//inner points
	  	   for (i <- 0 until points.length) { 
	  	  	   pts(i) = Formulas.lerp(points(i), middle,lineRatios.x)
	  	   }
	  	   if (polyType == PolygonType.LINE_POLYGON) {
	  	       newPolys(0) = new Polygon2D(pts.toList,  PolygonType.LINE_POLYGON)
	  	   } else {
	  	  	   newPolys(0) = new Polygon2D(pts.toList,  PolygonType.SPLINE_POLYGON)
	  	   }
	  	   //println("new polys length: " + newPolys.length)
	  	   //newPolys(newPolys.length-1) = new Polygon2D(pts.toList, PolygonType.LINE_POLYGON)
	   } else if (subdivisionType==Subdivision.ECHO_CENTER) {//always echoes relative to center of overall shape
	  	   newPolys = new Array[Polygon2D](1)
	  	   val pts: Array[Vector2D] = new Array[Vector2D](points.length)//inner points
	  	   for (i <- 0 until points.length) { 
	  	  	   pts(i) = points(i).clone//put original points into new inner points
	  	  	   pts(i) = Transform2D.scale(pts(i), new Vector2D(lineRatios.x, lineRatios.y))
	  	  	   //pts(i) = Formulas.average(List(points(i), middle))
	  	  	   //println("pts " + i + ": " + pts(i))
	  	   }
	  	   if (polyType == PolygonType.LINE_POLYGON) {
	  	       newPolys(0) = new Polygon2D(pts.toList,  PolygonType.LINE_POLYGON)
	  	   } else {
	  	  	   newPolys(0) = new Polygon2D(pts.toList,  PolygonType.SPLINE_POLYGON)
	  	   }
	  	   //println("new polys length: " + newPolys.length)
	  	   //newPolys(newPolys.length-1) = new Polygon2D(pts.toList, PolygonType.LINE_POLYGON)
	   } else if (subdivisionType==Subdivision.BORDER) {//create QUAD border
	  	   newPolys = new Array[Polygon2D](sidesTotal)
	  	   val pts: Array[Vector2D] = new Array[Vector2D](points.length)//inner points
	  	   for (i <- 0 until points.length) { 
	  	  	   pts(i) = Formulas.lerp(points(i), middle,lineRatios.x)
	  	  	   //pts(i) = Formulas.average(List(points(i), middle))
	  	  	   //println("pts " + i + ": " + pts(i))
	  	   }
	  	   for (i <- 0 until sidesTotal) { 
	  	  	   if (polyType == PolygonType.LINE_POLYGON) {
	  	  	       newPolys(i) = new Polygon2D(List(points(i).clone, points(Formulas.circularIndex(i+1, newPolys.length)).clone, pts(Formulas.circularIndex(i+1, newPolys.length)).clone, pts(i).clone), PolygonType.LINE_POLYGON)
	  	  	   } else {
	  	  	  	   
	  	  	  	   //some values to make straight bezier lines into visual curves
	  	            //val rX = Randomise.range(0,.05)-.05//translation value
	  	            val rX = 0
	  	            //val rR = Randomise.range(0, 10)-10//rotation value
	  	            val rR = 0
	  	            
	  	  	  	   val anchorPoints: Array[Vector2D] = new Array[Vector2D](4)
	  	  	  	   anchorPoints(0) = points(i*4).clone
	  	  	  	   anchorPoints(1) = points(Formulas.circularIndex((i*4)+3, points.length)).clone
	  	  	  	   anchorPoints(2) = pts(Formulas.circularIndex((i*4)+3, pts.length)).clone
	  	  	  	   anchorPoints(3) = pts(i*4).clone
	  	  	  	   
	  	  	  	   //calculate half way between anchor one and control point 1
	  	    		val pAc1: Vector2D = points((i*4)+1).clone
	  	    		//calculate half way between anchor two and control point 1
	  	    		val pAc2: Vector2D = points((i*4)+2).clone
	  	    		
	  	    		
	  	    		val pBc1: Vector2D = Formulas.lerp(anchorPoints(1), anchorPoints(2), .25)
	  	    		pBc1.translate(new Vector2D(-rX, 0))
	  	    		pBc1.rotate(-rR)
	  	    		val pBc2: Vector2D = Formulas.lerp(anchorPoints(1), anchorPoints(2), .75)
	  	    		pBc2.translate(new Vector2D(rX, 0))
	  	    		pBc2.rotate(rR)
	  	    		
	  	    		
	  	    		val pCc1: Vector2D = pts((i*4)+2).clone
	  	    		pCc1.translate(new Vector2D(rX, 0))
	  	    		pCc1.rotate(rR)
	  	    		val pCc2: Vector2D = pts((i*4)+1).clone
	  	    		pCc2.translate(new Vector2D(-rX, 0))
	  	    		pCc2.rotate(-rR)
	  	    		
	  	    		val pDc1: Vector2D = Formulas.lerp(anchorPoints(3), anchorPoints(0), .25)
	  	    		val pDc2: Vector2D = Formulas.lerp(anchorPoints(3), anchorPoints(0), .75)
	  	  	  	   
	  	  	  	   newPolys(i) = new Polygon2D(List(anchorPoints(0), pAc1, pAc2, anchorPoints(1), anchorPoints(1).clone, pBc1, pBc2, anchorPoints(2), anchorPoints(2).clone, pCc1, pCc2, anchorPoints(3), anchorPoints(3).clone, pDc1, pDc2, anchorPoints(0).clone), PolygonType.SPLINE_POLYGON)
	  	  	   }
	  	   }
	  	   //println("new polys length: " + newPolys.length)
	  	   //newPolys(newPolys.length-1) = new Polygon2D(pts.toList, PolygonType.LINE_POLYGON)
	   } else if (subdivisionType==Subdivision.ECHO_BORDER) {//create inner polygons connected from corners
	  	   newPolys = new Array[Polygon2D](sidesTotal + 1)
	  	   val pts: Array[Vector2D] = new Array[Vector2D](points.length)//inner points
	  	   for (i <- 0 until points.length) { 
	  	  	   pts(i) = Formulas.lerp(points(i), middle,lineRatios.x)
	  	   }
	  	   for (i <- 0 until sidesTotal) { 
	  	  	   if (polyType == PolygonType.LINE_POLYGON) {
	  	  	       newPolys(i) = new Polygon2D(List(points(i).clone, points(Formulas.circularIndex(i+1, newPolys.length)).clone, pts(Formulas.circularIndex(i+1, newPolys.length)).clone, pts(i).clone), PolygonType.LINE_POLYGON)
	  	  	   } else {
	  	  	  	   
	  	  	  	   //some values to make straight bezier lines into visual curves
	  	            //val rX = Randomise.range(0,.05)-.05//translation value
	  	            val rX = 0
	  	            //val rR = Randomise.range(0, 10)-10//rotation value
	  	            val rR = 0
	  	            
	  	  	  	   val anchorPoints: Array[Vector2D] = new Array[Vector2D](4)
	  	  	  	   anchorPoints(0) = points(i*4).clone
	  	  	  	   anchorPoints(1) = points(Formulas.circularIndex((i*4)+3, points.length)).clone
	  	  	  	   anchorPoints(2) = pts(Formulas.circularIndex((i*4)+3, pts.length)).clone
	  	  	  	   anchorPoints(3) = pts(i*4).clone
	  	  	  	   
	  	  	  	   //calculate half way between anchor one and control point 1
	  	    		val pAc1: Vector2D = points((i*4)+1).clone
	  	    		//calculate half way between anchor two and control point 1
	  	    		val pAc2: Vector2D = points((i*4)+2).clone
	  	    		
	  	    		
	  	    		val pBc1: Vector2D = Formulas.lerp(anchorPoints(1), anchorPoints(2), .25)
	  	    		pBc1.translate(new Vector2D(-rX, 0))
	  	    		pBc1.rotate(-rR)
	  	    		val pBc2: Vector2D = Formulas.lerp(anchorPoints(1), anchorPoints(2), .75)
	  	    		pBc2.translate(new Vector2D(rX, 0))
	  	    		pBc2.rotate(rR)
	  	    		
	  	    		
	  	    		val pCc1: Vector2D = pts((i*4)+2).clone
	  	    		pCc1.translate(new Vector2D(rX, 0))
	  	    		pCc1.rotate(rR)
	  	    		val pCc2: Vector2D = pts((i*4)+1).clone
	  	    		pCc2.translate(new Vector2D(-rX, 0))
	  	    		pCc2.rotate(-rR)
	  	    		
	  	    		val pDc1: Vector2D = Formulas.lerp(anchorPoints(3), anchorPoints(0), .25)
	  	    		val pDc2: Vector2D = Formulas.lerp(anchorPoints(3), anchorPoints(0), .75)
	  	  	  	   
	  	  	  	   newPolys(i) = new Polygon2D(List(anchorPoints(0), pAc1, pAc2, anchorPoints(1), anchorPoints(1).clone, pBc1, pBc2, anchorPoints(2), anchorPoints(2).clone, pCc1, pCc2, anchorPoints(3), anchorPoints(3).clone, pDc1, pDc2, anchorPoints(0).clone), PolygonType.SPLINE_POLYGON)
	  	  	   }
	  	   }
	  	   if (polyType == PolygonType.LINE_POLYGON) {
	  	       newPolys(newPolys.length-1) = new Polygon2D(pts.toList, PolygonType.LINE_POLYGON)
	  	   } else {
	  	  	   newPolys(newPolys.length-1) = new Polygon2D(pts.toList, PolygonType.SPLINE_POLYGON)
	  	   }
	   } 
	   */

}