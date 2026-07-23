# Convolution — Spec

**Status**: Concept / pre-implementation
**Affects**: LoomEngine, Loom (studio), Geometric Lifecycle pipeline (`Specs/GeometricLifecycle.md`)

---

## 1. The Gap

Raised by user request 2026-07-23. Across all five existing Geometric Lifecycle modes,
nothing takes an already-resolved set of point coordinates and warps them in place
through a continuous spatial function:

- **Involution** partitions a form's interior via discrete recursive rules (Quad, Tri,
  Split, …) — it changes vertex/polygon *count*, but by construction preserves the outer
  silhouette.
- **Extension** adds new connected structure beyond the original boundary (Branch,
  Extrude) — it changes vertex/polygon *count* and extends the silhouette outward.
- **Evolution** either blends scalar parameters toward a target (Momentum Drift,
  Convergence Pressure — changes *what subdivision computes*, not raw coordinates
  directly) or iteratively mutates materialized geometry structurally (Generational —
  changes vertex/polygon *count* again, via Extrude/Split/Graft).
- **Fulguration** conditionally reveals transient assembled or transformed content.
- **Dissolution** removes material (Collapse, Partial Loss) or lets it drift as rigid
  pieces (Drift) — again changing count, or moving whole polygons rather than
  reshaping the point field they're built from.

There is no operator today that takes the existing point list — however it got there —
and bends, twists, or shears it as a field, the way a lattice deformer, bend modifier,
or displacement map works in 3D tools. Sprite-level rotation/scale/skew (position,
scale, rotation drivers) is the closest existing analogue, but that's a single rigid
transform of the *whole sprite*, not a spatially-varying warp of its *internal* point
distribution — a twist that rotates more at the shape's edge than at its centre, for
instance, has no way to exist today.

This spec proposes **Convolution**: a coordinate-space warp stage, driver-animatable
like every other stage, that fills exactly this gap.

---

## 2. Taxonomy — Evolution, Involution, or its own mode?

Raised directly by the user alongside the proposal, because it's a real design fork,
not a naming detail: does Convolution belong under Evolution, does it pair with
Involution under some wider shared category, or does it stand alone as a sixth mode?

**The user's own test — "does it produce something new, or only modify what already
exists?" — is correct and important**, but applying it precisely reveals Convolution
sits almost exactly *between* Involution and Evolution rather than cleanly inside
either:

- **Vs. Involution.** Convolution shares Involution's "no new material" property —
  neither adds nor removes a single vertex. But Involution's defining *mechanism* is
  discrete recursive partition that deliberately **preserves the outer silhouette**
  while increasing internal complexity ("a form analyzes itself"). Convolution's
  mechanism is a continuous coordinate remap that **alters the outer silhouette**
  while leaving vertex/polygon count untouched. The two are almost mirror images of
  each other along different axes (count vs. silhouette) — an elegant contrast, but
  one that means folding Convolution *under* Involution would stretch Involution's
  specific meaning (recursive self-partition) to also cover something structurally
  opposite to it.
