# Drawing Modes

`BezierWidget` operates in one of several mutually exclusive modes. At most one mode flag is `True` at a time. Mode changes are broadcast via the `mode_changed(str)` signal.

---

## Mode List

| Flag | String name | Toolbar colour | Description |
|---|---|---|---|
| (none) | `"default"` | — | Default: closed polygon drawing mode |
| `point_mode` | `"point"` | green (creation) | Place discrete free-standing points |
| `oval_mode` | `"oval"` | green (creation) | Create ovals by click-drag |
| `polygon_selection_mode` | `"polygon_selection"` | orange (selection) | Select/move whole polygons and ovals |
| `edge_selection_mode` | `"edge_selection"` | orange (selection) | Select individual edges |
| `point_selection_mode` | `"point_selection"` | orange (selection) | Select and drag individual control points |
| `open_curve_selection_mode` | `"open_curve_selection"` | orange (selection) | Select open curves |
| `freehand_mode` | `"freehand"` | green (creation) | Draw freehand strokes, auto-fit to Bézier |
| `knife_mode` | `"knife"` | green (creation) | Cut closed polygons along a drawn line |
| `mesh_build_mode` | `"mesh_build"` | green (creation) | Build quad-mesh polygons from anchor sequence |

---

## Default Mode (Closed Polygon Drawing)

When no mode flag is set, mouse clicks draw closed cubic Bézier polygons.

- **Click:** Place points via `CubicCurveManager.set_point()` state machine (4 clicks per segment).
- **Near first anchor:** Snapping to the first anchor closes the polygon. `PolygonManager.finish_closed()` is called, committing the curve. Undo snapshot pushed.
- **Finish Curve (menu/key):** Force-closes the active polygon if ≥2 curves exist.
- **Space (pause):** Suppresses the rubber line while held.

---

## Open Curve Mode

Activated by `--open-curve` CLI flag or `Edit → Finish Open Curve` action (which finishes the current open curve).

Same 4-click-per-segment drawing as default, but `PolygonManager.finish_open()` is called instead of `finish_closed()`.

---

## Point Mode

- **Click:** Appends a `QPointF` to `_discrete_points`. Pressure recorded from `QTabletEvent` if available; defaults to `1.0`.
- Points are rendered as purple filled circles sized by pressure.
- One point can be selected and dragged.

---

## Oval Mode

- **Press:** Start of oval. Records press position as centre.
- **Drag:** Updates radii `(rx, ry)` from the drag delta.
- **Release:** Commits the `OvalManager` to `_ovals`. Undo snapshot pushed.

The oval centre is set to the mouse-press position. Radii equal the absolute X/Y drag deltas from the press.

---

## Polygon Selection Mode

Select and move whole closed polygons, open curves, and ovals.

- **Click on polygon/oval:** Select it. `Cmd+click` adds to selection without deselecting others.
- **Click on empty canvas:** Deselect all.
- **Drag on selected polygon/oval:** Move it (and all selected items together).
- **Drag on empty canvas:** Start rubber-band. On release, select all polygons whose bounding box or centroid is inside the rectangle.
- **Delete key:** Delete all selected polygons/ovals. Undo snapshot pushed.

Selection sub-modes (`SelectionSubMode`):
- `RELATIONAL` (default): selecting a polygon also highlights its weld partners.
- `DISCRETE` (`Cmd+click`): affects only the clicked item.

---

## Edge Selection Mode

Select individual Bézier edges (segments).

- **Click on edge:** Select the nearest edge within hit threshold.
- **Selected edges** are highlighted in blue (discrete) or orange (relational).
- **Drag on edge:** Move adjacent anchor and propagate to weld partners.
- **Rubber-band:** Selects all edges whose midpoints fall inside the rectangle.

---

## Point Selection Mode

Select and drag individual anchor and control points.

- **Click on point:** Select it. Highlights with colour-coded ring.
- **Drag on selected point:** Move it; weld partners move simultaneously.
- **Rubber-band:** Selects all points inside the rectangle.
- **Control point visibility:** Control points are always shown in this mode.

