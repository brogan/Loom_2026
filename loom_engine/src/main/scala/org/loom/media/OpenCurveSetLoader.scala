package org.loom.media

import scala.xml.*
import java.io.File
import org.loom.geometry.{OpenCurveSet, OpenCurveSetCollection, Polygon2D, PolygonType, Vector2D}
import scala.collection.mutable.ListBuffer

/**
 * Loads OpenCurveSetCollection from curves.xml configuration files.
 * curves.xml structure mirrors polygons.xml but uses <OpenCurveSetLibrary> /
 * <OpenCurveSet> elements and references files in the curveSets/ directory.
 */
object OpenCurveSetLoader {

  /** Load XML ignoring DOCTYPE/DTD (same approach as PolygonConfigLoader). */
  private def loadXMLLenient(filePath: String): Elem = {
    val factory = javax.xml.parsers.SAXParserFactory.newInstance()
    factory.setValidating(false)
    factory.setFeature("http://apache.org/xml/features/nonvalidating/load-dtd-grammar", false)
    factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
    val saxParser = factory.newSAXParser()
    XML.withSAXParser(saxParser).loadFile(filePath)
  }

  /** Load an OpenCurveSetCollection from a curves.xml config file. */
  def load(filePath: String, resourcesBasePath: String): OpenCurveSetCollection = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Curve config file not found: $filePath")
      return OpenCurveSetCollection()
    }

    try {
      val xml = XML.loadFile(filePath)
      parseCurveConfig(xml, resourcesBasePath)
    } catch {
      case e: Exception =>
        println(s"Error loading curve config from $filePath: ${e.getMessage}")
        OpenCurveSetCollection()
    }
  }

  private def parseCurveConfig(root: Elem, resourcesBasePath: String): OpenCurveSetCollection = {
    val collection = OpenCurveSetCollection()

    val libNode = (root \ "OpenCurveSetLibrary").headOption.getOrElse(root)

    (libNode \ "OpenCurveSet").foreach { setNode =>
      val curveSet = parseCurveSetEntry(setNode, resourcesBasePath)
      if (curveSet != null) collection.add(curveSet)
    }

    collection
  }

  private def parseCurveSetEntry(node: Node, resourcesBasePath: String): OpenCurveSet = {
    val name = (node \ "@name").text
    if (name.isEmpty) {
      println("Warning: OpenCurveSet without name attribute, skipping")
      return null
    }

    val sourceNode = (node \ "Source").headOption
    if (sourceNode.isEmpty) {
      println(s"Warning: OpenCurveSet '$name' has no Source element, skipping")
      return null
    }

    val sourceType = (sourceNode.get \ "@type").text
    sourceType match {
      case "file" =>
        val filename = getTextOrDefault(sourceNode.get, "Filename", "")
        if (filename.isEmpty) {
          println(s"Warning: OpenCurveSet '$name' has empty filename, skipping")
          return null
        }
        val filePath = s"$resourcesBasePath${File.separator}$filename"
        try {
          val curves = loadOpenCurvesFromFile(filePath)
          new OpenCurveSet(curves, name)
        } catch {
          case e: Exception =>
            println(s"Error loading curve file for '$name': ${e.getMessage}")
            null
        }
      case _ =>
        println(s"Warning: Unknown source type '$sourceType' for OpenCurveSet '$name', skipping")
        null
    }
  }

  /** Parse an openCurveSet XML file and return the list of open Polygon2D curves.
   *  Handles both the Phase 3 <openCurveSet>/<openCurve> format and the Phase 2
   *  <polygonSet>/<polygon isClosed="false"> format so older Bezier exports work too. */
  def loadOpenCurvesFromFile(filePath: String): List[Polygon2D] = {
    val polys = ListBuffer[Polygon2D]()
    val doc = loadXMLLenient(filePath)

    // Detect format by root element label
    val curveNodes: NodeSeq = doc.label match {
      case "openCurveSet" => doc \ "openCurve"
      case "polygonSet"   => (doc \ "polygon").filter(n => (n \ "@isClosed").text != "true")
      case other =>
        println(s"Warning: Unexpected root element '$other' in curve file, trying <openCurve>")
        doc \ "openCurve"
    }

    for (curveNode <- curveNodes) {
      val curves: NodeSeq = (curveNode \ "curve")
      val pts = ListBuffer[Vector2D]()
      val numCurves = curves.length
      val anchorPressures = Array.fill(numCurves + 1)(1.0f)

      for ((curve, cIdx) <- curves.zipWithIndex) {
        val points: NodeSeq = (curve \ "point")
        for ((point, pIdx) <- points.zipWithIndex) {
          val x = (point \ "@x").text.toDouble
          val y = (point \ "@y").text.toDouble
          pts += Vector2D(x, y)
          if (pIdx == 0 || pIdx == 3) {
            val prStr = (point \ "@pressure").text
            if (prStr.nonEmpty) {
              try {
                val anchorIdx = if (pIdx == 0) cIdx else cIdx + 1
                anchorPressures(anchorIdx) = prStr.toFloat
              } catch { case _: NumberFormatException => () }
            }
          }
        }
      }

      if (pts.nonEmpty) {
        val poly = Polygon2D(pts.toList, PolygonType.OPEN_SPLINE_POLYGON)
        if (anchorPressures.exists(_ != 1.0f)) poly.pressures = Some(anchorPressures)
        polys += poly
      }
    }

    polys.toList
  }

  private def getTextOrDefault(node: Node, elem: String, default: String): String =
    (node \ elem).headOption.map(_.text.trim).filter(_.nonEmpty).getOrElse(default)
}
