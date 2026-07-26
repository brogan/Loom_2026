# LoomLive V1 Scope

**Status**: Active — defines what gets built first
**Companion to**: `MIDIPerformance.md`, `PerformanceArchitecture.md`, `SessionWorkflow.md` — those
three describe the long-term vision for LoomLive; this document narrows that vision to a first
buildable slice, in direct response to the scope concerns raised in a review pass of the three
(see §4 below).

**Where V1 lives**: as an additional tab inside Loom itself, positioned after the Rendering
tab — not a separate app. See `PerformanceArchitecture.md` §0 for the reasoning: the original
case for a separate app rested on a technical claim (live engine mutation being a big,
unproven capability) that turned out to be overstated; what's left is a UX consideration
worth being deliberate about, not a hard requirement to build somewhere else. This is a
decision for V1, not necessarily for the whole long-term vision — see §3.

---

## 1. The core hypothesis

Everything else in the three companion specs — Clips, Tracks, Session View, the Library, the
Visual Score, MIDI mapping, live geometry drawing — is built on one architectural bet: that
`LoomEngine` can be driven live, with a running engine mutated in place rather than saved and
reloaded, closely enough to feel like an instrument rather than a form. `PerformanceArchitecture.md`
§0.1 confirms the *mechanism* for this already exists and is small — `Engine.updateLightingConfig`-
style methods, extended to cover renderer-set/transform-set/driver mutation — but existing and
small isn't the same as validated: nobody has yet built the full rehearsal surface on top of it
and used it for a real session.

V1 exists to test that in practice, before committing to anything built on top of it. The
crucial, load-bearing capability is: **live switching between sprites, transform sets, and
renderer sets, with no save-to-disk and no engine reload in the loop.** If this works well — feels
responsive, doesn't glitch, holds up over a real rehearsal session — everything else in the
companion specs becomes a question of which feature to build next on solid ground. If it doesn't,
that's exactly the thing to find out first, cheaply, rather than after a Library system and a DAW
clip model have been built on top of an assumption that turned out not to hold.

## 2. In scope for V1

### 2.1 The live rehearsal surface

A stripped-down version of `MIDIPerformance.md` §4.5, with the MIDI half of that document
entirely out of scope (see §3 below):

- Select a sprite from the project's existing sprite sets; it stages at canvas centre with basic
  position/scale/rotation controls.
- Assign any of the project's transform (subdivision) sets or renderer sets to that sprite, live —
  swap one for another mid-play, with no perceptible reload.
- Toggle a sprite's drivers on and off live.
- Show or hide a staged sprite at any time; stage several simultaneously.

No MIDI input, no MIDI mapping editor, no hardware controllers. Control is direct GUI
manipulation only. The architecture shouldn't preclude MIDI later, but nothing about V1 depends
on it existing.

The tab holds its own `Engine` instance, constructed once from the project already open in
Loom — independent of `AppController`'s own engine, so an ordinary inspector edit made in
another tab (which still goes through the normal save→reload cycle) can't silently discard
the tab's live mutations by replacing the engine out from under it (`PerformanceArchitecture.md`
§0.1). The tab needs a clear, hard-to-miss visual indicator that it's in its own live mode,
since a renderer swap made here won't show up back in the Rendering tab — expected behaviour,
not a bug, but worth making legible.

### 2.2 Capture

Every action on the rehearsal surface — a sprite shown or hidden, a renderer set swapped, a
transform set assigned, a driver toggled — is logged as a timestamped event, using a narrow
subset of the visual-action schema already specified in `SessionWorkflow.md` §3.2
(`spriteShow`/`spriteHide`, `rendererSetAssign`, `transformSetAssign`, driver-toggle events). No
MIDI track, no audio track, no rendered-state preview cache, no clips, no assembly of multiple
sessions — just the one event log for one continuous rehearsal.

### 2.3 Timing edit

The captured log can be edited after the fact — at minimum, adjusting an event's timestamp
directly in a simple, ordered list (matching `SessionWorkflow.md` §3.2's description of the log
as "human-readable and editable"). The full DAW-style multi-lane editor (`SessionWorkflow.md`
§4.5, with its MIDI/visual-action/audio/rendered-preview lanes) is explicitly not required for
V1 — a single ordered list of events with editable timestamps is enough to satisfy "subsequently
edited in terms of timing." A lane view can come later if a flat list turns out to be
insufficient in practice.

### 2.4 Render

The edited event log is recomputed and rendered to video, reusing Loom's existing
`VideoExporter`/`AVAssetWriter` pipeline (already confirmed engine-agnostic and requiring no
changes) — matching the deterministic "recompute from the log, don't play back a cache"
principle already established in `SessionWorkflow.md` §3.3/§4.3, just without any of the MIDI or
audio inputs that principle was originally specified alongside.

That may be the entire first version of the Live tab: stage sprites, switch what's
driving/rendering them live, capture what happened, tweak the timing, render it out.

### 2.5 No distinct project format

