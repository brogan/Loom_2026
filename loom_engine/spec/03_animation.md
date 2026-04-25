# Loom Engine — Animation System
**Specification 03**  
**Date:** 2026-04-18  
**Depends on:** `01_technical_overview.md`

---

## 1. Purpose

This document specifies the animation system — the mechanism by which sprites move, scale, rotate, and morph between frames. It covers:

- The `SpriteAnimator` interface
- All four animator implementations (`Animator2D`, `Animator3D`, `KeyframeAnimator`, `JitterMorphAnimator`)
- The sprite transform pipeline (`Sprite2D`, `Sprite3D`)
- The `Scene` update loop
- The `Camera` and `View` coordinate system
- Supporting utilities (`Randomise`, `Easing`, `Range`)
- Design assessment and improvement recommendations

---

## 2. Conceptual Overview

Loom's animation model is **geometry-mutation based**: animating a sprite means directly and cumulatively modifying the coordinates of its underlying polygon points on every frame. There is no concept of a separate "transform matrix" that is applied to a canonical geometry — the geometry itself is the state.

This has a profound consequence: **a sprite's polygon data is never in a canonical pose**. The points are always in their current transformed state. Cloning a sprite requires carefully unwinding all applied transforms to reconstruct the original, and the jitter mode in `Animator2D` must explicitly undo the previous frame's transforms before applying new ones.

Four animator types exist, each suited to a different style of animation:

| Animator | Style | Key feature |
|----------|-------|-------------|
| `Animator2D` | Continuous / oscillating 2D movement | Stochastic per-frame randomisation; jitter (oscillation) mode |
| `Animator3D` | Continuous 3D movement | Simple cumulative 3D transforms |
| `KeyframeAnimator` | Path-following 2D animation | Eased interpolation between explicit keyframes |
| `JitterMorphAnimator` | Vertex morphing | Random per-frame interpolation between two shapes |

---

## 3. Interface: SpriteAnimator

```scala
trait SpriteAnimator {
  var animating: Boolean
  def update(sprite: Sprite2D): Unit
  def cloneAnimator(): SpriteAnimator
}
```

`Sprite2D.update()` calls `animator.update(this)` each frame. The animator is responsible for calling `sprite.translate()`, `sprite.scale()`, and/or `sprite.rotate()` as appropriate.

All implementations extend `SpriteAnimator`. `Animator3D` is the exception — it operates on `Sprite3D` directly and does not implement `SpriteAnimator` (which is typed to `Sprite2D`).

---

## 4. Animator2D

### 4.1 Constructor

```scala
class Animator2D(
  var animating: Boolean,
  var scale: Vector2D,      // base scale factor (multiplier, applied each frame)
  var rotation: Double,     // base rotation in degrees (applied each frame)
  var speed: Vector2D       // base translation vector (applied each frame)
)
```

### 4.2 Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `jitter` | `Boolean` | `false` | Oscillation mode (see §4.5) |
| `currentScale` | `Vector2D` | `= scale` | Per-frame computed scale value |
| `currentRotation` | `Double` | `= rotation` | Per-frame computed rotation value |
| `currentSpeed` | `Vector2D` | `= speed` | Per-frame computed speed value |
| `lastAppliedScale` | `Vector2D` | `(1.0, 1.0)` | Previous frame's applied scale — used to undo in jitter mode |
| `lastAppliedRotation` | `Double` | `0.0` | Previous frame's applied rotation |
| `lastAppliedSpeed` | `Vector2D` | `(0.0, 0.0)` | Previous frame's applied speed |
| `randomFeatures` | `Map[String, Boolean]` | all `false` | Which parameters have randomisation enabled |
| `randomScaleParams` | `Map[String, Array[Double]]` | `[0,0]` per axis | Random range for scale: `"x" → [min, max]`, `"y" → [min, max]` |
| `randomRotationParams` | `Map[String, Array[Double]]` | `[0,0]` | Random range for rotation: `"x" → [min, max]` |
| `randomSpeedParams` | `Map[String, Array[Double]]` | `[0,0]` per axis | Random range for speed: `"x" → [min, max]`, `"y" → [min, max]` |

