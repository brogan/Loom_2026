# Loom Engine — Technical Overview
**Version:** 1.0  
**Date:** 2026-04-18  
**Scope:** Scala 3 implementation (current); intended to inform Swift migration

---

## 1. Purpose and Scope

This document is the first in a series of technical specifications for the Loom engine. It provides an architectural overview of the current Scala 3 implementation, identifies structural strengths and weaknesses, and establishes the vocabulary and component model for subsequent detailed specifications covering:

- Subdivision system
- Animation and sprite system
- Rendering pipeline
- Configuration and parameter loading
- I/O and media
- Scene and camera management

A migration assessment for Swift is included at the end.

---

## 2. Build and Infrastructure

**Language:** Scala 3.7.3  
**Build tool:** SBT  
**Runtime:** JVM (2 GB – 12 GB heap, G1GC, 32 MB regions)  

**Key dependencies:**

| Library | Version | Role |
|---------|---------|------|
| scala-swing | 3.0.0 | Display (JFrame / JPanel) |
| scala-xml | 2.2.0 | Configuration and shape loading |

No external geometry or graphics libraries are used. All rendering is through Java 2D (AWT Graphics2D).

The JVM is configured for large buffer allocations (up to ~277 MB for 8320×8320 @ quality ×8) with pre-touched heap pages and GCLocker retry logic for JNI critical sections.

**Compiler options:** `-Wunused:all`, `-deprecation`, `-feature`

---

## 3. Package Structure

```
org.loom
├── scaffold/     (10 files)  Application frame, rendering loop, lifecycle
├── geometry/     (29 files)  Coordinate primitives, polygons, shapes, subdivision dispatch
├── subdivide/    (20 files)  Concrete subdivision algorithm implementations
├── scene/        (20 files)  Sprites, renderers, animation, camera
├── transform/    ( 9 files)  Pluggable point-transform strategies
├── media/        (18 files)  XML loaders, image I/O, sound, text I/O
├── config/       ( 4 files)  Global and project configuration
├── interaction/  ( 6 files)  Keyboard, mouse, serial port input
├── utility/      (13 files)  Math helpers, ranges, colour palettes, easing
├── mysketch/     ( 1 file)   User sketch — concrete drawing implementation
├── ui/           ( 1 file)   Project selector dialog
└── tools/        ( 1 file)   CLI subdivision baking utility
```

Total: ~135 Scala source files.

---

## 4. Layered Architecture

The engine is organised in clear layers, each building on the one below:

```
┌─────────────────────────────────────────────────┐
│  MySketch (user drawing logic)                  │
├─────────────────────────────────────────────────┤
│  Scene / Sprite2D / Sprite3D                    │  Scene management
│  Animator2D / Animator3D / Camera               │
├─────────────────────────────────────────────────┤
│  Renderer / RendererSet / RendererSetLibrary    │  Rendering pipeline
│  RenderTransform                               │
├─────────────────────────────────────────────────┤
│  Subdivision / SubdivisionParams               │  Geometry processing
│  Transform plugins                             │
├─────────────────────────────────────────────────┤
│  Shape2D/3D / Polygon2D/3D / Vector2D/3D       │  Geometry primitives
│  PolygonSet / PolygonSetCollection             │
├─────────────────────────────────────────────────┤
│  XML Loaders / ImageWriter / SerialListener    │  I/O
├─────────────────────────────────────────────────┤
│  Sketch / DrawManager / DrawPanel / DrawFrame  │  Application scaffold
│  Config / GlobalConfig / ProjectConfigManager  │
└─────────────────────────────────────────────────┘
```

Data flows from the bottom (configuration and shapes loaded from disk), upward through geometry processing (subdivision) and scene assembly, before being rendered each frame top-to-bottom back through the rendering pipeline.

---

## 5. Geometry Layer

### 5.1 Coordinate Types

| Class | Dimensions | Mutability |
|-------|-----------|-----------|
| `Vector2D` | 2D (x, y) | Mutable — coordinates modified in-place by all transforms |
| `Vector3D` | 3D (x, y, z) + scale factors | Mutable |

