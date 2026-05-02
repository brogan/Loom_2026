import SwiftUI
import LoomEngine

struct SubdivisionTabView: View {

    @EnvironmentObject private var controller: AppController

    // Expansion state for the subdivision sets tree (index-based so renames don't lose state)
    @State private var expandedSets: Set<Int> = []

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                spriteSection
                    .frame(height: geo.size.height * 0.38)

                applyBar
                    .frame(height: shouldShowApplyBar ? 32 : 0)
                    .clipped()

                Divider()

                setsSection
                    .frame(height: max(0, geo.size.height * 0.62
                                       - (shouldShowApplyBar ? 32 : 0)
                                       - 1   // divider
                                       - 30  // toolbar
                    ))

                Divider()
                setsToolbar
                    .frame(height: 30)
            }
        }
        .onAppear { autoSelectFirstSprite() }
    }

    // MARK: - Sprite section (top)

    private var spriteSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Sprites (polygon sets)")
            Divider()
            spriteTree
        }
    }

    private var spriteTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let cfg = controller.projectConfig {
                    let spriteSets = cfg.spriteConfig.library.spriteSets
                    if spriteSets.isEmpty || polygonSetSprites(in: cfg).isEmpty {
                        emptyText("No polygon-set sprites")
                    } else {
                        ForEach(spriteSets, id: \.name) { spriteSet in
                            let relevant = spriteSet.sprites.filter { isPolygonSetSprite($0, in: cfg) }
                            if !relevant.isEmpty {
                                spriteSetHeader(spriteSet.name)
                                ForEach(relevant, id: \.name) { sprite in
                                    spriteRow(sprite, cfg: cfg)
                                        .onTapGesture { handleSpriteSelected(sprite, cfg: cfg) }
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

    private func spriteSetHeader(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spriteRow(_ sprite: SpriteDef, cfg: ProjectConfig) -> some View {
        let isSelected  = controller.subdivSelectedSpriteID == sprite.name
        let assignedSet = assignedSetName(sprite: sprite, cfg: cfg)
        return HStack(spacing: 6) {
            Image(systemName: isSelected ? "circle.fill" : "circle")
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            Text(sprite.name.isEmpty ? "(unnamed)" : sprite.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 2)
            if let setName = assignedSet {
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

    // MARK: - Apply bar (shown when previewing a different set than assigned)

    private var applyBar: some View {
        Group {
            if shouldShowApplyBar,
               let previewName = controller.subdivPreviewSetName {
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
        guard let spriteID = controller.subdivSelectedSpriteID,
              let cfg = controller.projectConfig,
              let sprite = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID })
        else { return false }
        let assigned = assignedSetName(sprite: sprite, cfg: cfg)
        return controller.subdivPreviewSetName != assigned
    }

    // MARK: - Sets section (bottom)

    private var setsSection: some View {
        VStack(spacing: 0) {
            sectionLabel("Subdivision Sets")
            Divider()
            setsTree
        }
    }

    private var setsTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let sets = controller.projectConfig?.subdivisionConfig.paramsSets ?? []
                if sets.isEmpty {
                    emptyText("No subdivision sets")
                } else {
                    ForEach(sets.indices, id: \.self) { setIdx in
                        let set = sets[setIdx]
                        setDisclosureRow(set: set, setIdx: setIdx)
                        if expandedSets.contains(setIdx) {
                            ForEach(set.params.indices, id: \.self) { paramIdx in
                                paramRow(param: set.params[paramIdx],
                                         setIdx: setIdx, paramIdx: paramIdx)
                                    .onTapGesture { handleParamSelected(setIdx: setIdx, paramIdx: paramIdx) }
                            }
                            if set.params.isEmpty {
                                Text("No params — use + to add")
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

    private func setDisclosureRow(set: SubdivisionParamsSet, setIdx: Int) -> some View {
        let isSelected  = controller.selectedSubdivisionIndex == setIdx
        let isExpanded  = expandedSets.contains(setIdx)
        let isPreviewed = controller.subdivPreviewSetName == set.name

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
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 2)

            if isPreviewed {
                Image(systemName: "eye.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }

            Text("\(set.params.count)")
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

    private func paramRow(param: SubdivisionParams, setIdx: Int, paramIdx: Int) -> some View {
        let isSelected = controller.selectedSubdivisionIndex == setIdx
                      && controller.selectedSubdivisionParamIndex == paramIdx
        return HStack(spacing: 5) {
            Spacer().frame(width: 22)
            Text("\(paramIdx)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)
            Text(param.name.isEmpty ? param.subdivisionType.shortLabel : param.name)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Text(param.subdivisionType.shortLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Sets toolbar

    private var setsToolbar: some View {
        HStack(spacing: 0) {
            // Set-level buttons
            toolbarButton("plus", tooltip: "New set")         { addSet() }
            toolbarButton("minus", tooltip: "Delete set")     { deleteSelectedSet() }
                .disabled(controller.selectedSubdivisionIndex == nil)
            toolbarButton("plus.square.on.square", tooltip: "Duplicate set") { duplicateSelectedSet() }
                .disabled(controller.selectedSubdivisionIndex == nil)

            Divider().frame(height: 14).padding(.horizontal, 4)

            // Param-level buttons
            toolbarButton("plus.circle", tooltip: "Add param") { addParam() }
                .disabled(controller.selectedSubdivisionIndex == nil)
            toolbarButton("minus.circle", tooltip: "Delete param") { deleteSelectedParam() }
                .disabled(controller.selectedSubdivisionParamIndex == nil)
            toolbarButton("arrow.triangle.2.circlepath", tooltip: "Duplicate param") { duplicateSelectedParam() }
                .disabled(controller.selectedSubdivisionParamIndex == nil)

            Divider().frame(height: 14).padding(.horizontal, 4)

            toolbarButton("flame", tooltip: "Bake param (not yet implemented)") { /* TODO: bake */ }
                .disabled(true)

            Spacer()
        }
        .padding(.horizontal, 4)
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

    // MARK: - Interaction handlers

    private func handleSpriteSelected(_ sprite: SpriteDef, cfg: ProjectConfig) {
        controller.subdivSelectedSpriteID        = sprite.name
        controller.selectedSubdivisionParamIndex = nil
        let assigned = assignedSetName(sprite: sprite, cfg: cfg)
        controller.subdivPreviewSetName = assigned
        if let assigned,
           let idx = cfg.subdivisionConfig.paramsSets.firstIndex(where: { $0.name == assigned }) {
            controller.selectedSubdivisionIndex = idx
            expandedSets.insert(idx)
        } else {
            controller.selectedSubdivisionIndex = nil
        }
    }

    private func handleSetSelected(_ setIdx: Int) {
        guard let cfg = controller.projectConfig,
              setIdx < cfg.subdivisionConfig.paramsSets.count else { return }

        // Already selected with no param — any further published update would rebuild
        // the view and steal focus from the inline TextField. Return early to preserve it.
        if controller.selectedSubdivisionIndex == setIdx,
           controller.selectedSubdivisionParamIndex == nil { return }

        let setName = cfg.subdivisionConfig.paramsSets[setIdx].name
        controller.selectedSubdivisionIndex      = setIdx
        controller.selectedSubdivisionParamIndex = nil
        expandedSets.insert(setIdx)

        if controller.subdivSelectedSpriteID != nil {
            controller.subdivPreviewSetName = setName
        }
    }

    private func handleParamSelected(setIdx: Int, paramIdx: Int) {
        // Already selected — preserve TextField focus.
        if controller.selectedSubdivisionIndex == setIdx,
           controller.selectedSubdivisionParamIndex == paramIdx { return }

        controller.selectedSubdivisionIndex      = setIdx
        controller.selectedSubdivisionParamIndex = paramIdx
        guard let cfg = controller.projectConfig,
              setIdx < cfg.subdivisionConfig.paramsSets.count else { return }
        let setName = cfg.subdivisionConfig.paramsSets[setIdx].name
        expandedSets.insert(setIdx)
        if controller.subdivSelectedSpriteID != nil {
            controller.subdivPreviewSetName = setName
        }
    }

    // MARK: - Apply / Revert

    private func applyPreviewSet() {
        guard let spriteID  = controller.subdivSelectedSpriteID,
              let preview   = controller.subdivPreviewSetName,
              let cfg       = controller.projectConfig,
              let sprite    = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID })
        else { return }
        let ssName = sprite.shapeSetName
        let sName  = sprite.shapeName
        controller.updateProjectConfig { config in
            for ssIdx in config.shapeConfig.library.shapeSets.indices
            where config.shapeConfig.library.shapeSets[ssIdx].name == ssName {
                for sIdx in config.shapeConfig.library.shapeSets[ssIdx].shapes.indices
                where config.shapeConfig.library.shapeSets[ssIdx].shapes[sIdx].name == sName {
                    config.shapeConfig.library.shapeSets[ssIdx].shapes[sIdx].subdivisionParamsSetName = preview
                }
            }
        }
    }

    private func revertPreviewSet() {
        guard let spriteID = controller.subdivSelectedSpriteID,
              let cfg = controller.projectConfig,
              let sprite = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID })
        else { return }
        let assigned = assignedSetName(sprite: sprite, cfg: cfg)
        controller.subdivPreviewSetName = assigned
        if let assigned,
           let idx = cfg.subdivisionConfig.paramsSets.firstIndex(where: { $0.name == assigned }) {
            controller.selectedSubdivisionIndex = idx
        } else {
            controller.selectedSubdivisionIndex = nil
        }
        controller.selectedSubdivisionParamIndex = nil
    }

    // MARK: - CRUD: sets

    private func addSet() {
        guard let cfg = controller.projectConfig else { return }
        let name    = uniqueSetName(base: "new_set", in: cfg.subdivisionConfig.paramsSets)
        let newSet  = SubdivisionParamsSet(name: name, params: [SubdivisionParams()])
        controller.updateProjectConfig { config in
            config.subdivisionConfig.paramsSets.append(newSet)
        }
        guard let updatedCfg = controller.projectConfig else { return }
        let newIdx = updatedCfg.subdivisionConfig.paramsSets.count - 1
        controller.selectedSubdivisionIndex      = newIdx
        controller.selectedSubdivisionParamIndex = nil
        expandedSets.insert(newIdx)

        // If sprite selected with no assigned set, auto-apply the new set
        if let spriteID = controller.subdivSelectedSpriteID,
           let sprite = updatedCfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID }),
           assignedSetName(sprite: sprite, cfg: updatedCfg) == nil {
            controller.subdivPreviewSetName = name
            applyPreviewSet()
        } else {
            controller.subdivPreviewSetName = name
        }
    }

    private func deleteSelectedSet() {
        guard let idx = controller.selectedSubdivisionIndex,
              let cfg = controller.projectConfig,
              idx < cfg.subdivisionConfig.paramsSets.count else { return }
        let deletedName = cfg.subdivisionConfig.paramsSets[idx].name
        controller.updateProjectConfig { config in
            config.subdivisionConfig.paramsSets.remove(at: idx)
            // Clear any sprite shape references to this set
            for ssIdx in config.shapeConfig.library.shapeSets.indices {
                for sIdx in config.shapeConfig.library.shapeSets[ssIdx].shapes.indices
                where config.shapeConfig.library.shapeSets[ssIdx].shapes[sIdx].subdivisionParamsSetName == deletedName {
                    config.shapeConfig.library.shapeSets[ssIdx].shapes[sIdx].subdivisionParamsSetName = ""
                }
            }
        }
        expandedSets.removeAll()
        let remaining = controller.projectConfig?.subdivisionConfig.paramsSets.count ?? 0
        let newIdx = remaining > 0 ? min(idx, remaining - 1) : nil
        controller.selectedSubdivisionIndex = newIdx
        if let newIdx { expandedSets.insert(newIdx) }
        controller.selectedSubdivisionParamIndex = nil
        // If the deleted set was being previewed, revert
        if controller.subdivPreviewSetName == deletedName {
            controller.subdivPreviewSetName = nil
        }
    }

    private func duplicateSelectedSet() {
        guard let idx = controller.selectedSubdivisionIndex,
              let cfg = controller.projectConfig,
              idx < cfg.subdivisionConfig.paramsSets.count else { return }
        var copy = cfg.subdivisionConfig.paramsSets[idx]
        copy.name = uniqueSetName(base: "\(copy.name)_copy", in: cfg.subdivisionConfig.paramsSets)
        let copyName = copy.name
        controller.updateProjectConfig { config in
            config.subdivisionConfig.paramsSets.insert(copy, at: idx + 1)
        }
        let newIdx = idx + 1
        controller.selectedSubdivisionIndex      = newIdx
        controller.selectedSubdivisionParamIndex = nil
        expandedSets.insert(newIdx)
        if controller.subdivSelectedSpriteID != nil {
            controller.subdivPreviewSetName = copy.name
        }
    }

    // MARK: - CRUD: params

    private func addParam() {
        guard let setIdx = controller.selectedSubdivisionIndex,
              let cfg    = controller.projectConfig,
              setIdx < cfg.subdivisionConfig.paramsSets.count else { return }
        let newParam = SubdivisionParams()
        controller.updateProjectConfig { config in
            config.subdivisionConfig.paramsSets[setIdx].params.append(newParam)
        }
        let newParamIdx = (controller.projectConfig?.subdivisionConfig.paramsSets[setIdx].params.count ?? 1) - 1
        controller.selectedSubdivisionParamIndex = newParamIdx
    }

    private func deleteSelectedParam() {
        guard let setIdx   = controller.selectedSubdivisionIndex,
              let paramIdx = controller.selectedSubdivisionParamIndex,
              let cfg      = controller.projectConfig,
              setIdx < cfg.subdivisionConfig.paramsSets.count,
              paramIdx < cfg.subdivisionConfig.paramsSets[setIdx].params.count else { return }
        controller.updateProjectConfig { config in
            config.subdivisionConfig.paramsSets[setIdx].params.remove(at: paramIdx)
        }
        let remaining = controller.projectConfig?.subdivisionConfig.paramsSets[safe: setIdx]?.params.count ?? 0
        controller.selectedSubdivisionParamIndex = remaining > 0 ? min(paramIdx, remaining - 1) : nil
    }

    private func duplicateSelectedParam() {
        guard let setIdx   = controller.selectedSubdivisionIndex,
              let paramIdx = controller.selectedSubdivisionParamIndex,
              let cfg      = controller.projectConfig,
              setIdx < cfg.subdivisionConfig.paramsSets.count,
              paramIdx < cfg.subdivisionConfig.paramsSets[setIdx].params.count else { return }
        let copy = cfg.subdivisionConfig.paramsSets[setIdx].params[paramIdx]
        controller.updateProjectConfig { config in
            config.subdivisionConfig.paramsSets[setIdx].params.insert(copy, at: paramIdx + 1)
        }
        controller.selectedSubdivisionParamIndex = paramIdx + 1
    }

    // MARK: - Auto-select on appear

    private func autoSelectFirstSprite() {
        guard controller.subdivSelectedSpriteID == nil,
              let cfg = controller.projectConfig
        else {
            // Restore expansion for already-selected sprite's set
            if let setName = controller.subdivPreviewSetName,
               let idx = controller.projectConfig?.subdivisionConfig.paramsSets
                   .firstIndex(where: { $0.name == setName }) {
                expandedSets.insert(idx)
            }
            return
        }
        if let first = polygonSetSprites(in: cfg).first {
            handleSpriteSelected(first, cfg: cfg)
        }
    }

    // MARK: - Expansion toggle

    private func toggleExpansion(_ setIdx: Int) {
        if expandedSets.contains(setIdx) { expandedSets.remove(setIdx) }
        else { expandedSets.insert(setIdx) }
    }

    // MARK: - Helpers

    private func polygonSetSprites(in cfg: ProjectConfig) -> [SpriteDef] {
        cfg.spriteConfig.library.allSprites.filter { isPolygonSetSprite($0, in: cfg) }
    }

    private func isPolygonSetSprite(_ sprite: SpriteDef, in cfg: ProjectConfig) -> Bool {
        guard let shape = cfg.shapeConfig.library.shapeSets
            .first(where: { $0.name == sprite.shapeSetName })?
            .shapes.first(where: { $0.name == sprite.shapeName })
        else { return false }
        return shape.sourceType == .polygonSet || shape.sourceType == .regularPolygon
    }

    private func assignedSetName(sprite: SpriteDef, cfg: ProjectConfig) -> String? {
        cfg.shapeConfig.library.shapeSets
            .first(where: { $0.name == sprite.shapeSetName })?
            .shapes.first(where: { $0.name == sprite.shapeName })?
            .subdivisionParamsSetName.nonEmpty
    }

    private func uniqueSetName(base: String, in sets: [SubdivisionParamsSet]) -> String {
        guard sets.contains(where: { $0.name == base }) else { return base }
        var i = 2
        while sets.contains(where: { $0.name == "\(base)_\(i)" }) { i += 1 }
        return "\(base)_\(i)"
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
}

// MARK: - Subdivision type display name

private extension SubdivisionType {
    var shortLabel: String {
        switch self {
        case .quad:               return "Quad"
        case .quadBord:           return "QuadBord"
        case .quadBordEcho:       return "QuadBordEcho"
        case .quadBordDouble:     return "QuadBordDbl"
        case .quadBordDoubleEcho: return "QuadBordDblEcho"
        case .tri:                return "Tri"
        case .triBordA:           return "TriBordA"
        case .triBordAEcho:       return "TriBordAEcho"
        case .triBordB:           return "TriBordB"
        case .triBordBEcho:       return "TriBordBEcho"
        case .triBordC:           return "TriBordC"
        case .triBordCEcho:       return "TriBordCEcho"
        case .triStar:            return "TriStar"
        case .triStarFill:        return "TriStarFill"
        case .splitVert:          return "SplitVert"
        case .splitHoriz:         return "SplitHoriz"
        case .splitDiag:          return "SplitDiag"
        case .echo:               return "Echo"
        case .echoAbsCenter:      return "EchoAbsCtr"
        }
    }
}
