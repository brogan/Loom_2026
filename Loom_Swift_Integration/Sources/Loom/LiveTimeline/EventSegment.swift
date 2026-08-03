import Foundation
import LoomEngine

/// The derived, editable view of a recorded Live session — turns the mostly
/// point-based `[LiveEvent]` log into lanes of segments/markers/curves for
/// `EventTimelineView`. Always computed fresh from the current
/// `[RecordedEvent]` array (see `EventSegmentDerivation.derive`), never
/// cached — a session realistically holds dozens to low hundreds of events
/// (manual live capture, not imported MIDI), so recomputing on every body
/// evaluation is cheap and avoids a second source of truth to keep in sync.
struct EventTimelineModel {
    var instanceLanes: [InstanceLane]
    var globalMarkers: [GlobalMarker]
    var audioReference: AudioReference?
}

/// Live mode's own audio track, as recorded in the session — derived from
/// the *last* `.audioSet` event in the log (the same "last one wins for the
/// whole session" model already used for BPM), not a time-varying span.
struct AudioReference {
    var eventID: UUID
    var filename: String
    var offsetFrames: Int
}

struct InstanceLane: Identifiable {
    var id: String { instanceName }
    var instanceName: String
    var spriteLabel: String
    var visibilitySegments: [VisibilitySegment] = []
    var rendererSegments: [AssignSegment] = []
    var transformSegments: [AssignSegment] = []
    var enabledSegments: [LiveDriverTarget: [EnabledSegment]] = [:]
    var poseMarkers: [PoseMarker] = []
    var automationCurves: [AutomationCurve] = []
    var musicalRateMarkers: [MusicalRateMarker] = []
}

/// Common shape shared by every derived time-span (`VisibilitySegment`,
/// `AssignSegment`, `EnabledSegment`) — lets `EventTimelineView`'s
/// hit-testing/dragging/drawing operate generically over all three instead
/// of switching on kind at every step, since move/resize/delete mean
/// exactly the same thing (retime/delete the underlying start/end events)
/// regardless of which kind of span it is.
protocol EventSpan {
    var id: UUID { get }
    var startEventID: UUID { get }
    var endEventID: UUID? { get }
    var startFrame: Int { get }
    var endFrame: Int? { get }
    /// What to draw inside the band, if anything — e.g. the sprite/set name.
    var displayLabel: String? { get }
}

/// Common shape shared by every derived single-frame point
/// (`AutomationPoint`, `PoseMarker`) — `pairedID` is the companion event
/// that must retime alongside `id` (a vector automation point's y-event),
/// nil where there is none.
protocol EventPoint {
    var id: UUID { get }
    var pairedID: UUID? { get }
    var frame: Int { get }
}

/// A span derived from a "start" event paired with the next matching "end"
/// event for the same instance (`endEventID == nil` means open-ended — the
/// span was still active when the log ended, and its right edge can't be
/// dragged since there's no event there to retime).
struct VisibilitySegment: Identifiable, EventSpan {
    var id: UUID { startEventID }
    var startEventID: UUID
    var endEventID: UUID?
    var startFrame: Int
    var endFrame: Int?
    var spriteSetName: String
    var spriteName: String
    var displayLabel: String? { spriteName }
}

enum AssignKind {
    case renderer, transform
}

/// A "holds until superseded" span — one per `rendererSetAssign`/
/// `transformSetAssign` event, ending at whichever comes first: the next
/// same-kind assign for this instance, or its next hide.
struct AssignSegment: Identifiable, EventSpan {
    var id: UUID { startEventID }
    var startEventID: UUID
    var endEventID: UUID?
    var startFrame: Int
    var endFrame: Int?
    var setName: String
    var displayLabel: String? { setName }
}

struct EnabledSegment: Identifiable, EventSpan {
    var id: UUID { startEventID }
    var startEventID: UUID
    var endEventID: UUID?
    var startFrame: Int
    var endFrame: Int?
    var displayLabel: String? { nil }
}

struct PoseMarker: Identifiable, EventPoint {
    var id: UUID { eventID }
    var pairedID: UUID? { nil }
    var eventID: UUID
    var frame: Int
    var position: Vector2D
    var scale: Vector2D
    var rotation: Double
}

struct AutomationPoint: Identifiable, EventPoint {
    var id: UUID { xEventID }
    var pairedID: UUID? { yEventID }
    var xEventID: UUID
    var yEventID: UUID?
    var frame: Int
    var x: Double
    var y: Double?
}

struct AutomationCurve: Identifiable {
    var id: String { "\(instanceName)|\(target.section.rawValue)|\(target.entryName)|\(target.field)|\(quantity)" }
    var instanceName: String
    var target: LiveDriverTarget
    var quantity: String // "rate" or "range"
    var points: [AutomationPoint]
}

