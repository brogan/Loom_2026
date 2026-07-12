import SwiftUI
import LoomEngine

struct SubdivisionTabView: View {

    @EnvironmentObject private var controller: AppController

    @State private var hiddenSubdivSprites: Set<String> = []
    @State private var hasAppeared                      = false
    @State private var bakeAlert: BakeAlert?            = nil

    private let setsToolbarHeight: CGFloat = 54

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
                                       - setsToolbarHeight
                    ))

                Divider()
                setsToolbar
                    .frame(height: setsToolbarHeight)
            }
        }
        .onAppear { autoSelectFirstSprite() }
        .alert(item: $bakeAlert) { a in
            Alert(title: Text(a.title), message: Text(a.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Sprite section (top)

    private var spriteSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sprite Set")
                Spacer()
                Text("Transform Set")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            spriteTree
        }
    }

    private var spriteTree: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let cfg = controller.projectConfig {
                    let spriteSets = cfg.spriteConfig.library.spriteSets
                    if spriteSets.isEmpty || transformableSprites(in: cfg).isEmpty {
                        emptyText("No transformable sprites")
                    } else {
                        ForEach(spriteSets, id: \.name) { spriteSet in
                            let relevant = spriteSet.sprites.filter { isTransformableSprite($0, in: cfg) }
                            if !relevant.isEmpty {
                                spriteSetHeader(spriteSet.name, sprites: relevant)
                                let visible = relevant.filter {
                                    !hiddenSubdivSprites.contains(subdivSpriteKey(spriteSet.name, $0.name))
                                }
                                ForEach(visible, id: \.name) { sprite in
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

    private func spriteSetHeader(_ setName: String, sprites: [SpriteDef]) -> some View {
        let hiddenCount  = sprites.filter { hiddenSubdivSprites.contains(subdivSpriteKey(setName, $0.name)) }.count
        let hidableCount = sprites.filter { !$0.enabled && !hiddenSubdivSprites.contains(subdivSpriteKey(setName, $0.name)) }.count

        return HStack(spacing: 4) {
            Text(setName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)
            Spacer()
            if hiddenCount > 0 {
                Button {
                    for s in sprites { hiddenSubdivSprites.remove(subdivSpriteKey(setName, s.name)) }
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
                .padding(.trailing, 8)
                .padding(.top, 4)
                .help("Restore \(hiddenCount) hidden sprite\(hiddenCount == 1 ? "" : "s")")
            } else if hidableCount > 0 {
                Button {
                    for s in sprites where !s.enabled { hiddenSubdivSprites.insert(subdivSpriteKey(setName, s.name)) }
                } label: {
                    Image(systemName: "eye").font(.system(size: 9)).foregroundStyle(.tertiary)
                        .iconHitArea()
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .padding(.top, 4)
                .help("Hide \(hidableCount) disabled sprite\(hidableCount == 1 ? "" : "s")")
            }
        }
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
            sectionLabel("Transform Sets")
            Divider()
            setsTree
        }
    }

    private var setsTree: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let sets = controller.projectConfig?.subdivisionConfig.paramsSets ?? []
                if sets.isEmpty {
                    emptyText("No transform sets")
                } else {
                    ForEach(sets.indices, id: \.self) { setIdx in
                        setRow(set: sets[setIdx], setIdx: setIdx)
                    }
                }
            }
        }
    }

    /// A set is just a name and a total pass count here — adding, removing,
    /// and editing individual passes (of any of the five lifecycle modes)
    /// happens entirely in the right-hand inspector.
    private func setRow(set: SubdivisionParamsSet, setIdx: Int) -> some View {
        let isSelected  = controller.selectedSubdivisionIndex == setIdx
        let isPreviewed = controller.subdivPreviewSetName == set.name

        return HStack(spacing: 5) {
            Text(set.name.isEmpty ? "(unnamed)" : set.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 2)

            if isPreviewed {
                Image(systemName: "eye.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }

            Text("\(totalPassCount(set))")
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

    /// Total passes across all five lifecycle modes — not just closed-polygon
    /// subdivision passes — so open-curve/Extension/Evolution/Dissolution-only
    /// sets don't read as empty in this tree.
    private func totalPassCount(_ set: SubdivisionParamsSet) -> Int {
        set.params.count + set.curveRefinement.count + set.segmentExtraction.count
            + set.extensionPasses.count + set.evolutionPasses.count + set.fulgurationPasses.count
            + set.dissolutionPasses.count
    }

    // MARK: - Sets toolbar

    private var setsToolbar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Sets")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                toolbarButton("plus", tooltip: "New set") { addSet() }
                toolbarButton("minus", tooltip: "Delete set") { deleteSelectedSet() }
                    .disabled(controller.selectedSubdivisionIndex == nil)
                toolbarButton("plus.square.on.square", tooltip: "Duplicate set") { duplicateSelectedSet() }
                    .disabled(controller.selectedSubdivisionIndex == nil)
                Spacer()
            }
            .frame(height: 24)

            HStack(spacing: 0) {
                Text("Output")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
                toolbarButton("flame", tooltip: "Bake selected set to polygon file") { bakeSelectedSet() }
                    .disabled(!canBake)
                Button {
                    saveSelectedSetAsSVG()
                } label: {
                    SVGExportIcon()
                        .frame(width: 28, height: 20)
                        .frame(width: 30, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(!canExportSVG)
                .help("Save subdivided geometry as SVG wireframe to svgs/")
                Spacer()
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private func toolbarButton(_ icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        toolbarIconButton(tooltip: tooltip) {
            Image(systemName: icon).font(.system(size: 12))
        } action: {
            action()
        }
    }

    private func toolbarIconButton<Label: View>(
        tooltip: String,
        @ViewBuilder label: () -> Label,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .modifier(LoomHoverHelp(tooltip))
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

        // `subdivPreviewSetName` can go stale (the set it was tracking got
        // renamed or deleted elsewhere, e.g. via the Sprites tab or another
        // window) — never write a dangling name onto the shape. Resync to the
        // sprite's actual assigned set instead of applying garbage.
        guard cfg.subdivisionConfig.paramsSets.contains(where: { $0.name == preview }) else {
            controller.subdivPreviewSetName = assignedSetName(sprite: sprite, cfg: cfg)
            return
        }

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
        let newSet  = SubdivisionParamsSet(name: name)
        controller.updateProjectConfig { config in
            config.subdivisionConfig.paramsSets.append(newSet)
        }
        guard let updatedCfg = controller.projectConfig else { return }
        let newIdx = updatedCfg.subdivisionConfig.paramsSets.count - 1
        controller.selectedSubdivisionIndex      = newIdx
        controller.selectedSubdivisionParamIndex = nil

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
        let remaining = controller.projectConfig?.subdivisionConfig.paramsSets.count ?? 0
        let newIdx = remaining > 0 ? min(idx, remaining - 1) : nil
        controller.selectedSubdivisionIndex = newIdx
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
        if controller.subdivSelectedSpriteID != nil {
            controller.subdivPreviewSetName = copyName
        }
    }

    // MARK: - Bake

    private var canBake: Bool {
        guard controller.selectedSubdivisionIndex != nil,
              let spriteID = controller.subdivSelectedSpriteID,
              let cfg      = controller.projectConfig,
              let sprite   = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID }),
              let shape    = cfg.shapeConfig.library.shapeSets
                  .first(where: { $0.name == sprite.shapeSetName })?
                  .shapes.first(where: { $0.name == sprite.shapeName }),
              shape.sourceType == .polygonSet,
              !shape.polygonSetName.isEmpty,
              let polyDef = cfg.polygonConfig.library.polygonSets
                  .first(where: { $0.name == shape.polygonSetName }),
              polyDef.regularParams == nil,  // file-backed only, not generated
              !polyDef.filename.isEmpty
        else { return false }
        return true
    }

    /// Deliberately looser than `canBake`: SVG export goes through
    /// `SpriteScene.loadBasePolygons`, which resolves *any* `ShapeSourceType`
    /// (regular polygons, open curves, ovals, points — not just file-backed
    /// polygon sets), so it only needs a sprite+shape to resolve at all. Sharing
    /// `canBake`'s guard here previously left the SVG export button disabled for
    /// every non-file-backed-polygonSet source, even though the export itself
    /// (once reachable) already handled them once fixed — 2026-07-09.
    private var canExportSVG: Bool {
        guard controller.selectedSubdivisionIndex != nil,
              let spriteID = controller.subdivSelectedSpriteID,
              let cfg      = controller.projectConfig,
              let sprite   = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID }),
              cfg.shapeConfig.library.shapeSets
                  .first(where: { $0.name == sprite.shapeSetName })?
                  .shapes.first(where: { $0.name == sprite.shapeName }) != nil
        else { return false }
        return true
    }

    private func bakeSelectedSet() {
        guard let setIdx    = controller.selectedSubdivisionIndex,
              let cfg       = controller.projectConfig,
              let projectURL = controller.projectURL,
              setIdx < cfg.subdivisionConfig.paramsSets.count,
              let spriteID  = controller.subdivSelectedSpriteID,
              let sprite    = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID }),
              let shape     = cfg.shapeConfig.library.shapeSets
                  .first(where: { $0.name == sprite.shapeSetName })?
                  .shapes.first(where: { $0.name == sprite.shapeName }),
              let polyDef   = cfg.polygonConfig.library.polygonSets
                  .first(where: { $0.name == shape.polygonSetName })
        else { return }

        // Resolve source file path.
        let resolvedFolder = (polyDef.folder == "polygonSet" || polyDef.folder.isEmpty)
            ? "polygonSets" : polyDef.folder
        let sourceURL = projectURL
            .appendingPathComponent(resolvedFolder)
            .appendingPathComponent(polyDef.filename)

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            bakeAlert = BakeAlert(title: "Bake Failed",
                                  message: "Source polygon file not found:\n\(sourceURL.path)")
            return
        }

        // Load polygons — JSON editable geometry files and legacy XML files both supported.
        let polys: [Polygon2D]
        do {
            if sourceURL.pathExtension.lowercased() == "json" {
                polys = try EditableGeometryJSONLoader.load(url: sourceURL)
                    .runtimePolygons(targetLayerID: polyDef.editableLayerID,
                                     targetLayerName: polyDef.editableLayerName)
            } else {
                polys = try XMLPolygonLoader.load(url: sourceURL, normalise: false)
            }
        } catch {
            bakeAlert = BakeAlert(title: "Bake Failed",
                                  message: "Could not load polygon file:\n\(error.localizedDescription)")
            return
        }

        // Run evolution (modifies params) → subdivision → refinement → extraction → extension.
        let paramSet     = cfg.subdivisionConfig.paramsSets[setIdx]
        var evolvedParams = paramSet.params
        var evolvedCurveParams = paramSet.curveRefinement
        if !paramSet.evolutionPasses.isEmpty {
            EvolutionEngine.apply(params: &evolvedParams, curveRefinementParams: &evolvedCurveParams,
                                   passes: paramSet.evolutionPasses,
                                   elapsedFrames: 0, targetFPS: 24, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        }
        var rng    = SystemRandomNumberGenerator()
        var result = SubdivisionEngine.process(polygons: polys, paramSet: evolvedParams, rng: &rng)
        if !evolvedCurveParams.isEmpty {
            result = CurveRefinementEngine.process(polygons: result, paramSet: evolvedCurveParams)
        }
        if !paramSet.segmentExtraction.isEmpty {
            result = SegmentExtractionEngine.process(polygons: result, paramSet: paramSet.segmentExtraction)
        }
        if !paramSet.extensionPasses.isEmpty {
            result = ExtensionEngine.process(polygons: result, paramSet: paramSet.extensionPasses)
        }
        if paramSet.evolutionPasses.contains(where: { $0.enabled && $0.operationType == .generational }) {
            let customPrimitives = SpriteScene.loadGraftCustomPrimitives(config: cfg, projectDirectory: projectURL)
            result = GenerationalEvolutionEngine.process(polygons: result, passes: paramSet.evolutionPasses,
                                                          elapsedFrames: 0, targetFPS: 24, spriteIndex: 0,
                                                          customPrimitives: customPrimitives)
        }
        if !paramSet.fulgurationPasses.isEmpty {
            result = FulgurationEngine.apply(polygons: result, passes: paramSet.fulgurationPasses,
                                              elapsedFrames: 0, spriteIndex: 0)
        }
        if !paramSet.dissolutionPasses.isEmpty {
            result = DissolutionEngine.apply(polygons: result, passes: paramSet.dissolutionPasses,
                                              elapsedFrames: 0, spriteIndex: 0)
        }

        // Build output path in polygonSets/.
        let safePolyName  = shape.polygonSetName.replacingOccurrences(of: " ", with: "_")
        let safeSetName   = paramSet.name.replacingOccurrences(of: " ", with: "_")
        let baseName      = "\(safePolyName)_\(safeSetName)_baked"
        let outputDir     = projectURL.appendingPathComponent("polygonSets")
        let filename      = uniqueBakeFilename(base: baseName, in: outputDir)
        let outputURL     = outputDir.appendingPathComponent(filename)
        let stem          = String(filename.dropLast(4))  // drop ".xml"

        // Create polygonSets/ directory if needed.
        do {
            try FileManager.default.createDirectory(at: outputDir,
                                                     withIntermediateDirectories: true)
        } catch {
            bakeAlert = BakeAlert(title: "Bake Failed",
                                  message: "Could not create output directory:\n\(error.localizedDescription)")
            return
        }

        // Write XML.
        do {
            try XMLPolygonWriter.write(result, name: stem, to: outputURL)
        } catch {
            bakeAlert = BakeAlert(title: "Bake Failed",
                                  message: "Could not write baked file:\n\(error.localizedDescription)")
            return
        }

        // Register new polygon set in config.
        let newDef = PolygonSetDef(name: stem, folder: "polygonSet", filename: filename)
        controller.updateProjectConfig { config in
            config.polygonConfig.library.polygonSets.append(newDef)
        }

        bakeAlert = BakeAlert(title: "Bake Complete",
                              message: "Saved \(result.count) polygon(s) to:\n\(filename)\n\nThe baked set '\(stem)' is now available in the Geometry tab.")
    }

    private func saveSelectedSetAsSVG() {
        guard let setIdx    = controller.selectedSubdivisionIndex,
              let cfg       = controller.projectConfig,
              let projectURL = controller.projectURL,
              setIdx < cfg.subdivisionConfig.paramsSets.count,
              let spriteID  = controller.subdivSelectedSpriteID,
              let sprite    = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID }),
              let shape     = cfg.shapeConfig.library.shapeSets
                  .first(where: { $0.name == sprite.shapeSetName })?
                  .shapes.first(where: { $0.name == sprite.shapeName })
        else { return }

        // SpriteScene.loadBasePolygons is the single canonical ShapeDef → [Polygon2D]
        // dispatch (same one the live render pipeline uses) — covers every source
        // type (polygon sets incl. algorithmically-generated regular polygons, open
        // curve sets, oval sets, point sets), unlike the polygonSets-only lookup
        // this used to do by hand, which silently failed for anything else.
        let polys: [Polygon2D]
        do {
            polys = try SpriteScene.loadBasePolygons(shapeDef: shape, config: cfg, projectDirectory: projectURL)
        } catch {
            bakeAlert = BakeAlert(title: "SVG Export Failed",
                                  message: "Could not load geometry:\n\(error.localizedDescription)")
            return
        }
        guard !polys.isEmpty else {
            bakeAlert = BakeAlert(title: "SVG Export Failed",
                                  message: "No geometry found for this sprite's shape (\(shape.sourceType.rawValue)).")
            return
        }

        let paramSet2     = cfg.subdivisionConfig.paramsSets[setIdx]
        var evolvedParams2 = paramSet2.params
        var evolvedCurveParams2 = paramSet2.curveRefinement
        if !paramSet2.evolutionPasses.isEmpty {
            EvolutionEngine.apply(params: &evolvedParams2, curveRefinementParams: &evolvedCurveParams2,
                                   passes: paramSet2.evolutionPasses,
                                   elapsedFrames: 0, targetFPS: 24, spriteIndex: 0, allSets: [:], allCurveSets: [:])
        }
        var rng    = SystemRandomNumberGenerator()
        var result = SubdivisionEngine.process(polygons: polys, paramSet: evolvedParams2, rng: &rng)
        if !evolvedCurveParams2.isEmpty {
            result = CurveRefinementEngine.process(polygons: result, paramSet: evolvedCurveParams2)
        }
        if !paramSet2.segmentExtraction.isEmpty {
            result = SegmentExtractionEngine.process(polygons: result, paramSet: paramSet2.segmentExtraction)
        }
        if !paramSet2.extensionPasses.isEmpty {
            result = ExtensionEngine.process(polygons: result, paramSet: paramSet2.extensionPasses)
        }
        if paramSet2.evolutionPasses.contains(where: { $0.enabled && $0.operationType == .generational }) {
            let customPrimitives2 = SpriteScene.loadGraftCustomPrimitives(config: cfg, projectDirectory: projectURL)
            result = GenerationalEvolutionEngine.process(polygons: result, passes: paramSet2.evolutionPasses,
                                                          elapsedFrames: 0, targetFPS: 24, spriteIndex: 0,
                                                          customPrimitives: customPrimitives2)
        }
        if !paramSet2.fulgurationPasses.isEmpty {
            result = FulgurationEngine.apply(polygons: result, passes: paramSet2.fulgurationPasses,
                                              elapsedFrames: 0, spriteIndex: 0)
        }
        if !paramSet2.dissolutionPasses.isEmpty {
            result = DissolutionEngine.apply(polygons: result, passes: paramSet2.dissolutionPasses,
                                              elapsedFrames: 0, spriteIndex: 0)
        }

        // Source name for the output filename — the relevant field varies by
        // sourceType (polygonSetName is empty for e.g. an open-curve-sourced shape).
        let sourceName: String
        switch shape.sourceType {
        case .polygonSet:     sourceName = shape.polygonSetName
        case .openCurveSet:   sourceName = shape.openCurveSetName
        case .pointSet:       sourceName = shape.pointSetName
        case .ovalSet:        sourceName = shape.ovalSetName
        case .regularPolygon: sourceName = "\(shape.regularPolygonSides)gon"
        case .inlinePoints, .unknown: sourceName = shape.name
        }
        let safePolyName = (sourceName.isEmpty ? shape.name : sourceName).replacingOccurrences(of: " ", with: "_")
        let safeSetName  = paramSet2.name.replacingOccurrences(of: " ", with: "_")
        let stem         = "\(safePolyName)_\(safeSetName)"
        let svgsDir      = projectURL.appendingPathComponent("svgs")

        let w = Double(cfg.globalConfig.width)
        let h = Double(cfg.globalConfig.height)

        do {
            let url = try LoomSVGWriter.writeSVG(polygons: result, stem: stem, canvasSize: (w, h), to: svgsDir)
            bakeAlert = BakeAlert(title: "SVG Saved",
                                  message: "Saved \(result.count) polygon(s) to:\nsvgs/\(url.lastPathComponent)")
        } catch {
            bakeAlert = BakeAlert(title: "SVG Export Failed",
                                  message: "Could not write SVG:\n\(error.localizedDescription)")
        }
    }

    private func uniqueBakeFilename(base: String, in dir: URL) -> String {
        let candidate = "\(base).xml"
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            return candidate
        }
        var i = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(base)_\(i).xml").path) {
            i += 1
        }
        return "\(base)_\(i).xml"
    }

    // MARK: - Auto-select on appear

    private func autoSelectFirstSprite() {
        if !hasAppeared {
            hasAppeared = true
        }

        guard let cfg = controller.projectConfig else { return }

        if let spriteID = controller.subdivSelectedSpriteID,
           let sprite = cfg.spriteConfig.library.allSprites.first(where: { $0.name == spriteID }) {
            resyncPreviewToAssigned(sprite: sprite, cfg: cfg)
            return
        }
        if let first = transformableSprites(in: cfg).first {
            handleSpriteSelected(first, cfg: cfg)
        }
    }

    /// Re-checks `subdivPreviewSetName` against the sprite's actual current
    /// assignment every time this tab appears — called even when the sprite
    /// was already selected (unlike `handleSpriteSelected`, which resets
    /// `selectedSubdivisionParamIndex` too and is meant for a fresh
    /// selection, not a revisit). `subdivPreviewSetName` is transient UI
    /// state (which set is being browsed without committing) and shouldn't
    /// survive a trip away from this tab and back unexamined — without this,
    /// a change made elsewhere to the sprite's assignment (most commonly via
    /// the Sprites tab's own "Transform set" picker) leaves the preview
    /// pointed at the old value, which then shows a spurious "Previewing: X
    /// — Apply" bar whose Apply would clobber the just-made, correct
    /// assignment right back to the stale one.
    private func resyncPreviewToAssigned(sprite: SpriteDef, cfg: ProjectConfig) {
        let assigned = assignedSetName(sprite: sprite, cfg: cfg)
        guard controller.subdivPreviewSetName != assigned else { return }
        controller.subdivPreviewSetName = assigned
        if let assigned,
           let idx = cfg.subdivisionConfig.paramsSets.firstIndex(where: { $0.name == assigned }) {
            controller.selectedSubdivisionIndex = idx
        }
    }

    // MARK: - Helpers

    private func subdivSpriteKey(_ setName: String, _ spriteName: String) -> String { "\(setName)\t\(spriteName)" }

    private func transformableSprites(in cfg: ProjectConfig) -> [SpriteDef] {
        cfg.spriteConfig.library.allSprites.filter { isTransformableSprite($0, in: cfg) }
    }

    /// A sprite is eligible for the Transform tab if its shape resolves to a
    /// source type this tab's pipeline (Subdivision/CurveRefinement/
    /// SegmentExtraction/Extension/Evolution/Fulguration/Dissolution) can
    /// actually operate on — closed polygons and open curves alike, since
    /// 2026-07-13 (previously polygon-only: `.polygonSet`/`.regularPolygon`,
    /// which left curve-set sprites entirely absent from this tab's sprite
    /// list and wireframe preview, even though the underlying processing
    /// chain — `SubdivisionEngine.process` already passes `.openSpline`
    /// through untouched via `isBypassType`, and `CurveRefinementEngine`
    /// handles it explicitly — has supported curves all along).
    private func isTransformableSprite(_ sprite: SpriteDef, in cfg: ProjectConfig) -> Bool {
        guard let shape = cfg.shapeConfig.library.shapeSets
            .first(where: { $0.name == sprite.shapeSetName })?
            .shapes.first(where: { $0.name == sprite.shapeName })
        else { return false }
        return shape.sourceType == .polygonSet || shape.sourceType == .regularPolygon
            || shape.sourceType == .openCurveSet
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

// MARK: - Bake alert model

private struct BakeAlert: Identifiable {
    let id      = UUID()
    let title:   String
    let message: String
}

