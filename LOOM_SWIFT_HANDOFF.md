# Loom Swift Integration – General Handoff

Last updated: 2026-05-08

This document covers the full Loom Swift Integration app, organised by tab/area. For geometry-editor-specific detail, see `GEOMETRY_EDITOR_HANDOFF.md`.

---

## What is implemented

### App shell and project management

- Launch screen: create a new project by name, open an existing project via folder picker.
- New projects receive the full Loom directory structure on creation:
  `polygonSets`, `curveSets`, `pointSets`, `ovalSets`, `regularPolygons`,
  `background_image`, `brushes`, `configuration`, `morphTargets`,
  `palettes`, `stamps`, `svgs`, `renders/stills`, `renders/animations`.
- New projects include three default brush PNGs (`circle.png`, `soft_circle.png`, `scatter.png`) written to `brushes/` by `DefaultBrushes.swift`.
- AppController is the single shared observable state holder; all tabs bind to it.
- Global inspector (right panel) carries a permanent Status section at the bottom for feedback/debug text.
- Config edits (colours, sliders) are debounced and committed on a background queue; the render canvas does not blank between ticks.

### Geometry tab

Fully featured — see `GEOMETRY_EDITOR_HANDOFF.md` for the complete list.
Summary: layered editable JSON documents, polygon/open-curve/point geometry, freehand/mesh/knife/extrude tools, weld, undo/redo, Quick Setup pipeline builder.
- Layer reordering via drag-and-drop (same `NSItemProvider` + `DropDelegate` pattern as Sprites tab).
- Keyboard shortcuts: ⌘Z/⌘⇧Z (undo/redo), ⌘X/⌘C/⌘V (cut/copy/paste), ⌫ (delete selected geometry).
- Confirmation dialog before deleting a non-empty layer.

### Sprites tab

- Left panel: browsable, searchable tree of sprite sets, each collapsible, showing sprites within each set.
  - Filter bar at the top: filters by set and sprite name simultaneously; filtered sets auto-expand; drag-and-drop is disabled while a filter is active.
- Drag-and-drop reordering: sets can be dragged to new positions; sprites can be dragged within their set or moved to another set; visual insertion-line indicator throughout.
- Rename: double-click any set or sprite name to rename inline, or use the pencil toolbar button; renaming a set preserves expansion state.
- Add/delete/duplicate sets and sprites exist via toolbar buttons.
- Right inspector: sprite properties (name, enabled, shape set/shape, renderer set, position, scale, rotation).
- Animation inspector section: structure present for `SpriteAnimation` fields.

### Rendering tab

- Renderer set list with collapsible sets and per-renderer enabled checkbox.
- Brush editor and stamp editor panels in the inspector.
- Palette editor: create, save, import, and duplicate palettes (`PaletteIO.swift`, `PaletteEditors.swift`).
- Palette data is embedded in the rendering config JSON and persists across sessions.
- Rendering list uses collapsible sets matching the Sprites tab pattern.
- Slider/colour-picker changes are debounced (0.35 s) before saving; the canvas is not cleared on each tick.

### Subdivision tab

- Subdivision parameter list with collapsible sets.
- Per-subdivision-level enabled toggle.
- Param controls exposed in the inspector for the selected subdivision level.
- Live preview visible in the main canvas at all times.

### Inspector (right panel)

- Geometry editor inspector: fully icon-based Edit, Delete, File sections; Create, View, Transform, Multiply, Weld sections.
- Sprite inspector: sprite properties, animation fields.
- Rendering inspector: renderer parameters, brush/stamp editors, palette editors.
- Global inspector:
  - Canvas: name, width, height, quality multiplier, scale-image toggle, background image picker (Choose…/clear).
  - Colors: background, border, overlay colour pickers.
  - Playback: FPS, animating toggle, draw-background-once toggle.
  - Note: free-text field.
  - 3-D: enabled toggle, camera view angle.
  - Status: live status/debug text.

### Export

- **Save Still** (photo icon in RunControlBar): renders current frame to a timestamped PNG in `renders/stills/`.
- **Export Video…** (clapper icon): sheet for animation export via `VideoExporter`.
- **Save SVG…** (doc.text icon): exports current frame geometry as an SVG file to `svgs/`. Runs the full morph → subdivide → transform pipeline per sprite; handles `.line`, `.spline`, `.openSpline`, `.oval`, and `.point` polygon types. Implemented in `loom_swift/Sources/LoomEngine/Export/SVGExporter.swift`.
- **Open Renders Folder** (folder icon): opens `renders/stills` or `renders/animations` depending on last export type.

---

## Remaining tasks

Tasks are ordered roughly by priority / natural next step.

### Geometry editor

1. **Oval parametric inspector** — the regular polygon inspector (sides, radius, inner, scale XY, rotation) is implemented; oval creation exists but has no matching width/height/rotation parametric controls. Add `OvalParameters` metadata and an Oval inspector matching the regular-polygon pattern. *(deferred — ovals can be adjusted with edit controls)*

### Sprites tab

2. **Animation inspector** — `SpriteAnimation` fields need wiring in the inspector (enabled, frames, frame duration, loop, ping-pong). Deferred until animation work begins.
3. **Sprite playback preview** — a small preview canvas in the inspector cycling the animated sprite. Deferred until animation work begins.

### Rendering tab

4. **Renderer type validation pass** — confirm all renderer modes (Stroked, Filled, Stamped/Brushed, Stenciled, Points, etc.) have complete inspector controls surfaced.

### Project management

5. **Morph target support** — `morphTargets/` directory is created and the engine has `MorphInterpolator`; UI for authoring/assigning morph targets is not yet built. Deferred until animation work begins.

### Engine / LoomEngine package

6. **Animation system** — `SpriteAnimation` loading, frame advance, loop/ping-pong, and per-sprite playback state are the next major engine feature block.

---

## Files most relevant to continue

| Area | File |
|------|------|
| App shell / state | `Loom_Swift_Integration/Sources/Loom/AppController.swift` |
| Default brushes | `Loom_Swift_Integration/Sources/Loom/DefaultBrushes.swift` |
| Geometry tab | `Loom_Swift_Integration/Sources/Loom/Tabs/GeometryTabView.swift` |
| Sprites tab | `Loom_Swift_Integration/Sources/Loom/Tabs/SpritesTabView.swift` |
| Rendering tab | `Loom_Swift_Integration/Sources/Loom/Tabs/RenderingTabView.swift` |
| Global inspector | `Loom_Swift_Integration/Sources/Loom/Inspector/GlobalInspector.swift` |
| Inspector panel | `Loom_Swift_Integration/Sources/Loom/Inspector/InspectorPanel.swift` |
| Run control bar | `Loom_Swift_Integration/Sources/Loom/RunControlBar.swift` |
| SVG exporter | `loom_swift/Sources/LoomEngine/Export/SVGExporter.swift` |
| Still exporter | `loom_swift/Sources/LoomEngine/Export/StillExporter.swift` |
| Editable geometry | `loom_swift/Sources/LoomEngine/Geometry/Editable/EditableGeometry.swift` |
| Engine entry point | `loom_swift/Sources/LoomEngine/LoomEngine.swift` |
| Sprite config | `loom_swift/Sources/LoomEngine/Config/SpriteConfig.swift` |
| Palette IO | `Loom_Swift_Integration/Sources/Loom/Inspector/PaletteIO.swift` |
| Tests | `loom_swift/Tests/LoomEngineTests/EditableGeometryTests.swift` |
