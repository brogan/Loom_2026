# Bezier Python — Technical Specification

## 1. Coordinate System

### Internal buffer
- `WIDTH = HEIGHT = 1040` px — fixed QImage buffer
- `GRIDWIDTH = GRIDHEIGHT = 1000` — usable drawing grid
- `EDGE_OFFSET = 20` — gap between buffer edge and grid edge
- Grid occupies canvas pixels **20–1020** in both axes
- Canvas centre: `(520, 520)`

### Coordinate flow (save → XML)
| Step | Formula | Example (centre point) |
|---|---|---|
| Canvas pixel | `x` | 520 |
| Normalise | `x / GRIDWIDTH - 0.5` | 0.02 |
| Adjust offset | `normalised - EDGE_OFFSET/GRIDWIDTH` | 0.00 |
| Simplify | `round(adjusted * 100) / 100` | 0.0 |
| XML value | written as `x="0.0"` | `x="0.0"` |

XML range: **−0.5 to +0.5** (centre = 0.0)

### Coordinate flow (XML → canvas)
| Step | Formula | Example |
|---|---|---|
| Read XML | `x` | 0.0 |
| Add offset back | `x + EDGE_OFFSET/GRIDWIDTH` | 0.02 |
| Denormalise | `val * GRIDWIDTH + GRIDWIDTH/2` | 520 |

### scaleMouse
```python
def scale_mouse(event) -> QPointF:
    return QPointF(
        event.position().x() * WIDTH / widget.width(),
        event.position().y() * HEIGHT / widget.height()
    )
```

---

## 2. XML Formats

### polygonSet (closed + open polygons)
```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<!DOCTYPE polygonSet SYSTEM "polygonSet.dtd">
<polygonSet>
    <name>myshape</name>
    <shapeType>CUBIC_CURVE</shapeType>
    <polygon>                          <!-- isClosed="false" for open curves -->
        <curve>
            <point x="-0.27" y="-0.27"/>   <!-- anchor[0] -->
            <point x="-0.23" y="-0.28"/>   <!-- control[1] -->
            <point x="-0.19" y="-0.31"/>   <!-- control[2] -->
            <point x="-0.16" y="-0.3"/>    <!-- anchor[3] -->
        </curve>
        <!-- last curve in closed polygon = synthetic closing curve -->
    </polygon>
    <scaleX>1.0</scaleX>
    <scaleY>1.0</scaleY>
    <rotationAngle>0.0</rotationAngle>
    <transX>0.0</transX>
    <transY>0.0</transY>
</polygonSet>
```

- DOCTYPE header: **required** for polygonSet
- `isClosed="false"` attribute on `<polygon>` for open curves (omit for closed)
- Pressure attribute: `pressure="0.788"` on anchor `<point>` elements (optional)
- Closed polygon: last curve is a synthetic closing curve linking last anchor to first

### openCurveSet (open curves only — no DOCTYPE)
```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<openCurveSet>
    <name>face</name>
    <shapeType>CUBIC_CURVE</shapeType>
    <openCurve>
        <curve>
            <point x="-0.27" y="-0.27" pressure="0.050"/>
            ...
        </curve>
    </openCurve>
</openCurveSet>
```

### ovalSet (no DOCTYPE)
```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<ovalSet>
    <name>myovals</name>
    <oval cx="0.0" cy="0.0" rx="0.25" ry="0.15"/>
</ovalSet>
```

### pointSet (no DOCTYPE)
```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<pointSet>
    <name>mypoints</name>
    <point x="0.0" y="-0.1" pressure="1.0"/>
</pointSet>
```

### layerSet manifest (`.layers.xml`)
```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<layerSet>
    <name>myshape</name>
    <layer id="1" name="Background" visible="true" file="myshape_Background.xml"/>
    <layer id="2" name="Foreground" visible="true" file="myshape_Foreground.xml"/>
</layerSet>
```

---

## 3. Graphics2D → QPainter equivalents

