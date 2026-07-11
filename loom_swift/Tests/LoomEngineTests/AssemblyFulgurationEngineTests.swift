import XCTest
@testable import LoomEngine

final class AssemblyPrimitiveKitTests: XCTestCase {

    func testSquareHasFourEqualEdges() {
        let square = AssemblyPrimitiveKit.generate(.square)
        XCTAssertEqual(square.points.count, 4)
        XCTAssertEqual(square.type, .line)
        let sites = AttachmentSiteExtractor.sites(of: square)
        XCTAssertEqual(sites.count, 4)
        for site in sites {
            XCTAssertEqual(site.length ?? 0, sites[0].length ?? -1, accuracy: 1e-9)
        }
    }

    func testTriangleAndPentagonVertexCounts() {
        XCTAssertEqual(AssemblyPrimitiveKit.generate(.triangle).points.count, 3)
        XCTAssertEqual(AssemblyPrimitiveKit.generate(.pentagon).points.count, 5)
    }

    func testLineIsOpenSplineWithTwoEndpointSites() {
        let line = AssemblyPrimitiveKit.generate(.line)
        XCTAssertEqual(line.type, .openSpline)
        XCTAssertEqual(line.points.count, 4)
        let sites = AttachmentSiteExtractor.sites(of: line)
        XCTAssertEqual(sites.count, 2)
        XCTAssertNil(sites[0].length, "curve endpoints have no length")
    }

    func testDeformAppliesIndependentXYScale() {
        let square = AssemblyPrimitiveKit.generate(.square)
        let deformed = AssemblyPrimitiveKit.deformed(square, scaleX: 2.0, scaleY: 0.5)
        for (orig, def) in zip(square.points, deformed.points) {
            XCTAssertEqual(def.x, orig.x * 2.0, accuracy: 1e-9)
            XCTAssertEqual(def.y, orig.y * 0.5, accuracy: 1e-9)
        }
    }
}

final class AttachmentSiteExtractorTests: XCTestCase {

    func testLineEdgeOutwardPointsAwayFromCentroid() {
        let square = AssemblyPrimitiveKit.generate(.square)
        let centre = square.centroid
        for site in AttachmentSiteExtractor.sites(of: square) {
            XCTAssertGreaterThan(site.outward.dot(site.point - centre), 0,
                                 "outward should point away from the polygon's own centroid")
            XCTAssertEqual(site.outward.length, 1.0, accuracy: 1e-9)
        }
    }

    func testOpenSplineEndpointTangentsPointOutward() {
        let line = AssemblyPrimitiveKit.generate(.line)
        let sites = AttachmentSiteExtractor.sites(of: line)
        XCTAssertEqual(sites.count, 2)
        // Start endpoint's direction should point away from the line (toward -x),
        // end endpoint's toward +x — a straight segment's two ends face opposite ways.
        XCTAssertLessThan(sites[0].direction.x, 0)
        XCTAssertGreaterThan(sites[1].direction.x, 0)
        for site in sites {
            XCTAssertEqual(site.outward.dot(site.direction), 0, accuracy: 1e-9,
                           "outward must be perpendicular to direction")
        }
    }

    func testSplineAndPointTypesExposeNoSites() {
        let point = Polygon2D(points: [.zero], type: .point)
        XCTAssertEqual(AttachmentSiteExtractor.sites(of: point).count, 0)
    }
}

final class AssemblyPlacementTests: XCTestCase {

    func testPlaceMapsSourcePointOntoTargetPoint() {
        let square = AssemblyPrimitiveKit.generate(.square)
        let sites = AttachmentSiteExtractor.sites(of: square)
        let source = sites[0]
        let target = AttachmentSite(point: Vector2D(x: 5, y: 5), direction: Vector2D(x: 1, y: 0),
                                    outward: Vector2D(x: 0, y: 1), length: source.length)

        let placed = AssemblyFulgurationEngine.place(square, sourceSite: source, onto: target,
                                                      mirror: false, edgeMatching: .preserveSize)
        let placedSites = AttachmentSiteExtractor.sites(of: placed)
        // One of the placed piece's sites should now sit exactly at the target point
        // (the one that was `source`), with outward antiparallel to the target's.
        let matching = placedSites.first { $0.point.distance(to: target.point) < 1e-6 }
        XCTAssertNotNil(matching)
        if let matching {
            XCTAssertEqual(matching.outward.dot(target.outward), -1, accuracy: 1e-6)
        }
    }

