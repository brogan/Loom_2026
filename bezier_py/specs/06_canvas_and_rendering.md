# Canvas and Rendering

**Source:** `canvas/draw_panel.py`, `canvas/render_engine.py`

---

## `BezierWidget` (`canvas/draw_panel.py`)

The main canvas widget. Inherits `QWidget`.

### Constants

| Constant | Value |
|---|---|
| `WIDTH` / `HEIGHT` | 1040 |
| `GRIDWIDTH` / `GRIDHEIGHT` | 1000 |
| `EDGE_OFFSET` | 20 |

### Signals

| Signal | Type | Description |
|---|---|---|
| `modified` | (no args) | Emitted when geometry changes |
| `layer_changed` | (no args) | Emitted when active layer or layer list changes |
| `mode_changed` | str | Emitted when the editing mode changes; value is the mode name |

### State fields

```python
# Mode flags (mutually exclusive; at most one True at a time)
point_mode:              bool
oval_mode:               bool
polygon_selection_mode:  bool
edge_selection_mode:     bool
point_selection_mode:    bool
open_curve_selection_mode: bool
freehand_mode:           bool
knife_mode:              bool
mesh_build_mode:         bool

# Reference / trace image
_reference_image:        QImage | None    # background overlay (not saved)
_show_reference_image:   bool

# Off-screen render buffer
_buffer:                 QImage           # ARGB32, 1040×1040

# Undo/redo
_undo_stack:             deque            # maxlen=20, GeometrySnapshot
_redo_stack:             deque            # maxlen=20, GeometrySnapshot

# Active drawing
_polygon_manager:        PolygonManager
_layer_manager:          LayerManager
_ovals:                  list[OvalManager]
_discrete_points:        list[QPointF]
_discrete_pressures:     list[float]

# Tool state
_renderer:               RenderEngine
_mouse_handler:          MouseHandler
_freehand_pts:           list[QPointF]   # accumulation during freehand stroke
_freehand_pressures:     list[float]
_knife_start:            QPointF | None
_mesh_sequence:          list[QPointF]   # point sequence for mesh build mode
```

### Render Loop

A `QTimer` fires every 20 ms and calls `self.update()`. `paintEvent` calls `_draw_to_buffer()` then blits the buffer to the widget.

```python
def paintEvent(self, event):
    self._draw_to_buffer()
    painter = QPainter(self)
    painter.drawImage(0, 0, self._buffer)
```

`_draw_to_buffer()` creates a `QPainter` on the `QImage` buffer and delegates all drawing to `RenderEngine` methods.

### Layer Opacity Rule

When drawing committed managers:
- Active layer's managers: `opacity = 1.0`
- Inactive layers' managers: `opacity = 0.2`

Trace layer is rendered at `layer.trace_alpha` regardless of which geometry layer is active.

---

## `RenderEngine` (`canvas/render_engine.py`)

Stateless helper class. All methods are `@staticmethod`.

### Colour Palette

| Constant | Colour | Use |
|---|---|---|
| `COL_BACKGROUND` | `(255,255,255)` | Canvas fill |
| `COL_GRID` | `(200,200,200)` | Fine grid lines |
| `COL_AXIS_ODD` | `(50,150,200)` | Grid axis odd lines (blue) |
| `COL_AXIS_EVEN` | `(50,200,150)` | Grid axis even lines (teal) |
| `COL_STROKE` | `(0,0,0)` | Curve stroke |
| `COL_HANDLE_LINE` | `(0,50,230)` | Control handle lines |
| `COL_ANCHOR` | `(0,230,50,160)` | Unselected anchor fill |
| `COL_ANCHOR_SEL` | `(230,250,0,220)` | Selected anchor fill |
| `COL_CONTROL` | `(230,50,0,80)` | Unselected control fill |
| `COL_CONTROL_SEL` | `(230,100,0,220)` | Selected control fill |
| `COL_SEL_CLOSED` | `(0,100,255,160)` | Selected closed polygon overlay |
| `COL_SEL_REL` | `(255,140,0,160)` | Selected relational polygon overlay |
| `COL_IN_PROG` | `(80,80,80,200)` | In-progress curve stroke |

