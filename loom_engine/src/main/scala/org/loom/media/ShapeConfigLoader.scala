package org.loom.media

import scala.xml.*
import java.io.File
import org.loom.geometry.*

/**
 * Loads ShapeLibrary from shapes.xml configuration files.
 */
object ShapeConfigLoader {

  // Shape source types
  val SOURCE_POLYGON_SET = 0
  val SOURCE_REGULAR_POLYGON = 1
  val SOURCE_INLINE_POINTS = 2

  // 3D shape types
  val SHAPE3D_NONE = 0
  val SHAPE3D_CRYSTAL = 1
  val SHAPE3D_RECT_PRISM = 2
  val SHAPE3D_EXTRUSION = 3
  val SHAPE3D_GRID_PLANE = 4
  val SHAPE3D_GRID_BLOCK = 5

  def load(filePath: String): ShapeLibrary = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Shape config file not found: $filePath")
      return ShapeLibrary("default")
    }

    try {
      val xml = XML.loadFile(filePath)
      parseShapeConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error loading shape config from $filePath: ${e.getMessage}")
        ShapeLibrary("default")
    }
  }

  def loadFromString(xmlContent: String): ShapeLibrary = {
    try {
      val xml = XML.loadString(xmlContent)
      parseShapeConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error parsing shape config XML: ${e.getMessage}")
        ShapeLibrary("default")
    }
  }

  private def parseShapeConfig(root: Elem): ShapeLibrary = {
    val libElem = (root \\ "ShapeLibrary").headOption
    val libraryName = libElem.map(e => (e \ "@name").text).getOrElse("MainLibrary")
    val library = ShapeLibrary(libraryName)

    // Parse ShapeSets
    (root \\ "ShapeSet").foreach { setNode =>
      val shapeSet = parseShapeSet(setNode)
      library.addShapeSet(shapeSet)
    }

    // Also check for Shapes directly under ShapeLibrary (flat structure)
    libElem.foreach { lib =>
      (lib \ "Shape").foreach { shapeNode =>
        if (library.shapeSets.isEmpty) {
          library.addShapeSet(ShapeSet("default"))
        }
        val shapeDef = parseShapeDef(shapeNode)
        library.shapeSets.head.addShape(shapeDef)
      }
    }

    library
  }

  private def parseShapeSet(node: Node): ShapeSet = {
    val name = (node \ "@name").text match {
      case "" => "default"
      case n => n
    }

    val shapeSet = ShapeSet(name)

    (node \ "Shape").foreach { shapeNode =>
      val shapeDef = parseShapeDef(shapeNode)
      shapeSet.addShape(shapeDef)
    }

    shapeSet
  }

  private def parseShapeDef(node: Node): ShapeDef = {
    val name = (node \ "@name").text match {
      case "" => "default"
      case n => n
    }

    val shapeDef = ShapeDef(name)

    // Parse source
    (node \ "Source").headOption.foreach { sourceNode =>
      val sourceType = parseSourceType((sourceNode \ "@type").text)
      shapeDef.sourceType = sourceType

      sourceType match {
        case SOURCE_POLYGON_SET =>
          shapeDef.polygonSetName = (sourceNode \ "@polygonSet").text
        case SOURCE_REGULAR_POLYGON =>
          shapeDef.regularPolygonSides = (sourceNode \ "@sides").text match {
            case "" => 4
            case s => s.toInt
          }
        case SOURCE_INLINE_POINTS =>
          shapeDef.inlinePoints = parseInlinePoints(sourceNode)
        case _ =>
      }
    }

    // Parse subdivision params set reference
    (node \ "SubdivisionParamsSet").headOption.foreach { subdivNode =>
      shapeDef.subdivisionParamsSetName = (subdivNode \ "@name").text
    }

    // Parse 3D shape type
    (node \ "Shape3D").headOption.foreach { shape3dNode =>
      shapeDef.shape3DType = parse3DType((shape3dNode \ "@type").text)
      shapeDef.shape3DParam1 = (shape3dNode \ "@param1").text match {
        case "" => 4
        case s => s.toInt
      }
      shapeDef.shape3DParam2 = (shape3dNode \ "@param2").text match {
        case "" => 4
        case s => s.toInt
      }
      shapeDef.shape3DParam3 = (shape3dNode \ "@param3").text match {
        case "" => 4
        case s => s.toInt
      }
    }

    // Parse transform
    (node \ "Transform").headOption.foreach { transformNode =>
      (transformNode \ "Translation").headOption.foreach { transNode =>
        shapeDef.translateX = (transNode \ "@x").text match {
          case "" => 0.0
          case s => s.toDouble
        }
        shapeDef.translateY = (transNode \ "@y").text match {
          case "" => 0.0
          case s => s.toDouble
        }
      }
      (transformNode \ "Scale").headOption.foreach { scaleNode =>
        shapeDef.scaleX = (scaleNode \ "@x").text match {
          case "" => 1.0
          case s => s.toDouble
        }
        shapeDef.scaleY = (scaleNode \ "@y").text match {
          case "" => 1.0
          case s => s.toDouble
        }
      }
      (transformNode \ "Rotation").headOption.foreach { rotNode =>
        shapeDef.rotation = (rotNode \ "@angle").text match {
          case "" => 0.0
          case s => s.toDouble
        }
      }
    }

    shapeDef
  }

  private def parseInlinePoints(sourceNode: Node): List[Vector2D] = {
    (sourceNode \ "Point").map { pointNode =>
      val x = (pointNode \ "@x").text match {
        case "" => 0.0
        case s => s.toDouble
      }
      val y = (pointNode \ "@y").text match {
        case "" => 0.0
        case s => s.toDouble
      }
      Vector2D(x, y)
    }.toList
  }

  private def parseSourceType(typeStr: String): Int = {
    typeStr.toUpperCase match {
      case "POLYGON_SET" => SOURCE_POLYGON_SET
      case "REGULAR_POLYGON" => SOURCE_REGULAR_POLYGON
      case "INLINE_POINTS" => SOURCE_INLINE_POINTS
      case _ => SOURCE_POLYGON_SET
    }
  }

  private def parse3DType(typeStr: String): Int = {
    typeStr.toUpperCase match {
      case "NONE" => SHAPE3D_NONE
      case "CRYSTAL" => SHAPE3D_CRYSTAL
      case "RECT_PRISM" => SHAPE3D_RECT_PRISM
      case "EXTRUSION" => SHAPE3D_EXTRUSION
      case "GRID_PLANE" => SHAPE3D_GRID_PLANE
      case "GRID_BLOCK" => SHAPE3D_GRID_BLOCK
      case _ => SHAPE3D_NONE
    }
  }
}


