# Spec: Cycle-Name Driver + Per-Variant Image Filenames

**Status:** Planned  
**Scope:** loom_swift engine + Loom_Swift_Integration UI  
**Dependencies:** Existing `NameDriver` / `evaluateName` infrastructure; existing `spriteVariants` shape-driver system; existing image-sprite rendering path

---

## Background

Loom sprites can currently be driven by several keyframe-based animation drivers
(position, scale, rotation, morph, opacity, shape index, subdivision set,
renderer set). The renderer-set driver (`TransformDrivers.rendererSet: NameDriver`)
already demonstrates the pattern for switching a named resource at runtime via
keyframes. This spec adds two closely related features using the same pattern:

1. **Cycle-name driver** — keyframe-switch the active `SpriteCycle` assigned to a
   sprite, enabling smooth transitions between e.g. a walk cycle and a run cycle
   within a single timeline.

2. **Per-variant image filenames** — each entry in a sprite's `spriteVariants` list
   can optionally carry its own `imageFilename`, so that when the shape driver
   selects variant N the corresponding image is displayed, mirroring how cycle
   states already associate images with time-indexed states.

These two features are independent and can be implemented separately, but are
specced together because they serve the same broad goal: richer, more
convincing multi-state animation without requiring separate sprites.

---

## Feature 1 — Cycle-Name Driver

### Motivation

A character may have multiple named cycles (walk, run, idle, jump). Currently
`SpriteDef.cycleName` is a static string — the cycle is fixed for the life of
the sprite. To switch cycles mid-animation the user must either use separate
sprites with parent-child switching, or hand-craft cycle blending by other
means. A `cycleNameDriver: NameDriver` field evaluates keyframes at runtime and
overrides `cycleName` each frame, enabling frame-accurate cycle transitions
driven by the main keyframe timeline.

### Data model change

**`TransformDrivers`** (`loom_swift/Sources/LoomEngine/Animation/TransformDrivers.swift`):

```swift
/// Overrides which SpriteCycle runs on this sprite each frame.
/// Disabled (default) leaves the static cycleName assignment in effect.
public var cycleName: NameDriver = .disabled
```

Add to `init`, `CodingKeys`, and `init(from:)` with `decodeIfPresent` default
`.disabled` (backward-compatible — existing projects load without the field).

### Engine change

**`SpriteScene.renderInstance`** (`loom_swift/.../Scene/SpriteScene.swift`):

After the existing renderer-set driver override block (around line 950), add:

```swift
if let drv = activeInstance.def.animation.drivers?.cycleName, drv.enabled,
   let name = DriverEvaluator.evaluateName(drv, globalElapsed: elapsedFrames,
                                           spriteIndex: spriteIndex),
   let overrideCycle = allCycles[name] {
    // Re-enter the cycle rendering path with the overridden cycle.
    renderCycleInstance(activeInstance, spriteIndex: spriteIndex,
                        parentWorld: parentWorld, cycle: overrideCycle, ...)
    return
}
```

The existing `renderCycleInstance` / `renderSVGInstance` paths handle image vs.
geometry dispatch, so no new rendering code is needed — only the cycle lookup is
overridden.

For `applyTransform` (polygon rendering path), the same guard applies: if
`cycleNameDriver` produces a name, the instance uses that cycle's state
geometry rather than the base polygons.

### Inspector UI

In the sprite animation section (alongside the existing renderer-set driver
row), add:

- **Cycle driver** section header with enabled checkbox and keyframe indicator
- Keyframe list showing frame → cycle name pairs
- Cycle name picker (dropdown of all named cycles in the project)
- "Add keyframe" button

The timeline shows a new lane `Cycle` beneath the existing `Renderer Set` lane
when the driver is enabled.

### Behaviour rules

- When `cycleNameDriver` is disabled (default), `SpriteDef.cycleName` is used
  unchanged — no behaviour change for existing projects.
- When enabled, the driver value at the current frame completely overrides
  `cycleName`. The cycle's own internal `drawCycle` counter continues to
  advance normally; switching cycles resets neither the cycle counter nor any
  other sprite state.
- If the driver evaluates to a name that does not match any cycle in the
  project, the sprite falls back to its static `cycleName` for that frame.
- `evaluateName` uses step evaluation (last keyframe at-or-before current
  frame), matching the existing renderer-set driver semantics — no
  interpolation between cycle names.

---

## Feature 2 — Per-Variant Image Filenames

### Motivation

The shape driver selects between a base sprite and N named variant sprites,
each with its own geometry and renderer set. Image sprites (`svgFilename`) are
currently an all-or-nothing property of the whole `SpriteDef`. The extension:
each variant entry can carry an optional `imageFilename` so that the shape
driver controls both geometry/renderer switching and image switching in a single
unified index. Useful when some states of a sprite are Loom geometry and others
are imported bitmaps or SVGs, or when each variant represents a distinctly
different image (e.g. costume or expression swap).

### Data model change

**`SpriteDef`** (`loom_swift/Sources/LoomEngine/Config/SpriteConfig.swift`):

