# Bezier Py to Swift Inventory and Behavior Map

This note is a first-pass migration map for bringing `bezier_py` into the current
single Swift Loom app. The legacy three-part system should remain intact; this
map is for the integrated Swift path.

## Current Integrated App Frame

The Swift app already has the target shell for the migration:

- Top run/render toolbar: media state, still/video export, render-directory access.
- Tab bar: Global, Geometry, Subdivision, Sprites, Rendering.
- Left panel: per-tab collapsible or grouped item lists.
- Main view: live canvas, wireframes, or editing surface depending on selected tab.
- Right inspector: per-selection parameter controls.

The Bezier migration belongs primarily in the Geometry tab, with reusable model,
math, and XML code placed in `LoomEngine` where possible.

## Bezier Py Package Inventory

### Entry and Orchestration

- `main.py`: CLI startup contract for legacy subprocess use.
- `ui/bezier_app.py`: top-level Qt window, menu wiring, save/load dispatch,
  trace/reference image loading, auto-save on close.

Swift destination:

- Legacy subprocess contract becomes optional compatibility behavior.
- Integrated behavior should move into Geometry tab actions and project-aware
  save/update methods on `AppController`.

### UI Panels

- `ui/toolbar_panel.py`: mode buttons and actions.
- `ui/layer_panel.py`: geometry layers plus singleton trace layer controls.
- `ui/name_panel.py`: shape name and Save/Load.
- `ui/slider_panel.py`: scale and rotate gesture controls.

Swift destination:

- Mode/actions should become text-labeled controls in the Geometry tab side
  panels. Prefer labels over icons if icons veer away from the broader Loom app
  visual style.
- Layers naturally fit the Geometry tab left panel when editing a geometry item.
- Shape name and file identity fit the right Geometry inspector.
- Scale/rotate controls can begin as inspector controls or a bottom strip. Exact
  placement can stay minimal until behavior is stable.

### Canvas and Interaction

- `canvas/draw_panel.py`: `BezierWidget`, central state owner, render loop,
  undo/redo, modes, keyboard handling, selection, layer operations.
- `canvas/mouse_handler.py`: press/drag/release dispatch by mode.
- `canvas/render_engine.py`: all drawing of grid, curves, handles, selections,
  ovals, points, overlays, freehand preview, knife, mesh.

Swift destination:

- Main Geometry view should become a SwiftUI `Canvas`-based editor or an
  `NSViewRepresentable` if event handling becomes too dense for SwiftUI gestures.
- The first functional target should preserve the 1040x1040 canvas model,
  1000x1000 active grid, and 20 px edge offset, even if displayed responsively.

### Model

- `model/cubic_point.py`: anchor/control point identity and drag behavior.
- `model/cubic_curve.py`: one cubic segment of 4 points.
- `model/cubic_curve_manager.py`: one closed polygon or open curve.
- `model/polygon_manager.py`: committed managers plus active drawing manager.
- `model/oval_manager.py`: axis-aligned ovals.
- `model/layer.py`, `model/layer_manager.py`: geometry and trace layers.
- `model/weld_registry.py`: linked point movement.
- `model/geometry_snapshot.py`: undo/redo snapshots.

Swift destination:

- These should be migrated as pure Swift model types first, likely in
  `LoomEngine` or a new `LoomGeometry` sub-area, with UI-independent tests.
- Weld identity needs careful design because Python relies on object identity and
  shared point references. Swift should probably use stable point IDs rather than
  value copies for editable geometry.

### Tools

- `canvas/curve_fitter.py`: Schneider freehand fitting.
- `canvas/knife_tool.py`: De Casteljau line cutting for closed polygons.
- `canvas/intersect_tool.py`: annular quad creation from compatible polygons.
- `model/weld_registry.py`: manual and automatic weld behavior.

Swift destination:

- Migrate after the base model and XML parity are in place.
- Each tool should get fixture-based Python-vs-Swift comparison tests before UI
  integration, because these are the easiest places to lose subtle behavior.

### File IO

- `bezier_io/polygon_set_xml.py`: closed polygon and open-curve read/write.
- `bezier_io/open_curve_set_xml.py`: open curve save and layer-set variants.
- `bezier_io/oval_set_xml.py`: oval read/write.
- `bezier_io/point_set_xml.py`: point set read/write.
- `bezier_io/layer_set_xml.py`: multi-layer manifest.
- `bezier_io/svg_exporter.py`, `svg_importer.py`: SVG interoperability.

Swift destination:

- Existing Swift `XMLPolygonLoader` and `XMLPolygonWriter` cover part of this,
  but not the full Bezier authoring contract.
- The save pipeline must preserve Bezier's exact coordinate conversion and
  DOCTYPE conventions where existing Loom projects depend on them.

### Legacy Geometry Generators

The legacy Loom editor has two geometry-creation paths that are conceptually
part of the new integrated Bezier authoring system:

- Regular polygons: currently a Geometry sub-tab/dialog that writes an editor
  regular-polygon source and registers it in the shared polygon library.
- Bitmap polygons: currently a Geometry sub-tab/dialog that traces bitmap
  outlines or generates bitmap-derived meshes, writes polygon-set XML, then
  refreshes the polygon-set list.

Swift destination:

- Treat both as geometry creation modes/tools inside the integrated Geometry
  authoring surface, not as separate long-term tabs.
- Regular polygons can be a parameterized creation tool that produces editable
  Bezier/linear polygon geometry or stores parametric `regularParams` when that
  is the better project representation.
- Bitmap tracing should become a source/import tool that writes normal
  polygon-set geometry, then opens it in the same Bezier editing model for
  cleanup.

## Behavior Map by Integrated Loom Area

### Geometry Tab Left Panel

Current Swift behavior:

- Lists Algorithmic, Polygon Sets, Curve Sets, and Point Sets.
- Supports rename, duplicate, delete.
- Creation buttons are placeholders.

Bezier behavior to integrate:

- The left side should focus on layers while the Geometry editor is active,
  keeping the main view the same scale as other tab main views.
- Layer controls:
  - New.
  - Rename.
  - Duplicate.
  - Delete.
  - Shift selected up.
  - Shift selected down.
- Shift up/down can later be replaced or supplemented by drag-and-drop ordering
  if that feels natural in SwiftUI.
- Project geometry lists can remain available in the existing Geometry-tab
  structure when no editor session is active, but active creation/editing should
  prioritize layer management here.

### Geometry Main View

Current Swift behavior:

- Shows a wireframe preview of the selected geometry.
- Falls back to live render when no geometry is selected.

Bezier behavior to integrate:

- Editable 1040x1040 canvas with 20 px margin and 1000 px active grid.
- Preserve the main-view footprint used by the other tabs as much as possible:
  keep layers and tools in the left/right panels, not in extra main-view chrome.
- Closed polygon drawing, open curve drawing, point placement, oval creation.
- Selection modes for polygons/open curves, edges, and points.
- Handle drawing and dragging.
- Rubber-band selection.
- Reference/trace image rendering.
- Tool overlays for freehand, knife, and mesh build.
- Regular polygon creation preview and bitmap-trace/bitmap-mesh preview, as
  part of the same geometry authoring canvas once the base editor is stable.
- The editor needs a clear control to return to the default geometry display
  after entering a specialized creation/editing view.

### Geometry Inspector

Current Swift behavior:

- Shows selected geometry metadata and quick setup actions.
- Supports regular polygon parameter editing.

Bezier behavior to integrate:

- The right side should hold most creation/editing controls as collapsible
  sections. This is worth prototyping and discussing, because there are enough
  controls that a permanently expanded inspector may become noisy.
- Prefer text-labeled buttons over icon-only buttons unless a specific icon is
  already established elsewhere in Loom.

Proposed collapsible sections:

- **Create**
  - Points.
  - Oval.
  - Regular polygons.
  - Point-by-point drawing.
  - Finalise polygon.
  - Finalise open curve.
  - Mesh build.
  - Freehand draw with a detail slider; record pressure sensitivity when
    available.
  - Bitmap to polygon.
- **Edit**
  - Points.
  - Edges.
  - Open curves.
  - Polygons.
- **Weld**
  - Auto-weld toggle.
  - Weld adjacent edges.
- **Multiply**
  - Duplicate.
  - Knife. Polygon-only initially; later extend to open curves.
  - Intersect.
- **Transform**
  - Flip horizontally.
  - Flip vertically.
  - Move by dragging.
  - Scale with axis choice: XY, X, or Y.
  - Scale scope: anchors and controls, anchors only, or controls only.
  - Rotate around each selected item's local centre, the common selection centre,
    or the absolute canvas centre.
- **View**
  - Zoom in.
  - Zoom out.
  - Centre selected; if nothing is selected, centre all.
  - Toggle grid display.
  - Toggle control point display.
- **Delete**
  - All geometry.
  - Only selected geometry.
- **File**
  - Name field.
  - Save.
  - Load.

