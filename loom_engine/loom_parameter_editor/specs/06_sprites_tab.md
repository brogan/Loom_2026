# Sprites Tab

**Source:** `ui/sprite_tab.py`, `ui/sprite_preview_widget.py`  
**Model:** `models/sprite_config.py`  
**IO:** `file_io/sprite_config_io.py`  
**XML file:** `configuration/sprites.xml`

## Purpose

The Sprites tab edits the `SpriteLibrary` — the complete set of sprite definitions that the engine renders. Each sprite definition (`SpriteDef`) links a geometry source to a renderer set and specifies all position, scale, rotation, and animation parameters.

## Layout

Horizontal splitter:

### Left Panel — Sprite Tree

`QTreeWidget` with columns: `Sel` (checkbox), `Name`, `Enabled`, `Anim`

- Top-level items: **SpriteSets** (bold)
- Child items: **SpriteDefs** (with checkbox in `Sel` column)

**Buttons below tree:**
| Button | Action |
|---|---|
| `+ Set` | Add new `SpriteSet` (prompts for name) |
| `- Set` | Remove selected set (with confirmation) |
| `+ Sprite` | Add new `SpriteDef` to selected set |
| `- Sprite` | Remove selected sprite |
| `Rename` | Rename selected item |
| `Duplicate` | Duplicate selected item |
| `↑ / ↓` | Reorder within parent |
| `Delete Selected` | Remove all checked sprites |
| `Open Bezier` | Launch Bezier editor for the geometry source (polygon/curve) |

### Right Panel — Property Editor

`QTabWidget` with inner tabs: **Geometry**, **Position**, **Animation**, **Keyframes**, **Morphs**

Below the inner tabs: a **preview canvas** (`SpritePreviewWidget`) showing a live schematic of all sprites on the configured canvas.

---

## SpriteDef Fields

### Geometry Tab

| Field | Widget | Description |
|---|---|---|
| `enabled` | `QCheckBox` | Whether this sprite is drawn |
| `name` | `QLineEdit` | Identifier |
| `animator_type` | `QComboBox` | "random", "keyframe", "jitter_morph", "keyframe_morph" |
| `geo_source_type` | Radio group | POLYGON_SET, REGULAR_POLYGON, INLINE_POINTS, OPEN_CURVE_SET, POINT_SET, OVAL_SET |
| `geo_polygon_set_name` | `QComboBox` | Selected from registered PolygonSets |
| `geo_open_curve_set_name` | `QComboBox` | Selected from registered OpenCurveSets |
| `geo_point_set_name` | `QComboBox` | Selected from registered PointSets |
| `geo_oval_set_name` | `QComboBox` | Selected from registered OvalSets |
| `geo_regular_polygon_sides` | `QSpinBox` | Number of sides (3–100) |
| `geo_inline_points` | Table editor | List of (x, y) point pairs |
| `geo_subdivision_params_set_name` | `QComboBox` | SubdivisionParamsSet to apply |
| `geo_shape_3d_type` | `QComboBox` | 3D shape generator: NONE, CRYSTAL, RECT_PRISM, EXTRUSION, GRID_PLANE, GRID_BLOCK |
| `geo_shape_3d_param1/2/3` | `QSpinBox` | 3D shape generator parameters |
| `renderer_set_name` | `QComboBox` | Selected from registered RendererSets |

Only the widgets relevant to the selected `geo_source_type` are shown (others hidden).

### Position Tab

| Field | Widget | Default | Description |
|---|---|---|---|
| `location_x` | `QDoubleSpinBox` | 0.0 | X position (pixels from top-left) |
| `location_y` | `QDoubleSpinBox` | 0.0 | Y position (pixels from top-left) |
| `size_x` | `QDoubleSpinBox` | 1.0 | X scale factor |
| `size_y` | `QDoubleSpinBox` | 1.0 | Y scale factor |
| `start_rotation` | `QDoubleSpinBox` | 0.0 | Initial rotation in degrees |
| `rot_offset_x` | `QDoubleSpinBox` | 0.0 | Rotation centre X offset (editor only) |
| `rot_offset_y` | `QDoubleSpinBox` | 0.0 | Rotation centre Y offset (editor only) |

A mini canvas preview updates as position/size change, showing where sprites will appear relative to the canvas.

### Animation Tab