`Vector2D` is used for three semantically distinct things — position, velocity, and scale — with no type-level distinction. This is a source of confusion and a candidate for Swift's type aliases or opaque types.

### 5.2 Polygon Types

```
PolygonType constants (Int — not enum):
  0 = LINE_POLYGON       — explicit points joined by straight lines
  1 = SPLINE_POLYGON     — closed cubic Bézier (4 points per segment)
  2 = OPEN_SPLINE_POLYGON — open cubic Bézier
```

`Polygon2D` holds a `List[Vector2D]` (immutable list reference, mutable contents) plus a `polyType` Int and a `visible` flag. Pressure data for stylus input is stored as `Option[Array[Float]]`.

`Polygon3D` mirrors Polygon2D in 3D. It performs shallow cloning by default — polygon lists are shallow-copied but point references are shared — which is a latent correctness risk when points are mutated.

### 5.3 Shape and Collection Types

`Shape2D` wraps a `List[Polygon2D]` with an associated `SubdivisionParamsSet`. It is the central unit of geometry: everything that gets subdivided and rendered is a Shape2D.

`PolygonSet` is a named `List[Polygon2D]` as loaded from XML. `PolygonSetCollection` is a mutable `ListBuffer[PolygonSet]` searched by name. The `ListBuffer.find()` lookup is O(n) — acceptable at small collection sizes but worth noting.

### 5.4 Mutability Model

All transforms (translate, scale, rotate) modify point coordinates in-place. Clone operations create deep copies of the point array but the polygon list is shallow. This mutation-heavy model is fast but complicates debugging and makes parallelisation difficult.

---

## 6. Subdivision System

### 6.1 Overview

Subdivision is the computational heart of Loom. A `Polygon2D` is recursively decomposed into finer polygons by applying a chosen algorithm at each generation. The result is a `List[Polygon2D]` that replaces the original.

### 6.2 Algorithm Dispatch

`SubdivisionParams` holds an integer `subdivisionType` constant. The dispatch happens in `Subdivision.subdivide()` via a `match` expression with 15+ cases:

```
QUAD          → SplineQuad
TRI           → SplineTri
QUAD_BORD     → SplineQuadBord
TRI_STAR      → SplineTriStar
ECHO          → SplineEcho
SPLIT_VERT    → SplineSplitVert
... (15+ total)
```

Each case maps to a separate class. This is clean and extensible but means adding a new algorithm requires changes in both the constants object and the dispatch match.

### 6.3 SubdivisionParams Structure

A single `SubdivisionParams` configures one level of subdivision:

- **Algorithm selection:** `subdivisionType`, `lineRatios`, `controlPointRatios`
- **Randomisation:** `ranMiddle`, `ranDiv` (random centre point offset)
- **Visibility rules:** `visibilityRule` (ALL, ALTERNATE, RANDOM_1_3, etc.)
- **Whole-polygon transforms:** `polysTranformWhole`, probability, `Transform2D`
- **Per-point transforms:** `polysTransformPoints`, `transformSet: ArrayBuffer[Transform]`
- **Continuity:** `continuous` (link adjacent midpoints across edges)

`SubdivisionParamsSet` is a named list of `SubdivisionParams` — one per subdivision generation. `SubdivisionParamsSetCollection` is the full library of sets for a sketch.

### 6.4 Transform Plugins

Five transform classes modify polygon points after subdivision:

| Class | Target points |
|-------|--------------|
| `ExteriorAnchors` | Outer corner points |
| `CentralAnchors` | Central anchor points |
| `AnchorsLinkedToCentre` | Anchors scaled relative to centre |
| `OuterControlPoints` | Outer Bézier control points |
| `InnerControlPoints` | Inner Bézier control points |

All transforms implement the same `transform(polys, centreIndex, subdivisionType, ...)` interface and modify their target array in-place. A probability field controls whether each polygon is transformed.

### 6.5 Design Notes

