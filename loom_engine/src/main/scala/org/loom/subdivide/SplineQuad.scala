package org.loom.subdivide

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

//gets current points and calculates new array of points for each of new polys

class SplineQuad(subdivObj: Subdivision, middle: Vector2D, subP: SubdivisionParams, polyType: Int) {

	val totNewPolys: Int = subdivObj.sidesTotal//use this to get number of sides of old poly
	val numSidesPerPoly: Int = 4//QUAD for new poly
	val numPointsPerPolySide: Int =4//2 anchor points and 2 control points

	val tGrid: TextGrid = new TextGrid(40,40,new Vector2D(1,1))

    def getPolys(): Array[Polygon2D] = {
        
    	//val setOfPolys: Array[Polygon2D] = new Array[Polygon2D](totNewPolys)

    	val oldSides: Array[Array[Vector2D]] = getArrayOfOldSides()

    	val newSides: Array[Array[Array[Vector2D]]] = getArrayOfNewSides(oldSides)

    	val internalSides: Array[Array[Vector2D]] = getArrayOfInternalSides(newSides)

    	val newPolySides: Array[Array[Array[Vector2D]]] = getArrayOfPolySides(newSides, internalSides)

    	val polyArray: Array[Polygon2D] = makePolys(newPolySides)

        //the centre index is 8 for each of the new quad polys
    	val centreIndex: Int = (polyArray(0).points.length/2)//the centre in a QUAD subdivision

    	if (subP.polysTransform) {//If we are transforming subdivided polygons
    		if (subP.polysTransformPoints) {//transform sets of points in new polys
    			PointsTransform.transformPoints(polyArray, subP, centreIndex, subdivObj.sidesTotal, numSidesPerPoly)
    		}
    		if (subP.polysTranformWhole) {//transform whole polys
    	    	PolysTransform.transform(polyArray, subdivObj, subP)//before overall polys adjustment - maybe this could be reversed?  Maybe need a flag in subP to determine order
    	    }
    	}
    	//printPolyArray(polyArray)
    	makePolysVisible(polyArray)

    	polyArray
    		

    }

    /**
     * The sides on the original polygon as an array of any number of sides, with each an array of 4 points
     * old sides = n sides, and 4 points per side
    */ 
    def getArrayOfOldSides(): Array[Array[Vector2D]] = {
        val polySides: Array[Array[Vector2D]] = new Array[Array[Vector2D]](subdivObj.sidesTotal)
    	for (i <- 0 until subdivObj.sidesTotal) {
    		val side: Array[Vector2D] = new Array[Vector2D](numPointsPerPolySide)
            for (j <- 0 until numPointsPerPolySide) {
               val ptIndex: Int = (numPointsPerPolySide * i) + j
               side(j) = subdivObj.points(ptIndex)
            }
            polySides(i) = side
    	}
    	polySides

    }

        /**
     * The external sides of the new set of polygons - an array of any number of sides, with 2 subsides each, which are each composed of 4 points
    */ 

    def getArrayOfNewSides(oldSides: Array[Array[Vector2D]]): Array[Array[Array[Vector2D]]] = {
       val newPolySides: Array[Array[Array[Vector2D]]] = new Array[Array[Array[Vector2D]]](subdivObj.sidesTotal)
       for (i <- 0 until subdivObj.sidesTotal) {
       	   val subSides: Array[Array[Vector2D]] = getSubSides(oldSides(i), i)

       	   //tGrid.show(subSides(0).toList)

       	   newPolySides(i) = subSides
       }
       newPolySides
    }

