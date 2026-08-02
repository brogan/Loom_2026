import Foundation

/// Mutations on a recorded session's `[RecordedEvent]` array — the
/// "document" `EventTimelineView` edits directly, with no `ProjectConfig`/
/// `AppController.updateProjectConfig`/undo-stack involvement, since a
/// session under review isn't part of the authored project at all.
enum EventTimelineEditing {

    /// Retimes a single event (by its `RecordedEvent.id`) to `newFrame`,
    /// clamped to non-negative. A no-op if `id` isn't present.
    static func retime(_ id: UUID, to newFrame: Int, in events: inout [RecordedEvent]) {
        guard let idx = events.firstIndex(where: { $0.id == id }) else { return }
        events[idx].event = events[idx].event.withT(max(0, newFrame))
    }

    /// Shifts one or two paired events (e.g. a segment's start+end) by the
    /// same frame delta — a clip-slip that preserves the span's duration.
    /// `idB` is optional since an open-ended segment has no end event to move.
    static func retimePair(_ idA: UUID, _ idB: UUID?, byDelta delta: Int, in events: inout [RecordedEvent]) {
        if let idxA = events.firstIndex(where: { $0.id == idA }) {
            events[idxA].event = events[idxA].event.withT(max(0, events[idxA].event.t + delta))
        }
        if let idB, let idxB = events.firstIndex(where: { $0.id == idB }) {
            events[idxB].event = events[idxB].event.withT(max(0, events[idxB].event.t + delta))
        }
    }

    /// Removes every event whose id is in `ids`. Deliberately non-cascading
    /// — deleting a visibility/enabled segment's pair (or an assign event)
    /// removes only those specific events, leaving anything else in the
    /// same span untouched (harmless: replay mutators already no-op for an
    /// instance that isn't currently shown).
    static func delete(_ ids: Set<UUID>, in events: inout [RecordedEvent]) {
        events.removeAll { ids.contains($0.id) }
    }
}
