package org.loom.media

import scala.xml.*
import java.io.File
import org.loom.geometry.Vector2D

/** A reference to a single morph target file in the morphTargets/ directory. */
case class MorphTargetRef(file: String, name: String = "")

/**
 * Loads SpriteLibrary from sprites.xml configuration files.
 */
object SpriteConfigLoader {

  def load(filePath: String): SpriteLibrary = {
    val file = File(filePath)
    if (!file.exists()) {
      println(s"Warning: Sprite config file not found: $filePath")
      return SpriteLibrary("default")
    }

    try {
      val xml = XML.loadFile(filePath)
      parseSpriteConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error loading sprite config from $filePath: ${e.getMessage}")
        SpriteLibrary("default")
    }
  }

  def loadFromString(xmlContent: String): SpriteLibrary = {
    try {
      val xml = XML.loadString(xmlContent)
      parseSpriteConfig(xml)
    } catch {
      case e: Exception =>
        println(s"Error parsing sprite config XML: ${e.getMessage}")
        SpriteLibrary("default")
    }
  }

  private def parseSpriteConfig(root: Elem): SpriteLibrary = {
    val libElem = (root \\ "SpriteLibrary").headOption
    val libraryName = libElem.map(e => (e \ "@name").text).getOrElse("MainLibrary")
    val library = SpriteLibrary(libraryName)

    (root \\ "SpriteSet").foreach { setNode =>
      val spriteSet = parseSpriteSet(setNode)
      library.addSpriteSet(spriteSet)
    }

    library
  }

  private def parseSpriteSet(node: Node): SpriteSet = {
    val name = (node \ "@name").text match {
      case "" => "default"
      case n => n
    }

    val spriteSet = SpriteSet(name)

    (node \ "Sprite").foreach { spriteNode =>
      val spriteDef = parseSpriteDef(spriteNode)
      spriteSet.addSprite(spriteDef)
    }

    spriteSet
  }

