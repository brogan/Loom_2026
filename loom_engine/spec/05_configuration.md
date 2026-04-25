# Loom Engine — Configuration System
**Specification 05**  
**Date:** 2026-04-19  
**Depends on:** `01_technical_overview.md`

---

## 1. Purpose

This document specifies the configuration system — how Loom initialises itself from files, how the application scaffold is structured, and how runtime control works. It covers:

- The legacy `Config` singleton
- The modern `GlobalConfig` / `GlobalConfigLoader` system
- `ProjectConfigManager` — the loader orchestrator
- The application scaffold: `Main`, `DrawFrame`, `DrawPanel`, `DrawManager`, `AnimationRunnable`
- The sentinel file system for external sketch control
- Design assessment and improvement recommendations

---

## 2. Two Configuration Systems

Loom has two configuration systems that coexist due to incremental modernisation. Understanding the distinction is important for the Swift migration.

| | Legacy | Modern |
|-|--------|--------|
| Class | `Config` (Scala `object`) | `GlobalConfig` (case class) |
| Loader | `Config.configure()` | `GlobalConfigLoader.load()` |
| XML format | Flat `<sketch>` elements | Typed `<GlobalConfig>` with attributes |
| Error handling | None — crashes on missing fields | Safe defaults throughout |
| Save support | No | Yes (`GlobalConfigLoader.save()`) |
| Used by | `DrawFrame`, `DrawPanel`, the entire scaffold | `ProjectConfigManager`, modern GUI path |

The modern system is the target. The legacy `Config` object is still the live dependency of the scaffold — `DrawFrame`, `DrawPanel`, and `Sketch` all read from `Config.*` directly. `Main.applyGlobalConfigToLegacy()` bridges the two by copying a loaded `GlobalConfig` into the `Config` singleton before the scaffold initialises.

---

## 3. Legacy Config Object

**File:** `src/main/scala/org/loom/scaffold/Config.scala`

`Config` is a Scala `object` (singleton). All fields are `var`.

### 3.1 Fields

| Field | Type | Default | XML element |
|-------|------|---------|-------------|
| `name` | `String` | `""` | `<name>` |
| `width` | `Int` | `720` | `<width>` |
| `height` | `Int` | `720` | `<height>` |
| `qualityMultiple` | `Int` | `1` | `<qualityMultiple>` |
| `animating` | `Boolean` | `false` | `<animating>` |
| `drawBackgroundOnce` | `Boolean` | `false` | `<drawBackgroundOnce>` |
| `fullscreen` | `Boolean` | `false` | `<fullscreen>` |
| `borderColor` | `Color` | black | `<borderColor>` ("R,G,B" string) |
| `serial` | `Boolean` | `false` | `<serial>` |
| `port` | `String` | `""` | `<port>` |
| `mode` | `String` | `""` | `<mode>` |
| `quantity` | `Int` | `0` | `<quantity>` |
| `backgroundImagePath` | `String` | `""` | `<backgroundImagePath>` |

### 3.2 XML Format

```xml
<sketch>
  <name>Subdivide</name>
  <width>1080</width>
  <height>1080</height>
  <qualityMultiple>1</qualityMultiple>
  <animating>false</animating>
  <fullscreen>false</fullscreen>
  <borderColor>0,0,0</borderColor>
  <serial>false</serial>
  <port>/dev/ttyUSB0</port>
  <mode>bytes</mode>
  <quantity>4</quantity>
</sketch>
```

Color is a comma-separated RGB string (`"0,0,0"`). No alpha support, no attribute form.

### 3.3 Loading

```scala
Config.configure(sketchName: String, configName: String): Unit
```

Reads from `sketches/<sketchName>/config/<configName>.xml` using `scala.xml.XML.loadFile()` with no error handling. Any missing element will throw a `NullPointerException`; any malformed number will throw a `NumberFormatException`.

### 3.4 Design Issues

- **C1:** No error handling — `TODO: XML loading not working!!!!!` comment remains on line 28. The file parses in practice because the actual config files are well-formed, but this is fragile.
- **C2:** Color uses a comma-separated RGB string — inconsistent with the modern RGBA attribute format.
- **C3:** No alpha channel for `borderColor`.
- **C4:** Entire scaffold depends on this singleton, making unit testing impossible without a real config file on disk.

---

## 4. Modern GlobalConfig

**File:** `src/main/scala/org/loom/config/GlobalConfig.scala`

