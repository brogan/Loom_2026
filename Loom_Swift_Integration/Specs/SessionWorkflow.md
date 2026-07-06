# Session Workflow — Spec

**Status**: Conceptual / pre-implementation  
**Companion to**: `PerformanceArchitecture.md`, `MusicVisualRelations.md`, `MIDIPerformance.md`

---

## 1. The Dialogue Problem

The current framing of the performance system — MIDI drives visual parameters — is
fundamentally one-directional. The musician performs; the visual system responds. This is
not a dialogue: it is accompaniment with extra steps.

A genuine dialogue requires that both parties are *legible* to each other. The musician must
be able to read the visual collaborator's actions as intentional gestures — a context switch
is a statement, not a random parameter change — and the visual collaborator must be able to
make moves *toward* the musician, not only react to them. This bidirectionality is not a
nice-to-have feature; it is the condition under which the work can be genuinely co-authored.

### 1.1 What the musician needs to read

At minimum: which context is active, and when it changed. A simple "visual state" indicator
at the musician's position (a small display, or a set of lights, or text on a monitor not
in the projection path) shows the name of the current context and highlights when a switch
occurs. The musician sees "SPARSE — ANGULAR" become "DENSE — CURVED" and knows to respond
to that as a musical event.

More richly: the visual collaborator's actions as a timestamped event stream that the musician
can briefly scan. Not parameter values (meaningless without context) but named events:
"switched to bridge context", "drew new figure", "reduced sensitivity", "extending a line".
These are legible as compositional gestures.

The musician's interface is minimal — they are playing an instrument — and should require
no active attention. It is ambient information, not a control surface.

### 1.2 What the visual collaborator can signal

Beyond reacting to MIDI, the visual collaborator can make moves that constitute signals to
the musician. These are not automated messages; they are compositional acts that the musician
reads because they are watching the visual output and/or the state display.

Examples:
- A context switch to very sparse, still material is a signal that the music could open up,
  thin out, let silence in
- A sudden dense, complex context is a signal toward density and complexity in the music
- Reducing sensitivity (letting the visuals run freely, uncoupled from MIDI) is a signal
  that the music can depart from where it is, since the visuals are no longer dependent on it

None of these signals are automatic or protocol-defined. They work because both parties have
developed a shared vocabulary during preparation and rehearsal. The system supports this by
making the collaborator's actions visible to the musician, not by defining what those actions
mean.

---

## 2. The Development Workflow

Live performance is not the only, or even the primary, context for this work. A more common
workflow is iterative development: record a section, review, discuss, revise, record again.
This is how almost all collaborative creative work actually proceeds — in cycles of doing,
reflecting, and redoing.

The system must support this workflow at least as well as it supports pure live performance.

### 2.1 Session

A **session** is a bounded recording of collaborative activity — one take of a section, or
a full run-through of a piece, or an exploration of a particular context configuration.
A session has:

- A start time and end time
- A MIDI track: the complete time-indexed MIDI event stream for the duration
- A visual track: the complete time-indexed record of the visual collaborator's actions
  (context switches, parameter overrides, geometry additions, sensitivity changes)
- A rendered record: the animation state at each frame (or at keyframes with interpolation
  data — exact representation depends on storage constraints)
