import Foundation

public typealias EditableGeometryID = UUID

private extension Vector2D {
    // Editor space and runtime world space both use Y-UP (positive Y = up).
    // These are identity transforms; they exist so call sites are explicit about
    // the conceptual boundary, and so the v1 → v2 JSON migration can negate Y
    // on load without touching call sites.
    func runtimeWorldToEditor() -> Vector2D { self }
    func editorToRuntimeWorld() -> Vector2D { self }
    func mirroredY() -> Vector2D { Vector2D(x: x, y: -y) }
}

public enum EditablePointKind: String, Codable, Equatable, Sendable {
    case anchor
    case control
}

public struct EditableCubicPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: EditableGeometryID
    public var position: Vector2D
    public var kind: EditablePointKind

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        position: Vector2D,
        kind: EditablePointKind
    ) {
        self.id = id
        self.position = position
        self.kind = kind
    }
}

public struct EditableCubicSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: EditableGeometryID
    public var startAnchorID: EditableGeometryID
    public var controlOutID: EditableGeometryID
    public var controlInID: EditableGeometryID
    public var endAnchorID: EditableGeometryID

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        startAnchorID: EditableGeometryID,
        controlOutID: EditableGeometryID,
        controlInID: EditableGeometryID,
        endAnchorID: EditableGeometryID
    ) {
        self.id = id
        self.startAnchorID = startAnchorID
        self.controlOutID = controlOutID
        self.controlInID = controlInID
        self.endAnchorID = endAnchorID
    }

    public var pointIDs: [EditableGeometryID] {
        [startAnchorID, controlOutID, controlInID, endAnchorID]
    }
}

public enum EditableGeometryError: Error, Equatable, LocalizedError {
    case missingPoint(EditableGeometryID)
    case invalidSplinePointCount(Int)
    case unsupportedPolygonType(PolygonType)

    public var errorDescription: String? {
        switch self {
        case .missingPoint(let id):
            return "Editable geometry is missing point \(id)."
        case .invalidSplinePointCount(let count):
            return "Closed spline point count must be a non-zero multiple of 4; got \(count)."
        case .unsupportedPolygonType(let type):
            return "Editable closed polygons only support spline geometry; got \(type)."
        }
    }
}

public enum EditableAnchorDeletionResult: Equatable, Sendable {
    case closedPolygon(EditableClosedPolygon)
    case openCurve(EditableOpenCurve)
}

public struct EditableRegularPolygonParameters: Codable, Equatable, Sendable {
    public var sides: Int
    public var centre: Vector2D
    public var radius: Double
    public var innerRadius: Double
    public var scaleX: Double
    public var scaleY: Double
    /// Default `.pi / 2.0` places vertex 0 straight up (`+Y`), matching the
    /// Y-UP convention both the editor and runtime use (see the `Vector2D`
    /// editor/runtime extension above). Do not "fix" this back to `-.pi / 2.0` —
    /// that was the value before the Y-axis-flip fix (commit `ed0f3234`), when a
    /// compensating negation elsewhere made it *look* correct; without that
    /// negation it points vertex 0 straight down instead.
    public var rotationRadians: Double

    public init(
        sides: Int,
        centre: Vector2D = .zero,
        radius: Double = 0.3,
        innerRadius: Double = 1.0,
        scaleX: Double = 1.0,
        scaleY: Double = 1.0,
        rotationRadians: Double = .pi / 2.0
    ) {
        self.sides = sides
        self.centre = centre
        self.radius = radius
        self.innerRadius = innerRadius
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotationRadians = rotationRadians
    }
}

public enum EditableParametricSource: Codable, Equatable, Sendable {
    case regularPolygon(EditableRegularPolygonParameters)
}