### 4.3 Configuration Methods

Features are opt-in: a parameter is only animated if its `setRandom*` method has been called.

```scala
def setRandomScale(params: Map[String, Array[Double]]): Unit
// Sets randomFeatures("scale") = true; stores x/y ranges

def setRandomRotation(params: Map[String, Array[Double]]): Unit
// Sets randomFeatures("rotation") = true; stores range

def setRandomSpeed(params: Map[String, Array[Double]]): Unit
// Sets randomFeatures("speed") = true; stores x/y ranges
```

### 4.4 Update Algorithm

Each frame, `update(sprite)` executes:

**Step 1 — compute `process()`:**  
For each enabled feature, draw a random value from its configured range and add it to the base value:

```
currentScale.x  = scale.x  + rand(randomScaleParams("x"))
currentScale.y  = scale.y  + rand(randomScaleParams("y"))
currentSpeed.x  = speed.x  + rand(randomSpeedParams("x"))   [jitter: from 0, not base]
currentSpeed.y  = speed.y  + rand(randomSpeedParams("y"))
```

For **rotation** the behaviour differs between modes:
- *Cumulative:* `currentRotation += rand(randomRotationParams("x"))`  — rotation accumulates over time
- *Jitter:* `currentRotation = rotation + rand(randomRotationParams("x"))` — rotation is re-sampled from the base each frame

**Step 2 — apply transforms:**

*Cumulative mode (`jitter = false`):*
```
if scale enabled:    sprite.scale(currentScale)
if rotation enabled: sprite.rotate(currentRotation)
if speed enabled:    sprite.translate(currentSpeed)
```
Transforms accumulate indefinitely. Sprites drift, grow, or spin continuously.

*Jitter mode (`jitter = true`):*
```
// Undo previous frame (reverse order, multiplicative inverse for scale):
if speed enabled:    sprite.translate(-lastAppliedSpeed)
if rotation enabled: sprite.rotate(-lastAppliedRotation)
if scale enabled:    sprite.scale(1/lastAppliedScale.x, 1/lastAppliedScale.y)

// Apply new values (forward order):
if scale enabled:    sprite.scale(currentScale);    lastAppliedScale    = currentScale
if rotation enabled: sprite.rotate(currentRotation); lastAppliedRotation = currentRotation
if speed enabled:    sprite.translate(currentSpeed); lastAppliedSpeed    = currentSpeed
```
The sprite oscillates around a home position rather than drifting. The `lastApplied*` fields store exact copies of the values applied in the previous frame, enabling exact inversion.

### 4.5 Jitter Mode in Detail

Jitter mode is the primary mechanism for "living" sprites — shapes that breathe, shimmer, or quiver without leaving their position. The key invariant is:

> Every frame the sprite is returned to exactly the state it was in two frames ago, then a new random displacement is applied.

This requires that the undo operations are exact inverses. For translation and rotation this is straightforward (negate). For scale it requires division: if frame N applied scale (1.05, 0.98), frame N+1 must apply scale (1/1.05, 1/0.98) before applying the new value. The code guards against zero-scale division.

**Cumulative jitter risk:** If `jitter = true` but randomFeatures is not symmetric around zero (e.g. scale range `[1.0, 1.2]`), the sprite will slowly drift in scale rather than oscillate, because the undo undoes the exact last value but the new value is always drawn from the same positive range.

### 4.6 Clone Behaviour

```scala
override def clone(): Animator2D
```

Clones `scale`, `rotation`, and `speed` (deep-copied as new `Vector2D` instances). Copies `jitter`.

**Bug:** `randomFeatures` and `randomXxxParams` maps are **not copied** into the clone. A cloned `Animator2D` will have no randomisation enabled, regardless of the original's configuration. This means sprites created by cloning an animator-equipped sprite will animate with their base (non-random) values only.

