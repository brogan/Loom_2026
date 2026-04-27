# Loom Engine — Rendering System
**Specification 04**  
**Date:** 2026-04-15  
**Depends on:** `01_technical_overview.md`, `03_animation.md`

---

## 1. Purpose

This document specifies the rendering system — the mechanism by which Loom's geometric data is converted to screen pixels each frame. It covers:

- The three-level renderer hierarchy (`Renderer` → `RendererSet` → `RendererSetLibrary`)
- All six rendering modes and their dispatch logic
- `RenderTransform`: dynamic per-frame parameter animation
- `Sprite2D` and `Sprite3D` draw pipelines
- Coordinate systems and the `View` / `Camera` model
- `Scene` — the top-level container and render loop
- Brush and stencil stamping subsystems
- Design assessment and improvement recommendations

---

## 2. Conceptual Overview

Loom rendering is a **three-layer pipeline**:

```
1. WHAT to draw       — geometry (Shape2D, Polygon2D, Vector2D points)
2. HOW to draw it     — renderer configuration (Renderer, RendererSet)
3. HOW it changes     — parameter animation (RenderTransform)
```

Layer 1 is the product of the subdivision and animation systems. Layers 2 and 3 are the exclusive concern of this document.

The `RendererSetLibrary` is a global library of `RendererSet` objects. Each `RendererSet` holds one or more `Renderer` objects and applies a selection policy — static, sequential, random, or "all active". Each `Renderer` holds the styling state (stroke color, fill color, stroke width, point size, brush config) for one rendering style. Inside each `Renderer`, up to five `RenderTransform` objects continuously animate the renderer's parameters over time.

A `Sprite2D` holds a reference to a `RendererSet`. On every frame its `draw()` method asks the `RendererSet` which renderer to use for each polygon, dispatches to the appropriate low-level drawing routine, then tells the `RendererSet` to advance its parameter animation.

---

## 3. Renderer

**File:** `src/main/scala/org/loom/scene/Renderer.scala`

### 3.1 Constructor

```scala
class Renderer(
  val name: String,         // unique identifier
  var mode: Int,            // rendering mode constant (see §3.3)
  var strokeWidth: Float,
  var strokeColor: Color,   // java.awt.Color
  var fillColor: Color,
  var pointSize: Float,
  val holdLength: Int       // frames to hold this renderer before cycling to next
)
```

### 3.2 Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `brushConfig` | `BrushConfig` | Configuration for `BRUSHED` mode; `null` otherwise |
| `stencilConfig` | `StencilConfig` | Configuration for `STENCILED` mode; `null` otherwise |
| `changing` | `Boolean` | Whether any `RenderTransform` is active |
| `pointStroked` | `Boolean` | Render points as stroked ellipses |
| `pointFilled` | `Boolean` | Render points as filled ellipses |
| `changeSet` | `Array[RenderTransform]` (5) | One transform slot per change type (see §5) |

### 3.3 Rendering Modes

| Constant | Value | Description |
|----------|-------|-------------|
| `Renderer.POINTS` | 0 | Individual dots at every polygon vertex |
| `Renderer.STROKED` | 1 | Outlined geometry (stroke only) |
| `Renderer.FILLED` | 2 | Solid filled geometry |
| `Renderer.FILLED_STROKED` | 3 | Fill then stroke on top |
| `Renderer.BRUSHED` | 4 | Brush-stamp images along polygon edges |
| `Renderer.STENCILED` | 5 | Full-RGBA image stamps along polygon edges |

### 3.4 Dynamic Parameter Configuration

Callers configure which renderer parameters will animate at runtime by calling one of a family of `setChanging*` convenience methods. Each method configures a slot in `changeSet`:

```
changeSet(0)  →  STROKE_WIDTH changes
changeSet(1)  →  STROKE_COLOR changes
changeSet(2)  →  FILL_COLOR changes
changeSet(3)  →  POINT_SIZE changes
changeSet(4)  →  STENCIL_OPACITY changes
```

Methods:

