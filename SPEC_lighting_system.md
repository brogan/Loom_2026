# Spec: Theatrical Lighting System

**Status:** Planned  
**Scope:** loom_swift engine + Loom_Swift_Integration UI  
**Dependencies:** `LoomLayer`, `SpriteScene.renderLayered`, `DoubleDriver`, existing Layers tab

---

## Motivation

Loom's compositing pipeline renders sprites into per-layer offscreen buffers and
composites them onto the canvas. What is currently missing is any mechanism for
spatially modulating light and shadow across a layer's content — e.g. vignettes,
silhouettes, spotlight pools, or colour washes. A lightweight theatrically-biased
lighting system would fill this gap without requiring ray-tracing or physically-based
shading. All light types are procedural gradient primitives that combine into a
per-frame **light map** which is then applied as a blend pass on opted-in layers.

Goals:
- Theatrical expressiveness over physical realism
- Near-zero cost when disabled (flag-gated; no changes to existing render path)
- Animatable via the existing `DoubleDriver` system (position, intensity, colour, etc.)
- Proxy objects in wireframe view for positioning
- Per-layer opt-in in Layers inspector
- Dedicated Lights tab for management

---

## Light Types

| Type | Shape | Key parameters |
|---|---|---|
| **Omni** | Radial gradient from a centre point | position, radius, falloff |
| **Spot** | Directional cone | position, direction, cone angle, penumbra, falloff |
| **Area** | Soft-edged rectangle | position, width, height, rotation, edge softness |

All three produce a fragment in the light map — a `CGImage` (or `CIImage`) in which
pixel value represents illumination intensity (0 = dark, 1 = full light). Coloured
lights produce RGBA fragments; the final map is composited in RGBA.

---

## Data Model

### `LightType`

**File:** `loom_swift/Sources/LoomEngine/Config/LightingConfig.swift` (new file)

```swift
public enum LightType: String, Codable, CaseIterable, Sendable {
    case omni
    case spot
    case area
}
```

### `LoomLight`

```swift
public struct LoomLight: Codable, Equatable, Identifiable, Sendable {
    public var id:           UUID
    public var name:         String
    public var type:         LightType
    public var isEnabled:    Bool

    // World-space position (Y-up, same coordinate space as sprites).
    // x and y are independently driveable.
    public var positionX:        Double
    public var positionXDriver:  DoubleDriver
    public var positionY:        Double
    public var positionYDriver:  DoubleDriver

    // Intensity: 0 = no contribution, 1 = full contribution.
    public var intensity:        Double
    public var intensityDriver:  DoubleDriver

    // Colour (default white = pure luminance light).
    // The rendered colour blends between the layer's natural colour
    // (intensity 0) and the light colour (intensity 1) in the lit region.
    public var color:            LoomColor

    // Falloff: controls the rate at which intensity drops with distance.
    // 1.0 = linear, 2.0 = quadratic (default), higher = sharper edge.
    public var falloff:          Double

    // Radius (Omni and Spot): world-space distance at which intensity reaches zero.
    public var radius:           Double
    public var radiusDriver:     DoubleDriver

    // Spot only
    public var direction:        Double    // radians, 0 = right, π/2 = up
    public var directionDriver:  DoubleDriver
    public var coneAngle:        Double    // half-angle of the inner cone (radians)
    public var coneAngleDriver:  DoubleDriver
    public var penumbraAngle:    Double    // extra angle for soft edge (radians)

    // Area only
    public var width:            Double
    public var widthDriver:      DoubleDriver
    public var height:           Double
    public var heightDriver:     DoubleDriver
    public var rotation:         Double    // radians
    public var rotationDriver:   DoubleDriver
    public var edgeSoftness:     Double    // world units; 0 = hard edge
}
```

Sensible defaults: `isEnabled = true`, `intensity = 1.0`, `color = white`,
`falloff = 2.0`, `radius = 0.3`, `coneAngle = π/6`, `penumbraAngle = π/12`,
`width = 0.3`, `height = 0.2`, `edgeSoftness = 0.05`.

All `DoubleDriver` fields default to `.one` (constant) for intensity/radius/width/height
and `.zero` for position and direction deltas, matching the existing driver pattern used
by `LoomLayer`.

