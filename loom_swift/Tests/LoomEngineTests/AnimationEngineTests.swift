import XCTest
@testable import LoomEngine

// MARK: - Easing tests

final class EasingMathTests: XCTestCase {

    func testLinearBoundaries() {
        XCTAssertEqual(EasingMath.ease(0, type: .linear), 0)
        XCTAssertEqual(EasingMath.ease(1, type: .linear), 1)
    }

    func testLinearMidpoint() {
        XCTAssertEqual(EasingMath.ease(0.5, type: .linear), 0.5)
    }

    func testEaseInQuad() {
        // f(t) = t²; 0.5² = 0.25
        XCTAssertEqual(EasingMath.ease(0.5, type: .easeInQuad), 0.25, accuracy: 1e-9)
    }

    func testEaseOutQuad() {
        // f(t) = t(2-t); 0.5 * 1.5 = 0.75
        XCTAssertEqual(EasingMath.ease(0.5, type: .easeOutQuad), 0.75, accuracy: 1e-9)
    }

    func testEaseInOutQuadMidpoint() {
        // Symmetric — midpoint must be exactly 0.5.
        XCTAssertEqual(EasingMath.ease(0.5, type: .easeInOutQuad), 0.5, accuracy: 1e-9)
    }

    func testEaseInOutQuadSlowStart() {
        // At t=0.25 the value should be below 0.25 (accelerating).
        XCTAssertLessThan(EasingMath.ease(0.25, type: .easeInOutQuad), 0.25)
    }

    func testEaseInOutQuadFastMiddle() {
        // At t=0.75 the value should be above 0.75 (decelerating in the upper half).
        XCTAssertGreaterThan(EasingMath.ease(0.75, type: .easeInOutQuad), 0.75)
    }

    func testEaseInCubic() {
        // f(t) = t³; 0.5³ = 0.125
        XCTAssertEqual(EasingMath.ease(0.5, type: .easeInCubic), 0.125, accuracy: 1e-9)
    }

    func testEaseOutCubic() {
        // f(t) = (t-1)³ + 1; at 0.5 → (-0.5)³ + 1 = -0.125 + 1 = 0.875
        XCTAssertEqual(EasingMath.ease(0.5, type: .easeOutCubic), 0.875, accuracy: 1e-9)
    }

    func testEaseInOutCubicMidpoint() {
        XCTAssertEqual(EasingMath.ease(0.5, type: .easeInOutCubic), 0.5, accuracy: 1e-9)
    }

    func testAllEasingBoundaries() {
        for type in EasingType.allCases {
            XCTAssertEqual(EasingMath.ease(0, type: type), 0, accuracy: 1e-9,
                           "f(0) ≠ 0 for \(type)")
            XCTAssertEqual(EasingMath.ease(1, type: type), 1, accuracy: 1e-9,
                           "f(1) ≠ 1 for \(type)")
        }
    }
}

// MARK: - Loop normalisation tests (disabled: normalizedCycle API removed)
/*
final class LoopNormalisationTests: XCTestCase {
    // These tests used TransformAnimator.normalizedCycle which was removed.
    // TODO: rewrite against TransformAnimator.normalizedElapsed when needed.
}
*/

// MARK: - Keyframe transform tests (keyframe_rect from Test_052)

final class KeyframeTransformTests: XCTestCase {

    /// Animation from Test_052 — keyframe_rect sprite.
    private var animation: SpriteAnimation = {
        SpriteAnimation(
            enabled: true,
            type: .keyframe,
            loopMode: .loop,
            totalDraws: 200,
            keyframes: [
                Keyframe(drawCycle: 0,   position: .zero,                    scale: Vector2D(x: 1, y: 1), rotation: 0,   easing: .easeInOutQuad),
                Keyframe(drawCycle: 50,  position: Vector2D(x: 50, y: 0),    scale: Vector2D(x: 0.5, y: 0.5), rotation: -45, easing: .easeInOutQuad),
                Keyframe(drawCycle: 100, position: Vector2D(x: -50, y: 0),   scale: Vector2D(x: 0.5, y: 0.2), rotation: 45,  easing: .easeInOutQuad),
                Keyframe(drawCycle: 150, position: .zero,                    scale: Vector2D(x: 1, y: 1), rotation: 0,   easing: .easeInOutQuad),
            ]
        )
    }()

