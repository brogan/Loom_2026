import SwiftUI
import LoomEngine

struct RenderingTabView: View {

    @EnvironmentObject private var controller: AppController

    @State private var expandedSets: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            rendererList
            Divider()
            toolbar
        }
        .onAppear { autoExpand() }
        .onChange(of: controller.selectedRendererIndex) { _, idx in
            if let idx { expandedSets.insert(idx) }
        }
    }

    // MARK: - List

    private var rendererList: some View {
        let sets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []
        return Group {
            if sets.isEmpty {
                emptyState(controller.projectConfig == nil ? "No project open" : "No renderer sets")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sets.indices, id: \.self) { setIdx in
                            setRow(set: sets[setIdx], setIdx: setIdx)
                            if expandedSets.contains(setIdx) {
                                ForEach(sets[setIdx].renderers.indices, id: \.self) { itemIdx in
                                    rendererRow(
                                        renderer: sets[setIdx].renderers[itemIdx],
                                        setIdx: setIdx, itemIdx: itemIdx
                                    )
                                }
                                if sets[setIdx].renderers.isEmpty {
                                    Text("No renderers — use + to add")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(.leading, 28)
                                        .padding(.vertical, 3)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Set row

    private func setRow(set: RendererSet, setIdx: Int) -> some View {
        let isSelected = controller.selectedRendererIndex == setIdx
        let isExpanded = expandedSets.contains(setIdx)

        return HStack(spacing: 5) {
            Button {
                toggleExpansion(setIdx)
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Text(set.name.isEmpty ? "(unnamed)" : set.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 2)

            Text("\(set.renderers.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { handleSetSelected(setIdx) }
    }

    // MARK: - Renderer row

    private func rendererRow(renderer: Renderer, setIdx: Int, itemIdx: Int) -> some View {
        let isSelected = controller.selectedRendererIndex == setIdx
                      && controller.selectedRendererItemIndex == itemIdx

        return HStack(spacing: 5) {
            Spacer().frame(width: 22)
            Text(renderer.name.isEmpty ? "(unnamed)" : renderer.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .opacity(renderer.enabled ? 1.0 : 0.38)
            Spacer(minLength: 2)
            Text(renderer.mode.shortLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .opacity(renderer.enabled ? 1.0 : 0.38)
            Toggle("", isOn: bindRendererEnabled(setIdx: setIdx, itemIdx: itemIdx))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .scaleEffect(0.82)
                .frame(width: 18)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { handleItemSelected(setIdx: setIdx, itemIdx: itemIdx) }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("plus",                   tooltip: "New renderer set")       { addSet() }
            toolbarButton("minus",                  tooltip: "Delete renderer set")    { deleteSelectedSet() }
                .disabled(controller.selectedRendererIndex == nil)
            toolbarButton("plus.square.on.square",  tooltip: "Duplicate renderer set") { duplicateSelectedSet() }
                .disabled(controller.selectedRendererIndex == nil)

            Divider().frame(height: 14).padding(.horizontal, 4)

            toolbarButton("plus.circle",            tooltip: "Add renderer")           { addRenderer() }
                .disabled(controller.selectedRendererIndex == nil)
            toolbarButton("minus.circle",           tooltip: "Delete renderer")        { deleteSelectedRenderer() }
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

    // MARK: - Interaction

    private func handleSetSelected(_ setIdx: Int) {
        if controller.selectedRendererIndex == setIdx,
           controller.selectedRendererItemIndex == nil {
            toggleExpansion(setIdx)
            return
        }
        controller.selectedRendererIndex     = setIdx
        controller.selectedRendererItemIndex = nil
        expandedSets.insert(setIdx)
    }

    private func handleItemSelected(setIdx: Int, itemIdx: Int) {
        controller.selectedRendererIndex     = setIdx
        controller.selectedRendererItemIndex = itemIdx
        expandedSets.insert(setIdx)
    }

    private func toggleExpansion(_ setIdx: Int) {
        if expandedSets.contains(setIdx) { expandedSets.remove(setIdx) }
        else { expandedSets.insert(setIdx) }
    }

    private func autoExpand() {
        if let idx = controller.selectedRendererIndex { expandedSets.insert(idx) }
    }

    // MARK: - Binding: renderer enabled

    private func bindRendererEnabled(setIdx: Int, itemIdx: Int) -> Binding<Bool> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.renderingConfig.library
                    .rendererSets[safe: setIdx]?.renderers[safe: itemIdx]?.enabled ?? true
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx  < cfg.renderingConfig.library.rendererSets.count,
                          itemIdx < cfg.renderingConfig.library.rendererSets[setIdx].renderers.count
                    else { return }
                    cfg.renderingConfig.library.rendererSets[setIdx].renderers[itemIdx].enabled = v
                }
            }
        )
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
        expandedSets.insert(newIdx)
    }

    private func deleteSelectedSet() {
        guard let idx = controller.selectedRendererIndex,
              let cfg = controller.projectConfig,
              idx < cfg.renderingConfig.library.rendererSets.count else { return }
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets.remove(at: idx)
        }
        expandedSets.remove(idx)
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
        expandedSets.insert(idx + 1)
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
        expandedSets.insert(setIdx)
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

// MARK: - RendererMode short label

private extension RendererMode {
    var shortLabel: String {
        switch self {
        case .points:        return "Pts"
        case .stroked:       return "Str"
        case .filled:        return "Fill"
        case .filledStroked: return "Fill+Str"
        case .brushed:       return "Brush"
        case .stenciled:     return "Stencil"
        case .stamped:       return "Stamp"
        }
    }
}
