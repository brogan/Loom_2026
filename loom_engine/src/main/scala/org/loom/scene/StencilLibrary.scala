package org.loom.scene

import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import scala.collection.mutable

/**
 * Singleton that loads and caches full-RGBA stencil PNG images.
 * Stencils are stored in the project's stamps/ directory (separate from brushes/).
 * Unlike BrushLibrary there is no tinting cache — RGBA data is used as-is.
 */
object StencilLibrary {

  private var stencilDir: String = ""
  private val rawCache: mutable.Map[String, BufferedImage] = mutable.Map()
  private val MaxScaledCacheSize = 32
  private val scaledCache: mutable.LinkedHashMap[(String, Int), BufferedImage] = mutable.LinkedHashMap()

  def initialize(stencilDirectory: String): Unit = {
    stencilDir = stencilDirectory
    rawCache.clear()
    scaledCache.clear()
    println(s"StencilLibrary initialized: $stencilDirectory")
  }

  /**
   * Get a stencil image, scaled for quality if needed.
   */
  def getStencil(name: String, qualityMultiple: Int): BufferedImage = {
    val key = (name, qualityMultiple)
    scaledCache.get(key) match {
      case Some(img) => img
      case None =>
        val raw = loadRaw(name)
        if (raw == null) return null
        val img = if (qualityMultiple > 1) BrushLibrary.scaleImage(raw, qualityMultiple) else raw
        while (scaledCache.size >= MaxScaledCacheSize) {
          scaledCache.remove(scaledCache.head._1)
        }
        scaledCache(key) = img
        img
    }
  }

  def listStencils(): Array[String] = {
    val dir = new File(stencilDir)
    if (dir.exists() && dir.isDirectory) {
      dir.listFiles()
        .filter(f => f.isFile && f.getName.toLowerCase.endsWith(".png"))
        .map(_.getName)
        .sorted
    } else {
      Array.empty
    }
  }

  private def loadRaw(name: String): BufferedImage = {
    rawCache.getOrElseUpdate(name, {
      val file = new File(stencilDir, name)
      if (!file.exists()) {
        println(s"StencilLibrary: stencil not found: ${file.getAbsolutePath}")
        return null
      }
      try {
        val img = ImageIO.read(file)
        // Ensure ARGB format for correct compositing
        if (img.getType == BufferedImage.TYPE_INT_ARGB) img
        else {
          val argb = new BufferedImage(img.getWidth, img.getHeight, BufferedImage.TYPE_INT_ARGB)
          val g = argb.createGraphics()
          g.drawImage(img, 0, 0, null)
          g.dispose()
          argb
        }
      } catch {
        case e: Exception =>
          println(s"StencilLibrary: failed to load stencil '$name': ${e.getMessage}")
          null
      }
    })
  }
}