    func testAtFirstKeyframe() {
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: 0, using: &rng)
        XCTAssertEqual(t.positionOffset, .zero)
        XCTAssertEqual(t.scale, Vector2D(x: 1, y: 1))
        XCTAssertEqual(t.rotation, 0, accuracy: 1e-9)
    }

    func testAtLastKeyframe() {
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: Double(150)/30.0, using: &rng)
        XCTAssertEqual(t.positionOffset, .zero)
        XCTAssertEqual(t.scale, Vector2D(x: 1, y: 1))
        XCTAssertEqual(t.rotation, 0, accuracy: 1e-9)
    }

    func testAtMidpointFirstSegment() {
        // Cycle 25: halfway between KF0 and KF1, easeInOutQuad(0.5) = 0.5.
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: Double(25)/30.0, using: &rng)
        XCTAssertEqual(t.positionOffset.x, 25, accuracy: 1e-9)
        XCTAssertEqual(t.positionOffset.y, 0,  accuracy: 1e-9)
        XCTAssertEqual(t.scale.x, 0.75, accuracy: 1e-9)
        XCTAssertEqual(t.rotation, -22.5, accuracy: 1e-9)
    }

    func testLoopWrapsBackToStart() {
        // Cycle 200 wraps to normalised 0.
        var rng = SystemRandomNumberGenerator()
        let t0 = TransformAnimator.transform(for: animation, elapsedFrames: 0, using: &rng)
        let t1 = TransformAnimator.transform(for: animation, elapsedFrames: Double(200)/30.0, using: &rng)
        XCTAssertEqual(t0, t1)
    }

    func testHoldAfterLastKeyframe() {
        // Cycle 180 is past the last keyframe (150); should hold at KF3.
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: Double(180)/30.0, using: &rng)
        XCTAssertEqual(t.positionOffset, .zero)
        XCTAssertEqual(t.scale, Vector2D(x: 1, y: 1))
        XCTAssertEqual(t.rotation, 0, accuracy: 1e-9)
    }

    func testDisabledAnimationReturnsIdentity() {
        var rng = SystemRandomNumberGenerator()
        var anim = animation
        anim.enabled = false
        let t = TransformAnimator.transform(for: anim, elapsedFrames: 0, using: &rng)
        XCTAssertEqual(t, .identity)
    }
}

// MARK: - Morph keyframe tests (morphTarget_saw from Test_052)

final class MorphKeyframeTests: XCTestCase {

    private var animation: SpriteAnimation = {
        SpriteAnimation(
            enabled: true,
            type: .keyframeMorph,
            loopMode: .pingPong,
            totalDraws: 100,
            keyframes: [
                Keyframe(drawCycle: 0,  position: .zero, scale: Vector2D(x: 1, y: 1), rotation: 0, easing: .linear, morphAmount: 1.0),
                Keyframe(drawCycle: 50, position: .zero, scale: Vector2D(x: 1, y: 1), rotation: 0, easing: .linear, morphAmount: 2.0),
            ],
            morphTargets: [
                MorphTargetRef(file: "saw_mt_1.poly.xml"),
                MorphTargetRef(file: "saw_mt_2.poly.xml"),
            ]
        )
    }()

