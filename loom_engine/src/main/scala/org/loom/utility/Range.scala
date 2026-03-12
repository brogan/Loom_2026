package org.loom.utility

class Range (val min: Double, val max: Double) {

	override def toString(): String = {
      var s: String = ""
      s += "min: " + min + ",  "
      s += "max: " + max + ",  "
      s
    }
	
}