import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LoomEngine

// MARK: - Main editor sheet

struct SpriteCycleEditorView: View {

    @EnvironmentObject private var controller: AppController
    @State private var selectedStateIndex: Int? = nil
    @State private var expandedStateIndices: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let idx = controller.selectedCycleIndex,
               let cycles = controller.projectConfig?.cycles,
               cycles.indices.contains(idx) {
                let cycle = cycles[idx]
                HStack(spacing: 0) {
                    // Left: cycle controls + state list
                    VStack(spacing: 0) {
                        cycleMetaSection(cycle: cycle, idx: idx)
                        Divider()
                        ScrollView {
                            stateListSection(cycle: cycle, cycleIdx: idx)
                        }
                    }
                    .frame(width: 360)

                    Divider()

                    // Right: preview with onion skinning
                    CyclePreviewPanel(cycle: cycle, selectedStateIndex: $selectedStateIndex)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                emptyCycleMessage
            }
        }
        .frame(minWidth: 560, idealWidth: 680, maxWidth: .infinity,
               minHeight: 440, idealHeight: 540, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Cycle Editor")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("Done") {
                controller.showingCycleEditor = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Cycle metadata

    private func cycleMetaSection(cycle: SpriteCycle, idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Name")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                TextField("", text: bindName(idx))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 160)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                Text("Loop")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: bindLoopMode(idx)) {
                    ForEach(SpriteCycleLoopMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                Spacer()

                Text("\(cycle.totalCycleFrames) frames")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: State list

    private func stateListSection(cycle: SpriteCycle, cycleIdx: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("States")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
                Spacer()
                Button {
                    addState(toCycle: cycleIdx)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Add state")

                Button {
                    if let s = selectedStateIndex {
                        removeState(at: s, fromCycle: cycleIdx)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(selectedStateIndex == nil)
                .help("Remove selected state")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if cycle.states.isEmpty {
                Text("No states. Press + to add.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(cycle.states.indices, id: \.self) { si in
                    stateRow(cycle: cycle, cycleIdx: cycleIdx, stateIdx: si)
                    Divider()
                }
            }
        }
    }

    // MARK: State row

    private func stateRow(cycle: SpriteCycle, cycleIdx: Int, stateIdx: Int) -> some View {
        let state = cycle.states[stateIdx]
        let isSelected = selectedStateIndex == stateIdx
        let isExpanded = expandedStateIndices.contains(stateIdx)

        return VStack(alignment: .leading, spacing: 0) {
            // Summary row
            HStack(spacing: 8) {
                Text("\(stateIdx + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    if let svg = state.svgFilename {
                        Text(svg.isEmpty ? "No image file" : svg)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Text("Image sprite")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(state.shapeName.isEmpty ? "—" : state.shapeName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Text(state.shapeSetName.isEmpty ? "no set" : state.shapeSetName)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("hold \(state.holdFrames)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                if state.transitionFrames > 0 {
                    Text("→ \(state.transitionFrames)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    if isExpanded {
                        expandedStateIndices.remove(stateIdx)
                    } else {
                        expandedStateIndices.insert(stateIdx)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { selectedStateIndex = stateIdx }

            // Expanded detail
            if isExpanded {
                stateDetail(cycleIdx: cycleIdx, stateIdx: stateIdx)
                    .padding(.bottom, 6)
                    .background(Color.primary.opacity(0.03))
            }
        }
    }

    // MARK: State detail

    private func stateDetail(cycleIdx: Int, stateIdx: Int) -> some View {
        let isSVG        = controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.svgFilename != nil
        let svgFilename  = controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.svgFilename ?? ""
        let allShapeSets = controller.projectConfig?.shapeConfig.library.shapeSets ?? []
        let shapeSetName = controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.shapeSetName ?? ""
        let shapesInSet  = allShapeSets.first(where: { $0.name == shapeSetName })?.shapes.map { $0.name } ?? []
        let allRendererSets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []

        return VStack(alignment: .leading, spacing: 4) {
            // Source type toggle
            stateDetailRow("Source") {
                Picker("", selection: Binding(
                    get: { isSVG },
                    set: { newIsSVG in
                        controller.updateProjectConfig { cfg in
                            guard cfg.cycles.indices.contains(cycleIdx),
                                  cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                            cfg.cycles[cycleIdx].states[stateIdx].svgFilename = newIsSVG ? "" : nil
                        }
                    }
                )) {
                    Text("Loom").tag(false)
                    Text("Image").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 120)
            }

            if isSVG {
                // Image file
                stateDetailRow("Image File") {
                    HStack(spacing: 6) {
                        Text(svgFilename.isEmpty ? "No file chosen" : svgFilename)
                            .font(.system(size: 11))
                            .foregroundStyle(svgFilename.isEmpty ? .tertiary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 110, alignment: .leading)
                        Button("Choose…") {
                            pickSVGFile(cycleIdx: cycleIdx, stateIdx: stateIdx)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                    }
                }
            } else {
                // Shape set
                stateDetailRow("Shape Set") {
                    Picker("", selection: bindStateStr(cycleIdx, stateIdx, \.shapeSetName)) {
                        Text("—").tag("")
                        ForEach(allShapeSets, id: \.name) { set in
                            Text(set.name).tag(set.name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                // Shape name
                stateDetailRow("Shape") {
                    if shapesInSet.isEmpty {
                        TextField("", text: bindStateStr(cycleIdx, stateIdx, \.shapeName))
                            .textFieldStyle(.squareBorder)
                            .font(.system(size: 12))
                            .frame(maxWidth: 180)
                    } else {
                        Picker("", selection: bindStateStr(cycleIdx, stateIdx, \.shapeName)) {
                            Text("—").tag("")
                            ForEach(shapesInSet, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 180)
                    }
                }

                // Renderer override
                stateDetailRow("Renderer") {
                    Picker("", selection: bindStateOptStr(cycleIdx, stateIdx, \.rendererSetName)) {
                        Text("Inherit").tag(String?.none)
                        ForEach(allRendererSets, id: \.name) { set in
                            Text(set.name).tag(String?.some(set.name))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
            }

            Divider().padding(.horizontal, 12)
            poseSection(cycleIdx: cycleIdx, stateIdx: stateIdx)
            Divider().padding(.horizontal, 12)

            // Hold frames
            stateDetailRow("Hold frames") {
                IntStepperField(value: bindStateInt(cycleIdx, stateIdx, \.holdFrames), min: 1, max: 999)
            }

            // Transition frames
            stateDetailRow("Trans frames") {
                IntStepperField(value: bindStateInt(cycleIdx, stateIdx, \.transitionFrames), min: 0, max: 999)
            }

            // Easing (only shown when transitionFrames > 0)
            let hasTrans = (controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.transitionFrames ?? 0) > 0
            if hasTrans {
                stateDetailRow("Easing") {
                    Picker("", selection: bindStateEasing(cycleIdx, stateIdx)) {
                        ForEach(EasingType.allCases, id: \.self) { e in
                            Text(e.rawValue.capitalized.replacingOccurrences(of: "_", with: " "))
                                .tag(e)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }
                stateDetailRow("Style tween") {
                    Toggle("", isOn: bindStateBool(cycleIdx, stateIdx, \.styleTween))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
            }
        }
        .padding(.top, 4)
    }

    private func pickSVGFile(cycleIdx: Int, stateIdx: Int) {
        let supportedExts = ["svg", "png", "jpg", "jpeg", "tiff", "tif", "gif", "webp"]
        let panel = NSOpenPanel()
        panel.allowedContentTypes = supportedExts.compactMap { UTType(filenameExtension: $0) }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an image file (SVG, PNG, JPG, TIFF, GIF) for this cycle state"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let projectURL = controller.projectURL else { return }
            let filename = url.lastPathComponent
            let destDir  = projectURL.appendingPathComponent("svgs/sprites")
            let destURL  = destDir.appendingPathComponent(filename)
            do {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: url, to: destURL)
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Could not copy image"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                return
            }
            // Inject the new image into the engine's live cache so the canvas updates
            // immediately without requiring a project reload.
            if let img = NSImage(contentsOf: destURL) {
                controller.registerSpriteImage(img, filename: filename)
            }
            controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx].svgFilename = filename
            }
        }
    }

    private func stateDetailRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 94, alignment: .leading)
                .padding(.leading, 28)
            content()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    // MARK: Pose editor

    private func poseSection(cycleIdx: Int, stateIdx: Int) -> some View {
        let overrides = controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.poseOverrides ?? [:]
        let allSpriteNames = controller.projectConfig?.spriteConfig.library.spriteSets
            .flatMap { $0.sprites }.map { $0.name } ?? []
        let overriddenNames = Set(overrides.keys)
        let available = allSpriteNames.filter { !overriddenNames.contains($0) }
        let sorted = overrides.keys.sorted()

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("POSES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
                Spacer()
                if !available.isEmpty {
                    Menu {
                        ForEach(available, id: \.self) { name in
                            Button(name) {
                                addPoseOverride(spriteName: name, cycleIdx: cycleIdx, stateIdx: stateIdx)
                            }
                        }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 12))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Add pose override for a sprite")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            if sorted.isEmpty {
                Text("No pose overrides")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                ForEach(sorted, id: \.self) { name in
                    poseOverrideRows(cycleIdx: cycleIdx, stateIdx: stateIdx, spriteName: name)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func poseOverrideRows(cycleIdx: Int, stateIdx: Int, spriteName: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(spriteName)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.leading, 28)
                Spacer()
                Button {
                    removePoseOverride(spriteName: spriteName, cycleIdx: cycleIdx, stateIdx: stateIdx)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 12)
            }
            .padding(.vertical, 2)

            stateDetailRow("Pos") {
                HStack(spacing: 4) {
                    Text("X").font(.system(size: 10)).foregroundStyle(.secondary)
                    FloatEntryField(value: bindPoseDouble(cycleIdx, stateIdx, spriteName, \.position.x), width: 54, fractionDigits: 2)
                    Text("Y").font(.system(size: 10)).foregroundStyle(.secondary)
                    FloatEntryField(value: bindPoseDouble(cycleIdx, stateIdx, spriteName, \.position.y), width: 54, fractionDigits: 2)
                }
            }
            stateDetailRow("Rot") {
                HStack(spacing: 4) {
                    FloatEntryField(value: bindPoseDouble(cycleIdx, stateIdx, spriteName, \.rotation), width: 65, fractionDigits: 2)
                    Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            stateDetailRow("Scale") {
                HStack(spacing: 4) {
                    Text("X").font(.system(size: 10)).foregroundStyle(.secondary)
                    FloatEntryField(value: bindPoseDouble(cycleIdx, stateIdx, spriteName, \.scale.x), width: 54, fractionDigits: 3)
                    Text("Y").font(.system(size: 10)).foregroundStyle(.secondary)
                    FloatEntryField(value: bindPoseDouble(cycleIdx, stateIdx, spriteName, \.scale.y), width: 54, fractionDigits: 3)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func bindPoseDouble(_ cycleIdx: Int, _ stateIdx: Int, _ spriteName: String,
                                 _ kp: WritableKeyPath<SpritePoseOverride, Double>) -> Binding<Double> {
        Binding(
            get: {
                controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?
                    .poseOverrides[spriteName]?[keyPath: kp] ?? 0
            },
            set: { v in
                controller.updateProjectConfig { cfg in
                    guard cfg.cycles.indices.contains(cycleIdx),
                          cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                    cfg.cycles[cycleIdx].states[stateIdx].poseOverrides[spriteName]?[keyPath: kp] = v
                }
            }
        )
    }

    private func addPoseOverride(spriteName: String, cycleIdx: Int, stateIdx: Int) {
        let baseDef = controller.projectConfig?.spriteConfig.library.spriteSets
            .flatMap { $0.sprites }
            .first(where: { $0.name == spriteName })
        let initialOverride = SpritePoseOverride(
            position: baseDef?.position ?? .zero,
            rotation: baseDef?.rotation ?? 0,
            scale:    baseDef?.scale    ?? Vector2D(x: 1, y: 1)
        )
        controller.updateProjectConfig { cfg in
            guard cfg.cycles.indices.contains(cycleIdx),
                  cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
            cfg.cycles[cycleIdx].states[stateIdx].poseOverrides[spriteName] = initialOverride
        }
    }

    private func removePoseOverride(spriteName: String, cycleIdx: Int, stateIdx: Int) {
        controller.updateProjectConfig { cfg in
            guard cfg.cycles.indices.contains(cycleIdx),
                  cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
            cfg.cycles[cycleIdx].states[stateIdx].poseOverrides.removeValue(forKey: spriteName)
        }
    }

    // MARK: Empty state

    private var emptyCycleMessage: some View {
        VStack(spacing: 8) {
            Text("No cycle selected.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func addState(toCycle cycleIdx: Int) {
        guard let cfg = controller.projectConfig,
              cfg.cycles.indices.contains(cycleIdx)
        else { return }
        let firstShapeSet = cfg.shapeConfig.library.shapeSets.first
        let newState = SpriteCycleState(
            shapeSetName: firstShapeSet?.name ?? "",
            shapeName: firstShapeSet?.shapes.first?.name ?? ""
        )
        controller.updateProjectConfig { cfg in
            cfg.cycles[cycleIdx].states.append(newState)
        }
        let newIdx = (controller.projectConfig?.cycles[cycleIdx].states.count ?? 1) - 1
        selectedStateIndex = newIdx
        expandedStateIndices.insert(newIdx)
    }

    private func removeState(at stateIdx: Int, fromCycle cycleIdx: Int) {
        guard let cfg = controller.projectConfig,
              cfg.cycles.indices.contains(cycleIdx),
              cfg.cycles[cycleIdx].states.indices.contains(stateIdx)
        else { return }
        controller.updateProjectConfig { cfg in
            cfg.cycles[cycleIdx].states.remove(at: stateIdx)
        }
        expandedStateIndices.remove(stateIdx)
        let remaining = controller.projectConfig?.cycles[safe: cycleIdx]?.states.count ?? 0
        selectedStateIndex = remaining == 0 ? nil : min(stateIdx, remaining - 1)
    }

    // MARK: Bindings

    private func bindName(_ cycleIdx: Int) -> Binding<String> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.name ?? "" },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx) else { return }
                cfg.cycles[cycleIdx].name = v
            }}
        )
    }

    private func bindLoopMode(_ cycleIdx: Int) -> Binding<SpriteCycleLoopMode> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.loopMode ?? .loop },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx) else { return }
                cfg.cycles[cycleIdx].loopMode = v
            }}
        )
    }

    private func bindStateStr(_ cycleIdx: Int, _ stateIdx: Int,
                               _ kp: WritableKeyPath<SpriteCycleState, String>) -> Binding<String> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?[keyPath: kp] ?? "" },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx][keyPath: kp] = v
            }}
        )
    }

    private func bindStateOptStr(_ cycleIdx: Int, _ stateIdx: Int,
                                  _ kp: WritableKeyPath<SpriteCycleState, String?>) -> Binding<String?> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?[keyPath: kp] ?? nil },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx][keyPath: kp] = v
            }}
        )
    }

    private func bindStateInt(_ cycleIdx: Int, _ stateIdx: Int,
                               _ kp: WritableKeyPath<SpriteCycleState, Int>) -> Binding<Int> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?[keyPath: kp] ?? 1 },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx][keyPath: kp] = v
            }}
        )
    }

    private func bindStateBool(_ cycleIdx: Int, _ stateIdx: Int,
                                _ kp: WritableKeyPath<SpriteCycleState, Bool>) -> Binding<Bool> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?[keyPath: kp] ?? false },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx][keyPath: kp] = v
            }}
        )
    }

    private func bindStateEasing(_ cycleIdx: Int, _ stateIdx: Int) -> Binding<EasingType> {
        Binding(
            get: { controller.projectConfig?.cycles[safe: cycleIdx]?.states[safe: stateIdx]?.easing ?? .easeInOutCubic },
            set: { v in controller.updateProjectConfig { cfg in
                guard cfg.cycles.indices.contains(cycleIdx),
                      cfg.cycles[cycleIdx].states.indices.contains(stateIdx) else { return }
                cfg.cycles[cycleIdx].states[stateIdx].easing = v
            }}
        )
    }
}

// MARK: - IntStepperField

private struct IntStepperField: View {
    @Binding var value: Int
    let min: Int
    let max: Int

    var body: some View {
        HStack(spacing: 4) {
            TextField("", value: $value, formatter: {
                let f = NumberFormatter()
                f.numberStyle = .decimal
                f.minimum = NSNumber(value: min)
                f.maximum = NSNumber(value: max)
                return f
            }())
            .textFieldStyle(.squareBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 48)
            Stepper("", value: $value, in: min...max)
                .labelsHidden()
                .scaleEffect(0.85)
        }
    }
}
