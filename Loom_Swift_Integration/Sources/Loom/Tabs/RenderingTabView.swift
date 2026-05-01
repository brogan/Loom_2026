import SwiftUI
import LoomEngine

struct RenderingTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            rendererList
            Divider()
            addButton
        }
    }

    @ViewBuilder
    private var rendererList: some View {
        let sets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []
        if sets.isEmpty {
            emptyState(controller.projectConfig == nil ? "No project open" : "No renderer sets")
        } else {
            List(selection: $controller.selectedRendererIndex) {
                ForEach(Array(sets.enumerated()), id: \.offset) { idx, set in
                    RendererSetRow(set: set)
                        .tag(idx)
                }
            }
            .listStyle(.plain)
        }
    }

    private var addButton: some View {
        HStack {
            Button {
                // Phase 3: add renderer set
            } label: {
                Label("New Renderer Set", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .padding(8)
            Spacer()
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.tertiary)
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RendererSetRow: View {
    let set: RendererSet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(set.name.isEmpty ? "(unnamed)" : set.name)
                .font(.system(size: 12, weight: .medium))
            Text("\(set.renderers.count) renderer\(set.renderers.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
