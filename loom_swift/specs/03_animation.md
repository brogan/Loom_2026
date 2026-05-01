# Loom Engine — Animation System
**Specification 03**
**Date:** 2026-04-27
**Depends on:** `01_technical_overview.md`

---

## 1. Purpose

This document specifies the animation system — the mechanism by which sprites move, scale, rotate, morph, and change renderer parameters between frames. It covers:

- The `SpriteAnimation` configuration struct
- `TransformAnimator` — pure-function transform computation
- `SpriteTransform` — the value produced by animation
- `MorphInterpolator` — polygon blending toward morph targets
- `RenderStateEngine` and `RendererAnimationState` — renderer parameter animation
- `EasingMath` — easing curve implementations
- How `SpriteScene.advance` orchestrates all of the above

---

## 2. Conceptual Overview

The Swift animation model uses a **separate transform from geometry** approach. A `SpriteInstance` holds:

- `basePolygons: [Polygon2D]` — canonical geometry, never mutated
- `state.transform: SpriteTransform` — current position/scale/rotation/morphAmount, updated each frame
- `state.rendererAnimationStates: [RendererAnimationState]` — per-renderer palette cursor state

At render time, `SpriteScene` applies `state.transform` to `basePolygons` to produce screen-space vertices. The canonical geometry is never touched.

This contrasts with the Scala engine, where animation directly and cumulatively modified polygon vertex coordinates in-place — making snapshot/restore impossible and requiring explicit "undo" passes for oscillation mode.

---

## 3. SpriteAnimation (Configuration)

`SpriteAnimation` is a `Codable` struct loaded from `sprites.xml`. It is the static configuration that governs how a sprite animates. The runtime state is in `SpriteState`, separate from this config.

```swift
public struct SpriteAnimation: Codable, Sendable {
    public var enabled: Bool
    public var type: AnimationType           // .keyframe | .random | .keyframeMorph | .jitterMorph
    public var totalDraws: Int               // 0 = animate indefinitely
    public var loopMode: LoopMode            // .loop | .once | .pingPong

    // Continuous / random animation
    public var scale: Vector2D
    public var rotation: Double
    public var speed: Vector2D
    public var jitter: Bool                  // true = oscillate; false = cumulate
    public var randomScale: RangeXY?
    public var randomRotation: FloatRange?
    public var randomSpeed: RangeXY?

    // Keyframe animation
    public var keyframes: [Keyframe]

    // Morph animation
    public var morphTargets: [MorphTargetRef]  // files relative to project morphTargets/
    public var morphAmount: Double
    public var morphRange: FloatRange?
}

public enum AnimationType: String, Codable, Sendable {
    case keyframe, random, keyframeMorph, jitterMorph
}

public enum LoopMode: String, Codable, Sendable {
    case loop, once, pingPong
}
```

---

## 4. SpriteTransform

`SpriteTransform` is the per-frame animation output — a value-type record of the current sprite state. It is produced by `TransformAnimator` and consumed by `SpriteScene.applyTransform` to position polygons on screen.

```swift
public struct SpriteTransform: Sendable {
    public var positionOffset: Vector2D   // additional pixel offset from sprite base position
    public var scale: Vector2D            // multiplier applied on top of sprite base scale
    public var rotation: Double           // degrees, applied on top of sprite base rotation
    public var morphAmount: Double        // continuous morph chain position [0..N]

    public static let identity = SpriteTransform(
        positionOffset: .zero, scale: Vector2D(x: 1, y: 1),
        rotation: 0, morphAmount: 0
    )
}
```

---

## 5. TransformAnimator

`TransformAnimator` is a pure-function `enum` namespace in `Animation/TransformAnimator.swift`. It has no stored state. The same call with the same inputs produces the same output.

### 5.1 Entry Point

```swift
public static func transform<RNG: RandomNumberGenerator>(
    for animation: SpriteAnimation,
    elapsedFrames: Double,
    using rng: inout RNG
) -> SpriteTransform
```

`elapsedFrames` is `elapsedTime × targetFPS` — a fractional virtual frame count. This is compared directly against integer `drawCycle` values in XML.

If `animation.enabled == false`, returns `.identity`.

### 5.2 Animation Types

| `AnimationType` | Description |
|----------------|-------------|
| `.keyframe` | Interpolate position/scale/rotation between explicit keyframes |
| `.random` | Random jitter around base values each frame |
| `.keyframeMorph` | Keyframe animation + morph amount follows keyframe `morphAmount` |
| `.jitterMorph` | Random morph amount drawn from `morphRange` each frame |

### 5.3 Keyframe Animation

For `.keyframe` and `.keyframeMorph`:

1. Normalise `elapsedFrames` against `animation.totalDraws` and `animation.loopMode`:
   - `.loop`: `elapsedFrames mod totalDraws`
   - `.once`: `min(elapsedFrames, totalDraws - 1)`
   - `.pingPong`: forward pass then return pass with period `(totalDraws-1) × 2`

2. Find the two bracketing keyframes `kf1`, `kf2` where `kf1.drawCycle ≤ normalised < kf2.drawCycle`.

3. Compute `t = (normalised - kf1.drawCycle) / (kf2.drawCycle - kf1.drawCycle)`.

4. Apply `kf2.easing` to `t` via `EasingMath`.

5. Lerp each field: `posX`, `posY`, `scaleX`, `scaleY`, `rotation`, `morphAmount` (for `.keyframeMorph`).

6. Return as `SpriteTransform`.

**Keyframe struct:**

```swift
public struct Keyframe: Codable, Sendable {
    public var drawCycle: Int       // virtual frame number at targetFPS
    public var posX: Double         // position in sprite units (100 = half canvas)
    public var posY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var rotation: Double
    public var morphAmount: Double
    public var easing: String       // Penner easing name, e.g. "EASE_IN_OUT_QUAD"
}
```

### 5.4 Random / Jitter Animation

For `.random`:

Each call draws random values from the configured ranges and returns a `SpriteTransform`:

```
positionOffset.x = rand(randomSpeed.x)
positionOffset.y = rand(randomSpeed.y)
scale.x          = animation.scale.x + rand(randomScale.x)
scale.y          = animation.scale.y + rand(randomScale.y)
rotation         = animation.rotation + rand(randomRotation)
```

