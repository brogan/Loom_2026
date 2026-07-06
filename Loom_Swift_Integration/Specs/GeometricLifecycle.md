# Geometric Lifecycle — Spec

**Status**: Phases 0–6 complete; Phase 7 (Fulguration) pending  
**Affects**: LoomEngine, Loom (studio), subdivision tab architecture

---

## 1. The Framework

Loom's current identity is defined by recursive subdivision: a closed polygon divides
into structured child polygons. This is powerful but partial. The subdivision tab is
being extended into a five-part system covering the complete lifecycle of a geometric form.

The five modes are not a toolkit of arbitrary transformations. They represent the
fundamental things that can happen to any existing form — stages of existence that carry
philosophical weight alongside geometric meaning:

| Mode            | What happens                                    | Philosophical register              |
|-----------------|-------------------------------------------------|-------------------------------------|
| **Involution**  | A form analyzes itself into parts               | Self-complexity, inner structure    |
| **Extension**   | A form grows outward into new territory         | Growth, becoming, reaching          |
| **Evolution**   | A form accumulates change along a trajectory    | Metamorphosis, directed development |
| **Fulguration** | Form emerges when conditions are met            | Emergence, threshold, encounter     |
| **Dissolution** | A form loses specificity or suddenly ends       | Entropy, release, ending            |

These are not alternatives; they compose. A sprite can have operations from all five modes
active simultaneously. The pipeline applies them in order: Involution → Extension → Evolution
→ Fulguration → Dissolution, each stage operating on the output of the previous. Any stage
can be empty (disabled).

The subdivision tab becomes five subtabs, one per mode. Each has its own parameter
structure, driver system, and engine. They share the rendering pipeline and the driver
infrastructure (DoubleDriver, DriverEvaluator).

Two modes require architectural novelties beyond the current engine:
- **Evolution** requires *stateful* parameters — the form remembers its history across
  frames. The current engine is stateless (same inputs → same frame output). Evolution
  breaks this.
- **Fulguration** requires *conditionality* — geometry that exists only when specified
  conditions are met. The current engine has no conditional geometry existence.

---

## 2. Involution

### 2.1 What it is

A form analyzes itself — decomposes into structured components, or complicates its
internal structure without changing its outer integrity. For closed polygons this is
the existing subdivision pipeline. For open curves, involution has two distinct operations
with different characters: refinement (adds internal complexity while preserving the
whole) and segment extraction (releases the parts from the whole).

### 2.2 Closed polygons — subdivision (existing, complete)

The QUAD, TRI, BORD, SPLIT, STAR, TRISTAR algorithms and their full parameter/driver
system are the implementation of involution for closed polygons. This mode is mature.

### 2.3 Open curves — curve refinement

New anchor and control points are inserted along an existing open curve. The overall
gesture of the curve is preserved (or only gently altered); the refinement populates
its interior with controllable structure.

Insertion can be:
- **Parametric** — new anchors at Chaikin midpoints or at driven fractional positions
  along arc length
- **Uniform** — divide each segment into N equal sub-segments
- **Driven** — insertion density varies along the arc, driven by a DoubleDriver sampled
  at each point's arc-position

Once inserted, the new points become individually addressable through the per-point
transform system (PTP equivalent for open curves). Each inserted anchor can have
independent displacement drivers — oscillating, noise, or phase-staggered — so the
curve's macro form remains recognizable while its micro-behavior becomes complex.

This is genuinely parallel to closed-polygon subdivision: subdivision doesn't change
the outer boundary of the polygon's space, it populates the interior. Curve refinement
doesn't change the overall gesture, it populates the interior of the curve with
controllable structure.

### 2.4 Open curves — segment extraction

The curve is broken at its existing anchor points, producing its edges as independent
open sub-curves. Each sub-curve proceeds independently and can itself be subjected to
extension, evolution, or dissolution.

Refinement and extraction are inverses in character: refinement complicates while
preserving the whole; extraction liberates the parts at the cost of the whole.

A `segmentExtractionMode` parameter:
- `.all` — all edges extracted as independent curves
- `.alternate` — alternate edges extracted, others left in place
- `.driven` — a DoubleDriver selects which edges extract on which frames (can pulse
  between intact and extracted states)

