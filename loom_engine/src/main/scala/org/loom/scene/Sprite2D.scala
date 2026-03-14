/**
 Sprite2D represents a 2D sprite with a location, size and speed.  A sprite contains a shape, which is composed of a set of polygons, each of which are themselves composed of a set of Vector2Ds.  A sprite gets moved around a screen, while the underlying shape always remains at 0,0 for rotation and scaling purposes.  The trick is to draw the shape wherever the sprite happens to be - so at the last second we add the x and y of the sprite to the shapes 0,0 oriented coordinates.
 Parameters
 SHAPE: the Shape2D to move, rotate, scale
 LOCATION: the x,y coordinate of the sprite (Vector2D)
 SIZE: the x,y dimensions of the sprite (Vector2D)
 ROTATION: the angle of rotation
 SPEED: the x,y movement vector (Vector2D)
 ANIMATOR: takes a custom animator class which extends Animator2D
 RENDERER: renderer for the sprite
 */

package org.loom.scene

import scala.annotation.unused

import org.loom.geometry._
import org.loom.utility._
import org.loom.scaffold.Config

import java.awt.{Graphics2D, BasicStroke}
import java.awt.geom._
import java.awt.Polygon
import java.awt.image.BufferedImage

class Sprite2D(val shape: Shape2D, val spriteParams: Sprite2DParams, var animator: SpriteAnimator, var rendererSet: RendererSet) extends Drawable {

  // Brush rendering state (lazy-initialized when BRUSHED mode is used)
  var brushState: BrushState = null

  var location: Vector2D = spriteParams.loc2D
  //var size: Vector2D = new Vector2D(spriteParams.size2D.x * spriteParams.sizeFactor.x, spriteParams.size2D.y * spriteParams.sizeFactor.y)
  var size: Vector2D = new Vector2D(spriteParams.size2D.x, spriteParams.size2D.y)
  System.out.println("Sprite2D, constructor, translate, rotate and scale shape, shape: " + shape)
  shape.translate(spriteParams.rotOffset2D)//move shape not sprite because establishing rotation point
  System.out.println("Sprite2D, constructor, internal call to rotate")
  rotate(spriteParams.startRotation2D)//at beginning (or whenever necessary)
  translate(spriteParams.loc2D)
  scale(size)//at beginning (or whenever necessary)


  /**
   Get Shape2D
   */
  def getShape(): Shape2D = {
    shape
  }
  /**
   Get Shape3D
   NOT USED here
   */
  def getShape3D(): Shape3D = {
    null
  }
  /**
   Get number of shapes
   */
  def getSize(): Int = {
    shape.getSize()
  }
  /**
   Translate the sprite position
  @param trans new position (Vector2D)
   */
  def translate(trans: Vector2D): Unit = {
    //println("***Sprite2D, translate: " + trans)
    //maybe losinginitial tranlation
    //location = Transform2D.translate(location, trans)//is this necessary (referred to in getPolygonFromPolygon2D() below
    shape.translate(trans)
    //println("***Sprite2D, location: " + location)
  }

  /**
   Scale the sprite
  @param s scaling factor (Vector2D)
   */
  def scale(scale: Vector2D): Unit = {
    shape.scale(scale)
  }
  /**
   Rotate the sprite 
  @param angle angle increment
   */
  def rotate(angle: Double): Unit = {
    //println("Sprite2D, rotate function: call to shape2D to rotate, shape: " + shape)
    shape.rotate(angle)
  }
  /**
   Rotate the sprite around a parent
   Not implemented 
  @param angle angle increment
   */
  def rotateAroundParent(rot: Double, parent: Vector2D): Unit = {
    //shape.rotate(angle)
  }
  /**
   Clone the Sprite2D.  Produces an independent copy.
  @return cloned Sprite2D
   */
  override def clone(): Sprite2D = {
    println ("Sprite2D, clone")
    val s: Shape2D = shape.clone()
    val sz: Vector2D = size.clone()
    val ro: Vector2D = spriteParams.rotOffset2D.clone()

    s.translate(Vector2D.invert(ro))//to return it back to original centred position
    val invertedStartRotation: Double = -(spriteParams.startRotation2D)
    s.rotate(invertedStartRotation)
    s.scale(new Vector2D(1/sz.x, 1/sz.y))//to return it back to original scale

    val a: SpriteAnimator = animator.cloneAnimator()
    val r: RendererSet = rendererSet
    new Sprite2D(s, spriteParams, a, r)
  }
  /**
   Check intersect with another sprite within a specific distance
  @param otherSprite the other sprite (Vector2D)
  @param dist collision distance
  @return Boolean
   */
  def checkIntersect(otherSprite: Sprite2D, dist: Double): Boolean = {
    val h: Double = Formulas.hypotenuse(location, otherSprite.location)
    if (h<=dist) true else false
  }
  /**
   toString - gets location, size, startRotation and rotOffset
  @return String representation of sprite2D properties
   */
  override def toString(): String = "Sprite2D location: (" + location.x + ", " + location.y + ")  size: (" +
    size.x + ", " + size.y + ")  start rotation: " + spriteParams.startRotation2D + "  rotOffset: (" + spriteParams.rotOffset2D.x + ", " + spriteParams.rotOffset2D.y + ")"

