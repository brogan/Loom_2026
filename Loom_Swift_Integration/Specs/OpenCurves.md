# Procedural Open Curves — Spec

**Status**: Concept / pre-implementation  
**Affects**: LoomEngine, Loom (studio), LoomLive (performance instrument)

---

## 1. The Gap

Loom's procedural system is built around a single core operation: structural decomposition
of closed polygons. One closed polygon splits into N child polygons, each inheriting and
transforming the parent's properties. This is powerful for building recursive, self-similar
visual forms — but it has no natural equivalent for open curves.

Open curves (a sequence of Bezier segments without closing) are:
- The most immediate geometry to produce live (a single drawn gesture)
- Often more expressive than closed forms for musical contexts (direction, tension, line quality)
- Capable of their own rich procedural vocabulary — but that vocabulary is entirely different
  from subdivision

Subdivision makes no sense for an open curve. Splitting a stroke into child strokes is not
a useful operation. What *is* useful is:

- **Deformation**: the curve moves, breathes, distorts over time
- **Refinement**: detail is added at the curve's control points without structural decomposition
- **Growth**: the curve extends from one or both ends
- **Parametric generation**: curves defined by mathematical functions rather than manual drawing
- **Stroke rendering**: variable width, taper, pressure, brush profile along the arc

These constitute a distinct procedural class — call it **curve evolution** — that stands
alongside subdivision rather than beneath it.

---

## 2. The Existing Model

Loom currently has a `line` polygon type. The subdivision engine already handles it
specially — converting line points to spline points via `BezierMath.lineToSplinePoints`
before dispatching. But then the existing subdivision algorithms (QUAD, TRI, BORD) are
applied, which are designed for closed forms. The result is technically functional for
certain cases but is not a coherent open-curve procedural system.

What exists:
- Open curve geometry type (`Polygon2D` with `.line` type)
- Basic stroke rendering
- Per-point transforms (PTP) — these could apply to open curve points
- Driver system — applicable in principle

What is missing:
- Deformation operations designed for open curves
- Growth/extension operations
- Parametric curve generators
- Variable-width stroke rendering driven by parameters or drivers
- A coherent "curve evolution" layer distinct from subdivision

---

## 3. Curve Deformation Operations

These operations transform the shape of an existing open curve each frame. They compose
with each other and with the driver system.

### 3.1 Orthogonal displacement (Breathe)

Each control point is displaced perpendicular to the local curve tangent by an amount
driven by a DoubleDriver. The simplest form: a single sinusoidal driver displaces all
points by the same signed amount — the curve "breathes" in and out, like a bow.

A more complex form: each point has a phase offset proportional to its position along
the arc length, so displacement travels as a wave down the curve. This produces a
"swimming" or "flag in the wind" motion.

Parameters:
- `breatheAmplitude: DoubleDriver` — peak displacement (canvas units)
- `breatheFreq: DoubleDriver` — oscillation frequency (shares DoubleDriver modes)
- `breathePhaseSpread: Double` — 0 = all points in phase; 1 = one full cycle of phase
  shift from first to last point (travelling wave)
- `breatheDirection: BreatheDirection` — toward/from canonical normal, or full oscillation

### 3.2 Tangential displacement (Stretch)

Points are displaced along the local tangent direction. This compresses and extends
segments of the curve without breaking its overall direction. Useful for rhythmic
pulsing along the length of a stroke.

### 3.3 Noise deformation

Each point is displaced by a 2D noise value sampled from its (x, y, t) position in
a smooth noise field. This produces organic, irregular motion that is coherent across
the curve (nearby points move similarly) but varies over time.

Parameters:
- `noiseAmplitude: Double`
- `noiseScale: Double` — spatial frequency of the noise field
- `noiseSpeed: Double` — rate of temporal evolution
- `noiseSeed: Int`

### 3.4 Attractor deformation

One or more attractor points pull or repel control points by an inverse-square or
linear falloff. The curve bends toward or away from attractor positions. Attractors
can themselves be driven (oscillating, moving).

This is most useful in the performance context: the collaborator (or a MIDI CC) moves
an attractor position, and curves in the scene respond by bending toward the musical
gesture.

