# Rendering Tab

**Source:** `ui/rendering_tab.py`, `ui/widgets/renderer_tree.py`, `ui/widgets/change_editor.py`, `ui/widgets/color_picker.py`, `ui/widgets/palette_editor.py`, `ui/widgets/size_palette_editor.py`, `ui/widgets/brush_editor.py`, `ui/widgets/brush_editor_window.py`, `ui/widgets/brush_library.py`, `ui/widgets/stencil_editor_window.py`, `ui/widgets/stencil_library.py`  
**Model:** `models/rendering.py`, `models/constants.py`  
**IO:** `file_io/rendering_io.py`  
**XML file:** `configuration/rendering.xml`

## Purpose

The Rendering tab edits the `RendererSetLibrary` — the complete collection of renderer sets. Each renderer set contains one or more individual renderers. Sprites reference renderer sets by name.

## Layout

Horizontal splitter:

### Left Panel — Renderer Tree (`RendererTreeWidget`)

`QTreeWidget` with columns: `Enabled`, `Name`, `Mode`

- Top-level items: **RendererSets** (bold)
- Child items: **Renderers** within each set

**Buttons below tree:**
| Button | Action |
|---|---|
| `+ Set` | Add new `RendererSet` |
| `- Set` | Remove selected set |
| `+ Renderer` | Add new `Renderer` to selected set |
| `- Renderer` | Remove selected renderer |
| `Rename` | Rename selected item |
| `Duplicate` | Duplicate selected item |
| `↑ / ↓` | Reorder items |

Also accessible via Edit menu: `Add Renderer Set`, `Add Renderer`.

### Right Panel — Property Editor

The right panel uses `QTabWidget` with tabs that appear/disappear based on the selected object:

**When a RendererSet is selected:** "Set Properties" tab  
**When a Renderer is selected:** "Renderer Properties" tab

---

## RendererSet Properties

| Field | Widget | Default | Description |
|---|---|---|---|
| `name` | `QLineEdit` | "default" | Display name and lookup key |
| `enabled` | `QCheckBox` | True | Entire set on/off |
| `playback_mode` | `EnumDropdown` | STATIC | How renderers cycle within the set |
| `change_frequency` | `QSpinBox` | 1 | Draw cycles per renderer switch |

### Playback Modes (`PlaybackMode` enum)

| Value | Name | Description |
|---|---|---|
| 0 | STATIC | No switching; always use first enabled renderer |
| 1 | SEQUENTIAL | Cycle through renderers in order |
| 2 | RANDOM | Select a random renderer each cycle |
| 3 | ALL | Draw with every renderer each cycle (layered output) |

---

## Renderer Properties

The renderer editor is displayed in a `QScrollArea` with multiple grouped sections.

### Basic Settings

| Field | Widget | Default | Description |
|---|---|---|---|
| `name` | `QLineEdit` | "default" | Identifier within the set |
| `enabled` | `QCheckBox` | True | This renderer on/off |
| `mode` | `EnumDropdown` | FILLED | Drawing mode |
| `hold_length` | `QSpinBox` | 1 | Draw cycles before advancing |

### Render Modes (`RenderMode` enum)

| Value | Name | Description |
|---|---|---|
| 0 | POINTS | Draw only vertices as points |
| 1 | STROKED | Draw polygon edges as stroked lines |
| 2 | FILLED | Fill polygons with solid colour |
| 3 | FILLED_STROKED | Fill + stroke |
| 4 | BRUSHED | Stamp brush PNGs along polygon edges |
| 5 | STAMPED | Stamp full-RGBA stencil PNGs along polygon edges |

### Stroke Settings (STROKED, FILLED_STROKED)

| Field | Widget | Default |
|---|---|---|
| `stroke_width` | `QDoubleSpinBox` (0–500) | 1.0 |
| `stroke_color` | `ColorPickerWidget` (RGBA) | 0,0,0,255 |

### Fill Settings (FILLED, FILLED_STROKED)

| Field | Widget | Default |
|---|---|---|
| `fill_color` | `ColorPickerWidget` (RGBA) | 0,0,0,255 |

### Point Settings (POINTS)

| Field | Widget | Default |
|---|---|---|
| `point_size` | `QDoubleSpinBox` (0–500) | 2.0 |
| `point_stroked` | `QCheckBox` | True |
| `point_filled` | `QCheckBox` | True |

