# Loom Performance Architecture — Visual Composition Spec

**Status**: Concept / pre-implementation  
**Companion to**: `MIDIPerformance.md`, `OpenCurves.md`

---

## 0. Where LoomLive Lives

**Revised.** Earlier drafts of this section argued LoomLive must be a wholly separate
application from Loom. That argument rested on a technical claim — live, in-place engine
mutation being "a genuinely new runtime capability, not achievable by exposing more of
Loom's existing UI" — which turned out to be wrong, or at least badly overstated. See §0.1
for what's actually true. With that removed, what's left is a softer UX argument that doesn't
force the same conclusion.

**For now: an additional tab inside Loom itself**, positioned after the Rendering tab (the
original proposal this whole effort started from). This is cheaper to build than standing up
a second app, needs no cross-app exchange format or project-import step (the tab just
operates on whichever project is already open), and gets the core hypothesis
(`LoomLiveV1Scope.md` §1) tested faster.

This is a decision for now, not for the whole vision. If MIDI hardware controllers, the DAW
model (§8), or a genuinely full-screen gig-ready performance mode later grow to a point where
a tab feels structurally cramped, revisit spinning it out into its own app at that point —
§0.2 keeps the separate-app model on file for exactly that. Don't treat "it's a tab" as
settled architecture for the whole vision, only for what's actually being built now.

### 0.1 What actually needed correcting

The claim was that Loom's editing model can't support live mutation at all. What's actually
true is narrower: **Loom's *inspector* is wired through a save-and-reload cycle** — every
edit goes through `AppController.updateProjectConfig`, a ~0.35s debounce, a disk write, and
then the entire `Engine` is torn down and rebuilt from that saved file, restarting animation
at frame 0. That's a deliberate, appropriate choice for a composition studio: edits are
infrequent relative to render time, and reproducibility from a saved file is the point.

But `LoomEngine` itself already supports cheap, in-place mutation of a *running* instance —
it just isn't exposed through the inspector's editing path. `Engine.updateLightingConfig(_:)`
and `Engine.updateLayers(_:)` (`loom_swift/Sources/LoomEngine/LoomEngine.swift:118,124`)
already push a new value straight into a live scene with no disk round-trip, used today by
the Lighting inspector for instant feedback. The same shape of method covers exactly what a
Live tab needs — staging (showing) and hiding a sprite, swapping its renderer set, attaching a
different transform set, toggling a driver — each a handful of lines, because `SpriteInstance`
already stores a sprite's geometry and its transform-pipeline parameters as separate,
independently-mutable fields, re-evaluated fresh every frame rather than baked once at
construction.

These mutators should identify their target sprite **by name, not by array index or any other
position-based reference**. Sprites can be shown and hidden at any time, so an index into
`scene.instances` is only valid until the next hide silently shifts everything after it —
name-based lookup (a linear scan for `def.name == target`, cheap given how few sprites a live
session realistically stages) avoids that whole bug class instead of working around it later.
`SessionWorkflow.md` §3.2 records the same requirement from the recording side: every visual
action event targets a sprite by name too, for exactly this reason, and reuses these same
mutators at replay time (§3.3).

So a Live tab doesn't need `AppController.updateProjectConfig` at all — it holds its own
`Engine` instance and calls mutators like these directly. This is small, real, additive
engineering, not the open-ended "genuinely new runtime capability" earlier drafts described.

**One thing this does require**: the Live tab's `Engine` must be a separate instance from
`AppController`'s own, constructed once from the same project directory. If it shared that
instance, an ordinary inspector edit made anywhere else in the app would trigger the usual
save→reload cycle, which replaces the whole `Engine` object — silently discarding whatever
live mutations the tab had made. Owning a separate instance pointed at the same project
directory sidesteps this cleanly.

**What's left of the original argument** is the UX one: a "nothing here is saved, everything
bypasses the normal editing flow" tab living in the same window as "everything here
autosaves deterministically" is a real mental-model seam, even though it's no longer a
technical wall. Worth a clear, hard-to-miss visual indicator that the Live tab is in its own
mode, so a renderer swap made there not showing up back in the Rendering tab reads as
expected behaviour, not a bug.

### 0.2 If this is ever spun out into a separate app

Kept for later, not current architecture. The model: `LoomEngine` as a shared Swift package
underneath two applications —

