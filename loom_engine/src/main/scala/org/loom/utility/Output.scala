package org.loom.utility

import java.awt.Color
import org.loom.geometry.Vector2D
//import org.loom.utility.Colors

object Output {
	
	def printPt (pt: Vector2D, name: String): Unit = {

		println("POINT_____")
		println(name + " x: " + pt.x + "      y: " +pt.y)
		println("__________")

	}

	def printPts(pts: List[Vector2D], info: String): Unit= {
		println("LIST OF POINTS_____")
       for (i <- 0 until pts.length) {
			println(info + i + " x: " + pts(i).x + "       y: " + pts(i).y)
		}
		println("__________")
	}

	def printColor(col: Color): Unit = {
		val a: Array[Int] = Colors.colorToArray(col)
		println("  RGBA: [" + a(0) + ", " + a(1) + ", " + a(2) + ", " + a(3) + "]")
	}

	def printColor(a: Array[Int]): Unit = {
		println("  RGBA: [" + a(0) + ", " + a(1) + ", " + a(2) + ", " + a(3) + "]")
	}

}