Currently:
```swift
public var spriteVariants: [String] = []   // list of sibling sprite names
```

Replace with a lightweight struct that preserves the existing name field and
adds an optional image:

```swift
public struct SpriteVariantEntry: Codable, Equatable, Sendable {
    public var spriteName:     String
    public var imageFilename:  String?   // nil = use variant's geometry/renderer

    public init(spriteName: String, imageFilename: String? = nil) {
        self.spriteName    = spriteName
        self.imageFilename = imageFilename
    }

    // Backward-compatible decoder: plain String becomes SpriteVariantEntry
    // with imageFilename = nil.
    public init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer(), let s = try? c.decode(String.self) {
            spriteName = s; imageFilename = nil; return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spriteName    = try c.decode(String.self, forKey: .spriteName)
        imageFilename = try c.decodeIfPresent(String.self, forKey: .imageFilename)
    }
}

public var spriteVariants: [SpriteVariantEntry] = []
```

The backward-compatible decoder ensures existing project files (which store
`spriteVariants` as a plain `[String]`) continue to load correctly, with
`imageFilename` defaulting to `nil` for all existing variants.

### Engine change

**`SpriteInstance`** already loads variant polygons and renderer sets into
`variantPolygons` and `variantRendererSets` at initialisation time. Extend to
also load variant image filenames:

```swift
var variantImageFilenames: [String?] = []
```

Populated during `SpriteInstance` init alongside the existing variant loop:
```swift
variantImageFilenames = sprite.spriteVariants.map { $0.imageFilename }
```

**`renderInstance`**: after shape-driver index selection:
```swift
if shapeIdx > 0, shapeIdx - 1 < instance.variantImageFilenames.count,
   let imgName = instance.variantImageFilenames[shapeIdx - 1] {
    // Render as image sprite using imgName, same path as def.svgFilename.
    renderImageSprite(activeInstance, filename: imgName, ...)
    return
}
```

The existing `renderSVGInstance` / image rendering path is reused unchanged —
only the filename source differs.

### Image loading

Variant images are loaded from the same directory as `def.svgFilename` images
(`svgs/sprites/` relative to the project folder). No new loading infrastructure
is needed.

> **Deferred:** `LoomEngine.loadSVGImages` currently loads every file in
> `svgs/sprites/` unconditionally, regardless of whether any sprite references
> it. This is fine for small projects but becomes a startup-time and memory
> problem as the folder grows. When that becomes noticeable, refactor the loader
> to build a reference set by scanning all `svgFilename`, cycle-state image, and
> variant image fields first, then load only those filenames. That change belongs
> together with any future selective-loading work — not as a separate patch.

### Inspector UI

In the sprite variants list (shape driver section of the sprite inspector), each
variant row gains:

- A small image-file picker button (folder icon) showing the current
  `imageFilename` or "—" when unset
- Clearing the filename reverts that variant to geometry rendering

The base sprite (index 0) already has the top-level `imageFilename` / `svgFilename`
field in the inspector — no change needed there.

### Behaviour rules

- A variant with `imageFilename = nil` renders its geometry + renderer set as
  today — no change.
- A variant with `imageFilename` set renders the image instead, bypassing the
  polygon pipeline for that index, exactly as `def.svgFilename` does for the
  whole sprite.
- Geometry and image variants can be freely mixed across indices of the same
  sprite (e.g. index 0 = geometry walk, index 1 = bitmap imported pose).
- If the file named by `imageFilename` is not found, the variant falls back to
  its geometry silently (no crash).

---

## Interaction between the two features

Both features are independent and compose naturally:

- A sprite can have a `cycleNameDriver` that switches between a walk cycle
  (image-based states) and a run cycle (geometry-based states).
- A sprite can have variant entries where index 0 is a geometry idle pose and
  index 1 is a bitmap jump image, with the shape driver switching between them.
- Both can be active simultaneously on the same sprite.

---

## Implementation order

1. **Cycle-name driver** — smaller change; touches `TransformDrivers`, engine
   `renderInstance`, inspector, and timeline lane. No data migration needed.

2. **Per-variant image filenames** — slightly larger due to the `SpriteVariantEntry`
   struct replacing the plain `[String]` array, but the backward-compatible
   decoder removes migration risk.

---

## Files touched

| File | Change |
|---|---|
| `loom_swift/.../Animation/TransformDrivers.swift` | Add `cycleName: NameDriver` |
| `loom_swift/.../Config/SpriteConfig.swift` | Add `SpriteVariantEntry`; replace `[String]` with `[SpriteVariantEntry]` |
| `loom_swift/.../Scene/SpriteScene.swift` | Cycle-name override in `renderInstance`; variant image dispatch; load `variantImageFilenames` |
| `Loom_Swift_Integration/.../Inspector/SpritesInspector.swift` | Cycle driver UI; image picker on variant rows |
| `Loom_Swift_Integration/.../Timeline/TimelinePanel.swift` | Cycle driver lane |
| `Loom_Swift_Integration/.../Resources/help.html` | Document both features |
