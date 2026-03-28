/** *************************************************
 * MySketch
 */

//package declaration

package org.loom.mysketch

//import java library classes

import scala.annotation.unused
import scala.collection.mutable
import scala.collection.mutable.ListBuffer

import java.awt.{Color, Graphics2D}

//import loom classes
import org.loom.geometry.*
import org.loom.media.*
import org.loom.scaffold.*
import org.loom.scene.*
import org.loom.config.{ProjectConfigManager, ProjectPaths}

//import Easing
//import org.brogan.animation.easing._


/**
 * This sketch does polygonal subdivision.
 * Please Note:
 * MySketch inherits the following properties from Sketch:
 * backgroundColor, overlayColor, axesColor, axesStrokeWeight, paused, serialByteTeadings, serialStringReadings,
 * renderer.
 * MySketch inherits the following methods from Sketch:
 * setup, update, draw, drawBackground, drawBackgroundOnce, drawOverlay, drawAxes, serialEventNotify.
 */

/**
 * INIT____________________________________________________________________
 */

class MySketch(width: Int, height: Int) extends Sketch(width, height) {

  // Initialize project configuration system
  // Use already loaded project from ProjectSelector, or fall back to hard-coded defaults
  val projectName: String = if (ProjectConfigManager.isProjectLoaded) {
    ProjectConfigManager.currentProject
  } else {
    "" // Use hard-coded defaults
  }
  val useProjectConfig: Boolean = ProjectConfigManager.isProjectLoaded

  // Global settings - from project config or hard-coded defaults
  private val globalConfig = if (useProjectConfig) ProjectConfigManager.getGlobalConfig else null
  val scaleImage: Boolean = if (globalConfig != null) globalConfig.scaleImage else false
  private val quality: Int = Config.qualityMultiple //for adjusting sketch to different quality settings
  private val defaultLineWidth: Float = 1
  private val defaultPointSize: Float = 2f * quality

  //the render set library contains renderer sets that themselves contain renderers
  val renderSetLibrary: RendererSetLibrary = makeRendererSetLibrary("renderSetLibrary")


  //Create list of polygons
  //val polyList: List[Polygon2D] = createPolygons()//for literally creating polygons from scratch (legacy code)

  //Load list of polygons from polygonSet - this is the normal way (create polygon sets in Bezier Draw application)
  val polyCollection: PolygonSetCollection = loadPolygonCollection()

  //Load open curve sets from curves.xml
  val openCurveSetCollection: org.loom.geometry.OpenCurveSetCollection = loadOpenCurveCollection()

  //Load discrete point sets from points.xml
  val pointSetCollection: org.loom.geometry.PointSetCollection = loadPointCollection()

  //Load oval sets from ovals.xml
  val ovalSetCollection: org.loom.geometry.OvalSetCollection = loadOvalCollection()

  //Create a list of subdivision parameters
  val initialSubdivisionType: Int = Subdivision.QUAD //a default
  val subdivisionParamsSetCollection: SubdivisionParamsSetCollection = createSubdivisionParamsSetCollection()

  // Map built inside make2DShapes() using actual indices of successfully created shapes
  private var _shapeNameMap: Map[(String, String), Int] = Map.empty

  //make a list of shapes based on polyCollection
  val shapes2D: ListBuffer[Shape2D] = make2DShapes()

  // Map from (shapeSetName, shapeName) → index in shapes2D for name-based lookup
  val shapeNameMap: Map[(String, String), Int] = buildShapeNameMap()

  val startRotation2D: Double = 0 //needed for heart, set to 0 normally

  //REVISED TO WORK WITH POLYGON SETS. MAY NOT WORK WITH REGULAR POLYGONS ANYMORE
  standShapesUpright()
  reverseShapesHorizontally()

  //2D OR 3D>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  val threeD: Boolean = if (globalConfig != null) globalConfig.threeD else false

  //RECURSIVE SUBDIVIDE IN 2D OR 3D THROUGH LIST OF SUBDIVISIONS
  //if sudividing is TRUE, otherwise just keep original shapes
  val subdividing: Boolean = if (globalConfig != null) globalConfig.subdividing else true
  val subdividedShapes: List[AbstractShape] = makeRecursiveShapes(subdividing)


  //System.out.println("MySketch, recursive subdivision complete, shape: " + shape)

  //val shape: AbstractShape = shape2D//no subdivision

  //OR RUN JUST ONE SPECIFIC SUBDIVISION PER SHAPE (HERE IN 2D)
  /**
   * val shape: AbstractShape = subdivideShape(0)
   * val shape2 = shape.asInstanceOf[Shape2D].subdivide(subdivisionParamsList(2))
   * val shape3 = shape2.asInstanceOf[Shape2D].subdivide(subdivisionParamsList(3))
   * val shape4 = shape3.asInstanceOf[Shape2D].subdivide(subdivisionParamsList(3))
   * val shape5 = shape4.asInstanceOf[Shape2D].subdivide(subdivisionParamsList(2))
   * val shape6 = shape5.clone()
   */
  //val shape2: AbstractShape = makeRecursiveShape()


