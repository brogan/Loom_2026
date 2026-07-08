# Geometric Lifecycle — Spec

**Status**: Phases 0–6 complete; Phase 7 (Fulguration) V1 complete, V2 pending; Phase 8
(Evolution: generational artificial-life) in progress (core loop complete, see below)  
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

### 4.4 Generational evolution (artificial life) — planned

#### 4.4.1 What it is

A third `EvolutionParams.operationType` case, `.generational`, distinct in kind from
momentum drift and convergence pressure: those two *perturb parameters*
(`SubdivisionParams` fields) that the pipeline then subdivides once; generational
evolution instead *iteratively mutates the polygon itself*, across N generations, each
generation operating on the actual materialized output of the previous one and judged
by a fitness measure before deciding whether to keep mutating. It's a minimal
artificial-life system: random structural variation, a success criterion, and
selection — applied to geometry instead of organisms.

Each shape subject to a generational-evolution pass has:
- `generationCount: Int` — how many generations to run.
- A weighted/random choice of **mutation operator** per generation.
- A **fitness measure** each resulting generation is judged by.
- A **lock rule**: once a generation is judged successful, it stops mutating (and may
  be duplicated/grafted) rather than continuing to be mutated by further generations.

#### 4.4.2 Mutation operators

- **Contiguous edge extrusion** — one or more adjacent edges pushed outward by a
  distance sampled from a range each generation (RPSR — random probability within a
  specified range). Structurally the same move as Extension's edge extrusion (§3.3),
  but applied per-generation to a shape that already carries prior generations' changes,
  rather than once to the base form.
- **Edge split + outward displacement** — split one or more edges, then move one or
  more of the new points outward from the current polygon boundary by an RPSR distance.
  Genuinely new (no existing operator does this): it's a structural mutation, not a
  static transform, since where the "outward" direction and the pre-split shape are
  depend on everything that happened in prior generations.
- **Duplicate-and-graft** — copy a contiguous sub-portion of the current boundary
  (a run of vertices/edges) and attach the copy elsewhere on the shape. Needs an
  attachment rule (nearest edge, a symmetric position across the shape's axis, or a
  driven/random vertex) — left as an open detail for the first prototype.
- **Subdivision cycle** — run one pass of `SubdivisionEngine.process` on the current
  polygon as a mutation step. This does *not* require reordering the five-stage
  pipeline (Involution → Extension → Evolution → Fulguration → Dissolution) — it's an
  internal function call within Evolution's own generation loop, operating on
  `[Polygon2D]` directly, exactly as Extension's engine already calls into geometry
  helpers internally.
- **Operator selection** — a per-generation weighted random pick across the above
  (`operatorWeights: [GenerationOperator: Double]`, seeded), so the user can bias
  toward mostly-extrusion, mostly-grafting, an even mix, or a fixed single operator
  by zeroing the others' weights.

#### 4.4.3 Fitness and selection

- **Symmetry score** — reflect the current polygon across a candidate mirror axis
  (best-fit, or user-specified) and measure vertex/edge deviation from that reflection;
  lower deviation scores higher. A `symmetryTarget: Double` (0 = reward asymmetry,
  1 = reward symmetry) lets the user pick either end of the scale rather than always
  maximizing regularity.
- **Reference-shape similarity** — compare the evolving shape against a small library
  of reference polygons (built-in primitives like square/isosceles-triangle, or
  shapes the user has created/selected from their own project) using coarse
  descriptors (vertex count, edge-length variance, interior-angle variance) as a cheap
  first pass; a full scale/rotation-invariant registration (Procrustes-style) is a
  possible later refinement if the coarse measure doesn't discriminate well enough.
- **Combined fitness** — a weighted sum of whichever measures are active.
- **Lock rule** — once a generation's fitness crosses `successThreshold`, the shape
  stops being mutated by extrusion/splitting/subdivision. `lockMode` decides what
  happens next: `.hold` (carry forward unchanged for any remaining generations) or
  `.graft` (duplicate the locked shape onto itself or another lineage rather than
  continuing to mutate it — connects back to the duplicate-and-graft operator above).

#### 4.4.4 Architecture: state, determinism, and cost

This is the part worth being precise about, since Evolution's other two operation
types were deliberately built closed-form/stateless (§4.1) and this one structurally
cannot be:

- **Not closed-form.** Generation N depends on generation N−1's actual materialized
  polygon and its measured fitness — there is no formula that computes generation 47
  without having produced generations 1–46. Momentum drift and convergence pressure
  don't have this dependency (their "memory" is of a noise seed, not of prior
  geometry), which is what let them stay O(1)/instantly-seekable.
- **Still fully deterministic and free of persistent state**, in the sense that
  matters architecturally: given `(baseShape, seed, generationCount, operatorWeights,
  fitnessRule)`, re-simulating from generation 0 produces the identical result every
  time. Nothing is incrementally mutated frame-by-frame during playback — the whole
  chain is recomputed within a single evaluation. This is the same category as
  subdivision depth or Extension's `branchDepth`/`extrusionGenerations`: recursive and
  O(N) to reach depth/generation N, but not "state" in the sense that broke seeking or
  required save/restore. `GenerationalEvolutionEngine.process(polygon:, seed:,
  generations:, operators:, fitness:) -> Polygon2D` walks the chain once per call;
  memoizing the result per shape-instance (invalidated on any input change) is a valid
  performance optimization, never a correctness requirement.
- **A hard complexity budget is required**, not optional. Duplicate-and-graft and the
  subdivision-cycle operator both multiply vertex/polygon count per generation.
  Extension hit exactly this failure mode at branch depth 8 (~87,000 polygons before
  the fix) and had to thread a budget counter through the recursion (§3.2 note); the
  generation loop needs the same discipline — a `maxVertexBudget` (or equivalent) that
  stops mutation once exceeded, from the first implementation, not added after an
  incident.
- **Lineage growth needs its own cap.** If duplicate-and-graft or `.graft` lock mode
  produces more than one independent descendant, each descendant runs its own
  generation chain onward — a small population, not a single path. `maxLineages`
  bounds this the same way `maxVertexBudget` bounds per-shape complexity.

#### 4.4.5 Suggested build order

Start with only extrusion and edge-split as operators, symmetry as the only fitness
measure, and both caps enforced from the outset. Add duplicate-and-graft and
reference-shape matching afterward — they're the two riskiest pieces (grafting for
uncontrolled complexity growth, reference-matching for metric quality), and validating
the generation/fitness/lock loop on the simpler pair first makes it much easier to
tell whether problems come from the core loop or from those two additions.

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

### 5.2 Scope: V1 (self-contained) and V2 (relational)

Scoped 2026-07-08 into two tiers, following the same "validate the simple core before the
riskier pieces" build order already used for Generational Evolution (§4.4.5): the fully
relational form (§5.1's "product of the relationship" ideal — geometry appearing from the
*interaction* of two other sprites) is the eventual goal, but it depends on the harder,
still-open questions in §5.9/§13.3–4 (cross-sprite render ordering, trigger-instance
identity for overlapping firings). A self-contained V1 needs none of that:

- **V1** (§5.3–5.5): a sprite's own transform pass appears and disappears on a
  frame-count cycle, with per-appearance translation/scale/rotation variation and an
  optional brief grow-in/shrink-out. No dependency on any other sprite's state.
- **V2** (§5.6–5.8): triggering generalizes to global parameters, another named
  sprite's resolved geometry (vertex/polygon count, bounding size), and true proximity
  between two sprites; geometry variation extends to the actual subdivision/curve
  parameters, not just a rigid transform.

