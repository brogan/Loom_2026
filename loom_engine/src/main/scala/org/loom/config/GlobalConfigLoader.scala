package org.loom.config

import scala.xml.*
import java.awt.Color
import java.io.File

/**
 * Loads and saves GlobalConfig from/to XML files.
 */
object GlobalConfigLoader {

  def load(filePath: String): GlobalConfig = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Global config file not found: $filePath")
      return GlobalConfig.default
    }

    try {
      val xml = XML.loadFile(filePath)
      parseGlobalConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error loading global config from $filePath: ${e.getMessage}")
        GlobalConfig.default
    }
  }

  def loadFromString(xmlContent: String): GlobalConfig = {
    try {
      val xml = XML.loadString(xmlContent)
      parseGlobalConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error parsing global config XML: ${e.getMessage}")
        GlobalConfig.default
    }
  }

  private def parseGlobalConfig(root: Elem): GlobalConfig = {
    val name = getTextOrDefault(root, "Name", "Untitled")
    val width = getIntOrDefault(root, "Width", 1080)
    val height = getIntOrDefault(root, "Height", 1080)
    val qualityMultiple = getIntOrDefault(root, "QualityMultiple", 1)
    val scaleImage = getBoolOrDefault(root, "ScaleImage",
      getBoolOrDefault(root, "ScaleStrokeWidth",
        getBoolOrDefault(root, "Large", false)))  // legacy fallbacks
    val animating = getBoolOrDefault(root, "Animating", false)
    val drawBackgroundOnce = getBoolOrDefault(root, "DrawBackgroundOnce", true)
    val fullscreen = getBoolOrDefault(root, "Fullscreen", false)
    val borderColor = getColorOrDefault(root, "BorderColor", Color.BLACK)
    val backgroundColor = getColorOrDefault(root, "BackgroundColor", Color.WHITE)
    val overlayColor = getColorOrDefault(root, "OverlayColor", Color.BLACK)
    val backgroundImagePath = getTextOrDefault(root, "BackgroundImage", "")
    val threeD = getBoolOrDefault(root, "ThreeD", false)
    val cameraViewAngle = getIntOrDefault(root, "CameraViewAngle", 120)
    val subdividing = getBoolOrDefault(root, "Subdividing", true)

    GlobalConfig(
      name = name,
      width = width,
      height = height,
      qualityMultiple = qualityMultiple,
      scaleImage = scaleImage,
      animating = animating,
      drawBackgroundOnce = drawBackgroundOnce,
      fullscreen = fullscreen,
      borderColor = borderColor,
      backgroundColor = backgroundColor,
      overlayColor = overlayColor,
      backgroundImagePath = backgroundImagePath,
      threeD = threeD,
      cameraViewAngle = cameraViewAngle,
      subdividing = subdividing
    )
  }

  def save(config: GlobalConfig, filePath: String): Unit = {
    val xml =
      <GlobalConfig version="1.0">
        <Name>{config.name}</Name>
        <Width>{config.width}</Width>
        <Height>{config.height}</Height>
        <QualityMultiple>{config.qualityMultiple}</QualityMultiple>
        <ScaleImage>{config.scaleImage}</ScaleImage>
        <Animating>{config.animating}</Animating>
        <DrawBackgroundOnce>{config.drawBackgroundOnce}</DrawBackgroundOnce>
        <Fullscreen>{config.fullscreen}</Fullscreen>
        <BorderColor r={config.borderColor.getRed.toString} g={config.borderColor.getGreen.toString} b={config.borderColor.getBlue.toString} a={config.borderColor.getAlpha.toString}/>
        <BackgroundColor r={config.backgroundColor.getRed.toString} g={config.backgroundColor.getGreen.toString} b={config.backgroundColor.getBlue.toString} a={config.backgroundColor.getAlpha.toString}/>
        <OverlayColor r={config.overlayColor.getRed.toString} g={config.overlayColor.getGreen.toString} b={config.overlayColor.getBlue.toString} a={config.overlayColor.getAlpha.toString}/>
        {if (config.backgroundImagePath.nonEmpty) <BackgroundImage>{config.backgroundImagePath}</BackgroundImage>}
        <ThreeD>{config.threeD}</ThreeD>
        <CameraViewAngle>{config.cameraViewAngle}</CameraViewAngle>
        <Subdividing>{config.subdividing}</Subdividing>
      </GlobalConfig>

    XML.save(filePath, xml, "UTF-8", xmlDecl = true)
  }

  // Helper methods
  private def getTextOrDefault(root: Elem, elem: String, default: String): String = {
    (root \ elem).headOption.map(_.text.trim).filter(_.nonEmpty).getOrElse(default)
  }

  private def getIntOrDefault(root: Elem, elem: String, default: Int): Int = {
    try {
      (root \ elem).headOption.map(_.text.trim.toInt).getOrElse(default)
    } catch {
      case _: NumberFormatException => default
    }
  }

  private def getBoolOrDefault(root: Elem, elem: String, default: Boolean): Boolean = {
    (root \ elem).headOption.map(_.text.trim.toLowerCase == "true").getOrElse(default)
  }

  private def getColorOrDefault(root: Elem, elem: String, default: Color): Color = {
    (root \ elem).headOption.map { node =>
      val r = (node \ "@r").text match { case "" => default.getRed; case s => s.toInt }
      val g = (node \ "@g").text match { case "" => default.getGreen; case s => s.toInt }
      val b = (node \ "@b").text match { case "" => default.getBlue; case s => s.toInt }
      val a = (node \ "@a").text match { case "" => default.getAlpha; case s => s.toInt }
      Color(r, g, b, a)
    }.getOrElse(default)
  }
}
