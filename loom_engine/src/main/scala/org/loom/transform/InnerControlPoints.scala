
package org.loom.transform

import org.loom.geometry._
import org.loom.utility._
import scala.collection.mutable.ArrayBuffer



class InnerControlPoints(curving: Boolean) extends Transform (curving) {

	var probability: Double = 100

	var sidesTotal: Int = 4//number of sides in original polygon (prior to subdivision)
	var numSidesPerPoly: Int = 4//default quad subdivision

	//QUADS
	//mainly relevant for quads - makes inner control point relate external control points on outer line
    var referToOuter: Boolean = false//mainly relevant for quads, best to turn off for tris because angle is too radical
    var followOuter: Boolean = false//outside inner control points are placed on the opposite vector relative to the anchor of the external control points (to make things smooth)
    var exaggerateOuter: Boolean = false//the left 45 degree vector from external control point
    var counterOuter: Boolean = false//the 45 degree vector from external control point

    //the next two are only relevant in following scenarios
    //if one set of multipliers is even and the other odd then they both move in same direction
    //if both even or both odd then then move in opposite direction
    var outerMultiplier: Vector2D = new Vector2D(1,1)//affects outer inner control points
    var innerMultiplier: Vector2D = new Vector2D(1,1)//affects inner inner control points

    //TRIS
    //mainly used by tris to avoid standard quad following (see just above)
    var outerRatio: Double = 1.1//normally takes a value between -.5 and .5 to place outer control point either to the left or the right of the line between relevant external anchor and centre
    var innerRatio: Double = -.15//normally takes a value between -.5 and .5 to place inner control point either to the left or the right of the line between relevant external anchor and centre
    var randomRatio: Boolean = false
    var ranOuterRatio: Range = new Range(-.5, .5)//specify a random outer ratio
    var ranInnerRatio: Range = new Range(-.5, .5)//specify a random inner ratio

    var commonLine: Boolean = true//adjoining control points are identically postioned (or not) - if not creates inner overlapping shapes

    //mutually exclusive
    var evenCommon: Boolean = true//common line taken from left poly of internal line 
    var oddCommon: Boolean = false//common line taken from right poly of internal line 
    var ranCommon: Boolean = false//selects either even or odd




	override def toString(): String = "this is a inside cur transform and it is: " + curving

	//convenience methods
	//sets inner line curve to respond to adjacent outer curve
	//if followOuter then curve matches outer curve (cps placed on opposite vectors relative to parent anchors so that they are in line)
	//if exaggerateOuter then response is exaggerated (45 degrees in quads)
    //if counterOuter it is opposed
	def setQuadReferToOuter(approach: Int): Unit = {
		referToOuter = true
		approach match {
			case 0 => 
				followOuter = true
				exaggerateOuter = false
				counterOuter = false
			case 1 =>
				followOuter = false
				exaggerateOuter = true
				counterOuter = false
			case 2 =>
				followOuter = false
				exaggerateOuter = false
				counterOuter = true
			case _ => println("InnerControlPoints, setRelationToOuter, value out of range - approach: " + approach)			
		}

	}
	def setQuadMultipliers(inner: Vector2D, outer: Vector2D): Unit = {
		outerMultiplier = outer
		innerMultiplier = inner
	}
	def setTriRatios(inner: Double, outer: Double): Unit = {
		outerRatio = outer
		innerRatio = inner
	}
	def setRandomTriRatios(inner: Range, outer: Range): Unit = {
		randomRatio = true
		ranOuterRatio = outer
		ranInnerRatio = inner
	}
	def setCommonLine(common_type: Int): Unit = {
		commonLine = true
		common_type match {
			case 0 => 
				evenCommon = true
				oddCommon = false
				ranCommon = false
			case 1 =>
				evenCommon = false
				oddCommon = true
				ranCommon = false
			case 2 =>
				evenCommon = false
				oddCommon = false
				ranCommon = true
			case _ => println("InnerControlPoints, setCommonLine, value out of range - common_type: " + common_type)	
		}	
	}
	//end convenience methods 

