package org.loom.scene

import org.loom.utility.Randomise
import org.loom.utility.Colors
import org.loom.utility.Formulas

import java.awt.Color


private class RenderTransform(val renderer: Renderer, var changeType: Int) {

  //params
  var kind: Int = -1 //either SEQ (0) or RAN (1), default is -1 (no kind), actual values specified in Renderer
  var motion: Int = -1 //UP, DOWN, PING_PONG
  var cycle: Int = -1 //CONSTANT, ONCE, ONCE_REVERT, PAUSING, PAUSING_RANDOM
  var scale: Int = -1//SPRITE, POLY, POINT_LINE level change

  //follow values are for pausing when in random KIND
  private val ranMax: Int = 100
  private var ranCount: Int = 0

  private var pausing: Boolean = false//is any pausing occurring (always intermittently pausing unless Renderer.CONSTANT)
  private var paused: Boolean = false//current state of paused or not
  private var pauseChan: Int = 0//color channel for evaluating when a color pause should occur (not relevant for line or point size change)
  private var pauseColMin: Array[Int] = Array(0,0,0,0)//empty default
  private var pauseColMax: Array[Int] = Array(0,0,0,0)//empty default
  private var fixedPauseCol: Boolean = false
  private var originPauseMax: Int = 0//originally specified number of update cycles to pause (needed for random length pauses)
  private var pauseMax: Int = 0 //fixed for ordinary pausing but changes with pausing random

  private var pauseCount: Int = 0 //current value of pause

  private var pingPongUpComplete: Boolean = false//needed to evaluate whether ping pong has completed a full cycle for pausing purposes

  private val strokeWidthValues: SizeValues = new SizeValues()
  private val pointSizeValues: SizeValues = new SizeValues()
  private val opacityValues: SizeValues = new SizeValues()
  private val strokeColorValues: ColorValues = new ColorValues()
  private val fillColorValues: ColorValues = new ColorValues()

  // Color palette fields for PAL_SEQ / PAL_RAN kinds
  private var strokePalette: Array[java.awt.Color] = Array.empty
  private var fillPalette: Array[java.awt.Color] = Array.empty
  private var strokePaletteIndex: Int = 0
  private var fillPaletteIndex: Int = 0
  private var strokePaletteDir: Int = 1
  private var fillPaletteDir: Int = 1

  // Size palette fields for PAL_SEQ / PAL_RAN kinds
  private var strokeWidthPalette: Array[Float] = Array.empty
  private var pointSizePalette: Array[Float] = Array.empty
  private var strokeWidthPaletteIndex: Int = 0
  private var pointSizePaletteIndex: Int = 0
  private var strokeWidthPaletteDir: Int = 1
  private var pointSizePaletteDir: Int = 1


  /**
   * Scale pixel-based size values (stroke width and point size change ranges)
   * by the given factor for quality-multiple consistency.
   */
  def scalePixelValues(factor: Float): Unit = {
    strokeWidthValues.scaleBy(factor)
    pointSizeValues.scaleBy(factor)
    strokeWidthPalette = strokeWidthPalette.map(_ * factor)
    pointSizePalette = pointSizePalette.map(_ * factor)
    // opacityValues is a 0-1 float ratio — no pixel scaling needed
  }

  //sent from Renderer along with change parameters and values
  def setChanging(cType: Int): Unit = {
    changeType = cType
    paused = false
  }

  def setParams(params: Array[Int]): Unit = {
    kind = params(0)
    motion = params(1)
    cycle = params(2)
    scale = params(3)
  }

  def setStrokeWidthValues(min: Float, max: Float, increment: Float): Unit = {
    strokeWidthValues.setSizeValues(min, max, increment)
  }

  def setPointSizeValues(min: Float, max: Float, increment: Float): Unit = {
    pointSizeValues.setSizeValues(min, max, increment)
  }

  def setStencilOpacityValues(min: Float, max: Float, increment: Float): Unit = {
    opacityValues.setSizeValues(min, max, increment)
  }