---

## 5. Animator3D

### 5.1 Constructor

```scala
class Animator3D(
  var animating: Boolean,
  var scale: Vector3D,
  var rotation: Vector3D,   // degrees per frame on each axis
  var speed: Vector3D       // units per frame on each axis
)
```

### 5.2 Update Algorithm

Simple, fully cumulative, no randomisation:

```scala
def update(sprite: Sprite3D): Unit = {
  if (animating) {
    if (scale    ≠ (1,1,1)) sprite.scale(scale)
    if (rotation ≠ (0,0,0)) sprite.rotate(rotation)   // → rotateX + rotateY + rotateZ
    if (speed    ≠ (0,0,0)) sprite.translate(speed)    // → updates sprite.location
  }
}
```

All transforms are applied unconditionally each frame (modulo identity check). Rotation accumulates on all three axes simultaneously. No jitter, no easing, no feature flags.

**Important 3D distinction:** `sprite.translate()` updates `sprite.location` (a `Vector3D` world-space position), not the shape's vertex coordinates. Scale and rotation do modify shape vertices. This asymmetry exists because 3D perspective projection needs the world-space position at draw time.

---

## 6. KeyframeAnimator

### 6.1 Purpose

Moves a sprite along an explicitly defined path with eased interpolation between keyframe positions. This is the animator used when deterministic, choreographed motion is required rather than random animation.

### 6.2 Keyframe

```scala
case class Keyframe(
  drawCycle: Int,     // Frame index at which this keyframe applies
  posX: Double,       // Position in normalised units [-200, 200] (100 = half canvas width)
  posY: Double,       // Position in normalised units
  scaleX: Double,     // Absolute scale factor (not a delta)
  scaleY: Double,
  rotation: Double,   // Absolute rotation in degrees
  easing: String      // Easing function name applied when transitioning TO this keyframe
)
```

All values are **absolute** — `posX = 50` means 50 normalised units from centre, not 50 units from the previous keyframe.

### 6.3 Constructor

```scala
class KeyframeAnimator(
  var animating: Boolean,
  val keyframes: Array[Keyframe],   // Must be sorted by drawCycle ascending
  val loopMode: String              // "NONE" | "LOOP" | "PING_PONG"
)
```

### 6.4 State

| Field | Type | Initial value | Description |
|-------|------|--------------|-------------|
| `drawCount` | `Int` | `keyframes.head.drawCycle` | Current frame counter |
| `direction` | `Int` | `1` | `1` = forward, `-1` = backward (PING_PONG) |
| `lastPosX/Y` | `Double` | `0.0` | Last-applied position (delta tracking) |
| `lastScaleX/Y` | `Double` | `1.0` | Last-applied scale |
| `lastRotation` | `Double` | `0.0` | Last-applied rotation |
| `finished` | `Boolean` | `false` | Set true when NONE loop reaches end |

### 6.5 Update Algorithm

Each frame:

1. **Find bracketing keyframes** for the current `drawCount` — the two keyframes `kf1` and `kf2` such that `kf1.drawCycle ≤ drawCount < kf2.drawCycle`.

2. **Interpolate each parameter** using the easing function from `kf2`:
   ```
   t = drawCount - kf1.drawCycle
   d = kf2.drawCycle - kf1.drawCycle
   
   easedPosX   = Easing.ease(t, kf1.posX,    kf2.posX    - kf1.posX,    d, kf2.easing)
   easedPosY   = Easing.ease(t, kf1.posY,    kf2.posY    - kf1.posY,    d, kf2.easing)
   easedScaleX = Easing.ease(t, kf1.scaleX,  kf2.scaleX  - kf1.scaleX,  d, kf2.easing)
   easedScaleY = Easing.ease(t, kf1.scaleY,  kf2.scaleY  - kf1.scaleY,  d, kf2.easing)
   easedRot    = Easing.ease(t, kf1.rotation, kf2.rotation - kf1.rotation, d, kf2.easing)
   ```