public struct EditableClosedPolygon: Codable, Equatable, Identifiable, Sendable {
    public var id: EditableGeometryID
    public var name: String
    public var points: [EditableCubicPoint]
    public var segments: [EditableCubicSegment]
    public var pressures: [Double]
    public var segmentPressureProfiles: [EditableGeometryID: [Double]]?
    public var isVisible: Bool
    public var parametricSource: EditableParametricSource?

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        name: String,
        points: [EditableCubicPoint] = [],
        segments: [EditableCubicSegment] = [],
        pressures: [Double] = [],
        segmentPressureProfiles: [EditableGeometryID: [Double]]? = nil,
        isVisible: Bool = true,
        parametricSource: EditableParametricSource? = nil
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.segments = segments
        self.pressures = pressures
        self.segmentPressureProfiles = segmentPressureProfiles
        self.isVisible = isVisible
        self.parametricSource = parametricSource
    }

    public init(name: String, polygon: Polygon2D) throws {
        guard polygon.type == .spline else {
            throw EditableGeometryError.unsupportedPolygonType(polygon.type)
        }
        guard !polygon.points.isEmpty, polygon.points.count.isMultiple(of: 4) else {
            throw EditableGeometryError.invalidSplinePointCount(polygon.points.count)
        }

        self.id = EditableGeometryID()
        self.name = name
        self.points = []
        self.segments = []
        self.pressures = polygon.pressures
        self.segmentPressureProfiles = nil
        self.isVisible = polygon.visible
        self.parametricSource = nil

        var previousEndAnchorID: EditableGeometryID?
        for segmentIndex in stride(from: 0, to: polygon.points.count, by: 4) {
            let startAnchorID: EditableGeometryID
            if let previousEndAnchorID {
                startAnchorID = previousEndAnchorID
            } else {
                let point = EditableCubicPoint(
                    position: polygon.points[segmentIndex].runtimeWorldToEditor(),
                    kind: .anchor
                )
                points.append(point)
                startAnchorID = point.id
            }

            let controlOut = EditableCubicPoint(
                position: polygon.points[segmentIndex + 1].runtimeWorldToEditor(),
                kind: .control
            )
            let controlIn = EditableCubicPoint(
                position: polygon.points[segmentIndex + 2].runtimeWorldToEditor(),
                kind: .control
            )
            let endAnchor = EditableCubicPoint(
                position: polygon.points[segmentIndex + 3].runtimeWorldToEditor(),
                kind: .anchor
            )
            points.append(contentsOf: [controlOut, controlIn, endAnchor])

            segments.append(
                EditableCubicSegment(
                    startAnchorID: startAnchorID,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: endAnchor.id
                )
            )
            previousEndAnchorID = endAnchor.id
        }

        if segments.count > 1,
           let firstStart = segments.first?.startAnchorID,
           let lastEnd = segments.last?.endAnchorID,
           let firstPoint = point(id: firstStart),
           let lastPoint = point(id: lastEnd),
           firstPoint.position == lastPoint.position {
            replacePointReferences(from: lastEnd, to: firstStart)
            points.removeAll { $0.id == lastEnd }
        }
        self.segmentPressureProfiles = editablePressureProfiles(
            polygon.pressureProfiles,
            segments: segments
        )
    }

    public init(name: String, anchors: [Vector2D]) throws {
        guard anchors.count >= 3 else {
            throw EditableGeometryError.invalidSplinePointCount(anchors.count)
        }

        self.id = EditableGeometryID()
        self.name = name
        self.points = []
        self.segments = []
        self.pressures = Array(repeating: 1.0, count: anchors.count)
        self.segmentPressureProfiles = nil
        self.isVisible = true
        self.parametricSource = nil

        let anchorPoints = anchors.map { EditableCubicPoint(position: $0, kind: .anchor) }
        points.append(contentsOf: anchorPoints)
        for index in anchors.indices {
            let a0 = anchors[index]
            let a1 = anchors[(index + 1) % anchors.count]
            let delta = a1 - a0
            let controlOut = EditableCubicPoint(position: a0 + delta * (1.0 / 3.0), kind: .control)
            let controlIn = EditableCubicPoint(position: a0 + delta * (2.0 / 3.0), kind: .control)
            points.append(contentsOf: [controlOut, controlIn])
            segments.append(
                EditableCubicSegment(
                    startAnchorID: anchorPoints[index].id,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: anchorPoints[(index + 1) % anchors.count].id
                )
            )
        }
    }

    public init(
        name: String,
        regularPolygonSides sides: Int,
        centre: Vector2D = .zero,
        radius: Double = 0.3,
        innerRadius: Double = 1.0,
        scaleX: Double = 1.0,
        scaleY: Double = 1.0,
        rotationRadians: Double = .pi / 2.0
    ) throws {
        let parameters = EditableRegularPolygonParameters(
            sides: sides,
            centre: centre,
            radius: radius,
            innerRadius: innerRadius,
            scaleX: scaleX,
            scaleY: scaleY,
            rotationRadians: rotationRadians
        )
        try self.init(name: name, regularPolygonParameters: parameters)
    }

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        name: String,
        regularPolygonParameters parameters: EditableRegularPolygonParameters,
        isVisible: Bool = true
    ) throws {
        let anchors = try Self.regularPolygonAnchors(parameters)
        try self.init(name: name, anchors: anchors)
        self.id = id
        self.isVisible = isVisible
        self.parametricSource = .regularPolygon(parameters)
    }

    public init(
        name: String,
        ovalCentre centre: Vector2D = .zero,
        radiusX: Double = 0.28,
        radiusY: Double = 0.2
    ) {
        let kappa = 0.552_284_749_830_793_6
        let top = EditableCubicPoint(position: Vector2D(x: centre.x, y: centre.y - radiusY), kind: .anchor)
        let right = EditableCubicPoint(position: Vector2D(x: centre.x + radiusX, y: centre.y), kind: .anchor)
        let bottom = EditableCubicPoint(position: Vector2D(x: centre.x, y: centre.y + radiusY), kind: .anchor)
        let left = EditableCubicPoint(position: Vector2D(x: centre.x - radiusX, y: centre.y), kind: .anchor)

        let topToRightOut = EditableCubicPoint(position: Vector2D(x: centre.x + kappa * radiusX, y: centre.y - radiusY), kind: .control)
        let topToRightIn = EditableCubicPoint(position: Vector2D(x: centre.x + radiusX, y: centre.y - kappa * radiusY), kind: .control)
        let rightToBottomOut = EditableCubicPoint(position: Vector2D(x: centre.x + radiusX, y: centre.y + kappa * radiusY), kind: .control)
        let rightToBottomIn = EditableCubicPoint(position: Vector2D(x: centre.x + kappa * radiusX, y: centre.y + radiusY), kind: .control)
        let bottomToLeftOut = EditableCubicPoint(position: Vector2D(x: centre.x - kappa * radiusX, y: centre.y + radiusY), kind: .control)
        let bottomToLeftIn = EditableCubicPoint(position: Vector2D(x: centre.x - radiusX, y: centre.y + kappa * radiusY), kind: .control)
        let leftToTopOut = EditableCubicPoint(position: Vector2D(x: centre.x - radiusX, y: centre.y - kappa * radiusY), kind: .control)
        let leftToTopIn = EditableCubicPoint(position: Vector2D(x: centre.x - kappa * radiusX, y: centre.y - radiusY), kind: .control)

        self.init(
            name: name,
            points: [
                top, topToRightOut, topToRightIn, right,
                rightToBottomOut, rightToBottomIn, bottom,
                bottomToLeftOut, bottomToLeftIn, left,
                leftToTopOut, leftToTopIn
            ],
            segments: [
                EditableCubicSegment(
                    startAnchorID: top.id,
                    controlOutID: topToRightOut.id,
                    controlInID: topToRightIn.id,
                    endAnchorID: right.id
                ),
                EditableCubicSegment(
                    startAnchorID: right.id,
                    controlOutID: rightToBottomOut.id,
                    controlInID: rightToBottomIn.id,
                    endAnchorID: bottom.id
                ),
                EditableCubicSegment(
                    startAnchorID: bottom.id,
                    controlOutID: bottomToLeftOut.id,
                    controlInID: bottomToLeftIn.id,
                    endAnchorID: left.id
                ),
                EditableCubicSegment(
                    startAnchorID: left.id,
                    controlOutID: leftToTopOut.id,
                    controlInID: leftToTopIn.id,
                    endAnchorID: top.id
                )
            ],
            pressures: Array(repeating: 1.0, count: 4),
            isVisible: true,
            parametricSource: nil
        )
    }

    public func regeneratedFromParametricSource(
        _ source: EditableParametricSource
    ) throws -> EditableClosedPolygon {
        switch source {
        case .regularPolygon(let parameters):
            return try EditableClosedPolygon(
                id: id,
                name: name,
                regularPolygonParameters: parameters,
                isVisible: isVisible
            )
        }
    }

    public func withoutParametricSource() -> EditableClosedPolygon {
        var copy = self
        copy.parametricSource = nil
        return copy
    }

    private static func regularPolygonAnchors(
        _ parameters: EditableRegularPolygonParameters
    ) throws -> [Vector2D] {
        guard parameters.sides >= 3 else {
            throw EditableGeometryError.invalidSplinePointCount(parameters.sides)
        }
        let isStar = parameters.innerRadius < 0.999
        let vertexCount = isStar ? parameters.sides * 2 : parameters.sides
        let angleStep = 2.0 * .pi / Double(vertexCount)
        return (0..<vertexCount).map { index in
            let radius = isStar && index % 2 == 1
                ? parameters.radius * parameters.innerRadius
                : parameters.radius
            let angle = parameters.rotationRadians + Double(index) * angleStep
            return Vector2D(
                x: parameters.centre.x + Foundation.cos(angle) * radius * parameters.scaleX,
                y: parameters.centre.y + Foundation.sin(angle) * radius * parameters.scaleY
            )
        }
    }

    public var anchorIDs: [EditableGeometryID] {
        var ids: [EditableGeometryID] = []
        for segment in segments where !ids.contains(segment.startAnchorID) {
            ids.append(segment.startAnchorID)
        }
        if let lastEnd = segments.last?.endAnchorID, !ids.contains(lastEnd) {
            ids.append(lastEnd)
        }
        return ids
    }

    public func point(id: EditableGeometryID) -> EditableCubicPoint? {
        points.first { $0.id == id }
    }

    public mutating func setPointPosition(id: EditableGeometryID, to position: Vector2D) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        points[index].position = position
    }

    public mutating func translatePoint(id: EditableGeometryID, by delta: Vector2D) {
        guard let point = point(id: id) else { return }
        setPointPosition(id: id, to: point.position + delta)
    }

    public mutating func moveAnchorWithAttachedControls(id: EditableGeometryID, to position: Vector2D) {
        guard let anchor = point(id: id), anchor.kind == .anchor else { return }
        let delta = position - anchor.position
        setPointPosition(id: id, to: position)
        translateControlsAttached(to: id, by: delta)
    }

    public mutating func resetControlsToInferredPositions(segmentIDs ids: Set<EditableGeometryID>? = nil) {
        let selected = ids ?? Set(segments.map(\.id))
        for segment in segments where selected.contains(segment.id) {
            resetControlsToInferredPositions(segmentID: segment.id)
        }
    }

    public func segmentIDs(containingPoint pointID: EditableGeometryID) -> Set<EditableGeometryID> {
        Set(segments.filter { $0.pointIDs.contains(pointID) }.map(\.id))
    }

    public func segmentIDs(touchingSegmentIDs ids: Set<EditableGeometryID>) -> Set<EditableGeometryID> {
        let anchors = Set(segments.filter { ids.contains($0.id) }.flatMap { [$0.startAnchorID, $0.endAnchorID] })
        guard !anchors.isEmpty else { return [] }
        return Set(segments.filter {
            anchors.contains($0.startAnchorID) || anchors.contains($0.endAnchorID)
        }.map(\.id))
    }

    public func attachedControlIDs(forSegment segment: EditableCubicSegment) -> Set<EditableGeometryID> {
        var ids = Set(segment.pointIDs)
        for neighbour in segments {
            if neighbour.startAnchorID == segment.startAnchorID { ids.insert(neighbour.controlOutID) }
            if neighbour.endAnchorID == segment.startAnchorID { ids.insert(neighbour.controlInID) }
            if neighbour.startAnchorID == segment.endAnchorID { ids.insert(neighbour.controlOutID) }
            if neighbour.endAnchorID == segment.endAnchorID { ids.insert(neighbour.controlInID) }
        }
        return ids
    }

    public mutating func translateSegment(id segmentID: EditableGeometryID, by delta: Vector2D) {
        guard let segment = segments.first(where: { $0.id == segmentID }),
              let start = point(id: segment.startAnchorID)?.position,
              let end = point(id: segment.endAnchorID)?.position
        else { return }
        moveAnchorWithAttachedControls(id: segment.startAnchorID, to: start + delta)
        moveAnchorWithAttachedControls(id: segment.endAnchorID, to: end + delta)
    }

    public func translated(by delta: Vector2D) -> EditableClosedPolygon {
        var copy = self
        copy.points = points.map { point in
            var next = point
            next.position = point.position + delta
            return next
        }
        if case .regularPolygon(var parameters) = copy.parametricSource {
            parameters.centre = parameters.centre + delta
            copy.parametricSource = .regularPolygon(parameters)
        }
        return copy
    }

    public func duplicated(name: String? = nil) -> EditableClosedPolygon {
        var pointIDMap: [EditableGeometryID: EditableGeometryID] = [:]
        let copiedPoints = points.map { point in
            let copiedID = EditableGeometryID()
            pointIDMap[point.id] = copiedID
            return EditableCubicPoint(id: copiedID, position: point.position, kind: point.kind)
        }
        var segmentIDMap: [EditableGeometryID: EditableGeometryID] = [:]
        let copiedSegments = segments.map { segment in
            let copiedID = EditableGeometryID()
            segmentIDMap[segment.id] = copiedID
            return EditableCubicSegment(
                id: copiedID,
                startAnchorID: pointIDMap[segment.startAnchorID] ?? segment.startAnchorID,
                controlOutID: pointIDMap[segment.controlOutID] ?? segment.controlOutID,
                controlInID: pointIDMap[segment.controlInID] ?? segment.controlInID,
                endAnchorID: pointIDMap[segment.endAnchorID] ?? segment.endAnchorID
            )
        }
        return EditableClosedPolygon(
            name: name ?? self.name,
            points: copiedPoints,
            segments: copiedSegments,
            pressures: pressures,
            segmentPressureProfiles: remappedPressureProfiles(using: segmentIDMap),
            isVisible: isVisible,
            parametricSource: parametricSource
        )
    }

    public func deletingAnchor(id anchorID: EditableGeometryID) -> EditableAnchorDeletionResult? {
        guard let anchor = point(id: anchorID), anchor.kind == .anchor else { return nil }
        let anchors = anchorIDs
        guard let deletedIndex = anchors.firstIndex(of: anchorID), anchors.count >= 3 else { return nil }
        let remainingAnchors = anchors.filter { $0 != anchorID }
        let pointMap = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0) })

        if remainingAnchors.count == 2 {
            let remaining = Set(remainingAnchors)
            guard let segment = segments.first(where: {
                remaining.contains($0.startAnchorID) && remaining.contains($0.endAnchorID)
            }) else { return nil }
            return .openCurve(
                EditableOpenCurve(
                    name: "\(name) Open",
                    points: points,
                    segments: [segment],
                    pressures: [pressures.indices.contains(0) ? pressures[0] : 1.0],
                    isVisible: isVisible
                ).prunedToReferencedPoints()
            )
        }

        let deletedPrevious = anchors[(deletedIndex - 1 + anchors.count) % anchors.count]
        let deletedNext = anchors[(deletedIndex + 1) % anchors.count]
        var rebuiltPoints: [EditableCubicPoint] = []
        var rebuiltSegments: [EditableCubicSegment] = []

        func appendPointIfNeeded(_ point: EditableCubicPoint) {
            if !rebuiltPoints.contains(where: { $0.id == point.id }) {
                rebuiltPoints.append(point)
            }
        }

        for index in remainingAnchors.indices {
            let startAnchorID = remainingAnchors[index]
            let endAnchorID = remainingAnchors[(index + 1) % remainingAnchors.count]
            guard let startAnchor = pointMap[startAnchorID],
                  let endAnchor = pointMap[endAnchorID]
            else { return nil }

            appendPointIfNeeded(startAnchor)
            if startAnchorID == deletedPrevious && endAnchorID == deletedNext {
                let delta = endAnchor.position - startAnchor.position
                let controlOut = EditableCubicPoint(position: startAnchor.position + delta * (1.0 / 3.0), kind: .control)
                let controlIn = EditableCubicPoint(position: startAnchor.position + delta * (2.0 / 3.0), kind: .control)
                rebuiltPoints.append(contentsOf: [controlOut, controlIn])
                rebuiltSegments.append(
                    EditableCubicSegment(
                        startAnchorID: startAnchorID,
                        controlOutID: controlOut.id,
                        controlInID: controlIn.id,
                        endAnchorID: endAnchorID
                    )
                )
            } else {
                guard let segment = segments.first(where: {
                    $0.startAnchorID == startAnchorID && $0.endAnchorID == endAnchorID
                }),
                      let controlOut = pointMap[segment.controlOutID],
                      let controlIn = pointMap[segment.controlInID]
                else { return nil }
                rebuiltPoints.append(contentsOf: [controlOut, controlIn])
                rebuiltSegments.append(segment)
            }
            appendPointIfNeeded(endAnchor)
        }

        return .closedPolygon(
            EditableClosedPolygon(
                id: id,
                name: name,
                points: rebuiltPoints,
                segments: rebuiltSegments,
                pressures: Array(repeating: 1.0, count: rebuiltSegments.count),
                isVisible: isVisible
            )
        )
    }

    public func deletingSegment(id segmentID: EditableGeometryID) -> EditableOpenCurve? {
        guard let deletedIndex = segments.firstIndex(where: { $0.id == segmentID }),
              segments.count >= 2
        else { return nil }
        let orderedSegments = Array(segments[(deletedIndex + 1)..<segments.count]) + Array(segments[0..<deletedIndex])
        return EditableOpenCurve(
            name: "\(name) Open",
            points: points,
            segments: orderedSegments,
            pressures: Array(repeating: 1.0, count: orderedSegments.count),
            isVisible: isVisible
        ).prunedToReferencedPoints()
    }

    public func toPolygon2D() throws -> Polygon2D {
        let pointMap = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0.position) })
        var encoded: [Vector2D] = []
        encoded.reserveCapacity(segments.count * 4)
        for segment in segments {
            for id in segment.pointIDs {
                guard let position = pointMap[id] else {
                    throw EditableGeometryError.missingPoint(id)
                }
                encoded.append(position.editorToRuntimeWorld())
            }
        }
        return Polygon2D(
            points: encoded,
            type: .spline,
            pressures: pressures,
            pressureProfiles: runtimePressureProfiles(),
            visible: isVisible
        )
    }

    public func pressureProfile(for segmentID: EditableGeometryID) -> [Double]? {
        segmentPressureProfiles?[segmentID]
    }

    public mutating func setPressureProfile(_ samples: [Double]?, for segmentID: EditableGeometryID) {
        if let samples, !samples.isEmpty {
            var profiles = segmentPressureProfiles ?? [:]
            profiles[segmentID] = samples
            segmentPressureProfiles = profiles
        } else {
            segmentPressureProfiles?[segmentID] = nil
            if segmentPressureProfiles?.isEmpty == true {
                segmentPressureProfiles = nil
            }
        }
    }

    private func runtimePressureProfiles() -> [[Double]]? {
        guard let segmentPressureProfiles, !segmentPressureProfiles.isEmpty else { return nil }
        let profiles = segments.map { segment in segmentPressureProfiles[segment.id] ?? [] }
        return profiles.contains { !$0.isEmpty } ? profiles : nil
    }

    private func remappedPressureProfiles(using segmentIDMap: [EditableGeometryID: EditableGeometryID]) -> [EditableGeometryID: [Double]]? {
        guard let segmentPressureProfiles, !segmentPressureProfiles.isEmpty else { return nil }
        var remapped: [EditableGeometryID: [Double]] = [:]
        for (oldID, samples) in segmentPressureProfiles {
            if let newID = segmentIDMap[oldID] {
                remapped[newID] = samples
            }
        }
        return remapped.isEmpty ? nil : remapped
    }

    private mutating func replacePointReferences(from oldID: EditableGeometryID, to newID: EditableGeometryID) {
        for index in segments.indices {
            if segments[index].startAnchorID == oldID { segments[index].startAnchorID = newID }
            if segments[index].controlOutID == oldID { segments[index].controlOutID = newID }
            if segments[index].controlInID == oldID { segments[index].controlInID = newID }
            if segments[index].endAnchorID == oldID { segments[index].endAnchorID = newID }
        }
    }

    private mutating func translateControlsAttached(to anchorID: EditableGeometryID, by delta: Vector2D) {
        for segment in segments {
            if segment.startAnchorID == anchorID {
                translatePoint(id: segment.controlOutID, by: delta)
            }
            if segment.endAnchorID == anchorID {
                translatePoint(id: segment.controlInID, by: delta)
            }
        }
    }

    private mutating func resetControlsToInferredPositions(segmentID: EditableGeometryID) {
        guard let segment = segments.first(where: { $0.id == segmentID }),
              let start = point(id: segment.startAnchorID)?.position,
              let end = point(id: segment.endAnchorID)?.position
        else { return }
        let delta = end - start
        setPointPosition(id: segment.controlOutID, to: start + delta * (1.0 / 3.0))
        setPointPosition(id: segment.controlInID, to: start + delta * (2.0 / 3.0))
    }
}