  def setStrokeColorValues(min: Array[Int], max: Array[Int], increment: Array[Int]): Unit = {
    strokeColorValues.setColorValues(min, max, increment)
  }

  def setFillColorValues(min: Array[Int], max: Array[Int], increment: Array[Int]): Unit = {
    fillColorValues.setColorValues(min, max, increment)
  }

  def setStrokePalette(p: Array[java.awt.Color]): Unit = {
    strokePalette = p; strokePaletteIndex = 0; strokePaletteDir = 1
  }

  def setFillPalette(p: Array[java.awt.Color]): Unit = {
    fillPalette = p; fillPaletteIndex = 0; fillPaletteDir = 1
  }

  def setStrokeWidthPalette(p: Array[Float]): Unit = {
    strokeWidthPalette = p; strokeWidthPaletteIndex = 0; strokeWidthPaletteDir = 1
  }

  def setPointSizePalette(p: Array[Float]): Unit = {
    pointSizePalette = p; pointSizePaletteIndex = 0; pointSizePaletteDir = 1
  }

  private def getRandomisedColor(col: ColorValues): Color = {
    val r: Int = Randomise.range(col.min(0), col.max(0))
    val g: Int = Randomise.range(col.min(1), col.max(1))
    val b: Int = Randomise.range(col.min(2), col.max(2))
    val a: Int = Randomise.range(col.min(3), col.max(3))
    new Color(r, g, b, a)
  }

  // Set renderer value to start-of-cycle position (min for UP, max for DOWN, midpoint for PING_PONG)
  def setInitialValues(): Unit = {
    if (kind == Renderer.SEQ || kind == Renderer.RAN) {
      changeType match {
        case Renderer.STROKE_COLOR =>
          if (strokePalette.nonEmpty) {
            strokePaletteIndex = if (motion == Renderer.DOWN) strokePalette.length - 1 else 0
            renderer.strokeColor = strokePalette(strokePaletteIndex)
          }
        case Renderer.FILL_COLOR =>
          if (fillPalette.nonEmpty) {
            fillPaletteIndex = if (motion == Renderer.DOWN) fillPalette.length - 1 else 0
            renderer.fillColor = fillPalette(fillPaletteIndex)
          }
        case Renderer.STROKE_WIDTH =>
          if (strokeWidthPalette.nonEmpty) {
            strokeWidthPaletteIndex = if (motion == Renderer.DOWN) strokeWidthPalette.length - 1 else 0
            renderer.strokeWidth = strokeWidthPalette(strokeWidthPaletteIndex)
          }
        case Renderer.POINT_SIZE =>
          if (pointSizePalette.nonEmpty) {
            pointSizePaletteIndex = if (motion == Renderer.DOWN) pointSizePalette.length - 1 else 0
            renderer.pointSize = pointSizePalette(pointSizePaletteIndex)
          }
        case _ =>
      }
    } else if (motion == Renderer.UP) {
      changeType match {
        case Renderer.STROKE_WIDTH => renderer.strokeWidth = strokeWidthValues.min
        case Renderer.STROKE_COLOR => renderer.strokeColor = new Color(strokeColorValues.min(0), strokeColorValues.min(1), strokeColorValues.min(2), strokeColorValues.min(3))
        case Renderer.FILL_COLOR => renderer.fillColor = new Color(fillColorValues.min(0), fillColorValues.min(1), fillColorValues.min(2), fillColorValues.min(3))
        case Renderer.POINT_SIZE => renderer.pointSize = pointSizeValues.min
        case Renderer.STENCIL_OPACITY => if (renderer.stencilConfig != null) renderer.stencilConfig.currentOpacity = opacityValues.min
        case _ =>
      }
    } else if (motion == Renderer.DOWN) {
      changeType match {
        case Renderer.STROKE_WIDTH => renderer.strokeWidth = strokeWidthValues.max
        case Renderer.STROKE_COLOR => renderer.strokeColor = new Color(strokeColorValues.max(0), strokeColorValues.max(1), strokeColorValues.max(2), strokeColorValues.max(3))
        case Renderer.FILL_COLOR => renderer.fillColor = new Color(fillColorValues.max(0), fillColorValues.max(1), fillColorValues.max(2), fillColorValues.max(3))
        case Renderer.POINT_SIZE => renderer.pointSize = pointSizeValues.max
        case Renderer.STENCIL_OPACITY => if (renderer.stencilConfig != null) renderer.stencilConfig.currentOpacity = opacityValues.max
        case _ =>
      }
    } else if (motion == Renderer.PING_PONG) {
      pingPongUpComplete = false
      changeType match {
        case Renderer.STROKE_WIDTH => renderer.strokeWidth = strokeWidthValues.half
        case Renderer.STROKE_COLOR => renderer.strokeColor = new Color(strokeColorValues.half(0), strokeColorValues.half(1), strokeColorValues.half(2), strokeColorValues.half(3))
        case Renderer.FILL_COLOR => renderer.fillColor = new Color(fillColorValues.half(0), fillColorValues.half(1), fillColorValues.half(2), fillColorValues.half(3))
        case Renderer.POINT_SIZE => renderer.pointSize = pointSizeValues.half
        case Renderer.STENCIL_OPACITY => if (renderer.stencilConfig != null) renderer.stencilConfig.currentOpacity = opacityValues.half
        case _ =>
      }
    }
  }