### 2.5 Renaming consideration

"Subdivision" communicates what the algorithm does. "Involution" communicates what it
*means*. A middle path: label the subtab "Subdivision" with "Involution" as a subtitle
or tooltip, so the philosophical vocabulary is present without obscuring the function.

---

## 3. Extension

### 3.1 What it is

A form grows outward. Extension adds to the spatial extent of the form — it creates
geometry that lies *outside* or *beyond* the original boundary, connected to but distinct
from the source. The growth follows a logic (a rule, a branching structure, a normal
direction) rather than distributing copies independently in space.

The distinction from PTW scatter is topological: scattered polygons are independent
copies; extended forms remain connected to their parent.

### 3.2 Branching

From any endpoint of an open curve or any vertex of a closed polygon, spawn sub-forms
at a specified angle and scale ratio, with recursion up to a specified depth. Each
branch level inherits a scaled-down version of the parent form's geometry and can itself
branch.

Parameters:
- `branchAngle: DoubleDriver` — angle of each branch relative to parent direction
- `branchAngleJitter: Double` — random variation in angle per branch
- `branchScaleRatio: Double` — scale factor applied at each level (typically < 1)
- `branchDepth: Int` — maximum recursion depth
- `branchCount: Int` — number of sub-branches per branch point (2 = binary branching)
- `branchProbability: Double` — probability that any given branch point actually spawns,
  allowing sparse or irregular branching

For open curves, branching extends from the curve's endpoints. For closed polygons,
branching extends from selected vertices (driven by a vertex selection rule analogous
to the existing `whichSpike` parameter in PTP).

The branching logic is the key differentiator from subdivision: subdivision divides the
*interior* of an existing form; branching grows new forms at the *boundary*.

### 3.3 Edge extrusion

A polygon vertex or edge grows outward along its normal direction, producing a new
polygon that is topologically connected to the parent at the extruded edge. The result
is a compound form — parent and child share an edge, and the child can itself be extruded.

Parameters:
- `extrusionDistance: DoubleDriver` — how far the vertex/edge moves outward
- `extrusionWidth: Double` — width of the new polygon at its outer edge (< 1 = taper,
  > 1 = flare, = 1 = parallel)
- `extrusionCurvature: Double` — bow on the extruded edge (analogous to CP normal offset)
- `extrusionGenerations: Int` — number of sequential extrusions (each extruded form is
  itself extruded)
- `extrusionTarget: ExtrusionTarget` — `.allEdges`, `.selectedVertices`, `.longestEdge`,
  `.drivenEdge`

---

## 4. Evolution

### 4.1 What it is

A form changes character over time along a trajectory. The defining feature of evolution —
and the thing that distinguishes it from the existing DoubleDriver system — is that it is
*cumulative*: the form remembers where it has been, and that history shapes where it goes
next. Each frame is not computed independently from the same parameters; it builds on the
previous frame's state.

Evolution involves: some element of randomness at the start; a trajectory that emerges
from that randomness; and a focusing/intensification of that trajectory over time.

This requires the Evolution engine to maintain per-sprite state across frames — a new
architectural requirement for LoomEngine.

### 4.2 Momentum drift

The form's parameters (subdivision centre position, line ratios, inset scale, or any
driven value) accumulate a slowly-changing velocity vector rather than sampling a new
random value each frame. Each frame applies the current velocity; the velocity itself
undergoes a slow random walk. The result: the form wanders with *inertia*, not jitter.
The same random seed produces the same trajectory, but the trajectory has memory.

Parameters:
- `driftTarget: DriftTarget` — which parameter(s) are subject to momentum drift
  (centre position, line ratios, inset scale, etc.)
- `driftMomentum: Double` — how much of the previous frame's velocity is retained
  (0 = no memory, pure jitter; 1 = no change, frozen; 0.9 = slow organic drift)
- `driftNoiseStrength: Double` — magnitude of the random perturbation added each frame
- `driftNoiseFrequency: Double` — rate of change of the noise field driving perturbations
- `driftSeed: Int` — deterministic seed for the trajectory

