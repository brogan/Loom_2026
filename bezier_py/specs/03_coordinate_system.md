# Coordinate System

## Three Coordinate Spaces

The application uses three distinct coordinate spaces that must be kept separate.

### 1. Canvas Space (pixel)

The drawable area is a `QImage` of size `1040 × 1040` pixels. All runtime geometry is stored in canvas space. The origin is at the top-left (Qt convention).

| Constant | Value | Meaning |
|---|---|---|
| `WIDTH` / `HEIGHT` | 1040 | Canvas pixel dimensions |
| `GRIDWIDTH` / `GRIDHEIGHT` | 1000 | Active grid area |
| `EDGE_OFFSET` | 20 | Margin on each side (inactive pixels) |

The active grid occupies pixels `[20, 1020)` in both axes. Canvas centre is at `(520, 520)`.

### 2. Normalised Space (XML storage)

XML coordinate values are normalised floating-point numbers. Range is approximately `−0.5` to `+0.5` for the grid area, with the offset adjustment shifting values slightly inward.

### 3. SVG Space (export/import)

SVG user units correspond to canvas pixels minus the edge offset:
```
svg_coord = canvas_px − EDGE_OFFSET
```
SVG viewport is always `1000 × 1000` user units, matching `GRIDWIDTH`.

---

## Coordinate Pipeline

### Canvas → XML (save)

```
normalise:      norm = canvas_px / GRIDWIDTH − 0.5
adjust offset:  adjusted = norm − EDGE_OFFSET / GRIDWIDTH   (i.e. − 0.02)
simplify:       xml_val = round(round(adjusted × 100)) / 100.0
```

Combined in code (`_to_xml_coord`):
```python
norm    = canvas_val / 1000 - 0.5
adj     = norm - 20 / 1000           # = norm - 0.02
xml_val = round(round(adj * 100)) / 100.0
```

### XML → Canvas (load)

```
add offset:   val = xml_x + EDGE_OFFSET / GRIDWIDTH   (i.e. + 0.02)
denormalise:  canvas_px = val * GRIDWIDTH + GRIDWIDTH / 2
```

Combined:
```python
val       = xml_val + 20 / 1000       # add offset back
canvas_px = val * 1000 + 1000 / 2    # = val * 1000 + 500
```

### Oval Coordinates

Oval **centres** use the same normalise/denormalise as above.  
Oval **radii** use a simpler pipeline (no offset adjustment, no 0.5 shift):

```
Save:  norm_radius = radius / GRID
Load:  radius = norm_radius * GRID
```

Centre denormalise for ovals:
```
canvas_px = (norm + 0.5) * GRID + EDGE
```
(This is equivalent to the polygon denormalise when `xml_val` already has the offset applied.)

---

## Coordinate Examples

| Canvas px | Normalised+adjusted (XML) |
|---|---|
| 520 (centre) | 0.0 |
| 20 (left edge) | −0.5 |
| 1020 (right edge) | +0.48 |

---

## SVG Coordinate Transform

```python
svg_x = canvas_px - EDGE_OFFSET           # 520 - 20 = 500
```

Import maps SVG coordinates back to canvas:
```python
canvas_x = (svg_x - vb_x) / vb_w * GRID_SIZE + EDGE_OFFSET
```
Where `vb_x, vb_y, vb_w, vb_h` come from the SVG `viewBox` attribute.

---

## Grid Rendering

The fine grid has `100 × 100` cells, each `10 px` wide (matches Java `Grid(100, 100, ...)`).  
The axis grid has `20` divisions at `50 px` spacing (matches Java `GridAxes(..., 20, ...)`).

Axis lines alternate between `COL_AXIS_ODD` (blue) and `COL_AXIS_EVEN` (teal). The alternation uses `(i % 2 != 0)` — odd index produces the even colour and vice versa, matching the original Java convention.

---

## Point Hit Testing

| Constant | Value | Use |
|---|---|---|
| `HIT_RADIUS` (MouseHandler) | 8.0 px | Snap to existing anchor on click |
| `POINT_RADIUS` (MouseHandler) | 15.0 px | Polygon containment detection radius |
| `ANCHOR_RADIUS` (RenderEngine) | 5.0 px | Drawn anchor point oval radius |
| `CONTROL_RADIUS` (RenderEngine) | 4.0 px | Drawn control point oval radius |