- `Subdivision.subdivide()` is stateless — a pure dispatch function.
- Algorithm classes are also stateless — they take inputs and return `List[Polygon2D]`.
- The mutation happens in the transform layer, not the algorithm layer. This is a good separation.
- The transform `ArrayBuffer` is iterated unconditionally; inactive transforms are gated by `t.transforming` inside the loop.

---

## 7. Rendering Pipeline

### 7.1 Renderer

A `Renderer` holds one complete set of drawing instructions:

| Field | Type | Role |
|-------|------|------|
| `mode` | Int | POINTS / STROKED / FILLED / FILLED_STROKED / BRUSHED / STENCILED |
| `strokeWidth` | Float | Line weight |
| `strokeColor` | Color | Line colour |
| `fillColor` | Color | Fill colour |
| `pointSize` | Float | Vertex dot size |
| `holdLength` | Int | Frames before switching to next renderer |
| `brushConfig` | BrushConfig | Texture stamp configuration (BRUSHED mode) |
| `stencilConfig` | StencilConfig | Image mask configuration (STENCILED mode) |
| `changeSet` | Array[RenderTransform] | Per-frame parameter animation |

Renderer modes as raw Int constants is the main code smell here; Scala 3 enums would improve safety and readability.

### 7.2 RenderTransform

`RenderTransform` animates a single renderer parameter over time. It is the engine of dynamic rendering behaviour.

**What it animates:** stroke width, stroke colour, fill colour, point size, opacity, alpha.

**How it animates:**

| Dimension | Values |
|-----------|--------|
| Kind | NUM_SEQ, NUM_RAN, SEQ (palette), RAN (palette random) |
| Motion | UP, DOWN, PING_PONG |
| Cycle | CONSTANT, ONCE, ONCE_REVERT, PAUSING, PAUSING_RANDOM |
| Scale | SPRITE (once per sprite), POLY (once per polygon), POINT (once per point) |

Each `RenderTransform` maintains stateful indices and direction flags that are updated on every call to `update()`. This state is what drives animated colour sequences, oscillating stroke widths, etc.

### 7.3 RendererSet and RendererSetLibrary

`RendererSet` holds a list of `Renderer` objects and a selection policy:

| Policy | Behaviour |
|--------|-----------|
| `staticRendering = true` | Always use the same renderer |
| `sequenceIndexChange = true` | Step through renderers in order |
| `randomIndexChange = true` | Pick a random renderer |
| `allRenderersActive = true` | Apply all renderers to every polygon |

`RendererSetLibrary` is a named collection of `RendererSet` objects, loaded from XML configuration. It supports a `scalePixelValuesForQuality(factor)` method that scales all stroke widths and point sizes when rendering at a quality multiple.

### 7.4 Sprite2D Rendering Dispatch

For each frame, `Sprite2D.draw(g2D)` iterates over `shape.polys` and dispatches each polygon to the appropriate rendering method based on `ren.mode`:

```
POINTS        → drawPoints()     — vertex dots
STROKED       → drawLines()      — polygon edges
FILLED        → drawFilled()     — filled polygon
FILLED_STROKED → drawFilledStroked() — both
BRUSHED       → drawBrushed()    — returns early (operates on all polys)
STENCILED     → drawStenciled()  — returns early (operates on all polys)
```

Within each drawing method, a coordinate transform step (`coordinateCorrect()`) applies the sprite's current location, size, and rotation before converting to AWT integer screen coordinates.

`RendererSet.updateRenderer(scale)` is called at the POLY level (after each polygon) and at the SPRITE level (after all polygons), advancing `RenderTransform` state accordingly.

---

## 8. Scene and Sprite Management

### 8.1 Scene

`Scene` is a `ListBuffer[Drawable]` with `draw()` and `update()` methods that iterate and delegate. It also provides bulk transform methods (`translate`, `scale`, `rotate`) that apply to all sprites simultaneously.

The `Drawable` trait is the common interface for `Sprite2D` and `Sprite3D`.

### 8.2 Sprite2D

```
Sprite2D
├── shape: Shape2D              — geometry (polygons + subdivision params)
├── spriteParams: Sprite2DParams — initial location, size, rotation
├── animator: SpriteAnimator    — per-frame movement strategy
├── rendererSet: RendererSet    — how to draw it
└── location, size: Vector2D    — current transform state
```