Everything below reuses existing engine vocabulary and math rather than introducing new
primitives — RPSR sampling (Extension, Generational Evolution), a seeded-per-instance
choice held stable across frames (Dissolution's contraction anchor, drift direction),
and `Polygon2D.scaled(by:around:)` (already used directly by Dissolution's Brief collapse).

### 5.3 V1 — Frame-cycle trigger

The most self-contained possible trigger: independent of any other sprite or global
parameter, a `FulgurationParams` pass simply cycles its owning geometry on and off.
Structurally this is Dissolution's Collapse-loop (§6.3/Phase 6) inverted — a hidden
interval, then a held/visible interval, repeating — except each cycle's interval and
hold are *independently* RPSR-resampled rather than a fixed repeating period, so it
can't reuse Collapse's `effectiveFrames mod period` shortcut directly (see §5.9).

Parameters:
- `intervalMin/Max: Int` — RPSR range for frames hidden before the next appearance
- `holdMin/Max: Int` — RPSR range for frames visible once triggered
- `cycleSeed: Int` — seeds interval/hold sampling for every cycle, and (§5.4) the
  per-cycle transform variation; same seed drives both so a given seed always
  reproduces the identical sequence of appearances

### 5.4 V1 — Appearance transform variation

Each appearance is one rigid transform applied to the whole flash (not per-polygon —
that's what Dissolution's Drift is for), sampled once per cycle from `cycleSeed`
combined with the cycle index (same pattern as Dissolution's per-polygon seeded
choices, just keyed by cycle index instead of polygon index):

- `translationRange: Double` — max per-cycle offset from the sprite's normal
  placement, canvas-normalized units
- `scaleMin/Max: Double` — per-cycle scale range around 1.0
- `rotationRange: Double` — max per-cycle rotation, radians

A given cycle's sampled transform is held fixed for that entire appearance — the flash
doesn't drift or rotate continuously while visible, it appears already-transformed.

### 5.5 V1 — Development: brief grow-in and shrink-out

Rather than only an instant on/off pop, a flash can briefly develop and dissolve within
its own hold window, addressing the "more than a single-frame flash" gap directly:

- `developmentMode: FulgurationDevelopmentMode` — `.instant` (on for the full hold
  duration, off — simplest possible, zero extra cost) or `.growShrink` (scale
  ramps in and out at the edges of the hold window)
- `growInDuration/shrinkOutDuration: Int` — frames at the start/end of the hold
  window spent ramping scale from/to zero, using `Polygon2D.scaled(by:around:)`
  around the polygon's centroid — the exact primitive Dissolution's Brief collapse
  already calls, applied here in reverse for the grow-in half. No new geometry math,
  and no coupling to a specific `DissolutionEngine` pass — `scaled(by:around:)` is a
  general `Polygon2D` method already used directly by more than one engine.

This is deliberately simpler than cross-referencing a named `DissolutionParams` pass by
name (considered and set aside for V1): a cross-reference would need its own resolution
step and could conflict with that pass's *own* independent trigger/timing running at the
same time. Reusing just the shared low-level scale primitive avoids that entirely. A
named cross-reference (letting a flash's development literally be "whatever entropy
target Dissolution pass X uses") remains a reasonable V2+ enhancement once the simpler
version is validated.

### 5.6 V2 — Threshold-relative trigger

Generalizes the original global-parameter trigger design to include another sprite's
*resolved* geometry as a source, not only external/global values:

- `triggerSource: TriggerSource` — `.framePhase` (0–1 within a cycle), `.driver(name:)`
  (any DoubleDriver output), `.audioAmplitude`, `.audioBeatPhase`, or
  `.spriteMetric(setName:, metric:)` — a named sprite's `.polygonCount`,
  `.vertexCount`, `.boundingWidth`, or `.boundingHeight`
- `triggerThreshold: Double` — the value at which the trigger fires
- `triggerEdge: TriggerEdge` — `.rising`, `.falling`, `.both`
- `holdMin/Max: Int` — RPSR range for frames visible once triggered (same as §5.3,
  reused rather than a separate fixed `holdDuration`)
- `refractory: Int` — minimum frames between successive triggers; the pragmatic V2
  answer to overlapping firings (§5.9) — simpler than tracking concurrent
  trigger-instances, at the cost of missing rapid successive events

For `.spriteMetric`, the value read is the *referenced sprite's previous frame's*
resolved geometry, not the current frame's — see §5.9 for why.

### 5.7 V2 — Proximity trigger

Geometry appears when two specified polygon sets come within a defined distance of each
other. The fulguration geometry exists *at the encounter* — not as a property of either
parent but as the product of their relationship. It disappears when they separate beyond
the threshold distance. This is the fullest expression of §5.1's relational ideal, and
the most expensive to evaluate cheaply — see §5.9.

Parameters:
- `proximitySetA` / `proximitySetB: String` — names of the two polygon sets
- `proximityThreshold: DoubleDriver` — maximum distance between nearest points of the
  two sets at which the fulguration fires (can be driven, allowing the sensitivity to
  change over time)
- `proximityGeometry: ProximityGeometry` — what appears: `.connectionLine` (a line
  between the nearest points), `.midpointForm` (a polygon centred at the midpoint
  of the two nearest points), `.customSet` (a named polygon set placed at the midpoint)

### 5.8 V2 — Geometry variation per flash

Extends variation beyond the rigid transform (§5.4) to the actual subdivision/curve
parameters, so each flash can be a genuinely different *shape*, not just a different
placement of the same shape — reusing the exact field vocabulary Evolution's momentum
drift already perturbs, rather than inventing a parallel one:

- `variationTargets: [DriftTarget]` — which field(s) vary each cycle: line ratio
  X/Y/XY, CP normal X/Y, inset scale, inset rotation (closed polygons); the
  equivalent curve-refinement fields (insertion count/distribution, CP mode/curvature)
  for open curves
- `variationRangeMin/Max: Double` per target — RPSR range, resampled fresh from
  `cycleSeed` each cycle

Architecturally this sits at a different pipeline point than §5.3–5.5: it perturbs
`SubdivisionParams`/`CurveRefinementParams` *before* `SubdivisionEngine`/
`CurveRefinementEngine` run (the same slot Evolution's momentum drift occupies, step 2a),
whereas the visibility/transform/development mechanics of §5.3–5.5 operate on the fully
composed output geometry (alongside Dissolution, step 2f). Fulguration ends up with the
same two-natured shape Evolution already has (param-perturb at 2a, geometry-mutate/
post-process at 2e/2f) rather than needing a new kind of pipeline composition.

### 5.9 Architecture: state, determinism, and cost

- **Frame-cycle trigger is not closed-form, but is still fully stateless** in the sense
  that matters (same category as Generational Evolution, §4.4.4): because each cycle's
  interval/hold is independently resampled, there's no fixed period to take a modular
  remainder against. Finding which cycle `elapsedFrames` currently falls in means
  enumerating cycles by index from 0, hash-sampling each one's (interval, hold) pair,
  and summing until the running total exceeds `elapsedFrames` — O(cycles so far), not
  O(1), recomputed fresh on every evaluation, nothing incrementally mutated across
  rendered frames. This needs the same kind of scan cap Collapse's probability trigger
  already uses (100,000 iterations, §6.3/Phase 6) so a pathological config (e.g.
  `intervalMin/Max` near zero) can't hang. Memoizing the cycle list per pass (invalidated
  on any parameter change) is a valid future optimization, never a correctness
  requirement — same wording as §4.4.4 for Generational Evolution's chain.
- **`.spriteMetric` reads the previous frame's resolved geometry, deliberately.**
  Reading the *current* frame's value would require guaranteeing the referenced sprite
  is fully resolved before the fulgurating sprite's trigger is evaluated — a
  render-order dependency between sprites that doesn't exist anywhere else in the
  engine today, and that gets genuinely hard the moment two sprites reference each
  other (a cycle). One frame of lag sidesteps this entirely: every sprite still
  resolves independently, in any order, exactly as today. The visible cost is a
  single frame of latency on the trigger, imperceptible at typical frame rates.
- **Proximity trigger cost** is the one piece that's a real algorithmic problem, not
  just a data-availability one: nearest-point distance between two `[Polygon2D]` sets
  is O(m×n) naively. A bounding-box pre-check (already noted in the original spec,
  now retained as the concrete plan) reduces this to O(1) for the common case of two
  sets that aren't already close, falling back to the full check only when boxes
  already overlap or are near.
- **Overlapping firings are not tracked as separate instances in V1 or V2.** `refractory`
  (§5.6) suppresses re-triggering while a previous flash is still developing — simple,
  cheap, and sufficient for a first version, at the cost of occasionally missing a
  rapid successive event. True concurrent multi-instance firing (each with its own
  local development clock) is deferred; it reopens the cross-mode polygon identity
  question already flagged as unresolved in §13.4, and shouldn't be tackled until V1/V2
  are validated and a concrete case actually needs it (same reasoning §4.4.5 gives for
  deferring duplicate-and-graft).

### 5.10 Suggested build order

1. **V1** (§5.3–5.5): frame-cycle trigger, transform variation, instant and
   grow-shrink development modes. Fully self-contained — no dependency on any other
   sprite, no new render-ordering concerns, reuses `Polygon2D.scaled(by:around:)`
   directly. This is the "not the most interesting, but something" starting point.
2. **V2a**: threshold-relative trigger against global/driver/audio sources only
   (§5.6, excluding `.spriteMetric`) — cheap, reuses `DriverEvaluator` exactly as
   Convergence Pressure already does.
3. **V2b**: `.spriteMetric` threshold source, previous-frame lag (§5.6, §5.9).
4. **V2c**: proximity trigger with the bounding-box pre-check (§5.7, §5.9).
5. **V2d**: pre-subdivision geometry variation (§5.8) — depends on nothing above,
   could in principle be built in parallel with 2–4, but sequenced last here since
   it's the piece least connected to what makes Fulguration distinctive (the
   conditional appearance), more an extension of Evolution's existing drift concept
   into a new trigger context.
6. **Deferred beyond V2**: true concurrent multi-instance firing (§5.9's last point).

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

### 6.6 The two-track driver system

Dissolution mirrors Generational Evolution's split (§4.4.4, §4.4's doc-comment
distinction) between two independent axes, rather than growing entropy/collapse's
own bespoke progress math to cover the newer mechanics below:

- **`dissolutionPhase: DoubleDriver`** — the "how much" track. An optional per-frame
  animation of overall progress in `[0, 1]`. Disabled by default, in which case Partial
  Loss and Drift (§6.8, §6.9) are always applied at full strength — their own
  `*Enabled` flags gate them, not phase — matching `generationPhase`'s same
  disabled-means-static-full-effect default. Enabling it (an Oscillator or Keyframe
  track, typically) tweens the loss/drift in over playback time instead of having it
  present from frame one.
- **`dissolutionSeed: Int` / `varySeedPerCycle: Bool`** — the "which" track. Seeds all
  deterministic structural choices (contraction anchor point, which polygons are lost,
  per-polygon drift direction). `varySeedPerCycle` reuses
  `GenerationalEvolutionEngine.revealCycleIndex`/`combineSeed` directly rather than
  reimplementing cycle-counting and seed-mixing a second time — when the phase driver
  loops, each cycle gets a different effective seed, so a different set of polygons is
  lost or a different drift direction is chosen each time instead of an identical repeat.

Entropy and Collapse (§6.2–§6.3) are untouched by this system — they keep their own
frame-count-based progress math exactly as before. The two-track system is additive,
covering only the three mechanics below plus contraction anchor choice.

### 6.7 Contraction anchor

Both non-spline entropy shrink (the `default:` branch for `.line`/`.oval`/`.point`
types — `.spline` already has its own richer per-anchor `entropyTarget`) and Collapse's
Brief-mode shrink previously always scaled uniformly toward the polygon's centroid.
`contractionAnchor: ContractionAnchor` generalizes the target:

- `.centroid` (default) — symmetric shrink in place, unchanged existing behavior
- `.edge` — shrinks toward one edge's midpoint, chosen once per polygon (seeded by
  `dissolutionSeed`, stable across frames — it doesn't jump between edges frame to
  frame)
- `.vertex` — shrinks toward one vertex, chosen the same way

Edge/vertex anchoring makes a shrink read as pulling to one side rather than
collapsing evenly in place — a step toward the "contract inward from an edge or a
calculated point" idea raised when scoping this phase.

### 6.8 Partial loss

Collapse is all-or-nothing for a given pass — the whole polygon set it's applied to
either survives or is gone. Partial Loss instead prunes a *fraction* of the polygons
in a subdivided set, so a many-polygon shape can lose some of its members while the
rest continue on:

- `partialLossEnabled: Bool`
- `partialLossMaxFraction: Double` — fraction of polygons pruned at full
  `dissolutionPhase` progress (or always, if that driver is off), chosen
  deterministically per polygon index via `dissolutionSeed`

No-op when the pass's polygon array has only one member — pruning "a fraction of one
shape" isn't meaningful; use Collapse for that case.

### 6.9 Drift

Surviving polygons can translate and/or rotate away from their original placement:

- `driftEnabled: Bool`
- `driftDistance: Double` — max per-polygon translation at full phase progress,
  canvas-normalized units
- `driftRotation: Double` — max per-polygon rotation at full phase progress, radians

Direction and rotation are chosen once per polygon (seeded, stable across frames) —
each polygon drifts one consistent way, it does not wander randomly frame to frame.

### 6.10 Not yet implemented

From the ideas raised when scoping this phase, two remain deliberately deferred as a
materially different order of complexity from the above:

- **Closed polygon → open curve** (losing an edge to become an `.openSpline`). The
  type system already supports the target representation and downstream engines
  (`CurveRefinementEngine`, `SegmentExtractionEngine`, `ExtensionEngine`) already
  operate on `.openSpline`, but the closed→open conversion itself doesn't exist yet.
- **Edge fragmentation** (one edge breaking into several displaced fragments — a
  genuine 1→N topology split, structurally similar to how Subdivision already does
  1→N, but a new kind of operator rather than an extension of an existing one).

---

## 7. The Pipeline

```
Base geometry
     ↓
[Evolution]    — momentum drift; convergence pressure (mutates params, not geometry yet)
     ↓
[Involution]   — closed: subdivision (QUAD/TRI/BORD/SPLIT/STAR)
               — open: curve refinement; segment extraction
     ↓
[Extension]    — branching (open/closed); edge extrusion (closed)
     ↓
[Evolution]    — generational (artificial-life mutation of materialized geometry)
     ↓
[Fulguration]  — geometry variation (V2, §5.8) — NOT YET IMPLEMENTED
     ↓
[Fulguration]  — frame-cycle trigger; transform variation; grow-shrink development
                 (§5.3–5.5, V1 complete). Threshold/proximity triggers (§5.6–5.7) V2.
     ↓
[Dissolution]  — entropy; collapse; contraction anchor; partial loss; drift
     ↓
Render
```

This is the actual current pipeline order in `SpriteScene.swift` (steps 2a through 2g),
not just the conceptual grouping — Evolution appears twice because its two mechanisms
operate at fundamentally different points: momentum drift/convergence pressure perturb
*parameters* before subdivision runs, while generational evolution mutates
*materialized geometry* after Extension, alongside Dissolution. Fulguration V1 (step
2f) has the same shape as generational evolution and Dissolution — a `FulgurationEngine.apply`
call operating on the fully composed `[Polygon2D]` output, step 2f, between
Generational Evolution (2e) and Dissolution (renumbered 2g). Fulguration's V2
pre-subdivision geometry variation (§5.8, not yet built) will land at the *other* slot
in the diagram, alongside momentum drift — the same two-natured split Evolution
already has.

Each stage is optional. The output of each stage is the input to the next. **The
pipeline order is fixed for predictable composition, and this is deliberate for now**:
within each stage, multiple stacked passes run serially and cumulatively (5 stacked
Subdivision passes each consume the previous pass's output — this is literally how
subdivision "generations" are built — and all 5 complete before Extension or any later
stage ever sees the geometry). No stage currently has visibility into another stage's
*resolved runtime state* — every stage receives the same raw `elapsedFrames`/
`targetFPS`/`spriteIndex`, not e.g. Dissolution reading Evolution's current generation
count. See §13's open question on cross-stage interaction for why this is expected to
change eventually, and why it's deferred rather than built now.

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

**Update (2026-07-07) — left-panel mode tab bar removed.** The Inv/Ext/Evo/Ful/Dis
button bar at the top of the Transform tab's left panel (`lifecycleTabBar` in
`SubdivisionTabView`) has been removed, along with the matching gate in
`InspectorPanel` and the `LifecycleTab` enum / `AppController.lifecycleTab` property
that backed it. It was dead weight: switching between the five modes is already
handled directly in the right-hand inspector (`SubdivisionInspector`), which lists
Involution/Extension/Evolution/Fulguration/Dissolution as separate collapsible
sections — each with its own add/duplicate/delete controls for that mode's passes —
with a single field editor beneath for whichever pass is currently selected. The left
panel's sprite tree and transform-set list are now shown unconditionally, with no
top-level mode switch gating them.