/**
 * Shape definition loaded from configuration.
 */
class ShapeDef(val name: String) {
  var sourceType: Int = ShapeConfigLoader.SOURCE_POLYGON_SET
  var polygonSetName: String = ""
  var regularPolygonSides: Int = 4
  var inlinePoints: List[Vector2D] = List.empty
  var subdivisionParamsSetName: String = ""
  var shape3DType: Int = ShapeConfigLoader.SHAPE3D_NONE
  var shape3DParam1: Int = 4
  var shape3DParam2: Int = 4
  var shape3DParam3: Int = 4
  var translateX: Double = 0.0
  var translateY: Double = 0.0
  var scaleX: Double = 1.0
  var scaleY: Double = 1.0
  var rotation: Double = 0.0

  override def toString: String = s"ShapeDef($name, source=$sourceType)"
}


/**
 * A set of shape definitions.
 */
class ShapeSet(val name: String) {
  import scala.collection.mutable.ListBuffer
  private val _shapes: ListBuffer[ShapeDef] = ListBuffer.empty

  def shapes: List[ShapeDef] = _shapes.toList

  def addShape(shape: ShapeDef): Unit = _shapes += shape

  def getShape(shapeName: String): Option[ShapeDef] = _shapes.find(_.name == shapeName)

  override def toString: String = s"ShapeSet($name, shapes=${_shapes.size})"
}


/**
 * Library of shape sets.
 */
class ShapeLibrary(val name: String) {
  import scala.collection.mutable.ListBuffer
  private val _shapeSets: ListBuffer[ShapeSet] = ListBuffer.empty

  def shapeSets: List[ShapeSet] = _shapeSets.toList

  def addShapeSet(shapeSet: ShapeSet): Unit = _shapeSets += shapeSet

  def getShapeSet(setName: String): Option[ShapeSet] = _shapeSets.find(_.name == setName)

  def getShape(setName: String, shapeName: String): Option[ShapeDef] = {
    getShapeSet(setName).flatMap(_.getShape(shapeName))
  }

  override def toString: String = s"ShapeLibrary($name, sets=${_shapeSets.size})"
}