  //2D OR 3D>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  val sprite2DList: List[Sprite2D] = make2DSpriteList() //make sprites corresponding to subdividedShapes
  //3D
  //val sprite3DList: List[Sprite3D] = make3DSpriteList()

  //create a notional view
  //parameters: screen width, screen height, view width, view height, border width, border height
  val view: View = View(width * Config.qualityMultiple, height * Config.qualityMultiple, width * Config.qualityMultiple, height * Config.qualityMultiple, 0, 0)
  //create a scene
  val scene: Scene = Scene()
  //set properties in Camera object: view3D, viewAngle and scene3D
  Camera.view = view
  Camera.viewAngle = if (globalConfig != null) globalConfig.cameraViewAngle else 120
  Camera.scene = scene

  //2D OR 3D>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  //3D
  /**
   * for (sprit <- sprite3DList) {
   * scene.addSprite(sprit)
   * }
   */

  //2D

  for (sprit <- sprite2DList) {
    scene.addSprite(sprit)
  }


  /**
   * Creates or loads a RendererSetLibrary.
   */
  def makeRendererSetLibrary(n: String, @unused xmlPath: Option[String] = None): RendererSetLibrary = {

    // Try loading from project config first
    if (useProjectConfig) {
      ProjectConfigManager.getRenderingConfig match {
        case Some(library) =>
          println("Loaded RendererSetLibrary from project XML")
          return library
        case None =>
          println("No rendering config in project, falling back to hard-coded")
      }
    }

    //CREATE AN OVERALL RENDERING LIBRARY
    val renderSetLibrary: RendererSetLibrary = RendererSetLibrary(n)

    //CREATE A SET IN THAT LIBRARY
    val renderSetA: RendererSet = RendererSet("BlueOrangeGreenFilled")

    //CREATE A RENDERER IN THAT SET WITH SOME CHANGING FEATURES
    val rendererBlue: Renderer = Renderer("Blue", Renderer.FILLED_STROKED, defaultLineWidth * quality, Renderer.BLACK_FAINT, Renderer.RED, 3, 1)

    val kind: Int = Renderer.SEQ
    val motion: Int = Renderer.UP
    val cycle: Int = Renderer.PAUSING
    val scale: Int = Renderer.POLY
    val params: Array[Int] = Array(kind, motion, cycle, scale)

    val pauseMax = 17

    val fillCInc: Array[Int] = Array(5, 2, 1, 1)
    val fillCMin: Array[Int] = Array(20, 40, 60, 240)
    val fillCMax: Array[Int] = Array(90, 110, 130, 255)
    val pauseChan: Int = Renderer.GREEN_CHAN
    val pauseColMin: Array[Int] = Array(180, 50, 0, 255)
    val pauseColMax: Array[Int] = Array(180, 100, 0, 255)
    rendererBlue.setChangingFillColor(params, fillCMin, fillCMax, fillCInc, pauseMax, pauseChan, pauseColMin, pauseColMax)

    val rendererRed: Renderer = Renderer("Red", Renderer.FILLED, defaultLineWidth * quality, Renderer.BLUE, Renderer.BLUE, defaultPointSize, 1)

    renderSetA.add(rendererBlue)
    renderSetA.add(rendererRed)

    renderSetA.setPreferredRenderer("Blue")
    renderSetA.setCurrentRenderer("Blue")

    renderSetA.modifyRenderers()
    renderSetA.sequenceRendererSet(renderSetA.preferredRendererIndex, 50)

    renderSetLibrary.add(renderSetA)
    renderSetLibrary.setCurrentRendererSet("BlueOrangeGreenFilled")
    renderSetLibrary.setPreferredRendererSet("BlueOrangeGreenFilled")

    renderSetLibrary
  }


  /**
   * LOADPOLYGONSET: Load sets of Bezier Polygons
   */
  def loadPolygonCollection(): PolygonSetCollection = {

    // Try loading from project config first
    if (useProjectConfig) {
      ProjectConfigManager.getPolygonConfig match {
        case Some(collection) =>
          println("Loaded PolygonSetCollection from project XML")
          return collection
        case None =>
          println("No polygon config in project, falling back to hard-coded")
      }
    }

    val polyCollection: PolygonSetCollection = PolygonSetCollection()
    polyCollection.add(PolygonSet(PolygonSetLoader.loadSplinePolygons("Subdivide", "polygonSet", "square_good_centred.xml"), "sixSix"))
    polyCollection
  }