| Method | Configures |
|--------|-----------|
| `setChangingStrokeWidth(params, min, max, increment, pauseMax)` | Numeric stroke width animation |
| `setChangingStrokeColor(params, min, max, increment, pauseMax, pauseChan, ...)` | Numeric RGBA stroke color animation |
| `setChangingFillColor(params, min, max, increment, pauseMax, pauseChan, ...)` | Numeric RGBA fill color animation |
| `setChangingStrokeColorPalette(params, palette, pauseMax)` | Palette-based stroke color selection |
| `setChangingFillColorPalette(params, palette, pauseMax)` | Palette-based fill color selection |
| `setChangingStrokeWidthPalette(params, palette, pauseMax)` | Palette-based stroke width selection |
| `setChangingPointSizePalette(params, palette, pauseMax)` | Palette-based point size selection |
| `setChangingPointSize(params, min, max, increment, pauseMax)` | Numeric point size animation |
| `setChangingStencilOpacity(params, min, max, increment, pauseMax)` | Numeric stencil opacity animation |

### 3.5 update()

```scala
def update(scale: Int): Unit
```

Called by `RendererSet.updateRenderer()` on every frame. If `changing` is true, iterates over `changeSet` and calls `renderTransform.update(changeType, scale)` for each active slot. The `scale` parameter (`SPRITE`, `POLY`, or `POINT`) lets each transform opt in or out depending on which update granularity it was configured for.

### 3.6 scalePixelValues()

```scala
def scalePixelValues(factor: Float): Unit
```

Multiplies `strokeWidth`, `pointSize`, and all palette float values by `factor`. Delegates to `brushConfig.scalePixelValues()` and `stencilConfig.scalePixelValues()` if present. Used to adapt pixel sizes for high-DPI or high-quality export.

### 3.7 Predefined Colors

`Renderer` companion object defines 17 named `Color` constants (BLACK, WHITE, GREY, YELLOW, ORANGE, RED, GREEN, CYAN, BLUE, PURPLE, MAGENTA, etc.) plus faint variants.

---

## 4. RendererSet

**File:** `src/main/scala/org/loom/scene/RendererSet.scala`

### 4.1 Constructor

```scala
class RendererSet(val name: String)
```

### 4.2 Key Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `rendererSet` | `ArrayBuffer[Renderer]` | empty | All renderers in this set |
| `currentRenderer` | `Renderer` | first added | The renderer returned by `getRenderer()` |
| `selectedIndex` | `Int` | 0 | Index of the currently selected renderer |
| `preferredRendererIndex` | `Int` | 0 | For random selection: preferred renderer |
| `preferredProbability` | `Double` | 0.0 | Probability (0–100) of selecting preferred renderer |
| `staticRendering` | `Boolean` | `true` | No renderer switching |
| `modifyInternalParameters` | `Boolean` | `false` | Allow `RenderTransform` updates |
| `frozen` | `Boolean` | `false` | Suspend parameter updates globally |
| `sequenceIndexChange` | `Boolean` | `false` | Cycle renderers in order |
| `randomIndexChange` | `Boolean` | `false` | Select renderers at random |
| `allRenderersActive` | `Boolean` | `false` | Use every renderer on every draw cycle |

### 4.3 Selection Policy

`getRenderer()` applies the following priority:

1. If only 1 renderer in the set → always return it.
2. If `staticRendering` → return `rendererSet(selectedIndex)`.
3. If `sequenceIndexChange` → advance index and return next renderer.
4. If `randomIndexChange` → call `getRandomRendererConsideringPreferredRenderer()`.
5. Otherwise → return `rendererSet(selectedIndex)`.

`getRandomRendererConsideringPreferredRenderer()` gives the preferred renderer an additional weighted chance using `Randomise.probabilityResult(preferredProbability)`.

### 4.4 Configuration Helpers

| Method | Effect |
|--------|--------|
| `modifyRenderers()` | Sets `modifyInternalParameters = true` |
| `sequenceRendererSet(preferred, prob)` | Sets sequential cycling; configures preferred/probability |
| `randomRendererSet(preferred, prob)` | Sets random selection; configures preferred/probability |
| `allRenderersMode()` | Sets `allRenderersActive = true` |

### 4.5 updateRenderer()

```scala
def updateRenderer(scale: Int): Unit
```

Called by `Sprite2D.draw()` at three points in the frame — `Renderer.SPRITE`, `Renderer.POLY`, and `Renderer.POINT` — passing the appropriate scale constant. Only executes if `!staticRendering && modifyInternalParameters && !frozen`. Delegates to `currentRenderer.update(scale)`.

