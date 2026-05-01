# Loom Engine — Rendering System
**Specification 04**
**Date:** 2026-04-27
**Depends on:** `01_technical_overview.md`, `03_animation.md`

---

## 1. Purpose

This document specifies the rendering system — the mechanism by which Loom's geometric data is converted to screen pixels each frame. It covers:

- The renderer hierarchy (`Renderer` → `RendererSet`) and all six rendering modes
- `RenderEngine` — the Core Graphics drawing implementation
- `BrushStampEngine` and `StampEngine` — brush and stencil subsystems
- Coordinate systems and `ViewTransform`
- How `SpriteScene.render` orchestrates the pipeline
- Design notes and comparisons to the Scala implementation

---

## 2. Conceptual Overview

Loom rendering is a three-layer pipeline:

```
1. WHAT to draw   — subdivided, morph-blended, transform-applied polygon arrays
2. HOW to draw it — Renderer config (mode, colors, stroke width, brush/stencil config)
3. HOW it changes — RendererAnimationState (stepped each frame by RenderStateEngine)
```

`SpriteScene.render(into:viewTransform:brushImages:stampImages:elapsedFrames:using:)` iterates every `SpriteInstance` and:
1. Applies morph interpolation (`MorphInterpolator`)
2. Applies subdivision (`SubdivisionEngine`)
3. Applies the sprite transform (world → pixels)
4. Resolves the active renderer(s) for this frame
5. Dispatches to `RenderEngine.draw`, `BrushStampEngine.drawFullPath`, or `StampEngine.draw`

---

## 3. RendererMode

```swift
public enum RendererMode: Int, Codable, Sendable {
    case points        = 0   // individual dots at every polygon vertex
    case stroked       = 1   // outlined geometry (stroke only)
    case filled        = 2   // solid filled geometry
    case filledStroked = 3   // fill then stroke on top
    case brushed       = 4   // brush-stamp images along polygon edges
    case stamped       = 5   // full-RGBA image stamps at discrete point positions
    case stenciled     = 5   // alias for stamped
}
```

---

## 4. Renderer

**File:** `Rendering/` (via `Config/RenderingConfig.swift`)

```swift
public struct Renderer: Codable, Sendable {
    public var name: String
    public var mode: RendererMode
    public var strokeWidth: Double
    public var strokeColor: LoomColor
    public var fillColor: LoomColor
    public var pointSize: Double
    public var holdLength: Int              // virtual frames before cycling to next renderer
    public var pointStyle: PointStyle       // stroked, filled, or both
    public var brushConfig: BrushConfig?    // non-nil for .brushed mode
    public var stencilConfig: StencilConfig? // non-nil for .stamped/.stenciled mode
    public var changes: RendererChanges     // parameter animation specifications
}
```

`LoomColor` is a `Codable` RGBA struct. `LoomColor+CoreGraphics.swift` provides `toCGColor()` and `toCGColorComponents()`.

### 4.1 RendererChanges

`RendererChanges` holds the animation specifications for each animatable parameter. Each slot is an optional `ParameterAnimation`:

```swift
public struct RendererChanges: Codable, Sendable {
    public var strokeWidth:    ParameterAnimation?
    public var strokeColor:    ColorAnimation?
    public var fillColor:      ColorAnimation?
    public var pointSize:      ParameterAnimation?
    public var opacity:        ParameterAnimation?
    public var stencilOpacity: ParameterAnimation?
}
```

---

## 5. RendererSet and Playback Policy

```swift
public struct RendererSet: Codable, Sendable {
    public var name: String
    public var renderers: [Renderer]
    public var playbackConfig: PlaybackConfig
}

public struct PlaybackConfig: Codable, Sendable {
    public var mode: PlaybackMode           // .static | .sequential | .random | .all
    public var preferredRenderer: String    // name of preferred renderer for .random
    public var preferredProbability: Double // 0–100 probability of using preferred
    public var modifyInternalParameters: Bool
}

public enum PlaybackMode: String, Codable, Sendable {
    case `static`, sequential, random, all
}
```

**Active renderer selection** (in `SpriteScene.resolveActiveRenderers`):

- `.all` → all renderers in the set are applied to every polygon
- `.static` → always `renderers[activeRendererIndex]` (index never changes)
- `.sequential` → advance index when `holdFramesRemaining` reaches 0
- `.random` → pick a random index; apply `preferredProbability` weight when `preferredRenderer` is set

The `activeRendererIndex` and `holdFramesRemaining` are stored in `SpriteState`, not in `RendererSet` — so the set itself is immutable.

---

## 6. RenderEngine

**File:** `Rendering/RenderEngine.swift`

`RenderEngine` is a pure-function `enum` namespace. It draws one polygon into a `CGContext`. No side effects outside the context.

```swift
public enum RenderEngine {
    public static func draw(
        _ polygon: Polygon2D,
        renderer: Renderer,
        into context: CGContext,
        transform: ViewTransform,
        qualityMultiple: Int = 1
    )
}
```

### 6.1 Coordinate Convention