    func testAtCycle0() {
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: 0, using: &rng)
        XCTAssertEqual(t.morphAmount, 1.0, accuracy: 1e-9)
    }

    func testAtCycle50() {
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: Double(50)/30.0, using: &rng)
        XCTAssertEqual(t.morphAmount, 2.0, accuracy: 1e-9)
    }

    func testAtCycle25Midpoint() {
        // Linear easing, halfway between 1.0 and 2.0 → 1.5.
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: Double(25)/30.0, using: &rng)
        XCTAssertEqual(t.morphAmount, 1.5, accuracy: 1e-9)
    }

    func testPingPongReturnPass() {
        // With totalDraws=100, period=198. Cycle=75 → normalised=198-75=123? No.
        // n = 75 % 198 = 75; 75 < 100 → 75.
        // Between KF0(0) and KF1(50)? No, 75 > 50 → hold at last KF → morphAmount=2.0.
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: Double(75)/30.0, using: &rng)
        XCTAssertEqual(t.morphAmount, 2.0, accuracy: 1e-9)
    }

    func testPingPongAtCycle125() {
        // n = 125 % 198 = 125; 125 >= 100 → 198 - 125 = 73.
        // 73 is past KF1(50) → hold at KF1 → morphAmount=2.0.
        // Actually 73 > 50, so hold at last KF.
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: animation, elapsedFrames: Double(125)/30.0, using: &rng)
        XCTAssertEqual(t.morphAmount, 2.0, accuracy: 1e-9)
    }
}

// MARK: - Jitter transform tests

final class JitterTransformTests: XCTestCase {

    private let jitterAnim = SpriteAnimation(
        enabled: true,
        type: .random,
        translationRange: VectorRange(
            x: FloatRange(min: -30, max: 30),
            y: FloatRange(min: 0,   max: 0)
        )
    )

    func testTranslationXWithinBounds() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<100 {
            let t = TransformAnimator.transform(for: jitterAnim, elapsedFrames: 0, using: &rng)
            XCTAssertGreaterThanOrEqual(t.positionOffset.x, -30)
            XCTAssertLessThanOrEqual(t.positionOffset.x,     30)
        }
    }

    func testTranslationYZeroRange() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let t = TransformAnimator.transform(for: jitterAnim, elapsedFrames: 0, using: &rng)
            XCTAssertEqual(t.positionOffset.y, 0)
        }
    }

    func testZeroRangeScaleBecomesOne() {
        // When scale range is zero the animator must not collapse the sprite to 0.
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: jitterAnim, elapsedFrames: 0, using: &rng)
        XCTAssertEqual(t.scale.x, 1)
        XCTAssertEqual(t.scale.y, 1)
    }

    func testMorphAmountIsZeroForJitter() {
        var rng = SystemRandomNumberGenerator()
        let t = TransformAnimator.transform(for: jitterAnim, elapsedFrames: 0, using: &rng)
        XCTAssertEqual(t.morphAmount, 0)
    }
}

// MARK: - Jitter-morph transform tests

final class JitterMorphTransformTests: XCTestCase {

    private let jitterMorphAnim = SpriteAnimation(
        enabled: true,
        type: .jitterMorph,
        totalDraws: 50,
        morphTargets: [
            MorphTargetRef(file: "saw_mt_1.poly.xml"),
            MorphTargetRef(file: "saw_mt_2.poly.xml"),
        ],
        morphMin: 0,
        morphMax: 2
    )

    func testMorphAmountWithinBounds() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<100 {
            let t = TransformAnimator.transform(for: jitterMorphAnim, elapsedFrames: 0, using: &rng)
            XCTAssertGreaterThanOrEqual(t.morphAmount, 0)
            XCTAssertLessThanOrEqual(t.morphAmount, 2)
        }
    }

    func testDeterministicWithSeededRNG() {
        var rng1 = SeededRNG(seed: 42)
        var rng2 = SeededRNG(seed: 42)
        let t1 = TransformAnimator.transform(for: jitterMorphAnim, elapsedFrames: 0, using: &rng1)
        let t2 = TransformAnimator.transform(for: jitterMorphAnim, elapsedFrames: 0, using: &rng2)
        XCTAssertEqual(t1, t2)
    }
}

// MARK: - MorphInterpolator tests

final class MorphInterpolatorTests: XCTestCase {