A high `driftMomentum` with low `driftNoiseStrength` produces slow, sweeping movement
that turns gradually. A lower `driftMomentum` produces more erratic, direction-changing
motion. The trajectory character is controlled by the ratio between these two.

### 4.3 Convergence pressure

An attractor state is defined — a target set of parameter values — and the form is
progressively pulled toward it at a rate governed by a `pressure` parameter. The pressure
itself can be driven (e.g., starting near zero and ramping up over time), producing the
quality described as "starts random, accumulates into a trajectory, then gets focused
and pushed": the form begins diffuse or varied, and as pressure increases, it is pulled
with increasing force toward the attractor state.

Parameters:
- `convergenceTarget: ConvergenceTarget` — named parameter set to converge toward;
  can reference another SubdivisionParamsSet in the project
- `convergencePressure: DoubleDriver` — current rate of convergence (0 = no pull;
  1 = snap to target in one frame; typical values 0.01–0.1 for smooth convergence)
- `convergenceMode: ConvergenceMode` — `.hold` (stay at target once reached),
  `.oscillate` (bounce between start and target), `.loop` (reset to start and
  converge again)

Convergence pressure and momentum drift compose: a form can drift stochastically
while also being pulled toward a target, so the drift becomes increasingly constrained
as pressure rises.

---

## 5. Fulguration

### 5.1 What it is

Fulguration introduces *conditionality* as a first-class geometric operation. Geometry
exists not continuously but when conditions are met — it appears as a flash at the moment
of threshold-crossing, holds for a duration, and disappears. The conditions involve both
the state of other geometry and global parameters; the appearance is therefore both
predictable (the conditions are specified in advance) and unpredictable (the exact moment
depends on runtime dynamics).

This is categorically different from the existing visibility rules, which are
probability-based and stateless. Fulguration geometry is *conditional* — it is the
geometric embodiment of the threshold, the encounter, the moment of emergence.

The term itself carries the image: the flash of lightning, something that appears in an
instant and is gone. The conditions are the atmospheric charge; the appearance is the
discharge.

### 5.2 Global-parameter trigger

Geometry becomes visible when a specified global parameter crosses a threshold value.
It holds for a specified duration, then disappears. The shape of the appearance and
disappearance is parameterised.

Parameters:
- `triggerSource: TriggerSource` — the global parameter to monitor: frame phase (0–1
  within a cycle), any DoubleDriver output, audio amplitude, audio beat phase, or a
  named driver value
- `triggerThreshold: Double` — the value at which the trigger fires
- `triggerEdge: TriggerEdge` — `.rising` (fires when value crosses upward),
  `.falling` (downward), `.both`
- `holdDuration: Int` — frames to remain visible after triggering
- `appearanceMode: AppearanceMode` — `.instant` (flash: on in one frame, off when
  hold expires), `.fade` (brief linear fade in/out over N frames)
- `refractory: Int` — minimum frames between successive triggers (prevents rapid
  re-firing on noisy signals)

Multiple polygon sets can reference the same trigger source with the same threshold,
producing simultaneous flashes across different parts of the scene.

### 5.3 Proximity trigger

Geometry appears when two specified polygon sets come within a defined distance of each
other. The fulguration geometry exists *at the encounter* — not as a property of either
parent but as the product of their relationship. It disappears when they separate beyond
the threshold distance.

Parameters:
- `proximitySetA: String` — name of the first polygon set
- `proximitySetB: String` — name of the second polygon set
- `proximityThreshold: DoubleDriver` — maximum distance between nearest points of the
  two sets at which the fulguration fires (can be driven, allowing the sensitivity to
  change over time)
- `proximityGeometry: ProximityGeometry` — what appears: `.connectionLine` (a line
  between the nearest points), `.midpointForm` (a polygon centred at the midpoint
  of the two nearest points), `.customSet` (a named polygon set placed at the midpoint)
- `appearanceMode: AppearanceMode` — same as global-parameter trigger

The proximity trigger makes fulguration geometry a genuine *relational* object: it has
no existence independent of the spatial relationship that produces it.

### 5.4 Architectural note

Both trigger types require the engine to evaluate conditions *before* deciding whether
to render the associated geometry. This is a new evaluation pattern: currently the engine
renders all geometry unconditionally (visibility rules operate on the output polygons, not
on whether the generation runs at all). Fulguration requires a pre-render condition
check that can suppress entire polygon sets. The condition evaluation must be cheap
(one comparison per set, not per polygon) and deterministic for replay.

