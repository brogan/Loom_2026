import SwiftUI
import LoomEngine

struct GlobalInspector: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        if controller.projectConfig != nil {
            projectSection
            canvasSection
            colorsSection
            playbackSection
            noteSection
            threeDSection
        } else {
            Text("No project open")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(16)
        }
    }

    // MARK: - Sections

    private var projectSection: some View {
        InspectorSection("Project") {
            VStack(alignment: .leading, spacing: 3) {
                if let url = controller.projectURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No project")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            HStack {
                Spacer()
                Button("Change…") { controller.presentOpenPanel() }
                    .font(.system(size: 12))
                    .padding(.trailing, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    private var canvasSection: some View {
        InspectorSection("Canvas") {
            InspectorField("Name") {
                TextField("", text: bind(\.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 120)
            }
            InspectorField("Width") {
                TextField("", value: bind(\.width), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 60)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            InspectorField("Height") {
                TextField("", value: bind(\.height), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 60)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            InspectorField("Quality") {
                TextField("", value: bind(\.qualityMultiple), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 40)
                Text("×").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            InspectorField("Scale img") {
                Toggle("", isOn: bind(\.scaleImage)).labelsHidden()
            }
        }
    }

    private var colorsSection: some View {
        InspectorSection("Colors") {
            LoomColorField(label: "Background", color: bindColor(\.backgroundColor))
            LoomColorField(label: "Border",     color: bindColor(\.borderColor))
            LoomColorField(label: "Overlay",    color: bindColor(\.overlayColor))
        }
    }

    private var playbackSection: some View {
        InspectorSection("Playback") {
            InspectorField("FPS") {
                FloatEntryField(value: bind(\.targetFPS), width: 50, fractionDigits: 1)
            }
            InspectorField("Animating") {
                Toggle("", isOn: bind(\.animating)).labelsHidden()
            }
            InspectorField("BG once") {
                Toggle("", isOn: bind(\.drawBackgroundOnce)).labelsHidden()
            }
        }
    }

    private var noteSection: some View {
        InspectorSection("Note") {
            TextEditor(text: bind(\.note))
                .font(.system(size: 12))
                .frame(minHeight: 80, maxHeight: 120)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private var threeDSection: some View {
        InspectorSection("3-D") {
            InspectorField("Enabled") {
                Toggle("", isOn: bind(\.threeD)).labelsHidden()
            }
            InspectorField("View angle") {
                TextField("", value: bind(\.cameraViewAngle), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Binding helpers

    private func bind<T>(_ kp: WritableKeyPath<GlobalConfig, T>) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.globalConfig[keyPath: kp] ?? GlobalConfig.default[keyPath: kp] },
            set: { v in ctl.updateProjectConfig { $0.globalConfig[keyPath: kp] = v } }
        )
    }

    private func bindColor(_ kp: WritableKeyPath<GlobalConfig, LoomColor>) -> Binding<LoomColor> {
        bind(kp)
    }
}