  /**
   * Load open curve sets from curves.xml if present in the project.
   */
  def loadOpenCurveCollection(): org.loom.geometry.OpenCurveSetCollection = {
    if (useProjectConfig) {
      val curvesConfigPath = ProjectConfigManager.getConfigPath("curves")
      if (curvesConfigPath.nonEmpty) {
        val curveSetsPath = ProjectConfigManager.getCurveSetsPath
        return org.loom.media.OpenCurveSetLoader.load(curvesConfigPath, curveSetsPath)
      }
    }
    new org.loom.geometry.OpenCurveSetCollection()
  }

  /**
   * Load discrete point sets from points.xml if present in the project.
   */
  def loadPointCollection(): org.loom.geometry.PointSetCollection = {
    if (useProjectConfig) {
      val pointsConfigPath = ProjectConfigManager.getConfigPath("points")
      if (pointsConfigPath.nonEmpty) {
        val pointSetsPath = ProjectConfigManager.getPointSetsPath
        return org.loom.media.PointSetLoader.load(pointsConfigPath, pointSetsPath)
      }
    }
    new org.loom.geometry.PointSetCollection()
  }

  /**
   * Load oval sets from ovals.xml if present in the project.
   */
  def loadOvalCollection(): org.loom.geometry.OvalSetCollection = {
    if (useProjectConfig) {
      val ovalsConfigPath = ProjectConfigManager.getConfigPath("ovals")
      if (ovalsConfigPath.nonEmpty) {
        val ovalSetsPath = ProjectConfigManager.getOvalSetsPath
        return org.loom.media.OvalSetLoader.load(ovalsConfigPath, ovalSetsPath)
      }
    }
    new org.loom.geometry.OvalSetCollection()
  }

  /**
   * CREATESUBDIVISIONPARAMETERS
   */
  def createSubdivisionParamsSetCollection(): SubdivisionParamsSetCollection = {

    // Try loading from project config first
    if (useProjectConfig) {
      ProjectConfigManager.getSubdivisionConfig match {
        case Some(collection) =>
          println("Loaded SubdivisionParamsSetCollection from project XML")
          return collection
        case None =>
          println("No subdivision config in project, falling back to hard-coded")
      }
    }

    val subPCollection: SubdivisionParamsSetCollection = SubdivisionParamsSetCollection()
    val subPSetA: SubdivisionParamsSet = SubdivisionParamsSet("subPSetA")

    val simple: SubdivisionParams = SubdivisionParams("simple")
    simple.subdivisionType = Subdivision.QUAD
    simple.polysTransform = true
    simple.ranMiddle = true
    simple.ranDiv = 2
    simple.visibilityRule = Subdivision.ALL

    val simpler: SubdivisionParams = SubdivisionParams("simpler")

    subPSetA.add(simpler)
    subPSetA.add(simpler)
    subPSetA.add(simpler)
    subPSetA.add(simpler)
    subPSetA.add(simple)
    subPSetA.add(simple)

    subPCollection.add(subPSetA)
    subPCollection
  }


  def make2DShapes(): ListBuffer[Shape2D] = {

    val shapes: ListBuffer[Shape2D] = ListBuffer[Shape2D]()

    // Try loading from project shape config first
    if (useProjectConfig) {
      ProjectConfigManager.getShapeConfig match {
        case Some(shapeLibrary) =>
          println(s"Creating shapes from ShapeLibrary: ${shapeLibrary.name}")
          val nameMap = mutable.Map[(String, String), Int]()
          for (shapeSet <- shapeLibrary.shapeSets) {
            for (shapeDef <- shapeSet.shapes) {
              val shape = createShapeFromDef(shapeDef)
              if (shape != null) {
                nameMap((shapeSet.name, shapeDef.name)) = shapes.size
                shapes += shape
                println(s"  Created shape: ${shapeDef.name}")
              }
            }
          }
          if (shapes.nonEmpty) {
            _shapeNameMap = nameMap.toMap
            return shapes
          }
          println("No shapes created from config, falling back to hard-coded")
        case None =>
          println("No shape config in project, falling back to hard-coded")
      }
    }

    // Fall back to hard-coded shapes
    val polySet = polyCollection.getPolySet("sixSix")
    val subdivParams = subdivisionParamsSetCollection.getParamsSet("subPSetA")
    if (polySet != null && subdivParams != null) {
      shapes += Shape2D(polySet.polySet, subdivParams)
    } else {
      val squarePolySet = polyCollection.getPolySet("Square")
      if (squarePolySet != null) {
        val defaultParams = subdivisionParamsSetCollection.getParamsSet("default")
        shapes += Shape2D(squarePolySet.polySet, defaultParams)
      }
    }
    shapes
  }


