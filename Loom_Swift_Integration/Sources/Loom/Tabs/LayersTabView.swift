import SwiftUI
import LoomEngine

struct LayersTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            layerList
            Spacer(minLength: 0)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Layers")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                controller.addLayer()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Add layer")
            .modifier(LoomHoverHelp("Add layer"))

            Button {
                if let idx = controller.selectedLayerIndex {
                    controller.removeLayer(at: idx)
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(controller.selectedLayerIndex == nil)
            .help("Remove selected layer")
            .modifier(LoomHoverHelp("Remove selected layer"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Layer list

    private var layerList: some View {
        let layers = controller.projectConfig?.layers ?? []
        return List(selection: Binding(
            get: { controller.selectedLayerIndex },
            set: { controller.selectedLayerIndex = $0 }
        )) {
            ForEach(Array(layers.enumerated()), id: \.element.id) { idx, layer in
                layerRow(layer: layer, index: idx)
                    .tag(idx)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            .onMove { source, dest in
                controller.moveLayer(from: source, to: dest)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 30)
    }

    private func layerRow(layer: LoomLayer, index: Int) -> some View {
        let isSelected = controller.selectedLayerIndex == index
        return HStack(spacing: 6) {
            Button {
                controller.updateProjectConfig { cfg in
                    cfg.layers[index].isVisible.toggle()
                }
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(layer.isVisible ? Color.primary : Color.secondary.opacity(0.5))
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(layer.name.isEmpty ? "Layer" : layer.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if !layer.spriteSetNames.isEmpty {
                    Text(layer.spriteSetNames.joined(separator: ", "))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            if layer.parallaxFactor != 1.0 {
                Text(String(format: "%.1f×", layer.parallaxFactor))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if layer.blendMode != .normal {
                Text(layer.blendMode.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.selectedLayerIndex = index
        }
    }
}
