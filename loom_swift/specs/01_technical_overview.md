# Loom Engine — Technical Overview
**Version:** 2.0
**Date:** 2026-04-27
**Scope:** Swift implementation (current); Scala 3 documented as legacy reference

---

## 1. Purpose and Scope

This document provides an architectural overview of the current Swift implementation of the Loom engine, identifies the legacy Scala foundation it replaces, and establishes the vocabulary and component model for the accompanying specification series:

- Subdivision system
- Animation and sprite system
- Rendering pipeline
- Configuration and parameter loading
- Serialization / I/O
- Interaction model

---

## 2. Implementation Status

**The Swift implementation (`loom_swift/`) is the active engine.** The Scala 3 codebase (`loom_engine/`) remains as a reference but is under light maintenance only — no new features.

All 11 phases of the migration plan have been substantially implemented. The Swift engine reads the same `.loom_projects` XML format as the Scala engine and is visually compatible with it.

---

## 3. Build and Infrastructure

**Language:** Swift 6.0
**Build tool:** Swift Package Manager
**Minimum targets:** macOS 14 (Sonoma), iOS 17+

**Package targets:**

| Target | Kind | Description |
|--------|------|-------------|
| `LoomEngine` | Library | Platform-agnostic engine; no AppKit/UIKit imports |
| `LoomApp` | Executable | macOS SwiftUI application |
| `LoomBake` | Executable | Headless CLI for batch frame export |

`LoomApp` and `LoomBake` both depend on `LoomEngine`. `LoomEngine` imports only `Foundation`, `CoreGraphics`, `CoreImage`, and `AVFoundation` — it compiles for macOS and iOS without conditional compilation.

**Current platform status:** `LoomApp` currently imports `AppKit` (macOS only). The iOS / `UIViewRepresentable` path has not yet been implemented; the architecture keeps it cleanly separable.

---

## 4. Source Layout

```
loom_swift/Sources/
  LoomEngine/
    Geometry/
      Vector2D.swift
      Vector3D.swift
      PolygonType.swift
      Polygon2D.swift
      Polygon3D.swift
      ViewTransform.swift
      RegularPolygonGenerator.swift
    Subdivision/
      SubdivisionType.swift         (enum, 20 cases, raw values 0–19 with gap at 15)
      SubdivisionType+XML.swift
      VisibilityRule.swift          (enum, 16 cases, raw values 0–15)
      VisibilityRule+XML.swift
      SubdivisionParams.swift
      SubdivisionEngine.swift
      BezierMath.swift
      InsetTransform.swift
      PTPTransformSet.swift         (PTW/PTP plug-in transforms)
      PolygonTransforms.swift
      Algorithms/
        QuadAlgorithm.swift
        QuadBordAlgorithm.swift
        TriAlgorithm.swift
        TriBordAlgorithm.swift
        TriStarAlgorithm.swift
        SplitAlgorithm.swift
        EchoAlgorithm.swift
    Animation/
      TransformAnimator.swift       (pure function: animation → SpriteTransform)
      SpriteTransform.swift         (value: position, scale, rotation, morphAmount)
      RenderStateEngine.swift       (advances RendererAnimationState each frame)
      RendererAnimationState.swift  (per-renderer animation cursor state)
      MorphInterpolator.swift       (blends base polygons toward morph targets)
      EasingMath.swift              (easing curve implementations)
    Rendering/
      RenderEngine.swift            (CGContext drawing; pure functions)
      BrushConfig.swift
      BrushEdge.swift
      BrushStampEngine.swift        (brush-along-path stamping)
      StampEngine.swift             (stencil/stamp mode)
      PathPerturbation.swift
      SmoothNoise.swift
      LoomColor+CoreGraphics.swift
    Scene/
      SpriteScene.swift             (assembly + advance + render)
      SpriteInstance.swift
      SpriteState.swift
    Config/
      GlobalConfig.swift
      ProjectConfig.swift
      ShapeConfig.swift
      PolygonConfig.swift
      SubdivisionConfig.swift
      RenderingConfig.swift
      SpriteConfig.swift
      SpriteAnimation.swift
      CurveConfig.swift
      OvalConfig.swift
      PointConfig.swift
      StencilConfig.swift
      FloatRange.swift
      LoomColor.swift
    Loaders/
      ProjectLoader.swift
      XMLConfigLoader.swift
      XMLPolygonLoader.swift
      XMLNode.swift
      JSONConfigLoader.swift
    Engine/
      Engine.swift                  (class: wraps LoomEngine, drives FrameLoop)
      FrameLoop.swift               (protocol)
    Export/
      StillExporter.swift
      VideoExporter.swift
    LoomEngine.swift                (struct: core scene state)

  LoomApp/
    LoomApp.swift
    ContentView.swift
    EngineController.swift
    RenderSurface.swift
    ExportSheet.swift

  LoomBake/
    main.swift
```