3. **Convert to delta transforms** (because `sprite.translate/scale/rotate` are cumulative):
   ```
   deltaX_px = (easedPosX - lastPosX) × canvasW / 200
   deltaY_px = (easedPosY - lastPosY) × canvasH / 200
   scaleRatioX = easedScaleX / lastScaleX
   scaleRatioY = easedScaleY / lastScaleY
   deltaRotation = easedRotation - lastRotation
   ```

4. **Apply transforms:**  
   Scale and rotation are applied around the sprite's current interpolated position (translate to origin, transform, translate back) to prevent positional drift.

5. **Update `last*` state** for next frame.

6. **Advance `drawCount`** by `direction`, then handle loop boundary:

| loopMode | At last keyframe | At first keyframe (PING_PONG) |
|----------|-----------------|-------------------------------|
| `"NONE"` | `finished = true` | — |
| `"LOOP"` | Reset to start, `drawCount = keyframes.head.drawCycle` | — |
| `"PING_PONG"` | `direction = -1` | `direction = 1` |

### 6.6 Coordinate System

`posX` and `posY` use a normalised unit system where `±200` corresponds to the canvas edges. The conversion to pixels is:

```
x_pixels = posX × canvasWidth  / 200
y_pixels = posY × canvasHeight / 200
```

where `canvasWidth = Config.width × Config.qualityMultiple`.

**Design note:** This creates a direct coupling from `KeyframeAnimator` into the `Config` singleton. Keyframe values baked into XML at one `qualityMultiple` will produce incorrect pixel positions if `qualityMultiple` changes.

---

## 7. Morph Animation

Loom has a dedicated morph system built around `MorphTarget`, which supports morphing a sprite's vertex positions between multiple shape snapshots. Two animators use it: `JitterMorphAnimator` (random per-frame morph) and `KeyframeMorphAnimator` (eased morph integrated with full keyframe animation).

### 7.1 MorphTarget

`MorphTarget` holds a chain of vertex snapshots enabling multi-target morphing:

```scala
class MorphTarget(val snapshots: Array[Array[Array[Vector2D]]])
// snapshots(i)(polyIndex)(vertexIndex) = Vector2D
// snapshots(0) = base shape
// snapshots(1) = morph target 1
// snapshots(2) = morph target 2 … etc.
```

`morphAmount` is a continuous position `0..N` through the chain:
- `0.0` → base shape
- `1.0` → target 1
- `2.0` → target 2
- `k..k+1` → lerp between `snapshots(k)` and `snapshots(k+1)` at fraction `(morphAmount − k)`

Single-target use (N=1) with `morphAmount ∈ [0,1]` is the common case.

**`applyMorph(shape, position)`:** Overwrites every polygon vertex directly (not delta-based):
```
pts(vi).x = from(vi).x + (to(vi).x − from(vi).x) × t
pts(vi).y = from(vi).y + (to(vi).y − from(vi).y) × t
```
This is an absolute write — it unconditionally replaces the current vertex positions with the interpolated snapshot values. Any other transform applied to the sprite before `applyMorph` in the same frame is discarded.

**`MorphTarget.snapshot(shape)`:** Deep-copies all polygon vertices from a shape into the `Array[Array[Vector2D]]` format. This is how morph targets are created — take a snapshot of a shape after it has been set up in the desired pose.

**`MorphTarget.validate(base, target)`:** Checks that two shapes share the same topology (polygon count, vertex count per polygon, polygon type) before morphing. Logs diagnostic messages and returns false on mismatch.

**`MorphTarget.clone()`:** Deep-copies all snapshot arrays. Safe to assign to a cloned sprite.

### 7.2 JitterMorphAnimator

```scala
class JitterMorphAnimator(
  var animating: Boolean,
  val morphTarget: MorphTarget,
  val morphMin: Double,
  val morphMax: Double
)
```

