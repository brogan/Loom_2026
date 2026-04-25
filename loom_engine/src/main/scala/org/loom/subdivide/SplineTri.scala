package org.loom.subdivide

import org.loom.geometry._
import org.loom.utility._
import org.loom.transform._

//gets current points and calculates new array of points for each of new polys

class SplineTri(subdivObj: Subdivision, middle: Vector2D, subP: SubdivisionParams, polyType: Int) {


	val totNewPolys: Int = subdivObj.sidesTotal//use this to get number of sides of old poly
	val numSidesPerPoly: Int = 3
	val numPointsPerPolySide: Int = 4//2 anchor points and 2 control points

	val tGrid: TextGrid = new TextGrid(40,40,new Vector2D(1,1))

    def getPolys(): Array[Polygon2D] = {

    	val oldSides: Array[Array[Vector2D]] = getArrayOfOldSides()//an array of splines (with each spline an array of 4 points)

    	val internalSides: Array[Array[Array[Vector2D]]] = getArrayOfInternalSides(oldSides)//an array of pairs of splines corresponding to the two internal sides of new triangles

    	val polyArray: Array[Polygon2D] = makePolys(oldSides, internalSides)

        // centreIndex = 8: centre anchors sit at points[7] and points[8] in both QUAD and TRI layouts
    	val centreIndex: Int = 8

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
     * Gets the sides that run from the middle points on external splines to the middle point of the polygon
     * new sides (sides/subsides/points)
     * internal sides (sides/points)
     */ 
    def getArrayOfInternalSides(oldSides: Array[Array[Vector2D]]): Array[Array[Array[Vector2D]]] = {


    	val internalSides: Array[Array[Array[Vector2D]]] = new Array[Array[Array[Vector2D]]](subdivObj.sidesTotal)

    	for (j <- 0 until oldSides.length) {

    		val A1: Vector2D = oldSides(j)(0).clone()
    		val B1: Vector2D = middle.clone()//ADJUST CENTRE POINTS HERE?

    		val AC1: Vector2D = Formulas.lerp(A1,B1,subP.controlPointRatios.x)
    		val BC1: Vector2D = Formulas.lerp(A1,B1,subP.controlPointRatios.y)

            val A2: Vector2D = oldSides(j)(3).clone()
            val B2: Vector2D = middle.clone()//ADJUST CENTRE POINTS HERE?

            val AC2: Vector2D = Formulas.lerp(A2,B2,subP.controlPointRatios.x)
            val BC2: Vector2D = Formulas.lerp(A2,B2,subP.controlPointRatios.y)

            internalSides(j) = Array(Array(A2, AC2, BC2, B2), Array(B1, BC1, AC1, A1))
    	}

    	internalSides

    }


    def makePolys(oldSides: Array[Array[Vector2D]], internalSides: Array[Array[Array[Vector2D]]]): Array[Polygon2D] = {
    	
        val polyArray: Array[Polygon2D] = new Array[Polygon2D](totNewPolys)

        for (i <- 0 until totNewPolys) {
        	val ptArray: Array[Vector2D] = new Array[Vector2D](numSidesPerPoly*numPointsPerPolySide)//12
            ptArray(0) = oldSides(i)(0).clone()
            ptArray(1) = oldSides(i)(1).clone()
            ptArray(2) = oldSides(i)(2).clone()
            ptArray(3) = oldSides(i)(3).clone()
            ptArray(4) = internalSides(i)(0)(0).clone()
            ptArray(5) = internalSides(i)(0)(1).clone()
            ptArray(6) = internalSides(i)(0)(2).clone()
            ptArray(7) = internalSides(i)(0)(3).clone()
            ptArray(8) = internalSides(i)(1)(0).clone()
            ptArray(9) = internalSides(i)(1)(1).clone()
            ptArray(10) = internalSides(i)(1)(2).clone()
            ptArray(11) = internalSides(i)(1)(3).clone()

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
    	 	println ("$$$$$$$$Spline TRI    Polygon index: " + j)
    	 	for (k <- 0 until 12) {
    	 		println ("    Spline TRI    Point index: " + k + "      *100 x: " + (polyArray(j).points(k).x * 100).toInt  + "    *100 y: " + (polyArray(j).points(k).y * 100).toInt)
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