	override def transform(polys: Array[Polygon2D], centreIndex: Int, subdivisionType: Int, sidesTot: Int, sidesPerPoly: Int): Unit = {
		
	sidesTotal = sidesTot//in original polygon (can have any number of sides)
	numSidesPerPoly = sidesPerPoly//in subdivisions (TRI or QUAD - 3 or 4 currently)

		if (transforming) {//superclass field


		    if (Randomise.happens(probability)) {

		    	if (numSidesPerPoly == 3) {
		    		println("Tri inside curves")
					curveTri(polys, centreIndex)

		    	} else if (numSidesPerPoly == 4) {
		    		println("Quad inside curves")
					curveQuad(polys, centreIndex)

		    	}


			}

		}

	}

	/**
	 * 
	 * Inner control points organised as 6 or 8 pairs of adjoining control points, 2 pairs for each internal line
	 * Note that this conceives the transformation in terms of the overall set of polys, not the each poly individually
	 * So think of each internal line in a quad subdivision as A, B, C & possibly D (quad)
	 * The first pair of inner control points in A is the external pair (controls(0)(0)), the internal pair is the second pair (controls(0)(1))
	 * the B spline is (controls(1)(0) & (controls(1)(1), etc.
	 * relevant point indexes are calculated in terms of centre index, which should be poly.points/2 (8 for a quad)
	 */
	def getInnerControlPoints(polys: Array[Polygon2D], centreIndex: Int): Array[Array[Vector2D]] = {

		val centreControlBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]] 
		val initialBuffer: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]

		for(poly <- polys) {

			initialBuffer += poly.points(centreIndex-3)
			initialBuffer += poly.points(centreIndex-2)
			initialBuffer += poly.points(centreIndex+1)
			initialBuffer += poly.points(centreIndex+2)

		}

		var bufferIndex: Int  = 0

		for (_ <- 0 until sidesTotal) {
			
			centreControlBufferPairs += Array(initialBuffer(bufferIndex), initialBuffer(Formulas.circularIndex(bufferIndex+7, sidesTotal*4)))
			centreControlBufferPairs += Array(initialBuffer(bufferIndex+1), initialBuffer(Formulas.circularIndex(bufferIndex+6, sidesTotal*4)))
			bufferIndex+=4

		}
		centreControlBufferPairs.toArray

	}

	/**
	 * Side anchors organised as 6 or 8 pairs of adjoining anchors, 2 pairs for each inner (not outside corner) anchor position - A, B, C, D
	 * THe first pair for any side are the anchors related to external lines, the other pair relates to internal lines (as indicated for A and assumed for others)
	 * 
	 *           A
	 * _________(XX)_________
	 * |        (XX)         |
	 * |                     |
	 * |                     |
	 * x D                   x B
	 * x                     x
	 * |                     |
	 * |                     |
	 * |                     |
	 * _________XX___________
	 *          C
	 * 
	 * Note that this conceives the transformation in terms of the overall set of polys, not the each poly individually
	 * The first pair of anchors in A are those that fall on the external line, the second pair fall on the internal line
	 * relevant point indexes are calculated in terms of centre index, which should be poly.points/2 (8 for a quad)
	 */

	def getSideAnchors(polys: Array[Polygon2D], centreIndex: Int): Array[Array[Vector2D]] = {

		val sideAnchorBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]]

		val initialBuffer: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]

		for(poly <- polys) {

			initialBuffer += poly.points(centreIndex-5)//point 3
			initialBuffer += poly.points(centreIndex-4)//point 4
			initialBuffer += poly.points(centreIndex+3)//point 11
			initialBuffer += poly.points(Formulas.circularIndex(centreIndex+4, numSidesPerPoly*4))//point 12 (Quad), point 0 (TRI)

		}

		var bufferIndex: Int  = 0

		for (i <- 0 until sidesTotal) {

			if (i < (sidesTotal - 1)) {

				sideAnchorBufferPairs += Array(initialBuffer(bufferIndex), initialBuffer(bufferIndex+7))
				sideAnchorBufferPairs += Array(initialBuffer(bufferIndex+1), initialBuffer(bufferIndex+6))

				bufferIndex+=4

			} else {

				sideAnchorBufferPairs += Array(initialBuffer(bufferIndex), initialBuffer(Formulas.circularIndex(bufferIndex+7, sidesTotal*4)))
				sideAnchorBufferPairs += Array(initialBuffer(bufferIndex+1), initialBuffer(Formulas.circularIndex(bufferIndex+6, sidesTotal*4)))

			}
		}
		sideAnchorBufferPairs.toArray
		

	}
	/**
	 * Gets 4 pairs of control points that fall on either side of the anchor points that form outside points of internal lines (to centre)
	 * Note that this conceives the transformation in terms of the overall set of polys, not each poly individually
	 * Note as well that unlike the set of internal control points and external anchors, this set only has 4 pairs altogether,
	 * while the other two have eight
	 */

	def getSideControlPoints(polys: Array[Polygon2D], centreIndex: Int): Array[Array[Vector2D]] = {

		val centreControlBufferPairs: ArrayBuffer[Array[Vector2D]] = new ArrayBuffer[Array[Vector2D]] 

		val initialBuffer: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D]

		for(poly <- polys) {

			initialBuffer += poly.points(centreIndex-6)
			initialBuffer += poly.points(Formulas.circularIndex(centreIndex+5, numSidesPerPoly*4))

		}

		var bufferIndex: Int  = 0

		for (i <- 0 until sidesTotal) {

			if (i < (sidesTotal - 1)) {

				centreControlBufferPairs += Array(initialBuffer(bufferIndex), initialBuffer(bufferIndex+3))

				bufferIndex+=2

			} else {

				centreControlBufferPairs += Array(initialBuffer(bufferIndex), initialBuffer(Formulas.circularIndex(bufferIndex+3, sidesTotal*2)))


			}
		}
		centreControlBufferPairs.toArray
		

	}

	//here is where difference between quad and tri subdivision is handled
	//quad refereces 4 outside corner points for shifting the centre
	//tri references the notional middle points on the 3 outside lines
	def getOutsideRefs(polys: Array[Polygon2D], lineRatio: Double): Array[Vector2D] = {

		val refs: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D] 


		for(i <- 0 until sidesTotal) {

			refs += Formulas.lerp(polys(i).points(0), polys(i).points(3), lineRatio)
			
		}
		refs.toArray

	}

	//gets array of notional mid points on internal lines
	//this is 4 on QUAD and 3 on TRI
	//This does not take account of adjacent internal lines, only the notional ones from side anchor to centre
	//this is used for calculating diffVector from internal control points to this mid point
	//then a perpendicular vector is applied to control points following that vector with a multiplier
	//this is an alternative to the 'referToOuter' approach for calculating inner curves
	def getNotionalMidPointInternalLines(polys: Array[Polygon2D], centre: Int, lineRatio: Double): Array[Vector2D] = {

		val mids: ArrayBuffer[Vector2D] = new ArrayBuffer[Vector2D] 


		for(i <- 0 until sidesTotal) {

			mids += Formulas.lerp(polys(i).points(centre-3), polys(i).points(centre), lineRatio)
			
		}
		mids.toArray

	}

	def curveTri(polys: Array[Polygon2D], centreIndex: Int): Unit = {

		val controls: Array[Array[Vector2D]] = getInnerControlPoints(polys, centreIndex)//n sets of two pairs of control points for each inner side
		val outsideMiddles: Array[Vector2D] = getOutsideRefs(polys, .5)//the middles of the outer lines
		//we also get the notional outside control point positions because we can lerp between them for positioning inner control points
		val outsideQuartersA: Array[Vector2D] = getOutsideRefs(polys, .25)//the notional first control point position on each outside line
		val outsideQuartersB: Array[Vector2D] = getOutsideRefs(polys, .75)//the notional second control point position on each outside line

		var curvePosA: Vector2D = new Vector2D(0,0)
		var curvePosB: Vector2D = new Vector2D(0,0)

		var curvePosC: Vector2D = new Vector2D(0,0)
		var curvePosD: Vector2D = new Vector2D(0,0)

		if (referToOuter) {

			//code needed for radical curving based on following external control points - may just be able to call curveQuad?

		} else {

			for (i <- 0 until sidesTotal) {

				if (randomRatio) {

					val ranOuter: Double = Randomise.range(ranOuterRatio.min, ranOuterRatio.max)
					val ranInner: Double = Randomise.range(ranInnerRatio.min, ranInnerRatio.max)

					curvePosA = Formulas.lerp(outsideQuartersB(i), outsideQuartersA(Formulas.circularIndex(i+1, sidesTotal)), ranOuter)
					curvePosB = Formulas.lerp(outsideQuartersB(i), outsideQuartersA(Formulas.circularIndex(i+1, sidesTotal)), 1-ranOuter)//inverse

					curvePosC = Formulas.lerp(outsideMiddles(i), outsideMiddles(Formulas.circularIndex(i+1, sidesTotal)), ranInner)
					curvePosD = Formulas.lerp(outsideMiddles(i), outsideMiddles(Formulas.circularIndex(i+1, sidesTotal)), 1-ranInner)

				} else {

					curvePosA = Formulas.lerp(outsideQuartersB(i), outsideQuartersA(Formulas.circularIndex(i+1, sidesTotal)), outerRatio)
					curvePosB = Formulas.lerp(outsideQuartersB(i), outsideQuartersA(Formulas.circularIndex(i+1, sidesTotal)), 1-outerRatio)

					curvePosC = Formulas.lerp(outsideMiddles(i), outsideMiddles(Formulas.circularIndex(i+1, sidesTotal)), innerRatio)
					curvePosD = Formulas.lerp(outsideMiddles(i), outsideMiddles(Formulas.circularIndex(i+1, sidesTotal)), 1-innerRatio)

				}
				if (commonLine) {

					if (evenCommon) {

						Vector2D.copyValues(curvePosA, controls(i*2)(0)) 
						Vector2D.copyValues(curvePosA, controls(i*2)(1))

						Vector2D.copyValues(curvePosC, controls((i*2)+1)(0)) 
						Vector2D.copyValues(curvePosC, controls((i*2)+1)(1)) 

					} else if (oddCommon) {

						Vector2D.copyValues(curvePosB, controls(i*2)(0)) 
						Vector2D.copyValues(curvePosB, controls(i*2)(1))

						Vector2D.copyValues(curvePosD, controls((i*2)+1)(0)) 
						Vector2D.copyValues(curvePosD, controls((i*2)+1)(1)) 

					} else if (ranCommon) {

						val ran: Int = Randomise.range(0,1)
						if (ran==0) {
							Vector2D.copyValues(curvePosA, controls(i*2)(0)) 
							Vector2D.copyValues(curvePosA, controls(i*2)(1))
							Vector2D.copyValues(curvePosC, controls((i*2)+1)(0)) 
							Vector2D.copyValues(curvePosC, controls((i*2)+1)(1)) 

						} else if (ran==1) {
							Vector2D.copyValues(curvePosB, controls(i*2)(0)) 
							Vector2D.copyValues(curvePosB, controls(i*2)(1))
							Vector2D.copyValues(curvePosD, controls((i*2)+1)(0)) 
							Vector2D.copyValues(curvePosD, controls((i*2)+1)(1)) 

						}

					}

				} else {

					println("not a shared (common) line")

					Vector2D.copyValues(curvePosA, controls(i*2)(0)) 
					Vector2D.copyValues(curvePosB, controls(i*2)(1))

					Vector2D.copyValues(curvePosC, controls((i*2)+1)(0)) 
					Vector2D.copyValues(curvePosD, controls((i*2)+1)(1)) 

				}

			}

		}


	}


	def curveQuad(polys: Array[Polygon2D], centreIndex: Int): Unit = {

		val controls: Array[Array[Vector2D]] = getInnerControlPoints(polys, centreIndex)//n sets of two pairs of control points for each inner side
		val anchors: Array[Array[Vector2D]] = getSideAnchors(polys, centreIndex)//n pairs of side anchors
		val outerControls: Array[Array[Vector2D]] = getSideControlPoints(polys, centreIndex)//n pairs of side control points
		val mids: Array[Vector2D] = getNotionalMidPointInternalLines(polys, centreIndex, .5)


        //for calculating a corresponding vector between external control points and inner outside control points
		var vectorDiffA: Vector2D = new Vector2D(0,0)//external anchor to outer control points
		var vectorDiffB: Vector2D = new Vector2D(0,0)
		var vectorDiffC1: Vector2D = new Vector2D(0,0)//external anchor to inner control points
		var vectorDiffC2: Vector2D = new Vector2D(0,0)

		var curvePosA: Vector2D = new Vector2D(0,0)//for outer inner control points
		var curvePosB: Vector2D = new Vector2D(0,0)//for outer inner control points

		var curvePosC: Vector2D = new Vector2D(0,0)//for inner inner control points
		var curvePosD: Vector2D = new Vector2D(0,0)//for inner inner control points

		var distFromAnchorA: Vector2D = new Vector2D(0,0)//line from anchor point to adjusted inner control point
		var distFromAnchorB: Vector2D = new Vector2D(0,0)

		var distFromAnchorC: Vector2D = new Vector2D(0,0)//line from old center to adjusted inner inner control point
		var distFromAnchorD: Vector2D = new Vector2D(0,0)



		if (referToOuter) {

			for (i <- 0 until sidesTotal) {//iterate not through polys but the corresponding internal lines 

                /**
				vectorDiffA = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), outerControls(i)(0))//anchor 0 to control 0
				vectorDiffB = Formulas.differenceBetweenTwoVectors(anchors(i*2)(1), outerControls(i)(1))//anchor 1 to control 1
				vectorDiffC1 = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), controls(i*2)(0))//anchor 0 to inner control 0
				vectorDiffC2 = Formulas.differenceBetweenTwoVectors(anchors(i*2)(1), controls(i*2)(1))//anchor 1 to inner control 1
				*/

				vectorDiffA = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), outerControls(i)(0))//anchor 0 to control 0
				vectorDiffB = Formulas.differenceBetweenTwoVectors(anchors(i*2)(1), outerControls(i)(1))//anchor 1 to control 1
				vectorDiffC1 = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), controls(i*2)(0))//anchor 0 to inner control 0
				vectorDiffC2 = Formulas.differenceBetweenTwoVectors(anchors(i*2)(1), controls(i*2)(1))//anchor 1 to inner control 1


				if(followOuter) {

					println("Follow Outer, Internal side: " + i)
					
					curvePosA = Vector2D.add(anchors(i*2)(0), Formulas.reverseVector(vectorDiffA))
					curvePosB = Vector2D.add(anchors(i*2)(1), Formulas.reverseVector(vectorDiffB))

					//curvePosC = Vector2D.add(polys(i).points(centreIndex), Formulas.rightPerpendicularVector(vectorDiffC1))
					//curvePosD = Vector2D.add(polys(i).points(centreIndex), Formulas.rightPerpendicularVector(vectorDiffC2))

					Vector2D.copyValues(controls((i*2)+1)(0), curvePosC)//this leaves control point values unchanged!
					Vector2D.copyValues(controls((i*2)+1)(1), curvePosD)//this leaves control point values unchanged!


				} else if (exaggerateOuter) {

					println("exaggerateOuter, Internal side: " + i)	

					curvePosA = Vector2D.add(anchors(i*2)(0), Formulas.average(vectorDiffB, vectorDiffC2))
					val anchorAToCPDiff: Vector2D = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), curvePosA)

					curvePosB = Vector2D.add(anchors(i*2)(0), Formulas.average(vectorDiffA, vectorDiffC1))
					val anchorBToCPDiff: Vector2D = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), curvePosB)

					curvePosC = Vector2D.add(polys(i).points(centreIndex), anchorAToCPDiff)
					curvePosD = Vector2D.add(polys(i).points(centreIndex), anchorBToCPDiff)

				} else if (counterOuter) {

					println("counterOuter, Internal side: " + i)

					curvePosA = Vector2D.add(anchors(i*2)(0), Formulas.average(vectorDiffA, vectorDiffC1))
					val anchorAToCPDiff: Vector2D = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), curvePosA)

					curvePosB = Vector2D.add(anchors(i*2)(0), Formulas.average(vectorDiffB, vectorDiffC2))
					val anchorBToCPDiff: Vector2D = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), curvePosB)

					curvePosC = Vector2D.add(polys(i).points(centreIndex), anchorAToCPDiff)
					curvePosD = Vector2D.add(polys(i).points(centreIndex), anchorBToCPDiff)


				}
				//multiplies the vector from relevant anchor to adjusted control point for both outer and inner pairs of 'inner' control points
				distFromAnchorA = Formulas.differenceBetweenTwoVectors(anchors(i*2)(0), curvePosA)
				distFromAnchorA = Vector2D.multiply(distFromAnchorA, outerMultiplier)
				curvePosA = Vector2D.add(curvePosA, distFromAnchorA)

				distFromAnchorB = Formulas.differenceBetweenTwoVectors(anchors(i*2)(1), curvePosB)
				distFromAnchorB = Vector2D.multiply(distFromAnchorB, outerMultiplier)
				curvePosB = Vector2D.add(curvePosB, distFromAnchorB)

				distFromAnchorC = Formulas.differenceBetweenTwoVectors(polys(i).points(centreIndex), curvePosC)
				distFromAnchorC = Vector2D.multiply(distFromAnchorC, innerMultiplier)
				curvePosC = Vector2D.add(curvePosC, distFromAnchorC)

				distFromAnchorD = Formulas.differenceBetweenTwoVectors(polys(i).points(centreIndex), curvePosD)
				distFromAnchorD = Vector2D.multiply(distFromAnchorD, innerMultiplier)
				curvePosD = Vector2D.add(curvePosD, distFromAnchorD)

				if (commonLine) {

					if (evenCommon) {

						Vector2D.copyValues(curvePosA, controls(i*2)(0)) 
						Vector2D.copyValues(curvePosA, controls(i*2)(1))

						Vector2D.copyValues(curvePosC, controls((i*2)+1)(0)) 
						Vector2D.copyValues(curvePosC, controls((i*2)+1)(1)) 

					} else if (oddCommon) {

						Vector2D.copyValues(curvePosB, controls(i*2)(0)) 
						Vector2D.copyValues(curvePosB, controls(i*2)(1))

						Vector2D.copyValues(curvePosD, controls((i*2)+1)(0)) 
						Vector2D.copyValues(curvePosD, controls((i*2)+1)(1)) 

					} else if (ranCommon) {

						val ran: Int = Randomise.range(0,1)
						if (ran==0) {
							Vector2D.copyValues(curvePosA, controls(i*2)(0)) 
							Vector2D.copyValues(curvePosA, controls(i*2)(1))
							Vector2D.copyValues(curvePosC, controls((i*2)+1)(0)) 
							Vector2D.copyValues(curvePosC, controls((i*2)+1)(1)) 

						} else if (ran==1) {
							Vector2D.copyValues(curvePosB, controls(i*2)(0)) 
							Vector2D.copyValues(curvePosB, controls(i*2)(1))
							Vector2D.copyValues(curvePosD, controls((i*2)+1)(0)) 
							Vector2D.copyValues(curvePosD, controls((i*2)+1)(1)) 

						}

					}

				} else {

					println("not a shared (common) line")

					Vector2D.copyValues(curvePosA, controls(i*2)(0)) 
					Vector2D.copyValues(curvePosB, controls(i*2)(1))

					Vector2D.copyValues(curvePosC, controls((i*2)+1)(0)) 
					Vector2D.copyValues(curvePosD, controls((i*2)+1)(1)) 

				}

			}

		} else {

			println("not refer to outer")

			val curveMultiplier: Range = new Range(-2,2)

			for (i <- 0 until sidesTotal) {//iterate not through polys but the corresponding internal lines

				val diffVectA: Vector2D = Formulas.differenceBetweenTwoVectors(controls(i*2)(0), mids(i))
				println("not refer to outer, diffVectA: " + diffVectA.toString())
				val diffVectB: Vector2D = Formulas.differenceBetweenTwoVectors(controls(i*2)(1), mids(i))
				val diffVectC: Vector2D = Formulas.differenceBetweenTwoVectors(controls((i*2)+1)(0), mids(i))
				val diffVectD: Vector2D = Formulas.differenceBetweenTwoVectors(controls((i*2)+1)(1), mids(i))

				val invA: Vector2D = Formulas.inverseVector(diffVectA)
				println("not refer to outer, invA: " + invA.toString())
				val invB: Vector2D = Formulas.inverseVector(diffVectB)
				val invC: Vector2D = Formulas.inverseVector(diffVectC)
				val invD: Vector2D = Formulas.inverseVector(diffVectD)

				val curvePosA: Vector2D = Vector2D.add(controls(i*2)(0), Vector2D.multiply(invA, curveMultiplier.min))
				val curvePosB: Vector2D = Vector2D.add(controls(i*2)(1), Vector2D.multiply(invB, curveMultiplier.max))
				val curvePosC: Vector2D = Vector2D.add(controls((i*2)+1)(0), Vector2D.multiply(invC, curveMultiplier.min))
				val curvePosD: Vector2D = Vector2D.add(controls((i*2)+1)(1), Vector2D.multiply(invD, curveMultiplier.max))

				Vector2D.copyValues(curvePosA, controls(i*2)(0)) 
				Vector2D.copyValues(curvePosB, controls(i*2)(1))
				Vector2D.copyValues(curvePosC, controls((i*2)+1)(0)) 
				Vector2D.copyValues(curvePosD, controls((i*2)+1)(1)) 

			}

		}	

	}
}