struct MusicalRateMarker: Identifiable {
    var id: UUID { eventID }
    var eventID: UUID
    var frame: Int
    var target: LiveDriverTarget
    var multiplier: Double?
}

struct GlobalMarker: Identifiable {
    enum Kind {
        case bpmSet(bpm: Double, beatsPerBar: Int)
        case tapSync(referenceFrame: Int)
    }
    var id: UUID { eventID }
    var eventID: UUID
    var frame: Int
    var kind: Kind
}

enum EventSegmentDerivation {

    /// Pure function: one chronological pass, grouping by `instanceName`
    /// where relevant, pairing show→next-hide, assign→next-assign-or-hide,
    /// on→next-off. Instance lanes are ordered by first appearance in the
    /// log — the order sprites were actually staged in.
    static func derive(from recorded: [RecordedEvent]) -> EventTimelineModel {
        let sorted = recorded.sorted { $0.event.t < $1.event.t }

        var laneOrder: [String] = []
        var lanesByInstance: [String: InstanceLane] = [:]

        func lane(for instanceName: String) -> InstanceLane {
            if let existing = lanesByInstance[instanceName] { return existing }
            laneOrder.append(instanceName)
            let fresh = InstanceLane(instanceName: instanceName, spriteLabel: instanceName)
            lanesByInstance[instanceName] = fresh
            return fresh
        }

        // MARK: Visibility (spriteShow/spriteHide)
        for (instanceName, group) in groupedByInstance(sorted, cases: [.spriteShow, .spriteHide]) {
            var l = lane(for: instanceName)
            var openStart: (id: UUID, frame: Int, setName: String, spriteName: String)?
            for item in group {
                switch item.event {
                case .spriteShow(let t, _, let spriteSetName, let spriteName, _, _, _):
                    if let open = openStart {
                        // Two shows with no hide between them — close the
                        // first implicitly at the second show's frame so
                        // segments never overlap.
                        l.visibilitySegments.append(VisibilitySegment(
                            startEventID: open.id, endEventID: nil, startFrame: open.frame, endFrame: t,
                            spriteSetName: open.setName, spriteName: open.spriteName
                        ))
                    }
                    if l.spriteLabel == l.instanceName {
                        l.spriteLabel = "\(spriteSetName) / \(spriteName)"
                    }
                    openStart = (item.id, t, spriteSetName, spriteName)
                case .spriteHide(let t, _):
                    if let open = openStart {
                        l.visibilitySegments.append(VisibilitySegment(
                            startEventID: open.id, endEventID: item.id, startFrame: open.frame, endFrame: t,
                            spriteSetName: open.setName, spriteName: open.spriteName
                        ))
                        openStart = nil
                    }
                default: break
                }
            }
            if let open = openStart {
                l.visibilitySegments.append(VisibilitySegment(
                    startEventID: open.id, endEventID: nil, startFrame: open.frame, endFrame: nil,
                    spriteSetName: open.setName, spriteName: open.spriteName
                ))
            }
            lanesByInstance[instanceName] = l
        }

        // MARK: Renderer / transform assign ("holds until superseded")
        for (instanceName, group) in groupedByInstance(sorted, cases: [.rendererSetAssign, .spriteHide]) {
            var l = lane(for: instanceName)
            l.rendererSegments = assignSegments(from: group, matching: { if case .rendererSetAssign = $0 { return true }; return false })
            lanesByInstance[instanceName] = l
        }
        for (instanceName, group) in groupedByInstance(sorted, cases: [.transformSetAssign, .spriteHide]) {
            var l = lane(for: instanceName)
            l.transformSegments = assignSegments(from: group, matching: { if case .transformSetAssign = $0 { return true }; return false })
            lanesByInstance[instanceName] = l
        }

        // MARK: Driver enabled toggles
        for (instanceName, group) in groupedByInstance(sorted, cases: [.driverEnabledToggle]) {
            var l = lane(for: instanceName)
            var byTarget: [LiveDriverTarget: [RecordedEvent]] = [:]
            for item in group {
                if case .driverEnabledToggle(_, _, let target, _) = item.event {
                    byTarget[target, default: []].append(item)
                }
            }
            for (target, events) in byTarget {
                var segments: [EnabledSegment] = []
                var openStart: (id: UUID, frame: Int)?
                for e in events.sorted(by: { $0.event.t < $1.event.t }) {
                    guard case .driverEnabledToggle(let t, _, _, let enabled) = e.event else { continue }
                    if enabled {
                        if let open = openStart {
                            segments.append(EnabledSegment(startEventID: open.id, endEventID: nil, startFrame: open.frame, endFrame: t))
                        }
                        openStart = (e.id, t)
                    } else if let open = openStart {
                        segments.append(EnabledSegment(startEventID: open.id, endEventID: e.id, startFrame: open.frame, endFrame: t))
                        openStart = nil
                    }
                }
                if let open = openStart {
                    segments.append(EnabledSegment(startEventID: open.id, endEventID: nil, startFrame: open.frame, endFrame: nil))
                }
                l.enabledSegments[target] = segments.sorted { $0.startFrame < $1.startFrame }
            }
            lanesByInstance[instanceName] = l
        }

        // MARK: Pose markers
        for (instanceName, group) in groupedByInstance(sorted, cases: [.poseUpdate]) {
            var l = lane(for: instanceName)
            l.poseMarkers = group.compactMap { item -> PoseMarker? in
                guard case .poseUpdate(let t, _, let position, let scale, let rotation) = item.event else { return nil }
                return PoseMarker(eventID: item.id, frame: t, position: position, scale: scale, rotation: rotation)
            }
            lanesByInstance[instanceName] = l
        }

        // MARK: Automation curves — reuses the shared grouping so the
        // editor's curves can never disagree with SessionReplayer's.
        let idLookup = automationEventIDLookup(sorted)
        let grouped = LiveEvent.groupedAutomationPoints(sorted.map(\.event))
        var curvesByInstance: [String: [AutomationCurve]] = [:]
        for (key, points) in grouped {
            let mapped: [AutomationPoint] = points.compactMap { pt in
                guard let xID = idLookup[AutomationEventKey(instanceName: key.instanceName, target: key.target, quantity: key.quantity, axis: "x", t: pt.t)]
                    ?? idLookup[AutomationEventKey(instanceName: key.instanceName, target: key.target, quantity: key.quantity, axis: nil, t: pt.t)]
                else { return nil }
                let yID = idLookup[AutomationEventKey(instanceName: key.instanceName, target: key.target, quantity: key.quantity, axis: "y", t: pt.t)]
                return AutomationPoint(xEventID: xID, yEventID: yID, frame: pt.t, x: pt.x, y: pt.y)
            }
            guard !mapped.isEmpty else { continue }
            curvesByInstance[key.instanceName, default: []].append(
                AutomationCurve(instanceName: key.instanceName, target: key.target, quantity: key.quantity, points: mapped)
            )
        }
        for (instanceName, curves) in curvesByInstance {
            var l = lane(for: instanceName)
            l.automationCurves = curves.sorted { ($0.target.field, $0.quantity) < ($1.target.field, $1.quantity) }
            lanesByInstance[instanceName] = l
        }

        // MARK: Musical rate assigns
        for (instanceName, group) in groupedByInstance(sorted, cases: [.driverMusicalRateAssign]) {
            var l = lane(for: instanceName)
            l.musicalRateMarkers = group.compactMap { item -> MusicalRateMarker? in
                guard case .driverMusicalRateAssign(let t, _, let target, let multiplier) = item.event else { return nil }
                return MusicalRateMarker(eventID: item.id, frame: t, target: target, multiplier: multiplier)
            }
            lanesByInstance[instanceName] = l
        }

        // MARK: Global markers (bpmSet / tapSync)
        var globalMarkers: [GlobalMarker] = []
        for item in sorted {
            switch item.event {
            case .bpmSet(let t, let bpm, let beatsPerBar):
                globalMarkers.append(GlobalMarker(eventID: item.id, frame: t, kind: .bpmSet(bpm: bpm, beatsPerBar: beatsPerBar)))
            case .tapSync(let t, let referenceFrame):
                globalMarkers.append(GlobalMarker(eventID: item.id, frame: t, kind: .tapSync(referenceFrame: referenceFrame)))
            default: break
            }
        }

        // MARK: Audio reference — last audioSet in the log wins
        var audioReference: AudioReference?
        for item in sorted {
            if case .audioSet(_, let filename, let offsetFrames) = item.event {
                audioReference = AudioReference(eventID: item.id, filename: filename, offsetFrames: offsetFrames)
            }
        }

        let lanes = laneOrder.compactMap { lanesByInstance[$0] }
        return EventTimelineModel(instanceLanes: lanes, globalMarkers: globalMarkers, audioReference: audioReference)
    }