    private let base = [
        Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0),
                           Vector2D(x: 1, y: 1), Vector2D(x: 0, y: 1)],
                  type: .line)
    ]

    private let target0 = [
        Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 2, y: 0),
                           Vector2D(x: 2, y: 2), Vector2D(x: 0, y: 2)],
                  type: .line)
    ]

    private let target1 = [
        Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 4, y: 0),
                           Vector2D(x: 4, y: 4), Vector2D(x: 0, y: 4)],
                  type: .line)
    ]

    func testMorphAmountZeroReturnsBase() {
        let result = MorphInterpolator.interpolate(base: base, targets: [target0, target1], morphAmount: 0)
        XCTAssertEqual(result, base)
    }

    func testMorphAmountOneReturnsTarget0() {
        let result = MorphInterpolator.interpolate(base: base, targets: [target0, target1], morphAmount: 1)
        XCTAssertEqual(result, target0)
    }

    func testMorphAmountTwoReturnsTarget1() {
        let result = MorphInterpolator.interpolate(base: base, targets: [target0, target1], morphAmount: 2)
        XCTAssertEqual(result, target1)
    }

    func testMorphAmount0_5BlendsBetweenBaseAndTarget0() {
        // Halfway between base x=1 and target0 x=2 → x=1.5
        let result = MorphInterpolator.interpolate(base: base, targets: [target0, target1], morphAmount: 0.5)
        let pts = result[0].points
        XCTAssertEqual(pts[1].x, 1.5, accuracy: 1e-9)
        XCTAssertEqual(pts[2].x, 1.5, accuracy: 1e-9)
        XCTAssertEqual(pts[2].y, 1.5, accuracy: 1e-9)
    }

    func testMorphAmount1_5BlendsBetweenTarget0AndTarget1() {
        // Halfway between target0 x=2 and target1 x=4 → x=3
        let result = MorphInterpolator.interpolate(base: base, targets: [target0, target1], morphAmount: 1.5)
        let pts = result[0].points
        XCTAssertEqual(pts[1].x, 3, accuracy: 1e-9)
        XCTAssertEqual(pts[2].x, 3, accuracy: 1e-9)
    }

    func testMorphAmountClampedAtMax() {
        // morphAmount 3.0 exceeds target count (2); should return last target.
        let result = MorphInterpolator.interpolate(base: base, targets: [target0, target1], morphAmount: 3.0)
        XCTAssertEqual(result, target1)
    }

    func testEmptyTargetsReturnsBase() {
        let result = MorphInterpolator.interpolate(base: base, targets: [], morphAmount: 1.0)
        XCTAssertEqual(result, base)
    }

    func testMismatchedPointCountFallsBackToBase() {
        let badTarget = [
            Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0)], type: .line)
        ]
        let result = MorphInterpolator.interpolate(base: base, targets: [badTarget], morphAmount: 0.5)
        XCTAssertEqual(result, base)
    }
}

// MARK: - PaletteIndexState / RenderStateEngine tests

final class PaletteIndexStateTests: XCTestCase {

    // MARK: Helpers

    private func makeStrokeColorChange(
        kind: ChangeKind = .sequential,
        motion: ChangeMotion = .up,
        cycle: ChangeCycle = .constant,
        colors: [LoomColor],
        pauseMax: Int = 0
    ) -> StrokeColorChange {
        StrokeColorChange(
            enabled: true, kind: kind, motion: motion,
            cycle: cycle, scale: .poly,
            palette: colors, pauseMax: pauseMax
        )
    }

    private let threeColors = [
        LoomColor(r: 255, g: 0,   b: 0,   a: 255),
        LoomColor(r: 0,   g: 255, b: 0,   a: 255),
        LoomColor(r: 0,   g: 0,   b: 255, a: 255),
    ]

    // MARK: SEQ UP

