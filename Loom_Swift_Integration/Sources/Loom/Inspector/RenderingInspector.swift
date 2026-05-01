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

    // MARK: - Binding helpers

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