public struct EditableOpenCurve: Codable, Equatable, Identifiable, Sendable {
    public var id: EditableGeometryID
    public var name: String
    public var points: [EditableCubicPoint]
    public var segments: [EditableCubicSegment]
    public var pressures: [Double]
    public var segmentPressureProfiles: [EditableGeometryID: [Double]]?
    public var isVisible: Bool

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        name: String,
        points: [EditableCubicPoint] = [],
        segments: [EditableCubicSegment] = [],
        pressures: [Double] = [],
        segmentPressureProfiles: [EditableGeometryID: [Double]]? = nil,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.segments = segments
        self.pressures = pressures
        self.segmentPressureProfiles = segmentPressureProfiles
        self.isVisible = isVisible
    }

    public init(name: String, anchors: [Vector2D], isVisible: Bool = true) {
        self.id = EditableGeometryID()
        self.name = name
        self.points = []
        self.segments = []
        self.pressures = Array(repeating: 1.0, count: max(0, anchors.count - 1))
        self.segmentPressureProfiles = nil
        self.isVisible = isVisible

        guard anchors.count >= 2 else { return }
        let firstAnchor = EditableCubicPoint(position: anchors[0], kind: .anchor)
        points.append(firstAnchor)
        var previousAnchorID = firstAnchor.id
        for index in 0..<(anchors.count - 1) {
            let start = anchors[index]
            let end = anchors[index + 1]
            let delta = end - start
            let controlOut = EditableCubicPoint(position: start + delta * (1.0 / 3.0), kind: .control)
            let controlIn = EditableCubicPoint(position: start + delta * (2.0 / 3.0), kind: .control)
            let endAnchor = EditableCubicPoint(position: end, kind: .anchor)
            points.append(contentsOf: [controlOut, controlIn, endAnchor])
            segments.append(
                EditableCubicSegment(
                    startAnchorID: previousAnchorID,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: endAnchor.id
                )
            )
            previousAnchorID = endAnchor.id
        }
    }

    public init(name: String, polygon: Polygon2D) throws {
        guard polygon.type == .openSpline else {
            throw EditableGeometryError.unsupportedPolygonType(polygon.type)
        }
        guard !polygon.points.isEmpty, polygon.points.count.isMultiple(of: 4) else {
            throw EditableGeometryError.invalidSplinePointCount(polygon.points.count)
        }

        self.id = EditableGeometryID()
        self.name = name
        self.points = []
        self.segments = []
        self.pressures = polygon.pressures
        self.segmentPressureProfiles = nil
        self.isVisible = polygon.visible

        var previousEndAnchorID: EditableGeometryID?
        for segmentIndex in stride(from: 0, to: polygon.points.count, by: 4) {
            let startAnchorID: EditableGeometryID
            if let previousEndAnchorID {
                startAnchorID = previousEndAnchorID
            } else {
                let point = EditableCubicPoint(
                    position: polygon.points[segmentIndex].runtimeWorldToEditor(),
                    kind: .anchor
                )
                points.append(point)
                startAnchorID = point.id
            }

            let controlOut = EditableCubicPoint(
                position: polygon.points[segmentIndex + 1].runtimeWorldToEditor(),
                kind: .control
            )
            let controlIn = EditableCubicPoint(
                position: polygon.points[segmentIndex + 2].runtimeWorldToEditor(),
                kind: .control
            )
            let endAnchor = EditableCubicPoint(
                position: polygon.points[segmentIndex + 3].runtimeWorldToEditor(),
                kind: .anchor
            )
            points.append(contentsOf: [controlOut, controlIn, endAnchor])
            segments.append(
                EditableCubicSegment(
                    startAnchorID: startAnchorID,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: endAnchor.id
                )
            )
            previousEndAnchorID = endAnchor.id
        }
        self.segmentPressureProfiles = editablePressureProfiles(
            polygon.pressureProfiles,
            segments: segments
        )
    }

    public var anchorIDs: [EditableGeometryID] {
        var ids: [EditableGeometryID] = []
        for segment in segments where !ids.contains(segment.startAnchorID) {
            ids.append(segment.startAnchorID)
        }
        if let lastEnd = segments.last?.endAnchorID, !ids.contains(lastEnd) {
            ids.append(lastEnd)
        }
        return ids
    }

    public func point(id: EditableGeometryID) -> EditableCubicPoint? {
        points.first { $0.id == id }
    }

    public mutating func setPointPosition(id: EditableGeometryID, to position: Vector2D) {
        guard let index = points.firstIndex(where: { $0.id == id }) else { return }
        points[index].position = position
    }

    public mutating func translatePoint(id: EditableGeometryID, by delta: Vector2D) {
        guard let point = point(id: id) else { return }
        setPointPosition(id: id, to: point.position + delta)
    }

    public mutating func moveAnchorWithAttachedControls(id: EditableGeometryID, to position: Vector2D) {
        guard let anchor = point(id: id), anchor.kind == .anchor else { return }
        let delta = position - anchor.position
        setPointPosition(id: id, to: position)
        translateControlsAttached(to: id, by: delta)
    }

    public mutating func resetControlsToInferredPositions(segmentIDs ids: Set<EditableGeometryID>? = nil) {
        let selected = ids ?? Set(segments.map(\.id))
        for segment in segments where selected.contains(segment.id) {
            resetControlsToInferredPositions(segmentID: segment.id)
        }
    }

    public func segmentIDs(containingPoint pointID: EditableGeometryID) -> Set<EditableGeometryID> {
        Set(segments.filter { $0.pointIDs.contains(pointID) }.map(\.id))
    }

    public func segmentIDs(touchingSegmentIDs ids: Set<EditableGeometryID>) -> Set<EditableGeometryID> {
        let anchors = Set(segments.filter { ids.contains($0.id) }.flatMap { [$0.startAnchorID, $0.endAnchorID] })
        guard !anchors.isEmpty else { return [] }
        return Set(segments.filter {
            anchors.contains($0.startAnchorID) || anchors.contains($0.endAnchorID)
        }.map(\.id))
    }

    public func attachedControlIDs(forSegment segment: EditableCubicSegment) -> Set<EditableGeometryID> {
        var ids = Set(segment.pointIDs)
        for neighbour in segments {
            if neighbour.startAnchorID == segment.startAnchorID { ids.insert(neighbour.controlOutID) }
            if neighbour.endAnchorID == segment.startAnchorID { ids.insert(neighbour.controlInID) }
            if neighbour.startAnchorID == segment.endAnchorID { ids.insert(neighbour.controlOutID) }
            if neighbour.endAnchorID == segment.endAnchorID { ids.insert(neighbour.controlInID) }
        }
        return ids
    }

    public mutating func translateSegment(id segmentID: EditableGeometryID, by delta: Vector2D) {
        guard let segment = segments.first(where: { $0.id == segmentID }),
              let start = point(id: segment.startAnchorID)?.position,
              let end = point(id: segment.endAnchorID)?.position
        else { return }
        moveAnchorWithAttachedControls(id: segment.startAnchorID, to: start + delta)
        moveAnchorWithAttachedControls(id: segment.endAnchorID, to: end + delta)
    }

    public func translated(by delta: Vector2D) -> EditableOpenCurve {
        var copy = self
        copy.points = points.map { point in
            var next = point
            next.position = point.position + delta
            return next
        }
        return copy
    }

    public func duplicated(name: String? = nil) -> EditableOpenCurve {
        var pointIDMap: [EditableGeometryID: EditableGeometryID] = [:]
        let copiedPoints = points.map { point in
            let copiedID = EditableGeometryID()
            pointIDMap[point.id] = copiedID
            return EditableCubicPoint(id: copiedID, position: point.position, kind: point.kind)
        }
        var segmentIDMap: [EditableGeometryID: EditableGeometryID] = [:]
        let copiedSegments = segments.map { segment in
            let copiedID = EditableGeometryID()
            segmentIDMap[segment.id] = copiedID
            return EditableCubicSegment(
                id: copiedID,
                startAnchorID: pointIDMap[segment.startAnchorID] ?? segment.startAnchorID,
                controlOutID: pointIDMap[segment.controlOutID] ?? segment.controlOutID,
                controlInID: pointIDMap[segment.controlInID] ?? segment.controlInID,
                endAnchorID: pointIDMap[segment.endAnchorID] ?? segment.endAnchorID
            )
        }
        return EditableOpenCurve(
            name: name ?? self.name,
            points: copiedPoints,
            segments: copiedSegments,
            pressures: pressures,
            segmentPressureProfiles: remappedPressureProfiles(using: segmentIDMap),
            isVisible: isVisible
        )
    }

    public func closingToPolygon(name: String? = nil) -> EditableClosedPolygon? {
        guard let firstID = anchorIDs.first,
              let lastID = anchorIDs.last,
              let first = point(id: firstID)?.position,
              let last = point(id: lastID)?.position,
              anchorIDs.count >= 3
        else { return nil }
        var closedPoints = points
        var closedSegments = segments

        if first.distance(to: last) <= 1e-8, let finalSegmentIndex = closedSegments.indices.last {
            closedSegments[finalSegmentIndex].endAnchorID = firstID
            closedPoints.removeAll { $0.id == lastID }
        } else {
            let delta = first - last
            let controlOut = EditableCubicPoint(position: last + delta * (1.0 / 3.0), kind: .control)
            let controlIn = EditableCubicPoint(position: last + delta * (2.0 / 3.0), kind: .control)
            closedPoints.append(contentsOf: [controlOut, controlIn])
            closedSegments.append(
                EditableCubicSegment(
                    startAnchorID: lastID,
                    controlOutID: controlOut.id,
                    controlInID: controlIn.id,
                    endAnchorID: firstID
                )
            )
        }

        return EditableClosedPolygon(
            name: name ?? self.name,
            points: closedPoints,
            segments: closedSegments,
            pressures: pressures.normalizedPressureValues(count: closedSegments.count),
            segmentPressureProfiles: segmentPressureProfiles,
            isVisible: isVisible
        )
    }

    public func toPolygon2D() throws -> Polygon2D {
        let pointMap = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0.position) })
        var encoded: [Vector2D] = []
        encoded.reserveCapacity(segments.count * 4)
        for segment in segments {
            for id in segment.pointIDs {
                guard let position = pointMap[id] else {
                    throw EditableGeometryError.missingPoint(id)
                }
                encoded.append(position.editorToRuntimeWorld())
            }
        }
        return Polygon2D(
            points: encoded,
            type: .openSpline,
            pressures: pressures,
            pressureProfiles: runtimePressureProfiles(),
            visible: isVisible
        )
    }

    public func pressureProfile(for segmentID: EditableGeometryID) -> [Double]? {
        segmentPressureProfiles?[segmentID]
    }

    public mutating func setPressureProfile(_ samples: [Double]?, for segmentID: EditableGeometryID) {
        if let samples, !samples.isEmpty {
            var profiles = segmentPressureProfiles ?? [:]
            profiles[segmentID] = samples
            segmentPressureProfiles = profiles
        } else {
            segmentPressureProfiles?[segmentID] = nil
            if segmentPressureProfiles?.isEmpty == true {
                segmentPressureProfiles = nil
            }
        }
    }

    private func runtimePressureProfiles() -> [[Double]]? {
        guard let segmentPressureProfiles, !segmentPressureProfiles.isEmpty else { return nil }
        let profiles = segments.map { segment in segmentPressureProfiles[segment.id] ?? [] }
        return profiles.contains { !$0.isEmpty } ? profiles : nil
    }

    private func remappedPressureProfiles(using segmentIDMap: [EditableGeometryID: EditableGeometryID]) -> [EditableGeometryID: [Double]]? {
        guard let segmentPressureProfiles, !segmentPressureProfiles.isEmpty else { return nil }
        var remapped: [EditableGeometryID: [Double]] = [:]
        for (oldID, samples) in segmentPressureProfiles {
            if let newID = segmentIDMap[oldID] {
                remapped[newID] = samples
            }
        }
        return remapped.isEmpty ? nil : remapped
    }

    public func prunedToReferencedPoints() -> EditableOpenCurve {
        let referenced = Set(segments.flatMap(\.pointIDs))
        var copy = self
        copy.points = points.filter { referenced.contains($0.id) }
        return copy
    }

    private mutating func translateControlsAttached(to anchorID: EditableGeometryID, by delta: Vector2D) {
        for segment in segments {
            if segment.startAnchorID == anchorID {
                translatePoint(id: segment.controlOutID, by: delta)
            }
            if segment.endAnchorID == anchorID {
                translatePoint(id: segment.controlInID, by: delta)
            }
        }
    }

    private mutating func resetControlsToInferredPositions(segmentID: EditableGeometryID) {
        guard let segment = segments.first(where: { $0.id == segmentID }),
              let start = point(id: segment.startAnchorID)?.position,
              let end = point(id: segment.endAnchorID)?.position
        else { return }
        let delta = end - start
        setPointPosition(id: segment.controlOutID, to: start + delta * (1.0 / 3.0))
        setPointPosition(id: segment.controlInID, to: start + delta * (2.0 / 3.0))
    }
}

