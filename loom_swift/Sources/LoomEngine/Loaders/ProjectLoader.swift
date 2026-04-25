import Foundation

/// Errors thrown by `ProjectLoader`.
public enum ProjectLoaderError: Error, LocalizedError {
    case projectDirectoryNotFound(URL)
    case missingFile(String)

    public var errorDescription: String? {
        switch self {
        case .projectDirectoryNotFound(let url):
            return "Project directory not found: \(url.path)"
        case .missingFile(let name):
            return "Required project file missing: \(name)"
        }
    }
}

/// Loads a complete `ProjectConfig` from a `.loom_projects` project directory.
///
/// ### Expected layout
/// ```
/// <ProjectName>/
///   configuration/
///     global_config.xml
///     shapes.xml
///     polygons.xml
///     subdivision.xml
///     rendering.xml
///     sprites.xml
/// ```
///
/// All six config files are required; missing files throw `ProjectLoaderError.missingFile`.
public enum ProjectLoader {

    public static func load(projectDirectory: URL) throws -> ProjectConfig {
        let fm   = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: projectDirectory.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectLoaderError.projectDirectoryNotFound(projectDirectory)
        }

        let configDir = projectDirectory.appendingPathComponent("configuration")

        func file(_ name: String) throws -> URL {
            let url = configDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else {
                throw ProjectLoaderError.missingFile("configuration/\(name)")
            }
            return url
        }

        let globalConfig      = try XMLConfigLoader.loadGlobalConfig(url:    file("global_config.xml"))
        let shapeConfig       = try XMLConfigLoader.loadShapeConfig(url:     file("shapes.xml"))
        let polygonConfig     = try XMLConfigLoader.loadPolygonConfig(url:   file("polygons.xml"))
        let subdivisionConfig = try XMLConfigLoader.loadSubdivisionConfig(url: file("subdivision.xml"))
        let renderingConfig   = try XMLConfigLoader.loadRenderingConfig(url: file("rendering.xml"))
        let spriteConfig      = try XMLConfigLoader.loadSpriteConfig(url:    file("sprites.xml"))

        // curves.xml and ovals.xml are optional — projects that don't use those
        // geometry types omit them.
        func optionalConfig<T>(_ filename: String, load: (URL) throws -> T, fallback: T) -> T {
            let url = configDir.appendingPathComponent(filename)
            guard fm.fileExists(atPath: url.path) else { return fallback }
            return (try? load(url)) ?? fallback
        }

        let curveConfig = optionalConfig("curves.xml",
                                          load: XMLConfigLoader.loadCurveConfig,
                                          fallback: CurveConfig())
        let ovalConfig  = optionalConfig("ovals.xml",
                                          load: XMLConfigLoader.loadOvalConfig,
                                          fallback: OvalConfig())
        let pointConfig = optionalConfig("points.xml",
                                          load: XMLConfigLoader.loadPointConfig,
                                          fallback: PointConfig())

        return ProjectConfig(
            globalConfig:      globalConfig,
            shapeConfig:       shapeConfig,
            polygonConfig:     polygonConfig,
            curveConfig:       curveConfig,
            ovalConfig:        ovalConfig,
            pointConfig:       pointConfig,
            subdivisionConfig: subdivisionConfig,
            renderingConfig:   renderingConfig,
            spriteConfig:      spriteConfig
        )
    }
}
