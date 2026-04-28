# Project Model and File Structure

## Project Manifest (`project.xml`)

The manifest is the root file of every Loom project. It is stored at `<project_dir>/project.xml`.

### XML Structure

```xml
<?xml version='1.0' encoding='UTF-8'?>
<LoomProject version="1.0">
  <Name>MyProject</Name>
  <Description></Description>
  <Created>2025-11-01T14:22:00</Created>
  <Modified>2025-11-01T14:22:00</Modified>
  <Files>
    <File domain="global"      path="configuration/global_config.xml"/>
    <File domain="rendering"   path="configuration/rendering.xml"/>
    <File domain="polygons"    path="configuration/polygons.xml"/>
    <File domain="subdivision" path="configuration/subdivision.xml"/>
    <File domain="shapes"      path="configuration/shapes.xml"/>
    <File domain="sprites"     path="configuration/sprites.xml"/>
    <File domain="curves"      path="configuration/curves.xml"/>
    <File domain="points"      path="configuration/points.xml"/>
    <File domain="ovals"       path="configuration/ovals.xml"/>
  </Files>
</LoomProject>
```

### Python Model — `models/project.py`

```
Project
  name        : str          — display name
  description : str          — free-text note
  created     : datetime     — ISO 8601, set at project creation
  modified    : datetime     — ISO 8601, updated on every save (touch())
  files       : List[ProjectFile]
  version     : str          — always "1.0"

ProjectFile
  domain : str  — lookup key (global, rendering, polygons, subdivision, shapes, sprites, curves, points, ovals)
  path   : str  — relative path from project directory
```

`Project.add_file(domain, path)` replaces any existing entry for the same domain before appending.

### IO Class — `file_io/project_io.py`

| Method | Description |
|---|---|
| `ProjectIO.load(file_path)` | Parse XML into `Project` |
| `ProjectIO.save(project, file_path)` | Serialise `Project` to XML |
| `ProjectIO.create_new(name)` | Return a new `Project` with default `rendering` file reference |

XML library: **lxml** (`etree.parse` / `etree.ElementTree.write`). Datetime format: `%Y-%m-%dT%H:%M:%S`.

## Domain Config Files

Each domain has its own IO class in `file_io/`:

| Domain | File | IO class | Tab |
|---|---|---|---|
| `global` | `configuration/global_config.xml` | `GlobalConfigIO` | Global |
| `rendering` | `configuration/rendering.xml` | `RenderingIO` | Rendering |
| `polygons` | `configuration/polygons.xml` | `PolygonConfigIO` | Geometry → Spline/Regular Polygons |
| `subdivision` | `configuration/subdivision.xml` | `SubdivisionConfigIO` | Subdivision |
| `sprites` | `configuration/sprites.xml` | `SpriteConfigIO` | Sprites |
| `shapes` | `configuration/shapes.xml` | `auto_generate_shapes_xml()` | auto-generated |
| `curves` | `configuration/curves.xml` | `OpenCurveConfigIO` | Geometry → Curves |
| `points` | `configuration/points.xml` | `PointConfigIO` | Geometry → Points |
| `ovals` | `configuration/ovals.xml` | `OvalConfigIO` | Geometry → Ovals |

`shapes.xml` is the only file that is never read by the editor — it is written only (from `sprites.xml` data) for Scala backward compatibility.

## Project Subdirectories

| Directory | Purpose |
|---|---|
| `configuration/` | All XML config files |
| `polygonSets/` | Bezier-exported `.poly.xml` polygon geometry files |
| `curveSets/` | Bezier-exported `.curve.xml` open curve geometry files |
| `pointSets/` | Point set geometry files |
| `regularPolygons/` | Editor-generated regular polygon XML (editor-only, not read by engine) |
| `morphTargets/` | Morph-target geometry files (`.poly.xml` or `.curve.xml`) |
| `brushes/` | PNG brush images consumed by the BRUSHED renderer |
| `background_image/` | Optional background image files |
| `palettes/` | Colour palette JSON files |
| `renders/stills/` | Still image captures |
| `renders/animations/` | Animation frame captures |

## Save Sequence

`MainWindow._do_save()` executes these steps in order:

1. `project.touch()` — update modified timestamp.
2. Ensure all 9 domain file references exist in the project manifest.
3. Update project name from Global tab.
4. `ProjectIO.save()` — write `project.xml`.
5. Save each domain in tab order: global → rendering → polygons → subdivision → sprites.
6. `auto_generate_shapes_xml()` — write `shapes.xml` from sprite geo data.
7. Save curves → points → ovals.
8. Update recent-projects list in app settings.

## Save As / Copy Behaviour

`_save_project_as()` creates a new directory structure and copies:
- `polygonSets/` — all `.poly.xml` files
- `regularPolygons/` — all regular polygon XML files
- `curveSets/` — all `.curve.xml` files
- `pointSets/` — all point set files

The curveSets and pointSets data are also copied to preserve geometry assets that are referenced by path in the config files.

## Open Project Dialog

`OpenProjectDialog` scans the configured projects directory for subdirectories that contain `project.xml`. It presents a table with columns: `#`, `Name` (folder name), `Date` (directory creation, `st_birthtime`), `Edited` (`project.xml` mtime). Uses `DontUseNativeDialog` to avoid macOS hiding `~/.loom_projects` (dot-prefixed directory).

## Recent Projects

Stored in `AppSettings.recent_projects` (max 10). Populated via `add_recent_project()` on every successful open or save. Rendered as a "File → Open Recent Project" submenu. Stale entries (directory no longer exists) are pruned on access.
