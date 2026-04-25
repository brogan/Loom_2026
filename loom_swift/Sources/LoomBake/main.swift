import Foundation
import LoomEngine

// Usage: LoomBake <input_path> <subdiv_xml> <set_name> <output_path>
let args = CommandLine.arguments
guard args.count == 5 else {
    fputs("Usage: LoomBake <input_path> <subdiv_xml> <set_name> <output_path>\n", stderr)
    exit(1)
}

let inputPath  = args[1]
let subdivXml  = args[2]
let setName    = args[3]
let outputPath = args[4]

// Load polygons — no normalisation to match Scala's loadSplinePolygonsFromFile (Y as-is)
let inputURL = URL(fileURLWithPath: inputPath)
let polys: [Polygon2D]
do {
    polys = try XMLPolygonLoader.load(url: inputURL, normalise: false)
} catch {
    fputs("[LoomBake] Error loading polygons from \(inputPath): \(error)\n", stderr)
    exit(1)
}
guard !polys.isEmpty else {
    fputs("[LoomBake] Error: no polygons loaded from \(inputPath)\n", stderr)
    exit(1)
}
print("[LoomBake] Loaded \(polys.count) polygon(s).")

// Load subdivision config
let subdivURL = URL(fileURLWithPath: subdivXml)
let subdivConfig: SubdivisionConfig
do {
    subdivConfig = try XMLConfigLoader.loadSubdivisionConfig(url: subdivURL)
} catch {
    fputs("[LoomBake] Error loading subdivision config: \(error)\n", stderr)
    exit(1)
}
guard let paramsSet = subdivConfig.paramsSet(named: setName) else {
    fputs("[LoomBake] Error: subdivision set '\(setName)' not found in \(subdivXml)\n", stderr)
    exit(1)
}
print("[LoomBake] Using set '\(setName)' (\(paramsSet.params.count) pass(es)).")

// Run subdivision
print("[LoomBake] Running subdivision...")
var rng = SystemRandomNumberGenerator()
let result = SubdivisionEngine.process(polygons: polys, paramSet: paramsSet.params, rng: &rng)
print("[LoomBake] Produced \(result.count) polygon(s).")

// Write output — same format as Scala PolygonSetWriter
let stem = URL(fileURLWithPath: outputPath).deletingPathExtension().lastPathComponent
var xml = "<polygonSet>\n"
xml += "  <name>\(stem)</name>\n"
xml += "  <shapeType>CUBIC_CURVE</shapeType>\n"

for poly in result {
    guard poly.type == .spline || poly.type == .openSpline else { continue }
    let sidesTotal = poly.points.count / 4
    guard sidesTotal > 0 else { continue }

    if poly.type == .openSpline {
        xml += "  <polygon isClosed=\"false\">\n"
    } else {
        xml += "  <polygon>\n"
    }
    for side in 0..<sidesTotal {
        let base = side * 4
        xml += "    <curve>\n"
        for j in 0..<4 {
            let p = poly.points[base + j]
            xml += String(format: "      <point x=\"%.6f\" y=\"%.6f\"/>\n", p.x, p.y)
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

let outputURL = URL(fileURLWithPath: outputPath)
do {
    try xml.write(to: outputURL, atomically: true, encoding: .utf8)
    print("[LoomBake] Written to \(outputPath)")
} catch {
    fputs("[LoomBake] Error writing output: \(error)\n", stderr)
    exit(1)
}
