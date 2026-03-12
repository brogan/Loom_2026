/**
MouseMotion
*/
package org.loom.interaction

import java.awt.event._

class MouseMotion (val interactionManager: InteractionManager) extends MouseMotionListener {
	
   /**
   * mouseMoved
   * @param event
   */
   override def mouseMoved(event: MouseEvent): Unit = {
      //println("Mouse X: "+event.getPoint().x);
      //interactionManager.mousePosition = event.getPoint()
   }
   /**
   * mouseDragged
   * @param event
   */
   override def mouseDragged(event: MouseEvent): Unit = {
      interactionManager.mouseDragged = true
      interactionManager.mousePosition = event.getPoint()
      println("mouseDragged interactionManager.mousePosition: " + interactionManager.mousePosition)
   }
}
