import SwiftUI
import AVFoundation
import LoomEngine

// MARK: - ExportSheet

/// A sheet that presents video export options.
struct ExportSheet: View {

    let engine: Engine
    @EnvironmentObject private var controller: EngineController
    @Environment(\.dismiss) private var dismiss

    // MARK: - Export settings state

    @State private var fps:           Int              = 30
    @State private var startFrame:    Int              = 0
    @State private var endFrame:      Int              = 0
    @State private var codec:         AVVideoCodecType = .h264
    @State private var restartFromZero: Bool           = true

    // MARK: - UI state

    @State private var isExporting  = false
    @State private var exportError: String?

    private let fpsOptions:   [Int]              = [24, 25, 30, 60]
    private let codecOptions: [(AVVideoCodecType, String)] = [
        (.h264,       "H.264"),
        (.hevc,       "HEVC (H.265)"),
        (.proRes4444, "ProRes 4444"),
    ]

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Export Video")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 12)

            Divider()

            // Settings form
            Form {
                Section("Canvas") {
                    LabeledContent("Size") {
                        Text("\(engine.globalConfig.width) × \(engine.globalConfig.height) px")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Quality multiple") {
                        Text("\(engine.globalConfig.qualityMultiple)×")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Frame Range") {
                    HStack {
                        Text("Start frame")
                        Spacer()
                        TextField("", value: $startFrame, format: .number)
                            .frame(width: 72).textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("End frame")
                        Spacer()
                        TextField("", value: $endFrame, format: .number)
                            .frame(width: 72).textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Total frames") {
                        Text("\(max(1, endFrame - max(0, startFrame)))").foregroundStyle(.secondary)
                    }
                    LabeledContent("Duration") {
                        let total = max(1, endFrame - max(0, startFrame))
                        Text(String(format: "%.2f s", Double(total) / Double(fps))).foregroundStyle(.secondary)
                    }
                }

                Section("Video") {
                    Picker("Frame rate", selection: $fps) {
                        ForEach(fpsOptions, id: \.self) { f in
                            Text("\(f) fps").tag(f)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Codec", selection: $codec) {
                        ForEach(codecOptions, id: \.0.rawValue) { option in
                            Text(option.1).tag(option.0)
                        }
                    }

                    Toggle("Restart animation from beginning", isOn: $restartFromZero)
                }
            }
            .formStyle(.grouped)
            .disabled(isExporting)

            Divider()

            // Progress / error / action row
            VStack(spacing: 8) {
                if isExporting {
                    ProgressView(value: controller.exportProgress)
                        .padding(.horizontal)

                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let err = exportError {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                HStack {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)

                    Spacer()

                    Button(isExporting ? "Exporting…" : "Export") {
                        startExport()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting || endFrame <= startFrame)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private var totalFrames: Int { max(1, endFrame - max(0, startFrame)) }

    private var progressLabel: String {
        let done = Int(controller.exportProgress * Double(totalFrames))
        return "Frame \(done) of \(totalFrames)"
    }

    // MARK: - Export action

    private func startExport() {
        guard endFrame > startFrame else { return }

        let projectName = engine.globalConfig.name.isEmpty
            ? (controller.projectURL?.lastPathComponent ?? "loom")
            : engine.globalConfig.name

        let timestamp = timestampString()
        let filename  = "\(projectName)_\(timestamp).mov"

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes  = [.movie]
        savePanel.nameFieldStringValue = filename
        savePanel.prompt               = "Export Video"
        if let dir = controller.animationRendersDirectory() {
            savePanel.directoryURL = dir
        }

        let fps           = self.fps
        let startFrame    = self.startFrame
        let endFrame      = self.endFrame
        let codec         = self.codec
        let shouldRestart = self.restartFromZero
        let engine        = self.engine

        let beginExportTask: (URL) -> Void = { url in
            isExporting = true
            exportError = nil
            controller.beginExport()

            let settings = VideoExporter.Settings(
                fps:        fps,
                startFrame: startFrame,
                endFrame:   endFrame,
                codec:      codec,
                outputURL:  url
            )

            let progressCallback: @Sendable (Double) -> Void = { [weak controller] p in
                Task { @MainActor in controller?.exportProgress = p }
            }

            Task {
                do {
                    if shouldRestart { try engine.reset() }
                    let exporter = VideoExporter()
                    try await exporter.export(engine: engine,
                                              settings: settings,
                                              progress: progressCallback)
                    controller.endExport()
                    isExporting = false
                    dismiss()
                } catch {
                    exportError = error.localizedDescription
                    controller.endExport(error: error)
                    isExporting = false
                }
            }
        }

        // Use begin() rather than runModal() to avoid blocking the SwiftUI
        // event loop (runModal() causes the filename field to lose focus).
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            beginExportTask(url)
        }
    }

    private func timestampString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
