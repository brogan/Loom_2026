# Loom Engine — Subdivision System
**Specification 02**  
**Date:** 2026-04-18  
**Depends on:** `01_technical_overview.md`

---

## 1. Purpose

This document specifies the subdivision system — the computational core of Loom. It covers:

- The parameter model (`SubdivisionParams`, `SubdivisionParamsSet`, `SubdivisionParamsSetCollection`)
- The dispatch mechanism (`Subdivision`)
- Every subdivision algorithm (QUAD, TRI, ECHO, BORD variants, SPLIT variants)
- The post-subdivision transform system (five transform types)
- Visibility rules
- XML configuration format
- Design assessment and recommendations for improvement

---

## 2. Conceptual Overview

Subdivision in Loom is a process of **recursive polygon decomposition**. A source polygon is split into a set of child polygons. Each child can itself be subdivided in a subsequent generation, with potentially different parameters. After enough generations the result is a richly textured mesh of small polygons — the raw material for Loom's rendering system.

The key properties of the system are:

- **Spline-native:** The fundamental polygon type is a cubic Bézier spline. Every algorithm works directly on anchor and control point geometry, producing smooth curved output rather than flat-faced meshes.
- **Generation-based:** Parameters are organised into generations (a `SubdivisionParamsSet` is a list of `SubdivisionParams`, one per generation). The output of generation *n* is the input to generation *n+1*.
- **Stochastic:** Randomisation can be applied at multiple levels — centre point jitter, visibility filtering, whole-polygon placement, per-point displacement. This is what gives Loom its organic character.
- **Composable transforms:** After subdivision, five categories of point transform can be applied independently to different parts of the resulting geometry.

---

## 3. Data Model

### 3.1 SubdivisionParams

One `SubdivisionParams` object configures one generation of subdivision. It is identified by a name string.

#### Algorithm selection

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `subdivisionType` | `Int` | `QUAD` | Selects the algorithm (see §5) |
| `lineRatios` | `Vector2D` | `(0.5, 0.5)` | Edge interpolation positions. x = ratio on even-indexed edges; y = ratio on odd-indexed edges |
| `controlPointRatios` | `Vector2D` | `(0.25, 0.75)` | Bézier control point positions along new internal lines |
| `continuous` | `Boolean` | `true` | When `lineRatios.x ≠ lineRatios.y`, ensures matching mid-points on adjacent edges to produce a seamless mesh |
| `insetTransform` | `Transform2D` | scale `(0.5, 0.5)` | Translation, scale, rotation applied to echo and BORD insets |

#### Randomisation

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ranMiddle` | `Boolean` | `false` | Randomise the centre point before subdivision |
| `ranDiv` | `Double` | `100` | Divisor controlling centre-point jitter magnitude. Lower = more randomisation |

#### Visibility

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `visibilityRule` | `Int` | `ALL` | Which child polygons are made visible after subdivision (see §7) |

#### Whole-polygon transform

Applied to entire child polygons (translate/scale/rotate each polygon as a unit):

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `polysTransform` | `Boolean` | `true` | Master enable for any polygon transforms |
| `polysTranformWhole` | `Boolean` | `false` | Enable whole-polygon transform |
| `pTW_probability` | `Double` | `100` | % chance any given polygon is transformed |
| `pTW_commonCentre` | `Boolean` | `false` | All polygons share one pivot; if false each uses its own centroid |
| `pTW_randomCentreDivisor` | `Double` | `100` | Randomises pivot between polygon centroid and this divisor |
| `pTW_transform` | `Transform2D` | — | Fixed translate/scale/rotate |
| `pTW_randomTranslation` | `Boolean` | `false` | Replace fixed translation with random value |
| `pTW_randomTranslationRange` | `RangeXY` | — | X and Y translation ranges |
| `pTW_randomScale` | `Boolean` | `false` | Replace fixed scale with random value |
| `pTW_randomScaleRange` | `RangeXY` | — | X and Y scale ranges |
| `pTW_randomRotation` | `Boolean` | `false` | Replace fixed rotation with random value |
| `pTW_randomRotationRange` | `Range` | — | Rotation range (min, max degrees) |

#### Per-point transform

Applied to selected point categories within child polygons:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `polysTransformPoints` | `Boolean` | `false` | Enable per-point transforms |
| `pTP_probability` | `Double` | `100` | % chance any given polygon has its points transformed |
| `transformSet` | `ArrayBuffer[Transform]` | 5 entries | The five transform types (see §6) |

---

### 3.2 SubdivisionParamsSet

A named, ordered list of `SubdivisionParams` — one entry per subdivision generation.

```
SubdivisionParamsSet("mySet")
  [0] SubdivisionParams("gen1")  → QUAD, lineRatios(0.5, 0.5)
  [1] SubdivisionParams("gen2")  → TRI, visibilityRule ALTERNATE_ODD
  [2] SubdivisionParams("gen3")  → ECHO, insetTransform scale(0.7, 0.7)
