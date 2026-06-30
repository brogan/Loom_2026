import SwiftUI
import UniformTypeIdentifiers

struct AudioTabView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var audio: AudioController
    @State private var renamingID: UUID?  = nil
    @State private var renameText: String = ""

    private var fps: Double {
        controller.projectConfig?.globalConfig.targetFPS ?? 30
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if audio.audioFilename == nil {
                emptyState
            } else {
                transportSection
                Divider()
                markersSection
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Audio")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button { importAudio() } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 12))
                    .iconHitArea()
            }
            .buttonStyle(.plain)
            .modifier(LoomHoverHelp("Import audio file"))

            if audio.audioFilename != nil {
                Button { audio.clear() } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                        .iconHitArea()
                }
                .buttonStyle(.plain)
                .modifier(LoomHoverHelp("Remove audio"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No audio loaded")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Import Audio…") { importAudio() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Transport

    private var transportSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let name = audio.audioFilename {
                Text(audio.fileNotFound ? "\(name) — file not found" : name)
                    .font(.system(size: 11))
                    .foregroundStyle(audio.fileNotFound ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
            }

            HStack(spacing: 10) {
                Button { audio.togglePlayPause() } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .iconHitArea(28)
                }
                .buttonStyle(.plain)
                .disabled(audio.fileNotFound || audio.duration == 0)

                Button { audio.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13))
                        .iconHitArea(24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(audio.fileNotFound || audio.duration == 0)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatTimecode(audio.currentTime, fps: fps))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text("/ \(formatTimecode(audio.duration, fps: fps))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .trailing, spacing: 1) {
                    Text("f")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("\(Int((audio.currentTime * fps).rounded()))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
            }
            .padding(.horizontal, 12)

            Slider(
                value: Binding(
                    get: { audio.currentTime },
                    set: { audio.seek(to: $0) }
                ),
                in: 0...max(1, audio.duration)
            )
            .disabled(audio.fileNotFound || audio.duration == 0)
            .padding(.horizontal, 12)

            Button {
                audio.dropMarker(fps: fps)
            } label: {
                Label("Drop Marker", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("m", modifiers: .command)
            .disabled(audio.fileNotFound || audio.duration == 0)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Markers

    private var markersSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Markers")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !audio.markers.isEmpty {
                    Text("\(audio.markers.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            Divider()

            if audio.markers.isEmpty {
                Text("No markers — use ⌘M to drop one")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(audio.markers) { marker in
                            markerRow(marker)
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }

    private func markerRow(_ marker: AudioMarker) -> some View {
        HStack(spacing: 6) {
            Button {
                audio.seek(to: Double(marker.frame) / fps)
            } label: {
                Image(systemName: "mappin")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                    .iconHitArea()
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if renamingID == marker.id {
                    TextField("Label", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit {
                            audio.updateMarkerLabel(id: marker.id, label: renameText)
                            renamingID = nil
                        }
                } else {
                    Text(marker.label.isEmpty ? "Marker" : marker.label)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            renameText = marker.label
                            renamingID = marker.id
                        }
                }
                Text("f\(marker.frame)  ·  \(formatTimecode(Double(marker.frame) / fps, fps: fps))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                audio.removeMarker(id: marker.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .iconHitArea()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func importAudio() {
        guard controller.projectURL != nil else { return }
        let panel = NSOpenPanel()
        panel.title              = "Import Audio"
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = supportedAudioTypes()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        audio.importAudio(from: url)
    }

    private func supportedAudioTypes() -> [UTType] {
        ["wav", "aiff", "aif", "mp3", "m4a", "caf", "flac", "aac"]
            .compactMap { UTType(filenameExtension: $0) }
    }

    private func formatTimecode(_ t: Double, fps: Double) -> String {
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