### Animated Changes

Each animatable property has a collapsible group box (`SizeChangeEditor` or `ColorChangeEditor`):

| Group | Animates | Widget class |
|---|---|---|
| Stroke Width Change | `stroke_width_change` | `SizeChangeEditor` |
| Stroke Color Change | `stroke_color_change` | `ColorChangeEditor` |
| Fill Color Change | `fill_color_change` | `FillColorChangeEditor` |
| Point Size Change | `point_size_change` | `SizeChangeEditor` |

---

## Change Editors (`ui/widgets/change_editor.py`)

### `SizeChangeEditor` (used for stroke width, point size)

A `QGroupBox` with its checkbox controlling `SizeChange.enabled`.

| Field | Widget | Description |
|---|---|---|
| `kind` | `EnumDropdown` | NUM_SEQ, NUM_RAN, SEQ, RAN |
| `motion` | `EnumDropdown` | DOWN, PING_PONG, UP |
| `cycle` | `EnumDropdown` | CONSTANT, ONCE, ONCE_REVERT, PAUSING, PAUSING_RANDOM |
| `scale` | `EnumDropdown` | SPRITE, POLY, POINT |
| `min_val` | `QDoubleSpinBox` (0–100) | Lower bound |
| `max_val` | `QDoubleSpinBox` (0–100) | Upper bound |
| `increment` | `QDoubleSpinBox` (0.01–10) | Step size |
| `pause_max` | `QSpinBox` | Max pause duration |
| `size_palette` | `SizePaletteEditorWidget` | List of discrete values (for SEQ/RAN kinds) |

Palette section is shown only when `kind` is SEQ or RAN.

### `ColorChangeEditor` (used for stroke color)

Same structural layout as `SizeChangeEditor` but with colour-specific fields:

| Field | Widget | Description |
|---|---|---|
| `kind` | `EnumDropdown` | NUM_SEQ, NUM_RAN, SEQ, RAN |
| `motion` | `EnumDropdown` | DOWN, PING_PONG, UP |
| `cycle` | `EnumDropdown` | CONSTANT, ONCE, ONCE_REVERT, PAUSING, PAUSING_RANDOM |
| `scale` | `EnumDropdown` | SPRITE, POLY, POINT |
| `min_color` | `ColorPickerWidget` | Start colour |
| `max_color` | `ColorPickerWidget` | End colour |
| `increment` | `ColorPickerWidget` | Per-step RGBA increment |
| `pause_max` | `QSpinBox` | Max pause duration |
| `pause_channel` | `EnumDropdown` | RED, GREEN, BLUE, ALPHA |
| `pause_color_min/max` | `ColorPickerWidget` | Pause trigger colour range |
| `palette` | `PaletteEditorWidget` | List of discrete colours (for SEQ/RAN kinds) |

### `FillColorChangeEditor`

Identical to `ColorChangeEditor` but operates on `FillColorChange`. Uses a distinct Scala dispatch path for fill colour vs stroke colour.

---

## Change Kind / Motion / Cycle / Scale Enums

### `ChangeKind`
| Value | Name | Description |
|---|---|---|
| 0 | NUM_SEQ | Sequential numeric transition (min→max→min…) |
| 1 | NUM_RAN | Random value within [min, max] each cycle |
| 2 | SEQ | Sequential palette selection |
| 3 | RAN | Random palette selection |

### `Motion`
| Value | Name | Description |
|---|---|---|
| -1 | DOWN | Decreasing (max → min) |
| 0 | PING_PONG | Bounce at limits |
| 1 | UP | Increasing (min → max) |

### `Cycle`
| Value | Name | Description |
|---|---|---|
| 0 | CONSTANT | Change every draw cycle without pause |
| 1 | ONCE | Change once then stop |
| 2 | ONCE_REVERT | Change once then revert to start |
| 3 | PAUSING | Change with fixed pause intervals |
| 4 | PAUSING_RANDOM | Change with random pause intervals |

### `Scale`
| Value | Name | Description |
|---|---|---|
| 0 | SPRITE | Update once per sprite per draw cycle |
| 1 | POLY | Update once per polygon per draw cycle |
| 2 | POINT | Update once per vertex per draw cycle |

---

## Brush Configuration (`BrushConfig`)