  /**
   * Create a Shape2D from a ShapeDef loaded from XML configuration.
   */
  private def createShapeFromDef(shapeDef: ShapeDef): Shape2D = {

    // Get polygon set
    val polygons: List[Polygon2D] = shapeDef.sourceType match {
      case ShapeConfigLoader.SOURCE_POLYGON_SET =>
        val polySet = polyCollection.getPolySet(shapeDef.polygonSetName)
        if (polySet != null) polySet.polySet.map(_.clone())
        else {
          println(s"  Warning: Polygon set '${shapeDef.polygonSetName}' not found")
          return null
        }
      case ShapeConfigLoader.SOURCE_REGULAR_POLYGON =>
        val diameter = 1.0
        List(PolygonCreator.makePolygon2D(shapeDef.regularPolygonSides, diameter, diameter))
      case ShapeConfigLoader.SOURCE_INLINE_POINTS =>
        if (shapeDef.inlinePoints.nonEmpty) {
          List(Polygon2D(shapeDef.inlinePoints, PolygonType.LINE_POLYGON))
        } else {
          println(s"  Warning: Shape '${shapeDef.name}' has no inline points")
          return null
        }
      case ShapeConfigLoader.SOURCE_OPEN_CURVE_SET =>
        val curveSet = openCurveSetCollection.getSet(shapeDef.openCurveSetName)
        if (curveSet != null) curveSet.curves.map(_.clone())
        else {
          println(s"  Warning: Open curve set '${shapeDef.openCurveSetName}' not found")
          return null
        }
      case ShapeConfigLoader.SOURCE_POINT_SET =>
        val ps = pointSetCollection.getSet(shapeDef.pointSetName)
        if (ps != null) ps.points.map(_.clone())
        else {
          println(s"  Warning: Point set '${shapeDef.pointSetName}' not found")
          return null
        }
      case ShapeConfigLoader.SOURCE_OVAL_SET =>
        val os = ovalSetCollection.getSet(shapeDef.ovalSetName)
        if (os != null) os.ovals.map(_.clone())
        else {
          println(s"  Warning: Oval set '${shapeDef.ovalSetName}' not found")
          return null
        }
      case _ =>
        println(s"  Warning: Unknown source type for shape '${shapeDef.name}'")
        return null
    }

    // Get subdivision params set (optional - can be null)
    val subdivParams: SubdivisionParamsSet = if (shapeDef.subdivisionParamsSetName.nonEmpty) {
      subdivisionParamsSetCollection.getParamsSet(shapeDef.subdivisionParamsSetName)
    } else {
      null
    }

    // Create the shape
    Shape2D(polygons, subdivParams)
  }


  /**
   * Returns the map from (shapeSetName, shapeName) to index in shapes2D.
   * Populated by make2DShapes() using actual indices so null shapes are not counted.
   */
  private def buildShapeNameMap(): Map[(String, String), Int] = _shapeNameMap


  /**
   * MAKE2DSPRITELIST
   */
  def make2DSpriteList(): List[Sprite2D] = {

    // Try loading from project sprite config first
    if (useProjectConfig) {
      ProjectConfigManager.getSpriteConfig match {
        case Some(spriteLibrary) =>
          println(s"Creating sprites from SpriteLibrary: ${spriteLibrary.name}")
          val sprites = ListBuffer[Sprite2D]()

          for (spriteSet <- spriteLibrary.spriteSets) {
            for (spriteDef <- spriteSet.sprites) {
              val shapeIndex = shapeNameMap.getOrElse(
                (spriteDef.shapeSetName, spriteDef.shapeName), -1)
              if (shapeIndex >= 0 && shapeIndex < subdividedShapes.size) {
                val sprite = createSpriteFromDef(spriteDef, shapeIndex)
                if (sprite != null) {
                  sprites += sprite
                  println(s"  Created sprite: ${spriteDef.name} with renderer set: ${spriteDef.rendererSetName}")
                }
              } else {
                println(s"  Warning: Shape '${spriteDef.shapeName}' in set '${spriteDef.shapeSetName}' not found in shapeNameMap")
              }
            }
          }

          if (sprites.nonEmpty) return sprites.toList
          println("No sprites created from config, falling back to hard-coded")
        case None =>
          println("No sprite config in project, falling back to hard-coded")
      }
    }

    // Fall back to hard-coded sprite creation
    val defaultSpriteParams: Sprite2DParams = Sprite2DParams("defaultSpriteParams", Vector2D(0, 0), Vector2D(1, 1), 1)
    val animator2D: Animator2D = Animator2D(true, Vector2D(1, 1), defaultSpriteParams.rotFactor2D, defaultSpriteParams.speedFactor2D)

    val scaleParams: mutable.Map[String, Array[Double]] = mutable.Map(("x" -> Array(-.0008, .0005)), ("y" -> Array(-.0008, .0005)))
    animator2D.setRandomScale(scaleParams)

    val rotationParams: mutable.Map[String, Array[Double]] = mutable.Map(("x" -> Array(-.5, .5)))
    animator2D.setRandomRotation(rotationParams)

    val translationParams: mutable.Map[String, Array[Double]] = mutable.Map(("x" -> Array(-3 * quality, 3 * quality)), ("y" -> Array(-1 * quality, 1 * quality)))
    animator2D.setRandomSpeed(translationParams)

    val animator2DA: Animator2D = Animator2D(true, defaultSpriteParams.scaleFactor2D, defaultSpriteParams.rotFactor2D, defaultSpriteParams.speedFactor2D)

    val TwoRects_SpriteParams: Sprite2DParams = Sprite2DParams("TwoRects_SpriteParams", Vector2D(0 * quality, 0 * quality), Vector2D(1, 1), 0)

    // Get renderer set - try legacy name first, then fallbacks (silent probe via hasRendererSet)
    val rendererSet: RendererSet = {
      if (renderSetLibrary.hasRendererSet("BlueOrangeGreenFilled"))
        renderSetLibrary.getRendererSet("BlueOrangeGreenFilled")
      else if (renderSetLibrary.hasRendererSet("DefaultSet"))
        renderSetLibrary.getRendererSet("DefaultSet")
      else
        renderSetLibrary.getRendererSet(0) // Get first available
    }

    if (rendererSet == null) {
      println("Warning: No renderer set available, sprites will not render correctly")
    }

    if (subdividedShapes.isEmpty) {
      println("Warning: No subdivided shapes available for hard-coded fallback sprite")
      return List()
    }

    val sprite2D1: Sprite2D = Sprite2D(subdividedShapes(0).asInstanceOf[Shape2D], TwoRects_SpriteParams, animator2DA, rendererSet)

    List(sprite2D1)
  }