### `LightingConfig`

```swift
public struct LightingConfig: Codable, Equatable, Sendable {
    /// Master switch. When false the entire lighting pass is skipped and
    /// renderLayered behaves exactly as today.
    public var isEnabled: Bool
    public var lights:    [LoomLight]
}
```

Default: `isEnabled = false`, `lights = []`.

### `ProjectConfig` addition

Add one field to `ProjectConfig`:

```swift
public var lightingConfig: LightingConfig
```

Decoded with `decodeIfPresent` defaulting to `LightingConfig(isEnabled: false, lights: [])`.
Existing projects load without modification and see no lighting overhead.

### `LoomLayer` addition

Add one field to `LoomLayer`:

```swift
/// When true this layer receives the lighting pass. Default false.
public var receivesLighting: Bool
```

Decoded with `decodeIfPresent` defaulting to `false`. Layers with `false` (the majority
in existing projects) skip the lighting composite entirely.

---

## Light Map Computation

**File:** `loom_swift/Sources/LoomEngine/Lighting/LightMapRenderer.swift` (new file)

### Overview

`LightMapRenderer` accepts the evaluated lighting config for the current frame and
produces a `CGImage` at the canvas pixel resolution. The map is RGBA — each channel
encodes the contribution of the colour-multiplied light at that pixel.

### CoreImage pipeline

Each light generates a `CIImage` fragment:

| Light type | CoreImage primitive |
|---|---|
| Omni | `CIRadialGradient` — inner radius 0, outer radius = `radius` in pixels |
| Spot | `CILinearGradient` masked with an angular ramp built from two `CIRadialGradient` instances (one for core, one for penumbra edge) |
| Area | Two perpendicular `CILinearGradient`s intersected via `CIMinimumCompositing` |

Fragments are composited using `CIAdditionCompositing` (lights add together, clamped to 1).
A final colour tint is applied per-fragment before compositing: the fragment is multiplied
by the light's `color` (using `CIColorMatrix`).

The resulting `CIImage` is rendered to a `CGImage` via a single `CIContext.render` call.

### Coordinate mapping

The canvas occupies world x ∈ [−0.52, 0.52], y ∈ [−0.52, 0.52] (Y-up).
Pixel coordinates are straightforward linear: `px = (wx + 0.52) / 1.04 * canvasWidth`.
Light positions are converted to pixel coordinates before feeding to CoreImage.

### Caching

The light map is cached as a `CGImage?` on `SpriteScene`. It is invalidated when:
- Any light parameter changes (intensity, position, colour, etc.) — detected by
  comparing a hash of the evaluated lighting state against the previous frame's hash
- `LoomEngine.seek(toFrame:)` is called (same path as the existing accumulate-buffer
  invalidation)

When the cache is valid, rendering re-uses the previous map at zero cost. For fully
static lighting (common in non-animated scenes) the map is computed once and reused
for every frame.

### Driver evaluation

`LightMapRenderer.evaluate(light:at frame:)` resolves all `DoubleDriver` fields
(position, intensity, radius, etc.) exactly as other drivers are evaluated elsewhere
in the engine. The resulting evaluated `LoomLight` is a plain struct with all values
resolved to `Double`.

---

## Rendering Integration

**File:** `loom_swift/Sources/LoomEngine/Scene/SpriteScene.swift`

### Modified `renderLayered`

After compositing a layer's sprite buffer into the main canvas, if
`lightingConfig.isEnabled && layer.receivesLighting`:

```
1. Obtain the light map (compute or reuse from cache).
2. Apply map to the layer buffer using CISourceAtopCompositing or multiply blend:
      litBuffer = layerBuffer * lightMap
   The multiply blend darkens pixels in proportion to the light map value (0 = fully
   dark, 1 = unchanged). Lit regions keep their colour; unlit regions go to black.
3. Composite litBuffer → main canvas (replacing the un-lit layer composite).
```

The blend can be implemented as:
```swift
let mapped = CIFilter(name: "CIMultiplyCompositing")!
mapped.setValue(layerCIImage, forKey: kCIInputImageKey)
mapped.setValue(lightMapCIImage, forKey: kCIInputBackgroundImageKey)
```