### 3.5 Anchor-point drivers (per-point)

Each anchor point on an open curve can have independent position drivers — the existing
`PTP` (per-point transform) concept extended for open curves. The drivers apply in the
curve's local coordinate system (along and perpendicular to the curve direction) or in
global canvas space.

This is the most general deformation model: individual points move independently
according to oscillator, noise, or MIDI-driven values. It requires an interface to
assign and configure per-point drivers, which is more complex than the global operations
above but more expressive.

---

## 4. Curve Growth

Growth operations add or remove points from a curve's ends over time, causing it to
extend, contract, or trace a path through space.

### 4.1 Extension

The curve's endpoint moves along a direction (constant, oscillating, or driven by a
DoubleDriver). New Bezier segments are appended as the endpoint travels. The control
points of new segments are computed by continuing the curvature of the most recent
segment, optionally with added noise or angular jitter.

Parameters:
- `growthRate: DoubleDriver` — canvas units per frame
- `growthDirection: DoubleDriver` — angle in radians, driven or constant
- `growthCurvature: Double` — how strongly new segments follow existing curvature
- `growthNoise: Double` — angular noise added to each new segment
- `maxLength: Double` — if set, the oldest end of the curve is consumed as the new end grows (snake mode)

### 4.2 Decay / erosion

Points are removed from one or both ends of the curve over time. Combined with extension,
this produces a snake or comet effect: a fixed-length curve that traces a path through
space.

### 4.3 Branching (future / complex)

A growth point splits into two, producing a branching tree structure from an initially
simple stroke. This is architecturally complex (the data model changes from a linear
sequence to a tree) and is left to a later phase.

---

## 5. Parametric Curve Generators

Rather than starting from a manually drawn gesture, parametric generators produce curves
from mathematical definitions. These are specified by parameter values, which can
themselves be driven.

### 5.1 Lissajous

`x(t) = A · sin(a·t + δ)`, `y(t) = B · sin(b·t)`

The frequency ratio `a:b` determines the loop structure. Driving `a` or `b` with a
slowly changing value produces morphing Lissajous figures. Mapping MIDI pitch to the
ratio gives a direct musical-to-visual correspondence that is structural rather than
decorative.

### 5.2 Spiral

`x(t) = r(t) · cos(t)`, `y(t) = r(t) · sin(t)` where `r(t)` grows or shrinks.
Driving the growth rate or angular velocity gives expanding/contracting spirals.

### 5.3 Harmonic curve

A base circle perturbed by a sum of harmonics:
`r(θ) = R + Σ aₙ · sin(n·θ + φₙ)`

Each harmonic's amplitude can be driven independently. This connects directly to musical
harmonic structure: driving the first few harmonic amplitudes from the first few overtones
of the current musical note produces curves whose geometry reflects the timbre.

### 5.4 Reaction-diffusion / flow field (complex, future)

Curves that follow vector field lines through a reaction-diffusion or flow field, where
the field parameters are driven by musical variables. This is computationally heavier
and deferred to a later phase.

---

## 6. Stroke Rendering

Open curves need a rendering model different from closed polygon fill. Key parameters:

### 6.1 Width profile

The stroke width varies along the arc length according to a profile function. Profiles:
- `constant`: uniform width
- `taper`: width decreases toward one or both ends (pressure-sensitive pen feel)
- `envelope`: width follows a user-defined curve (wide in middle, narrow at ends)
- `driven`: width at each point is driven by a DoubleDriver sampled along the arc

Width can also be driven globally — a single DoubleDriver scales the entire width
profile. This allows musical amplitude (velocity envelope) to control stroke weight.

### 6.2 Opacity profile

Same structure as width — constant, taper, envelope, or driven variation along the arc.

### 6.3 Brush profiles / texture (future)

Stamp-based stroke rendering (a sequence of brush stamps placed along the path) already
exists in Loom for closed polygon edges. Adapting this to open curves would give access
to the full brush system for stroke rendering.

### 6.4 Color along arc

The stroke color shifts from one value to another along its length. Useful for
representing directed energy or motion — a curve that fades from its origin color
to a destination color.

---

## 7. Integration with the Driver System