    // MARK: - Helpers

    /// A coarse case tag used only to pre-filter events cheaply before the
    /// real per-case pattern match — avoids writing the full instanceName
    /// extraction switch twice per event kind.
    private enum EventCaseTag: Hashable {
        case spriteShow, spriteHide, poseUpdate, rendererSetAssign, transformSetAssign,
             driverEnabledToggle, driverAutomationPoint, driverMusicalRateAssign
    }

    private static func caseTag(_ event: LiveEvent) -> EventCaseTag? {
        switch event {
        case .spriteShow:               return .spriteShow
        case .spriteHide:                return .spriteHide
        case .poseUpdate:               return .poseUpdate
        case .rendererSetAssign:        return .rendererSetAssign
        case .transformSetAssign:       return .transformSetAssign
        case .driverEnabledToggle:      return .driverEnabledToggle
        case .driverAutomationPoint:    return .driverAutomationPoint
        case .driverMusicalRateAssign:  return .driverMusicalRateAssign
        case .bpmSet, .tapSync, .audioSet, .sessionStart, .sessionEnd: return nil
        }
    }

    private static func instanceName(of event: LiveEvent) -> String? {
        switch event {
        case .spriteShow(_, let n, _, _, _, _, _): return n
        case .spriteHide(_, let n): return n
        case .poseUpdate(_, let n, _, _, _): return n
        case .rendererSetAssign(_, let n, _): return n
        case .transformSetAssign(_, let n, _): return n
        case .driverEnabledToggle(_, let n, _, _): return n
        case .driverAutomationPoint(_, let n, _, _, _, _): return n
        case .driverMusicalRateAssign(_, let n, _, _): return n
        case .bpmSet, .tapSync, .audioSet, .sessionStart, .sessionEnd: return nil
        }
    }