    func testSeqUpAdvances() {
        let change   = makeStrokeColorChange(kind: .sequential, motion: .up, colors: threeColors)
        let changes  = RendererChanges(strokeColor: change)
        var state    = RendererAnimationState.initial(for: changes)
        var rng      = SystemRandomNumberGenerator()

        // index 0 → 1 → 2 → 0
        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 1)
        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 2)
        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 0)  // wrap
    }

    // MARK: SEQ DOWN

    func testSeqDownAdvances() {
        let change   = makeStrokeColorChange(kind: .sequential, motion: .down, colors: threeColors)
        let changes  = RendererChanges(strokeColor: change)
        var state    = RendererAnimationState.initial(for: changes)
        var rng      = SystemRandomNumberGenerator()

        // index 0 → 2 → 1 → 0
        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 2)
        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 1)
        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 0)
    }

    // MARK: SEQ PING_PONG

    func testSeqPingPongBounces() {
        let change   = makeStrokeColorChange(kind: .sequential, motion: .pingPong, colors: threeColors)
        let changes  = RendererChanges(strokeColor: change)
        var state    = RendererAnimationState.initial(for: changes)
        var rng      = SystemRandomNumberGenerator()

        // palette size 3: expected sequence after init (index=0): 1, 2, 1, 0, 1, 2, ...
        let expected = [1, 2, 1, 0, 1, 2, 1, 0]
        for exp in expected {
            state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
            XCTAssertEqual(state.strokeColorState?.index, exp)
        }
    }

    // MARK: PAUSING cycle

    func testPausingHoldsBeforeAdvancing() {
        let change  = makeStrokeColorChange(kind: .sequential, motion: .up,
                                            cycle: .pausing, colors: threeColors, pauseMax: 0)
        let changes = RendererChanges(strokeColor: change)
        // Inject a state with a pending pause.
        var state   = RendererAnimationState(
            strokeColorState: PaletteIndexState(index: 0, pauseRemaining: 2, direction: 1)
        )
        var rng = SystemRandomNumberGenerator()

        // Should NOT advance — burns a pause frame.
        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 0)
        XCTAssertEqual(state.strokeColorState?.pauseRemaining, 1)

        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 0)
        XCTAssertEqual(state.strokeColorState?.pauseRemaining, 0)

        // Now it can advance.
        state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
        XCTAssertEqual(state.strokeColorState?.index, 1)
    }

    // MARK: Resolve

    func testResolveAppliesFillColor() {
        let colors  = [LoomColor(r: 200, g: 100, b: 50, a: 255)]
        let change  = FillColorChange(enabled: true, kind: .sequential, motion: .up,
                                      cycle: .constant, scale: .poly, palette: colors, pauseMax: 0)
        let changes = RendererChanges(fillColor: change)
        let state   = RendererAnimationState(fillColorState: PaletteIndexState(index: 0))
        let renderer = Renderer()

        let resolved = RenderStateEngine.resolve(renderer: renderer, state: state, changes: changes)
        XCTAssertEqual(resolved.fillColor, colors[0])
    }

    func testResolveAppliesStrokeWidth() {
        let sizes   = [0.1, 0.3, 0.6]
        let change  = StrokeWidthChange(enabled: true, kind: .sequential, motion: .up,
                                        cycle: .constant, scale: .poly, sizePalette: sizes, pauseMax: 0)
        let changes = RendererChanges(strokeWidth: change)
        let state   = RendererAnimationState(strokeWidthState: PaletteIndexState(index: 1))
        let resolved = RenderStateEngine.resolve(renderer: Renderer(), state: state, changes: changes)
        XCTAssertEqual(resolved.strokeWidth, 0.3, accuracy: 1e-9)
    }

    func testResolveDisabledChangeIsIgnored() {
        let colors  = [LoomColor(r: 200, g: 100, b: 50, a: 255)]
        let change  = FillColorChange(enabled: false, kind: .sequential, motion: .up,
                                      cycle: .constant, scale: .poly, palette: colors, pauseMax: 0)
        let changes = RendererChanges(fillColor: change)
        let state   = RendererAnimationState(fillColorState: PaletteIndexState(index: 0))
        var renderer = Renderer()
        renderer.fillColor = .black

        let resolved = RenderStateEngine.resolve(renderer: renderer, state: state, changes: changes)
        XCTAssertEqual(resolved.fillColor, .black)
    }

    func testInitialStateIndexIsZero() {
        let colors  = threeColors
        let change  = FillColorChange(enabled: true, kind: .sequential, motion: .up,
                                      cycle: .constant, scale: .poly, palette: colors, pauseMax: 0)
        let changes = RendererChanges(fillColor: change)
        let state   = RendererAnimationState.initial(for: changes)
        XCTAssertEqual(state.fillColorState?.index, 0)
        XCTAssertNil(state.strokeColorState)
        XCTAssertNil(state.strokeWidthState)
    }
}