---

## 5. RenderTransform

**File:** `src/main/scala/org/loom/scene/RenderTransform.scala`

`RenderTransform` is a `private` class — it is only accessible through `Renderer.changeSet`. It handles the continuous per-frame animation of a single renderer parameter (stroke width, fill color, etc.).

### 5.1 Change Kind

| Constant | Value | Behaviour |
|----------|-------|-----------|
| `NUM_SEQ` | 0 | Numeric value increments/decrements each frame |
| `NUM_RAN` | 1 | New random value picked each frame (or every N frames for colors) |
| `SEQ` | 2 | Palette index advances sequentially |
| `RAN` | 3 | Palette index chosen at random |

### 5.2 Motion Direction

| Constant | Value | Effect |
|----------|-------|--------|
| `UP` | 1 | Value moves from min toward max |
| `DOWN` | -1 | Value moves from max toward min |
| `PING_PONG` | 0 | Value bounces between min and max |

### 5.3 Cycle Mode

| Constant | Value | Effect |
|----------|-------|--------|
| `CONSTANT` | 0 | Runs indefinitely |
| `ONCE` | 1 | Stops after reaching the far limit |
| `ONCE_REVERT` | 2 | Returns to start value after reaching the far limit, then stops |
| `PAUSING` | 3 | Pauses at the limits for a fixed number of frames |
| `PAUSING_RANDOM` | 4 | Pause duration is randomised each cycle |

### 5.4 Pausing

For size parameters (`strokeWidth`, `pointSize`, `opacity`), pausing simply freezes the value for `pauseMax` frames.

For color parameters, pausing is richer. A *pause channel* (`pauseChan` — one of R, G, B, A) acts as the trigger. When that channel reaches its boundary, the renderer is set to a distinct *pause color* (`pauseColMin` / `pauseColMax`) for the pause duration, after which normal cycling resumes.

Additional color channel roles during pause:

| Role | Effect |
|------|--------|
| `EVAL` | Channel that triggers/controls pause timing |
| `FREE` | Channel that continues cycling regardless of pause |
| `TIED` | Channel that follows EVAL's pause timing |
| `FIXED` | Channel held at its `max` value during pause |
| `SWITCH` | Channel alternates between min and max |
| `RANDOM` | Channel takes random values during pause |

### 5.5 Palette-Based Changes

When `kind == SEQ` or `kind == RAN`, a pre-set array of discrete values (colors or float sizes) replaces the numeric min/max/increment model. Palette cycling respects the same `motion` and `cycle` semantics as numeric changes.

### 5.6 update() Execution Flow

```
RenderTransform.update(changeType, scale):
  if scale doesn't match configured scale → return early

  if pausing enabled:
    if currently paused:
      increment pauseCount
      apply pause color (color changes) or hold value (size changes)
      if pauseCount >= pauseMax → resume
    else:
      updateTransform()
  else:
    updateTransform()

updateTransform():
  dispatch by kind:
    NUM_SEQ → updateStrokeWidth() / updateStrokeColor() / updateFillColor() / updatePointSize() / updateOpacity()
    NUM_RAN → pick new random value immediately
    SEQ     → updateStrokeColorPalette() / updateFillColorPalette() / updateStrokeWidthPalette() / updatePointSizePalette()
    RAN     → pick random palette index
```

### 5.7 SizeValues Inner Class

```scala
private class SizeValues {
  var min, max, increment, half: Float
  var incrementCount, totalIncrements: Int
  var goingUp: Boolean
  
  def getSizeUp(size: Float): Float   // add increment, clamp at max
  def getSizeDown(size: Float): Float // subtract increment, clamp at min
  def checkPingPongEnd(): Unit        // toggle goingUp at boundary
  def setSizeValues(min, max, inc): Unit
  def scaleBy(factor: Float): Unit
}
```

### 5.8 ColorValues Inner Class

```scala
private class ColorValues {
  var min, max, increments: Array[Int]  // 4 elements (RGBA)
  val half: Array[Int]                  // computed midpoint per channel
  var goingUp: Boolean
  
  def getChanUp(chan: Int, dex: Int): Int   // increment channel value
  def getChanDown(chan: Int, dex: Int): Int // decrement channel value
  def setColorValues(min, max, inc): Unit
}
```

