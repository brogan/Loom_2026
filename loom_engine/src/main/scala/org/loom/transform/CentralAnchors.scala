package org.loom.transform

import org.loom.geometry._
import org.loom.utility._
import scala.collection.mutable.ArrayBuffer



class CentralAnchors(tearing: Boolean) extends Transform (tearing) {

	var probability: Double = 100

	var sidesTotal: Int = 4//number of sides in original polygon (prior to subdivision) - here set to quad by default
	var numSidesPerPoly: Int = 4//default quad subdivision

	var tearXY: Boolean = true
	var tearX: Boolean = false
	var tearY: Boolean = false
	var randomTearAxis: Boolean = false

	var tearDiagonal: Boolean = true//tear diagonally out from the centre (makes smooth tears)
	var tearLeft: Boolean = false//tear towards next anchor
	var tearRight: Boolean = false//tear towards previous anchor
	var ranTearDirection: Boolean = false//tear at some random point between left and right anchors

	var tearFactor: Double = .2//small fractions work best
	var randomTear: Boolean = false//randomly determine tear factor - this leads to unaligned polygon inside corners
	var randomTearFactor: Range = new Range(-.2, .2)//random tearing ranges 

	var cpsFollow: Boolean = false//child control points follow their parent anchors
	var cpsFollowMultiplier: Double = -7//following can be multiplied to accentuate or reverse (negative numbers)
	var randomCPsFollow: Boolean = false//randomly determine following
	var randomCPsFollowMultiplier: Range = new Range(-1.5, 1.5)//in terms of this range

	var allPointsFollowCentre: Boolean = false//remaining poly points follow same vector as adjusted centre has moved from original centre
	var invertedFollowCentre: Boolean = false//remaining following can either correspond to centre adjustment or be opposite (which actually produces 4 different outcomes)

	override def toString(): String = "this is a tear transform and it is: " + tearing

	//convenience method for initialising standard values
	def adjustStandardFields (p: Double, tF: Double, cpsF: Boolean, cpsFM: Double, all: Boolean, inv: Boolean): Unit = {
		probability = p
		tearFactor = tF
		cpsFollow = cpsF
		cpsFollowMultiplier = cpsFM
		allPointsFollowCentre = all
		invertedFollowCentre = inv
	}
//convenience method 
	def setTearAxis(tearAxis: Int): Unit = {

		tearAxis match {
			case 0 => 
				tearXY = true
				tearX = false
				tearY = false
				randomTearAxis = false
			case 1 =>
				tearXY = false
				tearX = true
				tearY = false
				randomTearAxis = false
			case 2 =>
				tearXY = false
				tearX = false
				tearY = true
				randomTearAxis = false
			case 3 =>
				tearXY = false
				tearX = false
				tearY = false
				randomTearAxis = true
			case _ => println("CentralAnchors, setTearAxis, value out of range - tearAxis: " + tearAxis)			
		}

	}
//convenience method 
	def setTearDirection(tearDirection: Int): Unit = {

		tearDirection match {
			case 4=> 
				tearDiagonal = true
				tearLeft = false
				tearRight = false
				ranTearDirection = false
			case 5 =>
				tearDiagonal = false
				tearLeft = true
				tearRight = false
				ranTearDirection = false
			case 6 =>
				tearDiagonal = false
				tearLeft = false
				tearRight = true
				ranTearDirection = false
			case 7 =>
				tearDiagonal = false
				tearLeft = false
				tearRight = false
				ranTearDirection = true
			case _ => println("CentralAnchors, setTearDirection, value out of range - tearDirection: " + tearDirection)			
		}

	}
//convenience method 
	def setRandomTearFactor(f: Range): Unit = {
		randomTear = true
		randomTearFactor = f

	}
//convenience method 
	def setRandomCPsFollow(f: Range): Unit = {
		randomCPsFollow = true
		randomCPsFollowMultiplier = f
	}

	override def transform(polys: Array[Polygon2D], centreIndex: Int, subdivisionType: Int, sidesTot: Int, sidesPerPoly: Int): Unit = {
		
	sidesTotal = sidesTot//in original polygon (can have any number of sides)
	numSidesPerPoly = sidesPerPoly//in subdivisions (TRI or QUAD - 3 or 4 currently)

		if (transforming) {//superclass field


		    if (Randomise.happens(probability)) {

				tearCentre(polys, centreIndex)

			}

		}

	}