  private def parseSpriteDef(node: Node): SpriteDef = {
    val name = (node \ "@name").text match {
      case "" => "default"
      case n => n
    }

    val spriteDef = SpriteDef(name)

    // Shape reference
    spriteDef.shapeSetName = (node \ "Shape" \ "@shapeSet").text
    spriteDef.shapeName = (node \ "Shape" \ "@name").text

    // Renderer set reference
    spriteDef.rendererSetName = (node \ "RendererSet" \ "@name").text

    // Position
    (node \ "Position").headOption.foreach { posNode =>
      val x = (posNode \ "@x").text match { case "" => 0.0; case s => s.toDouble }
      val y = (posNode \ "@y").text match { case "" => 0.0; case s => s.toDouble }
      spriteDef.position = Vector2D(x, y)
    }

    // Scale
    (node \ "Scale").headOption.foreach { scaleNode =>
      val x = (scaleNode \ "@x").text match { case "" => 1.0; case s => s.toDouble }
      val y = (scaleNode \ "@y").text match { case "" => 1.0; case s => s.toDouble }
      spriteDef.scale = Vector2D(x, y)
    }

    // Rotation
    spriteDef.rotation = (node \ "Rotation").text match {
      case "" => 0.0
      case s => s.toDouble
    }

    // Animation settings
    (node \ "Animation").headOption.foreach { animNode =>
      spriteDef.animationEnabled = (animNode \ "@enabled").text.toLowerCase != "false"

      // Animator type: "random" (default) or "keyframe"
      spriteDef.animatorType = (animNode \ "@type").text match {
        case "" => "random"
        case s => s
      }

      // Loop mode for keyframe animation
      spriteDef.loopMode = (animNode \ "@loopMode").text match {
        case "" => "NONE"
        case s => s
      }

      // Jitter mode (oscillate around home position instead of accumulating)
      spriteDef.jitter = (animNode \ "@jitter").text.toLowerCase == "true"

      spriteDef.totalDraws = (animNode \ "TotalDraws").text match {
        case "" => 0
        case s => try { s.trim.toInt } catch { case _: NumberFormatException => 0 }
      }

      (animNode \ "ScaleRange").headOption.foreach { sr =>
        val xMin = (sr \ "@xMin").text match { case "" => 0.0; case s => s.toDouble }
        val xMax = (sr \ "@xMax").text match { case "" => 0.0; case s => s.toDouble }
        val yMin = (sr \ "@yMin").text match { case "" => 0.0; case s => s.toDouble }
        val yMax = (sr \ "@yMax").text match { case "" => 0.0; case s => s.toDouble }
        spriteDef.scaleRangeX = (xMin, xMax)
        spriteDef.scaleRangeY = (yMin, yMax)
      }

      (animNode \ "RotationRange").headOption.foreach { rr =>
        val min = (rr \ "@min").text match { case "" => 0.0; case s => s.toDouble }
        val max = (rr \ "@max").text match { case "" => 0.0; case s => s.toDouble }
        spriteDef.rotationRange = (min, max)
      }

      (animNode \ "TranslationRange").headOption.foreach { tr =>
        val xMin = (tr \ "@xMin").text match { case "" => 0.0; case s => s.toDouble }
        val xMax = (tr \ "@xMax").text match { case "" => 0.0; case s => s.toDouble }
        val yMin = (tr \ "@yMin").text match { case "" => 0.0; case s => s.toDouble }
        val yMax = (tr \ "@yMax").text match { case "" => 0.0; case s => s.toDouble }
        spriteDef.translationRangeX = (xMin, xMax)
        spriteDef.translationRangeY = (yMin, yMax)
      }

      // Morph target chain — new format: <MorphTargets><MorphTarget file="..." name="..."/>...
      // Backward compat: <MorphTarget polygonSet="..."/> (single target, old format)
      val newMtFmt = (animNode \ "MorphTargets")
      if (newMtFmt.nonEmpty) {
        val mtsNode = newMtFmt.head
        spriteDef.morphTargets = (mtsNode \ "MorphTarget").map { n =>
          MorphTargetRef((n \ "@file").text, (n \ "@name").text)
        }.toSeq
        spriteDef.morphMin = (mtsNode \ "@morphMin").text match { case "" => 0.0; case s => s.toDouble }
        spriteDef.morphMax = (mtsNode \ "@morphMax").text match { case "" => 1.0; case s => s.toDouble }
      } else {
        (animNode \ "MorphTarget").headOption.foreach { mtNode =>
          val ps = (mtNode \ "@polygonSet").text
          if (ps.nonEmpty) spriteDef.morphTargets = Seq(MorphTargetRef(ps))
          spriteDef.morphMin = (mtNode \ "@morphMin").text match { case "" => 0.0; case s => s.toDouble }
          spriteDef.morphMax = (mtNode \ "@morphMax").text match { case "" => 1.0; case s => s.toDouble }
        }
      }

      // Keyframe animation data
      (animNode \ "Keyframes").headOption.foreach { kfsNode =>
        val keyframeDefs = (kfsNode \ "Keyframe").map { kfNode =>
          val kd = new KeyframeDef
          kd.drawCycle = (kfNode \ "@drawCycle").text match { case "" => 0; case s => s.toInt }
          kd.posX = (kfNode \ "@posX").text match { case "" => 0.0; case s => s.toDouble }
          kd.posY = (kfNode \ "@posY").text match { case "" => 0.0; case s => s.toDouble }
          kd.scaleX = (kfNode \ "@scaleX").text match { case "" => 1.0; case s => s.toDouble }
          kd.scaleY = (kfNode \ "@scaleY").text match { case "" => 1.0; case s => s.toDouble }
          kd.rotation = (kfNode \ "@rotation").text match { case "" => 0.0; case s => s.toDouble }
          kd.easing = (kfNode \ "@easing").text match { case "" => "LINEAR"; case s => s }
          kd.morphAmount = (kfNode \ "@morphAmount").text match { case "" => 0.0; case s => s.toDouble }
          kd
        }.toList
        spriteDef.keyframes = keyframeDefs
      }
    }

    // EditorExtensions - animation base factors
    (node \ "EditorExtensions").headOption.foreach { eeNode =>
      (eeNode \ "ScaleFactor").headOption.foreach { sf =>
        val x = (sf \ "@x").text match { case "" => 1.0; case s => s.toDouble }
        val y = (sf \ "@y").text match { case "" => 1.0; case s => s.toDouble }
        spriteDef.scaleFactor = Vector2D(x, y)
      }
      (eeNode \ "RotationFactor").headOption.foreach { rf =>
        spriteDef.rotationFactor = (rf \ "@value").text match { case "" => 0.0; case s => s.toDouble }
      }
      (eeNode \ "SpeedFactor").headOption.foreach { sf =>
        val x = (sf \ "@x").text match { case "" => 0.0; case s => s.toDouble }
        val y = (sf \ "@y").text match { case "" => 0.0; case s => s.toDouble }
        spriteDef.speedFactor = Vector2D(x, y)
      }
      (eeNode \ "RotationOffset").headOption.foreach { ro =>
        val x = (ro \ "@x").text match { case "" => 0.0; case s => s.toDouble }
        val y = (ro \ "@y").text match { case "" => 0.0; case s => s.toDouble }
        spriteDef.rotationOffset = Vector2D(x, y)
      }
    }

    spriteDef
  }
}