public struct EditableStandalonePoint: Codable, Equatable, Identifiable, Sendable {
    public var id: EditableGeometryID
    public var name: String
    public var position: Vector2D
    public var pressure: Double
    public var isVisible: Bool

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        name: String,
        position: Vector2D,
        pressure: Double = 1.0,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.pressure = pressure
        self.isVisible = isVisible
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, position, pressure, isVisible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(EditableGeometryID.self, forKey: .id) ?? EditableGeometryID()
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(Vector2D.self, forKey: .position)
        pressure = try container.decodeIfPresent(Double.self, forKey: .pressure) ?? 1.0
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
    }

    public func translated(by delta: Vector2D) -> EditableStandalonePoint {
        var copy = self
        copy.position = position + delta
        return copy
    }

    public func duplicated(name: String? = nil) -> EditableStandalonePoint {
        EditableStandalonePoint(
            name: name ?? self.name,
            position: position,
            pressure: pressure,
            isVisible: isVisible
        )
    }

    public func toPolygon2D() -> Polygon2D {
        Polygon2D(points: [position.editorToRuntimeWorld()], type: .point, pressures: [pressure], visible: isVisible)
    }
}

public struct EditableGeometryLayer: Codable, Equatable, Identifiable, Sendable {
    public var id: EditableGeometryID
    public var name: String
    public var isVisible: Bool
    public var isEditable: Bool
    public var polygons: [EditableClosedPolygon]
    public var openCurves: [EditableOpenCurve]
    public var points: [EditableStandalonePoint]

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        name: String,
        isVisible: Bool = true,
        isEditable: Bool = true,
        polygons: [EditableClosedPolygon] = [],
        openCurves: [EditableOpenCurve] = [],
        points: [EditableStandalonePoint] = []
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isEditable = isEditable
        self.polygons = polygons
        self.openCurves = openCurves
        self.points = points
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isVisible
        case isEditable
        case polygons
        case openCurves
        case points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EditableGeometryID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isEditable = try container.decodeIfPresent(Bool.self, forKey: .isEditable) ?? true
        polygons = try container.decodeIfPresent([EditableClosedPolygon].self, forKey: .polygons) ?? []
        openCurves = try container.decodeIfPresent([EditableOpenCurve].self, forKey: .openCurves) ?? []
        points = try container.decodeIfPresent([EditableStandalonePoint].self, forKey: .points) ?? []
    }

    public func duplicated(name: String? = nil) -> EditableGeometryLayer {
        EditableGeometryLayer(
            name: name ?? self.name,
            isVisible: isVisible,
            isEditable: isEditable,
            polygons: polygons.map { $0.duplicated(name: $0.name) },
            openCurves: openCurves.map { $0.duplicated(name: $0.name) },
            points: points.map { $0.duplicated(name: $0.name) }
        )
    }
}

