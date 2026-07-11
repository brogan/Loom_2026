import Foundation

/// V3 Fulguration content mode (`contentMode == .assembly`) — see
/// Specs/GeometricLifecycle.md §5.12. Builds a flash's content by combinatorially
/// attaching pieces drawn from `AssemblyPrimitiveKit`, rather than transforming the
/// sprite's own resolved geometry (that's `FulgurationEngine`'s `.transform` path).
enum AssemblyFulgurationEngine {

    /// Every roll this cycle needs, in one `centreHash` namespace: piece count (1),
    /// then per-piece kind/size/deformX/deformY/targetSite/sourceSite/mirror (7 per
    /// piece). `cycleIndex * rollStride` keeps every cycle's rolls disjoint from every
    /// other cycle's, same spacing idea `FulgurationEngine.sampleTransform` already
    /// uses with `cycleIndex * 8`.
    private static let rollStride = 1 + 7 * 64   // headroom for up to 64 pieces/cycle

    /// Deterministic per-cycle assembly (§5.12.4): same `(seed, cycleIndex)` always
    /// produces the identical piece list, no incremental state — matching the
    /// stateless-per-frame requirement (§5.9) V1 already satisfies.
    static func assemble(pass: FulgurationParams, seed: Int, cycleIndex: Int) -> [Polygon2D] {
        let base = cycleIndex * rollStride

        let countLo = min(pass.assemblyPieceCountMin, pass.assemblyPieceCountMax)
        let countHi = max(pass.assemblyPieceCountMin, pass.assemblyPieceCountMax)
        let countRoll = SubdivisionEngine.centreHash(seed: seed, cycle: base)
        let pieceCount = max(1, countLo + Int(countRoll * Double(countHi - countLo + 1)))

        let kinds = AssemblyPrimitiveKind.allCases
        let sizeLo = min(pass.assemblySizeMin, pass.assemblySizeMax)
        let sizeHi = max(pass.assemblySizeMin, pass.assemblySizeMax)
        let deformLo = min(pass.assemblyDeformMin, pass.assemblyDeformMax)
        let deformHi = max(pass.assemblyDeformMin, pass.assemblyDeformMax)

        var placed: [Polygon2D] = []
        placed.reserveCapacity(pieceCount)

        for pieceIndex in 0..<pieceCount {
            let rollBase = base + 1 + pieceIndex * 7

            let kindRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 0)
            let kind = kinds[min(kinds.count - 1, Int(kindRoll * Double(kinds.count)))]
            var piece = AssemblyPrimitiveKit.generate(kind)

            // Uniform size (independent of the x/y deform below) — applied first so
            // "size" and "deform" compose as size-then-shape-variation rather than
            // interacting asymmetrically.
            let sizeRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 1)
            let size = sizeLo + sizeRoll * (sizeHi - sizeLo)

            let sxRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 2)
            let syRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 3)
            let sx = deformLo + sxRoll * (deformHi - deformLo)
            let sy = deformLo + syRoll * (deformHi - deformLo)
            piece = AssemblyPrimitiveKit.deformed(piece, scaleX: size * sx, scaleY: size * sy)

            guard pieceIndex > 0 else {
                placed.append(piece)
                continue
            }

            let existingSites: [AttachmentSite] = placed.flatMap { AttachmentSiteExtractor.sites(of: $0) }
            let incomingSites = AttachmentSiteExtractor.sites(of: piece)
            guard !existingSites.isEmpty, !incomingSites.isEmpty else {
                // Nothing to attach to/from (degenerate piece) — still counted, placed
                // at the origin rather than dropped, so pieceCount stays meaningful.
                placed.append(piece)
                continue
            }

            let targetRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 4)
            let target = existingSites[min(existingSites.count - 1, Int(targetRoll * Double(existingSites.count)))]

            let sourceRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 5)
            let source = incomingSites[min(incomingSites.count - 1, Int(sourceRoll * Double(incomingSites.count)))]

            let mirrorRoll = SubdivisionEngine.centreHash(seed: seed, cycle: rollBase + 6)
            let mirror = mirrorRoll < 0.5

            piece = place(piece, sourceSite: source, onto: target,
                         mirror: mirror, edgeMatching: pass.assemblyEdgeMatching)
            placed.append(piece)
        }

        return placed
    }

    // MARK: - Placement

    /// Rigid-transforms `piece` (rotate, optionally mirror and scale, then translate)
    /// so `sourceSite` lands on `targetSite`, on the target's outward side (§5.12.4
    /// step 3). Internal (not `private`) so it's directly unit-testable, same
    /// convention as `ExtensionEngine.outwardNormal`.
    static func place(
        _ piece:        Polygon2D,
        sourceSite:     AttachmentSite,
        onto targetSite: AttachmentSite,
        mirror:         Bool,
        edgeMatching:   AssemblyEdgeMatching
    ) -> Polygon2D {
        var pts = piece.points
        var sourceOutward = sourceSite.outward

        if mirror {
            pts = pts.map { reflect($0, throughPoint: sourceSite.point, direction: sourceSite.direction) }
            sourceOutward = -sourceOutward
        }

        if edgeMatching == .matchLength,
           let sourceLength = sourceSite.length, sourceLength > 1e-9,
           let targetLength = targetSite.length, targetLength > 1e-9 {
            let factor = targetLength / sourceLength
            pts = pts.map { p in
                Vector2D(
                    x: sourceSite.point.x + (p.x - sourceSite.point.x) * factor,
                    y: sourceSite.point.y + (p.y - sourceSite.point.y) * factor
                )
            }
        }

        // Rotate so the (possibly mirrored) source site's outward direction becomes
        // antiparallel to the target's — the incoming piece ends up on the target's
        // outward side, back-to-back at the shared point.
        let angle = (-targetSite.outward).angle - sourceOutward.angle
        let cosT = cos(angle), sinT = sin(angle)
        pts = pts.map { p in
            let rx = p.x - sourceSite.point.x, ry = p.y - sourceSite.point.y
            return Vector2D(x: sourceSite.point.x + rx * cosT - ry * sinT,
                            y: sourceSite.point.y + rx * sinT + ry * cosT)
        }

        let delta = targetSite.point - sourceSite.point
        pts = pts.map { $0 + delta }

        return Polygon2D(points: pts, type: piece.type,
                         pressures: piece.pressures,
                         pressureProfiles: piece.pressureProfiles,
                         visible: piece.visible)
    }

    /// Reflects `p` across the line through `point` in `direction` (must be a unit
    /// vector) — used for the optional mirror roll in `place`.
    private static func reflect(_ p: Vector2D, throughPoint point: Vector2D, direction: Vector2D) -> Vector2D {
        let d = p - point
        let parallel = direction * d.dot(direction)
        let perpendicular = d - parallel
        return point + parallel - perpendicular
    }
}