Unlike the Scala jitter mode (which undid the previous frame's transform), the Swift model simply re-samples every frame. Because `positionOffset` is applied as a delta on top of the sprite's base position (not accumulated into the geometry), there is nothing to undo — the next frame's fresh sample replaces the previous one naturally.

### 5.5 Loop Normalisation

`TransformAnimator.normalizedElapsed(_:totalDraws:loopMode:)` maps raw `elapsedFrames` onto a position in `[0, totalDraws)`:

```swift
static func normalizedElapsed(_ elapsed: Double, totalDraws: Int, loopMode: LoopMode) -> Double
```

For `.pingPong`: period = `(totalDraws-1) × 2`. Forward pass `[0, totalDraws)`, then return pass `(totalDraws, 0]` via `period - n`.

---

## 6. MorphInterpolator

`MorphInterpolator` blends the base polygon array toward one or more morph target polygon arrays.

```swift
public enum MorphInterpolator {
    public static func interpolate(
        base: [Polygon2D],
        targets: [[Polygon2D]],
        morphAmount: Double
    ) -> [Polygon2D]
}
```

`morphAmount` is a continuous chain position `[0..N]`:
- `0.0` → returns `base`
- `1.0` → returns `targets[0]`
- `1.5` → halfway between `targets[0]` and `targets[1]`
- `k..k+1` → lerps between `targets[k-1]` and `targets[k]` at fraction `(morphAmount - k)`

The function lerps each corresponding `Vector2D` point between the two polygon arrays. The base and all targets must have the same polygon count and point count per polygon — mismatches silently return the base.

Morph target files are polygon XMLs loaded by `XMLPolygonLoader` from `<project>/morphTargets/<ref.file>`. Missing files are silently replaced with empty arrays so a bad reference doesn't block the whole load.

---

## 7. Renderer Parameter Animation

### 7.1 Overview

Each `Renderer` carries `changes: RendererChanges` — an optional set of animations for stroke width, stroke color, fill color, point size, opacity, and stencil opacity. `RenderStateEngine` advances these animations each virtual frame.

### 7.2 RendererAnimationState

`RendererAnimationState` holds all cursor state for one renderer's animations — palette indices, direction flags, hold counters, accumulated values:

```swift
public struct RendererAnimationState: Sendable {
    public var strokeWidthState:  FloatAnimState
    public var strokeColorState:  ColorAnimState
    public var fillColorState:    ColorAnimState
    public var pointSizeState:    FloatAnimState
    public var opacityState:      FloatAnimState
    public var stencilOpacityState: FloatAnimState?
}
```

`SpriteState.rendererAnimationStates` holds one `RendererAnimationState` per renderer in the renderer set.

### 7.3 RenderStateEngine

Two methods on the `enum RenderStateEngine` namespace:

```swift
// Advance all animation states by one virtual frame
public static func advance(
    state:         RendererAnimationState,
    changes:       RendererChanges,
    stencilConfig: StencilConfig?,
    using rng:     inout some RandomNumberGenerator
) -> RendererAnimationState

// Apply current state values to produce the resolved Renderer for this frame
public static func resolve(
    renderer: Renderer,
    state:    RendererAnimationState,
    changes:  RendererChanges
) -> Renderer
```

`advance` is called once per virtual frame (per `framesToAdvance` in `SpriteScene.advance`).
`resolve` is called at render time to produce the `Renderer` with current animated values.

### 7.4 Animation Dimensions

Each animatable parameter supports the same dimensions as the Scala `RenderTransform`:

| Dimension | Values |
|-----------|--------|
| Kind | `NUM_SEQ`, `NUM_RAN`, `SEQ` (palette), `RAN` (palette random) |
| Motion | `UP`, `DOWN`, `PING_PONG` |
| Cycle | `CONSTANT`, `ONCE`, `ONCE_REVERT`, `PAUSING`, `PAUSING_RANDOM` |
| Scale | `SPRITE` (once per sprite), `POLY` (once per polygon), `POINT` (once per point) |

---

## 8. SpriteScene.advance Orchestration

`SpriteScene.advance(deltaTime:targetFPS:using:)` mutates every `SpriteInstance.state` in-place:

```
for each instance:
  1. Check totalDraws limit (withinLimit = drawCycle < totalDraws || totalDraws == 0)
  2. If withinLimit:
       accumulate elapsedTime += deltaTime
       elapsedFrames = elapsedTime × targetFPS
       state.transform = TransformAnimator.transform(for: def.animation,
                                                      elapsedFrames: elapsedFrames,
                                                      using: &rng)

  3. Accumulate frameTimeAccumulator += deltaTime
     framesToAdvance = floor(frameTimeAccumulator / (1/targetFPS))
     subtract framesToAdvance × frameStep from accumulator

  4. For each of framesToAdvance virtual frames:
       a. Advance renderer index (per playback mode: static/sequential/random)
       b. If modifyInternalParameters:
            advance RendererAnimationState for active renderer
       c. Increment drawCycle
```

Step 2 uses real elapsed time for smooth interpolation. Steps 3–4 use virtual frame counting to honour integer hold lengths and `pauseMax` values in XML.

---

## 9. EasingMath

`EasingMath` implements Robert Penner's easing equations.

```swift
public enum EasingMath {
    public static func ease(t: Double, from: Double, to: Double,
                            duration: Double, name: String) -> Double
}
```

All standard Penner families are supported (linear, quad, cubic, quart, quint, sine, expo, circ, elastic, back, bounce, each in in/out/inOut variants). An unrecognised `name` returns linear.

---

## 10. Sprite Coordinate Pipeline (Transform Application)

`SpriteScene.applyTransform(_:to:canvasSize:)` converts a polygon from world space to pixel space:

```
// Loom geometry scale: polygon coords ≈ ±0.5; ×2 maps to world ±1
sx = def.scale.x × state.transform.scale.x × 2.0
sy = def.scale.y × state.transform.scale.y × 2.0

// Rotation in world space (degrees → radians)
rotRad = (def.rotation + state.transform.rotation) × π / 180

// Pixel-space position: raw units / 100 × canvas half-size
tx = (def.position.x + state.transform.positionOffset.x) / 100.0 × hw
ty = (def.position.y + state.transform.positionOffset.y) / 100.0 × hh

// Per-point:
wx = pt.x × sx;  wy = pt.y × sy      // 1. scale
rx = wx×cos - wy×sin; ry = wx×sin + wy×cos  // 2. rotate
final = Vector2D(rx × hw + tx, ry × hh + ty)   // 3. to pixels + position
```

`ViewTransform.worldToScreen` then adds the canvas-centre offset to produce final screen coordinates.

---

## 11. Scala Reference: Key Differences

| Concern | Scala | Swift |
|---------|-------|-------|
| Animation model | In-place vertex mutation | Pure `SpriteTransform` value |
| Jitter | Undo/redo applied transform | Re-sample; no history needed |
| Delta-time | Not used (fixed 10 FPS) | `deltaTime` throughout |
| Easing | String dispatch, silent fallthrough | String dispatch with linear fallback |
| Clone issues | Random config not cloned | Struct value semantics; automatic |
| Scale origin | Around coordinate origin (drift) | Around sprite's normalised centre |
| Config coupling | Read `Config` singleton at animate time | `def.scale`, `def.position` from struct |

---

## 12. Morph Target File Loading

Morph target files are loaded at `SpriteScene` init time:

```swift
let morphTargetPolygons: [[Polygon2D]] = sprite.animation.morphTargets.map { ref in
    let url = projectDirectory
        .appendingPathComponent("morphTargets")
        .appendingPathComponent(ref.file)
    return (try? XMLPolygonLoader.load(url: url)) ?? []
}
```

Missing files produce an empty array, not a throw — so a bad morph target reference shows no morph effect rather than crashing the scene load.