  /**
   * Create a Sprite2D from a SpriteDef loaded from XML configuration.
   */
  private def createSpriteFromDef(spriteDef: SpriteDef, shapeIndex: Int): Sprite2D = {

    if (shapeIndex >= subdividedShapes.size) {
      println(s"  Warning: No shape available for sprite '${spriteDef.name}'")
      return null
    }

    // Clone so each sprite gets its own mutable Shape2D (Sprite2D constructor mutates it)
    val shape = subdividedShapes(shapeIndex).asInstanceOf[Shape2D].clone()

    // Get renderer set by name from the sprite config
    val rendererSet: RendererSet = {
      if (spriteDef.rendererSetName.nonEmpty) {
        val namedSet = renderSetLibrary.getRendererSet(spriteDef.rendererSetName)
        if (namedSet != null) {
          namedSet
        } else {
          println(s"  Warning: Renderer set '${spriteDef.rendererSetName}' not found, using first available")
          renderSetLibrary.getRendererSet(0)
        }
      } else {
        renderSetLibrary.getRendererSet(0)
      }
    }

    if (rendererSet == null) {
      println(s"  Warning: No renderer set available for sprite '${spriteDef.name}'")
      return null
    }

    // Create sprite params from sprite def
    val spriteParams = Sprite2DParams(
      spriteDef.name,
      spriteDef.position,
      spriteDef.scale,
      spriteDef.rotation
    )

    // Apply animation factors from EditorExtensions
    spriteParams.scaleFactor2D = spriteDef.scaleFactor
    spriteParams.rotFactor2D = spriteDef.rotationFactor
    spriteParams.speedFactor2D = spriteDef.speedFactor
    spriteParams.rotOffset2D = spriteDef.rotationOffset

    // Create animator based on type
    val animatorType = spriteDef.animatorType
    val animationEnabled = spriteDef.animationEnabled

    // Quality scaling factor for pixel-based animation values
    val qf: Double = if (scaleImage && quality > 1) quality.toDouble else 1.0

    val animator: SpriteAnimator = if ((animatorType == "jitter_morph" || animatorType == "keyframe_morph") && spriteDef.morphTargets.nonEmpty) {
      // Morph animation modes — need to build MorphTarget after sprite construction
      // We'll create a placeholder animator here; the morph target gets wired below
      null // placeholder, replaced after sprite construction
    } else if (animatorType == "keyframe" && spriteDef.keyframes.nonEmpty) {
      // Keyframe animation mode — scale position values by quality factor
      val kfs = spriteDef.keyframes.map { kd =>
        Keyframe(kd.drawCycle, kd.posX, kd.posY, kd.scaleX, kd.scaleY, kd.rotation, kd.easing)
      }.sortBy(_.drawCycle).toArray
      KeyframeAnimator(animationEnabled, kfs, spriteDef.loopMode)
    } else {
      // Random jitter animation mode (default)
      // Scale speed factor by quality so pixel-based movement stays proportional
      val scaledSpeedFactor = Vector2D(spriteParams.speedFactor2D.x * qf, spriteParams.speedFactor2D.y * qf)
      val randomAnimator = Animator2D(
        animationEnabled,
        spriteParams.scaleFactor2D,
        spriteParams.rotFactor2D,
        scaledSpeedFactor
      )

      // Enable animation features when factors are non-default or ranges are non-zero
      val hasScaleFactor = spriteDef.scaleFactor.x != 1.0 || spriteDef.scaleFactor.y != 1.0
      if (spriteDef.scaleRangeX != (0.0, 0.0) || spriteDef.scaleRangeY != (0.0, 0.0) || hasScaleFactor) {
        val scaleParams: mutable.Map[String, Array[Double]] = mutable.Map(
          "x" -> Array(spriteDef.scaleRangeX._1, spriteDef.scaleRangeX._2),
          "y" -> Array(spriteDef.scaleRangeY._1, spriteDef.scaleRangeY._2)
        )
        randomAnimator.setRandomScale(scaleParams)
      }

      val hasRotationFactor = spriteDef.rotationFactor != 0.0
      if (spriteDef.rotationRange != (0.0, 0.0) || hasRotationFactor) {
        val rotationParams: mutable.Map[String, Array[Double]] = mutable.Map(
          "x" -> Array(spriteDef.rotationRange._1, spriteDef.rotationRange._2)
        )
        randomAnimator.setRandomRotation(rotationParams)
      }

      val hasSpeedFactor = spriteDef.speedFactor.x != 0.0 || spriteDef.speedFactor.y != 0.0
      if (spriteDef.translationRangeX != (0.0, 0.0) || spriteDef.translationRangeY != (0.0, 0.0) || hasSpeedFactor) {
        // Scale translation ranges by quality factor
        val translationParams: mutable.Map[String, Array[Double]] = mutable.Map(
          "x" -> Array(spriteDef.translationRangeX._1 * qf, spriteDef.translationRangeX._2 * qf),
          "y" -> Array(spriteDef.translationRangeY._1 * qf, spriteDef.translationRangeY._2 * qf)
        )
        randomAnimator.setRandomSpeed(translationParams)
      }
      randomAnimator.jitter = spriteDef.jitter
      randomAnimator
    }

    // For morph modes, we need a temporary non-morph animator to construct the sprite,
    // then build the MorphTarget from the constructed sprite and swap in the real animator.
    if (animator == null && (animatorType == "jitter_morph" || animatorType == "keyframe_morph") && spriteDef.morphTargets.nonEmpty) {
      // Use a dummy animator for construction
      val dummyAnimator = Animator2D(false, Vector2D(1, 1), 0.0, Vector2D(0, 0))
      val sprite = Sprite2D(shape, spriteParams, dummyAnimator, rendererSet)

      // Build morph target
      val morphAnimator = buildMorphAnimator(sprite, spriteDef, animationEnabled)
      if (morphAnimator != null) {
        sprite.animator = morphAnimator
      } else {
        println(s"  Warning: Failed to build morph animator for sprite '${spriteDef.name}', using no animation")
        sprite.animator = Animator2D(false, Vector2D(1, 1), 0.0, Vector2D(0, 0))
      }
      sprite.spriteTotalDraws = spriteDef.totalDraws
      return sprite
    }

    val sprite = Sprite2D(shape, spriteParams, animator, rendererSet)
    sprite.spriteTotalDraws = spriteDef.totalDraws
    sprite
  }


