/**
 * Program entry point
 * Supports both GUI mode (default) and CLI mode for backward compatibility.
 *
 * Usage:
 *   GUI mode (default):    sbt "run"
 *   CLI mode (legacy):     sbt "run --cli Subdivide config_default.xml"
 *   Project mode:          sbt "run --project MyProject"
 */
package org.loom.scaffold

import org.loom.config.{ProjectConfigManager, GlobalConfig}
import org.loom.ui.ProjectSelector

object Main {

  def main(args: Array[String]): Unit = {
    // Initialize the configuration manager
    ProjectConfigManager.initialize()

    // Parse arguments
    args.toList match {
      case "--cli" :: sketchName :: configName :: _ =>
        // Legacy CLI mode: load from sketches directory
        runCliMode(sketchName, configName)

      case "--project" :: projectName :: _ =>
        // Load project from ~/.loom_projects/
        runProjectMode(projectName)

      case "--help" :: _ =>
        printHelp()

      case "--bake-subdivision" :: inputPath :: subdivXmlPath :: setName :: outputPath :: _ =>
        org.loom.tools.SubdivisionBaker.bake(inputPath, subdivXmlPath, setName, outputPath)
        System.exit(0)

      case Nil =>
        // Default: GUI mode
        runGuiMode()

      case sketchName :: configName :: _ if !sketchName.startsWith("--") =>
        // Legacy format without --cli flag (backward compatible)
        runCliMode(sketchName, configName)

      case _ =>
        // Default to GUI mode for any other args
        runGuiMode()
    }
  }

  private def runGuiMode(): Unit = {
    println("Loom - Starting in GUI mode")

    // Use selectProject() which blocks until a project is selected
    val selectedProject = ProjectSelector.selectProject()

    if (selectedProject.nonEmpty) {
      // Project loaded, start the application
      val globalConfig = ProjectConfigManager.getGlobalConfig
      applyGlobalConfigToLegacy(globalConfig)

      println(s"[Loom] Project '${ProjectConfigManager.currentProject}' — canvas: ${globalConfig.width}×${globalConfig.height}, quality: ${globalConfig.qualityMultiple}×, animating: ${globalConfig.animating}")

      // Create the draw frame
      val frame: DrawFrame = DrawFrame()

      // Keep main thread alive while GUI is running
      val latch = java.util.concurrent.CountDownLatch(1)
      frame.frame.addWindowListener(new java.awt.event.WindowAdapter {
        override def windowClosed(e: java.awt.event.WindowEvent): Unit = {
          latch.countDown()
        }
      })
      latch.await()
    } else {
      println("No project selected. Exiting.")
      System.exit(0)
    }
  }

  private def runProjectMode(projectName: String): Unit = {
    println(s"Loom - Loading project: $projectName")

    if (ProjectConfigManager.loadProject(projectName)) {
      val globalConfig = ProjectConfigManager.getGlobalConfig
      applyGlobalConfigToLegacy(globalConfig)

      println(s"[Loom] Project '$projectName' — canvas: ${globalConfig.width}×${globalConfig.height}, quality: ${globalConfig.qualityMultiple}×, animating: ${globalConfig.animating}")

      // Create the draw frame
      val frame: DrawFrame = DrawFrame()

      // Keep main thread alive while GUI is running
      val latch = java.util.concurrent.CountDownLatch(1)
      frame.frame.addWindowListener(new java.awt.event.WindowAdapter {
        override def windowClosed(e: java.awt.event.WindowEvent): Unit = {
          latch.countDown()
        }
      })
      latch.await()
    } else {
      println(s"[Loom] Error: failed to load project '$projectName'")
      println(s"Available projects: ${ProjectConfigManager.listProjects.mkString(", ")}")
      System.exit(1)
    }
  }

  private def runCliMode(sketchName: String, configName: String): Unit = {
    println(s"Loom - CLI mode: sketchName=$sketchName, config=$configName")

    // Use legacy Config loading
    Config.configure(sketchName, configName)
    println(Config.toString())

    // Create the draw frame
    val frame: DrawFrame = DrawFrame()
  }

  def applyGlobalConfigToLegacy(globalConfig: GlobalConfig): Unit = {
    Config.name = globalConfig.name
    Config.width = globalConfig.width
    Config.height = globalConfig.height
    Config.qualityMultiple = globalConfig.qualityMultiple
    Config.animating = globalConfig.animating
    Config.drawBackgroundOnce = globalConfig.drawBackgroundOnce
    Config.fullscreen = globalConfig.fullscreen
    Config.borderColor = globalConfig.borderColor
    Config.backgroundImagePath = globalConfig.backgroundImagePath
    Config.serial = false
    Config.port = ""
    Config.mode = ""
    Config.quantity = 1
  }

  private def printHelp(): Unit = {
    println(
      """
        |Loom - Generative Art Application
        |
        |Usage:
        |  loom                              Start in GUI mode (project selector)
        |  loom --project <name>             Load project from ~/.loom_projects/
        |  loom --cli <sketch> <config>      Legacy CLI mode (sketches directory)
        |  loom --bake-subdivision <in> <subdiv.xml> <setName> <out>  Bake subdivision to file
        |  loom --help                       Show this help message
        |
        |Examples:
        |  sbt "run"                         Start GUI mode
        |  sbt "run --project MyProject"     Load MyProject
        |  sbt "run --cli Subdivide config_default.xml"  Legacy mode
        |
        |Projects Directory: ~/.loom_projects/
        |""".stripMargin)
  }
}