```scala
case class GlobalConfig(
  name: String              = "default",
  width: Int                = 1080,
  height: Int               = 1080,
  qualityMultiple: Int      = 1,
  scaleImage: Boolean       = false,
  animating: Boolean        = false,
  drawBackgroundOnce: Boolean = false,
  fullscreen: Boolean       = false,
  borderColor: Color        = Color(0,0,0,255),
  backgroundColor: Color    = Color(255,255,255,255),
  overlayColor: Color       = Color(0,0,0,255),
  backgroundImagePath: String = "",
  threeD: Boolean           = false,
  cameraViewAngle: Int      = 120,
  subdividing: Boolean      = true
)

object GlobalConfig {
  def default: GlobalConfig = GlobalConfig()
}
```

### 4.1 XML Format

```xml
<GlobalConfig version="1.0">
  <Name>Project Name</Name>
  <Width>1080</Width>
  <Height>1080</Height>
  <QualityMultiple>1</QualityMultiple>
  <ScaleImage>false</ScaleImage>
  <Animating>false</Animating>
  <DrawBackgroundOnce>true</DrawBackgroundOnce>
  <Fullscreen>false</Fullscreen>
  <BorderColor r="0" g="0" b="0" a="255"/>
  <BackgroundColor r="255" g="255" b="255" a="255"/>
  <OverlayColor r="0" g="0" b="0" a="255"/>
  <BackgroundImage>/path/to/image.png</BackgroundImage>
  <ThreeD>false</ThreeD>
  <CameraViewAngle>120</CameraViewAngle>
  <Subdividing>true</Subdividing>
</GlobalConfig>
```

Colors use four separate `r`/`g`/`b`/`a` attributes; each attribute defaults independently if absent.

### 4.2 GlobalConfigLoader

**File:** `src/main/scala/org/loom/config/GlobalConfigLoader.scala`

```scala
object GlobalConfigLoader {
  def load(filePath: String): GlobalConfig
  def loadFromString(xmlContent: String): GlobalConfig
  def save(config: GlobalConfig, filePath: String): Unit
}
```

**Parsing helpers (all return defaults, never crash):**

```scala
getTextOrDefault(node, elem, default: String): String
getIntOrDefault(node, elem, default: Int): Int
getBoolOrDefault(node, elem, default: Boolean): Boolean
getColorOrDefault(node, elem, default: Color): Color
```

`load()` wraps everything in a `try/catch` that returns `GlobalConfig.default` on any exception. This is the only loader with save-back support.

---

## 5. ProjectConfigManager

**File:** `src/main/scala/org/loom/config/ProjectConfigManager.scala`

`ProjectConfigManager` is the central orchestrator for the modern loading pipeline.

### 5.1 Project Directory Layout

```
~/.loom_projects/<ProjectName>/
    global.xml              → GlobalConfig
    shapes.xml              → ShapeLibrary
    polygons.xml            → PolygonSetCollection
    curves.xml              → OpenCurveSetCollection
    points.xml              → PointSetCollection
    ovals.xml               → OvalSetCollection
    subdivision.xml         → SubdivisionParamsSetCollection
    rendering.xml           → RendererSetLibrary
    sprites.xml             → SpriteLibrary
    resources/
        polygonSet/         → referenced polygon XML files
        openCurveSet/       → referenced curve XML files
        brushes/            → brush images
        stencils/           → stencil images
        images/             → background images
```

### 5.2 Loading Sequence

```scala
object ProjectConfigManager {
  def initialize(): Unit
  def loadProject(projectName: String): ProjectConfig
  def reloadProject(): Unit
  def currentProject: ProjectConfig
}
```

`loadProject()` calls each loader in order:

```
GlobalConfigLoader.load(global.xml)
ShapeConfigLoader.load(shapes.xml)
PolygonConfigLoader.load(polygons.xml)
OpenCurveSetLoader.load(curves.xml)
PointSetLoader.load(points.xml)
OvalSetLoader.load(ovals.xml)
SubdivisionConfigLoader.load(subdivision.xml)
RenderingConfigLoader.load(rendering.xml)
SpriteConfigLoader.load(sprites.xml)
```

Each loader is independent — failure in one does not prevent the others from loading. The resulting `ProjectConfig` bundles all nine loaded structures.

### 5.3 ProjectConfig