The operations above are most useful when their parameters are driven — connected to
oscillators, noise, or (via the MIDI system) to live musical input.

The existing `DoubleDriver` system applies directly: any scalar parameter on a curve
evolution operation can be a DoubleDriver. The integration work is:

1. Representing curve evolution parameters in the data model (alongside subdivision params)
2. Resolving drivers at frame time (same pattern as `resolveDrivers` in SubdivisionEngine)
3. Applying the resulting parameter values to the curve geometry before rendering

The natural data structure is a `CurveEvolutionParams` type analogous to `SubdivisionParams`,
with its own driver struct (`CurveEvolutionDrivers`) and engine (`CurveEvolutionEngine`).

---

## 8. Relationship to Subdivision

Curve evolution and closed-polygon subdivision are parallel systems, not a hierarchy.
A Loom polygon set can contain both closed polygons (processed by SubdivisionEngine) and
open curves (processed by CurveEvolutionEngine). They render into the same canvas.

The two systems share:
- The driver infrastructure (DoubleDriver, DriverEvaluator)
- The rendering pipeline
- The PTW / per-point transform concepts (though the specific operations differ)

They do not share:
- The subdivision algorithm dispatch (meaningless for open curves)
- The inset transform system
- The visibility rule system (though an analog — drawing probability — could exist for curves)

---

## 9. Relevance to LoomLive

In the live performance context, open curves with curve evolution are the most immediate
expressive material. The workflow is:

1. Draw a gesture (4–6 Bezier segments, a few seconds of work)
2. Assign a curve evolution preset (e.g., "breathe", "wave", "noise drift")
3. The gesture is immediately alive — it breathes, moves, responds
4. MIDI input drives the evolution parameters (amplitude from velocity, frequency from pitch)
5. The curve can be extended, branched, or allowed to decay during performance

This entry point — draw, evolve, perform — is faster and more gestural than the closed-polygon
workflow (construct geometry, design subdivision, tune parameters, animate). It is not a
replacement for that workflow but a complement: the studio work builds closed-form vocabulary,
the live work builds open-form gesture.

---

## 10. Implementation Phases

### Phase 1 — Deformation (foundation)

- `CurveEvolutionParams` data model with `breathe` and `noise` operations
- `CurveEvolutionEngine` applying operations per frame
- Driver integration for amplitude and frequency
- Loom inspector: curve evolution section for open-curve polygon sets

### Phase 2 — Growth and stroke rendering

- Extension / decay operations
- Variable-width stroke rendering (taper + driven width)
- "Snake mode" (fixed-length moving curve)

### Phase 3 — Parametric generators

- Lissajous and spiral generators
- MIDI-to-parameter mapping for generators (pitch → frequency ratio)
- Harmonic curve generator

### Phase 4 — LoomLive integration

- Gesture drawing in live session
- Quick evolution preset assignment
- Attractor control via live pointer / MIDI CC
- Per-point driver assignment in performance context

---

## 11. Open Questions

1. **Data model for per-point drivers.** Open curves can have variable numbers of points
   (growth changes point count). A per-point driver array would need to resize gracefully.
   One approach: drivers are indexed by normalised arc position (0–1) rather than point
   index, and interpolated to the current point count each frame.

2. **Closed vs open in the same polygon set.** Should a polygon set be able to contain
   both closed and open polygons? Currently yes (mixed sets are possible). The evolution
   engine needs to handle both without forcing every open curve to go through subdivision.

3. **Interaction between deformation and stroke rendering.** If a curve is simultaneously
   deformed (breathe) and rendered with a width profile, the visual weight of the stroke
   shifts as the geometry moves. This may be desirable (physical plausibility) or
   undesirable (the width should be stable). A flag on the width profile — `anchoredToGeometry`
   vs `anchoredToArcPosition` — would control this.

4. **Edit mode for driven curves.** If a curve's control points are being driven, editing
   them in the geometry editor (which expects static positions) becomes confusing. A
   "freeze evolution" toggle during editing would address this.

5. **Performance of per-point noise.** A scene with many long open curves, each with
   per-point noise deformation, could become expensive. Spatial indexing and LOD (fewer
   deformation points for curves far from camera or small on screen) may be needed.