    def getSubSides(oldSide: Array[Vector2D], oldSideIndex: Int): Array[Array[Vector2D]] = {

       val A: Vector2D = oldSide(0).clone()//first anchor
       val AC: Vector2D = oldSide(1).clone()//first control
       val BC: Vector2D = oldSide(2).clone()//last controls
       val B: Vector2D = oldSide(3).clone()//last anchor

       /**
        * Next section gets the midpoints in terms of subB.lineRatios
        * Default is (.5,.5)
        * If x and y values differ then subP.continuous ensures adjacent polygons line up
        * If continous false then no overall seamless mesh
        */

       var Mb: Vector2D = new Vector2D(0,0)
       var M: Vector2D = new Vector2D(0,0)

       if (subP.continuous) {//this connects the mid-points on adjacent polygons

	  	    if (oldSideIndex % 2 == 0) {
                Mb = Formulas.bezierPoint(A,AC,BC,B, subP.lineRatios.x)//gets the middle point on bezier line
       			M = Formulas.lerp(A,B,subP.lineRatios.x)//get the absolute middle point between two anchors
	        } else {
                Mb = Formulas.bezierPoint(A,AC,BC,B, subP.lineRatios.y)//gets the middle point on bezier line
      			M = Formulas.lerp(A,B,subP.lineRatios.y)//get the absolute middle point between two anchors
	        } 

	  	} else {//lines on adjacent polygons are not aligned
            Mb = Formulas.bezierPoint(A,AC,BC,B, subP.lineRatios.x)//gets the middle point on bezier line
       		M = Formulas.lerp(A,B,subP.lineRatios.x)//get the absolute middle point between two anchors

	  	}



   	   val M_Mb: Vector2D = Formulas.differenceBetweenTwoVectors(M, Mb)//vector from A-B middle to bezier middle
   	   
       //POINTS TRANSFORM - BULGE/PUCKER********************************************************************************************************************************
   	   //bulge or pucker polygon via positioning of external control points beyond or within the A-B line relative to the polygon centre
       //bulgePucker(M_Mb, A, M, Mb, oldSideIndex)//if transforming points and bulging or puckering (set in subdivision parameters via MySketch)



       val A_Up = Formulas.addVector2Ds(A, M_Mb)//calculate a point equivalent to bezier middle above anchor one (A_Up)
       val B_Up = Formulas.addVector2Ds(B, M_Mb)//calculate a point equivalent to bezier middle above anchor two (B_Up)
       

       //scale original control points by half
       val AC_scaled: Vector2D = Formulas.average(List(A, AC))
       val BC_scaled: Vector2D = Formulas.average(List(B, BC))


       val A_AC_scaled: Double = Formulas.hypotenuse(A, AC_scaled)//get the distance between first anchor and first scaled control point
       val B_BC_scaled: Double = Formulas.hypotenuse(B, BC_scaled)//get the distance between second anchor and second scaled control point
       //println("A to AC scaled: " + A_AC_scaled)
       //println("B to BC scaled: " + B_BC_scaled)

       val A_Up_Mb: Double = Formulas.hypotenuse(A_Up, Mb)//get the distance between A_Up and bezier middle (this gives us a rectangle)
       val B_Up_Mb: Double = Formulas.hypotenuse(B_Up, Mb)//get the distance between B_Up and bezier middle (this gives us a rectangle)
       //println("A to Middle bezier: " + A_Up_Mb)
       //println("B to Middle bezier: " + B_Up_Mb)

       val cFactor: Double = 1//relationship between length of A-AC_scaled and new control running from Mb

       val Mb_MbAC: Double = A_AC_scaled * cFactor//sets length of new control handle from Mb running in direction of A
       val Mb_MbBC: Double = B_BC_scaled * cFactor//sets length of new control handle from Mb running in direction of A
       //need to think about this one because easy to have non symmetrical values that throw out calculation of subsequent bezier middles
       //the control points can throw out the calculation of the average
       val perA: Double = (Formulas.percentage(Mb_MbAC, A_Up_Mb))/100//get the new control handle length as a percentage
       val perB: Double = (Formulas.percentage(Mb_MbBC, B_Up_Mb))/100//get the new control handle length as a percentage
       //println("Percentage Mb to MbAC relative to A_Up to Mb length: " + perA)
       //println("Percentage Mb to MbBC relative to B_Up to Mb length: " + perB)

       val MbAC: Vector2D = Formulas.lerp (Mb, A_Up, perA)//lerp via the percentage from Mb in the direction of A_Up to calculate MbAC (first middle bezier point)
       val MbBC: Vector2D = Formulas.lerp (Mb, B_Up, perB)//lerp via the percentage from Mb in the direction of B_Up to calculate MbBC (second middle bezier point)

       val firstSide: Array[Vector2D] = Array(A, AC_scaled, MbAC, Mb.clone())
       val secondSide: Array[Vector2D] = Array(Mb.clone(), MbBC, BC_scaled, B)


       Array(firstSide, secondSide)


    }

