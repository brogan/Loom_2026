# Spec: Anchor-Point Knife Cut

**Status:** Planned  
**Scope:** Loom_Swift_Integration (AppController, GeometryTabView, InspectorPanel, help.html)  
**Dependencies:** Existing Knife / Curved Knife infrastructure

---

## Motivation

The regular knife always inserts new anchor points where the blade crosses polygon
edges. When the desired cut endpoints coincide with existing vertices, this creates
new points very close to (or duplicating) existing ones, complicating the topology.

The anchor-point knife mode lets the user Command-click two existing vertices on the
same polygon as the cut endpoints. The polygon is split at those vertices with no new
points created at all — the result is topologically clean.

---

## Interaction

### Activation

The mode is entered automatically when the user Command-clicks while the Knife or
Curved Knife tool is active (rather than initiating a drag). No new tool button or
mode switch is needed.

### Selecting the first anchor

- **Command-click** near an anchor point while in Knife or Curved Knife mode.
- The nearest vertex within hit-test range is highlighted: a filled orange circle.
- Status bar: `"Anchor knife: Command-click a second point on the same polygon (Escape to cancel)"`

### Selecting the second anchor

- **Command-click** near a second vertex **on the same polygon**.
- A preview appears between the two selected vertices:
  - **Knife tool:** orange dashed straight line chord.  
    Status: `"Press K or Return to cut, Escape to cancel"`
  - **Curved Knife tool:** orange dashed bezier curve, initially straight, with two
    open-circle handles at ⅓ and ⅔ of the chord (matching existing curved-knife
    defaults). Status: `"Drag handles to adjust curvature, press K or Return to cut"`
- If the Command-click lands on a vertex belonging to a **different polygon**, it is
  ignored. Status: `"Both points must be on the same polygon"`
- Command-clicking the **same vertex** as anchor 1 is ignored.

### Adjusting curvature (Curved Knife only)

- The user drags the two open-circle control handles exactly as in the normal
  Curved Knife adjust phase.
- The preview curve updates live.

### Committing the cut

- **K** or **Return** → perform the split and clear anchor state.
- Both result polygons are selected after the cut.
- Status: `"Anchor knife: polygon split at existing vertices"`

### Cancelling

- **Escape** → clear anchor state, return to idle knife mode.
- Starting a **normal drag** (no Command key) → clears anchor state and begins a
  regular knife drag. This lets the user abandon an anchor selection and fall back
  to the standard knife behaviour without switching tools.

---

## The Split Operation

Given a polygon with ordered vertices `[V0, V1, V2, V3, V4, V5]` and selected
vertices at indices 1 (`V1`) and 4 (`V4`):

```
Piece A: [V1, V2, V3, V4]
Piece B: [V4, V5, V0, V1]
```

Both endpoint vertices appear in both pieces — they are shared, not duplicated.
Each piece is a valid closed polygon.

**Open curves:** anchor-point knife is **not supported** for open curves. A
Command-click near an anchor on an open curve is ignored. The regular knife still
cuts open curves in drag mode.

**Curved knife variant:** the cut line itself follows the adjusted bezier rather
than the straight chord, and may insert intersection points where the curve crosses
the polygon's own edges (if the user has bent the curve so that it re-enters the
polygon). The two selected vertices are always exact endpoints with no rounding.

---

## Multi-Layer Scope

The all-visible-layers scope button is **not affected** by anchor-point mode —
it remains togglable and visible at all times. However:

- Its tooltip is updated to read:
  `"Cut through all visible layers (drag mode only — anchor-point cuts always target the layer that owns the selected polygon)"`
- When an anchor-point cut is committed, the scope button state is **ignored**.
  The cut always applies only to the layer that contains the polygon being split.

This avoids any need to grey out the button dynamically and keeps the UI consistent.
The clarification in the tooltip is sufficient to set expectations.

---

## State

New struct and property on `AppController`:

```swift
struct GeometryKnifeAnchorState: Equatable {
    var polygonID:   EditableGeometryID
    var layerID:     EditableGeometryID
    var vertexIdx1:  Int
    var point1:      Vector2D           // world-space position of vertex 1
    var vertexIdx2:  Int?       = nil
    var point2:      Vector2D?  = nil
    // Curved Knife control points (set when second vertex is selected)
    var cp1:         Vector2D?  = nil
    var cp2:         Vector2D?  = nil
    // Which drag handle is being moved (mirrors CurvedKnifeLine.activeDragTarget)
    var activeDragTarget: Int?  = nil   // 0 = cp1, 1 = cp2
}

@Published var geometryKnifeAnchorState: GeometryKnifeAnchorState? = nil
```

