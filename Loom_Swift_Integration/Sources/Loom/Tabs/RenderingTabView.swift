import SwiftUI
import LoomEngine
import UniformTypeIdentifiers

// MARK: - Drag/drop helpers

private enum RendererDragItem: Equatable {
    case set(name: String)
    case renderer(setName: String, name: String)
}

private enum RendererDropTarget: Equatable {
    case beforeSet(Int)
    case afterSets
    case beforeRenderer(setIdx: Int, rendererIdx: Int)
    case afterRenderers(setIdx: Int)
    case ontoSet(Int)
}

private struct RendererDropDelegate: DropDelegate {
    var validate: () -> Bool
    var entered:  () -> Void
    var exited:   () -> Void
    var perform:  () -> Bool

    func validateDrop(info: DropInfo) -> Bool { validate() }
    func dropEntered(info: DropInfo)           { entered() }
    func dropExited(info: DropInfo)            { exited() }
    func performDrop(info: DropInfo) -> Bool   { perform() }
}

// MARK: - View

struct RenderingTabView: View {

    @EnvironmentObject private var controller: AppController

    @State private var expandedSets:    Set<Int>              = []
    @State private var hiddenRenderers: Set<String>           = []
    @State private var hasAppeared                            = false
    @State private var dragItem:        RendererDragItem?     = nil
    @State private var dropTarget:      RendererDropTarget?   = nil

    private let setsToolbarHeight: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                spriteSection
                    .frame(height: geo.size.height * 0.36)

                applyBar
                    .frame(height: shouldShowApplyBar ? 32 : 0)
                    .clipped()

                Divider()

                setsSection
                    .frame(height: max(0, geo.size.height * 0.64
                                       - (shouldShowApplyBar ? 32 : 0)
                                       - 1
                                       - setsToolbarHeight))