- **Vs. Evolution.** Evolution's original framing in §1/§4 of `GeometricLifecycle.md`
  explicitly promised "deformation... noise, shear, twist" — this proposal is, in
  spirit, exactly that unbuilt promise (§4.4's phase plan lists "Phase 2: Evolution
  (deformation for closed polygons)," never delivered as a direct coordinate warp).
  But Evolution *as actually built* now means two specific, narrower things: blending
  scalar parameters toward a target state (Drift/Convergence — genuinely about
  *becoming* something else, "directed development"), or iterative artificial-life
  structural mutation (Generational — genuinely additive/subtractive, and notably
  already overlaps with Extension's own vocabulary since Generational's Extrude
  operator is literally Extension's edge-extrusion relocated into a generation loop).
  Neither of Evolution's two real mechanisms is a continuous field-warp. Adding
  Convolution as a *third* Evolution mechanism, at a *third* pipeline position, would
  mean one mode/tab covers three genuinely different kinds of operation — already a
  stretch with two (see `GeometricLifecycle.md` §7's note that Evolution "appears
  twice" for exactly this reason), and a third makes the mental model harder to hold,
  not easier.

**Recommendation: Convolution stands as its own, sixth, first-class mode** — not
nested under Involution or Evolution, and not placed under an invented shared parent
category either. The existing five modes are already a flat sibling list (no
hierarchy exists today in the UI, the inspector, or this spec's own framework table);
introducing a two-level hierarchy just to house two members (Involution + Convolution)
would need to also explain where Extension/Evolution/Fulguration/Dissolution sit
relative to that new grouping, and none of them fit under it cleanly either
(Generational Evolution is itself additive/subtractive, so a "no new material" parent
category would misclassify it). A flat sixth peer avoids that problem entirely and
costs nothing structurally, since nothing currently depends on the five-fold count
being exactly five.

Convolution's own philosophical register, added as a sixth row to the framework
table in `GeometricLifecycle.md` §1:

| Mode            | What happens                                        | Philosophical register              |
|-----------------|------------------------------------------------------|-------------------------------------|
| Involution      | A form analyzes itself into parts                   | Self-complexity, inner structure     |
| Extension       | A form grows outward into new territory              | Growth, becoming, reaching          |
| **Convolution** | **A form's own material bends and redistributes through space** | **Torsion, distortion, internal tension** |
| Evolution       | A form accumulates change along a trajectory         | Metamorphosis, directed development |
| Fulguration     | Form emerges when conditions are met                 | Emergence, threshold, encounter     |
| Dissolution     | A form loses specificity or suddenly ends            | Entropy, release, ending            |

If a shared parent still feels worth having purely for UI/conceptual tidiness later
(e.g. grouping Involution + Convolution as "the two modes that don't change how much
material exists," contrasted with Extension/Fulguration/Dissolution's "how much
material exists" changes, with Evolution as a cross-cutting temporal thread rather
than a peer) — that's a legitimate alternative framing, and cheap to introduce later
as a purely presentational grouping in the UI/docs without changing the engine
architecture below. It just isn't recommended as the starting structure, since it
doesn't cover all six modes cleanly and would need re-litigating the moment
Generational Evolution's own classification comes up.

---

## 3. Core Operations

Two analytic primitives form the minimal, cheap, well-understood phase-1 set. Both
operate purely on the existing point list — no new vertices, no topology change.

### 3.1 Torsion (twist)

Each point is rotated around a reference centre by an angle that is a function of the
point's distance from that centre — a spiral warp. At `twistFalloff: .constant` this
degenerates to a plain rigid rotation (already covered by sprite-level rotation), so
`.constant` should be flagged in the UI as a degenerate case rather than a genuinely
new effect, the same way the codebase already flags other degenerate parameter
corners (e.g. Branch's `n≤2` collapsing to a line).

Parameters:
- `twistCenter: TwistCenter` — `.centroid` (default, per-shape, closed polygons) |
  `.boundingBoxCentre` (default for open curves — see §5) | `.custom(Vector2D)`
- `twistAmount: DoubleDriver` — rotation (radians) at the reference radius
- `twistFalloff: TwistFalloff` — `.linear` (angle grows proportionally with distance —
  classic spiral) | `.inverse` (twist concentrated near the centre, fading toward the
  edge) | `.constant` (degenerate — see above)
- `twistReferenceRadius: Double` — normalizes the falloff curve so `twistAmount` means
  "the rotation at this radius," independent of the shape's absolute size

### 3.2 Shear

Each point's coordinate along one axis is offset proportional to its position along a
perpendicular reference axis — a generalized shear, not fixed to X/Y.

Parameters:
- `shearAxis: Double` — angle (radians) of the shear direction
- `shearAmount: DoubleDriver` — displacement magnitude per unit distance along the
  perpendicular axis
- `shearOrigin: TwistCenter` (reuses the same enum as §3.1 — the axis passes through
  this point) — default `.centroid` / `.boundingBoxCentre`

### 3.3 Bend (V2)

A virtual-arc distortion: points progressively rotate as if the shape were wrapped
around an invisible circle, the way a 3D "bend" deformer works. More expensive to
reason about than twist/shear (needs a defined "along" axis and origin position along
it) and shares enough machinery with Torsion that it's sequenced after §3.1–3.2 are
validated, not built in parallel with them.

Parameters (sketch, not finalized):
- `bendAxis: Double` — direction defining "along" vs. "across" the bend
- `bendCurvature: DoubleDriver` — inverse radius of the virtual bend circle (0 = no
  bend, dead straight)
- `bendOrigin: Double` — 0–1 position along the bend axis where the bend is centred

### 3.4 Displacement map (V3)

The heaviest addition, matching the user's "could potentially enable the use of
displacement maps" framing directly. Sample a greyscale (or single-channel) image and
use the sampled value at each point's location to displace that point along its own
local outward direction (closed polygons: true outward normal, exactly
`ExtensionEngine.outwardNormal`; open curves: the same `openCurveSafeOutward`
convention Extension/Generational Evolution already established for the "no true
interior" case, §3.3/§4.4.6 of `GeometricLifecycle.md`) — the same idea as a bump/
displacement map in a 3D pipeline, applied to a 2D point field instead of a mesh
surface.

Parameters (sketch, not finalized):
- `displacementMapName: String` — references an image asset (reuse the existing
  image-loading path already used for SVG sprites/brushes — no new asset pipeline)
- `displacementStrength: DoubleDriver` — scale from sampled value to coordinate offset
- `displacementMapping: DisplacementMapSpace` — `.boundingBox` (UV normalized to this
  shape's own bounding box — self-contained, portable distortion) | `.canvas` (UV
  normalized to absolute canvas position — lets one map drive correlated distortion
  across every sprite in a scene that samples it, e.g. a shared cloud/noise texture)
- `displacementChannel: DisplacementChannel` — `.luminance` (default) | `.red` |
  `.green` | `.blue` | `.alpha`

This is genuinely new engineering, not relocated code — nothing today samples an
image to warp *geometry*, only to *render* pixels (brush/stamp bitmaps, SVG sprite
rasters) — so it's correctly the last phase, built only once §3.1–3.2 have proven the
parameter/driver/UI pattern out.

---

## 4. Driver Integration

Every amount/strength field above (`twistAmount`, `shearAmount`, `bendCurvature`,
`displacementStrength`) is a `DoubleDriver`, exactly like Extrude Distance or Branch
Angle — wire an Oscillator for a shape that visibly twists back and forth, a slow
Noise driver for organic torsional drift, or a Keyframe ramp to un-twist a shape over
the course of an animation. This is not a new driver mechanism — it's the existing
`DriverEvaluator` infrastructure applied to a new set of fields, the same reuse
pattern every other stage already follows.

---

## 5. Applicability — Open Curves and Closed Polygons

Because these operations act purely on the point list regardless of topology, they
apply uniformly to **both** open curves and closed polygons with no toggle or
special-casing required — one of the only stages in the whole pipeline able to claim
unconditional "Both" support. The one real wrinkle: closed polygons have a natural
`centroid` for `twistCenter`/`shearOrigin`; open curves don't have an interior in the
same sense, so they default to the curve's own bounding-box centre instead — the same
"no true centroid" problem Extension's Branch and Generational Evolution's Split/Graft
already solved for open curves (via `openCurveSafeOutward` and bounding-box/chord-based
fallbacks), not a new kind of problem this spec needs to solve from scratch.

---

## 6. Pipeline Position

Recommended placement in the fixed pipeline (`GeometricLifecycle.md` §7):

```
Base geometry
     ↓
[Evolution]     — momentum drift; convergence pressure (params only)
     ↓
[Involution]    — subdivision (closed) / curve refinement + segment extraction (open)
     ↓
[Extension]     — branching (open/closed); edge extrusion (closed)
     ↓
[Convolution]   — torsion; shear (V2: bend; V3: displacement map)
     ↓
[Evolution]     — generational (artificial-life mutation of materialized geometry)
     ↓
[Fulguration]   — frame-cycle trigger; transform variation; assembly
     ↓
[Dissolution]   — entropy; collapse; contraction anchor; partial loss; drift
     ↓
Render
```

**Rationale for this slot** (after Extension, before Generational Evolution):
- Running *after* Involution + Extension means any newly grown structure (branches,
  extruded walls) gets captured in the same coherent warp — the whole assembled shape
  twists together as one piece, not just the pre-growth base.
- Running *before* Generational Evolution means subsequent generational mutation
  (Extrude/Split/Graft) operates on the already-warped base, so mutations follow the
  bent form's local geometry rather than being computed against a straight shape and
  only rigidly relocated afterward.

**Open alternative, not adopted by default:** running Convolution *before* Involution/
Extension instead would warp only the base shape, so branches/extrusions would grow
from already-twisted tangents — a different and also interesting character (spiraling
growth vs. growth-then-bent-as-one-piece). Worth prototyping both once a first version
exists; not a blocking decision for building phase 1.

---

## 7. Suggested Build Order

1. **Torsion only.** The single most legible operation, cheapest to validate — reuses
   existing per-point iteration (the same shape PTP's point-transform loop already
   uses) and existing `DoubleDriver` evaluation. Validate `twistFalloff` modes and
   centre resolution (`.centroid` vs. `.boundingBoxCentre`) against both open and
   closed test shapes before adding anything else.
2. **Shear.** Second analytic primitive, orthogonal to Torsion, similarly cheap —
   confirms the parameter/inspector pattern generalizes rather than being
   Torsion-specific.
3. **Bend (V2).** More involved math (virtual-arc mapping); sequence after Torsion/
   Shear are validated and feel right in the UI, not in parallel with them.
4. **Displacement map (V3).** Heaviest lift — needs the UV-mapping-space decision
   (§3.4) settled and an image-sampling function that nothing in the engine currently
   has. Build only once phases 1–3 have proven out the parameter/driver/UI pattern.

---

## 8. Open Questions

- **One stackable pass, or a mode picker? — Resolved 2026-07-23.** `ConvolutionParams`
  follows Extension's pattern (Branch vs. Extrude, `GeometricLifecycle.md` §3): one
  `operationType` case per pass (`.torsion` | `.shear`, later `.bend` | `.displacement`),
  each with its own conditionally-revealed field section, exactly one active per pass.
  To combine Torsion and Shear on the same shape, stack two Convolution passes in the
  set's pass list — the same way multiple Subdivision or Extension passes already
  stack. Rejected the alternative (all fields always present in one pass, closer to
  Dissolution's several-simultaneous-toggles model) on three grounds: (1) simplicity —
  matches the already-proven Extension/Evolution picker pattern instead of inventing a
  new one; (2) predictability — Torsion and Shear don't commute, so one combined pass
  would bake in a hidden fixed internal order, whereas stacked single-op passes make
  the order explicit and visible as plain pass-list order; (3) creative potential — a
  combined pass gives exactly one fixed composition, while stacked passes are a strict
  superset (any order, any repeat count, independent per-pass drivers) using the
  add/duplicate/delete/reorder/enable list UI every other mode already provides for
  free. Dissolution's toggle-in-one-pass model remains correct for *its* case because
  Entropy/Collapse/Drift are complementary aspects of one aging process, not
  alternative operations — that relationship doesn't hold between Torsion and Shear.
- **Convolution as a Generational Evolution operator, too?** Twist/shear could
  additionally become a fourth per-generation mutation operator (alongside Extrude/
  Split/Graft) inside Generational Evolution's own loop, exactly as Extrude is today
  reused both as a standalone Extension operator *and* as a Generational Evolution
  operator (`GeometricLifecycle.md` §4.4.2). Not exclusive with the standalone
  Convolution stage proposed here — both could exist — but sequencing/priority is
  worth deciding only once the standalone version is built and validated, not before.
- **Displacement-map UV convention** (`.boundingBox` vs. `.canvas`, §3.4) is a real
  creative fork — self-contained per-shape distortion vs. scene-coherent shared
  texture producing correlated distortion across every sprite that samples it. Worth
  prototyping both cheaply before committing to one as the default.
