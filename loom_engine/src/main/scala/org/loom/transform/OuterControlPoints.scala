
package org.loom.transform

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import scala.collection.mutable.ArrayBuffer



class OuterControlPoints(curving: Boolean) extends Transform (curving) {

	var probability: Double = 7

	var sidesTotal: Int = 4//number of sides in original polygon (prior to subdivision)
	var numSidesPerPoly: Int = 4//default quad subdivision
	var absoluteCentre: Vector2D = new Vector2D(0,0)//this is only needed when curveFromCentre is true (see just below)

	val midLineRatio: Double = .5//for calculating the initial middle

	//for calculating positions of control points along the outside line
    var lineSideRatio: Vector2D = new Vector2D(.33, .66)//first value for first control point on outer spline, second for next
    var randomLineRatio: Boolean = false
    var randomLineRatioA: Range = new Range(.1, .5)//specify a random outer ratio
    var randomLineRatioB: Range = new Range(.5, .9)//specify a random inner ratio

    //Two ways of calculating outside spline curvature :
    //1.  First way: calculateS difference vector between the control point and a notional middle point on the line, then convertS that to a perpendicular vector that gets applied
    //to the control point, either bulging it out (postive values or puckering it in (negative values).  A multiplier is then applied to exaggerate the vector.
    //A single curve can both bulge and pinch.  The curveTypes are given in the OuterControlPoints object. PUFF means that all control points on external lines bulge.  PINCH means
    //that they contract into the polygon.  Something like PUFF_PINCH_PUFF_PINCH means that first control point puffs and second pinches, while the second last control point in the new polygon
    //puffs and the last control point pinches.
    //2.  Second way takes the vector from the absolute centre of all polygons in subdivision and lerps (linear interpolation) between the centre and the notional midpoint on the outside line.
    //This then gets shifted by the vector difference between the mid point and the control points to move the control points along their parallel lines.
    //Fairly undpredictable if there is not symmetrical centre, but can create intresting wave like effects and major distortion when applied iteratively.

    //We begin with the much safer first way!

    var curveFromCentre: Boolean = false//so set this to FALSE if you want default predictable behaviour

    var curveType: Int = OuterControlPoints.PUFF
    //var curveType: Int = OuterControlPoints.PINCH
    //var curveType: Int = OuterControlPoints.PUFF_PINCH_PUFF_PINCH
    //var curveType: Int = OuterControlPoints.PUFF_PINCH_PINCH_PUFF
    //var curveType: Int = OuterControlPoints.PINCH_PUFF_PINCH_PUFF
    //var curveType: Int = OuterControlPoints.PINCH_PUFF_PUFF_PINCH

    var curveMultiplier: Range = new Range(1, 3)
    var randomMultiplier: Boolean = false
    var randomCurveMultiplier: Range = new Range(.5, 3)

    //and here are the additional variables needed if curveFromCentre is true

    var curveFromCentreRatio: Vector2D = new Vector2D(.2, -.5)//x is for control point next to 0, y for one next to 3 (same system as curveRatio)
    var ranCurveFromCentre: Boolean = false
    var ranCurveFromCentreRatioA: Range = new Range(-1, 1)//for control point next to point 0
    var ranCurveFromCentreRatioB: Range = new Range(-1, 1)//for control point next to point 3


	override def toString(): String = "this is a outside control points transform and it is: " + curving

    //CONVENIENCE METHODS
	def setRandomLineSideRatio(innerRatio: Range, outerRatio: Range): Unit = {
		randomLineRatio = true
		randomLineRatioA = outerRatio
		randomLineRatioB = innerRatio
	}


	def curvePerpendicular(prob: Double, cType: Int, lineRatio: Vector2D, cMultiplier: Range): Unit = {
		probability = prob
		curveType = cType
		lineSideRatio = lineRatio
		curveFromCentre = false
		curveMultiplier = cMultiplier
	}