`SubdivisionInspector`'s body is now explicitly split into two parts: a top section
(`transformSetSection`) covering set info plus the five per-mode pass lists, and a
bottom section (`selectedTransformationFields`) showing the fields for whichever
transformation is currently selected, separated by a `Divider`.

---

## 9. Open Curves Across the Lifecycle

| Mode           | Open curve operations                                          |
|----------------|----------------------------------------------------------------|
| Involution     | Curve refinement (insert driven anchor points, maintain gesture); segment extraction (break into independent sub-curves) |
| Extension      | Branching from endpoints; growth/extension from ends (OpenCurves.md) |
| Evolution      | Momentum drift and convergence pressure applied to control-point positions |
| Fulguration    | Curves that appear on a frame-cycle (V1) or at proximity encounters/global-parameter thresholds (V2); per-flash variation of insertion count/curvature (V2, §5.8) |
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
- `makePipeline` detects `folder == "curveSets"` and creates
  `ShapeDef(sourceType: .openCurveSet, openCurveSetName: geoName)` instead of a
  polygon set shape. `pipelineExists` updated accordingly.

**Update (2026-07-07) — QPS default-pass generalized to all five modes, both source types.**
Previously `sourceSupportsSubdivision` returned `false` for `folder == "curveSets"`,
so `recommendedQuickSetupSubdivSetName` forced "None" for open-curve sources — no
transform set was created by default at all, unlike closed polygons which always got
a recommended set name plus an automatic QUAD subdivision param. Fixed:
`sourceSupportsSubdivision` now returns `true` for `curveSets` too, so open curves get
a real recommended transform-set name by default, matching closed polygons.

