import SwiftUI

struct AudioAnalysisInspector: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var audio: AudioController

    @AppStorage("audioinsp.analysisCollapsed") private var analysisCollapsed = false

    private var fps: Double {
        controller.projectConfig?.globalConfig.targetFPS ?? 30
    }

    var body: some View {
        if audio.audioFilename == nil {
            placeholderText("Import an audio file to see analysis.")
        } else if let a = audio.analysis {
            analysisSection(a)
        } else {
            VStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Analysing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func analysisSection(_ a: AudioAnalysis) -> some View {
        let beatsOn = audio.hasAnalysisMarkers(prefix: "b")
        let kicksOn = audio.hasAnalysisMarkers(prefix: "k")

        InspectorSection("Analysis", isCollapsed: $analysisCollapsed) {
            if a.bpm > 0 {
                InspectorRow(label: "BPM",       value: String(format: "%.1f", a.bpm))
                InspectorRow(label: "Beat/frame", value: String(format: "%.2f", 60.0 / a.bpm * fps))
            } else {
                InspectorRow(label: "BPM", value: "—")
            }
            InspectorRow(label: "Beats",       value: "\(a.beatOnsets.count)")
            InspectorRow(label: "Kick events", value: "\(a.lowFreqOnsets.count)")

            HStack(spacing: 8) {
                Button(beatsOn ? "Hide Beats" : "Beat Markers") {
                    audio.toggleAnalysisMarkers(times: a.beatOnsets, fps: fps, prefix: "b")
                }
                .buttonStyle(.bordered)
                .tint(beatsOn ? Color.cyan : nil)
                .controlSize(.small)
                .disabled(a.beatOnsets.isEmpty)
                .modifier(LoomHoverHelp(beatsOn
                    ? "Remove beat markers from the timeline"
                    : "Add a marker at each detected beat onset (cyan ticks)"))

                Button(kicksOn ? "Hide Kicks" : "Kick Markers") {
                    audio.toggleAnalysisMarkers(times: a.lowFreqOnsets, fps: fps, prefix: "k")
                }
                .buttonStyle(.bordered)
                .tint(kicksOn ? Color.green : nil)
                .controlSize(.small)
                .disabled(a.lowFreqOnsets.isEmpty)
                .modifier(LoomHoverHelp(kicksOn
                    ? "Remove kick markers from the timeline"
                    : "Add a marker at each detected low-frequency onset — kick drum proxy (green ticks)"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            HStack(spacing: 12) {
                legendDot(color: .cyan,  label: "beats")
                legendDot(color: .green, label: "kick")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color.opacity(0.65))
                .frame(width: 14, height: 3)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func placeholderText(_ msg: String) -> some View {
        Text(msg)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
