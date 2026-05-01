# Loom Engine — Interaction and Application Control
**Specification 07**
**Date:** 2026-04-27
**Depends on:** `01_technical_overview.md`, `05_configuration.md`

---

## 1. Purpose

This document specifies the LoomApp interaction model — how the user controls the running engine and how external processes (the Python parameter editor) communicate with it. It covers:

- `EngineController` — the central `@MainActor` model object
- `PlaybackState` — the three-state playback model
- Sentinel file watching — compatibility with the Python editor
- `RenderSurface` — the macOS render view
- `ContentView` — top-level SwiftUI layout
- `ExportSheet` — export controls
- Command-line interface
- `LoomBake` — headless export
- Comparison with the Scala interaction system

---

## 2. EngineController

**File:** `LoomApp/EngineController.swift`

`EngineController` is the central model object for LoomApp. It is `@MainActor`, `ObservableObject`, and `@unchecked Sendable`.

```swift
@MainActor
final class EngineController: ObservableObject, @unchecked Sendable {
    @Published private(set) var engine:              Engine?
    @Published private(set) var projectURL:          URL?
    @Published private(set) var loadError:           String?
    @Published private(set) var isExporting:         Bool  = false
    @Published          var    exportProgress:       Double = 0
    @Published          var    exportError:          String?
    @Published private(set) var recentProjects:      [URL]  = []
    @Published private(set) var playbackState:       PlaybackState = .playing
    @Published          var    requestingExportSheet: Bool = false
}
```

### 2.1 PlaybackState

```swift
enum PlaybackState { case playing, paused, stopped }
```

| State | Engine behaviour |
|-------|----------------|
| `.playing` | `Engine.update(deltaTime:)` and `Engine.draw(into:)` called each frame |
| `.paused` | `Engine.draw(into:)` called to show current frame; `update` skipped |
| `.stopped` | `Engine.reset()` called; one frame rendered; loop halted |

### 2.2 Project Management

```swift
func open(projectDirectory: URL)   // load Engine, start sentinel timer, update recent list
func reload()                      // reload Engine from current projectURL
```

`open(projectDirectory:)` sets `playbackState` based on `engine.globalConfig.animating`:
- `true` → `.playing` (starts animating immediately)
- `false` → `.stopped` (renders one frame and halts)

### 2.3 Playback Controls

```swift
func play()   // sets playbackState = .playing; clears pausedBySentinel flag
func pause()  // sets playbackState = .paused;  clears pausedBySentinel flag
func stop()   // sets playbackState = .stopped; RenderSurface calls engine.reset()
```

The `pausedBySentinel` flag prevents the Play button from being overridden by the sentinel timer: if the user manually pressed Pause, the sentinel timer's `.pause` file check won't force-resume it.

### 2.4 Recent Projects

Recent projects are persisted to `UserDefaults` under `"recentProjects"` as an array of path strings. Maximum 10 entries. Paths that no longer exist are filtered out on load.

### 2.5 Renders Directory

```swift
func animationRendersDirectory() -> URL?  // looks for renders/animation or renders/animations
func stillRendersDirectory() -> URL?      // looks for renders/still or renders/stills
```

Falls back through: named subdirectory → `renders/` root → project root. Never creates directories.

---

## 3. Sentinel File Watching

`EngineController` starts a 500 ms `Timer` on `open(projectDirectory:)`. Every 500 ms it checks for the presence of control files:

### 3.1 File Actions

| File | Action |
|------|--------|
| `.reload` | Delete file, then `reload()` |
| `.pause` | **Present** → pause if currently playing (sets `pausedBySentinel = true`); **Absent** → resume if `pausedBySentinel` |
| `.capture_still` | Delete file, then `saveSentinelStill()` |
| `.capture_video` | Delete file, then set `requestingExportSheet = true` (ContentView presents ExportSheet) |

### 3.2 Still Capture

`saveSentinelStill()` renders one frame to a PNG:

```swift
let name = eng.globalConfig.name.isEmpty ? projectURL.lastPathComponent : eng.globalConfig.name
let url  = stillRendersDirectory().appendingPathComponent("\(name)_\(timestamp).png")
try? StillExporter.exportPNG(engine: eng, to: url)
```

The filename uses `yyyyMMdd_HHmmss` timestamp to avoid collisions.

### 3.3 Video Capture via `.capture_video`

The `.capture_video` sentinel does not begin video capture directly — it sets `requestingExportSheet = true`, which causes `ContentView` to present the `ExportSheet`. The user then confirms export settings and initiates export from the UI.

This differs from the Scala engine's `.capture_video` which toggled frame capture on/off inline. The Swift approach requires user confirmation but gives more control over codec, duration, and quality.

---

