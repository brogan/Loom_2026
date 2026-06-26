import SwiftUI
import LoomEngine

struct LayersInspector: View {

    @EnvironmentObject private var controller: AppController
    @State private var spriteSetsCollapsed   = false
    @State private var opacityCollapsed      = false
    @State private var blurCollapsed         = true
    @State private var opacityDrvCollapsed   = true
    @State private var blurDrvCollapsed      = true

    var body: some View {
        guard let idx = controller.selectedLayerIndex,
              let layers = controller.projectConfig?.layers,
              layers.indices.contains(idx)
        else { return AnyView(EmptyView()) }

        let layer = layers[idx]

        return AnyView(VStack(alignment: .leading, spacing: 0) {

            // MARK: Layer info
            InspectorSection("Layer") {
                // Name
                HStack(spacing: 8) {
                    Text("Name")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 94, alignment: .leading)
                    TextField("", text: bindName(idx))
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

                // Visible
                InspectorField("Visible") {
                    Toggle("", isOn: bindBool(idx, \.isVisible))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.75)
                }

                // Blend mode
                InspectorField("Blend Mode") {
                    Picker("", selection: bindBlendMode(idx)) {
                        ForEach(LayerBlendMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                // Parallax factor
                InspectorField("Parallax") {
                    Slider(value: bindDouble(idx, \.parallaxFactor), in: -2...3)
                    FloatEntryField(
                        value: bindDouble(idx, \.parallaxFactor),
                        width: 44, fractionDigits: 2
                    )
                }
            }

            // MARK: Opacity
            InspectorSection("Opacity", isCollapsed: $opacityCollapsed) {
                InspectorField("Opacity") {
                    Slider(value: bindDouble(idx, \.opacity), in: 0...1)
                    FloatEntryField(
                        value: bindDouble(idx, \.opacity),
                        width: 44, fractionDigits: 2
                    )
                }
                DoubleDriverEditor(
                    label: "Driver",
                    driver: bindOpacityDriver(idx),
                    isCollapsed: $opacityDrvCollapsed
                )
                .environmentObject(controller)
            }

            // MARK: Blur
            InspectorSection("Blur", isCollapsed: $blurCollapsed) {
                InspectorField("Blur") {
                    Slider(value: bindDouble(idx, \.blur), in: 0...60)
                    FloatEntryField(
                        value: bindDouble(idx, \.blur),
                        width: 44, fractionDigits: 1
                    )
                }
                DoubleDriverEditor(
                    label: "Driver",
                    driver: bindBlurDriver(idx),
                    isCollapsed: $blurDrvCollapsed
                )
                .environmentObject(controller)
            }

            // MARK: Sprite sets
            InspectorSection("Sprite Sets", isCollapsed: $spriteSetsCollapsed) {
                let allSets = controller.projectConfig?.spriteConfig.library.spriteSets.map { $0.name } ?? []
                if allSets.isEmpty {
                    Text("No sprite sets defined.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    ForEach(allSets, id: \.self) { setName in
                        let assigned = layer.spriteSetNames.contains(setName)
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { assigned },
                                set: { isOn in
                                    if isOn {
                                        controller.assignSpriteSet(named: setName, toLayerAt: idx)
                                    } else {
                                        controller.unassignSpriteSet(named: setName, fromLayerAt: idx)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                            Text(setName)
                                .font(.system(size: 12))
                                .lineLimit(1)

                            Spacer()

                            // Show which layer currently owns this set
                            if !assigned {
                                if let ownerLayer = controller.projectConfig?.layers.first(where: {
                                    $0.spriteSetNames.contains(setName) && $0.name != layer.name
                                }) {
                                    Text(ownerLayer.name)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if assigned {
                                controller.unassignSpriteSet(named: setName, fromLayerAt: idx)
                            } else {
                                controller.assignSpriteSet(named: setName, toLayerAt: idx)
                            }
                        }
                    }
                }
            }
        })
    }

    // MARK: - Bindings

    private func bindName(_ idx: Int) -> Binding<String> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.layers[safe: idx]?.name ?? "" },
            set: { v in ctl.updateProjectConfig { cfg in
                guard cfg.layers.indices.contains(idx) else { return }
                cfg.layers[idx].name = v
            }}
        )
    }

    private func bindBool(_ idx: Int, _ kp: WritableKeyPath<LoomLayer, Bool>) -> Binding<Bool> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.layers[safe: idx]?[keyPath: kp] ?? true },
            set: { v in ctl.updateProjectConfig { cfg in
                guard cfg.layers.indices.contains(idx) else { return }
                cfg.layers[idx][keyPath: kp] = v
            }}
        )
    }

    private func bindDouble(_ idx: Int, _ kp: WritableKeyPath<LoomLayer, Double>) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.layers[safe: idx]?[keyPath: kp] ?? 0 },
            set: { v in ctl.updateProjectConfig { cfg in
                guard cfg.layers.indices.contains(idx) else { return }
                cfg.layers[idx][keyPath: kp] = v
            }}
        )
    }

    private func bindBlendMode(_ idx: Int) -> Binding<LayerBlendMode> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.layers[safe: idx]?.blendMode ?? .normal },
            set: { v in ctl.updateProjectConfig { cfg in
                guard cfg.layers.indices.contains(idx) else { return }
                cfg.layers[idx].blendMode = v
            }}
        )
    }

    private func bindOpacityDriver(_ idx: Int) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.layers[safe: idx]?.opacityDriver ?? .one },
            set: { v in ctl.updateProjectConfig { cfg in
                guard cfg.layers.indices.contains(idx) else { return }
                cfg.layers[idx].opacityDriver = v
            }}
        )
    }

    private func bindBlurDriver(_ idx: Int) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.layers[safe: idx]?.blurDriver ?? .zero },
            set: { v in ctl.updateProjectConfig { cfg in
                guard cfg.layers.indices.contains(idx) else { return }
                cfg.layers[idx].blurDriver = v
            }}
        )
    }
}