`SessionWorkflow.md` §2.1 describes sessions as "stored as named files within a LoomLive
project" — implying LoomLive needs its own project container, separate from a Loom project. V1
needs none of that, and now needs even less of it than a separate app would have: since the Live
tab lives inside Loom itself (§0 above), there's no import step at all — it's not "a Loom project
becomes importable into LoomLive," it's literally the same project already open in the same app.
The tab works against whatever sprite/transform/renderer sets are already defined there, and adds
exactly one new thing to the project directory: a folder for captured event logs (e.g.
`sessions/`, alongside the project's existing `brushes/`, `palettes/`, `renders/`-style
subdirectories), each log a single flat JSON file. No new container format, no relationship to
define between a "LoomLive project" and a "Loom project" — there's only one project.

## 3. Explicitly deferred

Everything else in the three companion specs is out of scope for V1 — not rejected, deferred
until the core hypothesis in §1 has actually been tested:

- **All of MIDI** (`MIDIPerformance.md` in full) — signal routing, `MIDIDriver`, hardware
  controller mapping, grid clip-launch controllers, musical analysis. Its Phase 1–4 plan (§5) is
  superseded for now, since it assumes MIDI work starts immediately; it doesn't, until V1's
  live-switching core is proven.
- **The DAW Model** (`PerformanceArchitecture.md` §8 in full) — Clips, Tracks-as-channels,
  Session View, Arrangement View, Cycle/One-shot playback, Follow Actions, effects-rack framing.
  None of this is needed to test the core hypothesis, and building it first would mean building a
  lot of structure on top of an unvalidated foundation.
- **The Context and Library systems** (§2, §3) — named prepared states, cross-project tagging and
  sharing. V1's rehearsal surface works directly against one project's existing sprite/transform/
  renderer sets; there's no need yet for a system to name and recall whole prepared
  configurations.
- **The Visual Score** (§4) — a pre-performance structural planning document. Nothing to plan
  against yet until there's a working instrument to plan a performance for.
- **Live geometry drawing** (§5.1, §5.2) — freehand drawing, UM-style grid drawing, drawing
  layers. V1 works with sprites and sets that already exist in the loaded project; creating new
  geometry live is a separate, later capability.
- **The audio track and lane-based multi-track editor** (`SessionWorkflow.md` §3.5, §4.5) — no
  audio sync, no MIDI lane, no waveform view. Just the one visual-action log, edited as a flat
  list (§2.3 above).
- **Review/replay/overdub/session markers and multi-session assembly**
  (`SessionWorkflow.md` §2.2–§2.4, §4) — V1 is one continuous rehearsal captured, edited, and
  rendered; not multiple takes stitched together.
- **A distinct LoomLive project container** (`SessionWorkflow.md` §2.1's framing of sessions
  living "within a LoomLive project") — V1 has no such container; see §2.5.
- **Standing up LoomLive as a separate application** (`PerformanceArchitecture.md` §0.2) —
  deferred, not rejected. Revisit if the fuller vision (MIDI hardware, the DAW model, a
  full-screen gig-ready mode) later makes a tab feel structurally cramped; nothing about
  building V1 as a tab forecloses that option.

## 4. What this resolves from the review pass

A review of the three companion specs flagged, among other things, that no MVP line had been
drawn anywhere across them, and that the term "Track" was already colliding between two senses —
a session-recording data stream and a DAW mixing channel. Scoping V1 this narrowly resolves both
directly: there's now an explicit MVP line (this document), and because the DAW Model (§8, where
"Track" means a `LoomLayer`-backed channel) is deferred wholesale, only the session-recording
sense of "track" is even potentially live for V1 — and even that word isn't strictly needed yet,
since V1 has exactly one log, not several parallel ones that need naming and distinguishing.
Worth resolving the collision properly before the DAW Model phase is ever scheduled, but it isn't
blocking anything right now.

It also closes one of the review's "Gaps" findings directly: no container model existed for what
a "LoomLive project" actually is, relative to an imported Loom project and the cross-project
Library. V1 sidesteps the question rather than answering it in the abstract — there is no
separate container, only an existing Loom project plus one new folder of event logs (§2.5). The
real version of that question — how a Library spanning multiple Loom projects relates to a
LoomLive project container — stays open, but only becomes relevant once the Library itself is in
scope.

## 5. What "works well" means

Before expanding past V1, the honest questions to ask are:

- Does switching a sprite's renderer or transform set live actually feel instantaneous, or is
  there a perceptible hitch even with the new fast-mutation path?
- Does a real rehearsal session — staging several sprites, swapping sets repeatedly, toggling
  drivers — hold up over minutes of continuous use, or does state drift/leak in ways a
  reload-based architecture never had to worry about?
- Is the captured event log actually sufficient to reproduce what happened, and is editing its
  timing genuinely useful, or does it turn out you need finer-grained control (parameter
  automation within an event, not just its timestamp) sooner than expected?
- Does rendering the edited log produce output good enough to use, at the quality Loom's existing
  export already provides?

If the answers are good, the companion specs' further ambitions (§3's deferred list) become a
backlog to prioritise from a position of strength. If they're not, that's exactly the signal to
address before building anything else.