```

The set is associated with a `Shape2D`. When `Shape2D.recursiveSubdivide()` is called, it iterates this list and applies each params object in order.

---

### 3.3 SubdivisionParamsSetCollection

A `ListBuffer[SubdivisionParamsSet]` — the full library of subdivision configurations for a sketch, loaded from XML. Accessed by name.

---

## 4. Execution Pipeline

```
Shape2D.recursiveSubdivide(params: List[SubdivisionParams])
│
├── Separate bypass polygons (open curves, points, ovals) — not subdivided
│
├── for each SubdivisionParams in list:
│   │
│   ├── Shape2D.subdivide(subP)
│   │   └── for each Polygon2D:
│   │       └── Polygon2D.subdivide(subP)
│   │           └── Subdivision.subdivide(subP, polyType)
│   │               ├── Calculate centre (with optional ranMiddle jitter)
│   │               ├── Dispatch to algorithm (QUAD/TRI/ECHO/etc.)
│   │               │   └── Returns List[Polygon2D]
│   │               ├── Apply visibility rule
│   │               ├── Apply whole-polygon transform (if enabled)
│   │               └── Apply per-point transforms (if enabled)
│   │
│   └── Filter: keep only visible polygons → feed into next generation
│
└── Recombine subdivided polygons with bypass polygons
    → new Shape2D
```

**Key invariant:** Each generation receives only the *visible* polygons from the previous generation as its input. Invisible polygons are pruned from the pipeline at each step. This is what makes visibility rules compositionally powerful — `ALTERNATE_ODD` in generation 1 followed by `ALTERNATE_ODD` in generation 2 produces a quarter-density result.

---

## 5. Subdivision Algorithms

### 5.1 Polygon Representation

All algorithms operate on **cubic Bézier spline polygons**. A polygon with *N* sides is stored as a flat list of 4N points:

```
Side 0:  [A₀, C₀₁, C₀₂, A₁]
Side 1:  [A₁, C₁₁, C₁₂, A₂]
…
Side N-1:[Aₙ₋₁, Cₙ₋₁₁, Cₙ₋₁₂, A₀]
```

where `Aᵢ` are anchor points and `Cᵢ₁`, `Cᵢ₂` are the two Bézier control points for the segment connecting `Aᵢ` to `Aᵢ₊₁`.

The **centre point** for an N-sided polygon is computed from anchor points only (indices 0, 4, 8, … in the flat list), ignoring control points.

---

### 5.2 QUAD

**What it produces:** N quadrilateral child polygons from an N-sided parent. Each child shares one outer edge of the parent and converges on the parent's centre.

**Conceptual result:** A pinwheel or pie-slice decomposition. For a square parent, four squares. For a hexagon, six quads.

**Algorithm:**

1. **Split each outer edge** at parameter `lineRatios.x` (even edges) or `lineRatios.y` (odd edges) using de Casteljau subdivision. Each outer edge becomes two half-edges, with appropriately scaled control points. The split point `M` is the new anchor shared between the two halves.

2. **Compute internal edges** from each split point `M` to the polygon centre `C`. Control points are placed at `lerp(M, C, controlPointRatios.x)` and `lerp(M, C, controlPointRatios.y)`.

3. **Assemble each quad** from four sides:
   - Side 0: second half of outer edge `i`
   - Side 1: internal edge from split point `i` to centre
   - Side 2: reversed internal edge from centre to split point `i-1`
   - Side 3: first half of outer edge `i-1`

**Output:** N polygons, each 4 sides (16 points). `sidesTotal = 4`.

**Split parameter note:** When `lineRatios.x = lineRatios.y = 0.5` (default), all outer edges are split at their midpoints and all quads are symmetrical. Asymmetric ratios (e.g. 0.3 / 0.7) produce a rotational offset — each quad is skewed in the same direction, creating a spiral character.

---

### 5.3 TRI

**What it produces:** N triangular child polygons from an N-sided parent. Each child shares one complete outer edge of the parent (uncut) and converges on the centre with two internal edges.

**Conceptual result:** A fan or asterisk decomposition. For a triangle parent, three triangles. For a hexagon, six triangles.

**Algorithm:**

1. **Retain outer edges** unchanged (no splitting).

2. **Compute two internal edges** per side — one from `A₀` of that side to centre `C`, one from `A₁` of that side to centre `C`.

3. **Assemble each triangle** from three sides:
   - Side 0: outer edge `i` (unchanged)
   - Side 1: internal edge from `A₀(i)` to centre (forward)
   - Side 2: internal edge from centre to `A₁(i)` (reversed)

**Output:** N polygons, each 3 sides (12 points). `sidesTotal = 3`.

**Note:** `SplineTri` carries a 2022 developer comment questioning whether `centreIndex = 8` is correct for 12-point TRI polygons. It is correct — `CentralAnchors` reads `points(centreIndex-1)` and `points(centreIndex)`, and `makePolys` places the two centre anchor clones at indices 7 and 8 in both QUAD and TRI output. The comment should be removed from the source.

---

### 5.4 ECHO

**What it produces:** 1 inset polygon (a smaller copy of the parent, scaled toward its own centre).

**Conceptual result:** A shrinking concentric copy. Used for matryoshka-style layered shapes or to add an inner polygon to the scene.

**Two modes:**

**`ECHO` (relative centre):**  
Every point `P` is transformed as:  
```
P' = transformAroundOffset(P, insetTransform, centre)
   = centre + (P - centre) × insetTransform.scale  +  insetTransform.translate