---

## Open Curve Selection Mode

Behaves like polygon selection mode but specifically targets open-curve managers. Closed polygons are not selectable in this mode.

---

## Freehand Mode

Draw a stroke by dragging; the stroke is automatically fitted to cubic Bézier segments on release.

- **Press:** Begin stroke accumulation (`_freehand_pts`, `_freehand_pressures`).
- **Drag:** Accumulate raw points.
- **Near start point (snap_radius = 20 px):** Closing indicator shown (green circle at start).
- **Release:**
  - Call `CurveFitter.fit(pts, error_threshold)` to fit the stroke to Bézier segments.
  - If the release point is within snap radius of the start: close the resulting polygon.
  - Otherwise: commit as an open curve.
  - Undo snapshot pushed.
- **Error threshold:** Configurable; default 8.0 px (higher = fewer, coarser segments).

Tablet stylus pressure is recorded per sample. If any sample has pressure < 0.99, the open curve's `anchor_pressures` array is populated and the curve renders with variable stroke width.

---

## Knife Mode

Cut closed polygons along a line segment.

- **Press:** Record `_knife_start`.
- **Drag:** Show dashed red knife line from start to current mouse.
- **Release:** Call `knife_tool.perform_cut(...)`. Each polygon that the line crosses with exactly 2 (or 2N) intersections is split into two (or 2N) pieces. Cut pieces are auto-welded at their shared boundary points. Undo snapshot pushed.

Only closed polygons are cut. Open curves and ovals are unaffected.

Pre-knife-selected polygons: after cutting, the resulting pieces of previously-selected polygons are placed into the selection list.

---

## Mesh Build Mode

Build a polygon by clicking on existing anchor points in sequence.

- **Click near an anchor (within `_MESH_ADD_R = 10 px`):** Add that anchor's position to `_mesh_sequence`.
- **Click on already-sequenced anchor:** Ignored.
- **Hover within `_MESH_PREVIEW_R = 18 px`:** Show hover ring.
- **Finish Curve action:** If `_mesh_sequence` has ≥ 3 points: create a new closed polygon using straight segments (1/3–2/3 control points) through the sequenced anchor positions. Clear the sequence. Undo snapshot pushed.

The mesh overlay shows numbered green rings at each sequenced point, green connecting lines, a dashed ghost closing edge, and a dashed preview line from the last point to the mouse.

---

## Undo / Redo

`BezierWidget._push_undo()` captures a `GeometrySnapshot` and pushes it onto `_undo_stack` (deque, maxlen=20). The `_redo_stack` is cleared on every undo push.

`undo()`: pop from `_undo_stack`, push current state onto `_redo_stack`, restore snapshot.  
`redo()`: pop from `_redo_stack`, push current state onto `_undo_stack`, restore snapshot.

Undo is triggered by `Edit → Undo` (Ctrl+Z). Redo by `Edit → Redo` (Ctrl+Y / Ctrl+Shift+Z).

---

## Other Edit Actions

| Action | Menu / Key | Behaviour |
|---|---|---|
| Select All | Ctrl+A | Select all polygons, ovals, discrete points |
| Deselect | Ctrl+D | Deselect all |
| Copy | Ctrl+C | Copy selected polygons/ovals/points to clipboard |
| Paste | Ctrl+V | Paste with a small offset to avoid overlap |
| Cut | Ctrl+X | Copy + delete selected |
| Delete | Delete / Backspace | Delete selected geometry |
| Weld All Adjacent | — | Call `WeldRegistry` to weld all coincident anchor pairs |
| Clear Grid | — | Delete all geometry; undo snapshot pushed |
| Finish Curve | — | Close active drawing polygon |
| Finish Open Curve | — | Commit active drawing polygon as open curve |
| Create Oval | — | Create a default oval at canvas centre |
| Flip H | — | Mirror selected geometry horizontally around centroid |
| Flip V | — | Mirror vertically |