- Optional: audio track (if the musician's audio was recorded alongside MIDI)

Sessions are stored as named files within a LoomLive project. Multiple sessions can
represent multiple takes of the same material.

### 2.2 Review and replay

A recorded session can be replayed at any speed:
- Real-time: for review and discussion
- Slow: for detailed examination of specific moments
- Fast (headless): for export rendering

During replay, both parties can see exactly what happened — MIDI events, visual collaborator
actions, the resulting visual state — as a synchronized multi-track view. This makes
discussion concrete: "at 1:24 I switched to the dense context but the music was still in
the sparse section — the timing was wrong" is a specific, reviewable claim.

### 2.3 Stop, discuss, continue

The workflow supports pausing at any point, reviewing the current session up to that point,
discussing, and then either:
- **Continuing from the pause point**: the session resumes with the MIDI and visual state
  intact, as if no pause occurred
- **Restarting the current section**: the session rewinds to a marked section start, both
  parties can replay the previous attempt for reference, then perform the section again
- **Overdubbing a track**: the MIDI track is locked (the musician's contribution is fixed);
  the visual collaborator re-performs their part against the locked MIDI. Or vice versa.

This is the session-based development cycle:
1. Define the material (contexts prepared, MIDI instrument set up)
2. Record a take
3. Replay and discuss
4. Identify what to change (timing of a context switch, the character of a context,
   a section of MIDI that needs more space)
5. Record again — either the whole section or an overdub of one track
6. Repeat until the section is right
7. Move to the next section

### 2.4 Session markers

Both the musician and the visual collaborator can place markers during a session:
- **Planning markers**: placed before recording to indicate planned section boundaries
  and context switches (the visual score, pre-loaded)
- **Live markers**: placed during recording to flag moments ("this worked", "this didn't",
  "try something different here")
- **Review markers**: placed during replay to mark points for discussion

Markers are visible in the session timeline during review and are exportable as annotations.

---

## 3. Session Recording Format

A session is a time-indexed multi-track recording. The tracks are:

### 3.1 MIDI track

The complete MIDI event stream, timestamped to the session clock. Standard MIDI file (SMF
type 1) format for portability. Can be opened in any DAW for the musician to review or
re-record their part externally.

### 3.2 Visual action track

A JSON event log of all visual collaborator actions, timestamped to the session clock:

```json
[
  { "t": 0.000, "type": "sessionStart", "config": "morning_piece_v3" },
  { "t": 3.420, "type": "contextSwitch", "from": "sparse", "to": "opening",
    "mode": "crossfade", "durationFrames": 15 },
  { "t": 8.100, "type": "sensitivityChange", "value": 0.3 },
  { "t": 12.670, "type": "geometryAdded", "setName": "arc_01" },
  { "t": 19.200, "type": "macroAdjust", "macro": "density", "value": 0.72 },
  { "t": 24.000, "type": "contextSwitch", "from": "opening", "to": "development",
    "mode": "cut" },
  { "t": 24.033, "type": "marker", "label": "good moment", "flag": "positive" }
]
```

This log is human-readable and editable — a session can be refined by editing the visual
action track (adjusting the timing of a context switch by a few frames) without re-performing.

### 3.3 Rendered state track

The visual output at each frame, stored as:
- A keyframe of the full animation state at regular intervals (e.g., every 30 frames)
- A compact delta record between keyframes

This is the largest component and exists primarily to support fast review playback.
For export rendering, the rendered state is recomputed from the MIDI track and visual action
track rather than played back from this record — the record is a preview cache, not the
canonical source.

### 3.4 Session clock

All tracks are synchronised to a session clock that starts at zero when recording begins.
The MIDI track's timestamps are in session clock time, not MIDI ticks, allowing the two
tracks to be replayed in lockstep even if the MIDI tempo changes.

If an external MIDI clock is used (from a DAW or drum machine), the session clock is derived
from it. If not, the session clock is the system clock. The clock source is recorded in the
session header so replay uses the same reference.

---

## 4. Assembly

Multiple sessions can be assembled into a finished work. This is the post-performance
editing phase — analogous to editing a film from multiple takes, or assembling a recording
from overdubs.

### 4.1 The assembly timeline

An assembly is a timeline that references segments of recorded sessions:

```
Assembly: "morning_piece_final"
├── 0:00–0:32  session_take3, 0:00–0:32   (intro — best take)
├── 0:32–1:15  session_take7, 0:32–1:15   (A section — take 7 had the right timing)
├── 1:15–1:45  session_take7, 1:45–2:15   (bridge — from the same take but edited)
└── 1:45–3:20  session_take12, 0:00–1:35  (climax + resolution — final run-through)
```

Segments can be trimmed, slipped (shifted slightly in time to fix timing), and crossfaded.

### 4.2 Independent track assembly

Because MIDI and visual action are separate tracks, they can be assembled independently:

- Use the MIDI from take 3 but the visual action from take 7 for a section
- Use a single definitive visual action track with multiple MIDI overdubs layered
- Re-render the visuals from the MIDI track of take 3 with a revised context configuration

This is the central advantage of the multi-track model over a single-track "screen recording":
the two contributions remain separable until the final render.

### 4.3 Export rendering

When the assembly is complete, it is rendered to a final video file. This rendering:
- Uses the MIDI track and visual action track as inputs
- Recomputes the animation state at each frame from those inputs (not from the preview cache)
- Renders at full output resolution and frame rate
- Outputs a video file (or image sequence) for compositing or delivery

Because rendering is not real-time, it can be done at higher quality than live preview
allows: higher resolution, more subdivision iterations, more complex rendering configurations.
A context that was too expensive for real-time preview can be used in the final render at
full quality.

### 4.4 Refining after assembly

The assembly is not final until export. After assembling, both parties can:
- Review the assembled work and identify sections that need revision
- Record new overdubs of specific tracks for specific sections
- Adjust transition timing in the visual action track by direct editing
- Change the rendering configuration of a context without re-performing (the visual action
  track stays the same; the context's visual character changes)

---

## 5. Implications for Preparation

The session/assembly workflow changes how preparation works.

**Contexts need names that communicate.** In a review discussion, both parties refer to
contexts by name: "the dense context wasn't right for that moment." Names should be
descriptive of character, not technical ("sparse-angular" not "config_04"). The collaborator
names contexts during preparation.

**The visual score is a preparation document, not a prescription.** Because the session
records exactly what happened (not what was planned), departures from the visual score are
automatically preserved. After recording, the actual visual score can be derived from the
session log and compared with the planned score. Differences are starting points for
discussion.

**Multiple versions of a context.** During development, the collaborator may want to try
different versions of a context against the same MIDI take — "what does the A section
look like with the sparse context vs. the medium-density one?" This requires the ability to
re-render a session segment with a different context configuration without re-performing.
The visual action track records a context switch *by name*; if the context's definition
changes, the next render uses the updated definition.

---

## 6. Open Questions

1. **Session clock and tempo map.** If the music has a variable tempo (rubato, tempo
   changes), the relationship between clock time and musical time (bars and beats) is
   non-trivial. The session clock records wall time; analysis in terms of musical structure
   (this happened at bar 12, beat 3) requires a tempo map. How is this extracted? From
   MIDI clock events? From manually placed beat markers? This affects how the visual score
   is notated and reviewed.

2. **Overdub permissions.** If the visual collaborator is overdubbing their track against
   a locked MIDI take, should the MIDI track be visible to them during the overdub? In
   music, hearing the existing recording while overdubbing is standard. Here, seeing the
   MIDI-triggered visual responses while re-performing the manual actions may be confusing.
   A "blind overdub" mode (manual actions only, MIDI responses hidden until after) might
   be more useful for some sections.

3. **What constitutes a "take"?** In music, a take is defined by start and stop of the
   recording transport. Here, a take might be a single context from start to finish, or
   a section, or a full run-through. The system needs a clear model of what constitutes
   a discrete take — both for naming/organisation and for assembly.

4. **Remote collaboration.** The current model assumes both parties are co-present.
   Remote collaboration (musician in one location, visual collaborator in another, connected
   via network) introduces latency between the two contributions. This is architecturally
   significant — session clock synchronization across a network connection requires careful
   treatment. Defer to a later phase, but don't architect in ways that preclude it.

5. **The musician's tool.** This spec assumes the musician uses their existing instrument
   and DAW, connected to LoomLive via MIDI (hardware or IAC). Should LoomLive include any
   musician-facing interface at all — cue lights, session transport controls, context state
   display — or is this always external? A minimal musician display (context name + beat
   indicator) embedded in LoomLive would make co-present work more fluent without requiring
   the musician to own a separate display application.