	def curvePerpendicularRandomMultiplier(prob: Double, cType: Int, lineRatio: Vector2D, cRandomMultiplier: Range): Unit = {
		probability = prob
		curveType = cType
		lineSideRatio = lineRatio
		curveFromCentre = false
		randomMultiplier = true
		randomCurveMultiplier = cRandomMultiplier
	}

	def curveFromCentre(prob: Double, cRatio: Vector2D): Unit = {
		probability = prob
		curveFromCentre = true
		ranCurveFromCentre = false
		curveFromCentreRatio = cRatio
	}

	def curveFromCentreRandom(prob: Double, cp1Ratio: Range, cp2Ratio: Range): Unit = {
		probability = prob
		curveFromCentre = true
		ranCurveFromCentre = true
		ranCurveFromCentreRatioA = cp1Ratio
		ranCurveFromCentreRatioB = cp2Ratio
	}
	//END CONVENIENCE METHODS

	override def transform(polys: Array[Polygon2D], centreIndex: Int, subdivisionType: Int, sidesTot: Int, sidesPerPoly: Int): Unit = {
		
		sidesTotal = sidesTot//in original polygon (can have any number of sides)
		numSidesPerPoly = sidesPerPoly//in subdivisions (TRI or QUAD - 3 or 4 currently)
		absoluteCentre = Formulas.average(getExteriorAnchors(polys, centreIndex))

		if (transforming) {//superclass field

			for (i <- 0 until polys.length) {

			    if (Randomise.happens(probability)) {

			    	if (numSidesPerPoly == 3) {
			    		println("Tri inside curves")

			    		val controls1: Array[Vector2D] = Array(polys(i).points(1), polys(i).points(2))
						val controls: Array[Array[Vector2D]] = Array(controls1)//the control points as Vector2Ds
						val indexes: Array[Array[Int]] = Array(Array(1, 2))//indexes of two relevant control points in each poly

						curve(polys(i), centreIndex, controls, indexes, i)

			    	} else if (numSidesPerPoly == 4) {
			    		println("Quad inside curves")

			    		val controls1: Array[Vector2D] = Array(polys(i).points(1), polys(i).points(2))
						val controls2: Array[Vector2D] = Array(polys(i).points(13), polys(i).points(14))
						val controls: Array[Array[Vector2D]] = Array(controls1, controls2)
						val indexes: Array[Array[Int]] = Array(Array(1, 2), Array(13,14))

						curve(polys(i), centreIndex, controls, indexes, i)

			    	}
		    	}

			}

		}

	}
	//needed for curveFromCentre curving
	def getExteriorAnchors(polys: Array[Polygon2D], centreIndex: Int): List[Vector2D] = {
		//initArray for tri (0,3,4,11), for quad (0,3,4,11, 12, 15)
		val initArray: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]//to store anchors in a linear array
		for(k <- 0 until polys.length) {
			for (i <- 0 until polys(k).points.length) {
				if (i%4 == 0 || i%4 == 3) {//if points 0, 3 in every spline
					if (i != centreIndex || i != centreIndex -1) {//if not centre points
						initArray += polys(k).points(i)
					}
				}
			}
		}
		initArray.toList
	}

	def curve(poly: Polygon2D, centreIndex: Int, controls: Array[Array[Vector2D]], indexes: Array[Array[Int]], @unused polyIndex: Int): Unit = {

		for(i <- 0 until controls.length) {//controls is composed of two arrays, first made up of two cps on first spline, second of two cps on last spline in poly

			//println("controls: " + controls(0)(0) + "   " + controls(0)(1) + "   " + controls(1)(0) + "   " + controls(1)(1)) 

			val mid: Vector2D = Formulas.lerp(poly.points(indexes(i)(0)-1), poly.points(indexes(i)(1)+1), midLineRatio)//middle of outer line
			val centerToMidVector = Formulas.differenceBetweenTwoVectors(poly.points(centreIndex), mid)
			val orientation = Vector2D. getVectorOrientation(centerToMidVector)
			//println("controls " +i + " orientation: " + orientation)


			var controlA: Vector2D = new Vector2D(0,0)
			var controlB: Vector2D = new Vector2D(0,0)

			if (randomLineRatio) {

				val ranRatioA: Double = Randomise.range(randomLineRatioA.min, randomLineRatioA.max)
				val ranRatioB: Double = Randomise.range(randomLineRatioB.min, randomLineRatioB.max)

				controlA = Formulas.lerp(poly.points(indexes(i)(0)-1), poly.points(indexes(i)(1)+1), ranRatioA)
				controlB = Formulas.lerp(poly.points(indexes(i)(0)-1), poly.points(indexes(i)(1)+1), ranRatioB)

			} else {

				controlA = Formulas.lerp(poly.points(indexes(i)(0)-1), poly.points(indexes(i)(1)+1), lineSideRatio.x)
				controlB = Formulas.lerp(poly.points(indexes(i)(0)-1), poly.points(indexes(i)(1)+1), lineSideRatio.y)

			}

			val diffVectA: Vector2D = Formulas.differenceBetweenTwoVectors(mid,controlA)
			//println("diffVectA: " + diffVectA)

			//var diffVectB: Vector2D = Formulas.differenceBetweenTwoVectors(controlB, mid)

			//val invA: Vector2D = Formulas.inverseVector(diffVectA)
			//val invB: Vector2D = Formulas.inverseVector(diffVectB)

			val matchingPerpVector: Vector2D = Formulas.perpendicularVectorMatchOrientation(diffVectA, orientation)//the vector that follows the orientation (puffing)
			//println("matchingPerpVector: " + matchingPerpVector)
			val reversePerpVector: Vector2D = Formulas.reverseVector(matchingPerpVector)//the vector that reverses the orientation (pinching)




			if (!curveFromCentre) {//CURVE VIA PERPENDICULAR MOVES BASED ON VECTOR DIFFERENCE BETWEEN CONTROL POINT AND A NOTIONAL MIDDLE ON THE LINE BETWEEN RELEVANT ANCHORS

				if (randomMultiplier) {

					controlA = Vector2D.add(controlA, Vector2D.multiply(matchingPerpVector, Randomise.range(randomCurveMultiplier.min, randomCurveMultiplier.max)))
					controlB = Vector2D.add(controlB, Vector2D.multiply(matchingPerpVector, Randomise.range(randomCurveMultiplier.min, randomCurveMultiplier.max)))

				} else {

					if (curveType == OuterControlPoints.PUFF) {

						controlA = Vector2D.add(controlA, Vector2D.multiply(matchingPerpVector, curveMultiplier.min))
						controlB = Vector2D.add(controlB, Vector2D.multiply(matchingPerpVector, curveMultiplier.max))


					} else if (curveType == OuterControlPoints.PINCH) {

						controlA = Vector2D.add(controlA, Vector2D.multiply(reversePerpVector, curveMultiplier.min))
						controlB = Vector2D.add(controlB, Vector2D.multiply(reversePerpVector, curveMultiplier.max))


					} else if (curveType == OuterControlPoints.PUFF_PINCH_PUFF_PINCH) {

						if((i%2)==0) {//first set of control points

							controlA = Vector2D.add(controlA, Vector2D.multiply(matchingPerpVector, curveMultiplier.min))
							controlB = Vector2D.add(controlB, Vector2D.multiply(reversePerpVector, curveMultiplier.max))

						} else {

							controlA = Vector2D.add(controlA, Vector2D.multiply(matchingPerpVector, curveMultiplier.min))
							controlB = Vector2D.add(controlB, Vector2D.multiply(reversePerpVector, curveMultiplier.max))

						}

					} else if (curveType == OuterControlPoints.PUFF_PINCH_PINCH_PUFF) {

						if((i%2)==0) {//first set of control points

							controlA = Vector2D.add(controlA, Vector2D.multiply(matchingPerpVector, curveMultiplier.min))
							controlB = Vector2D.add(controlB, Vector2D.multiply(reversePerpVector, curveMultiplier.max))

						} else {

							controlA = Vector2D.add(controlA, Vector2D.multiply(reversePerpVector, curveMultiplier.min))
							controlB = Vector2D.add(controlB, Vector2D.multiply(matchingPerpVector, curveMultiplier.max))

						}

					} else if (curveType == OuterControlPoints.PINCH_PUFF_PINCH_PUFF) {

						if((i%2)==0) {//first set of control points

							controlA = Vector2D.add(controlA, Vector2D.multiply(reversePerpVector, curveMultiplier.min))
							controlB = Vector2D.add(controlB, Vector2D.multiply(matchingPerpVector, curveMultiplier.max))

						} else {

							controlA = Vector2D.add(controlA, Vector2D.multiply(reversePerpVector, curveMultiplier.min))
							controlB = Vector2D.add(controlB, Vector2D.multiply(matchingPerpVector, curveMultiplier.max))

						}

					} else if (curveType == OuterControlPoints.PINCH_PUFF_PUFF_PINCH) {

						if((i%2)==0) {//first set of control points

							controlA = Vector2D.add(controlA, Vector2D.multiply(reversePerpVector, curveMultiplier.min))
							controlB = Vector2D.add(controlB, Vector2D.multiply(matchingPerpVector, curveMultiplier.max))

						} else {

							controlA = Vector2D.add(controlA, Vector2D.multiply(matchingPerpVector, curveMultiplier.min))
							controlB = Vector2D.add(controlB, Vector2D.multiply(reversePerpVector, curveMultiplier.max))

						}

					}

				}

			} else {//CURVE IN RELATION TO ABSOLUTE CENTRE

				if (ranCurveFromCentre) {

					val ranCurveRatioA: Double = Randomise.range(ranCurveFromCentreRatioA.min, ranCurveFromCentreRatioA.max)
					val ranCurveRatioB: Double = Randomise.range(ranCurveFromCentreRatioB.min, ranCurveFromCentreRatioB.max)

					val curveA: Vector2D = Formulas.lerp(absoluteCentre, mid, ranCurveRatioA)
					controlA = Vector2D.add(controlA, curveA)
					
					val curveB: Vector2D = Formulas.lerp(absoluteCentre, mid, ranCurveRatioB)
					controlB= Vector2D.add(controlB, curveB)

				} else {

					println("curve from centre")

					val curveA: Vector2D = Formulas.lerp(absoluteCentre, mid, curveFromCentreRatio.x)
					val diffVectA: Vector2D = Formulas.differenceBetweenTwoVectors(absoluteCentre,curveA)
			
					controlA = Vector2D.add(mid, diffVectA)

					println("curve from centre a: " + curveA.toString())
					
					val curveB: Vector2D = Formulas.lerp(absoluteCentre, mid, curveFromCentreRatio.y)
					val diffVectB: Vector2D = Formulas.differenceBetweenTwoVectors(absoluteCentre,curveB)
					controlB= Vector2D.add(mid, diffVectB)

				}				
			}

			Vector2D.copyValues(controlA, poly.points(indexes(i)(0)))
			Vector2D.copyValues(controlB, poly.points(indexes(i)(1)))

		}
		println("////")
	}


}

object OuterControlPoints {

	val PUFF: Int = 0
	val PINCH: Int = 1
	val PUFF_PINCH_PUFF_PINCH: Int = 2
	val PUFF_PINCH_PINCH_PUFF: Int = 3
    val PINCH_PUFF_PUFF_PINCH: Int = 4
	val PINCH_PUFF_PINCH_PUFF: Int = 5

}