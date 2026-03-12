/**
Colors defines some default colors that you can access via name.
*/

package org.loom.utility

import java.awt.Color

object Colors {

   val WHITE = new Color(255,255,255)
   val BLACK = new Color(0,0,0)
   val GREY = new Color(150,150,150)
   val RED = new Color(255,0,0)
   val GREEN = new Color(0,255,0)
   val BLUE = new Color(0,0,255)

   def colorToArray(col: Color): Array[Int] = {
      val a = Array(0,0,0,0)
      a(0) = col.getRed
      a(1) = col.getGreen
      a(2) = col.getBlue
      a(3) = col.getAlpha
      a
   }

}