Quick Pipeline Setup's "Transform" phase now has a **Mode** picker
(`QuickSetupDefaultMode` in `InspectorPanel.swift`) offering Involution / Extension /
Evolution / Fulguration / Dissolution / None. It controls what default pass is seeded
into a **newly-created** transform set only (has no effect if the named set already
exists):
- **Involution** — `SubdivisionParams(.quad)` for closed polygons, `CurveRefinementParams`
  for open curves (this replaces the old hardcoded default and is still the QPS default
  mode).
- **Extension** — `ExtensionParams` with `operationType: .extrude` for closed polygons,
  `.branch` for open curves (the two are mutually exclusive per §3/Phase 4 — the wrong
  pairing silently no-ops, so QPS always sets the correct one for the source type).
- **Evolution** — `EvolutionParams` (momentum drift). Only offered for closed-polygon
  sources: `EvolutionEngine` exclusively mutates `SubdivisionParams` fields, which
  `SubdivisionEngine` bypasses entirely for `.openSpline` polygons, so it would have no
  visible effect on an open curve. Excluded from the picker for `curveSets` sources.
- **Fulguration** — `FulgurationParams` (frame-cycle visibility/transform/development,
  §5.3–§5.5). Works for both source types, like Dissolution — V1 operates on the fully
  composed output geometry regardless of polygon type.
  **Update (2026-07-09):** added to the picker; originally omitted when this section
  was written because Fulguration had no engine yet.
- **Dissolution** — `DissolutionParams` (entropy/collapse). Works for both source types
  (open curves get a simpler uniform centroid-shrink entropy vs. closed polygons' full
  anchor-smoothing/circle-fit, per §6.2 — same engine, degraded fidelity, not absent).

The left-panel Transform Sets tree (`SubdivisionTabView.setsTree`) previously summarized
a set's size using `set.params.count` alone (closed-polygon subdivision only), so a
newly-created open-curve/Extension/Evolution/Dissolution-only default set looked empty
("0", "No params — use + to add") despite having a real pass. Fixed with a
`totalPassCount` helper summing all six pass arrays; the empty-state message now
distinguishes "no passes at all" from "passes exist, see right panel" (since this tree
still only renders `params` rows in detail — full per-type row rendering in the left
tree remains future work, not covered by this fix).

The right-inspector top section (`SubdivisionInspector.transformSetSection`, see §1 note
above) already reflects any newly-seeded pass live, since it reads directly from the same
`SubdivisionParamsSet` arrays. Each mode's section header also now shows a small circle,
filled green when that mode has at least one pass configured.

**Bugfix (2026-07-07) — stale pass selection shadowed other modes' inspectors.**
`SubdivisionInspector.selectedTransformationFields` picks which bottom-section editor
to show via an `if/else if` priority chain (Dissolution → Evolution → Extension →
Segment Extraction → Curve Refinement → Subdivision — first non-nil
`selected*ParamIndex` wins). Each mini-list's selection binding was hand-nil-ing only
the *other* indices it happened to know about at the time it was written, which in
practice meant only the indices **below** itself in that priority chain. E.g.
selecting a Subdivision pass cleared `selectedCurveRefinementParamIndex` but not
Evolution/Extension/Dissolution/Segment Extraction; selecting an Extension pass
cleared everything below it but not Evolution or Dissolution above it. Once any
higher-priority mode's pass had ever been selected, its index was never cleared by
selecting a lower-priority mode's pass afterward, so the bottom section kept showing
that higher-priority mode's editor forever — reported as "clicking Subdivision or
Extension after Evolution has been selected always shows the Evolution inspector, no
matter what's clicked." The `add*Param` functions had the identical bug (each only
nil'd a partial list when auto-selecting the newly-created pass).

Fixed by centralizing the invariant in one place: `selectPass(_:_:)` clears all six
`selected*ParamIndex` properties unconditionally, then sets the one requested. Every
mini-list's selection binding and every `add*Param` function now routes through it
instead of hand-maintaining its own partial clear-list. This closes the whole class of
bug for good — adding a future mode's selection index can't reintroduce it, since
there's no per-list clear-list left to forget to update.

**Phase C — Mode selection (future):**
- Add `activeModes: Set<LifecycleMode>` to `SubdivisionParamsSet` / future
  `TransformationSet`.
- UI: mode-selection control in set header; collapse stages whose mode is not active.
- This gives users an explicit, discoverable way to say "this set uses curve refinement
  only" or "this set uses subdivision + dissolution".

**Update (2026-07-07) — left-panel/right-panel CRUD split, "pass" terminology.**
Two more single-mode-era leftovers, both in the Transform tab's left panel
(`SubdivisionTabView`):

1. `addSet()` created every new transform set with a default `SubdivisionParams()`
   (Quad) already in it — the left panel's only affordance for adding *any* pass was a
   "Params" toolbar row that exclusively created closed-polygon subdivision passes, a
   relic of the era before Extension/Evolution/Dissolution/Curve Refinement/Segment
   Extraction existed. This was also the immediate cause of the QPS-recommended-name
   confusion documented above. Fixed: `addSet()` now creates an empty
   `SubdivisionParamsSet(name:)` with no default pass, matching how every other mode's
   "add" already behaves.
2. The left panel's "Params" toolbar row (add/delete/duplicate/rename) and the
   per-set expand-to-see-params tree (`expandedSets`, per-param rows, hidden-param
   eye toggle, a separate rename sheet) were removed entirely. This was the *only*
   place any individual pass could be added, deleted, duplicated, or renamed outside
   the right panel — every other mode (Extension/Evolution/Dissolution/Curve
   Refinement/Segment Extraction) already did this exclusively via its own mini-list
   in `SubdivisionInspector`. Renaming already worked via each pass's inline "Name"
   field in the bottom-section editor once selected (`paramEditor`,
   `CurveRefinementInspector`, `ExtensionInspector`, etc.), making the left panel's
   separate rename sheet a second, redundant path. The left panel (`setRow`) now
   just shows a set's name and total pass count across all six pass arrays
   (`totalPassCount`); selecting a set loads it into the right panel, where all pass
   CRUD for all five modes now lives consistently.
3. `SubdivisionInspector.paramsList` (the Subdivision entry under Involution) gained
   the add/delete/duplicate controls every other mode's mini-list already had. Adding
   a pass is a **dropdown of `SubdivisionType` options** (Quad/Tri/Bord/Split/Star/etc.,
   `addSubdivisionParamMenu`) rather than a plain "+" that silently always created
   Quad — the user picks the algorithm at creation time instead of getting a default
   they then have to notice and change.
4. **Terminology**: "pass" is now the single term used for an individual configured
   item within any of the five lifecycle modes, in all user-facing text (buttons,
   help strings, empty-state messages, counts) — matching what Extension/Evolution/
   Dissolution/Curve Refinement/Segment Extraction already used; "param"/"params" no
   longer appears in Subdivision's UI strings either. The underlying Swift symbols
   (`SubdivisionParams`, `SubdivisionParamsSet.params`, `selectedSubdivisionParamIndex`,
   etc.) are intentionally left as-is — renaming those is Phase D below, deferred
   because it touches Codable keys and dozens of call sites project-wide; the fix
   here was scoped to what users actually read.

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

