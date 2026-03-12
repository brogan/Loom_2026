/**
DrawPanel
*/

package org.loom.scaffold

import javax.swing._
import java.awt._
import java.awt.event._
import java.awt.image.BufferedImage
import java.io.File
import org.loom.interaction._
import org.loom.media.ImageWriter
import org.loom.config.ProjectConfigManager

class DrawPanel() extends JPanel {

    println("DrawPanel loaded")

    ImageWriter.setWriteType("png")

    var paused: Boolean = false
    val drawManager: DrawManager = new DrawManager()

    val interactionManager: InteractionManager = new InteractionManager(drawManager)

    val keyL: KeyListener = new KeyPressListener(interactionManager)
    addKeyListener(keyL)

    val mC: MouseAdapter = new MouseClick(interactionManager).asInstanceOf[MouseAdapter]
    addMouseListener(mC)

    val mML: MouseMotionListener = new MouseMotion(interactionManager).asInstanceOf[MouseMotionListener]
    addMouseMotionListener(mML)

    setFocusable(true)

    var dBuffer: Image = null
    /*
    AnimationActor.setDrawPanel(this)
    AnimationActor.start()
    */


    val Animate: AnimationRunnable = new AnimationRunnable()
    Animate.setDrawPanel(this)

    setOpaque(true) // panel covers all its pixels — prevents parent background flashing through

    Animate.startAnimationThread()
    Animate.begin()

    // Sentinel file watcher — checks every 500ms for .reload, .capture_still, .capture_video
    private val sentinelTimer: Timer = new Timer(500, (_: ActionEvent) => checkSentinelFiles())
    sentinelTimer.start()


    def animationUpdate(): Unit = {
        //println("updating animation");
        if (!paused) {
           drawManager.update()
        }
    }

    def animationRender(): Unit = {
        //println("rendering animation");
        if (dBuffer == null) {//only runs first time through
           //dBuffer = createImage(Config.width * Config.qualityMultiple, Config.height * Config.qualityMultiple);
           dBuffer = new BufferedImage(Config.width * Config.qualityMultiple, Config.height * Config.qualityMultiple, BufferedImage.TYPE_INT_ARGB);//not working? (2022)
        } else {
            val dBufferGraphics = dBuffer.getGraphics();
            drawManager.draw(dBufferGraphics);
            repaint() // schedule paint on EDT — thread-safe, no direct getGraphics() call
        }
        exportSequencesStills()
    }

//this is apparently the way to enable alpha transparency
    override def paintComponent(g: Graphics): Unit = {
        super.paintComponent(g);
        val g2D: Graphics2D = g.asInstanceOf[Graphics2D]
        //g2D.setComposite(AlphaComposite.DstOver);//added 2022
        if (dBuffer != null) {
            scaleImageToPanel(g2D, dBuffer)
        } else {
            System.out.println("unable to create double buffer")
        }
    }
//this was the old method which did not refer to superclass
    def paintScreen(g: Graphics): Unit = {
        val g2D: Graphics2D = g.asInstanceOf[Graphics2D]
        if (dBuffer != null) {
            scaleImageToPanel(g2D, dBuffer)
        } else {
            System.out.println("unable to create double buffer")
        }
    }

    /**
     * Scale dBuffer to fit the panel, maintaining aspect ratio.
     * Centres the image and fills any letterbox/pillarbox area with the border colour.
     */
    private def scaleImageToPanel(g2D: Graphics2D, img: Image): Unit = {
        val srcW = img.getWidth(null)
        val srcH = img.getHeight(null)
        val panelW = getWidth
        val panelH = getHeight
        val scale = Math.min(panelW.toDouble / srcW, panelH.toDouble / srcH)
        val destW = Math.round(srcW * scale).toInt
        val destH = Math.round(srcH * scale).toInt
        val destX = (panelW - destW) / 2
        val destY = (panelH - destH) / 2
        // Fill letterbox / pillarbox areas with border colour
        g2D.setColor(Config.borderColor)
        g2D.fillRect(0, 0, panelW, panelH)
        // Draw scaled image with bilinear interpolation
        g2D.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
        g2D.drawImage(img, destX, destY, destW, destH, null)
    }
    def exportSequencesStills(): Unit = {
        if (Capture.savingStill) {
            writeImage();
            Capture.savingStill = false;
        } else if (Capture.savingVideo) {
            Capture.incrementSaveCount()
            writeImage();
        }
    }
    def writeImage(): Unit = {
        println("DrawPanel, writePath: " + Capture.writePath)
        if (dBuffer == null) {
            println("DrawPanel: buffer null: can't save image")
        }
        ImageWriter.saveImage(dBuffer.asInstanceOf[BufferedImage]);
    }

    private def checkSentinelFiles(): Unit = {
        val projectPath = ProjectConfigManager.currentProjectPath
        if (projectPath.isEmpty) return

        val projectDir = new File(projectPath)
        if (!projectDir.isDirectory) return

        // Check .reload sentinel
        val reloadFile = new File(projectDir, ".reload")
        if (reloadFile.exists()) {
            reloadFile.delete()
            println("DrawPanel: .reload sentinel detected, reloading...")
            drawManager.reload()
        }

        // Check .capture_still sentinel
        val captureStillFile = new File(projectDir, ".capture_still")
        if (captureStillFile.exists()) {
            captureStillFile.delete()
            println("DrawPanel: .capture_still sentinel detected")
            Capture.captureStill()
        }

        // Check .capture_video sentinel
        val captureVideoFile = new File(projectDir, ".capture_video")
        if (captureVideoFile.exists()) {
            captureVideoFile.delete()
            println("DrawPanel: .capture_video sentinel detected")
            if (Capture.savingVideo) {
                // Toggle off
                Capture.savingVideo = false
                println("DrawPanel: video capture stopped")
            } else {
                Capture.captureVideo()
                println("DrawPanel: video capture started")
            }
        }

        // Check .pause sentinel (persistent — not deleted, presence = paused)
        val pauseFile = new File(projectDir, ".pause")
        val shouldPause = pauseFile.exists()
        if (shouldPause != paused) {
            paused = shouldPause
            drawManager.sketch.paused = shouldPause
            // Freeze/unfreeze dynamic renderer changes so they pause cleanly
            drawManager.sketch match {
                case ms: org.loom.mysketch.MySketch =>
                    for (rs <- ms.renderSetLibrary.library) {
                        rs.frozen = shouldPause
                    }
                case _ =>
            }
            if (shouldPause) {
                println("DrawPanel: animation paused")
            } else {
                println("DrawPanel: animation resumed")
            }
        }
    }
}
