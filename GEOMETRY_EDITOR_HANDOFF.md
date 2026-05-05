# Geometry Editor Handoff

Last updated: 2026-05-06

## What is now implemented

- Launch screen supports creating a new project by name, as well as opening an existing project.
- Geometry tab can create a new blank polygon set and open it in the new editor.
- Closed polygon point-by-point creation is anchor-only:
  - user clicks anchors;
  - controls are inferred at one-third and two-thirds along each anchor-to-anchor edge;
  - Finalise Polygon automatically creates the closing edge back to the first anchor.
- Point placement offset was corrected.
- Editable geometry has a Swift-native JSON authoring format:
  - files are saved under `polygonSets/<name>.json`;
  - JSON is now the standard for new editable geometry;
  - legacy XML polygon sets remain loadable.
- Save and Load buttons in the editor File section are wired to the JSON document.
- The runtime scene and geometry preview can load JSON-backed polygon sets.
- Layers are now real geometry owners in the editable document:
  - new polygons are created in the selected layer;
  - selecting geometry also selects its owning layer;
  - clicking a layer row focuses editing on that layer by making other visible layers non-editable/greyed;
  - the pencil toggle can opt additional layers back into editability for multi-layer editing;
  - non-editable layers are drawn grey and excluded from selection/editing;
  - hidden layers are not drawn and are excluded from selection/editing;
  - layer order is document order and is saved in JSON.
- Layer list operations now mutate the editable document, not just the side panel:
  - New creates a real document layer;
  - Rename updates the document layer name;
  - Duplicate creates a real layer copy with fresh polygon, segment, anchor, and control IDs;
  - Delete removes the selected layer and its contained geometry, while preserving at least one layer;
  - Shift Up/Shift Down reorder document layers;
  - layer-row edit and visibility icon buttons update saved layer state.
- Dragging an anchor moves its attached controls by the same delta, preserving their relative handle positions.
- Control points can now be selected and dragged directly.
- Selected points are drawn with a white ring on the editor canvas.
- Reset Controls restores selected control/segment geometry to inferred one-third/two-thirds positions.
- Whole polygons can be selected by clicking inside them and deleted with Delete > Only Selected Geometry.
- In Polygons mode, dragging empty canvas creates a rubber-band selection rectangle for selecting multiple polygons.
- Undo/Redo are available in the editor Edit section for geometry edits.
- Edit modes are explicit: Points, Edges, Open Curves, and Polygons. The older Inspect mode has been folded into these selection modes.
- Edges can be selected visually and dragged. Dragging an edge moves its two anchors and attached controls together. Selected edges can use Reset Controls. Closed-polygon edge deletion converts the polygon to an open curve.
- Open curves are now represented as a separate editable geometry type:
  - they save/load inside the same editable JSON document;
  - they export to runtime as `openSpline` geometry;
  - they draw in the editor and support whole-curve, point, and edge selection/dragging, plus reset controls.
- Anchor deletion is implemented for closed polygons:
  - control points cannot be deleted directly;
  - deleting an anchor from a polygon with four or more anchors removes the anchor and replaces its two adjoining edges with one inferred curve;
  - deleting an anchor from a triangle converts the surviving edge into an open curve while preserving that edge's current control positions.
- Edge deletion is implemented for closed polygons:
  - deleting an edge converts the closed polygon into an open curve at the deleted-edge break;
  - Undo restores the original closed polygon.
- A selected open curve with at least three anchors can be closed into a polygon through Finalise Polygon.
- Point-by-point drafts with at least two anchors can now be finalised as open curves, so open-curve transforms can be tested without first deleting polygon edges.
- Point By Point remains active after Finalise Polygon, so several polygons can be created without reselecting the tool each time.
- Freehand creation is now implemented:
  - the Freehand tool records a drag stroke as sampled points;
  - the detail slider maps to the Python editor's curve-fitting tolerance pattern, where higher detail produces a tighter fitted curve;
  - stroke samples are filtered with a small minimum spacing, matching the Python editor's approach to avoiding overly dense raw input;
  - returning near the start point closes the stroke into a closed polygon; otherwise the stroke becomes an open curve;
  - the preview path is drawn live while dragging, with a closure ring shown near the start point;
  - tablet/stylus pressure is captured from the current macOS input event when available, with mouse input falling back to full pressure;
  - fitted anchor pressures are mapped from the recorded raw pressure samples.