**Update (2026-07-09) — directional edge selection.** `ExtensionParams.directionalSelector`
further restricts `extrusionTarget`'s candidates by outward-normal direction — see
§14. Also factored the previously-duplicated inline outward-normal formula into one
`ExtensionEngine.outwardNormal(of:segIdx:)`, reused by `extrudePolygon`, `extrudeEdge`,
and the new filter.

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

**Driver system + three new mechanics (complete, 2026-07-08):** see §6.6–§6.10 for
the full design. Summary of what changed:

- `DissolutionParams` gained `dissolutionPhase: DoubleDriver`, `dissolutionSeed: Int`,
  `varySeedPerCycle: Bool` — the same two-track pattern as `EvolutionParams`'
  `generationPhase`/`generationSeed`/`varySeedPerCycle`, and `DissolutionEngine`
  gained a public `effectiveSeed(for:elapsedFrames:targetFPS:)` that delegates to
  `GenerationalEvolutionEngine.revealCycleIndex`/`combineSeed` directly (same module)
  rather than re-deriving cycle-counting and seed-mixing a second time.
- `contractionAnchor: ContractionAnchor` (`.centroid` default / `.edge` / `.vertex`)
  generalizes the shrink target previously hardcoded to centroid in non-spline
  entropy and Collapse's Brief mode. Picking an anchor point is itself seeded and
  polygon-index-stable (`anchorPoint(for:anchor:seed:polygonIndex:)`), so a shape
  contracts toward the same edge/vertex every frame rather than jumping around.
- `partialLossEnabled`/`partialLossMaxFraction` prune a fraction of a subdivided
  set's polygons rather than collapsing the whole set together — a no-op below two
  polygons.
- `driftEnabled`/`driftDistance`/`driftRotation` apply a per-polygon rigid
  translation/rotation, direction chosen once per polygon (seeded) and scaled by
  `dissolutionPhase`'s progress.
- `DissolutionEngine.apply` gained a `targetFPS` parameter (defaulted to `30` so the
  three static/bake call sites in `Loom_Swift_Integration` — `SubdivisionTabView`
  ×2, `SubdivisionWireframeView` — compile unchanged; `SpriteScene.swift`'s live-render
  call site passes the real value).