| Field | Widget | Default | Description |
|---|---|---|---|
| `animation_enabled` | `QCheckBox` | True | Enable animation for this sprite |
| `total_draws` | `QSpinBox` | 0 | 0 = infinite; >0 = stop after N cycles |
| `translation_range_x_min/max` | `QDoubleSpinBox` | 0.0 | Random translation range X |
| `translation_range_y_min/max` | `QDoubleSpinBox` | 0.0 | Random translation range Y |
| `scale_range_x_min/max` | `QDoubleSpinBox` | 0.0 | Random scale range X |
| `scale_range_y_min/max` | `QDoubleSpinBox` | 0.0 | Random scale range Y |
| `rotation_range_min/max` | `QDoubleSpinBox` | 0.0 | Random rotation range |
| `scale_factor_x` | `QDoubleSpinBox` | 1.0 | Scale multiplier per cycle (editor only) |
| `scale_factor_y` | `QDoubleSpinBox` | 1.0 | Scale multiplier per cycle (editor only) |
| `rotation_factor` | `QDoubleSpinBox` | 0.0 | Rotation increment per cycle (editor only) |
| `speed_factor_x` | `QDoubleSpinBox` | 0.0 | Translation speed per cycle (editor only) |
| `speed_factor_y` | `QDoubleSpinBox` | 0.0 | Translation speed per cycle (editor only) |
| `jitter` | `QCheckBox` | False | Oscillate around home position |

### Keyframes Tab

Applies when `animator_type` is "keyframe" or "keyframe_morph".

`QTableWidget` with columns: `Draw Cycle`, `Pos X`, `Pos Y`, `Scale X`, `Scale Y`, `Rotation`, `Easing`, `Morph Amount`

| Field | Description |
|---|---|
| `draw_cycle` | Integer draw cycle at which this keyframe applies |
| `pos_x/y` | Absolute position at this keyframe |
| `scale_x/y` | Scale at this keyframe |
| `rotation` | Rotation at this keyframe |
| `easing` | Easing function (see Easing Types below) |
| `morph_amount` | Morph blend amount (0.0–1.0) |

`loop_mode` dropdown: `NONE`, `LOOP`, `PING_PONG` — controls what happens after the last keyframe.

**Easing Types:** 41 values — LINEAR, EASE_IN/OUT/IN_OUT/OUT_IN variants for QUAD, CUBIC, QUART, QUINT, SINE, EXPO, CIRC, ELASTIC, BACK, BOUNCE.

### Morphs Tab

Applies when `animator_type` is "jitter_morph" or "keyframe_morph".

| Field | Description |
|---|---|
| Morph targets list | Ordered list of `MorphTargetRef` (filename in `morphTargets/`) |
| `morph_min` | Minimum morph blend (0.0–1.0) |
| `morph_max` | Maximum morph blend (0.0–1.0) |

**Buttons:** `+ Morph Target` (browse `morphTargets/` or launch Bezier to create), `- Morph Target`, `↑ / ↓`

Each morph target is a `.poly.xml` or `.curve.xml` file in `<project_dir>/morphTargets/`. Clicking `Open Bezier` for a morph target opens the Bezier editor pre-loaded with that file.

---

## Geometry Source Types (`GeoSourceType` enum)

| Value | Name | Description |
|---|---|---|
| 0 | POLYGON_SET | File from `polygonSets/` |
| 1 | REGULAR_POLYGON | N-gon generated by editor |
| 2 | INLINE_POINTS | Explicit point list defined in this sprite |
| 3 | OPEN_CURVE_SET | File from `curveSets/` |
| 4 | POINT_SET | File from `pointSets/` |
| 5 | OVAL_SET | Oval defined in `ovals.xml` |

## 3D Shape Generator Types (`GeoShape3DType` enum)

| Value | Name |
|---|---|
| 0 | NONE |
| 1 | CRYSTAL |
| 2 | RECT_PRISM |
| 3 | EXTRUSION |
| 4 | GRID_PLANE |
| 5 | GRID_BLOCK |

---

## Preview Widget — `SpritePreviewWidget` / `SpritePreviewCanvas`

`SpritePreviewWidget` is a thin container (`QWidget`) holding `SpritePreviewCanvas` plus a control strip. `SpritePreviewCanvas` is the interactive rendering surface.

### Rendering

- Background pixmap cache (`_bg_pixmap`) is rebuilt only when the scene changes (sprite added/removed, background sprites moved, grid size changed). During a drag only the selected sprite is repainted each frame, making drag performance independent of scene complexity.
- Each sprite is rendered as its actual geometry (bezier paths or polygon outlines) transformed to canvas coordinates. If geometry cannot be resolved, a placeholder rectangle is shown.
- **Colour coding:** selected sprite = bright green; same sprite set = mid-blue; other sets = grey.
- Grid and canvas border drawn in the background pixmap.

