import XCTest
@testable import LoomEngine

// MARK: - Fixture

private func makeSquare() -> Polygon2D {
    let cp = Vector2D(x: 0.25, y: 0.75)
    let corners = [
        Vector2D(x: 0, y: 0),
        Vector2D(x: 1, y: 0),
        Vector2D(x: 1, y: 1),
        Vector2D(x: 0, y: 1),
    ]
    var pts = [Vector2D]()
    for i in 0..<4 {
        pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 4], cpRatios: cp)
    }
    return Polygon2D(points: pts, type: .spline)
}

final class GenerationalEvolutionEngineTests: XCTestCase {

    private func totalVertexCount(_ polygons: [Polygon2D]) -> Int {
        polygons.reduce(0) { $0 + $1.points.count }
    }

    // MARK: - Disabled / zero generations

    func testDisabledReturnsInputUnchanged() {
        let square = makeSquare()
        var params = EvolutionParams(generationCount: 5)
        params.enabled = false
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result, [square])
    }

    func testZeroGenerationsReturnsInputUnchanged() {
        let square = makeSquare()
        let params = EvolutionParams(generationCount: 0)
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result, [square])
    }

    // MARK: - Extrude-only

    func testExtrudeOnlyAddsPolygonsEachGeneration() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 4,
            extrudeWeight: 1.0,
            splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.1, extrudeDistanceMax: 0.1,
            generationSeed: 42,
            maxVertexBudget: 10_000
        )
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        // Original polygon plus one quad per generation.
        XCTAssertEqual(result.count, 1 + 4)
        for poly in result {
            XCTAssertEqual(poly.type, .spline)
            XCTAssertEqual(poly.points.count % 4, 0)
        }
    }

    // MARK: - Split-only

    func testSplitOnlyGrowsTargetPolygonPointCountWithoutAddingPolygons() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 3,
            extrudeWeight: 0.0,
            splitWeight: 1.0,
            splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
            generationSeed: 7,
            maxVertexBudget: 10_000
        )
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result.count, 1, "split must not create new polygons")
        // Each split adds exactly one new anchor (+4 points: new anchor + 2 new controls
        // + the pre-existing far anchor duplicated into the second half-segment... net +4).
        XCTAssertEqual(result[0].points.count, square.points.count + 3 * 4)
    }

    func testSplitDisplacesNewAnchorOutwardFromCentre() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 1,
            extrudeWeight: 0.0,
            splitWeight: 1.0,
            splitDisplacementMin: 0.3, splitDisplacementMax: 0.3,
            generationSeed: 3,
            maxVertexBudget: 10_000
        )
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let centre = BezierMath.centreSpline(square.points)

        // Find the one anchor present in the result but not in the original square —
        // that's the newly-split, displaced point.
        let originalAnchors = Set((0..<(square.points.count / 4)).map { square.points[$0 * 4] })
        let resultAnchors = (0..<(result[0].points.count / 4)).map { result[0].points[$0 * 4] }
        let newAnchors = resultAnchors.filter { !originalAnchors.contains($0) }

        XCTAssertEqual(newAnchors.count, 1)
        guard let newAnchor = newAnchors.first else { return }
        // The un-displaced split point (edge midpoint-ish) is inside/on the square,
        // so its distance from centre should be less than the displaced anchor's.
        let undisplacedDistanceUpperBound = Vector2D(x: 1, y: 1).distance(to: .zero) // generous bound
        XCTAssertLessThan(centre.distance(to: newAnchor), undisplacedDistanceUpperBound)
        XCTAssertGreaterThan(centre.distance(to: newAnchor), 0.5,
                              "displaced anchor should sit further from centre than an undisplaced edge point would")
    }

    // MARK: - Determinism

    func testSameSeedProducesIdenticalResult() {
        let square = makeSquare()
        let params = EvolutionParams(generationCount: 6, generationSeed: 99)
        let a = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsCanProduceDifferentResults() {
        let square = makeSquare()
        var paramsA = EvolutionParams(generationCount: 6)
        paramsA.generationSeed = 1
        var paramsB = paramsA
        paramsB.generationSeed = 2

        let a = GenerationalEvolutionEngine.process(polygons: [square], params: paramsA)
        let b = GenerationalEvolutionEngine.process(polygons: [square], params: paramsB)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Budget cap

    func testVertexBudgetStopsGenerationEarly() {
        let square = makeSquare()
        let generous = EvolutionParams(
            generationCount: 20, extrudeWeight: 1.0, splitWeight: 0.0,
            generationSeed: 5, maxVertexBudget: 100_000
        )
        let capped = EvolutionParams(
            generationCount: 20, extrudeWeight: 1.0, splitWeight: 0.0,
            generationSeed: 5, maxVertexBudget: totalVertexCount([square]) + 16 * 2 // room for ~2 quads
        )
        let generousResult = GenerationalEvolutionEngine.process(polygons: [square], params: generous)
        let cappedResult   = GenerationalEvolutionEngine.process(polygons: [square], params: capped)

        XCTAssertLessThan(totalVertexCount(cappedResult), totalVertexCount(generousResult))
        XCTAssertLessThanOrEqual(totalVertexCount(cappedResult), capped.maxVertexBudget)
    }

    // MARK: - passes: pipeline wrapper (EvolutionParams.operationType filtering)

    func testPassesWrapperIgnoresNonGenerationalPasses() {
        let square = makeSquare()
        let momentumDrift = EvolutionParams(operationType: .momentumDrift)
        let result = GenerationalEvolutionEngine.process(polygons: [square], passes: [momentumDrift])
        XCTAssertEqual(result, [square], "non-.generational passes must be ignored, not crash or mutate")
    }

    func testPassesWrapperIgnoresDisabledGenerationalPass() {
        let square = makeSquare()
        var disabled = EvolutionParams(operationType: .generational, generationCount: 5)
        disabled.enabled = false
        let result = GenerationalEvolutionEngine.process(polygons: [square], passes: [disabled])
        XCTAssertEqual(result, [square])
    }

    func testPassesWrapperChainsMultipleGenerationalPasses() {
        let square = makeSquare()
        let passA = EvolutionParams(
            operationType: .generational, generationCount: 2,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1, generationSeed: 1
        )
        let passB = EvolutionParams(
            operationType: .generational, generationCount: 3,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1, generationSeed: 2
        )
        let chained  = GenerationalEvolutionEngine.process(polygons: [square], passes: [passA, passB])
        let sequential = GenerationalEvolutionEngine.process(
            polygons: GenerationalEvolutionEngine.process(polygons: [square], params: passA),
            params: passB
        )
        XCTAssertEqual(chained, sequential, "passes: should apply each pass to the previous pass's output, in order")
        // 2 + 3 generations of extrude-only, run length pinned to 1 quad each = 5 new polygons.
        XCTAssertEqual(chained.count, 1 + 5)
    }

    // MARK: - Tweened phase

    func testNilPhaseMatchesFullGenerationCount() {
        let square = makeSquare()
        let params = EvolutionParams(generationCount: 4, generationSeed: 3)
        let implicit = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        let explicit = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 4.0)
        XCTAssertEqual(implicit, explicit, "omitting phase must match passing the full generationCount")
    }

    func testZeroPhaseReturnsInputUnchanged() {
        let square = makeSquare()
        let params = EvolutionParams(generationCount: 5, generationSeed: 3)
        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0)
        XCTAssertEqual(result, [square])
    }

    func testIntegerPhaseMatchesEquivalentGenerationCount() {
        let square = makeSquare()
        let fiveGen = EvolutionParams(generationCount: 5, generationSeed: 7)
        var twoGen  = fiveGen
        twoGen.generationCount = 2

        // Generation N's random draws depend only on (generationSeed, N), not on
        // generationCount — so phase=2 against a 5-generation config must match a
        // config whose generationCount is simply 2.
        let viaPhase = GenerationalEvolutionEngine.process(polygons: [square], params: fiveGen, phase: 2.0)
        let viaCount = GenerationalEvolutionEngine.process(polygons: [square], params: twoGen)
        XCTAssertEqual(viaPhase, viaCount)
    }

    func testFractionalPhaseScalesExtrudeDistance() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 1, extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            extrudeDistanceMin: 0.2, extrudeDistanceMax: 0.2,
            generationSeed: 11, maxVertexBudget: 10_000
        )
        let full = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 1.0)
        let half = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0.5)

        XCTAssertEqual(full.count, 2)
        XCTAssertEqual(half.count, 2, "a partially-tweened generation still adds its quad — just smaller")

        // Layout per ExtensionEngine.extrudeSegment: [a0,cp,cp,a1, a1,..,oa1, oa1,..,oa0, oa0,..,a0].
        // points[3] = a1 (inner/source edge), points[7] = oa1 (outer edge) — their
        // separation is exactly the extrusion distance when width == 1.0 (the default).
        let fullDistance = full[1].points[7].distance(to: full[1].points[3])
        let halfDistance = half[1].points[7].distance(to: half[1].points[3])

        XCTAssertEqual(fullDistance, 0.2, accuracy: 1e-9)
        XCTAssertEqual(halfDistance, 0.1, accuracy: 1e-9, "half phase through the generation should halve the distance")
    }

    func testFractionalPhaseScalesSplitDisplacement() {
        let square = makeSquare()
        let params = EvolutionParams(
            generationCount: 1, extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.3, splitDisplacementMax: 0.3,
            generationSeed: 4, maxVertexBudget: 10_000
        )
        let centre = BezierMath.centreSpline(square.points)
        let full = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 1.0)
        let quarter = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 0.25)

        let originalAnchors = Set((0..<(square.points.count / 4)).map { square.points[$0 * 4] })
        func newAnchor(_ result: [Polygon2D]) -> Vector2D {
            let anchors = (0..<(result[0].points.count / 4)).map { result[0].points[$0 * 4] }
            return anchors.first { !originalAnchors.contains($0) }!
        }

        // Undisplaced split point sits at distance 0.5 from centre (see the
        // non-tweened split test in this file); full/quarter phase should displace
        // it outward by the full/quarter-scaled RPSR distance respectively.
        let fullDistance    = centre.distance(to: newAnchor(full))
        let quarterDistance = centre.distance(to: newAnchor(quarter))
        XCTAssertEqual(fullDistance,    0.8,  accuracy: 1e-9)
        XCTAssertEqual(quarterDistance, 0.575, accuracy: 1e-9, "0.5 + 0.3*0.25")
    }

    func testPassesWrapperEvaluatesEnabledGenerationPhaseDriver() {
        let square = makeSquare()
        var params = EvolutionParams(
            operationType: .generational, generationCount: 4,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            generationSeed: 9
        )
        params.generationPhase = DoubleDriver(mode: .constant, base: 1.5, enabled: true)

        let viaPasses = GenerationalEvolutionEngine.process(polygons: [square], passes: [params])
        let viaDirect = GenerationalEvolutionEngine.process(polygons: [square], params: params, phase: 1.5)
        XCTAssertEqual(viaPasses, viaDirect)
    }

    func testPassesWrapperFallsBackToFullCountWhenDriverDisabled() {
        let square = makeSquare()
        var params = EvolutionParams(operationType: .generational, generationCount: 3, generationSeed: 2)
        params.generationPhase.enabled = false

        let viaPasses = GenerationalEvolutionEngine.process(polygons: [square], passes: [params])
        let viaFull    = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(viaPasses, viaFull)
    }

    // MARK: - Vary seed per cycle

    func testRevealCycleIndexOscillatorAlignsWithTroughNotWrapPoint() {
        // fps=8, freqHz=1 -> period 8 frames. phase=0.75 puts the trough (generation 0)
        // at elapsedFrames=0, matching the "start at frame 0" setup from the Reveal
        // driver walkthrough. The seed must not flip until a full cycle has passed
        // *from the trough*, not at the wave's internal p=0 wrap (a quarter-cycle
        // earlier), or it would glitch mid-climb.
        let driver = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                  freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 0, targetFPS: 8), 0)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 4, targetFPS: 8), 0,
                       "quarter-cycle in (partway up the climb) must still be cycle 0")
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 7.999, targetFPS: 8), 0)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 8, targetFPS: 8), 1,
                       "exactly one full cycle after the trough")
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 12, targetFPS: 8), 1)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 16, targetFPS: 8), 2)
    }

    func testRevealCycleIndexZeroWhenDriverDisabledOrNonLooping() {
        var disabled = DoubleDriver(mode: .oscillator, freqHz: 1.0, enabled: false)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: disabled, elapsedFrames: 100, targetFPS: 30), 0)

        let onceKeyframe = DoubleDriver(
            mode: .keyframe, loopMode: .once,
            keyframes: [DoubleKeyframe(frame: 0, value: 0), DoubleKeyframe(frame: 60, value: 5)],
            enabled: true
        )
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: onceKeyframe, elapsedFrames: 200, targetFPS: 30), 0,
                       "a one-shot (non-looping) keyframe track never restarts, so there's no cycle to key off")

        disabled.mode = .noise
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: disabled, elapsedFrames: 100, targetFPS: 30), 0)
    }

    func testRevealCycleIndexKeyframeLoop() {
        let driver = DoubleDriver(
            mode: .keyframe, loopMode: .loop,
            keyframes: [DoubleKeyframe(frame: 0, value: 0), DoubleKeyframe(frame: 60, value: 5)],
            enabled: true
        )
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 0,  targetFPS: 30), 0)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 59, targetFPS: 30), 0)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 60, targetFPS: 30), 1)
        XCTAssertEqual(GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 125, targetFPS: 30), 2)
    }

    func testEffectiveSeedMatchesGenerationSeedWhenVaryingIsOff() {
        var params = EvolutionParams(operationType: .generational, generationSeed: 42)
        params.generationPhase = DoubleDriver(mode: .oscillator, freqHz: 1.0, enabled: true)
        params.varySeedPerCycle = false
        XCTAssertEqual(
            GenerationalEvolutionEngine.effectiveSeed(for: params, elapsedFrames: 999, targetFPS: 30),
            42
        )
    }

    func testEffectiveSeedMatchesGenerationSeedWhenDriverDisabledEvenIfVaryingIsOn() {
        var params = EvolutionParams(operationType: .generational, generationSeed: 42)
        params.varySeedPerCycle = true
        params.generationPhase.enabled = false
        XCTAssertEqual(
            GenerationalEvolutionEngine.effectiveSeed(for: params, elapsedFrames: 999, targetFPS: 30),
            42
        )
    }

    func testEffectiveSeedMatchesCombineSeedOfCurrentCycleWhenVaryingIsOn() {
        var params = EvolutionParams(operationType: .generational, generationSeed: 42)
        params.generationPhase = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                              freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        params.varySeedPerCycle = true

        let cycle = GenerationalEvolutionEngine.revealCycleIndex(for: params.generationPhase, elapsedFrames: 12, targetFPS: 8)
        XCTAssertEqual(cycle, 1, "sanity check against testRevealCycleIndexOscillatorAlignsWithTroughNotWrapPoint")
        XCTAssertEqual(
            GenerationalEvolutionEngine.effectiveSeed(for: params, elapsedFrames: 12, targetFPS: 8),
            GenerationalEvolutionEngine.combineSeed(42, 1)
        )
    }

    func testVarySeedPerCycleProducesDifferentResultsAcrossCyclesAtSamePhase() {
        let square = makeSquare()
        var params = EvolutionParams(
            operationType: .generational, generationCount: 4,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            generationSeed: 21
        )
        params.generationPhase = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                              freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        params.varySeedPerCycle = true

        // elapsedFrames 4 and 12 are both a quarter-cycle past their respective
        // troughs (cycles 0 and 1 respectively — see testRevealCycleIndex... above),
        // so they evaluate to the *same* phase value but should mutate differently.
        let cycle0 = GenerationalEvolutionEngine.process(polygons: [square], passes: [params],
                                                          elapsedFrames: 4, targetFPS: 8)
        let cycle1 = GenerationalEvolutionEngine.process(polygons: [square], passes: [params],
                                                          elapsedFrames: 12, targetFPS: 8)
        XCTAssertNotEqual(cycle0, cycle1, "different cycles should mutate differently when varySeedPerCycle is on")

        // Same elapsedFrames called twice must still be fully deterministic.
        let cycle0Again = GenerationalEvolutionEngine.process(polygons: [square], passes: [params],
                                                               elapsedFrames: 4, targetFPS: 8)
        XCTAssertEqual(cycle0, cycle0Again)
    }

    func testVarySeedPerCycleHasNoEffectWhenDriverDisabled() {
        let square = makeSquare()
        var withVary = EvolutionParams(operationType: .generational, generationCount: 3, generationSeed: 5)
        withVary.varySeedPerCycle = true
        withVary.generationPhase.enabled = false

        var withoutVary = withVary
        withoutVary.varySeedPerCycle = false

        let a = GenerationalEvolutionEngine.process(polygons: [square], passes: [withVary],
                                                     elapsedFrames: 500, targetFPS: 30)
        let b = GenerationalEvolutionEngine.process(polygons: [square], passes: [withoutVary],
                                                     elapsedFrames: 500, targetFPS: 30)
        XCTAssertEqual(a, b, "varySeedPerCycle must be inert when the reveal driver itself is disabled")
    }

    func testSameCycleProducesSameResultRegardlessOfExactFrame() {
        let driver = DoubleDriver(mode: .oscillator, base: 2, amplitude: 2,
                                  freqHz: 1.0, phase: 0.75, wave: .sine, enabled: true)
        // elapsedFrames 4 and 4.5 are both within cycle 0 (see revealCycleIndex
        // tests above) — the cycle index (and therefore the effective seed) must
        // be identical even though the phase itself differs between them.
        XCTAssertEqual(
            GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 4,   targetFPS: 8),
            GenerationalEvolutionEngine.revealCycleIndex(for: driver, elapsedFrames: 4.5, targetFPS: 8)
        )
    }

    // MARK: - Directional selector (Specs/GeometricLifecycle.md §14)

    func testDirectionalSelectorRestrictsExtrudeTargetEdge() {
        let square = makeSquare()
        // Ground truth taken from the engine's own computed normal rather than an
        // assumed winding convention, so this test is correct regardless of which
        // way the fixture happens to wind.
        let seg0Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)

        var params = EvolutionParams(
            operationType: .generational, generationCount: 1,
            extrudeWeight: 1.0, splitWeight: 0.0,
            extrudeRunLengthMin: 1, extrudeRunLengthMax: 1,
            generationSeed: 42, maxVertexBudget: 10_000
        )
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg0Normal.angle, tolerance: 0.2)

        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result.count, 2, "exactly one quad should be extruded, from the matching edge")
        let addedQuad = result[1]
        XCTAssertEqual(addedQuad.points[0], square.points[0], "extruded quad's inner face should coincide with segment 0")
        XCTAssertEqual(addedQuad.points[3], square.points[3])
    }

    func testDirectionalSelectorNoMatchLeavesPolygonUnchangedForExtrude() {
        let square = makeSquare()
        let seg0Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 0)
        // Exactly between two adjacent segments' normals (90° apart on a square) —
        // with a tight tolerance, no segment's normal falls inside the cone.
        var params = EvolutionParams(
            operationType: .generational, generationCount: 3,
            extrudeWeight: 1.0, splitWeight: 0.0,
            generationSeed: 42, maxVertexBudget: 10_000
        )
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg0Normal.angle + .pi / 4, tolerance: 0.05)

        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result, [square], "no edge matches the directional filter, so every generation should no-op")
    }

    func testDirectionalSelectorRestrictsSplitTargetEdge() {
        let square = makeSquare()
        let seg2Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 2)

        var params = EvolutionParams(
            operationType: .generational, generationCount: 1,
            extrudeWeight: 0.0, splitWeight: 1.0,
            splitDisplacementMin: 0.1, splitDisplacementMax: 0.1,
            generationSeed: 7, maxVertexBudget: 10_000
        )
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg2Normal.angle, tolerance: 0.2)

        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result.count, 1, "split never adds polygons")
        let originalAnchors = Set((0..<4).map { square.points[$0 * 4] })
        let resultAnchors = (0..<(result[0].points.count / 4)).map { result[0].points[$0 * 4] }
        let newAnchors = resultAnchors.filter { !originalAnchors.contains($0) }
        XCTAssertEqual(newAnchors.count, 1, "exactly one split should have occurred")
    }

    func testDirectionalSelectorNoMatchLeavesPolygonUnchangedForSplit() {
        let square = makeSquare()
        let seg2Normal = ExtensionEngine.outwardNormal(of: square, segIdx: 2)
        var params = EvolutionParams(
            operationType: .generational, generationCount: 3,
            extrudeWeight: 0.0, splitWeight: 1.0,
            generationSeed: 7, maxVertexBudget: 10_000
        )
        params.directionalSelector = DirectionalSelector(enabled: true, targetAngle: seg2Normal.angle + .pi / 4, tolerance: 0.05)

        let result = GenerationalEvolutionEngine.process(polygons: [square], params: params)
        XCTAssertEqual(result, [square], "no edge matches the directional filter, so every generation should no-op")
    }
}