- `DissolutionInspector` gained four sections: **Contraction** (anchor picker),
  **Driver** (seed field via `IntEntryField`, the Phase `DoubleDriverEditor`, vary-seed
  toggle — mirroring `EvolutionInspector`'s `generationPhaseDriverSection`), **Partial
  Loss**, **Drift**.

Verified with 26 new `DissolutionEngineTests` (previously zero tests existed for this
engine, despite Phase 6 predating this work — added baseline entropy/collapse
regression coverage alongside the new-mechanic tests as a safety net for the shared
`contractTo`/`anchorPoint` refactor): centroid-anchor regression, edge/vertex anchor
symmetry-breaking and convergence, partial-loss fraction/phase/seed behavior including
the single-polygon no-op, drift distance/rotation bounds and centroid preservation,
`effectiveSeed` parity with `GenerationalEvolutionEngine.combineSeed`, and
`varySeedPerCycle` producing different partial-loss outcomes across reveal cycles. All
504 tests in `LoomEngineTests` pass; both packages build clean.

**Not yet done:** closed polygon → open curve, edge fragmentation (§6.10 — both
deferred as a materially larger step than the above), and any cross-stage coupling
(e.g. dissolution phase driven by Evolution's generation count — see §13).

### Phase 7 — Fulguration: triggers (V1 complete, V2 pending)

Scoped 2026-07-08 into V1/V2 — see §5.2–§5.10 for the full design. `FulgurationParams`
on `SubdivisionParamsSet.fulgurationPasses: [FulgurationParams]`, matching the
`*Passes` array convention Extension/Evolution/Dissolution already use. Engine:
`FulgurationEngine`. Inspector: `FulgurationInspector` wired into `SubdivisionInspector`.

**V1 (complete, 2026-07-08, §5.3–§5.5):** frame-cycle trigger (independently
RPSR-resampled interval/hold per cycle, §5.3), per-cycle rigid transform variation
(translation/scale/rotation, §5.4), and `.instant`/`.growShrink` development modes
using `Polygon2D.scaled(by:around:)` directly (§5.5 — the same primitive Dissolution's
Brief collapse already calls, no cross-engine coupling needed). Fully self-contained:
no dependency on any other sprite's state, no render-ordering concerns.

Pipeline position: step 2f in `SpriteScene.swift`, after Generational Evolution (2e)
and before Dissolution (renumbered 2g) — a visibility gate plus rigid transform plus
scale-envelope applied to the fully composed geometry, same point in the pipeline the
original spec diagram reserved for Fulguration. Also wired into
`SubdivisionTabView.swift`'s `bakeSelectedSet()`/`saveSelectedSetAsSVG()` and
`SubdivisionWireframeView.swift`'s preview, matching how Dissolution and Generational
Evolution were wired into those same three call sites.

**Implementation notes:**
- The cycle-walk (`FulgurationEngine.resolveVisibility`) enumerates cycles from index
  0 — hidden interval, then held interval, repeating — summing each cycle's
  independently-sampled durations until the running total exceeds `elapsedFrames`.
  Capped at 100,000 iterations, the same cap Collapse's probability trigger uses, so a
  pathological config (near-zero interval/hold) can't hang. O(cycles-so-far), not
  O(1) — same non-closed-form-but-stateless category as Generational Evolution (§4.4.4),
  confirmed by test (`testLargeElapsedFramesWithTightCycleCompletesWithoutHanging`).
- `spriteIndex` is folded into the seed (`cycleSeed &+ spriteIndex &* 2_654_435_761`,
  the same constant Dissolution's Collapse probability trigger already uses) so
  sprites sharing one `FulgurationParams` preset don't flash in lockstep.
- The rigid transform (§5.4) and development scale envelope (§5.5) are applied around
  one shared **group centroid** — the unweighted average of every polygon's own
  centroid in the pass's array — rather than each polygon's individual centre, so a
  multi-polygon flash reads as one object appearing/growing/rotating together, not
  each member moving independently (that's what Dissolution's Drift is for).
- Development factor: `.instant` is always `1.0` for the whole hold window;
  `.growShrink` ramps `0→1` over `growInDuration` and `1→0` over `shrinkOutDuration`,
  with both clamped (`growIn = min(growInDuration, holdDuration)`,
  `shrinkOut = min(shrinkOutDuration, holdDuration - growIn)`) so they can never
  overlap or exceed a given cycle's actual sampled hold duration, even if configured
  larger than any plausible hold.

Verified with 17 `FulgurationEngineTests`: disabled-pass and empty-polygon no-ops,
exact hidden/visible cycle-boundary frames (using fixed `intervalMin == intervalMax`/
`holdMin == holdMax` so RPSR sampling degenerates to a known value, making boundary
frames precisely predictable rather than statistical), determinism for repeated calls,
different `spriteIndex` values sampling a different transform, translation/scale
bounds, grow-in/shrink-out ramping at the exact predicted linear factor at several
points through the hold window, the clamp behavior when durations exceed the hold,
`apply(passes:)` chaining with early short-circuit on a hidden pass, and the cycle-scan
cap not hanging on a tight (1-frame interval/hold) configuration at 5,000 elapsed
frames. All 521 tests in `LoomEngineTests` pass; both packages build clean.

**Not yet done (V2, §5.6–§5.8):** threshold-relative trigger against global/driver/audio
sources first (cheap, reuses `DriverEvaluator` exactly as Convergence Pressure does),
then `.spriteMetric` sources reading the referenced sprite's *previous* frame's
resolved geometry (deliberately, to avoid a cross-sprite render-ordering dependency —
§5.9), then the proximity trigger with a bounding-box pre-check to keep the O(m×n)
nearest-point cost practical, then pre-subdivision geometry variation (§5.8, the same
pipeline slot as Evolution's momentum drift, step 2a) reusing `DriftTarget`'s exact
field vocabulary rather than a new one.

**Deferred beyond V2:** true concurrent multi-instance firing (§5.9) — `refractory`
is the V1/V2 answer to overlapping triggers; tracking genuinely simultaneous
independent flash instances reopens the cross-mode polygon identity question in §13.4
and isn't worth taking on until a concrete case needs it.

**Architectural notes carried over from the original spec, still accurate:** requires
a pre-render condition evaluation pass (the trigger state — firing/held/refractory —
is frame-level state, not per-polygon state); the frame-cycle trigger's cycle-walk is
O(cycles so far) rather than O(1), same non-closed-form-but-stateless category as
Generational Evolution (§4.4.4), and needs the same scan cap Collapse's probability
trigger already uses.

### Phase 8 — Evolution: generational artificial-life system (in progress)

`EvolutionParams.operationType` (§4.4) is `.momentumDrift` | `.convergencePressure` |
`.generational`. Engine for the third: `GenerationalEvolutionEngine`, operating on
`[Polygon2D]` directly rather than perturbing `SubdivisionParams` fields the way
momentum drift/convergence pressure do.

**Build order (recommended):** extrusion + edge-split operators only, symmetry-only
fitness, hard vertex-budget and generation-count caps enforced from the start.
Duplicate-and-graft and reference-shape similarity matching follow once the core
generate/measure/lock loop is validated — see §4.4.5 for why those two are deferred.

**Not closed-form, still stateless in the sense that matters:** see §4.4.4. No
per-sprite mutable state persists across rendered frames; the full generation chain
is recomputed from `(baseShape, seed, generationCount, operatorWeights, fitnessRule)`
on each evaluation, same category as subdivision depth or Extension's `branchDepth`.

**Engine (prototyped 2026-07-07):** `GenerationalEvolutionEngine` in the `loom_swift`
package. `process(polygons:params:) -> [Polygon2D]` runs `generationCount`
generations, each applying a weighted-random choice of extrude or split to one
eligible (`.spline`) polygon, with the vertex budget enforced every generation (a
generation that would exceed budget is rejected outright, chain stops there).
- **Extrude operator** reuses `ExtensionEngine`'s existing outward-quad math exactly
  rather than reimplementing it: an internal `ExtensionEngine.extrudeEdge(_:segIdx:distance:width:curvature:)`
  wraps the same `extrudeSegment` the `.extrude` operation type already uses, exposed
  per-edge so a contiguous *run* of edges (RPSR-sampled run length, RPSR distance) can
  be extruded as a set of neighboring quads sharing endpoints — same compound-growth
  model as Extension (§3.3), confirmed to match how the geometry editor's own
  interactive extrude tool works (`AppController.performGeometryDisplacementExtrude` /
  `makeExtrudeQuad`: welds a new quad's edge to the source rather than growing the
  source polygon's own boundary).
- **Split operator** reuses `BezierMath.split(seg:t:)` — the same de Casteljau
  primitive the geometry editor's edge-insert tool uses
  (`AppController.splitPolygonSegment`) — to insert a new anchor at t=0.5 on a
  randomly-chosen edge, then displaces *only that anchor* (not its flanking control
  points) outward along the direction from `BezierMath.centreSpline` (anchor-only
  centre, matching Dissolution's `.centroid` target) by an RPSR distance. Leaving the
  control points in place pulls the boundary into a rounded spike rather than a sharp
  corner.
- Randomness (operator choice, target polygon, run length, distance, split edge) all
  comes from `SubdivisionEngine.centreHash(seed:cycle:)` — deliberately *not*
  `DoubleDriver`, which is a per-frame animation primitive; generation index is a
  structural axis, not playback time, so the two shouldn't be conflated (see the doc
  comment on `EvolutionParams`).

**Data model + pipeline wiring (complete, 2026-07-07):** the generational fields
(`generationCount`, `extrudeWeight`/`splitWeight`, `extrudeRunLengthMin/Max`,
`extrudeDistanceMin/Max`, `splitDisplacementMin/Max`, `generationSeed`,
`maxVertexBudget`) live flat on `EvolutionParams` alongside the momentum-drift/
convergence-pressure fields, matching how `ExtensionParams`/`DissolutionParams`
already carry all their modes' fields on one struct gated by `operationType`. The
short-lived standalone `GenerationalEvolutionParams` struct from the prototype was
deleted; `GenerationalEvolutionEngine.process` now takes `EvolutionParams` directly,
plus a `process(polygons:passes:[EvolutionParams])` convenience overload that filters
to enabled `.generational` passes and chains them in order (mirroring
`DissolutionEngine.apply`'s array-taking convention).

Pipeline position: `EvolutionEngine.apply` (step 2a, before Subdivision) treats
`.generational` as a no-op — it only knows how to mutate `SubdivisionParams`, and
`.generational` needs materialized geometry that doesn't exist yet at that point.
`GenerationalEvolutionEngine.process(polygons:passes:)` instead runs at a new step 2e
in `SpriteScene.swift`, after Extension (2d) and before Dissolution (renumbered 2f) —
operating on the fully-composed per-frame geometry, consistent with "the set of
polygons that compose the shape" from the original design note. The same step was
added to `SubdivisionTabView.swift`'s `bakeSelectedSet()`/`saveSelectedSetAsSVG()` in
the Loom_Swift_Integration app so baking and SVG export match live rendering.

Verified with 11 `GenerationalEvolutionEngineTests` checks (up from the prototype's 8):
disabled/zero-generation no-ops, extrude-only polygon-count growth, split-only
point-count growth with no new polygons, split displacement direction/magnitude,
same-seed determinism, different-seed variation, budget-cap enforcement, the
`passes:` overload ignoring non-`.generational` and disabled passes, and multi-pass
chaining producing the same result as sequential calls. All 461 tests in
`LoomEngineTests` pass (the prototype-era `ExportTests.swift` breakage and ~56 other
pre-existing failures found along the way have since been fixed in separate work).

**Inspector UI (complete, 2026-07-07):** `EvolutionInspector`'s Operation-type picker
switched from segmented to menu style (three options no longer fit segmented
cleanly) and gained a "Generational: iteratively mutates..." line in its help text.
Three new sections appear when Generational is selected: **Generations**
(count/seed/vertex budget), **Extrude** (weight, run-length range, distance range),
**Split** (weight, displacement range). `SubdivisionInspector`'s "add evolution pass"
button became a type-picker menu (mirroring Subdivision's algorithm dropdown)
instead of always defaulting to Momentum Drift, since the three operation types are
different enough in kind that a silent default would be misleading.

**Animated reveal (complete, 2026-07-07):** a `generationPhase: DoubleDriver` field
on `EvolutionParams` (disabled by default — the full `generationCount` is always
applied statically, unchanged from before this existed) maps playback time to a
continuous position in `[0, generationCount]`:
- The integer part is how many generations are fully applied — unchanged mechanics
  from before.
- The fractional part scales the **in-progress** generation's operator magnitude
  (extrude distance or split displacement) from 0 up to its full sampled value,
  holding the target polygon/edge choice fixed — the same mutation that would happen
  at full strength, just growing in rather than popping in. `GenerationalEvolutionEngine.process`
  gained a `phase: Double?` parameter (`nil` = old static behavior, used by all
  pre-existing callers/tests unchanged) and `applyExtrude`/`applySplit` gained a
  `strength` multiplier on the sampled distance.
- `GenerationalEvolutionEngine.process(polygons:passes:elapsedFrames:targetFPS:spriteIndex:)`
  evaluates each pass's own `generationPhase` driver via the standard
  `DriverEvaluator.evaluate` (the same mechanism camera pan/zoom/opacity already
  use) — this is the one place playback time deliberately *does* drive the
  generational engine, unlike the internal per-generation randomness (§ note in
  `EvolutionParams`'s doc comment on why those two shouldn't be conflated).
- Fully consistent with the determinism model (§4.4.4): phase is just a continuous
  generalization of the discrete generation count, the whole chain still recomputes
  from scratch given `(baseShape, seed, params, phase)`, and scrubbing backward or
  looping an oscillator/keyframe driver "de-evolves" cleanly — no ratchet effect.
- Inspector: a `DoubleDriverEditor` "Reveal" section under Generations, same widget
  already used for Convergence Pressure.
- Help doc (`Resources/help.html`): new "Evolution — Generational" section with
  step-by-step guides for both a static evolved shape and an animated reveal
  (discrete vs. tweened), and a full parameter reference table.

Verified with 7 additional `GenerationalEvolutionEngineTests` (18 total, up from 11):
nil-phase matches static full-count, zero-phase is a no-op, integer phase matches
an equivalent static `generationCount`, fractional phase scales extrude distance and
split displacement by the exact predicted amount, and the `passes:` overload both
evaluates an enabled driver and falls back correctly when disabled. All 468 tests
in `LoomEngineTests` pass; both packages build clean.

**Vary seed per cycle (complete, 2026-07-07):** a `varySeedPerCycle: Bool` field on
`EvolutionParams` (default `false`, no effect unless `generationPhase` is also
enabled). Without it, a looping `generationPhase` driver (Oscillator, or Keyframe
with Loop/Ping-pong) retraces the *identical* growth every cycle — the engine is a
pure function of `(seed, generation index)`, and neither changes cycle-to-cycle. With
it, `GenerationalEvolutionEngine.process(polygons:passes:elapsedFrames:targetFPS:spriteIndex:)`
computes a cycle index for the pass's driver and swaps in an effective seed
(`generationSeed` combined with the cycle index via a golden-ratio splitmix64-style
mix, `combineSeed`) before calling the per-pass core — `generationSeed` itself is
never mutated, only the copy used for that call.

The cycle boundary is aligned to the driver's **trough** (its minimum output, i.e.
generation 0), not its raw internal wrap point:
- **Oscillator** — trough offset in normalized wave-position is `0.75` for
  Sine/Triangle, `0.5` for Square, `0.0` for Sawtooth (where each wave shape's
  minimum actually falls); `revealCycleIndex` computes `floor(t − troughOffset)`
  where `t` is the same `elapsedFrames·freqHz/targetFPS + phase` used internally by
  `DriverEvaluator`. Aligning to the raw wrap point instead (`floor(t)`) would flip
  the seed a quarter-cycle *after* the trough for Sine/Triangle — partway up the
  climb from generation 0 — producing a visible glitch mid-growth instead of a clean
  per-cycle change.
- **Keyframe** with `loopMode == .loop` — period is the last keyframe's frame;
  `.pingPong` — period is double that (a full there-and-back); `.once` and
  Constant/Jitter/Noise modes have no defined "restart," so `revealCycleIndex`
  returns `0` (no variation) for those.

Verified with 6 additional tests (24 total, up from 18): the trough-alignment math
itself (cycle stays 0 for a full period after the trough, increments exactly one
period later — both for Oscillator and Keyframe-loop), the `0`-fallback for a
disabled/non-looping driver, that two elapsedFrames values landing in the same
cycle produce the same cycle index despite different phases, that two values in
*different* cycles at the *same* phase produce different geometry when the toggle
is on, that results stay fully deterministic for a fixed elapsedFrames, and that the
toggle is inert when the reveal driver itself is disabled. All 474 tests in
`LoomEngineTests` pass.

Inspector: a "Vary seed per cycle" toggle directly below the Reveal driver section
in `EvolutionInspector`. Help doc: two new step-by-step guides (a smooth Oscillator
sweep with the `base = amplitude = Count/2`, `phase = 0.75` recipe worked out above,
and the vary-seed-per-cycle walkthrough) plus a new parameter-reference row.

**Live seed readout (complete, 2026-07-07):** `GenerationalEvolutionEngine` gained a
public `effectiveSeed(for:elapsedFrames:targetFPS:)` — a single shared entry point
wrapping the same "is `varySeedPerCycle` on and the driver enabled? combine; else
return `generationSeed` unchanged" logic that `process(polygons:passes:...)` already
used inline, so the pipeline and any UI reading the value can't drift out of sync.
`revealCycleIndex` was also made `public` (previously internal to the engine module)
so the UI can show which cycle is active alongside the seed.

`GlobalInspector` gained an "Evolution Seed" section at the very bottom of its
inspector — deliberately on the Global tab rather than the Transform tab, so it's
visible while watching a live preview regardless of which tab's canvas is showing.
It reads whichever Generational pass is currently selected via
`controller.selectedSubdivisionIndex`/`selectedEvolutionParamIndex` (set in the
Transform tab), evaluates `effectiveSeed`/`revealCycleIndex` at
`controller.currentTimelineFrame` (already kept in sync with live playback via
`ContentView`'s `.onChange(of: currentFrame)`) and `engine.globalConfig.targetFPS`,
and displays the set/pass name, the seed (selectable text, for copy-paste), and the
current cycle number when varying is active. Shows a placeholder when no
Generational pass is selected. The intended workflow: watch an animated reveal,
spot a generation you like, copy the seed shown here into that pass's own Seed
field, and turn off Vary seed per cycle to lock it in.

Verified with 3 additional tests (27 total) for `effectiveSeed`: matches
`generationSeed` unchanged when varying is off, matches it unchanged when the
driver is disabled even with varying on, and matches `combineSeed` of the current
cycle when varying is genuinely active. All 477 tests in `LoomEngineTests` pass.

**Bugfix (2026-07-07) — pasting a large seed silently failed.** Reported after
using the live seed readout above: copying a huge `effectiveSeed` (e.g.
`-3239489724241199657`, from `combineSeed`'s splitmix64-style mixing, which
routinely produces values across the full `Int` range) into the Seed field and
turning off "Vary seed per cycle" still played back the old (default `0`) seed
rather than the pasted one. Two independent bugs, both in the shared
`FloatEntryField` component (`Sources/Loom/Inspector/InspectorComponents.swift`),
not in the engine:

1. `FloatEntryField.formatted(_:)` displays large numbers with thousands
   separators (e.g. `"1,234"`), but `commit()` parsed the raw text with
   `Double(text)`, which rejects comma-grouped strings and returns `nil` —
   `commit()` then silently no-ops, leaving the stored value (and the visible
   `text`, confusingly still showing what was typed) unchanged. This affected
   *any* value ≥ 1000 in *any* field using this shared component, not just
   seeds. Fixed generally: `commit()` now strips thousands separators/whitespace
   before parsing.
2. Even with (1) fixed, `generationSeed`/`driftSeed` were edited via
   `intAsDoubleBinding`, bridging through `Double` for the text field. `Double`
   only exactly represents integers up to 2^53 (~9×10¹⁵) — a 19-digit seed like
   the one above (~3.2×10¹⁸) silently rounds to a *different* integer on the
   round trip, defeating the entire point of pasting an exact seed to reproduce
   a specific result. Fixed by adding `IntEntryField` — parses/formats `Int`
   natively with no floating-point step at all — and switching
   `EvolutionInspector`'s `generationSeed` and `driftSeed` fields to it. Other
   `Int` fields in the same inspector (`generationCount`, `extrudeRunLengthMin/Max`,
   `maxVertexBudget`) stay on the `Double`-bridged `FloatEntryField` — they're
   small user-chosen values (2–2000 range) well within `Double`'s exact-integer
   range, so there's no precision risk there, and no reason to touch working code.

Not fixed (out of scope for this bug report, flagged for awareness): other
`Int` seed-like fields elsewhere in the app (`branchSeed`, `entropySeed`, etc.)
share the same `Double`-bridging pattern and would have the identical precision
bug *if* a similarly huge value were ever pasted into them — none of them
currently have a "live huge-value readout" feature feeding them, so the practical
risk is low, but the pattern is worth remembering if that changes.

**Not yet done:** duplicate-and-graft, subdivision-cycle-as-operator, fitness
measures, lock/graft selection, budget cap on *lineage* count (moot until grafting
exists), an easing curve option for the tween (currently linear).

**Update (2026-07-09) — directional edge selection.** `EvolutionParams.directionalSelector`
restricts which edge the extrude/split operators may target by outward-normal
direction (§14) — reuses `ExtensionEngine.outwardNormal` via a new
`GenerationalEvolutionEngine.eligibleSegments` helper rather than a separate
implementation. Verified with 4 new tests (restricts target edge / no-op when no
edge qualifies, for both operators); all 27 pre-existing tests in this file needed
no changes.

---

## 13. Open Questions

1. **Naming in the UI (partially resolved).** Tab now shows "Transform" (the functional
   label) with Inv/Ext/Evo/Ful/Dis subtab abbreviations and full names in tooltips.
   The philosophical full names ("Fulguration", "Involution") appear in help documentation
   and subtab tooltips but not in inspector section headers — section headers use
   functional names ("Branch", "Extrude", "Curve Refinement") for discoverability.
   The data-model rename (Phase D: `SubdivisionParamsSet` → `TransformationSet`) is still
   deferred pending a migration strategy.

2. **Evolution state and determinism (resolved for momentum drift/convergence
   pressure).** No per-sprite state is accumulated. Drift at frame N is a closed-form
   weighted sum over a bounded history window (constant time, fully seekable).
   Verified via Phase 5 implementation. The planned generational sub-mode (§4.4,
   Phase 8) is a *different* case: it cannot be closed-form (generation N depends on
   N−1's materialized geometry and measured fitness), but is still fully
   deterministic and free of persistent state — the whole generation chain is
   recomputed per evaluation from its inputs, same category as subdivision depth or
   Extension's `branchDepth` (recursive and O(N), not O(1), but nothing incrementally
   mutated across rendered frames). See §4.4.4.

3. **Fulguration and the render pipeline (largely resolved by scoping, 2026-07-08).**
   §5.2–§5.10 works through most of this: V1's frame-cycle trigger needs no cross-sprite
   condition pre-pass at all (§5.3, Phase 7); V2's `.spriteMetric` trigger sidesteps the
   render-ordering question by reading the referenced sprite's previous frame rather than
   requiring a dependency-ordered evaluation pass (§5.9); the proximity trigger is the one
   piece that still needs the O(m×n)-with-bounding-box-pre-check treatment originally
   anticipated here. What's still genuinely open: true concurrent multi-instance firing
   (§5.9's last point) does need frame-level trigger state (firing/held/refractory) beyond
   what a stateless per-evaluation model provides, and is deferred beyond V1/V2 for exactly
   that reason.

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

7. **Serial pipeline now, parallel/cross-stage interaction later (deliberately
   deferred, 2026-07-08).** All five modes currently run in a fixed serial order
   (§7) — stacking N passes of one stage (e.g. 5 Subdivision passes) means all N
   complete before the next stage type ever sees the geometry, and no stage can see
   another stage's *resolved runtime state* (Dissolution can't read what generation
   Evolution landed on this frame; every stage only gets the same raw
   `elapsedFrames`/`targetFPS`/`spriteIndex`). This was a deliberate scoping decision
   when building Dissolution's driver system (§6.6): get all five modes solid and
   working serially first, then revisit interaction.

   The motivating example: a dissolution factor that *increases as Evolution's
   generation count increases*, so late generations start showing entropy/collapse/
   drift — decay as a function of evolutionary age, not just elapsed frame count.
   More generally, once Fulguration exists (Phase 7), its trigger state is an
   obvious candidate to feed Dissolution too (a Fulguration-triggered event
   accelerating nearby dissolution, for instance).

   This is *not yet built* — today, `dissolutionPhase` only reads
   `elapsedFrames`/`targetFPS`/`spriteIndex`, the same inputs every other stage
   reads independently. Enabling real cross-stage coupling needs new plumbing:
   `SpriteScene.renderInstance` already has both `activeInstance.evolutionParams`
   and `activeInstance.dissolutionParams` in scope at the point Dissolution runs
   (step 2f, after Generational Evolution's step 2e), so threading a resolved value
   — e.g. `GenerationalEvolutionEngine`'s current phase/generation count for a named
   pass — through as a new parameter to `DissolutionEngine.apply` is straightforward
   in principle. The open design questions are less about feasibility and more about
   shape: does every stage need a generic "read a named upstream value" mechanism
   (a small per-frame shared context passed through the whole pipeline), or are
   coupling points added one at a time as specific features are built (as sketched
   above)? The former is more general but risks premature abstraction before there's
   a second or third concrete use case to generalize from; the latter is simpler now
   but may need reworking once two or three specific couplings exist side by side.
   No decision has been made — flagged here so it isn't lost, not to be resolved
   until there's a concrete second stage genuinely needing it.

---

## 14. Directional Selection

### 14.1 What it is

Raised 2026-07-09: can a transformation be constrained to a *portion* of a shape —
"just the top edge of a square" — or to a *direction* — "only grow vertically
upward," or on an open curve, "only where the tangent falls within some angle
range"? Before this, every mode's edge/vertex selection was either positional/index
(Extension's `.longestEdge`, PTP's `whichSpike` "CORNERS"/"MIDDLES") or magnitude
(longest edge by length) or pure random (Generational Evolution's hash-picked edge)
— nothing tested *which way something faces*. Index-based selection ("edge 2") only
picks the intended edge by coincidence, for one specific known shape; it doesn't
generalize. Direction-based selection does: "the edge(s) whose outward normal points
within 20° of straight up" finds the right edge on *any* polygon, and is the same
underlying test whether the question is "the top edge" or "vertically upward" —
they're the same constraint, just phrased two ways. On a curve, the equivalent is
tangent angle instead of normal angle.

### 14.2 `DirectionalSelector`

A single shared primitive (`Sources/LoomEngine/Subdivision/DirectionalSelector.swift`)
rather than a bespoke filter per mode — the same reuse principle already applied to
`DoubleDriver` and the two-track phase/seed pattern (§6.6, §5.9) rather than
reinventing a similar mechanism for each mode that needs it:

```swift
struct DirectionalSelector {
    var enabled:     Bool             // false by default — every candidate eligible, unchanged
    var targetAngle: Double           // radians, atan2 convention: 0 = +x, π/2 = +y (up, Y-up engine)
    var tolerance:   Double           // half-width of the acceptance cone, radians
    var basis:       DirectionalBasis // .outwardNormal (closed polygons) | .tangent (open curves)
}
```

`accepts(_ direction: Vector2D) -> Bool` is the whole interface: true unconditionally
when `enabled` is false; otherwise true when `direction`'s angle is within
`tolerance` of `targetAngle` (wrapped correctly across the ±π boundary); true for a
near-zero-length `direction` (a degenerate edge has no direction to test — treated
as "not excluded by this filter," not as a false match for a real direction).

**Prerequisite math added, not previously present:** `Vector2D` had no `.angle`
(atan2), `.normalized()`, or `.dot(_:)` — every call site that needed a direction or
angle hand-rolled it inline. Added directly to `Vector2D.swift` since nothing
downstream (this selector, or any future directional feature) can be built without
them.

### 14.3 Where it's wired in (2026-07-09)

Two modes, chosen because both already compute the exact vector this selector
needs to test — the filter only had to intercept an existing computation, not
introduce a new one:

- **Extension** (`ExtensionParams.directionalSelector`) — applied in
  `ExtensionEngine.extrudePolygon` as an additional filter on the candidate segment
  indices *after* `extrusionTarget`'s existing `.allEdges`/`.longestEdge` selection,
  so the two compose ("the longest edge, but only if it also faces the required
  direction" is a legitimate, and correctly empty-able, combination).
- **Generational Evolution** (`EvolutionParams.directionalSelector`) — applied in
  `GenerationalEvolutionEngine.eligibleSegments`, restricting which edge the extrude
  operator's run may *start* from and which edge the split operator may target. A
  contiguous extrude run still grows contiguously from its (now direction-filtered)
  start point exactly as before, which can spill onto non-eligible neighboring edges
  as `runLength` grows past 1 — treated as intentional ("a run growing from a
  qualifying edge"), not a leak to close.

**Byte-for-byte unchanged when disabled**, not just "approximately the same": both
integrations replace an old `Int(roll * Double(segCount)) % segCount` index
computation with `eligibleSegs[Int(roll * Double(eligibleSegs.count))]`, and
`eligibleSegs == Array(0..<segCount)` whenever the selector is off — the same roll
value produces the identical index either way. All 27 pre-existing
`GenerationalEvolutionEngineTests` needed zero changes to keep passing.

**Shared normal computation.** `ExtensionEngine`'s outward-normal formula
(edge-direction vector rotated 90°, normalized) was previously duplicated inline at
three call sites (`extrudePolygon`, `extrudeEdge`, and — now — the directional
filter itself). Factored into one internal `ExtensionEngine.outwardNormal(of:segIdx:)`
used by all three, and reused directly by `GenerationalEvolutionEngine.eligibleSegments`
rather than a fourth copy of the same math.

### 14.4 Not yet wired in

- **Involution's `whichSpike`** (`PTPTransformSet.swift`) is a raw `String`
  ("ALL"/"CORNERS"/"MIDDLES"), not an enum, and its selection is purely
  positional over pre-built anchor pairs — no normal/direction concept exists there
  at all yet. Adopting `DirectionalSelector` here is plausible but untouched so far.
- **Dissolution's Partial Loss** selects whole *polygons* from a subdivided set, not
  edges of one polygon — "directional" for that case can't mean "outward normal" (a
  whole polygon doesn't have a single one); it would need a different selector kind,
  most likely "polygon centroid position relative to the set's bounding box." Related
  to, but not a drop-in extension of, the edge-based selector above.
- **"Direction of effect" as distinct from "which edges are eligible"** — forcing an
  operator's displacement to point in a fixed direction (e.g. "any edge, but always
  push it upward") regardless of that edge's own normal — was named explicitly in
  the motivating discussion but not built. Extension's width/curvature math currently
  assumes displacement runs *along* the edge's own outward normal; decoupling the two
  needs rework there, not just a filter.

---