### Geometry Resolution

`_resolve_geometry(sprite)` parses the sprite's geo source XML on first use and caches the result in `_geo_cache`. The cache is keyed by file path and invalidated only when project directories change.

### Bounding Box and Handle Interaction

The selected sprite shows a dashed bounding box with eight handles:
- **Corners TL / BR** — uniform scale (drag distance from centre changes both `size_x` and `size_y` proportionally)
- **Edges T / B** — scale Y only
- **Edges L / R** — scale X only
- **Corners TR / BL** — rotation (drag angle from centre changes `start_rotation`)

**Bounding box computation** (`_sprite_bbox_world`): the world-space bbox is built from all anchor points **and** bezier control points in `geo.ctrl_polys`. This matches exactly what `_build_path` accumulates when painting, so the handle draw positions and hit-test positions are always consistent. For curved geometry (e.g., baked `CUBIC_CURVE` polygon sets), control points extend beyond the anchor hull; including them in both paint and hit-test is critical for handles to respond correctly.

Handle hit radius: 6 px. Click inside the bbox (outside all handles) initiates a move drag.

### Control Strip

Below the canvas:

| Control | Description |
|---|---|
| Grid combo (5%/10%/25%/50%) | Grid spacing as % of canvas half-width |
| Snap to Grid checkbox | Snaps move drags to grid steps |
| KF combo | Selects a keyframe to preview (enabled for keyframe/keyframe_morph sprites) |
| Edit KF checkbox | When checked, drags write back to the selected keyframe row |
| Transform readout | `p X, Y  s SX, SY  r ROT` — live during drag |

---

## Cross-Tab References

The sprite tab receives library references for dropdown population:

```python
set_polygon_library(lib)          # PolygonSetLibrary
set_open_curve_library(lib)       # OpenCurveSetLibrary
set_point_set_library(lib)        # PointSetLibrary
set_oval_set_library(lib)         # OvalSetLibrary
set_subdivision_collection(coll)  # SubdivisionParamsSetCollection
set_renderer_library(lib)         # RendererSetLibrary
```

These are called by `MainWindow._notify_tabs_of_project_dir()` whenever any tab changes.

**Identity guards:** All six setters short-circuit (`return` immediately) when the incoming library/collection is the same Python object as the cached one. This prevents `_refresh_geo_name_combo()` and `_refresh_renderer_set_dropdown()` from rebuilding combo boxes on every mouse-move event during a preview drag. The same guard pattern is applied to `GeometryTab.set_sprite_library / set_subdivision_collection / set_renderer_library`.

---

## Data Model Hierarchy

```
SpriteLibrary
  name        : str
  sprite_sets : List[SpriteSet]

SpriteSet
  name    : str
  sprites : List[SpriteDef]

SpriteDef
  name                       : str
  enabled                    : bool
  geo_source_type            : GeoSourceType
  geo_polygon_set_name       : str
  geo_open_curve_set_name    : str
  geo_point_set_name         : str
  geo_oval_set_name          : str
  geo_regular_polygon_sides  : int
  geo_inline_points          : List[GeoInlinePoint]
  geo_subdivision_params_set_name : str
  geo_shape_3d_type          : GeoShape3DType
  geo_shape_3d_param1/2/3    : int
  shape_set_name             : str  (auto-derived on save for Scala compat)
  shape_name                 : str  (auto-derived on save for Scala compat)
  renderer_set_name          : str
  animator_type              : str
  params                     : SpriteParams

SpriteParams
  location_x/y               : float
  size_x/y                   : float
  start_rotation             : float
  animation_enabled          : bool
  total_draws                : int
  translation_range_x/y_min/max : float
  scale_range_x/y_min/max    : float
  rotation_range_min/max     : float
  rot_offset_x/y             : float (editor only)
  scale_factor_x/y           : float (editor only)
  rotation_factor            : float (editor only)
  speed_factor_x/y           : float (editor only)
  jitter                     : bool
  loop_mode                  : str
  keyframes                  : List[Keyframe]
  morph_targets              : List[MorphTargetRef]
  morph_min/max              : float

Keyframe
  draw_cycle   : int
  pos_x/y      : float
  scale_x/y    : float
  rotation     : float
  easing       : str
  morph_amount : float

MorphTargetRef
  file : str
  name : str
```