`Sprite2D.update()` delegates to `animator.update(this)`, which mutates `location`, `size`, and rotation in-place. `Sprite2D.draw()` uses the current transform state to position the polygon geometry on screen.

### 8.3 Animation System

`SpriteAnimator` is a trait with `update(sprite)` and `cloneAnimator()`.

`Animator2D` is the primary implementation. It applies translation, scaling, and rotation each frame. Two modes:

- **Cumulative (`jitter = false`):** Transforms accumulate frame to frame (sprite drifts/grows/rotates continuously)
- **Jitter (`jitter = true`):** Each frame undoes the previous frame's transform and applies a new random offset. The sprite oscillates around its home position rather than drifting.

Per-axis randomisation flags (`random.scale`, `random.rotation`, `random.speed`) can make each frame's transform value be drawn from a range rather than a fixed value.

`Animator3D` extends this for 3D sprites, adding camera interaction.

---

## 9. Application Scaffold and Rendering Loop

### 9.1 Component Responsibilities

| Class | Role |
|-------|------|
| `Main` | Entry point; selects mode (GUI / CLI / bake); connects components |
| `DrawFrame` | Swing JFrame; fullscreen management |
| `DrawPanel` | Swing JPanel; owns the double buffer; starts AnimationRunnable |
| `DrawManager` | Owns the `Sketch` instance; drives `update()` / `draw()` lifecycle |
| `AnimationRunnable` | Background thread; drives the frame loop |
| `Sketch` | Abstract base for all drawing sketches |
| `MySketch` | Concrete sketch; loads assets, builds scene, implements logic |

### 9.2 Frame Loop

```
AnimationRunnable.run()  [background thread, ~10 FPS]
│
├── drawPanel.animationUpdate()
│   └── DrawManager.update()
│       └── sketch.update()
│           └── scene.update()
│               └── sprite.update()  [for each sprite]
│                   └── animator.update(sprite)
│
├── drawPanel.animationRender()
│   └── DrawManager.draw()
│       └── sketch.draw()
│           └── scene.draw(g2D)
│               └── sprite.draw(g2D)  [for each sprite]
│                   ├── rendererSet.getRenderer()
│                   ├── for each polygon: dispatch to draw method
│                   └── rendererSet.updateRenderer()
│
└── drawPanel.repaint()  [schedules paintComponent on EDT]
    └── EDT: scale dBuffer → panel
```

**Frame rate:** Fixed at 10 FPS (`Thread.sleep(100)`). There is no delta-time calculation; all animation assumes a constant 100 ms tick. This is a significant limitation for smooth animation.

**Double buffer:** All rendering goes to a `BufferedImage dBuffer`. On repaint, the EDT scales `dBuffer` to the panel dimensions (supporting quality multiples).

### 9.3 Sentinel File Control

Every 500 ms a timer fires on the EDT and checks for control files in the project directory:

| File | Action |
|------|--------|
| `.reload` | Reload configuration, re-create sketch |
| `.pause` | Toggle animation pause |
| `.capture_still` | Save current buffer as image |
| `.capture_video` | Begin/end video frame capture |

This mechanism allows external tools (including the parameter editor) to control the engine without a direct inter-process API. It is pragmatic but carries up to 500 ms latency and is fragile under rapid repeated signals.

---

## 10. Configuration System

### 10.1 Dual Configuration Layer

The engine has two parallel configuration systems:

| System | Type | Status |
|--------|------|--------|
| `Config` object | Mutable global singleton | Legacy — still used throughout |
| `GlobalConfig` | Immutable case class | Modern — loaded from `global.xml` |

`Main.applyGlobalConfigToLegacy()` bridges them at startup by copying `GlobalConfig` fields into `Config`. This bridge is a temporary measure that introduces the risk of the two getting out of sync.

### 10.2 Configuration Pipeline

