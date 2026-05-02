import SwiftUI
import LoomEngine

struct RenderingInspector: View {

    @EnvironmentObject private var controller: AppController

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
            }
        })
    }

    // MARK: - Set header

    private func setHeader(set: RendererSet, setIdx: Int) -> some View {
        InspectorSection("Set") {
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
            InspectorRow(label: "Renderers", value: "\(set.renderers.count)")
        }
    }

    // MARK: - Renderers mini-list

    private func renderersList(set: RendererSet, setIdx: Int) -> some View {
        InspectorSection("Renderers") {
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
        InspectorSection("Renderer") {
            InspectorField("Name") {
                TextField("", text: bindR(setIdx, itemIdx, \.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            InspectorField("Mode") {
                Picker("", selection: bindR(setIdx, itemIdx, \.mode)) {
                    ForEach(RendererMode.allCases, id: \.self) { m in
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
                TextField("", value: bindR(setIdx, itemIdx, \.strokeWidth),
                          format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 60)
            }
            InspectorField("Point size") {
                TextField("", value: bindR(setIdx, itemIdx, \.pointSize),
                          format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 60)
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
        InspectorSection("Brush") {
            InspectorField("Brushes") {
                TextField("", text: bindBrush(setIdx, itemIdx,
                    get: { $0.brushNames.joined(separator: ", ") },
                    set: { cfg, v in cfg.brushNames = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
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
                TextField("", value: bindBrushKP(setIdx, itemIdx, \.stampSpacing,
                                                 fallback: cfg.stampSpacing),
                          format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 55)
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
        }
        InspectorSection("Meander") {
            InspectorField("Enabled") {
                Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.meander.enabled,
                                             fallback: cfg.meander.enabled))
                    .labelsHidden()
            }
            if cfg.meander.enabled {
                InspectorField("Amplitude") {
                    TextField("", value: bindBrushKP(setIdx, itemIdx, \.meander.amplitude,
                                                     fallback: cfg.meander.amplitude),
                              format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 60)
                }
                InspectorField("Frequency") {
                    TextField("", value: bindBrushKP(setIdx, itemIdx, \.meander.frequency,
                                                     fallback: cfg.meander.frequency),
                              format: .number.precision(.fractionLength(4)))
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 60)
                }
                InspectorField("Animated") {
                    Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.meander.animated,
                                                 fallback: cfg.meander.animated))
                        .labelsHidden()
                }
                if cfg.meander.animated {
                    InspectorField("Anim speed") {
                        TextField("", value: bindBrushKP(setIdx, itemIdx, \.meander.animSpeed,
                                                         fallback: cfg.meander.animSpeed),
                                  format: .number.precision(.fractionLength(4)))
                            .textFieldStyle(.squareBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 60)
                    }
                }
            }
        }
    }

    // MARK: - Stencil config section

    @ViewBuilder
    private func stencilConfigSection(setIdx: Int, itemIdx: Int, cfg: StencilConfig) -> some View {
        InspectorSection("Stamp") {
            InspectorField("Stamps") {
                TextField("", text: bindStencil(setIdx, itemIdx,
                    get: { $0.stampNames.joined(separator: ", ") },
                    set: { cfg, v in cfg.stampNames = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
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
                TextField("", value: bindStencilKP(setIdx, itemIdx, \.stampSpacing,
                                                   fallback: cfg.stampSpacing),
                          format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 55)
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
        }
    }

    // MARK: - Shared field helper

    private func rangeField2(_ label: String,
                              v1: Binding<Double>, v2: Binding<Double>) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                TextField("", value: v1, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 54)
                Text("–").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("", value: v2, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 54)
            }
        }
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

    // MARK: - Binding helpers: set and renderer

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
                    if cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].brushConfig == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].brushConfig = BrushConfig()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].brushConfig![keyPath: kp] = v
                }
            }
        )
    }

    private func bindBrush(_ setIdx: Int, _ itemIdx: Int,
                            get: @escaping (BrushConfig) -> String,
                            set setter: @escaping (inout BrushConfig, String) -> Void) -> Binding<String> {
        let ctl = controller
        return Binding(
            get: {
                guard let cfg = ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?.brushConfig
                else { return "" }
                return get(cfg)
            },
            set: { v in
                ctl.updateProjectConfig { projCfg in
                    guard setIdx < projCfg.renderingConfig.library.rendererSets.count,
                          itemIdx < projCfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    var brush = projCfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].brushConfig ?? BrushConfig()
                    setter(&brush, v)
                    projCfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].brushConfig = brush
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
                    if cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].stencilConfig == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].stencilConfig = StencilConfig()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].stencilConfig![keyPath: kp] = v
                }
            }
        )
    }

    private func bindStencil(_ setIdx: Int, _ itemIdx: Int,
                              get: @escaping (StencilConfig) -> String,
                              set setter: @escaping (inout StencilConfig, String) -> Void) -> Binding<String> {
        let ctl = controller
        return Binding(
            get: {
                guard let cfg = ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?.stencilConfig
                else { return "" }
                return get(cfg)
            },
            set: { v in
                ctl.updateProjectConfig { projCfg in
                    guard setIdx < projCfg.renderingConfig.library.rendererSets.count,
                          itemIdx < projCfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    var stencil = projCfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].stencilConfig ?? StencilConfig()
                    setter(&stencil, v)
                    projCfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].stencilConfig = stencil
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
