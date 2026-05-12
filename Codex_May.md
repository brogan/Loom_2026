# Codex May Handoff

## Current Focus

Recent work has focused on connecting Loom's newer keyframe/driver animation system to renderer behavior. The core idea is now in place:

- sprite drivers animate sprite-level state
- renderer drivers animate renderer-level appearance
- legacy renderer "Changes" remain available for palette/random/sequential behavior

Renderer drivers currently override static renderer values and legacy renderer changes when active.

## Implemented This Session

### Sprite Opacity Driver

- Added `opacity` to `TransformDrivers`.
- Added `opacity` to `SpriteTransform`.
- Evaluated opacity through `TransformAnimator`.
- Applied opacity as whole-sprite alpha during rendering.
- Exposed an `Opacity` sprite driver in the Sprites inspector.
- Added opacity as a sprite timeline lane.
- Added opacity editing to the keyframe inspector.

This enables sprite fade in/out, including combined fill, stroke, brush, stamp, and multi-renderer output.

### Renderer Stroke Width Driver

- Added `RendererDrivers`.
- Added `strokeWidth` as a `DoubleDriver`.
- Exposed `Stroke Width Driver` in the Rendering inspector.
- Evaluated stroke-width driver after static stroke width and after legacy stroke-width changes.

This enables interpolated/keyframed stroke width animation.

### Renderer Fill And Stroke Color Drivers

- Added `ColorKeyframe`.
- Added `ColorDriver` with `Constant` and `Keyframe` modes.
- Added RGBA color interpolation with easing.
- Added optional `fillColor` and `strokeColor` drivers to `RendererDrivers`.
- Exposed `Fill Color Driver` and `Stroke Color Driver` in the Rendering inspector.
- Evaluated color drivers after static values and after legacy fill/stroke color changes.

This enables keyframed fill and stroke color interpolation.

### Render Progress Field

- Added a small render progress/status field at the right of the main tab row.
- It provides coarse feedback while heavier renders are calculating.
- This is not yet true per-stamp/per-frame exact progress.

### Keyframe Creation Behavior

- Changed first keyframe creation in parameter tables so the first keyframe lands at the current timeline frame rather than automatically at frame 30.
- The first keyframe uses the current/base driver value.
- Subsequent keyframes still advance by 30 frames from the previous one.

## Important Design Notes

### Renderer Drivers Are Not Yet Timeline Lanes

Renderer driver keyframes are currently edited in the Rendering inspector only. They do not yet appear in the main timeline.

The underlying data is keyframe-capable, but the timeline is still sprite-focused. It only knows about sprite `TransformDrivers`.

### Driver Precedence

The current precedence is:

1. static renderer value
2. legacy renderer Changes
3. renderer driver

This means a fill/stroke/width driver becomes the final value when present.

### Color Drivers Are Deliberately Simple

Color drivers currently support:

- Constant
- Keyframe

They do not yet support jitter, noise, oscillator, or palette-library sampling. This is intentional for now because color interpolation is the important initial behavior.

## Suggested Next Steps

### 1. Add Renderer Driver Keyframes To Timeline

This is the most obvious next step.

Suggested approach:

- Keep existing sprite lanes under each sprite.
- Add renderer driver lanes under either:
  - the selected sprite's assigned renderer set, or
  - the currently selected renderer in the Rendering tab.
- Start with lanes for:
  - Fill Color
  - Stroke Color
  - Stroke Width
- Add a renderer-keyframe inspector, separate from the sprite keyframe inspector.

This will make renderer keyframes visually editable rather than hidden in the parameter panel.

### 2. Decide How Renderer Drivers Relate To Renderer Sets

Need to clarify whether renderer driver lanes should be shown:

- per renderer inside a renderer set
- per sprite using that renderer set
- only for the currently selected renderer

My recommendation: show them in the timeline in relation to the selected sprite, because users usually think in terms of animating a visible sprite. But the keyframes should still be stored on the renderer, not duplicated per sprite, unless we explicitly introduce per-sprite renderer overrides later.

### 3. Consider Renderer Opacity Driver

Sprite opacity now fades the whole sprite. A renderer opacity driver would be different:

- fade only a specific renderer layer in a multi-renderer set
- useful for crossfading fill/stroke/brush layers
- should probably be implemented as a renderer-level alpha multiplier

This would be especially useful when Playback is `All`.

### 4. Consider Color Driver Expansion

Possible later extensions:

- oscillator between two colors
- noise/jitter around a base color
- palette-driven interpolated color paths
- HSV/HSL interpolation option, not just RGBA interpolation

For now, RGBA keyframe interpolation is the practical baseline.

### 5. Improve Render Progress Accuracy

The current render progress field is coarse. A more accurate version would require deeper instrumentation:

- count total sprite/render passes
- count brush edges/stamps for brush rendering
- report progress from `BrushStampEngine`
- route progress up through `LoomEngine.makeFrame`

This is useful but probably lower priority than making renderer animation editing more visible.

### 6. Follow-Up Testing To Do

Manual checks recommended after compaction:

- sprite opacity fade with fill renderer
- sprite opacity fade with brush renderer
- stroke-width keyframe interpolation
- fill color keyframe interpolation
- stroke color keyframe interpolation
- combined renderer set with Playback `All`
- renderer drivers combined with legacy renderer Changes
- export video with renderer drivers active

## Build Status

Swift build passed after the latest renderer driver changes.

Known warnings remain from existing code:

- unused `basePointCounts` in `SpriteScene.swift`
- a few XML loader nil-coalescing warnings where `.text` is non-optional

These warnings were not introduced by the renderer driver feature work.
