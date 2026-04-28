# Shared Widgets

All shared widgets live in `ui/widgets/`. They are re-used across multiple tabs.

---

## `ColorPickerWidget` (`ui/widgets/color_picker.py`)

A compact RGBA colour selector.

### Interface

```python
class ColorPickerWidget(QWidget):
    colorChanged = Signal()

    def __init__(self, show_alpha: bool = True, parent=None)
    def get_color() -> Color
    def set_color(color: Color)
```

### Layout

Row of elements:
- Colour swatch (clickable `QLabel` that opens `QColorDialog`)
- R/G/B/A `QSpinBox` fields (0–255); alpha only shown when `show_alpha=True`
- Hex input field (optional, synced to RGB)

Clicking the swatch opens `QColorDialog`. On accept, all spinboxes update and `colorChanged` is emitted. Changes to any spinbox also update the swatch and emit `colorChanged`.

---

## `PaletteEditorWidget` (`ui/widgets/palette_editor.py`)

An editable list of RGBA colours for sequential/random colour-change palettes.

### Interface

```python
class PaletteEditorWidget(QWidget):
    changed = Signal()

    def get_palette() -> List[Color]
    def set_palette(palette: List[Color])
```

### Layout

- `QListWidget` showing colour swatches
- `+ Color` button — add a new colour (opens colour picker)
- `- Color` button — remove selected
- `Edit` button — re-edit selected colour
- `↑ / ↓` buttons — reorder
- `Load Palette…` / `Save Palette…` — read/write JSON palette files from `palettes/`

Each list item renders as a filled rectangle showing the colour.

---

## `SizePaletteEditorWidget` (`ui/widgets/size_palette_editor.py`)

An editable list of float values for sequential/random size-change palettes (stroke width or point size).

### Interface

```python
class SizePaletteEditorWidget(QWidget):
    changed = Signal()

    def get_palette() -> List[float]
    def set_palette(palette: List[float])
```

### Layout

- `QTableWidget` (single column) with inline-editable float cells
- `+ Value` / `- Value` buttons
- `↑ / ↓` reorder buttons

---

## `EnumDropdown` (`ui/widgets/enum_dropdown.py`)

A labelled `QComboBox` bound to a Python `Enum` class.

### Interface

```python
class EnumDropdown(QWidget):
    valueChanged = Signal(object)   # emits the selected Enum value

    def __init__(self, enum_class, label: str = "", parent=None)
    def get_value() -> Enum
    def set_value(value: Enum)
```

Populates from `enum_class` members. Selection changes emit the `Enum` instance (not the name or int).

---

## `RendererTreeWidget` (`ui/widgets/renderer_tree.py`)

The main tree control for the Rendering tab. Wraps `QTreeWidget` with add/remove/reorder operations for `RendererSet` and `Renderer` objects.

### Interface

```python
class RendererTreeWidget(QWidget):
    selectionChanged = Signal(object)  # emits RendererSet or Renderer

    def set_library(library: RendererSetLibrary)
    def get_library() -> RendererSetLibrary
    def _add_set()
    def _remove_set()
    def _add_renderer()
    def _remove_renderer()
    def _refresh_tree()
```

The tree uses `QTreeWidgetItem.setData(Qt.UserRole, obj)` to store model objects on each item. The "Enabled" column uses item checkboxes. Drag-and-drop reorder within the same parent is supported.

---

## `BrushEditorWidget` / `BrushEditorWindow` (`ui/widgets/brush_editor.py`, `ui/widgets/brush_editor_window.py`)

Edits a `BrushConfig`. `BrushEditorWidget` is the inline form panel; `BrushEditorWindow` wraps it in a standalone floating `QDialog`.

### Layout (`BrushEditorWidget`)

`QScrollArea` containing groups:
- **Brush Library** — `BrushLibraryWidget` (below)
- **Draw Mode** — `EnumDropdown` (FULL_PATH / PROGRESSIVE)
- **Spacing** — stamp_spacing, spacing_easing
- **Path Behaviour** — follow_tangent, perpendicular_jitter_min/max
- **Scale** — scale_min/max
- **Opacity** — opacity_min/max
- **Timing** — stamps_per_frame, agent_count
- **Post-completion** — `EnumDropdown` (HOLD / LOOP / PING_PONG)
- **Effects** — blur_radius
- **Pressure** — pressure_size_influence, pressure_alpha_influence
- **Meander** — all `MeanderConfig` fields in a collapsible group box