  /**
   * Load a single morph target file and return it as a post-processed, subdivided,
   * transformed Shape2D ready for snapshotting. Returns null on failure.
   */
  private def loadAndPrepareTargetShape(
      filePath: String,
      subdivParams: SubdivisionParamsSet,
      spriteParams: Sprite2DParams
  ): Shape2D = {
    val polygons: List[Polygon2D] = if (filePath.endsWith(".curve.xml")) {
      val curves = org.loom.media.OpenCurveSetLoader.loadOpenCurvesFromFile(filePath)
      if (curves.isEmpty) {
        println(s"  Warning: No curves loaded from morph target: $filePath")
        return null
      }
      curves
    } else {
      val polys = PolygonConfigLoader.loadSplinePolygonsFromFile(filePath)
      if (polys.isEmpty) {
        println(s"  Warning: No polygons loaded from morph target: $filePath")
        return null
      }
      polys
    }

    var targetShape = Shape2D(polygons, subdivParams)

    // Same pre-processing as base shapes (standShapesUpright + reverseShapesHorizontally)
    for (poly <- targetShape.polys) {
      poly.rotate(180)
      for (point <- poly.points) {
        point.x = point.x * -1
      }
    }

    // Subdivide if needed
    if (subdividing && subdivParams != null) {
      targetShape = targetShape.recursiveSubdivide(subdivParams.toList())
    }

    // Apply same constructor transforms as Sprite2D
    val clone = targetShape.clone()
    clone.translate(spriteParams.rotOffset2D)
    clone.rotate(spriteParams.startRotation2D)
    clone.translate(spriteParams.loc2D)
    clone.scale(spriteParams.size2D)
    clone
  }

