# Spec: Per-Layer Redraw Modes

**Status:** Implemented  
**Scope:** loom_swift engine + Loom_Swift_Integration UI  
**Dependencies:** Existing `LoomLayer` / `renderLayered` compositing infrastructure

---

## Background

The current global `drawBackgroundOnce` setting causes the entire canvas to
accumulate — every sprite on every layer fades together. There is no way to
have a sharp, fully-redrawn foreground over a softly accumulating midground
over a static background within a single project.

This spec adds a `redrawMode` property to `LoomLayer` that controls how each
layer's offscreen buffer is handled between frames:

| Mode | Buffer behaviour | Use case |
|---|---|---|
| **Full** | Cleared and redrawn every frame | Animated foreground, any layer that must be sharp |
| **Once** | Drawn on the first frame; never redrawn | Fully static background plates |
| **Accumulate** | Faded toward background, then new frame rendered on top | Ghost trails, motion blur, soft midground accumulation |

The motivating composition is: static background (`.once`) + softly
accumulating midground (`.accumulate(fade: 0.03)`) + sharp animated
foreground (`.full`). Each layer is fully independent; no global redraw
mode is needed.

---

## Data Model

### `LayerRedrawMode` — new enum

**File:** `loom_swift/Sources/LoomEngine/Config/LoomLayer.swift`

```swift
public enum LayerRedrawMode: String, Codable, Sendable, CaseIterable {
    case full        // clear and redraw every frame (default)
    case once        // draw once on frame 0, hold permanently
    case accumulate  // fade previous content, draw new frame on top
}
```

### `LoomLayer` additions

```swift
public var redrawMode:     LayerRedrawMode = .full
/// Fraction of old content preserved each frame in accumulate mode.
/// 0.0 = instant full clear; 1.0 = nothing fades (no accumulation).
/// Typical useful range: 0.90–0.99.
public var accumulateFade: Double          = 0.95
```

Add to `CodingKeys`, `init`, and `init(from:)` with `decodeIfPresent`
defaults (`.full` and `0.95`). Existing projects load cleanly with
`redrawMode = .full`, which is identical to current behaviour.

**Note on `accumulateFade` semantics:** a value of `0.95` means 95% of
the previous frame's content is retained; the remaining 5% is replaced by
the background colour. At 30 fps, content has a half-life of roughly
0.95^n = 0.5 → ~13 frames (~0.4 seconds). Lower values = faster fade.

---

## Engine Changes

### Persistent layer buffers

**File:** `loom_swift/Sources/LoomEngine/Scene/SpriteScene.swift`

Add a mutable dictionary to `SpriteScene`:

```swift
/// Persistent offscreen buffers for .once and .accumulate layers, keyed by layer UUID.
/// Created on first render; reused across frames. Cleared by invalidateAccumulateBuffers().
var layerBuffers: [UUID: CGContext] = [:]
```

`CGContext` is a class — reference semantics inside the value type are fine
here; the dict holds a stable reference to each context.

### Modified `renderLayered`

Replace the per-layer `makeOffscreenContext` + fresh-render block with
mode-dispatched logic:

```swift
for (layerIndex, layer) in layers.enumerated() {
    guard layer.isVisible else {
        // Discard buffer if layer becomes invisible while in persistent mode.
        if layer.redrawMode != .full { layerBuffers.removeValue(forKey: layer.id) }
        continue
    }

    let lt        = layerViewTransform(viewTransform, parallaxFactor: layer.parallaxFactor)
    let indices   = layerIndices(for: layer)

    switch layer.redrawMode {

    case .full:
        // Existing behaviour — fresh context every frame.
        layerBuffers.removeValue(forKey: layer.id)   // discard any stale buffer
        guard let offscreen = makeOffscreenContext(size: viewTransform.canvasSize)
        else { continue }
        renderSpritesInto(offscreen, indices: indices, lt: lt, ...)
        applyLayerComposite(from: offscreen, ...)

    case .once:
        if layerBuffers[layer.id] == nil {
            guard let offscreen = makeOffscreenContext(size: viewTransform.canvasSize)
            else { continue }
            renderSpritesInto(offscreen, indices: indices, lt: lt, ...)
            layerBuffers[layer.id] = offscreen
        }
        applyLayerComposite(from: layerBuffers[layer.id]!, ...)

    case .accumulate:
        let buffer: CGContext
        if let existing = layerBuffers[layer.id] {
            buffer = existing
        } else {
            guard let fresh = makeOffscreenContext(size: viewTransform.canvasSize)
            else { continue }
            buffer = fresh
            layerBuffers[layer.id] = fresh
        }
        // Fade step: draw a semi-transparent fill over existing content,
        // blending old content toward the background colour.
        let fadeAlpha = 1.0 - layer.accumulateFade   // 0.05 for accumulateFade=0.95
        buffer.saveGState()
        buffer.setFillColor(backgroundColor.copy(alpha: fadeAlpha) ?? .black)
        buffer.fill(CGRect(origin: .zero, size: viewTransform.canvasSize))
        buffer.restoreGState()
        // New frame rendered on top of faded content.
        renderSpritesInto(buffer, indices: indices, lt: lt, ...)
        applyLayerComposite(from: buffer, ...)
    }
}
```