  def update(): Unit = {

    animator.update(this)
  }
  /**
   Draw, draws a sprite
   Handles all sprite draw calls and passes them to specialised rendering methods depending on the rendering mode.
  @param g2D the Graphics2D context
   */
  def draw(g2D: Graphics2D): Unit = {
    /**
     println("")
     println("drawing at sprite level")
     */
    //val ren: Renderer = rendererSet.getRenderer()
    var holdRendererCount: Int = 0
    val changeRenMax: Int = rendererSet.getRenderer(rendererSet.selectedIndex).holdLength

    var ren: Renderer = rendererSet.getRenderer(rendererSet.selectedIndex)

    for (poly <- shape.polys) {

      if (holdRendererCount > changeRenMax) {
        ren = rendererSet.getNextRenderer()
        holdRendererCount = 0
      } else {
        holdRendererCount = holdRendererCount + 1
      }

      rendererSet.setCurrentRenderer(ren.name)
      //println("Sprite: renderer: " + ren.mode)

      ren.mode match {
        case Renderer.POINTS => if (poly.visible) drawPoints(g2D, poly, Camera.view)
        case Renderer.STROKED => if (poly.visible) drawLines(g2D, poly, Camera.view)
        case Renderer.FILLED => if (poly.visible) drawFilled(g2D, poly, Camera.view)
        case Renderer.FILLED_STROKED => if (poly.visible) drawFilledStroked(g2D, poly, Camera.view)
        case Renderer.BRUSHED =>
          // BRUSHED handles all polys at once (for edge deduplication) — draw once then skip per-poly loop
          drawBrushed(g2D, Camera.view)
          // Update at both scales so dynamic changes fire regardless of user's scale setting
          rendererSet.updateRenderer(Renderer.POLY)
          rendererSet.updateRenderer(Renderer.SPRITE)
          return
      }
      //UPDATE RENDERER AT POLY LEVEL
      //println("SPRITE 2D DRAW - GOING THROUGH EACH POLY")
      rendererSet.updateRenderer(Renderer.POLY)//renderer only gets updated if it's internal scale field is set to poly level updating
    }
    //UPDATE RENDERER AT SPRITE LEVEL
    rendererSet.updateRenderer(Renderer.SPRITE)////renderer only gets updated if it's internal scale field is set to sprite level updating

  }

  /**
   Draw, draws a particular Polygon2D within a Shape within a Sprite
   Handles all sprite draw calls and passes them to specialised rendering methods depending on the rendering mode.
  @param g2D the Graphics2D context
   */
  def drawPoly(g2D: Graphics2D, index: Int): Unit = {
    /**
     println("")
     println("drawing at poly level")
     */

    val poly: Polygon2D = shape.polys(index)
    val ren = rendererSet.getRenderer(rendererSet.selectedIndex)

    //UPDATE RENDERER AT POLY LEVEL
    //rendererSet.updateRenderer(Renderer.POLY)

    //println("Sprite2D, drawPoly, update poly")
    ren.mode match {
      case Renderer.POINTS => if (poly.visible) drawPoints(g2D, poly, Camera.view)
      case Renderer.STROKED => if (poly.visible) drawLines(g2D, poly, Camera.view)
      case Renderer.FILLED => if (poly.visible) drawFilled(g2D, poly, Camera.view)
      case Renderer.FILLED_STROKED => if (poly.visible) drawFilledStroked(g2D, poly, Camera.view)
      //case Renderer.FILLED_STROKED => for (i <- 0 until 1) drawFilledStroked(g2D, shape.polys(i), Camera.view)
    }

  }