---

## 6. Dissolution

### 6.1 What it is

A form loses its specificity or ends. Dissolution is not concealment (visibility rules
handle that) but *process* — the form actively changes toward absence or simplicity.
It has two fundamental modes: entropy (slow, continuous loss of complexity) and collapse
(sudden, triggered termination). These can combine: a form erodes gradually until a
trigger condition causes it to collapse completely.

### 6.2 Entropy

The form progressively loses its geometric specificity over time. Vertex positions
migrate toward the polygon's centroid or toward a smoothed version of the polygon,
corners round, and the form approaches a simpler shape — ultimately a circle or a
point. The form never disappears; it *forgets* its original character.

Parameters:
- `entropyRate: DoubleDriver` — fraction of each vertex's distance from its smoothed
  position that is consumed each frame (0 = frozen; 0.01 = slow erosion; 0.1 = fast)
- `entropyTarget: EntropyTarget` — `.centroid` (all vertices converge to centre),
  `.smoothed` (vertices migrate toward Chaikin-smoothed positions — corners round,
  curves remain), `.circle` (vertices migrate toward a best-fit circle)
- `entropyNoise: Double` — random perturbation added during erosion, so the path toward
  simplicity is not perfectly uniform
- `entropySeed: Int` — deterministic seed for noise variation

At full entropy, a complex subdivided polygon becomes a circle or a point. The rate can
be driven to produce pulses of erosion alternating with recovery.

### 6.3 Collapse

The form persists at its full complexity until a trigger condition is met, at which
point it disappears — in a single frame, or over a very brief window. Unlike entropy,
there is no gradual degradation before the moment of collapse; the form is entirely
itself and then entirely gone.

Parameters:
- `collapseMode: CollapseMode` — `.instant` (disappears in one frame), `.brief`
  (disappears over N frames with a rapid linear fade)
- `collapseTrigger: CollapseTrigger` — what causes the collapse:
  - `.frameCount(n)` — collapses after exactly N frames
  - `.probability(p)` — each frame has probability p of triggering collapse (the form
    survives with probability 1-p each frame; expected lifetime = 1/p frames)
  - `.threshold(source, value)` — collapses when a global parameter crosses a value
    (same source vocabulary as Fulguration triggers)
- `collapseEndMode: CollapseEndMode` — `.remove` (form is gone permanently),
  `.loop` (form resets to its original state and the countdown begins again),
  `.respawn` (a new form is generated from the collapse point — connecting back to
  Fulguration: the end of one form is the trigger condition for the emergence of another)

The `.loop` mode with a probability trigger produces intermittent spontaneous
disappearance and reappearance — a different quality from the visibility rules' per-frame
randomness, because the form persists at full intensity between collapses rather than
flickering.

### 6.4 Composition

Entropy and collapse can be combined on the same form. The typical pattern is entropy
first (complexity drains away over time) followed by collapse (the simplified form
finally disappears). The entropy rate and collapse trigger can be parameterised to
control the ratio of the two phases.

### 6.5 Relationship to visibility rules

Visibility rules (random 1-in-N, etc.) operate per-polygon, per-frame, independently.
Dissolution operates on the whole form over time. They are complementary: visibility
rules govern *which* polygons within a generation are rendered at a given frame;
dissolution governs *how* the form as a whole changes over its lifetime.

---

## 7. The Pipeline

```
Base geometry
     ↓
[Involution]   — closed: subdivision (QUAD/TRI/BORD/SPLIT/STAR)
               — open: curve refinement; segment extraction
     ↓
[Extension]    — branching (open/closed); edge extrusion (closed)
     ↓
[Evolution]    — momentum drift; convergence pressure
     ↓
[Fulguration]  — global-parameter trigger; proximity trigger
     ↓
[Dissolution]  — entropy; collapse
     ↓
Render
```

Each stage is optional. The output of each stage is the input to the next. The pipeline
order is fixed for predictable composition; within each stage, operations can be stacked.

---

## 8. UI: The Five Subtabs

