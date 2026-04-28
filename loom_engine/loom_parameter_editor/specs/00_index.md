# Loom Parameter Editor — Specification Index

Technical specifications for the current Python/PySide6 Loom Parameter Editor (LPE). These specs document the editor as it exists, to serve as the definitive reference for the Swift reimplementation that will unify LPE, Bezier, and the Loom engine into a single native macOS/iPadOS application.

## Spec Files

| # | File | Contents |
|---|---|---|
| 01 | [01_overview.md](01_overview.md) | Purpose, technology stack, architecture, workflow, engine selection, sentinel file protocol, key design decisions |
| 02 | [02_project_and_file_structure.md](02_project_and_file_structure.md) | Project manifest XML, directory layout, domain file registry, save sequence, Save As, Open Project dialog |
| 03 | [03_global_tab.md](03_global_tab.md) | Global configuration tab: canvas, display, engine, 3D, serial; GlobalConfig model; split ownership pattern |
| 04 | [04_geometry_tab.md](04_geometry_tab.md) | Geometry container tab and all six sub-tabs: Spline Polygons, Regular Polygons, Curves, Points, Ovals, Bitmap Polygons |
| 05 | [05_subdivision_tab.md](05_subdivision_tab.md) | Subdivision tab: params tree, all SubdivisionParams fields, SubdivisionType enum, VisibilityRule enum, TransformSet/PTP system, Bake feature |
| 06 | [06_sprites_tab.md](06_sprites_tab.md) | Sprites tab: sprite tree, geometry source types, position/animation/keyframe/morph editors, SpritePreviewWidget, cross-tab references |
| 07 | [07_rendering_tab.md](07_rendering_tab.md) | Rendering tab: RendererSetLibrary tree, RendererSet properties, Renderer properties, all RenderModes, change editors, BrushConfig, StencilConfig, MeanderConfig |
| 08 | [08_run_tab.md](08_run_tab.md) | Run tab: drawing settings, process controls, sentinel files, Scala/Swift launch commands, capture controls, keyboard shortcuts |
| 09 | [09_data_models.md](09_data_models.md) | All data model classes with field names, types, and defaults |
| 10 | [10_file_io.md](10_file_io.md) | XML serialisation format for all config files, encoding conventions, backward-compat migration |
| 11 | [11_shared_widgets.md](11_shared_widgets.md) | All shared UI widgets: ColorPicker, PaletteEditor, SizePaletteEditor, EnumDropdown, RendererTree, BrushEditor, StencilEditor, BitmapPolygonDialog, SpritePreview, ChangeEditors |
| 12 | [12_app_settings.md](12_app_settings.md) | AppSettings: persistent editor preferences, JSON format, lifecycle |

## Scope

These specs cover the **current Python implementation** only. They intentionally do not spec:
- Planned GUI redesigns (drag-and-drop, etc.) — those are for a separate Swift spec series
- The Scala Loom engine internals — covered by `loom_engine/spec/`
- The Bezier editor — to be documented separately

## Relationship to Scala Engine

The editor produces XML that the Scala engine reads. The critical interface contracts are:
- `constants.py` enums must match `org.loom.scene.Renderer` constants exactly
- `shapes.xml` auto-generation must match `org.loom.scaffold.Config` expectations
- Sentinel file names (`.reload`, `.capture_still`, `.capture_video`, `.pause`, `.render_path`) must match the engine's polling loop
