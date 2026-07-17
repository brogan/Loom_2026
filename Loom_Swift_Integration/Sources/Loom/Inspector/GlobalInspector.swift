import AppKit
import SwiftUI
import LoomEngine

private enum CanvasPreset: String, CaseIterable, Identifiable {
    case square = "Square"
    case sd     = "SD"
    case hd     = "HD"
    case fullHD = "Full HD"
    case uhd4k  = "4K"
    case a4     = "A4"
    case a2     = "A2"
    case custom = "Custom"

    var id: String { rawValue }

    var size: (width: Int, height: Int)? {
        switch self {
        case .square: return (1080, 1080)
        case .sd:     return (640,  480)
        case .hd:     return (1280, 720)
        case .fullHD: return (1920, 1080)
        case .uhd4k:  return (3840, 2160)
        case .a4:     return (630,  891)
        case .a2:     return (840,  1188)
        case .custom: return nil
        }
    }

    static func matching(width: Int, height: Int) -> CanvasPreset {
        allCases.first { $0.size?.width == width && $0.size?.height == height } ?? .custom
    }
}

struct GlobalInspector: View {

    @EnvironmentObject private var controller: AppController

    @State private var renameText:  String  = ""
    @State private var renameError: String? = nil
    @State private var renameActive: Bool   = false

