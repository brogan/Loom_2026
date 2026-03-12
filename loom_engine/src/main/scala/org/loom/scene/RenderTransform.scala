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
  private val strokeColorValues: ColorValues = new ColorValues()
  private val fillColorValues: ColorValues = new ColorValues()


  /**
   * Scale pixel-based size values (stroke width and point size change ranges)
   * by the given factor for quality-multiple consistency.
   */
  def scalePixelValues(factor: Float): Unit = {
    strokeWidthValues.scaleBy(factor)
    pointSizeValues.scaleBy(factor)
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

  def setStrokeColorValues(min: Array[Int], max: Array[Int], increment: Array[Int]): Unit = {
    strokeColorValues.setColorValues(min, max, increment)
  }

  def setFillColorValues(min: Array[Int], max: Array[Int], increment: Array[Int]): Unit = {
    fillColorValues.setColorValues(min, max, increment)
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
    if (motion == Renderer.UP) {
      changeType match {
        case Renderer.STROKE_WIDTH => renderer.strokeWidth = strokeWidthValues.min
        case Renderer.STROKE_COLOR => renderer.strokeColor = new Color(strokeColorValues.min(0), strokeColorValues.min(1), strokeColorValues.min(2), strokeColorValues.min(3))
        case Renderer.FILL_COLOR => renderer.fillColor = new Color(fillColorValues.min(0), fillColorValues.min(1), fillColorValues.min(2), fillColorValues.min(3))
        case Renderer.POINT_SIZE => renderer.pointSize = pointSizeValues.min
        case _ =>
      }
    } else if (motion == Renderer.DOWN) {
      changeType match {
        case Renderer.STROKE_WIDTH => renderer.strokeWidth = strokeWidthValues.max
        case Renderer.STROKE_COLOR => renderer.strokeColor = new Color(strokeColorValues.max(0), strokeColorValues.max(1), strokeColorValues.max(2), strokeColorValues.max(3))
        case Renderer.FILL_COLOR => renderer.fillColor = new Color(fillColorValues.max(0), fillColorValues.max(1), fillColorValues.max(2), fillColorValues.max(3))
        case Renderer.POINT_SIZE => renderer.pointSize = pointSizeValues.max
        case _ =>
      }
    } else if (motion == Renderer.PING_PONG) {
      pingPongUpComplete = false
      changeType match {
        case Renderer.STROKE_WIDTH => renderer.strokeWidth = strokeWidthValues.half
        case Renderer.STROKE_COLOR => renderer.strokeColor = new Color(strokeColorValues.half(0), strokeColorValues.half(1), strokeColorValues.half(2), strokeColorValues.half(3))
        case Renderer.FILL_COLOR => renderer.fillColor = new Color(fillColorValues.half(0), fillColorValues.half(1), fillColorValues.half(2), fillColorValues.half(3))
        case Renderer.POINT_SIZE => renderer.pointSize = pointSizeValues.half
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
      if (kind == Renderer.SEQ) { //sequence
        changeType match {
          case Renderer.STROKE_WIDTH => updateStrokeWidth()
          case Renderer.STROKE_COLOR => updateStrokeColor()
          case Renderer.FILL_COLOR => updateFillColor()
          case Renderer.POINT_SIZE => updatePointSize()
          case _ => println("RendertTransform update SEQ, cycleEnded but no relevant changeType: " + changeType)
        }
      } else if (kind == Renderer.RAN) { //random
        changeType match {
          case Renderer.STROKE_WIDTH => renderer.strokeWidth = Randomise.range(strokeWidthValues.min, strokeWidthValues.max).toFloat
          case Renderer.STROKE_COLOR => renderer.strokeColor = getRandomisedColor(strokeColorValues)
          case Renderer.FILL_COLOR => updateFillColor()//renderer.fillColor = getRandomisedColor(fillColorValues)
          case Renderer.POINT_SIZE => renderer.pointSize = Randomise.range(pointSizeValues.min, pointSizeValues.max).toFloat
          case _ => println("RendertTransform update RAN, cycleEnded but no relevant changeType: " + changeType)
        }
        //
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

    val newColor: Array[Int] = Array(0,0,0,0)
    val currCol: Array[Int] = Colors.colorToArray(renderer.strokeColor)
    for (i <- 0 until 4) {
      val colVal: Int = currCol(i)
      if (motion == Renderer.UP) {
        if (colVal < strokeColorValues.max(i)) {
          newColor(i) = colVal + strokeColorValues.increments(i)
          if (newColor(i) > 255) {
            newColor(i) = 255
          }
        } else {//reached end of UP
          if (pausing) {
            paused = true
          } else {
            newColor(i) = strokeColorValues.min(i)
          }
        }
      } else if (motion == Renderer.DOWN) {
        if (colVal > strokeColorValues.min(i)) {
          newColor(i) = colVal - strokeColorValues.increments(i)
          if (newColor(i) < 0) {
            newColor(i) = 0
          }
        } else {//reached end of DOWN
          if (pausing) {
            paused = true
          } else {
            newColor(i) = strokeColorValues.max(i)
          }
        }
      } else { //PING_PONG
        if (strokeColorValues.goingUp) {
          if (colVal < strokeColorValues.max(i)) {
            newColor(i) = colVal + strokeColorValues.increments(i)
            if (newColor(i) > 255) {
              newColor(i) = 255
            }
            if (pausing) {
              if (pingPongUpComplete) {
                if (colVal > strokeColorValues.half(i)) {
                  paused = true
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
            if (newColor(i) < 0) {
              newColor(i) = 0
            }
          } else {
            strokeColorValues.goingUp = true
          }
        }
      }
    }
    //println("updating stroke color: "+ newColor(0) + ", " + newColor(1) + ", " + newColor(2) + ", " + newColor(3))
    renderer.strokeColor = new Color(newColor(0), newColor(1), newColor(2), newColor(3))
    //val newCol: Array[Int] = Colors.colorToArray(renderer.strokeColor)
    //println("RenderTransform, updating STROKE color, newColor: " + Output.printColor(newColor))

  }

  private def updateFillColor(): Unit = {
    val currCol: Array[Int] = Colors.colorToArray(renderer.fillColor)
    var newColor: Array[Int] = currCol
    for (i <- 0 until 4) {
      if (!paused) {
        val colVal: Int = currCol(i)
        if(kind == Renderer.SEQ) {
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
        } else if (kind == Renderer.RAN) {
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
          renderer.pointSize = renderer.strokeWidth - pointSizeValues.increment
        } else {
          strokeWidthValues.goingUp = true
        }
      }

    }
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