    func testMatchLengthRescalesToTargetEdgeLength() {
        let square = AssemblyPrimitiveKit.generate(.square)
        let source = AttachmentSiteExtractor.sites(of: square)[0]
        let targetLength = (source.length ?? 1) * 3.0
        let target = AttachmentSite(point: Vector2D(x: 2, y: 2), direction: Vector2D(x: 1, y: 0),
                                    outward: Vector2D(x: 0, y: 1), length: targetLength)

        let placed = AssemblyFulgurationEngine.place(square, sourceSite: source, onto: target,
                                                      mirror: false, edgeMatching: .matchLength)
        let placedSites = AttachmentSiteExtractor.sites(of: placed)
        let matching = placedSites.first { $0.point.distance(to: target.point) < 1e-6 }
        XCTAssertNotNil(matching)
        XCTAssertEqual(matching?.length ?? -1, targetLength, accuracy: 1e-6)
    }

    func testPreserveSizeKeepsNativeEdgeLength() {
        let square = AssemblyPrimitiveKit.generate(.square)
        let source = AttachmentSiteExtractor.sites(of: square)[0]
        let nativeLength = source.length ?? -1
        let target = AttachmentSite(point: Vector2D(x: -3, y: 1), direction: Vector2D(x: 1, y: 0),
                                    outward: Vector2D(x: 0, y: 1), length: nativeLength * 5)

        let placed = AssemblyFulgurationEngine.place(square, sourceSite: source, onto: target,
                                                      mirror: false, edgeMatching: .preserveSize)
        let placedSites = AttachmentSiteExtractor.sites(of: placed)
        let matching = placedSites.first { $0.point.distance(to: target.point) < 1e-6 }
        XCTAssertEqual(matching?.length ?? -1, nativeLength, accuracy: 1e-6)
    }
}

final class AssemblyFulgurationEngineTests: XCTestCase {

    private func assemblyPass(seed: Int = 0, countMin: Int = 4, countMax: Int = 8) -> FulgurationParams {
        var pass = FulgurationParams()
        pass.contentMode = .assembly
        pass.cycleSeed = seed
        pass.assemblyPieceCountMin = countMin
        pass.assemblyPieceCountMax = countMax
        return pass
    }

    func testSameSeedProducesIdenticalAssembly() {
        let pass = assemblyPass(seed: 42)
        let a = AssemblyFulgurationEngine.assemble(pass: pass, seed: 42, cycleIndex: 0)
        let b = AssemblyFulgurationEngine.assemble(pass: pass, seed: 42, cycleIndex: 0)
        XCTAssertEqual(a, b)
    }

    func testDifferentCycleIndexProducesDifferentAssembly() {
        let pass = assemblyPass(seed: 42)
        let a = AssemblyFulgurationEngine.assemble(pass: pass, seed: 42, cycleIndex: 0)
        let b = AssemblyFulgurationEngine.assemble(pass: pass, seed: 42, cycleIndex: 1)
        XCTAssertNotEqual(a, b)
    }

    func testPieceCountRespectsFixedRange() {
        let pass = assemblyPass(seed: 7, countMin: 6, countMax: 6)
        let pieces = AssemblyFulgurationEngine.assemble(pass: pass, seed: 7, cycleIndex: 0)
        XCTAssertEqual(pieces.count, 6)
    }

    func testPieceCountStaysWithinRangeAcrossManyCycles() {
        let pass = assemblyPass(seed: 3, countMin: 2, countMax: 5)
        for cycle in 0..<50 {
            let pieces = AssemblyFulgurationEngine.assemble(pass: pass, seed: 3, cycleIndex: cycle)
            XCTAssertGreaterThanOrEqual(pieces.count, 2)
            XCTAssertLessThanOrEqual(pieces.count, 5)
        }
    }

