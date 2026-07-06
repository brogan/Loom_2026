# Loom Performance Architecture — Visual Composition Spec

**Status**: Concept / pre-implementation  
**Companion to**: `MIDIPerformance.md`, `OpenCurves.md`

---

## 0. Application Separation

The live performance system described in this spec and `MIDIPerformance.md` should **not**
be built inside Loom. Loom is a composition studio — its design centre is deliberate,
frame-precise, project-oriented work. A live performance instrument has a different centre:
immediacy, minimal interface, non-linear time, real-time responsiveness. Forcing both into
one application would compromise both.

**The right model: `LoomEngine` as shared library**

`LoomEngine` is already a separate Swift package. Both applications build on it:

```
LoomEngine (Swift package)
    ↓                    ↓
Loom (studio)       LoomLive (performance instrument)
```

`Loom` is where vocabulary is built: geometry is drawn and refined, subdivision parameter
sets are designed, palettes and renderers are crafted, contexts are prepared and tagged.

`LoomLive` is where vocabulary is performed: contexts are switched, MIDI drives the
procedural parameters, the visual score is followed or departed from, the session is recorded.

**Exchange format**: a Loom project directory becomes importable into LoomLive as a library
of prepared contexts. The `.loom_projects` format is the contract between the two applications.
No features need to be shared in the UI; only the data model and engine need to be consistent.

**What this implies for Loom itself**: Loom benefits from this separation — it does not need
to become a performance instrument. The features it should develop for this ecosystem are:
1. Context authoring (see Section 2 of this spec)
2. Library tagging and export
3. Open curve procedural tools (see `OpenCurves.md`) — relevant to both studio and live use

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
internally), and switching between contexts switches which of those loops is playing.

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

## 8. Open Questions

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
