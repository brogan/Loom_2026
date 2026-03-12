/**
Config - parses config files
*/
package org.loom.scaffold

import org.loom.media._
import java.awt.Color
import scala.xml._

object Config {

    var config: Seq[Node] = null
    var sketchName: String = ""
    var name: String = "noname"
    var width: Int = 720
    var height: Int = 720
    var qualityMultiple: Int = 1
    var animating: Boolean = true
    var drawBackgroundOnce: Boolean = true
    var fullscreen: Boolean = false
    var borderColor: Color = new Color(0,0,0)
    var backgroundImagePath: String = ""
    var serial: Boolean = false
    var port: String = "dev/ttyUSB0"
    var mode: String = "bytes"
    var quantity: Int = 1

    //XML loading not working!!!!!
    def configure(sN: String, configName: String): Unit = {
        println("in config.configure")
        println("project file path: " + ProjectFilePath.filePath + ProjectFilePath.separator + "sketches" + ProjectFilePath.separator + sN + ProjectFilePath.separator + "config" + ProjectFilePath.separator + configName)
        config = XML.loadFile(ProjectFilePath.filePath + ProjectFilePath.separator + "sketches" + ProjectFilePath.separator + sN + ProjectFilePath.separator + "config" + ProjectFilePath.separator + configName)
        sketchName = sN
       
        name = (config \ "name").text
        width = (config \ "width").text.toInt
        height = (config \ "height").text.toInt
        qualityMultiple = (config \ "qualityMultiple").text.toInt
        animating = (config \ "animating").text.toBoolean
        fullscreen = (config \ "fullscreen").text.toBoolean
        borderColor = getColor((config \ "borderColor").text)
        serial = (config \ "serial").text.toBoolean
        port = (config \ "port").text
        mode = (config \ "mode").text
        quantity = (config \ "quantity").text.toInt
        
    }

    def getColor(col: String): Color = {
        val c: Array[String] = col.split(",")
        new Color(c(0).toInt, c(1).toInt, c(2).toInt)
    }

    override def toString(): String = {
        "\nConfig:\n" +
        "   sketchName: " + sketchName + "\n" +
        "   name: " + name + "\n" +
        "   width: " + width + "\n" +
        "   height: " + height + "\n" +
        "   qualityMultiple: " + qualityMultiple + "\n" +
        "   animating: " + animating + "\n" +
        "   fullscreen: " + fullscreen + "\n" +
        "   borderColor: " + borderColor + "\n" +
        "   serial: " + serial + "\n" +
        "   port: " + port + "\n" +
        "   mode: " + mode + "\n" +
        "   quantity: " + quantity + "\n\n"
    }
}
