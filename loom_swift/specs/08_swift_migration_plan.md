# Loom Engine — Swift Migration: Status and Retrospective
**Specification 08**
**Date:** 2026-04-27
**Depends on:** All previous specs (01–07)

---

## 1. Goals and Constraints

**Goals:**
- Full functional parity with the Scala engine (all 20 subdivision algorithms, all 6 rendering modes, all animator types, video export)
- macOS 14+ from a single codebase; iOS path deferred (see §4, Phase 9)
- Proper delta-time-based frame loop: all animation is frame-rate independent
- First-class video export via `AVAssetWriter`

**Non-goals (deferred):**
- iOS support (planned but not yet implemented — macOS only)
- Serial communication (low priority, not implemented)
- Replacing the Python parameter editor (Stage 3, future)
- SwiftUI parameter editor (Stage 3, future)

**Constraints:**
- The Python Loom Editor (bezier_py) continues producing polygon XML files — the Swift engine reads the existing `.loom_projects` format
- Minimum target: macOS 14 (Sonoma) — required for `CADisplayLink` parity

---

## 2. Architecture

### 2.1 Two-Layer Structure

```
┌──────────────────────────────────────────────────────┐
│  Swift Package: LoomEngine                           │
│  Imports: Foundation · CoreGraphics · AVFoundation   │
│  No AppKit · No UIKit · No SwiftUI                   │
│                                                      │
│  LoomEngine struct — core scene state                │
│  Engine class — wraps LoomEngine + FrameLoop         │
└──────────────────────────────────────────────────────┘
                      ↑ used by
┌──────────────────────────────────────────────────────┐
│  SwiftUI App: LoomApp (macOS only currently)         │
│  Imports: SwiftUI · AppKit                           │
│                                                      │
│  EngineController · RenderSurface · ExportSheet      │
│  NSOpenPanel for file selection                      │
└──────────────────────────────────────────────────────┘
```

**Note:** The original plan described a single `Engine` class as the top-level type. The actual implementation uses a two-layer split: `LoomEngine` is an `@unchecked Sendable` struct holding all scene state; `Engine` is a thin `final class` that wraps `LoomEngine` and owns the `FrameLoop`. See `01_technical_overview.md §4`.

### 2.2 Actual Source Layout

```
loom_swift/
  Package.swift
  Sources/
    LoomEngine/
      Geometry/
        Vector2D.swift
        Vector3D.swift
        PolygonType.swift
        Polygon2D.swift
        ViewTransform.swift
      Subdivision/
        SubdivisionType.swift       (enum, 20 cases; gap at raw value 15)
        VisibilityRule.swift        (enum, 16 cases, raw values 0–15)
        SubdivisionParams.swift
        SubdivisionEngine.swift
        InsetTransform.swift
        PTPTransformSet.swift
        PolygonTransforms.swift     (transform plugin implementations)
      Rendering/
        RendererMode.swift
        Renderer.swift
        RendererSet.swift
        RenderEngine.swift
        BrushConfig.swift
        BrushEdge.swift
        BrushStampEngine.swift
        PathPerturbation.swift
        SmoothNoise.swift
        StampEngine.swift
        StencilConfig.swift
      Animation/
        TransformAnimator.swift     (pure-function enum; replaces Animator protocol)
        SpriteTransform.swift       (value struct; replaces in-place mutation)
        MorphInterpolator.swift
        RenderStateEngine.swift
        RendererAnimationState.swift
        EasingMath.swift
      Scene/
        SpriteScene.swift           (assembly + advance + render; no SceneAssembler)
        SpriteInstance.swift
        SpriteState.swift
      Config/
        ProjectConfig.swift
        GlobalConfig.swift
        ShapeConfig.swift
        PolygonConfig.swift
        CurveConfig.swift
        OvalConfig.swift
        PointConfig.swift
        SubdivisionConfig.swift
        RenderingConfig.swift
        SpriteConfig.swift
      Loaders/
        ProjectLoader.swift
        XMLPolygonLoader.swift
        XMLConfigLoader.swift
        JSONConfigLoader.swift
        XMLNode.swift
        RegularPolygonGenerator.swift
      Engine/
        LoomEngine.swift
        Engine.swift
        FrameLoop.swift
        DisplayLinkFrameLoop.swift
        AccumulationCanvas.swift
      Export/
        VideoExporter.swift
        StillExporter.swift
    LoomApp/
      LoomApp.swift
      EngineController.swift
      ContentView.swift
      RenderSurface.swift
      ExportSheet.swift
      LoomCommands.swift
    LoomBake/
      main.swift
  Tests/
    LoomEngineTests/
      GeometryTests.swift
      SubdivisionTests.swift
      ConfigLoaderTests.swift
      RenderingTests.swift
      AnimationTests.swift
      FrameLoopTests.swift
      ExportTests.swift
```

