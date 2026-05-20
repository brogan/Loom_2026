import AppKit
import SwiftUI
import AVFoundation
import LoomEngine

struct ExportSheet: View {

    let engine: Engine
    @EnvironmentObject private var controller: AppController
    @Environment(\.dismiss) private var dismiss

    @State private var fps:             Int              = 30
    @State private var startFrame:      Int              = 0
    @State private var endFrame:        Int              = 0
    @State private var codec:           AVVideoCodecType = .h264
    @State private var restartFromZero: Bool             = true
    @State private var isExporting      = false
    @State private var exportError:     String?

    private let fpsOptions:   [Int]                           = [24, 25, 30, 60]
    private let codecOptions: [(AVVideoCodecType, String)]    = [
        (.h264, "H.264"), (.hevc, "HEVC (H.265)"), (.proRes4444, "ProRes 4444")
    ]

    private var totalFrames: Int { max(1, endFrame - max(0, startFrame)) }
    private var durationSeconds: Double { Double(totalFrames) / Double(fps) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Video").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 12)

            Divider()

            Form {
                Section("Canvas") {
                    LabeledContent("Size") {
                        Text("\(engine.globalConfig.width) × \(engine.globalConfig.height) px")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Quality") {
                        Text("\(engine.globalConfig.qualityMultiple)×").foregroundStyle(.secondary)
                    }
                }
                Section("Frame Range") {
                    HStack {
                        Text("Start frame")
                        Spacer()
                        TextField("", value: $startFrame, format: .number)
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("End frame")
                        Spacer()
                        TextField("", value: $endFrame, format: .number)
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Total frames") {
                        Text("\(totalFrames)").foregroundStyle(.secondary)
                    }
                    LabeledContent("Duration") {
                        Text(String(format: "%.2f s", durationSeconds)).foregroundStyle(.secondary)
                    }
                }
                Section("Video") {
                    Picker("Frame rate", selection: $fps) {
                        ForEach(fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Codec", selection: $codec) {
                        ForEach(codecOptions, id: \.0.rawValue) { Text($1).tag($0) }
                    }

                    Toggle("Restart from beginning", isOn: $restartFromZero)
                }
            }
            .formStyle(.grouped)
            .disabled(isExporting)

            Divider()

            VStack(spacing: 8) {
                if isExporting {
                    ProgressView(value: controller.exportProgress).padding(.horizontal)
                    Text("Frame \(Int(controller.exportProgress * Double(totalFrames))) of \(totalFrames)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let err = exportError {
                    Text(err).foregroundStyle(.red).font(.caption)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                HStack {
                    Button("Cancel") { dismiss() }.disabled(isExporting)
                    Spacer()
                    Button(isExporting ? "Exporting…" : "Export") { startExport() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isExporting || endFrame <= startFrame)
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            startFrame = engine.globalConfig.startFrame
            fps        = Int(engine.globalConfig.targetFPS)
            let max = engine.maxAnimationFrames
            // For purely parametric animations maxAnimationFrames is 0 (unbounded).
            // Default to 10 seconds so the export field has a usable starting value.
            endFrame = max > 0 ? max : Int(engine.globalConfig.targetFPS) * 10
        }
    }

    private func startExport() {
        guard endFrame > startFrame else { return }
        let name = engine.globalConfig.name.isEmpty
            ? (controller.projectURL?.lastPathComponent ?? "loom")
            : engine.globalConfig.name
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        let panel = NSSavePanel()
        panel.allowedContentTypes  = [.movie]
        panel.nameFieldStringValue = "\(name)_\(f.string(from: Date())).mov"
        if let dir = controller.animationRendersDirectory() { panel.directoryURL = dir }

        let fps = self.fps; let startFrame = self.startFrame; let endFrame = self.endFrame
        let codec = self.codec; let restart = self.restartFromZero
        let engine = self.engine

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            isExporting = true
            exportError = nil
            controller.beginExport()
            Task {
                do {
                    if restart { try engine.reset() }
                    let settings = VideoExporter.Settings(fps: fps, startFrame: startFrame,
                                                          endFrame: endFrame, codec: codec,
                                                          outputURL: url)
                    let progress: @Sendable (Double) -> Void = { p in
                        Task { @MainActor in controller.exportProgress = p }
                    }
                    try await VideoExporter().export(engine: engine, settings: settings,
                                                     progress: progress)
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
    }
}