```scala
class ProjectConfig(
  val globalConfig: GlobalConfig,
  val shapeLibrary: ShapeLibrary,
  val polygonSetCollection: PolygonSetCollection,
  val openCurveSetCollection: OpenCurveSetCollection,
  val pointSetCollection: PointSetCollection,
  val ovalSetCollection: OvalSetCollection,
  val subdivisionParamsSetCollection: SubdivisionParamsSetCollection,
  val rendererSetLibrary: RendererSetLibrary,
  val spriteLibrary: SpriteLibrary
)
```

### 5.4 Hot Reload

`reloadProject()` re-reads all nine XML files and replaces `currentProject`. This is triggered from `DrawManager.reload()` in response to the `.reload` sentinel file (see §8).

---

## 6. Application Scaffold

The scaffold is the runtime harness: window management, animation loop, input handling, and capture. It lives in `org.loom.scaffold`.

### 6.1 Main

**File:** `src/main/scala/org/loom/scaffold/Main.scala`

`Main` is the application entry point. It supports three launch modes:

| Flag | Behaviour |
|------|-----------|
| *(none)* | Shows `ProjectSelector` GUI dialog; user picks a project by name; loads via `ProjectConfigManager` |
| `--cli <sketchName> <configName>` | Legacy mode: loads `Config` from `sketches/<sketch>/config/<config>.xml` directly |
| `--project <name>` | Headless project load via `ProjectConfigManager.loadProject()` |
| `--bake-subdivision <args>` | Offline subdivision baking: processes a polygon set and exits |

After loading, all paths converge on:

```scala
applyGlobalConfigToLegacy(globalConfig: GlobalConfig): Unit
// Copies all GlobalConfig fields into the Config singleton
// Hardcodes serial = false (serial comms not supported in modern path)
```

Then creates a `DrawFrame`, which chains `DrawPanel → DrawManager → MySketch`.

Window lifecycle uses a `CountDownLatch` to keep the main thread alive until the `JFrame` window is closed.

### 6.2 DrawFrame

**File:** `src/main/scala/org/loom/scaffold/DrawFrame.scala`

A `JFrame` wrapper. Reads directly from `Config.*`.

**Windowed mode:** Sets initial size to `Config.width × (Config.height + 16)`. The `+ 16` is a hardcoded approximation of the title bar height — platform-specific and unreliable.

**Fullscreen mode:** Uses `JFrame.MAXIMIZED_BOTH` rather than exclusive fullscreen (avoids window-manager conflicts on macOS). The canvas is centered on a `Config.borderColor` background.

There is no window position or size persistence between sessions.

### 6.3 DrawPanel

**File:** `src/main/scala/org/loom/scaffold/DrawPanel.scala`

A `JPanel` that owns the draw loop, input handling, and the sentinel watcher.

**Key members:**

| Member | Type | Role |
|--------|------|------|
| `drawManager` | `DrawManager` | Drives sketch update/draw |
| `interactionManager` | `InteractionManager` | Routes keyboard/mouse to sketch |
| `Animate` | `AnimationRunnable` | Animation thread |
| `sentinelTimer` | `javax.swing.Timer` | Polls for sentinel files every 500 ms |
| `dBuffer` | `BufferedImage` | Off-screen double buffer |

**Double buffering:** All rendering goes to `dBuffer` (TYPE_INT_ARGB). `paintComponent()` scales the buffer to the panel size while maintaining aspect ratio with letterboxing.

**Render path resolution:** When capturing, the output directory is determined by:
1. Read `.render_path` file from project directory (custom path override).
2. Fall back to `<projectDir>/renders`.
3. Fall back to `sketches/<sketchName>/captures`.

### 6.4 DrawManager

**File:** `src/main/scala/org/loom/scaffold/DrawManager.scala`

Coordinates the sketch update/draw cycle:

```scala
def update(): Unit   // calls sketch.update() if Config.animating
def draw(g: Graphics): Unit  // renders sketch to buffer
def reload(): Unit   // full reload: re-parse XML, rebuild sketch, call setup()
```

`reload()` sequence:
1. `ProjectConfigManager.reloadProject()`
2. `Main.applyGlobalConfigToLegacy()`
3. `new MySketch(width, height)` — fresh sketch instance
4. `sketch.setup()`
5. `sketch.setupBackgroundImage()`

### 6.5 AnimationRunnable

**File:** `src/main/scala/org/loom/scaffold/AnimationRunnable.scala`

A `Runnable` that drives the animation loop:

