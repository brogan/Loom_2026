/**
 Renderer holds rendering parameters.  You must define all parameters even if you don't use them all.
 MODE: one of four rendering modes (points, lines, filled and filled_stroked) expressed as an Int.  Specify mode via the Renderer Object definitions.
 STROKEWIDTH: the width of the stroke expressed as Float.
 STROKECOLOR: the stroke color (java.awt.Color)
 FILLCOLOR: the stroke color (java.awt.Color)
 */

package org.loom.scene


import java.awt.Color

class Renderer (val name: String, var mode: Int, var strokeWidth: Float, var strokeColor: Color, var fillColor: Color, var pointSize: Float, val holdLength: Int) {

  // Brush config for BRUSHED mode (mode == 4)
  var brushConfig: BrushConfig = null
  // Stencil config for STENCILED mode (mode == 5)
  var stencilConfig: StencilConfig = null
  //Note: holdLength - how long to hold current renderer in renderSet random or sequential playback - see sprite2D draw
  //overall switch for changing
  private var changing: Boolean = false

  var pointStroked: Boolean = true
  var pointFilled: Boolean = true


  private val changeSet: Array[RenderTransform] = Array(
    new RenderTransform(this, Renderer.NO_CHANGE),
    new RenderTransform(this, Renderer.NO_CHANGE),
    new RenderTransform(this, Renderer.NO_CHANGE),
    new RenderTransform(this, Renderer.NO_CHANGE),
    new RenderTransform(this, Renderer.NO_CHANGE)  // STENCIL_OPACITY
  )

  def setPointDrawingStyle(stroky: Int, filly: Int): Unit = {
    if (stroky == Renderer.STROKED) {
      pointStroked = true
    } else if (stroky == Renderer.NOT_STROKED) {
      pointStroked = false
    }
    if (filly == Renderer.FILLED) {
      pointFilled = true
    } else if (filly == Renderer.NOT_FILLED) {
      pointFilled = false
    }

  }

  def setNotChanging(changType: Int): Unit = {
    changeSet(changType).changeType = Renderer.NO_CHANGE
  }

  /** convenience methods for rendering change
   * call from MySketch
   */

  def setChangingStrokeWidth(params: Array[Int], min: Float, max: Float, increment: Float, pauseMax: Int): Unit = {
    if (mode != Renderer.FILLED) {
      changing = true
      val strokeWidthTransform = changeSet(Renderer.STROKE_WIDTH)
      strokeWidthTransform.setChanging(Renderer.STROKE_WIDTH)
      renderTransformStoreParams(strokeWidthTransform, params)
      strokeWidthTransform.setStrokeWidthValues(min, max, increment)
      if (params(Renderer.CYCLE) != Renderer.CONSTANT) {
        strokeWidthTransform.setPausing(pauseMax)
      }

      strokeWidthTransform.setInitialValues()

    } else {
      println("Renderer, setChangingStrokeWidth: not applied, this method is not relevant for exclusively FILLED rendering")
    }
  }

  def setChangingStrokeColor(params: Array[Int], min: Array[Int], max: Array[Int], increment: Array[Int], pauseMax: Int): Unit = {
    if (mode != Renderer.FILLED) {
      changing = true
      val strokeColorTransform = changeSet(Renderer.STROKE_COLOR)
      renderTransformStoreParams(strokeColorTransform, params)
      strokeColorTransform.setChanging(Renderer.STROKE_COLOR)
      strokeColorTransform.setStrokeColorValues(min, max, increment)
      if (params(Renderer.CYCLE) != Renderer.CONSTANT) {
        strokeColorTransform.setPausing(pauseMax)
      }

      strokeColorTransform.setInitialValues()

    } else {
      println("Renderer, setChangingStrokeColor: not applied, this method is not relevant for FILLED rendering")
    }
  }

