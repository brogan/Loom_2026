import SwiftUI
import LoomEngine
import UniformTypeIdentifiers

// MARK: - Drag item tracking

private enum LoomDragItem: Equatable {
    case set(name: String)
    case sprite(name: String)
}

private enum SpriteDropTarget: Equatable {
    case beforeSet(Int)
    case afterSets
    case beforeSprite(setIdx: Int, spriteIdx: Int)
    case afterSprites(setIdx: Int)
    case ontoSet(Int)
}

// Single reusable delegate type; all logic supplied as closures.
private struct LoomDropDelegate: DropDelegate {
    var validate: () -> Bool
    var entered:  () -> Void
    var exited:   () -> Void
    var perform:  () -> Bool

    func validateDrop(info: DropInfo) -> Bool { validate() }
    func dropEntered(info: DropInfo)           { entered() }
    func dropExited(info: DropInfo)            { exited() }
    func performDrop(info: DropInfo) -> Bool   { perform() }
}

// MARK: - InheritToggleStyle

private struct InheritToggleStyle: ToggleStyle {
    let label: String
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .frame(width: 14, height: 14)
                .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(configuration.isOn ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(configuration.isOn ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View

struct SpritesTabView: View {

    @EnvironmentObject private var controller: AppController

    @State private var expandedSets:       Set<String>   = []
    @State private var hiddenSprites:      Set<String>   = []
    @State private var hasAppeared                       = false
    @State private var selectedSetIndex:   Int?          = nil
    @State private var dragItem:           LoomDragItem? = nil
    @State private var dropTarget:         SpriteDropTarget? = nil
    @State private var filterText:         String        = ""
    @State private var showingRenameAlert  = false
    @State private var renameText          = ""
    @State private var renamingSetIdx:     Int?          = nil
    @State private var renamingSpriteName: String?       = nil
    @State private var renamingSceneID:    UUID?         = nil
    @State private var showingNewSceneAlert = false
    @State private var newSceneName         = ""
    @State private var sceneSectionExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            spriteList
            Divider()
            toolbar
            Divider()
            sceneSection
        }
        .onAppear { autoExpand() }
        .alert("Rename", isPresented: $showingRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) {
                renamingSetIdx = nil; renamingSpriteName = nil; renamingSceneID = nil
            }
        }
        .alert("New Scene", isPresented: $showingNewSceneAlert) {
            TextField("Scene name", text: $newSceneName)
            Button("Add") { commitAddScene() }
            Button("Cancel", role: .cancel) { newSceneName = "" }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $filterText)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .iconHitArea()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            Divider()
        }
    }

    // MARK: - Filter model

    private struct DisplayEntry {
        let setIdx:       Int
        let set:          SpriteSet
        let spriteIndices: [Int]
    }

    private var displayedSets: [DisplayEntry] {
        let sets = controller.projectConfig?.spriteConfig.library.spriteSets ?? []
        let q    = filterText.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return sets.enumerated().map {
                DisplayEntry(setIdx: $0.offset, set: $0.element, spriteIndices: Array($0.element.sprites.indices))
            }
        }
        return sets.enumerated().compactMap { offset, set in
            let setMatches     = set.name.localizedCaseInsensitiveContains(q)
            let spriteMatches  = set.sprites.indices.filter { set.sprites[$0].name.localizedCaseInsensitiveContains(q) }
            if setMatches      { return DisplayEntry(setIdx: offset, set: set, spriteIndices: Array(set.sprites.indices)) }
            if !spriteMatches.isEmpty { return DisplayEntry(setIdx: offset, set: set, spriteIndices: spriteMatches) }
            return nil
        }
    }

    // MARK: - Tree display model

    private struct SpriteDisplayNode {
        var setIdx:    Int
        var spriteIdx: Int
        var sprite:    SpriteDef
        var depth:     Int
    }

    private func buildDisplayNodes(for entry: DisplayEntry) -> [SpriteDisplayNode] {
        let sprites = entry.set.sprites
        var nameToIdx: [String: Int] = [:]
        for idx in entry.spriteIndices { nameToIdx[sprites[idx].name] = idx }

        let roots = entry.spriteIndices.filter { idx in
            guard let pn = sprites[idx].parentName else { return true }
            return nameToIdx[pn] == nil
        }
        var result:  [SpriteDisplayNode] = []
        var visited = Set<Int>()

        func visit(_ idx: Int, depth: Int) {
            guard !visited.contains(idx) else { return }
            visited.insert(idx)
            result.append(SpriteDisplayNode(setIdx: entry.setIdx, spriteIdx: idx,
                                             sprite: sprites[idx], depth: depth))
            let children = entry.spriteIndices.filter {
                sprites[$0].parentName == sprites[idx].name && $0 != idx
            }
            for child in children { visit(child, depth: depth + 1) }
        }
        for root in roots { visit(root, depth: 0) }
        for idx in entry.spriteIndices where !visited.contains(idx) {
            result.append(SpriteDisplayNode(setIdx: entry.setIdx, spriteIdx: idx,
                                             sprite: sprites[idx], depth: 0))
        }
        return result
    }

    // MARK: - List

    private var spriteList: some View {
        let allSets     = controller.projectConfig?.spriteConfig.library.spriteSets ?? []
        let entries     = displayedSets
        let isFiltering = !filterText.trimmingCharacters(in: .whitespaces).isEmpty
        return Group {
            if allSets.isEmpty {
                emptyState(controller.projectConfig == nil ? "No project open" : "No sprite sets")
            } else if entries.isEmpty {
                emptyState("No matches for \"\(filterText.trimmingCharacters(in: .whitespaces))\"")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(entries, id: \.setIdx) { entry in
                            let isExpanded = isFiltering
                                || expandedSets.contains(entry.set.name)
                                || entry.set.sprites.contains(where: { $0.name == controller.selectedSpriteID })
                            setRow(set: entry.set, setIdx: entry.setIdx)
                            if isExpanded {
                                let filteredEntry = DisplayEntry(
                                    setIdx: entry.setIdx, set: entry.set,
                                    spriteIndices: isFiltering ? entry.spriteIndices
                                        : entry.spriteIndices.filter {
                                            !hiddenSprites.contains(spriteKey(entry.set.name, entry.set.sprites[$0].name))
                                        })
                                let nodes = buildDisplayNodes(for: filteredEntry)
                                ForEach(nodes, id: \.spriteIdx) { node in
                                    spriteTreeRow(node: node)
                                }
                                if !isFiltering {
                                    afterSpritesRow(setIdx: entry.setIdx, count: entry.set.sprites.count)
                                    if entry.spriteIndices.isEmpty {
                                        Text("No sprites — use + to add")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .padding(.leading, 28)
                                            .padding(.vertical, 3)
                                    }
                                }
                            }
                        }
                        if !isFiltering { afterSetsRow(total: allSets.count) }
                    }
                }
            }
        }
    }

    // MARK: - Set row

    private func setRow(set: SpriteSet, setIdx: Int) -> some View {
        let isFiltering    = !filterText.trimmingCharacters(in: .whitespaces).isEmpty
        let isSelected     = selectedSetIndex == setIdx && controller.selectedSpriteID == nil
        let isExpanded     = isFiltering || expandedSets.contains(set.name)
        let isBeforeTarget = !isFiltering && dropTarget == .beforeSet(setIdx)
        let isOntoTarget   = !isFiltering && dropTarget == .ontoSet(setIdx)
        let hiddenCount    = isFiltering ? 0 : set.sprites.filter { hiddenSprites.contains(spriteKey(set.name, $0.name)) }.count
        let hidableCount   = isFiltering ? 0 : set.sprites.filter { !$0.enabled && !hiddenSprites.contains(spriteKey(set.name, $0.name)) }.count

        return HStack(spacing: 5) {
            Button { if !isFiltering { toggleExpansion(set.name) } } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(set.name.isEmpty ? "(unnamed)" : set.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    renamingSetIdx     = setIdx
                    renamingSpriteName = nil
                    renameText         = set.name
                    showingRenameAlert = true
                }

            Spacer(minLength: 2)

            if hiddenCount > 0 {
                Button {
                    for sprite in set.sprites { hiddenSprites.remove(spriteKey(set.name, sprite.name)) }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "eye.slash").font(.system(size: 9))
                        Text("\(hiddenCount)").font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Restore \(hiddenCount) hidden sprite\(hiddenCount == 1 ? "" : "s")")
            } else if hidableCount > 0 {
                Button {
                    for sprite in set.sprites where !sprite.enabled {
                        hiddenSprites.insert(spriteKey(set.name, sprite.name))
                    }
                } label: {
                    Image(systemName: "eye").font(.system(size: 9)).foregroundStyle(.tertiary)
                        .iconHitArea()
                }
                .buttonStyle(.plain)
                .help("Hide \(hidableCount) disabled sprite\(hidableCount == 1 ? "" : "s")")
            }

            Text("\(set.sprites.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { handleSetSelected(setIdx: setIdx, setName: set.name) }
        .onDrag {
            guard !isFiltering else { return NSItemProvider() }
            self.dragItem = .set(name: set.name)
            return NSItemProvider(object: set.name as NSString)
        }
        .onDrop(of: [UTType.utf8PlainText], delegate: setHeaderDelegate(setIdx: setIdx))
        .overlay(alignment: .top) {
            if isBeforeTarget { insertionLine }
        }
        .overlay {
            if isOntoTarget {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .padding(.horizontal, 3).padding(.vertical, 1)
            }
        }
    }

    // MARK: - Sprite row

    private func spriteRow(sprite: SpriteDef, setIdx: Int, itemIdx: Int) -> some View {
        let isFiltering    = !filterText.trimmingCharacters(in: .whitespaces).isEmpty
        let isSelected     = controller.selectedSpriteID == sprite.name
        let isBeforeTarget = !isFiltering && dropTarget == .beforeSprite(setIdx: setIdx, spriteIdx: itemIdx)

        return HStack(spacing: 5) {
            Spacer().frame(width: 22)
            Text(sprite.name.isEmpty ? "(unnamed)" : sprite.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .opacity(sprite.enabled ? 1.0 : 0.38)
                .onTapGesture(count: 2) {
                    renamingSpriteName = sprite.name
                    renamingSetIdx     = nil
                    renameText         = sprite.name
                    showingRenameAlert = true
                }
            Spacer(minLength: 2)
            if sprite.animation.enabled {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .opacity(sprite.enabled ? 1.0 : 0.38)
            }
            Toggle("", isOn: bindSpriteEnabled(setIdx: setIdx, itemIdx: itemIdx))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .scaleEffect(0.82)
                .frame(width: 18)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { handleSpriteSelected(setIdx: setIdx, itemIdx: itemIdx, sprite: sprite) }
        .onDrag {
            guard !isFiltering else { return NSItemProvider() }
            self.dragItem = .sprite(name: sprite.name)
            return NSItemProvider(object: sprite.name as NSString)
        }
        .onDrop(of: [UTType.utf8PlainText], delegate: spriteDropDelegate(setIdx: setIdx, spriteIdx: itemIdx))
        .overlay(alignment: .top) {
            if isBeforeTarget { insertionLine.padding(.leading, 22) }
        }
    }

    // MARK: - Sprite tree row

    private func spriteTreeRow(node: SpriteDisplayNode) -> some View {
        let sprite     = node.sprite
        let setIdx     = node.setIdx
        let spriteIdx  = node.spriteIdx
        let isFiltering    = !filterText.trimmingCharacters(in: .whitespaces).isEmpty
        let isSelected     = controller.selectedSpriteID == sprite.name
        let isBeforeTarget = !isFiltering && dropTarget == .beforeSprite(setIdx: setIdx, spriteIdx: spriteIdx)
        let indent         = CGFloat(node.depth) * 14 + 22

        return HStack(spacing: 4) {
            Spacer().frame(width: indent)
            if node.depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
            }
            Text(sprite.name.isEmpty ? "(unnamed)" : sprite.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .opacity(sprite.enabled ? 1.0 : 0.38)
                .onTapGesture(count: 2) {
                    renamingSpriteName = sprite.name
                    renamingSetIdx     = nil
                    renameText         = sprite.name
                    showingRenameAlert = true
                }
            Spacer(minLength: 2)
            if sprite.parentName != nil {
                Toggle("P", isOn: inheritBinding(setIdx: setIdx, spriteIdx: spriteIdx, kp: \.inheritMask.position))
                    .labelsHidden()
                    .toggleStyle(InheritToggleStyle(label: "P"))
                Toggle("R", isOn: inheritBinding(setIdx: setIdx, spriteIdx: spriteIdx, kp: \.inheritMask.rotation))
                    .labelsHidden()
                    .toggleStyle(InheritToggleStyle(label: "R"))
                Toggle("S", isOn: inheritBinding(setIdx: setIdx, spriteIdx: spriteIdx, kp: \.inheritMask.scale))
                    .labelsHidden()
                    .toggleStyle(InheritToggleStyle(label: "S"))
            }
            if sprite.animation.enabled {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .opacity(sprite.enabled ? 1.0 : 0.38)
            }
            Toggle("", isOn: bindSpriteEnabled(setIdx: setIdx, itemIdx: spriteIdx))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .scaleEffect(0.82)
                .frame(width: 18)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { handleSpriteSelected(setIdx: setIdx, itemIdx: spriteIdx, sprite: sprite) }
        .onDrag {
            guard !isFiltering else { return NSItemProvider() }
            self.dragItem = .sprite(name: sprite.name)
            return NSItemProvider(object: sprite.name as NSString)
        }
        .onDrop(of: [UTType.utf8PlainText], delegate: spriteDropDelegate(setIdx: setIdx, spriteIdx: spriteIdx))
        .overlay(alignment: .top) {
            if isBeforeTarget { insertionLine.padding(.leading, indent) }
        }
    }

    // MARK: - "After last" drop zones

    private func afterSpritesRow(setIdx: Int, count: Int) -> some View {
        let t = SpriteDropTarget.afterSprites(setIdx: setIdx)
        return Color.clear
            .frame(height: 8)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.utf8PlainText], delegate: afterSpritesDelegate(setIdx: setIdx, count: count))
            .overlay(alignment: .bottom) {
                if dropTarget == t { insertionLine.padding(.leading, 22) }
            }
    }

    private func afterSetsRow(total: Int) -> some View {
        let t = SpriteDropTarget.afterSets
        return Color.clear
            .frame(height: 10)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.utf8PlainText], delegate: afterSetsDelegate(total: total))
            .overlay(alignment: .bottom) {
                if dropTarget == t { insertionLine }
            }
    }

    // MARK: - Scene section

    private var sceneSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { sceneSectionExpanded.toggle() }
                } label: {
                    Image(systemName: sceneSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                        .frame(minHeight: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("SCENES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if sceneSectionExpanded {
                    Button {
                        let existing = controller.projectConfig?.scenes.map(\.name) ?? []
                        newSceneName = uniqueName(base: "Scene", existing: existing)
                        showingNewSceneAlert = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .iconHitArea()
                    }
                    .buttonStyle(.plain)
                    .help("Add scene")
                    .disabled(controller.projectConfig == nil)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 24)

            if sceneSectionExpanded {
                let scenes = controller.projectConfig?.scenes ?? []
                if scenes.isEmpty {
                    Text("No scenes")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    List {
                        ForEach(scenes) { scene in
                            sceneRow(scene: scene)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .onMove { from, to in controller.moveScene(from: from, to: to) }
                    }
                    .listStyle(.plain)
                    .frame(height: min(CGFloat(scenes.count) * 26 + 2, 130))
                }
            }
        }
    }

    private func sceneRow(scene: LoomScene) -> some View {
        let isActive = controller.projectConfig?.activeSceneID == scene.id
        return HStack(spacing: 5) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 9))
                .foregroundStyle(isActive ? Color.accentColor : Color.clear)
                .frame(width: 12)
            Text(scene.name)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    renamingSceneID    = scene.id
                    renamingSetIdx     = nil
                    renamingSpriteName = nil
                    renameText         = scene.name
                    showingRenameAlert = true
                }
            Spacer(minLength: 2)
            Button {
                controller.deleteScene(id: scene.id)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .iconHitArea()
            }
            .buttonStyle(.plain)
            .disabled((controller.projectConfig?.scenes.count ?? 0) <= 1)
            .help("Delete scene")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isActive else { return }
            controller.switchScene(to: scene.id)
        }
    }

    private func commitAddScene() {
        let name = newSceneName.trimmingCharacters(in: .whitespaces)
        newSceneName = ""
        guard !name.isEmpty else { return }
        controller.addScene(name: name)
    }

    // MARK: - Insertion indicator

    private var insertionLine: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 8)
    }

    // MARK: - Drop delegates

    // Set header: dispatches on dragItem kind.
    private func setHeaderDelegate(setIdx: Int) -> LoomDropDelegate {
        let beforeT = SpriteDropTarget.beforeSet(setIdx)
        let ontoT   = SpriteDropTarget.ontoSet(setIdx)
        return LoomDropDelegate(
            validate: { self.dragItem != nil },
            entered: {
                switch self.dragItem {
                case .set:    self.dropTarget = beforeT
                case .sprite: self.dropTarget = ontoT
                case nil:     break
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
                case .set(let name):    return self.dropSet(named: name, beforeSetIdx: setIdx)
                case .sprite(let name): return self.dropSprite(named: name, ontoSetIdx: setIdx)
                case nil:               return false
                }
            }
        )
    }

    // Sprite row: only accepts sprite drags.
    private func spriteDropDelegate(setIdx: Int, spriteIdx: Int) -> LoomDropDelegate {
        let t = SpriteDropTarget.beforeSprite(setIdx: setIdx, spriteIdx: spriteIdx)
        return LoomDropDelegate(
            validate: { if case .sprite = self.dragItem { return true }; return false },
            entered:  { self.dropTarget = t },
            exited:   { if self.dropTarget == t { self.dropTarget = nil } },
            perform: {
                guard case .sprite(let name) = self.dragItem else { return false }
                defer { self.dragItem = nil; self.dropTarget = nil }
                return self.dropSprite(named: name, beforeSetIdx: setIdx, spriteIdx: spriteIdx)
            }
        )
    }

    // After-sprites zone: only accepts sprite drags.
    private func afterSpritesDelegate(setIdx: Int, count: Int) -> LoomDropDelegate {
        let t = SpriteDropTarget.afterSprites(setIdx: setIdx)
        return LoomDropDelegate(
            validate: { if case .sprite = self.dragItem { return true }; return false },
            entered:  { self.dropTarget = t },
            exited:   { if self.dropTarget == t { self.dropTarget = nil } },
            perform: {
                guard case .sprite(let name) = self.dragItem else { return false }
                defer { self.dragItem = nil; self.dropTarget = nil }
                return self.dropSprite(named: name, beforeSetIdx: setIdx, spriteIdx: count)
            }
        )
    }

    // After-sets zone: only accepts set drags.
    private func afterSetsDelegate(total: Int) -> LoomDropDelegate {
        let t = SpriteDropTarget.afterSets
        return LoomDropDelegate(
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

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("plus",                        tooltip: "New sprite set")        { addSet() }
            toolbarButton("minus",                       tooltip: "Delete sprite set")     { deleteSelectedSet() }
                .disabled(selectedSetIndex == nil)
            toolbarButton("plus.square.on.square",       tooltip: "Duplicate sprite set")  { duplicateSelectedSet() }
                .disabled(selectedSetIndex == nil)

            Divider().frame(height: 14).padding(.horizontal, 4)

            toolbarButton("plus.circle",                 tooltip: "Add sprite — creates a blank entry. Leave Shape Set/Name empty to use it as a container/group root: assign other sprites to it via their Parent picker.")            { addSprite() }
                .disabled(selectedSetIndex == nil)
            toolbarButton("minus.circle",                tooltip: "Delete sprite")         { deleteSelectedSprite() }
                .disabled(controller.selectedSpriteID == nil)
            toolbarButton("arrow.triangle.2.circlepath", tooltip: "Duplicate sprite")      { duplicateSelectedSprite() }
                .disabled(controller.selectedSpriteID == nil)

            Divider().frame(height: 14).padding(.horizontal, 4)

            toolbarButton("pencil",                      tooltip: "Rename selection")      { beginRename() }
                .disabled(controller.selectedSpriteID == nil && selectedSetIndex == nil)

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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .modifier(LoomHoverHelp(tooltip))
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.tertiary)
            .font(.caption)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Interaction

    private func handleSetSelected(setIdx: Int, setName: String) {
        if selectedSetIndex == setIdx, controller.selectedSpriteID == nil {
            toggleExpansion(setName); return
        }
        selectedSetIndex            = setIdx
        controller.selectedSpriteID = nil
        expandedSets.insert(setName)
    }

    private func handleSpriteSelected(setIdx: Int, itemIdx: Int, sprite: SpriteDef) {
        selectedSetIndex            = setIdx
        controller.selectedSpriteID = sprite.name
        if let sn = setName(at: setIdx) { expandedSets.insert(sn) }
    }

    private func toggleExpansion(_ setName: String) {
        if expandedSets.contains(setName) { expandedSets.remove(setName) }
        else { expandedSets.insert(setName) }
    }

    private func autoExpand() {
        guard !hasAppeared else { return }
        hasAppeared = true
        let sets = controller.projectConfig?.spriteConfig.library.spriteSets ?? []
        for set in sets { expandedSets.insert(set.name) }
        if let name = controller.selectedSpriteID,
           let (setIdx, _) = location(ofSprite: name),
           let sn = setName(at: setIdx) {
            selectedSetIndex = setIdx
            expandedSets.insert(sn)
        }
    }

    // MARK: - Drop mutations

    private func dropSet(named name: String, beforeSetIdx target: Int) -> Bool {
        guard let sets = controller.projectConfig?.spriteConfig.library.spriteSets,
              let fromIdx = sets.firstIndex(where: { $0.name == name })
        else { return false }
        guard target != fromIdx && target != fromIdx + 1 else { return false }

        controller.updateProjectConfig { cfg in
            var s = cfg.spriteConfig.library.spriteSets
            let set = s.remove(at: fromIdx)
            let insertAt = fromIdx < target ? target - 1 : target
            s.insert(set, at: max(0, min(insertAt, s.count)))
            cfg.spriteConfig.library.spriteSets = s
        }
        let newSets = controller.projectConfig?.spriteConfig.library.spriteSets ?? []
        selectedSetIndex = newSets.firstIndex(where: { $0.name == name })
        return true
    }

    private func dropSprite(named name: String, beforeSetIdx targetSetIdx: Int, spriteIdx targetSpriteIdx: Int) -> Bool {
        guard let (fromSetIdx, _) = location(ofSprite: name),
              let sets = controller.projectConfig?.spriteConfig.library.spriteSets,
              targetSetIdx < sets.count
        else { return false }

        let srcSprites    = sets[fromSetIdx].sprites
        let groupNames    = subtreeNames(of: name, in: srcSprites)
        let groupIndices  = srcSprites.indices.filter { groupNames.contains(srcSprites[$0].name) }
        guard !groupIndices.isEmpty else { return false }

        // No-op for single sprite: target is immediately before or after it
        if groupIndices.count == 1 {
            let fi = groupIndices[0]
            if fromSetIdx == targetSetIdx,
               targetSpriteIdx == fi || targetSpriteIdx == fi + 1 { return false }
        }

        let targetSetName = sets[targetSetIdx].name
        controller.updateProjectConfig { cfg in
            var src = cfg.spriteConfig.library.spriteSets[fromSetIdx].sprites
            let group = groupIndices.map { src[$0] }
            for idx in groupIndices.reversed() { src.remove(at: idx) }
            cfg.spriteConfig.library.spriteSets[fromSetIdx].sprites = src

            var dst = cfg.spriteConfig.library.spriteSets[targetSetIdx].sprites
            let removedBefore = fromSetIdx == targetSetIdx
                ? groupIndices.filter { $0 < targetSpriteIdx }.count : 0
            let insertIdx = max(0, min(targetSpriteIdx - removedBefore, dst.count))
            for (offset, sprite) in group.enumerated() {
                dst.insert(sprite, at: insertIdx + offset)
            }
            cfg.spriteConfig.library.spriteSets[targetSetIdx].sprites = dst
        }
        let newSets = controller.projectConfig?.spriteConfig.library.spriteSets ?? []
        selectedSetIndex = newSets.firstIndex(where: { $0.name == targetSetName })
        controller.selectedSpriteID = name
        expandedSets.insert(targetSetName)
        return true
    }

    private func dropSprite(named name: String, ontoSetIdx targetSetIdx: Int) -> Bool {
        guard let (fromSetIdx, _) = location(ofSprite: name),
              let sets = controller.projectConfig?.spriteConfig.library.spriteSets,
              targetSetIdx < sets.count
        else { return false }

        let srcSprites   = sets[fromSetIdx].sprites
        let groupNames   = subtreeNames(of: name, in: srcSprites)
        let groupIndices = srcSprites.indices.filter { groupNames.contains(srcSprites[$0].name) }
        guard !groupIndices.isEmpty else { return false }

        // No-op: same set and group is already at the tail
        if fromSetIdx == targetSetIdx, groupIndices.last == srcSprites.count - 1 { return false }

        let targetSetName = sets[targetSetIdx].name
        controller.updateProjectConfig { cfg in
            var src = cfg.spriteConfig.library.spriteSets[fromSetIdx].sprites
            let group = groupIndices.map { src[$0] }
            for idx in groupIndices.reversed() { src.remove(at: idx) }
            cfg.spriteConfig.library.spriteSets[fromSetIdx].sprites = src
            cfg.spriteConfig.library.spriteSets[targetSetIdx].sprites.append(contentsOf: group)
        }
        let newSets = controller.projectConfig?.spriteConfig.library.spriteSets ?? []
        selectedSetIndex = newSets.firstIndex(where: { $0.name == targetSetName })
        controller.selectedSpriteID = name
        expandedSets.insert(targetSetName)
        return true
    }

    // MARK: - CRUD: sets

    private func addSet() {
        guard let cfg = controller.projectConfig else { return }
        let name = uniqueName(base: "new_set",
                              existing: cfg.spriteConfig.library.spriteSets.map(\.name))
        controller.updateProjectConfig { c in
            c.spriteConfig.library.spriteSets.append(SpriteSet(name: name))
        }
        let newIdx = (controller.projectConfig?.spriteConfig.library.spriteSets.count ?? 1) - 1
        selectedSetIndex            = newIdx
        controller.selectedSpriteID = nil
        expandedSets.insert(name)
    }

    private func deleteSelectedSet() {
        guard let idx = selectedSetIndex,
              let cfg = controller.projectConfig,
              idx < cfg.spriteConfig.library.spriteSets.count else { return }
        let sn = cfg.spriteConfig.library.spriteSets[idx].name
        if let name = controller.selectedSpriteID,
           let (si, _) = location(ofSprite: name), si == idx {
            controller.selectedSpriteID = nil
        }
        controller.updateProjectConfig { c in c.spriteConfig.library.spriteSets.remove(at: idx) }
        expandedSets.remove(sn)
        let remaining = controller.projectConfig?.spriteConfig.library.spriteSets.count ?? 0
        selectedSetIndex = remaining > 0 ? min(idx, remaining - 1) : nil
    }

    private func duplicateSelectedSet() {
        guard let idx = selectedSetIndex,
              let cfg = controller.projectConfig,
              idx < cfg.spriteConfig.library.spriteSets.count else { return }
        var copy = cfg.spriteConfig.library.spriteSets[idx]
        copy.name = uniqueName(base: "\(copy.name)_copy",
                               existing: cfg.spriteConfig.library.spriteSets.map(\.name))
        let allExisting = cfg.spriteConfig.library.spriteSets.flatMap { $0.sprites.map(\.name) }
        var usedNames = allExisting
        copy.sprites = copy.sprites.map { sprite in
            var s = sprite
            s.name = uniqueName(base: "\(sprite.name)_copy", existing: usedNames)
            usedNames.append(s.name)
            return s
        }
        controller.updateProjectConfig { c in
            c.spriteConfig.library.spriteSets.insert(copy, at: idx + 1)
        }
        selectedSetIndex            = idx + 1
        controller.selectedSpriteID = nil
        expandedSets.insert(copy.name)
    }

    // MARK: - CRUD: sprites

    private func addSprite() {
        guard let setIdx = selectedSetIndex,
              let cfg    = controller.projectConfig,
              setIdx < cfg.spriteConfig.library.spriteSets.count else { return }
        let allExisting = cfg.spriteConfig.library.spriteSets.flatMap { $0.sprites.map(\.name) }
        let name = uniqueName(base: "sprite", existing: allExisting)
        controller.updateProjectConfig { c in
            c.spriteConfig.library.spriteSets[setIdx].sprites.append(SpriteDef(name: name))
        }
        controller.selectedSpriteID = name
        if let sn = setName(at: setIdx) { expandedSets.insert(sn) }
    }

    private func deleteSelectedSprite() {
        guard let name = controller.selectedSpriteID,
              let (setIdx, itemIdx) = location(ofSprite: name),
              let cfg = controller.projectConfig,
              setIdx  < cfg.spriteConfig.library.spriteSets.count,
              itemIdx < cfg.spriteConfig.library.spriteSets[setIdx].sprites.count else { return }
        controller.updateProjectConfig { c in
            c.spriteConfig.library.spriteSets[setIdx].sprites.remove(at: itemIdx)
        }
        let remaining = controller.projectConfig?.spriteConfig.library
            .spriteSets[safe: setIdx]?.sprites ?? []
        controller.selectedSpriteID = remaining.isEmpty
            ? nil : remaining[min(itemIdx, remaining.count - 1)].name
    }

    private func duplicateSelectedSprite() {
        guard let name = controller.selectedSpriteID,
              let (setIdx, itemIdx) = location(ofSprite: name),
              let cfg = controller.projectConfig,
              setIdx  < cfg.spriteConfig.library.spriteSets.count,
              itemIdx < cfg.spriteConfig.library.spriteSets[setIdx].sprites.count else { return }
        let allExisting = cfg.spriteConfig.library.spriteSets.flatMap { $0.sprites.map(\.name) }
        var copy = cfg.spriteConfig.library.spriteSets[setIdx].sprites[itemIdx]
        copy.name = uniqueName(base: "\(copy.name)_copy", existing: allExisting)
        controller.updateProjectConfig { c in
            c.spriteConfig.library.spriteSets[setIdx].sprites.insert(copy, at: itemIdx + 1)
        }
        controller.selectedSpriteID = copy.name
    }

    // MARK: - Binding: sprite enabled

    private func bindSpriteEnabled(setIdx: Int, itemIdx: Int) -> Binding<Bool> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: setIdx]?.sprites[safe: itemIdx]?.enabled ?? true
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx  < cfg.spriteConfig.library.spriteSets.count,
                          itemIdx < cfg.spriteConfig.library.spriteSets[setIdx].sprites.count
                    else { return }
                    cfg.spriteConfig.library.spriteSets[setIdx].sprites[itemIdx].enabled = v
                }
            }
        )
    }

    // MARK: - Binding: inherit mask

    private func inheritBinding(setIdx: Int, spriteIdx: Int, kp: WritableKeyPath<SpriteDef, Bool>) -> Binding<Bool> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]?[keyPath: kp] ?? false
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard setIdx   < cfg.spriteConfig.library.spriteSets.count,
                          spriteIdx < cfg.spriteConfig.library.spriteSets[setIdx].sprites.count
                    else { return }
                    cfg.spriteConfig.library.spriteSets[setIdx].sprites[spriteIdx][keyPath: kp] = v
                }
            }
        )
    }

    // MARK: - Rename

    private func beginRename() {
        if let spriteName = controller.selectedSpriteID {
            renamingSpriteName = spriteName
            renamingSetIdx     = nil
            renameText         = spriteName
            showingRenameAlert = true
        } else if let idx = selectedSetIndex,
                  let cfg = controller.projectConfig,
                  idx < cfg.spriteConfig.library.spriteSets.count {
            renamingSetIdx     = idx
            renamingSpriteName = nil
            renameText         = cfg.spriteConfig.library.spriteSets[idx].name
            showingRenameAlert = true
        }
    }

    private func commitRename() {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        defer { renamingSetIdx = nil; renamingSpriteName = nil; renamingSceneID = nil }
        guard !newName.isEmpty else { return }

        if let sceneID = renamingSceneID {
            controller.renameScene(id: sceneID, name: newName)
            return
        }

        if let idx = renamingSetIdx,
           let cfg = controller.projectConfig,
           idx < cfg.spriteConfig.library.spriteSets.count {
            let oldName = cfg.spriteConfig.library.spriteSets[idx].name
            guard oldName != newName else { return }
            controller.updateProjectConfig { c in
                c.spriteConfig.library.spriteSets[idx].name = newName
            }
            if expandedSets.contains(oldName) { expandedSets.remove(oldName); expandedSets.insert(newName) }

        } else if let spriteName = renamingSpriteName,
                  let (sIdx, iIdx) = location(ofSprite: spriteName),
                  let cfg = controller.projectConfig,
                  sIdx < cfg.spriteConfig.library.spriteSets.count,
                  iIdx < cfg.spriteConfig.library.spriteSets[sIdx].sprites.count {
            guard spriteName != newName else { return }
            let allNames = cfg.spriteConfig.library.spriteSets.flatMap { $0.sprites.map(\.name) }
            guard !allNames.contains(newName) else { return }
            controller.updateProjectConfig { c in
                c.spriteConfig.library.spriteSets[sIdx].sprites[iIdx].name = newName
            }
            if controller.selectedSpriteID == spriteName { controller.selectedSpriteID = newName }
        }
    }

    // MARK: - Helpers

    private func spriteKey(_ setName: String, _ spriteName: String) -> String { "\(setName)\t\(spriteName)" }

    private func subtreeNames(of name: String, in sprites: [SpriteDef]) -> Set<String> {
        var names = Set<String>()
        func collect(_ n: String) {
            names.insert(n)
            for s in sprites where s.parentName == n { collect(s.name) }
        }
        collect(name)
        return names
    }

    private func location(ofSprite name: String) -> (Int, Int)? {
        guard let sets = controller.projectConfig?.spriteConfig.library.spriteSets else { return nil }
        for (si, set) in sets.enumerated() {
            if let ii = set.sprites.firstIndex(where: { $0.name == name }) { return (si, ii) }
        }
        return nil
    }

    private func setName(at idx: Int) -> String? {
        controller.projectConfig?.spriteConfig.library.spriteSets[safe: idx]?.name
    }

    private func uniqueName(base: String, existing: [String]) -> String {
        guard existing.contains(base) else { return base }
        var i = 2
        while existing.contains("\(base)_\(i)") { i += 1 }
        return "\(base)_\(i)"
    }
}
