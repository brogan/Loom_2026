/**
DrawFrame
*/
package org.loom.scaffold

import javax.swing._
import java.awt._
import java.awt.event._

class DrawFrame () extends JFrame {

   println("DrawFrame loaded")

   val frame: JFrame = new JFrame(Config.name)

   val panel: DrawPanel = new DrawPanel()

   if (Config.fullscreen) {
      // Centre the canvas at its configured pixel size on a borderColor background.
      // Uses JFrame maximise rather than exclusive fullscreen, which is unreliable
      // on modern macOS (AWT setFullScreenWindow fights the OS window manager).
      val holder: JPanel = new JPanel()
      holder.setLayout(new BoxLayout(holder, BoxLayout.LINE_AXIS))
      holder.setBackground(Config.borderColor)

      val panelDim: Dimension = new Dimension(Config.width, Config.height)
      panel.setMinimumSize(panelDim)
      panel.setPreferredSize(panelDim)
      panel.setMaximumSize(panelDim)
      holder.add(Box.createHorizontalGlue())
      holder.add(panel)
      holder.add(Box.createHorizontalGlue())

      frame.setUndecorated(true)
      frame.setDefaultCloseOperation(javax.swing.WindowConstants.EXIT_ON_CLOSE)
      frame.getContentPane().add(holder, java.awt.BorderLayout.CENTER)
      frame.setExtendedState(Frame.MAXIMIZED_BOTH)
      frame.setVisible(true)
      println("DrawFrame: fullscreen via MAXIMIZED_BOTH")
   } else {
         frame.setDefaultCloseOperation(javax.swing.WindowConstants.EXIT_ON_CLOSE)
         frame.setResizable(true)
         frame.setMinimumSize(new Dimension(Math.max(Config.width / 4, 120), Math.max(Config.height / 4, 120) + 16))
         frame.setSize(Config.width, Config.height + 16)
         frame.getContentPane().add(panel, java.awt.BorderLayout.CENTER)
         frame.setVisible(true);
   }

   override def processWindowEvent(e: WindowEvent): Unit = {
      if (e.getID() == WindowEvent.WINDOW_CLOSING) {
         frame.removeAll();
	     frame.dispose();
      }
   }
}