  def setChangingFillColor(params: Array[Int], min: Array[Int], max: Array[Int],increment: Array[Int], pauseMax: Int, pauseChan: Int, pauseColMin: Array[Int], pauseColMax: Array[Int]): Unit = {
    if (mode != Renderer.STROKED) {
      changing = true
      val fillColorTransform = changeSet(Renderer.FILL_COLOR)
      renderTransformStoreParams(fillColorTransform, params)
      fillColorTransform.setChanging(Renderer.FILL_COLOR)
      fillColorTransform.setFillColorValues(min, max, increment)
      if (params(Renderer.CYCLE) != Renderer.CONSTANT) {
        fillColorTransform.setPausing(pauseMax, pauseChan, pauseColMin, pauseColMax)
      } else {
      }

      fillColorTransform.setInitialValues()
    } else {
      println("Renderer, setChangingFillColor: not applied, this method is not relevant for exclusively STROKED rendering")
    }
  }

  def setChangingPointSize(params: Array[Int], min: Float, max: Float, increment: Float, pauseMax: Int): Unit = {
    if (mode == Renderer.POINTS) {
      changing = true
      val pointSizeTransform = changeSet(Renderer.POINT_SIZE)
      pointSizeTransform.setChanging(Renderer.POINT_SIZE)
      renderTransformStoreParams(pointSizeTransform, params)
      pointSizeTransform.setPointSizeValues(min, max, increment)
      if (params(Renderer.CYCLE) != Renderer.CONSTANT) {
        pointSizeTransform.setPausing(pauseMax)
      }

      pointSizeTransform.setInitialValues()
    } else {
      println("Renderer, setChangingPointSize: not applied, this method is only relevant for POINT rendering")
    }
  }

  def setChangingStencilOpacity(params: Array[Int], min: Float, max: Float, increment: Float, pauseMax: Int): Unit = {
    if (mode == Renderer.STENCILED) {
      changing = true
      val opacityTransform = changeSet(Renderer.STENCIL_OPACITY)
      opacityTransform.setChanging(Renderer.STENCIL_OPACITY)
      renderTransformStoreParams(opacityTransform, params)
      opacityTransform.setStencilOpacityValues(min, max, increment)
      if (params(Renderer.CYCLE) != Renderer.CONSTANT) {
        opacityTransform.setPausing(pauseMax)
      }
      opacityTransform.setInitialValues()
    } else {
      println("Renderer, setChangingStencilOpacity: not applied, only relevant for STENCILED rendering")
    }
  }

  private def renderTransformStoreParams(transform: RenderTransform, params: Array[Int]): Unit = {
    transform.setParams(params)
  }


  //end convenience methods called from MySketch

  /**
   * Scale all pixel-based values (stroke width, point size, and their dynamic
   * change ranges) by the given factor.  Used to ensure consistent visual output
   * when rendering at higher quality multiples.
   */
  def scalePixelValues(factor: Float): Unit = {
    strokeWidth = strokeWidth * factor
    pointSize = pointSize * factor
    changeSet.foreach(_.scalePixelValues(factor))
    if (brushConfig != null) brushConfig.scalePixelValues(factor.toDouble)
    if (stencilConfig != null) stencilConfig.scalePixelValues(factor.toDouble)
  }

  def update(scale: Int): Unit = {
    //println("updating: " + changing)
    if (changing) {

      if (changeSet(Renderer.STROKE_WIDTH).changeType == Renderer.STROKE_WIDTH) { //changing stroke width

        //println("updating stroke width")
        changeSet(Renderer.STROKE_WIDTH).update(Renderer.STROKE_WIDTH, scale)
      }

      if (changeSet(Renderer.STROKE_COLOR).changeType == Renderer.STROKE_COLOR) {
        changeSet(Renderer.STROKE_COLOR).update(Renderer.STROKE_COLOR, scale)
      }

      if (changeSet(Renderer.FILL_COLOR).changeType == Renderer.FILL_COLOR) {
        changeSet(Renderer.FILL_COLOR).update(Renderer.FILL_COLOR, scale)
      }
      if (changeSet(Renderer.POINT_SIZE).changeType == Renderer.POINT_SIZE) {
        changeSet(Renderer.POINT_SIZE).update(Renderer.POINT_SIZE, scale)
      }

      if (changeSet(Renderer.STENCIL_OPACITY).changeType == Renderer.STENCIL_OPACITY) {
        changeSet(Renderer.STENCIL_OPACITY).update(Renderer.STENCIL_OPACITY, scale)
      }

    }

  }
}