The subdivision tab becomes five subtabs labelled by the abbreviated mode names (Inv /
Ext / Evo / Ful / Dis), with full names shown in tooltips. Phase 0 (five-subtab shell)
is already built.

Each subtab follows the same structural pattern as the current subdivision inspector:
a list of named parameter sets for this mode, a selection panel, and a driver/param
editor for the selected set. The parameter set structure is mode-specific but the
list/expand/collapse/reorder UI pattern is shared.

A sprite with only the Involution subtab populated behaves exactly as current Loom
sprites do — backwards compatibility is preserved.

---

## 9. Open Curves Across the Lifecycle

| Mode           | Open curve operations                                          |
|----------------|----------------------------------------------------------------|
| Involution     | Curve refinement (insert driven anchor points, maintain gesture); segment extraction (break into independent sub-curves) |
| Extension      | Branching from endpoints; growth/extension from ends (OpenCurves.md) |
| Evolution      | Momentum drift and convergence pressure applied to control-point positions |
| Fulguration    | Curves that appear at proximity encounters or global-parameter thresholds |
| Dissolution    | Entropy (control points converge to smoothed positions); collapse (curve disappears) |

---

## 10. Geometry Layer Architecture

A single `EditableGeometryLayer` can contain all three geometry types simultaneously:
closed polygons (`polygons`), open curves (`openCurves`), and standalone points
(`points`). There is no separate layer type for any of them; regular/parametric polygons
are `EditableClosedPolygon` objects with a `parametricSource` attached, living in the
same layer structure.

The config and save system maintains separate file-type tracks:
`polygonSets/`, `curveSets/`, `pointSets/`, `ovalSets/`, `regularPolygons/`. These are
storage distinctions, not layering distinctions.

A `ShapeDef.sourceType` is mutually exclusive: `.polygonSet` OR `.openCurveSet`.
A single sprite shape can reference either a closed-polygon file or an open-curve file,
but not both simultaneously. A polygon-set file CAN contain both closed polygons and
open curves in the same document; when loaded at runtime it produces a `[Polygon2D]`
mix, and the render pipeline dispatches by type — `SubdivisionEngine` handles `.spline`,
`CurveRefinementEngine` handles `.openSpline`.

**Transformation set routing:** Because a single transformation set contains both
`[SubdivisionParams]` (affecting closed shapes) and `[CurveRefinementParams]` (affecting
open curves), a mixed-type polygon-set file is served by one transformation set that
covers both. Separate layers are not required; the dispatch is automatic by polygon type.

**Curve set save routing (resolved):** The geometry editor can now save open-curve
documents directly to `curveSets/`. `saveGeometryEditorDocument` detects a
`curveSets/...` key and routes to the curve set folder, updating
`curveConfig.library.curveSets`. The curveSets load path now supports both `.xml`
(legacy) and `.json` (geometry editor output) via `EditableGeometryJSONLoader`.
A `uniqueCurveSetName` helper mirrors `uniquePolygonSetName` for the curve namespace.

**Open question:** There is still no direct path to *create* a new `curveSets/` entry
from the Geometry tab's "+" button — new geometry always starts as a `polygonSets/`
entry. The workaround is to draw an open curve in any polygon-set document and save
it; the editor detects the `curveSets/` key and routes correctly. Adding an explicit
"New Curve Set" button is a pending UX improvement.

---

## 11. UX Naming — "Subdivision" to "Transform" Migration

With five lifecycle modes in place, the term "Subdivision" no longer describes the
full transformation pipeline. A phased rename is in progress:

**Phase A — Surface labels (complete):**
- Default new geometry name: `New_Polygon_Set` → `New_Geometry_Set`
- Sprite inspector: "Subdiv set" → "Transform set"; "Subdivision Set Driver" → "Transform Set Driver"
- Subdivision tab left panel: "Subdivision Sets" → "Transform Sets"
- Subdivision tab sprite column header: "Subdivision Set" → "Transform Set"
- Quick Pipeline Setup: "Subdivision set" → "Transform set"

**Phase B — QPS type awareness (complete):**
- `recommendedQuickSetupSubdivSetName` already returns "None" for open-curve sources
  (via `sourceSupportsSubdivision` returning `false` for `curveSets`).