  /**
   * Build a morph animator (jitter_morph or keyframe_morph) for a constructed sprite.
   * Supports a chain of morph targets: base → mt1 → mt2 → …
   * Dispatches on file extension: .curve.xml → OpenCurveSetLoader, else PolygonConfigLoader.
   */
  private def buildMorphAnimator(sprite: Sprite2D, spriteDef: SpriteDef, animationEnabled: Boolean): SpriteAnimator = {
    try {
      val morphTargetsDir = ProjectPaths.getMorphTargetsPath(projectName)

      // Get subdivision params for the base shape
      val shapeIndex = shapeNameMap.getOrElse((spriteDef.shapeSetName, spriteDef.shapeName), -1)
      val baseShape2D = if (shapeIndex >= 0 && shapeIndex < shapes2D.size) shapes2D(shapeIndex) else null
      val subdivParams = if (baseShape2D != null) baseShape2D.subdivisionParamsSet else null

      val spriteParams = Sprite2DParams(
        "morphTarget",
        spriteDef.position,
        spriteDef.scale,
        spriteDef.rotation
      )
      spriteParams.rotOffset2D = spriteDef.rotationOffset

      // Build snapshot chain: [base, mt1, mt2, ...]
      val baseSnap = MorphTarget.snapshot(sprite.shape)
      val targetSnaps = spriteDef.morphTargets.zipWithIndex.flatMap { case (ref, idx) =>
        val filePath = morphTargetsDir + java.io.File.separator + ref.file
        if (!java.io.File(filePath).exists()) {
          println(s"  Warning: Morph target file not found: $filePath")
          None
        } else {
          val prepared = loadAndPrepareTargetShape(filePath, subdivParams, spriteParams)
          if (prepared == null) {
            println(s"  Warning: Failed to load morph target ${idx + 1} for sprite '${spriteDef.name}'")
            None
          } else if (!MorphTarget.validate(sprite.shape, prepared)) {
            println(s"  Warning: Morph target ${idx + 1} topology mismatch for sprite '${spriteDef.name}'")
            None
          } else {
            Some(MorphTarget.snapshot(prepared))
          }
        }
      }.toArray

      if (targetSnaps.isEmpty) {
        println(s"  Warning: No valid morph targets for sprite '${spriteDef.name}'")
        return null
      }

      val allSnaps: Array[Array[Array[Vector2D]]] = Array(baseSnap) ++ targetSnaps
      val morphTarget = MorphTarget(allSnaps)

      // Create the appropriate morph animator
      spriteDef.animatorType match {
        case "jitter_morph" =>
          JitterMorphAnimator(animationEnabled, morphTarget, spriteDef.morphMin, spriteDef.morphMax)
        case "keyframe_morph" if spriteDef.keyframes.nonEmpty =>
          val mkfs = spriteDef.keyframes.map { kd =>
            MorphKeyframe(kd.drawCycle, kd.posX, kd.posY, kd.scaleX, kd.scaleY, kd.rotation, kd.morphAmount, kd.easing)
          }.sortBy(_.drawCycle).toArray
          KeyframeMorphAnimator(animationEnabled, mkfs, spriteDef.loopMode, morphTarget)
        case _ =>
          println(s"  Warning: keyframe_morph requires keyframes for sprite '${spriteDef.name}'")
          null
      }
    } catch {
      case e: Exception =>
        println(s"  Error building morph animator for sprite '${spriteDef.name}': ${e.getMessage}")
        null
    }
  }


  /**
   * Compute totalDraws from loaded sprite config.
   * Only animated sprites (animationEnabled=true) contribute to the limit.
   * If any animated sprite has totalDraws=0 (infinite), the whole session is infinite.
   * Returns the max totalDraws across animated sprites, or 0 if none are limited.
   */
  private def computeTotalDraws(): Int = {
    if (!useProjectConfig) return 150  // legacy default
    ProjectConfigManager.getSpriteConfig match {
      case Some(spriteLibrary) =>
        var maxDraws = 0
        for (spriteSet <- spriteLibrary.spriteSets) {
          for (spriteDef <- spriteSet.sprites) {
            if (spriteDef.animationEnabled) {
              if (spriteDef.totalDraws == 0) return 0  // animated + no limit → infinite
              if (spriteDef.totalDraws > maxDraws) maxDraws = spriteDef.totalDraws
            }
          }
        }
        if (maxDraws > 0) maxDraws else 0
      case None => 150  // fallback default
    }
  }