  def update(changeType: Int, scaley: Int): Unit = {
    if (pausing) {
      if (paused) updatePausing()
      else updateTransform(changeType, scaley)
    } else {
      updateTransform(changeType, scaley)
    }
  }

  //for stroke and point size changing
  def setPausing(pMax: Int): Unit = {
    pausing = true
    originPauseMax = pMax
    pauseMax = originPauseMax
  }

  //for color changing - need to specify color channel to evaluate for when cycle completed (when pausing true)
  def setPausing(pMax: Int, pChan: Int, pColMin: Array[Int], pColMax: Array[Int]): Unit = {
    pausing = true
    originPauseMax = pMax
    pauseMax = originPauseMax
    pauseChan = pChan//this is the color channel that manages pausing
    pauseColMin = pColMin
    pauseColMax = pColMax
    if (Formulas.arraysAreEqual(pauseColMin, pauseColMax)) {
      fixedPauseCol = true//so just render pause color as pauseColMax
    } else {
      fixedPauseCol = false//randomise pause color between pauseColMin and pauseColMax
    }
  }

  private def pauseCycleFinished(): Boolean = {
    var cycleEndReached: Boolean = false
    if (pauseCount > pauseMax) {
      cycleEndReached = true
    }
    cycleEndReached
  }

  private def updatePausing(): Unit = {
    //println("RenderTransform, changeType: " + changeType + ", updatePausing, paused = true, pauseCount: " + pauseCount)
    if (pauseCycleFinished()) {
      if (cycle == Renderer.ONCE) {
        renderer.setNotChanging(changeType)
      } else if (cycle == Renderer.ONCE_REVERT) {
        setInitialValues() //reset renderer values
        renderer.setNotChanging(changeType)
      } else if (cycle == Renderer.PAUSING) {
        //println("updatePausing, calling setInitialValues!!!!!!!!!!!!!!!!!!!!!!!!")
        setInitialValues() //reset renderer values
        pauseMax = originPauseMax
      } else if (cycle == Renderer.PAUSING_RANDOM) {
        setInitialValues() //reset renderer values
        pauseMax = Randomise.range(0, originPauseMax.toDouble).toInt
        //println("RenderTransform, updatePausing, pauseMax: " + pauseMax)
      }
      pauseCount = 0
      paused = false
      //println("____________RenderTransform, updatePausing  finished, pauseCount: " + pauseCount)
    } else {//pause cycle not finished increment pauseCount
      //println("RenderTransform, updatePausing, pauseCount: " + pauseCount)
      pauseCount = pauseCount + 1
    }
  }