```  
Default `insetTransform.scale = (0.5, 0.5)` produces a 50% inset. Rotation can also be applied via `insetTransform.rotation`.

**`ECHO_ABS_CENTER` (absolute centre):**  
Every point `P` is scaled around the origin:  
```
P' = P × insetTransform.scale
```  
This scales toward the absolute (0,0) origin rather than the polygon's own centroid. Produces different behaviour when polygons are offset from centre.

**Output:** 1 polygon with the same number of sides as the parent. `sidesTotal` unchanged.

**Usage note:** ECHO is typically combined with ALL_BUT_LAST or SECOND_HALF visibility — in standard use the *original* polygon and the *inset* are both output; the visibility rule determines which one is passed to the next generation.

---

### 5.5 QUAD_BORD (and QUAD_BORD_ECHO, QUAD_BORD_DOUBLE, QUAD_BORD_DOUBLE_ECHO)

**What it produces:** N "frame" polygons running along the border of the parent — like a picture frame composed of N rectangular segments.

**Conceptual result:** A border or margin decomposition. The interior of the parent is left empty (or filled by ECHO variants).

**Algorithm:**

1. Extract the N outer edges of the parent.
2. Scale the entire parent toward its centre using `insetTransform` → produces an inner polygon.
3. Extract the N inner edges of this inset polygon.
4. For each `i`, assemble one quad from:
   - Outer edge `i` (from original)
   - Right connector from outer end to inner end
   - Reversed inner edge `i` (from inset polygon)
   - Left connector from inner start to outer start
   - Connectors are Bézier segments with control points placed at `controlPointRatios` positions.

**ECHO variant:** Adds the inset polygon itself as an additional output (the "fill").  
**DOUBLE variant:** Two nested border rings.  
**DOUBLE_ECHO variant:** Two rings plus the inner fill.

**Output (QUAD_BORD):** N polygons (4 sides each). No centre polygon.

---

### 5.6 TRI_BORD_A, TRI_BORD_B, TRI_BORD_C (and ECHO variants)

Border decompositions using triangles rather than quads. Three sub-variants exist:

| Type | Triangle arrangement |
|------|---------------------|
| `TRI_BORD_A` | Each outer edge becomes one triangle, with apex at inset polygon edge midpoint |
| `TRI_BORD_B` | Triangles arranged with shared apex at inset polygon corners |
| `TRI_BORD_C` | Alternate triangulation, creates interlocking pattern |

Each `ECHO` variant adds the central inset polygon to the output.

---

### 5.7 TRI_STAR and TRI_STAR_FILL

**What it produces:** N triangles arranged as a star pattern — outer points spike outward from the polygon centre.

`TRI_STAR_FILL` adds a central polygon (the inset) in addition to the N star triangles.

---

### 5.8 SPLIT_VERT, SPLIT_HORIZ, SPLIT_DIAG

**What it produces:** 2 child polygons — the parent split by a line.

**Conceptual result:** Binary subdivision. Repeated application produces a grid or diagonal lattice.

**Algorithm:**

1. **Find best split axis** by examining all candidate split lines and selecting the one closest to the target orientation (vertical / horizontal / diagonal). For even-sided polygons this is a pair of opposite edges; for odd-sided polygons it is a vertex-to-opposite-midpoint line.

2. **Split the two boundary edges** using de Casteljau at `lineRatios`. This produces:
   - Two half-edges on the "top" boundary  
   - Two half-edges on the "bottom" boundary  
   - Two new anchor points (the split midpoints)

3. **Create connector edges** between the two split midpoints (the new shared edge between the two child polygons).

4. **Assemble two polygons:**  
   Child 1: right half of top edge + right sides + left half of bottom edge + connector  
   Child 2: right half of bottom edge + remaining sides + left half of top edge + reversed connector

**Output:** 2 polygons. Each inherits `sidesTotal` from the parent minus 2 plus the connector count.

**Orientation selection note:** The rotation-finding logic is heuristic — it selects the side pair whose midpoint-to-midpoint vector best matches the desired axis. This can produce unexpected results for highly irregular polygons.

---

## 6. Transform System

After subdivision produces child polygons, five categories of per-point transform can be applied. Each is independently enabled, parameterised, and gated by a probability value. They are applied in the order they appear in `transformSet`.

All transforms share the same interface:

```scala
abstract class Transform(val transforming: Boolean) {
  def transform(polys: Array[Polygon2D], centreIndex: Int,
                subdivisionType: Int, sidesTotal: Int,
                numSidesPerPoly: Int): Unit
}
```

The `centreIndex` parameter is the index within the flat point array where the centre-adjacent anchor points are located. Its value depends on the polygon type (16/2 = 8 for QUAD; nominally 4 for TRI — see bug note in §5.3).

---

### 6.1 ExteriorAnchors — Spike / Contract

**Target:** The anchor points on the outer edges of the child polygons (the corners that came from the parent's boundary).

**What it does:** Moves outer anchors toward or away from the polygon's centre, creating spike or contracted effects.

**Key parameters:**

| Parameter | Description |
|-----------|-------------|
| `spikeFactor` | Negative: moves outward (spike). Positive (0–0.99): contracts toward centre |
| `spikeAllExteriorAnchors` | Move all outer anchors; alternatives: corners only, edge-midpoints only |
| `symmetricalSpike` | Both anchors of a pair move equally; alternatives: left only, right only, random |
| `spikeXY / spikeX / spikeY` | Constrain displacement axis |
| `randomSpike` | Replace fixed factor with random value in `randomSpikeFactor` range |
| `cpsFollow` | Adjacent control points follow the anchor displacement |
| `cpsFollowMultiplier` | Amplify control point following (default 2) |
| `cpsSqueeze` | Additionally squeeze control points toward each other |

**Core displacement:**  
`spikedPosition = lerp(anchorPoint, centrePoint, spikeFactor)`  
`displacement = spikedPosition − anchorPoint`

---

### 6.2 CentralAnchors — Tear

**Target:** The anchor points adjacent to the centre of the child polygons (the inner anchors of the internal edges).

**What it does:** Displaces the centre anchors toward an external reference point — "tearing" the polygon away from its centre.

**Key parameters:**

| Parameter | Description |
|-----------|-------------|
| `tearFactor` | Magnitude of displacement (0 = no tear, 1 = at reference) |
| `tearDiagonal / tearLeft / tearRight / ranTearDirection` | Choose which external anchor to tear toward |
| `cpsFollow` | Control points follow centre anchor displacement |
| `allPointsFollowCentre` | All polygon points displace by the same vector as the centre anchor |

---

### 6.3 AnchorsLinkedToCentre — Side Tear

**Target:** The side anchor points on the internal edges (the points connecting outer edge midpoints to the centre).

**What it does:** Displaces these anchors toward a chosen reference — either the outer corner, the opposite corner, or the centre — creating bowing or folding effects along the internal edges.

**Key parameters:**

| Parameter | Description |
|-----------|-------------|
| `tearTowardsOutsideCorner` | Anchors bow toward the nearest outer corner |
| `tearTowardsOppositeCorner` | Anchors bow toward the diametrically opposite corner |
| `tearTowardsCentre` | Anchors bow inward toward the polygon's own centre |
| `randomTearType` | Choose tear direction randomly |
| `tearFactor` | Displacement magnitude (default 0.45) |
| `cpsFollow` | Adjacent control points follow |

---

### 6.4 OuterControlPoints — Curvature

**Target:** The Bézier control points on the outer edges of the child polygons.

**What it does:** Bows the outer edges inward or outward by displacing their control points along a perpendicular vector.

**Key parameters:**

| Parameter | Description |
|-----------|-------------|
| `curveType` | PUFF (outward), PINCH (inward), PUFF_PINCH_* (alternating patterns) |
| `curveMultiplier` | Range controlling the magnitude of the bow |
| `lineSideRatio` | Position of each control point along the outer edge (default 0.33, 0.66) |
| `probability` | % chance any polygon gets this transform applied (default 7%) |
| `curveFromCentre` | Calculate perpendicular vector relative to all-polygon shared centre vs per-polygon centre |

**Core calculation:** The midpoint of the outer edge is found; the vector from the polygon's centre to this midpoint is rotated 90° to obtain the perpendicular displacement direction. Control points are positioned at `lineSideRatio` positions and then offset by `perpendicularVector × curveMultiplier`.

---

### 6.5 InnerControlPoints — Internal Curvature

**Target:** The Bézier control points on the internal edges (the edges running from outer anchors to the centre).

**What it does:** Curves the internal lines, affecting how the polygon bulges between its outer boundary and its centre.

Two modes depending on subdivision type:

**QUAD mode:**

| Parameter | Description |
|-----------|-------------|
| `referToOuter` | Reference to outer control point positions |
| `followOuter` | Inner CPs mirror the outer curvature (opposite vectors — creates consistent bulge) |
| `exaggerateOuter` | 45° exaggeration relative to outer |
| `counterOuter` | Counter-direction to outer (pinch where outer puffs) |
| `outerMultiplier / innerMultiplier` | Amplification factors |

**TRI mode:**

| Parameter | Description |
|-----------|-------------|
| `outerRatio` | Position of outer control points (±0.5 from the internal line, default 1.1) |
| `innerRatio` | Position of inner control points (default −0.15) |
| `commonLine` | Both CPs lie on the same line (true = straight internal edges, false = S-curves) |
| `randomRatio` | Randomise placement |
| `evenCommon / oddCommon / ranCommon` | Apply commonLine selectively |

---

## 7. Visibility Rules

After subdivision produces child polygons, a visibility rule determines which ones are passed forward to the next generation (and ultimately to the renderer).

| Constant | Value | Behaviour |
|----------|-------|-----------|
| `ALL` | 0 | All polygons visible |
| `QUADS` | 1 | Only polygons with `sidesTotal = 4` |
| `TRIS` | 2 | Only polygons with `sidesTotal = 3` |
| `ALL_BUT_LAST` | 3 | All except the final polygon |
| `ALTERNATE_ODD` | 4 | Every odd-indexed polygon (1, 3, 5, …) |
| `ALTERNATE_EVEN` | 5 | Every even-indexed polygon (0, 2, 4, …) |
| `FIRST_HALF` | 6 | First ⌊N/2⌋ polygons |
| `SECOND_HALF` | 7 | Last ⌈N/2⌉ polygons |
| `EVERY_THIRD` | 8 | Indices divisible by 3 |
| `EVERY_FOURTH` | 9 | Indices divisible by 4 |
| `EVERY_FIFTH` | 10 | Indices divisible by 5 |
| `RANDOM_1_2` | 11 | 1-in-2 probability |
| `RANDOM_1_3` | 12 | 1-in-3 probability |
| `RANDOM_1_5` | 13 | 1-in-5 probability |
| `RANDOM_1_7` | 14 | 1-in-7 probability |
| `RANDOM_1_10` | 15 | 1-in-10 probability |

**Compositional effect:** The pruning happens *between* generations. Applying `ALTERNATE_ODD` at generation 1 and `ALTERNATE_ODD` again at generation 2 leaves approximately 25% of the generation-2 polygons. Applying `RANDOM_1_3` three generations in a row leaves approximately 1 in 27 polygons — this is the primary mechanism for producing sparse, cloud-like distributions.

**Note on random rules:** Because random visibility is evaluated at subdivision time (not lazily), the result is non-reproducible between runs unless a seed is fixed. This is intentional — the stochastic variation is part of the aesthetic — but makes exact reproduction impossible without a seeded random source.

---

## 8. XML Configuration Format

Subdivision parameters are loaded by `PolygonConfigLoader`. The XML structure follows an element-per-field pattern:

```xml
<SubdivisionParamsSetCollection>
  <SubdivisionParamsSet name="mySet">

    <SubdivisionParams name="gen1">
      <SubdivisionType>QUAD</SubdivisionType>
      <LineRatios x="0.5" y="0.5"/>
      <ControlPointRatios x="0.25" y="0.75"/>
      <Continuous>true</Continuous>
      <RanMiddle>false</RanMiddle>
      <RanDiv>100</RanDiv>
      <VisibilityRule>ALL</VisibilityRule>

      <PolysTransform>true</PolysTransform>
      <PolysTranformWhole>false</PolysTranformWhole>
      <!-- ... whole-polygon transform fields -->

      <PolysTransformPoints>false</PolysTransformPoints>
      <!-- ... per-point transform fields -->
    </SubdivisionParams>

    <SubdivisionParams name="gen2">
      <!-- ... -->
    </SubdivisionParams>

  </SubdivisionParamsSet>
