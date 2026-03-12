package org.loom.utility

class RangeXY (val x: Range, val y: Range) {

	override def toString(): String = {
      var s: String = ""
      s += "x: " + x.toString + ",  "
      s += "y: " + y.toString + ",  "
      s
    }
	
}