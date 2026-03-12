package org.loom.geometry

import scala.collection.mutable.ArrayBuffer
import org.loom.utility._
import org.loom.transform._

class SubdivisionParams(val name: String) {


  //lines and splines
  var subdivisionType: Int = Subdivision.QUAD //defined in Subdivision object

  var ranMiddle: Boolean = false //you can randomise the middle point position of QUAD & TRIANGLE subdivisions - this randomises the middle of the old polygon before calculating the new subdivisions
  var ranDiv: Double = 100 //you can specify a randomDivisor for the randomMiddle- low values randomise more, large values less

  //for modes of subdivision which calculate intermediate points on line segments
  //these can be positioned wherever you like on the line via the following ratios
  //only caters for QUADS at present (two line segments)
  var lineRatios: Vector2D = new Vector2D(.5, .5) //when intermediate points on lines need to be calculated (say for QUAD subdivision), first ratio is distance along first line (.4 works well) and second ratio is distance along second line (.6 for instance).  More extreme values create other effects (try .75 for both).
  var controlPointRatios: Vector2D = new Vector2D(.25, .75) //the default value for placing control points along the new calculated line

  var insetTransform: Transform2D = new Transform2D(new Vector2D(0, 0), new Vector2D(.5, .5), new Vector2D(0, 0)) //translation, scale, rotation of inset shape (relevant for echo subdivision) - CHANGE NAME TO ECHOINSETRANSFORM

  var continuous: Boolean = true //links adjacent mid-points on QUADS when lineRatios differ between x and y (as long as they add up to 1 altogether).  This is necessary because new polygons are effectively rotated relative to one another.  If, for instance, a square is being subdivided, the first new polygon has its origin at the top left original point.  The next has its origin at the top right point, which means that it is notionally rotated 90 degrees in relation to the first polygon.  This notional rotation means that lines calculated non-middle line ratios do not line up.  Selecting continuous makes them line up.
  var visibilityRule: Int = Subdivision.ALL //defined in Subdivision object - see below for choices

  /**
   * //visibility rules (which polys to make visible after subdivision)
   * ALL
   * QUADS
   * TRIS
   * ALL_BUT_LAST
   * ALTERNATE_ODD
   * ALTERNATE_EVEN
   * FIRST_HALF
   * SECOND_HALF
   * EVERY_THIRD
   * EVERY_FOURTH
   * EVERY_FIFTH
   * RANDOM_1_2
   * RANDOM_1_3
   * RANDOM_1_5
   * RANDOM_1_7
   * RANDOM_1_10
   */

  var polysTransform: Boolean = true //switch to determine if any transformations needed)

  //ALL POLYGONS

  var polysTranformWhole: Boolean = false
  var pTW_randomTranslation: Boolean = false
  var pTW_randomScale: Boolean = false
  var pTW_randomRotation: Boolean = false

  //common centre: if true all transformations occur in relation to a common centre, otherwise to the centres of individual polys
  var pTW_commonCentre: Boolean = false

  var pTW_probability: Double = 100 //probability that any given polygon will be transformed (percentage)
  var pTW_transform: Transform2D = new Transform2D(new Vector2D(0, 0), new Vector2D(0, 0), new Vector2D(0, 0)) //null transform - translation, scale, rotatio
  var pTW_randomCentreDivisor: Double = 100 //randomised value between specified value and the poly centre
  var pTW_randomTranslationRange: RangeXY = new RangeXY(new Range(0, 0), new Range(0, 0)) //randomised x y translation value (both x and y have separate min and max values in Range object)
  var pTW_randomScaleRange: RangeXY = new RangeXY(new Range(1, 1), new Range(1, 1)) //randomised x y scale value (both x and y have separate min and max values in Range object)
  var pTW_randomRotationRange: Range = new Range(0, 0) //randomised rotation value with min and max

  //end all polygons


  //SELECTED POINTS WITHIN POLYGONS

