# Loom Engine — Configuration System
**Specification 05**
**Date:** 2026-04-27
**Depends on:** `01_technical_overview.md`

---

## 1. Purpose

This document specifies the Swift configuration system — how the engine loads, represents, and persists all project settings. It covers:

- `ProjectConfig` — the root configuration struct
- `GlobalConfig` and all nine sub-config types
- `ProjectLoader` — orchestrates loading from a project directory
- `XMLConfigLoader` — reads legacy XML project files
- `JSONConfigLoader` — reads/writes the Swift-native JSON format
- Project directory layout
- The sentinel file system for external control
- Comparison with the Scala configuration system

---

## 2. Overview

The Swift configuration system uses a single `ProjectConfig` struct (all `Codable`) that bundles nine sub-configs. Two load paths produce the same struct type:

```
Legacy .loom_projects XML ──── XMLConfigLoader ──┐
                                                   ├── ProjectConfig (Codable struct)
Swift-native JSON ──────────── JSONConfigLoader ──┘
```

`JSONConfigLoader` is also the write path — it saves `ProjectConfig` as pretty-printed JSON for Swift-native projects.

---

## 3. ProjectConfig

**File:** `Config/ProjectConfig.swift`

```swift
public struct ProjectConfig: Codable, Sendable {
    public var globalConfig:      GlobalConfig
    public var shapeConfig:       ShapeConfig
    public var polygonConfig:     PolygonConfig
    public var curveConfig:       CurveConfig
    public var ovalConfig:        OvalConfig
    public var pointConfig:       PointConfig
    public var subdivisionConfig: SubdivisionConfig
    public var renderingConfig:   RenderingConfig
    public var spriteConfig:      SpriteConfig
}
```

All fields have safe defaults via their sub-config initialisers. A `ProjectConfig()` with no arguments is a valid, runnable (if empty) project.

---

## 4. GlobalConfig

**File:** `Config/GlobalConfig.swift`

```swift
public struct GlobalConfig: Equatable, Codable, Sendable {
    public var name: String              = "default"
    public var width: Int                = 1080
    public var height: Int               = 1080
    public var qualityMultiple: Int      = 1
    public var scaleImage: Bool          = false
    public var animating: Bool           = false
    public var drawBackgroundOnce: Bool  = false
    public var fullscreen: Bool          = false
    public var borderColor: LoomColor    = .black
    public var backgroundColor: LoomColor = .white
    public var overlayColor: LoomColor   = LoomColor(r: 0, g: 0, b: 0, a: 170)
    public var backgroundImagePath: String = ""
    public var threeD: Bool              = false
    public var cameraViewAngle: Int      = 120
    public var subdividing: Bool         = true
    public var targetFPS: Double         = 30.0
}
```

### 4.1 targetFPS

`targetFPS` is a field added in the Swift implementation (not present in Scala `GlobalConfig`). It is used by `LoomEngine.advance(deltaTime:)` to convert wall-clock time to virtual frame counts:

```
elapsedFrames = elapsedTime × globalConfig.targetFPS
```

Virtual frame counts are then compared against integer `drawCycle` values in XML (keyframes, hold lengths, `pauseMax`). Default 30 matches the typical Scala Loom frame rate.

### 4.2 overlayColor

`overlayColor` is loaded and stored but **never applied** to the canvas, matching the Scala engine behaviour where it was defined but unused.

### 4.3 XML Element Name