public struct EditableWeldGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: EditableGeometryID
    public var pointIDs: Set<EditableGeometryID>

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        pointIDs: Set<EditableGeometryID>
    ) {
        self.id = id
        self.pointIDs = pointIDs
    }
}

public struct EditableGeometrySelection: Codable, Equatable, Sendable {
    public var layerID: EditableGeometryID?
    public var polygonIDs: Set<EditableGeometryID>
    public var openCurveIDs: Set<EditableGeometryID>
    public var standalonePointIDs: Set<EditableGeometryID>
    public var segmentIDs: Set<EditableGeometryID>
    public var pointIDs: Set<EditableGeometryID>

    public init(
        layerID: EditableGeometryID? = nil,
        polygonIDs: Set<EditableGeometryID> = [],
        openCurveIDs: Set<EditableGeometryID> = [],
        standalonePointIDs: Set<EditableGeometryID> = [],
        segmentIDs: Set<EditableGeometryID> = [],
        pointIDs: Set<EditableGeometryID> = []
    ) {
        self.layerID = layerID
        self.polygonIDs = polygonIDs
        self.openCurveIDs = openCurveIDs
        self.standalonePointIDs = standalonePointIDs
        self.segmentIDs = segmentIDs
        self.pointIDs = pointIDs
    }

