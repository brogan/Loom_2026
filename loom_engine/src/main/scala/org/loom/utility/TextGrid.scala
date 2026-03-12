package org.loom.utility

import org.loom.geometry.Vector2D
import org.loom.utility._

/**
 * 
 * Displays a text grid to standard output of one or a set of Vector2D values
 * center is 0,0 and values are arranged around this center
 * they are normalised and adjusted in terms of sepecified row, columns and max value parameters
 * 
 */

class TextGrid(val rows: Int, val cols: Int, val max: Vector2D) {

	def show(pt: Vector2D): Unit = {
		
		val nP = adjustPoint(pt)
        var txt: String = ""
        val emptyTxt: String = "__"
        val middleTxt: String = "X_"
        val middle: Int = ((rows*cols)/2)+cols/2
        var filled: Boolean = false
		for (r <- 0 until rows) {
			for (c <- 0 until cols+1) {
                val currIndex = (r * rows) + c
                if (c < cols) {
	                if (c == nP.x && r == nP.y) {
	                    txt = txt + "0_"
	                    filled = true
	                } else {
	                    if (filled == false) {
	                 	   if (currIndex == middle) {
	                 	      txt = txt + middleTxt
	                       } else {
	                    	  if (c != 0) {
	                 	         txt = txt + emptyTxt
	                 	      } else {
	                 	         txt = txt + "|_"
	                 	      }
	                 	   }
	                    }
	                }
	            } else {
	            	txt = txt + "|\n"
	            }
	            filled = false

            }

		}
		println("")
		println(txt)
		println("")
	    println("Grid DONE - X represents point zero/zero")
	    println("")
	    println("rows: " + rows + "     columns: " + cols)
	    println("max value x: " + max.x + "      min value x: " + (max.x*(-1)))
	    println("mmin value y: " + max.y + "      min value y: " + (max.y*(-1)))
	    println("")
        println("Original point value: " + pt.x + "     y: " + pt.y)
		println("Adjusted point value for display x: " + nP.x + "     y: " + nP.y)
	    println("")

	}

	def show(points: List[Vector2D]): Unit = {
		
		val pts: List[Vector2D] = adjustPointsList(points)
        var txt: String = ""
        val emptyTxt: String = "__"
        val middleTxt: String = "X_"
        val middle: Int = ((rows*cols)/2)+cols/2
        var filled: Boolean = false
		for (r <- 0 until rows) {
			for (c <- 0 until cols+1) {
                val currIndex: Int = (r * rows) + c
                if (c < cols) {
                	for (p <- 0 until pts.length) {
	                   if (r == pts(p).y && c == pts(p).x) {
	                       txt= txt + p + "_"//assumes fewer than 10 points
	                       filled = true
	                    } 
	                 }

	                 if (filled == false) {
	                 	if (currIndex == middle) {
	                 	   txt = txt + middleTxt
	                    } else {
	                    	if (c != 0) {
	                 	      txt = txt + emptyTxt
	                 	    } else {
	                 	       txt = txt + "|_"
	                 	    }
	                 	}
	                 }
	            } else {
	               txt = txt + "|\n"
	            }
	            filled = false

            }

		}
		println("")
		println(txt)
		println("")
		println("Grid done- X represents point zero/zero")
		println("")
		println("rows: " + rows + "     columns: " + cols)
	    println("max value x: " + max.x + "      min value x: " + (max.x*(-1)))
	    println("mmin value y: " + max.y + "      min value y: " + (max.y*(-1)))
	    println("")
		Output.printPts(points, "Original grid values: ")
		println("")
		Output.printPts(pts, "Adjusted point values for display: ")
		println("")

	}

	def printVals(pts: List[Vector2D], info: String): Unit = {
       for (i <- 0 until pts.length) {
			println(info + i + " x: " + pts(i).x + "       y: " + pts(i).y)
		}
	}

    def adjustPointsList(pts: List[Vector2D]): List [Vector2D] = {
    	val ptArray: Array[Vector2D] = new Array[Vector2D](pts.length)
    	for(n <- 0 until pts.length) {
		   var nP: Vector2D = normalisePt(pts(n))
		   nP = switchY(nP)
		   nP = centerPtZero(nP)
		   ptArray(n) = nP
	    }
	    ptArray.toList
	}
	/**
	 * normalise for a specified max value in terms of row/column display, reverse y value, center point around zero 
	 */

	def adjustPoint(pt: Vector2D): Vector2D = {
		var nP: Vector2D = normalisePt(pt)
		nP = switchY(nP)
		nP = centerPtZero(nP)
		nP
	}
	/**
	 * basic formula (n/max) * total
	 * (number/maxPossibleNumber) * totalDisplay unit (columns in this case)
	 * multiply max x and y values by 2 makes 50% available negative and 50% positive
	 */

	def normalisePt(pt: Vector2D): Vector2D = {
	    val nX: Double = ((pt.x/(max.x * 2) * cols)).toInt
		val nY: Double = ((pt.y/(max.y * 2) * rows)).toInt
		new Vector2D(nX,nY)
	}

    /**
     * because otherwise y values go down as they increase
    */
	def switchY(pt: Vector2D): Vector2D = {
		val nY: Double = pt.y * (-1)
		new Vector2D(pt.x,nY)
	}
    
    /**
     * add half the col and row values to center pt around zero
     */

	def centerPtZero(pt: Vector2D): Vector2D = {
		val nX: Double = pt.x + (cols/2.0)
		val nY: Double = pt.y + (rows/2.0)
		new Vector2D(nX,nY)
	}


}