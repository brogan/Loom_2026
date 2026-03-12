package org.loom.scene

import org.loom.geometry._
import java.awt._

trait Drawable {
	
	def update(): Unit
	def draw (g2D: Graphics2D): Unit
	def drawPoly (g2D: Graphics2D, polyIndex: Int): Unit
	def getShape (): AbstractShape //Shape2D or Shape3D
	def getSize (): Int

}