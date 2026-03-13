package org.loom.media

import org.loom.geometry._
import scala.xml._
import scala.collection.mutable.ListBuffer

object PolygonSetLoader {
  
  	def loadLinePolygons(sketchName: String, shapeType: String, shapeName: String): List[Polygon2D] = {
			var polygonSet: Seq[Node] = null
					val polys: ListBuffer[Polygon2D] = new ListBuffer[Polygon2D]()
					polygonSet = XML.loadFile(ProjectFilePath.filePath + ProjectFilePath.separator + "sketches" + ProjectFilePath.separator + sketchName + ProjectFilePath.separator + "resources" + ProjectFilePath.separator + "shapes" + ProjectFilePath.separator + shapeType + ProjectFilePath.separator + shapeName)

					val polygons: NodeSeq = (polygonSet \\ "polygon")
					println("polygons.length: " + polygons.length)

					for (i <- 0 until polygons.length) {//load polygon data
						val polygon: NodeSeq = polygons(i)
								val curves: NodeSeq = (polygon \\ "curve")
								val pts: ListBuffer[Vector2D] = new ListBuffer[Vector2D]()

								for (c <- 0 until curves.length) { //load curves data for each polygon
									val curve: NodeSeq = curves(c)
											val points: NodeSeq = (curve \\ "point")


											for (p <- 0 until points.length) {//load points data for each curve
											    if (p == 0 || p == 3) {
												    val x: String = (points(p) \ "@x").text
												    println("x: " + x)
														val xD: Double = (x.toDouble)
												
														val y: String = (points(p) \ "@y").text
														//println("y: " + y)
														val yD: Double = (y.toDouble)
														pts += new Vector2D(xD, yD)
											    }
											}

								}
								polys += new Polygon2D(pts.toList, PolygonType.LINE_POLYGON)	
					}
					polys.toList
	}
  
	def loadSplinePolygons(sketchName: String, shapeType: String, shapeName: String): List[Polygon2D] = {
			var polygonSet: Seq[Node] = null
					val polys: ListBuffer[Polygon2D] = new ListBuffer[Polygon2D]()
					polygonSet = XML.loadFile(ProjectFilePath.filePath + ProjectFilePath.separator + "sketches" + ProjectFilePath.separator + sketchName + ProjectFilePath.separator + "resources" + ProjectFilePath.separator + "shapes" + ProjectFilePath.separator + shapeType + ProjectFilePath.separator + shapeName)

					val polygons: NodeSeq = (polygonSet \\ "polygon")
					//println("PolygonSetLoader, loadSplinePolygons, polygons.length: " + polygons.length)

					for (i <- 0 until polygons.length) {//load polygon data
						val polygon: NodeSeq = polygons(i)
								val isClosedAttr = (polygon \ "@isClosed").text
								val polyType = if (isClosedAttr == "false") PolygonType.OPEN_SPLINE_POLYGON else PolygonType.SPLINE_POLYGON
								val curves: NodeSeq = (polygon \\ "curve")
								val pts: ListBuffer[Vector2D] = new ListBuffer[Vector2D]()

								for (c <- 0 until curves.length) { //load curves data for each polygon
									val curve: NodeSeq = curves(c)
											val points: NodeSeq = (curve \\ "point")


											for (p <- 0 until points.length) {//load points data for each curve
												    val x: String = (points(p) \ "@x").text
												    //println("PolygonSetLoader, loadSplinePolygons points x: " + x)
														val xD: Double = (x.toDouble)
												
														val y: String = (points(p) \ "@y").text
														//println("PolygonSetLoader, loadSplinePolygons points y: " + y)
														val yD: Double = (y.toDouble)
														pts += new Vector2D(xD, yD)
											}

								}
								polys += new Polygon2D(pts.toList, polyType)
					}
					polys.toList
	}
	
    def load3DShape(sketchName: String, shapeType: String, shapeName: String): List[Vector3D] = {
	   var shape: Seq[Node] = null
	   val points: ListBuffer[Vector3D] = new ListBuffer[Vector3D]()
       shape = XML.loadFile(ProjectFilePath.filePath + ProjectFilePath.separator + "sketches" + ProjectFilePath.separator + sketchName + ProjectFilePath.separator + "resources" + ProjectFilePath.separator + "shapes" + ProjectFilePath.separator + shapeType + ProjectFilePath.separator + shapeName)
       val polyPoints: NodeSeq = (shape \\ "polyPoint")
       println("polyPoints.length: " + polyPoints.length)
       for (i <- 0 until polyPoints.length) {
    	   val point: NodeSeq = polyPoints(i)
    	   val x: String = (point \ "x").text
    	   val xD: Double = x.toDouble
    	   val y: String = (point \ "y").text
    	   val yD: Double = y.toDouble
    	   println("y: " + y)
    	   points += new Vector3D(xD, yD, 0)
       }
       points.toList
   }
  
}