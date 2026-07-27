# Global Music Sync — Authored (Non-Live) BPM Driver Sync

## 0. Relationship to other specs

`LoomLiveV1Scope.md` §2.6 built a manual-tap BPM/multiplier sync for the
**Live** tab — a rehearsal/performance surface where the reference clock is
real time and there's no fixed origin to sync against, hence the tap-a-
downbeat gesture. This spec applies the same underlying mechanism (musical
multiplier → `freqHz`, computed `phase`) to **ordinary, authored Loom
projects** — the Global tab, the sprite/renderer timeline, and every
driver's inspector — where the project already has an unambiguous origin
(frame 0 / `GlobalConfig.startFrame`), so no live tap is needed at all: the
beat grid is simply derived from BPM and drawn on the timeline like any
other ruler.

This is the technical implementation of `MusicVisualRelations.md` §1.1's
"synchronous (beat-level) coupling" — that doc covers *why* and *when* tight
sync is creatively useful (and its warning that constant sync exhausts
itself fast); this spec covers how the software offers it as an option, not
whether/when to reach for it.

## 1. Motivation

A user crafting a video destined to be cut to music wants some sprites'
oscillation to land on the beat without hand-tuning `freqHz`/`phase` by
converting BPM to Hz themselves and eyeballing alignment against a plain
frame-number ruler. This is a simple, mechanical need — no audio analysis,
no beat detection, nothing MIDI-related (that stays in the separate adjunct
app per `PerformanceArchitecture.md` §0.2 / `MIDIPerformance.md`).

## 2. `MusicSyncConfig` — project-wide, not per-scene

**Revised from the original draft of this section**, which proposed adding
these fields to `GlobalConfig`. Implementation surfaced a real conflict:
`GlobalConfig` is *per-scene* (`loom_swift/Sources/LoomEngine/Config/
ProjectConfig.swift` — every `LoomScene` carries its own copy), but
`subdivisionConfig`/`renderingConfig` — where transform-pass and renderer
`musicalMultiplier` drivers live — are **not** per-scene, they're shared
project-wide across every scene. A shared pass's musical driver can't
cleanly follow two different scenes' BPMs at once. Resolution: BPM is a
single project-wide clock, living in its own `MusicSyncConfig` on
`ProjectConfig`, sibling to `scenes` — not nested in `GlobalConfig`.

```swift
public struct MusicSyncConfig: Equatable, Codable, Sendable {
    public var enabled:           Bool   = false
    public var bpm:                Double = 120
    public var beatsPerBar:        Int    = 4
    public var barReferenceFrame:  Int    = 0   // "bar 1, beat 1" lands here
}
```

Same `decodeIfPresent`-with-defaults Codable pattern every config struct in
this codebase uses. Not read from XML — same precedent as `lightingConfig`/
`cycles`/`layers`, which `ProjectLoader.swift` never populates from the
legacy XML files either; purely default-constructed there, round-tripped
through `JSONConfigLoader` once saved.

`enabled` is an explicit toggle rather than an implicit "`bpm != 0` means
on" — a magic-zero convention would be one more thing to remember when
reading the field later. Toggling it on reveals the bar/beat ruler and the
per-driver manual/music switch described below; toggling off doesn't erase
`bpm`/`beatsPerBar`/`barReferenceFrame`, so re-enabling restores the same
grid, and it also forces every music-linked driver's controls out of view
(§8 — resolved: turning music mode off means "stop being driven by BPM,"
not "keep syncing invisibly").

`barReferenceFrame` defaults to 0, not to a tapped moment — see §4.

## 3. Timeline: bars and beats

`TimelinePanel.swift`'s ruler (`drawRuler`, ~line 1178) is hand-drawn via
`GraphicsContext`, computing tick positions directly from frame numbers via
`zoom`/`hOffset` — nothing about it assumes frame-only labeling. When
`musicModeEnabled`, a second tick row is drawn beneath the existing
frame-number ticks:

- Convert `frame → beat = (frame - barReferenceFrame) / fps × bpm / 60`,
  `bar = floor(beat / beatsPerBar) + 1`, `beatInBar = floor(beat) mod
  beatsPerBar + 1`.
- Major ticks at bar boundaries, minor ticks at beat boundaries — labeled
  `"bar.beat"` (e.g. `"5.1"`), same `tickIntervals()`-style major/minor
  selection the frame ruler already does, just computed from beats instead
  of a fixed frame stride.
- This is additive to the ruler, not a replacement — the frame-number row
  stays, since export settings, keyframe placement, and everything else
  still fundamentally operate in frames.

## 4. Where "beat 1" sits: default vs. override

`barReferenceFrame` defaults to `0` rather than requiring a Live-style tap
gesture, because an authored timeline already has an unambiguous origin.
This is also what a viewer scrubbing the timeline would *expect*: frame 0
reads as bar 1 beat 1 the moment Music Sync is switched on.

The escape hatch, both implemented in the Global tab's Music Sync section:
a numeric "Downbeat frame" field next to BPM/beats-per-bar, and a "Set at
playhead" button (reads `AppController.currentTimelineFrame`)
that captures the current scrub position — real source audio often has a
pickup beat or count-in before the beat grid the user actually wants to
align sprites to, so the default won't always be right. This mirrors Live's
`barReferenceFrame`/tap concept, just authored once rather than tapped
live, since there's no real-time performance happening here to tap against.

## 5. Per-driver manual/music toggle

`DoubleDriver`, `VectorDriver`, `ColorDriver`
(`loom_swift/Sources/LoomEngine/Animation/AnimationDriver.swift`) each
already expose plain `freqHz`/`phase` fields bound directly in their
inspectors (`AnimationDriverInspector.swift`) — edit-time struct fields, not
routed through any engine mutator. Each gains two new fields, Codable via
the same `decodeIfPresent` pattern already used for every field in these
structs:

```swift
public var musicalMultiplier:  Double? = nil   // nil = manual (unchanged today)
public var musicalPhaseOffset: Double  = 0     // see §6 — a dedicated field, not a reuse of `phase`
```

`musicalMultiplier` is the same shape as `LiveSessionController
.DriverControlInfo.musicalMultiplier` from the Live feature — same
vocabulary ("1 cycle per bar," "4 cycles per bar," "1 cycle per 4 bars"),
same conversion arithmetic (`musicalMultiplier × bpm / (60 × beatsPerBar)`
→ `freqHz`), same reuse of `LiveSessionController.musicalFreqHzAndPhase`/
`musicalRateAndPhase` — those two functions are pure arithmetic already,
with no Live-specific state baked in, so `MusicSync.swift` (Loom_Swift
_Integration) calls them as-is.