```
~/.loom_projects/MyProject/
├── global.xml                     → GlobalConfig (width, height, fps, quality, etc.)
├── config/subdivisions.xml        → SubdivisionParamsSetCollection
├── config/renderers.xml           → RendererSetLibrary
├── config/sprites.xml             → Sprite placement and assignment
└── polygonSets/*.xml              → PolygonSet geometry
         ↓
ProjectConfigManager.loadProject()
         ↓
MySketch.__init__()
   ├── loadPolygonCollection()      → PolygonSetCollection
   ├── makeRendererSetLibrary()     → RendererSetLibrary
   ├── createSubdivisionParamsSetCollection()
   ├── make2DShapes()               → List[Shape2D]
   └── populate Scene with Sprite2D
```

### 10.3 XML Loading Pattern

All loaders follow the same pattern:
1. Locate XML file relative to project path
2. Parse with `scala-xml`
3. Construct domain objects, assigning defaults for missing attributes
4. Return collection

Error handling is minimal — missing files throw, malformed values may silently produce defaults. There is no schema validation.

---

## 11. I/O Layer

### 11.1 Shape Loading

`PolygonSetLoader` reads polygon XML into `List[Polygon2D]`. It handles all three polygon types (line, spline, open spline) and 3D shapes.

Companion loaders cover: open curves, point sets, oval sets.

### 11.2 Output and Capture

`ImageWriter` writes `BufferedImage` to PNG or JPEG. `Capture` tracks frame counts and filenames for both still and video (sequential frame) capture.

Capture is triggered either via sentinel file or keyboard shortcut (Ctrl+S / Ctrl+V) handled by `KeyPressListener`.

### 11.3 Sound and Serial

`SoundManager` plays audio files. `SerialListener` reads bytes from a serial port (used for physical controller input, RFID, etc.).

---

## 12. Threading Model

Three threads are active at runtime:

| Thread | Responsibility |
|--------|---------------|
| Main / EDT | Swing event processing, repaint, sentinel timer |
| AnimationRunnable | Frame loop — update + render to dBuffer |
| SerialListener | Serial port byte reading (when enabled) |

### 12.1 Thread Safety Issues

**Critical:**

1. **dBuffer race condition:** `AnimationRunnable` writes to `dBuffer`; the EDT reads it in `paintComponent()`. There is no synchronisation. Under normal operation this is benign (the EDT only scales and blits), but it is formally a data race.

2. **Sketch reassignment during reload:** `DrawManager.reload()` re-instantiates `sketch` while `AnimationRunnable` may be mid-update. There is no fence or lock around the reassignment.

**Lower priority:**

3. **Config singleton writes:** `applyGlobalConfigToLegacy()` writes to `Config` fields at startup before the animation thread is running, so in practice this is safe — but it is not enforced.

4. **Serial data flow:** `SerialListener` calls `interactionManager.passToSprite()` from its own thread. If this modifies shared scene state directly, it is a data race. Whether it is safe depends on what `passToSprite()` does internally.

---

## 13. Code Quality Assessment

### 13.1 Strengths

- Clear layer separation with well-defined responsibilities
- Pluggable subdivision algorithms (easy to add new types)
- Pluggable renderers and render transforms (rich, composable animation)
- Pragmatic use of Scala — no over-engineered abstractions
- Good use of companion objects for constants and utilities

### 13.2 Weaknesses

**Magic number constants:**  
Polygon types, renderer modes, subdivision types, and rotation modes are all bare `Int` constants. Scala 3 enums would provide type safety and improved readability at no performance cost.

**Legacy Config singleton:**  
The `Config` global object coexists with the `GlobalConfig` case class. All new code should use `GlobalConfig`; the bridge should be eliminated.

**Null returns:**  
Several loader methods can return null (e.g. `RendererSet.getRenderer()`). All should return `Option[T]`.

**Print debugging:**  
~50 `println()` calls throughout the codebase. A logging framework (e.g. slf4j + logback) should replace these.

**Mutation in hot paths:**  
All per-frame geometry transforms mutate coordinates in-place. This is fast but precludes parallelisation and makes debugging difficult. An immutable geometry option (copy-on-write) would improve debuggability at the cost of allocation.

