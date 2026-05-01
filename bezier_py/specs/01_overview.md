# Overview

**Source root:** `bezier_py/`  
**Entry point:** `main.py`  
**Technology:** Python 3.9+ · PySide6 / Qt 6 · standard library only (no lxml, no numpy)

## Purpose

Bezier Py is a canvas-based cubic Bézier curve editor. It lets the user draw, edit, and export closed polygons, open curves, ovals, and point sets. The geometry it produces is consumed by the Loom engine as shape input for algorithmic drawing.

The application is ported from a Java application (`CubicCurveFrame`, `BezierDrawPanel`, etc.). The Java class→Python module mapping is preserved in `bezier_py/TECHSPEC.md`.

## Technology Stack

| Concern | Library / API |
|---|---|
| UI framework | PySide6 (Qt 6) |
| Rendering | QPainter on a QImage off-screen buffer |
| XML read/write | `xml.etree.ElementTree` (stdlib) |
| SVG import/parse | `xml.etree.ElementTree` + regex |
| Curve fitting | Schneider algorithm (pure Python, `canvas/curve_fitter.py`) |
| Timer | `QTimer` 20 ms for canvas refresh |

## CLI Contract

```
python main.py --save-dir <path> [--load <file>] [--name <name>] [mode flags]
```

### Required argument

| Argument | Description |
|---|---|
| `--save-dir <path>` | Directory where saved files are written. Created if absent. |

### Optional arguments

| Argument | Description |
|---|---|
| `--load <file>` | Path to an XML file to load on startup. Root element determines file type. |
| `--name <name>` | Preset name shown in the NamePanel. Populates the name field on startup. |
| `--open-curve` | Start in open-curve drawing mode. |
| `--oval` | Start in oval creation mode. |
| `--point` | Start in point-placement mode. |

### Dispatch on `--load`

The root XML tag determines how the file is loaded:

| Root tag | Handler | Result |
|---|---|---|
| `polygonSet` | `_load_file` → `read_polygon_set` | Closed or open polygons loaded into layer system |
| `openCurveSet` | same | Open curves |
| `ovalSet` | `_load_file` → `read_oval_set` | Oval list |
| `pointSet` | `_load_file` → `read_point_set` | Discrete point list |
| `layerSet` | `_load_file` → `_load_layer_set` | Multi-layer rebuild |

## Window

`BezierApp(QMainWindow)` is the top-level window. It has no fixed minimum size. The default geometry is set by Qt.

Window title: `"Bezier"` (unchanged throughout the session).

## Auto-Save on Close

`closeEvent()` in `BezierApp` checks whether any geometry exists (committed managers, ovals, or discrete points). If content is present and a save-dir is set, it auto-saves using the same dispatch as the manual Save command, then calls `event.accept()`.

If no content exists, the window closes without saving.

## Origins (Java Port)

The application is a port of a Java Swing application. Key original class → Python mapping:

| Java class | Python equivalent |
|---|---|
| `CubicCurveFrame` | `BezierApp` |
| `BezierDrawPanel` | `BezierWidget` (+ `RenderEngine`, `MouseHandler`) |
| `CubicPoint` | `model/cubic_point.py` |
| `CubicCurve` | `model/cubic_curve.py` |
| `CubicCurveManager` | `model/cubic_curve_manager.py` |
| `PolygonManager` | `model/polygon_manager.py` |
| `WeldRegistry` | `model/weld_registry.py` |
| `CurveFitter` | `canvas/curve_fitter.py` |
| `BezierKnifeTool` | `canvas/knife_tool.py` |
| `BezierIntersectTool` | `canvas/intersect_tool.py` |
| `PolygonSetXml` | `bezier_io/polygon_set_xml.py` |
| `OvalSetXml` | `bezier_io/oval_set_xml.py` |
| `PointSetXml` | `bezier_io/point_set_xml.py` |
| `LayerSetXml` | `bezier_io/layer_set_xml.py` |
| `BezierSvgExporter` | `bezier_io/svg_exporter.py` |
| `BezierSvgImporter` | `bezier_io/svg_importer.py` |
| `BezierIntersectTool` | `canvas/intersect_tool.py` |
| `GeometrySnapshot` | `model/geometry_snapshot.py` |
