package org.loom.scene

import java.awt.Color
import java.awt.image.{BufferedImage, ConvolveOp, Kernel}
import java.io.File
import javax.imageio.ImageIO
import scala.collection.mutable

/**
 * Singleton that loads, caches, and pre-processes brush PNG images.
 * Brushes are greyscale bitmaps used as stamps in BRUSHED rendering mode.
 */
object BrushLibrary {

  private var brushDir: String = ""
  private val rawCache: mutable.Map[String, BufferedImage] = mutable.Map()
  // Bounded scaled cache: at quality 8×, a single 64×64 brush becomes 512×512 = 1 MB.
  // Cap at 32 entries to limit scaled-brush heap to ~32 MB at typical brush sizes.
  private val MaxScaledCacheSize = 32
  private val scaledCache: mutable.LinkedHashMap[(String, Int, Int), BufferedImage] = mutable.LinkedHashMap() // (name, qualityMultiple, blurRadius)
  // Bounded tinted cache — with dynamic color changes, unique colors are generated every frame.
  // Cap size to prevent heap exhaustion at high quality multiples.
  private val MaxTintedCacheSize = 64
  private val tintedCache: mutable.LinkedHashMap[(Int, Int, Int, Int), BufferedImage] = mutable.LinkedHashMap()

  def initialize(brushDirectory: String): Unit = {
    brushDir = brushDirectory
    rawCache.clear()
    scaledCache.clear()
    tintedCache.clear()
    println(s"BrushLibrary initialized: $brushDirectory")
  }

  /**
   * Get a brush image, scaled for quality and optionally blurred.
   * Results are cached.
   */
  def getBrush(name: String, qualityMultiple: Int, blurRadius: Int): BufferedImage = {
    val key = (name, qualityMultiple, blurRadius)
    scaledCache.get(key) match {
      case Some(img) => img
      case None =>
        val raw = loadRaw(name)
        if (raw == null) return null
        var img = if (qualityMultiple > 1) scaleImage(raw, qualityMultiple) else raw
        if (blurRadius > 0) img = applyBlur(img, blurRadius)
        while (scaledCache.size >= MaxScaledCacheSize) {
          scaledCache.remove(scaledCache.head._1)
        }
        scaledCache(key) = img
        img
    }
  }

  /**
   * Create a colour-tinted version of a brush.
   * The brush greyscale values become the alpha channel, and RGB is set to strokeColor.
   * Cached by (brush identity, color).
   */
  def getTintedBrush(brush: BufferedImage, strokeColor: Color): BufferedImage = {
    val key = (System.identityHashCode(brush), strokeColor.getRed, strokeColor.getGreen, strokeColor.getBlue)
    tintedCache.get(key) match {
      case Some(img) => img
      case None =>
        val w = brush.getWidth
        val h = brush.getHeight
        val tinted = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB)
        val r = strokeColor.getRed
        val g = strokeColor.getGreen
        val b = strokeColor.getBlue

        for (y <- 0 until h; x <- 0 until w) {
          val pixel = brush.getRGB(x, y)
          // Use the red channel of greyscale as luminance → alpha
          val alpha = (pixel >> 16) & 0xFF
          tinted.setRGB(x, y, (alpha << 24) | (r << 16) | (g << 8) | b)
        }
        // Evict oldest entries when cache is full
        while (tintedCache.size >= MaxTintedCacheSize) {
          tintedCache.remove(tintedCache.head._1)
        }
        tintedCache(key) = tinted
        tinted
    }
  }

  /**
   * Apply Gaussian blur using ConvolveOp.
   */
  def applyBlur(img: BufferedImage, radius: Int): BufferedImage = {
    if (radius <= 0) return img
    val size = radius * 2 + 1
    val weight = 1.0f / (size * size)
    val data = Array.fill(size * size)(weight)
    val kernel = new Kernel(size, size, data)
    val op = new ConvolveOp(kernel, ConvolveOp.EDGE_NO_OP, null)
    val dest = new BufferedImage(img.getWidth, img.getHeight, img.getType)
    op.filter(img, dest)
    dest
  }

  /**
   * Scale image by an integer factor.
   */
  def scaleImage(img: BufferedImage, factor: Int): BufferedImage = {
    val newW = img.getWidth * factor
    val newH = img.getHeight * factor
    val scaled = new BufferedImage(newW, newH, BufferedImage.TYPE_INT_ARGB)
    val g2d = scaled.createGraphics()
    g2d.setRenderingHint(
      java.awt.RenderingHints.KEY_INTERPOLATION,
      java.awt.RenderingHints.VALUE_INTERPOLATION_BILINEAR
    )
    g2d.drawImage(img, 0, 0, newW, newH, null)
    g2d.dispose()
    scaled
  }

  /**
   * List available brush filenames in the brush directory.
   */
  def listBrushes(): Array[String] = {
    val dir = new File(brushDir)
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
      val file = new File(brushDir, name)
      if (!file.exists()) {
        println(s"BrushLibrary: brush not found: ${file.getAbsolutePath}")
        return null
      }
      try {
        val img = ImageIO.read(file)
        // Convert to ARGB for consistent processing
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
          println(s"BrushLibrary: failed to load brush '$name': ${e.getMessage}")
          null
      }
    })
  }
}