                Divider()
                setsToolbar
                    .frame(height: setsToolbarHeight)
            }
        }
        .onAppear { autoExpand() }
        .onChange(of: controller.selectedRendererIndex) { _, idx in
            if let idx { expandedSets.insert(idx) }
        }
    }

    // MARK: - Sprite section (top)

    private var spriteSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Sprites")
            Divider()
            spriteTree
        }
    }

    private var spriteTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let cfg = controller.projectConfig {
                    let sets = cfg.spriteConfig.library.spriteSets
                    if sets.isEmpty || sets.allSatisfy({ $0.sprites.isEmpty }) {
                        emptyText("No sprites")
                    } else {
                        ForEach(sets, id: \.name) { spriteSet in
                            if !spriteSet.sprites.isEmpty {
                                spriteSetHeader(spriteSet.name, sprites: spriteSet.sprites)
                                ForEach(spriteSet.sprites, id: \.name) { sprite in
                                    spriteRow(sprite, cfg: cfg)
                                        .onTapGesture { handleSpriteSelected(sprite) }
                                }
                            }
                        }
                    }
                } else {
                    emptyText("No project open")
                }
            }
        }
    }

    private func spriteSetHeader(_ setName: String, sprites: [SpriteDef]) -> some View {
        Text(setName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spriteRow(_ sprite: SpriteDef, cfg: ProjectConfig) -> some View {
        let isSelected  = controller.renderingSelectedSpriteID == sprite.name
        let assigned    = sprite.rendererSetName.nonEmpty
        return HStack(spacing: 6) {
            Image(systemName: isSelected ? "circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            Text(sprite.name.isEmpty ? "(unnamed)" : sprite.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 2)
            if let setName = assigned {
                Text(setName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("—")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Apply bar

    private var applyBar: some View {
        Group {
            if shouldShowApplyBar, let previewName = controller.renderingPreviewSetName {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text("Previewing: \(previewName)")
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                    Button("Revert") { revertPreviewSet() }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button("Apply") { applyPreviewSet() }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                }
                .padding(.horizontal, 8)
                .background(Color.accentColor.opacity(0.08))
            }
        }
    }

    private var shouldShowApplyBar: Bool {
        guard let spriteID = controller.renderingSelectedSpriteID,
              let cfg = controller.projectConfig,
              let sprite = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID })
        else { return false }
        return controller.renderingPreviewSetName != sprite.rendererSetName.nonEmpty
    }

    // MARK: - Sets section (bottom)

    private var setsSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Renderer Sets")
            Divider()
            rendererList
        }
    }

    private var rendererList: some View {
        let sets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []
        return Group {
            if sets.isEmpty {
                emptyText(controller.projectConfig == nil ? "No project open" : "No renderer sets")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sets.indices, id: \.self) { setIdx in
                            setRow(set: sets[setIdx], setIdx: setIdx)
                            if expandedSets.contains(setIdx) {
                                ForEach(sets[setIdx].renderers.indices, id: \.self) { itemIdx in
                                    let r = sets[setIdx].renderers[itemIdx]
                                    if !hiddenRenderers.contains(rendererKey(sets[setIdx].name, r.name)) {
                                        rendererRow(renderer: r, setIdx: setIdx, itemIdx: itemIdx)
                                    }
                                }
                                if sets[setIdx].renderers.isEmpty {
                                    Text("No renderers — use + to add")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(.leading, 28)
                                        .padding(.vertical, 3)
                                }
                                afterRenderersRow(setIdx: setIdx,
                                                  count: sets[setIdx].renderers.count)
                            }
                        }
                        afterSetsRow(total: sets.count)
                    }
                }
            }
        }
    }

    // MARK: - Set row

    private func setRow(set: RendererSet, setIdx: Int) -> some View {
        let isSelected     = controller.selectedRendererIndex == setIdx
        let isExpanded     = expandedSets.contains(setIdx)
        let isPreviewed    = controller.renderingPreviewSetName == set.name
        let hiddenCount    = set.renderers.filter { hiddenRenderers.contains(rendererKey(set.name, $0.name)) }.count
        let hidableCount   = set.renderers.filter { !$0.enabled && !hiddenRenderers.contains(rendererKey(set.name, $0.name)) }.count
        let isBeforeTarget = dropTarget == .beforeSet(setIdx)
        let isOntoTarget   = dropTarget == .ontoSet(setIdx)

        return VStack(spacing: 0) {
            if isBeforeTarget { insertionLine }
            HStack(spacing: 5) {
                Button {
                    toggleExpansion(setIdx)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(set.name.isEmpty ? "(unnamed)" : set.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if isPreviewed {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                }

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

                Text("\(set.renderers.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOntoTarget
                ? Color.accentColor.opacity(0.22)
                : (isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
            .contentShape(Rectangle())
            .onTapGesture { handleSetSelected(setIdx) }
            .onDrag {
                self.dragItem = .set(name: set.name)
                return NSItemProvider(object: set.name as NSString)
            }
            .onDrop(of: [UTType.utf8PlainText], delegate: setHeaderDelegate(setIdx: setIdx))
        }
    }

    // MARK: - Renderer row

    private func rendererRow(renderer: Renderer, setIdx: Int, itemIdx: Int) -> some View {
        let isSelected    = controller.selectedRendererIndex == setIdx
                         && controller.selectedRendererItemIndex == itemIdx
        let isBeforeTarget = dropTarget == .beforeRenderer(setIdx: setIdx, rendererIdx: itemIdx)

        return VStack(spacing: 0) {
            if isBeforeTarget {
                insertionLine.padding(.leading, 22)
            }
            HStack(spacing: 5) {
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
            .onDrag {
                let sets = self.controller.projectConfig?.renderingConfig.library.rendererSets ?? []
                let setName = sets[safe: setIdx]?.name ?? ""
                self.dragItem = .renderer(setName: setName, name: renderer.name)
                return NSItemProvider(object: renderer.name as NSString)
            }
            .onDrop(of: [UTType.utf8PlainText],
                    delegate: rendererDropDelegate(setIdx: setIdx, rendererIdx: itemIdx))
        }
    }

    // MARK: - After-last drop zones

    private func afterRenderersRow(setIdx: Int, count: Int) -> some View {
        let t = RendererDropTarget.afterRenderers(setIdx: setIdx)
        return Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.utf8PlainText],
                    delegate: afterRenderersDelegate(setIdx: setIdx, count: count))
            .overlay(alignment: .bottom) {
                if dropTarget == t { insertionLine.padding(.leading, 22) }
            }
    }

    private func afterSetsRow(total: Int) -> some View {
        let t = RendererDropTarget.afterSets
        return Color.clear
            .frame(height: 10)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.utf8PlainText], delegate: afterSetsDelegate(total: total))
            .overlay(alignment: .bottom) {
                if dropTarget == t { insertionLine }
            }
    }

    // MARK: - Insertion indicator

    private var insertionLine: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 8)
    }

    // MARK: - Sets toolbar

    private var setsToolbar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Sets")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                toolbarButton("plus",                  tooltip: "New renderer set")       { addSet() }
                toolbarButton("minus",                 tooltip: "Delete renderer set")    { deleteSelectedSet() }
                    .disabled(controller.selectedRendererIndex == nil)
                toolbarButton("plus.square.on.square", tooltip: "Duplicate renderer set") { duplicateSelectedSet() }
                    .disabled(controller.selectedRendererIndex == nil)
                Spacer()
            }
            .frame(height: 28)

            HStack(spacing: 0) {
                Spacer().frame(width: 28)
                Text("Items")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                toolbarButton("plus.circle",  tooltip: "Add renderer") { addRenderer() }
                    .disabled(controller.selectedRendererIndex == nil)
                toolbarButton("minus.circle", tooltip: "Delete renderer") { deleteSelectedRenderer() }
                    .disabled(controller.selectedRendererItemIndex == nil)
                toolbarButton("arrow.triangle.2.circlepath", tooltip: "Duplicate renderer") { duplicateSelectedRenderer() }
                    .disabled(controller.selectedRendererItemIndex == nil)
                Spacer()
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 0)
    }

    private func toolbarButton(_ icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .modifier(LoomHoverHelp(tooltip))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private func emptyText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.tertiary)
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Interaction: sprites

    private func handleSpriteSelected(_ sprite: SpriteDef) {
        controller.renderingSelectedSpriteID     = sprite.name
        controller.selectedRendererItemIndex     = nil
        let assigned = sprite.rendererSetName.nonEmpty
        controller.renderingPreviewSetName = assigned
        if let assigned,
           let idx = controller.projectConfig?.renderingConfig.library.rendererSets
               .firstIndex(where: { $0.name == assigned }) {
            controller.selectedRendererIndex = idx
            expandedSets.insert(idx)
        } else {
            controller.selectedRendererIndex = nil
        }
    }

    // MARK: - Interaction: sets

    private func handleSetSelected(_ setIdx: Int) {
        if controller.selectedRendererIndex == setIdx,
           controller.selectedRendererItemIndex == nil { return }

        guard let cfg = controller.projectConfig,
              setIdx < cfg.renderingConfig.library.rendererSets.count else { return }

        let setName = cfg.renderingConfig.library.rendererSets[setIdx].name
        controller.selectedRendererIndex     = setIdx
        controller.selectedRendererItemIndex = nil
        expandedSets.insert(setIdx)

        if controller.renderingSelectedSpriteID != nil {
            controller.renderingPreviewSetName = setName
        }
    }

    private func handleItemSelected(setIdx: Int, itemIdx: Int) {
        if controller.selectedRendererIndex == setIdx,
           controller.selectedRendererItemIndex == itemIdx { return }

        guard let cfg = controller.projectConfig,
              setIdx < cfg.renderingConfig.library.rendererSets.count else { return }

        let setName = cfg.renderingConfig.library.rendererSets[setIdx].name
        controller.selectedRendererIndex     = setIdx
        controller.selectedRendererItemIndex = itemIdx
        expandedSets.insert(setIdx)

        if controller.renderingSelectedSpriteID != nil {
            controller.renderingPreviewSetName = setName
        }
    }

    private func toggleExpansion(_ setIdx: Int) {
        if expandedSets.contains(setIdx) { expandedSets.remove(setIdx) }
        else { expandedSets.insert(setIdx) }
    }

    private func autoExpand() {
        guard !hasAppeared else { return }
        hasAppeared = true
        let sets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []
        for idx in sets.indices { expandedSets.insert(idx) }
        if let idx = controller.selectedRendererIndex { expandedSets.insert(idx) }
    }

    // MARK: - Apply / Revert

    private func applyPreviewSet() {
        guard let spriteID = controller.renderingSelectedSpriteID,
              let preview  = controller.renderingPreviewSetName,
              controller.projectConfig != nil
        else { return }
        controller.updateProjectConfig { config in
            for ssIdx in config.spriteConfig.library.spriteSets.indices {
                for sIdx in config.spriteConfig.library.spriteSets[ssIdx].sprites.indices
                where config.spriteConfig.library.spriteSets[ssIdx].sprites[sIdx].name == spriteID {
                    config.spriteConfig.library.spriteSets[ssIdx].sprites[sIdx].rendererSetName = preview
                }
            }
        }
    }

    private func revertPreviewSet() {
        guard let spriteID = controller.renderingSelectedSpriteID,
              let cfg      = controller.projectConfig,
              let sprite   = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID })
        else { return }
        let assigned = sprite.rendererSetName.nonEmpty
        controller.renderingPreviewSetName = assigned
        if let assigned,
           let idx = cfg.renderingConfig.library.rendererSets.firstIndex(where: { $0.name == assigned }) {
            controller.selectedRendererIndex = idx
        } else {
            controller.selectedRendererIndex = nil
        }
        controller.selectedRendererItemIndex = nil
    }

    // MARK: - Drop delegates

    private func setHeaderDelegate(setIdx: Int) -> RendererDropDelegate {
        let beforeT = RendererDropTarget.beforeSet(setIdx)
        let ontoT   = RendererDropTarget.ontoSet(setIdx)
        return RendererDropDelegate(
            validate: { self.dragItem != nil },
            entered: {
                switch self.dragItem {
                case .set:      self.dropTarget = beforeT
                case .renderer: self.dropTarget = ontoT
                case nil:       break
                }
            },
            exited: {
                if self.dropTarget == beforeT || self.dropTarget == ontoT {
                    self.dropTarget = nil
                }
            },
            perform: {
                defer { self.dragItem = nil; self.dropTarget = nil }
                switch self.dragItem {
                case .set(let name):                     return self.dropSet(named: name, beforeSetIdx: setIdx)
                case .renderer(let setName, let rName):  return self.dropRenderer(fromSet: setName, named: rName, ontoSetIdx: setIdx)
                case nil:                                return false
                }
            }
        )
    }

    private func rendererDropDelegate(setIdx: Int, rendererIdx: Int) -> RendererDropDelegate {
        let t = RendererDropTarget.beforeRenderer(setIdx: setIdx, rendererIdx: rendererIdx)
        return RendererDropDelegate(
            validate: { if case .renderer = self.dragItem { return true }; return false },
            entered:  { self.dropTarget = t },
            exited:   { if self.dropTarget == t { self.dropTarget = nil } },
            perform: {
                guard case .renderer(let setName, let rName) = self.dragItem else { return false }
                defer { self.dragItem = nil; self.dropTarget = nil }
                return self.dropRenderer(fromSet: setName, named: rName,
                                         toSetIdx: setIdx, beforeIdx: rendererIdx)
            }
        )
    }

    private func afterRenderersDelegate(setIdx: Int, count: Int) -> RendererDropDelegate {
        let t = RendererDropTarget.afterRenderers(setIdx: setIdx)
        return RendererDropDelegate(
            validate: { if case .renderer = self.dragItem { return true }; return false },
            entered:  { self.dropTarget = t },
            exited:   { if self.dropTarget == t { self.dropTarget = nil } },
            perform: {
                guard case .renderer(let setName, let rName) = self.dragItem else { return false }
                defer { self.dragItem = nil; self.dropTarget = nil }
                return self.dropRenderer(fromSet: setName, named: rName,
                                         toSetIdx: setIdx, beforeIdx: count)
            }
        )
    }

    private func afterSetsDelegate(total: Int) -> RendererDropDelegate {
        let t = RendererDropTarget.afterSets
        return RendererDropDelegate(
            validate: { if case .set = self.dragItem { return true }; return false },
            entered:  { self.dropTarget = t },
            exited:   { if self.dropTarget == t { self.dropTarget = nil } },
            perform: {
                guard case .set(let name) = self.dragItem else { return false }
                defer { self.dragItem = nil; self.dropTarget = nil }
                return self.dropSet(named: name, beforeSetIdx: total)
            }
        )
    }

    // MARK: - Drop mutations

    private func dropSet(named name: String, beforeSetIdx target: Int) -> Bool {
        guard let sets = controller.projectConfig?.renderingConfig.library.rendererSets,
              let fromIdx = sets.firstIndex(where: { $0.name == name })
        else { return false }
        guard target != fromIdx && target != fromIdx + 1 else { return false }

        controller.updateProjectConfig { cfg in
            var s = cfg.renderingConfig.library.rendererSets
            let set = s.remove(at: fromIdx)
            let insertAt = fromIdx < target ? target - 1 : target
            s.insert(set, at: max(0, min(insertAt, s.count)))
            cfg.renderingConfig.library.rendererSets = s
        }
        let newSets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []
        controller.selectedRendererIndex = newSets.firstIndex(where: { $0.name == name })
        controller.selectedRendererItemIndex = nil
        return true
    }

    private func dropRenderer(fromSet srcSetName: String, named rName: String,
                               ontoSetIdx toSetIdx: Int) -> Bool {
        guard let sets = controller.projectConfig?.renderingConfig.library.rendererSets,
              let srcSetIdx = sets.firstIndex(where: { $0.name == srcSetName }),
              let srcItemIdx = sets[srcSetIdx].renderers.firstIndex(where: { $0.name == rName }),
              toSetIdx < sets.count
        else { return false }
        let toCount = sets[toSetIdx].renderers.count
        if srcSetIdx == toSetIdx, toCount > 0, srcItemIdx == toCount - 1 { return false }

        controller.updateProjectConfig { cfg in
            let r = cfg.renderingConfig.library.rendererSets[srcSetIdx].renderers.remove(at: srcItemIdx)
            cfg.renderingConfig.library.rendererSets[toSetIdx].renderers.append(r)
        }
        controller.selectedRendererIndex     = toSetIdx
        controller.selectedRendererItemIndex = (controller.projectConfig?.renderingConfig.library
            .rendererSets[safe: toSetIdx]?.renderers.count ?? 1) - 1
        expandedSets.insert(toSetIdx)
        return true
    }

    private func dropRenderer(fromSet srcSetName: String, named rName: String,
                               toSetIdx: Int, beforeIdx: Int) -> Bool {
        guard let sets = controller.projectConfig?.renderingConfig.library.rendererSets,
              let srcSetIdx = sets.firstIndex(where: { $0.name == srcSetName }),
              let srcItemIdx = sets[srcSetIdx].renderers.firstIndex(where: { $0.name == rName }),
              toSetIdx < sets.count
        else { return false }
        if srcSetIdx == toSetIdx,
           beforeIdx == srcItemIdx || beforeIdx == srcItemIdx + 1 { return false }

        controller.updateProjectConfig { cfg in
            let r = cfg.renderingConfig.library.rendererSets[srcSetIdx].renderers.remove(at: srcItemIdx)
            var insertIdx = beforeIdx
            if srcSetIdx == toSetIdx && srcItemIdx < beforeIdx { insertIdx -= 1 }
            let count = cfg.renderingConfig.library.rendererSets[toSetIdx].renderers.count
            cfg.renderingConfig.library.rendererSets[toSetIdx].renderers
                .insert(r, at: max(0, min(insertIdx, count)))
        }
        let newSets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []
        let newItemIdx = newSets[safe: toSetIdx]?.renderers.firstIndex(where: { $0.name == rName })
        controller.selectedRendererIndex     = toSetIdx
        controller.selectedRendererItemIndex = newItemIdx
        expandedSets.insert(toSetIdx)
        return true
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

        // If a sprite is selected with no renderer set, auto-apply the new set
        if let spriteID = controller.renderingSelectedSpriteID,
           let cfg2 = controller.projectConfig,
           let sprite = cfg2.spriteConfig.library.allSprites.first(where: { $0.name == spriteID }),
           sprite.rendererSetName.isEmpty {
            controller.renderingPreviewSetName = name
            applyPreviewSet()
        } else {
            controller.renderingPreviewSetName = name
        }
    }

    private func deleteSelectedSet() {
        guard let idx = controller.selectedRendererIndex,
              let cfg = controller.projectConfig,
              idx < cfg.renderingConfig.library.rendererSets.count else { return }
        let deletedName = cfg.renderingConfig.library.rendererSets[idx].name
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets.remove(at: idx)
        }
        expandedSets.remove(idx)
        let remaining = controller.projectConfig?.renderingConfig.library.rendererSets.count ?? 0
        controller.selectedRendererIndex     = remaining > 0 ? min(idx, remaining - 1) : nil
        controller.selectedRendererItemIndex = nil
        if controller.renderingPreviewSetName == deletedName {
            controller.renderingPreviewSetName = nil
        }
    }

    private func duplicateSelectedSet() {
        guard let idx = controller.selectedRendererIndex,
              let cfg = controller.projectConfig,
              idx < cfg.renderingConfig.library.rendererSets.count else { return }
        var copy = cfg.renderingConfig.library.rendererSets[idx]
        copy.name = uniqueName(base: "\(copy.name)_copy",
                               existing: cfg.renderingConfig.library.rendererSets.map(\.name))
        let copyName = copy.name
        controller.updateProjectConfig { c in
            c.renderingConfig.library.rendererSets.insert(copy, at: idx + 1)
        }
        controller.selectedRendererIndex     = idx + 1
        controller.selectedRendererItemIndex = nil
        expandedSets.insert(idx + 1)
        if controller.renderingSelectedSpriteID != nil {
            controller.renderingPreviewSetName = copyName
        }
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

    private func rendererKey(_ setName: String, _ rendererName: String) -> String { "\(setName)\t\(rendererName)" }

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
