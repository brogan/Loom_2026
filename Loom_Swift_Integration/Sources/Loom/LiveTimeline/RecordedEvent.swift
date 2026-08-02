import Foundation

/// A `LiveEvent` with a stable synthetic identity, assigned once when a
/// session is opened for review. `LiveEvent` has no identity of its own and
/// two events can be content-identical (e.g. two `driverEnabledToggle(enabled:
/// false)` at different frames), so array position or content equality is
/// too fragile to reference from a derived segment — a once-minted `UUID`
/// isn't.
struct RecordedEvent: Identifiable {
    let id: UUID
    var event: LiveEvent
}

extension RecordedEvent {
    /// Loads a session log (via `SessionReplayer.loadEvents(from:)`, unchanged)
    /// and mints an id for each event, sorted by frame.
    static func load(from url: URL) throws -> [RecordedEvent] {
        try SessionReplayer.loadEvents(from: url)
            .sorted { $0.t < $1.t }
            .map { RecordedEvent(id: UUID(), event: $0) }
    }
}
