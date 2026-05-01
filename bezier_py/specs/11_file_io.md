# File I/O

All I/O modules live in `bezier_io/`. They use Python's stdlib `xml.etree.ElementTree`.

---

## File Types

| Extension | Root element | Module | Encoding |
|---|---|---|---|
| `.poly.xml` | `<polygonSet>` | `polygon_set_xml.py` | ISO-8859-1 with DOCTYPE |
| `.curve.xml` | `<openCurveSet>` | `polygon_set_xml.py` | ISO-8859-1 with DOCTYPE |
| `.oval.xml` | `<ovalSet>` | `oval_set_xml.py` | UTF-8, no DOCTYPE |
| `.points.xml` | `<pointSet>` | `point_set_xml.py` | ISO-8859-1, no DOCTYPE |
| `.layers.xml` | `<layerSet>` | `layer_set_xml.py` | UTF-8, no DOCTYPE |
| `.svg` | `<svg>` | `svg_exporter.py` / `svg_importer.py` | UTF-8 |

---

## `polygon_set_xml.py` — PolygonSet and OpenCurveSet

### Save pipeline

```
canvas px → normalise (÷1000 − 0.5) → adjust offset (− 0.02) → simplify (2dp) → XML
```

Combined: `round(round((canvas/1000 − 0.5 − 0.02) × 100)) / 100`

### Load pipeline

```
XML → add offset (+0.02) → denormalise (×1000 + 500) → canvas px
```

### XML format

```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<!DOCTYPE polygonSet SYSTEM "polygonSet.dtd">
<polygonSet>
    <name>MyShape</name>
    <shapeType>CUBIC_CURVE</shapeType>
    <polygon>
        <curve>
            <point x="-0.04" y="-0.04"/>
            <point x="-0.04" y="0.12"/>
            <point x="0.12" y="0.12"/>
            <point x="0.12" y="-0.04"/>
        </curve>
        <!-- one <curve> per CubicCurve, including the synthetic closing curve -->
    </polygon>
    <!-- one <polygon> per CubicCurveManager -->
    <scaleX>1.0</scaleX>
    <scaleY>1.0</scaleY>
    <rotationAngle>0.0</rotationAngle>
    <transX>0.0</transX>
    <transY>0.0</transY>
</polygonSet>
```

For open curves the root tag is `<openCurveSet>` and each polygon has `<polygon isClosed="false">`.

### Pressure attribute

If a point is an anchor (`index 0` or `3` within a curve) and its pressure differs from `1.0`, it is written as:
```xml
<point x="0.12" y="-0.04" pressure="0.753"/>
```

On load, pressure values are read and stored in `CubicCurveManager.anchor_pressures`. If all pressures are `1.0`, the pressures list is set to `None`.

### DOCTYPE handling

bezier_py writes the DOCTYPE natively. On load, any `<!DOCTYPE ...>` declaration is stripped via regex before passing to `ElementTree` (which does not handle DOCTYPE).

The `_strip_doctype` function also accepts files without DOCTYPE (e.g., those written by older versions).

### Cross-format loading

`read_polygon_set` also accepts `<openCurveSet>` root elements — the same function handles both closed and open curve files.

---

## `oval_set_xml.py` — OvalSet

### Coordinate pipeline

```
Save centre:  norm = (canvas_px − EDGE) / GRID − 0.5
Save radius:  norm_r = radius / GRID
Load centre:  canvas_px = (norm + 0.5) * GRID + EDGE
Load radius:  radius = norm_r * GRID
```

### XML format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ovalSet>
    <name>MyOvals</name>
    <oval cx="-0.1000" cy="-0.1000" rx="0.1000" ry="0.0500"/>
</ovalSet>
```

No DOCTYPE. Floating-point values formatted to 4 decimal places.

---

## `point_set_xml.py` — PointSet

Same 2 dp coordinate pipeline as polygonSet:

```
Save:  adj = canvas_px/1000 − 0.5 − 0.02;  xml = round(round(adj×100))/100
Load:  canvas_px = (xml + 0.02) × 1000 + 500
```

### XML format

```xml
<pointSet>
    <name>MyPoints</name>
    <point x="-0.04" y="-0.04"/>
    <point x="0.12" y="0.12" pressure="0.800"/>
    <scaleX>1.0</scaleX>
    <scaleY>1.0</scaleY>
    <rotationAngle>0.0</rotationAngle>
    <transX>0.5</transX>
    <transY>0.5</transY>