  /**
   * SETUP: runs once when the sketch begins
   */
  override def setup(): Unit = {

    // Initialize brush library for BRUSHED rendering mode
    if (useProjectConfig && projectName.nonEmpty) {
      BrushLibrary.initialize(ProjectPaths.getBrushesPath(projectName))
    }

    // Initialize stencil library for STENCILED rendering mode
    if (useProjectConfig && projectName.nonEmpty) {
      StencilLibrary.initialize(ProjectPaths.getStencilsPath(projectName))
    }

    // Apply colors from project config, or use defaults
    if (globalConfig != null) {
      backgroundColor = globalConfig.backgroundColor
      overlayColor = globalConfig.overlayColor
    } else {
      backgroundColor = Color(255, 255, 255)
      overlayColor = Color(0, 0, 0, 170)
    }
    if (scaleImage && quality > 1) {
      val qf = quality.toFloat
      // Scale the legacy renderer
      renderer.strokeWidth = renderer.strokeWidth * qf
      // Scale all XML-loaded renderers in the library
      for (rs <- renderSetLibrary.library) {
        for (r <- rs.rendererSet) {
          r.scalePixelValues(qf)
        }
      }
    }
  }


  /**
   * UPDATE gets called prior to draw each drawing cycle.
   */
  override def update(): Unit = {

    if (!paused) {
      scene.update()
    }
  }


  //--------------------
  /////////ANIMATING

  var drawCount: Int = 0
  var totalDraws: Int = computeTotalDraws()

  var drawingDone: Boolean = false

  var spriteTotal: Int = scene.getSize()
  var spriteIndex: Int = 0

  var polyTotal: Int = 0
  if (threeD) {
    polyTotal = scene.getSprite(spriteIndex).getShape().asInstanceOf[Shape3D].getSize()
  } else {
    polyTotal = scene.getSprite(spriteIndex).getShape().asInstanceOf[Shape2D].getSize()
  }

  var polyCount = 0

  val drawingOnePolyAtATime: Boolean = false
  if (drawingOnePolyAtATime) {
    totalDraws = polyTotal
  }

  /**
   * DRAW: Here is where you draw to the screen
   */
  override def draw(g2D: Graphics2D): Unit = {

    if (Config.drawBackgroundOnce) drawBackgroundOnce(g2D)
    else drawBackground(g2D)

    if (totalDraws == 0 || drawCount < totalDraws) {

      if (drawingOnePolyAtATime) {
        if (polyCount < polyTotal) {
          scene.drawSpritePoly(g2D, spriteIndex, polyCount)
          polyCount += 1
        }
      } else {
        scene.draw(g2D)
      }

    } else {
      if (!drawingDone) {
        println("drawing done: total draws = " + totalDraws)
        drawingDone = true
      }
    }

    drawCount += 1
  }

  /**
   * MAKERECURSIVESHAPE
   */
  def makeRecursiveShapes(subdividing: Boolean): List[AbstractShape] = {

    val shapes: ListBuffer[AbstractShape] = ListBuffer[AbstractShape]()

    if (threeD) {
      //shape = shape.recursiveSubdivide(shape.subdivisionParamsSet.toList).to3D()
      ()
    } else {
      for (shape <- shapes2D) {
        if (subdividing && shape.subdivisionParamsSet != null) {
          shapes += shape.recursiveSubdivide(shape.subdivisionParamsSet.toList())
        } else {
          shapes += shape
        }
      }
    }

    shapes.toList
  }

  /**
   * SUBDIVIDE SHAPE
   */
  def subdivideShape(i: Int): AbstractShape = {
    val shape = shapes2D(i)
    if (shape.subdivisionParamsSet == null) {
      if (threeD) shape.to3D() else shape
    } else if (threeD) {
      shape.subdivide(shape.subdivisionParamsSet.getParams(0)).to3D()
    } else {
      shape.subdivide(shape.subdivisionParamsSet.getParams(0))
    }
  }


  /**
   * STANDSHAPEUPRIGHT
   */
  def standShapesUpright(): Unit = {
    for (shape <- shapes2D) {
      for (poly <- shape.polys) {
        poly.rotate(180)
      }
    }
  }

  /**
   * REVERSESHAPEHORIZONTALLY
   */
  def reverseShapesHorizontally(): Unit = {
    for (shape <- shapes2D) {
      for (poly <- shape.polys) {
        for (point <- poly.points) {
          point.x = point.x * -1
        }
      }
    }
  }

  /**
   * CREATEPOLYGONS - FROM POINTS, VIA POLYGON CREATOR OR AS SPLINES
   */
  def createPolygons(): List[Polygon2D] = {


    val spline: List[Vector2D] = ShapeLoader.load2DShape("Subdivide", "cubicCurve", "b_fish.xml")
    val pS: Polygon2D = Polygon2D(spline, PolygonType.SPLINE_POLYGON)

    List(pS)
  }
}