### 2.3 Divergences from Planned Layout

| Planned | Actual | Note |
|---------|--------|------|
| `Assembly/SceneAssembler.swift` | Absorbed into `SpriteScene.swift` | Assembly is `SpriteScene.init(config:projectDirectory:)` |
| `Animation/Animator.swift` (protocol) | Not present | Replaced by pure-function `TransformAnimator` |
| `Animation/Animator2D.swift` | Not present | Functionality in `TransformAnimator` |
| `Animation/KeyframeAnimator.swift` | Not present | Functionality in `TransformAnimator` |
| `Animation/MorphTarget.swift` | `Animation/MorphInterpolator.swift` | Different name, same function |
| `Animation/JitterMorphAnimator.swift` | Not present | `.jitterMorph` case in `TransformAnimator` |
| `Animation/KeyframeMorphAnimator.swift` | Not present | `.keyframeMorph` case in `TransformAnimator` |
| `Animation/Easing.swift` | `Animation/EasingMath.swift` | Different name |
| `Rendering/RenderTransform.swift` | `Animation/RenderStateEngine.swift` + `RendererAnimationState.swift` | Split into advance + state |
| `Rendering/BrushEngine.swift` | `Rendering/BrushStampEngine.swift` | Different name |
| `Rendering/StencilEngine.swift` | `Rendering/StampEngine.swift` | Different name |
| `Scene/Scene.swift` | `Scene/SpriteScene.swift` | Different name |
| `Scene/Camera.swift` | Not present | 3D camera not yet implemented |
| `Platform/RenderSurface+iOS.swift` | Not present | iOS deferred |
| `SubdivisionType` 19 cases | 20 cases (gap at raw 15) | `triStarFill` (19) and `triBordBEcho` (18) added |
| No `stamps/` support planned | `stamps/` directory loaded at init | `StampEngine` uses separate stamp images |
| No `targetFPS` in `GlobalConfig` | `targetFPS: Double = 30.0` present | Needed for wall-clock → virtual frame conversion |
| `DispatchSource` event-driven sentinel watching | 500 ms `Timer` polling | Simpler approach chosen; functionally equivalent |

---

## 3. Relationship to Existing Tools

```
bezier_py (Python)              →  produces polygonSet XML files
loom_parameter_editor (Python)  →  produces project XML files
                                      ↓
                            Swift LoomEngine reads both
                            (XMLConfigLoader, XMLPolygonLoader)
                                      ↓
                            Writes back as JSON
                            (JSONConfigLoader — full roundtrip for all config types)
```

The Python tools continue unchanged. `XMLConfigLoader` handles all quirks documented in `06_serialization.md`: DTD suppression, three color formats, preserved typos (`CpsSqueezeFacto`, `polysTranformWhole`).

---

## 4. Phase Status

---

### Phase 1 — Core geometry
**Status: Complete**

`Vector2D`, `Polygon2D`, `PolygonType`, `ViewTransform` are implemented as specified.