---

## 6. RendererSetLibrary

**File:** `src/main/scala/org/loom/scene/RendererSetLibrary.scala`

`RendererSetLibrary` is a thin container that mirrors the `RendererSet` API at one level of abstraction higher. It holds a collection of `RendererSet` objects and provides `add`, `remove`, `setCurrentRendererSet`, `getRendererSet`, `getRandomRendererSet`, `getNextRendererSet`, and `hasRendererSet` methods.

In practice it acts as a global palette of named renderer configurations. In `MySketch` implementations the library is typically constructed once at startup and individual sets are retrieved by name.

---

## 7. Coordinate Systems

Loom uses three distinct coordinate spaces:

### 7.1 World Space

The natural coordinate system of polygon geometry. Points are stored as `Vector2D` with the origin at the center of the conceptual canvas. Positive Y is up (mathematical convention).

### 7.2 View Space

A camera-adjusted space produced by `View.viewToScreenVertex()`. The camera can be translated and rotated in 3D; `Sprite3D` applies a perspective divide at this stage.

### 7.3 Screen Space

Pixel coordinates used by AWT/Java2D. Origin is top-left; Y increases downward. `coordinateCorrect()` in `Sprite2D` converts all polygon points from world to screen space immediately before drawing.

### 7.4 View Class

```scala
class View(var width: Int, var height: Int, var offset: Vector2D)
```

Provides `viewToScreenVertex(v: Vector2D): Vector2D` which maps from world to screen coordinates, accounting for canvas dimensions and the camera offset.

### 7.5 Camera Class

```scala
class Camera(var location: Vector3D, var rotOffset: Vector3D,
             var focalLength: Double, val view: View)
```

Holds the 3D perspective parameters for `Sprite3D` rendering:

- `location` — camera world position
- `focalLength` — projection distance for perspective divide
- `rotOffset` — camera rotation state
- `view` — the `View` used for final 2D screen mapping

Provides `rotateX/Y/Z(angle)` and `translate(speed: Vector3D)` for camera animation.

---

## 8. Sprite2D Draw Pipeline

**File:** `src/main/scala/org/loom/scene/Sprite2D.scala`

### 8.1 Class Definition

```scala
class Sprite2D(
  val shape: Shape2D,
  val spriteParams: Sprite2DParams,
  var animator: SpriteAnimator,
  var rendererSet: RendererSet
) extends Drawable
```

Constructor applies transforms in this order: rotation offset → initial rotation → translation to `spriteParams.location` → scale to `spriteParams.size`.

### 8.2 Frame Loop

```scala
def update(): Unit
  if drawLimit not exceeded:
    animator.update(this)

def draw(g2D: Graphics2D): Unit
  // See §8.3
```

### 8.3 draw() Dispatch

```
if draw limit exceeded → return

if rendererSet.allRenderersActive:
  for each renderer in set:
    for each polygon in shape (filtered visible):
      if BRUSHED → drawBrushed(g2D, view)
      if STENCILED → drawStenciled(g2D, view)
      else → dispatch by mode (see §8.4)
      updateRenderer(POLY)

else (normal mode):
  ren = rendererSet.getRenderer()
  for each polygon in shape (filtered visible):
    check holdLength → advance renderer if hold exceeded
    dispatch by mode
    updateRenderer(POLY)
  updateRenderer(SPRITE)
```

### 8.4 Per-Mode Dispatch

| Renderer mode | Method called | AWT primitives used |
|---------------|---------------|---------------------|
| `POINTS` | `drawPoints(g2D, pol, view)` | `Ellipse2D` per point |
| `STROKED` | `drawLines(g2D, pol, view)` | `Polygon` (LINE) or `GeneralPath` cubic Bézier (SPLINE) |
| `FILLED` | `drawFilled(g2D, pol, view)` | `Polygon` or `GeneralPath` fill |
| `FILLED_STROKED` | `drawFilledStroked(g2D, pol, view)` | Fill pass then stroke pass |
| `BRUSHED` | `drawBrushed(g2D, view)` | `BufferedImage` stamps (see §9) |
| `STENCILED` | `drawStenciled(g2D, view)` | `BufferedImage` stamps (see §9) |

### 8.5 Special Polygon Type Handling