</SubdivisionParamsSetCollection>
```

**Polygon source format** (produced by Bezier Draw, consumed by `PolygonSetLoader`):

```xml
<polygonSet>
  <polygon isClosed="true">
    <curve>                         <!-- one cubic Bézier segment -->
      <point x="0.5" y="0.0"/>     <!-- anchor start -->
      <point x="0.25" y="0.43"/>   <!-- control point 1 -->
      <point x="0.75" y="0.43"/>   <!-- control point 2 -->
      <point x="0.0" y="0.0"/>     <!-- anchor end -->
    </curve>
    <curve>
      <!-- next segment ... -->
    </curve>
  </polygon>
</polygonSet>
```

All coordinates are normalised to [0, 1] space. The engine scales them to canvas dimensions at load time.

---

## 9. Known Bugs

### 9.1 TRI centreIndex — Resolved Non-Issue

`SplineTri` carries a developer comment from 2022 questioning whether `centreIndex = 8` is correct for 12-point TRI polygons. After tracing through the actual transform code this is confirmed **correct**.

`CentralAnchors.getCentreAnchors()` reads `points(centreIndex-1)` and `points(centreIndex)`. In a TRI polygon, `makePolys` places the two centre anchor clones at indices 7 and 8 respectively — so `centreIndex = 8` correctly identifies them for both QUAD (16 points) and TRI (12 points).

The misleading comment should be removed from `SplineTri.scala` to avoid future confusion.

---

## 10. Design Assessment

### 10.1 What Works Well

**Algorithmic expressiveness:** The combination of algorithm selection, lineRatios, and three levels of stochastic control (centre jitter, whole-polygon transform probability, per-point transform probability) yields a very wide range of visual outputs from a small parameter space. This is the core of what makes Loom distinctive.

**Separation of algorithm from dispatch:** The individual algorithm classes (`SplineQuad`, `SplineTri`, etc.) are stateless and self-contained. The dispatch in `Subdivision.subdivide()` is clean. Adding a new algorithm requires only a new class and one new case in the dispatch match.

**Generation pipeline:** The prune-then-recurse approach (only visible polygons continue to the next generation) is elegant. It makes visibility rules compositionally powerful at minimal implementation cost.

**Transform composability:** Having five independent, probability-gated transform types means a designer can apply partial effects (e.g., spike only 20% of exterior anchors while curving 100% of outer control points) without the transforms conflicting.

---

### 10.2 Problems and Improvement Opportunities

#### P1 — Int constants instead of enums

`subdivisionType`, `visibilityRule`, renderer modes, and polygon types are all bare `Int` constants on companion objects. There is no compile-time check that a value is a valid `subdivisionType`; passing `17` where a `visibilityRule` is expected compiles silently.

**Recommendation:** Replace with Scala 3 enums. In Swift, these map directly to Swift enums — this change should be made in the Scala version to document intent before migration.

```scala
enum SubdivisionType:
  case Quad, QuadBord, QuadBordEcho, Tri, TriBordA, Echo, EchoAbsCenter, SplitVert, ...

