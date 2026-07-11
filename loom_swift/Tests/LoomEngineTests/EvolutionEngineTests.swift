import XCTest
@testable import LoomEngine

/// No dedicated test file existed for `EvolutionEngine` (Momentum Drift /
/// Convergence Pressure) before the 2026-07-10 open-curve extension — this
/// covers baseline `SubdivisionParams` behavior (previously untested) alongside
/// the new `CurveRefinementParams` routing added for open curves.
final class EvolutionEngineTests: XCTestCase {

    // MARK: - Fixtures

    private func driftPass(
        target: DriftTarget,
        strength: Double = 0.5,
        momentum: Double = 0.5,
        frequency: Double = 0.05,
        seed: Int = 1
    ) -> EvolutionParams {
        EvolutionParams(
            operationType: .momentumDrift,
            driftTarget: target,
            driftMomentum: momentum,
            driftNoiseStrength: strength,
            driftNoiseFrequency: frequency,
            driftSeed: seed
        )
    }

    private func convergencePass(targetSetName: String, pressure: Double = 1.0) -> EvolutionParams {
        EvolutionParams(
            operationType: .convergencePressure,
            convergenceTargetSetName: targetSetName,
            convergencePressure: .constant(pressure),
            convergenceMode: .hold
        )
    }

    // MARK: - Momentum Drift — SubdivisionParams (baseline, previously untested)

