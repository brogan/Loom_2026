# Data Model

All model classes live in `model/`. They operate in canvas pixel space at runtime.

---

## `CubicPoint` (`model/cubic_point.py`)

One control point on a cubic Bézier curve.

```python
class PointType(Enum):
    ANCHOR  = 0
    CONTROL = 1

class CubicPoint:
    pos:          QPointF    # current canvas position (mutable)
    orig_pos:     QPointF    # position at gesture start (for slider-based transforms)
    current_pos:  QPointF    # synonym for orig_pos (historical; kept for compat)
    type:         PointType
    selected:     bool       # True = selected in current selection set
```

### Key methods

| Method | Description |
|---|---|
| `save_current_pos()` | Copies `pos` → `orig_pos` (freeze for upcoming gesture) |
| `set_orig_to_pos()` | Same effect as `save_current_pos` |
| `drag(dx, dy)` | Moves `pos` by delta, also propagates to all weld partners via `WeldRegistry` |

Adjacent curves in a `CubicCurveManager` **share** anchor `CubicPoint` objects. Moving a shared anchor moves both curves.

---

## `CubicCurve` (`model/cubic_curve.py`)

One cubic segment: exactly 4 points in order `[anchor, control, control, anchor]`.

```python
class CubicCurve:
    points: list[CubicPoint | None]   # always length 4; None until populated
```

### Key methods

| Method | Description |
|---|---|
| `set_anchor_first(pt, master=None)` | Set `points[0]`; shares the object if `master` is given |
| `set_anchor_last(pt, master=None)` | Set `points[3]`; shares the object if `master` is given |
| `auto_control_points()` | Place controls at 1/3 and 2/3 between the two anchors |
| `set_control_points_from(other)` | Copy control point positions from another curve |
| `is_complete()` | True when all 4 points are non-None |
| `save_all_current_pos()` | Calls `save_current_pos` on all 4 points |

---

## `CubicCurveManager` (`model/cubic_curve_manager.py`)

One complete polygon or open curve. Owns a list of `CubicCurve` segments.

```python
class CubicCurveManager:
    curves:             list[CubicCurve]
    _current_curve:     CubicCurve          # active drawing curve
    _curve_count:       int
    _point_count:       int
    add_points:         bool                # True while drawing in progress
    is_closed:          bool
    layer_id:           int
    anchor_pressures:   list[float] | None  # per-anchor pressure (tablet); None = uniform
```

### Selection state fields

| Field | Type | Description |
|---|---|---|
| `selected` | bool | Whole-polygon selection |
| `selected_relational` | bool | Selection affects weld partners |
| `scoped` | bool | Highlighted with dashed yellow (knife/intersect scope) |
| `discrete_edge_indices` | set[int] | Blue-highlighted edge indices |
| `relational_edge_indices` | set[int] | Orange-highlighted edge indices |
| `weldable_edge_indices` | set[int] | Purple-highlighted weld-preview edge indices |
| `discrete_points` | set[CubicPoint] | Blue-highlighted points |
| `relational_points` | set[CubicPoint] | Red-highlighted points |

### Drawing state machine (`set_point`)

The `set_point(pt)` method is called on each mouse click during curve drawing. It implements a 4-click state machine per segment:
1. **Click 1:** place first anchor (`points[0]`)
2. **Click 2:** place first control (`points[1]`), auto-place mirrored control
3. **Click 3:** place last control (`points[2]`)
4. **Click 4:** place last anchor (`points[3]`), commit curve, start next segment with shared anchor

### Closing

`close_curve()` adds a synthetic closing segment from the last placed anchor back to the very first anchor (shared point), and sets `is_closed = True`.

`finish_open()` marks `add_points = False`, `is_closed = False`, and clears the in-progress cursor curve.

### Key methods

| Method | Description |
|---|---|
| `set_all_points(flat_pts)` | Load closed polygon from flat `[a,c,c,a, ...]` QPointF list |
| `set_open_points(flat_pts)` | Load open curve from flat QPointF list |
| `get_average_xy()` | Returns centroid QPointF of all anchor points |
| `contains_point(pt)` | True if `pt` is inside the closed path (via `QPainterPath.contains`) |
| `near_open_curve(pt, width)` | True if `pt` is within `width` px of the open curve stroke |
| `distance_to_edge(pt)` | Min distance from `pt` to any edge, via 30-sample parametric sampling |
| `check_for_intersect(pt, radius)` | True if `pt` is within `radius` of any anchor |
| `get_anchor_pressure(i)` | Returns pressure for anchor index `i`, or 1.0 if none |

