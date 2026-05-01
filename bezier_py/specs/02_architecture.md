# Architecture

## Module Layout

```
bezier_py/
├── main.py                         # CLI entry point → BezierApp
├── TECHSPEC.md                     # Coordinate math + XML formats reference
├── ui/
│   ├── bezier_app.py               # BezierApp(QMainWindow) — top-level orchestrator
│   ├── toolbar_panel.py            # ToolbarPanel — mode buttons
│   ├── layer_panel.py              # LayerPanel — layer list + trace controls
│   ├── name_panel.py               # NamePanel — name field + Save/Load buttons
│   └── slider_panel.py             # SliderPanel — scale/rotate gesture sliders
├── canvas/
│   ├── draw_panel.py               # BezierWidget(QWidget) — main canvas
│   ├── render_engine.py            # RenderEngine — all QPainter drawing logic
│   ├── mouse_handler.py            # MouseHandler — mouse event dispatch by mode
│   ├── selection_state.py          # SelectionSubMode, SelectedEdge, SelectionSnapshot
│   ├── curve_fitter.py             # CurveFitter — Schneider freehand fitting
│   ├── knife_tool.py               # KnifeTool — polygon cut along line
│   └── intersect_tool.py           # IntersectTool — concentric → annular quads
├── model/
│   ├── cubic_point.py              # CubicPoint, PointType
│   ├── cubic_curve.py              # CubicCurve
│   ├── cubic_curve_manager.py      # CubicCurveManager — one polygon/open curve
│   ├── polygon_manager.py          # PolygonManager — all polygons for the canvas
│   ├── oval_manager.py             # OvalManager — one ellipse
│   ├── geometry_snapshot.py        # GeometrySnapshot — undo/redo snapshot
│   ├── layer.py                    # Layer
│   └── layer_manager.py            # LayerManager
└── bezier_io/
    ├── polygon_set_xml.py          # polygonSet / openCurveSet read+write
    ├── oval_set_xml.py             # ovalSet read+write
    ├── point_set_xml.py            # pointSet read+write
    ├── layer_set_xml.py            # .layers.xml manifest read+write
    ├── svg_exporter.py             # SVG write
    └── svg_importer.py             # SVG read
```

## Class Hierarchy

```
QMainWindow
└── BezierApp
    ├── BezierWidget (QWidget)              canvas
    │   ├── RenderEngine                   stateless drawing helpers
    │   ├── MouseHandler                   event dispatch
    │   ├── PolygonManager                 committed polygon graph
    │   │   ├── CubicCurveManager[]        one per polygon/open curve
    │   │   │   ├── CubicCurve[]           4-point cubic segments
    │   │   │   │   └── CubicPoint[4]      anchor or control point
    │   │   │   └── anchor_pressures[]     optional tablet pressure data
    │   │   └── WeldRegistry               cross-manager point identity
    │   ├── OvalManager[]                  committed ovals
    │   ├── QPointF[]                      discrete points
    │   └── LayerManager
    │       └── Layer[]
    ├── ToolbarPanel (QWidget)
    ├── LayerPanel (QWidget)
    ├── NamePanel (QWidget)
    └── SliderPanel (QWidget)
```

## Object Graph and Ownership

- `BezierApp` creates all panels and `BezierWidget`, wires signals.
- `BezierWidget` owns `PolygonManager`, `LayerManager`, all ovals, and discrete points.
- `PolygonManager` holds `CubicCurveManager` instances and the shared `WeldRegistry`.
- `CubicCurveManager` holds `CubicCurve` instances; each curve holds exactly 4 `CubicPoint` references. Adjacent curves **share** endpoint `CubicPoint` objects — moving one shared anchor moves both curves simultaneously.
- `RenderEngine` is stateless — all drawing methods are `@staticmethod`.
- `MouseHandler` holds a reference to `BezierWidget` and delegates back to it for state mutation.

## Signal Wiring

| Emitter | Signal | Connected to |
|---|---|---|
| `BezierWidget` | `modified` | `BezierApp._on_canvas_modified` (updates window title) |
| `BezierWidget` | `layer_changed` | `LayerPanel.refresh` |
| `BezierWidget` | `mode_changed` | `ToolbarPanel._sync_buttons` |
| `ToolbarPanel` | `mode_changed(str)` | `BezierWidget._set_mode` |
| `LayerPanel` | `layer_selected(int)` | `BezierWidget.set_active_layer` |
| `LayerPanel` | `layer_visibility_changed(int, bool)` | `BezierWidget.set_layer_visible` |
| `LayerPanel` | `layer_created` | `BezierWidget.add_layer` |
| `LayerPanel` | `layer_deleted(int)` | `BezierWidget.delete_layer` |
| `LayerPanel` | `layer_renamed(int, str)` | `BezierWidget.rename_layer` |
| `LayerPanel` | `layer_duplicated(int)` | `BezierWidget.duplicate_layer` |
| `LayerPanel` | `layer_moved_up(int)` / `layer_moved_down(int)` | `BezierWidget.move_layer_up/down` |
| `LayerPanel` | `trace_scale_changed(float)` | `BezierWidget.set_trace_scale` |
| `LayerPanel` | `trace_alpha_changed(float)` | `BezierWidget.set_trace_alpha` |
| `LayerPanel` | `trace_visible_changed(bool)` | `BezierWidget.set_trace_visible` |
| `NamePanel` | `save_requested` | `BezierApp._on_save` |
| `NamePanel` | `load_requested` | `BezierApp._load_file` |
| `SliderPanel` | `scale_changed(float, str, str)` | `BezierWidget.apply_scale` |
| `SliderPanel` | `rotate_changed(float, str)` | `BezierWidget.apply_rotation` |
| `SliderPanel` | `transform_committed` | `BezierWidget._push_undo` |

## Render Loop

```
QTimer(20 ms) → BezierWidget.update() → paintEvent()
    → _draw_to_buffer(QPainter on QImage)
        → RenderEngine.draw_background()
        → RenderEngine.draw_trace_image()   [if trace layer visible]
        → For each layer (inactive layers at opacity 0.2):
            → RenderEngine.draw_manager() per polygon
            → RenderEngine.draw_ovals()
        → RenderEngine.draw_in_progress()  [active drawing manager]
        → RenderEngine.draw_edge_highlights()
        → RenderEngine.draw_point_highlights()
        → Mode overlays (rubber band, knife line, freehand preview, mesh overlay)
    → QPainter on widget → drawImage(buffer)
```