## 4. RenderSurface

**File:** `LoomApp/RenderSurface.swift`

`RenderSurface` is the platform view wrapper that owns the display `Engine` and its frame loop. Currently macOS-only (`NSViewRepresentable`).

```swift
struct RenderSurface: NSViewRepresentable {
    @ObservedObject var controller: EngineController
    // ...
}
```

The underlying `NSView` (or `RenderSurfaceNSView`):
- Creates and owns a `DisplayLinkFrameLoop` (CADisplayLink-based)
- On each tick: checks `controller.playbackState`
  - `.playing` → call `engine.update(deltaTime:)` then `engine.draw(into:)`
  - `.paused` → call `engine.draw(into:)` only (show static frame)
  - `.stopped` → call `engine.draw(into:)` only (show reset frame)
- Renders to a `CALayer`-backed context for hardware-composited display

---

## 5. ContentView

**File:** `LoomApp/ContentView.swift`

Top-level SwiftUI layout. Observes `EngineController` and composes:
- `RenderSurface` (the canvas)
- Toolbar with Play/Pause/Stop/Export buttons
- Project open/reload actions
- Recent projects menu
- Export sheet presentation when `controller.requestingExportSheet == true`

---

## 6. ExportSheet

**File:** `LoomApp/ExportSheet.swift`

A SwiftUI sheet with export parameters:
- FPS picker (24 / 25 / 30 / 60)
- Duration field (seconds)
- Quality multiple stepper (1× / 2× / 4×)
- Codec picker (H.264 / HEVC / ProRes)
- Output path
- Progress view during export (`controller.exportProgress`)

Export is performed by `VideoExporter` on a background task. `controller.beginExport()` / `controller.endExport(error:)` coordinate state transitions.

---

## 7. Command-Line Interface

`EngineController` checks for a `--project <path>` command-line argument at init:

```swift
private func openFromCommandLineIfPresent() {
    let args = CommandLine.arguments
    guard let idx = args.firstIndex(of: "--project"), idx + 1 < args.count else { return }
    let url = URL(fileURLWithPath: args[idx + 1])
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    open(projectDirectory: url)
}
```

This enables launching LoomApp directly to a specific project from the command line or from a `.command` file:

```bash
/path/to/LoomApp --project ~/.loom_projects/MyProject
```

---

## 8. LoomBake (Headless Export)

**File:** `LoomBake/main.swift`

`LoomBake` is a separate executable target that exports video without a UI. It accepts command-line arguments specifying:
- Project directory
- Output file path
- Duration
- FPS
- Quality multiple

Internally it creates an `Engine`, uses a fixed-deltaTime loop (`1.0 / targetFPS` per tick), and drives `VideoExporter` to completion. Exits with code 0 on success, non-zero on error.

This replaces the Scala `--bake-subdivision` CLI mode, which baked subdivision results but did not produce video.

---

## 9. LoomCommands

`LoomCommands` is a SwiftUI `Commands` struct registered in `LoomApp.body`. It suppresses the default `NewItem` menu group (which would show a "New Document" item irrelevant to Loom) and adds Loom-specific menu items (Open, Recent Projects, Reload, Export).

---

## 10. Comparison with Scala Interaction System

| Concern | Scala | Swift |
|---------|-------|-------|
| Input dispatcher | `InteractionManager` (keyboard, mouse, serial) | `EngineController` (project management only) |
| Keyboard shortcuts | `KeyPressListener` with hard-coded VK constants | SwiftUI `.keyboardShortcut` modifiers on toolbar buttons |
| Mouse input | Polled `mousePosition` / `mousePressed` flags | Not yet implemented (no `MySketch.update()` equivalent) |
| Serial input | RXTX library, 9600 baud, `bytes`/`char`/`rfid` modes | Not implemented |
| Camera navigation | Arrow keys → `InteractionManager.moveLeft/Right/Up/Down` | Not implemented (no 3D camera in Swift app yet) |
| Sentinel file polling | 500 ms `javax.swing.Timer` in `DrawPanel` | 500 ms `Timer` in `EngineController` |
| Video capture | Toggle flag via `.capture_video` sentinel | Presents `ExportSheet` for user confirmation |
| Still capture | Immediate frame save via `.capture_still` sentinel | Immediate PNG export via `StillExporter` |
| Project selector | `ProjectSelector` Swing dialog | SwiftUI `ContentView` + macOS `NSOpenPanel` |
| Recent projects | Not implemented | `UserDefaults` list of up to 10 paths |
| Headless export | `--bake-subdivision` (subdivision only) | `LoomBake` target (full video export) |
| Command-line launch | `--project <name>` loads from `ProjectConfigManager` | `--project <path>` loads from filesystem URL |