  def updateTransform(changeType: Int, scaley: Int): Unit = {
    if (scaley == scale) {//SPRITE, POLY or POINT
      if (kind == Renderer.NUM_SEQ) { //sequence
        changeType match {
          case Renderer.STROKE_WIDTH => updateStrokeWidth()
          case Renderer.STROKE_COLOR => updateStrokeColor()
          case Renderer.FILL_COLOR => updateFillColor()
          case Renderer.POINT_SIZE => updatePointSize()
          case Renderer.STENCIL_OPACITY => updateOpacity()
          case _ => println("RendertTransform update NUM_SEQ, cycleEnded but no relevant changeType: " + changeType)
        }
      } else if (kind == Renderer.NUM_RAN) { //random
        changeType match {
          case Renderer.STROKE_WIDTH => renderer.strokeWidth = Randomise.range(strokeWidthValues.min, strokeWidthValues.max).toFloat
          case Renderer.STROKE_COLOR => updateStrokeColor()
          case Renderer.FILL_COLOR => updateFillColor()
          case Renderer.POINT_SIZE => renderer.pointSize = Randomise.range(pointSizeValues.min, pointSizeValues.max).toFloat
          case Renderer.STENCIL_OPACITY =>
            if (renderer.stencilConfig != null)
              renderer.stencilConfig.currentOpacity = Randomise.range(opacityValues.min.toDouble, opacityValues.max.toDouble).toFloat
          case _ => println("RendertTransform update NUM_RAN, cycleEnded but no relevant changeType: " + changeType)
        }
        //
      } else if (kind == Renderer.SEQ || kind == Renderer.RAN) {
        changeType match {
          case Renderer.STROKE_COLOR => updateStrokeColorPalette()
          case Renderer.FILL_COLOR   => updateFillColorPalette()
          case Renderer.STROKE_WIDTH => updateStrokeWidthPalette()
          case Renderer.POINT_SIZE   => updatePointSizePalette()
          case _ =>
        }
      } else {
        println("RenderTransform update, no relevant kind")
      }
    }
  }



  private def updateStrokeWidth(): Unit = {
    if (motion == Renderer.UP) {
      if (renderer.strokeWidth < strokeWidthValues.max) {
        renderer.strokeWidth = renderer.strokeWidth + strokeWidthValues.increment
      } else {
        if (pausing) {
          paused = true
        } else {
          renderer.strokeWidth = strokeWidthValues.min
        }
      }
    } else if (motion == Renderer.DOWN) {
      if (renderer.strokeWidth > strokeWidthValues.min) {
        renderer.strokeWidth = renderer.strokeWidth - strokeWidthValues.increment
      } else {
        if (pausing) {
          paused = true
        } else {
          renderer.strokeWidth = strokeWidthValues.max
        }
      }
    } else { //PING_PONG
      if (strokeWidthValues.goingUp) {
        if (renderer.strokeWidth < strokeWidthValues.max) {
          renderer.strokeWidth = renderer.strokeWidth + strokeWidthValues.increment
          if (pausing) {
            if (pingPongUpComplete) {
              if (renderer.strokeWidth > strokeWidthValues.half) {
                paused = true
              }
            }
          }
        } else {//switch direction because reached max
          pingPongUpComplete = true
          strokeWidthValues.goingUp = false
        }
      } else {
        if (renderer.strokeWidth > strokeWidthValues.min) {
          renderer.strokeWidth = renderer.strokeWidth - strokeWidthValues.increment
        } else {//switch direction because reached min
          strokeWidthValues.goingUp = true
        }
      }
    }
  }