```scala
run(): Unit
  loop:
    Thread.sleep(100)    // ≈10 FPS — hardcoded
    if not paused:
      drawManager.update()
    drawPanel.repaint()
```

`sleep(100)` gives approximately 10 frames per second. This is hardcoded — there is no frame-rate configuration and no delta-time measurement.

Methods:

| Method | Effect |
|--------|--------|
| `startAnimationThread()` | Creates and starts a daemon `Thread` |
| `setPaused()` | Toggles `paused` flag |
| `kill()` | Sets a stop flag; thread exits on next iteration |

### 6.6 Sketch (Abstract Base)

**File:** `src/main/scala/org/loom/scaffold/Sketch.scala`

Abstract base for all drawing sketches. `MySketch` extends this.

**Fields:**

| Field | Default | Description |
|-------|---------|-------------|
| `paused` | `false` | Checked by animation thread |
| `backgroundColor` | transparent | Set from `Config.backgroundColor` |
| `overlayColor` | semi-black | Used for trail effects |
| `backgroundImage` | `null` | Loaded by `setupBackgroundImage()` |

**Methods for `MySketch` to override:**

```scala
def setup(): Unit                         // called once at start and on reload
def update(): Unit                        // called each frame if animating
def draw(g2D: Graphics2D): Unit           // called each frame
```

**Background helpers:**

```scala
def drawBackground(g2D: Graphics2D): Unit
  // fills with backgroundColor, or draws backgroundImage if loaded

def drawBackgroundOnce(g2D: Graphics2D): Unit
  // fills only on first call (for trail effects)

def drawOverlay(g2D: Graphics2D): Unit
  // semi-transparent fill with overlayColor (creates motion blur / trail)

def setupBackgroundImage(): Unit
  // loads image from Config.backgroundImagePath
  // resizes to width * qualityMultiple × height * qualityMultiple
  // bilinear interpolation; silent failure prints warning
```

---

## 7. Capture System

**File:** `src/main/scala/org/loom/scaffold/Capture.scala`

Handles both still frames and video (sequential frame) capture.

**Output paths:**

- Stills: `<renderBaseDir>/stills/<name>_<n>.png`
- Video frames: `<renderBaseDir>/animations/<name>_<n>.png`

Numbering continues from the highest existing file number in each directory.

**Quality scaling:** All pixel measurements are multiplied by `Config.qualityMultiple`. A still at `qualityMultiple = 2` on a 1080×1080 canvas produces a 2160×2160 PNG.

---

## 8. Sentinel File System

`DrawPanel`'s `sentinelTimer` polls for the existence of special files in the project directory every 500 ms. This allows external processes (scripts, the parameter editor) to control the running sketch without a GUI connection.

| File | Effect |
|------|--------|
| `.reload` | Re-read all XML config files and reinitialise sketch; file is then deleted |
| `.capture_still` | Save one frame to stills directory; file deleted |
| `.capture_video` | Toggle continuous frame-saving to animations directory; file deleted |
| `.pause` | Animation paused while file exists; resume when file is deleted |

The `.pause` sentinel is the only one checked by presence rather than creation. It is not deleted; removing the file resumes animation.

---

## 9. Design Assessment

### C1 — Legacy Config singleton blocks testability and parallelism

Every part of the scaffold reads `Config.*` directly. There is no dependency injection. Unit-testing any scaffold component requires either a real config file on disk or direct mutation of the singleton. The `applyGlobalConfigToLegacy()` bridge will be needed as long as the old scaffold exists.

**Swift:** Inject a `Configuration` value type at construction time. No singleton.

---

### C2 — Hardcoded frame rate (10 FPS)

`Thread.sleep(100)` in `AnimationRunnable` fixes the frame rate at approximately 10 FPS. This is not configurable per sketch, is not compensated for actual rendering time, and produces no delta-time value. Slower machines will render at less than 10 FPS with no detection.

**Swift:** Use a `CADisplayLink` or `Timer` with measured elapsed time; pass `deltaTime` to `update()`.

---

### C3 — No validation of any configuration values

Color values, canvas dimensions, probability ranges, and polygon counts are accepted verbatim. A canvas width of `-1` or a probability of `200` will be accepted silently. The modern loaders provide type safety but not range checking.

---

### C4 — Config.borderColor uses a legacy color format

