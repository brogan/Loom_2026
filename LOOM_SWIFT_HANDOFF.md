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
- AppController is the single shared observable state holder; all tabs bind to it.
- Global inspector (right panel) carries a permanent Status section at the bottom for feedback/debug text.

### Geometry tab

Fully featured — see `GEOMETRY_EDITOR_HANDOFF.md` for the complete list.
Summary: layered editable JSON documents, polygon/open-curve/point geometry, freehand/mesh/knife/extrude tools, weld, undo/redo, Quick Setup pipeline builder.

### Sprites tab

- Left panel: browsable tree of sprite sets, each collapsible, showing sprites within each set.
- Drag-and-drop reordering within the left panel:
  - sets can be dragged to new positions (insertion-line indicator between sets);
  - sprites can be dragged within their own set or moved to a different set (insertion-line indicator between sprites; set-header highlighted when a sprite is dragged over it);
  - visual state is driven by `@State dragItem: LoomDragItem?` and `@State dropTarget: SpriteDropTarget?`;
  - implemented via `NSItemProvider(object: NSString)` + `DropDelegate` pattern (registered UTType workaround for AppKit drag matching).
- Right inspector: sprite properties (name, enabled, shape set/shape, renderer set, position, scale, rotation).
- Animation inspector section: structure present for `SpriteAnimation` fields.

### Rendering tab

- Renderer set list with collapsible sets and per-renderer enabled checkbox.
- Brush editor and stamp editor panels in the inspector.
- Palette editor: create, save, import, and duplicate palettes (`PaletteIO.swift`, `PaletteEditors.swift`).
- Rendering list uses collapsible sets matching the Sprites tab pattern.

### Subdivision tab

- Subdivision parameter list with collapsible sets.
- Per-subdivision-level enabled toggle.
- Param controls exposed in the inspector for the selected subdivision level.

### Inspector (right panel)

- Geometry editor inspector: fully icon-based Edit, Delete, File sections; Create, View, Transform, Multiply, Weld sections.
- Sprite inspector: sprite properties, animation fields.
- Rendering inspector: renderer parameters, brush/stamp editors, palette editors.
- Global inspector: Status section at the bottom.

---

## Remaining tasks

Tasks are ordered roughly by priority / natural next step.

### Geometry editor

1. **Oval parametric inspector** — the regular polygon inspector (sides, radius, inner, scale XY, rotation) is implemented; oval creation exists but has no matching width/height/rotation parametric controls. Add `OvalParameters` metadata and an Oval inspector matching the regular-polygon pattern.
2. **Drag-and-drop layer reordering** — layers currently use Shift Up/Shift Down buttons. Implementing `.onDrag`/`.onDrop` using the same `NSItemProvider(object: NSString)` + `DropDelegate` pattern now used in the Sprites tab would be consistent.
3. **Keyboard shortcuts** — cut (⌘X), copy (⌘C), paste (⌘V), undo (⌘Z), redo (⌘⇧Z), delete (⌫) should be wired to the geometry editor commands. SwiftUI `.keyboardShortcut` or `NSEvent` monitoring via `onAppear`.
4. **Warning on non-empty layer delete** — currently deletes immediately. A confirmation alert for layers containing geometry would reduce accidental data loss.
5. **Validation pass** — items 1–12 in the "Recommended next stage" section of `GEOMETRY_EDITOR_HANDOFF.md` are all manual validation items still outstanding (Mesh, Knife, Weld, View, extrude, etc.).

### Sprites tab

6. **Animation inspector** — `SpriteAnimation` has `enabled`, `frames`, `frameDuration`, `loop`, and `pingPong` fields (or equivalent). The inspector section structure is present but controls for individual animation properties need wiring.
7. **Sprite playback preview** — a small canvas in the inspector (or a dedicated preview area) showing the animated sprite cycling through its frames would help confirm animation settings without running the full render pipeline.
8. **Sprite search/filter** — for projects with many sprite sets, a filter field at the top of the left panel would speed navigation.
9. **Add/delete/rename sprites and sets from the UI** — currently possible only by editing config XML directly or using the inspector name field; explicit add/delete/rename buttons in the left panel would complete the CRUD story.

### Rendering tab

10. **Parameter-edit rerender throttling** — colour slider changes in the Rendering tab currently cause more canvas repaints than needed. Narrowing which parts of AppController trigger scene rebuild (e.g., debouncing slider commits or narrowing the `@Published` surface) would smooth interaction.
11. **More renderer types in the inspector** — not all renderer type parameters may be surfaced yet. A validation pass checking each renderer mode (Stroked, Filled, Stamped, Points, etc.) against the inspector controls would ensure completeness.

### Subdivision tab

12. **Subdivision preview** — the Subdivision tab shows parameter controls but no live preview of the subdivided shape. A small canvas showing the result of the selected subdivision pipeline on the current sprite/shape would close the feedback loop.

### Project management

13. **Background image loading** — the `background_image` directory is now created; wiring it to an image picker and displaying it behind the geometry/render canvas is not yet done.
14. **Configuration file round-trip** — Python Loom wrote a project-level `configuration/` directory. Identify what Python stored there and ensure the Swift app reads/writes equivalent config (render resolution, background colour, frame rate, etc.).
15. **Morphtarget support** — `morphTargets/` directory is created. The engine concept exists in the spec series but Swift morph target loading/application is not yet implemented.
16. **Export/render to stills and animations** — `renders/stills` and `renders/animations` directories exist. The actual render-to-disk pipeline (frame loop → Metal → CGImage → PNG/GIF/video) is not yet wired.

### Engine / LoomEngine package

17. **SVG export** — `svgs/` directory is created; the engine has no SVG writer yet. Python exported subdivision results as SVG for downstream use.
18. **Stamps loading** — `stamps/` directory is created; the engine references stamps in renderer mode. Verify that stamp image loading from the project's `stamps/` directory is wired end-to-end.
19. **Brush loading** — similar to stamps; `brushes/` directory exists; confirm brush image loading pipeline is complete.
20. **Palette persistence** — palettes can be saved/imported via `PaletteIO`; confirm the saved palette files land in `palettes/` and are reloaded when the project is opened.

---

## Files most relevant to continue

| Area | File |
|------|------|
| App shell / state | `Loom_Swift_Integration/Sources/Loom/AppController.swift` |
| Geometry tab | `Loom_Swift_Integration/Sources/Loom/Tabs/GeometryTabView.swift` |
| Sprites tab | `Loom_Swift_Integration/Sources/Loom/Tabs/SpritesTabView.swift` |
| Rendering tab | `Loom_Swift_Integration/Sources/Loom/Tabs/RenderingTabView.swift` |
| Inspector | `Loom_Swift_Integration/Sources/Loom/Inspector/InspectorPanel.swift` |
| Editable geometry | `loom_swift/Sources/LoomEngine/Geometry/Editable/EditableGeometry.swift` |
| Engine entry point | `loom_swift/Sources/LoomEngine/LoomEngine.swift` |
| Sprite config | `loom_swift/Sources/LoomEngine/Config/SpriteConfig.swift` |
| Palette IO | `Loom_Swift_Integration/Sources/Loom/Inspector/PaletteIO.swift` |
| Tests | `loom_swift/Tests/LoomEngineTests/EditableGeometryTests.swift` |
