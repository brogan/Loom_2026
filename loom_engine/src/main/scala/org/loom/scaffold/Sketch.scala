/**
All individual sketches extend Sketch
*/

package org.loom.scaffold

import java.awt.image.BufferedImage
import java.awt._
import java.awt.geom._
import java.io.File
import javax.imageio.ImageIO

import org.loom.scene._
import org.loom.utility._

class Sketch(val width: Int, val height: Int) {

   var paused: Boolean = false
   var serialByteReadings: Array[Int] = new Array[Int](Config.quantity-1)//we don't store the first (-5) byte
   var serialStringReading: String = "noreading"//for storing RFID codes

   var backgroundColor: Color = new Color(255,255,255,0)//trying to set transparent background - not working (2022)
   //var backgroundColor: Color = Colors.WHITE

   var overlayColor: Color = new Color(0,0,0,30)
   var axesColor: Color = Colors.BLACK
   var axesStrokeWeight: Float = .5f
   var renderer = new Renderer("WhiteLinesThick", Renderer.STROKED, .2f, new Color(255,255,255,50), new Color(120,10,3,20),1, 10)//default

   var drawn: Boolean = false

   // Background image (loaded from Config.backgroundImagePath if set)
   var backgroundImage: BufferedImage = null

   def setupBackgroundImage(): Unit = {
     if (Config.backgroundImagePath.nonEmpty) {
       try {
         val raw = ImageIO.read(new File(Config.backgroundImagePath))
         if (raw != null) {
           val canvasW = width * Config.qualityMultiple
           val canvasH = height * Config.qualityMultiple
           val scaled = new BufferedImage(canvasW, canvasH, BufferedImage.TYPE_INT_ARGB)
           val g = scaled.createGraphics()
           g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
           g.drawImage(raw, 0, 0, canvasW, canvasH, null)
           g.dispose()
           backgroundImage = scaled
           println(s"Background image loaded: ${Config.backgroundImagePath}")
         }
       } catch {
         case e: Exception =>
           println(s"Warning: background image load failed: ${e.getMessage}")
           backgroundImage = null
       }
     } else {
       backgroundImage = null
     }
   }

   def setup(): Unit = {}
   def update():Unit = {}
   def draw(g2D: Graphics2D):Unit = {}

   //paint the panel background (uses backgroundImage if set, else fills with backgroundColor)
   def drawBackground(g2D: Graphics2D): Unit = {
     if (backgroundImage != null) {
       g2D.drawImage(backgroundImage, 0, 0, null)
     } else {
       g2D.setColor(backgroundColor)
       g2D.fill(new Rectangle2D.Double(0, 0, width * Config.qualityMultiple, height * Config.qualityMultiple))
     }
   }
   //paint the panel background with an explicit image (legacy overload)
   def drawBackground(g2D: Graphics2D, im: BufferedImage): Unit = {
      g2D.drawImage(im, null, 0, 0)
   }
   //paint the panel background once
   def drawBackgroundOnce(g2D: Graphics2D): Unit = {
       if (!drawn) { drawBackground(g2D); drawn = true }
   }
   //paint the panel background once with an image (legacy overload)
   def drawBackgroundOnce(g2D: Graphics2D, im: BufferedImage): Unit = {
       g2D.drawImage(im, null, 0, 0)
   }
   /**
   Draws an overlay semi-transparent rectangle - useful for creating trail effect.
   */
   def drawOverlay(g2D: Graphics2D): Unit = {
       g2D.setColor(overlayColor)
       g2D.fill(new Rectangle2D.Double(0, 0, width, height))
   }

   /**
   draws central axes on the screen
   */
   def drawAxes(g2D: Graphics2D): Unit = {
      g2D.setColor(axesColor)
      g2D.setStroke(new BasicStroke(axesStrokeWeight))
      g2D.drawLine(width/2, 0, width/2, height)
      g2D.drawLine(0, height/2, width, height/2)
   }
   /**
   implemented in MySketch (particularly for rfid events
   */
   def serialEventNotify(): Unit = {
   }

}