### Point Sizes

| Constant | Value |
|---|---|
| `ANCHOR_RADIUS` | 5.0 px |
| `CONTROL_RADIUS` | 4.0 px |
| `GRID_FINE_DIVISIONS` | 100 |
| `GRID_AXES_DIVISIONS` | 20 |

### Methods

#### `draw_background(p, w, h, edge_offset, grid_w, grid_h, show_grid=True)`

1. Fill entire canvas with white.
2. Draw fine grid (100×100 squares, 10 px each) with AA disabled for crisp pixel lines.
3. Draw axis grid (20 divisions, 50 px each) alternating blue/teal.
4. Re-enable AA.

#### `draw_trace_image(p, layer)`

Draw the trace image centred at `(layer.trace_x, layer.trace_y)` scaled by `layer.trace_scale`. Set painter opacity to `layer.trace_alpha`, restore to 1.0 after.

#### `draw_manager(p, mgr, show_handles=True, opacity=1.0)`

1. Build `QPainterPath` from the manager's curves.
2. If open curve with pressure data: draw per-segment strokes with width proportional to average anchor pressures `((p0+p1)*0.5) * 8.0`, minimum 1.0 px.
3. Otherwise: stroke the full path at `2.0 px` black.
4. If `mgr.selected`: overlay a 4 px stroke in blue (discrete) or orange (relational).
5. If `mgr.scoped`: overlay a 2 px yellow dashed stroke.
6. If `show_handles`: call `_draw_handles`.

#### `_draw_handles(p, mgr)`

For each curve: draw blue handle lines from each anchor to its adjacent control, then draw all 4 point ovals.

#### `_draw_point_oval(p, pt)`

Draw a filled circle at `pt.pos` with radius `ANCHOR_RADIUS` (anchor) or `CONTROL_RADIUS` (control). Fill uses selected/unselected colours. Outline: 80% opacity black, 1 px.

#### `draw_in_progress(p, mgr, mouse_pos=None, paused=False)`

Draw the active drawing manager: committed curves so far in grey, handles, and a dashed rubber line from the last placed point to the current mouse position (suppressed if `paused=True`).

#### `draw_edge_highlights(p, mgr)`

Draw highlighted edges by index from the manager's three edge-selection sets:
- `weldable_edge_indices`: purple, 5 px
- `relational_edge_indices`: orange, 4 px
- `discrete_edge_indices`: blue, 4 px

#### `draw_point_highlights(p, mgr)`

Draw 12 px circles over highlighted points:
- `discrete_points`: blue anchors, white controls
- `relational_points`: red anchors, yellow controls

#### `draw_mesh_build_overlay(p, seq, mouse_pos, point_list)`

Mesh build mode overlay:
1. Green connecting lines between sequence points.
2. Dashed ghost closing-edge from last to first (if ≥3 points).
3. Dashed preview line from last sequence point to mouse.
4. Hover ring (pale green) when mouse is within 18 px of an un-sequenced point.
5. Numbered green rings at each sequence position.

#### `draw_knife_line(p, start, end)`

Dashed red line with a perpendicular tick at the start and dot markers at both ends.

#### `draw_freehand_preview(p, pts, pressures=None, first_pt=None, snap_radius=20.0)`

If tablet pressure data is present: draw a variable-width ribbon (`max_half_w = 5.0 px`).  
Otherwise: thin blue polyline.  
Highlight `first_pt` in green when the last drawn point is within `snap_radius` (auto-close imminent), otherwise white.

#### `draw_rubber_band(p, start, end)`

Dashed blue rectangle for drag selection.

#### `draw_ovals(p, ovals)`

For each oval: draw ellipse at canvas-space bounds. Selected ovals use a 4 px blue outline; unselected use 1.5 px black.

#### `draw_discrete_points(p, points, pressures, selected_index)`

For each point: draw a purple filled circle. Radius scales with pressure (`max(3, int(pr * 8))`). Selected point gets an extra yellow outer ring.
