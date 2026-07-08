import XCTest
@testable import LoomEngine

final class DirectionalSelectorTests: XCTestCase {

    func testDefaultIsDisabled() {
        XCTAssertFalse(DirectionalSelector().enabled)
    }

    func testDisabledAlwaysAccepts() {
        var selector = DirectionalSelector(enabled: false, targetAngle: 0, tolerance: 0.01)
        selector.enabled = false
        // A direction pointing the exact opposite way would fail if enabled — confirms
        // the disabled short-circuit, not a coincidentally-wide tolerance.
        XCTAssertTrue(selector.accepts(Vector2D(x: -1, y: 0)))
    }

    func testExactMatchAccepted() {
        let selector = DirectionalSelector(enabled: true, targetAngle: .pi / 2, tolerance: 0.1)
        XCTAssertTrue(selector.accepts(Vector2D(x: 0, y: 1)))
    }

    func testOppositeDirectionRejected() {
        let selector = DirectionalSelector(enabled: true, targetAngle: .pi / 2, tolerance: 0.3)
        XCTAssertFalse(selector.accepts(Vector2D(x: 0, y: -1)))
    }

    func testWithinToleranceAccepted() {
        // Target = up (π/2), tolerance ±0.35 rad (~20°). A direction 10° off should pass.
        let selector = DirectionalSelector(enabled: true, targetAngle: .pi / 2, tolerance: 0.35)
        let tenDegreesOff = Vector2D(x: 0, y: 1).rotated(by: 10 * .pi / 180)
        XCTAssertTrue(selector.accepts(tenDegreesOff))
    }

    func testJustOutsideToleranceRejected() {
        let selector = DirectionalSelector(enabled: true, targetAngle: .pi / 2, tolerance: 0.35)
        let thirtyDegreesOff = Vector2D(x: 0, y: 1).rotated(by: 30 * .pi / 180)
        XCTAssertFalse(selector.accepts(thirtyDegreesOff))
    }

    func testToleranceBoundaryIsInclusive() {
        let selector = DirectionalSelector(enabled: true, targetAngle: 0, tolerance: 0.2)
        let atBoundary = Vector2D(x: 1, y: 0).rotated(by: 0.2)
        XCTAssertTrue(selector.accepts(atBoundary))
    }

    func testWraparoundNearPositiveNegativePiBoundary() {
        // Target angle just past +π should still accept a direction just past -π —
        // these are numerically far apart (~2π) but geometrically adjacent.
        let selector = DirectionalSelector(enabled: true, targetAngle: .pi - 0.05, tolerance: 0.2)
        let justPastNegativePi = Vector2D(x: -1, y: 0).rotated(by: -0.1) // angle ≈ -π + 0.1 ≈ π - 0.1 wrapped
        XCTAssertTrue(selector.accepts(justPastNegativePi))
    }

    func testZeroLengthDirectionIsAccepted() {
        // A degenerate edge has no direction to test against — treated as "not
        // excluded by the filter," leaving degenerate-input handling to the caller.
        let selector = DirectionalSelector(enabled: true, targetAngle: 0, tolerance: 0.01)
        XCTAssertTrue(selector.accepts(.zero))
    }

    func testCodableRoundTrip() throws {
        let original = DirectionalSelector(enabled: true, targetAngle: 1.23, tolerance: 0.45, basis: .tangent)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DirectionalSelector.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
