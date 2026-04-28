# Subdivision Tab

**Source:** `ui/subdivision_tab.py`  
**Model:** `models/subdivision_config.py`, `models/transform_config.py`  
**IO:** `file_io/subdivision_config_io.py`  
**XML file:** `configuration/subdivision.xml`

## Purpose

Edits the `SubdivisionParamsSetCollection` — the full set of subdivision rules that the engine applies to polygon geometry. Supports multiple named "sets", each containing multiple named "params" entries. The enabled/disabled state of each params entry is persisted (checkboxes in tree).

## Layout

Horizontal splitter:

### Left Panel — Tree

`QTreeWidget` with columns: `Sel` (checkbox), `Name`, `Type`, `Inset`, `PTW`, `PTP`

- Top-level items: **SubdivisionParamsSets** (bold)
- Child items: **SubdivisionParams** (with checkbox in `Sel` column)
- `Inset` column: ✓ when inset_transform scale ≠ (1,1)
- `PTW` column: ✓ when `polys_transform_whole` is enabled
- `PTP` column: ✓ when `polys_transform_points` is enabled

**Buttons below tree:**
| Button | Action |
|---|---|
| `+ Set` | Add new `SubdivisionParamsSet` (prompts for name) |
| `- Set` | Remove selected set (with confirmation) |
| `+ Params` | Add new `SubdivisionParams` to selected set |
| `- Params` | Remove selected params |
| `Rename` | Rename selected item |
| `Duplicate` | Duplicate selected item |
| `▲ / ▼` | Reorder items within their parent |
| `Bake…` | Run subdivision and save result as a polygon set |
| `Delete Selected` | Remove all checked params entries |

### Right Panel — Property Editor

Top: **Enable Subdivision** checkbox — global toggle (`GlobalConfig.subdividing`). Propagated to `MainWindow` and saved in `global_config.xml`.

Below: `QScrollArea` containing sub-sections displayed when a `SubdivisionParams` is selected.

---

## SubdivisionParams Fields (Property Editor)

### Core Settings

| Field | Widget | Default | Description |
|---|---|---|---|
| `name` | `QLineEdit` | "default" | Identifier |
| `enabled` | `QCheckBox` | True | Whether this params is active |
| `subdivision_type` | `QComboBox` | QUAD | Algorithm (see below) |
| `visibility_rule` | `QComboBox` | ALL | Which generated polygons are visible |
| `ran_middle` | `QCheckBox` | False | Randomise the midpoint location |
| `ran_div` | `QDoubleSpinBox` | 100.0 | Random divisor (0–1000) |
| `continuous` | `QCheckBox` | True | Apply subdivision recursively on every draw cycle |

### Line Ratios

| Field | Default | Description |
|---|---|---|
| `line_ratios.x` | 0.5 | Position of first midpoint along each edge (0–1) |
| `line_ratios.y` | 0.5 | Position of second midpoint along each edge (0–1) |
| `control_point_ratios.x` | 0.25 | Spline control point ratio 1 |
| `control_point_ratios.y` | 0.75 | Spline control point ratio 2 |

### Inset Transform (for ECHO subdivision types)

| Field | Default | Description |
|---|---|---|
| `inset_transform.translation.x/y` | 0.0 | Translation offset |
| `inset_transform.scale.x/y` | 0.5 | Scale factor (makes echo polygon smaller) |
| `inset_transform.rotation.x/y` | 0.0 | Rotation (in degrees or normalised units) |

### Poly Transform Whole (PTW)

Applies a rigid transform to entire polygons after subdivision.

| Field | Default | Description |
|---|---|---|
| `polys_transform` | True | Enable polygon transforms |
| `polys_transform_whole` | False | Transform whole polygons (PTW mode) |
| `ptw_probability` | 100.0 | Probability (%) that each polygon is transformed |
| `ptw_random_translation` | False | Enable random translation |
| `ptw_random_scale` | False | Enable random scale |
| `ptw_random_rotation` | False | Enable random rotation |
| `ptw_common_centre` | False | Use common centre for all polygon transforms |
| `ptw_random_centre_divisor` | 100.0 | Divisor for centre-based random offset |
| `ptw_transform.translation.x/y` | 0.0 | Fixed translation |
| `ptw_transform.scale.x/y` | 1.0 | Fixed scale |
| `ptw_transform.rotation.x/y` | 0.0 | Fixed rotation |
| `ptw_random_translation_range.x/y` | 0–0 | Random translation range |
| `ptw_random_scale_range.x/y` | 1–1 | Random scale range |
| `ptw_random_rotation_range` | 0–0 | Random rotation range |

### Point Transform (PTP)

Applies per-point transforms using the `TransformSet` system.

| Field | Default | Description |
|---|---|---|
| `polys_transform_points` | False | Enable point-level transforms |
| `ptp_probability` | 100.0 | Probability (%) each point is transformed |
| `transform_set` | TransformSetConfig | One or more named transform configurations |

