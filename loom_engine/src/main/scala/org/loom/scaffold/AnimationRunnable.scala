package org.loom.scaffold



/**
 * @author brogan

 */

class AnimationRunnable extends Runnable {
  
  var drawPanel: DrawPanel = null
  var AnimationThread:Thread = null 
  var isRunning: Boolean = false
  var isPaused: Boolean = false
  var ex: InterruptedException = null
  
  def run(): Unit = {
    //System.out.println("begin in run: "+isRunning);
        while (isRunning) {
          if (!isPaused) {
            //System.out.println("IconDrawPanel, paused: "+ paused);
            drawPanel.animationUpdate();
            drawPanel.animationRender();//to a buffer
            Thread.sleep(100)
          }
        }
                /*
        try {
          Thread.sleep(20)
        } 

        catch { 
          ex: InterruptedException
        }
        */
        
  }
  
  
  def begin(): Unit = {
    isRunning = true
  }

  def startAnimationThread(): Unit = {
    AnimationThread = new Thread(this)
    if (AnimationThread != null) {
        begin()
        AnimationThread.start()
        println("[Loom] Animation thread started")
    } else {
        println("[Loom] Warning: animation thread could not be created")
    }
  }
  
    def setDrawPanel(dP: DrawPanel): Unit = {
       drawPanel = dP
    }
  
    def setPaused(): Unit = {
      if (isPaused) {
         isPaused = false;
      } else {
         isPaused = true;
      }
    }
    
    def kill(): Unit = {
        isRunning = false
        println("[Loom] Animation thread stopped")
    }
    
    

}