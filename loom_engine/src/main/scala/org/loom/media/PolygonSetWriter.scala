package org.loom.media

import java.io.{File, FileWriter, BufferedWriter, PrintWriter}
import org.loom.geometry.{Polygon2D, PolygonType}

/**
 * Serialises a List[Polygon2D] to polygon set XML readable by
 * PolygonConfigLoader.loadSplinePolygonsFromFile.
 *
 * Only SPLINE_POLYGON and OPEN_SPLINE_POLYGON are written; LINE_POLYGON
 * and POINT_POLYGON are silently skipped (they don't appear in
 * subdivision output).
 */
object PolygonSetWriter {

  def write(polys: List[Polygon2D], outputPath: String): Unit = {
    // Derive a name from the output filename (stem without .xml)
    val name = new File(outputPath).getName.replaceAll("\\.xml$", "")

    val sb = new StringBuilder
    sb.append("<polygonSet>\n")
    // Required elements per polygonSet.dtd that Bezier's XOM parser validates against
    sb.append(s"  <name>$name</name>\n")
    sb.append("  <shapeType>CUBIC_CURVE</shapeType>\n")

    for (poly <- polys) {
      if (poly.polyType == PolygonType.SPLINE_POLYGON || poly.polyType == PolygonType.OPEN_SPLINE_POLYGON) {
        if (poly.polyType == PolygonType.OPEN_SPLINE_POLYGON)
          sb.append("  <polygon isClosed=\"false\">\n")
        else
          sb.append("  <polygon>\n")

        val pts = poly.points
        for (side <- 0 until poly.sidesTotal) {
          val base = side * 4
          sb.append("    <curve>\n")
          for (j <- 0 to 3) {
            val p = pts(base + j)
            sb.append(f"      <point x=\"${p.x}%.6f\" y=\"${p.y}%.6f\"/>\n")
          }
          sb.append("    </curve>\n")
        }

        sb.append("  </polygon>\n")
      }
    }

    // Trailing required elements (default identity transform)
    sb.append("  <scaleX>1.0</scaleX>\n")
    sb.append("  <scaleY>1.0</scaleY>\n")
    sb.append("  <rotationAngle>0.0</rotationAngle>\n")
    sb.append("  <transX>0.5</transX>\n")
    sb.append("  <transY>0.5</transY>\n")
    sb.append("</polygonSet>\n")

    val file = new File(outputPath)
    val parent = file.getParentFile
    if (parent != null && !parent.exists()) parent.mkdirs()

    val pw = new PrintWriter(new BufferedWriter(new FileWriter(file)))
    try {
      pw.print(sb.toString())
    } finally {
      pw.close()
    }
  }
}
