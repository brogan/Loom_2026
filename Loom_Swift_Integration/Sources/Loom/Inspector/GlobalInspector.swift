import AppKit
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
            cameraSection
            noteSection
            statusSection
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
            InspectorField("BG image") {
                let path = bind(\.backgroundImagePath).wrappedValue
                if !path.isEmpty {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 80)
                    Button("✕") {
                        controller.updateProjectConfig { $0.globalConfig.backgroundImagePath = "" }
                    }
                    .font(.system(size: 10))
                }
                Button("Choose…") { pickBackgroundImage() }
                    .font(.system(size: 11))
            }
        }
    }

    private var colorsSection: some View {
        InspectorSection("Colors") {
            LoomColorField(label: "Background", color: bindColor(\.backgroundColor))
            LoomColorField(label: "Border",     color: bindColor(\.borderColor))
            InspectorField("Border width") {
                FloatEntryField(value: bind(\.borderWidth), width: 50, fractionDigits: 1)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            LoomColorField(label: "Overlay",    color: bindColor(\.overlayColor))
        }
    }

    private var playbackSection: some View {
        InspectorSection("Playback") {
            InspectorField("FPS") {
                FloatEntryField(value: bind(\.targetFPS), width: 50, fractionDigits: 1)
            }
            InspectorField("Scrub bar") {
                Toggle("", isOn: $controller.showScrubBar).labelsHidden()
            }
        }
    }

    private var cameraSection: some View {
        InspectorSection("Camera") {
            InspectorField("Enabled") {
                Toggle("", isOn: bind(\.camera.enabled)).labelsHidden()
            }
            InspectorField("Perspective") {
                FloatEntryField(value: bind(\.camera.perspectiveStrength), width: 65, fractionDigits: 4)
                Text("0=flat").font(.system(size: 10)).foregroundStyle(.tertiary)
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

    private var statusSection: some View {
        InspectorSection("Status") {
            Text(controller.appStatusMessage)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Actions

    private func pickBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .heic]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            controller.updateProjectConfig { $0.globalConfig.backgroundImagePath = url.path }
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