Used when `mode == BRUSHED`. Accessed via a `BrushEditorWindow` (separate floating window).

| Field | Default | Description |
|---|---|---|
| `brush_names` | [] | List of PNG filenames in `brushes/` |
| `brush_enabled` | [] | Per-brush enable flag |
| `draw_mode` | FULL_PATH | FULL_PATH: render entire path; PROGRESSIVE: reveal over time |
| `stamp_spacing` | 4.0 | Distance between stamps along path |
| `spacing_easing` | "LINEAR" | Easing for stamp spacing variation |
| `follow_tangent` | True | Rotate stamp to follow path direction |
| `perpendicular_jitter_min/max` | -2.0 / 2.0 | Random offset perpendicular to path |
| `scale_min/max` | 0.8 / 1.2 | Random stamp scale range |
| `opacity_min/max` | 0.6 / 1.0 | Random stamp opacity range |
| `stamps_per_frame` | 10 | Number of stamps placed per draw cycle |
| `agent_count` | 1 | Number of simultaneous brushing agents |
| `post_completion_mode` | HOLD | HOLD / LOOP / PING_PONG — after path is complete |
| `blur_radius` | 0 | Post-processing blur radius |
| `pressure_size_influence` | 0.0 | Tablet pressure → stamp size |
| `pressure_alpha_influence` | 0.0 | Tablet pressure → stamp opacity |
| `meander_config` | MeanderConfig() | Path perturbation settings |

### Meander Config (`MeanderConfig`)

| Field | Default | Description |
|---|---|---|
| `enabled` | False | Enable path meandering |
| `amplitude` | 8.0 | Displacement amplitude (px) |
| `frequency` | 0.03 | Oscillation frequency |
| `samples` | 24 | Path subdivision samples |
| `seed` | 0 | Random seed |
| `animated` | False | Animate the meander over time |
| `anim_speed` | 0.01 | Animation speed |
| `scale_along_path` | False | Vary amplitude along path |
| `scale_along_path_frequency` | 0.05 | Frequency of along-path variation |
| `scale_along_path_range` | 0.4 | Range of along-path variation |

### Brush Library (`BrushLibrary` widget)

Displays available PNG files from `<project_dir>/brushes/`. Allows:
- Import PNG files to the brushes directory
- Enable/disable individual brushes
- Preview each brush in `BrushPreviewWidget` (dark background, pixel grid overlay at high zoom)

---

## Stencil Configuration (`StencilConfig`)

Used when `mode == STAMPED`. Similar to `BrushConfig` but stamps full-RGBA PNGs without tinting.

| Field | Default | Description |
|---|---|---|
| `stencil_names` | [] | List of PNG filenames in `brushes/` (shares directory with brushes) |
| `stencil_enabled` | [] | Per-stencil enable flag |
| `draw_mode` | FULL_PATH | FULL_PATH or PROGRESSIVE |
| `stamp_spacing` | 4.0 | Distance between stamps |
| `spacing_easing` | "LINEAR" | Easing for spacing variation |
| `follow_tangent` | True | Rotate stamp to follow path |
| `perpendicular_jitter_min/max` | -2.0 / 2.0 | Random perpendicular offset |
| `scale_min/max` | 0.8 / 1.2 | Random scale range |
| `stamps_per_frame` | 10 | Stamps per draw cycle |
| `agent_count` | 1 | Simultaneous agents |
| `post_completion_mode` | HOLD | Post-path behaviour |
| `opacity_change` | SizeChange() | Animated opacity (via SizeChangeEditor) |

---

## Data Model Hierarchy

```
RendererSetLibrary
  name         : str
  renderer_sets : List[RendererSet]

RendererSet
  name             : str
  enabled          : bool
  playback_mode    : PlaybackMode
  change_frequency : int
  renderers        : List[Renderer]

Renderer
  name                : str
  enabled             : bool
  mode                : RenderMode
  stroke_width        : float
  stroke_color        : Color
  fill_color          : Color
  point_size          : float
  hold_length         : int
  point_stroked       : bool
  point_filled        : bool
  stroke_width_change : SizeChange
  stroke_color_change : ColorChange
  fill_color_change   : FillColorChange
  point_size_change   : SizeChange
  brush_config        : Optional[BrushConfig]
  stencil_config      : Optional[StencilConfig]
```