The caller must have applied a Y-flip transform to the `CGContext` before calling `draw`. This converts Core Graphics' bottom-left Y-up coordinates to Loom's screen-space convention (origin top-left, Y-down). `LoomEngine.advance` applies this flip when drawing to the accumulation canvas.

### 6.2 Dispatch by Mode

| Mode | Drawing approach |
|------|----------------|
| `.points` | `CGContext.fillEllipse` at each polygon vertex |
| `.stroked` | `CGMutablePath` with `strokePath()` |
| `.filled` | `CGMutablePath` with `fillPath()` |
| `.filledStroked` | Fill path then stroke path |
| `.brushed` | Returns immediately — handled by `BrushStampEngine` |
| `.stamped` / `.stenciled` | Returns immediately — handled by `StampEngine` |

### 6.3 Bézier Path Construction

For `.spline` polygons (groups of 4 points):

```swift
let path = CGMutablePath()
path.move(to: transform.worldToScreen(points[0]))
stride(from: 0, to: points.count, by: 4).forEach { i in
    path.addCurve(
        to:       transform.worldToScreen(points[i+3]),
        control1: transform.worldToScreen(points[i+1]),
        control2: transform.worldToScreen(points[i+2])
    )
}
if polygon.type == .spline { path.closeSubpath() }
```

For `.line` polygons: `addLine(to:)` between consecutive points, closed with `closeSubpath()`.

For `.point` polygons: each point becomes a filled ellipse of `pointSize` diameter.

For `.oval` polygons: two-point encoding — point[0] is the centre, point[1] is `(cx+rx, cy+ry)`. The radii are extracted and drawn with `addEllipse(in:)`.

### 6.4 Quality Scaling

`qualityMultiple` (from `GlobalConfig`) scales all pixel-size values: `strokeWidth`, `pointSize`, brush stamp parameters. This enables high-resolution export without rescaling existing projects.

---

## 7. ViewTransform

**File:** `Geometry/ViewTransform.swift`

```swift
public struct ViewTransform: Sendable {
    public var canvasSize: CGSize

    public func worldToScreen(_ v: Vector2D) -> CGPoint {
        CGPoint(
            x: canvasSize.width  / 2 + v.x,
            y: canvasSize.height / 2 - v.y   // Y-flip for screen space
        )
    }
}
```

The Y-flip (`- v.y`) converts from Loom world space (Y-up) to Core Graphics screen space (Y-down, origin top-left). After the sprite transform pipeline, polygon points are in pixel-space offsets from canvas centre — `worldToScreen` adds the canvas-centre offset.

---

## 8. Brush Rendering

**Files:** `Rendering/BrushConfig.swift`, `Rendering/BrushEdge.swift`, `Rendering/BrushStampEngine.swift`, `Rendering/PathPerturbation.swift`, `Rendering/SmoothNoise.swift`

### 8.1 Overview

Brush rendering stamps pre-blurred images along polygon edge paths at configurable spacing. It replaces the Scala `drawBrushed()` approach with a Swift implementation that uses `CGContext` drawing and Core Image pre-blurring.

### 8.2 Brush Image Pre-blur

Brush images are pre-blurred at `LoomEngine` init time:

```swift
let blurredKey = "\(filename)@\(scaledRadius)"
let blurred = applyCIBoxBlur(image: rawImage, radius: scaledRadius)
brushImages[blurredKey] = blurred
```

`CIBoxBlur` (Core Image) is used — GPU-accelerated. The blur radius is `blurRadius × qualityMultiple`. Multiple blur radii for the same file are cached independently.

At render time, `BrushStampEngine` looks up the pre-blurred image by key.

### 8.3 BrushEdge

`BrushEdge.extractEdges(from:viewTransform:)` converts transformed polygons into a flat list of screen-space edges, each carrying the associated pressure values for pressure-sensitive stamp sizing/opacity.

### 8.4 BrushStampEngine

```swift
public enum BrushStampEngine {
    public static func drawFullPath(
        edges:         [BrushEdge],
        config:        BrushConfig,
        color:         LoomColor,
        context:       CGContext,
        elapsedFrames: Double,
        brushImages:   [String: CGImage]
    )
}
```

**Full-path mode:** The entire edge path is traversed in one pass, placing stamps at intervals of `config.stampSpacing`. For each stamp:
1. Position along the edge at the current arc-length
2. Apply perpendicular jitter (`perpendicularJitterMin..Max`)
3. Apply random scale (`scaleMin..Max`)
4. Apply random opacity (`opacityMin..Max`)
5. Modulate size/opacity by pressure (controlled by `pressureSizeInfluence`, `pressureAlphaInfluence`)
6. Draw the CGImage at the stamp position

`PathPerturbation` and `SmoothNoise` provide meander animation — a sinusoidal perturbation applied to the path that can be animated by `elapsedFrames`.

### 8.5 BrushConfig

