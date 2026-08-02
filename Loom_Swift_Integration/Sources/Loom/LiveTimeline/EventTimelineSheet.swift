import AppKit
import SwiftUI
import LoomEngine

/// Review/edit a recorded Live session as a timeline before rendering it —
/// separate from `SessionReplaySheet`, which stays a tight "just render it"
/// fast path for when no review is needed.
struct EventTimelineSheet: View {

    let projectURL: URL
    let sessionURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var recordedEvents: [RecordedEvent] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var showRenderSheet = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review Session").font(.headline)
                Text(sessionURL.lastPathComponent).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 12)

            Divider()

            if let loadError {
                Text(loadError).foregroundStyle(.red).font(.callout).padding()
                Spacer()
            } else if isLoading {
                VStack { ProgressView("Loading session…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EventTimelineView(recordedEvents: $recordedEvents)
                    .frame(minHeight: 320)
            }

            if let saveError {
                Text(saveError).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Copy…") { presentSaveCopyPanel() }
                    .disabled(isLoading || loadError != nil)
                Button("Render…") { showRenderSheet = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || loadError != nil)
            }
            .padding()
        }
        .frame(width: 760, height: 560)
        .sheet(isPresented: $showRenderSheet) {
            SessionReplaySheet(projectURL: projectURL, sessionURL: sessionURL, presetEvents: recordedEvents.map(\.event))
        }
        .onAppear { loadSession() }
    }

    /// Writes the edited events as a new `.jsonl` in `<project>/sessions/`,
    /// via a save panel defaulted to a "<original> edited" name — collision-
    /// safe via `LiveSessionController.uniqueSessionURL`/`sanitizedSessionName`
    /// (the same naming the recorder itself uses), so this never silently
    /// overwrites the original take.
    private func presentSaveCopyPanel() {
        saveError = nil
        let sessionsDir = projectURL.appendingPathComponent("sessions")
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        let base = sessionURL.deletingPathExtension().lastPathComponent + " edited"
        let defaultURL = LiveSessionController.uniqueSessionURL(
            in: sessionsDir,
            base: LiveSessionController.sanitizedSessionName(base) ?? LiveSessionController.timestampedSessionName()
        )

        let panel = NSSavePanel()
        panel.directoryURL = sessionsDir
        panel.nameFieldStringValue = defaultURL.lastPathComponent
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try writeEvents(recordedEvents.map(\.event), to: url)
            } catch {
                saveError = "Couldn't save copy: \(error.localizedDescription)"
            }
        }
    }

    /// Same on-disk shape `LiveSessionController.recordEvent` writes — one
    /// flat JSON object per line, no enclosing array.
    private func writeEvents(_ events: [LiveEvent], to url: URL) throws {
        let sorted = events.sorted { $0.t < $1.t }
        let encoder = JSONEncoder()
        var lines: [String] = []
        for event in sorted {
            let data = try encoder.encode(event)
            guard let line = String(data: data, encoding: .utf8) else { continue }
            lines.append(line)
        }
        let contents = lines.joined(separator: "\n") + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadSession() {
        let sessionURL = self.sessionURL
        Task {
            do {
                let events = try await Task.detached(priority: .userInitiated) {
                    try RecordedEvent.load(from: sessionURL)
                }.value
                recordedEvents = events
                isLoading = false
            } catch {
                loadError = "Couldn't load session: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}