    public static let empty = EditableGeometrySelection()
}

// MARK: - Named point sets

/// A reference to a single control point by structural position (topology-stable across morph layers).
public struct GeometryPointSetEntry: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case polygon, openCurve, standalone
    }
    public var kind: Kind
    /// Polygon or open-curve index within the layer; 0 for standalone.
    public var containerIndex: Int
    /// Point index within the polygon or curve; standalone point index for `.standalone`.
    public var pointIndex: Int

    public init(kind: Kind, containerIndex: Int, pointIndex: Int) {
        self.kind = kind
        self.containerIndex = containerIndex
        self.pointIndex = pointIndex
    }
}

/// A named, saved selection of control points identified by structural position.
public struct GeometryNamedPointSet: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var entries: [GeometryPointSetEntry]

    public init(id: UUID = UUID(), name: String, entries: [GeometryPointSetEntry] = []) {
        self.id = id
        self.name = name
        self.entries = entries
    }
}

// MARK: - Document

public struct EditableGeometryDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: EditableGeometryID
    public var name: String
    public var layers: [EditableGeometryLayer]
    public var activeLayerID: EditableGeometryID?
    public var weldGroups: [EditableWeldGroup]
    public var namedPointSets: [GeometryNamedPointSet]

    public init(
        id: EditableGeometryID = EditableGeometryID(),
        name: String,
        layers: [EditableGeometryLayer] = [],
        activeLayerID: EditableGeometryID? = nil,
        weldGroups: [EditableWeldGroup] = [],
        namedPointSets: [GeometryNamedPointSet] = []
    ) {
        self.id = id
        self.name = name
        self.layers = layers
        self.activeLayerID = activeLayerID ?? layers.first?.id
        self.weldGroups = weldGroups.filter { $0.pointIDs.count > 1 }
        self.namedPointSets = namedPointSets
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case layers
        case activeLayerID
        case weldGroups
        case namedPointSets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(EditableGeometryID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        layers = try container.decodeIfPresent([EditableGeometryLayer].self, forKey: .layers) ?? []
        activeLayerID = try container.decodeIfPresent(EditableGeometryID.self, forKey: .activeLayerID) ?? layers.first?.id
        weldGroups = try container.decodeIfPresent([EditableWeldGroup].self, forKey: .weldGroups) ?? []
        namedPointSets = try container.decodeIfPresent([GeometryNamedPointSet].self, forKey: .namedPointSets) ?? []
        pruneWeldGroups()
    }

    public var activeLayer: EditableGeometryLayer? {
        guard let activeLayerID else { return nil }
        return layers.first { $0.id == activeLayerID }
    }

    public mutating func ensureActiveLayer() {
        if layers.isEmpty {
            let layer = EditableGeometryLayer(name: "Layer 1")
            layers = [layer]
            activeLayerID = layer.id
        } else if activeLayerID == nil || !layers.contains(where: { $0.id == activeLayerID }) {
            activeLayerID = layers.first?.id
        }
    }

    public var allPointIDs: Set<EditableGeometryID> {
        var ids = Set<EditableGeometryID>()
        for layer in layers {
            ids.formUnion(layer.polygons.flatMap { $0.points.map(\.id) })
            ids.formUnion(layer.openCurves.flatMap { $0.points.map(\.id) })
            ids.formUnion(layer.points.map(\.id))
        }
        return ids
    }

    public func point(id pointID: EditableGeometryID) -> EditableCubicPoint? {
        for layer in layers {
            if let point = layer.polygons.lazy.compactMap({ $0.point(id: pointID) }).first {
                return point
            }
            if let point = layer.openCurves.lazy.compactMap({ $0.point(id: pointID) }).first {
                return point
            }
            if let point = layer.points.first(where: { $0.id == pointID }) {
                return EditableCubicPoint(id: point.id, position: point.position, kind: .anchor)
            }
        }
        return nil
    }

    public mutating func setPointPosition(id pointID: EditableGeometryID, to position: Vector2D) {
        for layerIndex in layers.indices {
            for polygonIndex in layers[layerIndex].polygons.indices {
                if layers[layerIndex].polygons[polygonIndex].point(id: pointID) != nil {
                    layers[layerIndex].polygons[polygonIndex].setPointPosition(id: pointID, to: position)
                    return
                }
            }
            for curveIndex in layers[layerIndex].openCurves.indices {
                if layers[layerIndex].openCurves[curveIndex].point(id: pointID) != nil {
                    layers[layerIndex].openCurves[curveIndex].setPointPosition(id: pointID, to: position)
                    return
                }
            }
            if let pointIndex = layers[layerIndex].points.firstIndex(where: { $0.id == pointID }) {
                layers[layerIndex].points[pointIndex].position = position
                return
            }
        }
    }

    public func attachedControlIDs(to anchorID: EditableGeometryID) -> Set<EditableGeometryID> {
        guard point(id: anchorID)?.kind == .anchor else { return [] }
        var ids = Set<EditableGeometryID>()
        for layer in layers {
            for polygon in layer.polygons {
                for segment in polygon.segments {
                    if segment.startAnchorID == anchorID { ids.insert(segment.controlOutID) }
                    if segment.endAnchorID == anchorID { ids.insert(segment.controlInID) }
                }
            }
            for curve in layer.openCurves {
                for segment in curve.segments {
                    if segment.startAnchorID == anchorID { ids.insert(segment.controlOutID) }
                    if segment.endAnchorID == anchorID { ids.insert(segment.controlInID) }
                }
            }
        }
        return ids
    }

    public func weldedPointIDs(containing pointID: EditableGeometryID) -> Set<EditableGeometryID> {
        weldGroups.first { $0.pointIDs.contains(pointID) }?.pointIDs ?? [pointID]
    }

    public func relationalPointIDs(startingWith seedIDs: Set<EditableGeometryID>) -> Set<EditableGeometryID> {
        var result = seedIDs
        var queue = Array(seedIDs)
        while let pointID = queue.popLast() {
            for weldedID in weldedPointIDs(containing: pointID) where !result.contains(weldedID) {
                result.insert(weldedID)
                queue.append(weldedID)
            }
            if point(id: pointID)?.kind == .anchor {
                for controlID in attachedControlIDs(to: pointID) where !result.contains(controlID) {
                    result.insert(controlID)
                    queue.append(controlID)
                }
            }
        }
        return result
    }

    public mutating func weldPoints(_ pointIDs: Set<EditableGeometryID>) {
        let existingIDs = allPointIDs
        var merged = pointIDs.intersection(existingIDs)
        guard merged.count > 1 else { return }

        var keptGroups: [EditableWeldGroup] = []
        for group in weldGroups {
            let validGroupIDs = group.pointIDs.intersection(existingIDs)
            if validGroupIDs.isDisjoint(with: merged) {
                if validGroupIDs.count > 1 {
                    keptGroups.append(EditableWeldGroup(id: group.id, pointIDs: validGroupIDs))
                }
            } else {
                merged.formUnion(validGroupIDs)
            }
        }
        keptGroups.append(EditableWeldGroup(pointIDs: merged))
        weldGroups = keptGroups
    }

    public mutating func removePointIDsFromWelds(_ pointIDs: Set<EditableGeometryID>) {
        guard !pointIDs.isEmpty else { return }
        weldGroups = weldGroups.compactMap { group in
            let remaining = group.pointIDs.subtracting(pointIDs)
            return remaining.count > 1 ? EditableWeldGroup(id: group.id, pointIDs: remaining) : nil
        }
    }

    public mutating func pruneWeldGroups() {
        let existingIDs = allPointIDs
        weldGroups = weldGroups.compactMap { group in
            let remaining = group.pointIDs.intersection(existingIDs)
            return remaining.count > 1 ? EditableWeldGroup(id: group.id, pointIDs: remaining) : nil
        }
    }

    public func runtimePolygons(
        includeHiddenLayers: Bool = false,
        targetLayerID: EditableGeometryID? = nil,
        targetLayerName: String? = nil
    ) throws -> [Polygon2D] {
        var runtime: [Polygon2D] = []
        let targetName = targetLayerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLayers: [EditableGeometryLayer]
        if let targetLayerID,
           let layer = layers.first(where: { $0.id == targetLayerID }) {
            sourceLayers = [layer]
        } else if let targetName,
                  !targetName.isEmpty,
                  let layer = layers.first(where: { $0.name == targetName }) {
            sourceLayers = [layer]
        } else if targetLayerID != nil || !(targetName?.isEmpty ?? true) {
            sourceLayers = []
        } else {
            sourceLayers = layers
        }

        for layer in sourceLayers {
            guard targetLayerID != nil || !(targetName?.isEmpty ?? true) || includeHiddenLayers || layer.isVisible else {
                continue
            }
            for polygon in layer.polygons where polygon.isVisible {
                runtime.append(try polygon.toPolygon2D())
            }
            for curve in layer.openCurves where curve.isVisible {
                runtime.append(try curve.toPolygon2D())
            }
            for point in layer.points where point.isVisible {
                runtime.append(point.toPolygon2D())
            }
        }
        return runtime
    }

    /// Migrate a v1 JSON document to the v2 coordinate convention.
    /// v1 stored editor positions with Y negated relative to world space.
    /// v2 stores positions directly in Y-UP world space (identity conversion).
    public func mirroringY() -> EditableGeometryDocument {
        var doc = self
        doc.layers = layers.map { layer in
            var l = layer
            l.polygons = layer.polygons.map { poly in
                var p = poly
                p.points = poly.points.map { pt in
                    var q = pt; q.position = pt.position.mirroredY(); return q
                }
                if case .regularPolygon(var params) = p.parametricSource {
                    params.centre = params.centre.mirroredY()
                    p.parametricSource = .regularPolygon(params)
                }
                return p
            }
            l.openCurves = layer.openCurves.map { curve in
                var c = curve
                c.points = curve.points.map { pt in
                    var q = pt; q.position = pt.position.mirroredY(); return q
                }
                return c
            }
            l.points = layer.points.map { sp in
                var s = sp; s.position = sp.position.mirroredY(); return s
            }
            return l
        }
        return doc
    }

    public static func closedPolygonDocument(
        name: String,
        polygons: [Polygon2D],
        layerName: String = "Layer 1"
    ) throws -> EditableGeometryDocument {
        let editablePolygons = try polygons.enumerated().map { index, polygon in
            try EditableClosedPolygon(name: "Polygon \(index + 1)", polygon: polygon)
        }
        let layer = EditableGeometryLayer(name: layerName, polygons: editablePolygons)
        return EditableGeometryDocument(name: name, layers: [layer], activeLayerID: layer.id)
    }

    /// Append a new layer populated from `polygons` to this document.
    /// Spline polygons become `EditableClosedPolygon`; open splines become `EditableOpenCurve`.
    /// Other polygon types (line, point, oval) are silently skipped.
    /// Returns the new layer's ID.
    @discardableResult
    public mutating func appendLayer(from polygons: [Polygon2D], named name: String) throws -> EditableGeometryID {
        var closedCount = 0
        var openCount   = 0
        var editablePolygons: [EditableClosedPolygon] = []
        var editableCurves:   [EditableOpenCurve]     = []
        for polygon in polygons {
            switch polygon.type {
            case .spline:
                closedCount += 1
                editablePolygons.append(
                    try EditableClosedPolygon(name: "Polygon \(closedCount)", polygon: polygon))
            case .openSpline:
                openCount += 1
                editableCurves.append(
                    try EditableOpenCurve(name: "Curve \(openCount)", polygon: polygon))
            default:
                break
            }
        }
        let layer = EditableGeometryLayer(name: name, polygons: editablePolygons, openCurves: editableCurves)
        layers.append(layer)
        return layer.id
    }
}