The XML element is `<GlobalConfig>` with child elements `<Name>`, `<Width>`, `<Height>`, etc. (capital first letter, matching Scala's `GlobalConfigLoader` convention). See `06_serialization.md §4` for the full XML schema.

---

## 5. Sub-Config Types

All sub-config structs are `Codable, Sendable` with empty/default initialisers.

### 5.1 ShapeConfig

```swift
public struct ShapeConfig: Codable, Sendable {
    public var library: ShapeLibrary
}
```

`ShapeLibrary` holds `shapeSets: [ShapeSetDef]`, each containing `shapes: [ShapeDef]`. A `ShapeDef` specifies the geometry source (polygon set file, regular polygon, inline points, open curve set, point set, or oval set) and optional subdivision params set name and initial transform.

```swift
public enum SourceType: String, Codable, Sendable {
    case polygonSet, regularPolygon, inlinePoints, openCurveSet, pointSet, ovalSet
}
```

### 5.2 PolygonConfig / CurveConfig / OvalConfig / PointConfig

Each holds a `library` of named file references:

```swift
public struct PolygonSetDef: Codable, Sendable {
    public var name: String
    public var folder: String      // "polygonSet" → maps to "polygonSets/" at load time
    public var filename: String
    public var polygonType: PolygonFileType  // .splinePolygon | .linePolygon
    public var filter: String
    public var regularParams: RegularPolygonParams?  // non-nil for computed regular polygons
}
```

**Folder name mapping:** When `folder == "polygonSet"` (singular, the Scala legacy name) or is empty, `SpriteScene` resolves it to `"polygonSets/"` (plural, the actual on-disk directory name). Any other folder value is used as-is relative to the project root.

### 5.3 SubdivisionConfig

```swift
public struct SubdivisionConfig: Codable, Sendable {
    public var paramsSetCollection: [SubdivisionParamsSetDef]

    public func paramsSet(named: String) -> SubdivisionParamsSetDef?
}
```

See `02_subdivision.md` for the full `SubdivisionParams` field reference.

### 5.4 RenderingConfig

```swift
public struct RenderingConfig: Codable, Sendable {
    public var library: RendererSetLibraryDef

    public func rendererSet(named: String) -> RendererSet?
}
```

`rendererSet(named:)` returns the named set, or `nil` if not found. When `SpriteScene` gets `nil`, it falls back to a single default renderer — matching the Scala engine's behaviour when a renderer set name isn't found.

### 5.5 SpriteConfig

```swift
public struct SpriteConfig: Codable, Sendable {
    public var library: SpriteLibraryDef
}
```

`SpriteLibraryDef` contains `spriteSets: [SpriteSetDef]`. `allSprites` returns sprites from all sets in declaration order.

```swift
public struct SpriteDef: Codable, Sendable {
    public var name: String
    public var shapeSetName: String
    public var shapeName: String
    public var rendererSetName: String
    public var position: Vector2D
    public var scale: Vector2D
    public var rotation: Double
    public var animation: SpriteAnimation
}
```

---

## 6. ProjectLoader

**File:** `Loaders/ProjectLoader.swift`

```swift
public enum ProjectLoader {
    public static func load(projectDirectory: URL) throws -> ProjectConfig
}
```

`load(projectDirectory:)` reads six required files from `<projectDirectory>/configuration/`:

| File | Loaded by |
|------|-----------|
| `global_config.xml` | `XMLConfigLoader.loadGlobalConfig` |
| `shapes.xml` | `XMLConfigLoader.loadShapeConfig` |
| `polygons.xml` | `XMLConfigLoader.loadPolygonConfig` |
| `subdivision.xml` | `XMLConfigLoader.loadSubdivisionConfig` |
| `rendering.xml` | `XMLConfigLoader.loadRenderingConfig` |
| `sprites.xml` | `XMLConfigLoader.loadSpriteConfig` |

Three optional files (loaded if present):

| File | Loaded by |
|------|-----------|
| `curves.xml` | `XMLConfigLoader.loadCurveConfig` |
| `ovals.xml` | `XMLConfigLoader.loadOvalConfig` |
| `points.xml` | `XMLConfigLoader.loadPointConfig` |

Missing required files throw `ProjectLoaderError.missingFile`. Missing optional files use empty defaults.

### 6.1 Project Directory Layout

```
<ProjectName>/
  configuration/
    global_config.xml      ← GlobalConfig
    shapes.xml             ← ShapeConfig
    polygons.xml           ← PolygonConfig
    subdivision.xml        ← SubdivisionConfig
    rendering.xml          ← RenderingConfig
    sprites.xml            ← SpriteConfig
    curves.xml             ← CurveConfig (optional)
    ovals.xml              ← OvalConfig (optional)
    points.xml             ← PointConfig (optional)
  polygonSets/             ← polygon XML files (Bezier editor output)
  openCurveSets/           ← open curve XML files (optional)
  morphTargets/            ← morph target polygon files (optional)
  brushes/                 ← brush images (PNG/JPG)
  stamps/                  ← stamp/stencil images (PNG/JPG)
  renders/
    stills/                ← PNG exports
    animations/            ← video frames
```

---

## 7. XMLConfigLoader

**File:** `Loaders/XMLConfigLoader.swift`

`XMLConfigLoader` is a pure-function enum namespace. Each `load*` method reads one XML file and returns the corresponding config struct.

```swift
public enum XMLConfigLoader {
    public static func loadGlobalConfig(url: URL) throws -> GlobalConfig
    public static func loadShapeConfig(url: URL) throws -> ShapeConfig
    public static func loadPolygonConfig(url: URL) throws -> PolygonConfig
    public static func loadCurveConfig(url: URL) throws -> CurveConfig
    public static func loadOvalConfig(url: URL) throws -> OvalConfig
    public static func loadPointConfig(url: URL) throws -> PointConfig
    public static func loadSubdivisionConfig(url: URL) throws -> SubdivisionConfig
    public static func loadRenderingConfig(url: URL) throws -> RenderingConfig
    public static func loadSpriteConfig(url: URL) throws -> SpriteConfig
}
```

`XMLConfigLoader` handles all XML quirks documented in `06_serialization.md`:
- DTD suppression (Bezier-generated polygon files with DOCTYPE declarations)
- Three color formats (comma-string, RGBA attributes, key=value attributes)
- Preserved typos (`CpsSqueezeFacto`, `polysTranformWhole`) — reads both spellings
- Missing elements silently use Swift defaults

### 7.1 XMLNode

**File:** `Loaders/XMLNode.swift`

`XMLNode` is an internal helper struct that wraps `XMLParser`-based parsing into a lightweight DOM-like tree. `XMLConfigLoader` uses it for all XML loading.

---

## 8. JSONConfigLoader

**File:** `Loaders/JSONConfigLoader.swift`

```swift
public enum JSONConfigLoader {
    public static func encode(_ config: ProjectConfig) throws -> Data
    public static func save(_ config: ProjectConfig, to url: URL) throws
    public static func decode(from data: Data) throws -> ProjectConfig
    public static func load(url: URL) throws -> ProjectConfig
}
```

All config structs are `Codable`, so encode/decode are lossless (within floating-point precision). This is the write path for Swift-native projects; `XMLConfigLoader` remains the read path for legacy projects.

`JSONEncoder` output is `.prettyPrinted` and `.sortedKeys` for human readability and stable diffs.

---

## 9. LoomEngine Initialisation

`LoomEngine.init(projectDirectory: URL)` performs full project setup:

1. `ProjectLoader.load(projectDirectory:)` → `ProjectConfig`
2. `SpriteScene(config:projectDirectory:)` → `SpriteScene` (loads polygon files, assembles sprite instances)
3. `ViewTransform(canvasSize:)` from `config.globalConfig.width/height × qualityMultiple`
4. Load `backgroundImage` from `config.globalConfig.backgroundImagePath`
5. Load brush images from `<projectDirectory>/brushes/` — apply `CIBoxBlur` at each configured blur radius
6. Load stamp images from `<projectDirectory>/stamps/`
7. Initialise `AccumulationCanvas` if `drawBackgroundOnce == true`

---

## 10. Sentinel File System

The Swift engine preserves the sentinel file protocol for compatibility with `loom_parameter_editor`:

| File | Effect |
|------|--------|
| `.reload` | Re-read configuration, rebuild scene |
| `.capture_still` | Save one PNG frame to `renders/stills/` |
| `.capture_video` | Toggle sequential frame saving |
| `.pause` | Toggle animation pause while file exists |

The `.reload` and `.capture_still` files are deleted after processing. `.pause` is checked by presence — removing the file resumes animation.

**Polling vs events:** The Scala engine used a 500 ms `javax.swing.Timer`. The Swift implementation can use `DispatchSource.makeFileSystemObjectSource` for event-driven detection (lower latency, no polling overhead).

---

## 11. Scala Configuration Reference

For context, the Scala configuration system had two parallel systems:

| | Scala Legacy | Scala Modern |
|-|-------------|-------------|
| Class | `Config` (`object` singleton) | `GlobalConfig` (case class) |
| XML | `<sketch>` flat elements | `<GlobalConfig>` with typed attributes |
| Error handling | None — `NullPointerException` on missing fields | Safe defaults throughout |
| Scaffold coupling | All scaffold reads `Config.*` directly | Bridge via `applyGlobalConfigToLegacy()` |

The Swift implementation has no legacy system — it uses `ProjectConfig` exclusively. The Scala `Config` singleton, `DrawFrame`, `DrawPanel`, `DrawManager`, and `AnimationRunnable` are all replaced by `Engine`, `FrameLoop`, and `LoomApp`.