| Java | Python |
|---|---|
| `Graphics2D g2d = img.createGraphics()` | `p = QPainter(dBuffer)` |
| `g2d.setRenderingHint(ANTIALIASING, ON)` | `p.setRenderHint(QPainter.RenderHint.Antialiasing)` |
| `new GeneralPath(); path.moveTo(); path.curveTo()` | `QPainterPath(); path.moveTo(); path.cubicTo()` |
| `g2d.draw(path)` | `p.drawPath(path)` |
| `g2d.fill(path)` | `p.fillPath(path, brush)` |
| `g2d.setColor(new Color(r,g,b,a))` | `p.setPen(QColor(r,g,b,a))` |
| `g2d.setStroke(new BasicStroke(w))` | `pen = QPen(color, w); p.setPen(pen)` |
| `g2d.fillOval(x,y,w,h)` | `p.setBrush(color); p.drawEllipse(QRectF(x,y,w,h))` |
| `AlphaComposite` for dimming | `p.setOpacity(0.2)` |
| `paintComponent: g.drawImage(buf, 0,0,W,H)` | `paintEvent: p.drawImage(self.rect(), self.dBuffer)` |
| `javax.swing.Timer(20ms)` | `QTimer(20ms).timeout.connect(self.update)` |

---

## 4. Python class ↔ Java class

| Python | Java |
|---|---|
| `model.cubic_point.CubicPoint` | `CubicPoint` |
| `model.cubic_curve.CubicCurve` | `CubicCurve` |
| `model.cubic_curve_manager.CubicCurveManager` | `CubicCurveManager` |
| `model.polygon_manager.PolygonManager` | `CubicCurvePolygonManager` |
| `model.oval_manager.OvalManager` | `OvalManager` |
| `model.layer.Layer` | `Layer` |
| `model.layer_manager.LayerManager` | `LayerManager` |
| `model.weld_registry.WeldRegistry` | `WeldRegistry` |
| `model.geometry_snapshot.GeometrySnapshot` | `GeometrySnapshot` |
| `canvas.draw_panel.BezierWidget` | `BezierDrawPanel` |
| `canvas.render_engine.RenderEngine` | (methods inside BezierDrawPanel) |
| `canvas.mouse_handler.MouseHandler` | (mouse methods inside BezierDrawPanel) |
| `ui.bezier_app.BezierApp` | `CubicCurveFrame` |
| `ui.toolbar_panel.ToolbarPanel` | `BezierToolBarPanel` |
| `ui.layer_panel.LayerPanel` | `LayerPanel` |
| `ui.name_panel.NamePanel` | (parts of CubicCurvePanel) |
| `io.polygon_set_xml.PolygonSetXml` | `PolygonSetXml` |

---

## 5. CLI Contract

```
python main.py --save-dir <dir> [--load <file>] [--name <name>]
```

- `--save-dir`: directory where XML files are written on save/close
- `--load`: optional path to an existing XML file to open
- `--name`: optional initial name for the shape

On close: writes `{name}.xml` (polygonSet) to `--save-dir`.
The Loom editor detects new/modified files in `--save-dir` after the process exits.

### Loom editor launch pattern
```python
BEZIER_PY = "/Users/broganbunt/Loom_2026/bezier_py/main.py"
PYTHON = "/Users/broganbunt/Loom_2026/loom_parameter_editor/.venv/bin/python"
process.start(PYTHON, [BEZIER_PY, "--save-dir", dir, "--load", file])
```

---

## 6. Loom editor integration protocol

1. Loom editor adds `<?xml...><!DOCTYPE...>` headers before calling Bezier (for polygonSet)
2. Bezier loads file, user edits, saves
3. Loom editor strips headers from all `.xml` files in polygonSets dir on close
4. For `openCurveSet`: no headers added/stripped (no DOCTYPE)
5. For `layerSet` (`.layers.xml`): Loom detects root element, calls bundle loading path
