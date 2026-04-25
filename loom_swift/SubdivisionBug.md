Subdivision Bug

We are working on migrating the Scala Loom Engine to Swift.  There are a number of missing features and bugs in the current Swift implementation.  I want to begin with a bug affecting a very basic feature of the subdivision engine.  It is axiomatic for the Loom system that if a square shape is subject to quad subdivision with default parameters that it should produce a 2X2 grid of 4 smaller squares. It is also axiomatic that if this subdivision is pursued through several recursive stages of quad subdivision that it should produce an increasingly fine grid of squares.

I created a project in Loom Editor (Loom_056) that employs a simple square as the base geometry.  As a sprite, this is then subject to 4 stages of recursive quad subdivision.  This produces correct results up until the 3rd stage of subdivision - then the shape of selected squares becomes noticeably non-square.  The number of non-square shapes increases again in the 4th stage of subdivision.  The Scala version of the Loom Engine produces no such deformations.  Please have a look at the output of the two engines in the renders/stills directory.  There are renderings for each of the four stages of subdivision for both engines (the Swift renders have 'swift' in the file title).  I have also created baked versions of each of the subdivisions (in polygonsSets directory).  THese are the product of calling Scala subdivision algorithms.

Here is the last summary you wrote having failed to solve the bug across more than a whole session of effort:

What was proved this session: testQuad3LevelRectCollinearity passed — every Bézier segment in all 64 level-3 polygons is geometrically straight. The bug is definitively not in
  control point placement.

  What remains unexplained: The large visible S/U curves must come from somewhere else. The three most likely leads for tomorrow:

  1. Polygon winding in the central band — some level-3 quads may be self-intersecting ("butterfly" shaped) due to how connector sub-halves assemble at depth 3. CoreGraphics fills a
   butterfly quad as an X-shape, which looks like an S-curve. Check convexity of the 64 anchor sets, especially the interior ones (the anchor print only covered the 4 corner
  polygons).
  2. Compare anchor coordinates with Scala — the Swift anchors show tiny positional errors (~0.0006 units). If Scala's level-3 anchors are different positions (not just collinear vs
   non-collinear), the assembly logic differs despite appearing correct analytically.
  3. Test_055 runtime params vs hardcoded test params — verify the app's actual loaded subdivision params match what the test assumes.

I'm not convinced by this account.  I don't believe convexity is an issue here.  For a start tere are no curved lines.  It seems more like a miscalculation of anchor vertices.  What remains very unclear is why it only becomes apparent after two stages of subdivision.  The quad parameters for each stage are identical.  Why should conditions suddenly change in the 3rd stage?  I really don't believe it is about the accumulation of tiny numerical irregularities.  There is something more plainly wrong happening.

Rather than just continue with unlikely hypotheses/lines of enquiry, I would like you to take a more deliberate approach:

1.  Compare the two sets of rendered images in Test_056 and identify how the Swift anomalies relate to the Swift subdivision algorithm/recursive process.
1.  Enable me to capture more info.  Baking currently occurs via a call to Scala Loom Engine algorithms.  Change this.  It should be switchable.  When the user selects in the Global tab to render to the Swift engine then baking to should shift to the Swift Loom Engine subdivision algorithms.  This will enable us to capture and assess the Swift calculations alongside the Scala Loom engine calculations.
2.  Confirm to me that the two axioms that I described above are applying.  Is quad subdivision always producing 4 sub squares when applied to an overall square?  And is recursion being applied rigorously with no potential for other parameters to interfere?
3.  Closely compare the Scala implementation to the Swift implmentation.  Are there any relevant points of difference?

_________________________

## Session 3 Findings (2026-04-25)

### 1. What the images reveal

All four Scala renders are perfect grids. Comparing the Swift renders:

- **Level 1** (4 cells): identical to Scala. ✓
- **Level 2** (16 cells): identical to Scala. ✓
- **Level 3** (64 cells): clear distortion. Specific internal column and row dividers are visibly displaced — they bow or kink. The distortion is concentrated in the interior of the grid; the outer boundary cells are nearly correct.
- **Level 4** (256 cells): heavy distortion — and crucially, **the pattern is self-similar**. The level-3 distortion pattern repeats inside every subdivided region at level 4. It is fractal.

**What the fractal/self-similar level-4 pattern proves:**
The bug is applied fresh at every subdivision step. It is not an accumulation of floating-point error (that would produce a smooth gradient of increasing error). Something is computed incorrectly in the subdivision algorithm itself, and that same wrong computation happens every time a polygon is subdivided. Whatever the wrong calculation is, it produces correct-looking output for the first two levels and becomes visible at level 3.

The distortion in level 3 is NOT random — specific cells are wrong while others are right. The affected cells are the interior ones (those whose all four sides are connectors from a previous subdivision step, rather than sub-halves of original edges). This points toward a systematic difference between how "original" sides and "connector" sides are handled.

### 2. Configuration of Test_056