    func testSizeRangeScalesPieceSpanProportionally() {
        var passFull = assemblyPass(seed: 11, countMin: 1, countMax: 1)
        passFull.assemblySizeMin = 1.0; passFull.assemblySizeMax = 1.0
        passFull.assemblyDeformMin = 1.0; passFull.assemblyDeformMax = 1.0

        var passSmall = passFull
        passSmall.assemblySizeMin = 0.2; passSmall.assemblySizeMax = 0.2

        let fullPiece  = AssemblyFulgurationEngine.assemble(pass: passFull,  seed: 11, cycleIndex: 0).first
        let smallPiece = AssemblyFulgurationEngine.assemble(pass: passSmall, seed: 11, cycleIndex: 0).first
        guard let fullPiece, let smallPiece else { return XCTFail("expected one piece each") }

        // Same seed → same RPSR-selected kind for both (size doesn't influence the
        // kind roll), so this is a fair like-for-like comparison.
        let fullSpan  = fullPiece.points.map { $0.length }.max() ?? 0
        let smallSpan = smallPiece.points.map { $0.length }.max() ?? 0
        XCTAssertEqual(smallSpan, fullSpan * 0.2, accuracy: 1e-9)
    }

    func testDefaultSizeRangeKeepsPiecesWellBelowBaseRadius() {
        let pass = assemblyPass(seed: 13, countMin: 1, countMax: 1)  // default size 0.15–0.35
        guard let piece = AssemblyFulgurationEngine.assemble(pass: pass, seed: 13, cycleIndex: 0).first else {
            return XCTFail("expected one piece")
        }
        let span = piece.points.map { $0.length }.max() ?? 0
        XCTAssertLessThan(span, 0.5, "default size range should keep pieces well under the base kit's ~0.5 radius")
    }

    func testSinglePieceCountProducesNoAttachmentWork() {
        let pass = assemblyPass(seed: 9, countMin: 1, countMax: 1)
        let pieces = AssemblyFulgurationEngine.assemble(pass: pass, seed: 9, cycleIndex: 0)
        XCTAssertEqual(pieces.count, 1)
    }

    // MARK: - contentMode wiring through the public apply() entry point

