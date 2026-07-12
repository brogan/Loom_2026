import XCTest
@testable import LoomEngine

/// `.spline` case coverage for `AttachmentSiteExtractor` (2026-07-12) — previously
/// returned `[]` unconditionally for closed, curved (bezier-encoded) shapes, the
/// format the Geometry editor actually produces, meaning a user-drawn closed shape
/// could never be attached as a Graft piece at all. `.line` (straight-edged,
/// raw-vertex) and `.openSpline` sites are unaffected by this change.
final class AttachmentSiteTests: XCTestCase {

    /// A straight-sided square, encoded as `.spline` (collinear control points —
    /// no bow), corners at (0,0)-(1,0)-(1,1)-(0,1).
    private func straightSplineSquare() -> Polygon2D {
        let corners = [
            Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0),
            Vector2D(x: 1, y: 1), Vector2D(x: 0, y: 1),
        ]
        var pts = [Vector2D]()
        for i in 0..<4 {
            pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 4],
                                        cpRatios: Vector2D(x: 1.0 / 3.0, y: 2.0 / 3.0))
        }
        return Polygon2D(points: pts, type: .spline)
    }

    /// The same square, encoded as `.line` (raw vertex list) — used as the
    /// known-correct reference `lineEdgeSites` already produces.
    private func lineSquare() -> Polygon2D {
        Polygon2D(points: [
            Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0),
            Vector2D(x: 1, y: 1), Vector2D(x: 0, y: 1),
        ], type: .line)
    }

    func testSplineSitesMatchLineSitesForTheSameStraightShape() {
        let lineSites   = AttachmentSiteExtractor.sites(of: lineSquare())
        let splineSites = AttachmentSiteExtractor.sites(of: straightSplineSquare())
        XCTAssertEqual(splineSites.count, lineSites.count)
        for (l, s) in zip(lineSites, splineSites) {
            XCTAssertEqual(s.point.distance(to: l.point), 0, accuracy: 1e-9)
            XCTAssertEqual(s.direction.distance(to: l.direction), 0, accuracy: 1e-9)
            XCTAssertEqual(s.outward.distance(to: l.outward), 0, accuracy: 1e-9)
            XCTAssertEqual(s.length ?? -1, l.length ?? -2, accuracy: 1e-9)
        }
    }

    func testSplineSitesIgnoreBowAndUseTheAnchorChordOnly() {
        // Bow the square's edges outward — sites should still land at the exact
        // anchor midpoints/directions, unaffected by the control points.
        let corners = [
            Vector2D(x: 0, y: 0), Vector2D(x: 1, y: 0),
            Vector2D(x: 1, y: 1), Vector2D(x: 0, y: 1),
        ]
        var pts = [Vector2D]()
        for i in 0..<4 {
            pts += BezierMath.connector(from: corners[i], to: corners[(i + 1) % 4],
                                        cpRatios: Vector2D(x: 1.0 / 3.0, y: 2.0 / 3.0),
                                        cpNormalOffsets: Vector2D(x: 0.3, y: 0.3))
        }
        let bowed = Polygon2D(points: pts, type: .spline)
        let straight = straightSplineSquare()

        let bowedSites    = AttachmentSiteExtractor.sites(of: bowed)
        let straightSites = AttachmentSiteExtractor.sites(of: straight)
        XCTAssertEqual(bowedSites.count, straightSites.count)
        for (b, s) in zip(bowedSites, straightSites) {
            XCTAssertEqual(b.point.distance(to: s.point), 0, accuracy: 1e-9,
                            "site midpoint must come from the anchor chord, not the bowed control points")
            XCTAssertEqual(b.length ?? -1, s.length ?? -2, accuracy: 1e-9)
        }
    }

    func testSplineSitesOutwardPointsAwayFromCentroid() {
        let sites = AttachmentSiteExtractor.sites(of: straightSplineSquare())
        let centre = BezierMath.centreSpline(straightSplineSquare().points)
        for site in sites {
            let toSite = site.point - centre
            XCTAssertGreaterThan(site.outward.dot(toSite), 0,
                                  "outward normal should point away from the shape's own centre")
        }
    }

    func testSplineSitesLengthMatchesEachSegmentsChordLength() {
        let square = straightSplineSquare()
        let sites = AttachmentSiteExtractor.sites(of: square)
        for site in sites {
            XCTAssertEqual(site.length ?? -1, 1.0, accuracy: 1e-9, "unit square: every edge is exactly length 1")
        }
    }

    func testOpenSplineAndLineSitesAreUnaffectedByTheSplineCaseAddition() {
        // Regression: adding `.spline` support must not touch the existing
        // `.line`/`.openSpline` code paths at all.
        let line = lineSquare()
        XCTAssertEqual(AttachmentSiteExtractor.sites(of: line).count, 4)

        let openCurve = Polygon2D(points: [
            Vector2D(x: 0, y: 0), Vector2D(x: 0.33, y: 0),
            Vector2D(x: 0.67, y: 0), Vector2D(x: 1, y: 0),
        ], type: .openSpline)
        let openSites = AttachmentSiteExtractor.sites(of: openCurve)
        XCTAssertEqual(openSites.count, 2, "an open curve exposes exactly its 2 endpoint sites")
        XCTAssertNil(openSites[0].length, "endpoint sites have no length")
    }

    func testPointAndOvalStillExposeNoSites() {
        XCTAssertTrue(AttachmentSiteExtractor.sites(of: Polygon2D(points: [.zero], type: .point)).isEmpty)
        XCTAssertTrue(AttachmentSiteExtractor.sites(of: Polygon2D(points: [.zero, Vector2D(x: 1, y: 1)], type: .oval)).isEmpty)
    }
}