  def drawPoints(g2D: Graphics2D, pol: Polygon2D, view: View): Unit = {

    val ren = rendererSet.getRenderer(rendererSet.selectedIndex)

    val polyCorrected: Polygon2D = coordinateCorrect(pol, view)

    val sX: Int = location.x.toInt
    val sY: Int = location.y.toInt
    for(point <- polyCorrected.points) {

      //UPDATE RENDERER AT POINT LEVEL
      rendererSet.updateRenderer(Renderer.POINT)//UPDATE RENDERER TRANSFORM

      g2D.setStroke(new BasicStroke(ren.strokeWidth))
      val e: Ellipse2D.Double = new Ellipse2D.Double(point.x.toInt + sX, point.y.toInt + sY, ren.pointSize, ren.pointSize)
      //val e: Ellipse2D.Double = new Ellipse2D.Double(point.x.toInt + sX, point.y.toInt + sY, 10, 10)
      val pointFilled = ren.pointFilled
      val pointStroked = ren.pointStroked
      if (pointFilled && pointStroked) {
        //println("filled and stroked")
        g2D.setColor(ren.fillColor)
        g2D.fill(e)
        g2D.setColor(ren.strokeColor)
        g2D.draw(e)
      } else if (pointFilled && !pointStroked) {
        //println("just filled")
        g2D.setColor(ren.fillColor)
        g2D.fill(e)
      } else {
        g2D.setColor(ren.strokeColor)
        g2D.draw(e)
      }

    }
  }


  /** Render a POINT_POLYGON as a small filled ellipse at the point's transformed position. */
  def drawPoint(g2D: Graphics2D, pol: Polygon2D, view: View): Unit = {
    if (pol.points.isEmpty) return
    val polyCorrected: Polygon2D = coordinateCorrect(pol, view)
    val pt = polyCorrected.points.head
    val ren = rendererSet.getRenderer(rendererSet.selectedIndex)
    val dotSize = (ren.pointSize).toInt max 2
    val dotRadius = dotSize / 2
    g2D.setColor(ren.strokeColor)
    g2D.fillOval(pt.x.toInt - dotRadius, pt.y.toInt - dotRadius, dotSize, dotSize)
  }

  def drawLines(g2D: Graphics2D, pol: Polygon2D, view: View): Unit = {
    if (pol.polyType == PolygonType.POINT_POLYGON) { drawPoint(g2D, pol, view); return }

    val polyCorrected: Polygon2D = coordinateCorrect(pol, view)
    //val polyCorrected: Polygon2D = pol

    val poly: Polygon = getPolygonFromPolygon2D(polyCorrected)

    val ren = rendererSet.getRenderer(rendererSet.selectedIndex)
    //rendererSet.updateRenderer(Renderer.POLY)//UPDATE RENDERER TRANSFORM

    //println("____________________DRAWING POLY")

    if (pol.polyType == PolygonType.LINE_POLYGON) {
      g2D.setColor(ren.strokeColor)
      g2D.setStroke(new BasicStroke(ren.strokeWidth))
      g2D.draw(poly)
    } else {
      //iterate through each of the spline segments in the spline Polygon3d
      //println("poly sides total: " + poly2D.sidesTotal)
      val path: GeneralPath = new GeneralPath(Path2D.WIND_EVEN_ODD)
      path.moveTo(polyCorrected.points(0).x.toFloat, polyCorrected.points(0).y.toFloat)
      //println("polyCorrected points length: " + polyCorrected.points.length)
      for (i <- 0 until pol.sidesTotal) {
        //println ("i: " + i)

        val c1X: Float = polyCorrected.points(1 + i*4).x.toFloat
        val c1Y: Float = polyCorrected.points(1 + i*4).y.toFloat
        val c2X: Float = polyCorrected.points(2 + i*4).x.toFloat
        val c2Y: Float = polyCorrected.points(2 + i*4).y.toFloat
        val a2X: Float = polyCorrected.points(3 + i*4).x.toFloat
        val a2Y: Float = polyCorrected.points(3 + i*4).y.toFloat

        path.curveTo(c1X, c1Y, c2X, c2Y, a2X, a2Y);
      }
      g2D.setColor(ren.strokeColor)
      g2D.setStroke(new BasicStroke(ren.strokeWidth))
      g2D.draw(path)
    }

  }

