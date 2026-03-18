package org.loom.media

import scala.xml.*
import java.io.File
import java.awt.Color
import org.loom.scene.{BrushConfig, StencilConfig, Renderer, RendererSet, RendererSetLibrary}

/**
 * Loads RendererSetLibrary from rendering.xml configuration files.
 */
object RenderingConfigLoader {

  def load(filePath: String): RendererSetLibrary = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Rendering config file not found: $filePath")
      return RendererSetLibrary("default")
    }

    try {
      val xml = XML.loadFile(filePath)
      parseRenderingConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error loading rendering config from $filePath: ${e.getMessage}")
        RendererSetLibrary("default")
    }
  }

  def loadFromString(xmlContent: String): RendererSetLibrary = {
    try {
      val xml = XML.loadString(xmlContent)
      parseRenderingConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error parsing rendering config XML: ${e.getMessage}")
        RendererSetLibrary("default")
    }
  }

  private def parseRenderingConfig(root: Elem): RendererSetLibrary = {
    val libElem = (root \\ "RendererSetLibrary").headOption
    val libraryName = libElem.map(e => (e \ "@name").text).getOrElse("MainLibrary")
    val library = RendererSetLibrary(libraryName)

    (root \\ "RendererSet").foreach { setNode =>
      val rendererSet = parseRendererSet(setNode)
      library.add(rendererSet)
    }

    // Set first renderer set as current if available
    if (library.library.nonEmpty) {
      library.setCurrentRendererSet(0)
    }

    library
  }

  private def parseRendererSet(node: Node): RendererSet = {
    val name = (node \ "@name").text match {
      case "" => "default"
      case n => n
    }

    val rendererSet = RendererSet(name)

    // Parse playback config
    val playbackNode = (node \ "PlaybackConfig").headOption
    playbackNode.foreach { pb =>
      val mode = (pb \ "Mode").text
      val preferredName = (pb \ "PreferredRenderer").text
      mode match {
        case "SEQUENTIAL" => rendererSet.sequenceRendererSet(0, 50)
        case "RANDOM" =>
          val prob = getDoubleOrDefault(pb, "PreferredProbability", 50.0)
          rendererSet.randomRendererSet(preferredName, prob)
        case _ => // STATIC - do nothing special
      }

      val preferredRenderer = (pb \ "PreferredRenderer").text
      if (preferredRenderer.nonEmpty) {
        rendererSet.setPreferredRenderer(preferredRenderer)
      }

      val modifyParams = (pb \ "ModifyInternalParameters").text.toLowerCase == "true"
      if (modifyParams) {
        rendererSet.modifyRenderers()
      }
    }

    // Parse renderers
    (node \ "Renderer").foreach { rendererNode =>
      val renderer = parseRenderer(rendererNode)
      rendererSet.add(renderer)
    }

    // Set current renderer if preferred is specified
    if (rendererSet.rendererSet.nonEmpty) {
      rendererSet.setCurrentRenderer(0)
    }

    rendererSet
  }

  private def parseRenderer(node: Node): Renderer = {
    val name = (node \ "@name").text match {
      case "" => "default"
      case n => n
    }

    val mode = parseRenderMode((node \ "Mode").text)
    val strokeWidth = getFloatOrDefault(node, "StrokeWidth", 1.0f)
    val strokeColor = parseColor(node \ "StrokeColor", Color(0, 0, 0, 128))
    val fillColor = parseColor(node \ "FillColor", Color(100, 150, 200, 200))
    val pointSize = getFloatOrDefault(node, "PointSize", 3.0f)
    val holdLength = getIntOrDefault(node, "HoldLength", 1)

    val renderer = Renderer(name, mode, strokeWidth, strokeColor, fillColor, pointSize, holdLength)

    // Parse point style
    (node \ "PointStyle").headOption.foreach { ps =>
      val stroked = (ps \ "@stroked").text.toLowerCase != "false"
      val filled = (ps \ "@filled").text.toLowerCase != "false"
      renderer.setPointDrawingStyle(
        if (stroked) Renderer.STROKED else 0,
        if (filled) Renderer.FILLED else 0
      )
    }

    // Parse changes
    val changesNode = (node \ "Changes").headOption
    changesNode.foreach { changes =>
      parseStrokeWidthChange(changes \ "StrokeWidthChange", renderer)
      parseStrokeColorChange(changes \ "StrokeColorChange", renderer)
      parseFillColorChange(changes \ "FillColorChange", renderer)
      parsePointSizeChange(changes \ "PointSizeChange", renderer)
    }

    // Parse brush config (for BRUSHED mode)
    (node \ "BrushConfig").headOption.foreach { bc =>
      renderer.brushConfig = parseBrushConfig(bc)
    }

    // Parse stencil config (for STENCILED mode)
    (node \ "StencilConfig").headOption.foreach { sc =>
      renderer.stencilConfig = parseStencilConfig(sc)
      // Parse optional opacity change animation
      parseOpacityChange(sc \ "OpacityChange", renderer)
    }

    renderer
  }

  private def parseBrushConfig(node: Node): BrushConfig = {
    val allBrushNames = (node \ "BrushNames" \ "Brush").map(_.text.trim).toArray
    val brushEnabledFlags = (node \ "BrushEnabled" \ "Enabled").map(_.text.trim.toLowerCase != "false").toArray
    val brushNames = if (brushEnabledFlags.length == allBrushNames.length) {
      val enabled = allBrushNames.zip(brushEnabledFlags).collect { case (n, true) => n }
      if (enabled.nonEmpty) enabled else allBrushNames // fallback: use all if all disabled
    } else {
      allBrushNames // legacy file with no BrushEnabled element — use all
    }
    val drawMode = (node \ "DrawMode").text.trim.toUpperCase match {
      case "PROGRESSIVE" => BrushConfig.PROGRESSIVE
      case _ => BrushConfig.FULL_PATH
    }
    val stampSpacing = getDoubleOrDefault(node, "StampSpacing", 4.0)
    val spacingEasing = (node \ "SpacingEasing").headOption.map(_.text.trim).getOrElse("LINEAR")
    val followTangent = (node \ "FollowTangent").headOption.map(_.text.trim.toLowerCase == "true").getOrElse(true)
    val perpJitterMin = getDoubleOrDefault(node, "PerpendicularJitterMin", -2.0)
    val perpJitterMax = getDoubleOrDefault(node, "PerpendicularJitterMax", 2.0)
    val scaleMin = getDoubleOrDefault(node, "ScaleMin", 0.8)
    val scaleMax = getDoubleOrDefault(node, "ScaleMax", 1.2)
    val opacityMin = getDoubleOrDefault(node, "OpacityMin", 0.6)
    val opacityMax = getDoubleOrDefault(node, "OpacityMax", 1.0)
    val stampsPerFrame = getIntOrDefault(node, "StampsPerFrame", 10)
    val agentCount = getIntOrDefault(node, "AgentCount", 1)
    val postCompletionMode = (node \ "PostCompletionMode").text.trim.toUpperCase match {
      case "LOOP" => BrushConfig.LOOP
      case "PING_PONG" => BrushConfig.PING_PONG
      case _ => BrushConfig.HOLD
    }
    val blurRadius = getIntOrDefault(node, "BlurRadius", 0)

    BrushConfig(
      brushNames = brushNames,
      drawMode = drawMode,
      stampSpacing = stampSpacing,
      spacingEasing = spacingEasing,
      followTangent = followTangent,
      perpendicularJitterMin = perpJitterMin,
      perpendicularJitterMax = perpJitterMax,
      scaleMin = scaleMin,
      scaleMax = scaleMax,
      opacityMin = opacityMin,
      opacityMax = opacityMax,
      stampsPerFrame = stampsPerFrame,
      agentCount = agentCount,
      postCompletionMode = postCompletionMode,
      blurRadius = blurRadius
    )
  }

  private def parseStencilConfig(node: Node): StencilConfig = {
    val allStencilNames = (node \ "StencilNames" \ "Stencil").map(_.text.trim).toArray
    val enabledFlags = (node \ "StencilEnabled" \ "Enabled").map(_.text.trim.toLowerCase != "false").toArray
    val stencilNames = if (enabledFlags.length == allStencilNames.length) {
      val enabled = allStencilNames.zip(enabledFlags).collect { case (n, true) => n }
      if (enabled.nonEmpty) enabled else allStencilNames
    } else {
      allStencilNames
    }
    val drawMode = (node \ "DrawMode").text.trim.toUpperCase match {
      case "PROGRESSIVE" => StencilConfig.PROGRESSIVE
      case _ => StencilConfig.FULL_PATH
    }
    val stampSpacing   = getDoubleOrDefault(node, "StampSpacing", 4.0)
    val spacingEasing  = (node \ "SpacingEasing").headOption.map(_.text.trim).getOrElse("LINEAR")
    val followTangent  = (node \ "FollowTangent").headOption.map(_.text.trim.toLowerCase == "true").getOrElse(true)
    val perpJitterMin  = getDoubleOrDefault(node, "PerpendicularJitterMin", -2.0)
    val perpJitterMax  = getDoubleOrDefault(node, "PerpendicularJitterMax",  2.0)
    val scaleMin       = getDoubleOrDefault(node, "ScaleMin", 0.8)
    val scaleMax       = getDoubleOrDefault(node, "ScaleMax", 1.2)
    val stampsPerFrame = getIntOrDefault(node, "StampsPerFrame", 10)
    val agentCount     = getIntOrDefault(node, "AgentCount", 1)
    val postCompletionMode = (node \ "PostCompletionMode").text.trim.toUpperCase match {
      case "LOOP"      => StencilConfig.LOOP
      case "PING_PONG" => StencilConfig.PING_PONG
      case _           => StencilConfig.HOLD
    }
    new StencilConfig(
      stencilNames          = stencilNames,
      drawMode              = drawMode,
      stampSpacing          = stampSpacing,
      spacingEasing         = spacingEasing,
      followTangent         = followTangent,
      perpendicularJitterMin = perpJitterMin,
      perpendicularJitterMax = perpJitterMax,
      scaleMin              = scaleMin,
      scaleMax              = scaleMax,
      stampsPerFrame        = stampsPerFrame,
      agentCount            = agentCount,
      postCompletionMode    = postCompletionMode
    )
  }

  private def parseOpacityChange(nodeSeq: NodeSeq, renderer: Renderer): Unit = {
    nodeSeq.headOption.foreach { node =>
      val enabled = (node \ "@enabled").text.toLowerCase != "false"
      if (enabled) {
        val params   = parseChangeParams(node)
        val min      = getFloatOrDefault(node, "Min",       0.0f)
        val max      = getFloatOrDefault(node, "Max",       1.0f)
        val inc      = getFloatOrDefault(node, "Increment", 0.05f)
        val pauseMax = getIntOrDefault(node, "PauseMax", 10)
        renderer.setChangingStencilOpacity(params, min, max, inc, pauseMax)
      }
    }
  }

  private def parseStrokeWidthChange(nodeSeq: NodeSeq, renderer: Renderer): Unit = {
    nodeSeq.headOption.foreach { node =>
      val enabled = (node \ "@enabled").text.toLowerCase != "false"
      if (enabled) {
        val params = parseChangeParams(node)
        val min = getFloatOrDefault(node, "Min", 0.1f)
        val max = getFloatOrDefault(node, "Max", 5.0f)
        val inc = getFloatOrDefault(node, "Increment", 0.1f)
        val pauseMax = getIntOrDefault(node, "PauseMax", 10)
        renderer.setChangingStrokeWidth(params, min, max, inc, pauseMax)
      }
    }
  }

  private def parseStrokeColorChange(nodeSeq: NodeSeq, renderer: Renderer): Unit = {
    nodeSeq.headOption.foreach { node =>
      val enabled = (node \ "@enabled").text.toLowerCase != "false"
      if (enabled) {
        val params = parseChangeParams(node)
        val minColor = parseColorArray(node \ "Min", Array(0, 0, 0, 0))
        val maxColor = parseColorArray(node \ "Max", Array(255, 255, 255, 255))
        val incColor = parseColorArray(node \ "Increment", Array(1, 1, 1, 1))
        val pauseMax = getIntOrDefault(node, "PauseMax", 10)
        renderer.setChangingStrokeColor(params, minColor, maxColor, incColor, pauseMax)
      }
    }
  }

  private def parseFillColorChange(nodeSeq: NodeSeq, renderer: Renderer): Unit = {
    nodeSeq.headOption.foreach { node =>
      val enabled = (node \ "@enabled").text.toLowerCase != "false"
      if (enabled) {
        val params = parseChangeParams(node)
        val minColor = parseColorArray(node \ "Min", Array(0, 0, 0, 0))
        val maxColor = parseColorArray(node \ "Max", Array(255, 255, 255, 255))
        val incColor = parseColorArray(node \ "Increment", Array(1, 1, 1, 1))
        val pauseMax = getIntOrDefault(node, "PauseMax", 10)
        val pauseChannel = parsePauseChannel((node \ "PauseChannel").text)
        val pauseColorMin = parseColorArray(node \ "PauseColorMin", Array(0, 0, 0, 255))
        val pauseColorMax = parseColorArray(node \ "PauseColorMax", Array(255, 255, 255, 255))
        renderer.setChangingFillColor(params, minColor, maxColor, incColor, pauseMax, pauseChannel, pauseColorMin, pauseColorMax)
      }
    }
  }

  private def parsePointSizeChange(nodeSeq: NodeSeq, renderer: Renderer): Unit = {
    nodeSeq.headOption.foreach { node =>
      val enabled = (node \ "@enabled").text.toLowerCase != "false"
      if (enabled) {
        val params = parseChangeParams(node)
        val min = getFloatOrDefault(node, "Min", 1.0f)
        val max = getFloatOrDefault(node, "Max", 10.0f)
        val inc = getFloatOrDefault(node, "Increment", 0.5f)
        val pauseMax = getIntOrDefault(node, "PauseMax", 10)
        renderer.setChangingPointSize(params, min, max, inc, pauseMax)
      }
    }
  }

  private def parseChangeParams(node: Node): Array[Int] = {
    val kind = (node \ "Kind").text match {
      case "RAN" => Renderer.RAN
      case _ => Renderer.SEQ
    }

    val motion = (node \ "Motion").text match {
      case "DOWN" => Renderer.DOWN
      case "PING_PONG" => Renderer.PING_PONG
      case _ => Renderer.UP
    }

    val cycle = (node \ "Cycle").text match {
      case "CONSTANT" => Renderer.CONSTANT
      case "ONCE" => Renderer.ONCE
      case "ONCE_REVERT" => Renderer.ONCE_REVERT
      case "PAUSING_RANDOM" => Renderer.PAUSING_RANDOM
      case _ => Renderer.PAUSING
    }

    val scale = (node \ "Scale").text match {
      case "SPRITE" => Renderer.SPRITE
      case "POINT" => Renderer.POINT
      case _ => Renderer.POLY
    }

    Array(kind, motion, cycle, scale)
  }

  private def parseRenderMode(modeStr: String): Int = {
    modeStr.toUpperCase match {
      case "POINTS" => Renderer.POINTS
      case "STROKED" => Renderer.STROKED
      case "FILLED" => Renderer.FILLED
      case "FILLED_STROKED" => Renderer.FILLED_STROKED
      case "BRUSHED"   => Renderer.BRUSHED
      case "STENCILED" => Renderer.STENCILED
      case _ => Renderer.FILLED
    }
  }

  private def parsePauseChannel(channelStr: String): Int = {
    channelStr.toUpperCase match {
      case "RED" => Renderer.RED_CHAN
      case "GREEN" => Renderer.GREEN_CHAN
      case "BLUE" => Renderer.BLUE_CHAN
      case "ALPHA" => Renderer.ALPHA_CHAN
      case _ => Renderer.GREEN_CHAN
    }
  }

  private def parseColor(nodeSeq: NodeSeq, default: Color): Color = {
    nodeSeq.headOption.map { node =>
      val r = (node \ "@r").text match { case "" => default.getRed; case s => s.toInt }
      val g = (node \ "@g").text match { case "" => default.getGreen; case s => s.toInt }
      val b = (node \ "@b").text match { case "" => default.getBlue; case s => s.toInt }
      val a = (node \ "@a").text match { case "" => default.getAlpha; case s => s.toInt }
      Color(r, g, b, a)
    }.getOrElse(default)
  }

  private def parseColorArray(nodeSeq: NodeSeq, default: Array[Int]): Array[Int] = {
    nodeSeq.headOption.map { node =>
      val r = (node \ "@r").text match { case "" => default(0); case s => s.toInt }
      val g = (node \ "@g").text match { case "" => default(1); case s => s.toInt }
      val b = (node \ "@b").text match { case "" => default(2); case s => s.toInt }
      val a = (node \ "@a").text match { case "" => default(3); case s => s.toInt }
      Array(r, g, b, a)
    }.getOrElse(default)
  }

  private def getFloatOrDefault(node: Node, elem: String, default: Float): Float = {
    try {
      (node \ elem).headOption.map(_.text.trim.toFloat).getOrElse(default)
    } catch {
      case _: NumberFormatException => default
    }
  }

  private def getIntOrDefault(node: Node, elem: String, default: Int): Int = {
    try {
      (node \ elem).headOption.map(_.text.trim.toInt).getOrElse(default)
    } catch {
      case _: NumberFormatException => default
    }
  }

  private def getDoubleOrDefault(node: Node, elem: String, default: Double): Double = {
    try {
      (node \ elem).headOption.map(_.text.trim.toDouble).getOrElse(default)
    } catch {
      case _: NumberFormatException => default
    }
  }
}
