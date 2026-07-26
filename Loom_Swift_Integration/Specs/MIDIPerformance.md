# Loom MIDI Performance — Rough Spec

**Status**: Concept / pre-implementation  
**Motivation**: Loom's geometrical-procedural system (subdivision, PTW, rendering) has an
inherently abstract, structural character that maps well onto musical concepts — rhythm,
harmonic density, register, tension and release. MIDI provides a clean, low-latency, already-
parsed signal that is easier to work with than audio analysis (no onset detection uncertainty,
no waveform computation). The goal is to let musical input — both pre-recorded and live —
drive Loom's procedural parameters, and ultimately to support a live "duet" format in which
a musician and a procedural animator co-perform a finished music-animation piece.

---

## 1. Signal Model

### 1.1 MIDI message types as signal sources

| MIDI message          | Signal type       | Natural Loom use |
|-----------------------|-------------------|------------------|
| Note On velocity      | 0–127 impulse     | Beat trigger, intensity spike |
| Note Off              | gate close        | Animation hold, decay |
| Pitch (note number)   | 0–127 stepped     | Pitch-class mapping, register |
| CC (0–127)            | continuous 0–127  | Any DoubleDriver target |
| Pitch bend            | −8192–+8191       | Fine continuous control |
| MIDI Clock (24 ppq)   | tempo pulse       | BPM-locked oscillator sync |
| Program Change        | 0–127 event       | Subdivision set / palette switch |
| Aftertouch            | continuous 0–127  | Expression, pressure |

### 1.2 Derived musical analysis

Beyond raw MIDI messages, a lightweight analysis layer can derive higher-level signals:

| Derived signal        | Computation                             | Loom use |
|-----------------------|-----------------------------------------|----------|
| BPM                   | MIDI clock (exact) or note-onset delta  | Oscillator phase sync |
| Beat phase            | 0–1 sawtooth locked to detected BPM    | Oscillator base frequency |
| Current chord         | Set of active note pitches              | Harmony richness, consonance |
| Bass/root note        | Lowest active note                      | Global scale or palette index |
| Harmonic richness     | Count of simultaneous note classes      | Subdivision depth, inset scale |
| Velocity envelope     | Smoothed note-velocity stream           | Global intensity driver |
| Register              | Mean octave of active notes (0–8)       | Size, zoom, inset ratio |

Harmonic analysis should be conservative — detect chord density (monophonic / dyad / chord)
rather than full Roman numeral analysis, which is fragile in real-time contexts.

---

## 2. Architecture

### 2.1 MIDIController

Analogous to `AudioController`. Lives on the main actor. Responsible for:

- Enumerating CoreMIDI sources (hardware, virtual, IAC bus)
- Receiving MIDI messages via a CoreMIDI callback (on a background MIDI thread) and
  queueing them into a main-thread-safe ring buffer
- Loading and playing back SMF (Standard MIDI Files, `.mid`) pre-recorded sequences
- Maintaining a live state snapshot updated every render frame:
  - `noteVelocities: [Int: Int]`   — keyed by note number, current velocity (0 = off)
  - `ccValues: [Int: Double]`      — keyed by CC number, normalised 0–1
  - `pitchBend: Double`            — normalised −1…+1
  - `currentBPM: Double`
  - `beatPhase: Double`            — 0–1 within current beat
  - `analysis: MIDIAnalysis`       — derived signals

### 2.2 MIDIDriver (new DoubleDriver mode)

Add a `.midi` mode to `DoubleDriver` with sub-fields:

```swift
// within DoubleDriver
case midi

// new fields active when mode == .midi:
var midiChannel:   Int           // 0 = any
var midiSource:    MIDISource    // note, cc, pitchBend, beatPhase, richness, register, velocityEnvelope
var midiNumber:    Int           // note number or CC number (where applicable)
var inputMin:      Double        // MIDI input range lo (default 0)
var inputMax:      Double        // MIDI input range hi (default 127)
var outputMin:     Double        // mapped output range lo
var outputMax:     Double        // mapped output range hi
var smoothing:     Double        // 0 = none, >0 = one-pole LP for smoothing CC input
```