    /// Groups `sorted` events whose case matches any of `cases` by
    /// `instanceName`, preserving chronological order within each group.
    private static func groupedByInstance(
        _ sorted: [RecordedEvent], cases: Set<EventCaseTag>
    ) -> [(instanceName: String, group: [RecordedEvent])] {
        var byInstance: [String: [RecordedEvent]] = [:]
        var order: [String] = []
        for item in sorted {
            guard let tag = caseTag(item.event), cases.contains(tag),
                  let name = instanceName(of: item.event) else { continue }
            if byInstance[name] == nil { order.append(name) }
            byInstance[name, default: []].append(item)
        }
        return order.map { ($0, byInstance[$0] ?? []) }
    }

    /// Builds "holds until superseded" segments from a chronological,
    /// single-instance event group already filtered to one assign kind plus
    /// `spriteHide` (the two things that can end a span) via `matching`.
    private static func assignSegments(
        from group: [RecordedEvent], matching: (LiveEvent) -> Bool
    ) -> [AssignSegment] {
        var segments: [AssignSegment] = []
        var open: (id: UUID, frame: Int, setName: String)?
        for item in group.sorted(by: { $0.event.t < $1.event.t }) {
            let e = item.event
            if matching(e) {
                let (t, name) = assignFields(e)
                if let o = open {
                    segments.append(AssignSegment(startEventID: o.id, endEventID: item.id, startFrame: o.frame, endFrame: t, setName: o.setName))
                }
                open = (item.id, t, name)
            } else if case .spriteHide(let t, _) = e {
                if let o = open {
                    segments.append(AssignSegment(startEventID: o.id, endEventID: item.id, startFrame: o.frame, endFrame: t, setName: o.setName))
                    open = nil
                }
            }
        }
        if let o = open {
            segments.append(AssignSegment(startEventID: o.id, endEventID: nil, startFrame: o.frame, endFrame: nil, setName: o.setName))
        }
        return segments
    }

    private static func assignFields(_ event: LiveEvent) -> (t: Int, name: String) {
        switch event {
        case .rendererSetAssign(let t, _, let name): return (t, name)
        case .transformSetAssign(let t, _, let name): return (t, name)
        default: return (event.t, "")
        }
    }

    private struct AutomationEventKey: Hashable {
        let instanceName: String
        let target: LiveDriverTarget
        let quantity: String
        let axis: String?
        let t: Int
    }

    /// Maps each `driverAutomationPoint` event to its own id, keyed by
    /// exactly the fields `LiveEvent.groupedAutomationPoints` groups on plus
    /// frame — lets the derivation recover which event produced which
    /// merged point without re-deriving the grouping logic itself.
    private static func automationEventIDLookup(_ sorted: [RecordedEvent]) -> [AutomationEventKey: UUID] {
        var lookup: [AutomationEventKey: UUID] = [:]
        for item in sorted {
            guard case .driverAutomationPoint(let t, let instanceName, let target, let quantity, let axis, _) = item.event else { continue }
            lookup[AutomationEventKey(instanceName: instanceName, target: target, quantity: quantity, axis: axis, t: t)] = item.id
        }
        return lookup
    }
}