Anchor state is cleared by:
- `cancelGeometryKnifeAnchorState()` (Escape, or beginning a normal drag)
- Any geometry undo/redo snapshot (since the vertex indices may no longer be valid)
- `cancelGeometryKnifeLine()` / `cancelGeometryCurvedKnifeLine()` (for safety)

---

## AppController Functions

```swift
func handleKnifeAnchorCommandClick(at worldPoint: Vector2D)
// Finds nearest visible vertex within hit-test radius across the active layer.
// If no anchor1 yet: sets anchor1, highlights it.
// If anchor1 set: validates same polygon, sets anchor2, initialises preview.

func updateKnifeAnchorHandleDrag(to worldPoint: Vector2D)
func endKnifeAnchorHandleDrag()
// Curved Knife only — mirrors existing handle-drag helpers.

func commitAnchorKnifeCut()
// Called on K / Return when geometryKnifeAnchorState has both vertices set.
// Performs the topological polygon split; ignores knife scope flag.

func cancelGeometryKnifeAnchorState()
// Clears geometryKnifeAnchorState = nil.
```

---

## GeometryTabView Changes

**Tap / click handler:**
- Detect `Command` modifier on click.
- If tool is `.knife` or `.curvedKnife` and Command is held:
  - call `controller.handleKnifeAnchorCommandClick(at:)` instead of beginning a drag.
- If a normal drag begins while `geometryKnifeAnchorState != nil`:
  - call `cancelGeometryKnifeAnchorState()` first, then proceed with normal knife drag.

**Overlay drawing:**
- When `geometryKnifeAnchorState != nil`, draw on top of the normal canvas:
  - Filled orange circle at `point1` (and `point2` if set).
  - If both set: preview line (straight or bezier).
  - Bezier handles (open circles on arms) if tool is `.curvedKnife` and both points set.
  - Handle drag detection follows the same `beginCurvedKnifeHandleDrag` / `updateCurvedKnifeHandleDrag` pattern.

**K / Return key handler:**
- Existing handler calls `finishGeometryCurvedKnifeCut()` when tool is `.curvedKnife`.
- Extend to also check `geometryKnifeAnchorState` first:
  ```swift
  if let anchor = controller.geometryKnifeAnchorState, anchor.vertexIdx2 != nil {
      controller.commitAnchorKnifeCut()
      return true
  }
  ```
  This check runs before the existing knife/curved-knife handlers.

---

## Inspector Panel Changes

Update the two scope-button `help:` strings:

```swift
// Knife scope button
help: "Cut through all visible layers (drag mode only — anchor-point cuts always target the polygon's own layer)"

// Curved Knife scope button
help: "Cut through all visible layers (drag mode only — anchor-point cuts always target the polygon's own layer)"
```

---

## Help Documentation

Add a subsection **Anchor-Point Knife Cuts** to the geometry knife section, covering:

- The Command-click workflow (select two vertices → preview → K/Return to cut)
- Difference from regular knife: no new points; topologically clean split
- Curved variant: handle adjustment
- Multi-layer note: scope button does not apply; cut always stays in the selected polygon's layer

---

## Files Touched

| File | Change |
|---|---|
| `AppController.swift` | `GeometryKnifeAnchorState` struct; `@Published var geometryKnifeAnchorState`; `handleKnifeAnchorCommandClick`, `commitAnchorKnifeCut`, `cancelGeometryKnifeAnchorState`, handle-drag helpers |
| `GeometryTabView.swift` | Command-click detection; overlay drawing for anchor highlights + preview line/curve; K/Return handler extension |
| `InspectorPanel.swift` | Scope button tooltip updates |
| `help.html` | Anchor-point knife subsection |

---

## Implementation Order

1. `AppController` — state + functions. Build check.
2. `GeometryTabView` — input and overlay. Smoke test.
3. `InspectorPanel` — tooltip strings.
4. `help.html` — documentation.