    func testMomentumDriftZeroStrengthIsNoOp() {
        var params = [SubdivisionParams()]
        var curve: [CurveRefinementParams] = []
        let pass = driftPass(target: .lineRatioX, strength: 0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 10, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(params[0].lineRatios.x, 0.5, accuracy: 1e-12)
    }

    func testMomentumDriftDisabledPassIsNoOp() {
        var params = [SubdivisionParams()]
        var curve: [CurveRefinementParams] = []
        var pass = driftPass(target: .lineRatioX, strength: 1.0)
        pass.enabled = false
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 10, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(params[0].lineRatios.x, 0.5, accuracy: 1e-12)
    }

    func testMomentumDriftLineRatioXStaysClamped() {
        let params = [SubdivisionParams()]
        var curve: [CurveRefinementParams] = []
        let pass = driftPass(target: .lineRatioX, strength: 5.0)  // deliberately huge
        for frame: Double in stride(from: 0, through: 200, by: 7) {
            var p = params
            EvolutionEngine.apply(params: &p, curveRefinementParams: &curve, passes: [pass],
                                  elapsedFrames: frame, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
            XCTAssertGreaterThanOrEqual(p[0].lineRatios.x, 0.0)
            XCTAssertLessThanOrEqual(p[0].lineRatios.x, 1.0)
        }
    }

    func testMomentumDriftInsetScaleNeverBelowMinimum() {
        var params = [SubdivisionParams()]
        var curve: [CurveRefinementParams] = []
        let pass = driftPass(target: .insetScale, strength: 100.0)  // deliberately huge, always negative-leaning check
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 3, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertGreaterThanOrEqual(params[0].insetTransform.scale.x, 0.01)
    }

    func testMomentumDriftIsDeterministicForSameFrame() {
        var a = [SubdivisionParams()]
        var b = [SubdivisionParams()]
        var curveA: [CurveRefinementParams] = []
        var curveB: [CurveRefinementParams] = []
        let pass = driftPass(target: .cpNormalX, strength: 0.3)
        EvolutionEngine.apply(params: &a, curveRefinementParams: &curveA, passes: [pass],
                              elapsedFrames: 42, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        EvolutionEngine.apply(params: &b, curveRefinementParams: &curveB, passes: [pass],
                              elapsedFrames: 42, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(a, b)
    }

    func testMomentumDriftSubdivisionTargetLeavesCurveParamsUntouched() {
        var params = [SubdivisionParams()]
        var curve = [CurveRefinementParams()]
        let pass = driftPass(target: .lineRatioX, strength: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 10, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(curve, [CurveRefinementParams()], "a subdivision-targeted pass must not touch curve params")
    }

    // MARK: - Momentum Drift — CurveRefinementParams (new, 2026-07-10)

    func testIsCurveTargetCorrectForEveryCase() {
        let curveTargets: Set<DriftTarget> = [.curveDisplacement, .curveCPNormalOffset, .curvePressure]
        for target in DriftTarget.allCases {
            XCTAssertEqual(target.isCurveTarget, curveTargets.contains(target), "mismatch for \(target)")
        }
    }

    func testMomentumDriftCurveDisplacementWritesToCurveParamsOnly() {
        var params = [SubdivisionParams()]
        var curve = [CurveRefinementParams()]
        let pass = driftPass(target: .curveDisplacement, strength: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 10, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(params, [SubdivisionParams()], "a curve-targeted pass must not touch subdivision params")
        XCTAssertNotEqual(curve[0].displacement, 0, "displacement should have drifted away from its 0 default")
    }

    func testMomentumDriftCurveCPNormalOffsetWrites() {
        var params: [SubdivisionParams] = []
        var curve = [CurveRefinementParams()]
        let pass = driftPass(target: .curveCPNormalOffset, strength: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 10, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertNotEqual(curve[0].cpNormalOffset, 0)
    }

    func testMomentumDriftCurvePressureStaysClamped() {
        var params: [SubdivisionParams] = []
        let curve = [CurveRefinementParams(pressureValue: 0.95)]
        let pass = driftPass(target: .curvePressure, strength: 10.0)  // deliberately huge
        for frame: Double in stride(from: 0, through: 200, by: 7) {
            var c = curve
            EvolutionEngine.apply(params: &params, curveRefinementParams: &c, passes: [pass],
                                  elapsedFrames: frame, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
            XCTAssertGreaterThanOrEqual(c[0].pressureValue, 0.0)
            XCTAssertLessThanOrEqual(c[0].pressureValue, 1.0)
        }
    }

    func testMomentumDriftCurveTargetOnEmptyCurveParamsIsNoOp() {
        var params: [SubdivisionParams] = []
        var curve: [CurveRefinementParams] = []
        let pass = driftPass(target: .curveDisplacement, strength: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 10, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertTrue(curve.isEmpty)
    }

    // MARK: - Convergence Pressure — SubdivisionParams (baseline, previously untested)

    func testConvergencePressureFullyConvergesAtPressureOne() {
        var params = [SubdivisionParams(lineRatios: Vector2D(x: 0.1, y: 0.1))]
        var curve: [CurveRefinementParams] = []
        let target = [SubdivisionParams(lineRatios: Vector2D(x: 0.9, y: 0.9))]
        let pass = convergencePass(targetSetName: "target", pressure: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 0, targetFPS: 30, spriteIndex: 0,
                              allSets: ["target": target], allCurveSets: [:])
        XCTAssertEqual(params[0].lineRatios.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(params[0].lineRatios.y, 0.9, accuracy: 1e-9)
    }

    func testConvergencePressureNoOpWhenTargetSetNameEmpty() {
        var params = [SubdivisionParams(lineRatios: Vector2D(x: 0.1, y: 0.1))]
        var curve: [CurveRefinementParams] = []
        let pass = convergencePass(targetSetName: "", pressure: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 0, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(params[0].lineRatios.x, 0.1, accuracy: 1e-12)
    }

    func testConvergencePressureNoOpWhenTargetSetMissing() {
        var params = [SubdivisionParams(lineRatios: Vector2D(x: 0.1, y: 0.1))]
        var curve: [CurveRefinementParams] = []
        let pass = convergencePass(targetSetName: "doesNotExist", pressure: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 0, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(params[0].lineRatios.x, 0.1, accuracy: 1e-12)
    }

    func testConvergencePressureNoOpAtZeroPressure() {
        var params = [SubdivisionParams(lineRatios: Vector2D(x: 0.1, y: 0.1))]
        var curve: [CurveRefinementParams] = []
        let target = [SubdivisionParams(lineRatios: Vector2D(x: 0.9, y: 0.9))]
        let pass = convergencePass(targetSetName: "target", pressure: 0.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 0, targetFPS: 30, spriteIndex: 0,
                              allSets: ["target": target], allCurveSets: [:])
        XCTAssertEqual(params[0].lineRatios.x, 0.1, accuracy: 1e-9)
    }

    // MARK: - Convergence Pressure — CurveRefinementParams (new, 2026-07-10)

    func testConvergencePressureAlsoConvergesCurveRefinementParams() {
        var params = [SubdivisionParams(lineRatios: Vector2D(x: 0.1, y: 0.1))]
        var curve = [CurveRefinementParams(displacement: 0.0, cpNormalOffset: 0.0, pressureValue: 0.2)]
        let targetSubdiv = [SubdivisionParams(lineRatios: Vector2D(x: 0.9, y: 0.9))]
        let targetCurve  = [CurveRefinementParams(displacement: 0.5, cpNormalOffset: 0.3, pressureValue: 0.8)]
        let pass = convergencePass(targetSetName: "shared", pressure: 1.0)

        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 0, targetFPS: 30, spriteIndex: 0,
                              allSets: ["shared": targetSubdiv], allCurveSets: ["shared": targetCurve])

        // Same pass, same target-set name, converges both arrays at once.
        XCTAssertEqual(params[0].lineRatios.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(curve[0].displacement, 0.5, accuracy: 1e-9)
        XCTAssertEqual(curve[0].cpNormalOffset, 0.3, accuracy: 1e-9)
        XCTAssertEqual(curve[0].pressureValue, 0.8, accuracy: 1e-9)
    }

    func testConvergencePressureCurveNoOpWhenCurveParamsEmpty() {
        var params: [SubdivisionParams] = []
        var curve: [CurveRefinementParams] = []
        let targetCurve = [CurveRefinementParams(displacement: 0.5)]
        let pass = convergencePass(targetSetName: "shared", pressure: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 0, targetFPS: 30, spriteIndex: 0,
                              allSets: [:], allCurveSets: ["shared": targetCurve])
        XCTAssertTrue(curve.isEmpty)
    }

    func testConvergencePressureCurveNoOpWhenTargetCurveSetMissing() {
        var params: [SubdivisionParams] = []
        var curve = [CurveRefinementParams(displacement: 0.1)]
        let pass = convergencePass(targetSetName: "doesNotExist", pressure: 1.0)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 0, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(curve[0].displacement, 0.1, accuracy: 1e-12)
    }

    // MARK: - Generational pass type is a no-op here

    func testGenerationalOperationTypeIsNoOpInEvolutionEngine() {
        var params = [SubdivisionParams(lineRatios: Vector2D(x: 0.3, y: 0.3))]
        var curve = [CurveRefinementParams(displacement: 0.2)]
        let pass = EvolutionParams(operationType: .generational, generationCount: 3)
        EvolutionEngine.apply(params: &params, curveRefinementParams: &curve, passes: [pass],
                              elapsedFrames: 10, targetFPS: 30, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        XCTAssertEqual(params[0].lineRatios.x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(curve[0].displacement, 0.2, accuracy: 1e-12)
    }
}