/**
 * Sprite definition loaded from configuration.
 */
class SpriteDef(val name: String) {
  var shapeSetName: String = ""
  var shapeName: String = ""
  var rendererSetName: String = ""
  var position: Vector2D = Vector2D(0, 0)
  var scale: Vector2D = Vector2D(1, 1)
  var rotation: Double = 0.0
  var animationEnabled: Boolean = true
  var totalDraws: Int = 0  // 0 = infinite, >0 = stop after N draw cycles
  // Animation random ranges (from <Animation> block)
  var scaleRangeX: (Double, Double) = (0.0, 0.0)
  var scaleRangeY: (Double, Double) = (0.0, 0.0)
  var rotationRange: (Double, Double) = (0.0, 0.0)
  var translationRangeX: (Double, Double) = (0.0, 0.0)
  var translationRangeY: (Double, Double) = (0.0, 0.0)
  // Animation base factors (from <EditorExtensions> block)
  var scaleFactor: Vector2D = Vector2D(1, 1)
  var rotationFactor: Double = 0.0
  var speedFactor: Vector2D = Vector2D(0, 0)
  var rotationOffset: Vector2D = Vector2D(0, 0)

  // Keyframe animation fields
  var animatorType: String = "random" // "random" or "keyframe"
  var loopMode: String = "NONE"       // "NONE", "LOOP", "PING_PONG"
  var keyframes: List[KeyframeDef] = List.empty
  var jitter: Boolean = false         // true = oscillate around home position

  // Morph target chain (base → mt1 → mt2 → …)
  var morphTargets: Seq[MorphTargetRef] = Seq.empty
  var morphMin: Double = 0.0
  var morphMax: Double = 1.0

  override def toString: String = s"SpriteDef($name, shape=$shapeName)"
}

/**
 * Keyframe definition loaded from configuration.
 */
class KeyframeDef {
  var drawCycle: Int = 0
  var posX: Double = 0.0
  var posY: Double = 0.0
  var scaleX: Double = 1.0
  var scaleY: Double = 1.0
  var rotation: Double = 0.0
  var easing: String = "LINEAR"
  var morphAmount: Double = 0.0
}


/**
 * A set of sprite definitions.
 */
class SpriteSet(val name: String) {
  import scala.collection.mutable.ListBuffer
  private val _sprites: ListBuffer[SpriteDef] = ListBuffer.empty

  def sprites: List[SpriteDef] = _sprites.toList

  def addSprite(sprite: SpriteDef): Unit = _sprites += sprite

  def getSprite(spriteName: String): Option[SpriteDef] = _sprites.find(_.name == spriteName)

  override def toString: String = s"SpriteSet($name, sprites=${_sprites.size})"
}


/**
 * Library of sprite sets.
 */
class SpriteLibrary(val name: String) {
  import scala.collection.mutable.ListBuffer
  private val _spriteSets: ListBuffer[SpriteSet] = ListBuffer.empty

  def spriteSets: List[SpriteSet] = _spriteSets.toList

  def addSpriteSet(spriteSet: SpriteSet): Unit = _spriteSets += spriteSet

  def getSpriteSet(setName: String): Option[SpriteSet] = _spriteSets.find(_.name == setName)

  def getSprite(setName: String, spriteName: String): Option[SpriteDef] = {
    getSpriteSet(setName).flatMap(_.getSprite(spriteName))
  }

  override def toString: String = s"SpriteLibrary($name, sets=${_spriteSets.size})"
}
