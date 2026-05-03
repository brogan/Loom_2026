import SwiftUI
import LoomEngine

struct SpritesTabView: View {

    @EnvironmentObject private var controller: AppController

    @State private var expandedSets:    Set<Int> = []
    @State private var selectedSetIndex: Int?    = nil

    var body: some View {
        VStack(spacing: 0) {
            spriteList
            Divider()
            toolbar
        }
        .onAppear { autoExpand() }
        .onChange(of: controller.selectedSpriteID) { _, name in
            if let name, let (setIdx, _) = location(ofSprite: name) {
                selectedSetIndex = setIdx
                expandedSets.insert(setIdx)
            }
        }
    }

    // MARK: - List

    private var spriteList: some View {
        let sets = controller.projectConfig?.spriteConfig.library.spriteSets ?? []
        return Group {
            if sets.isEmpty {
                emptyState(controller.projectConfig == nil ? "No project open" : "No sprite sets")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sets.indices, id: \.self) { setIdx in
                            setRow(set: sets[setIdx], setIdx: setIdx)
                            if expandedSets.contains(setIdx) {
                                ForEach(sets[setIdx].sprites.indices, id: \.self) { itemIdx in
                                    spriteRow(
                                        sprite: sets[setIdx].sprites[itemIdx],
                                        setIdx: setIdx, itemIdx: itemIdx
                                    )
                                }
                                if sets[setIdx].sprites.isEmpty {
                                    Text("No sprites — use + to add")
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

    private func setRow(set: SpriteSet, setIdx: Int) -> some View {
        let isSelected = selectedSetIndex == setIdx && controller.selectedSpriteID == nil
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

            Text("\(set.sprites.count)")
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

    // MARK: - Sprite row

    private func spriteRow(sprite: SpriteDef, setIdx: Int, itemIdx: Int) -> some View {
        let isSelected = controller.selectedSpriteID == sprite.name

        return HStack(spacing: 5) {
            Spacer().frame(width: 22)
            Text(sprite.name.isEmpty ? "(unnamed)" : sprite.name)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 2)
            if sprite.animation.enabled {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { handleSpriteSelected(setIdx: setIdx, itemIdx: itemIdx, sprite: sprite) }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("plus",               tooltip: "New sprite set")      { addSet() }
            toolbarButton("minus",              tooltip: "Delete sprite set")   { deleteSelectedSet() }
                .disabled(selectedSetIndex == nil)
            toolbarButton("plus.square.on.square", tooltip: "Duplicate sprite set") { duplicateSelectedSet() }
                .disabled(selectedSetIndex == nil)

            Divider().frame(height: 14).padding(.horizontal, 4)

            toolbarButton("plus.circle",        tooltip: "Add sprite")          { addSprite() }
                .disabled(selectedSetIndex == nil)
            toolbarButton("minus.circle",       tooltip: "Delete sprite")       { deleteSelectedSprite() }
                .disabled(controller.selectedSpriteID == nil)
            toolbarButton("arrow.triangle.2.circlepath", tooltip: "Duplicate sprite") { duplicateSelectedSprite() }
                .disabled(controller.selectedSpriteID == nil)

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
        if selectedSetIndex == setIdx, controller.selectedSpriteID == nil {
            toggleExpansion(setIdx)
            return
        }
        selectedSetIndex             = setIdx
        controller.selectedSpriteID  = nil
        expandedSets.insert(setIdx)
    }

    private func handleSpriteSelected(setIdx: Int, itemIdx: Int, sprite: SpriteDef) {
        selectedSetIndex            = setIdx
        controller.selectedSpriteID = sprite.name
        expandedSets.insert(setIdx)
    }

    private func toggleExpansion(_ setIdx: Int) {
        if expandedSets.contains(setIdx) { expandedSets.remove(setIdx) }
        else { expandedSets.insert(setIdx) }
    }

    private func autoExpand() {
        guard let name = controller.selectedSpriteID,
              let (setIdx, _) = location(ofSprite: name) else { return }
        selectedSetIndex = setIdx
        expandedSets.insert(setIdx)
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
        expandedSets.insert(newIdx)
    }

    private func deleteSelectedSet() {
        guard let idx = selectedSetIndex,
              let cfg = controller.projectConfig,
              idx < cfg.spriteConfig.library.spriteSets.count else { return }
        // Clear any sprite selection inside the deleted set
        if let name = controller.selectedSpriteID,
           let (si, _) = location(ofSprite: name), si == idx {
            controller.selectedSpriteID = nil
        }
        controller.updateProjectConfig { c in
            c.spriteConfig.library.spriteSets.remove(at: idx)
        }
        expandedSets.remove(idx)
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
        // Give each sprite a unique name too
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
        expandedSets.insert(idx + 1)
    }

    // MARK: - CRUD: sprites within selected set

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
        expandedSets.insert(setIdx)
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
        if remaining.isEmpty {
            controller.selectedSpriteID = nil
        } else {
            let newIdx = min(itemIdx, remaining.count - 1)
            controller.selectedSpriteID = remaining[newIdx].name
        }
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

    // MARK: - Helpers

    private func location(ofSprite name: String) -> (Int, Int)? {
        guard let sets = controller.projectConfig?.spriteConfig.library.spriteSets else { return nil }
        for (si, set) in sets.enumerated() {
            if let ii = set.sprites.firstIndex(where: { $0.name == name }) {
                return (si, ii)
            }
        }
        return nil
    }

    private func uniqueName(base: String, existing: [String]) -> String {
        guard existing.contains(base) else { return base }
        var i = 2
        while existing.contains("\(base)_\(i)") { i += 1 }
        return "\(base)_\(i)"
    }
}