// MARK: - Selection inversion (2026-07-14)

extension EditableGeometryDocument {
    /// Inverts `selection` within its own layer (Edit ▸ Invert Selection, ⌘I).
    ///
    /// The editor's selection has three mutually exclusive modes, each
    /// maintained by its own family of `AppController.selectGeometry*`
    /// functions: **point** (`pointIDs` non-empty, the common case — clicking
    /// or marquee-selecting anchors/control points), **segment**
    /// (`segmentIDs` non-empty — edge selection for mesh-extend/knife-style
    /// operations), and **whole-object** (`polygonIDs`/`openCurveIDs`
    /// non-empty with *no* points or segments selected — selecting entire
    /// shapes for move/duplicate/delete). Inversion stays within whichever
    /// mode is currently active, complementing that mode's own universe
    /// (every point in the layer, every segment in the layer, or every
    /// polygon+curve in the layer, respectively) — switching modes as a side
    /// effect of inverting would be surprising. Nothing selected defaults to
    /// point mode, so the first ⌘I with an empty selection selects every
    /// point in the layer, matching "select all" in most editors.
    ///
    /// `polygonIDs`/`openCurveIDs`/`standalonePointIDs` are rebuilt to stay
    /// consistent with the new `pointIDs`/`segmentIDs`, mirroring exactly how
    /// `selectGeometryPoints`/`selectGeometrySegments` already maintain them
    /// (each tracks "which container has at least one selected point/segment").
    /// Standalone points have no separate segment concept, so they only ever
    /// participate in point-mode inversion.
    public func invertedSelection(from selection: EditableGeometrySelection) -> EditableGeometrySelection {
        guard let layerID = selection.layerID,
              let layer = layers.first(where: { $0.id == layerID })
        else { return selection }

        if !selection.segmentIDs.isEmpty {
            return invertedSegmentSelection(layerID: layerID, layer: layer, current: selection)
        }
        if selection.pointIDs.isEmpty && (!selection.polygonIDs.isEmpty || !selection.openCurveIDs.isEmpty) {
            return invertedWholeObjectSelection(layerID: layerID, layer: layer, current: selection)
        }
        return invertedPointSelection(layerID: layerID, layer: layer, current: selection)
    }

