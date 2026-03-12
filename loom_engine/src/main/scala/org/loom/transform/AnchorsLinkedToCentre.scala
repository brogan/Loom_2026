package org.loom.transform

import org.loom.geometry._
import org.loom.utility._
import scala.collection.mutable.ArrayBuffer



class AnchorsLinkedToCentre(tearing: Boolean) extends Transform (tearing) {

	var probability: Double = 100

	var sidesTotal: Int = 4//number of sides in original polygon (prior to subdivision)
	var numSidesPerPoly: Int = 4//default quad subdivision

	var tearTowardsOutsideCorner: Boolean = true
	var tearTowardsOppositeCorner: Boolean = false
	var tearTowardsCentre: Boolean = false
	var randomTearType: Boolean = false

	var tearFactor: Double = .45
	var randomTear: Boolean = false//randomly determine tear factor - this leads to unaligned polygon inside corners
	var randomTearFactor: Range = new Range(-.2, .2)//random tearing ranges 

	var cpsFollow: Boolean = true//child control points follow their parent anchors
	var cpsFollowMultiplier: Double = 1//following can be multiplied to accentuate or reverse (negative numbers)
	var randomCPsFollow: Boolean = false//randomly determine following
	var randomCPsFollowMultiplier: Range = new Range(-1.5, 1.5)//in terms of this range

	override def toString(): String = "this is a tear transform and it is: " + tearing

	//convenience method for initialising standard values
	def adjustStandardFields (p: Double, tF: Double, cpsF: Boolean, cpsFM: Double, rCPSFollow: Boolean, rCPSFollowMultiplier: Range): Unit = {
		probability = p
		tearFactor = tF
		cpsFollow = cpsF
		cpsFollowMultiplier = cpsFM
		randomCPsFollow = rCPSFollow
		randomCPsFollowMultiplier = rCPSFollowMultiplier
	}
//convenience method 
	def setTearType(tearType: Int): Unit = {

		tearType match {
			case 0 => 
				tearTowardsOutsideCorner = true
				tearTowardsOppositeCorner = false
				tearTowardsCentre = false
				randomTearType = false
			case 1 =>
				tearTowardsOutsideCorner = false
				tearTowardsOppositeCorner = true
				tearTowardsCentre = false
				randomTearType = false
			case 2 =>
				tearTowardsOutsideCorner = false
				tearTowardsOppositeCorner = false
				tearTowardsCentre = true
				randomTearType = false
			case 3 =>
				tearTowardsOutsideCorner = false
				tearTowardsOppositeCorner = false
				tearTowardsCentre = false
				randomTearType = true
			case _ => println("AnchorsLinkedToCentre, setTearType, value out of range - tearType: " + tearType)			
		}

	}

//convenience method 
	def setRandomTearFactor(f: Range): Unit = {
		randomTear = true
		randomTearFactor = f

	}
//convenience method 
	def setRandomCPsFollow(f: Range): Unit = {
		cpsFollow = true
		randomCPsFollow = true
		randomCPsFollowMultiplier = f
	}

	override def transform(polys: Array[Polygon2D], centreIndex: Int, subdivisionType: Int, sidesTot: Int, sidesPerPoly: Int): Unit = {
		
	sidesTotal = sidesTot//in original polygon (can have any number of sides)
	numSidesPerPoly = sidesPerPoly//in subdivisions (TRI or QUAD - 3 or 4 currently)
		
		if (transforming) {//superclass field

			for(polyIndex <- 0 until polys.length) {//process each poly separately

			    if (Randomise.happens(probability)) {

					tearSides(polys, polyIndex, centreIndex, numSidesPerPoly)

				}

			}

		}

	}