The legacy format uses a comma-separated string (`"0,0,0"`) with no alpha; the modern format uses four separate XML attributes. Any tooling that reads `Config.borderColor` is incompatible with `GlobalConfig.borderColor` without the bridge function.

---

### C5 — DrawFrame title bar offset is platform-specific

`Config.height + 16` assumes 16 pixels for the title bar. This is incorrect on most platforms and on HiDPI displays. The JFrame `MAXIMIZED_BOTH` approach works acceptably for fullscreen but the windowed offset should use `getInsets()` after pack/show.

---

### C6 — No window state persistence

Window size and position are not saved between sessions. Each launch resets to the configured canvas dimensions.

---

### C7 — Animation hardcoded to ≈10 FPS with no delta-time

See C2. Additionally, `AnimationRunnable` sleeps a fixed 100 ms before checking whether rendering is done — there is no frame timing. On a machine that renders in 5 ms, 95 ms per frame is wasted. On a machine that renders in 120 ms, frames are dropped silently.

---

## 10. Runtime Assembly: ProjectConfig → Scene

**File:** `src/main/scala/org/loom/mysketch/MySketch.scala`

This section documents the most migration-critical process: how the loaded `ProjectConfig` structures (specs 05–06) are converted into a running `Scene` full of `Sprite2D` objects (specs 02–04). This is the seam between configuration and runtime.

### 10.1 Config-First Pattern

Every loading step in `MySketch` tries the XML config first, then falls back to hard-coded defaults:

```scala
if (useProjectConfig) {
  // load from ProjectConfigManager
} else {
  // hard-coded fallback (e.g., "BlueOrangeGreenFilled" renderer, "sixSix" polygon set)
}
```

`useProjectConfig` is `true` when `ProjectConfigManager.isProjectLoaded` — i.e., when launched via `--project` or the GUI selector.

### 10.2 Assembly Sequence

The following steps execute in order during `MySketch` construction:

**Step 1 — Load RendererSetLibrary**
```scala
val renderSetLibrary = makeRendererSetLibrary("renderSetLibrary")
```
Loads from `ProjectConfigManager.getRenderingConfig()` or builds a hard-coded renderer. All renderer sets and their dynamic parameter configurations are available here.

**Step 2 — Load Geometry Collections**
```scala
val polyCollection      = loadPolygonCollection()
val openCurveSetColl    = loadOpenCurveCollection()
val pointSetCollection  = loadPointCollection()
val ovalSetCollection   = loadOvalCollection()
```
Loads all four geometry collections from their respective XML files. These are pools of named `PolygonSet` objects; shapes reference them by name.

**Step 3 — Load Subdivision Parameters**
```scala
val subdivisionParamsSetCollection = createSubdivisionParamsSetCollection()
```
Loads from `subdivision.xml`. All named `SubdivisionParamsSet` objects are available here.

**Step 4 — Create Shape2D Objects**
```scala
val shapes2D: ListBuffer[Shape2D] = make2DShapes()
```
Iterates over every `ShapeDef` in the loaded `ShapeLibrary`. For each:
- Retrieves the appropriate polygon list from the relevant collection based on `ShapeDef.sourceType` (`POLYGON_SET`, `REGULAR_POLYGON`, `INLINE_POINTS`, `OPEN_CURVE_SET`, `POINT_SET`, `OVAL_SET`)
- Looks up the `SubdivisionParamsSet` by name (may be `null`)
- Creates `Shape2D(polygons, subdivisionParamsSet)`

Builds a `shapeNameMap: Map[(shapeSetName, shapeName), Int]` that maps each shape's identity to its index in `shapes2D`. Sprites later look up their shape by this key.

**Step 5 — Preprocess Shape Orientation**
```scala
standShapesUpright()        // rotate all polygons 180°
reverseShapesHorizontally() // flip all points: x *= -1
```
Corrects for the coordinate system difference between the Bezier editor (Y-up, right-hand) and the Loom renderer. Applied to all shapes before subdivision.

**Step 6 — Apply Recursive Subdivision**
```scala
val subdividedShapes: List[AbstractShape] = makeRecursiveShapes(subdividing)
```
For each `Shape2D` that has a non-null `subdivisionParamsSet` and `subdividing == true`:
- Calls `shape.recursiveSubdivide(subdivisionParamsSet.toList())`
- Each pass applies one `SubdivisionParams`, filters invisible polygons, feeds into next pass
- Result is a new `Shape2D` with final render geometry

Shapes without subdivision params are included unchanged.