```
LoomEngine (Swift package)
    ↓                    ↓
Loom (studio)       LoomLive (performance instrument)
```

`Loom` is where vocabulary is built: geometry is drawn and refined, subdivision parameter
sets are designed, palettes and renderers are crafted, contexts are prepared and tagged.
`LoomLive` is where vocabulary is performed: contexts are switched, MIDI drives the
procedural parameters, the visual score is followed or departed from, the session is
recorded. A Loom project directory becomes importable into LoomLive as a library of prepared
contexts — the `.loom_projects` format as the contract between the two applications, with no
UI shared, only the data model and engine kept consistent. Concretely, LoomLive would load a
Loom project's full asset surface, not a reduced subset: geometry (polygon, curve, oval, and
point sets), transform sets (the Transform tab's subdivision parameter sets —
Involution/Extension/Convolution/Evolution/Fulguration/Dissolution passes), sprites and
sprite sets (including each sprite's own position/scale/rotation drivers — see the Driver
libraries addition to §3.1), and renderer sets (including each renderer's own drivers —
fill/stroke colour, point size, opacity, blur), with *all* associated sets available per
category, not just ones a specific scene references — this is what makes the rehearsal
surface (§2.5) possible regardless of which side of the app boundary it ends up on.

If this path is taken, Loom's own useful contribution to the ecosystem stays the same:
context authoring (§2), library tagging and export (§3), and open curve procedural tools
(`OpenCurves.md`) relevant to both studio and live use.

---

## 1. Motivation

The MIDI spec addresses *how* musical signals can be routed to Loom parameters.
This spec addresses the higher-level question: what is the nature of the visual collaborator's
work, and what architecture does that require? The core claim is that the visual collaborator
is a *composer*, not an *operator*. Their work is building a set of prepared visual-temporal
forms whose structural character is congruent with musical form — not wiring musical events
to visual parameters.

---

## 1. The Compositional Problem

The mechanical-mapping approach (MIDI CC 74 → ranDiv; beat → inset pulse) is seductive because
it is technically straightforward and immediately spectacular. It is also exhaustible: once you
have heard a visual element react to a beat, you have heard everything that approach has to say.
The problem is that it treats the visual layer as a *decoration* of the music rather than as a
parallel voice.

The alternative is structural correspondence: the visual work is constructed so that its own
internal organisation — its rhythms, its densities, its qualities of tension and resolution —
are *congruent* with those of the music, without being mechanically caused by them. The
difference is like the difference between a shadow (caused by the object, no independent
existence) and a counterpoint (a separate line that has its own identity while being composed
in relation to another).

What this requires practically:

1. The visual collaborator must be able to *prepare* visual material of varied character —
   not just a single scene but a repertoire of forms with different structural qualities.
2. They must be able to *move between* these prepared states during performance.
3. The associations between musical and visual form must be designed in advance as a
   compositional act — *these geometric forms belong to this musical section* — rather than
   computed in real-time by a mapping function.
4. There must be room for live improvisation *within* that prepared structure: the collaborator
   should be able to inflect, extend, or deviate from the prepared plan during performance.

---

## 2. The Context System

### 2.1 What is a context?

A **performance context** is a named, self-contained visual state. It specifies:

- Which polygon sets are active (geometry)
- Which subdivision parameter sets apply
- Which renderer (or renderer set) is active
- Which palette is in use
- Initial animation state (phase offsets, driver values)
- Contextual MIDI response behaviour (what MIDI events modify this context and how)

A context is not a complete project; it is a *prepared configuration* within a project.
A project used for performance might contain 8–12 contexts representing different sections
or characters of the visual composition.

### 2.2 Switching between contexts

Switching is a compositional act — the collaborator decides *when* to move. It is not
automatically triggered by a musical event (though a MIDI event can be mapped as a
*cue signal* that *suggests* a switch, not causes one — the collaborator confirms it).

Switch modes:
- **Cut**: immediate — the new context replaces the old with no transition
- **Crossfade**: the two visual states are composited, fading from one to the other over
  N frames. Useful when the musical transition is gradual (modulation, fade, bridge).
- **Morph**: subdivision parameters, line ratios, and inset scales interpolate between
  the two contexts. The geometry is the same; the character changes. Useful for
  gradual intensification or release within a section.

The collaborator can set a default switch mode per context-pair in advance, then override
it live.

### 2.3 Shared access between contexts