`DriverEvaluator.evaluate` queries `MIDIController.shared.currentState` to resolve the value
at evaluation time. The mapping is a simple linear remap from `[inputMin, inputMax]` to
`[outputMin, outputMax]`, with optional smoothing via a per-driver running average.

### 2.3 Pre-recorded MIDI playback

A pre-recorded `.mid` file is loaded by `MIDIController`. During playback the controller
replays events against the project's elapsed-frame clock (using the same BPM-to-frame
mapping as the animation). This makes MIDI-driven and keyframe-driven parameters composable:
the animator can bake a MIDI sequence into a project file and the performance is reproducible.

### 2.4 Live MIDI input

CoreMIDI delivers MIDI messages on a background thread. The controller marshals them to the
main thread via a lock-free ring buffer (or `DispatchQueue.main.async` for simplicity in a
first implementation). The render loop reads the live state snapshot once per frame, so
all MIDI-driven drivers see a consistent state within one frame.

Latency target: MIDI → visual response ≤ 2 frames at 30fps (~67ms). CoreMIDI latency is
typically < 5ms; the bottleneck is frame-rate.

---

## 3. Musical-to-Geometric Mapping Ideas

These are not prescriptive — they illustrate the design space.

### Rhythm → subdivision structure

- **Beat onset → ranMiddle spike**: Each detected beat briefly increases ranDiv jitter
  (reduces divisor for 2–3 frames), creating a percussive "flick" in the midpoint.
- **BPM → oscillator sync**: Oscillator freq driver set to `bpm / 60` Hz, so subdivision
  waves pulse exactly in time with the music.
- **Beat phase → PTW rotation**: Polygon rotation driven by the 0–1 beat-phase sawtooth,
  producing one rotation cycle per beat.

### Harmony → geometry

- **Chord richness → subdivision depth**: Monophonic = 1 generation; dyad = 2;
  full chord = 3+. Achieved via a name driver selecting subdivision parameter sets
  ("gen1", "gen2", "gen3") keyed to the richness signal.
- **Register (octave) → inset scale**: Higher register = smaller inset polygons (more
  delicate geometry); lower register = larger, heavier forms.
- **Bass note → palette index**: Root note maps to a palette or colour temperature — low
  bass notes = warm/dark, high notes = cool/bright.
- **Consonance vs dissonance**: A simple interval-quality score (sum of interval semitones
  weighted by roughness curves from psychoacoustics) drives curvature or cpNormalOffset.

### Velocity → intensity

- **Note velocity → global lineRatio driver**: Hard attacks push line ratios toward 0.5
  (equal split), soft playing allows unequal ratios. Creates visual "punching" on accents.
- **Velocity envelope → inset rotation**: Smoothed velocity drives rotation rate —
  louder playing = faster rotation.
- **Sustain/release → visibility rule**: A sustain pedal (CC 64) toggles between
  `visibilityRule = .all` and `visibilityRule = .random1in2`.

---

## 4. Performance Mode UI

A dedicated full-screen-friendly "performance" tab (or window) separate from the main
inspector workflow.

### 4.1 Musician's MIDI status panel (read-only, display only)

- Live MIDI input indicator (source name, active notes, BPM)
- Active CC strip: horizontal bars showing current values for mapped CCs
- Beat-phase pulse indicator
- Chord display (active note classes)

### 4.2 Animator's real-time controls

A set of 6–12 assignable macro sliders / buttons that the animator manipulates during
performance. Each macro is a named parameter binding (e.g. "Chaos", "Density", "Scale")
mapped to one or more Loom parameters via a simple multiplier curve. The animator
can:

- Morph between saved subdivision parameter sets ("base state" / "bridge state" / "peak state")
- Trigger one-shot events (visibility shuffle, palette swap)
- Adjust global scale, rotation, or camera zoom in real-time
- Toggle specific subdivision generations on/off

MIDI mapping (§4.3) is one way to drive these — every macro and every rehearsal-surface
slider (§4.5) is playable directly by mouse/trackpad/tablet with no MIDI device attached
at all, since not every session has a MIDI controller within reach and direct manipulation
is often the more precise input for a fine adjustment. The control surface should offer a
richer vocabulary than plain sliders where the parameter calls for it:

- **Sliders** for a single bounded continuous value (frequency, amplitude, opacity)
- **XY pads** for two correlated parameters at once (e.g. scale × rotation, or two macro
  targets that are usually adjusted together) — a single drag gesture instead of two
  simultaneous slider drags
- **Toggle grids** for on/off state across many items at once (which subdivision
  generations are active, which sprites are shown) — see the rehearsal surface's sprite
  show/hide (§4.5)
- **Radial knobs** where a physical-control metaphor reads more intuitively than a linear
  slider (e.g. a "sensitivity" dial, hue rotation)

Whichever widget is used, the underlying event is the same shape — a named
parameter/value pair, timestamped — so the choice of control widget is a UI decision only
and does not change what gets captured to the session log (`SessionWorkflow.md` §3.2).

### 4.3 Mapping editor

A simple two-column list: left column = MIDI source (CC #74, note E3 velocity, etc.),
right column = Loom target (parameter path). A "learn" mode captures the next incoming
MIDI message as the source for a selected mapping. Mappings are saved with the project.

This should work identically whether the MIDI source is a software instrument, a DAW's
MIDI output over IAC, or a physical hardware controller — fader banks, knob banks, and
generic MIDI control surfaces used by musicians and DJs (Behringer X-Touch, Novation
Launch Control, and similar class-compliant devices) all just look like a stream of CC
messages, and "learn" mode maps them exactly like any other source. No vendor-specific
integration is required for this baseline case — only for the deeper, model-aware
control-surface protocols some hardware supports (Ableton's Control Surface scripts, for
example), which is a larger undertaking deferred to a later phase (§6, Open Question 7).

### 4.4 Score display (optional, future)

If a pre-recorded MIDI file is loaded, display a scrolling piano roll in the performance
tab, with the playhead tracking the current frame. This gives the animator visual
anticipation of upcoming musical events.

### 4.5 Sprite/driver/renderer rehearsal surface

A more granular layer beneath the macro controls in 4.2: a working surface where the
collaborator selects sprites from the project's sprite sets and stages them directly,
independent of which context (`PerformanceArchitecture.md` §2) is currently active.

- **Left panel**: the project's sprite sets and sprites, mirroring Loom's own Sprites-tab
  list. Selecting a sprite stages it at canvas centre with basic position/scale/rotation
  controls — enough to place it usefully without needing the full inspector.
- **Right panel**: three sub-panels — sprite drivers, transform (subdivision) sets, and
  renderer sets defined in the project (see the Library System, `PerformanceArchitecture.md`
  §3). Any of these can be applied to a staged sprite at any time, live: a renderer set can
  be swapped for another mid-performance (a hard cut in the visual character of that one
  sprite, distinct from a whole-context switch), a different transform set can be attached,
  a driver can be toggled on or off.
- **Staged sprites** can be shown or hidden at any time, and several can be staged and
  manipulated simultaneously — this is the mechanism for building up a visual moment sprite
  by sprite, live, rather than only recalling a pre-built context wholesale.
- **Live parameter sliders**: for any active driver with continuous parameters (oscillator
  frequency, amplitude, jitter range, seed), an on-screen slider drives the value directly
  as the animation plays, so the collaborator can hear/see the effect of a change land in
  real time rather than editing a field and re-checking the result afterward. These sliders
  live in a floating panel (or docked at the lower-left of the sprite list) so they stay
  reachable without covering the main render surface.

This surface is a finer-grained sibling to context switching (§2.2 of
`PerformanceArchitecture.md`): a context switch recalls a whole prepared state; the
rehearsal surface lets the collaborator inflect *within* a context, or build a new one
interactively before naming and saving it as a context (see `PerformanceArchitecture.md`
§2.5). Every action here — a sprite shown, a renderer swapped, a slider moved — is a visual
action event (`SessionWorkflow.md` §3.2) and is what gets captured for later editing and
export.

**Architectural note**: unlike Loom's own editing model, where any parameter change is
saved to disk and the engine is rebuilt from scratch (~0.35s debounce, restarts at frame 0),
the sliders above require a fast, in-place mutation path into a *running* engine so a drag
reads as live control rather than a reload. This is real engineering work specific to
LoomLive's runtime, not just new UI — see `PerformanceArchitecture.md` §0.1.

### 4.6 Clip-launch grid controllers

Grid-style MIDI controllers built for clip launching — Ableton Push, Novation Launchpad,
Akai APC, and similar — map naturally onto the Session View grid described in
`PerformanceArchitecture.md` §8.2: physical pad rows/columns correspond to track/scene
positions, a pad press launches the clip at that position, and pad LED colour/brightness
reflects clip state (empty, stopped, queued to launch, currently playing) exactly as it
would in the DAW these devices were built for. Supporting the common grid-controller
message convention (note-on/off per pad, LED colour set via note velocity or a
vendor-specific SysEx palette) covers the popular hardware without a bespoke integration
per device; richer per-device feedback (exact LED colour palettes, pad aftertouch) can be
added per controller as needed, but isn't required for basic clip launching to work.

---

## 5. Implementation Phases

### Phase 1 — Pre-recorded MIDI + CC mapping (foundation)

- `MIDIController` with SMF loading and playback
- `MIDIDriver` mode on `DoubleDriver` (CC only, initially)
- Inspector UI: "MIDI" option in driver mode picker; MIDI mapping panel
- No live input, no harmony analysis

### Phase 2 — Live MIDI input

- CoreMIDI source enumeration and live message receipt
- Ring-buffer main-thread bridge
- Beat-phase and BPM detection from MIDI Clock and/or note onsets
- Live status display in audio/MIDI tab

### Phase 3 — Musical analysis

- Harmonic richness and register derived signals
- Note-velocity envelope smoothing
- Sustain pedal and other special CCs
- Name driver integration (MIDI Program Change → subdivision set switch)

### Phase 4 — Performance Mode UI

- Dedicated performance tab / window
- Animator macro controls
- MIDI learn mode
- Score / piano-roll display (with pre-recorded sequences)

---

## 6. Open Questions

1. **MIDI source abstraction**: Should `MIDIDriver` reference a source by name (device name)
   or by slot index? Named references survive device reconnects but can silently fail if the
   device name changes. A "default input" fallback is needed.

2. **Harmony analysis granularity**: Detecting chord quality (major/minor/diminished) is
   useful but fragile in polyphonic/live contexts. Start with richness (note count) and
   register only; defer quality to a later phase.

3. **Latency compensation**: Pre-recorded MIDI can be offset by a negative delay to
   compensate for render latency. Live MIDI cannot. A global "MIDI latency offset" field
   (in frames) on `MIDIController` lets the user trim the live response.

4. **Relationship to audio analysis**: Both systems can coexist. Audio analysis gives BPM
   and beat detection from a final mix; MIDI gives per-instrument articulation. A future
   integration could allow MIDI to "correct" audio-derived BPM during live performance.
   Separately, `SessionWorkflow.md` §3.5 lets a reference audio recording be attached to a
   session purely as a sync/reference signal (a waveform to align to in the lane-based
   editor, §4.5) — that use doesn't require any analysis at all, and is independent of
   whether audio-derived driving signals are ever implemented.

5. **IAC (Inter-Application Communication) bus**: macOS's IAC driver lets any app on the
   machine send MIDI to Loom. This enables DAW-synced playback (Ableton → Loom via IAC)
   without requiring hardware MIDI — important for studio use.

6. **Real-time parameter recording**: Should the animator's macro-slider movements during
   a live session be record-able as keyframe data? This would let a live performance be
   "captured" and reproduced exactly — essentially a motion-capture of the visual performance.
   **Resolved in `SessionWorkflow.md` §3**: yes — captured as a visual action event log, not
   baked keyframe/frame data, and recomputed deterministically at export time. See
   `SessionWorkflow.md` §3.2 for the event schema (now extended in that section to cover the
   rehearsal surface's sprite/driver/renderer/slider events from §4.5 above) and §4.3 for
   export rendering from the log.

7. **Deep control-surface protocol support.** Generic CC/note learn (§4.3) covers any
   class-compliant hardware, and the grid-controller convention (§4.6) covers clip
   launching on popular pad controllers. Going further — bidirectional, model-aware
   integration like Ableton's Control Surface scripts, where the software drives the
   hardware's own display/LEDs to always mirror its exact current state rather than just
   reacting to input — is a much larger, per-device undertaking. Worth deferring until
   generic support is validated in real use; not worth committing to for any specific
   device now.