---

## 5. Core Architecture

### 5.1 Two-Layer Engine Design

```
┌─────────────────────────────────────────────────────┐
│  Engine (final class)                               │
│  Wraps LoomEngine struct + drives FrameLoop         │
│  Exposes: start(with:), stop(), update(deltaTime:), │
│           draw(into:), makeFrame(), reset()         │
│  Properties: currentFrame, canvasSize, globalConfig │
└────────────────────────┬────────────────────────────┘
                         │ owns
┌────────────────────────▼────────────────────────────┐
│  LoomEngine (public struct, @unchecked Sendable)    │
│  Fields:                                            │
│    scene: SpriteScene                               │
│    config: ProjectConfig                            │
│    viewTransform: ViewTransform                     │
│    backgroundImage: CGImage?                        │
│    brushImages: [String: CGImage]  (pre-blurred)    │
│    stampImages: [String: CGImage]  (from stamps/)   │
│    rng: SystemRandomNumberGenerator                 │
│    frameCount: Int                                  │
│    elapsedFrames: Double                            │
│    accumulationCanvas: AccumulationCanvas           │
└─────────────────────────────────────────────────────┘
```

`LoomEngine` is a `struct` — value-type semantics, no reference sharing. `Engine` is a `final class` that provides the external API and manages object lifetime (FrameLoop ownership, notification hooks).

`AccumulationCanvas` is a heap-backed `CGContext` (class) that persists across frames when `globalConfig.drawBackgroundOnce = true`, enabling accumulation/trails rendering.

### 5.2 Scene

`SpriteScene` (`struct, Sendable`) is the assembled, runnable scene. It is both the product of loading a project and the runtime scene state.

```
SpriteScene
├── instances: [SpriteInstance]
│   └── each SpriteInstance:
│       ├── def:                SpriteDef           (config; immutable)
│       ├── basePolygons:       [Polygon2D]         (loaded geometry)
│       ├── morphTargetPolygons:[[Polygon2D]]        (morph targets)
│       ├── rendererSet:        RendererSet          (resolved at assembly)
│       ├── subdivisionParams:  [SubdivisionParams]  (resolved at assembly)
│       └── state:              SpriteState          (mutable frame state)
└── qualityMultiple: Int
```

### 5.3 Value Types

All engine types — `Vector2D`, `Polygon2D`, `SubdivisionParams`, `Renderer`, `SpriteTransform`, `GlobalConfig` — are `struct`. The engine has no shared mutable state. Mutation of animation state is explicit: `SpriteScene.advance(deltaTime:targetFPS:using:)` mutates the scene in-place (structs copied on assignment).

---

## 6. Geometry Layer

### 6.1 Coordinate Types

| Type | Semantics |
|------|-----------|
| `Vector2D(x: Double, y: Double)` | Position, offset, scale |
| `Vector3D(x: Double, y: Double, z: Double)` | 3D geometry (not yet fully used) |

`Vector2D` is `Codable`, `Equatable`, `Sendable`. Transforms return new values.

### 6.2 Polygon Types

```swift
enum PolygonType: Int, Codable, Sendable {
    case line         = 0   // straight-edged polygon
    case spline       = 1   // closed cubic Bézier (groups of 4)
    case openSpline   = 2   // open cubic Bézier
    case point        = 3   // single-vertex (discrete point)
    case oval         = 4   // 2-point ellipse encoding
}
```

`Polygon2D` holds `points: [Vector2D]`, `type: PolygonType`, `pressures: [Double]` (per-anchor, defaults empty), and `visible: Bool`.

Spline encoding: groups of 4 — `[anchor₀, controlOut₀, controlIn₁, anchor₁]`. `points.count` is always a multiple of 4 for `.spline` and `.openSpline`.

### 6.3 Coordinate Convention

Y-up, origin at canvas centre (Loom world space). The `ViewTransform` converts world coordinates to screen pixels. `RenderEngine` expects the caller to have applied a Y-flip transform to the `CGContext` before drawing.

**Sprite coordinate pipeline:**
1. Polygon points in normalised geometry space (≈ ±0.5)
2. Scale by `2.0 × sprite.scale` → world range ≈ ±1
3. Rotate in world space
4. Multiply by canvas half-size → pixel offsets from canvas centre
5. Add pixel-space position (raw_pos / 100 × canvas_half)
6. `ViewTransform.worldToScreen` adds canvas-centre offset → final screen pixels

---

## 7. Subdivision System