enum VisibilityRule:
  case All, Quads, Tris, AllButLast, AlternateOdd, AlternateEven,
       FirstHalf, SecondHalf, EveryThird, EveryFourth, EveryFifth,
       Random1in2, Random1in3, Random1in5, Random1in7, Random1in10
```

---

#### P2 — In-place coordinate mutation

Every transform modifies `Vector2D` coordinates in-place. There is no concept of an "original" polygon and a "transformed" polygon — the transform is destructive. This has two consequences:

1. **Non-reproducibility between generations:** The output of generation 1 is immediately overwritten by the transforms. If you want to compare generation 1 before and after transforms for debugging, you cannot without adding explicit clone calls.

2. **No parallelism:** In-place mutation of shared point objects means subdivision cannot safely be parallelised across polygons. This is the primary performance ceiling for dense subdivisions.

**Recommendation for Swift:** Make `Vector2D` and `Polygon` value types (structs). Swift's copy-on-write semantics mean unused copies are not allocated. This opens subdivision to parallel execution via `DispatchQueue.concurrentPerform` or Swift Concurrency `async/await` task groups.

---

#### P3 — Stochastic non-reproducibility

Random visibility rules, random centre jitter, and random whole-polygon transforms all draw from a global `Randomise` utility with no seed. Two runs of the same project with the same parameters produce different output.

This is partly intentional (the variation is aesthetic), but it means:
- Still captures are non-reproducible
- Debugging a specific visual outcome is impossible
- The parameter editor preview does not match the engine output reliably

**Recommendation:** Accept a seed value in `SubdivisionParams` (or at the sketch level). Default to unseeded for live animation; support a fixed seed for export/capture. In Swift, use a `RandomNumberGenerator` protocol to inject the source — seeded or not.

---

#### P4 — centreIndex fragility

`centreIndex` is computed from polygon point count and passed down through the transform system as a raw integer. It assumes a specific layout (QUAD = 8, TRI = 4) that is not enforced. The TRI bug (§9.1) is a symptom of this brittleness.

**Recommendation:** Replace `centreIndex` with a structured polygon descriptor that explicitly identifies which indices are exterior anchors, centre anchors, outer control points, and inner control points. In Swift, this maps naturally to an enum-indexed struct:

```swift
struct PolygonGeometry {
    let points: [Vector2D]
    let sidesTotal: Int
    let exteriorAnchorIndices: [Int]
    let centreAnchorIndices: [Int]
    let outerControlIndices: [Int]
    let innerControlIndices: [Int]
}
```

---

#### P5 — Subdivision result polygon count is partially implicit

`Shape2D.subdivide()` contains conditional logic to determine how many output polygons to allocate per input polygon (N for QUAD/TRI, 2 for SPLIT, N+1 for BORD_ECHO, etc.). This logic is not co-located with the algorithms; it must be kept manually in sync with them.

**Recommendation:** Each algorithm class should declare its own output count formula:

```swift
protocol SubdivisionAlgorithm {
    func outputCount(sidesTotal: Int) -> Int
    func subdivide(polygon: Polygon, params: SubdivisionParams) -> [Polygon]
}
```

---

#### P6 — `println` diagnostics in the subdivision hot path

`Shape2D.recursiveSubdivide()` prints subdivision type and polygon counts on every call. For a scene with many sprites updating at 10 FPS this generates enormous console output and consumes measurable time.

**Recommendation:** Remove or gate behind a debug flag.

---

#### P7 — No caching of subdivision results

Subdivision is deterministic given the same input polygon and the same `SubdivisionParams` (when `ranMiddle = false` and no stochastic transforms are enabled). Yet the full subdivision pipeline is re-executed on every frame for animated sprites, even when no parameters have changed.

**Recommendation:** Cache `(polygonHash, paramsHash) → List[Polygon2D]` for the deterministic case. Only invalidate on parameter change or when stochastic transforms are active. This would be the single highest-impact performance improvement for complex scenes. In Swift, implement as a keyed cache in the `SubdivisionEngine` with explicit invalidation.

---

#### P8 — `lineRatios` and `continuous` coupling is non-obvious

The `continuous` flag is only meaningful when `lineRatios.x ≠ lineRatios.y`. When they are equal, `continuous` has no effect. This implicit dependency is not documented anywhere in the parameter class.

**Recommendation:** Document this explicitly. In Swift, consider making this a computed property:
```swift
var isContinuous: Bool { lineRatios.x != lineRatios.y && continuous }
```

---

## 11. Swift Migration Notes

### 11.1 Direct Translations

| Scala | Swift | Notes |
|-------|-------|-------|
| `SubdivisionParams` class | `SubdivisionParams` struct | Fields become stored properties |
| `SubdivisionParamsSet` | `[SubdivisionParams]` with a name | Named array |
| `Subdivision` companion object | `enum SubdivisionType` + `SubdivisionEngine` struct | Split constants from logic |
| `SplineQuad`, `SplineTri`, etc. | Conforming types of `SubdivisionAlgorithm` protocol | |
| `Transform` abstract class | `SubdivisionTransform` protocol | |
| `Polygon2D.subdivide()` | `SubdivisionEngine.subdivide(polygon:params:)` free function | Remove from geometry type |
| `Shape2D.recursiveSubdivide()` | `SubdivisionPipeline.process(shape:paramSet:)` | |

### 11.2 Key Design Changes for Swift

1. **Make geometry value types:** `Vector2D` and `Polygon` as structs. This eliminates in-place mutation and enables parallelism.

2. **Algorithm protocol:** All 20 algorithm classes conform to `SubdivisionAlgorithm`. The dispatch `switch` in `Subdivision.subdivide()` becomes a method call on the protocol type, removing the need for centralised dispatch.

3. **Introduce seeded randomness:** Thread `RandomNumberGenerator` through the subdivision pipeline.

4. **Add result caching:** `SubdivisionCache` keyed by polygon content hash + params hash. Cache entries are immutable (structs) and safe to access from multiple threads.

5. **Structured point roles:** Replace `centreIndex: Int` with `PolygonGeometry` struct (see P4 above).

6. **Parallel subdivision:** With value types and no shared mutable state, `polygons.concurrentMap { subdivide($0, params) }` is safe and straightforward.

---

## 12. Algorithm Reference Summary

| Constant | Output count | Output type | Centre used |
|----------|-------------|-------------|-------------|
| `QUAD` | N | 4-sided (16 pts) | Yes |
| `QUAD_BORD` | N | 4-sided border | No (inset) |
| `QUAD_BORD_ECHO` | N + 1 | N border + 1 inset | No |
| `QUAD_BORD_DOUBLE` | 2N | Two border rings | No |
| `QUAD_BORD_DOUBLE_ECHO` | 2N + 1 | Two rings + inset | No |
| `TRI` | N | 3-sided (12 pts) | Yes |
| `TRI_BORD_A` | N | 3-sided border A | No (inset) |
| `TRI_BORD_A_ECHO` | N + 1 | Border A + inset | No |
| `TRI_BORD_B` | N | 3-sided border B | No (inset) |
| `TRI_BORD_B_ECHO` | N + 1 | Border B + inset | No |
| `TRI_BORD_C` | N | 3-sided border C | No (inset) |
| `TRI_BORD_C_ECHO` | N + 1 | Border C + inset | No |
| `TRI_STAR` | N | Star triangles | Yes |
| `TRI_STAR_FILL` | N + 1 | Star + inset | Yes |
| `SPLIT_VERT` | 2 | Two halves | No |
| `SPLIT_HORIZ` | 2 | Two halves | No |
| `SPLIT_DIAG` | 2 | Two halves | No |
| `ECHO` | 1 | Inset (relative) | Yes |
| `ECHO_ABS_CENTER` | 1 | Inset (absolute) | No |