Each frame picks a random `morphAmount ∈ [morphMin, morphMax]` and calls `morphTarget.applyMorph(sprite.shape, amount)`. No state is tracked. The sprite oscillates randomly through the morph chain, producing a continuously shape-shifting appearance.

### 7.3 KeyframeMorphAnimator

The most sophisticated animator in the system. Combines `MorphTarget` interpolation with full keyframe position/scale/rotation animation, all eased.

```scala
class KeyframeMorphAnimator(
  var animating: Boolean,
  val keyframes: Array[MorphKeyframe],  // sorted by drawCycle
  val loopMode: String,
  val morphTarget: MorphTarget
)

case class MorphKeyframe(
  drawCycle: Int,
  posX: Double, posY: Double,
  scaleX: Double, scaleY: Double,
  rotation: Double,
  morphAmount: Double,   // continuous chain position (0..N)
  easing: String
)
```

**Key design decision — absolute transforms after morph reset:**

`applyMorph` overwrites all vertex positions every frame, which means any delta-based position tracking (as used by `KeyframeAnimator`) would be lost. If frame N applied a +50px translate and frame N+1 calls `applyMorph`, the +50px is gone. The animator cannot simply apply a per-frame delta on top.

The solution: after each `applyMorph`, re-apply the **full current transform as an absolute offset from the first keyframe's baseline (`kf0`)**:

```
dx = easedPosX   − kf0.posX
dy = easedPosY   − kf0.posY
sx = easedScaleX / kf0.scaleX
sy = easedScaleY / kf0.scaleY
dr = easedRotation − kf0.rotation
```