  var polysTransformPoints: Boolean = false
  var pTP_probability: Double = 100

  val transformSet: ArrayBuffer[Transform] = new ArrayBuffer[Transform]()

  var exteriorAnchors: ExteriorAnchors = new ExteriorAnchors(false)
  transformSet += exteriorAnchors

  var centralAnchors: CentralAnchors = new CentralAnchors(false)
  transformSet += centralAnchors

  var anchorsLinkedToCentre: AnchorsLinkedToCentre = new AnchorsLinkedToCentre(false)
  transformSet += anchorsLinkedToCentre

  var outerControlPoints: OuterControlPoints = new OuterControlPoints(false)
  transformSet += outerControlPoints

  var innerControlPoints: InnerControlPoints = new InnerControlPoints(false)
  transformSet += innerControlPoints

  var pTP_transformSet: Array[Transform] = transformSet.toArray

  //end points


  override def toString(): String = {
    var s: String = "" + "\n"
    s += "Subdivision params:" + "\n"
    s += "Name:" + name + "\n"
    s += "subdivisionType: " + Subdivision.getType(subdivisionType) + "\n"

    s += "polysTransform: " + polysTransform + "\n"
    s += "polysTranformWhole: " + polysTranformWhole + "\n"
    s += "pTW_randomTranslation: " + pTW_randomTranslation + "\n"
    s += "pTW_randomScale: " + pTW_randomScale + "\n"
    s += "pTW_randomRotation: " + pTW_randomRotation + "\n"
    s += "pTW_commonCentre: " + polysTransform + "\n"

    s += "pTW_probability: " + pTW_probability + "\n"

    s += "pTW_transform: " + pTW_transform.toString + "\n"
    s += "pTW_randomCentreDivisor: " + pTW_randomCentreDivisor + "\n"
    s += "pTW_randomTranslationRange: " + pTW_randomTranslationRange.toString + "\n"
    s += "pTW_randomScaleRange: " + pTW_randomScaleRange.toString + "\n"
    s += "pTW_randomRotationRange: " + pTW_randomRotationRange.toString + "\n"


    s += "ranMiddle: " + ranMiddle + "\n"
    s += "ranDiv: " + ranDiv + "\n"
    s += "lineRatios: " + lineRatios.toString + "\n"

    s += "insetTransform: " + insetTransform.toString + "\n"
    s += "continuous: " + continuous + "\n"
    s += "visibilityRule: " + Subdivision.getVisibilityRule(visibilityRule) + "\n"

    s
  }


  def setParameters(sT: Int, pT: Boolean,
                    rM: Boolean, rD: Double, lR: Vector2D, cPR: Vector2D, iT: Transform2D, c: Boolean, vR: Int,
                    pTW: Boolean, pTWRT: Boolean, pTWRS: Boolean, pTWRR: Boolean, pTW_CC: Boolean, pTWP: Double, pTWT: Transform2D, pTWrCD: Double, pTWrTR: RangeXY, pTWrSR: RangeXY, pTWrRR: Range,
                    pTP_flag: Boolean, pTP_prob: Double, pTP_transform: Array[Transform]): Unit = {

    subdivisionType = sT
    polysTransform = pT

    ranMiddle = rM
    ranDiv = rD
    lineRatios = lR
    controlPointRatios = cPR
    insetTransform = iT
    continuous = c
    visibilityRule = vR

    polysTranformWhole = pTW
    pTW_randomTranslation = pTWRT
    pTW_randomScale = pTWRS
    pTW_randomRotation = pTWRR
    pTW_commonCentre = pTW_CC

    pTW_probability = pTWP
    pTW_transform = pTWT
    pTW_randomCentreDivisor = pTWrCD
    pTW_randomTranslationRange = pTWrTR
    pTW_randomScaleRange = pTWrSR
    pTW_randomRotationRange = pTWrRR

    polysTransformPoints = pTP_flag
    pTP_probability = pTP_prob
    pTP_transformSet = pTP_transform

  }

}