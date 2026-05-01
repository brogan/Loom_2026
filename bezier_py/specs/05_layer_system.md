# Layer System

**Source:** `model/layer.py`, `model/layer_manager.py`

---

## `Layer`

```python
class Layer:
    id:                int       # unique, auto-incremented class var _next_id
    name:              str
    visible:           bool      # default True
    is_trace:          bool      # False for geometry layers
    # Trace-layer fields (only meaningful when is_trace=True):
    trace_image_path:  str | None
    trace_image:       QImage | None    # runtime only, not serialised
    trace_x:           float     # canvas px, default 520.0 (centre)
    trace_y:           float     # canvas px, default 520.0 (centre)
    trace_scale:       float     # default 1.0, range 0.10–4.00
    trace_alpha:       float     # default 1.0, range 0.00–1.00
```

Layer IDs are assigned at creation by incrementing `Layer._next_id`. IDs are not reused within a session.

Geometry layers have `is_trace = False`. Each `CubicCurveManager` and `OvalManager` carries a `layer_id` field that links them to their owning layer.

The trace layer is a special singleton layer at list index 0. It holds a reference image for tracing and is always displayed at its configured alpha regardless of which geometry layer is active.

---

## `LayerManager`

```python
class LayerManager:
    layers:         list[Layer]    # trace layer (if any) is at index 0
    active_layer_id: int
```

On construction, a single geometry layer named `"Layer 1"` is created automatically. `active_layer_id` is set to its ID.

### Geometry vs Trace Layers

```python
def geometry_layers(self) -> list[Layer]:
    return [l for l in self.layers if not l.is_trace]

def get_trace_layer(self) -> Layer | None:
    return next((l for l in self.layers if l.is_trace), None)
```

### Key methods

| Method | Description |
|---|---|
| `create_trace_layer()` | Inserts a trace layer at index 0, replacing any existing trace layer |
| `get_layer_by_id(id)` | Returns `Layer` or `None` |
| `add_layer(name)` | Append a new geometry layer; return it |
| `delete_layer(id)` | Remove layer; guards against deleting the last geometry layer |
| `rename_layer(id, name)` | Rename by ID |
| `duplicate_layer(id)` | Deep-copy all polygons on that layer into a new layer |
| `move_layer_up(id)` | Swap layer upward in the display order |
| `move_layer_down(id)` | Swap layer downward |

---

## Display Order

`LayerPanel` displays layers in **reverse** list order (newest layer appears at the top of the UI). The active layer is shown in bold. Layer visibility is toggled per-row.

Inactive geometry layers are rendered at `opacity 0.2` by `BezierWidget._draw_to_buffer`. The active layer renders at full opacity.

---

## Trace Layer

The trace layer is a special singleton that provides a reference image background for tracing. It is created via `File → Load Trace Image`. Controls for the trace layer are displayed in a collapsible `TraceLayerWidget` at the bottom of `LayerPanel`.

### TraceLayerWidget controls

| Control | Range | Default |
|---|---|---|
| Scale | 0.10 – 4.00× (QDoubleSpinBox, step 0.05) | 1.00 |
| Alpha | 0.00 – 1.00 (QDoubleSpinBox, step 0.05) | 1.00 |
| Visible | checkbox | True |

The trace image can also be repositioned by dragging it on the canvas while in polygon selection mode (right-click drag of the trace layer).

### Trace Layer in Save/Load

The trace layer is **not** saved in single-file polygon saves. In multi-layer saves (`.layers.xml`), the trace layer metadata (`image_path`, `x`, `y`, `scale`, `alpha`, `visible`) is written as a `<traceLayer>` element in the manifest. The image file itself is referenced by (relative) path and is not copied.

On load, the image is reloaded from the stored path and rendered at the saved scale/alpha/position.

---

## Layer Duplication

`LayerManager.duplicate_layer(id)` creates a new `Layer` with a new unique ID and `copy()` of each `CubicCurveManager` whose `layer_id` matches. The deep copy preserves all geometry but does not preserve weld links to geometry in other layers.