**Fixed 10 FPS frame cap:**  
`Thread.sleep(100)` gives a fixed 10 FPS with no delta-time compensation. This limits animation smoothness. A proper frame timer using `System.nanoTime()` with configurable target FPS would be a straightforward improvement.

**Sentinel file polling:**  
500 ms timer + `File.exists()` checks. Should use `java.nio.file.WatchService` for lower latency and less overhead.

**No input validation on XML:**  
Malformed coordinates or out-of-range parameter values can silently corrupt rendering. A validation pass after XML loading would improve robustness.

---

## 14. Swift Migration Assessment

### 14.1 What Maps Cleanly

| Scala concept | Swift equivalent | Effort |
|---------------|-----------------|--------|
| Case class | Codable struct | Low |
| Companion object | Static methods / enum namespace | Low |
| Pattern matching | switch with exhaustive cases | Low |
| Trait (single) | Protocol | Low |
| `Option[T]` | `Optional<T>` | Trivial |
| `ArrayBuffer[T]` | `[T]` (copy-on-write array) or `NSMutableArray` | Low |
| Animation thread | DispatchQueue / CADisplayLink | Low–Medium |

### 14.2 What Requires Significant Work

| Area | Challenge | Effort |
|------|-----------|--------|
| Java 2D rendering | Core Graphics or Metal backend | High |
| Swing UI (DrawFrame/DrawPanel) | SwiftUI Window + Canvas / CALayer | High |
| scala-xml parsing | Foundation XMLParser or Codable | Medium |
| In-place mutation model | Decision: struct (copy) vs class (reference) for Vector2D | Medium |
| Serial port | ORSSerialPort library | Medium |
| Capture / ImageWriter | Core Image / UIImage / PhotoKit | Medium |

### 14.3 Migration Risks

1. **Rendering fidelity:** Java 2D's polygon fill/stroke model may differ subtly from Core Graphics. Visual regression testing against reference renders will be essential.
2. **Floating-point behaviour:** JVM double vs Swift Double are both IEEE 754 but may produce different results for trigonometric subdivision at extreme parameter values. Keep reference outputs.
3. **Coordinate system:** Java 2D is top-left origin, y-down. Core Graphics is bottom-left, y-up (in some contexts). This must be resolved consistently.
4. **Performance target:** The current 10 FPS loop is forgiving. A Swift version targeting 60 FPS will expose any O(n²) subdivision or rendering paths that the slow loop currently hides.

### 14.4 Recommended Migration Approach

Rather than a big-bang rewrite, a phased approach by layer is lower risk:

1. **Phase 1 — Geometry and subdivision** (Swift package, no UI)  
   Translate Vector2D/3D, Polygon2D/3D, Shape2D/3D, and all subdivision algorithm classes. Validate output geometry against Scala reference output.

2. **Phase 2 — Rendering pipeline** (Swift + Core Graphics)  
   Implement Renderer, RendererSet, RenderTransform, and the Sprite2D draw dispatch using Core Graphics. Validate visually against Scala renders.

3. **Phase 3 — Scene and animation** (complete loop)  
   Scene, Sprite2D, Animator2D, and the frame loop via CADisplayLink. Confirm animation behaviour matches.

4. **Phase 4 — Configuration and I/O**  
   XML loaders (Codable or XMLParser), project management, image capture.

5. **Phase 5 — Application shell**  
   SwiftUI app, window management, project selector, keyboard/mouse input.

---

## 15. Subsequent Specification Areas

The following detailed specifications are planned, each covering one functional area in depth:

| Document | Working title |
|----------|--------------|
| `02_subdivision.md` | Subdivision system — algorithms, params, transforms |
| `03_rendering.md` | Rendering pipeline — Renderer, RendererSet, RenderTransform |
| `04_animation.md` | Animation system — Animator2D/3D, jitter model, 3D camera |
| `05_configuration.md` | Configuration and parameter loading — XML format, data model |
| `06_scene.md` | Scene, Sprite, and Shape management |
| `07_io_media.md` | I/O, image capture, video export, serial, sound |
| `08_scaffold.md` | Application scaffold, rendering loop, threading model |