/**

  /**
   Clone the Renderer.  Produces an independent copy. FIX: Needs updating to reflect new fields above
   */
  override def clone(): Renderer = {
    var sc: Color = new Color(strokeColor.getRed(), strokeColor.getGreen(), strokeColor.getBlue(), strokeColor.getAlpha())
    var fc: Color = new Color(fillColor.getRed(), fillColor.getGreen(), fillColor.getBlue(), fillColor.getAlpha())
    new Renderer(name +"_clone", mode, strokeWidth, sc, fc)
  }

  override def toString(): String = {
    var s: String = "Renderer "
    s += "name: " + name
    s += ", stroke width: " + strokeWidth
    s += ", stroke color: " + strokeColor.getRed() + ", " + strokeColor.getGreen() + ", " + strokeColor.getBlue() + ", " + strokeColor.getAlpha()
    s += ", fill color: " + fillColor.getRed() + ", " + fillColor.getGreen() + ", " + fillColor.getBlue() + ", " + fillColor.getAlpha()
    s += "\n"
    s
  }

}
*/



/**
 Renderer static fields
 */
object Renderer {

  //mode
  val POINTS: Int = 0
  val STROKED: Int = 1
  val FILLED: Int = 2
  val FILLED_STROKED: Int = 3
  val BRUSHED: Int = 4
  val STENCILED: Int = 5

  val NOT_STROKED: Int = 4
  val NOT_FILLED: Int = 5

  //changeType
  val NO_CHANGE: Int = -1
  val STROKE_WIDTH: Int = 0
  val STROKE_COLOR: Int = 1
  val FILL_COLOR: Int = 2
  val POINT_SIZE: Int = 3
  val STENCIL_OPACITY: Int = 4

  //CHANGE PARAMS
  val KIND: Int = 0
  val MOTION: Int = 1
  val CYCLE: Int = 2

  //kind
  val SEQ: Int = 0
  val RAN: Int = 1

  //motion
  val UP: Int = 1
  val DOWN: Int = -1
  val PING_PONG = 0

  //cycle
  val CONSTANT: Int = 0
  val ONCE: Int = 1
  val ONCE_REVERT = 2
  val PAUSING: Int = 3
  val PAUSING_RANDOM: Int = 4

  //scale - the level that change updates occur
  val SPRITE: Int = 0
  val POLY: Int = 1
  val POINT: Int = 2

  //color attribute for evaluating pause max in RenderTransform
  val RED_CHAN: Int = 0
  val GREEN_CHAN: Int = 1
  val BLUE_CHAN: Int = 2
  val ALPHA_CHAN: Int = 3

  //color
  val EVAL: Int = 0//the color channel evaluated for pausing/cycling purposes
  val FREE: Int = 1//color channels that keep running, disregarding any pausing
  val TIED: Int = 2//color channels that follow the cycling pattern of EVAL
  val FIXED: Int = 3//color channels that remain at a fixed value (MAX)
  val SWITCH: Int = 4//color channels that alternate between MAX and MIN value - MAX when running, MIN when pausing (following EVAL)
  val RANDOM: Int = 5//color channel subject to random change between MIN and Max


  //DEFINED Colors
  val BLACK: Color = new Color(0,0,0,255)
  val BLACK_FAINT: Color = new Color(0,0,0,30)
  val WHITE: Color = new Color(255,255,255,255)
  val GREY: Color = new Color(127,127,127,255)
  val YELLOW: Color = new Color(255,255,0,50)
  val ORANGE: Color = new Color(255,128,0,50)
  val RED: Color = new Color(255,0,0,50)
  val YELLOWGREEN: Color = new Color(128,255,0,50)
  val GREEN: Color = new Color(0,255,0,50)
  val GREENBLUE: Color = new Color(0,255,128,50)
  val CYAN: Color = new Color(0,255,255,50)
  val BLUEGREEN: Color = new Color(0,128,255,50)
  val BLUE: Color = new Color(0,0,150,100)
  val BLUE_FAINT: Color = new Color(0,0,200,10)
  val PURPLE: Color = new Color(127,0,255,50)
  val MAGENTA: Color = new Color(255,0,255,50)
  val REDBLUE: Color = new Color(255,0,127,50)


}
