/**
DrawManager
*/

package org.loom.scaffold

import java.awt._
import org.loom.mysketch._
import org.loom.config.ProjectConfigManager

class DrawManager() {

   var drawn: Boolean = false
   private var drawCycle: Int = 0

   // --- Setup ---
   var sketch: Sketch = new MySketch(Config.width, Config.height)
   sketch.setup()
   sketch.setupBackgroundImage()

   def update(): Unit = {
      if (Config.animating) {
         sketch.update()
      }
   }

   def draw(graphics: Graphics): Unit = {
      val g2D: Graphics2D = graphics.asInstanceOf[Graphics2D]
      g2D.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
      if (Config.animating) {
         // --- Animating: draw each frame and report cycle count every 100 frames ---
         sketch.draw(g2D)
         drawCycle += 1
         if (drawCycle % 100 == 0) println(s"[Loom] Draw cycle: $drawCycle")
      } else {
         // --- Static: draw once only ---
         if (!drawn) sketch.draw(g2D)
         drawn = true
      }
   }

   def reload(): Unit = {
      // --- Reload: re-read all project config and reinitialise sketch ---
      println(s"[Loom] Reloading project '${ProjectConfigManager.currentProject}'...")
      if (ProjectConfigManager.reloadProject()) {
         val globalConfig = ProjectConfigManager.getGlobalConfig
         Main.applyGlobalConfigToLegacy(globalConfig)
         sketch = new MySketch(Config.width, Config.height)
         sketch.setup()
         sketch.setupBackgroundImage()
         drawn = false
         drawCycle = 0
         println(s"[Loom] Reload complete — canvas: ${Config.width}×${Config.height}, quality: ${Config.qualityMultiple}×")
      } else {
         println("[Loom] Reload failed — check project config files")
      }
   }
}