**Divergences:**
- `Vector3D` present but minimal — 3D camera not yet implemented
- `Polygon2D` does not have `translated/scaled/rotated` returning new values as chainable methods; transforms are applied in `SpriteScene.applyTransform`
- `ViewTransform` has no `offset` field — the canvas-centre offset is computed inside `worldToScreen` from `canvasSize`

---

### Phase 2 — Subdivision engine
**Status: Complete**

`SubdivisionType`, `VisibilityRule`, `SubdivisionParams`, `SubdivisionEngine`, all transform plugins are implemented.

**Divergences from plan:**
- `SubdivisionType` has **20 cases** (not 19). Raw values 0–19 with a gap at 15. Cases `triBordBEcho` (18) and `triStarFill` (19) were added. See `02_subdivision.md §12`.
- `SubdivisionEngine.process(polygons:paramSet:rng:)` takes a `[SubdivisionParams]` array (the full paramSet), not individual params + recursion logic
- The enum has a raw `Int` type for XML compatibility, not `String`
- Transform plugins implemented in `PolygonTransforms.swift` and `PTPTransformSet.swift`; no per-plugin files
- **Post-completion fix:** `OuterControlPoints`, `AnchorsLinkedToCentre`, and `InnerControlPoints` were initially absent from the Swift engine (only `ExteriorAnchors` and `CentralAnchors` were implemented). All three were added in a subsequent session. `InnerControlPoints` required a full-array pass (cross-polygon pairing) and is applied separately after the per-polygon transforms.

---

### Phase 3 — Configuration and serialization
**Status: Complete**

All config structs, `ProjectLoader`, `XMLConfigLoader`, `XMLPolygonLoader`, `JSONConfigLoader` implemented.

**Divergences from plan:**
- `JSONConfigLoader` provides **full roundtrip for all 9 config types** (not just `GlobalConfig`)
- `GlobalConfig` has a `targetFPS: Double = 30.0` field not in the original plan — needed for wall-clock → virtual frame conversion
- Folder name mapping: `"polygonSet"` (singular, Scala legacy) → `"polygonSets/"` (plural, on-disk) handled in `SpriteScene`, not `XMLPolygonLoader`
- `XMLPolygonLoader` does **not** apply a normalisation matrix at load time (no `standShapesUpright` / `reverseShapesHorizontally` equivalent). Polygon coordinates are loaded as-is.
- `XMLNode` internal helper (`Loaders/XMLNode.swift`) wraps `XMLParser` into a lightweight DOM tree

---

### Phase 4 — Rendering primitives
**Status: Complete**

All 6 rendering modes implemented including brush and stencil (not deferred to Phase 10 as planned).

**Divergences from plan:**
- `RendererMode` uses raw `Int` values (not `String`)
- `RendererMode.stenciled = 5` is an alias for `RendererMode.stamped = 5` — same raw value
- `Renderer` uses `LoomColor` (custom RGBA struct), not `CGColor` — `LoomColor+CoreGraphics.swift` provides `toCGColor()`
- Brush images pre-blurred at init time using `CIBoxBlur` (Core Image), cached as `"<filename>@<scaledRadius>"` keys
- Stamp images loaded from `<project>/stamps/` directory (not in original plan)
- Accumulation mode (`drawBackgroundOnce`) implemented via `AccumulationCanvas` — heap-backed `CGContext` class

---

### Phase 5 — Animation system
**Status: Complete, with different architecture**

All animation types implemented, but the architecture diverges significantly from the plan.

**The planned `Animator` protocol approach was not used.** Instead:

- `TransformAnimator` is a pure-function `enum` namespace (no protocol, no instances). Given `SpriteAnimation` + `elapsedFrames`, returns a `SpriteTransform` value.
- `SpriteTransform` is a value struct holding `positionOffset`, `scale`, `rotation`, `morphAmount`. It is never accumulated into polygon geometry — applied fresh each frame.
- Four animation types: `.keyframe`, `.random`, `.keyframeMorph`, `.jitterMorph` (as `AnimationType` enum cases).
- `RenderStateEngine` + `RendererAnimationState` replace `RenderTransform`. `RenderStateEngine.advance()` returns a new state; `RenderStateEngine.resolve()` applies state to produce an animated `Renderer`.
- Delta-time is used throughout, but renderer parameter animation uses virtual frame counting (not pure time), to honour integer hold lengths from XML.

See `03_animation.md` for the full specification of the implemented system.

---

### Phase 6 — Scene assembly
**Status: Complete, absorbed into SpriteScene**

`SceneAssembler.swift` was not created as a separate file. Assembly is `SpriteScene.init(config:projectDirectory:)`.

**Divergences from plan:**
- No `Scene` struct wrapping sprites + camera — `SpriteScene` holds `instances: [SpriteInstance]` directly
- No `Camera` struct — 3D camera not yet implemented
- Name resolution errors do **not** throw — missing renderer set falls back to a single default renderer; missing subdivision params uses empty pass-through. This matches Scala's silent-fallback behaviour.
- Assembly errors (malformed XML, missing required files) are handled at the `ProjectLoader` layer (throws `ProjectLoaderError.missingFile`), not the assembly layer

---

### Phase 7 — Frame loop and timing
**Status: Complete**

`FrameLoop` protocol, `DisplayLinkFrameLoop`, `Engine` class all implemented as specified.

**Divergences from plan:**
- `ExportFrameLoop` is not a separate file. `LoomBake/main.swift` drives a manual fixed-deltaTime loop directly via `Engine`.
- `Engine` is a thin wrapper; all frame state is in `LoomEngine` (the struct). `Engine.update(deltaTime:)` delegates to `LoomEngine.advance(deltaTime:)`.
- No `RenderTransform` conversion of `increment` values at load time. Virtual frame counting handles the frame-rate translation transparently.

---

### Phase 8 — Still and video export
**Status: Complete**

`StillExporter` and `VideoExporter` implemented. `LoomBake` headless CLI target implemented.

**Actual API:**

```swift
public enum StillExporter {
    public static func exportPNG(engine: LoomEngine, to url: URL) throws
}
```

`VideoExporter` is a class with async `export(settings:progressHandler:)` method, driven by `AVAssetWriter`. Export settings (fps, duration, quality, codec, output path) match the `ExportSheet` UI controls.

`LoomBake` (`LoomBake/main.swift`) is a separate executable target that accepts command-line arguments, creates an `Engine`, runs the fixed-deltaTime loop, and drives `VideoExporter` to completion.

---

### Phase 9 — UI shell
**Status: macOS only — iOS path not implemented**

`LoomApp` is a macOS-only SwiftUI app. The `#if os(macOS)` / iOS split was not implemented; there is no `RenderSurface+iOS.swift`.

**What is implemented:**
- `EngineController` (`@MainActor ObservableObject`) — central model object
- `RenderSurface` (`NSViewRepresentable`) — wraps `DisplayLinkFrameLoop` + CALayer rendering
- `ContentView` — toolbar with Play/Pause/Stop/Export, recent projects menu
- `ExportSheet` — FPS/duration/quality/codec/output-path controls + progress view
- `LoomCommands` — SwiftUI `Commands` (suppresses "New Document", adds Loom menu items)
- `--project <path>` CLI argument — launches to a specific project
- Recent projects via `UserDefaults`, max 10 entries

**Sentinel file watching:**  
Uses 500 ms `Timer` polling (not `DispatchSource` as the plan suggested). Functionally equivalent; event-driven approach remains a potential future improvement.