`transform_set` is edited via a separate `TransformSetDialog` (opened by `Edit Transforms…` button).

---

## Subdivision Types (`SubdivisionType` enum)

| Value | Name | Description |
|---|---|---|
| 0 | QUAD | Standard 4-point quad subdivision |
| 1 | QUAD_BORD | Quad with border preservation |
| 2 | QUAD_BORD_ECHO | Quad border with inset echo |
| 3 | QUAD_BORD_DOUBLE | Double quad border |
| 4 | QUAD_BORD_DOUBLE_ECHO | Double quad border with echo |
| 5 | TRI | Triangle subdivision |
| 6 | TRI_BORD_A | Triangle border variant A |
| 7 | TRI_BORD_A_ECHO | Triangle border A with echo |
| 8 | TRI_BORD_B | Triangle border variant B |
| 9 | TRI_STAR | Triangle star pattern |
| 10 | TRI_BORD_C | Triangle border variant C |
| 11 | TRI_BORD_C_ECHO | Triangle border C with echo |
| 12 | SPLIT_VERT | Vertical split |
| 13 | SPLIT_HORIZ | Horizontal split |
| 14 | SPLIT_DIAG | Diagonal split |
| 16 | ECHO | Pure inset echo (no subdivision) |
| 17 | ECHO_ABS_CENTER | Echo with absolute centre |
| 18 | TRI_BORD_B_ECHO | Triangle border B with echo |
| 19 | TRI_STAR_FILL | Triangle star with filled centre |

## Visibility Rules (`VisibilityRule` enum)

| Value | Name |
|---|---|
| 0 | ALL |
| 1 | QUADS |
| 2 | TRIS |
| 3 | ALL_BUT_LAST |
| 4 | ALTERNATE_ODD |
| 5 | ALTERNATE_EVEN |
| 6 | FIRST_HALF |
| 7 | SECOND_HALF |
| 8 | EVERY_THIRD |
| 9 | EVERY_FOURTH |
| 10 | EVERY_FIFTH |
| 11 | RANDOM_1_2 |
| 12 | RANDOM_1_3 |
| 13 | RANDOM_1_5 |
| 14 | RANDOM_1_7 |
| 15 | RANDOM_1_10 |

---

## TransformSet / Transform Config (`models/transform_config.py`)

The point-transform system (`PTP`) uses a `TransformSetConfig` containing named transform entries. Five transform types are supported, each with its own config dataclass:

| Class | Scala type | Description |
|---|---|---|
| `ExteriorAnchorsConfig` | ExteriorAnchors | Radial displacement of polygon corner points |
| `CentralAnchorsConfig` | CentralAnchors | Displacement toward/away from polygon centroid |
| `AnchorsLinkedToCentreConfig` | AnchorsLinkedToCentre | Anchor-point displacement linked to polygon centre |
| `OuterControlPointsConfig` | OuterControlPoints | Outer spline control point displacement |
| `InnerControlPointsConfig` | InnerControlPoints | Inner spline control point displacement |

Each config contains a `Range` (min/max) for the transform magnitude.

`TransformSetDialog` is a modal dialog presenting a list of configured transforms with add/remove/edit capability.

---

## Bake Feature

The `Bake…` button applies the currently selected `SubdivisionParams` to the currently selected polygon set and saves the resulting subdivided geometry as a new `.poly.xml` file in `polygonSets/`. This uses `QProcess` to invoke the engine's batch subdivision mode. On completion, `polygon_baked` signal fires; `MainWindow` calls `SplinePolygonTab._refresh_file_list()` to pick up the new file.

The bake operation is engine-specific:
- **Scala engine**: runs `sbt "run --bake …"` in the `loom_engine` directory.
- **Swift engine**: runs `swift run LoomApp --bake …` in the `loom_swift` directory.

---

## Data Model Hierarchy

```
SubdivisionParamsSetCollection
  params_sets : List[SubdivisionParamsSet]

SubdivisionParamsSet
  name        : str
  params_list : List[SubdivisionParams]

SubdivisionParams
  name                      : str
  enabled                   : bool
  subdivision_type          : SubdivisionType
  visibility_rule           : VisibilityRule
  ran_middle                : bool
  ran_div                   : float
  line_ratios               : Vector2D
  control_point_ratios      : Vector2D
  inset_transform           : Transform2D
  continuous                : bool
  polys_transform           : bool
  polys_transform_whole     : bool
  ptw_probability           : float
  ptw_random_translation    : bool
  ptw_random_scale          : bool
  ptw_random_rotation       : bool
  ptw_common_centre         : bool
  ptw_random_centre_divisor : float
  ptw_transform             : Transform2D
  ptw_random_translation_range : RangeXY
  ptw_random_scale_range    : RangeXY
  ptw_random_rotation_range : Range
  polys_transform_points    : bool
  ptp_probability           : float
  transform_set             : TransformSetConfig
```