The `backgroundColor: CGColor` parameter is threaded in from `LoomEngine`
(already known there from `config.globalConfig.backgroundColor`). Pass it
into `renderLayered` alongside the existing parameters.

### Buffer invalidation helper

```swift
/// Clears all accumulate-mode layer buffers. Called on seek so that
/// accumulation restarts from the correct frame position.
/// Once-mode buffers are left intact — they are frame-independent.
public mutating func invalidateAccumulateBuffers(layers: [LoomLayer]) {
    for layer in layers where layer.redrawMode == .accumulate {
        layerBuffers.removeValue(forKey: layer.id)
    }
}

/// Clears all persistent layer buffers (accumulate + once).
/// Call when canvas size changes or project is reloaded.
public mutating func invalidateAllLayerBuffers() {
    layerBuffers.removeAll()
}
```

### `LoomEngine.seek` update

**File:** `loom_swift/Sources/LoomEngine/LoomEngine.swift`

In `seek(toFrame:)`, after `accumulationCanvas = nil`, add:

```swift
scene.invalidateAccumulateBuffers(layers: config.layers)
```

This ensures that on timeline scrub, accumulate layers restart their ghost
trail from the seek position rather than carrying forward stale pre-seek
content.

Once-mode layers are intentionally preserved on seek — they represent
static, time-independent content and do not need rebuilding.

---

## Scrubbing Behaviour Summary

| Mode | On seek | Why |
|---|---|---|
| `.full` | N/A — no buffer to manage | Redrawn from scratch every frame anyway |
| `.once` | Buffer preserved | Content is time-independent; never needs rebuilding |
| `.accumulate` | Buffer cleared | Content is path-dependent; must restart from seek position |

The consequence: after seeking into the middle of a timeline, accumulate
layers show no ghost trail on the first rendered frame — the trail builds
up again as playback proceeds. This is correct and expected; it matches
the behaviour of film multiple-exposure effects.

---

## Inspector UI

**File:** `Loom_Swift_Integration/Sources/Loom/Inspector/LayersInspector.swift`

Add a **Redraw** section to the layer inspector, above the existing Opacity
section:

```
┌─ Redraw ──────────────────────────────────────────────┐
│  Mode     [Full ▾]                                      │
│  Fade       ━━━━━━━━━━●━━━━━  0.95   (only when Accum) │
└───────────────────────────────────────────────────────┘
```

- **Mode picker:** `Full` / `Once` / `Accumulate` (maps to `LayerRedrawMode`)
- **Fade slider:** `0.50 – 0.99`, step `0.01`, shown only when mode is
  `Accumulate`. Label "Retain" to make the direction intuitive — higher
  value = more retention = slower fade.

The `accumulateFade` field on `LoomLayer` stores the retain fraction
(0.95 = retain 95%). The slider range excludes extremes (0 = instant
clear = equivalent to `.full`; 1.0 = nothing ever fades = unusable).

---

## Help Documentation

Add a **Redraw Modes** subsection to the Layers section of `help.html`,
covering:
- The three modes and their visual effect
- The `accumulateFade` / Retain slider and its half-life formula
- The scrubbing caveat for accumulate layers
- The three-layer composition pattern (once / accumulate / full) as a
  worked example

Add nav entry and TOC entry alongside the existing Layers subsections.

---

## Files Touched

| File | Change |
|---|---|
| `loom_swift/.../Config/LoomLayer.swift` | Add `LayerRedrawMode` enum; add `redrawMode` and `accumulateFade` fields |
| `loom_swift/.../Scene/SpriteScene.swift` | Add `layerBuffers`; modify `renderLayered`; add `invalidateAccumulateBuffers` / `invalidateAllLayerBuffers` |
| `loom_swift/.../LoomEngine.swift` | Call `invalidateAccumulateBuffers` in `seek(toFrame:)`; pass `backgroundColor` into `renderLayered` |
| `Loom_Swift_Integration/.../Inspector/LayersInspector.swift` | Add Redraw section (mode picker + fade slider) |
| `Loom_Swift_Integration/.../Resources/help.html` | Document redraw modes in Layers section |

---

## Implementation Order

1. `LoomLayer` — data model (enum + fields + decoder). Build check.
2. `SpriteScene` — `layerBuffers` + modified `renderLayered` + invalidation helpers. Build + manual smoke test.
3. `LoomEngine.seek` — invalidate accumulate buffers on seek. 
4. Inspector UI — Redraw section in `LayersInspector`.
5. Help — document in Layers section.