**Step 7 — Create Sprite2D Objects**
```scala
val sprite2DList: List[Sprite2D] = make2DSpriteList()
```
Iterates over every `SpriteDef` in the loaded `SpriteLibrary`. For each:

1. Look up shape index: `shapeNameMap((spriteDef.shapeSetName, spriteDef.shapeName))`
2. Clone the subdivided shape at that index — each sprite must own a mutable copy
3. Look up renderer set: `renderSetLibrary.getRendererSet(spriteDef.rendererSetName)`
4. Build `Sprite2DParams` from position, scale, rotation in `SpriteDef`
5. Build the animator based on `spriteDef.animatorType`:
   - `ANIMATOR2D`: `Animator2D` with random scale/rotation/speed ranges from config; jitter flag set
   - `KEYFRAME`: `KeyframeAnimator` with keyframes sorted by `drawCycle`, loop mode applied
   - `JITTER_MORPH` / `KEYFRAME_MORPH`: loads morph target files from disk, builds `MorphTarget` snapshots, creates `JitterMorphAnimator` or `KeyframeMorphAnimator`
6. Create `Sprite2D(clonedShape, spriteParams, animator, rendererSet)`
7. Set `sprite.spriteTotalDraws` from config (0 = draw indefinitely)

**Step 8 — Assemble Scene**
```scala
val view = View(width * Config.qualityMultiple, height * Config.qualityMultiple, ...)
val scene = Scene()
Camera.view = view
Camera.viewAngle = Config.cameraViewAngle
for (sprite <- sprite2DList) scene.addSprite(sprite)
```
`View` and `Camera` are set as globals. All sprites are added in `SpriteLibrary` order, which determines z-draw order.

### 10.3 Name Resolution Chain

All connections between loaded structures are name-based, resolved at assembly time:

```
SpriteLibrary  ──(shapeSetName, shapeName)──▶  shapes2D index
SpriteLibrary  ──(rendererSetName)──────────▶  RendererSetLibrary
ShapeLibrary   ──(polygonSetName)───────────▶  PolygonSetCollection
ShapeLibrary   ──(subdivParamsSetName)──────▶  SubdivisionParamsSetCollection
MorphTargetRef ──(file path)────────────────▶  disk XML file
```

If any name lookup fails, the sprite or shape is silently skipped or assigned a null. There is no error reporting for unresolved references.

### 10.4 Lifecycle After Assembly

```scala
def setup(): Unit
  // Initialises BrushLibrary and StencilLibrary from project resource paths
  // Sets backgroundColor and overlayColor from GlobalConfig
  // Calls renderer.scalePixelValues(qualityMultiple) if qualityMultiple > 1

def update(): Unit
  // Each frame: scene.update() → sprite.update() → animator.update(sprite)

def draw(g2D: Graphics2D): Unit
  // Each frame: drawBackground(); scene.draw(g2D)
  // Respects totalDraws limit; prints "drawing done" when limit reached
```

### 10.5 Swift Migration Notes

| Concern | Scala approach | Swift approach |
|---------|---------------|----------------|
| Shape container | `Shape2D` wraps `List[Polygon2D]` | Sprite holds `[Polygon2D]` directly |
| Name resolution | String maps, silent null on miss | `Dictionary` lookups with explicit error handling |
| Orientation correction | Two hard-coded pre-subdivision transforms | Specify coordinate convention in the format; no silent correction |
| Mutable clone per sprite | Manual deep clone before each sprite | Value-type polygons copy automatically |
| Morph target loading | Lazy disk load at animator build time | Preload all resources; no disk reads during assembly |
| Global Camera/View | Singleton mutation | Pass `Camera` and `View` as parameters to `Scene` or `Renderer` |

---

## 11. Swift Migration Notes

| Concern | Scala approach | Recommended Swift approach |
|---------|---------------|--------------------------|
| Configuration | Global singleton + file | `struct AppConfig` injected at construction |
| Frame timing | `Thread.sleep(100)` | `CADisplayLink` with `deltaTime` |
| Hot reload | Sentinel file polling | `FSEvents` / `DispatchSource` file watcher |
| Capture | Sequential PNG files | `AVAssetWriter` for video; `CGImageDestination` for stills |
| Window layout | Hardcoded offsets | `NSWindowController` with autosave |
| Config format | Two XML formats (legacy + modern) | Single `Codable` struct; JSON or property list |
