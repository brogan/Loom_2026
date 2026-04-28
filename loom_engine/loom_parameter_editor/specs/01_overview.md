# Loom Parameter Editor — Application Overview

## Purpose

The Loom Parameter Editor (LPE) is a PySide6 desktop application for configuring all parameters of a Loom generative-art project. It produces a set of XML files that are consumed by either the Scala Loom engine (via SBT) or the Swift Loom engine. It also drives those engines directly — launching, reloading, pausing, and capturing renders — via a sentinel-file protocol and managed subprocesses.

## Technology Stack

| Layer | Choice |
|---|---|
| Language | Python 3.9+ |
| UI framework | PySide6 (Qt 6) |
| XML I/O | lxml |
| Style | Fusion (cross-platform) |
| Process management | `QProcess` (embedded subprocess, not shell) |

## High-Level Architecture

```
main.py
  └── MainWindow  (QMainWindow)
        ├── GlobalTab           → global_config.xml
        ├── GeometryTab         → polygons.xml / curves.xml / points.xml / ovals.xml
        │     ├── SplinePolygonTab
        │     ├── RegularPolygonTab
        │     ├── OpenCurveTab
        │     ├── PointTab
        │     ├── OvalTab
        │     └── BitmapPolygonTab
        ├── SubdivisionTab      → subdivision.xml
        ├── SpriteTab           → sprites.xml  (+ shapes.xml generated on save)
        ├── RenderingTab        → rendering.xml
        └── RunTab              (no XML — drawing settings, capture controls, sentinel files)
              └── control_bar  (QWidget in QTabWidget TopRightCorner — ▶ ⏸ ⏹ + frame + status)
```

All tabs communicate upward through `Signal()` emissions. `MainWindow` is the single orchestrator that owns the `Project` manifest, all IO operations, and cross-tab data propagation.

## Workflow

1. **Open/New Project** — project directory created with standardised subdirectory structure.
2. **Author parameters** — edit geometry, subdivision, sprites, rendering in respective tabs.
3. **Save All** (⌘S) — writes `project.xml` plus all XML config files under `configuration/`.
4. **▶ (Play)** — auto-saves, then: launches the engine from scratch if not running; sends a `.reload` sentinel if already running. The same button covers both the old "Run Loom" (⌘L) and "Reload" (⌘R) actions.
5. **⌘R** — dedicated reload shortcut, application-wide; writes `.reload` sentinel directly.
6. **Capture** (F9/F10) — writes `.capture_still` or `.capture_video` sentinel.

## Engine Selection

The editor supports two engines, selected via a radio button on the Global tab and persisted in app settings:

- **Scala** — launched with `sbt "run --project <name>"` from the `loom_engine` directory.
- **Swift** — launched with `swift run LoomApp -- --project "<project_dir>"` from the `loom_swift` directory.

The Run tab adapts its path fields and button label accordingly.

## Project Directory Layout

```
<project_name>/
├── project.xml                    # manifest (name, timestamps, file references)
├── configuration/
│   ├── global_config.xml
│   ├── rendering.xml
│   ├── polygons.xml
│   ├── subdivision.xml
│   ├── sprites.xml
│   ├── shapes.xml                 # auto-generated from sprites on save (Scala compat)
│   ├── curves.xml
│   ├── points.xml
│   └── ovals.xml
├── polygonSets/                   # Bezier-exported .poly.xml files
├── curveSets/                     # Bezier-exported .curve.xml files
├── pointSets/                     # point geometry XML files
├── regularPolygons/               # editor-generated regular polygon XML files
├── morphTargets/                  # morph-target geometry files
├── brushes/                       # PNG brush images for BRUSHED renderer
├── background_image/              # optional background images
├── palettes/                      # optional palette JSON files
└── renders/
    ├── stills/
    └── animations/
```

## Key Design Decisions (Current Python Implementation)

- **Single shared polygon library** — both `SplinePolygonTab` and `RegularPolygonTab` reference the same `PolygonSetLibrary` object so additions in either tab are immediately visible in the other.
- **Sentinel file protocol** — reload/capture signals are communicated to the running engine by writing empty files (`.reload`, `.capture_still`, `.capture_video`, `.pause`, `.render_path`) into the project directory. The engine polls for these and deletes them after processing.
- **`shapes.xml` auto-generation** — `SpriteConfigIO.auto_generate_shapes_xml()` re-derives the Scala `shapes.xml` format from `SpriteDef` geo fields on every save, maintaining Scala backward compatibility without storing a redundant data structure.
- **Backward-compatible migration** — on open, `migrate_shapes_into_sprites()` reads legacy `shapes.xml` and patches geo fields into `SpriteDef` records if they are missing.
- **App settings vs project settings** — persistent app-level preferences (recent projects list, engine selection, LoomApp path, default projects directory) are stored in `~/.loom_projects/.loom_editor_settings.json` and never included in `project.xml`.
