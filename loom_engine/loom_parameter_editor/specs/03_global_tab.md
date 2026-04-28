# Global Tab

**Source:** `ui/global_tab.py`  
**Model:** `models/global_config.py`  
**IO:** `file_io/global_config_io.py`  
**XML file:** `configuration/global_config.xml`

## Purpose

Edits project-wide settings: canvas dimensions, display colours, background image, engine selection, and legacy 3D/serial options.

## Layout

`GlobalTab` is itself a `QTabWidget` with two inner tabs:

### "Project" inner tab

Scroll area containing four groups:

**Project group** (QFormLayout)
- `Name` — `QLineEdit`; free-text project name (also updates `project.xml` `<Name>` on save)
- `Note` — `QTextEdit` (80 px fixed height); free-text notes

**Project Directory group**
- Read-only label showing the current projects directory (persisted in `AppSettings`, not in project XML)
- `Change...` button — opens a `QFileDialog.getExistingDirectory`, emits `projects_dir_changed` signal which `MainWindow` writes to `AppSettings`

**Loom Engine group**
- `Scala` / `Swift` radio buttons — emits `engine_changed` signal; `MainWindow` propagates to `RunTab` and `SubdivisionTab` and persists to `AppSettings`

**Canvas group** (QFormLayout)
- `Width` / `Height` — `QSpinBox` (1–16384); defaults 1080 × 1080

**Display group** (QFormLayout)
- `Fullscreen` — `QCheckBox`
- `Border Color` — `ColorPickerWidget` (RGBA)
- `Background Color` — `ColorPickerWidget` (RGBA); default white
- `Overlay Color` — `ColorPickerWidget` (RGBA); default semi-transparent black
- `Background Image` — label showing filename + `Background Image...` button that emits `background_image_browse_requested`; `MainWindow` handles the file dialog and calls `set_background_image_path()`
- `Output size` — read-only computed label (width × height × quality_multiple); updated by `MainWindow._update_output_hint()`

### "3D & Serial" inner tab

**3D Settings group** (labelled "not implemented")
- `Enable 3D` — `QCheckBox`
- `Camera View Angle` — `QSpinBox` (1–180)

**Serial Communication (Legacy) group**
- `Enable Serial` — `QCheckBox`
- `Port` — `QLineEdit`; default `/dev/ttyUSB0`
- `Mode` — `QComboBox`: `bytes`, `text`
- `Quantity` — `QSpinBox` (1–256)

## Data Model — `GlobalConfig`

| Field | Type | Default | Notes |
|---|---|---|---|
| `name` | str | "Untitled" | Project display name |
| `note` | str | "" | Free-text notes |
| `width` | int | 1080 | Canvas width in pixels |
| `height` | int | 1080 | Canvas height in pixels |
| `quality_multiple` | int | 1 | Render resolution multiplier (1–8); edited in RunTab |
| `scale_image` | bool | False | Scale pixel values by quality; edited in RunTab |
| `animating` | bool | False | Continuous draw loop; edited in RunTab |
| `draw_background_once` | bool | True | Background only on first frame; edited in RunTab |
| `subdividing` | bool | True | Master subdivision switch; edited in SubdivisionTab |
| `fullscreen` | bool | False | |
| `border_color` | Color | 0,0,0,255 | |
| `background_color` | Color | 255,255,255,255 | |
| `overlay_color` | Color | 0,0,0,170 | |
| `background_image_path` | str | "" | Absolute or relative path |
| `three_d` | bool | False | |
| `camera_view_angle` | int | 120 | |
| `serial` | bool | False | |
| `port` | str | "/dev/ttyUSB0" | |
| `mode` | str | "bytes" | "bytes" or "text" |
| `quantity` | int | 4 | |

## Split Ownership

Five `GlobalConfig` fields are not edited in `GlobalTab` — they live in sibling tabs and are patched together by `MainWindow._get_full_global_config()` before every save:

| Field | Edited in |
|---|---|
| `quality_multiple` | RunTab |
| `scale_image` | RunTab |
| `animating` | RunTab |
| `draw_background_once` | RunTab |
| `subdividing` | SubdivisionTab |

`GlobalTab.get_config()` returns placeholder values (1/False/True) for these five; callers must use `_get_full_global_config()` to get authoritative values.

## Signals

| Signal | Emitted when | Handler |
|---|---|---|
| `modified` | Any field changes | `MainWindow._on_modified()` |
| `background_image_browse_requested` | Browse button clicked | `MainWindow._on_background_image_browse()` |
| `projects_dir_changed(str)` | Directory changed | `MainWindow._on_projects_dir_changed()` |
| `engine_changed(str)` | Engine radio toggled | `MainWindow._on_engine_changed()` |

## XML Format

```xml
<GlobalConfig>
  <Name>MyProject</Name>
  <Note>Optional notes</Note>
  <Width>1080</Width>
  <Height>1080</Height>
  <QualityMultiple>1</QualityMultiple>
  <ScaleImage>false</ScaleImage>
  <Animating>false</Animating>
  <DrawBackgroundOnce>true</DrawBackgroundOnce>
  <Subdividing>true</Subdividing>
  <Fullscreen>false</Fullscreen>
  <BorderColor r="0" g="0" b="0" a="255"/>
  <BackgroundColor r="255" g="255" b="255" a="255"/>
  <OverlayColor r="0" g="0" b="0" a="170"/>
  <BackgroundImagePath></BackgroundImagePath>
  <ThreeD>false</ThreeD>
  <CameraViewAngle>120</CameraViewAngle>
  <Serial>false</Serial>
  <Port>/dev/ttyUSB0</Port>
  <Mode>bytes</Mode>
  <Quantity>4</Quantity>
</GlobalConfig>
```