Before the generic rendering path, `draw*` methods check `polygon.polyType`:

| PolyType | Override behaviour |
|----------|--------------------|
| `POINT_POLYGON` | Single dot or filled circle at `points.head` |
| `OVAL_POLYGON` | Axis-aligned ellipse via `drawOval()`; for brush/stencil converted to polyline via `ovalToPolyline()` |
| `OPEN_SPLINE_POLYGON` | In `drawFilled()`: rendered as stroked (cannot meaningfully fill an open path) |

### 8.6 Spline Point Encoding

For `SPLINE_POLYGON` types, points are stored in groups of 4 per segment:

```
segment i = [anchor_i, control_out_i, control_in_{i+1}, anchor_{i+1}]
```

`drawLines()` and `drawFilled()` iterate in steps of 4, constructing a `GeneralPath` with `moveTo` / `curveTo` calls.

### 8.7 coordinateCorrect()

```scala
def coordinateCorrect(pol: Polygon2D, view: View): Polygon2D
```

Copies all points through `view.viewToScreenVertex()`, returning a new `Polygon2D` in screen space. The original geometry is not modified.

### 8.8 Brush and Stencil State

Brush/stencil rendering maintains per-renderer state keyed by renderer name:

```scala
private val brushStates:   mutable.Map[String, BrushState]
private val stencilStates: mutable.Map[String, BrushState]
```

This allows multiple `BRUSHED` or `STENCILED` renderers in the same `RendererSet` to each maintain independent progressive-reveal agents.

---

## 9. Brush and Stencil Subsystems

### 9.1 BrushConfig / StencilConfig

`BrushConfig` holds:

| Field | Description |
|-------|-------------|
| `brushNames: Array[String]` | Names of brush images to load |
| `blurRadius: Float` | Gaussian blur radius applied to brush on load |
| `stampSpacing: Float` | Minimum pixel distance between stamps along an edge |
| `stampsPerFrame: Int` | Stamps advanced per frame in PROGRESSIVE mode |
| `agentCount: Int` | Number of independent progressive agents |
| `drawMode: Int` | `FULL_PATH` (0) or `PROGRESSIVE` (1) |
| `postCompletionMode: Int` | What to do after all agents complete |

`StencilConfig` is similar but additionally carries `currentOpacity: Float` (animated via `RenderTransform` slot 4).

### 9.2 BrushState / BrushAgent

`BrushState` manages the edge data derived from a set of polygons:

```scala
class BrushState {
  var edges: List[Edge]
  var agents: List[BrushAgent]
  var initialized: Boolean
  
  def initializeFromPolys(polys: List[Polygon2D]): Unit
  def createAgents(n: Int): Unit
  def checkCompletion(postMode: Int): Unit
}
```

Edges are deduplicated using canonical string keys to prevent double-stamping on shared polygon boundaries.

`BrushAgent` tracks the position of one progressive agent along the edge list.

### 9.3 Draw Modes

**FULL_PATH**: A fresh `BrushState` is created every frame. All edges are stamped in their entirety. `meanderFrame` counter is advanced to animate any time-based perturbation in the brush config.

**PROGRESSIVE**: `BrushState` is lazily initialised on first draw and retained across frames. Each `BrushAgent` advances by `stampsPerFrame` stamps per frame, producing a reveal effect. Once all agents complete, `checkCompletion()` applies the `postCompletionMode` policy (e.g., reset, freeze).

### 9.4 Stamp Engines

`BrushStampEngine` and `StencilStampEngine` are the low-level stamp appliers. They walk the edge, apply spacing logic, composite the brush/stencil image onto `g2D` with the appropriate color tint (BRUSHED) or raw opacity (STENCILED), and report progress back to the agent.

---

## 10. Sprite3D Draw Pipeline

**File:** `src/main/scala/org/loom/scene/Sprite3D.scala`

### 10.1 Class Definition

```scala
class Sprite3D(
  var shape: Shape3D,
  var location: Vector3D,
  var size: Vector3D,
  val startRotation: Vector3D,
  val rotOffset: Vector3D,
  var animator: Animator3D,
  var rendererSet: RendererSet
) extends Drawable
```

### 10.2 3D Perspective Pipeline

For each polygon, `Sprite3D` applies:

