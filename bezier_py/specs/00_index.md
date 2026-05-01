# Bezier Py — Specification Index

Technical specifications for the Python/PySide6 Bezier curve editor (`bezier_py`). These specs document the application as it exists, to serve as the definitive reference for the Swift reimplementation that will unify Bezier, the Loom Parameter Editor, and the Swift Loom Engine into a single native macOS/iPadOS application.

## Spec Files

| # | File | Contents |
|---|---|---|
| 01 | [01_overview.md](01_overview.md) | Purpose, technology stack, CLI contract, Java origins, Loom integration protocol |
| 02 | [02_architecture.md](02_architecture.md) | Module layout, class hierarchy, object graph, signal wiring |
| 03 | [03_coordinate_system.md](03_coordinate_system.md) | Canvas/grid/XML coordinate spaces, normalisation pipeline, coordinate math |
| 04 | [04_data_model.md](04_data_model.md) | All model classes: CubicPoint, CubicCurve, CubicCurveManager, OvalManager, GeometrySnapshot |
| 05 | [05_layer_system.md](05_layer_system.md) | Layer, LayerManager — geometry and trace layers, identity, ordering |
| 06 | [06_canvas_and_rendering.md](06_canvas_and_rendering.md) | BezierWidget, RenderEngine, off-screen buffer, draw pipeline, all visual elements |
| 07 | [07_drawing_modes.md](07_drawing_modes.md) | All 9+ mutually exclusive drawing/editing modes and their interaction logic |
| 08 | [08_ui_panels.md](08_ui_panels.md) | ToolbarPanel, LayerPanel, NamePanel, SliderPanel — layout, signals, behaviour |
| 09 | [09_tools.md](09_tools.md) | CurveFitter (Schneider), KnifeTool, IntersectTool, WeldRegistry |
| 10 | [10_selection_system.md](10_selection_system.md) | Selection types, sub-modes, undo stack, selection history |
| 11 | [11_file_io.md](11_file_io.md) | All XML formats (polygonSet, openCurveSet, ovalSet, pointSet, layerSet), SVG export/import |
| 12 | [12_loom_integration.md](12_loom_integration.md) | Subprocess launch contract, DOCTYPE protocol, save-dir convention, auto-save |

## Scope

These specs cover the **current Python implementation** only. They intentionally do not spec:
- Planned GUI redesigns — those are for a separate Swift spec series
- The Scala Loom engine internals
- The Loom Parameter Editor — documented separately in `loom_engine/loom_parameter_editor/specs/`

## Relationship to Loom Parameter Editor

The LPE launches bezier_py as a subprocess and reads the XML files it produces. The critical interface contracts are:
- CLI argument protocol: `--save-dir`, `--load`, `--name`, mode flags
- DOCTYPE header: LPE adds `<!DOCTYPE polygonSet SYSTEM "polygonSet.dtd">` to saved files before feeding them to the Scala engine; bezier_py writes it natively
- File naming: the LPE expects `<name>.poly.xml` in the project's `polygonSets/` directory