  def drawFilled(g2D: Graphics2D, pol: Polygon2D, view: View): Unit = {
    // Discrete points rendered as filled ellipses.
    if (pol.polyType == PolygonType.POINT_POLYGON) { drawPoint(g2D, pol, view); return }
    // Open curves cannot be filled — render as stroked line instead.
    if (pol.polyType == PolygonType.OPEN_SPLINE_POLYGON) { drawLines(g2D, pol, view); return }
    //println("drawFilled at sprite level")
    val polyCorrected: Polygon2D = coordinateCorrect(pol, view)

    val poly: Polygon = getPolygonFromPolygon2D(polyCorrected)
    val ren = rendererSet.getRenderer(rendererSet.selectedIndex)

    //rendererSet.updateRenderer(Renderer.POLY)

    if (pol.polyType == PolygonType.LINE_POLYGON) {
      g2D.setColor(ren.fillColor)
      g2D.fill(poly)
    } else {
      //iterate through each of the spline segments in the spline Polygon3d
      //println("poly sides total: " + poly2D.sidesTotal)
      val path: GeneralPath = new GeneralPath(Path2D.WIND_EVEN_ODD)
      path.moveTo(polyCorrected.points(0).x.toFloat, polyCorrected.points(0).y.toFloat)
      for (i <- 0 until pol.sidesTotal) {
        val c1X: Float = polyCorrected.points(1 + i*4).x.toFloat
        val c1Y: Float = polyCorrected.points(1 + i*4).y.toFloat
        val c2X: Float = polyCorrected.points(2 + i*4).x.toFloat
        val c2Y: Float = polyCorrected.points(2 + i*4).y.toFloat
        val a2X: Float = polyCorrected.points(3 + i*4).x.toFloat
        val a2Y: Float = polyCorrected.points(3 + i*4).y.toFloat
        path.curveTo(c1X, c1Y, c2X, c2Y, a2X, a2Y);
      }
      /**
       println("drawing filled with current renderer color:")
       Output.printColor(ren.fillColor)
       println("_________________________________________")
       */
      g2D.setColor(ren.fillColor)
      g2D.fill(path)
    }

  }

  def drawFilledStroked(g2D: Graphics2D, pol: Polygon2D, view: View): Unit = {
    // Discrete points rendered as filled ellipses.
    if (pol.polyType == PolygonType.POINT_POLYGON) { drawPoint(g2D, pol, view); return }
    // Open curves cannot be filled — render as stroked line instead.
    if (pol.polyType == PolygonType.OPEN_SPLINE_POLYGON) { drawLines(g2D, pol, view); return }

    val polyCorrected: Polygon2D = coordinateCorrect(pol, view)

    val poly: Polygon = getPolygonFromPolygon2D(polyCorrected)
    val ren = rendererSet.getRenderer(rendererSet.selectedIndex)

    if (pol.polyType == PolygonType.LINE_POLYGON) {

      g2D.setColor(ren.fillColor)

      g2D.fill(poly)
      g2D.setColor(ren.strokeColor)
      g2D.setStroke(new BasicStroke(ren.strokeWidth))
      g2D.draw(poly)
    } else {

      g2D.setColor(ren.fillColor)

      //iterate through each of the spline segments in the spline Polygon3d
      //println("poly sides total: " + poly2D.sidesTotal)
      //val path: GeneralPath = new GeneralPath(Path2D.WIND_EVEN_ODD)
      val path: GeneralPath = new GeneralPath(Path2D.WIND_NON_ZERO)
      path.moveTo(polyCorrected.points(0).x.toFloat, polyCorrected.points(0).y.toFloat)
      for (i <- 0 until pol.sidesTotal) {
        val c1X: Float = polyCorrected.points(1 + i*4).x.toFloat
        val c1Y: Float = polyCorrected.points(1 + i*4).y.toFloat
        val c2X: Float = polyCorrected.points(2 + i*4).x.toFloat
        val c2Y: Float = polyCorrected.points(2 + i*4).y.toFloat
        val a2X: Float = polyCorrected.points(3 + i*4).x.toFloat
        val a2Y: Float = polyCorrected.points(3 + i*4).y.toFloat
        path.curveTo(c1X, c1Y, c2X, c2Y, a2X, a2Y);
      }
      g2D.fill(path)
      g2D.setColor(ren.strokeColor)
      g2D.setStroke(new BasicStroke(ren.strokeWidth))
      g2D.draw(path)
    }

  }