See `02_subdivision.md` for full detail.

`SubdivisionEngine` is a pure-function enum namespace. `SubdivisionEngine.process(polygons:paramSet:rng:)` applies each `SubdivisionParams` in the set in sequence. The result of each generation is the input to the next.

`SubdivisionType` is a 20-case enum (raw Int values 0–19, gap at 15). Seven concrete algorithm files cover all cases.

---

## 8. Animation System

See `03_animation.md` for full detail.

Animation is a pure transform — `TransformAnimator.transform(for:elapsedFrames:using:)` returns a `SpriteTransform` with no side effects. `SpriteScene.advance(deltaTime:targetFPS:using:)` accumulates `elapsedTime`, updates `SpriteTransform`, advances renderer index, and steps `RendererAnimationState` palettes.

**Delta-time-based:** All timing is wall-clock seconds converted to virtual frames via `targetFPS`. Frame-count-based XML values (keyframe `drawCycle`, hold lengths, `pauseMax`) are integer virtual frame numbers compared against `elapsedFrames = elapsedTime × targetFPS`.

---

## 9. Rendering Pipeline

See `04_rendering.md` for full detail.

`RenderEngine` is a pure-function enum namespace drawing to a `CGContext`. `SpriteScene.render(into:viewTransform:brushImages:stampImages:elapsedFrames:using:)` iterates instances and dispatches to `RenderEngine.draw`, `BrushStampEngine.drawFullPath`, or `StampEngine.draw` depending on `renderer.mode`.

Brush images are pre-blurred using `CIBoxBlur` at `LoomEngine` init time, keyed by `"<filename>@<scaledRadius>"`. Stamp images are loaded from `<project>/stamps/`.

---

## 10. Configuration and Loading

See `05_configuration.md` for full detail.

**`ProjectConfig`** (`struct, Codable`) is the root config type holding nine sub-configs.

**`ProjectLoader`** orchestrates loading from `<project>/configuration/`. Six files are required; curves/ovals/points XML is optional.

**Two load paths:**
- `XMLConfigLoader` — reads existing `.loom_projects` XML
- `JSONConfigLoader` — reads/writes `ProjectConfig` as JSON via `Codable`

---

## 11. Frame Loop

`FrameLoop` is a protocol:
```swift
protocol FrameLoop: AnyObject {
    func start(onTick: @escaping (_ deltaTime: Double) -> Void)
    func stop()
}
```

`Engine.start(with: any FrameLoop)` connects the loop. `LoomBake/main.swift` drives export without a display loop, passing `1.0 / targetFPS` as a fixed delta time.

---

## 12. Application Shell (LoomApp)

`LoomApp` is currently macOS-only (`import AppKit`). Entry point:
```swift
@main struct LoomApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate
    var body: some Scene { ... }
}
```
`AppDelegate.applicationShouldTerminateAfterLastWindowClosed` returns `true`. `LoomCommands` suppresses the `NewItem` menu group.

---

## 13. Sentinel File Control

The Swift engine preserves the Scala sentinel file protocol for compatibility with `loom_parameter_editor`:

| File | Action |
|------|--------|
| `.reload` | Reload configuration and rebuild scene |
| `.pause` | Toggle animation pause |
| `.capture_still` | Save one PNG frame |
| `.capture_video` | Toggle video capture |

---

## 14. Legacy Scala Reference

The Scala 3 codebase (`loom_engine/`) is retained as a reference. Key differences from Swift:

| Concern | Scala | Swift |
|---------|-------|-------|
| Core engine type | Multiple classes, mutable | `LoomEngine` struct, value semantics |
| Frame rate | Fixed 10 FPS (`Thread.sleep(100)`) | Delta-time via `FrameLoop` protocol |
| Geometry mutation | In-place on `Vector2D` | Returns new values |
| Config system | Dual: `Config` singleton + `GlobalConfig` | Single `ProjectConfig` struct |
| Rendering | Java 2D (`Graphics2D`) | Core Graphics (`CGContext`) |
| Serial input | RXTX library | Not yet implemented |

---

## 15. Specification Series

| Document | Title |
|----------|-------|
| `01_technical_overview.md` | This document |
| `02_subdivision.md` | Subdivision algorithms, params, transforms |
| `03_animation.md` | Animation system — TransformAnimator, RenderStateEngine |
| `04_rendering.md` | Rendering pipeline — RenderEngine, brush/stencil |
| `05_configuration.md` | Configuration structs and loading |
| `06_serialization.md` | XML/JSON serialization; file format reference |
| `07_interaction.md` | LoomApp interaction model |
| `08_swift_migration_plan.md` | Phase plan and implementation status |