  private def updateStrokeColor(): Unit = {
    val currCol: Array[Int] = Colors.colorToArray(renderer.strokeColor)
    var newColor: Array[Int] = currCol
    for (i <- 0 until 4) {
      if (!paused) {
        val colVal: Int = currCol(i)
        if (kind == Renderer.NUM_SEQ) {
          if (motion == Renderer.UP) {
            if (colVal < strokeColorValues.max(i)) {
              newColor(i) = colVal + strokeColorValues.increments(i)
              if (newColor(i) >= strokeColorValues.max(i)) newColor(i) = strokeColorValues.max(i)
            } else {
              if (pausing) {
                if (i == pauseChan) {
                  paused = true
                  if (fixedPauseCol) newColor = pauseColMax
                  else newColor = Randomise.getRandomisedColorArray(pauseColMin, pauseColMax)
                }
              } else {
                newColor(i) = strokeColorValues.min(i)
              }
            }
          } else if (motion == Renderer.DOWN) {
            if (colVal > strokeColorValues.min(i)) {
              newColor(i) = colVal - strokeColorValues.increments(i)
              if (newColor(i) <= strokeColorValues.min(i)) newColor(i) = strokeColorValues.min(i)
            } else {
              if (pausing) {
                if (i == pauseChan) {
                  paused = true
                  if (fixedPauseCol) newColor = pauseColMax
                  else newColor = Randomise.getRandomisedColorArray(pauseColMin, pauseColMax)
                } else {
                  newColor(i) = strokeColorValues.max(i)
                }
              } else {
                newColor(i) = strokeColorValues.max(i)
              }
            }
          } else { // PING_PONG
            if (strokeColorValues.goingUp) {
              if (colVal < strokeColorValues.max(i)) {
                newColor(i) = colVal + strokeColorValues.increments(i)
                if (newColor(i) > 255) strokeColorValues.goingUp = false
                if (pausing) {
                  if (pingPongUpComplete) {
                    if (newColor(i) > strokeColorValues.half(i)) {
                      if (i == pauseChan) paused = true
                    }
                  }
                }
              } else {
                pingPongUpComplete = true
                strokeColorValues.goingUp = false
              }
            } else {
              if (colVal > strokeColorValues.min(i)) {
                newColor(i) = colVal - strokeColorValues.increments(i)
                if (newColor(i) < 0) strokeColorValues.goingUp = true
              }
            }
          }
        } else if (kind == Renderer.NUM_RAN) {
          if (ranCount < ranMax) {
            newColor = Colors.colorToArray(getRandomisedColor(strokeColorValues))
          } else {
            if (pausing) {
              if (i == pauseChan) {
                paused = true
                ranCount = 0
                if (fixedPauseCol) newColor = pauseColMax
                else newColor = Randomise.getRandomisedColorArray(pauseColMin, pauseColMax)
              } else {
                newColor = Colors.colorToArray(getRandomisedColor(strokeColorValues))
              }
            } else {
              ranCount = 0
              newColor = Colors.colorToArray(getRandomisedColor(strokeColorValues))
            }
          }
        }
      }
    }
    ranCount = ranCount + 1
    renderer.strokeColor = new Color(newColor(0), newColor(1), newColor(2), newColor(3))
  }