- `makePipeline` now detects `folder == "curveSets"` and creates
  `ShapeDef(sourceType: .openCurveSet, openCurveSetName: geoName)` instead of a
  polygon set shape. `pipelineExists` updated accordingly.
- When creating a new transformation set from QPS for a closed-polygon source, a QUAD
  subdivision param is added as the default. For open-curve sources, no default param is
  added (the set starts empty; the user adds curve refinement passes via the inspector).

**Phase C — Mode selection (future):**
- Add `activeModes: Set<LifecycleMode>` to `SubdivisionParamsSet` / future
  `TransformationSet`.
- UI: mode-selection control in set header; collapse stages whose mode is not active.
- This gives users an explicit, discoverable way to say "this set uses curve refinement
  only" or "this set uses subdivision + dissolution".

**Phase D — Data model rename (future):**
- `SubdivisionParamsSet` → `TransformationSet`
- `SubdivisionConfig` → `TransformationConfig`
- `subdivisionParamsSetName` → `transformationSetName`
- Requires a migration pass and file-format bump; deferred until Phase C is stable.

**Tab icon:** The current subdivision icon is no longer representative of the five-mode
pipeline. Updating it is a pending UX task; it does not affect functionality.

**Chaining:** The five modes already compose as a fixed pipeline
(Involution → Extension → Evolution → Fulguration → Dissolution). A transformation set
will eventually support specifying which modes are active. The architecture does not
preclude more complex chaining (e.g., skipping stages, feeding one mode's output back).
This is explicitly not addressed in Phase A–D but the data model must not foreclose it.

---

## 12. Implementation Phases

### Phase 0 — Shell (complete)

Five-subtab UI structure built. Involution subtab shows existing subdivision functionality
unchanged. Other four subtabs show "Coming soon" placeholders.

### Phase 1 — Involution: open-curve refinement (complete)

Curve refinement: insertion of N anchor points per segment, three distribution modes
(linear/exponential/random), displacement (jitter or lazy tween), three CP modes
(smooth Catmull-Rom / straight / bowed), pressure, and a full driver set. Data model:
`CurveRefinementParams` on `SubdivisionParamsSet.curveRefinement`. Engine:
`CurveRefinementEngine`. Inspector: `CurveRefinementInspector` wired into
`SubdivisionInspector`.

Segment extraction (`.all`, `.alternate`, `.driven`) is specified but not yet
implemented.

### Phase 2 — UX naming corrections (complete)

Phase A and B renames described in §11. Transformation set naming, QPS type awareness,
default geometry name.

### Phase 3 — Involution: open-curve segment extraction (complete)

`SegmentExtractionParams` on `SubdivisionParamsSet.segmentExtraction`. Engine:
`SegmentExtractionEngine`. Inspector: `SegmentExtractionInspector` wired into
`SubdivisionInspector`. Modes implemented: `.all`, `.alternate`, `.every(n, offset)`,
`.driven`. Output types: open curve, closed polygon. Inspector uses `DoubleDriverEditor`
for the driven-mode selector. Full help documentation added.

### Phase 4 — Extension: branching and edge extrusion (complete)

`ExtensionParams` on `SubdivisionParamsSet.extensionPasses: [ExtensionParams]`.
(Property name is `extensionPasses` not `extension` — Swift reserved word.)
Engine: `ExtensionEngine`. Inspector: `ExtensionInspector` wired into
`SubdivisionInspector`.

**Branch** (`.openSpline` input): recursive tree from both endpoints of each open
curve. `branchAngle: DoubleDriver`, `branchAngleJitter`, `branchScaleRatio`, `branchDepth`
(1–8, capped at practical depth by budget), `branchCount`, `branchProbability`,
`branchSeed`. Deterministic jitter via `SubdivisionEngine.centreHash`.

**Extrude** (`.spline` input): outward 4-segment closed polygon per target segment.
`extrusionDistance: DoubleDriver`, `extrusionWidth`, `extrusionCurvature`,
`extrusionGenerations` (1–6), `extrusionTarget` (`.allEdges` / `.longestEdge`). Outward
normal computed once from original chord; passed through all recursive generations.
Outer edge control points bow in the outward-normal direction.

**Memory fix (post-initial-commit):** The original implementation applied
`prefix(256)` *after* the full recursive tree was materialized — with depth=8 count=2
this built ~87,000 `Polygon2D` objects before trimming. Fixed by threading an
`inout budget: Int` counter through `branchPolygon`; recursion stops the moment 256
branches are produced. OOM crash and black render canvas are resolved.

**QPS transform-set dropdown fix:** `subdivisionSetOptions` in `InspectorPanel` now
always includes existing transform sets regardless of `sourceSupportsSubdivision`,
so open-curve sources see the full list in Quick Setup.

**Tab label fix:** `AppTab.subdivision.label` returns `"Transform"` (rawValue stays
`"Subdivision"` for config-file persistence). `GlobalProjectInfoView` left panel
renamed to match. Help doc updated: nav, TOC, and section heading all say "Transform
Tab"; Curve Refinement, Segment Extraction, Branch, and Extrude all have full
step-by-step sections with parameter tables and safe-value guidance.

### Phase 5 — Evolution: momentum drift + convergence pressure (complete)

`EvolutionParams` on `SubdivisionParamsSet.evolutionPasses: [EvolutionParams]`. Engine:
`EvolutionEngine`. Inspector: `EvolutionInspector` wired into `SubdivisionInspector`.

**Architecture decision — no per-sprite state:** The spec anticipated an `EvolutionState`
accumulator. This was resolved with a closed-form drift formula instead:
```
drift[N] = Σ noise(seed, N-k) × momentum^k   for k = 0 .. K
```
where K = log(epsilon) / log(momentum), constant-time and fully seekable. Any frame can
be evaluated without prior frames having been rendered. No stateful accumulator needed.

**Momentum drift**: Applies closed-form noise-driven displacement to a `DriftTarget`
field in each SubdivisionParam before SubdivisionEngine runs. Targets: line ratio X/Y/XY,
CP normal X/Y, inset scale, inset rotation. Parameters: `driftMomentum` (0–1),
`driftNoiseStrength`, `driftNoiseFrequency`, `driftSeed`.

**Convergence pressure**: Lerps each SubdivisionParam's lineRatios, cpNormalOffsets, and
insetTransform toward a named target set. Pressure is a `DoubleDriver`. Three modes:
`.hold` (driver value applied directly), `.oscillate` (sin wave over duration frames),
`.loop` (0→1→0→1 cycle). Target set looked up via `allSubdivisionSets` (existing
`[String: [SubdivisionParams]]` cache — no new data structure).

**Pipeline position:** EvolutionEngine runs after the subdivision-set driver override
and before SubdivisionEngine — it modifies `activeInstance.subdivisionParams` in-place.

**Bake / SVG export / wireframe preview:** All three paths pass evolution passes through.
Convergence target lookup uses `[:]` at static-export time (frame 0, no convergence
targets in non-interactive contexts); drift still applies at frame 0.

### Phase 6 — Dissolution: entropy and collapse (complete)

`DissolutionParams` on `SubdivisionParamsSet.dissolutionPasses: [DissolutionParams]`.
Engine: `DissolutionEngine`. Inspector: `DissolutionInspector` wired into
`SubdivisionInspector`. Pipeline position: after `ExtensionEngine`, before sprite
transform (step 2e in `SpriteScene`).

**Architecture decision — stateless:** Dissolution does not accumulate per-sprite
state. Entropy uses a closed-form exponential decay:
```
factor(N) = 1 - (1 - rate)^N
vertex_N  = lerp(vertex_current, target_current, factor)
```
"Current" means the polygon as produced by the upstream pipeline for this frame
(post-evolution). Any frame is computable independently without prior state.

Collapse probability mode determines the first-fire frame by a deterministic hash
scan (`SubdivisionEngine.centreHash`) — same result for any given frame, fully
seekable. The `.loop` end mode wraps `effectiveFrames` by the period
`collapseFrame + briefDuration` rather than storing a reset timestamp.

**Entropy targets:**
- `.centroid`: each anchor in the spline encoding (indices `4k`) moves toward the
  `BezierMath.centreSpline` average; control points translated by the same delta
  (rigid follow), preserving local curve shape
- `.smoothed`: each anchor moves toward the average of its two neighbours (Laplacian
  step) — corners round while the overall polygon gesture is retained
- `.circle`: anchors normalised to a mean-radius circle centered on the anchor
  centroid — angular forms become progressively rounder

Per-anchor noise added via `centreHash(seed, cycle: Int(frames))` — changes each
frame, seeded per-anchor and per-sprite.

**Collapse:**
- `frameCount`: fires at exactly N frames
- `probability(p)`: hash scan over `[0, 100_000)` finds first frame k where
  `hash(seed ^ k*1231, cycle: k) < p`; expected lifetime = 1/p frames
- `brief` mode: polygon scaled toward `BezierMath.centreSpline` centroid over the
  fade window using `Polygon2D.scaled(by:around:)`
- `loop` end mode: wraps effective frames; `remove` and `respawn` return `[]`
  once collapsed (respawn is a placeholder for Fulguration integration)

**Note:** The spec originally anticipated per-sprite state for `.loop` reset.
Resolved identically to Evolution: closed-form modular arithmetic on frame count
eliminates the need for stored state without changing the observable behavior.

### Phase 7 — Fulguration: triggers (pending)

Condition-check pre-pass in the render pipeline. Global-parameter trigger.
Proximity trigger with `.connectionLine` geometry. Both require the new
`FulgurationParams` model and the conditional rendering architecture.

**Architectural note:** Requires a pre-render condition evaluation pass that runs
*before* `SubdivisionEngine` dispatch. The trigger state (firing / held / refractory)
is frame-level state, not per-polygon state. The proximity trigger requires computing
nearest-point distances between two `[Polygon2D]` sets per frame — O(m×n) naively;
a bounding-box pre-check reduces practical cost to O(1) for non-overlapping sets.

---

## 13. Open Questions

1. **Naming in the UI (partially resolved).** Tab now shows "Transform" (the functional
   label) with Inv/Ext/Evo/Ful/Dis subtab abbreviations and full names in tooltips.
   The philosophical full names ("Fulguration", "Involution") appear in help documentation
   and subtab tooltips but not in inspector section headers — section headers use
   functional names ("Branch", "Extrude", "Curve Refinement") for discoverability.
   The data-model rename (Phase D: `SubdivisionParamsSet` → `TransformationSet`) is still
   deferred pending a migration strategy.

2. **Evolution state and determinism (resolved).** No per-sprite state is accumulated.
   Drift at frame N is a closed-form weighted sum over a bounded history window
   (constant time, fully seekable). Verified via Phase 5 implementation.

3. **Fulguration and the render pipeline.** The current render loop evaluates all
   sprite polygon sets unconditionally. A Fulguration condition check requires a
   pre-pass that may suppress some sets entirely. The condition evaluation must be
   separated from the polygon-level processing and positioned before the SubdivisionEngine
   dispatch. The trigger state (is it currently firing?) must be part of the per-frame
   engine state, not per-polygon state.

4. **Cross-mode polygon identity.** A polygon produced by involution, extended by
   branching, drifted by evolution, and then collapsing under dissolution — at what
   point does it cease to be "the same polygon" for the purposes of driver seeds,
   PTW phase staggering, and replay? The splitmix64 per-polygon seed hash needs to
   be stable across all five pipeline stages.

5. **Entropy and subdivision depth.** Entropy erodes a polygon toward a circle or
   centroid. But the polygon may itself be the *output* of a subdivision generation —
   it is one of many children, and its vertices are the result of the subdivision
   algorithm. Entropy applied to the *child* polygons erodes their subdivision-derived
   complexity, which produces a very different visual effect from entropy applied to
   the *source* polygon before subdivision runs. Both are valid but the pipeline order
   (Involution → Dissolution) produces the former. A flag that allows Dissolution to
   operate on pre-Involution geometry would enable the latter.

6. **Performance of Evolution state.** If a project has many sprites with momentum
   drift active, the engine maintains O(sprites) state vectors and updates them every
   frame. At typical sprite counts this is negligible. At very high sprite counts
   (hundreds of named sprites) it may be worth lazy-evaluating: only update the
   drift state for sprites that are visible in the current frame.
