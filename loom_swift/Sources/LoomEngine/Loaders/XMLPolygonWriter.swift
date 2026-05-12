import Foundation

/// Writes `[Polygon2D]` arrays to the Bezier-editor polygon XML format.
///
/// The output format matches the `<polygonSet>` files read by `XMLPolygonLoader`
/// and produced by `LoomBake`.  Only spline polygons (`.spline` / `.openSpline`)
/// are written; line polygons are skipped.
public enum XMLPolygonWriter {

    /// Render `polygons` to a `<polygonSet>` XML string.
    ///
    /// - Parameters:
    ///   - polygons: Subdivided polygon array (typically the output of `SubdivisionEngine.process`).
    ///   - name: Value written into the `<name>` element.
    public static func polygonSetXML(_ polygons: [Polygon2D], name: String) -> String {
        var xml = "<polygonSet>\n"
        xml += "  <name>\(name)</name>\n"
        xml += "  <shapeType>CUBIC_CURVE</shapeType>\n"

        for poly in polygons {
            guard poly.type == .spline || poly.type == .openSpline else { continue }
            let sidesTotal = poly.points.count / 4
            guard sidesTotal > 0 else { continue }

            xml += poly.type == .openSpline
                ? "  <polygon isClosed=\"false\">\n"
                : "  <polygon>\n"
            for side in 0..<sidesTotal {
                let base = side * 4
                xml += "    <curve>\n"
                for j in 0..<4 {
                    let p = poly.points[base + j]
                    let pressure: Double?
                    if j == 0 {
                        pressure = side < poly.pressures.count ? poly.pressures[side] : nil
                    } else if poly.type == .openSpline, j == 3 {
                        let endPressureIndex = side + 1
                        pressure = endPressureIndex < poly.pressures.count ? poly.pressures[endPressureIndex] : nil
                    } else {
                        pressure = nil
                    }

                    if let pressure {
                        xml += String(
                            format: "      <point x=\"%.6f\" y=\"%.6f\" pressure=\"%.6f\"/>\n",
                            p.x,
                            p.y,
                            pressure
                        )
                    } else {
                        xml += String(format: "      <point x=\"%.6f\" y=\"%.6f\"/>\n", p.x, p.y)
                    }
                }
                xml += "    </curve>\n"
            }
            xml += "  </polygon>\n"
        }

        xml += "  <scaleX>1.0</scaleX>\n"
        xml += "  <scaleY>1.0</scaleY>\n"
        xml += "  <rotationAngle>0.0</rotationAngle>\n"
        xml += "  <transX>0.5</transX>\n"
        xml += "  <transY>0.5</transY>\n"
        xml += "</polygonSet>\n"
        return xml
    }

    /// Write `polygons` as a `<polygonSet>` XML file at `url`.
    public static func write(_ polygons: [Polygon2D], name: String, to url: URL) throws {
        let xml = polygonSetXML(polygons, name: name)
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
}