  private def updateFillColor(): Unit = {
    val currCol: Array[Int] = Colors.colorToArray(renderer.fillColor)
    var newColor: Array[Int] = currCol
    for (i <- 0 until 4) {
      if (!paused) {
        val colVal: Int = currCol(i)
        if(kind == Renderer.NUM_SEQ) {
          if (motion == Renderer.UP) {
            if (colVal < fillColorValues.max(i)) {
              newColor(i) = colVal + fillColorValues.increments(i)
              if (newColor(i) >= fillColorValues.max(i)) {
                newColor(i) = fillColorValues.max(i)
              }
            } else {
              if (pausing) {
                if (i == pauseChan) {
                  paused = true
                  if (fixedPauseCol) {
                    newColor = pauseColMax
                  } else {
                    newColor = Randomise.getRandomisedColorArray(pauseColMin, pauseColMax)
                  }
                }
              } else {
                newColor(i) = fillColorValues.min(i)
              }
            }
          } else if (motion == Renderer.DOWN) {
            if (colVal > fillColorValues.min(i)) {
              newColor(i) = colVal - fillColorValues.increments(i)
              if (newColor(i) <= fillColorValues.min(i)) {
                newColor(i) = fillColorValues.min(i)
              }
            } else {
              if (pausing) {
                if(i == pauseChan) {
                  paused = true
                  if (fixedPauseCol) {
                    newColor = pauseColMax//max is the default fixed color
                  } else {
                    newColor = Randomise.getRandomisedColorArray(pauseColMin, pauseColMax)
                  }
                } else {
                  newColor(i) = fillColorValues.max(i)
                }
              } else {
                newColor(i) = fillColorValues.max(i)
              }
            }
          } else if (motion == Renderer.PING_PONG) {
            if (fillColorValues.goingUp) {
              if (colVal < fillColorValues.max(i)) {
                newColor(i) = colVal + fillColorValues.increments(i)
                if (newColor(i) > 255) {
                  //newColor(i) = 255
                  fillColorValues.goingUp = false
                }
                if (pausing) {
                  if (pingPongUpComplete) {
                    if (newColor(i) > fillColorValues.half(i)) {
                      if (i == pauseChan) {
                        paused = true
                      }
                    }
                  }
                }
              }
            } else {
              if (colVal > fillColorValues.min(i)) {
                newColor(i) = colVal - fillColorValues.increments(i)
                if (newColor(i) < 0) {
                  //newColor(i) = 0
                  fillColorValues.goingUp = true
                }
              }
            }
          }
        } else if (kind == Renderer.NUM_RAN) {
          if (ranCount < ranMax) {
            newColor = Colors.colorToArray(getRandomisedColor(fillColorValues))
          } else {
            if (pausing) {
              if (i == pauseChan) {
                paused = true
                ranCount = 0
                if (fixedPauseCol) {
                  newColor = pauseColMax
                } else {
                  newColor = Randomise.getRandomisedColorArray(pauseColMin, pauseColMax)
                }
              } else {
                newColor = Colors.colorToArray(getRandomisedColor(fillColorValues))
              }
            } else {
              // CONSTANT cycle with no pausing — reset and keep randomising every draw
              ranCount = 0
              newColor = Colors.colorToArray(getRandomisedColor(fillColorValues))
            }
          }
        }
      }
    }
    ranCount = ranCount + 1
    renderer.fillColor = new Color(newColor(0), newColor(1), newColor(2), newColor(3))

  }

  private def updatePointSize(): Unit = {
    if (motion == Renderer.UP) {
      if (renderer.pointSize < pointSizeValues.max) {
        renderer.pointSize = renderer.pointSize + pointSizeValues.increment
      } else {
        if (pausing) {
          paused = true
        } else {
          renderer.pointSize = pointSizeValues.min
        }
      }
    } else if (motion == Renderer.DOWN) {
      if (renderer.pointSize > pointSizeValues.min) {
        renderer.pointSize = renderer.pointSize - pointSizeValues.increment
      } else {
        if (pausing) {
          paused = true
        } else {
          renderer.pointSize = pointSizeValues.max
        }
      }
    } else { //PING_PONG
      if (pointSizeValues.goingUp) {
        if (renderer.pointSize < pointSizeValues.max) {
          renderer.pointSize = renderer.pointSize + pointSizeValues.increment
          if (pausing) {
            if (pingPongUpComplete) {
              if (renderer.pointSize > pointSizeValues.half) {
                paused = true
              }
            }
          }
        } else {
          pingPongUpComplete = true
          pointSizeValues.goingUp = false
        }
      } else {
        if (renderer.pointSize > pointSizeValues.min) {
          renderer.pointSize = renderer.pointSize - pointSizeValues.increment
        } else {
          pointSizeValues.goingUp = true
        }
      }

    }
  }
  private def updateOpacity(): Unit = {
    if (renderer.stencilConfig == null) return
    val sc = renderer.stencilConfig
    if (motion == Renderer.UP) {
      if (sc.currentOpacity < opacityValues.max) {
        sc.currentOpacity = sc.currentOpacity + opacityValues.increment
      } else {
        if (pausing) {
          paused = true
        } else {
          sc.currentOpacity = opacityValues.min
        }
      }
    } else if (motion == Renderer.DOWN) {
      if (sc.currentOpacity > opacityValues.min) {
        sc.currentOpacity = sc.currentOpacity - opacityValues.increment
      } else {
        if (pausing) {
          paused = true
        } else {
          sc.currentOpacity = opacityValues.max
        }
      }
    } else { // PING_PONG
      if (opacityValues.goingUp) {
        if (sc.currentOpacity < opacityValues.max) {
          sc.currentOpacity = sc.currentOpacity + opacityValues.increment
          if (pausing) {
            if (pingPongUpComplete) {
              if (sc.currentOpacity > opacityValues.half) {
                paused = true
              }
            }
          }
        } else {
          pingPongUpComplete = true
          opacityValues.goingUp = false
        }
      } else {
        if (sc.currentOpacity > opacityValues.min) {
          sc.currentOpacity = sc.currentOpacity - opacityValues.increment
        } else {
          opacityValues.goingUp = true
        }
      }
    }
    // clamp to [0,1]
    sc.currentOpacity = math.max(0f, math.min(1f, sc.currentOpacity))
  }