**Recompute** (`MusicSync.recomputeAll(in:)`): whenever `musicSync.bpm`,
`.beatsPerBar`, `.barReferenceFrame`, or a driver's own
`musicalMultiplier`/`musicalPhaseOffset` changes, every driver across the
project with a non-nil `musicalMultiplier` has its `freqHz`/`phase`/
`period` recomputed and overwritten — the same "recompute and push" shape
as Live's `recomputeAllMusicalDrivers`, but walking the full project's
driver set directly (`subdivisionConfig.paramsSets[]`'s eight pass arrays,
`renderingConfig.library.rendererSets[].renderers[]`, and every scene's
`spriteConfig` sprite-level `TransformDrivers` — each scene recomputed
against its *own* `targetFPS`, since that's still per-scene even though BPM
isn't) rather than only currently-staged Live instances.

**Per-driver mode UI**: a Manual/Music segmented control next to each
driver's rate fields (visible only when `musicSync.enabled`), in
`AnimationDriverInspector.swift`'s `.oscillator`/`.noise` mode branches for
all three driver editors. When set to Music, `freqHz` (or `period`, for
noise) becomes disabled/read-only and a multiplier picker
(`musicalMultiplierOptions`) replaces the raw value entry.

## 6. Phase: sync by default, offset for creative control

This is the one place where "lock everything to the beat" is the wrong
default, and needed a specific design rather than a blind port of the Live
behavior:

- **Rate is fully locked** when Music mode is on for a driver — there's no
  creative case for "approximately" matching tempo, so `freqHz`/`period` is
  always the computed value with no manual override while musical mode is
  active.
- **Phase syncs by default but stays tweakable as an offset, via a
  dedicated field — not by reusing `phase` itself.** `phase` is what
  `DriverEvaluator` actually reads, so recompute has to write the *summed*
  value (baseline + offset) into it; if the offset were stored by
  overwriting `phase` directly, the next recompute (BPM change, reference
  frame move) would have nothing to re-add it to without compounding drift.
  `musicalPhaseOffset` is the field the user actually edits and that
  persists; `phase` becomes a fully-derived, read-only display of
  `baseline + musicalPhaseOffset` (wrapped mod 1) while Music mode is
  active. `musicalPhaseOffset = 0` gives "exactly on the beat" — what a
  viewer expects at a glance — while `0.25` deliberately puts that sprite a
  quarter-cycle later (an off-beat pulse), and `0.5` gives a clean
  call-and-response pairing between two sprites. This directly answers the
  "sync to expectation vs. allow manual tweak" question: both, because
  they're not actually in tension once phase-offset is a field of its own
  rather than an overload of `phase`.

**Known constraint, carried over from the Live implementation**: noise-mode
drivers have no phase concept at all — `DriverEvaluator`'s noise case never
reads `phase`. Music mode for a noise-mode driver can only supply a locked
*rate* (a period, not a `freqHz`, per the existing `musicalRateAndPhase`
mode-awareness); the phase-offset control simply doesn't apply and should
be hidden rather than shown-and-ignored.

## 7. Build order (as implemented)

1. `MusicSyncConfig` (§2) + `ProjectConfig.musicSync` field.
2. `musicalMultiplier`/`musicalPhaseOffset` fields on `DoubleDriver`/
   `VectorDriver`/`ColorDriver` (§5).
3. `MusicSync.recomputeAll(in:)` (`Loom_Swift_Integration/Sources/Loom/
   MusicSync.swift`) — the config-tree walk + per-driver recompute,
   reusing `LiveSessionController.musicalRateAndPhase` unchanged.
4. Global tab Music Sync section (`GlobalInspector.swift`) — enabled
   toggle, BPM, beats/bar, downbeat frame + "Set at playhead," each write
   triggering `MusicSync.recomputeAll`.
5. Timeline bar/beat ruler row (`TimelinePanel.swift`'s `drawRuler`/
   `drawBeatRuler`) — additive sub-band below the existing frame ticks,
   only drawn when `musicSync.enabled`.
6. Per-driver Manual/Music UI (`AnimationDriverInspector.swift`) — shared
   `musicRateControls` helper + `.oscillator`/`.noise` case changes across
   all three driver editors.

## 8. Resolved questions

- **Does turning `musicSync.enabled` off freeze existing music-linked
  drivers, or keep them live?** Freeze. `MusicSync.recomputeAll` is only
  ever invoked from UI paths gated on `enabled`, and the per-driver
  Manual/Music controls are hidden entirely when it's off — a driver
  already locked to music keeps its last-computed `freqHz`/`phase`/
  `period` rather than resetting, but nothing recomputes it further until
  Music Sync is turned back on project-wide.
- **Does phase-offset need its own field?** Yes — resolved during
  implementation (§6): reusing `phase` directly doesn't work mechanically,
  since recompute needs to preserve the user's original offset across
  repeated BPM/reference-frame changes, and `phase` itself has already been
  overwritten with the summed result by the next time recompute runs.

## 9. Remaining open question

- Worth a project-wide "resync all" action (recompute every music-linked
  driver from current BPM/reference immediately) for when a user pastes in
  drivers from another project with a different BPM? Probably yes, but not
  blocking for this pass since `MusicSync.recomputeAll` already runs on
  every relevant edit and keeps things live.