Contexts are not silos. A project has a **shared library** (see Section 3) from which
all contexts draw. Two contexts can reference the same polygon set but with different
subdivision params; they can share a palette but use different rendering configurations.

Shared elements allow visual *motifs* to appear across contexts while sounding different —
the same geometric form recurs but is transformed, the way a theme in music is developed
across sections without being repeated literally.

### 2.4 Contexts and timeline scenes

The existing timeline-scene system addresses temporal structure within a single animation
(different parameter states at different frames). Contexts address a different level:
the *repertoire* of prepared states the collaborator can move between. They are orthogonal.

A context might itself contain multiple timeline scenes (e.g., a 4-bar loop that evolves
internally), and switching between contexts switches which of those loops is playing. This
loop-within-a-context is, made explicit and first-class, exactly what §8.2 calls a **clip**:
a context is the patch (which sprites, drivers, transform sets, and renderer sets exist to
be used); a clip is a bounded loop of what happens with them over time.

### 2.5 The rehearsal surface

`MIDIPerformance.md` §4.5 describes a concrete sprite/driver/renderer-set surface that
operates beneath the context abstraction above: a working view where sprites are staged
individually, each with its own driver, transform-set, and renderer-set choices, live. This
is the practical mechanism for both *authoring* a context — assemble sprites and settings
interactively, then name and save the result as a context — and for *inflecting within* an
active context during performance without switching away from it entirely.

---

## 3. The Library System

### 3.1 Purpose

The collaborator works from prepared material. A library allows them to accumulate, tag,
and deploy:

- **Geometry libraries**: named collections of polygon sets with associated metadata
  (structural character, musical associations, origin project)
- **Subdivision libraries**: named parameter sets or parameter-set sequences, tagged by
  visual character ("rhythmic", "sparse", "dense", "turbulent", "still")
- **Renderer libraries**: named rendering configurations and palettes
- **Driver libraries**: named, reusable animation drivers (oscillator, noise, jitter,
  keyframe parameter sets) that can be attached to any staged sprite on the rehearsal
  surface (§2.5, `MIDIPerformance.md` §4.5) independent of which sprite originally defined
  them
- **Context libraries**: complete contexts from previous projects that can be imported
  and adapted

### 3.2 Tagging

Library items can carry informal tags assigned by the collaborator. Tags are not a formal
taxonomy — they are personal semantic markers ("bass material", "transition geometry",
"high-energy renderer"). The library interface shows items by tag, allowing rapid
visual browsing during preparation.

### 3.3 Cross-project sharing

A library can span multiple Loom projects. This allows the collaborator to build a
personal visual vocabulary over time — a repertoire of forms with known character that
they return to and develop across different pieces. The library is not a preset system
(presets imply fixed results); it is more like a composer's sketchbook — material with
potential that is realised differently each time.

---

## 4. The Visual Score

### 4.1 Structural mapping (preparation phase)

Before performance, the collaborator creates a **visual score** — a high-level structural
plan that maps visual contexts to sections of the musical form. This is analogous to the
conductor's score annotations rather than to a MIDI automation lane.

The visual score is not frame-precise. It works at the level of musical sections (intro,
A section, development, climax, resolution) and records:

- Which context is associated with each section
- The intended switch mode at each transition
- Shared elements and motifs that persist across sections
- Notes about the *quality* of the visual-musical relationship in each section ("sustain
  the dense geometry here while the bass drops out — let the absence be structural")

The visual score is edited in a dedicated panel (not the main timeline). It is the
collaborator's compositional document, not a technical automation file.

### 4.2 Performing against the score (performance phase)

During performance, the score is a *guide*, not a script. The collaborator can follow
it, anticipate it, or depart from it. The live interface shows:

- Current position in the musical form (derived from MIDI clock or the collaborator's
  manual tracking)
- Current active context
- Upcoming planned switch (with the option to defer or skip it)
- A simple notation of the contextual MIDI response behaviour in the current context

Within any given context, the collaborator can:
- Inflect geometry live (draw new elements, modify existing ones — see Section 5)
- Adjust the degree of MIDI responsiveness (how much the current MIDI signals affect
  the visual state, via a master "sensitivity" control)
- Switch to a different context than planned

### 4.3 Recording the performance

Collaborator actions (context switches, live geometry changes, sensitivity adjustments)
are recorded as a timestamped event log. After performance, this log can be reviewed
and refined — transitions tightened, inflections cleaned up — and replayed exactly.
This turns a live performance into a realisable composition that can be reproduced.

---

## 5. Live Geometry Work

The collaborator is not limited to working with pre-prepared material. During performance
(or in open/improvisatory sections) they can:

- **Draw new geometry** using Loom's geometry editor in a floating panel. New geometry
  enters the current context immediately.
- **Import from the library** by name or by browsing a thumbnail grid — fast access
  to familiar forms.
- **Transform existing geometry** (scale, rotate, distort control points) in real-time.

The key design requirement is that geometry operations be fast and direct — the interface
must prioritise speed of access over completeness of controls. A floating "quick geometry"
panel that exposes the 5–6 most useful operations (add polygon, scale, duplicate, link to
subdivision set) is preferable to routing through the full inspector.

### 5.1 Grid drawing (UM-style)

Alongside freehand drawing, LoomLive should support a second, more structured placement
mode modelled on the sibling app UM's grid tool (`/Users/broganbunt/UMApp`) — a faster,
more deliberate alternative to freehand for building up repeated or regular arrangements
of sprites live, rather than tracing organic curves.

UM's model is a toggle-cell paint grid, not point placement or a guide overlay: a fixed
rows × columns array of cells, each carrying `isDrawn` plus whatever style/shape is
currently active (`UMGridDocument`/`UMGridCell`). Painting is drag-to-toggle (Draw/Erase),
with a flood-fill tool and a shift-click straight-line shortcut. Transformation is
two-tiered: whole-grid Flip Horizontal/Vertical operations (with a Move-vs-Stamp toggle
for whether a transform moves existing content or leaves a copy behind), and a
per-selection numeric transform panel (Offset X/Y, linked or independent Scale X/Y,
Rotation) driven by sliders and number fields rather than an on-canvas drag gizmo — only
the offset is directly draggable, via a dedicated Nudge tool.

For LoomLive, each grid cell places a sprite (drawing from the loaded project's sprite
sets, §0) rather than a raw shape reference — so painting a cell is "stage this sprite
here," and the existing transform panel becomes the live position/scale/rotation control
called for in the rehearsal surface (§2.5, `MIDIPerformance.md` §4.5). Because UM's own
shape geometry is already Loom-native polygon JSON, no geometry translation is needed; only
the grid-cell placement/transform records themselves (`UMGridCell`, `UMOffset`) are
UM-specific and need a LoomLive-native equivalent mapped onto sprite placement fields.

### 5.2 Drawing layers

Freehand and grid-drawn sprites are organised into drawing layers, created and deleted
freely during a session — a lighter-weight, faster-moving sibling to Loom's own Layers tab,
which is an authoring-time tool built around more deliberate, one-at-a-time layer setup.

The underlying model is the same either way: `LoomEngine`'s existing `LoomLayer` type
already carries `opacity`, `blendMode`, and `isVisible`, with rendering order given by a
layer's position in the project's layer list — LoomLive reuses this directly rather than
inventing a parallel compositing model. What LoomLive adds is speed: a new drawing layer
should be a single action (not a multi-field setup), deletable just as fast, with opacity
and reordering exposed as live controls (§4.2) rather than inspector fields. Whichever
drawing layer is currently active receives new freehand or grid-drawn sprites; reordering
layers changes on-screen rendering order immediately, live.

---

## 6. Structural Correspondences (Design Vocabulary)

These are not automatic mappings but compositional patterns — ways of designing contexts
and MIDI responses so that visual and musical forms are structurally congruent. The
collaborator chooses which of these patterns to employ, when, and with what degree of
directness.

### Register and scale

High register in music tends toward lightness, delicacy, rapid motion; low register toward
weight, slowness, mass. The visual analog is inset scale (small, intricate polygons vs large,
heavy ones) and animation speed. A context designed for high-register material would use
small inset scales, fast oscillator rates, thin rendering strokes. One designed for low
register would use large, slow forms with heavier rendering.

The correspondence is not 1:1 (it would become mechanical) but *prepared* — the collaborator
designs the context to have the right character, and then deploys it when the music is in
that register. The MIDI signal tells the collaborator when the music is there; they decide
whether to switch.

### Harmonic density and visual complexity

A monophonic line, a dyad, a dense chord: these represent increasing harmonic complexity.
The visual analog is subdivision depth — a single unsubdivided polygon, a first-generation
subdivision, a multi-generation subdivision. A context designed for the moment of maximum
harmonic density would have deep subdivision, many active polygon sets, rich rendering.
One designed for a single melodic line would be sparse — perhaps a single elegant curve.

Again: the MIDI analysis tells the collaborator the current chord density. They decide
whether to switch contexts, and when. The music does not control the visuals; it informs
the collaborator's compositional choices.

### Tension and resolution

Harmonic tension (dissonance moving toward consonance) has a visual analog in geometric
regularity — irregular, asymmetric forms resolving toward symmetric ones. This can be
designed into a pair of contexts: a "tension" context with broken symmetry (off-centre
ranMiddle, unequal line ratios, irregular PTW displacement) and a "resolution" context
with ordered symmetry. The collaborator moves between them at musically appropriate moments.

### Texture and density of event

The contrast between a sparse texture (one or two notes) and a full texture (many simultaneous
voices) has a direct visual analog in the number of active polygons and the density of
subdivision. But it also has a temporal analog: sparse music tends toward long durations,
full music toward shorter. The visual analog is oscillator rate and animation speed.

### Rhythmic profile

A piece with a strongly articulated rhythmic profile (clear downbeats, regular pulse) invites
visual forms with their own strong rhythm — regular subdivision, periodic animation, clear
geometric structure. A piece with a more fluid, arrhythmic character invites more continuously
evolving forms — smooth noise drivers, organic subdivision, less regular geometry.

The collaborator prepares contexts with the appropriate rhythmic character. The MIDI clock
provides the pulse reference; whether the visuals follow it strictly, loosely, or not at all
is a compositional choice about the *relationship* between the two voices.

---

## 7. The Collaborator's Interface — Design Principles

1. **Preparation is primary.** The most important work happens before the performance.
   The interface must support deep, careful preparation — exploring the library, building
   contexts, designing the visual score. Speed during performance comes from the quality
   of preparation.

2. **The performance interface is minimal.** During performance the collaborator needs to
   see the current state, the immediate past, and the immediate future of the visual score —
   not the full parameter space. Controls should be large, unambiguous, and reachable
   without looking.

3. **The collaborator is a performer, not a technician.** The interface should feel like an
   instrument, not a control panel. This means reducing the number of simultaneous decisions:
   at any moment, the collaborator should be choosing *what* to do (switch contexts, inflect,
   hold) not *how* to do it.

4. **Departure from the plan should be easy and consequence-free.** The visual score is a
   guide. If the music does something unexpected, the collaborator must be able to deviate —
   skip a section, extend a context, switch to something unprepared. The interface should
   make improvisation natural.

5. **The recording of the performance is the score.** The final artefact is not the pre-
   prepared visual score but the recording of what actually happened. This should be clean
   enough to be reproduced exactly and fine enough to be refined into a finished composition.

---

## 8. The DAW Model: Clips, Tracks, and Effects Racks

### 8.1 Why the DAW analogy matters

This is not only a structural convenience — it is a fit to the actual audience. The people
most likely to use LoomLive are musicians, DJs, and electronic performers who already have
a deep, working mental model of tracks, clips, scenes, and effects racks from years of DAW
use (Ableton Live, Bitwig, Logic, Traktor). Building on that vocabulary rather than
inventing a parallel one lowers the barrier to entry substantially: a new user should be
able to look at LoomLive's session view and immediately understand what a track is, what a
clip does, and how to launch one, because it looks and behaves like software they already
know. Departures from the DAW model should be deliberate and well-motivated, not accidental.

### 8.2 Clips: Session View and Arrangement View

A **clip** is a self-contained, loopable unit of visual behaviour — a fixed duration (e.g.
4 bars, 8 bars, or a frame-count equivalent) over which sprites are shown/hidden, drivers
adjusted, and transform sets/renderer sets assigned: the kind of visual-action event
sequence already described in `SessionWorkflow.md` §3.2. A clip differs from a context
(§2) the way a DAW clip differs from an instrument patch: a context defines *what
configuration is available* — which sprites, drivers, transform sets, and renderer sets
exist to be used; a clip is *what happens with them over time*, played through that
configuration.

Clips exist in two complementary views, directly modelled on Ableton Live and Bitwig:

- **Session View**: a grid where each **track** (§8.4) is a column and each **scene** is a
  row; a clip lives at the intersection of a track and a scene. Clicking a clip launches it
  on its track — immediately or quantized to the next musically meaningful boundary (bar,
  beat; configurable globally or per clip) — replacing whatever was previously playing on
  that track. Clicking a scene launches every populated clip in that row at once, a fast
  way to recall a whole prepared arrangement across every track simultaneously. This is the
  live-performance surface: non-linear, improvisational, built for reacting in the moment.
- **Arrangement View**: the DAW-style lane timeline already specified in
  `SessionWorkflow.md` §4.5. Clips can be dragged from the Session View onto a track's lane
  here, laid out linearly in time, trimmed and slipped like any other segment. This is
  where a performance — live or rehearsed — is assembled into a fixed, exportable sequence.

The relationship between the two views matches DAW convention exactly: Session View is for
playing and discovering; Arrangement View is for composing the final, fixed structure —
and material moves freely between them. A clip launched live in Session View during a
recorded session is captured as a `clipLaunch` visual-action event (`SessionWorkflow.md`
§3.2); if the resulting run is good, it can be committed as a literal segment on the
Arrangement lane rather than re-triggered from the log entry.

### 8.3 Cycle vs one-shot playback identity

Every clip has a playback identity, set once as a clip property rather than chosen at
launch time (matching Ableton's Loop toggle): **cycle** clips repeat continuously until
stopped or replaced by another clip on the same track; **one-shot** clips play through once
and then resolve to a defined end state. The toggle itself is simple; what happens around
it is where the real design work sits.

**Launch and playthrough.** Both identities can still launch quantized to a bar/beat
boundary (§8.2) — quantization governs *when a clip starts*, not how it behaves once
running. A one-shot clip, once triggered, plays through its own duration unquantized; only
its start is snapped to the beat.

**What happens when a one-shot finishes** needs an explicit, chosen behaviour, not a
default that just falls out of the implementation:
- **Stop** — the track goes empty until something else is launched on it.
- **Hold** — the track freezes on the clip's final frame/state, visually present but
  static, until replaced.
- **Resume** — the track reverts to whatever clip (if any) was playing before the one-shot
  interrupted it.
- **Follow** — a designated next clip launches automatically, optionally after a delay or
  chosen at random from a small set. This is Ableton's Follow Actions model and is worth
  adopting close to verbatim: it's exactly the mechanism for chaining one-shot moments into
  a sequence without the collaborator triggering every single one by hand.

**Retriggering.** If a one-shot clip is triggered again while still playing, does it
restart from its own beginning, ignore the new trigger until it finishes, or crossfade into
a fresh run? This matters more here than in a DAW, because several of Loom's procedural
passes (Evolution, Dissolution) carry accumulating internal state — restarting cleanly means
resetting that pass's state at the retrigger point, not just re-seeking a timeline position,
which is a genuine implementation detail and not only a UI question.

**Duration doesn't have to be authored — it can be native to the process.** A DAW one-shot
is always a fixed-length sample; a Loom one-shot doesn't have to be. Since several
procedural passes have a well-defined natural conclusion (Dissolution's collapse reaching
zero polygons, Evolution's generation count reaching its cap), a one-shot clip could equally
be defined as "play until this pass concludes" rather than "play for N frames" — closer to
triggering an envelope than triggering a fixed audio sample. Both should be supported; which
one a given clip uses is an authoring choice, not an either/or architectural decision.

**This significantly reframes Open Question 6** (clip looping vs. irreversible procedural
state, §9): a one-shot clip sidesteps that problem rather than needing to solve it —
Evolution and Dissolution are natural one-shot material, played through once (or chained via
Follow Actions) rather than forced to loop. Cycle clips remain best suited to naturally
loop-safe passes (Convolution's oscillator-driven Torsion/Shear/Bend, for instance). The
collaborator choosing the right identity for the right content, rather than the system
finding a clever way to loop everything, is probably the actual answer.

### 8.4 Tracks

A **track** is a persistent vertical channel — the thing that holds a sequence of clips
over time, in either view. The natural mapping onto Loom's existing model is one track per
drawing layer (§5.2): a track *is* a `LoomLayer`, with its own opacity, blend mode, and
position in render order, and the clips on it determine what's drawn into that layer at any
given moment. A project might have a "background" track, a "lead figure" track, and a
"texture/noise" track, each independently clip-driven — the same separation of concerns a
DAW gets from putting drums, bass, and pads on separate tracks.

### 8.5 Effects racks: transform sets and renderer drivers as procedural modifier chains

A DAW track carries an ordered effects chain — EQ, then compression, then reverb — each
stage independently toggleable and reorderable. Loom's transform sets are already
structured this way and need no redesign to fit the analogy: a transform set is an ordered
list of passes (Involution, Extension, Convolution, Evolution, Fulguration, Dissolution —
see `GeometricLifecycle.md`), each independently enabled and positioned. LoomLive should
expose a transform set as a literal rack: one row per pass, a bypass toggle, and
drag-to-reorder — the same interaction a musician already uses to reorder effects in
Ableton or Bitwig.

Renderer-level drivers (fill/stroke colour, point size, opacity, blur) form a second,
parallel modifier layer — closer to a DAW's per-track parameter automation than to an
insert effect, since they modulate continuously rather than process discretely, but worth
surfacing with the same rack-style presentation for consistency: each driver a labelled
slot, live-toggleable, with its parameters reachable via the real-time controls of
`MIDIPerformance.md` §4.2/§4.5.

---

## 9. Open Questions

1. **Context isolation vs shared state.** If two contexts share a polygon set, does
   modifying it in one context modify it in the other? The answer should probably be: shared
   elements are read-only references; contexts can make local overrides without affecting
   the shared version.

2. **Collaborative interface.** In a live duet, the musician and collaborator are in the
   same physical space. Does the musician ever see the visual score? Should the musician
   have any interface at all — cue lights, section indicators, a minimal score display?
   This requires physical and ergonomic design that goes beyond the software.

3. **Formal structure of the visual score.** A completely freeform structural map risks
   being too personal to communicate. Some formal structure — even minimal (section names,
   durations in bars rather than frames) — would make the visual score readable to others
   and reusable across performances of the same piece.

4. **Improvisation and pre-composition in proportion.** The most interesting work may lie
   at an intermediate point: a visual score that specifies broad sections and character but
   leaves the exact moments of transition and inflection to live judgement. How much should
   be determined in advance? This is a compositional question, not a technical one, but the
   interface design should support the full spectrum of approaches.

5. **Relationship to existing timeline.** The existing timeline is frame-precise and linear.
   The performance architecture is section-based and non-linear. Are these reconcilable in
   one system, or does performance mode require a genuinely separate representation? The
   question matters for export: a recorded performance should probably be exportable as a
   conventional timeline-based animation.
   **Addressed in `SessionWorkflow.md` §4.5**: not a reconciliation into one system, but a
   second, purpose-built representation — a DAW-style lanes-and-segments editor for
   recorded sessions and assemblies (MIDI lane, visual-action lane(s), audio lane, optional
   rendered-preview lane), built on an interaction model analogous to Loom's own
   `TimelinePanel` without being the same timeline. It exists specifically to make recorded
   material editable and exportable — including sync to external audio/video tools via the
   audio lane — which the section-based visual score itself was never meant to do.

6. **Clip looping vs. irreversible procedural state.** A DAW clip loops cleanly because
   MIDI/audio content is stateless between repeats — bar 5 sounds the same on loop 1 and
   loop 10. Several of Loom's own procedural passes are not loop-safe in the same way:
   Evolution's generational growth and Dissolution's decay accumulate state and are
   designed to look different each time they run, not to repeat identically. What does
   "looping a clip" (§8.2) mean when its transform set is built from Evolution or
   Dissolution? Candidate answers — reset the pass's state at the loop point (clean, but
   can produce a visible pop), let it continue accumulating across loop boundaries
   (musically loop-accurate in time but visually non-repeating), or restrict cleanly
   loopable clips to transform sets built from naturally loop-safe passes (Convolution's
   oscillator-driven Torsion/Shear/Bend already loops without incident, for instance) —
   need to be evaluated against how the visual collaborator actually wants to use clips,
   not decided in the abstract.
   **Substantially reframed by §8.3**: the cycle/one-shot playback toggle means this
   question mostly dissolves rather than needs solving — Evolution/Dissolution-based clips
   are natural one-shot material (play through once, or chain via Follow Actions), while
   only naturally loop-safe passes get set up as cycle clips. What remains open is narrower:
   retrigger behaviour for a one-shot mid-playthrough, and whether "reset at loop point" is
   ever worth supporting for a collaborator who deliberately wants a cycle clip built from a
   stateful pass despite the visible seam.