- The right Geometry Editor controls are compressed into icon rows with tooltip help:
  - Create uses icons for points, oval, regular polygon, point-by-point, finalise polygon/open curve, clear draft, mesh build, bitmap-to-polygon, and freehand detail;
  - Edit uses one row for points, edges, open curves, and polygons;
  - Undo/Redo sit beside each other and Reset Controls sits beneath them;
  - Weld, Multiply, Transform, and View use compact icon buttons where possible.
- Whole selected polygons/open curves can now be duplicated and transformed:
  - Duplicate creates an offset copy in the same layer and selects the copy;
  - Duplicate is enabled for selected polygons/open curves even when the current selection is a point or edge on that object;
  - Duplicate uses a world-space, size-aware offset so copied polygons/open curves remain visible on the editor canvas;
  - Flip Horizontally and Flip Vertically mirror around the common selected centre;
  - Scale uses a live centred horizontal slider and supports XY, X-only, and Y-only factors;
  - Rotate uses a live centred horizontal slider, with slider value mapped to `[-180°, 180°]`;
  - Scale/Rotate sliders preview from the geometry positions at gesture start, record one undo snapshot per drag, and reset to centre on release, matching the Python editor pattern;
  - Scale/Rotate share pivot options: local centre, common centre, or canvas centre;
  - transforms are undoable and apply through one shared weld-aware point transform path.
- Selected points and edges can now use the same live transform sliders:
  - selected points can be scaled/rotated around local/common/canvas pivots;
  - a single selected point with a local/common pivot has no visible scale/rotate effect, but can transform around the canvas pivot;
  - selected edges can be scaled/rotated through their edge anchors, controls, adjacent controls, and any welded partners.
- Weld support has a first persistent implementation:
  - editable JSON documents now save `weldGroups` made from stable point IDs;
  - old JSON with no weld data still decodes normally;
  - weld groups are pruned when geometry points disappear;
  - duplicate geometry receives fresh IDs and does not inherit weld links to the original;
  - the Weld section now has a button for welding selected points/edges, a button for unwelding selected geometry, a button for welding adjacent edges, and a single strict-to-loose tolerance slider placed directly to the right of the weld buttons;
  - welded edges draw with a purple highlight on editable layers;
  - welded anchors draw with a lighter pink-purple colour on editable layers;
  - unselected/non-editable layers draw welded geometry in grey like all other layer geometry.
- Edge selection supports multiple selected edges:
  - dragging from empty canvas in Edges mode creates a rubber-band selection rectangle;
  - segment midpoints inside the rectangle are selected;
  - Shift-click adds an edge to the existing selection;
  - Command-click toggles an edge in/out of the existing selection.
- Shift-click / Command-click selection modifiers are now shared across geometry selection modes:
  - Points, Edges, Open Curves, and Polygons all support Shift-click to add;
  - Points, Edges, Open Curves, and Polygons all support Command-click to toggle/remove;
  - polygon rubber-band selection can add to the current selection when Shift or Command is held.
- The temporary Geometry Editor status row has been removed:
  - feedback/debug text is now routed to a permanent Status section at the bottom of the Global inspector;
  - current duplicate and weld messages are posted there.
- Relational editing is now used for dragged welded geometry:
  - dragging a welded anchor carries its welded partners and the immediately attached controls of those partner anchors;
  - dragging a selected edge carries any welded point clusters touched by that edge;
  - dragging a whole selected polygon/open curve carries welded neighbouring points, allowing simple mesh-like movement while polygons remain self-contained.
- Whole-object scale/rotate now use the same relational point expansion, so welded neighbours follow transforms around the selected geometry pivot.
- Launch screen project name text uses a contrasting colour.
- Quick Setup creates the full pipeline while keeping shape sets/shapes hidden behind the scenes:
  - Source offers All visible layers plus individual editable JSON layers when the current polygon set is a layered JSON document;
  - choosing an individual layer creates/updates a layer-targeted polygon set entry that points back to the same JSON file and stores the stable layer ID plus display layer name;
  - subdivision set menu offers a recommended new set plus existing sets;
  - sprite set menu offers a recommended new set plus existing sets;
  - renderer set menu offers a recommended new set plus existing sets;
  - renderer menu offers a recommended new renderer plus existing renderers in the chosen renderer set;
  - hidden shape set/shape are created or updated behind the scenes to reference either the full JSON source or the selected layer-targeted source.
