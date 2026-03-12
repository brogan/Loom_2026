package org.loom.config

import org.loom.scene.{RendererSetLibrary, RendererSet}
import org.loom.media.{RenderingConfigLoader, PolygonConfigLoader, SubdivisionConfigLoader, ShapeConfigLoader, SpriteConfigLoader, ShapeLibrary, SpriteLibrary}
import org.loom.geometry.{PolygonSetCollection, SubdivisionParamsSetCollection}
import java.io.File

/**
 * Central manager for loading and accessing project configurations.
 * Orchestrates loading of all XML configuration files for a project.
 * Provides API for MySketch and other components to query configurations.
 */
object ProjectConfigManager {

  // Current state
  private var _currentProject: String = ""
  private var _projectLoaded: Boolean = false

  // Loaded configurations
  private var _globalConfig: GlobalConfig = GlobalConfig.default
  private var _renderingConfig: Option[RendererSetLibrary] = None
  private var _polygonConfig: Option[PolygonSetCollection] = None
  private var _subdivisionConfig: Option[SubdivisionParamsSetCollection] = None
  private var _shapeConfig: Option[ShapeLibrary] = None
  private var _spriteConfig: Option[SpriteLibrary] = None

  // Configuration file names
  val GlobalConfigFile = "global_config.xml"
  val RenderingConfigFile = "rendering.xml"
  val PolygonsConfigFile = "polygons.xml"
  val SubdivisionConfigFile = "subdivision.xml"
  val ShapesConfigFile = "shapes.xml"
  val SpritesConfigFile = "sprites.xml"
  val ProjectManifestFile = "project.xml"

  def initialize(): Unit = {
    ProjectPaths.initialize()
  }

  def loadProject(projectName: String): Boolean = {
    if (!ProjectPaths.projectExists(projectName)) {
      println(s"Project not found: $projectName")
      return false
    }

    _currentProject = projectName
    _projectLoaded = false

    try {
      // Load global config
      val globalConfigPath = ProjectPaths.getConfigFilePath(projectName, GlobalConfigFile)
      _globalConfig = if (File(globalConfigPath).exists()) {
        GlobalConfigLoader.load(globalConfigPath)
      } else {
        println(s"Warning: $GlobalConfigFile not found, using defaults")
        GlobalConfig.default
      }

      // Load rendering config
      val renderingConfigPath = ProjectPaths.getConfigFilePath(projectName, RenderingConfigFile)
      _renderingConfig = if (File(renderingConfigPath).exists()) {
        Some(RenderingConfigLoader.load(renderingConfigPath))
      } else {
        println(s"Warning: $RenderingConfigFile not found")
        None
      }

      // Load polygon config
      val polygonConfigPath = ProjectPaths.getConfigFilePath(projectName, PolygonsConfigFile)
      _polygonConfig = if (File(polygonConfigPath).exists()) {
        val polygonSetsPath = ProjectPaths.getPolygonSetsPath(projectName)
        val collection = PolygonConfigLoader.load(polygonConfigPath, polygonSetsPath)
        if (collection.collection.nonEmpty) Some(collection) else None
      } else {
        println(s"Warning: $PolygonsConfigFile not found")
        None
      }

      // Load subdivision config
      val subdivisionConfigPath = ProjectPaths.getConfigFilePath(projectName, SubdivisionConfigFile)
      _subdivisionConfig = if (File(subdivisionConfigPath).exists()) {
        val collection = SubdivisionConfigLoader.load(subdivisionConfigPath)
        if (collection.collection.nonEmpty) Some(collection) else None
      } else {
        println(s"Warning: $SubdivisionConfigFile not found")
        None
      }

      // Load shape config
      val shapeConfigPath = ProjectPaths.getConfigFilePath(projectName, ShapesConfigFile)
      _shapeConfig = if (File(shapeConfigPath).exists()) {
        val library = ShapeConfigLoader.load(shapeConfigPath)
        if (library.shapeSets.nonEmpty) Some(library) else None
      } else {
        println(s"Warning: $ShapesConfigFile not found")
        None
      }

      // Load sprite config
      val spriteConfigPath = ProjectPaths.getConfigFilePath(projectName, SpritesConfigFile)
      _spriteConfig = if (File(spriteConfigPath).exists()) {
        val library = SpriteConfigLoader.load(spriteConfigPath)
        if (library.spriteSets.nonEmpty) Some(library) else None
      } else {
        println(s"Warning: $SpritesConfigFile not found")
        None
      }

      // Update last project
      ProjectPaths.lastProject = projectName

      _projectLoaded = true
      println(s"Loaded project: $projectName")
      true

    } catch {
      case e: Exception =>
        println(s"Error loading project $projectName: ${e.getMessage}")
        e.printStackTrace()
        false
    }
  }

  def isProjectLoaded: Boolean = _projectLoaded

  def currentProject: String = _currentProject

  def getGlobalConfig: GlobalConfig = _globalConfig

  def getRenderingConfig: Option[RendererSetLibrary] = _renderingConfig

  def getRendererSet(name: String): RendererSet = {
    _renderingConfig.flatMap { lib =>
      Option(lib.getRendererSet(name))
    }.orNull
  }

  def getPolygonConfig: Option[PolygonSetCollection] = _polygonConfig

  def getSubdivisionConfig: Option[SubdivisionParamsSetCollection] = _subdivisionConfig

  def getShapeConfig: Option[ShapeLibrary] = _shapeConfig

  def getSpriteConfig: Option[SpriteLibrary] = _spriteConfig

  def projectsDirectory: String = ProjectPaths.projectsDirectory

  def projectsDirectory_=(dir: String): Unit = {
    ProjectPaths.projectsDirectory = dir
  }

  def listProjects: List[String] = ProjectPaths.listProjects()

  def createProject(projectName: String): Boolean = {
    if (ProjectPaths.createProject(projectName)) {
      createDefaultConfigFiles(projectName)
      true
    } else {
      false
    }
  }

  private def createDefaultConfigFiles(projectName: String): Unit = {
    val globalConfigPath = ProjectPaths.getConfigFilePath(projectName, GlobalConfigFile)
    val defaultGlobal = GlobalConfig(name = projectName)
    GlobalConfigLoader.save(defaultGlobal, globalConfigPath)
    println(s"Created default configuration files for project: $projectName")
  }

  def reloadProject(): Boolean = {
    if (_currentProject.nonEmpty) {
      loadProject(_currentProject)
    } else {
      false
    }
  }

  def unloadProject(): Unit = {
    _currentProject = ""
    _projectLoaded = false
    _globalConfig = GlobalConfig.default
    _renderingConfig = None
    _polygonConfig = None
    _subdivisionConfig = None
    _shapeConfig = None
    _spriteConfig = None
  }

  def currentProjectPath: String = {
    if (_currentProject.nonEmpty) {
      ProjectPaths.getProjectPath(_currentProject)
    } else {
      ""
    }
  }

  def loadLastProject(): Boolean = {
    val lastProject = ProjectPaths.lastProject
    if (lastProject.nonEmpty && ProjectPaths.projectExists(lastProject)) {
      loadProject(lastProject)
    } else {
      false
    }
  }
}
