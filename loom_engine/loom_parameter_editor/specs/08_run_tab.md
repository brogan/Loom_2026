# Run Tab

**Source:** `ui/run_tab.py`  
**No XML file** — process control only; drawing settings saved in `GlobalConfig` (quality, scale, animating, draw_bg_once)

## Purpose

The Run tab is the live control centre for the Loom engine. It:
- Hosts drawing settings that feed into `global_config.xml`
- Streams engine stdout/stderr into an in-app console
- Provides capture controls and render destination configuration
- Provides path configuration for both Scala and Swift engines

Process launch/reload/pause/stop are handled by the **media control bar**, which lives in the `QTabWidget` top-right corner (see below), not inside this tab.

---

## Media Control Bar

**Location:** `QTabWidget.setCornerWidget(run_tab.control_bar, Qt.Corner.TopRightCorner)`  
Placed level with the tab labels at the top-right of the window.

```
  ▶   ⏸   ⏹  │  — / —  │  Stopped
```

### Buttons

| Button | State | Action |
|---|---|---|
| ▶ (Play) | Process **not running** | Auto-save → launch engine (`_on_run_scala` / `_on_run_swift`) |
| ▶ (Play) | Process **running** | Auto-save → write `.reload` sentinel (`_on_reload`) |
| ⏸ (Pause) | Running | Toggle `.pause` sentinel; button remains checked while paused |
| ⏹ (Stop) | Running | `QProcess.terminate()`, kill after 3 s |

▶ is always enabled when a project is loaded; its meaning switches based on process state. ⏸ and ⏹ are disabled when the engine is not running.

### Frame Counter Label

Monospace label (`— / —`) to the right of the stop button. Updated by parsing engine stdout for the pattern `Frame: N/M` or `Frame: N`. Resets to `— / —` when the process exits.

> **Note:** The Swift LoomApp is a native macOS GUI app; it displays its own frame counter in its toolbar and does not print frame data to stdout. The frame label stays at `— / —` in Swift mode unless the engine is modified to emit frame lines.

### Status Label

Bold text to the right of the frame label:

| Text | Colour | Condition |
|---|---|---|
| `Stopped` | grey (#888) | Process not running |
| `Running` | green (#44cc44) | Scala engine running |
| `Running` | blue (#4488ff) | Swift engine running |
| `Paused` | amber (#ffaa44) | Pause sentinel active |
| `Reloading…` | amber (#ffaa44) | Reload sentinel written; reverts after 2 s |

---

## Run Tab Layout

Top-to-bottom sections:

### Drawing Settings Group

Owned here; saved in `global_config.xml` via `MainWindow._get_full_global_config()`.

| Field | Widget | Default | Description |
|---|---|---|---|
| `quality_multiple` | `QSpinBox` (1–8) | 1 | Render at N× canvas resolution |
| `scale_image` | `QCheckBox` | False | Scale stroke width, point size, translation ranges, speed factors, keyframe positions by quality multiple |
| `animating` | `QCheckBox` | False | Run draw loop continuously |
| `draw_background_once` | `QCheckBox` | True | Draw background only on first frame |

`quality_multiple` triggers `MainWindow._update_output_hint()` to update the output size label in the Global tab.

### Capture Controls Group

| Control | Shortcut | Action |
|---|---|---|
| `Save Still` | F9 | Write `.capture_still` sentinel |
| `Renders` | — | Open `renders/` folder in Finder |
| `Save Animation` | F10 | Toggle `.capture_video` sentinel |
| Render destination field | — | Override default `<project_dir>/renders/` path |
| `Browse...` | — | Directory picker |
| `Auto-save before run/reload` checkbox | — | When checked, calls save callback before ▶ or reload |

**Renders** button is positioned between `Save Still` and `Save Animation`.

**Auto-save** checkbox sits below the render destination row (separate from the process control buttons).

If render destination differs from the default, a `.render_path` sentinel is written containing the custom path. If reverted to default, `.render_path` is deleted.

### Engine Path Section

Two alternative sections, only one visible based on `set_engine()`:

**Scala engine (default):**
- `Loom SBT path` — `QLineEdit`; path to `loom_engine` directory. Default: `/Users/broganbunt/Loom_2026/loom_engine`

**Swift engine:**
- `Loom Swift path` — `QLineEdit`; path to `loom_swift` source directory. Default: `/Users/broganbunt/Loom_2026/loom_swift`
- `Browse…` button

### Loom Output Group

- `QPlainTextEdit` (read-only, max 5000 blocks) — live engine stdout/stderr
- `Clear` button

---

## Sentinel File Protocol

All IPC between the editor and a running engine uses plain files written to the project directory. The engine polls for these files, processes them, and deletes them.

| File | Meaning | Written by | Deleted by |
|---|---|---|---|
| `.reload` | Reload all XML config files | Editor (▶ when running) | Engine |
| `.capture_still` | Save a still PNG capture | Editor | Engine |
| `.capture_video` | Toggle animation capture | Editor | Engine |
| `.pause` | Pause/resume animation | Editor (⏸ on) | Editor (⏸ off) |
| `.render_path` | Custom render destination path (content = path) | Editor | Editor (on revert to default) |

---

## Process Management

Both engine modes use a `QProcess` owned by `RunTab`. The process inherits the system environment via `QProcessEnvironment.systemEnvironment()`. Launch commands are run through `/bin/zsh -l -c "…"` so the user's shell PATH (including `sbt`, `swift`) is available.

### Scala launch command
```
sbt "run --project <project_name>"
```
Working directory: `<loom_sbt_path>` (default: `/Users/broganbunt/Loom_2026/loom_engine`)

### Swift launch command
```
swift run LoomApp -- --project "<project_dir>"
```
Working directory: `<loom_swift_path>` (default: `/Users/broganbunt/Loom_2026/loom_swift`)

First Swift run triggers compilation; subsequent runs use the cached build.

### State transitions

| Action | Status label | ▶ | ⏸ | ⏹ |
|---|---|---|---|---|
| Process not running | `Stopped` (grey) | enabled | disabled | disabled |
| Scala launched | `Running` (green) | enabled (→ reload) | enabled | enabled |
| Swift launched | `Running` (blue) | enabled (→ reload) | enabled | enabled |
| Paused | `Paused` (amber) | enabled (→ reload) | checked | enabled |
| Reload sent | `Reloading…` (amber) | enabled | enabled | enabled |
| Process exits | `Stopped` (grey) | enabled (→ run) | disabled | disabled |

---

## Public API

```python
# Tab-level
set_engine(engine: str)                    # "scala" or "swift"
set_loom_app_path(path: str)               # Swift source dir
set_project_dir(path: str)                 # Updates render dest default
set_drawing_settings(quality, scale, animating, draw_bg_once)
get_quality_multiple() -> int
get_scale_image() -> bool
get_animating() -> bool
get_draw_bg_once() -> bool

# Control bar
control_bar -> QWidget                     # Corner widget for QTabWidget
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+L | Run / Reload (via Run menu; maps to ▶ action) |
| Cmd+R | Reload (application-scope shortcut; writes `.reload` sentinel) |
| Cmd+H | Stop (via Run menu) |
| F9 | Save Still (QShortcut on RunTab) |
| F10 | Save Animation (QShortcut on RunTab) |