1. Check near-clip: skip polygon if closer than `Camera.nearClipDistance`.
2. Project each point: `point_screen = getPerspective(point_world + sprite.location, viewDistance)`.
3. Apply view correction: `view.viewToScreenVertex(projected)`.
4. Render using AWT primitives identical to `Sprite2D`.

`getPerspective()` implements a simple central projection:

```
screenX = worldX * focalLength / worldZ
screenY = worldY * focalLength / worldZ
```

### 10.3 Limitations

- `Sprite3D` supports only `POINTS`, `STROKED`, `FILLED`, and `FILLED_STROKED` modes.
- `BRUSHED` and `STENCILED` modes are not available for 3D sprites.
- There is no z-sorting of individual polygons; painter's order is determined by polygon list order in `Shape3D`.

---

## 11. Scene

**File:** `src/main/scala/org/loom/scene/Scene.scala`

### 11.1 Structure

```scala
class Scene {
  private val sprites: ListBuffer[Drawable]
}
```

A flat list of `Drawable` objects (mix of `Sprite2D` and `Sprite3D`).

### 11.2 Public API

| Method | Description |
|--------|-------------|
| `addSprite(sprite)` | Append to end of list |
| `addSprite(sprite, zIndex)` | Insert at specific z-order position |
| `removeSprite(sprite/zIndex)` | Remove by reference or index |
| `changeZIndex(sprite, zIndex)` | Move to new position |
| `getSprite(zIndex)` | Return sprite at index |
| `getIndex(sprite)` | Return index of sprite |
| `getSize()` | Number of sprites |
| `update()` | Call `update()` on every sprite |
| `draw(g2D)` | Call `draw(g2D)` on every sprite in order |
| `drawSprite(g2D, index)` | Draw one specific sprite |
| `drawSpritePoly(g2D, spriteIndex, polyIndex)` | Draw one polygon of one sprite |

### 11.3 Transform Delegation

`Scene` provides bulk transform methods (`translate`, `scale`, `rotate`, `rotateX/Y/Z`, `rotateAroundParent`) that iterate over all sprites and delegate to the appropriate `Sprite2D` or `Sprite3D` method. These assume a homogeneous scene (all 2D or all 3D); mixing types requires the caller to manage the list directly.

---

## 12. Design Assessment

### R1 — Renderer.clone() and toString() are commented out

`Renderer.scala` contains commented-out `clone()` and `toString()` methods marked "FIX: Needs updating to reflect new fields". This means cloning a `RendererSet` is not possible without manually reconstructing each `Renderer`, and logging is degraded.

**Recommended fix:** Implement `clone()` following the same pattern as `Animator2D.clone()` (spec §03). Generate a fresh `Renderer`, copy all fields, deep-copy `changeSet` array.

---

### R2 — RenderTransform: two wrong field references in POINT_SIZE PING_PONG (bug)

**Location:** `RenderTransform.scala` lines 566–568

```scala
// Current (wrong):
renderer.pointSize = renderer.strokeWidth - pointSizeValues.increment
strokeWidthValues.goingUp = true

// Should be:
renderer.pointSize = renderer.pointSize - pointSizeValues.increment
pointSizeValues.goingUp = true
```

When `pointSize` animates in PING_PONG DOWN mode, the code accidentally reads `strokeWidth` as the current value and flags `strokeWidthValues.goingUp` instead of `pointSizeValues.goingUp`. Net effect: `pointSize` is corrupted and `strokeWidth` direction state may flicker whenever point-size ping-pong is used.

**Fix:** see §13.

---

### R3 — No delta-time: all animation is frame-rate dependent

`RenderTransform` increments by a fixed value per frame. On faster hardware the rendering runs visually faster; on slower hardware it runs visually slower. There is no concept of elapsed wall-clock time.

**Swift migration consideration:** Introduce a `deltaTime: Double` parameter to both the scene update loop and the parameter animation loop.

---

### R4 — Direct mutation of renderer properties

`RenderTransform.update()` writes directly to `renderer.strokeColor`, `renderer.fillColor`, `renderer.strokeWidth`, `renderer.pointSize`, and `renderer.stencilConfig.currentOpacity`. There is no change-notification system and no snapshot of previous state.

---

### R5 — Edge deduplication uses string keys (performance)

