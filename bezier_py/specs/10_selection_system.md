# Selection System

**Source:** `canvas/selection_state.py`, `canvas/mouse_handler.py`

---

## Selection Types

The editor supports four independent selection targets that can coexist:

| Target | Container | Selected indicator |
|---|---|---|
| Whole polygons / open curves | `CubicCurveManager.selected` | Blue/orange overlay stroke |
| Ovals | `OvalManager.selected` | Blue outline 4 px |
| Edges (curve segments) | `CubicCurveManager.discrete_edge_indices` / `relational_edge_indices` | Coloured edge highlight |
| Points (anchors/controls) | `CubicCurveManager.discrete_points` / `relational_points` | Coloured ring |

---

## Selection Sub-Modes

```python
class SelectionSubMode(Enum):
    RELATIONAL = auto()   # default: propagates to weld partners
    DISCRETE   = auto()   # Cmd+click: affects only the clicked item
```

- **Relational** (default): selecting an element also highlights all welded partners. Polygon overlay uses `COL_SEL_REL` (orange) when relational.
- **Discrete** (`Cmd+click`): selection affects only the clicked item. Polygon overlay uses `COL_SEL_CLOSED` (blue).

---

## `SelectedEdge`

```python
@dataclass
class SelectedEdge:
    manager:     CubicCurveManager
    curve_index: int

    def matches(self, other: SelectedEdge) -> bool: ...
```

Identifies a specific curve segment within a specific manager.

---

## `SelectionSnapshot`

```python
@dataclass
class SelectionSnapshot:
    points:   list   # list[CubicPoint]
    edges:    list   # list[SelectedEdge]
    polygons: list   # list[CubicCurveManager]
    ovals:    list   # list[OvalManager]

    def is_empty(self) -> bool: ...
```

`BezierWidget` maintains a selection history stack of up to 10 `SelectionSnapshot` entries. This allows navigating back through previous selection states without affecting geometry.

---

## Selection Highlight Colours

| Situation | Colour |
|---|---|
| Selected closed polygon (discrete) | `COL_SEL_CLOSED` — blue `(0,100,255,160)`, 4 px |
| Selected polygon (relational) | `COL_SEL_REL` — orange `(255,140,0,160)`, 4 px |
| Scoped polygon (knife/intersect) | Yellow dashed `(255,255,100,200)`, 2 px |
| Selected edge (discrete) | Blue `(0,100,255,200)`, 4 px |
| Selected edge (relational) | Orange `(255,140,0,200)`, 4 px |
| Weldable edge preview | Purple `(220,0,255,200)`, 5 px |
| Selected anchor (discrete) | Blue `(100,150,255)` ring, 12 px |
| Selected anchor (relational) | Red `(220,50,30)` ring, 12 px |
| Selected control (discrete) | White ring, 12 px |
| Selected control (relational) | Yellow `(255,220,0)` ring, 12 px |
| Selected oval | Blue outline, 4 px |
| Selected discrete point | Yellow ring |

---

## `MouseHandler` (`canvas/mouse_handler.py`)

Handles all mouse events and dispatches to the correct mode handler in `BezierWidget`.

```python
class MouseHandler:
    HIT_RADIUS   = 8.0    # px — snap to existing anchor on click
    POINT_RADIUS = 15.0   # px — polygon containment detection

    def press(self, event: QMouseEvent) -> None
    def move(self, event: QMouseEvent) -> None
    def release(self, event: QMouseEvent) -> None
    def double_click(self, event: QMouseEvent) -> None
```

`press()` checks the current mode and dispatches:
- `oval_mode` → start oval drag
- `freehand_mode` → begin stroke accumulation
- `knife_mode` → record knife start
- `mesh_build_mode` → add nearest anchor to sequence (within `_MESH_ADD_R`)
- `point_mode` → append discrete point
- `polygon_selection_mode` → hit-test polygons/ovals, or start rubber-band
- `edge_selection_mode` → hit-test edges
- `point_selection_mode` → hit-test points
- default (drawing) → `CubicCurveManager.set_point()` with snap-to-first-anchor check

`move()` handles drag updates for all interactive operations (oval resize, point drag, rubber-band, freehand accumulation, knife preview).

`release()` commits operations and pushes undo snapshots where needed.

---

## Rubber-Band Selection

In polygon selection mode, dragging on an empty area produces a blue dashed rectangle (`draw_rubber_band`). On release:
- Any polygon whose `get_average_xy()` centroid falls inside the rectangle is selected.
- Any oval whose `average_xy()` centre falls inside the rectangle is selected.

---

## Select All / Deselect

- **Select All (Ctrl+A):** Sets `selected = True` on all committed managers and ovals; adds all discrete points to the selection set.
- **Deselect (Ctrl+D):** Clears all `selected` flags and all edge/point highlight sets.