	def getSideAnchorsTri(poly: Polygon2D, centreIndex: Int): Array[Array[Vector2D]] = {

		val sideAnchorBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]] 

		val b1: Vector2D = poly.points(centreIndex-5)//point 3 in a quad
		val b2: Vector2D = poly.points(centreIndex-4)//point 4 in a quad
		sideAnchorBufferPairs += Array(b1, b2)

		val d1: Vector2D = poly.points(poly.points.length-1)//point 11 in a quad
		val d2: Vector2D = poly.points(0)//point 12 in a quad
		sideAnchorBufferPairs += Array(d1, d2)

		sideAnchorBufferPairs.toArray

	}

	def getSideControlPointsTri(poly: Polygon2D, centreIndex: Int): Array[Array[Vector2D]] = {

		val sideControlBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]] 

		val bC1: Vector2D = poly.points(centreIndex-6)//point 2 in a quad
		val bC2: Vector2D = poly.points(centreIndex-3)//point 5 in a quad
		sideControlBufferPairs += Array(bC1, bC2)

		val d1: Vector2D = poly.points(poly.points.length-1)//point 11 in a quad
		val d2: Vector2D = poly.points(0)//point 12 in a quad
		sideControlBufferPairs += Array(d1, d2)

		sideControlBufferPairs.toArray

	}

	def getSideAnchorsQuad(poly: Polygon2D, centreIndex: Int): Array[Array[Vector2D]] = {

		val sideAnchorBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]] 

		val b1: Vector2D = poly.points(centreIndex-5)//point 3 in a quad
		val b2: Vector2D = poly.points(centreIndex-4)//point 4 in a quad
		sideAnchorBufferPairs += Array(b1, b2)

		val d1: Vector2D = poly.points(centreIndex+3)//point 11 in a quad
		val d2: Vector2D = poly.points(centreIndex+4)//point 12 in a quad
		sideAnchorBufferPairs += Array(d1, d2)

		sideAnchorBufferPairs.toArray

	}

	def getSideControlPointsQuad(poly: Polygon2D, centreIndex: Int): Array[Array[Vector2D]] = {

		val sideControlBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]] 

		val bC1: Vector2D = poly.points(centreIndex-6)//point 2 in a quad
		val bC2: Vector2D = poly.points(centreIndex-3)//point 5 in a quad
		sideControlBufferPairs += Array(bC1, bC2)

		val dC1: Vector2D = poly.points(centreIndex+2)//point 10 in a quad
		val dC2: Vector2D = poly.points(centreIndex+5)//point 13 in a quad
		sideControlBufferPairs += Array(dC1, dC2)

		sideControlBufferPairs.toArray

	}


	def tearSides(polys: Array[Polygon2D], polyIndex: Int, centreIndex: Int, numSidesPerPoly: Int): Unit = {

		println("####Tearing sides poly: " + polyIndex)

		var anchors: Array[Array[Vector2D]] = new Array[Array[Vector2D]] (2)//1 for tris, 2 for quads
		var controls: Array[Array[Vector2D]] = new Array[Array[Vector2D]]  (2)//2 for both

		if (numSidesPerPoly == 3) {
			anchors = getSideAnchorsTri(polys(polyIndex), centreIndex)
			controls = getSideControlPointsTri(polys(polyIndex), centreIndex)
		} else if (numSidesPerPoly == 4) {
			anchors = getSideAnchorsQuad(polys(polyIndex), centreIndex)
			controls = getSideControlPointsQuad(polys(polyIndex), centreIndex)
		}


		var tearPos: Vector2D = new Vector2D(0,0)
		var vectorDiff: Vector2D = new Vector2D(0,0)



		for (i <- 0 until anchors.length) {

			var tearF: Double = tearFactor//make a copy of tear factor

			if (randomTear) {//if not a random tear factor value

				tearF = Randomise.range(randomTearFactor.min, randomTearFactor.max)

			}

			if (tearTowardsOutsideCorner) {

				tearPos = Formulas.lerp(anchors(i)(0), polys(polyIndex).points(0), tearF)//negative number spikes (normalised proportions)
				vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)


			} else if (tearTowardsOppositeCorner) {

				if (i == 0) {

					val index: Int = Formulas.circularIndex(centreIndex+4, numSidesPerPoly*4)
					tearPos = Formulas.lerp(anchors(i)(0), polys(polyIndex).points(index), tearF)//negative number spikes (normalised proportions)
					vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)

				} else {

					tearPos = Formulas.lerp(anchors(i)(0), polys(polyIndex).points(centreIndex-4), tearF)//negative number spikes (normalised proportions)
					vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)

				}

			} else if (tearTowardsCentre) {

				tearPos = Formulas.lerp(anchors(i)(0), polys(polyIndex).points(centreIndex), tearF)//negative number spikes (normalised proportions)
				vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)

			} else if (randomTearType) {

				val ran: Int = Randomise.range(0,2)
				if (ran==0) {
					tearPos = Formulas.lerp(anchors(i)(0), polys(polyIndex).points(0), tearF)//negative number spikes (normalised proportions)
					vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)
				} else if (ran==1) {

					if (i == 0) {
						val index: Int = Formulas.circularIndex(centreIndex+4, numSidesPerPoly*4)
						tearPos = Formulas.lerp(anchors(i)(0), polys(polyIndex).points(index), tearF)//negative number spikes (normalised proportions)
						vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)

					} else {

						tearPos = Formulas.lerp(anchors(i)(0), polys(polyIndex).points(centreIndex-4), tearF)//negative number spikes (normalised proportions)
						vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)

					}

				} else if (ran==2) {
					tearPos = Formulas.lerp(anchors(i)(0), polys(polyIndex).points(centreIndex), tearF)//negative number spikes (normalised proportions)
					vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)
				}

			}

			Vector2D.copyValues(tearPos, anchors(i)(0))
			Vector2D.copyValues(tearPos, anchors(i)(1))


			if (cpsFollow) {

				var cP1X: Double = 0
				var cP1Y: Double= 0
				var cP2X: Double = 0
				var cP2Y: Double= 0
					
				if (!randomCPsFollow) {

					cP1X = controls(i)(0).x + (vectorDiff.x * cpsFollowMultiplier)
					cP1Y = controls(i)(0).y + (vectorDiff.y * cpsFollowMultiplier)
					cP2X = controls(i)(1).x + (vectorDiff.x * cpsFollowMultiplier)
					cP2Y = controls(i)(1).y + (vectorDiff.y * cpsFollowMultiplier)

				} else {

					val ranMultiplier: Double = Randomise.range(randomCPsFollowMultiplier.min, randomCPsFollowMultiplier.max)
					cP1X = controls(i)(0).x + (vectorDiff.x * ranMultiplier)
					cP1Y= controls(i)(0).y + (vectorDiff.y * ranMultiplier)
					cP2X= controls(i)(1).x + (vectorDiff.x * ranMultiplier)
					cP2Y = controls(i)(1).y + (vectorDiff.y * ranMultiplier)

				}

				Vector2D.copyValues(new Vector2D(cP1X, cP1Y), controls(i)(0))
				Vector2D.copyValues(new Vector2D(cP2X, cP2Y), controls(i)(1))


			}

		}

	}
}
object AnchorsLinkedToCentre {

	val OUTSIDE_CORNER: Int  = 0
	val OPPOSITE_CORNER: Int  = 1
	val CENTRE: Int  = 2
	val RANDOM: Int  = 3

}