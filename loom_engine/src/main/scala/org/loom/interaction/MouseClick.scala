/**
MouseClick
*/
package org.loom.interaction

import java.awt.event._

class MouseClick (val interactionManager: InteractionManager) extends MouseAdapter {
	
   /**
   * mouseMoved
   * @param event
   */
   override def mouseMoved(event: MouseEvent): Unit = {
      //println("Mouse X: "+event.getPoint().x);
      //interactionManager.mousePosition = event.getPoint()
   }
   /**
   * mousePressed
   * @param event
   */
   override def mousePressed(event: MouseEvent): Unit = {
      interactionManager.mousePressed = true
      interactionManager.mousePosition = event.getPoint()
      println("interactionManager.mousePosition: " + interactionManager.mousePosition)
   }
   /**
   * mouseReleased
   * @param event
   */
   override def mouseReleased(event: MouseEvent): Unit = {
      interactionManager.mouseReleased = true
      interactionManager.mousePosition = event.getPoint()
   }
}
