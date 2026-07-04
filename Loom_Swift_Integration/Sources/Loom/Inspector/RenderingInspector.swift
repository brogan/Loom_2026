import AppKit
import SwiftUI
import LoomEngine

struct RenderingInspector: View {

    @EnvironmentObject private var controller: AppController

    @State private var hiddenRenderers: Set<String> = []

    // Collapse state — primary sections default open, secondary default closed
    @State private var renderersCollapsed    = false
    @State private var rendererCollapsed     = false
    @State private var fillColorDriverCollapsed = true
    @State private var strokeColorDriverCollapsed = true
    @State private var strokeWidthDriverCollapsed = true
    @State private var opacityDriverCollapsed = true
    @State private var blurDriverCollapsed   = true
    @State private var brushCollapsed        = false
    @State private var meanderCollapsed      = true
    @State private var stampCollapsed        = false
    @State private var gradientCollapsed     = false
    @State private var gradientBCollapsed    = true
    @State private var gradientBlendDriverCollapsed = true
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
                sectionDivider
                rendererDriversSection(renderer: renderer, setIdx: setIdx, itemIdx: itemIdx)
                switch renderer.mode {
                case .brushed:
                    brushConfigSection(setIdx: setIdx, itemIdx: itemIdx,
                                       cfg: renderer.brushConfig ?? BrushConfig())
                case .stenciled, .stamped:
                    stencilConfigSection(setIdx: setIdx, itemIdx: itemIdx,
                                         cfg: renderer.stencilConfig ?? StencilConfig())
                case .gradientFilled, .gradientFilledStroked:
                    gradientConfigSection(setIdx: setIdx, itemIdx: itemIdx,
                                          cfg: renderer.gradientConfig ?? GradientConfig())
                    gradientBConfigSection(setIdx: setIdx, itemIdx: itemIdx,
                                           cfg: renderer.gradientConfigB)
                default:
                    EmptyView()
                }
                sectionDivider
                changesSection(renderer: renderer, setIdx: setIdx, itemIdx: itemIdx)
            }
        })
    }

    // MARK: - Section divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1.5)
            .padding(.vertical, 3)
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
            .loomHelp("Name for this renderer set — shown in the set list and in sprite assignment dropdowns.")
            InspectorField("Playback") {
                Picker("", selection: bindSet(setIdx, \.playbackConfig.mode)) {
                    ForEach(PlaybackMode.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)
            }
            .loomHelp("How the set cycles through renderers — Static (always first), Sequential (in order by Hold length), All (draw simultaneously), Random (pick each frame).")
            if mode == .random {
                InspectorField("Preferred") {
                    TextField("", text: bindSet(setIdx, \.playbackConfig.preferredRenderer))
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 110)
                }
                .loomHelp("Name of the renderer to favour when Playback is Random. Leave blank to disable preference.")
                InspectorField("Pref. prob.") {
                    FloatEntryField(value: bindSet(setIdx, \.playbackConfig.preferredProbability),
                                    width: 55, fractionDigits: 1)
                    Text("%").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .loomHelp("Chance (0–100%) that the preferred renderer is chosen instead of a uniformly random one.")
            }
            InspectorField("Mod. params") {
                Toggle("", isOn: bindSet(setIdx, \.playbackConfig.modifyInternalParameters))
                    .labelsHidden()
            }
            .loomHelp("When on, internal animation state (palette index, opacity step) advances each virtual frame. Turn off to freeze procedural variation.")
            InspectorRow(label: "Renderers", value: "\(set.renderers.count)")
        }
    }

    // MARK: - Renderers mini-list

    private func rendererKey(_ setName: String, _ rendererName: String) -> String { "\(setName)\t\(rendererName)" }

    private func renderersList(set: RendererSet, setIdx: Int) -> some View {
        let hiddenCount  = set.renderers.filter { hiddenRenderers.contains(rendererKey(set.name, $0.name)) }.count
        let hidableCount = set.renderers.filter { !$0.enabled && !hiddenRenderers.contains(rendererKey(set.name, $0.name)) }.count

        return InspectorSection("Renderers", isCollapsed: $renderersCollapsed, trailing: {
            if hiddenCount > 0 {
                Button {
                    for r in set.renderers { hiddenRenderers.remove(rendererKey(set.name, r.name)) }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "eye.slash").font(.system(size: 9))
                        Text("\(hiddenCount)").font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .frame(minWidth: 22, minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Restore \(hiddenCount) hidden renderer\(hiddenCount == 1 ? "" : "s")")
            } else if hidableCount > 0 {
                Button {
                    for r in set.renderers where !r.enabled {
                        hiddenRenderers.insert(rendererKey(set.name, r.name))
                    }
                } label: {
                    Image(systemName: "eye").font(.system(size: 9)).foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide \(hidableCount) disabled renderer\(hidableCount == 1 ? "" : "s")")
            }
        }) {
            ForEach(Array(set.renderers.enumerated()), id: \.offset) { idx, renderer in
                if !hiddenRenderers.contains(rendererKey(set.name, renderer.name)) {
                    let selected = controller.selectedRendererItemIndex == idx
                    HStack(spacing: 6) {
                        Text("\(idx)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 18, alignment: .trailing)
                        Text(renderer.name.isEmpty ? "(unnamed)" : renderer.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(selected ? Color.accentColor.opacity(0.15) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { controller.selectedRendererItemIndex = idx }
                }
            }
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
            .loomHelp("Name for this renderer — shown in the timeline lane and renderer list.")
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
            .loomHelp("Drawing mode — Stroked (outline), Filled (solid), Filled+Stroked (both), Points (dot cloud), Brushed (stamps along path), Stamped (images at point positions).")
            LoomColorField(label: "Stroke color",
                           color: bindR(setIdx, itemIdx, \.strokeColor))
            .loomHelp("Colour and opacity used for stroked outlines and point markers.")
            LoomColorField(label: "Fill color",
                           color: bindR(setIdx, itemIdx, \.fillColor))
            .loomHelp("Colour and opacity used when the mode includes a filled area.")
            InspectorField("Stroke w") {
                FloatEntryField(value: bindR(setIdx, itemIdx, \.strokeWidth), width: 60, fractionDigits: 2)
            }
            .loomHelp("Stroke line width in pixels at 1× quality. Scaled proportionally at higher quality multiples.")
            InspectorField("Point size") {
                FloatEntryField(value: bindR(setIdx, itemIdx, \.pointSize), width: 60, fractionDigits: 2)
            }
            .loomHelp("Diameter of drawn points in Points mode, in pixels at 1× quality.")
            InspectorField("Hold") {
                TextField("", value: bindR(setIdx, itemIdx, \.holdLength), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
                Text("frames").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .loomHelp("Number of virtual frames this renderer is held before the set advances to the next renderer in Sequential playback mode.")
            InspectorField("Blur radius") {
                FloatEntryField(value: bindR(setIdx, itemIdx, \.blurRadius), width: 55, fractionDigits: 1)
                Text("px").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Gaussian blur radius applied to this renderer's output in logical pixels. Scaled by the quality multiplier. 0 = off. Animate with the Blur Driver below.")
        }
    }

    // MARK: - Renderer drivers

    @ViewBuilder
    private func rendererDriversSection(renderer: Renderer, setIdx: Int, itemIdx: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            rendererBatchEyeButton(for: renderer)
            ColorDriverEditor(
                label: "Fill Color Driver",
                driver: bindRendererFillColorDriver(setIdx, itemIdx, fallback: renderer.fillColor),
                isCollapsed: $fillColorDriverCollapsed,
                isHighlighted: selectedRendererLane(setIdx: setIdx, itemIdx: itemIdx) == .fillColor
            )
            ColorDriverEditor(
                label: "Stroke Color Driver",
                driver: bindRendererStrokeColorDriver(setIdx, itemIdx, fallback: renderer.strokeColor),
                isCollapsed: $strokeColorDriverCollapsed,
                isHighlighted: selectedRendererLane(setIdx: setIdx, itemIdx: itemIdx) == .strokeColor
            )
            DoubleDriverEditor(
                label: "Stroke Width Driver",
                driver: bindRendererStrokeWidthDriver(setIdx, itemIdx, fallback: renderer.strokeWidth),
                isCollapsed: $strokeWidthDriverCollapsed,
                isHighlighted: selectedRendererLane(setIdx: setIdx, itemIdx: itemIdx) == .strokeWidth
            )
            DoubleDriverEditor(
                label: "Opacity Driver",
                driver: bindRendererOpacityDriver(setIdx, itemIdx),
                isCollapsed: $opacityDriverCollapsed,
                isHighlighted: selectedRendererLane(setIdx: setIdx, itemIdx: itemIdx) == .opacity
            )
            DoubleDriverEditor(
                label: "Blur Driver",
                driver: bindRendererBlurDriver(setIdx, itemIdx, fallback: renderer.blurRadius),
                isCollapsed: $blurDriverCollapsed,
                isHighlighted: selectedRendererLane(setIdx: setIdx, itemIdx: itemIdx) == .blur
            )
            if renderer.mode == .gradientFilled || renderer.mode == .gradientFilledStroked {
                DoubleDriverEditor(
                    label: "Gradient Blend",
                    driver: bindRendererGradientBlendDriver(setIdx, itemIdx),
                    isCollapsed: $gradientBlendDriverCollapsed,
                    isHighlighted: false
                )
            }
        }
    }

    @ViewBuilder
    private func rendererBatchEyeButton(for renderer: Renderer) -> some View {
        let d = renderer.drivers
        let isGradient = renderer.mode == .gradientFilled || renderer.mode == .gradientFilledStroked
        let fillUnused   = !(d?.fillColor?.enabled   ?? false) && (d?.fillColor?.keyframes.isEmpty   ?? true)
        let sColorUnused = !(d?.strokeColor?.enabled ?? false) && (d?.strokeColor?.keyframes.isEmpty ?? true)
        let sWidthUnused = !(d?.strokeWidth.enabled  ?? false) && (d?.strokeWidth.keyframes.isEmpty  ?? true)
        let opacUnused   = !(d?.opacity.enabled      ?? false) && (d?.opacity.keyframes.isEmpty      ?? true)
        let blurUnused   = !(d?.blur.enabled         ?? false) && (d?.blur.keyframes.isEmpty         ?? true)
        let blendUnused  = !(d?.gradientBlend.enabled ?? false) && (d?.gradientBlend.keyframes.isEmpty ?? true)

        let blendCollapsed = isGradient && gradientBlendDriverCollapsed
        let collapsed = [fillColorDriverCollapsed, strokeColorDriverCollapsed,
                         strokeWidthDriverCollapsed, opacityDriverCollapsed,
                         blurDriverCollapsed, blendCollapsed].filter { $0 }.count

        let blendUnusedVisible = isGradient && blendUnused && !gradientBlendDriverCollapsed
        let unusedVisible = [fillUnused   && !fillColorDriverCollapsed,
                              sColorUnused && !strokeColorDriverCollapsed,
                              sWidthUnused && !strokeWidthDriverCollapsed,
                              opacUnused   && !opacityDriverCollapsed,
                              blurUnused   && !blurDriverCollapsed,
                              blendUnusedVisible].filter { $0 }.count

        if collapsed > 0 {
            HStack {
                Spacer()
                Button {
                    fillColorDriverCollapsed = false; strokeColorDriverCollapsed = false
                    strokeWidthDriverCollapsed = false; opacityDriverCollapsed = false
                    blurDriverCollapsed = false
                    if isGradient { gradientBlendDriverCollapsed = false }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash").font(.system(size: 10))
                        Text("\(collapsed)").font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .loomHelp("\(collapsed) renderer driver section\(collapsed == 1 ? "" : "s") collapsed. Click to expand all.")
                .padding(.trailing, 12)
                .padding(.vertical, 4)
            }
        } else if unusedVisible > 0 {
            HStack {
                Spacer()
                Button {
                    if fillUnused   { fillColorDriverCollapsed = true }
                    if sColorUnused { strokeColorDriverCollapsed = true }
                    if sWidthUnused { strokeWidthDriverCollapsed = true }
                    if opacUnused   { opacityDriverCollapsed = true }
                    if blurUnused   { blurDriverCollapsed = true }
                    if isGradient && blendUnused { gradientBlendDriverCollapsed = true }
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .loomHelp("Collapse all renderer driver sections that are disabled and have no keyframes.")
                .padding(.trailing, 12)
                .padding(.vertical, 4)
            }
        }
    }

    private func selectedRendererLane(setIdx: Int, itemIdx: Int) -> RendererTimelineLane? {
        guard let selection = controller.selectedRendererTimelineKF,
              selection.rendererSetIdx == setIdx,
              selection.rendererItemIdx == itemIdx
        else { return nil }
        return selection.lane
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
            .loomHelp("Full Path — stamps the entire path each frame; Progressive — agents traverse the path incrementally, adding stamps over time.")
            InspectorField("Spacing") {
                FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.stampSpacing,
                                                   fallback: cfg.stampSpacing),
                                width: 55, fractionDigits: 1)
            }
            .loomHelp("Distance between stamp centres along the path in pixels. Smaller values = denser coverage.")
            InspectorField("Follow tang.") {
                Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.followTangent,
                                             fallback: cfg.followTangent))
                    .labelsHidden()
            }
            .loomHelp("When on, each stamp rotates to align with the path tangent at its placement point.")
            rangeField2("Perp. jitter",
                        v1: bindBrushKP(setIdx, itemIdx, \.perpendicularJitterMin,
                                        fallback: cfg.perpendicularJitterMin),
                        v2: bindBrushKP(setIdx, itemIdx, \.perpendicularJitterMax,
                                        fallback: cfg.perpendicularJitterMax))
            .loomHelp("Min/max perpendicular offset from the path in pixels. Adds scatter away from the line.")
            rangeField2("Scale",
                        v1: bindBrushKP(setIdx, itemIdx, \.scaleMin, fallback: cfg.scaleMin),
                        v2: bindBrushKP(setIdx, itemIdx, \.scaleMax, fallback: cfg.scaleMax))
            .loomHelp("Min/max scale multiplier applied to each stamp image (1.0 = original size).")
            rangeField2("Opacity",
                        v1: bindBrushKP(setIdx, itemIdx, \.opacityMin, fallback: cfg.opacityMin),
                        v2: bindBrushKP(setIdx, itemIdx, \.opacityMax, fallback: cfg.opacityMax))
            .loomHelp("Min/max opacity multiplier per stamp (0 = invisible, 1 = fully opaque).")
            InspectorField("Stamps/frame") {
                TextField("", value: bindBrushKP(setIdx, itemIdx, \.stampsPerFrame,
                                                 fallback: cfg.stampsPerFrame), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            .loomHelp("Number of stamp placements each draw frame in Progressive mode. Higher values = faster path coverage.")
            InspectorField("Agents") {
                TextField("", value: bindBrushKP(setIdx, itemIdx, \.agentCount,
                                                 fallback: cfg.agentCount), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            .loomHelp("Number of independent traversal agents in Progressive mode. More agents spread stamps across the path simultaneously.")
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
            .loomHelp("What happens when Progressive mode finishes — Hold (freeze at end), Loop (restart from beginning), Ping-Pong (reverse direction).")
            InspectorField("Blur radius") {
                TextField("", value: bindBrushKP(setIdx, itemIdx, \.blurRadius,
                                                 fallback: cfg.blurRadius), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            .loomHelp("Gaussian blur radius applied to each stamp image before drawing. 0 = no blur.")
            InspectorField("Pressure→size") {
                FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.pressureSizeInfluence,
                                                   fallback: cfg.pressureSizeInfluence),
                                width: 55, fractionDigits: 2)
            }
            .loomHelp("How strongly source polygon pressure data scales stamp size (0 = no effect, 1 = full influence).")
            InspectorField("Pressure→α") {
                FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.pressureAlphaInfluence,
                                                   fallback: cfg.pressureAlphaInfluence),
                                width: 55, fractionDigits: 2)
            }
            .loomHelp("How strongly source polygon pressure data scales stamp opacity (0 = no effect, 1 = full influence).")
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
            .loomHelp("Adds sinusoidal wave deviation to the stamp path before stamps are placed, creating a wavy brush stroke.")
            if cfg.meander.enabled {
                InspectorField("Amplitude") {
                    FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.meander.amplitude,
                                                       fallback: cfg.meander.amplitude),
                                    width: 60, fractionDigits: 1)
                }
                .loomHelp("Height of the wave deviation from the path centre in pixels. Larger values = more extreme undulation.")
                InspectorField("Frequency") {
                    FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.meander.frequency,
                                                       fallback: cfg.meander.frequency),
                                    width: 60, fractionDigits: 4)
                }
                .loomHelp("Wave frequency — higher values produce more oscillations per path unit length.")
                InspectorField("Samples") {
                    TextField("", value: bindBrushKP(setIdx, itemIdx, \.meander.samples,
                                                     fallback: cfg.meander.samples), format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50)
                }
                .loomHelp("Number of sample points used to build the meandered path. More samples = smoother wave; typically 50–200.")
                InspectorField("Seed") {
                    TextField("", value: bindBrushKP(setIdx, itemIdx, \.meander.seed,
                                                     fallback: cfg.meander.seed), format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50)
                    Text("0=auto").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                .loomHelp("Random seed for the meander shape. 0 = auto (varies each draw cycle); any other value locks the shape.")
                InspectorField("Animated") {
                    Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.meander.animated,
                                                 fallback: cfg.meander.animated))
                        .labelsHidden()
                }
                .loomHelp("When on, the meander phase shifts each frame, creating a flowing wave effect over time.")
                if cfg.meander.animated {
                    InspectorField("Anim speed") {
                        FloatEntryField(value: bindBrushKP(setIdx, itemIdx, \.meander.animSpeed,
                                                           fallback: cfg.meander.animSpeed),
                                        width: 60, fractionDigits: 4)
                    }
                    .loomHelp("Rate at which the meander phase advances per draw cycle. Higher values = faster wave movement.")
                }
                InspectorField("Scale path") {
                    Toggle("", isOn: bindBrushKP(setIdx, itemIdx, \.meander.scaleAlongPath,
                                                 fallback: cfg.meander.scaleAlongPath))
                        .labelsHidden()
                }
                .loomHelp("Modulate stamp scale along the path length using a secondary wave — stamps grow and shrink as they travel the path.")
                if cfg.meander.scaleAlongPath {
                    InspectorField("Path freq.") {
                        FloatEntryField(
                            value: bindBrushKP(setIdx, itemIdx, \.meander.scaleAlongPathFrequency,
                                               fallback: cfg.meander.scaleAlongPathFrequency),
                            width: 60, fractionDigits: 4)
                    }
                    .loomHelp("Frequency of the scale-along-path wave. Higher values = more scale variation cycles per path length.")
                    InspectorField("Path range") {
                        FloatEntryField(
                            value: bindBrushKP(setIdx, itemIdx, \.meander.scaleAlongPathRange,
                                               fallback: cfg.meander.scaleAlongPathRange),
                            width: 60, fractionDigits: 3)
                    }
                    .loomHelp("Amplitude of the scale variation — how much stamp size oscillates along the path.")
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
            .loomHelp("Full Path — stamps the entire path each frame; Progressive — agents traverse the path incrementally, adding stamps over time.")
            InspectorField("Spacing") {
                FloatEntryField(value: bindStencilKP(setIdx, itemIdx, \.stampSpacing,
                                                     fallback: cfg.stampSpacing),
                                width: 55, fractionDigits: 1)
            }
            .loomHelp("Distance between stamp centres along the path in pixels. Smaller values = denser coverage.")
            InspectorField("Follow tang.") {
                Toggle("", isOn: bindStencilKP(setIdx, itemIdx, \.followTangent,
                                               fallback: cfg.followTangent))
                    .labelsHidden()
            }
            .loomHelp("When on, each stamp rotates to align with the path tangent at its placement point.")
            rangeField2("Perp. jitter",
                        v1: bindStencilKP(setIdx, itemIdx, \.perpendicularJitterMin,
                                          fallback: cfg.perpendicularJitterMin),
                        v2: bindStencilKP(setIdx, itemIdx, \.perpendicularJitterMax,
                                          fallback: cfg.perpendicularJitterMax))
            .loomHelp("Min/max perpendicular offset from the path in pixels. Adds scatter away from the line.")
            rangeField2("Scale",
                        v1: bindStencilKP(setIdx, itemIdx, \.scaleMin, fallback: cfg.scaleMin),
                        v2: bindStencilKP(setIdx, itemIdx, \.scaleMax, fallback: cfg.scaleMax))
            .loomHelp("Min/max scale multiplier applied to each stamp image (1.0 = original size).")
            InspectorField("Stamps/frame") {
                TextField("", value: bindStencilKP(setIdx, itemIdx, \.stampsPerFrame,
                                                   fallback: cfg.stampsPerFrame), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            .loomHelp("Number of stamp placements each draw frame in Progressive mode. Higher values = faster path coverage.")
            InspectorField("Agents") {
                TextField("", value: bindStencilKP(setIdx, itemIdx, \.agentCount,
                                                   fallback: cfg.agentCount), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            .loomHelp("Number of independent traversal agents in Progressive mode. More agents spread stamps across the path simultaneously.")
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
            .loomHelp("What happens when Progressive mode finishes — Hold (freeze at end), Loop (restart from beginning), Ping-Pong (reverse direction).")
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
            .loomHelp("Animate stamp opacity over time using the palette and settings below.")
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

    // MARK: - Gradient config section

    @ViewBuilder
    private func gradientConfigSection(setIdx: Int, itemIdx: Int, cfg: GradientConfig) -> some View {
        InspectorSection("Gradient", isCollapsed: $gradientCollapsed) {
            InspectorField("Type") {
                Picker("", selection: bindGradientKP(setIdx, itemIdx, \.type, fallback: cfg.type)) {
                    ForEach(GradientType.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            .loomHelp("Linear — straight colour ramp between two control points. Radial — circular ramp from a centre point outward.")

            // Stops
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Stops").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        let pos = cfg.stops.last.map { min($0.position + 0.1, 1.0) } ?? 1.0
                        addGradientStop(setIdx: setIdx, itemIdx: itemIdx,
                                        stop: GradientStop(color: .white, position: pos))
                    } label: {
                        Image(systemName: "plus").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                ForEach(cfg.stops.indices, id: \.self) { si in
                    HStack(spacing: 6) {
                        gradientStopColorPicker(setIdx: setIdx, itemIdx: itemIdx,
                                                stopIdx: si, stop: cfg.stops[si])
                        FloatEntryField(value: bindGradientStopPos(setIdx, itemIdx, stopIdx: si,
                                                                    fallback: cfg.stops[si].position),
                                        width: 46, fractionDigits: 2)
                        Button {
                            removeGradientStop(setIdx: setIdx, itemIdx: itemIdx, stopIdx: si)
                        } label: {
                            Image(systemName: "minus.circle").font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(cfg.stops.count <= 2)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .loomHelp("Colour stops define the gradient. Position 0 = start/centre; 1 = end/outer edge. Minimum two stops required.")

            Divider().padding(.horizontal, 12)

            if cfg.type == .linear {
                InspectorField("Start X") {
                    FloatEntryField(value: bindGradientKP(setIdx, itemIdx, \.x0, fallback: cfg.x0),
                                    width: 55, fractionDigits: 2)
                }
                .loomHelp("X position of the gradient start point as a fraction of the polygon's bounding box width (0 = left edge, 1 = right edge).")
                InspectorField("Start Y") {
                    FloatEntryField(value: bindGradientKP(setIdx, itemIdx, \.y0, fallback: cfg.y0),
                                    width: 55, fractionDigits: 2)
                }
                .loomHelp("Y position of the gradient start point as a fraction of the bounding box height (0 = top, 1 = bottom).")
                InspectorField("End X") {
                    FloatEntryField(value: bindGradientKP(setIdx, itemIdx, \.x1, fallback: cfg.x1),
                                    width: 55, fractionDigits: 2)
                }
                .loomHelp("X position of the gradient end point as a fraction of the bounding box width.")
                InspectorField("End Y") {
                    FloatEntryField(value: bindGradientKP(setIdx, itemIdx, \.y1, fallback: cfg.y1),
                                    width: 55, fractionDigits: 2)
                }
                .loomHelp("Y position of the gradient end point as a fraction of the bounding box height.")
            } else {
                InspectorField("Centre X") {
                    FloatEntryField(value: bindGradientKP(setIdx, itemIdx, \.x0, fallback: cfg.x0),
                                    width: 55, fractionDigits: 2)
                }
                .loomHelp("X position of the radial gradient centre as a fraction of the bounding box width (0 = left, 1 = right).")
                InspectorField("Centre Y") {
                    FloatEntryField(value: bindGradientKP(setIdx, itemIdx, \.y0, fallback: cfg.y0),
                                    width: 55, fractionDigits: 2)
                }
                .loomHelp("Y position of the radial gradient centre as a fraction of the bounding box height (0 = top, 1 = bottom).")
                InspectorField("Radius") {
                    FloatEntryField(value: bindGradientKP(setIdx, itemIdx, \.radius, fallback: cfg.radius),
                                    width: 55, fractionDigits: 2)
                }
                .loomHelp("Outer radius of the radial gradient as a fraction of max(bounding box width, height). 0.5 = half the largest dimension.")
            }
        }
    }

    // MARK: - Gradient B section

    @ViewBuilder
    private func gradientBConfigSection(setIdx: Int, itemIdx: Int, cfg: GradientConfig?) -> some View {
        let hasCfg = cfg != nil
        let resolved = cfg ?? GradientConfig()
        InspectorSection("Gradient B", isCollapsed: $gradientBCollapsed) {
            if !hasCfg {
                HStack {
                    Text("No Gradient B defined.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add") {
                        controller.updateProjectConfig { config in
                            guard setIdx < config.renderingConfig.library.rendererSets.count,
                                  itemIdx < config.renderingConfig.library.rendererSets[setIdx].renderers.count
                            else { return }
                            config.renderingConfig.library.rendererSets[setIdx]
                                .renderers[itemIdx].gradientConfigB = GradientConfig()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 11))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Text("Add Gradient B and enable the Gradient Blend driver to animate between the two gradient states.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            } else {
                HStack {
                    Spacer()
                    Button("Remove B") {
                        controller.updateProjectConfig { config in
                            guard setIdx < config.renderingConfig.library.rendererSets.count,
                                  itemIdx < config.renderingConfig.library.rendererSets[setIdx].renderers.count
                            else { return }
                            config.renderingConfig.library.rendererSets[setIdx]
                                .renderers[itemIdx].gradientConfigB = nil
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.system(size: 10))
                    .padding(.trailing, 12)
                    .padding(.top, 4)
                }

                InspectorField("Type") {
                    Picker("", selection: bindGradientBKP(setIdx, itemIdx, \.type, fallback: resolved.type)) {
                        ForEach(GradientType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 130)
                }
                .loomHelp("Gradient B type — linear or radial. At blend=1 this type fully governs the gradient shape; it transitions at blend=0.5.")

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Stops").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            let pos = resolved.stops.last.map { min($0.position + 0.1, 1.0) } ?? 1.0
                            addGradientBStop(setIdx: setIdx, itemIdx: itemIdx,
                                             stop: GradientStop(color: .white, position: pos))
                        } label: {
                            Image(systemName: "plus").font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    ForEach(resolved.stops.indices, id: \.self) { si in
                        HStack(spacing: 6) {
                            gradientBStopColorPicker(setIdx: setIdx, itemIdx: itemIdx,
                                                     stopIdx: si, stop: resolved.stops[si])
                            FloatEntryField(
                                value: bindGradientBStopPos(setIdx, itemIdx, stopIdx: si,
                                                            fallback: resolved.stops[si].position),
                                width: 46, fractionDigits: 2)
                            Button {
                                removeGradientBStop(setIdx: setIdx, itemIdx: itemIdx, stopIdx: si)
                            } label: {
                                Image(systemName: "minus.circle").font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(resolved.stops.count <= 2)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .loomHelp("Gradient B colour stops — the blend target. Each stop is interpolated toward its matching Gradient A stop by index. Position 0 = start/centre; 1 = end/outer edge.")

                Divider().padding(.horizontal, 12)

                if resolved.type == .linear {
                    InspectorField("Start X") {
                        FloatEntryField(value: bindGradientBKP(setIdx, itemIdx, \.x0, fallback: resolved.x0),
                                        width: 55, fractionDigits: 2)
                    }
                    .loomHelp("Gradient B linear start X as a fraction of the polygon bounding box width (0 = left, 1 = right). Interpolated from Gradient A's Start X at blend=1.")
                    InspectorField("Start Y") {
                        FloatEntryField(value: bindGradientBKP(setIdx, itemIdx, \.y0, fallback: resolved.y0),
                                        width: 55, fractionDigits: 2)
                    }
                    .loomHelp("Gradient B linear start Y as a fraction of the bounding box height (0 = top, 1 = bottom).")
                    InspectorField("End X") {
                        FloatEntryField(value: bindGradientBKP(setIdx, itemIdx, \.x1, fallback: resolved.x1),
                                        width: 55, fractionDigits: 2)
                    }
                    .loomHelp("Gradient B linear end X as a fraction of the bounding box width.")
                    InspectorField("End Y") {
                        FloatEntryField(value: bindGradientBKP(setIdx, itemIdx, \.y1, fallback: resolved.y1),
                                        width: 55, fractionDigits: 2)
                    }
                    .loomHelp("Gradient B linear end Y as a fraction of the bounding box height.")
                } else {
                    InspectorField("Centre X") {
                        FloatEntryField(value: bindGradientBKP(setIdx, itemIdx, \.x0, fallback: resolved.x0),
                                        width: 55, fractionDigits: 2)
                    }
                    .loomHelp("Gradient B radial centre X as a fraction of the bounding box width (0 = left, 1 = right).")
                    InspectorField("Centre Y") {
                        FloatEntryField(value: bindGradientBKP(setIdx, itemIdx, \.y0, fallback: resolved.y0),
                                        width: 55, fractionDigits: 2)
                    }
                    .loomHelp("Gradient B radial centre Y as a fraction of the bounding box height (0 = top, 1 = bottom).")
                    InspectorField("Radius") {
                        FloatEntryField(value: bindGradientBKP(setIdx, itemIdx, \.radius, fallback: resolved.radius),
                                        width: 55, fractionDigits: 2)
                    }
                    .loomHelp("Gradient B outer radius as a fraction of max(bounding box width, height). Interpolated from Gradient A's radius at blend=1.")
                }
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
            .loomHelp("Animate the fill colour over time using the palette and settings below.")
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
            .loomHelp("Animate the stroke colour over time using the palette and settings below.")
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
            .loomHelp("Animate the stroke width over time using the size palette and settings below.")
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
        .loomHelp("Sequential — steps through palette colours in order; Random — picks a random palette colour each step.")
        InspectorField("Motion") {
            Picker("", selection: motion) {
                Text("Up").tag(ChangeMotion.up)
                Text("Down").tag(ChangeMotion.down)
                Text("Ping-Pong").tag(ChangeMotion.pingPong)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        .loomHelp("Up — advances forward through the palette; Down — steps in reverse; Ping-Pong — bounces back and forth.")
        InspectorField("Cycle") {
            Picker("", selection: cycle) {
                Text("Constant").tag(ChangeCycle.constant)
                Text("Pausing").tag(ChangeCycle.pausing)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        .loomHelp("Constant — advances one step per draw unit; Pausing — holds each colour for a random number of steps up to Pause max.")
        InspectorField("Scale") {
            Picker("", selection: scale) {
                Text("Poly").tag(ChangeScale.poly)
                Text("Sprite").tag(ChangeScale.sprite)
                Text("Point").tag(ChangeScale.point)
                Text("Global").tag(ChangeScale.global)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        .loomHelp("What counts as one step — Poly (each polygon), Sprite (each sprite), Point (each point), Global (all sprites share the same palette index).")
        if cycle.wrappedValue == .pausing {
            InspectorField("Pause max") {
                TextField("", value: pauseMax, format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            .loomHelp("Maximum number of steps to hold on each colour before advancing to the next palette entry.")
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
        .loomHelp("Sequential — steps through palette values in order; Random — picks a random palette value each step.")
        InspectorField("Motion") {
            Picker("", selection: motion) {
                Text("Up").tag(ChangeMotion.up)
                Text("Down").tag(ChangeMotion.down)
                Text("Ping-Pong").tag(ChangeMotion.pingPong)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        .loomHelp("Up — advances forward through the palette; Down — steps in reverse; Ping-Pong — bounces back and forth.")
        InspectorField("Cycle") {
            Picker("", selection: cycle) {
                Text("Constant").tag(ChangeCycle.constant)
                Text("Pausing").tag(ChangeCycle.pausing)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        .loomHelp("Constant — advances one step per draw unit; Pausing — holds each value for a random number of steps up to Pause max.")
        InspectorField("Scale") {
            Picker("", selection: scale) {
                Text("Poly").tag(ChangeScale.poly)
                Text("Sprite").tag(ChangeScale.sprite)
                Text("Point").tag(ChangeScale.point)
                Text("Global").tag(ChangeScale.global)
            }
            .labelsHidden().frame(maxWidth: 110)
        }
        .loomHelp("What counts as one step — Poly (each polygon), Sprite (each sprite), Point (each point), Global (all sprites share the same palette index).")
        if cycle.wrappedValue == .pausing {
            InspectorField("Pause max") {
                TextField("", value: pauseMax, format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 50)
            }
            .loomHelp("Maximum number of steps to hold on each value before advancing to the next palette entry.")
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
            if (mode == .gradientFilled || mode == .gradientFilledStroked) && r.gradientConfig == nil {
                r.gradientConfig = GradientConfig()
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

    private func bindRendererStrokeWidthDriver(_ setIdx: Int,
                                               _ itemIdx: Int,
                                               fallback: Double) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .drivers?.strokeWidth ?? DoubleDriver.constant(fallback)
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].drivers = defaultRendererDrivers(
                                for: cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
                            )
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers!.strokeWidth = v
                }
            }
        )
    }

    private func bindRendererFillColorDriver(_ setIdx: Int,
                                             _ itemIdx: Int,
                                             fallback: LoomColor) -> Binding<ColorDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .drivers?.fillColor ?? ColorDriver.constant(fallback)
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers == nil {
                        let renderer = cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].drivers = defaultRendererDrivers(for: renderer)
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers!.fillColor = v
                }
            }
        )
    }

    private func bindRendererStrokeColorDriver(_ setIdx: Int,
                                               _ itemIdx: Int,
                                               fallback: LoomColor) -> Binding<ColorDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .drivers?.strokeColor ?? ColorDriver.constant(fallback)
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers == nil {
                        let renderer = cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].drivers = defaultRendererDrivers(for: renderer)
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers!.strokeColor = v
                }
            }
        )
    }

    private func bindRendererOpacityDriver(_ setIdx: Int,
                                           _ itemIdx: Int) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .drivers?.opacity ?? .one
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].drivers = defaultRendererDrivers(
                                for: cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
                            )
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers!.opacity = v
                }
            }
        )
    }

    private func bindRendererBlurDriver(_ setIdx: Int,
                                        _ itemIdx: Int,
                                        fallback: Double) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .drivers?.blur ?? DoubleDriver.constant(fallback)
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].drivers = defaultRendererDrivers(
                                for: cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
                            )
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers!.blur = v
                }
            }
        )
    }

    private func defaultRendererDrivers(for renderer: Renderer) -> RendererDrivers {
        RendererDrivers(
            fillColor: ColorDriver.constant(renderer.fillColor),
            strokeColor: ColorDriver.constant(renderer.strokeColor),
            strokeWidth: DoubleDriver.constant(renderer.strokeWidth),
            opacity: .one,
            blur: DoubleDriver.constant(renderer.blurRadius),
            gradientBlend: .zero
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

    // MARK: - Binding helpers: gradient config

    private func bindGradientKP<T>(_ setIdx: Int, _ itemIdx: Int,
                                    _ kp: WritableKeyPath<GradientConfig, T>,
                                    fallback: T) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .gradientConfig?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].gradientConfig == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].gradientConfig = GradientConfig()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].gradientConfig![keyPath: kp] = v
                }
            }
        )
    }

    @ViewBuilder
    private func gradientStopColorPicker(setIdx: Int, itemIdx: Int,
                                          stopIdx: Int, stop: GradientStop) -> some View {
        let ctl = controller
        let binding = Binding<Color>(
            get: {
                Color(red: stop.color.rF, green: stop.color.gF,
                      blue: stop.color.bF, opacity: stop.color.aF)
            },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? NSColor.black
                let lc = LoomColor(
                    r: Int(max(0, min(255, (ns.redComponent   * 255 + 0.5).rounded(.down)))),
                    g: Int(max(0, min(255, (ns.greenComponent * 255 + 0.5).rounded(.down)))),
                    b: Int(max(0, min(255, (ns.blueComponent  * 255 + 0.5).rounded(.down)))),
                    a: Int(max(0, min(255, (ns.alphaComponent * 255 + 0.5).rounded(.down))))
                )
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count,
                          cfg.renderingConfig.library.rendererSets[setIdx]
                              .renderers[itemIdx].gradientConfig != nil,
                          stopIdx < cfg.renderingConfig.library.rendererSets[setIdx]
                              .renderers[itemIdx].gradientConfig!.stops.count
                    else { return }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].gradientConfig!.stops[stopIdx].color = lc
                }
            }
        )
        ColorPicker("", selection: binding, supportsOpacity: true)
            .labelsHidden()
            .frame(width: 44, height: 22)
    }

    private func bindGradientStopPos(_ setIdx: Int, _ itemIdx: Int,
                                      stopIdx: Int, fallback: Double) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .gradientConfig?.stops[safe: stopIdx]?.position ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count,
                          cfg.renderingConfig.library.rendererSets[setIdx]
                              .renderers[itemIdx].gradientConfig != nil,
                          stopIdx < cfg.renderingConfig.library.rendererSets[setIdx]
                              .renderers[itemIdx].gradientConfig!.stops.count
                    else { return }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].gradientConfig!.stops[stopIdx].position = max(0, min(1, v))
                }
            }
        )
    }

    private func addGradientStop(setIdx: Int, itemIdx: Int, stop: GradientStop) {
        controller.updateProjectConfig { cfg in
            guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                  itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
            else { return }
            if cfg.renderingConfig.library.rendererSets[setIdx]
                .renderers[itemIdx].gradientConfig == nil {
                cfg.renderingConfig.library.rendererSets[setIdx]
                    .renderers[itemIdx].gradientConfig = GradientConfig()
            }
            cfg.renderingConfig.library.rendererSets[setIdx]
                .renderers[itemIdx].gradientConfig!.stops.append(stop)
        }
    }

    private func removeGradientStop(setIdx: Int, itemIdx: Int, stopIdx: Int) {
        controller.updateProjectConfig { cfg in
            guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                  itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count,
                  let count = cfg.renderingConfig.library.rendererSets[setIdx]
                      .renderers[itemIdx].gradientConfig?.stops.count,
                  count > 2, stopIdx < count
            else { return }
            cfg.renderingConfig.library.rendererSets[setIdx]
                .renderers[itemIdx].gradientConfig!.stops.remove(at: stopIdx)
        }
    }

    // MARK: - Binding helpers: gradient B config

    private func bindGradientBKP<T>(_ setIdx: Int, _ itemIdx: Int,
                                     _ kp: WritableKeyPath<GradientConfig, T>,
                                     fallback: T) -> Binding<T> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .gradientConfigB?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].gradientConfigB == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].gradientConfigB = GradientConfig()
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].gradientConfigB![keyPath: kp] = v
                }
            }
        )
    }

    @ViewBuilder
    private func gradientBStopColorPicker(setIdx: Int, itemIdx: Int,
                                           stopIdx: Int, stop: GradientStop) -> some View {
        let ctl = controller
        let binding = Binding<Color>(
            get: {
                Color(red: stop.color.rF, green: stop.color.gF,
                      blue: stop.color.bF, opacity: stop.color.aF)
            },
            set: { newColor in
                let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? NSColor.black
                let lc = LoomColor(
                    r: Int(max(0, min(255, (ns.redComponent   * 255 + 0.5).rounded(.down)))),
                    g: Int(max(0, min(255, (ns.greenComponent * 255 + 0.5).rounded(.down)))),
                    b: Int(max(0, min(255, (ns.blueComponent  * 255 + 0.5).rounded(.down)))),
                    a: Int(max(0, min(255, (ns.alphaComponent * 255 + 0.5).rounded(.down))))
                )
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count,
                          cfg.renderingConfig.library.rendererSets[setIdx]
                              .renderers[itemIdx].gradientConfigB != nil,
                          stopIdx < cfg.renderingConfig.library.rendererSets[setIdx]
                              .renderers[itemIdx].gradientConfigB!.stops.count
                    else { return }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].gradientConfigB!.stops[stopIdx].color = lc
                }
            }
        )
        ColorPicker("", selection: binding, supportsOpacity: true)
            .labelsHidden()
            .frame(width: 44, height: 22)
    }

    private func bindGradientBStopPos(_ setIdx: Int, _ itemIdx: Int,
                                       stopIdx: Int, fallback: Double) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .gradientConfigB?.stops[safe: stopIdx]?.position ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count,
                          cfg.renderingConfig.library.rendererSets[setIdx]
                              .renderers[itemIdx].gradientConfigB != nil,
                          stopIdx < cfg.renderingConfig.library.rendererSets[setIdx]
                              .renderers[itemIdx].gradientConfigB!.stops.count
                    else { return }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].gradientConfigB!.stops[stopIdx].position = max(0, min(1, v))
                }
            }
        )
    }

    private func addGradientBStop(setIdx: Int, itemIdx: Int, stop: GradientStop) {
        controller.updateProjectConfig { cfg in
            guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                  itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
            else { return }
            if cfg.renderingConfig.library.rendererSets[setIdx]
                .renderers[itemIdx].gradientConfigB == nil {
                cfg.renderingConfig.library.rendererSets[setIdx]
                    .renderers[itemIdx].gradientConfigB = GradientConfig()
            }
            cfg.renderingConfig.library.rendererSets[setIdx]
                .renderers[itemIdx].gradientConfigB!.stops.append(stop)
        }
    }

    private func removeGradientBStop(setIdx: Int, itemIdx: Int, stopIdx: Int) {
        controller.updateProjectConfig { cfg in
            guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                  itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count,
                  let count = cfg.renderingConfig.library.rendererSets[setIdx]
                      .renderers[itemIdx].gradientConfigB?.stops.count,
                  count > 2, stopIdx < count
            else { return }
            cfg.renderingConfig.library.rendererSets[setIdx]
                .renderers[itemIdx].gradientConfigB!.stops.remove(at: stopIdx)
        }
    }

    // MARK: - Binding helpers: gradient blend driver

    private func bindRendererGradientBlendDriver(_ setIdx: Int,
                                                  _ itemIdx: Int) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?
                    .drivers?.gradientBlend ?? .zero
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    if cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers == nil {
                        cfg.renderingConfig.library.rendererSets[setIdx]
                            .renderers[itemIdx].drivers = defaultRendererDrivers(
                                for: cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
                            )
                    }
                    cfg.renderingConfig.library.rendererSets[setIdx]
                        .renderers[itemIdx].drivers!.gradientBlend = v
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
        case .points:               return "Points"
        case .stroked:              return "Stroked"
        case .filled:               return "Filled"
        case .filledStroked:        return "Filled+Stroked"
        case .gradientFilled:       return "Gradient Filled"
        case .gradientFilledStroked: return "Gradient Filled+Stroked"
        case .brushed:              return "Brushed"
        case .stenciled:            return "Stenciled"
        case .stamped:              return "Stamped"
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