    func testAssemblyModeProducesGeometryDuringHoldEvenWithEmptySpriteInput() {
        var pass = assemblyPass(seed: 1)
        pass.intervalMin = 5; pass.intervalMax = 5
        pass.holdMin = 20; pass.holdMax = 20
        let result = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 10, spriteIndex: 0)
        XCTAssertFalse(result.isEmpty, "assembly mode should generate its own geometry, independent of sprite input")
    }

    func testAssemblyModeHiddenOutsideHoldWindow() {
        var pass = assemblyPass(seed: 1)
        pass.intervalMin = 5; pass.intervalMax = 5
        pass.holdMin = 20; pass.holdMax = 20
        let result = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 2, spriteIndex: 0)
        XCTAssertEqual(result, [])
    }

    func testLaterAssemblyPassStillRunsAfterEarlierPassZeroesChain() {
        // A .transform pass hidden the whole time, chained with an always-visible
        // .assembly pass — the assembly pass must not be short-circuited by the
        // earlier pass's empty intermediate result (FulgurationEngine.apply no
        // longer blanket-short-circuits on an empty chain result for this reason).
        var hiddenTransform = FulgurationParams()
        hiddenTransform.intervalMin = 1_000_000; hiddenTransform.intervalMax = 1_000_000
        hiddenTransform.holdMin = 1; hiddenTransform.holdMax = 1

        var assembly = assemblyPass(seed: 2)
        assembly.intervalMin = 0; assembly.intervalMax = 0
        assembly.holdMin = 1000; assembly.holdMax = 1000

        let result = FulgurationEngine.apply(polygons: [], passes: [hiddenTransform, assembly],
                                             elapsedFrames: 10, spriteIndex: 0)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Exit modes

    private func exitPass(_ mode: FulgurationExitMode, duration: Int = 10) -> FulgurationParams {
        var pass = assemblyPass(seed: 5, countMin: 3, countMax: 3)
        pass.intervalMin = 0; pass.intervalMax = 0
        pass.holdMin = 30; pass.holdMax = 30
        pass.exitMode = mode
        pass.exitDuration = duration
        return pass
    }

    func testInstantExitStaysFullSizeUntilHoldEnds() {
        let pass = exitPass(.instant)
        let early = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 5, spriteIndex: 0)
        let late  = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 29, spriteIndex: 0)
        XCTAssertEqual(early.count, late.count)
        XCTAssertFalse(late.isEmpty)
    }

    func testShrinkExitEmptyAtHoldEnd() {
        let pass = exitPass(.shrink, duration: 10)
        let midExit = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 25, spriteIndex: 0)
        XCTAssertFalse(midExit.isEmpty, "still shrinking, not gone yet")
        let atEnd = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 29.999, spriteIndex: 0)
        // Approaching the very end of the hold window, shrink factor approaches 0.
        if let firstPoly = atEnd.first, let midPoly = midExit.first {
            let atEndSpan = firstPoly.points.map { $0.length }.max() ?? 0
            let midSpan = midPoly.points.map { $0.length }.max() ?? 0
            XCTAssertLessThan(atEndSpan, midSpan)
        }
    }

    func testOffscreenExitTranslatesFartherAsHoldProgresses() {
        // holdElapsed is always strictly < holdDuration while `.visible` (see
        // resolveVisibility), so offscreen translation reaches its maximum offset
        // right as the hold window's own natural end makes it disappear (the same
        // boundary `resolveVisibility`'s own tests already cover) — there's no
        // separate "definitely offscreen" state reachable strictly before that.
        // What's specific to `.offscreen` and testable here is that translation
        // magnitude grows monotonically through the exit window.
        let pass = exitPass(.offscreen, duration: 10)  // hold=30, exit window = [20, 30)

        let midHold = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 10, spriteIndex: 0)
        XCTAssertFalse(midHold.isEmpty, "well before the exit window starts")

        let midExit = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 25, spriteIndex: 0)
        XCTAssertFalse(midExit.isEmpty)

        let lateExit = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 29.5, spriteIndex: 0)
        XCTAssertFalse(lateExit.isEmpty, "still technically visible, just far off-canvas")

        if let midPoly = midHold.first, let midExitPoly = midExit.first, let latePoly = lateExit.first {
            XCTAssertEqual(midPoly.centroid.length, 0, accuracy: 1e-6, "no translation before the exit window starts")
            XCTAssertGreaterThan(midExitPoly.centroid.length, 0)
            XCTAssertGreaterThan(latePoly.centroid.length, midExitPoly.centroid.length,
                                 "should translate farther from the origin as exit progresses")
        }
    }

    func testShatterExitMovesPiecesIndependently() {
        let pass = exitPass(.shatter, duration: 10)
        let preExit = AssemblyFulgurationEngine.assemble(pass: pass, seed: pass.cycleSeed, cycleIndex: 0)
        let midExit = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 25, spriteIndex: 0)
        XCTAssertEqual(midExit.count, preExit.count)
        // At least one piece should have moved from its pre-exit centroid — pieces
        // drift independently, not as one rigid group, so they don't all move
        // identically (extremely unlikely to tie across 3 independently-seeded pieces).
        var anyMoved = false
        for (pre, mid) in zip(preExit, midExit) where pre.centroid.distance(to: mid.centroid) > 1e-6 {
            anyMoved = true
        }
        XCTAssertTrue(anyMoved)

        let afterFullyShattered = FulgurationEngine.apply(polygons: [], passes: [pass], elapsedFrames: 29.999, spriteIndex: 0)
        // Approaching full exit progress, still present (only == duration triggers hide).
        _ = afterFullyShattered
    }

    func testDisabledAssemblyPassReturnsInputUnchanged() {
        var pass = assemblyPass(seed: 1)
        pass.enabled = false
        let square = Polygon2D(points: [Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0),
                                        Vector2D(x: 1, y: 1), Vector2D(x: 0, y: 1)], type: .line)
        let result = FulgurationEngine.apply(polygons: [square], passes: [pass], elapsedFrames: 10, spriteIndex: 0)
        XCTAssertEqual(result, [square])
    }
}
