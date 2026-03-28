package org.loom.media

import scala.xml.*
import java.io.File
import org.loom.geometry.{OvalSet, OvalSetCollection, Polygon2D, PolygonType, Vector2D}
import scala.collection.mutable.ListBuffer

/**
 * Loads OvalSetCollection from ovals.xml configuration files.
 * ovals.xml structure mirrors points.xml but uses <OvalSetLibrary> / <OvalSet> elements
 * and references files in the ovalSets/ directory.
 */
object OvalSetLoader {

  private def loadXMLLenient(filePath: String): Elem = {
    val factory = javax.xml.parsers.SAXParserFactory.newInstance()
    factory.setValidating(false)
    factory.setFeature("http://apache.org/xml/features/nonvalidating/load-dtd-grammar", false)
    factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
    val saxParser = factory.newSAXParser()
    XML.withSAXParser(saxParser).loadFile(filePath)
  }

  def load(filePath: String, resourcesBasePath: String): OvalSetCollection = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Oval config file not found: $filePath")
      return OvalSetCollection()
    }
    try {
      val xml = XML.loadFile(filePath)
      parseOvalConfig(xml, resourcesBasePath)
    } catch {
      case e: Exception =>
        println(s"Error loading oval config from $filePath: ${e.getMessage}")
        OvalSetCollection()
    }
  }

  private def parseOvalConfig(root: Elem, resourcesBasePath: String): OvalSetCollection = {
    val collection = OvalSetCollection()
    val libNode = (root \ "OvalSetLibrary").headOption.getOrElse(root)

    (libNode \ "OvalSet").foreach { setNode =>
      val os = parseOvalSetEntry(setNode, resourcesBasePath)
      if (os != null) collection.add(os)
    }
    collection
  }

  private def parseOvalSetEntry(node: Node, resourcesBasePath: String): OvalSet = {
    val name = (node \ "@name").text
    if (name.isEmpty) {
      println("Warning: OvalSet without name attribute, skipping")
      return null
    }
    val sourceNode = (node \ "Source").headOption
    if (sourceNode.isEmpty) {
      println(s"Warning: OvalSet '$name' has no Source element, skipping")
      return null
    }
    val sourceType = (sourceNode.get \ "@type").text
    sourceType match {
      case "file" =>
        val filename = getTextOrDefault(sourceNode.get, "Filename", "")
        if (filename.isEmpty) {
          println(s"Warning: OvalSet '$name' has empty filename, skipping")
          return null
        }
        val filePath = s"$resourcesBasePath${File.separator}$filename"
        try {
          val ovals = loadOvalsFromFile(filePath)
          new OvalSet(ovals, name)
        } catch {
          case e: Exception =>
            println(s"Error loading oval file for '$name': ${e.getMessage}")
            null
        }
      case _ =>
        println(s"Warning: Unknown source type '$sourceType' for OvalSet '$name', skipping")
        null
    }
  }

  /**
   * Parse an ovalSet XML file and return one Polygon2D per <oval> element.
   * Stored as: Polygon2D(List(Vector2D(cx, cy), Vector2D(cx+rx, cy+ry)), OVAL_POLYGON)
   * so that coordinateCorrect can transform both points and radii can be recovered by subtraction.
   */
  def loadOvalsFromFile(filePath: String): List[Polygon2D] = {
    val polys = ListBuffer[Polygon2D]()
    val doc = loadXMLLenient(filePath)
    val ovalElems: NodeSeq = (doc \ "oval")
    for (ovalEl <- ovalElems) {
      val cx = (ovalEl \ "@cx").text.toDouble
      val cy = (ovalEl \ "@cy").text.toDouble
      val rx = (ovalEl \ "@rx").text.toDouble
      val ry = (ovalEl \ "@ry").text.toDouble
      polys += Polygon2D(List(Vector2D(cx, cy), Vector2D(cx + rx, cy + ry)), PolygonType.OVAL_POLYGON)
    }
    polys.toList
  }

  private def getTextOrDefault(node: Node, elem: String, default: String): String =
    (node \ elem).headOption.map(_.text.trim).filter(_.nonEmpty).getOrElse(default)
}
