# Loom Engine — Swift Migration Plan
**Specification 08**  
**Date:** 2026-04-19  
**Depends on:** All previous specs (01–07)

---

## 1. Goals and Constraints

**Goals:**
- Full functional parity with the Scala engine (all 19 subdivision algorithms, all 6 rendering modes, all animator types, video export)
- macOS 14+ and iOS 17+ from a single codebase
- Proper delta-time-based frame loop: all animation is frame-rate independent
- First-class video export via `AVAssetWriter`
- Each phase independently testable before the next begins

**Non-goals (deferred):**
- Serial communication (Phase 10, low priority)
- Replacing the Python parameter editor (future consideration)
- SwiftUI parameter editor (future consideration)

**Constraints:**
- The Python Loom Editor (bezier_py) continues producing polygon XML files — the Swift engine must read the existing `.loom_projects` format
- Minimum targets: macOS 14 (Sonoma), iOS 17 — required for `CADisplayLink` parity

---

## 2. Architecture

### 2.1 Two-Layer Structure

```
┌──────────────────────────────────────────────────────┐
│  Swift Package: LoomEngine                           │
│  Imports: Foundation · CoreGraphics · AVFoundation   │
│  No AppKit · No UIKit · No SwiftUI                   │
│                                                      │
│  Compiles unchanged for macOS, iOS, iPadOS           │
└──────────────────────────────────────────────────────┘
                      ↑ used by
┌──────────────────────────────────────────────────────┐
│  SwiftUI App (single target, macOS + iOS)            │
│  Imports: SwiftUI · AppKit (macOS) · UIKit (iOS)     │
│                                                      │
│  Thin render surface · Project UI · Export UI        │
│  #if os(macOS) only for file panels + key shortcuts  │
└──────────────────────────────────────────────────────┘
```

### 2.2 Package Source Layout

```
LoomEngine/                         (Swift Package root)
  Package.swift
  Sources/
    LoomEngine/
      Geometry/
        Vector2D.swift
        Vector3D.swift
        PolygonType.swift
        Polygon2D.swift
        Polygon3D.swift
        ViewTransform.swift         (world → screen mapping)
      Subdivision/
        SubdivisionType.swift       (enum, 19 cases)
        VisibilityRule.swift        (enum, 15 cases)
        SubdivisionParams.swift
        SubdivisionEngine.swift     (pure functions)
        TransformPlugins/
          ExteriorAnchors.swift
          CentralAnchors.swift
          AnchorsLinkedToCentre.swift
          InnerControlPoints.swift
          OuterControlPoints.swift
      Rendering/
        RendererMode.swift          (enum, 6 cases)
        Renderer.swift
        RendererSet.swift
        RendererSetLibrary.swift
        RenderTransform.swift
        RenderEngine.swift          (CGContext drawing)
        BrushEngine.swift           (Phase 10)
        StencilEngine.swift         (Phase 10)
      Animation/
        Animator.swift              (protocol)
        Animator2D.swift
        KeyframeAnimator.swift
        MorphTarget.swift
        JitterMorphAnimator.swift
        KeyframeMorphAnimator.swift
        Easing.swift
      Scene/
        Sprite.swift
        Scene.swift
        Camera.swift
      Config/
        ProjectConfig.swift
        GlobalConfig.swift
        ShapeConfig.swift
        PolygonSetConfig.swift
        SubdivisionConfig.swift
        RenderingConfig.swift
        SpriteConfig.swift
        OpenCurveConfig.swift
        PointConfig.swift
        OvalConfig.swift
      Loaders/
        ProjectLoader.swift         (orchestrates all loaders)
        XMLPolygonLoader.swift      (reads Bezier editor format)
        XMLConfigLoader.swift       (reads existing project XML)
        JSONConfigLoader.swift      (reads/writes new JSON format)
        RegularPolygonGenerator.swift
      Assembly/
        SceneAssembler.swift
      Engine/
        Engine.swift
        FrameLoop.swift             (protocol)
        DisplayLinkFrameLoop.swift
        ExportFrameLoop.swift
      Export/
        VideoExporter.swift
        StillExporter.swift
  Tests/
    LoomEngineTests/
      GeometryTests.swift
      SubdivisionTests.swift
      ConfigLoaderTests.swift
      RenderingTests.swift
      AnimationTests.swift
      AssemblyTests.swift
      FrameLoopTests.swift
      ExportTests.swift

LoomApp/                            (Xcode project, macOS + iOS target)
  App.swift
  Views/
    ContentView.swift
    RenderSurfaceView.swift
    ProjectSelectorView.swift
    ExportSheet.swift
  Platform/
    RenderSurface+macOS.swift       (NSViewRepresentable)
    RenderSurface+iOS.swift         (UIViewRepresentable)
    FileAccess.swift                (#if os(macOS) panels vs .fileImporter)
```

