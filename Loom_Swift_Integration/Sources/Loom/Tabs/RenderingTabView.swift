import SwiftUI
import LoomEngine

struct RenderingTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            rendererList
            Divider()
            toolbar
        }
    }

    // MARK: - List

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

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("plus",                   tooltip: "New renderer set")      { addSet() }
            toolbarButton("minus",                  tooltip: "Delete renderer set")   { deleteSelectedSet() }
                .disabled(controller.selectedRendererIndex == nil)
            toolbarButton("plus.square.on.square",  tooltip: "Duplicate renderer set") { duplicateSelectedSet() }
                .disabled(controller.selectedRendererIndex == nil)

            Divider().frame(height: 14).padding(.horizontal, 4)

            toolbarButton("plus.circle",            tooltip: "Add renderer")          { addRenderer() }
                .disabled(controller.selectedRendererIndex == nil)
            toolbarButton("minus.circle",           tooltip: "Delete renderer")       { deleteSelectedRenderer() }
                .disabled(controller.selectedRendererItemIndex == nil)
            toolbarButton("arrow.triangle.2.circlepath", tooltip: "Duplicate renderer") { duplicateSelectedRenderer() }
                .disabled(controller.selectedRendererItemIndex == nil)

            Spacer()
        }
        .padding(.horizontal, 4)
        .frame(height: 30)
    }

    private func toolbarButton(_ icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.tertiary)
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - CRUD: sets

    private func addSet() {
        guard let cfg = controller.projectConfig else { return }
        let name = uniqueName(base: "new_set",
                              existing: cfg.renderingConfig.library.rendererSets.map(\.name))
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets.append(RendererSet(name: name))
        }
        let newIdx = (controller.projectConfig?.renderingConfig.library.rendererSets.count ?? 1) - 1
        controller.selectedRendererIndex     = newIdx
        controller.selectedRendererItemIndex = nil
    }

    private func deleteSelectedSet() {
        guard let idx = controller.selectedRendererIndex,
              let cfg = controller.projectConfig,
              idx < cfg.renderingConfig.library.rendererSets.count else { return }
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets.remove(at: idx)
        }
        let remaining = controller.projectConfig?.renderingConfig.library.rendererSets.count ?? 0
        controller.selectedRendererIndex     = remaining > 0 ? min(idx, remaining - 1) : nil
        controller.selectedRendererItemIndex = nil
    }

    private func duplicateSelectedSet() {
        guard let idx = controller.selectedRendererIndex,
              let cfg = controller.projectConfig,
              idx < cfg.renderingConfig.library.rendererSets.count else { return }
        var copy = cfg.renderingConfig.library.rendererSets[idx]
        copy.name = uniqueName(base: "\(copy.name)_copy",
                               existing: cfg.renderingConfig.library.rendererSets.map(\.name))
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets.insert(copy, at: idx + 1)
        }
        controller.selectedRendererIndex     = idx + 1
        controller.selectedRendererItemIndex = nil
    }

    // MARK: - CRUD: renderers within selected set

    private func addRenderer() {
        guard let setIdx = controller.selectedRendererIndex,
              let cfg    = controller.projectConfig,
              setIdx < cfg.renderingConfig.library.rendererSets.count else { return }
        let existing = cfg.renderingConfig.library.rendererSets[setIdx].renderers.map(\.name)
        let name = uniqueName(base: "renderer", existing: existing)
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets[setIdx].renderers.append(Renderer(name: name))
        }
        let newItemIdx = (controller.projectConfig?.renderingConfig.library
            .rendererSets[safe: setIdx]?.renderers.count ?? 1) - 1
        controller.selectedRendererItemIndex = newItemIdx
    }

    private func deleteSelectedRenderer() {
        guard let setIdx  = controller.selectedRendererIndex,
              let itemIdx = controller.selectedRendererItemIndex,
              let cfg     = controller.projectConfig,
              setIdx  < cfg.renderingConfig.library.rendererSets.count,
              itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count else { return }
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets[setIdx].renderers.remove(at: itemIdx)
        }
        let remaining = controller.projectConfig?.renderingConfig.library
            .rendererSets[safe: setIdx]?.renderers.count ?? 0
        controller.selectedRendererItemIndex = remaining > 0 ? min(itemIdx, remaining - 1) : nil
    }

    private func duplicateSelectedRenderer() {
        guard let setIdx  = controller.selectedRendererIndex,
              let itemIdx = controller.selectedRendererItemIndex,
              let cfg     = controller.projectConfig,
              setIdx  < cfg.renderingConfig.library.rendererSets.count,
              itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count else { return }
        let existing = cfg.renderingConfig.library.rendererSets[setIdx].renderers.map(\.name)
        var copy = cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx]
        copy.name = uniqueName(base: "\(copy.name)_copy", existing: existing)
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets[setIdx].renderers.insert(copy, at: itemIdx + 1)
        }
        controller.selectedRendererItemIndex = itemIdx + 1
    }

    // MARK: - Helpers

    private func uniqueName(base: String, existing: [String]) -> String {
        guard existing.contains(base) else { return base }
        var i = 2
        while existing.contains("\(base)_\(i)") { i += 1 }
        return "\(base)_\(i)"
    }
}

// MARK: - Row

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
