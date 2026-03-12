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

   val toolkit: Toolkit  =  Toolkit.getDefaultToolkit()
   val dim: Dimension  = toolkit.getScreenSize()
   val panel: DrawPanel = new DrawPanel()

   if (Config.fullscreen) {
      val holder: JPanel = new JPanel()
      holder.setLayout(new BoxLayout(holder, BoxLayout.LINE_AXIS))
      holder.setSize(dim.width, dim.height)
      holder.setMinimumSize(dim)

      holder.setBackground(Config.borderColor)//SETS FRAME COLOR

      val panelDim: Dimension = new Dimension(Config.width, Config.height)
      panel.setMinimumSize(panelDim)
      panel.setPreferredSize(panelDim)
      panel.setMaximumSize(panelDim)
      holder.add(Box.createHorizontalGlue())
      holder.add(panel)
      holder.add(Box.createHorizontalGlue())

      frame.setDefaultCloseOperation(javax.swing.WindowConstants.EXIT_ON_CLOSE)
      frame.setSize(dim.width,dim.height)
      frame.getContentPane().add(holder)

      val screen: SimpleScreenManager = new SimpleScreenManager()

      var displayMode: DisplayMode  = Display.getDisplayMode(dim)
      if (displayMode==null) {
	 displayMode = new DisplayMode(5120, 2880, 32, DisplayMode.REFRESH_RATE_UNKNOWN)//default
      }
      try {
         println("Play Frame set full screen")
	 screen.setFullScreen(displayMode, frame)
      } catch {
         case _: Exception => println("Play Frame set full screen exception")
         System.exit(0)
      }
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