  /**
   * Draw all polygon edges using brush stamps.
   * Handles edge deduplication across all visible polygons.
   */
  def drawBrushed(g2D: Graphics2D, view: View): Unit = {
    val ren = rendererSet.getRenderer(rendererSet.selectedIndex)
    val config = ren.brushConfig
    if (config == null) return

    val brushes = loadBrushImages(config, ren)
    if (brushes.isEmpty) return

    // Coordinate-correct all visible polys
    val correctedPolys: List[Polygon2D] = shape.polys.filter(_.visible).map(p => coordinateCorrect(p, view))

    // POINT_POLYGON: stamp a single brush at each point position
    for (poly <- correctedPolys if poly.polyType == PolygonType.POINT_POLYGON) {
      if (poly.points.nonEmpty)
        BrushStampEngine.stampAtPoint(g2D, poly.points.head, config, brushes, ren.strokeColor)
    }

    val edgePolys = correctedPolys.filter(_.polyType != PolygonType.POINT_POLYGON)
    if (edgePolys.isEmpty) return

    // For FULL_PATH mode, re-extract edges each frame (shape may be animated)
    if (config.drawMode == BrushConfig.FULL_PATH) {
      val state = new BrushState()
      state.initializeFromPolys(edgePolys)

      for (edge <- state.edges) {
        BrushStampEngine.drawFullEdge(g2D, edge, config, brushes, ren.strokeColor)
      }
    } else {
      // PROGRESSIVE mode: lazy-init state, advance agents each frame
      if (brushState == null || !brushState.initialized) {
        brushState = new BrushState()
        brushState.initializeFromPolys(edgePolys)
        brushState.createAgents(config.agentCount)
      }

      for (agent <- brushState.agents) {
        if (!agent.completed) {
          BrushStampEngine.drawProgressiveStamps(
            g2D, brushState.edges, agent, config, brushes,
            ren.strokeColor, config.stampsPerFrame
          )
        }
      }

      brushState.checkCompletion(config.postCompletionMode)
    }
  }

  /**
   * Load brush images for the current renderer's brush config.
   * Returns un-tinted brushes — the stamp engine handles tinting per-stamp.
   */
  private def loadBrushImages(config: BrushConfig, @unused ren: Renderer): Array[BufferedImage] = {
    config.brushNames.flatMap { name =>
      val img = BrushLibrary.getBrush(name, Config.qualityMultiple, config.blurRadius)
      Option(img)
    }
  }

  def coordinateCorrect(pol: Polygon2D, view: View): Polygon2D = {
    val ccPoints: Array[Vector2D] = new Array[Vector2D](pol.points.length)
    var count: Int = 0
    for (point <- pol.points) {
      val coordinateCorrection: Vector2D = view.viewToScreenVertex(new Vector2D(point.x, point.y))
      ccPoints(count) = new Vector2D(coordinateCorrection.x, coordinateCorrection.y)
      count += 1
    }
    new Polygon2D(ccPoints.toList, pol.polyType)

  }

  def getPolygonFromPolygon2D(pol: Polygon2D): Polygon = {
    val tot: Int = pol.points.length
    val sX: Int = location.x.toInt
    val sY: Int = location.y.toInt
    val xPoints: Array[Int] = new Array[Int](tot)
    val yPoints: Array[Int] = new Array[Int](tot)
    for (i <- 0 until tot) {
      xPoints(i) = pol.points(i).x.toInt + sX
      yPoints(i) = pol.points(i).y.toInt + sY
    }
    new Polygon(xPoints, yPoints, tot)
  }

}