    var body: some View {
        if controller.projectConfig != nil {
            projectSection
            canvasSection
            colorsSection
            playbackSection
            cameraSection
            noteSection
            statusSection
            Divider()
            utilitySection
            liveEvolutionSeedSection
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
            VStack(alignment: .leading, spacing: 6) {
                if let url = controller.projectURL {
                    HStack(spacing: 6) {
                        TextField("Project name", text: $renameText)
                            .textFieldStyle(.squareBorder)
                            .font(.system(size: 12, weight: .medium))
                            .onAppear { renameText = url.lastPathComponent }
                            .onChange(of: url.lastPathComponent) { _, name in renameText = name }
                            .onSubmit { doRename() }
                        Button("Rename") { doRename() }
                            .font(.system(size: 11))
                            .disabled(renameText.isEmpty || renameText == url.lastPathComponent)
                    }
                    .padding(.horizontal, 12)
                    if let err = renameError {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 12)
                } else {
                    Text("No project")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                }
            }
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

    private func doRename() {
        renameError = controller.renameProject(to: renameText)
    }

    private var presetBinding: Binding<CanvasPreset> {
        Binding(
            get: {
                guard let cfg = controller.projectConfig else { return .square }
                return CanvasPreset.matching(width: cfg.globalConfig.width, height: cfg.globalConfig.height)
            },
            set: { preset in
                if let size = preset.size {
                    controller.updateProjectConfig {
                        $0.globalConfig.width  = size.width
                        $0.globalConfig.height = size.height
                    }
                }
            }
        )
    }

    private var canvasSection: some View {
        InspectorSection("Canvas") {
            InspectorField("Format") {
                Picker("", selection: presetBinding) {
                    ForEach(CanvasPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)
            }
            .loomHelp("Standard output size preset. Selecting a preset sets Width and Height automatically; editing dimensions manually shows Custom.")
            InspectorField("Width") {
                TextField("", value: bind(\.width), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 60)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Canvas width in pixels at 1× quality. Actual render width = Width × Quality multiplier.")
            InspectorField("Height") {
                TextField("", value: bind(\.height), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 60)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Canvas height in pixels at 1× quality. Actual render height = Height × Quality multiplier.")
            InspectorField("Quality") {
                TextField("", value: bind(\.qualityMultiple), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 40)
                Text("×").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Render quality multiplier. 2 doubles both dimensions (4× pixel count). Use 1 for fast preview, 2–4 for final export.")
            InspectorField("Scale img") {
                Toggle("", isOn: bind(\.scaleImage)).labelsHidden()
            }
            .loomHelp("When on, stroke widths, point sizes, and brush metrics are scaled by the quality multiplier so the output looks identical to the 1× render when scaled down. When off, those values stay at their logical-pixel sizes.")
            InspectorField("Softness") {
                FloatEntryField(value: bind(\.renderSoftness), width: 50, fractionDigits: 1)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Gaussian blur radius applied to each rendered frame, in logical pixels. Scaled by the quality multiplier at render time. Use to match the softer anti-aliasing appearance of lower-quality renders. 0 = off.")
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
            .loomHelp("Background image drawn behind all sprites. Supported formats: PNG, JPEG, TIFF, BMP, HEIC.")
        }
    }

    private var colorsSection: some View {
        InspectorSection("Colors") {
            LoomColorField(label: "Background", color: bindColor(\.backgroundColor))
                .loomHelp("Canvas background fill colour rendered behind all sprites.")
            LoomColorField(label: "Border",     color: bindColor(\.borderColor))
                .loomHelp("Colour of the optional border drawn around the canvas edge.")
            InspectorField("Border width") {
                FloatEntryField(value: bind(\.borderWidth), width: 50, fractionDigits: 1)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Thickness of the canvas border in pixels at 1× quality. Set to 0 for no border.")
            LoomColorField(label: "Overlay",    color: bindColor(\.overlayColor))
                .loomHelp("Colour tinted over the entire canvas after all sprites are drawn. Useful for global colour grading or vignettes.")
        }
    }

    private var playbackSection: some View {
        InspectorSection("Playback") {
            InspectorField("FPS") {
                FloatEntryField(value: bind(\.targetFPS), width: 50, fractionDigits: 1)
            }
            .loomHelp("Target frame rate for preview playback in frames per second. Actual rate depends on render complexity.")
            InspectorField("Scrub bar") {
                Toggle("", isOn: $controller.showScrubBar).labelsHidden()
            }
            .loomHelp("Show or hide the timeline scrub bar below the canvas.")
        }
    }

    private var cameraSection: some View {
        InspectorSection("Camera") {
            InspectorField("Enabled") {
                Toggle("", isOn: bind(\.camera.enabled)).labelsHidden()
            }
            .loomHelp("Activates perspective projection. When off, all sprites are rendered in flat 2D regardless of their Depth value.")
            InspectorField("Perspective") {
                FloatEntryField(value: bind(\.camera.perspectiveStrength), width: 65, fractionDigits: 4)
                Text("0=flat").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .loomHelp("Strength of the perspective effect. 0 = flat orthographic; larger values increase depth distortion for sprites away from the focal plane.")
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

    private var utilitySection: some View {
        InspectorSection("Utility") {
            Text("Move all renders from every project into a single folder for easy archiving or offloading to another disk.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 6)

            HStack(spacing: 8) {
                Button("Collect All Renders…") { confirmAndCollect() }
                    .disabled(controller.isCollectingRenders)
                    .loomHelp("Scan every project in the Loom projects directory and move stills → All/stills and animations → All/animations. Files are renamed ProjectName_0001.ext in chronological order. Running again only moves new renders.")

                if controller.isCollectingRenders {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(height: 16)
                }

                Spacer()

                if controller.allRendersDirectoryExists {
                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: controller.allRendersDirectory.path)
                    }
                    .loomHelp("Open the All renders folder in Finder.")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    /// Live readout of the seed actually driving the currently-selected Generational
    /// Evolution pass (selected in the Transform tab) at the current timeline frame.
    /// With "Vary seed per cycle" on, this changes each time the reveal loops — the
    /// point is to let a user watching an animated reveal note the seed of a
    /// generation they like, then paste it into that pass's Seed field (with Vary
    /// seed per cycle off) to reproduce that exact result.
    private var liveEvolutionSeedSection: some View {
        InspectorSection("Evolution Seed") {
            if let info = liveGenerationalSeedInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(info.setName) → \(info.passName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text("Seed")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(info.seed)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        if info.varying {
                            Text("cycle \(info.cycle)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                Text("Select a Generational Evolution pass in the Transform tab to see its live seed here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .loomHelp("The seed actually in effect for the selected Generational Evolution pass right now. Unchanged from the pass's own Seed field unless \"Vary seed per cycle\" is on, in which case it updates every time the reveal driver completes a cycle. Copy the number shown (select the text) into the pass's Seed field and turn off Vary seed per cycle to lock in and reproduce this exact generation.")
    }

    private struct LiveSeedInfo {
        let setName:  String
        let passName: String
        let seed:     Int
        let cycle:    Int
        let varying:  Bool
    }

    private var liveGenerationalSeedInfo: LiveSeedInfo? {
        guard let setIdx = controller.selectedSubdivisionIndex,
              let evIdx  = controller.selectedEvolutionParamIndex,
              let set    = controller.projectConfig?.subdivisionConfig.paramsSets[safe: setIdx],
              let pass   = set.evolutionPasses[safe: evIdx],
              pass.operationType == .generational
        else { return nil }

        let elapsedFrames = Double(controller.currentTimelineFrame)
        let targetFPS     = controller.engine?.globalConfig.targetFPS ?? 24
        let seed  = GenerationalEvolutionEngine.effectiveSeed(for: pass, elapsedFrames: elapsedFrames, targetFPS: targetFPS)
        let cycle = GenerationalEvolutionEngine.revealCycleIndex(for: pass.generationPhase, elapsedFrames: elapsedFrames, targetFPS: targetFPS)
        return LiveSeedInfo(
            setName:  set.name.isEmpty ? "(unnamed set)" : set.name,
            passName: pass.name.isEmpty ? "(unnamed pass)" : pass.name,
            seed:     seed,
            cycle:    cycle,
            varying:  pass.varySeedPerCycle && pass.generationPhase.enabled
        )
    }

    // MARK: - Actions

    private func confirmAndCollect() {
        let alert             = NSAlert()
        alert.messageText     = "Collect all renders?"
        alert.informativeText = "Stills and animations from every project in \(AppController.defaultProjectsDirectory.lastPathComponent) will be moved to the All folder. Files in All that are already collected will not be duplicated. This action cannot be undone."
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Collect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        controller.collectRenders()
    }

    private func pickBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .heic]
        panel.allowsMultipleSelection = false
        panel.directoryURL = controller.projectURL?.appendingPathComponent("background_image")
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