```swift
public struct BrushConfig: Codable, Sendable {
    public var brushNames: [String]
    public var stampSpacing: Double
    public var followTangent: Bool
    public var perpendicularJitterMin: Double
    public var perpendicularJitterMax: Double
    public var scaleMin: Double
    public var scaleMax: Double
    public var opacityMin: Double
    public var opacityMax: Double
    public var blurRadius: Int
    public var pressureSizeInfluence: Double
    public var pressureAlphaInfluence: Double
    public var meanderConfig: MeanderConfig
    public var stampsPerFrame: Int
    public var agentCount: Int
    public var postCompletionMode: PostCompletionMode  // .hold | .loop | .pingPong

    public func scaled(by factor: Double) -> BrushConfig  // scales pixel values for qualityMultiple
}
```

---

## 9. Stamp / Stencil Rendering

**Files:** `Rendering/StampEngine.swift`, `Config/StencilConfig.swift`

### 9.1 Overview

Stamp mode places full-RGBA images at each discrete point position in the polygon. Where brush mode distributes stamps along edges at arc-length intervals, stamp mode places one stamp per polygon point.

### 9.2 StampEngine

```swift
public enum StampEngine {
    public static func draw(
        polygon:       Polygon2D,
        config:        StencilConfig,
        context:       CGContext,
        viewTransform: ViewTransform,
        stampImages:   [String: CGImage],
        opacityState:  FloatAnimState?,
        using rng:     inout some RandomNumberGenerator
    )
}
```

Stamp images are loaded from `<project>/stamps/` at `LoomEngine` init time into `LoomEngine.stampImages`. They are **not pre-blurred** (unlike brush images).

The `opacityState` from `RendererAnimationState.stencilOpacityState` provides the current stepped palette index for `SEQ`/`PING_PONG` opacity animation.

### 9.3 StencilConfig

```swift
public struct StencilConfig: Codable, Sendable {
    public var stencilNames: [String]
    public var drawMode: DrawMode          // .progressive | .fullPath
    public var stampSpacing: Double
    public var stampsPerFrame: Int
    public var agentCount: Int
    public var postCompletionMode: PostCompletionMode
    public var opacityAnimation: ParameterAnimation?

    public func scaled(by factor: Double) -> StencilConfig
}
```

---

## 10. Accumulation Mode

When `globalConfig.drawBackgroundOnce = true`, the background is drawn once and subsequent frames accumulate on top without clearing. This produces trails / accumulation effects.

`LoomEngine.accumulationCanvas` is a heap-backed `CGContext` (class type `AccumulationCanvas`) that persists across frames. The engine draws into this context rather than a fresh context each frame.

`LoomEngine` initialises `AccumulationCanvas` at startup with the full canvas dimensions. The pointer to the underlying bitmap data is stable (heap-allocated, not moved by Swift ARC) — this is why `@unchecked Sendable` is used on `LoomEngine`.

---

## 11. Overlay Color

`globalConfig.overlayColor` is loaded and stored in `LoomEngine` but **never applied** to the canvas. This matches the Scala engine's behaviour (where the overlay color was similarly defined but unused). The field is preserved for future use.

---

## 12. SpriteScene Render Dispatch

The full per-instance render path in `SpriteScene.renderInstance`:

```
1. Guard: basePolygons not empty; drawCycle < totalDraws (unless totalDraws == 0)

2. MorphInterpolator.interpolate(base, targets, morphAmount)
   → morphed: [Polygon2D]

3. SubdivisionEngine.process(morphed, subdivisionParams, &rng)
   → subdivided: [Polygon2D]

4. applyTransform(each polygon, instance, canvasSize)
   → transformed: [Polygon2D]  (pixel-space offsets from canvas centre)

5. resolveActiveRenderers(instance)
   → [Renderer] (1 renderer unless playback mode is .all)

6. for each renderer:
   resolveRendererChanges(renderer, instance)
   → resolved: Renderer (animated values applied from RendererAnimationState)

   dispatch by resolved.mode:
     .brushed → BrushStampEngine.drawFullPath(edges, config, color, context, elapsedFrames, brushImages)
     .stamped / .stenciled → for each polygon: StampEngine.draw(polygon, ...)
     otherwise → for each polygon: RenderEngine.draw(polygon, renderer, context, viewTransform, qualityMultiple)
```

---

## 13. Scala Comparison

| Concern | Scala | Swift |
|---------|-------|-------|
| Drawing API | Java 2D `Graphics2D` | Core Graphics `CGContext` |
| Renderer | Mutable class | Immutable `struct` |
| RendererSet selection | Method calls on mutable object | Pure function in `SpriteScene` |
| Brush blur | Realtime per-frame | Pre-blurred at init with `CIBoxBlur` |
| Stamp images | `stencilConfig.stencilImages` map | `LoomEngine.stampImages` from `stamps/` dir |
| Coordinate system | AWT: origin top-left, Y-down | Core Graphics + Y-flip transform |
| Quality scaling | `scalePixelValues(factor)` mutates renderer | `BrushConfig.scaled(by:)` returns new value |
| Overlay color | Defined but unused | Same — loaded but not applied |
