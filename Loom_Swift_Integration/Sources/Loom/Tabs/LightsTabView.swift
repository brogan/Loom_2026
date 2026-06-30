import SwiftUI
import LoomEngine

struct LightsTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            lightList
            Spacer(minLength: 0)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Lights")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            // Master enable toggle
            let isEnabled = controller.projectConfig?.lightingConfig.isEnabled ?? false
            Button {
                controller.updateLightingConfig { cfg in cfg.isEnabled.toggle() }
            } label: {
                Image(systemName: isEnabled ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 12))
                    .foregroundStyle(isEnabled ? Color.yellow : Color.secondary)
                    .iconHitArea()
            }
            .buttonStyle(.plain)
            .modifier(LoomHoverHelp(isEnabled ? "Lighting enabled — click to disable" : "Lighting disabled — click to enable"))

            // Add buttons
            Button { controller.addLight(type: .omni) } label: {
                Text("Omni").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .modifier(LoomHoverHelp("Add omni (radial) light"))

            Button { controller.addLight(type: .spot) } label: {
                Text("Spot").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .modifier(LoomHoverHelp("Add spotlight"))

            Button { controller.addLight(type: .area) } label: {
                Text("Area").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .modifier(LoomHoverHelp("Add area light"))

            Button {
                if let idx = controller.selectedLightIndex {
                    controller.removeLight(at: idx)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12))
                    .iconHitArea()
            }
            .buttonStyle(.plain)
            .disabled(controller.selectedLightIndex == nil)
            .modifier(LoomHoverHelp("Remove selected light"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Light list

    private var lightList: some View {
        let lights = controller.projectConfig?.lightingConfig.lights ?? []
        return List(selection: Binding(
            get: { controller.selectedLightIndex },
            set: { controller.selectedLightIndex = $0 }
        )) {
            ForEach(Array(lights.enumerated()), id: \.element.id) { idx, light in
                lightRow(idx: idx, light: light)
                    .tag(idx)
            }
            .onMove { from, to in
                controller.updateLightingConfig { cfg in
                    cfg.lights.move(fromOffsets: from, toOffset: to)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func lightRow(idx: Int, light: LoomLight) -> some View {
        HStack(spacing: 6) {
            // Enable toggle
            Button {
                controller.updateLightingConfig { cfg in
                    guard cfg.lights.indices.contains(idx) else { return }
                    cfg.lights[idx].isEnabled.toggle()
                }
            } label: {
                Image(systemName: light.isEnabled ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 11))
                    .foregroundStyle(light.isEnabled ? Color.yellow : Color.secondary)
                    .iconHitArea()
            }
            .buttonStyle(.plain)

            // Type icon
            Image(systemName: typeIcon(light.type))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            // Name (editable inline)
            TextField("", text: bindName(idx))
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            Spacer()

            // Colour swatch
            let c = light.color
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: c.rF, green: c.gF, blue: c.bF))
                .frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.primary.opacity(0.2), lineWidth: 0.5))
        }
        .opacity(light.isEnabled ? 1 : 0.5)
        .contentShape(Rectangle())
    }

    private func typeIcon(_ type: LightType) -> String {
        switch type {
        case .omni: return "circle.dotted"
        case .spot: return "triangle"
        case .area: return "rectangle"
        }
    }

    // MARK: - Bindings

    private func bindName(_ idx: Int) -> Binding<String> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.lightingConfig.lights[safe: idx]?.name ?? "" },
            set: { v in ctl.updateLightingConfig { cfg in
                guard cfg.lights.indices.contains(idx) else { return }
                cfg.lights[idx].name = v
            }}
        )
    }
}
