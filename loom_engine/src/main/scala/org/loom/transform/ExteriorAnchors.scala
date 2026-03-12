package org.loom.transform

import org.loom.geometry._
import org.loom.utility._
import scala.collection.mutable.ArrayBuffer

class ExteriorAnchors(spiking: Boolean) extends Transform (spiking) {

	var probability: Double = 100

	var sidesTotal: Int = 4//number of sides in original polygon (prior to subdivision)
	var numSidesPerPoly: Int = 4//default quad subdivision

	//mutually exclusive - select just one
	var spikeAllExteriorAnchors: Boolean = true
	var spikeCornerAnchors: Boolean = false//corner anchors (the zero point in any polygon)
	var spikeMiddleExteriorAnchors: Boolean = false//the 1 and the 3 anchors in a quad polygon

	//mutually exclusive - select just one
	var symmetricalSpike: Boolean = true//sibling anchors are equally affected
	var spikeRight: Boolean = false//only the right sibling is affected
	var spikeLeft: Boolean = false//only the left
	var randomSpikeType: Boolean = false//randomly selects one of the above 3 options

	//mutually exclusive - select just one
	var spikeXY: Boolean = true//spike applied to both x and y
	var spikeX: Boolean = false//only on x
	var spikeY: Boolean = false//only on y

	var spikeFactor: Double = -.3//negative numbers make spiking, positive numbers between 0 and .99 move closer to middle (1)
	var randomSpike: Boolean = false//randomly determine spike factor - this leads to unaligned polygon inside corners
	var randomSpikeFactor: Range = new Range(-.2, .2)//random spiking ranges 

	var cpsFollow: Boolean = false//child control points follow their parent anchors
	var cpsFollowMultiplier: Double = 2//following can be multiplied to accentuate or reverse (negative numbers)
	var randomCPsFollow: Boolean = false//randomly determine following
	var randomCPsFollowMultiplier: Range = new Range(-1.5, 1.5)//in terms of this range

	var cpsSqueeze: Boolean = false//
	var cpsSqueezeFactor: Double = -.2
	var randomCPsSqueeze: Boolean = false
	var randomCPsSqueezeFactor: Range = new Range(-.5, .5)

	/**
	 * spike is called from pointsTransform
	 * @polys the set of subdivided polys
	 * @centreIndex the centre indext in each poly's points (length/2 in quad subdivision)
	 * the centre is needed for all spike calculations, which either push points away from the centre or draw them towards it
	 */

	override def toString(): String = "this is a spike transform and it is: " + spiking


	//convenience method for initialising standard values
	def adjustStandardFields (p: Double, sF: Double, cpsF: Boolean, cpsFM: Double, squeeze: Boolean, squeezeF: Double): Unit = {
		probability = p
		spikeFactor = -(sF)//reverses spike factor so that positive parameters spike and negative parameters contract (which is actually the other way around without this switch)
		cpsFollow = cpsF
		cpsFollowMultiplier = cpsFM
		cpsSqueeze = squeeze
		cpsSqueezeFactor = squeezeF
	}
//convenience method 
	def setWhichSpike(which: Int): Unit = {

		which match {
			case 0 => 
				spikeAllExteriorAnchors = true
				spikeCornerAnchors = false
				spikeMiddleExteriorAnchors = false
			case 1 =>
				spikeAllExteriorAnchors = false
				spikeCornerAnchors = true
				spikeMiddleExteriorAnchors = false
			case 2 =>
				spikeAllExteriorAnchors = false
				spikeCornerAnchors = false
				spikeMiddleExteriorAnchors = true
			case _ => println("ExteriorAnchors, setWhichSpike, value out of range - which: " + which)			
		}

	}

//convenience method 
	def setSpikeType(spikeType: Int): Unit = {

		spikeType match {
			case 0 => 
				symmetricalSpike = true
				spikeRight = false
				spikeLeft = false
				randomSpikeType = false
			case 1 =>
				symmetricalSpike = false
				spikeRight = true
				spikeLeft = false
				randomSpikeType = false
			case 2 =>
				symmetricalSpike = false
				spikeRight = false
				spikeLeft = true
				randomSpikeType = false
			case 3 =>
				symmetricalSpike = false
				spikeRight = false
				spikeLeft = false
				randomSpikeType = true
			case _ => println("ExteriorAnchors, setSpikeType, value out of range - spikeType: " + spikeType)			
		}

	}

//convenience method 
	def setSpikeAxis(spikeAxis: Int): Unit = {

		spikeAxis match {
			case 0 => 
				spikeXY = true
				spikeX = false
				spikeY = false
			case 1 =>
				spikeXY = false
				spikeX = true
				spikeY = false
			case 2 =>
				spikeXY = false
				spikeX = false
				spikeY = true
			case _ => println("ExteriorAnchors, setSpikeAxis, value out of range - spikeAxis: " + spikeAxis)			
		}

	}

//convenience method 
	def setRandomSpikeFactor(f: Range): Unit = {
		randomSpike = true
		randomSpikeFactor = f

	}
//convenience method 
	def setRandomCPsFollow(f: Range): Unit = {
		cpsFollow = true
		randomCPsFollow = true
		randomCPsFollowMultiplier = f
	}