/**
 * 
 * Vector2D.copyValues(controls((i*2)+1)(0), curvePosC)//this leaves control point values unchanged!

var diffVectA: Vector2D = Formulas.differenceBetweenTwoVectors(mid,controlA)
var diffVectB: Vector2D = Formulas.differenceBetweenTwoVectors(mid,controlB)

val invA: Vector2D = Formulas.inverseVector(diffVectA)
val invB: Vector2D = Formulas.inverseVector(diffVectB)

if ((polyIndex%2) == 0) {

	if((i%2)==0) {//first set of control points

		controlA = Vector2D.add(controlA, Vector2D.multiply(invB, curveMultiplier.min))
		controlB = Vector2D.add(controlB, Vector2D.multiply(invB, curveMultiplier.max))

	} else {

		controlA = Vector2D.add(controlA, Vector2D.multiply(invA, curveMultiplier.min))
		controlB = Vector2D.add(controlB, Vector2D.multiply(invA, curveMultiplier.max))

	}

} else {

	if((i%2)==0) {//first set of control points

		controlA = Vector2D.add(controlA, Vector2D.multiply(invA, curveMultiplier.min))
		controlB = Vector2D.add(controlB, Vector2D.multiply(invA, curveMultiplier.max))

	} else {

		controlA = Vector2D.add(controlA, Vector2D.multiply(invB, curveMultiplier.min))
		controlB = Vector2D.add(controlB, Vector2D.multiply(invB, curveMultiplier.max))

	}

}

*/


object InnerControlPoints {

	val FOLLOW_OUTER: Int  = 0
	val EXAGGERATE_OUTER: Int  = 1
	val COUNTER_OUTER: Int  = 2

	val EVEN_COMMON: Int = 0
	val ODD_COMMON: Int = 1
	val RANDOM_COMMON: Int = 2

}