Or alternatively:
- **Luminance only** (greyscale map): multiply each channel by the greyscale value
- **Coloured lights**: multiply RGBA map × RGBA layer (screen blend for additive lights)

The spec proposes **multiply** as the default (dark map = dark layer, white map = full
layer colour), with an optional `LightBlendMode` field on `LoomLight` (`.multiply` /
`.screen`) for additive vs. subtractive lights in a future iteration.

### `SpriteScene` additions

```swift
var lightMapCache:      CGImage? = nil
var lightMapCacheHash:  Int      = 0

mutating func invalidateLightMap() {
    lightMapCache = nil
    lightMapCacheHash = 0
}
```

`invalidateLightMap()` is called from `LoomEngine.seek(toFrame:)` alongside the
existing `invalidateAccumulateBuffers()`.

---

## Proxy Wireframe Rendering

**File:** `Loom_Swift_Integration/Sources/Loom/Tabs/SpritesTabView.swift` (or a shared
overlay drawn in the canvas view)

When wireframe / proxy display is active, each `LoomLight` is drawn as an overlay
using `GraphicsContext`:

| Light type | Proxy shape |
|---|---|
| Omni | Circle centred at position; radius = light radius; dashed stroke |
| Spot | Two rays from position at ±coneAngle relative to direction; arc at radius closing the cone; dashed stroke. A second lighter arc at ±(coneAngle + penumbraAngle) shows the penumbra. |
| Area | Dashed rectangle at position, width × height, rotated |

All proxies are drawn in a distinct colour (proposed: **amber**, matching the existing
canvas-frame guide colour) with an open circle at the light's position point. Disabled
lights are drawn at reduced opacity (0.3).

Lights that are selected in the Lights tab display their handles as draggable:
- **Omni**: drag the circle edge to resize radius
- **Spot**: drag the direction ray tip to rotate; drag the cone-edge ray to adjust angle
- **Area**: drag corners to resize; drag interior to translate

Handle drag logic mirrors the existing curved knife / extrude handle patterns.

---

## Lights Tab

**File:** `Loom_Swift_Integration/Sources/Loom/Tabs/LightsTabView.swift` (new file)

### Layout

```
┌─ Lights ──────────────────────────────────┐
│  [+ Omni]  [+ Spot]  [+ Area]    ☀ (master) │
│  ─────────────────────────────────────────  │
│  ☀ Key Light          Omni   ●  [■]         │
│  ☀ Fill Light         Area   ●  [■]         │
│  ● Spot 1             Spot   ○  [■]         │
└───────────────────────────────────────────┘
```

Each row: enable toggle, name (editable), type label, visibility indicator, delete button.

### Inspector (right panel, context-sensitive)

Appears when a light is selected in the list. Sections:

**Position**
- X field + driver button
- Y field + driver button

**Intensity**
- Slider 0–1 + driver button
- Colour swatch (opens colour picker)

**Shape** (type-specific)
- Omni: Radius + driver, Falloff stepper
- Spot: Direction + driver, Cone Angle + driver, Penumbra Angle, Falloff
- Area: Width + driver, Height + driver, Rotation + driver, Edge Softness

All driver buttons follow the existing inspector pattern (`DoubleDriverButton` /
`DriverSection`).

### Master toggle

A single enable button (lamp icon) in the tab header toggles `lightingConfig.isEnabled`.
When off, all layer rendering skips the lighting pass and the proxies are hidden.

---

## Layers Inspector Integration

**File:** `Loom_Swift_Integration/Sources/Loom/Inspector/LayersInspector.swift`

Add a **Lighting** row to the existing per-layer inspector section:

```
Lighting   [toggle]
```

The toggle maps to `LoomLayer.receivesLighting`. When off, the lighting pass is
skipped entirely for that layer regardless of `lightingConfig.isEnabled`. Default off
for all existing layers.

---

## Animation / Driver Integration

All `DoubleDriver` fields on `LoomLight` are animatable using the existing driver
system without modification. Examples:

| Effect | Driver target | Driver type |
|---|---|---|
| Firelight flicker | `intensity` | Random / noise driver |
| Tracking spotlight | `positionX`, `positionY` | Follow a sprite's position |
| Pulsing area light | `width`, `height` | Sine wave driver |
| Rotating spotlight | `direction` | Linear ramp |
| Light fade-in | `intensity` | Linear ramp 0→1 over N frames |

No new driver infrastructure is required. The driver evaluation call is the same
`DoubleDriver.evaluate(at frame:)` used everywhere else.

---

## Performance Characteristics

| Condition | Overhead |
|---|---|
| `lightingConfig.isEnabled == false` | Zero — existing code path, no branch taken |
| Enabled, `layer.receivesLighting == false` | Zero for that layer |
| Enabled, static lights, cached map | One `CGImage` reuse; one `CIFilter` blend per lit layer (~0.1ms) |
| Enabled, animated lights, N lights | One `CIContext.render` per frame + one blend per lit layer; ~0.5–2ms for N ≤ 8 on modern Mac |
| Full scene with 4 lights, 2 lit layers | Estimated < 3ms total at canvas resolution 1920×1080 |

The master toggle and per-layer toggle together ensure the lighting system has no
impact on day-to-day geometry editing, subdivision work, or projects that don't use it.

---

## Theatrical Use-Case Examples

| Effect | Configuration |
|---|---|
| Vignette | One Omni light at canvas centre, large radius, low falloff; single lit layer |
| Silhouette | Master light map very dark (intensity 0.05) on a background layer; subject layer unlit |
| Spotlight pool | One Spot, tight cone angle, high penumbra, pointing down; subjects lit below threshold remain in shadow |
| Firelight | One warm Omni (orange, radius 0.15) + random intensity driver; one cool ambient Omni at low intensity |
| Moonlight | One cool-white Area light (width 2.0, height 0.05) at top of canvas, slight blue tint |
| Stage wash | Three Area lights (warm centre, cool left, cool right) compositing additively |
| Dappled canopy | Five small Omni lights in a loose grid, each with a slight noise offset on position |

---

## Files Touched

| File | Change |
|---|---|
| `loom_swift/.../Config/LightingConfig.swift` | New: `LightType`, `LoomLight`, `LightingConfig` |
| `loom_swift/.../Config/LoomLayer.swift` | Add `receivesLighting: Bool` |
| `loom_swift/.../Config/ProjectConfig.swift` | Add `lightingConfig: LightingConfig` |
| `loom_swift/.../Lighting/LightMapRenderer.swift` | New: CoreImage light map computation |
| `loom_swift/.../Scene/SpriteScene.swift` | Add cache fields; modify `renderLayered` |
| `loom_swift/.../LoomEngine.swift` | Call `invalidateLightMap()` in `seek(toFrame:)` |
| `Loom_Swift_Integration/.../Tabs/LightsTabView.swift` | New: Lights tab |
| `Loom_Swift_Integration/.../Inspector/LayersInspector.swift` | Add Lighting toggle |
| Canvas overlay | Proxy wireframe drawing for lights |
| `help.html` | Document lighting system |

---

## Implementation Order

1. **Engine data model** — `LightingConfig.swift`, `LoomLight`, `LightType`; add
   `lightingConfig` to `ProjectConfig` and `receivesLighting` to `LoomLayer`.
   Build check + confirm JSON round-trip.

2. **Light map renderer** — `LightMapRenderer.swift`; Omni type only initially.
   Unit test: render a single white omni at canvas centre and confirm gradient shape.

3. **SpriteScene integration** — add cache; call `LightMapRenderer` from `renderLayered`;
   apply multiply blend. Smoke test: one omni light, one lit layer, confirm vignette.

4. **Spot and Area types** — add to `LightMapRenderer`. Smoke test each type.

5. **Lights tab** — list + add/delete + master toggle. Inspector: position and intensity
   only for the first pass.

6. **Full inspector** — type-specific params + driver buttons for all fields.

7. **Proxy wireframe** — draw overlay for each light type in canvas view.

8. **Layers inspector** — `receivesLighting` toggle.

9. **Driver wiring** — verify all `DoubleDriver` fields evaluate correctly in animation.

10. **Help documentation**.