  private def updateStrokeWidthPalette(): Unit = {
    if (strokeWidthPalette.isEmpty) return
    if (kind == Renderer.RAN) {
      strokeWidthPaletteIndex = Randomise.range(0, strokeWidthPalette.length - 1)
    } else {
      if (motion == Renderer.UP) {
        val next = strokeWidthPaletteIndex + 1
        if (next < strokeWidthPalette.length) strokeWidthPaletteIndex = next
        else { if (pausing) paused = true else strokeWidthPaletteIndex = 0 }
      } else if (motion == Renderer.DOWN) {
        val next = strokeWidthPaletteIndex - 1
        if (next >= 0) strokeWidthPaletteIndex = next
        else { if (pausing) paused = true else strokeWidthPaletteIndex = strokeWidthPalette.length - 1 }
      } else { // PING_PONG
        val next = strokeWidthPaletteIndex + strokeWidthPaletteDir
        if (next >= 0 && next < strokeWidthPalette.length) strokeWidthPaletteIndex = next
        else { strokeWidthPaletteDir = -strokeWidthPaletteDir; if (pausing) paused = true }
      }
    }
    renderer.strokeWidth = strokeWidthPalette(strokeWidthPaletteIndex)
  }

  private def updatePointSizePalette(): Unit = {
    if (pointSizePalette.isEmpty) return
    if (kind == Renderer.RAN) {
      pointSizePaletteIndex = Randomise.range(0, pointSizePalette.length - 1)
    } else {
      if (motion == Renderer.UP) {
        val next = pointSizePaletteIndex + 1
        if (next < pointSizePalette.length) pointSizePaletteIndex = next
        else { if (pausing) paused = true else pointSizePaletteIndex = 0 }
      } else if (motion == Renderer.DOWN) {
        val next = pointSizePaletteIndex - 1
        if (next >= 0) pointSizePaletteIndex = next
        else { if (pausing) paused = true else pointSizePaletteIndex = pointSizePalette.length - 1 }
      } else { // PING_PONG
        val next = pointSizePaletteIndex + pointSizePaletteDir
        if (next >= 0 && next < pointSizePalette.length) pointSizePaletteIndex = next
        else { pointSizePaletteDir = -pointSizePaletteDir; if (pausing) paused = true }
      }
    }
    renderer.pointSize = pointSizePalette(pointSizePaletteIndex)
  }

  private def updateStrokeColorPalette(): Unit = {
    if (strokePalette.isEmpty) return
    if (kind == Renderer.RAN) {
      strokePaletteIndex = Randomise.range(0, strokePalette.length - 1)
    } else { // SEQ
      if (motion == Renderer.UP) {
        val next = strokePaletteIndex + 1
        if (next < strokePalette.length) strokePaletteIndex = next
        else { if (pausing) paused = true else strokePaletteIndex = 0 }
      } else if (motion == Renderer.DOWN) {
        val next = strokePaletteIndex - 1
        if (next >= 0) strokePaletteIndex = next
        else { if (pausing) paused = true else strokePaletteIndex = strokePalette.length - 1 }
      } else { // PING_PONG
        val next = strokePaletteIndex + strokePaletteDir
        if (next >= 0 && next < strokePalette.length) {
          strokePaletteIndex = next
        } else {
          strokePaletteDir = -strokePaletteDir
          if (pausing) paused = true
        }
      }
    }
    renderer.strokeColor = strokePalette(strokePaletteIndex)
  }