// MARK: - RAN kind tests

final class RandomKindPaletteTests: XCTestCase {

    func testRanKindPicksValidIndex() {
        let colors  = [
            LoomColor(r: 255, g: 0,   b: 0,   a: 255),
            LoomColor(r: 0,   g: 255, b: 0,   a: 255),
            LoomColor(r: 0,   g: 0,   b: 255, a: 255),
        ]
        let change  = FillColorChange(enabled: true, kind: .random, motion: .pingPong,
                                      cycle: .pausing, scale: .poly, palette: colors, pauseMax: 5)
        let changes = RendererChanges(fillColor: change)
        var state   = RendererAnimationState.initial(for: changes)
        var rng     = SystemRandomNumberGenerator()

        for _ in 0..<50 {
            state = RenderStateEngine.advance(state: state, changes: changes, using: &rng)
            let idx = state.fillColorState!.index
            XCTAssertGreaterThanOrEqual(idx, 0)
            XCTAssertLessThan(idx, colors.count)
        }
    }

    func testRanKindIsDeterministicWithSeed() {
        let colors  = [
            LoomColor(r: 255, g: 0,   b: 0,   a: 255),
            LoomColor(r: 0,   g: 255, b: 0,   a: 255),
        ]
        let change  = FillColorChange(enabled: true, kind: .random, motion: .up,
                                      cycle: .constant, scale: .poly, palette: colors, pauseMax: 0)
        let changes = RendererChanges(fillColor: change)
        let init_state = RendererAnimationState.initial(for: changes)

        var rng1 = SeededRNG(seed: 99)
        var rng2 = SeededRNG(seed: 99)
        var s1 = init_state
        var s2 = init_state

        for _ in 0..<10 {
            s1 = RenderStateEngine.advance(state: s1, changes: changes, using: &rng1)
            s2 = RenderStateEngine.advance(state: s2, changes: changes, using: &rng2)
            XCTAssertEqual(s1.fillColorState?.index, s2.fillColorState?.index)
        }
    }
}

// MARK: - Test_052 integration — render changes round-trip via resolve

final class RendererChanges052ResolveTests: XCTestCase {

    /// Verify that the saw_renderer from Test_052 is correctly resolved at its initial state.
    func testSawRendererInitialResolve() {
        let sizes = [0.1, 0.3, 0.6]
        let strokeWidthChange = StrokeWidthChange(
            enabled: true, kind: .random, motion: .up,
            cycle: .constant, scale: .poly, sizePalette: sizes, pauseMax: 0
        )
        let changes = RendererChanges(strokeWidth: strokeWidthChange)
        let state   = RendererAnimationState.initial(for: changes)
        var r = Renderer()
        r.strokeWidth = 0.9   // some non-palette value

        let resolved = RenderStateEngine.resolve(renderer: r, state: state, changes: changes)
        // index 0 → 0.1
        XCTAssertEqual(resolved.strokeWidth, 0.1, accuracy: 1e-9)
    }
}

// MARK: - SeededRNG (injectable deterministic generator for tests)

/// A simple xorshift64 deterministic RNG for reproducible tests.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
