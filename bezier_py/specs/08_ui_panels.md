# UI Panels

All panels live in `ui/`. They communicate with `BezierWidget` via Qt signals.

---

## `ToolbarPanel` (`ui/toolbar_panel.py`)

Fixed-width side panel containing all mode-switching buttons and action buttons.

### Layout

Vertical `QVBoxLayout` with 11 named button groups. All mode buttons are `QPushButton` with `checkable=True`. Buttons are 40×40 px with 32×32 px icons loaded from `bezier/resources/images/`.

```css
/* _TOOLBAR_STYLE */
QPushButton { background: #3c3c3c; border: 1px solid #555; ... }
QPushButton:checked { background: #5a3a00; ... }   /* orange — selection modes */
QPushButton:hover   { background: #5a5a5a; ... }
```

Creation mode buttons are highlighted green when checked. Selection mode buttons are highlighted orange.

### Button Groups

| Group | Buttons |
|---|---|
| Drawing | Default (closed polygon), Open Curve, Freehand, Oval, Point |
| Selection | Polygon Selection, Edge Selection, Point Selection, Open Curve Selection |
| Tools | Knife, Mesh Build |
| Transform | Flip H, Flip V, Center, Simplify |
| Geometry | Close Curve, Create Oval, Weld All |
| Edit | Undo, Redo, Select All, Deselect, Copy, Paste, Cut, Delete |
| Layers | New Layer, Delete Layer |
| File | Save, Load |
| View | Toggle Reference Image |
| Help | Help (F1) |

### Signal

`mode_changed(str)` — emitted when a mode button is clicked. The string is the mode name. Connected to `BezierWidget._set_mode`.

### Sync

`_sync_buttons(mode_name)` is connected to `BezierWidget.mode_changed`. It sets the `checked` state of all mode buttons to match the new mode, and updates button highlight colours.

---

## `LayerPanel` (`ui/layer_panel.py`)

Fixed width: **280 px**. Displays the layer list and trace layer controls.

### Layout

```
LayerPanel (QWidget, 280px)
├── Layer list header ("Layers")
├── QTableWidget
│   └── Columns: Vis (checkbox) | # (index) | Name (bold if active)
├── New / Rename / Duplicate / Delete / ↑ / ↓ buttons
└── TraceLayerWidget (collapsible)
    ├── Load Trace Image button
    ├── Scale QDoubleSpinBox (0.10–4.00, step 0.05)
    ├── Alpha QDoubleSpinBox (0.00–1.00, step 0.05)
    └── Visible checkbox
```

Layer rows are displayed in **reverse** list order — the most recently added layer appears at the top. The active layer is shown in bold. Clicking a row activates that layer.

### TraceLayerWidget

Collapsible `QGroupBox` that is shown only when a trace layer exists. Controls update `Layer.trace_scale` and `Layer.trace_alpha` on the active trace layer and emit signals back to `BezierWidget`.

### Signals emitted by `LayerPanel`

| Signal | Payload | Description |
|---|---|---|
| `layer_selected` | `int` (layer ID) | User clicked a row |
| `layer_visibility_changed` | `int, bool` | Vis checkbox toggled |
| `layer_created` | — | New button clicked |
| `layer_deleted` | `int` | Delete button clicked |
| `layer_renamed` | `int, str` | Rename dialog confirmed |
| `layer_duplicated` | `int` | Duplicate button clicked |
| `layer_moved_up` | `int` | ↑ button clicked |
| `layer_moved_down` | `int` | ↓ button clicked |
| `trace_scale_changed` | `float` | Scale spinbox changed |
| `trace_alpha_changed` | `float` | Alpha spinbox changed |
| `trace_visible_changed` | `bool` | Visible checkbox changed |

### `refresh()`

Rebuilds the `QTableWidget` from the current `LayerManager` state. Called whenever `BezierWidget.layer_changed` fires.

---

## `NamePanel` (`ui/name_panel.py`)

Compact panel containing a name field and Save / Load buttons.

### Layout

```
NamePanel (QWidget)
├── QLineEdit  (name field)
├── Save button
└── Load… button
```

The name field holds the active shape name. On startup it is populated from the `--name` CLI argument.

### Signals

| Signal | Description |
|---|---|
| `save_requested` | Save button clicked; `BezierApp._on_save` is called |
| `load_requested` | Load button clicked; `BezierApp._load_file` is triggered via file dialog |

### `get_name()` / `set_name(name)`

Used by `BezierApp` to read the current name before saving and to set the name when a file is loaded.

---

## `SliderPanel` (`ui/slider_panel.py`)

Panel containing scale and rotate sliders for gesture-based transforms. Located below the canvas.

### Layout

```
SliderPanel (QWidget)
├── 280px left spacer (aligns sliders with canvas, not layer panel)
├── Scale group (QGroupBox)
│   ├── Slider  −100..100 (maps to ×0.5..×2.0 or similar)
│   ├── XY / X / Y radio buttons  (scale axis)
│   └── Anchors+Controls / Anchors only / Controls only QComboBox
└── Rotate group (QGroupBox)
    ├── Slider  −100..100 → ×1.8 → −180..180°
    └── Local / Common / Absolute radio buttons  (rotation pivot)
```

The 280 px left spacer aligns the sliders under the canvas rather than under the layer panel.

### Slider behaviour

Sliders are `Qt.Horizontal QSlider` with a range of `−100..100`. While dragging:
- Scale slider: `apply_scale(factor, axis, scope)` called on `BezierWidget` with each value change.
- Rotate slider: `apply_rotation(degrees, pivot_mode)` called on each value change.

On `sliderReleased`: save the committed origin positions (`save_current_pos` on all affected points) and reset the slider back to 0. Emits `transform_committed` to tell `BezierWidget` to push an undo snapshot.

### Scale parameters

| Radio | Effect |
|---|---|
| XY | Uniform scale in both axes |
| X | Scale X axis only |
| Y | Scale Y axis only |

| Scope dropdown | Effect |
|---|---|
| Anchors+Controls | Scale all points |
| Anchors only | Scale only anchor points |
| Controls only | Scale only control points |

### Rotate parameters

| Radio | Pivot |
|---|---|
| Local | Each polygon rotates around its own centroid |
| Common | All selected items rotate around their shared centroid |
| Absolute | Rotate around canvas centre (520, 520) |