Slider width may be a practical issue in the right panel, especially for scale
controls if the panel width stays close to the current left-panel width. Prefer
compact numeric fields, segmented axis/scope controls, or a popover for dense
transform options if narrow sliders feel imprecise.

Bitmap to polygon is the trickiest creation mode and has two plausible layouts:

- A separate modal/window dedicated to bitmap tracing and mesh generation.
- An in-place specialized Geometry view: top area shows the bitmap, with
  threshold and output-quality controls directly beneath; bottom area shows the
  output mesh, with Quad Mesh and output-name fields beneath; the right-side
  completion button exits this specialized view and returns to normal geometry
  editing.

The in-place approach better preserves the feeling of one integrated Geometry
editor, but it must not permanently shrink the standard editing canvas. This can
be decided later, after hand-drawn polygon editing is stable.

### Top Toolbar

Current Swift behavior:

- Playback, export, project/render access.

Bezier behavior to integrate:

- Most Bezier editing controls should probably not enter the global toolbar.
- Only project-level save/reload/render behaviors should stay global.
- Geometry-specific tools are better scoped to the Geometry tab main view so the
  other four tabs remain stable.

## Critical Behavior Contracts

### Coordinate Contract

Preserve these constants:

- Canvas size: 1040 x 1040 px.
- Active grid: 1000 x 1000 px.
- Edge offset: 20 px.
- Canvas center: 520, 520.

Polygon/point save:

```text
xml = round(round((canvas / 1000 - 0.5 - 0.02) * 100)) / 100.0
```

Polygon/point load:

```text
canvas = (xml + 0.02) * 1000 + 500
```

Oval center/radius uses its own pipeline and must not be collapsed into the
polygon pipeline.

### File Contract

- Geometry type should be authoritative in project config and XML/JSON
  root/type fields, not inferred from filename suffix.
- Filenames should be treated as storage identity. Prefer simple stable filenames
  such as `<name>.xml` or `<name>.json` inside type-specific folders
  (`polygonSets/`, `curveSets/`, `pointSets/`, `ovalSets/`) for new Swift-authored
  files.
- Keep compatibility when reading or referencing legacy `.poly.xml`,
  `.curve.xml`, and `.points.xml` files, especially morph targets and existing
  legacy projects.
- `polygonSet` files need the DOCTYPE line for legacy engine compatibility.
- Multi-layer manifests are authoring metadata; individual layer polygon files
  remain engine-readable.
- SVG export is non-critical for Loom runtime but useful for parity.

The legacy system is file-based: Bezier, the parameter editor, and the engine
exchange geometry and configuration through files on disk rather than through a
live in-memory model. The Swift path should preserve that project-file contract
even if the app feels more integrated. In practice this means:

- XML read/write parity remains required for existing projects and for as long as
  the legacy engine/editor can open the same geometry.
- JSON should be the new standard for Swift-authored project and geometry data,
  with explicit migration/export paths back to legacy XML where needed.
- The integrated editor may keep an editable in-memory model while a project is
  open, but save/load/reload boundaries should still be clear and testable as
  file operations.

The advantage of integration is not that files disappear. The advantage is that
the user can create, inspect, register, preview, and render geometry in one app
without manually handing files between Bezier, editor, and engine. The risk is
that hidden live state could make projects harder to reason about. The safe
target is therefore an integrated UI with explicit file-backed project state.

### Interaction Contract

- Exactly one mode is active at a time.
- Default mode draws closed cubic polygons using the four-click segment state
  machine.
- Open curves use the same segment model but finish as non-closed managers.
- Point and oval modes create non-polygon geometry.
- Selection has whole-polygon/open-curve, edge, point, and oval targets.
- Cmd-click means discrete selection; default means relational selection.
- Welded points move together.
- Undo/redo is snapshot-based with a 20-entry cap.

### Layers Contract

Layers should be treated as a durable authoring concept, not merely a temporary
UI convenience. They provide named grouping for geometry that belongs together
and a path for exporting or registering related geometry as separate named files.

The distinction:

- As a first-class geometry concept, layers are saved with stable IDs/names,
  participate in selection/visibility/editing rules, and can be mapped to
  separate output files or engine-readable polygon sets.
- As a convenience, layers would only be editor UI state: useful while drawing,
  but flattened or discarded when saving.

For Loom, first-class authoring layers are the better fit because they preserve
the existing multi-file workflow while giving the integrated Geometry tab a
clear way to distinguish related geometry from geometry that should become
separate named files. The engine does not necessarily need to understand layers
directly; the authoring layer set can compile/export into the existing geometry
files the engine already reads.