  private def updateFillColorPalette(): Unit = {
    if (fillPalette.isEmpty) return
    if (kind == Renderer.RAN) {
      fillPaletteIndex = Randomise.range(0, fillPalette.length - 1)
    } else { // SEQ
      if (motion == Renderer.UP) {
        val next = fillPaletteIndex + 1
        if (next < fillPalette.length) fillPaletteIndex = next
        else { if (pausing) paused = true else fillPaletteIndex = 0 }
      } else if (motion == Renderer.DOWN) {
        val next = fillPaletteIndex - 1
        if (next >= 0) fillPaletteIndex = next
        else { if (pausing) paused = true else fillPaletteIndex = fillPalette.length - 1 }
      } else { // PING_PONG
        val next = fillPaletteIndex + fillPaletteDir
        if (next >= 0 && next < fillPalette.length) {
          fillPaletteIndex = next
        } else {
          fillPaletteDir = -fillPaletteDir
          if (pausing) paused = true
        }
      }
    }
    renderer.fillColor = fillPalette(fillPaletteIndex)
  }

  //Inner data class within RenderTransform class - color values
  private class SizeValues() {

    var min: Float = 0
    var max: Float = 0

    var increment: Float = 0
    var incrementCount: Int = 0
    var totalIncrements: Int = 0//possibly useful for calculating ping pong cycle end (total increments * 2)
    var goingUp: Boolean = true
    var half: Float = 0

    def scaleBy(factor: Float): Unit = {
      min = min * factor
      max = max * factor
      half = half * factor
      increment = increment * factor
    }

    //SET SIZE VALUES - max and min ranges
    def setSizeValues(minny: Float, maxxy: Float, inc: Float): Unit = {
      min = minny
      max = maxxy
      half = max-min
      increment = inc
      totalIncrements = ((max-min)/inc).toInt
    }

    def getSizeUp(size: Float): Float = {
      var x: Float = 0
      if (size < max) {
        x = size + increment
      } else {
        x = min
      }
      incrementCount = incrementCount + 1
      x
    }

    def getSizeDown(size: Float): Float = {
      var x: Float = 0
      if (size > min) {
        x = size - increment
      } else {
        x = max
      }
      incrementCount = incrementCount + 1
      x
    }
    def checkPingPongEnd(): Unit = {
      var pingPongEndFlag: Boolean = false
      if (incrementCount >= (totalIncrements * 2)) {
        pingPongEndFlag = true
        resetIncrementCount()
      }
      pingPongEndFlag
    }
    def resetIncrementCount(): Unit = {
      incrementCount = 0
    }
  }


  //Inner data class within RenderTransform class - color values
  private class ColorValues() {

    var min: Array[Int] = Array(0, 0, 0, 0)
    var max: Array[Int] = Array(0, 0, 0, 0)

    var increments: Array[Int] = Array(0,0,0,0)
    var goingUp: Boolean = true
    val half: Array[Int] = Array(0, 0, 0, 0)

    //SET COLOR VALUES - max and min ranges
    def setColorValues(minny: Array[Int], maxxy: Array[Int], inc: Array[Int]): Unit = {
      min = minny
      max = maxxy
      half(0) = (max(0)+min(0))/2
      half(1) = (max(1)+min(1))/2
      half(2) = (max(2)+min(2))/2
      half(3) = (max(3)+min(3))/2
      increments = inc
      /**
       println("**********")
       println("RenderTransform, setColorValues, min and max")
       Output.printColor(min)
       Output.printColor(max)
       println("**********")
       */
    }
    def getChanUp(chan: Int, dex: Int): Int = {
      var x: Int = 0
      if (dex < max(chan)) {
        x = dex + increments(chan)
      } else {
        x = min(chan)
      }
      x
    }
    def getChanDown(chan: Int, dex: Int): Int = {
      var x: Int = 0
      if (dex > min(chan)) {
        x = dex - increments(chan)
      } else {
        x = max(chan)
      }
      x
    }
  }
}