- Quick Setup shows a compact Pipeline ready / Pipeline not built status.
- Layer-to-pipeline targeting is now wired:
  - `PolygonSetDef` can store an optional editable JSON layer target;
  - JSON-backed runtime loading in `SpriteScene` filters to the targeted layer when present;
  - geometry preview loading uses the same layer target;
  - no layer target preserves the previous behaviour of loading all visible layers.
- The ordinary Geometry list is now a flat Geometry Sources list rather than type-grouped sections:
  - each source appears once;
  - passive icon indicators show whether it contains polygons, curves, or points;
  - editable JSON sources inspect their saved layers and show polygon/curve indicators from document contents;
  - generated layer-target polygon set helpers are hidden, so a layered JSON file appears once as the editable source of truth;
  - hidden helper entries still exist in project config and are used by pipelines.

## Current editing behaviour

- Point By Point mode is for creating new closed polygons from anchors only.
- Finalise Polygon closes the current polygon, clears the draft, and keeps Point By Point mode active for the next polygon.
- Freehand mode:
  - drag on the canvas to draw a stroke;
  - release to fit the stroke into editable spline geometry;
  - if the stroke ends close to where it started, it creates a closed polygon;
  - otherwise it creates an open curve;
  - the detail slider controls how closely the fitted curve follows the drawn stroke.
- Points mode:
  - drag an anchor to reshape the polygon while carrying attached controls along with it;
  - drag a control point to manually adjust curvature;
  - selected points can use Scale/Rotate in the Transform section;
  - clicking away clears point selection.
- Edges mode:
  - click a curve segment to select it;
  - drag a selected or hit-tested segment to move that edge;
  - selected edges can use Scale/Rotate in the Transform section;
  - if the edge points are welded to another polygon's edge, the welded neighbour points move with it;
  - Reset Controls restores that segment and adjacent segments sharing its moved anchors to inferred handles;
  - Delete > Only Selected Geometry on a closed-polygon edge converts it into an open curve.
- Open curves:
  - are displayed as unclosed spline paths;
  - have their own Open Curves selection mode;
  - whole open curves can be selected, dragged, and deleted;
  - points and edges can be selected/dragged/reset like closed polygons;
  - selecting a whole open curve, open-curve point, or open-curve edge then pressing Finalise Polygon closes the open curve if it has at least three anchors.
- Layer focus:
  - clicking a layer row makes it the selected/focused layer;
  - the focused layer becomes editable;
  - other layers remain visible but become non-editable and greyed out;
  - clicking a non-selected layer's pencil toggle opts that layer into editing too, without changing the selected/focused layer;
  - toggling a layer editable also makes it visible, so editable layers are never hidden accidentally.
- Polygons mode:
  - click inside a polygon to select it;
  - rubber-band drag from empty canvas to select multiple polygons; this no longer turns into a move when the rectangle crosses a polygon;
  - drag selected polygons to move them; welded neighbouring points follow, so mesh boundaries can move together;
  - Delete > Only Selected Geometry removes selected polygons.
- Weld:
  - selecting two or more points and pressing Weld Selected snaps them to their average position and records a saved weld group;
  - selecting two edges and pressing Weld Selected snaps matching anchors/controls to averaged positions and welds the four point pairs;
  - Unweld Selected removes weld relationships touched by selected points, selected edges, or selected whole polygons/open curves;
  - Unweld Selected does not move geometry; it only removes the relationship, so anchors/edges return to their ordinary colour and become discretely transformable;
  - Weld Selected and Weld Adjacent Edges now use the same tolerance profile;
  - the tolerance slider maps one strict-to-loose value across midpoint distance, endpoint-pair distance, and edge direction similarity;
  - Weld Adjacent Edges scans editable visible polygon/open-curve edges for compatible pairs and welds them;
  - Auto Weld highlights candidate edge pairs in purple during whole polygon/open-curve drag;
  - releasing the mouse applies the highlighted auto-weld candidates, matching the Python editor pattern.