	def getCentreAnchors(polys: Array[Polygon2D], centreIndex: Int): Array[Array[Vector2D]] = {

		val centreAnchorBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]] 

		for(poly <- polys) {

			val a1: Vector2D = poly.points(centreIndex-1)
			val a2: Vector2D = poly.points(centreIndex)
			centreAnchorBufferPairs += Array(a1, a2)

		}
		centreAnchorBufferPairs.toArray

	}

	def getCentreControlPoints(polys: Array[Polygon2D], centreIndex: Int): Array[Array[Vector2D]] = {

		val centreControlBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]] 

		for(poly <- polys) {

			val c1: Vector2D = poly.points(centreIndex-2)
			val c2: Vector2D = poly.points(centreIndex+1)
			centreControlBufferPairs += Array(c1, c2)

		}
		centreControlBufferPairs.toArray

	}

	//here is where difference between quad and tri subdivision is handled
	//quad refereces 4 outside corner points for shifting the centre
	//tri references the notional middle points on the 3 outside lines
	def getOutsideRefs(polys: Array[Polygon2D], centreIndex: Int): Array[Vector2D] = {

		val refs: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]

		if (numSidesPerPoly == 3) {//TRI subdivision

			for(i <- 0 until polys.length) {

				if (tearDiagonal) {

					refs += Formulas.lerp(polys(i).points(0), polys(i).points(3), .5)

				} else if (tearLeft) {

					refs += polys(i).points(0)

				} else if (tearRight) {

					refs += polys(i).points(3)

				} else if (ranTearDirection) {

					val ran: Double = Randomise.range(0,1)
					refs += Formulas.lerp(polys(i).points(0), polys(i).points(3), ran)

				}

			}

		} else if (numSidesPerPoly == 4) {//QUAD subdivision

			for(i <- 0 until polys.length) {

				if (tearDiagonal) {

					refs += polys(i).points(0)

				} else if (tearLeft) {

					refs += polys(i).points(centreIndex+4)

				} else if (tearRight) {

					refs += polys(i).points(centreIndex-4)

				} else if (ranTearDirection) {

					val ran: Double = Randomise.range(0,1)
					refs += Formulas.lerp(polys(i).points(centreIndex+4), polys(i).points(centreIndex-4), ran)

				}

			}



		}

		refs.toArray

	}

	def tearCentre(polys: Array[Polygon2D], centreIndex: Int): Unit = {

		val oldCentre: Vector2D = polys(0).points(centreIndex).clone//just to store original centre prior to adjusting (needed to determine vector if all points follow)

		val anchors: Array[Array[Vector2D]] = getCentreAnchors(polys: Array[Polygon2D], centreIndex: Int)
		val controls: Array[Array[Vector2D]] = getCentreControlPoints(polys: Array[Polygon2D], centreIndex: Int)
		val outsideRefs: Array[Vector2D] = getOutsideRefs(polys: Array[Polygon2D], centreIndex: Int)

		var tearPos: Vector2D = new Vector2D(0,0)
		var vectorDiff: Vector2D = new Vector2D(0,0)

		var ranTearOutcome: Int = 0

		for (i <- 0 until anchors.length) {

			if (!randomTear) {//if not a random tear factor value

				tearPos = Formulas.lerp(anchors(i)(0), outsideRefs(i), tearFactor)//negative number spikes (normalised proportions)
				vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)

			} else {

				val ranFactor: Double = Randomise.range(randomTearFactor.min, randomTearFactor.max)
				tearPos = Formulas.lerp(anchors(i)(0), outsideRefs(i), ranFactor)
				vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(i)(0), tearPos)

			}

			if(tearXY) {

				Vector2D.copyValues(tearPos, anchors(i)(0))
				Vector2D.copyValues(tearPos, anchors(i)(1))

			} else if (tearX) {

				anchors(i)(0).x = tearPos.x
				anchors(i)(1).x = tearPos.x

			} else if (tearY) {


				anchors(i)(0).y = tearPos.y
				anchors(i)(1).y = tearPos.y

			} else if (randomTearAxis) {

					val ran: Int = Randomise.range(0,2)
					if (ran==0) {
						Vector2D.copyValues(tearPos, anchors(i)(0))
						Vector2D.copyValues(tearPos, anchors(i)(1))
						ranTearOutcome = 0
					} else if (ran==1) {
						anchors(i)(0).x = tearPos.x
						anchors(i)(1).x = tearPos.x
						ranTearOutcome = 1
					} else if (ran==2) {
						anchors(i)(0).y = tearPos.y
						anchors(i)(1).y = tearPos.y
						ranTearOutcome = 2
					}				

			} else {

				println("Tear transformation anchors: no tear type selected")

			}

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

				if(tearXY) {

					Vector2D.copyValues(new Vector2D(cP1X, cP1Y), controls(i)(0))
					Vector2D.copyValues(new Vector2D(cP2X, cP2Y), controls(i)(1))

				} else if (tearX) {

					controls(i)(0).x = cP1X
					controls(i)(1).x = cP2X

				} else if (tearY) {

					controls(i)(0).y = cP1Y
					controls(i)(1).y = cP2Y

				} else if (randomTearAxis) {

						if (ranTearOutcome==0) {
							Vector2D.copyValues(new Vector2D(cP1X, cP1Y), controls(i)(0))
							Vector2D.copyValues(new Vector2D(cP2X, cP2Y), controls(i)(1))
						} else if (ranTearOutcome==1) {
							controls(i)(0).x = cP1X
							controls(i)(1).x = cP2X
						} else if (ranTearOutcome==2) {
							controls(i)(0).y = cP1Y
							controls(i)(1).y = cP2Y
						}				

				} else {

					println("Tear transformation cps: no tear type selected")

				}

			}
			if (allPointsFollowCentre) {
				var vectorDiffC: Vector2D = new Vector2D(0,0)
				if (invertedFollowCentre) {
					vectorDiffC = Formulas.differenceBetweenTwoVectors(polys(i).points(centreIndex), oldCentre)
				} else {
					vectorDiffC = Formulas.differenceBetweenTwoVectors(oldCentre, polys(i).points(centreIndex))
				}
				
				println("vectorDiffC: "+ vectorDiffC.toString)

				for (p <- 0 until polys(i).points.length) {
					if (p != centreIndex -2 || p != centreIndex -1 || p != centreIndex +1 || p != centreIndex) {//not centre or child control points
						Vector2D.copyValues(Vector2D.add(polys(i).points(p), vectorDiffC), polys(i).points(p))
					}
				}

			}

		}

	}

}

object CentralAnchors {

	val TEAR_XY: Int = 0
	val TEAR_X: Int  = 1
	val TEAR_Y: Int  = 2
	val RANDOM_TEAR_AXIS: Int  = 3

	val TEAR_DIAGONAL: Int  = 4
	val TEAR_LEFT: Int  = 5
	val TEAR_RIGHT: Int  = 6
	val RANDOM_TEAR_DIRECTION: Int  = 7

	val RANDOM_CONTROL_POINTS_FOLLOW: Int  = 8


}