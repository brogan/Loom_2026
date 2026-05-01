# Tools

---

## `CurveFitter` (`canvas/curve_fitter.py`)

Port of `CurveFitter.java`. Fits a polyline of raw sample points to a chain of cubic Bézier segments using the Schneider algorithm.

### Public API

```python
def fit(pts: list[QPointF], error_threshold: float) -> list[QPointF] | None
```

Returns a flat list of `QPointF` in groups of 4 (`a0, c1, c2, a1`) per segment, or `None` if input is too short. Adjacent segments share the same end/start anchor value.

### Pipeline

1. **Deduplicate** — Remove consecutive duplicate points (within 0.01 px).
2. **Douglas-Peucker simplification** — Reduce point count using `epsilon = max(error_threshold, 2.0)`.
3. **2-point shortcut** — If only 2 points remain, return a single segment with controls at 1/3 and 2/3.
4. **Chord-length parameterisation** — Assign parameter `u[i]` to each point proportional to cumulative chord length.
5. **Least-squares Bézier generation** — Solve for optimal control points using the Bernstein basis.
6. **Max error check** — If the max squared distance from any point to the fitted curve exceeds `error_threshold²`, try Newton-Raphson reparameterisation once.
7. **Split and recurse** — If error still exceeds threshold or the bezier would loop, split at the worst-fit point and recurse on both halves.
8. **Loop detection** — A segment is rejected if the sum of its handle arm lengths exceeds the chord length (`arm1 + arm2 > chord`).

### Parameters

| Parameter | Typical range | Effect |
|---|---|---|
| `error_threshold` | 1–50 px | Higher = fewer segments, coarser fit |

---

## `KnifeTool` (`canvas/knife_tool.py`)

Port of `BezierKnifeTool.java`. Cuts closed polygons along a line segment using De Casteljau subdivision.

### Public API

```python
def perform_cut(polygon_manager, line_a, line_b, pre_knife_selection, selected_polygons)
```

### Algorithm

1. **Line equation:** Convert `line_a → line_b` to `ax + by + c = 0` form.
2. **For each closed polygon:**
   a. Compute signed distance of each control point to the line.
   b. Find roots via recursive De Casteljau subdivision (tolerance `1e-6`).
   c. Deduplicate intersections within `global_t` distance of 0.015.
   d. Filter to intersections whose projection onto the line segment falls in `[−0.02, 1.02]`.
3. **If exactly 2 (or 2N) intersections:** split the polygon at those points. Each pair of adjacent intersections defines one piece.
4. **De Casteljau split** (`casteljau_split`): split a cubic segment at parameter `t` exactly using the De Casteljau algorithm.
5. **Piece assembly:** Each piece is built from sub-curves between intersection pairs, closed with a straight segment.
6. **Remove originals** (descending index to avoid shift), add pieces to `PolygonManager`.
7. **Auto-weld** (`_weld_coincident_points`): register weld links for all cross-manager point pairs within `0.1 px`.

### Constraints

- Only closed polygons are cut; open curves and ovals are skipped.
- Polygons with an odd number of intersections (tangent/touching) are also skipped.
- The `pre_knife_selection` set tracks which polygons were selected before knife mode; their resulting cut pieces are added to `selected_polygons`.

---

## `IntersectTool` (`canvas/intersect_tool.py`)

Port of `BezierIntersectTool.java`. Takes two concentric closed polygons with the same curve count and creates N quad polygons spanning the annular region between them.

### Public API

```python
def perform_intersect(polygon_manager, a, b, active_layer_id, selected_polygons) -> bool
```

Returns `True` on success, `False` if validation fails (no changes made).

### Validation

- Both polygons must have the same curve count, minimum 3.
- Their first-edge directions must differ by less than 5°.
- One polygon must be fully inside the other (all anchors inside the other's path).

### Algorithm

For each curve index `i` from `0` to `N-1`:
1. Outer edge `i` (forward Bézier from outer polygon).
2. Right spoke: straight segment from `outer.anchor[i+1]` to `inner.anchor[i+1]`.
3. Inner edge `i` (reversed Bézier from inner polygon: `iAi+1, iC2, iC1, iAi`).
4. Left spoke: straight segment from `inner.anchor[i]` to `outer.anchor[i]`.

Straight segments are encoded as cubics with controls at 1/3 and 2/3 (`_straight_edge`).

### Post-processing

- Remove both originals (descending index order).
- Add N quad managers to `polygon_manager`.
- Weld all coincident boundary points within `WELD_EPSILON = 0.5 px`.
- All new quads are marked `selected = True` and returned in `selected_polygons`.

---

## `WeldRegistry` (`model/weld_registry.py`)

See [04_data_model.md](04_data_model.md#weldregistry) for full API.

### Weld Mechanics

A weld link means that when either welded point is dragged, the other point moves by the same delta. This is implemented in `CubicPoint.drag()`:

```python
def drag(self, dx, dy):
    self.pos = QPointF(self.pos.x() + dx, self.pos.y() + dy)
    for partner in weld_registry.get_linked(self):
        partner.pos = QPointF(partner.pos.x() + dx, partner.pos.y() + dy)
```

### Weld Operations

| Operation | Trigger |
|---|---|
| Auto-weld on drag | When two points are within the weld threshold during a drag in edge/point selection mode |
| Manual weld | `Edit → Weld All Adjacent` — welds all cross-manager anchor pairs within threshold |
| Knife auto-weld | After cut: weld all boundary coincident points (threshold 0.1 px) |
| Intersect auto-weld | After annular quad creation (threshold 0.5 px) |
| Unweld | `WeldRegistry.unregister_link(a, b)` — not currently exposed in UI |

### Weld State in Snapshots

Weld links are **not** preserved in `GeometrySnapshot` (undo/redo state). After undo, weld links from before the action are lost. This is a known limitation.