- Undo/Redo currently records geometry changes such as polygon creation, movement, reset controls, polygon deletion, anchor deletion, edge-to-open-curve conversion, and open-curve closing.
- Undo/Redo also records layer mutations: new, rename, duplicate, delete, editability toggle, visibility toggle, and layer reordering.
- Controls are inferred only at initial point-by-point polygon creation. After that they are ordinary editable handles unless a future reset-to-auto command is added.
- Reset Controls can be used to restore selected controls, or the controls of a selected polygon, to inferred positions.
- Clicking inside a polygon selects the whole polygon. Delete > Only Selected Geometry removes selected polygons.
- To use newly saved editor geometry in the main pipeline:
  - save geometry in the editor;
  - return to Default Geometry View;
  - select the polygon set in Geometry;
  - choose the recommended Quick Setup names or select existing sets/renderers from the menus;
  - press Make Pipeline.

## Verification

- `swift test --disable-sandbox --filter EditableGeometryTests` passes.
- `swift build --disable-sandbox` passes for `Loom_Swift_Integration`.
- EditableGeometryTests includes a JSON geometry to Shape/Sprite/Subdivision/Renderer scene pipeline regression.
- EditableGeometryTests includes reset-to-auto coverage.
- EditableGeometryTests includes duplicate polygon/layer coverage to ensure copied layers preserve geometry while receiving fresh IDs.
- EditableGeometryTests includes backwards-compatible decoding for older layer JSON that has no `isEditable` field.
- EditableGeometryTests includes coverage for anchor deletion, edge deletion to open curve, open-curve runtime export, and closing an open curve back to a polygon.
- EditableGeometryTests includes coverage for persistent weld groups, JSON round-trip, and relational expansion from a welded anchor to partner anchors and attached controls.

## Deferred Notes

- Rendering tab parameter edits, especially colour sliders, currently cause more screen rewrite than desired. This should be addressed later by narrowing update/reload behaviour, but it is deliberately deferred while the current focus remains the Geometry tab.
- The Python editor used Shift+press/drag in Edge mode with selected edges to trigger edge extrusion (`bezier_py/canvas/mouse_handler.py` and `draw_panel.py`). In the Swift editor, Shift is now reserved for add-to-selection, so extrusion will need a different modifier or explicit tool/button when implemented.

## Recommended next stage

Next session should start with a short manual validation pass of weld behaviour, then continue expanding mesh editing.

Suggested path:

1. Manually validate freehand creation:
   - draw an open stroke and confirm it becomes an editable open curve;
   - draw a stroke that returns near its start and confirm it becomes a closed polygon;
   - compare low and high detail slider values on the same kind of stroke;
   - save/reload and confirm the resulting curve/polygon persists;
   - if a pressure-capable tablet/stylus is available, confirm pressure variation is captured.
2. Continue creation-mode implementation:
   - parametric ovals and regular polygons as closed polygon runtime geometry with specialised editing controls;
   - default algorithmic objects to their own layer, while avoiding a hard long-term rule if mixed layers later prove useful.
3. Recheck weld behaviour after freehand validation:
   - create two polygons with a shared/near-shared edge;
   - select the two edges and press Weld Selected;
   - adjust the tolerance slider and confirm looser settings accept edges that stricter settings reject;
   - drag one welded edge and confirm the neighbour edge follows;
   - with Auto Weld enabled, drag a whole polygon near a compatible edge and confirm the purple candidate highlight appears before release;
   - release the mouse and confirm the highlighted candidate weld is applied;
   - save/reload and confirm welded dragging still works.
4. Add editable point geometry to the JSON model:
   - make the flat Geometry Sources point indicator meaningful for editable JSON sources;
   - add point creation/editing mode beyond the current anchor/control editing;
   - decide how point layers feed the pipeline.
5. UI polish can remain deferred:
   - drag-and-drop layer reordering instead of Shift Up/Shift Down;
   - warning/confirmation for deleting a non-empty layer;
   - final review of icon choices and tooltip coverage across Loom.
6. Edge extrusion remains future work:
   - preserve the Python operation concept, but do not reuse Shift as its trigger in Swift;
   - choose a different modifier or an explicit extrude button/tool before implementation.

## Files most relevant to continue

- `Loom_Swift_Integration/Sources/Loom/AppController.swift`
- `Loom_Swift_Integration/Sources/Loom/Tabs/GeometryTabView.swift`
- `Loom_Swift_Integration/Sources/Loom/Inspector/InspectorPanel.swift`
- `loom_swift/Sources/LoomEngine/Geometry/Editable/EditableGeometry.swift`
- `loom_swift/Sources/LoomEngine/Loaders/EditableGeometryJSONLoader.swift`
- `loom_swift/Tests/LoomEngineTests/EditableGeometryTests.swift`
