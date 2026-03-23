package org.loom.tools

import org.loom.media.{PolygonConfigLoader, PolygonSetWriter, SubdivisionConfigLoader}
import org.loom.geometry.Shape2D

/**
 * CLI tool: loads a polygon set, runs the Loom subdivision algorithm,
 * and writes the result as a new polygon set XML file.
 *
 * Invoked via:
 *   sbt "run --bake-subdivision <inputPath> <subdivXmlPath> <setName> <outputPath>"
 */
object SubdivisionBaker {

  def bake(inputPath: String, subdivXmlPath: String, setName: String, outputPath: String): Unit = {
    println(s"[SubdivisionBaker] Loading polygons from: $inputPath")
    val polys = PolygonConfigLoader.loadSplinePolygonsFromFile(inputPath)
    if (polys.isEmpty) {
      System.err.println(s"[SubdivisionBaker] Error: no polygons loaded from $inputPath")
      System.exit(1)
    }
    println(s"[SubdivisionBaker] Loaded ${polys.length} polygon(s).")

    println(s"[SubdivisionBaker] Loading subdivision config from: $subdivXmlPath")
    val collection = SubdivisionConfigLoader.load(subdivXmlPath)
    val paramsSet = collection.getParamsSet(setName)
    if (paramsSet == null) {
      System.err.println(s"[SubdivisionBaker] Error: subdivision set '$setName' not found in $subdivXmlPath")
      System.exit(1)
    }
    println(s"[SubdivisionBaker] Using set '$setName' (${paramsSet.toList().length} pass(es)).")

    println(s"[SubdivisionBaker] Running subdivision...")
    val shape = new Shape2D(polys, paramsSet)
    val subdivided = shape.recursiveSubdivide(paramsSet.toList())
    val outputPolys = subdivided.polys.toList

    println(s"[SubdivisionBaker] Writing ${outputPolys.length} polygon(s) to: $outputPath")
    PolygonSetWriter.write(outputPolys, outputPath)
    println(s"[SubdivisionBaker] Done.")
  }
}