---

## `BrushLibraryWidget` (`ui/widgets/brush_library.py`)

Displays and manages the brush PNG library for a project.

### Interface

```python
class BrushLibraryWidget(QWidget):
    selectionChanged = Signal(list)  # list of selected brush names

    def set_directory(brushes_dir: str)
    def set_brush_config(config: BrushConfig)
    def get_brush_config() -> BrushConfig
```

### Layout

- `QListWidget` — one item per PNG in `brushes/`; each item has a checkbox (enable/disable) and a small thumbnail
- `Import Brush…` button — copy a PNG into `brushes/`
- `Remove` button — delete selected brush file (with confirmation)
- `BrushPreviewWidget` — shows the selected brush at full resolution with pixel grid

`BrushPreviewWidget` is defined in `ui/rendering_tab.py`. It renders on a `#111111` background. When the brush image is large enough, it draws a pixel grid to help with precise alignment.

---

## `StencilEditorWindow` / `StencilLibraryWidget` (`ui/widgets/stencil_editor_window.py`, `ui/widgets/stencil_library.py`)

Mirrors the brush editor system for `StencilConfig` / STAMPED mode. The stencil library uses the same `brushes/` directory as brush PNGs (both are stamp images). The stencil editor omits opacity controls (opacity is handled via `opacity_change: SizeChange`) and pressure inputs.

---

## `BitmapPolygonDialog` (`ui/widgets/bitmap_polygon_dialog.py`)

A `QDialog` for the bitmap polygon tracing workflow.

### Layout

`QFormLayout` with:
- Source image field + Browse button
- Threshold spinner
- Invert checkbox
- Smoothing passes spinner
- Min polygon size spinner
- Output name field

Preview pane showing the thresholded mask.

On accept: runs the tracing algorithm, writes output to `polygonSets/<name>.poly.xml`, emits completion signal.

---

## `SpritePreviewWidget` (`ui/sprite_preview_widget.py`)

A live canvas preview in the Sprites tab showing sprite positions schematically.

### Interface

```python
class SpritePreviewWidget(QWidget):
    def set_sprite_library(library: SpriteLibrary)
    def set_canvas_size(width: int, height: int)
    def set_selected_sprite(sprite_def: SpriteDef)
    def refresh()
```

### Rendering

- Background: grey rectangle representing the canvas, scaled to fit the widget.
- Each sprite: coloured rectangle at `(location_x, location_y)` scaled by `(size_x, size_y)`.
- Selected sprite: highlighted with a brighter border.
- Canvas centre crosshair.
- Does not require a live engine — purely editor-side geometry.

The scale mapping from canvas coordinates to widget coordinates uses:
```
scale = min(widget_w / canvas_w, widget_h / canvas_h)
```

---

## `ChangeEditors` (`ui/widgets/change_editor.py`)

Three editor widgets for the three change types used in `Renderer`:

| Class | Edits | Parent |
|---|---|---|
| `SizeChangeEditor` | `SizeChange` | `QGroupBox` (checkable) |
| `ColorChangeEditor` | `ColorChange` | `QGroupBox` (checkable) |
| `FillColorChangeEditor` | `FillColorChange` | `QGroupBox` (checkable) |

`SizeChangeEditor` and `FillColorChangeEditor` extend `ColorChangeEditor`. All three share:
- `EnumDropdown` for `kind`, `motion`, `cycle`, `scale`
- Numeric fields for `min`, `max`, `increment`, `pause_max`
- Palette section (shown only when `kind ∈ {SEQ, RAN}`)

`ColorChangeEditor` additionally shows colour pickers for `min_color`, `max_color`, `increment`, `pause_color_min/max`, and a `pause_channel` dropdown.

All three emit a `changed` signal whenever any field is edited.