The square polygon: axis-aligned, corners at ±0.4, control points evenly spaced along each axis-aligned edge (so each side is geometrically a straight line). Four identical QUAD params: lineRatios=(0.5, 0.5), controlPointRatios=(0.25, 0.75), continuous=true, visibilityRule=ALL, polysTransformWhole=false.

With these parameters the algorithm should produce a perfect uniform grid. The lineRatios are (0.5, 0.5) so even/odd side alternation in `splitRatio` makes no difference.

### 3. Algorithm comparison: Scala vs Swift

**What is the same:**
- centreSpline: both average the anchor points (every 4th point) — identical
- Assembly order: both build child polygon as [left half of edge i, connector(split_i → centre), reversed connector(split_{i-1} → centre), right half of edge i-1] — identical
- Internal connector: both build [from, lerp(from,to,α), lerp(from,to,β), to] — identical
- Visibility application, reversal of connector — identical

**The one genuine difference:**
Scala's `getSubSides` uses a proportional approximation when computing the two sub-halves of each edge (it reconstructs the control points via proportion rather than exact de Casteljau). Swift's `BezierMath.split` uses exact de Casteljau. The Swift comment notes this gives identical results for t=0.5. With lineRatios=(0.5, 0.5) this difference is irrelevant.

**No algorithmic difference has been found that would explain the bug.**

### 4. The central unresolved mystery

The previous session's collinearity test (`testQuad3LevelRectCollinearity`) passed — all 64 level-3 polygons have geometrically straight Bézier segments. But the app clearly shows distortion at level 3.

**These two facts cannot both be true for the same data.** One of the following must be the case:

A. **The test is not exercising the same code path as the app.** The test calls `SubdivisionEngine.process` directly with a programmatically constructed polygon. The app goes through `ProjectLoader → SpriteScene → renderInstance`. The actual polygon the app subdivides may differ from the test polygon in some way (different point count, different winding, different type flag).

B. **The test polygon and the app polygon are structurally different.** The test uses `rect.xml` from Test_055 (α≈0.338, β≈0.662 control points). The app uses the square from Test_056 (evenly-spaced control points). These are different source polygons — the test may not be testing the failing case at all.

C. **The distortion shown in the PNG renders is not produced by subdivision at all**, but by some other transform applied later in the app's render pipeline that the test bypasses.

### 5. What must be done next — in priority order

**Step 1 (most important): Close the test/app gap.**
Write a test that constructs the exact square from Test_056 (corners ±0.4, control points at ±0.13) and runs 3 QUAD subdivisions with the exact params from Test_056's subdivision.xml (lineRatios=(0.5,0.5), cpRatios=(0.25,0.75)). Print the anchor coordinates of ALL 64 level-3 polygons — not just the first 4. If the test output is a perfect grid, the bug is in the app's render pipeline, not in `SubdivisionEngine`. If the test output is distorted, the bug IS in `SubdivisionEngine` and can be isolated in a test.

**Step 2: Print all anchors for the inner cells.**
The previous test only printed polygons 0–3, which are corner cells. The distortion is in interior cells. We need anchors for cells in the middle of the 8×8 grid (e.g., poly[27], poly[28], poly[35], poly[36]).

**Step 3: Trace a single interior cell from root to level 3.**
Pick one visibly distorted cell from the level-3 image. Trace backward: which of the 4 level-1 cells is it descended from? Which of the 16 level-2 cells? Then add a test that subdivides only that ancestry path and prints coordinates at each level.

**Step 4 (required regardless): Swift baking.**
Implement switchable baking so that when the Swift engine is selected, baking calls the Swift subdivision algorithms. This will let us capture the actual Swift output to files for direct coordinate inspection — without having to go through rendering.

### 6. What is NOT the bug (ruled out)

- Control point collinearity (test passed)
- centreSpline formula (identical in Scala and Swift)
- Connector formula (identical)
- Assembly side order (identical)
- Visibility pruning (ALL — no pruning at any level)
- InsetTransform (polysTransformWhole=false — no whole-polygon transform applied)
- EditorDisabled params leaking in (confirmed excluded by XML loader)


________

⏺ Now I have everything I need. I'll add two new tests to the bottom of SubdivisionEngineTests:                                                                                                                                        
                                                           
  1. testQuad3LevelSquare056PrintAllAnchors — uses the exact Test_056 square and params, runs 3 QUAD levels, prints all 64 anchor sets so we can see the actual coordinates.                                                           
  2. testQuad3LevelSquare056GridCheck — asserts that all 64 level-3 polygon anchors land on the expected 9×9 grid (i.e., at multiples of 0.1 from −0.4 to 0.4). If this fails, the error messages will tell us exactly which polygon,  
  which anchor, and by how much.                                                                                                                                                                                                       
                                                                                                                                                                                                                                       
⏺ Update(loom_swift/Tests/LoomEngineTests/SubdivisionTests.swift) 

