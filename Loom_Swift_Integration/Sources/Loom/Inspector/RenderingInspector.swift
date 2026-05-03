import AppKit
import SwiftUI
import LoomEngine

struct RenderingInspector: View {

    @EnvironmentObject private var controller: AppController

    // Collapse state — primary sections default open, secondary default closed
    @State private var renderersCollapsed    = false
    @State private var rendererCollapsed     = false
    @State private var brushCollapsed        = false
    @State private var meanderCollapsed      = true
    @State private var stampCollapsed        = false
    @State private var opacityAnimCollapsed  = true
    @State private var fillChangeCollapsed   = true
    @State private var strokeChangeCollapsed = true
    @State private var widthChangeCollapsed  = true

    var body: some View {
        let setIdx = controller.selectedRendererIndex ?? 0
        guard let set = controller.projectConfig?.renderingConfig.library.rendererSets[safe: setIdx]
        else { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: 0) {
            setHeader(set: set, setIdx: setIdx)
            renderersList(set: set, setIdx: setIdx)
            if let itemIdx = controller.selectedRendererItemIndex,
               let renderer = set.renderers[safe: itemIdx] {
                rendererEditor(renderer: renderer, setIdx: setIdx, itemIdx: itemIdx)
                switch renderer.mode {
                case .brushed:
                    brushConfigSection(setIdx: setIdx, itemIdx: itemIdx,
                                       cfg: renderer.brushConfig ?? BrushConfig())
                case .stenciled, .stamped:
                    stencilConfigSection(setIdx: setIdx, itemIdx: itemIdx,
                                         cfg: renderer.stencilConfig ?? StencilConfig())
                default:
                    EmptyView()
                }
                changesSection(renderer: renderer, setIdx: setIdx, itemIdx: itemIdx)
            }
        })
    }

    // MARK: - Set header

    private func setHeader(set: RendererSet, setIdx: Int) -> some View {
        let mode = set.playbackConfig.mode
        return InspectorSection("Set") {
            InspectorField("Name") {
                TextField("", text: bindSet(setIdx, \.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Playback") {
                Picker("", selection: bindSet(setIdx, \.playbackConfig.mode)) {
                    ForEach(PlaybackMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)
            }
            if mode == .random {
                InspectorField("Preferred") {
                    TextField("", text: bindSet(setIdx, \.playbackConfig.preferredRenderer))
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 110)
                }
                InspectorField("Pref. prob.") {
                    FloatEntryField(value: bindSet(setIdx, \.playbackConfig.preferredProbability),
                                    width: 55, fractionDigits: 1)
                    Text("%").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            InspectorField("Mod. params") {
                Toggle("", isOn: bindSet(setIdx, \.playbackConfig.modifyInternalParameters))
                    .labelsHidden()
            }
            InspectorRow(label: "Renderers", value: "\(set.renderers.count)")
        }
    }

    // MARK: - Renderers mini-list

    private func renderersList(set: RendererSet, setIdx: Int) -> some View {
        InspectorSection("Renderers", isCollapsed: $renderersCollapsed) {
            InspectorPickList(
                items: set.renderers,
                labelFor: { $0.name.isEmpty ? "(unnamed)" : $0.name },
                selection: Binding(
                    get: { controller.selectedRendererItemIndex },
                    set: { controller.selectedRendererItemIndex = $0 }
                )
            )
        }
        .onChange(of: controller.selectedRendererIndex) { _, _ in
            controller.selectedRendererItemIndex = nil
        }
    }

    // MARK: - Renderer editor

    @ViewBuilder
    private func rendererEditor(renderer: Renderer, setIdx: Int, itemIdx: Int) -> some View {
        InspectorSection("Renderer", isCollapsed: $rendererCollapsed) {
            InspectorField("Name") {
                TextField("", text: bindR(setIdx, itemIdx, \.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Mode") {
                Picker("", selection: bindR(setIdx, itemIdx, \.mode)) {
                    ForEach(RendererMode.allCases.filter { $0 != .stenciled }, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)
                .onChange(of: renderer.mode) { _, newMode in
                    initModeConfig(newMode, setIdx: setIdx, itemIdx: itemIdx)
                }
            }
            LoomColorField(label: "Stroke color",
                           color: bindR(setIdx, itemIdx, \.strokeColor))
            LoomColorField(label: "Fill color",
                           color: bindR(setIdx, itemIdx, \.fillColor))
            InspectorField("Stroke w") {
                FloatEntryField(value: bindR(setIdx, itemIdx, \.strokeWidth), width: 60, fractionDigits: 2)
            }
            InspectorField("Point size") {
                FloatEntryField(value: bindR(setIdx, itemIdx, \.pointSize), width: 60, fractionDigits: 2)
            }
            InspectorField("Hold") {
                TextField("", value: bindR(setIdx, itemIdx, \.holdLength), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
                Text("frames").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Brush config section

    @ViewBuilder
    private func brushConfigSection(setIdx: Int, itemIdx: Int, cfg: BrushConfig) -> some View {
        InspectorSection("Brush", isCollapsed: $brushCollapsed) {
            BrushLibraryView(
                dir: "brushes",
                names: bindBrushKP(setIdx, itemIdx, \.brushNames, fallback: []),
                enabled: bindBrushKP(setIdx, itemIdx, \.brushEnabled, fallback: [])
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            InspectorField("Draw mode") {
                Picker("", selection: bindBrushKP(setIdx, itemIdx, \.drawMode,
                                                  fallback: cfg.drawMode)) {
                    Text("Full Path").tag(BrushDrawMode.fullPath)
                    Text("Progressive").tag(BrushDrawMode.progressive)
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            InspectorField("Spacing") {
                FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.stampSpacing,
                                                   fallback: cfg.stampSpacing),
                                width: 55, fractionDigits: 1)
            }
            InspectorField("Follow tang.") {
                Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.followTangent,
                                             fallback: cfg.followTangent))
                    .labelsHidden()
            }
            rangeField2("Perp. jitter",
                        v1: bindBrushKP(setIdx, itemIdx, \.perpendicularJitterMin,
                                        fallback: cfg.perpendicularJitterMin),
                        v2: bindBrushKP(setIdx, itemIdx, \.perpendicularJitterMax,
                                        fallback: cfg.perpendicularJitterMax))
            rangeField2("Scale",
                        v1: bindBrushKP(setIdx, itemIdx, \.scaleMin, fallback: cfg.scaleMin),
                        v2: bindBrushKP(setIdx, itemIdx, \.scaleMax, fallback: cfg.scaleMax))
            rangeField2("Opacity",
                        v1: bindBrushKP(setIdx, itemIdx, \.opacityMin, fallback: cfg.opacityMin),
                        v2: bindBrushKP(setIdx, itemIdx, \.opacityMax, fallback: cfg.opacityMax))
            InspectorField("Stamps/frame") {
                TextField("", value: bindBrushKP(setIdx, itemIdx, \.stampsPerFrame,
                                                 fallback: cfg.stampsPerFrame), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            InspectorField("Agents") {
                TextField("", value: bindBrushKP(setIdx, itemIdx, \.agentCount,
                                                 fallback: cfg.agentCount), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            InspectorField("Post done") {
                Picker("", selection: bindBrushKP(setIdx, itemIdx, \.postCompletionMode,
                                                  fallback: cfg.postCompletionMode)) {
                    Text("Hold").tag(PostCompletionMode.hold)
                    Text("Loop").tag(PostCompletionMode.loop)
                    Text("Ping-Pong").tag(PostCompletionMode.pingPong)
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            }
            InspectorField("Blur radius") {
                TextField("", value: bindBrushKP(setIdx, itemIdx, \.blurRadius,
                                                 fallback: cfg.blurRadius), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            InspectorField("Pressure→size") {
                FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.pressureSizeInfluence,
                                                   fallback: cfg.pressureSizeInfluence),
                                width: 55, fractionDigits: 2)
            }
            InspectorField("Pressure→α") {
                FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.pressureAlphaInfluence,
                                                   fallback: cfg.pressureAlphaInfluence),
                                width: 55, fractionDigits: 2)
            }
            if let brushDir = controller.projectURL?.appendingPathComponent("brushes") {
                revealButton(label: "Reveal brushes folder", url: brushDir)
            }
        }
        InspectorSection("Meander", isCollapsed: $meanderCollapsed) {
            InspectorField("Enabled") {
                Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.meander.enabled,
                                             fallback: cfg.meander.enabled))
                    .labelsHidden()
            }
            if cfg.meander.enabled {
                InspectorField("Amplitude") {
                    FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.meander.amplitude,
                                                       fallback: cfg.meander.amplitude),
                                    width: 60, fractionDigits: 1)
                }
                InspectorField("Frequency") {
                    FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.meander.frequency,
                                                       fallback: cfg.meander.frequency),
                                    width: 60, fractionDigits: 4)
                }
                InspectorField("Samples") {
                    TextField("", value: bindBrushKP(setIdx, itemIdx, \.meander.samples,
                                                     fallback: cfg.meander.samples), format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50)
                }
                InspectorField("Seed") {
                    TextField("", value: bindBrushKP(setIdx, itemIdx, \.meander.seed,
                                                     fallback: cfg.meander.seed), format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50)
                    Text("0=auto").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                InspectorField("Animated") {
                    Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.meander.animated,
                                                 fallback: cfg.meander.animated))
                        .labelsHidden()
                }
                if cfg.meander.animated {
                    InspectorField("Anim speed") {
                        FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.meander.animSpeed,
                                                           fallback: cfg.meander.animSpeed),
                                        width: 60, fractionDigits: 4)
                    }
                }
                InspectorField("Scale path") {
                    Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.meander.scaleAlongPath,
                                                 fallback: cfg.meander.scaleAlongPath))
                        .labelsHidden()
                }
                if cfg.meander.scaleAlongPath {
                    InspectorField("Path freq.") {
                        FloatEntryField(
                            value: bindBrushKP(setIdx, itemIdx, \.meander.scaleAlongPathFrequency,
                                               fallback: cfg.meander.scaleAlongPathFrequency),
                            width: 60, fractionDigits: 4)
                    }
                    InspectorField("Path range") {
                        FloatEntryField(
                            value: bindBrushKP(setIdx, itemIdx, \.meander.scaleAlongPathRange,
                                               fallback: cfg.meander.scaleAlongPathRange),
                            width: 60, fractionDigits: 3)
                    }
                }
            }
        }
    }

    // MARK: - Stencil config section

    @ViewBuilder
    private func stencilConfigSection(setIdx: Int, itemIdx: Int, cfg: StencilConfig) -> some View {
        InspectorSection("Stamp", isCollapsed: $stampCollapsed) {
            BrushLibraryView(
                dir: "stamps",
                names: bindStencilKP(setIdx, itemIdx, \.stampNames, fallback: []),
                enabled: bindStencilKP(setIdx, itemIdx, \.stampEnabled, fallback: [])
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            InspectorField("Draw mode") {
                Picker("", selection: bindStencilKP(setIdx, itemIdx, \.drawMode,
                                                    fallback: cfg.drawMode)) {
                    Text("Full Path").tag(BrushDrawMode.fullPath)
                    Text("Progressive").tag(BrushDrawMode.progressive)
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            InspectorField("Spacing") {
                FloatEntryField(value: bindStencilKP(setIdx, itemIdx, \.stampSpacing,
                                                     fallback: cfg.stampSpacing),
                                width: 55, fractionDigits: 1)
            }
            InspectorField("Follow tang.") {
                Toggle("", isOn: bindStencilKP(setIdx, itemIdx, \.followTangent,
                                               fallback: cfg.followTangent))
                    .labelsHidden()
            }
            rangeField2("Perp. jitter",
                        v1: bindStencilKP(setIdx, itemIdx, \.perpendicularJitterMin,
                                          fallback: cfg.perpendicularJitterMin),
                        v2: bindStencilKP(setIdx, itemIdx, \.perpendicularJitterMax,
                                          fallback: cfg.perpendicularJitterMax))
            rangeField2("Scale",
                        v1: bindStencilKP(setIdx, itemIdx, \.scaleMin, fallback: cfg.scaleMin),
                        v2: bindStencilKP(setIdx, itemIdx, \.scaleMax, fallback: cfg.scaleMax))
            InspectorField("Stamps/frame") {
                TextField("", value: bindStencilKP(setIdx, itemIdx, \.stampsPerFrame,
                                                   fallback: cfg.stampsPerFrame), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            InspectorField("Agents") {
                TextField("", value: bindStencilKP(setIdx, itemIdx, \.agentCount,
                                                   fallback: cfg.agentCount), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            InspectorField("Post done") {
                Picker("", selection: bindStencilKP(setIdx, itemIdx, \.postCompletionMode,
                                                    fallback: cfg.postCompletionMode)) {
                    Text("Hold").tag(PostCompletionMode.hold)
                    Text("Loop").tag(PostCompletionMode.loop)
                    Text("Ping-Pong").tag(PostCompletionMode.pingPong)
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            }
            if let stampDir = controller.projectURL?.appendingPathComponent("stamps") {
                revealButton(label: "Reveal stamps folder", url: stampDir)
            }
        }
        InspectorSection("Opacity Animation", isCollapsed: $opacityAnimCollapsed) {
            let oc = cfg.opacityChange
            InspectorField("Enabled") {
                Toggle("", isOn: bindStencilKP(setIdx, itemIdx, \.opacityChange.enabled,
                                               fallback: oc.enabled))
                    .labelsHidden()
            }
            if oc.enabled {
                sizeChangeFields(
                    kind:      bindStencilKP(setIdx, itemIdx, \.opacityChange.kind,     fallback: oc.kind),
                    motion:    bindStencilKP(setIdx, itemIdx, \.opacityChange.motion,   fallback: oc.motion),
                    cycle:     bindStencilKP(setIdx, itemIdx, \.opacityChange.cycle,    fallback: oc.cycle),
                    scale:     bindStencilKP(setIdx, itemIdx, \.opacityChange.scale,    fallback: oc.scale),
                    pauseMax:  bindStencilKP(setIdx, itemIdx, \.opacityChange.pauseMax, fallback: oc.pauseMax),
                    palette:   bindStencilOpacityPalette(setIdx, itemIdx)
                )
            }
        }
    }

    // MARK: - Renderer changes section

    @ViewBuilder
    private func changesSection(renderer: Renderer, setIdx: Int, itemIdx: Int) -> some View {
        let ch = renderer.changes

        // Fill color change
        InspectorSection("Fill Color Change", isCollapsed: $fillChangeCollapsed) {
            let enabled = ch.fillColor?.enabled ?? false
            InspectorField("Enabled") {
                Toggle("", isOn: bindFillChange(setIdx, itemIdx, \.enabled, fallback: false))
                    .labelsHidden()
            }
            if enabled, let fc = ch.fillColor {
                colorChangeFields(
                    kind:     bindFillChange(setIdx, itemIdx, \.kind,     fallback: fc.kind),
                    motion:   bindFillChange(setIdx, itemIdx, \.motion,   fallback: fc.motion),
                    cycle:    bindFillChange(setIdx, itemIdx, \.cycle,    fallback: fc.cycle),
                    scale:    bindFillChange(setIdx, itemIdx, \.scale,    fallback: fc.scale),
                    pauseMax: bindFillChange(setIdx, itemIdx, \.pauseMax, fallback: fc.pauseMax)
                )
                ColorPaletteEditor(palette: bindFillColorPalette(setIdx, itemIdx))
            }
        }

        // Stroke color change
        InspectorSection("Stroke Color Change", isCollapsed: $strokeChangeCollapsed) {
            let enabled = ch.strokeColor?.enabled ?? false
            InspectorField("Enabled") {
                Toggle("", isOn: bindStrokeChange(setIdx, itemIdx, \.enabled, fallback: false))
                    .labelsHidden()
            }
            if enabled, let sc = ch.strokeColor {
                colorChangeFields(
                    kind:     bindStrokeChange(setIdx, itemIdx, \.kind,     fallback: sc.kind),
                    motion:   bindStrokeChange(setIdx, itemIdx, \.motion,   fallback: sc.motion),
                    cycle:    bindStrokeChange(setIdx, itemIdx, \.cycle,    fallback: sc.cycle),
                    scale:    bindStrokeChange(setIdx, itemIdx, \.scale,    fallback: sc.scale),
                    pauseMax: bindStrokeChange(setIdx, itemIdx, \.pauseMax, fallback: sc.pauseMax)
                )
                ColorPaletteEditor(palette: bindStrokeColorPalette(setIdx, itemIdx))
            }
        }

        // Stroke width change
        InspectorSection("Stroke Width Change", isCollapsed: $widthChangeCollapsed) {
            let enabled = ch.strokeWidth?.enabled ?? false
            InspectorField("Enabled") {
                Toggle("", isOn: bindWidthChange(setIdx, itemIdx, \.enabled, fallback: false))
                    .labelsHidden()
            }
            if enabled, let sw = ch.strokeWidth {
                sizeChangeFields(
                    kind:     bindWidthChange(setIdx, itemIdx, \.kind,     fallback: sw.kind),
                    motion:   bindWidthChange(setIdx, itemIdx, \.motion,   fallback: sw.motion),
                    cycle:    bindWidthChange(setIdx, itemIdx, \.cycle,    fallback: sw.cycle),
                    scale:    bindWidthChange(setIdx, itemIdx, \.scale,    fallback: sw.scale),
                    pauseMax: bindWidthChange(setIdx, itemIdx, \.pauseMax, fallback: sw.pauseMax),
                    palette:  bindWidthPalette(setIdx, itemIdx)
                )
            }
        }
    }

    // MARK: - Shared change field helpers

    @ViewBuilder
    private func colorChangeFields(kind: Binding<ChangeKind>, motion: Binding<ChangeMotion>,
                                    cycle: Binding<ChangeCycle>, scale: Binding<ChangeScale>,
                                    pauseMax: Binding<Int>) -> some View {
        InspectorField("Kind") {
            Picker("", selection: kind) {
                Text("Sequential").tag(ChangeKind.sequential)
                Text("Random").tag(ChangeKind.random)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        InspectorField("Motion") {
            Picker("", selection: motion) {
                Text("Up").tag(ChangeMotion.up)
                Text("Down").tag(ChangeMotion.down)
                Text("Ping-Pong").tag(ChangeMotion.pingPong)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        InspectorField("Cycle") {
            Picker("", selection: cycle) {
                Text("Constant").tag(ChangeCycle.constant)
                Text("Pausing").tag(ChangeCycle.pausing)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        InspectorField("Scale") {
            Picker("", selection: scale) {
                Text("Poly").tag(ChangeScale.poly)
                Text("Sprite").tag(ChangeScale.sprite)
                Text("Global").tag(ChangeScale.global)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        if cycle.wrappedValue == .pausing {
            InspectorField("Pause max") {
                TextField("", value: pauseMax, format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
        }
    }

    @ViewBuilder
    private func sizeChangeFields(kind: Binding<ChangeKind>, motion: Binding<ChangeMotion>,
                                   cycle: Binding<ChangeCycle>, scale: Binding<ChangeScale>,
                                   pauseMax: Binding<Int>, palette: Binding<[Double]>) -> some View {
        InspectorField("Kind") {
            Picker("", selection: kind) {
                Text("Sequential").tag(ChangeKind.sequential)
                Text("Random").tag(ChangeKind.random)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        InspectorField("Motion") {
            Picker("", selection: motion) {
                Text("Up").tag(ChangeMotion.up)
                Text("Down").tag(ChangeMotion.down)
                Text("Ping-Pong").tag(ChangeMotion.pingPong)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        InspectorField("Cycle") {
            Picker("", selection: cycle) {
                Text("Constant").tag(ChangeCycle.constant)
                Text("Pausing").tag(ChangeCycle.pausing)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        InspectorField("Scale") {
            Picker("", selection: scale) {
                Text("Poly").tag(ChangeScale.poly)
                Text("Sprite").tag(ChangeScale.sprite)
                Text("Global").tag(ChangeScale.global)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        if cycle.wrappedValue == .pausing {
            InspectorField("Pause max") {
                TextField("", value: pauseMax, format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
        }
        SizePaletteEditor(palette: palette)
    }

    // MARK: - Shared field helpers

    private func rangeField2(_ label: String,
                              v1: Binding<Double>, v2: Binding<Double>) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                FloatEntryField(value: v1, width: 54, fractionDigits: 2, fontSize: 11)
                Text("–").font(.system(size: 10)).foregroundStyle(.tertiary)
                FloatEntryField(value: v2, width: 54, fractionDigits: 2, fontSize: 11)
            }
        }
    }

    private func revealButton(label: String, url: URL) -> some View {
        Button(label) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mode config initialisation

    private func initModeConfig(_ mode: RendererMode, setIdx: Int, itemIdx: Int) {
        controller.updateProjectConfig { cfg in
            guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                  itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
            else { return }
            var r = cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
            if mode == .brushed && r.brushConfig == nil   { r.brushConfig   = BrushConfig()   }
            if (mode == .stenciled || mode == .stamped) && r.stencilConfig == nil {
                r.stencilConfig = StencilConfig()
            }
            cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx] = r
        }
    }

    // MARK: - Binding helpers: set

    private func bindSet<T>(_ setIdx: Int,
                             _ kp: WritableKeyPath<RendererSet, T>) -> Binding<T> {
        let ctl = controller
        let fallback = RendererSet(name: "")[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count else { return }
                    cfg.renderingConfig.library.rendererSets[setIdx][keyPath: kp] = v
                }
            }
        )
    }

    // MARK: - Binding helpers: renderer

    private func bindR<T>(_ setIdx: Int, _ itemIdx: Int,
                           _ kp: WritableKeyPath<Renderer, T>) -> Binding<T> {
        let ctl = controller
        let fallback = Renderer()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx][keyPath: kp] = v
                }
            }
        )
    }

    // MARK: - Binding helpers: brush config

    private func bindBrushKP<T>(_ setIdx: Int, _ itemIdx: Int,
                                 _ kp: WritableKeyPath<BrushConfig, T>,
                                 fallback: T) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .brushConfig?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].brushConfig == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].brushConfig = BrushConfig()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].brushConfig![keyPath: kp] = v
                }
            }
        )
    }

    // MARK: - Binding helpers: stencil config

    private func bindStencilKP<T>(_ setIdx: Int, _ itemIdx: Int,
                                   _ kp: WritableKeyPath<StencilConfig, T>,
                                   fallback: T) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .stencilConfig?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].stencilConfig == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].stencilConfig = StencilConfig()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].stencilConfig![keyPath: kp] = v
                }
            }
        )
    }

    private func bindStencilOpacityPalette(_ setIdx: Int, _ itemIdx: Int) -> Binding<[Double]> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .stencilConfig?.opacityChange.sizePalette ?? []
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].stencilConfig == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].stencilConfig = StencilConfig()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].stencilConfig!.opacityChange.sizePalette = v
                }
            }
        )
    }

    // MARK: - Binding helpers: RendererChanges — fill color

    private func bindFillChange<T>(_ setIdx: Int, _ itemIdx: Int,
                                    _ kp: WritableKeyPath<FillColorChange, T>,
                                    fallback: T) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .changes.fillColor?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.fillColor == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].changes.fillColor = FillColorChange()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.fillColor![keyPath: kp] = v
                }
            }
        )
    }

    private func bindFillColorPalette(_ setIdx: Int, _ itemIdx: Int) -> Binding<[LoomColor]> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .changes.fillColor?.palette ?? []
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.fillColor == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].changes.fillColor = FillColorChange()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.fillColor!.palette = v
                }
            }
        )
    }

    // MARK: - Binding helpers: RendererChanges — stroke color

    private func bindStrokeChange<T>(_ setIdx: Int, _ itemIdx: Int,
                                      _ kp: WritableKeyPath<StrokeColorChange, T>,
                                      fallback: T) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .changes.strokeColor?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.strokeColor == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].changes.strokeColor = StrokeColorChange()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.strokeColor![keyPath: kp] = v
                }
            }
        )
    }

    private func bindStrokeColorPalette(_ setIdx: Int, _ itemIdx: Int) -> Binding<[LoomColor]> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .changes.strokeColor?.palette ?? []
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.strokeColor == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].changes.strokeColor = StrokeColorChange()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.strokeColor!.palette = v
                }
            }
        )
    }

    // MARK: - Binding helpers: RendererChanges — stroke width

    private func bindWidthChange<T>(_ setIdx: Int, _ itemIdx: Int,
                                     _ kp: WritableKeyPath<StrokeWidthChange, T>,
                                     fallback: T) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .changes.strokeWidth?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.strokeWidth == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].changes.strokeWidth = StrokeWidthChange()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.strokeWidth![keyPath: kp] = v
                }
            }
        )
    }

    private func bindWidthPalette(_ setIdx: Int, _ itemIdx: Int) -> Binding<[Double]> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .changes.strokeWidth?.sizePalette ?? []
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.strokeWidth == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].changes.strokeWidth = StrokeWidthChange()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].changes.strokeWidth!.sizePalette = v
                }
            }
        )
    }
}

// MARK: - Display names

private extension RendererMode {
    var displayName: String {
        switch self {
        case .points:        return "Points"
        case .stroked:       return "Stroked"
        case .filled:        return "Filled"
        case .filledStroked: return "Filled+Stroked"
        case .brushed:       return "Brushed"
        case .stenciled:     return "Stenciled"
        case .stamped:       return "Stamped"
        }
    }
}

extension PlaybackMode: @retroactive CaseIterable {
    public static var allCases: [PlaybackMode] { [.static, .sequential, .random, .all] }
    var displayName: String {
        switch self {
        case .static:     return "Static"
        case .sequential: return "Sequential"
        case .random:     return "Random"
        case .all:        return "All"
        }
    }
}