### 2.3 Key Design Decisions

**Value types throughout the engine:**  
`Vector2D`, `Polygon2D`, `Sprite`, `SubdivisionParams`, `Renderer` are all `struct`. Mutation returns a new value. No shared mutable state in the engine layer.

**Sprite holds polygons directly:**  
No `Shape2D` wrapper. `Sprite.polygons: [Polygon2D]`. The `Shape2D.recursiveSubdivide()` logic becomes `SubdivisionEngine.recursiveSubdivide(_ polygons: [Polygon2D], paramSet: [SubdivisionParams]) -> [Polygon2D]`.

**Animation is a pure transform:**  
```swift
protocol Animator {
    func advance(_ sprite: Sprite, deltaTime: Double) -> Sprite
}
```
No mutation of sprite state in-place. Each frame produces a new `Sprite` value.

**Rendering is a pure function:**  
```swift
func draw(_ polygons: [Polygon2D], renderer: Renderer, 
          into context: CGContext, transform: ViewTransform)
```
No side effects outside the `CGContext`.

**Delta-time everywhere:**  
`Engine.update(deltaTime: Double)` is the single entry point for all animation advancement. `RenderTransform` (renderer parameter animation) also advances by `deltaTime`, not frame count.

**Coordinate convention:**  
Y-up, origin at canvas centre. No silent orientation correction at load time (unlike the Scala engine's `standShapesUpright` / `reverseShapesHorizontally`). The Bezier editor polygon files will be loaded with a one-time normalisation matrix applied in `XMLPolygonLoader`.

---

## 3. Relationship to Existing Tools

```
bezier_py (Python)              →  produces polygonSet XML files
loom_parameter_editor (Python)  →  produces project XML files
                                      ↓
                            Swift LoomEngine reads both
                            (XMLConfigLoader, XMLPolygonLoader)
                                      ↓
                            Optionally writes back as JSON
                            (JSONConfigLoader)
```

The Python tools continue unchanged. `XMLConfigLoader` must handle all quirks documented in spec 06: DTD suppression, three color formats, preserved typos (`CpsSqueezeFacto`, `polysTranformWhole`).

---

## 4. Phase Plan

---

### Phase 1 — Core geometry
**Deliverable:** `Vector2D`, `Vector3D`, `Polygon2D`, `Polygon3D`, `PolygonType`, `ViewTransform`  
**Tests:** `GeometryTests.swift`

**Design:**

```swift
struct Vector2D: Equatable {
    var x: Double
    var y: Double
    
    func translated(by v: Vector2D) -> Vector2D
    func scaled(by v: Vector2D) -> Vector2D
    func rotated(by angle: Double) -> Vector2D
    static func lerp(_ a: Vector2D, _ b: Vector2D, t: Double) -> Vector2D
}

enum PolygonType {
    case line, spline, openSpline, point, oval
}

struct Polygon2D: Equatable {
    var points: [Vector2D]
    var type: PolygonType
    var pressures: [Double]     // per-anchor pressure, 0.0–1.0
    var visible: Bool
    
    func translated(by v: Vector2D) -> Polygon2D
    func scaled(by v: Vector2D) -> Polygon2D
    func rotated(by angle: Double, around centre: Vector2D) -> Polygon2D
}

struct ViewTransform {
    var canvasSize: CGSize
    var offset: Vector2D
    
    func worldToScreen(_ v: Vector2D) -> CGPoint
}
```

**Spline point encoding** (must match Scala exactly):  
Groups of 4: `[anchor, controlOut, controlIn, anchor]`. `Polygon2D.points.count` is always a multiple of 4 for `.spline` type.

**Tests cover:**
- Translate/scale/rotate round-trips
- `lerp` at t=0, 0.5, 1.0
- `ViewTransform.worldToScreen` at canvas centre and corners
- Polygon value-copy semantics (mutating a copy does not affect original)

---

### Phase 2 — Subdivision engine
**Deliverable:** `SubdivisionType`, `VisibilityRule`, `SubdivisionParams`, `SubdivisionEngine`, all 5 transform plugins  
**Tests:** `SubdivisionTests.swift`  
**Depends on:** Phase 1

**Design:**

```swift
enum SubdivisionType: String, Codable {
    case quad, tri
    case quadEcho, triEcho
    case quadBord, triBord
    case quadBordEcho, triBordEcho
    case quadSplit, triSplit
    case echo, border, split
    // ... all 19 cases
}

struct SubdivisionParams: Codable {
    var type: SubdivisionType
    var visibilityRule: VisibilityRule
    var lineRatios: Vector2D
    var controlPointRatios: Vector2D
    var ranMiddle: Bool
    var ranDiv: Double
    var continuous: Bool
    var polysTransform: Bool
    var polysTransformPoints: Bool
    var polysTransformWhole: Bool
    var transformSet: TransformSet
    // ... PTW fields
}

enum SubdivisionEngine {
    static func subdivide(
        _ polygons: [Polygon2D], 
        params: SubdivisionParams
    ) -> [Polygon2D]
    
    static func recursiveSubdivide(
        _ polygons: [Polygon2D],
        paramSet: [SubdivisionParams]
    ) -> [Polygon2D]
}
```

**Bypass logic** (must match Scala):  
`.openSpline`, `.point`, `.oval` polygons pass through every subdivision pass unchanged. Visibility filtering is applied between passes.

**Tests cover:**
- Known triangle input → QUAD → expected polygon count (4×)
- Known triangle input → TRI → expected polygon count (3×)
- Multi-pass recursive: N passes → N^k polygons (approximately)
- Visibility rule filtering reduces output correctly
- Bypass polygons survive multiple passes unchanged
- Transform plugins modify point positions in expected direction

**Cross-validation strategy:**  
Run the same params on the same input polygon set in both Scala and Swift. Export Scala output as JSON (one-time). Assert Swift output matches to within floating-point tolerance.

---

### Phase 3 — Configuration and serialization
**Deliverable:** All config structs, `ProjectLoader`, `XMLConfigLoader`, `XMLPolygonLoader`, `JSONConfigLoader`  
**Tests:** `ConfigLoaderTests.swift`  
**Depends on:** Phases 1–2

**Config structs** are all `Codable` with defaults matching spec 06.

**Two loading paths:**

`XMLConfigLoader` — reads existing `.loom_projects` format:
- All quirks from spec 06: DTD suppression, three color formats, typo spellings
- Produces the same `ProjectConfig` struct as the JSON loader
- Color format detection: try attribute form first, then comma-string, then key=value

`JSONConfigLoader` — reads/writes new format:
- `ProjectConfig` directly encodes/decodes via Swift `Codable`
- `ProjectLoader.save(config:to:)` writes JSON — enables editing workflow later

`XMLPolygonLoader` — reads Bezier editor polygon files:
- Applies normalisation matrix: rotate 180°, flip X (the `standShapesUpright` + `reverseShapesHorizontally` equivalent, done once at load time rather than as a runtime step)
- Handles `isClosed` → `.spline` vs `.openSpline`
- Applies `pressure` attribute to `Polygon2D.pressures` array

**Tests cover:**
- Load a real `.loom_projects` project; assert sprite count, subdivision type names, renderer mode values
- Load same project with XML loader and JSON loader after round-trip save; assert equality
- `XMLPolygonLoader`: load a known polygon file; assert point count and first point coordinates
- Color parsing: all three color formats produce identical `CGColor`

---

### Phase 4 — Rendering primitives
**Deliverable:** `RendererMode`, `Renderer`, `RendererSet`, `RendererSetLibrary`, `RenderEngine`  
**Tests:** `RenderingTests.swift`  
**Depends on:** Phases 1, 3

**Design:**

```swift
enum RendererMode: Int, Codable {
    case points = 0, stroked, filled, filledStroked, brushed, stenciled
}

struct Renderer: Codable {
    var name: String
    var mode: RendererMode
    var strokeWidth: CGFloat
    var strokeColor: CGColor
    var fillColor: CGColor
    var pointSize: CGFloat
    var holdLength: Int
}

enum RenderEngine {
    static func draw(
        _ polygons: [Polygon2D],
        renderer: Renderer,
        into context: CGContext,
        transform: ViewTransform
    )
}
```

**Bézier path construction** (matches Scala `drawLines`/`drawFilled`):

```swift
// For .spline polygons: groups of 4
let path = CGMutablePath()
path.move(to: transform.worldToScreen(points[0]))
stride(from: 0, to: points.count, by: 4).forEach { i in
    path.addCurve(
        to:       transform.worldToScreen(points[i+3]),
        control1: transform.worldToScreen(points[i+1]),
        control2: transform.worldToScreen(points[i+2])
    )
}
```

**Brush and stencil** (`RendererMode.brushed`, `.stenciled`) are deferred to Phase 10. `RenderEngine.draw` returns early for these modes in this phase — the API is in place, the implementation comes later.

**Tests cover:**
- Render a known triangle to off-screen `CGContext`; assert non-transparent pixels exist in expected region
- `RendererMode.points`: assert pixels at each polygon vertex location
- `RendererMode.filled`: assert pixel inside triangle is filled, pixel outside is not
- `RendererMode.stroked`: assert pixels along edges, not interior
- ViewTransform: canvas-centre polygon renders to image centre

---

### Phase 5 — Animation system
**Deliverable:** `Sprite`, `Animator` protocol, `Animator2D`, `KeyframeAnimator`, `MorphTarget`, `JitterMorphAnimator`, `KeyframeMorphAnimator`, `RenderTransform`, `Easing`  
**Tests:** `AnimationTests.swift`  
**Depends on:** Phases 1, 4

**Sprite struct:**

```swift
struct Sprite {
    var polygons: [Polygon2D]       // current frame geometry
    var rendererSetName: String     // resolved at render time
    var drawCount: Int
    var totalDraws: Int             // 0 = infinite
    // transform state (position accumulated by Animator2D)
}
```

**Animator protocol:**

```swift
protocol Animator {
    func advance(_ sprite: Sprite, deltaTime: Double) -> Sprite
}
```

**Animator2D** maps directly from spec 03:
- `jitter: Bool` — oscillate vs cumulate
- Jitter mode: apply inverse of last frame's transform, then apply new random transform
- Cumulative mode: apply transform additively each frame
- Random ranges scale by `deltaTime` so speed is fps-independent

**RenderTransform** advances renderer parameters by `deltaTime`:
- Replaces frame-count increments with time-based increments
- `increment` in config is now `unitsPerSecond` rather than `unitsPerFrame`
- All cycle/pause/palette logic preserved; time replaces frame counter

**Tests cover:**
- `Animator2D` cumulative: after N seconds at speed V, position ≈ V×N
- `Animator2D` jitter: position stays within random range bounds across 1000 frames
- `KeyframeAnimator`: at t=0 sprite is at kf[0] position; at t=duration sprite is at kf[last] position; midpoint uses easing
- `MorphTarget`: at morphAmount=0.0 polygon points match snapshot[0]; at 1.0 match snapshot[1]
- `RenderTransform` UP motion: strokeWidth increases from min to max over expected duration

---

### Phase 6 — Scene assembly
**Deliverable:** `Scene`, `Camera`, `SceneAssembler`  
**Tests:** `AssemblyTests.swift`  
**Depends on:** Phases 2–5

**Design:**

```swift
struct Scene {
    var sprites: [Sprite]
    var camera: Camera
}

struct Camera {
    var location: Vector3D
    var focalLength: Double
    var viewTransform: ViewTransform
}

enum SceneAssembler {
    static func assemble(
        from config: ProjectConfig,
        canvasSize: CGSize
    ) throws -> Scene
}
```

`SceneAssembler.assemble()` implements the 8-step pipeline from spec 05 §10:
1. Build renderer set library from config
2. Load all geometry collections
3. Load subdivision params
4. Build polygon lists per shape def (by `sourceType`)
5. Apply `XMLPolygonLoader` normalisation (already done at load time in Phase 3)
6. Apply `SubdivisionEngine.recursiveSubdivide()` to each shape
7. Build sprites from sprite defs (name resolution, clone, animator construction)
8. Construct `Scene` with ordered sprites and camera

**Name resolution errors** throw rather than silently returning nil:
```swift
enum AssemblyError: Error {
    case shapeNotFound(setName: String, shapeName: String)
    case rendererSetNotFound(String)
    case subdivisionParamsNotFound(String)
    case polygonSetNotFound(String)
}
```

**Tests cover:**
- Assemble from a known project config; assert sprite count matches sprites.xml
- Assert each sprite has the correct polygon count for its subdivision params
- Assert that a missing renderer set name throws `AssemblyError.rendererSetNotFound`
- Sprites are in SpriteLibrary order

---

### Phase 7 — Frame loop and timing
**Deliverable:** `Engine`, `FrameLoop` protocol, `DisplayLinkFrameLoop`, `ExportFrameLoop`  
**Tests:** `FrameLoopTests.swift`  
**Depends on:** Phases 4–6

**Design:**

```swift
protocol FrameLoop: AnyObject {
    func start(onTick: @escaping (_ deltaTime: Double) -> Void)
    func stop()
}

// Preview: CADisplayLink, deltaTime = actual elapsed time
final class DisplayLinkFrameLoop: FrameLoop { ... }

// Export: no display, deltaTime = 1.0 / targetFPS, runs as fast as possible
final class ExportFrameLoop: FrameLoop {
    let fps: Double
    // calls onTick synchronously in a loop
}

final class Engine {
    private(set) var scene: Scene
    var frameLoop: FrameLoop
    
    func update(deltaTime: Double)
    // Advances all sprite animators
    // Advances all RenderTransform parameter animations
    
    func draw(into context: CGContext, size: CGSize)
    // Resolves renderer sets; calls RenderEngine.draw for each sprite
}
```

`RenderTransform` animation converted from frame-count to time:
- Config values remain as-is in XML (backward compatible)
- Loader multiplies `increment` by `1.0/10.0` to convert from "per 10fps frame" to "per second"
- Or: add a `timeScale` parameter to config (cleaner, not backward compatible)

**Tests cover:**
- `ExportFrameLoop` at 30fps calls `onTick` exactly 30 times per simulated second
- `deltaTime` values from `ExportFrameLoop` sum to expected duration over N frames
- `Engine.update` called N times with `1/30` delta: sprite at expected position (cross-validates with Phase 5 animation tests)
- `Engine.draw` produces non-empty CGContext output

---

### Phase 8 — Still and video export
**Deliverable:** `StillExporter`, `VideoExporter`  
**Tests:** `ExportTests.swift`  
**Depends on:** Phase 7

**Still export:**

```swift
enum StillExporter {
    static func exportPNG(
        engine: Engine,
        size: CGSize,
        to url: URL
    ) throws
}
```

Renders one frame to an off-screen `CGContext` → `CGImage` → `CGImageDestination` (PNG). Equivalent to the current `Capture.captureStill()`.

**Video export:**

```swift
final class VideoExporter {
    struct Settings {
        var fps: Int              // e.g. 24, 25, 30, 60
        var duration: Double      // seconds
        var size: CGSize          // pixels (apply qualityMultiple before passing)
        var codec: AVVideoCodecType  // .h264, .hevc, .proRes4444
        var outputURL: URL
    }
    
    func export(
        engine: Engine,
        settings: Settings,
        progress: ((Double) -> Void)? = nil
    ) async throws
}
```

**Export loop:**

```swift
// Inside VideoExporter.export():
let exportLoop = ExportFrameLoop(fps: Double(settings.fps))
let totalFrames = Int(settings.duration * Double(settings.fps))
var frameIndex = 0

let adaptor = AVAssetWriterInputPixelBufferAdaptor(...)

exportLoop.start { [weak self] deltaTime in
    guard frameIndex < totalFrames else { exportLoop.stop(); return }
    
    engine.update(deltaTime: deltaTime)
    
    let pixelBuffer = adaptor.pixelBufferPool!.makePixelBuffer()
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), ...)!
    engine.draw(into: ctx, size: settings.size)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    
    let pts = CMTime(value: CMTimeValue(frameIndex), timescale: CMTimeScale(settings.fps))
    adaptor.append(pixelBuffer, withPresentationTime: pts)
    
    frameIndex += 1
    progress?(Double(frameIndex) / Double(totalFrames))
}

writer.finishWriting()
```

**Tests cover:**
- Export 30 frames at 30fps; assert output file exists and `AVAsset.duration` ≈ 1.0 second
- Export at 2× quality multiple; assert output dimensions are 2× input
- `StillExporter`: output PNG has correct dimensions and is non-empty
- `VideoExporter` progress callback: called once per frame, final value is 1.0

---

### Phase 9 — UI shell
**Deliverable:** `LoomApp` Xcode project, `RenderSurfaceView`, `ContentView`, `ExportSheet`  
**Depends on:** Phases 7–8

**RenderSurface** — the platform view wrapper:

```swift
// Platform/RenderSurface+macOS.swift
struct RenderSurfaceView: NSViewRepresentable {
    let engine: Engine
    func makeNSView(context: Context) -> RenderSurfaceNSView { ... }
    func updateNSView(_ view: RenderSurfaceNSView, context: Context) { }
}

// RenderSurfaceNSView: NSView
// - owns DisplayLinkFrameLoop
// - on each tick: engine.update(deltaTime), engine.draw(into: layer.context)
// - renders to CALayer for hardware-composited display

// Platform/RenderSurface+iOS.swift — identical with UIViewRepresentable / UIView
```

**SwiftUI app structure:**

```swift
@main struct LoomApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .commands { LoomCommands() }
        #endif
    }
}
```

**Platform-specific items** (`#if os(macOS)` only):
- `NSOpenPanel` for project directory selection (iOS uses `.fileImporter`)
- `NSMenuItem` keyboard shortcuts (iOS uses toolbar buttons)
- Window sizing

**Export sheet** (shared macOS + iOS):
- FPS picker (24 / 25 / 30 / 60)
- Duration field
- Quality multiple stepper (1× / 2× / 4×)
- Codec picker (H.264 / HEVC / ProRes)
- Progress view during export

**Sentinel file watcher** replaced with `DispatchSource.makeFileSystemObjectSource` watching the project directory. Same `.reload` / `.pause` semantics, no polling — event-driven.

---

### Phase 10 — Brush and stencil rendering
**Deliverable:** `BrushEngine`, `StencilEngine`, complete `RendererMode.brushed` and `.stenciled` paths  
**Depends on:** Phase 9

Deferred because:
1. Brush/stencil add significant rendering complexity with no dependency from other phases
2. Phase 4 `RenderEngine.draw` already returns early for these modes — the API is in place
3. Can be added without touching any other phase's code

**Implementation approach:**
- Replace the Scala string-key edge deduplication with `Set<EdgeKey>` where `EdgeKey` is `(min(i,j), max(i,j))` — O(n) with no string allocation (spec 04 §R5)
- Use `Core Image` (`CIFilter`) for Gaussian blur on brush images rather than software blur — GPU-accelerated, same visual result
- `BrushAgent` / `StencilAgent` state held per-renderer-name in `Sprite` (same pattern as Scala `brushStates` map)

---

### Phase 11 — Serial communication (low priority)
**Deliverable:** `SerialManager` using `ORSSerialPort` (third-party) or `IOKit` directly  
**Depends on:** Phase 9

macOS only (no serial hardware on iOS). Implement as an optional capability — the engine and app function fully without it.

---

## 5. Testing Strategy

### Fixtures from .loom_projects

Before Phase 3 begins, identify one representative project (the user will nominate this) as the primary test fixture. Tests that load a real project assert:
- Sprite count
- Polygon count per sprite (post-subdivision)
- First sprite's first polygon's first point coordinates (validates load + normalisation)
- Subdivision type of first shape

This fixture validates the full load → assemble → subdivide chain against known good output.

### Cross-validation with Scala

For subdivision specifically (Phase 2), run the same test inputs through both engines and compare output polygon point coordinates. Accept floating-point tolerance of 1e-6. Discard any input polygon set that produces known-incorrect output in the Scala engine (the bugs documented in specs 02–04 are reference points).

### Off-screen rendering tests

Phase 4 tests render to `CGContext(bitmapInfo:)` and sample specific pixels. These are not pixel-perfect snapshots (fragile) but spatial assertions: "pixel at canvas centre is non-transparent", "pixel outside bounding box of polygon is transparent".

### Video export validation

Phase 8 exports a 1-second sequence and loads it back with `AVAsset`. Assert:
- `AVAsset.duration` within 1 frame of target
- Output file size > 0
- First video track dimensions match requested size

---

## 6. Config Format Migration Path

```
Phase 3:    XMLConfigLoader reads existing .loom_projects XML
            JSONConfigLoader writes new format
            Both produce identical ProjectConfig struct

Phase 9:    App can open XML projects (existing) or JSON projects (new)
            "Save as..." writes JSON from any opened project
            XML reading remains for lifetime of Python editor compatibility

Future:     If Python parameter editor is replaced by Swift:
            Drop XMLConfigLoader; all projects in JSON
            Migration script: loom_convert_projects converts XML → JSON in batch
```

---

## 7. What's Needed to Start Phase 1

**Already confirmed:**
- Platform: macOS 14+ · iOS 17+
- Rendering: Core Graphics
- Display: CADisplayLink + CALayer
- Video: AVAssetWriter
- UI: SwiftUI
- Package structure: as §2.2

**Still needed before Phase 3 (config/serialization):**
- One representative `.loom_projects` project to use as the primary test fixture (user to nominate)

**No blockers for Phases 1–2.** Core geometry and the subdivision engine depend only on the specs, not on any real project data.

---

## 8. Long-Term Architectural Constraints

The following decisions are made with a three-stage roadmap in mind. They do not require extra work now but should prevent choices that foreclose later options.

### Stage 1 (current): Scala/Python legacy
The existing Scala engine + Python tools remain as a cross-platform (Mac/Windows/Linux) reference implementation under light maintenance. No new features. Not a migration target.

### Stage 2 (current migration): Swift engine + Python tools
Swift replaces Scala. Python tools (bezier_py, loom_parameter_editor) continue unchanged, communicating with the Swift engine via project XML files and sentinel files. This is the active development platform.

### Stage 3 (future): Unified Swift application
Python tools are absorbed into the Swift codebase as native SwiftUI interfaces. The file-based Python↔Swift protocol becomes internal API calls. Single application, modern GUI throughout.

### Constraints on the Swift Package

**Expose clean interfaces for what the Python tools currently provide.**  
Define protocols for `ShapeEditorDelegate` (what Bezier provides: polygon sets) and `ParameterEditorDelegate` (what the parameter editor provides: subdivision + rendering config). The Python tools satisfy these protocols via file I/O today. SwiftUI replacements will satisfy them directly. The engine does not need restructuring at that point.

**Do not hardcode the file-based protocol as permanent.**  
`XMLConfigLoader` and the sentinel file watcher are the current bridging mechanism. They become legacy-only when the Python tools are absorbed; they can be deprecated without touching anything else.

**XML is the interchange format; JSON is the internal Swift format.**  
XML stays as long as Python tools write it. Codable JSON for all Swift-native state. Watch for XML unwieldiness in large subdivision/rendering configs — the likeliest pressure point — but no format changes needed yet.

**GUI modernisation is a replacement, not a port.**  
When Bezier becomes a SwiftUI drawing canvas, it should be designed from scratch to SwiftUI idioms — not translated widget-for-widget from PySide6.

---

## 9. Spec Cross-Reference

| Phase | Primary specs | Key sections |
|-------|--------------|-------------|
| 1 | 04 §7 | Coordinate systems; ViewTransform |
| 2 | 02 | All subdivision algorithms; transform plugins; visibility rules |
| 3 | 05 §3–5, 06 | All XML schemas; lenient parsing; DTD workaround; color formats |
| 4 | 04 §3–9 | Renderer hierarchy; RenderEngine dispatch; spline encoding |
| 5 | 03 | All animator types; MorphTarget chain; RenderTransform |
| 6 | 05 §10 | Assembly pipeline; name resolution chain |
| 7 | 05 §6.5 | Frame loop; delta-time |
| 8 | — | Video export (new for Swift) |
| 9 | 05 §6–8, 07 | Scaffold; sentinel files; interaction |
| 10 | 04 §9 | Brush/stencil subsystems |