**Post-completion fix — `reload()` playback state:**  
`EngineController.reload()` originally only handled the case where `animating` was `false` and `playbackState` was `.playing` (stopping animation). It did not handle the reverse direction: switching from non-animating to animating and reloading left `playbackState` as `.stopped`, so the render surface never called `update()`. Fixed by making `reload()` unconditionally mirror `open()`'s assignment: `playbackState = (engine?.globalConfig.animating == true) ? .playing : .stopped`.

---

### Phase 10 — Brush and stencil rendering
**Status: Complete (implemented earlier than planned)**

Brush and stencil were implemented as part of the Phase 4–5 work, not deferred. `BrushStampEngine` and `StampEngine` are in place.

---

### Phase 11 — Serial communication
**Status: Not implemented**

Low priority; no current need. The `loom_parameter_editor` sentinel file protocol covers the Python↔Swift communication path.

---

## 5. Testing Strategy

Tests exist in `Tests/LoomEngineTests/`. Coverage includes geometry, subdivision, config loading, rendering, animation, and export. The cross-validation strategy against Scala output from the plan is not implemented — the Swift engine output is validated against expected outputs determined from the spec.

---

## 6. Config Format Migration Path

```
Implemented:
  XMLConfigLoader reads existing .loom_projects XML
  JSONConfigLoader writes + reads new format (full roundtrip, all 9 config types)
  Both produce identical ProjectConfig struct

App can open XML projects (existing) and JSON projects (new)
XML reading remains for Python editor compatibility

Future (Stage 3):
  If Python parameter editor is replaced by Swift:
    XMLConfigLoader becomes legacy-only
    Migration script: loom_convert_projects converts XML → JSON in batch
```

---

## 7. Long-Term Architectural Constraints

The following decisions govern what should and should not change as the codebase evolves.

### Stage 1 (complete): Scala/Python legacy
The Scala engine remains as a cross-platform (Mac/Windows/Linux) reference under light maintenance. No new features. Not a migration target.

### Stage 2 (active): Swift engine + Python tools
Swift has replaced Scala. Python tools (bezier_py, loom_parameter_editor) continue unchanged, communicating with the Swift engine via project XML files and sentinel files. This is the active development platform.

### Stage 3 (future): Unified Swift application
Python tools absorbed into the Swift codebase as native SwiftUI interfaces. The file-based Python↔Swift protocol becomes internal API calls. Single application, modern GUI throughout.

### Constraints on the Swift Package

**Expose clean interfaces for what the Python tools currently provide.**  
The sentinel file protocol and `XMLConfigLoader` are the current bridging mechanism. They become legacy-only when the Python tools are absorbed — they can be deprecated without touching anything else.

**Do not hardcode the file-based protocol as permanent.**  
`XMLConfigLoader` and the sentinel file watcher are implementation details, not part of the engine's public API.

**XML is the interchange format; JSON is the Swift-native format.**  
XML stays as long as Python tools write it. `Codable` JSON for all Swift-native state.

**GUI modernisation is a replacement, not a port.**  
When bezier_py becomes a SwiftUI drawing canvas, design from scratch to SwiftUI idioms — not translated widget-for-widget from PySide6.

---

## 8. Spec Cross-Reference

| Topic | Spec | Key sections |
|-------|------|-------------|
| Architecture overview | 01 | Source layout; two-layer Engine/LoomEngine; coordinate pipeline |
| Subdivision algorithms | 02 | All 20 cases; visibility rules; transform plugins; output counts |
| Animation system | 03 | TransformAnimator; SpriteTransform; RenderStateEngine; SpriteScene.advance |
| Rendering pipeline | 04 | RendererMode; RenderEngine; BrushStampEngine; StampEngine; accumulation |
| Configuration structs | 05 | ProjectConfig; GlobalConfig; ProjectLoader; XMLConfigLoader; JSONConfigLoader |
| XML schemas | 06 | All project file formats; color formats; lenient parsing; DTD |
| Interaction and app control | 07 | EngineController; PlaybackState; sentinel files; RenderSurface; LoomBake |
