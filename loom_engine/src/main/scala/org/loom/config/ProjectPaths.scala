package org.loom.config

import java.io.File
import scala.xml.*

/**
 * Manages project directory paths and preferences.
 * Default projects directory: ~/.loom_projects/
 * Preferences stored in: ~/.loom_projects/.loom_config
 */
object ProjectPaths {

  // Default projects directory
  private val defaultProjectsDir: String = System.getProperty("user.home") + File.separator + ".loom_projects"

  // Current projects directory (can be changed by user)
  private var _projectsDirectory: String = defaultProjectsDir

  // Last loaded project name
  private var _lastProject: String = ""

  // Config file name
  private val configFileName = ".loom_config"

  def projectsDirectory: String = _projectsDirectory

  def projectsDirectory_=(dir: String): Unit = {
    _projectsDirectory = dir
    savePreferences()
  }

  def lastProject: String = _lastProject

  def lastProject_=(name: String): Unit = {
    _lastProject = name
    savePreferences()
  }

  /**
   * Initialize the projects directory structure.
   * Creates the directory if it doesn't exist.
   * Loads preferences if they exist.
   */
  def initialize(): Unit = {
    // Create default directory if needed
    val dir = File(defaultProjectsDir)
    if (!dir.exists()) {
      dir.mkdirs()
      println(s"Created projects directory: $defaultProjectsDir")
    }

    // Load preferences
    loadPreferences()

    // Ensure current projects directory exists
    val currentDir = File(_projectsDirectory)
    if (!currentDir.exists()) {
      currentDir.mkdirs()
    }
  }

  def getProjectPath(projectName: String): String = {
    _projectsDirectory + File.separator + projectName
  }

  /**
   * Get the full path to a config file within a project.
   * Config files are stored in the configuration/ subdirectory.
   */
  def getConfigFilePath(projectName: String, fileName: String): String = {
    val projectPath = getProjectPath(projectName)
    val configPath = projectPath + File.separator + "configuration" + File.separator + fileName
    // Fall back to root if configuration/ doesn't exist (backward compatibility)
    if (File(configPath).exists() || File(projectPath + File.separator + "configuration").isDirectory) {
      configPath
    } else {
      // Legacy: files directly in project root
      projectPath + File.separator + fileName
    }
  }

  def getPolygonSetsPath(projectName: String): String = {
    getProjectPath(projectName) + File.separator + "polygonSets"
  }

  def getCurveSetsPath(projectName: String): String = {
    getProjectPath(projectName) + File.separator + "curveSets"
  }

  def getPointSetsPath(projectName: String): String = {
    getProjectPath(projectName) + File.separator + "pointSets"
  }

  def getMorphTargetsPath(projectName: String): String = {
    getProjectPath(projectName) + File.separator + "morphTargets"
  }

  def getBrushesPath(projectName: String): String = {
    getProjectPath(projectName) + File.separator + "brushes"
  }

  def getStencilsPath(projectName: String): String = {
    getProjectPath(projectName) + File.separator + "stencils"
  }

  /**
   * List all available projects in the projects directory.
   * A valid project is a directory containing a project.xml file.
   */
  def listProjects(): List[String] = {
    val dir = File(_projectsDirectory)
    if (dir.exists() && dir.isDirectory) {
      dir.listFiles()
        .filter(_.isDirectory)
        .filter(d => File(d, "project.xml").exists() || File(d, "global_config.xml").exists())
        .map(_.getName)
        .sorted
        .toList
    } else {
      List.empty
    }
  }

  def projectExists(projectName: String): Boolean = {
    val projectDir = File(getProjectPath(projectName))
    projectDir.exists() && projectDir.isDirectory
  }

  def createProject(projectName: String): Boolean = {
    val projectDir = File(getProjectPath(projectName))
    if (projectDir.exists()) {
      println(s"Project '$projectName' already exists")
      return false
    }

    try {
      // Create project directory structure
      projectDir.mkdirs()
      File(projectDir, "configuration").mkdirs()
      File(projectDir, "polygonSets").mkdirs()
      File(projectDir, "morphTargets").mkdirs()
      File(projectDir, "brushes").mkdirs()
      File(projectDir, "stencils").mkdirs()
      File(projectDir, "background_image").mkdirs()
      File(projectDir, "renders").mkdirs()
      File(projectDir, "renders/stills").mkdirs()
      File(projectDir, "renders/animations").mkdirs()

      // Create default project.xml in project root
      val projectXml =
        <LoomProject version="1.0">
          <Name>{projectName}</Name>
          <Description></Description>
          <Created>{java.time.LocalDateTime.now().toString}</Created>
          <Modified>{java.time.LocalDateTime.now().toString}</Modified>
          <Files>
            <File domain="global" path="configuration/global_config.xml"/>
            <File domain="rendering" path="configuration/rendering.xml"/>
            <File domain="polygons" path="configuration/polygons.xml"/>
            <File domain="subdivision" path="configuration/subdivision.xml"/>
            <File domain="shapes" path="configuration/shapes.xml"/>
            <File domain="sprites" path="configuration/sprites.xml"/>
          </Files>
        </LoomProject>

      XML.save(getProjectPath(projectName) + File.separator + "project.xml", projectXml, "UTF-8", xmlDecl = true)

      println(s"Created project: $projectName")
      true
    } catch {
      case e: Exception =>
        println(s"Failed to create project: ${e.getMessage}")
        false
    }
  }

  private def loadPreferences(): Unit = {
    val configFile = File(defaultProjectsDir + File.separator + configFileName)
    if (configFile.exists()) {
      try {
        val xml = XML.loadFile(configFile)
        _projectsDirectory = (xml \ "ProjectsDirectory").text match {
          case "" => defaultProjectsDir
          case dir => dir
        }
        _lastProject = (xml \ "LastProject").text
      } catch {
        case e: Exception =>
          println(s"Warning: Could not load preferences: ${e.getMessage}")
          _projectsDirectory = defaultProjectsDir
      }
    }
  }

  private def savePreferences(): Unit = {
    try {
      val configFile = File(defaultProjectsDir + File.separator + configFileName)
      val xml =
        <LoomConfig version="1.0">
          <ProjectsDirectory>{_projectsDirectory}</ProjectsDirectory>
          <LastProject>{_lastProject}</LastProject>
        </LoomConfig>

      XML.save(configFile.getAbsolutePath, xml, "UTF-8", xmlDecl = true)
    } catch {
      case e: Exception =>
        println(s"Warning: Could not save preferences: ${e.getMessage}")
    }
  }

  def getDefaultProjectsDirectory: String = defaultProjectsDir

  def resetToDefaultDirectory(): Unit = {
    _projectsDirectory = defaultProjectsDir
    savePreferences()
  }
}