        /**
     * Gets the sides that run from the middle points on external splines to the middle point of the polygon
     * new sides (sides/subsides/points)
     * internal sides (sides/points)
     */ 
    def getArrayOfInternalSides(newSides: Array[Array[Array[Vector2D]]]): Array[Array[Vector2D]] = {

    	

    	val internalSides: Array[Array[Vector2D]] = new Array[Array[Vector2D]](subdivObj.sidesTotal)

    	val outerPoints: Array[Vector2D] = new Array[Vector2D](subdivObj.sidesTotal)
    	for (i <- 0 until subdivObj.sidesTotal) {
    		val v: Vector2D = newSides(i)(1)(0)//the first point in each second subside
    		outerPoints(i) = v
    	}

    	for (j <- 0 until subdivObj.sidesTotal) {

    		val A: Vector2D = outerPoints(j).clone()

    		val B: Vector2D = middle.clone()//ADJUST CENTRE POINTS HERE?

            //POINTS TRANSFORM CENTER
    		//B = Formulas.lerp(B, newSides(j)(0)(3), .05)
    		//B = Formulas.lerp(B, newSides(j)(0)(0), Randomise.range(.05, .1))

    		val AC: Vector2D = Formulas.lerp(A,B,subP.controlPointRatios.x)
    		val BC: Vector2D = Formulas.lerp(A,B,subP.controlPointRatios.y)
    		internalSides(j) = Array(A, AC, BC, B)
    	}

    	internalSides

    }


    def getArrayOfPolySides(newSides: Array[Array[Array[Vector2D]]], internalSides: Array[Array[Vector2D]]): Array[Array[Array[Vector2D]]] = {

    	//val newSides: Array[Array[Array[Vector2D]]] = cloneNewSides(nS)
    	//val internalSides: Array[Array[Vector2D]] = cloneInternalSides(iS)

        val polySides: Array[Array[Array[Vector2D]]] = new Array[Array[Array[Vector2D]]](subdivObj.sidesTotal)
        for (i <- 0 until polySides.length) {

        	val sideA: Array[Vector2D] = newSides(i)(0)
        	val sideB: Array[Vector2D] = internalSides(i)

        	val sideCIndex: Int = (i + ((subdivObj.sidesTotal)-1)) % subdivObj.sidesTotal
        	val sideC: Array[Vector2D] = reversePointsOfSide(internalSides(sideCIndex))

        	val sideDIndex: Int = (i + ((subdivObj.sidesTotal)-1)) % subdivObj.sidesTotal
        	val sideD: Array[Vector2D] = newSides(sideDIndex)(1)

        	polySides(i) = Array(sideA, sideB, sideC, sideD)
        	

        }

        polySides

    }

    def makePolys(newPolySides: Array[Array[Array[Vector2D]]]): Array[Polygon2D] = {
    	
        val polyArray: Array[Polygon2D] = new Array[Polygon2D](totNewPolys)
        for (i <- 0 until totNewPolys) {
        	val ptArray: Array[Vector2D] = new Array[Vector2D](numSidesPerPoly*numSidesPerPoly)//16
        	for (j <- 0 until numSidesPerPoly) {

        		for (k <- 0 until numPointsPerPolySide) {
        			//println("SplineQuad makePolys()   i: " + i + "    j: " + j + "    k: " + k + "   : " + newPolySides(i)(j)(k))
	    		    ptArray((j*numSidesPerPoly)+k) = newPolySides(i)(j)(k).clone()
        		}
        		
        	}
        	polyArray(i) = new Polygon2D(ptArray.toList, polyType)
        	
        }
        polyArray
    }



    def makePolysVisible(polyArray: Array[Polygon2D]): Unit = {
    	for (i <- 0 until totNewPolys) {
    		Subdivision.setVisible(polyArray(i), i, polyArray.length, subP.visibilityRule)
    	}

    }

    def printPolyArray(polyArray: Array[Polygon2D]): Unit = {
    	 for (j <- 0 until polyArray.length) {
    	 	println ("$$$$$$$$Spline QUAD    Polygon index: " + j)
    	 	for (k <- 0 until 16) {
    	 		println ("    Spline QUAD    Point index: " + k + "      *100 x: " + (polyArray(j).points(k).x * 100).toInt  + "    *100 y: " + (polyArray(j).points(k).y * 100).toInt)
    	 	}
    	 	tGrid.show(polyArray(j).points)

         }
    }


    //for lines going from center to outside (spline 2 in each poly)
    def reversePointsOfSide(side: Array[Vector2D]): Array[Vector2D] = {
        val reverse: Array[Vector2D] = new Array[Vector2D](side.length)
        var count: Int = 0
        for (i <- (numPointsPerPolySide-1) to 0 by -1) {
        	reverse(count) = side(i)
        	count = count + 1
        }
        reverse
    }


}

