package org.loom.geometry

import org.loom.scaffold._

class Sprite2DParams (val name: String, var loc: Vector2D, var size: Vector2D, var rot: Double) {
	
	//default parameters are all centred with no animation values
	//set initial location, size and rotation for the shape
    //location
    var x: Double = loc.x//the location is specified in terms of the object centre, not the top-left edge
    var y: Double = loc.y
    var locX: Double = ((x/2)/100)*(1/size.x)//takes a positive or negative percentage, divides by two and divides by 100 to make normalised (so -97% becomes -.48)
    var locY: Double = ((y/2)/100)*(1/size.y)//the latter size related multiplier ensures that the loc is conceived at normalised scale, not as a fraction

    var loc2D: Vector2D = new Vector2D(locX, locY)//initial location - negative x to move left, positive y to move up
    var sizeFactor: Vector2D = size
    var size2D: Vector2D = new Vector2D(Config.width * Config.qualityMultiple * sizeFactor.x, Config.height * Config.qualityMultiple * sizeFactor.y)//initial scale
    //(width config width of 1800 and quality multiple of 1 and sizeFactor.x of .7 you get 1260 pixels size on x axis)
    
	//rotOffset controls where the rotation point is set in the shape - so, for example, negative 1 on z brings all the points in the object
	//back by -1, which puts the rotation point on the tip of the crystal
	var startRotation2D: Double = rot
	var rotOffset2D: Vector2D = new Vector2D(0, 0)
	//set some animation parameters for the shape
	var scaleFactor2D: Vector2D = new Vector2D(1, 1)//.9 is about half original scale
	var rotFactor2D: Double = 0//negative values rotate clockwise, a value of 20 or -20 flips object upside down, 40/-40 returns to upright
	var speedFactor2D: Vector2D = new Vector2D(0, 0)

	override def toString(): String = {
		var s: String = "" + "\n"
		s += "Sprite2D params:" + "\n"
		s += "x:" + x + "\n"
		s += "y: " + y + "\n"
		s += "locX: " + locX + "\n"
		s += "locY: " + locY + "\n"
		s += "sizeFactor: " + sizeFactor + "\n"
		s += "size2D: " + size2D + "\n"
		s += "startRotation2D: " + startRotation2D + "\n"
		s += "rotOffset2D: " + rotOffset2D.toString + "\n"
		s += "scaleFactor2D: " + scaleFactor2D.toString + "\n"
		s += "rotFactor2D: " + rotFactor2D + "\n"
		s += "speedFactor2D: " + speedFactor2D.toString + "\n"
		
		
		s
	}

	
	def setParameters (posX: Double, posY: Double, size_Factor: Vector2D, startRotation: Double, rot_Offset2D: Vector2D, scaleFactor: Vector2D, rotFactor: Double, speedFactor: Vector2D): Unit = {

		x = posX
		y = posY
		sizeFactor = size_Factor
		startRotation2D = startRotation
		rotOffset2D = rot_Offset2D
		scaleFactor2D = scaleFactor
		rotFactor2D = rotFactor
		speedFactor2D = speedFactor
	
	}

}