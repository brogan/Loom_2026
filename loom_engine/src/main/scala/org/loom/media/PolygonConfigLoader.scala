package org.loom.media

import scala.xml.*
import java.io.File
import org.loom.geometry.{PolygonSetCollection, PolygonSet, Polygon2D, PolygonType, PolygonCreator}

/**
 * Loads PolygonSetCollection from polygons.xml configuration files.
 */
object PolygonConfigLoader {

  /**
   * Load an XML file while ignoring DOCTYPE/DTD declarations.
   * Bezier-created polygon files include an ISO-8859-1 DOCTYPE header that
   * scala-xml's default SAX parser tries to resolve and fails on.
   */
  private def loadXMLLenient(filePath: String): Elem = {
    val factory = javax.xml.parsers.SAXParserFactory.newInstance()
    factory.setValidating(false)
    factory.setFeature("http://apache.org/xml/features/nonvalidating/load-dtd-grammar", false)
    factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
    val saxParser = factory.newSAXParser()
    XML.withSAXParser(saxParser).loadFile(filePath)
  }

  def load(filePath: String, resourcesBasePath: String): PolygonSetCollection = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Polygon config file not found: $filePath")
      return PolygonSetCollection()
    }

    try {
      val xml = XML.loadFile(filePath)
      parsePolygonConfig(xml, resourcesBasePath)
    } catch {
      case e: Exception =>
        println(s"Error loading polygon config from $filePath: ${e.getMessage}")
        PolygonSetCollection()
    }
  }

  def loadFromString(xmlContent: String, resourcesBasePath: String): PolygonSetCollection = {
    try {
      val xml = XML.loadString(xmlContent)
      parsePolygonConfig(xml, resourcesBasePath)
    } catch {
      case e: Exception =>
        println(s"Error parsing polygon config XML: ${e.getMessage}")
        PolygonSetCollection()
    }
  }

  private def parsePolygonConfig(root: Elem, resourcesBasePath: String): PolygonSetCollection = {
    val collection = PolygonSetCollection()

    val libNode = (root \ "PolygonSetLibrary").headOption.getOrElse(root)

    (libNode \ "PolygonSet").foreach { psNode =>
      val polygonSet = parsePolygonSet(psNode, resourcesBasePath)
      if (polygonSet != null) {
        collection.add(polygonSet)
      }
    }

    collection
  }

  private def parsePolygonSet(node: Node, resourcesBasePath: String): PolygonSet = {
    val name = (node \ "@name").text
    if (name.isEmpty) {
      println("Warning: PolygonSet without name attribute, skipping")
      return null
    }

    val sourceNode = (node \ "Source").headOption
    if (sourceNode.isEmpty) {
      println(s"Warning: PolygonSet '$name' has no Source element, skipping")
      return null
    }

    val sourceType = (sourceNode.get \ "@type").text

    sourceType match {
      case "file" => loadFileBasedPolygonSet(name, sourceNode.get, resourcesBasePath)
      case "regular" => createRegularPolygonSet(name, sourceNode.get)
      case _ =>
        println(s"Warning: Unknown source type '$sourceType' for PolygonSet '$name', skipping")
        null
    }
  }

  private def loadFileBasedPolygonSet(name: String, sourceNode: Node, resourcesBasePath: String): PolygonSet = {
    val folder = getTextOrDefault(sourceNode, "Folder", "polygonSet")
    val filename = getTextOrDefault(sourceNode, "Filename", "")
    val polygonTypeStr = getTextOrDefault(sourceNode, "PolygonType", "SPLINE_POLYGON")

    if (filename.isEmpty) {
      println(s"Warning: PolygonSet '$name' has empty filename, skipping")
      return null
    }

    // Construct the full file path
    // If folder is specified and not default, use it as subdirectory
    val filePath = if (folder.nonEmpty && folder != "polygonSet") {
      s"$resourcesBasePath${File.separator}$folder${File.separator}$filename"
    } else {
      s"$resourcesBasePath${File.separator}$filename"
    }

    try {
      val polygons: List[Polygon2D] = polygonTypeStr match {
        case "LINE_POLYGON" => loadLinePolygonsFromFile(filePath)
        case "SPLINE_POLYGON" | _ => loadSplinePolygonsFromFile(filePath)
      }

      PolygonSet(polygons, name)
    } catch {
      case e: Exception =>
        println(s"Error loading polygon file for '$name': ${e.getMessage}")
        null
    }
  }

  def loadSplinePolygonsFromFile(filePath: String): List[Polygon2D] = {
    import scala.collection.mutable.ListBuffer

    val polys = ListBuffer[Polygon2D]()
    val polygonSet = loadXMLLenient(filePath)

    val polygons: NodeSeq = (polygonSet \\ "polygon")

    for (polygon <- polygons) {
      val curves: NodeSeq = (polygon \\ "curve")
      val pts = ListBuffer[org.loom.geometry.Vector2D]()

      for (curve <- curves) {
        val points: NodeSeq = (curve \\ "point")

        for (point <- points) {
          val x = (point \ "@x").text.toDouble
          val y = (point \ "@y").text.toDouble
          pts += org.loom.geometry.Vector2D(x, y)
        }
      }

      polys += Polygon2D(pts.toList, PolygonType.SPLINE_POLYGON)
    }

    polys.toList
  }

  private def loadLinePolygonsFromFile(filePath: String): List[Polygon2D] = {
    import scala.collection.mutable.ListBuffer

    val polys = ListBuffer[Polygon2D]()
    val polygonSet = loadXMLLenient(filePath)

    val polygons: NodeSeq = (polygonSet \\ "polygon")

    for (polygon <- polygons) {
      val curves: NodeSeq = (polygon \\ "curve")
      val pts = ListBuffer[org.loom.geometry.Vector2D]()

      for (curve <- curves) {
        val points: NodeSeq = (curve \\ "point")

        for (i <- 0 until points.length) {
          if (i == 0 || i == 3) {
            val point = points(i)
            val x = (point \ "@x").text.toDouble
            val y = (point \ "@y").text.toDouble
            pts += org.loom.geometry.Vector2D(x, y)
          }
        }
      }

      polys += Polygon2D(pts.toList, PolygonType.LINE_POLYGON)
    }

    polys.toList
  }

  private def createRegularPolygonSet(name: String, sourceNode: Node): PolygonSet = {
    val totalPoints = getIntOrDefault(sourceNode, "TotalPoints", 4)
    val internalRadius = getDoubleOrDefault(sourceNode, "InternalRadius", 0.5)
    val offset = getDoubleOrDefault(sourceNode, "Offset", 0.0)
    val scaleX = getDoubleOrDefault(sourceNode, "ScaleX", 1.0)
    val scaleY = getDoubleOrDefault(sourceNode, "ScaleY", 1.0)
    val rotationAngle = getDoubleOrDefault(sourceNode, "RotationAngle", 0.0)
    val transX = getDoubleOrDefault(sourceNode, "TransX", 0.5)
    val transY = getDoubleOrDefault(sourceNode, "TransY", 0.5)
    val positiveSynch = getBooleanOrDefault(sourceNode, "PositiveSynch", true)
    val synchMultiplier = getDoubleOrDefault(sourceNode, "SynchMultiplier", 1.0)

    // Star polygon: totalPoints outer tips, totalPoints inner points = 2*totalPoints vertices
    // Outer radius = 0.5, inner radius = internalRadius
    // proportion maps to makePolygon2DStar's proportion param: inner/outer ratio
    val numberOfSides = totalPoints * 2
    val outerDiameter = 1.0  // outer radius = 0.5
    val proportion = internalRadius * 2  // inner_r / outer_r = internalRadius / 0.5

    val polygon = PolygonCreator.makePolygon2DStar(
      numberOfSides, outerDiameter, proportion, positiveSynch, synchMultiplier
    )

    // Apply offset rotation (rotates the starting position of the star)
    if (offset != 0.0) {
      polygon.rotate(offset)
    }

    // Apply non-uniform scale (makePolygon2DStar only supports uniform diameter)
    if (scaleX != 1.0 || scaleY != 1.0) {
      polygon.scale(org.loom.geometry.Vector2D(scaleX, scaleY))
    }

    if (rotationAngle != 0.0) {
      polygon.rotate(rotationAngle)
    }

    if (transX != 0.5 || transY != 0.5) {
      polygon.translate(org.loom.geometry.Vector2D(transX - 0.5, transY - 0.5))
    }

    PolygonSet(List(polygon), name)
  }

  private def getTextOrDefault(node: Node, elem: String, default: String): String = {
    (node \ elem).headOption.map(_.text.trim).filter(_.nonEmpty).getOrElse(default)
  }

  private def getIntOrDefault(node: Node, elem: String, default: Int): Int = {
    try {
      (node \ elem).headOption.map(_.text.trim.toInt).getOrElse(default)
    } catch {
      case _: NumberFormatException => default
    }
  }

  private def getDoubleOrDefault(node: Node, elem: String, default: Double): Double = {
    try {
      (node \ elem).headOption.map(_.text.trim.toDouble).getOrElse(default)
    } catch {
      case _: NumberFormatException => default
    }
  }

  private def getBooleanOrDefault(node: Node, elem: String, default: Boolean): Boolean = {
    (node \ elem).headOption.map(_.text.trim.toLowerCase) match {
      case Some("true") | Some("1") | Some("yes") => true
      case Some("false") | Some("0") | Some("no") => false
      case _ => default
    }
  }
}