    private func invertedPointSelection(
        layerID: EditableGeometryID, layer: EditableGeometryLayer, current: EditableGeometrySelection
    ) -> EditableGeometrySelection {
        var newPointIDs      = Set<EditableGeometryID>()
        var newPolygonIDs    = Set<EditableGeometryID>()
        var newOpenCurveIDs  = Set<EditableGeometryID>()
        var newStandaloneIDs = Set<EditableGeometryID>()

        for polygon in layer.polygons {
            for point in polygon.points where !current.pointIDs.contains(point.id) {
                newPointIDs.insert(point.id)
                newPolygonIDs.insert(polygon.id)
            }
        }
        for curve in layer.openCurves {
            for point in curve.points where !current.pointIDs.contains(point.id) {
                newPointIDs.insert(point.id)
                newOpenCurveIDs.insert(curve.id)
            }
        }
        for point in layer.points where !current.pointIDs.contains(point.id) {
            newPointIDs.insert(point.id)
            newStandaloneIDs.insert(point.id)
        }

        guard !newPointIDs.isEmpty else { return .empty }
        return EditableGeometrySelection(
            layerID: layerID,
            polygonIDs: newPolygonIDs,
            openCurveIDs: newOpenCurveIDs,
            standalonePointIDs: newStandaloneIDs,
            pointIDs: newPointIDs
        )
    }

    private func invertedSegmentSelection(
        layerID: EditableGeometryID, layer: EditableGeometryLayer, current: EditableGeometrySelection
    ) -> EditableGeometrySelection {
        var newSegmentIDs   = Set<EditableGeometryID>()
        var newPolygonIDs   = Set<EditableGeometryID>()
        var newOpenCurveIDs = Set<EditableGeometryID>()

        for polygon in layer.polygons {
            for segment in polygon.segments where !current.segmentIDs.contains(segment.id) {
                newSegmentIDs.insert(segment.id)
                newPolygonIDs.insert(polygon.id)
            }
        }
        for curve in layer.openCurves {
            for segment in curve.segments where !current.segmentIDs.contains(segment.id) {
                newSegmentIDs.insert(segment.id)
                newOpenCurveIDs.insert(curve.id)
            }
        }

        guard !newSegmentIDs.isEmpty else { return .empty }
        return EditableGeometrySelection(
            layerID: layerID, polygonIDs: newPolygonIDs, openCurveIDs: newOpenCurveIDs, segmentIDs: newSegmentIDs
        )
    }

    private func invertedWholeObjectSelection(
        layerID: EditableGeometryID, layer: EditableGeometryLayer, current: EditableGeometrySelection
    ) -> EditableGeometrySelection {
        let newPolygonIDs   = Set(layer.polygons.map(\.id)).subtracting(current.polygonIDs)
        let newOpenCurveIDs = Set(layer.openCurves.map(\.id)).subtracting(current.openCurveIDs)
        guard !newPolygonIDs.isEmpty || !newOpenCurveIDs.isEmpty else { return .empty }
        return EditableGeometrySelection(layerID: layerID, polygonIDs: newPolygonIDs, openCurveIDs: newOpenCurveIDs)
    }
}

public struct EditableGeometrySnapshot: Codable, Equatable, Sendable {
    public var document: EditableGeometryDocument
    public var selection: EditableGeometrySelection

    public init(
        document: EditableGeometryDocument,
        selection: EditableGeometrySelection = .empty
    ) {
        self.document = document
        self.selection = selection
    }
}

public struct EditableGeometryHistory: Equatable, Sendable {
    public private(set) var undoStack: [EditableGeometrySnapshot]
    public private(set) var redoStack: [EditableGeometrySnapshot]
    public var limit: Int

    public init(limit: Int = 20) {
        self.undoStack = []
        self.redoStack = []
        self.limit = max(1, limit)
    }

    public mutating func record(_ snapshot: EditableGeometrySnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    public mutating func undo(current: EditableGeometrySnapshot) -> EditableGeometrySnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    public mutating func redo(current: EditableGeometrySnapshot) -> EditableGeometrySnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        return next
    }
}

private extension Array where Element == Double {
    func normalizedPressureValues(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !isEmpty else { return Array(repeating: 1.0, count: count) }
        if self.count == count { return self }
        if self.count > count { return Array(prefix(count)) }
        return self + Array(repeating: last ?? 1.0, count: count - self.count)
    }
}

private func editablePressureProfiles(
    _ profiles: [[Double]]?,
    segments: [EditableCubicSegment]
) -> [EditableGeometryID: [Double]]? {
    guard let profiles, !profiles.isEmpty else { return nil }
    var result: [EditableGeometryID: [Double]] = [:]
    for (index, segment) in segments.enumerated() where index < profiles.count && !profiles[index].isEmpty {
        result[segment.id] = profiles[index]
    }
    return result.isEmpty ? nil : result
}