</pointSet>
```

No DOCTYPE. ISO-8859-1 encoding (no XML declaration written). Transform elements are always written with default values. `transX` and `transY` default to `0.5` (matches Java convention for point sets).

---

## `layer_set_xml.py` — LayerSet Manifest

### File naming

The overall name and each layer name are converted to a filename-safe string (`_to_filename`):
- Lowercase
- Spaces → `_`
- Non-alphanumeric/dash/underscore characters stripped

The manifest is written as `{overall_fn}.layers.xml`. Each layer's polygon data is written as `{overall_fn}_{layer_fn}.xml`.

### Manifest format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<layerSet>
  <overallName>My Shape</overallName>
  <layer>
    <name>Layer 1</name>
    <file>my_shape_layer_1.xml</file>
    <visible>true</visible>
  </layer>
  <layer>
    <name>Detail</name>
    <file>my_shape_detail.xml</file>
    <visible>true</visible>
  </layer>
  <!-- optional — only present when a trace layer exists -->
  <traceLayer>
    <visible>true</visible>
    <imagePath>../tracing_images/photo.png</imagePath>
    <x>520.0000</x>
    <y>520.0000</y>
    <scale>1.0000</scale>
    <alpha>0.5000</alpha>
  </traceLayer>
</layerSet>
```

The `<traceLayer>` element is written only when a trace layer exists. `imagePath` is stored relative to `save_dir` where possible (may be absolute on Windows when on a different drive).

### Read API

```python
def read_layer_set(manifest_path) -> list[dict]
    # [{'name': str, 'file': str, 'visible': bool}, ...]

def read_trace_layer_info(manifest_path) -> dict | None
    # {'visible': bool, 'image_path': str, 'x': float, 'y': float,
    #  'scale': float, 'alpha': float}

def peek_overall_name(manifest_path) -> str
```

---

## SVG Export (`svg_exporter.py`)

### Coordinate transform

```
svg_coord = canvas_px − EDGE_OFFSET (20)
```

SVG viewport: `1000 × 1000` user units, `viewBox="0 0 1000 1000"`.

### Format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">
  <title>MyShape</title>
  <path d="M 500.0000,500.0000 C ..." fill="none" stroke="#000000" stroke-width="1"/>
</svg>
```

Each committed `CubicCurveManager` becomes one `<path>`. Closed paths end with `Z`.

### Auto-export

SVG is auto-exported alongside every polygon XML save. When saving a multi-layer file, one SVG is written per layer plus one for the overall set. SVGs go in `{save_dir}/` (same directory as the XML).

### API

```python
def save(polygon_manager, svg_dir_path, name) -> None
def save_managers(managers, svg_dir_path, name) -> None
```

---

## SVG Import (`svg_importer.py`)

### Supported path commands

| Command | Handled |
|---|---|
| `M`, `m` | Move to (absolute/relative) |
| `C`, `c` | Cubic Bézier (absolute/relative) |
| `L`, `l` | Line segment (absolute/relative) — converted to cubic |
| `Q`, `q` | Quadratic Bézier (absolute/relative) — degree-elevated to cubic |
| `Z`, `z` | Close subpath |
| `H`, `V`, `S`, `T`, `A` | Silently skipped |

### Coordinate transform

```
canvas_x = (svg_x − vb_x) / vb_w × GRID_SIZE + EDGE_OFFSET
```

Where `vb_x, vb_y, vb_w, vb_h` come from the SVG `viewBox`. Falls back to `width`/`height` attributes if no viewBox.

### Result

Each `<path>` element becomes one closed `CubicCurveManager` added to `polygon_manager`. A redundant final closing segment (when the last anchor matches the first) is removed before committing.

### API

```python
def import_svg(svg_file_path, polygon_manager, layer_id=0) -> int
    # Returns count of imported polygons
```

---

## `BezierApp` Save Dispatch (`ui/bezier_app.py`)

`BezierApp._on_save()` dispatches based on current content:

```python
def _on_save(self):
    name = self._name_panel.get_name()
    if self._layer_manager has > 1 geometry layer:
        # Multi-layer: save manifest + per-layer polygonSet files + SVGs
        write_layer_set(save_dir, name, layer_manager, polygon_manager)
    else:
        # Single layer: dispatch by geometry type
        if discrete_points exist → write_point_set(...)
        elif ovals exist → write_oval_set(...)
        elif open curves exist → write_polygon_set(...) with openCurveSet root
        else → write_polygon_set(...)  # default: closed polygon set
    # Auto-export SVG
    svg_exporter.save(polygon_manager, save_dir, name)
```

When in multi-layer mode, `write_layer_set` writes one polygon file per geometry layer plus the `.layers.xml` manifest. Per-layer SVG files are also written.

---

## `BezierApp` Load Dispatch

`BezierApp._load_file(path)` determines file type by reading the XML root element:

```python
root_tag = peek_root_tag(path)
if root_tag == 'layerSet':
    _load_layer_set(path)
elif root_tag in ('polygonSet', 'openCurveSet'):
    _load_polygon(path)
elif root_tag == 'ovalSet':
    _load_ovals(path)
elif root_tag == 'pointSet':
    _load_points(path)
```

`_load_layer_set` fully rebuilds the `LayerManager` from the manifest: creates a `Layer` per manifest entry, loads each per-layer polygon file into that layer's managers, and restores trace layer metadata.