### Algorithmic Geometry Contract

Regular polygons and ovals should remain parametric/algorithmic where that is
the user's chosen source representation. This matches the revised Geometry tab's
algorithmic polygon group and preserves editable intent: side count, radius,
rotation, oval center/radii, and similar source parameters remain available
after reload.

Generated polygon geometry is still useful. Regular polygons can be baked into
polygon sets at subdivision or export time when the downstream operation needs
explicit vertices. The important rule is to avoid accidental loss of source
intent: baking should be an explicit stage or derived artifact, not the only
stored representation unless the user asks to convert the shape to editable
polygon geometry.

## Suggested Migration Slices

1. **Parity fixtures**
   Generate or collect small `.xml` fixtures for polygon, open curve, oval,
   point, layer set, pressure open curve, SVG import, knife/intersect examples.
   Include legacy filename suffix fixtures and paired XML/JSON migration fixtures.

2. **Swift editable geometry model**
   Add editable cubic point/curve/manager/layer/weld/snapshot types with tests.
   Do not connect UI yet.

3. **Bezier XML authoring parity**
   Implement Swift read/write for the authoring formats, including exact
   coordinate conversion, DOCTYPE, pressure, oval, point, and layer manifests.

4. **Read-only Bezier editor canvas**
   Replace or augment the current Geometry wireframe with the Bezier canvas
   coordinate system, grid, layers, handles, ovals, points, and trace/reference
   display.

5. **Minimal creation/editing**
   Implement one geometry type and creation mode at a time, beginning with closed
   hand-authored polygon drawing, handle drag, finish curve, save, and reload.
   This gives the first useful integrated replacement and keeps each behavior
   small enough to perfect before adding the next mode.

6. **Selection and transforms**
   Add polygon/open/point/edge selection, rubber-band, delete, copy/paste,
   scale/rotate, undo/redo.

7. **Additional geometry types**
   Add point sets, ovals, open curves, and freehand fitting step by step, with
   each type getting save/load fixtures and basic editing before moving on.

8. **Legacy generators**
   Migrate regular polygon creation as parametric/algorithmic geometry first.
   Migrate bitmap polygon tracing/mesh generation after hand-drawn curves and
   polygons reach save/load parity.

9. **Advanced tools**
   Add weld, knife, intersect, mesh build, SVG import/export, layered save/load.

10. **App integration cleanup**
   Register newly saved geometry in `ProjectConfig`, trigger engine reload,
   preserve quick setup workflows, and only then refine the UI.

## Resolved Questions and Current Direction

- **File naming and formats:** Support legacy suffixes in the new/revised system
  because existing projects still need to open in the legacy system. New
  Swift-authored data should use JSON as the standard format, likely with simple
  stable names inside type-specific folders. Readers and project references must
  still understand `.poly.xml`, `.curve.xml`, `.points.xml`, and other legacy
  contracts. XML remains a compatibility and export target, not the preferred
  new authoring format.
- **Model/module placement:** Use the most practical and efficient module
  boundary. Start with the editable geometry model wherever it keeps development
  simple and testable; move shared, stable pieces into `LoomEngine` when the
  engine or other tabs need them.
- **Layers:** Treat layers as durable authoring structure. They distinguish
  geometry that belongs together from geometry that should be exported or
  registered as different named files. The engine can still receive flattened or
  separate geometry files.
- **Integrated architecture:** Preserve files as the project interchange
  boundary. The integrated Swift app should reduce manual movement between
  Bezier, editor, and engine, but should not hide the fact that geometry is saved,
  reloaded, registered, and rendered through file-backed project state.
- **Migration style:** Work step by step through all geometry types and creation
  modes. Prefer smaller complete slices over a broad partial port.
- **First editing slice:** Start with closed polygons only. This is the clearest
  first useful target and gives a focused path for canvas interaction, save/load,
  and later selection behavior.
- **Regular polygons and ovals:** Maintain parametric/algorithmic geometry types
  where useful. Baking to polygon sets remains appropriate at subdivision/export
  time, but should not erase source parameters unless explicitly converting to
  editable polygon geometry.
- **Bitmap polygons:** Migrate after hand-drawn curves and polygons.
- **Keyboard shortcuts:** Preserve well-known system shortcuts such as Cmd-X,
  Cmd-C, and Cmd-V. Other Bezier-specific shortcuts can be reconsidered, and a
  later preferences screen for shortcut customization is likely worthwhile.