---

## `PolygonManager` (`model/polygon_manager.py`)

Container for all committed `CubicCurveManager` objects plus the single active drawing manager.

```python
class PolygonManager:
    _layer_manager: LayerManager
    _managers:      list[CubicCurveManager]  # index 0 = active drawing; 1..N = committed
    weld_registry:  WeldRegistry
```

`polygon_count` = `len(_managers) - 1` (excludes the active drawing manager at index 0).

### Key methods

| Method | Description |
|---|---|
| `committed_managers()` | Returns `_managers[1:]` |
| `get_manager(i)` | Returns `_managers[i + 1]` (0-indexed committed list) |
| `get_managers_for_layer(layer_id)` | Filter committed managers by `layer_id` |
| `finish_closed()` | Commits active manager as closed polygon; starts new drawing manager |
| `finish_open()` | Commits active manager as open curve |
| `normalise_point(canvas_pt)` | Canvas px → normalised QPointF |
| `denormalise_point(norm_pt)` | Normalised → canvas px QPointF |
| `simplify()` | Round all points to 2 decimal places |
| `center_all()` | Translate all geometry so its centroid is at canvas centre (520, 520) |
| `snapshot()` | Returns `GeometrySnapshot` of current committed state |
| `restore_snapshot(snap)` | Replace committed managers from snapshot |
| `add_closed_from_points(pts, layer_id)` | Build and commit a closed manager from flat QPointF list |
| `add_open_from_points(pts, layer_id)` | Build and commit an open manager |
| `remove_manager_at(i)` | Remove committed manager by 0-based committed index |

---

## `OvalManager` (`model/oval_manager.py`)

One axis-aligned ellipse in canvas pixel space.

```python
class OvalManager:
    cx, cy:               float   # centre (canvas px)
    rx, ry:               float   # radii (canvas px)
    orig_cx, orig_cy:     float   # frozen for slider gestures
    orig_rx, orig_ry:     float
    layer_id:             int
    selected:             bool
```

### Key methods

| Method | Description |
|---|---|
| `contains(px, py)` | Point-in-ellipse test |
| `translate(dx, dy)` | Move centre |
| `freeze_orig()` | Capture current values for upcoming slider gesture |
| `scale_xy_from_orig(factor, pivot_x, pivot_y)` | Uniform scale around pivot from frozen values |
| `rotate(degrees, pivot_x, pivot_y)` | Rotate centre around pivot (radii unchanged) |
| `flip_h(center_x)` / `flip_v(center_y)` | Mirror centre position |
| `average_xy()` | Returns `QPointF(cx, cy)` |
| `copy()` | Deep copy with `selected = False` |

---

## `GeometrySnapshot` (`model/geometry_snapshot.py`)

Immutable snapshot of the full canvas state for undo/redo.

```python
@dataclass
class OvalSnap:
    cx, cy, rx, ry: float
    layer_id: int

@dataclass
class GeometrySnapshot:
    managers:   list   # deep-copied CubicCurveManagers
    ovals:      list   # list[OvalSnap]
    points:     list   # list[QPointF]
    pressures:  list   # list[float]
```

`GeometrySnapshot.capture(polygon_manager, oval_list, point_list, point_pressures, active_layer_id)` builds a snapshot via `copy.deepcopy` on the committed managers list. Weld links across managers are **not** preserved in the snapshot (this is a known limitation).

The undo/redo stacks in `BezierWidget` are `collections.deque` with `maxlen=20` each.

---

## `WeldRegistry` (`model/weld_registry.py`)

Bidirectional registry mapping each `CubicPoint` to its set of welded partners.

```python
class WeldRegistry:
    _links: dict[CubicPoint, set[CubicPoint]]
```

| Method | Description |
|---|---|
| `register_weld(a, b)` | Mark `a` and `b` as welded (mutual) |
| `get_linked(p)` | Return `frozenset` of all points welded to `p` |
| `unregister_point(p)` | Remove `p` and clean up reverse links |
| `unregister_link(a, b)` | Remove only the `a↔b` link |
| `clear()` | Clear all links |
| `entries()` | Return `list` of `(point, set)` items for snapshot capture |

When a welded point is dragged, the `CubicPoint.drag()` method calls `WeldRegistry.get_linked(self)` and applies the same delta to each partner.