	//convenience method 
	def setRandomCPsSqueeze(f: Range): Unit = {
		randomCPsSqueeze = true
		randomCPsSqueezeFactor = f

	}

	override def transform(polys: Array[Polygon2D], centreIndex: Int, subdivisionType: Int, sidesTot: Int, sidesPerPoly: Int): Unit = {
		
	sidesTotal = sidesTot//in original polygon (can have any number of sides)
	numSidesPerPoly = sidesPerPoly//in subdivisions (TRI or QUAD - 3 or 4 currently)
	
		if (transforming) {//superclass field

		    for(polyIndex <- 0 until polys.length) {//process each poly separately

			    if (Randomise.happens(probability)) {

					spike(polys, polyIndex, centreIndex)

				}
			}

		}

	}

	//gets all anchors pairs bar the centre ones

	def getExteriorAnchors(poly: Polygon2D, centreIndex: Int): Array[Array[Vector2D]] = {
		//initArray for tri (0,3,4,11), for quad (0,3,4,11, 12, 15)
		val initArray: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]//to store anchors in a linear array
		for (i <- 0 until poly.points.length) {
			if (i%4 == 0 || i%4 == 3) {//if points 0, 3 in every spline
				if (i != centreIndex || i != centreIndex -1) {//if not centre points
					initArray += poly.points(i)
				}
			}
		}
		val pairs: Array[Array[Vector2D]] = new Array[Array[Vector2D]](initArray.length/2)//to arrange in pairs
		pairs(0) = Array(initArray(initArray.length-1), initArray(0))//first pair is composed of last and first points in poly
		var count: Int = 1
		for (k <- 1 until initArray.length by 2) {//iterate from 1 to length of init array in twos (pairs)
			if (k != initArray.length-1) {//if not at the last point that has already been position in pair 0
				val pair: Array[Vector2D] = new Array[Vector2D](2)
				pair(0) = initArray(k)//1, 3, etc. in init arrray 
				pair(1) = initArray(k+1)//2, 4, etc.

				pairs(count) = pair
				count+=1
			}

		}
		pairs

	}

	//gets pair of control points that lie on either side of external anchors
	//tri: points 10,1 & 2,5
	//quads: points 14,1 & 2,5 & 10,13

	def getExteriorAnchorsControlPoints(poly: Polygon2D, centreIndex: Int): Array[Array[Vector2D]] = {
		//initArray for tri (1,2,5,10), for quad (1,2,5,10,13,14))
		val initArray: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]//to store anchors in a linear array
		for (i <- 0 until poly.points.length) {
			if (i%4 == 1 || i%4 == 2) {//if points 1 or 2 in every spline
				if (i != centreIndex-2 || i != centreIndex +1) {//if not control points surrounding centre points
					initArray += poly.points(i)
				}
			}
		}
		val pairs: Array[Array[Vector2D]] = new Array[Array[Vector2D]](initArray.length/2)//to arrange in pairs
		pairs(0) = Array(initArray(initArray.length-1), initArray(0))//first pair is composed of last and first points in poly
		var count: Int = 1
		for (k <- 1 until initArray.length by 2) {//iterate from 1 to length of init array in twos (pairs)
			if (k != initArray.length-1) {//if not at the last point that has already been position in pair 0
				val pair: Array[Vector2D] = new Array[Vector2D](2)
				pair(0) = initArray(k)//1, 3, etc. in init arrray 
				pair(1) = initArray(k+1)//2, 4, etc.

				pairs(count) = pair
				count+=1
			}

		}
		pairs

	}


	def spike(polys: Array[Polygon2D], polyIndex: Int, centreIndex: Int): Unit = {

		var anchors: Array[Array[Vector2D]] = null
		var controls: Array[Array[Vector2D]] = null

		if (spikeAllExteriorAnchors) {//all anchor points and controls apart from the ones that correspond to the older (larger polygon) centre

			anchors = getExteriorAnchors(polys(polyIndex), centreIndex)
			controls = getExteriorAnchorsControlPoints(polys(polyIndex), centreIndex)

		} else if (spikeCornerAnchors) {//just the first and last anchor points and their associated controls

			val firstAnchor: Vector2D = polys(polyIndex).points(0)
			val lastAnchor: Vector2D = polys(polyIndex).points(polys(polyIndex).points.length-1)
			anchors = Array(Array(firstAnchor, lastAnchor))

			val firstControl: Vector2D = polys(polyIndex).points(1)
			val lastControl: Vector2D = polys(polyIndex).points(polys(polyIndex).points.length-2)
			controls = Array(Array(firstControl, lastControl))

		} else if (spikeMiddleExteriorAnchors) {//anchors points and controls not linked to outside corner or centre

			val allAnchors: Array[Array[Vector2D]] = getExteriorAnchors(polys(polyIndex), centreIndex)
			val allAnchorsBuffer: ArrayBuffer[Array[Vector2D]] = ArrayBuffer.from(allAnchors)//copy anchor array to an ArrayBuffer
			allAnchorsBuffer.remove(0)//remove the first item (the corner)
			anchors = allAnchorsBuffer.toArray

			val allControls: Array[Array[Vector2D]] = getExteriorAnchorsControlPoints(polys(polyIndex), centreIndex)
			val allControlsBuffer: ArrayBuffer[Array[Vector2D]] = ArrayBuffer.from(allControls)
			allControlsBuffer.remove(0)
			controls = allControlsBuffer.toArray


		} else {
			println("Spike transformation: no anchor spike type selected")
		}

		var spikePos: Vector2D = new Vector2D(0,0)
		var vectorDiff: Vector2D = new Vector2D(0,0)

		var ranSpikeOutcome: Int = 0//need this to ensure proper control point following depending upon spike mode - zero indicates symmetrical, 1 equals spikeRight, 2 spikeLeft

		for (anchorPair <- 0 until anchors.length) {

			if (!randomSpike) {//if not a random spike factor value

				spikePos = Formulas.lerp(anchors(anchorPair)(0), polys(polyIndex).points(centreIndex), spikeFactor)//negative number spikes (normalised proportions)
				vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(anchorPair)(0), spikePos)

			} else {

				val ranFactor: Double = Randomise.range(randomSpikeFactor.min, randomSpikeFactor.max)
				spikePos = Formulas.lerp(anchors(anchorPair)(0), polys(polyIndex).points(centreIndex), ranFactor)
				vectorDiff = Formulas.differenceBetweenTwoVectors(anchors(anchorPair)(0), spikePos)

			}

			if (spikeXY) {

				if (symmetricalSpike) {
					
					Vector2D.copyValues(spikePos, anchors(anchorPair)(0))
					Vector2D.copyValues(spikePos, anchors(anchorPair)(1))
		
				} else if (spikeRight) {

					Vector2D.copyValues(spikePos, anchors(anchorPair)(0))

				} else if (spikeLeft) {

					Vector2D.copyValues(spikePos, anchors(anchorPair)(1))

				} else if (randomSpikeType) {

					val ran: Int = Randomise.range(0,2)
					if (ran==0) {
						Vector2D.copyValues(spikePos, anchors(anchorPair)(0))
						Vector2D.copyValues(spikePos, anchors(anchorPair)(1))
						ranSpikeOutcome = 0
					} else if (ran==1) {
						Vector2D.copyValues(spikePos, anchors(anchorPair)(0))
						ranSpikeOutcome = 1
					} else if (ran==2) {
						Vector2D.copyValues(spikePos, anchors(anchorPair)(1))
						ranSpikeOutcome = 2
					}

				} else {
					println("Spike - spikeAllExteriorAnchors is true, but no spike mode selected")
				}

			} else if (spikeX) {

				if (symmetricalSpike) {

					anchors(anchorPair)(0).x = spikePos.x
					anchors(anchorPair)(1).x = spikePos.x			
		
				} else if (spikeRight) {

					anchors(anchorPair)(0).x = spikePos.x

				} else if (spikeLeft) {

					anchors(anchorPair)(1).x = spikePos.x

				} else if (randomSpikeType) {

					val ran: Int = Randomise.range(0,2)
					if (ran==0) {
						anchors(anchorPair)(0).x = spikePos.x
						anchors(anchorPair)(1).x = spikePos.x
						ranSpikeOutcome = 0	
					} else if (ran==1) {
						anchors(anchorPair)(0).x = spikePos.x
						ranSpikeOutcome = 1
					} else if (ran==2) {
						anchors(anchorPair)(1).x = spikePos.x
						ranSpikeOutcome = 2
					}

				} else {
					println("Spike - spikeAllExteriorAnchors is true, but no spike mode selected")
				}

			} else if (spikeY) {

				if (symmetricalSpike) {
					
					anchors(anchorPair)(0).y = spikePos.y
					anchors(anchorPair)(1).y = spikePos.y
		
				} else if (spikeRight) {

					anchors(anchorPair)(0).y = spikePos.y

				} else if (spikeLeft) {

					anchors(anchorPair)(1).y = spikePos.y

				} else if (randomSpikeType) {

					val ran: Int = Randomise.range(0,2)
					if (ran==0) {
						anchors(anchorPair)(0).y = spikePos.y
						anchors(anchorPair)(1).y = spikePos.y
						ranSpikeOutcome = 0
					} else if (ran==1) {
						anchors(anchorPair)(0).y = spikePos.y
						ranSpikeOutcome = 1
					} else if (ran==2) {
						anchors(anchorPair)(1).y = spikePos.y
						ranSpikeOutcome = 2
					}

				} else {
					println("Spike - spikeAllExteriorAnchors is true, but no spike mode selected")
				}

			}

			//CONTROL POINTS FOLLOW ANCHOR POINTS
			

			if (cpsFollow) {

				var cP1X: Double = 0
				var cP1Y: Double= 0
				var cP2X: Double = 0
				var cP2Y: Double= 0
					
				if (!randomCPsFollow) {

					cP1X = controls(anchorPair)(0).x + (vectorDiff.x * cpsFollowMultiplier)
					cP1Y = controls(anchorPair)(0).y + (vectorDiff.y * cpsFollowMultiplier)
					cP2X = controls(anchorPair)(1).x + (vectorDiff.x * cpsFollowMultiplier)
					cP2Y = controls(anchorPair)(1).y + (vectorDiff.y * cpsFollowMultiplier)

				} else {

					val ranMultiplier: Double = Randomise.range(randomCPsFollowMultiplier.min, randomCPsFollowMultiplier.max)
					cP1X = controls(anchorPair)(0).x + (vectorDiff.x * ranMultiplier)
					cP1Y= controls(anchorPair)(0).y + (vectorDiff.y * ranMultiplier)
					cP2X= controls(anchorPair)(1).x + (vectorDiff.x * ranMultiplier)
					cP2Y = controls(anchorPair)(1).y + (vectorDiff.y * ranMultiplier)

				}


				if (spikeXY) {

					if (symmetricalSpike) {

						Vector2D.copyValues(new Vector2D(cP1X, cP1Y), controls(anchorPair)(0))
						Vector2D.copyValues(new Vector2D(cP2X, cP2Y), controls(anchorPair)(1))

					} else if (spikeRight) {

						Vector2D.copyValues(new Vector2D(cP1X, cP1Y), controls(anchorPair)(0))

					} else if (spikeLeft) {

						Vector2D.copyValues(new Vector2D(cP2X, cP2Y), controls(anchorPair)(1))

					} else if (randomSpikeType) {//need to remember anchor point spike type (symmetrical, etc.)

						if (ranSpikeOutcome == 0) {//symmetrical

							Vector2D.copyValues(new Vector2D(cP1X, cP1Y), controls(anchorPair)(0))
							Vector2D.copyValues(new Vector2D(cP2X, cP2Y), controls(anchorPair)(1))

						} else if (ranSpikeOutcome == 1) {//spikeRight

							Vector2D.copyValues(new Vector2D(cP1X, cP1Y), controls(anchorPair)(0))

						} else if (ranSpikeOutcome == 2) {//spikeLeft

							Vector2D.copyValues(new Vector2D(cP2X, cP2Y), controls(anchorPair)(1))

						}

					}

				} else if (spikeX) {

					if (symmetricalSpike) {

						controls(anchorPair)(0).x = cP1X
						controls(anchorPair)(1).x = cP2X


					} else if (spikeRight) {

						controls(anchorPair)(0).x = cP1X

					} else if (spikeLeft) {

						controls(anchorPair)(1).x = cP2X

					} else if (randomSpikeType) {//need to remember anchor point spike type (symmetrical, etc.)

						if (ranSpikeOutcome == 0) {//symmetrical

							controls(anchorPair)(0).x = cP1X
							controls(anchorPair)(1).x = cP2X

						} else if (ranSpikeOutcome == 1) {//spikeRight

							controls(anchorPair)(0).x = cP1X

						} else if (ranSpikeOutcome == 2) {//spikeLeft

							controls(anchorPair)(1).x = cP2X

						}

					}
				} else if (spikeY) {

					if (symmetricalSpike) {

						controls(anchorPair)(0).y = cP1Y
						controls(anchorPair)(1).y = cP2Y

					} else if (spikeRight) {

						controls(anchorPair)(0).y = cP1Y

					} else if (spikeLeft) {

						controls(anchorPair)(1).y = cP2Y

					} else if (randomSpikeType) {//need to remember anchor point spike type (symmetrical, etc.)

						if (ranSpikeOutcome == 0) {//symmetrical

							controls(anchorPair)(0).y = cP1Y
							controls(anchorPair)(1).y = cP2Y

						} else if (ranSpikeOutcome == 1) {//spikeRight

							controls(anchorPair)(0).y = cP1Y

						} else if (ranSpikeOutcome == 2) {//spikeLeft

							controls(anchorPair)(1).y = cP2Y

						}

					}
				}

				if (cpsSqueeze) {//decreasing (squeezing) or increasing distance between two control points on either side of an anchor

					var squeezePosA: Vector2D = new Vector2D(0,0)
					var squeezePosB: Vector2D = new Vector2D(0,0)

					if (!randomCPsSqueeze) {

						squeezePosA = Formulas.lerp(controls(anchorPair)(0), controls(anchorPair)(1), cpsSqueezeFactor)
						squeezePosB = Formulas.lerp(controls(anchorPair)(1), controls(anchorPair)(0), cpsSqueezeFactor)

					} else {

						val ranSqueezeFactor: Double = Randomise.range(randomCPsSqueezeFactor.min, randomCPsSqueezeFactor.max)
						squeezePosA = Formulas.lerp(controls(anchorPair)(0), controls(anchorPair)(1), ranSqueezeFactor)
						squeezePosB = Formulas.lerp(controls(anchorPair)(1), controls(anchorPair)(0), ranSqueezeFactor)

					}
					if (spikeXY) {

						if (symmetricalSpike) {

							Vector2D.copyValues(squeezePosA, controls(anchorPair)(0))
							Vector2D.copyValues(squeezePosB, controls(anchorPair)(1))

						} else if (spikeRight) {

							Vector2D.copyValues(squeezePosA, controls(anchorPair)(0))

						} else if (spikeLeft) {

							Vector2D.copyValues(squeezePosA, controls(anchorPair)(1))

						} else if (randomSpike) {

							if (ranSpikeOutcome == 0) {//symmetrical

								Vector2D.copyValues(squeezePosA, controls(anchorPair)(0))
								Vector2D.copyValues(squeezePosB, controls(anchorPair)(1))

							} else if (ranSpikeOutcome == 1) {//spikeRight

								Vector2D.copyValues(squeezePosA, controls(anchorPair)(0))

							} else if (ranSpikeOutcome == 2) {//spikeLeft

								Vector2D.copyValues(squeezePosB, controls(anchorPair)(1))

							}

						}

					} else if (spikeX) {

						if (symmetricalSpike) {

							controls(anchorPair)(0).x = squeezePosA.x
							controls(anchorPair)(1).x = squeezePosB.x

						} else if (spikeRight) {

							controls(anchorPair)(0).x = squeezePosA.x

						} else if (spikeLeft) {

							controls(anchorPair)(1).x = squeezePosB.x

						} else if (randomSpike) {

							if (ranSpikeOutcome == 0) {//symmetrical

								controls(anchorPair)(0).x = squeezePosA.x
								controls(anchorPair)(1).x = squeezePosB.x

							} else if (ranSpikeOutcome == 1) {//spikeRight

								controls(anchorPair)(0).x = squeezePosA.x

							} else if (ranSpikeOutcome == 2) {//spikeLeft

								controls(anchorPair)(1).x = squeezePosB.x

							}

						}						

					} else if (spikeY) {

						if (symmetricalSpike) {

							controls(anchorPair)(0).y = squeezePosA.y
							controls(anchorPair)(1).y = squeezePosB.y

						} else if (spikeRight) {

							controls(anchorPair)(0).y = squeezePosA.y

						} else if (spikeLeft) {

							controls(anchorPair)(1).y = squeezePosB.y

						} else if (randomSpike) {

							if (ranSpikeOutcome == 0) {//symmetrical

								controls(anchorPair)(0).y = squeezePosA.y
								controls(anchorPair)(1).y = squeezePosB.y

							} else if (ranSpikeOutcome == 1) {//spikeRight

								controls(anchorPair)(0).y = squeezePosA.y

							} else if (ranSpikeOutcome == 2) {//spikeLeft

								controls(anchorPair)(1).y = squeezePosB.y

							}

						}						

					} 
				}

			}


		}	

	}

}


object ExteriorAnchors {

	val ALL: Int = 0
	val CORNERS: Int  = 1
	val MIDDLES: Int  = 2

	val SYMMETRICAL: Int = 0
	val RIGHT: Int  = 1
	val LEFT: Int  = 2
	val RANDOM: Int  = 3

	val SPIKE_XY: Int = 0
	val SPIKE_X: Int = 1
	val SPIKE_Y: Int = 2

}