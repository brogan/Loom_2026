package org.loom.media

import scala.xml.*
import java.io.File
import org.loom.geometry.{PointSet, PointSetCollection, Polygon2D, PolygonType, Vector2D}
import scala.collection.mutable.ListBuffer

/**
 * Loads PointSetCollection from points.xml configuration files.
 * points.xml structure mirrors curves.xml but uses <PointSetLibrary> / <PointSet> elements
 * and references files in the pointSets/ directory.
 */
object PointSetLoader {

  private def loadXMLLenient(filePath: String): Elem = {
    val factory = javax.xml.parsers.SAXParserFactory.newInstance()
    factory.setValidating(false)
    factory.setFeature("http://apache.org/xml/features/nonvalidating/load-dtd-grammar", false)
    factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
    val saxParser = factory.newSAXParser()
    XML.withSAXParser(saxParser).loadFile(filePath)
  }

  def load(filePath: String, resourcesBasePath: String): PointSetCollection = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Point config file not found: $filePath")
      return PointSetCollection()
    }
    try {
      val xml = XML.loadFile(filePath)
      parsePointConfig(xml, resourcesBasePath)
    } catch {
      case e: Exception =>
        println(s"Error loading point config from $filePath: ${e.getMessage}")
        PointSetCollection()
    }
  }

  private def parsePointConfig(root: Elem, resourcesBasePath: String): PointSetCollection = {
    val collection = PointSetCollection()
    val libNode = (root \ "PointSetLibrary").headOption.getOrElse(root)

    (libNode \ "PointSet").foreach { setNode =>
      val ps = parsePointSetEntry(setNode, resourcesBasePath)
      if (ps != null) collection.add(ps)
    }
    collection
  }

  private def parsePointSetEntry(node: Node, resourcesBasePath: String): PointSet = {
    val name = (node \ "@name").text
    if (name.isEmpty) {
      println("Warning: PointSet without name attribute, skipping")
      return null
    }
    val sourceNode = (node \ "Source").headOption
    if (sourceNode.isEmpty) {
      println(s"Warning: PointSet '$name' has no Source element, skipping")
      return null
    }
    val sourceType = (sourceNode.get \ "@type").text
    sourceType match {
      case "file" =>
        val filename = getTextOrDefault(sourceNode.get, "Filename", "")
        if (filename.isEmpty) {
          println(s"Warning: PointSet '$name' has empty filename, skipping")
          return null
        }
        val filePath = s"$resourcesBasePath${File.separator}$filename"
        try {
          val points = loadPointsFromFile(filePath)
          new PointSet(points, name)
        } catch {
          case e: Exception =>
            println(s"Error loading point file for '$name': ${e.getMessage}")
            null
        }
      case _ =>
        println(s"Warning: Unknown source type '$sourceType' for PointSet '$name', skipping")
        null
    }
  }

  /** Parse a pointSet XML file and return one Polygon2D per <point> element. */
  def loadPointsFromFile(filePath: String): List[Polygon2D] = {
    val polys = ListBuffer[Polygon2D]()
    val doc = loadXMLLenient(filePath)
    val pointElems: NodeSeq = (doc \ "point")
    for (pointEl <- pointElems) {
      val x = (pointEl \ "@x").text.toDouble
      val y = (pointEl \ "@y").text.toDouble
      val poly = Polygon2D(List(Vector2D(x, y)), PolygonType.POINT_POLYGON)
      val prStr = (pointEl \ "@pressure").text
      if (prStr.nonEmpty) {
        try {
          val pr = prStr.toFloat
          if (pr != 1.0f) poly.pressures = Some(Array(pr))
        } catch { case _: NumberFormatException => () }
      }
      polys += poly
    }
    polys.toList
  }

  private def getTextOrDefault(node: Node, elem: String, default: String): String =
    (node \ elem).headOption.map(_.text.trim).filter(_.nonEmpty).getOrElse(default)
}