This works because `applyMorph` always restores the vertex positions to the morph-lerped snapshot state (which has the sprite's construction transforms baked in as the base), so the full transform from that base can be applied fresh every frame.

`cloneAnimator()` correctly copies `drawCount`, `direction`, and `finished` state, and deep-clones the `morphTarget`.

---

## 8. Sprite2D Transform Pipeline

### 8.1 Construction Sequence

When a `Sprite2D` is created, its shape is immediately transformed from normalised form to its initial world-space pose:

```
1. shape.translate(spriteParams.rotOffset2D)    — establish rotation pivot
2. sprite.rotate(spriteParams.startRotation2D)  — apply initial rotation
3. sprite.translate(spriteParams.loc2D)         — move to initial position
4. sprite.scale(size)                           — apply size
```

After construction the shape's vertices are in world-space coordinates. The `Sprite2DParams` values are preserved for use in `clone()`.

### 8.2 Per-Frame Transform Methods

```scala
def translate(trans: Vector2D): Unit = shape.translate(trans)
def scale(scale: Vector2D): Unit     = shape.scale(scale)
def rotate(angle: Double): Unit      = shape.rotate(angle)
```

All three delegate directly to `Shape2D`, which applies the transform to every polygon point in-place.

**Transforms are unconditionally cumulative.** Each call permanently moves all polygon vertices. There is no "base position" to return to except via jitter undo or explicit reverse transforms.

### 8.3 Sprite2DParams

Initial placement and animation base values for a sprite:

| Field | Description |
|-------|-------------|
| `loc: Vector2D` | Location in percentage units (x/y, 0–100 range) |
| `size: Vector2D` | Size as fraction of canvas dimensions |
| `rot: Double` | Initial rotation in degrees |
| `loc2D: Vector2D` | Derived canvas-space location |
| `size2D: Vector2D` | Derived canvas-space size (pixels × qualityMultiple) |
| `rotOffset2D: Vector2D` | Offset for rotation pivot |
| `scaleFactor2D: Vector2D` | Base scale per frame for Animator2D |
| `rotFactor2D: Double` | Base rotation per frame |
| `speedFactor2D: Vector2D` | Base speed per frame |

`loc2D` and `size2D` are computed at construction time using `Config.width`, `Config.height`, and `Config.qualityMultiple`. These values are fixed at load time; changing quality after a sprite is created will not retroactively update its world-space dimensions.

### 8.4 Clone

`Sprite2D.clone()` reverses all construction transforms before creating the new instance:

```
1. Undo translate(rotOffset2D)   → translate(-rotOffset2D)
2. Undo startRotation2D          → rotate(-startRotation2D)
3. Undo scale(size)              → scale(1/size.x, 1/size.y)
```

The cloned shape is then passed to a new `Sprite2D` constructor which re-applies these transforms. The animator is cloned via `cloneAnimator()` — but see the `Animator2D` clone bug noted in §4.6.

---

## 9. Sprite3D

`Sprite3D` differs from `Sprite2D` in one key respect: **translation does not modify shape vertices**. Instead it updates `sprite.location` — a separate `Vector3D` used by the renderer for 3D perspective projection. Scale and rotation still modify shape vertices directly.

This is architecturally inconsistent with `Sprite2D` where all three transforms modify vertices. The reason is practical: 3D rendering requires the world-space position at draw time (to compute perspective depth), but in 2D the coordinate transform is embedded into the vertices themselves.

---

## 10. Scene Update Loop

```scala
class Scene {
  val sprites: ListBuffer[Drawable]
  
  def update(): Unit = for (sprite <- sprites) sprite.update()
  def draw(g2D: Graphics2D): Unit = for (sprite <- sprites) sprite.draw(g2D)
}
```

`Scene` is a flat list. All sprites are updated in insertion order, then drawn in insertion order. Insertion order defines the z-stack (first added = drawn first = visually behind). There is no z-index field, no layer system, no spatial partitioning.

---

## 11. Camera and View

### 11.1 Camera (3D Only)

`Camera` is a global singleton that manages 3D scene viewing. Its core principle is **inverted control**: the camera is conceptually still and the world moves in the opposite direction. Calling `Camera.translate(v)` applies `scene.translate(-v)` to all sprites.

```scala
object Camera {
  var view: View
  var viewAngle: Double = 75            // Field of view in degrees
  var scene: Scene                      // The scene being "viewed"
  var viewDistance: Double              // Derived: (viewWidth/2) / tan(viewAngle/2)
  var translateSpeed: Double = 100
  var rotateSpeed: Double = 0.3
}
```

Camera movement (from `KeyPressListener` arrow keys) calls:
- `Camera.translate()` → `scene.translate(-v)` — pan
- `Camera.rotateX/Y()` → `scene.rotateXAroundParent(-angle, origin)` — orbit

### 11.2 View (2D and 3D)

`View` converts between **view-space** (mathematical coordinates: origin at centre, y-up) and **screen-space** (AWT coordinates: origin top-left, y-down).

```
screen_x = borderX + viewCentreX + view_x
screen_y = borderY + viewCentreY - view_y   ← y inversion
```

The `View` object is created at sketch initialisation with the canvas dimensions and does not change at runtime. Every polygon draw call passes vertices through `View.viewToScreenVertex()` before calling AWT drawing methods.

---

## 12. Utility: Randomise

```scala
object Randomise {
  def range(min: Double, max: Double): Double
  def range(min: Int, max: Int): Int
  def probabilityResult(percentage: Double): Boolean  // true if rand(0,100) ≤ percentage
}
```

**Critical bug: new Random instance per call.**  
Every invocation of `Randomise.range()` creates `new Random()` — a fresh instance seeded from `System.nanoTime()`. At 10 FPS with multiple sprites and multiple random features per sprite, this generates hundreds of `Random` instances per second, each immediately discarded. The creation cost is small individually but it also means the random sequence has no continuity and cannot be seeded for reproducibility.

**Fix:** Use a single static `Random` instance (or a thread-local one for future parallelism). In Swift: use a single `SystemRandomNumberGenerator` or inject a seeded generator.

---

## 13. Utility: Easing

```scala
object Easing {
  def ease(t: Double, start: Double, change: Double, duration: Double, easing: String): Double
}
```

Implements Robert Penner's easing equations. All standard families are supported:

| Family | Variants |
|--------|---------|
| Linear | LINEAR |
| Quadratic | EASE_IN/OUT/IN_OUT/OUT_IN_QUAD |
| Cubic | EASE_IN/OUT/IN_OUT/OUT_IN_CUBIC |
| Quartic | EASE_IN/OUT/IN_OUT/OUT_IN_QUART |
| Quintic | EASE_IN/OUT/IN_OUT/OUT_IN_QUINT |
| Sine | EASE_IN/OUT/IN_OUT/OUT_IN_SINE |
| Exponential | EASE_IN/OUT/IN_OUT/OUT_IN_EXPO |
| Circular | EASE_IN/OUT/IN_OUT/OUT_IN_CIRC |
| Elastic | EASE_IN/OUT/IN_OUT/OUT_IN_ELASTIC |
| Back | EASE_IN/OUT/IN_OUT/OUT_IN_BACK |
| Bounce | EASE_IN/OUT/IN_OUT/OUT_IN_BOUNCE |

Easing is currently only used by `KeyframeAnimator`. `Animator2D` and `Animator3D` do not support easing — all their per-frame changes are linear (or discrete random).

**Design note:** Easing function selection is a string match. An invalid string silently falls through without applying any easing, producing a linear result without warning.

---

## 14. Design Assessment

### 14.1 Strengths

**Jitter mode is architecturally elegant:** The "apply then undo" approach achieves oscillation without requiring a canonical state. For a system where the geometry is always in world-space, this is a pragmatic solution.

**KeyframeAnimator is capable:** The combination of per-keyframe easing, absolute values with delta application, and three loop modes provides a solid path-following system. The PING_PONG mode and all easing families give good expressive range.

**Four distinct animator types** cover the main use cases: continuous random motion, 3D motion, precise choreography, and shape morphing.

---

### 14.2 Problems and Improvement Opportunities

#### A1 — Animator2D.clone() does not copy randomisation config

`clone()` copies `scale`, `rotation`, `speed`, and `jitter`, but not `randomFeatures` or the random parameter maps. A cloned animator will animate with the base values only, producing deterministic (non-random) motion regardless of the original's configuration.

**Fix:** Deep-copy `randomFeatures` and `randomXxxParams` in `clone()`. This is a bug in the current Scala code and should be fixed now.

**Swift:** Use a value-type struct for the configuration; copying is automatic and complete.

---

#### A2 — Randomise creates a new Random instance per call

Every call to `Randomise.range()` constructs `new Random()`. This wastes allocation, cannot be seeded, and produces a sequence with no statistical continuity.

**Fix (Scala):** Replace with a single `Random` instance as a lazy val in the `Randomise` object:
```scala
object Randomise {
  private val rng = new scala.util.Random
  def range(min: Double, max: Double): Double = ...  // use rng
}
```

**Swift:** Use `Double.random(in: min...max)` which uses the system generator, or inject a `RandomNumberGenerator` for seedability.

---

#### A3 — No delta-time compensation

All animators assume a fixed frame duration. `Animator2D` applies `speed` as pixels-per-frame, not pixels-per-second. At the current 10 FPS this is consistent, but if the frame rate changes (Swift targeting 60 FPS) all animation speeds will be wrong by a factor of 6.

**Fix:** Pass a `deltaTime: Double` (seconds since last frame) to `update()` and scale speed/rotation by it.

**Swift:** CADisplayLink provides `targetTimestamp - timestamp` as the actual frame duration.

---

#### A4 — Sprite2D.scale() is not centre-anchored

`sprite.scale(v)` scales all polygon vertices around the coordinate origin (0, 0), not around the sprite's centroid. For a sprite not centred at the origin this causes it to drift outward from the origin as it grows.

`KeyframeAnimator` explicitly works around this for scale (translate to origin, scale, translate back). `Animator2D` does not — sprites using random scale will drift unless they happen to be centred near the origin.

**Fix:** `Sprite2D.scale()` should compute the centroid of the sprite's current points and scale around it. Or provide a separate `scaleAroundCentre()` method.

---

#### A5 — Geometry-mutation model precludes snapshot/restore

Because all animation is applied directly to polygon vertices, there is no way to:
- Read the sprite's current logical position (only the raw polygon centroid, which changes with shape)
- Reset a sprite to its initial pose without re-cloning
- Implement undo for live animation

**Swift recommendation:** Separate the logical transform (position, scale, rotation as independent values) from the rendered geometry. Store a canonical (untransformed) copy and compute the final vertex positions each frame from the transform state. This is standard in any scene graph (e.g., SpriteKit's `SKNode`).

---

#### A6 — KeyframeAnimator couples to Config singleton

`KeyframeAnimator.update()` reads `Config.width`, `Config.height`, and `Config.qualityMultiple` directly to convert normalised positions to pixels. This makes it impossible to test in isolation and breaks if the config changes after the animator is created.

**Fix:** Accept canvas dimensions as constructor parameters.

---

#### A7 — Easing string mismatch fails silently

An unrecognised easing name produces a linear result with no error. In a system where easing names are baked into XML files, a typo produces wrong visual output with no diagnostic.

**Fix:** Either validate at load time or log a warning for unknown names.

---

## 15. Swift Migration Notes

### 15.1 Recommended Structural Change

The most impactful change for Swift is to separate **transform state** from **geometry**:

```swift
struct SpriteTransform {
    var position: CGPoint
    var scale: CGSize
    var rotation: CGFloat
    var anchor: CGPoint    // pivot for scale/rotation, normalised [0,1]
}

struct Sprite2D {
    let baseGeometry: Shape2D        // canonical, never mutated
    var transform: SpriteTransform   // updated each frame by animator
    var animator: any SpriteAnimator
    var rendererSet: RendererSet
}
```

At draw time, the renderer applies `transform` to `baseGeometry` to produce screen vertices. No mutation of the canonical geometry — the transform is the state, not the vertices.

This eliminates: the jitter undo/redo problem, the clone transform unwinding, the scale drift issue, and all issues with non-reproducible state.

### 15.2 Animator Protocol

```swift
protocol SpriteAnimator {
    var animating: Bool { get set }
    mutating func update(transform: inout SpriteTransform, deltaTime: Double)
}
```

Using `inout` makes the mutation explicit and safe. The `deltaTime` parameter normalises all speed/rotation values to per-second rates.

### 15.3 Direct Translations

| Scala | Swift |
|-------|-------|
| `Animator2D` | `ContinuousAnimator` struct |
| `Animator3D` | `ContinuousAnimator3D` struct |
| `KeyframeAnimator` | `KeyframeAnimator` struct with `SpriteTransform` target |
| `JitterMorphAnimator` | `MorphAnimator` struct |
| `Easing.ease(t, s, c, d, name)` | `func ease(_ t: Double, from: Double, to: Double, duration: Double, curve: EasingCurve) -> Double` where `EasingCurve` is a Swift enum |
| `Randomise.range(min, max)` | `Double.random(in: min...max)` |
| `Range(min, max)` | `ClosedRange<Double>` |
| `RangeXY(x, y)` | `struct RangeXY { var x: ClosedRange<Double>; var y: ClosedRange<Double> }` |

### 15.4 Easing

In Swift, replace the string dispatch with an enum:

```swift
enum EasingCurve {
    case linear
    case easeInQuad, easeOutQuad, easeInOutQuad
    case easeInCubic, easeOutCubic, easeInOutCubic
    // ... all Penner families
    
    func apply(t: Double, from: Double, to: Double, duration: Double) -> Double
}
```

Exhaustive switch statement means the compiler flags any missing case. No silent fallthrough.