`BrushState.initializeFromPolys()` constructs a canonical string for each edge to prevent double-stamping. This is O(n²) in the number of edges and allocates a string per edge per frame in `FULL_PATH` mode.

**Swift migration fix:** Use integer point indices and a hash set of `(min(i,j), max(i,j))` tuples for O(n) deduplication without string allocation.

---

### R6 — RendererSet has no bounds check on selectedIndex

If `selectedIndex` is set to a value ≥ `rendererSet.length` (e.g., after removing a renderer), `rendererSet(selectedIndex)` will throw `IndexOutOfBoundsException`.

---

### R7 — Debug println in Sprite2D constructor

Lines 42–45 of `Sprite2D.scala` print sprite creation diagnostics to stdout unconditionally. Should be guarded by a debug flag.

---

### R8 — Sprite3D constructor transform order differs from Sprite2D

`Sprite2D`: rotation offset → rotation → translate → scale.
`Sprite3D`: rotation offset → scale → rotation (no constructor translate; location applied at draw time).

Not a bug, but a maintenance hazard. The convention should be explicitly documented in the constructor of each class.

---

### R9 — Renderer.update() scale filtering is effectively inert

`Renderer.update(scale: Int)` passes the scale level to each `RenderTransform` to allow per-granularity opt-in. In practice all renderer configurations tested use `SPRITE` level or leave scale unset, so the filtering mechanism exists but is never meaningfully exercised. This is dead complexity.

---

## 13. Shape2D and Shape3D: The Geometry Container

**Files:** `src/main/scala/org/loom/geometry/Shape2D.scala`, `Shape3D.scala`

`Shape2D` and `Shape3D` are thin containers that sit between the subdivision system (spec 02) and the sprite/render system. They exist in the Scala codebase for historical reasons; in the Swift rewrite they should be eliminated — the sprite will hold its polygon list directly (see §13.3).

### 13.1 Shape2D

```scala
class Shape2D(
  val polys: List[Polygon2D],
  val subdivisionParamsSet: SubdivisionParamsSet  // may be null
)
```

Adds to a bare polygon list:

- `translate`, `scale`, `rotate` — delegate to every polygon in `polys`
- `clone()` — deep-copies all polygons
- `recursiveSubdivide(subs: List[SubdivisionParams]): Shape2D` — produces final render geometry (see §13.2)
- `subdivide(subP: SubdivisionParams): Shape2D` — single subdivision pass across all 19 algorithm variants
- `alignPolys()` — shifts even-indexed quad-subdivided polygons to correct vertical alignment

### 13.2 recursiveSubdivide()

For each `SubdivisionParams` in the list in order:

1. Separate polygons into **bypass** (`OPEN_SPLINE`, `POINT`, `OVAL`) and **closed** (eligible for subdivision).
2. Apply `subdivide(subP)` to the closed polygons.
3. Filter out `visible == false` polygons before the next pass.
4. Recombine with bypass polygons.

The final `Shape2D` may have many times more polygons than the original. Bypass polygons pass through every pass unchanged — they appear alongside subdivided geometry in the final shape.

### 13.3 Shape3D

```scala
class Shape3D(val points: List[Vector3D], val polys: List[Polygon3D])
```

Uses a **shared point list**: all polygons reference shared `Vector3D` instances by index via `vertexOrders: Array[Array[Int]]`. A transform updates each point once regardless of how many polygons share it. Cloning must reconstruct `vertexOrders` mappings carefully.

### 13.4 Swift Migration: Eliminate Both Classes

`Sprite2D` should hold `[Polygon2D]` directly (as the Loom Editor already does). The `recursiveSubdivide()` logic moves to a free function or a `SubdivisionEngine` that takes `([Polygon2D], [SubdivisionParams]) → [Polygon2D]`.

The shared-point pattern in `Shape3D` is worth reconsidering for 3D meshes; if retained, encapsulate it behind a proper mesh type with safe mutation semantics.

---

## 14. Bug Fix: RenderTransform POINT_SIZE PING_PONG

Two wrong field references in `updatePointSize()`. The DOWN branch of the PING_PONG case reads `renderer.strokeWidth` as the current value (should be `renderer.pointSize`) and sets `strokeWidthValues.goingUp` (should be `pointSizeValues.goingUp`).
