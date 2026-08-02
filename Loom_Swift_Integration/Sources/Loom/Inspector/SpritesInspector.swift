import SwiftUI
import LoomEngine

struct SpritesInspector: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        guard let spriteName = controller.selectedSpriteID,
              let (setIdx, spriteIdx) = spriteLocation(named: spriteName),
              let sprite = controller.projectConfig?.spriteConfig.library
                  .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]
        else {
            LoomLogger.info("[Segments] SpritesInspector.body guard FAILED — returning EmptyView (selectedSpriteID=\(controller.selectedSpriteID ?? "nil"))")
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 0) {
            generalSection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
            cycleSection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
            transformSection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
            animationSection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
            if sprite.animation.drivers != nil {
                DriverSectionsView(setIdx: setIdx, spriteIdx: spriteIdx)
                    .environmentObject(controller)
            }
            hierarchySection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
        }
        .id("\(setIdx):\(spriteIdx)"))
    }

    // MARK: - General

    private func generalSection(sprite: SpriteDef, setIdx: Int, spriteIdx: Int) -> some View {
        InspectorSection("Sprite") {
            InspectorField("Name") {
                TextField("", text: bindS(setIdx, spriteIdx, \.name))
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 110)
            }
            .loomHelp("Name for this sprite — used in parent assignments, shape variants, and timeline identification.")
            let rendererSets = controller.projectConfig?.renderingConfig.library.rendererSets ?? []
            InspectorField("Renderer Set") {
                Picker("", selection: bindS(setIdx, spriteIdx, \.rendererSetName)) {
                    Text("None").tag("")
                    ForEach(rendererSets, id: \.name) { set in
                        Text(set.name).tag(set.name)
                    }
                }
                .labelsHidden()
                .font(.system(size: 12))
                .frame(maxWidth: 120)
            }
            .loomHelp("Renderer set that draws this sprite. Assign a set from the Rendering tab to control how the shape is painted.")
            let subdivSets = controller.projectConfig?.subdivisionConfig.paramsSets ?? []
            if !subdivSets.isEmpty {
                InspectorField("Transform set") {
                    Picker("", selection: subdivBinding(setIdx: setIdx, spriteIdx: spriteIdx)) {
                        Text("None").tag("")
                        ForEach(subdivSets, id: \.name) { set in
                            Text(set.name).tag(set.name)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 12))
                    .frame(maxWidth: 120)
                }
                .loomHelp("Transformation set applied to this sprite's geometry — controls subdivision (closed shapes) and curve refinement (open curves).")
            }
            let svgFiles = svgSpriteFiles()
            if !svgFiles.isEmpty {
                InspectorField("Image") {
                    Picker("", selection: svgFilenameBinding(setIdx: setIdx, spriteIdx: spriteIdx)) {
                        Text("None").tag("")
                        ForEach(svgFiles, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 12))
                    .frame(maxWidth: 150)
                }
                .loomHelp("Image file (SVG, PNG, JPG, TIFF, GIF) from the project's svgs/sprites/ folder. When set, renders this image instead of the polygon/renderer pipeline. Assign proxy geometry to the sprite's Shape fields for wireframe positioning.")
            }
        }
    }

    // MARK: - Cycle

    private func cycleSection(sprite: SpriteDef, setIdx: Int, spriteIdx: Int) -> some View {
        let cycles    = controller.projectConfig?.cycles ?? []
        let assigned  = sprite.cycleName
        let inherited = assigned == nil ? inheritedCycleName(for: sprite) : nil
        return InspectorSection("Cycle") {
            InspectorField("Cycle") {
                Picker("", selection: cycleBinding(setIdx: setIdx, spriteIdx: spriteIdx)) {
                    Text("None").tag(String?.none)
                    ForEach(cycles, id: \.name) { cycle in
                        Text(cycle.name).tag(String?.some(cycle.name))
                    }
                }
                .labelsHidden()
                .font(.system(size: 12))
                .frame(maxWidth: 130)
                if let name = assigned ?? inherited {
                    Button("Edit") {
                        if let idx = controller.projectConfig?.cycles.firstIndex(where: { $0.name == name }) {
                            controller.selectedCycleIndex = idx
                            controller.showingCycleEditor = true
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .loomHelp("Assign a SpriteCycle to drive this sprite's shape/renderer sequence (walk cycles, image replacement).")
            if let name = inherited {
                InspectorField("") {
                    Text("Inherited: \(name)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $controller.showingCycleEditor) {
            SpriteCycleEditorView()
                .environmentObject(controller)
        }
    }

    private func inheritedCycleName(for sprite: SpriteDef) -> String? {
        guard let config = controller.projectConfig else { return nil }
        let allSprites  = config.spriteConfig.library.spriteSets.flatMap(\.sprites)
        let byName      = Dictionary(allSprites.map { ($0.name, $0) },
                                     uniquingKeysWith: { first, _ in first })
        var cur = sprite.parentName
        while let parentName = cur {
            guard let parent = byName[parentName] else { break }
            if parent.shapeSetName.isEmpty && parent.shapeName.isEmpty,
               let cycle = parent.cycleName { return cycle }
            cur = parent.parentName
        }
        return nil
    }

    private func cycleBinding(setIdx: Int, spriteIdx: Int) -> Binding<String?> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]?.cycleName
            },
            set: { newValue in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.spriteConfig.library.spriteSets.count,
                          spriteIdx < cfg.spriteConfig.library.spriteSets[setIdx].sprites.count
                    else { return }
                    cfg.spriteConfig.library.spriteSets[setIdx].sprites[spriteIdx].cycleName = newValue
                }
            }
        )
    }

    /// Binding that maps `svgFilename: String?` to a `String` for Picker selection.
    /// Empty string represents nil (no SVG assigned).
    private func svgFilenameBinding(setIdx: Int, spriteIdx: Int) -> Binding<String> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]?.svgFilename ?? ""
            },
            set: { newValue in
                ctl.updateProjectConfig { cfg in
                    guard setIdx < cfg.spriteConfig.library.spriteSets.count,
                          spriteIdx < cfg.spriteConfig.library.spriteSets[setIdx].sprites.count
                    else { return }
                    cfg.spriteConfig.library.spriteSets[setIdx].sprites[spriteIdx]
                        .svgFilename = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }

    /// Returns image filenames (SVG, PNG, JPG, TIFF, GIF) from `svgs/sprites/`.
    private func svgSpriteFiles() -> [String] {
        guard let url = controller.projectURL else { return [] }
        let dir = url.appendingPathComponent("svgs/sprites")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        let supported: Set<String> = ["svg", "png", "jpg", "jpeg", "tiff", "tif", "gif", "webp"]
        return entries
            .filter { supported.contains($0.pathExtension.lowercased()) }
            .map    { $0.lastPathComponent }
            .sorted()
    }

    private func subdivBinding(setIdx: Int, spriteIdx: Int) -> Binding<String> {
        let ctl = controller
        return Binding(
            get: {
                guard let cfg = ctl.projectConfig,
                      let sprite = cfg.spriteConfig.library.spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]
                else { return "" }
                return cfg.shapeConfig.library.shapeSets
                    .first(where: { $0.name == sprite.shapeSetName })?
                    .shapes.first(where: { $0.name == sprite.shapeName })?
                    .subdivisionParamsSetName ?? ""
            },
            set: { newValue in
                ctl.updateProjectConfig { cfg in
                    guard let sprite = cfg.spriteConfig.library.spriteSets[safe: setIdx]?.sprites[safe: spriteIdx],
                          let ssIdx = cfg.shapeConfig.library.shapeSets.firstIndex(where: { $0.name == sprite.shapeSetName }),
                          let sIdx  = cfg.shapeConfig.library.shapeSets[ssIdx].shapes.firstIndex(where: { $0.name == sprite.shapeName })
                    else { return }
                    cfg.shapeConfig.library.shapeSets[ssIdx].shapes[sIdx].subdivisionParamsSetName = newValue
                }
            }
        )
    }

    // MARK: - Transform

    private func transformSection(sprite: SpriteDef, setIdx: Int, spriteIdx: Int) -> some View {
        let ctl = controller
        let si  = setIdx
        let pi  = spriteIdx
        return InspectorSection("Transform") {
            vec2Field("Position",
                      xBind: positionBinding(setIdx, spriteIdx, isX: true),
                      yBind: positionBinding(setIdx, spriteIdx, isX: false))
            .loomHelp("Canvas position in pixels. Origin (0,0) is top-left; positive X = right, positive Y = down.")
            vec2Field("Scale",
                      xKP: \.scale.x, yKP: \.scale.y,
                      setIdx: setIdx, spriteIdx: spriteIdx)
            .loomHelp("Scale multiplier (1.0 = original size). Applied around the sprite's anchor point.")
            InspectorField("Flip") {
                Toggle("Horizontal", isOn: Binding(
                    get: { sprite.scale.x < 0 },
                    set: { flipped in
                        ctl.updateProjectConfig { cfg in
                            guard si < cfg.spriteConfig.library.spriteSets.count,
                                  pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                            let current = cfg.spriteConfig.library.spriteSets[si].sprites[pi].scale.x
                            cfg.spriteConfig.library.spriteSets[si].sprites[pi].scale.x = flipped ? -abs(current) : abs(current)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                Toggle("Vertical", isOn: Binding(
                    get: { sprite.scale.y < 0 },
                    set: { flipped in
                        ctl.updateProjectConfig { cfg in
                            guard si < cfg.spriteConfig.library.spriteSets.count,
                                  pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                            let current = cfg.spriteConfig.library.spriteSets[si].sprites[pi].scale.y
                            cfg.spriteConfig.library.spriteSets[si].sprites[pi].scale.y = flipped ? -abs(current) : abs(current)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            }
            .loomHelp("Mirror the sprite horizontally and/or vertically by flipping the sign of Scale X/Y. Magnitude is preserved — only the sign toggles — so this combines cleanly with the Scale field. Applied around the sprite's anchor point, same as Scale.")
            InspectorField("Rotation") {
                FloatEntryField(value: rotationBinding(setIdx, spriteIdx), width: 65, fractionDigits: 2)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .loomHelp("Rotation in degrees, clockwise. Applied around the sprite's anchor point.")
            vec2Field("Pivot",
                      xBind: bindS(si, pi, \.pivotOffset.x),
                      yBind: bindS(si, pi, \.pivotOffset.y))
            .loomHelp("Rotation pivot offset in world units relative to the sprite's position. Rotation is applied around position + pivot. Drag the orange crosshair on the canvas or enter values here.")
            let hasConstraint = sprite.pivotConstraint != nil
            InspectorField("Rot range") {
                Toggle("", isOn: Binding(
                    get: { hasConstraint },
                    set: { on in
                        ctl.updateProjectConfig { cfg in
                            guard si < cfg.spriteConfig.library.spriteSets.count,
                                  pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                            cfg.spriteConfig.library.spriteSets[si].sprites[pi].pivotConstraint =
                                on ? PivotConstraint(minAngle: sprite.rotation - 45,
                                                     maxAngle: sprite.rotation + 45) : nil
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                Text("constrain rotation arc")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .loomHelp("When enabled, the sprite's rotation (including animation) is clamped to the arc between Min and Max. Drag the orange arc endpoints on the canvas to adjust. Mirrors a physical joint stop.")
            if hasConstraint {
                InspectorField("Arc min°") {
                    FloatEntryField(value: Binding(
                        get: { sprite.pivotConstraint?.minAngle ?? 0 },
                        set: { v in ctl.updateProjectConfig { cfg in
                            guard si < cfg.spriteConfig.library.spriteSets.count,
                                  pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                            cfg.spriteConfig.library.spriteSets[si].sprites[pi].pivotConstraint?.minAngle = v
                        }}
                    ), width: 65, fractionDigits: 1)
                }
                .loomHelp("Minimum allowed rotation in degrees. The sprite cannot rotate below this value regardless of animation drivers.")
                InspectorField("Arc max°") {
                    FloatEntryField(value: Binding(
                        get: { sprite.pivotConstraint?.maxAngle ?? 0 },
                        set: { v in ctl.updateProjectConfig { cfg in
                            guard si < cfg.spriteConfig.library.spriteSets.count,
                                  pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                            cfg.spriteConfig.library.spriteSets[si].sprites[pi].pivotConstraint?.maxAngle = v
                        }}
                    ), width: 65, fractionDigits: 1)
                }
                .loomHelp("Maximum allowed rotation in degrees. The sprite cannot rotate above this value regardless of animation drivers.")
            }
            InspectorField("Depth") {
                FloatEntryField(value: bindS(setIdx, spriteIdx, \.depth), width: 65, fractionDigits: 1)
                Text("0=focal").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .loomHelp("Depth relative to the focal plane for perspective projection. 0 = focal plane; positive recedes, negative comes forward.")
            InspectorField("") {
                Button("Reset Transform") {
                    ctl.updateProjectConfig { cfg in
                        guard si < cfg.spriteConfig.library.spriteSets.count,
                              pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                        else { return }
                        cfg.spriteConfig.library.spriteSets[si].sprites[pi].position    = .zero
                        cfg.spriteConfig.library.spriteSets[si].sprites[pi].scale       = Vector2D(x: 1, y: 1)
                        cfg.spriteConfig.library.spriteSets[si].sprites[pi].rotation    = 0
                        cfg.spriteConfig.library.spriteSets[si].sprites[pi].pivotOffset = .zero
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
            }
            .loomHelp("Reset position to (0,0), scale to (1,1), rotation to 0°, and pivot to (0,0).")
        }
    }

    // MARK: - Animation

    private func animationSection(sprite: SpriteDef, setIdx: Int, spriteIdx: Int) -> some View {
        let anim  = sprite.animation
        let ctl   = controller
        let si    = setIdx
        let pi    = spriteIdx
        return InspectorSection("Animation") {
            InspectorField("Enabled") {
                Toggle("", isOn: bindA(si, pi, \.enabled)).labelsHidden()
            }
            .loomHelp("Activates frame-by-frame animation for this sprite. When off, the sprite stays at its base transform.")
            InspectorField("Use Drivers") {
                Toggle("", isOn: Binding(
                    get: { ctl.projectConfig?.spriteConfig.library
                              .spriteSets[safe: si]?.sprites[safe: pi]?
                              .animation.drivers != nil },
                    set: { useDrivers in
                        ctl.updateProjectConfig { cfg in
                            guard si < cfg.spriteConfig.library.spriteSets.count,
                                  pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                            else { return }
                            cfg.spriteConfig.library.spriteSets[si].sprites[pi].animation.drivers =
                                useDrivers ? .identity : nil
                        }
                    }
                ))
                .labelsHidden()
                Text("new system").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .loomHelp("Switch to driver-based animation with independent keyframe lanes for position, scale, rotation, morph, opacity, and shape.")
            InspectorField("Gate start") {
                TextField("", value: bindSprite(setIdx, spriteIdx, \.gateStart), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 55)
                Text("0=off").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .loomHelp("First frame at which this sprite becomes visible and starts animating. 0 = no gate (active from frame 0).")
            InspectorField("Gate end") {
                TextField("", value: bindSprite(setIdx, spriteIdx, \.gateEnd), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 55)
                Text("0=off").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .loomHelp("Last frame at which this sprite is visible. 0 = no gate (stays visible through the end of playback).")
            if anim.enabled && anim.drivers == nil {
                InspectorField("Type") {
                    Picker("", selection: bindA(setIdx, spriteIdx, \.type)) {
                        ForEach(AnimationType.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 130)
                }
                .loomHelp("Animation strategy — Keyframe (interpolates between saved transforms), Random (jitters each frame), Keyframe Morph (shape morphing), Jitter Morph (random morph blend).")
                InspectorField("Loop") {
                    Picker("", selection: bindA(setIdx, spriteIdx, \.loopMode)) {
                        ForEach(LoopMode.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 100)
                }
                .loomHelp("How the animation behaves at the end — Loop (wrap to start), Ping-Pong (reverse), Once (hold at last frame).")
                InspectorField("Total draws") {
                    TextField("", value: bindA(setIdx, spriteIdx, \.totalDraws), format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 55)
                    Text("0=∞").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .loomHelp("Number of animation cycles before stopping. 0 = infinite loop.")
                rangeField("Transl X",
                           minKP: \.translationRange.x.min, maxKP: \.translationRange.x.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                .loomHelp("Min/max random translation in pixels along X per frame (Random animation mode).")
                rangeField("Transl Y",
                           minKP: \.translationRange.y.min, maxKP: \.translationRange.y.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                .loomHelp("Min/max random translation in pixels along Y per frame (Random animation mode).")
                rangeField("Scale X",
                           minKP: \.scaleRange.x.min, maxKP: \.scaleRange.x.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                .loomHelp("Min/max random scale multiplier along X per frame (Random animation mode).")
                rangeField("Scale Y",
                           minKP: \.scaleRange.y.min, maxKP: \.scaleRange.y.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                .loomHelp("Min/max random scale multiplier along Y per frame (Random animation mode).")
                rangeField("Rotation",
                           minKP: \.rotationRange.min, maxKP: \.rotationRange.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                .loomHelp("Min/max random rotation in degrees applied each frame (Random animation mode).")
                if anim.type == .jitterMorph {
                    InspectorField("Morph range") {
                        HStack(spacing: 3) {
                            FloatEntryField(value: bindA(setIdx, spriteIdx, \.morphMin),
                                            width: 54, fractionDigits: 2, fontSize: 11)
                            Text("–").font(.system(size: 10)).foregroundStyle(.tertiary)
                            FloatEntryField(value: bindA(setIdx, spriteIdx, \.morphMax),
                                            width: 54, fractionDigits: 2, fontSize: 11)
                        }
                    }
                    .loomHelp("Min/max blend amount in Jitter Morph mode (0 = base shape, 1 = fully blended to the morph target).")
                }
            }
        }
    }

    // MARK: - Hierarchy section

    private func hierarchySection(sprite: SpriteDef, setIdx si: Int, spriteIdx pi: Int) -> some View {
        let ctl        = controller
        let allNames   = ctl.projectConfig?.spriteConfig.library.spriteSets
                             .flatMap { $0.sprites }.map { $0.name } ?? []
        let otherNames = allNames.filter { $0 != sprite.name }
        let isContainer = sprite.shapeSetName.isEmpty && sprite.shapeName.isEmpty

        return InspectorSection("Hierarchy") {

            // ── Container-sprite guide + Reset Rig ──────────────────────────
            if isContainer {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Container sprite")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("""
                        This sprite has no geometry — it acts as an invisible \
                        group root. Other sprites set it as their Parent to move, \
                        rotate, or scale the whole group as one unit.

                        To set up a group:
                          1. Rename this sprite (✏ toolbar) to something \
                        meaningful, e.g. "Knight".
                          2. Select each sprite you want in the group, open its \
                        Hierarchy section, and set Parent → this sprite's name.
                          3. Come back here and add Keyframe animation drivers \
                        (Position X/Y, Rotation, Scale) to animate the whole group.
                          4. In the Sprites wireframe view (Edit tab), select this \
                        sprite to see a dashed bounding box covering all its \
                        children. Drag the interior to translate, drag corner \
                        handles to scale, drag the yellow corner handles to \
                        rotate, and drag the orange crosshair to set the \
                        rotation pivot.
                        """)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reset Rig Transforms") {
                        ctl.updateProjectConfig { cfg in
                            Self.resetRigTransforms(root: sprite.name,
                                                    setIdx: si, in: &cfg)
                        }
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Zero rotation, position, and scale on this container and all its descendants.")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // ── Parent picker ────────────────────────────────────────────────
            InspectorField("Parent") {
                Picker("", selection: Binding(
                    get: { ctl.projectConfig?.spriteConfig.library
                               .spriteSets[safe: si]?.sprites[safe: pi]?
                               .parentName ?? "" },
                    set: { name in
                        ctl.updateProjectConfig { cfg in
                            guard si < cfg.spriteConfig.library.spriteSets.count,
                                  pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                            else { return }
                            cfg.spriteConfig.library.spriteSets[si].sprites[pi].parentName =
                                name.isEmpty ? nil : name
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(otherNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 130)
            }
            .loomHelp("Parent sprite — its position, rotation, and scale propagate to this sprite. To group a figure: create a blank sprite (+○), name it, then set that name as Parent on each figure sprite.")

            if sprite.parentName != nil {
                InspectorField("Inherit") {
                    HStack(spacing: 6) {
                        Toggle("Pos", isOn: bindS(si, pi, \.inheritMask.position))
                            .toggleStyle(.checkbox).font(.system(size: 11))
                        Toggle("Rot", isOn: bindS(si, pi, \.inheritMask.rotation))
                            .toggleStyle(.checkbox).font(.system(size: 11))
                        Toggle("Scale", isOn: bindS(si, pi, \.inheritMask.scale))
                            .toggleStyle(.checkbox).font(.system(size: 11))
                    }
                }
                .loomHelp("Which parent transform components this sprite inherits — Pos (position), Rot (rotation), Scale. Uncheck any axis to break that link to the parent.")
            }
        }
    }

    // MARK: - Field helpers

    private func vec2Field(
        _ label: String,
        xKP: WritableKeyPath<SpriteDef, Double>,
        yKP: WritableKeyPath<SpriteDef, Double>,
        setIdx: Int, spriteIdx: Int
    ) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                Text("X").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 10)
                FloatEntryField(value: bindS(setIdx, spriteIdx, xKP), width: 54, fractionDigits: 2, fontSize: 11)
                Text("Y").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 10)
                FloatEntryField(value: bindS(setIdx, spriteIdx, yKP), width: 54, fractionDigits: 2, fontSize: 11)
            }
        }
    }

    private func vec2Field(
        _ label: String,
        xBind: Binding<Double>, yBind: Binding<Double>
    ) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                Text("X").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 10)
                FloatEntryField(value: xBind, width: 54, fractionDigits: 2, fontSize: 11)
                Text("Y").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 10)
                FloatEntryField(value: yBind, width: 54, fractionDigits: 2, fontSize: 11)
            }
        }
    }

    private func rangeField(
        _ label: String,
        minKP: WritableKeyPath<SpriteAnimation, Double>,
        maxKP: WritableKeyPath<SpriteAnimation, Double>,
        setIdx: Int, spriteIdx: Int
    ) -> some View {
        InspectorField(label) {
            HStack(spacing: 3) {
                FloatEntryField(value: bindA(setIdx, spriteIdx, minKP), width: 54, fractionDigits: 2, fontSize: 11)
                Text("–").font(.system(size: 10)).foregroundStyle(.tertiary)
                FloatEntryField(value: bindA(setIdx, spriteIdx, maxKP), width: 54, fractionDigits: 2, fontSize: 11)
            }
        }
    }

    // MARK: - Binding helpers

    private func spriteLocation(named name: String) -> (Int, Int)? {
        guard let lib = controller.projectConfig?.spriteConfig.library else { return nil }
        for (si, set) in lib.spriteSets.enumerated() {
            if let pi = set.sprites.firstIndex(where: { $0.name == name }) {
                return (si, pi)
            }
        }
        return nil
    }

    private func bindS<T>(_ si: Int, _ pi: Int,
                           _ kp: WritableKeyPath<SpriteDef, T>) -> Binding<T> {
        let ctl = controller
        let fallback = SpriteDef()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi][keyPath: kp] = v
                }
            }
        )
    }

    private func bindSprite<T>(_ si: Int, _ pi: Int,
                               _ kp: WritableKeyPath<SpriteDef, T>) -> Binding<T> {
        let ctl = controller
        let fallback = SpriteDef()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi][keyPath: kp] = v
                }
            }
        )
    }

    private func bindA<T>(_ si: Int, _ pi: Int,
                           _ kp: WritableKeyPath<SpriteAnimation, T>) -> Binding<T> {
        let ctl = controller
        let fallback = SpriteAnimation()[keyPath: kp]
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?.animation[keyPath: kp] ?? fallback
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi].animation[keyPath: kp] = v
                }
            }
        )
    }

    // MARK: - Propagating transform bindings

    private func positionBinding(_ si: Int, _ pi: Int, isX: Bool) -> Binding<Double> {
        let ctl = controller
        let kp: WritableKeyPath<SpriteDef, Double> = isX ? \.position.x : \.position.y
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?[keyPath: kp] ?? 0
            },
            set: { newVal in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                    let delta = newVal - cfg.spriteConfig.library.spriteSets[si].sprites[pi][keyPath: kp]
                    let name  = cfg.spriteConfig.library.spriteSets[si].sprites[pi].name
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi][keyPath: kp] = newVal
                    Self.propagatePosition(dx: isX ? delta : 0,
                                           dy: isX ? 0 : delta,
                                           from: name, in: &cfg, setIdx: si)
                }
            }
        )
    }

    private func rotationBinding(_ si: Int, _ pi: Int) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?.rotation ?? 0
            },
            set: { newRot in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count else { return }
                    let sprite = cfg.spriteConfig.library.spriteSets[si].sprites[pi]
                    let dRot   = newRot - sprite.rotation
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi].rotation = newRot
                    Self.propagateRotation(dRot: dRot,
                                           pivotX: sprite.position.x,
                                           pivotY: sprite.position.y,
                                           from: sprite.name, in: &cfg, setIdx: si)
                }
            }
        )
    }

    // MARK: - Child propagation (static so closures don't capture self)

    static func propagatePosition(
        dx: Double, dy: Double,
        from parentName: String,
        in cfg: inout ProjectConfig, setIdx: Int
    ) {
        guard setIdx < cfg.spriteConfig.library.spriteSets.count else { return }
        let sprites = cfg.spriteConfig.library.spriteSets[setIdx].sprites
        for i in sprites.indices where sprites[i].parentName == parentName {
            guard sprites[i].inheritMask.position else { continue }
            cfg.spriteConfig.library.spriteSets[setIdx].sprites[i].position.x += dx
            cfg.spriteConfig.library.spriteSets[setIdx].sprites[i].position.y += dy
            propagatePosition(dx: dx, dy: dy,
                              from: sprites[i].name, in: &cfg, setIdx: setIdx)
        }
    }

    static func propagateRotation(
        dRot: Double, pivotX: Double, pivotY: Double,
        from parentName: String,
        in cfg: inout ProjectConfig, setIdx: Int
    ) {
        guard setIdx < cfg.spriteConfig.library.spriteSets.count else { return }
        let rad = dRot * .pi / 180.0
        let cosR = cos(rad), sinR = sin(rad)
        let sprites = cfg.spriteConfig.library.spriteSets[setIdx].sprites
        for i in sprites.indices where sprites[i].parentName == parentName {
            let mask = sprites[i].inheritMask
            if mask.rotation {
                cfg.spriteConfig.library.spriteSets[setIdx].sprites[i].rotation += dRot
            }
            if mask.position {
                let ox = sprites[i].position.x - pivotX
                let oy = sprites[i].position.y - pivotY
                let newX = pivotX + ox * cosR - oy * sinR
                let newY = pivotY + ox * sinR + oy * cosR
                cfg.spriteConfig.library.spriteSets[setIdx].sprites[i].position.x = newX
                cfg.spriteConfig.library.spriteSets[setIdx].sprites[i].position.y = newY
                propagateRotation(dRot: dRot, pivotX: newX, pivotY: newY,
                                  from: sprites[i].name, in: &cfg, setIdx: setIdx)
            } else {
                propagateRotation(dRot: dRot,
                                  pivotX: sprites[i].position.x, pivotY: sprites[i].position.y,
                                  from: sprites[i].name, in: &cfg, setIdx: setIdx)
            }
        }
    }

    /// Reset rotation/position/scale to identity on the named root sprite and every
    /// descendant in the same sprite set, restoring a rig to its clean rest state.
    static func resetRigTransforms(root: String, setIdx: Int, in cfg: inout ProjectConfig) {
        guard setIdx < cfg.spriteConfig.library.spriteSets.count else { return }
        let sprites = cfg.spriteConfig.library.spriteSets[setIdx].sprites
        // Collect the root + all descendants via BFS.
        var queue   = [root]
        var visited = Set<String>()
        while !queue.isEmpty {
            let name = queue.removeFirst()
            guard !visited.contains(name) else { continue }
            visited.insert(name)
            for i in sprites.indices where sprites[i].parentName == name {
                queue.append(sprites[i].name)
            }
        }
        for i in sprites.indices where visited.contains(sprites[i].name) {
            cfg.spriteConfig.library.spriteSets[setIdx].sprites[i].rotation  = 0
            cfg.spriteConfig.library.spriteSets[setIdx].sprites[i].position  = .zero
            cfg.spriteConfig.library.spriteSets[setIdx].sprites[i].scale     = Vector2D(x: 1, y: 1)
        }
    }
}

// MARK: - Driver segment sections
//
// Wraps a base VectorDriverEditor/DoubleDriverEditor with a per-lane
// "Segments" list (named, time-bounded overrides — DriverLaneSegment).
// Deliberately two thin concrete views rather than one generic wrapper,
// matching how VectorDriverEditor/DoubleDriverEditor themselves are kept
// separate rather than unified. Does not touch VectorDriverEditor/
// DoubleDriverEditor themselves, since those are shared by camera/renderer
// inspectors that shouldn't gain segment UI they don't need. Mirrors
// CameraDriverInspector's segmentsSection/selectedSegmentDetail pattern,
// scoped to one (sprite, lane) instead of the single global camera.

private struct VectorDriverSegmentSection: View {
    let label: String
    let laneRawValue: Int
    @Binding var baseDriver: VectorDriver
    @Binding var allSegments: [DriverLaneSegment]
    @Binding var isCollapsed: Bool
    var isHighlighted: Bool = false

    @EnvironmentObject private var controller: AppController
    @State private var renamingSegmentID: UUID?  = nil
    @State private var renameText:        String = ""
    @State private var segDriverCollapsed = false

    private var laneSegments: [DriverLaneSegment] {
        allSegments.filter { $0.laneRawValue == laneRawValue }
    }
    private var selectedIndex: Int? {
        guard let id = controller.selectedSpriteSegmentID else { return nil }
        return allSegments.firstIndex { $0.id == id && $0.laneRawValue == laneRawValue }
    }

    var body: some View {
        if let idx = selectedIndex {
            selectedSegmentDetail(idx)
        } else {
            VectorDriverEditor(label: label, driver: $baseDriver, isCollapsed: $isCollapsed, isHighlighted: isHighlighted)
            segmentsSection
        }
    }

    @ViewBuilder
    private var segmentsSection: some View {
        InspectorSection("\(label) Segments") {
            if laneSegments.isEmpty {
                Text("No segments — \(label) uses the driver above for the whole timeline.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach(laneSegments) { segment in
                    segmentRow(segment)
                    Divider().padding(.leading, 12)
                }
            }
            Button {
                addSegment()
            } label: {
                Label("Add Segment", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func segmentRow(_ segment: DriverLaneSegment) -> some View {
        let isSelected = controller.selectedSpriteSegmentID == segment.id
        // A real foreground Button wrapping the whole row, not a background
        // one — logging proved a Button hidden in .background() with
        // Color.clear as its label doesn't reliably receive clicks on
        // macOS/SwiftUI. This mirrors the already-working back/duplicate/
        // delete buttons elsewhere in this same row (all real foreground
        // buttons); nested Buttons/TextFields inside a Button's label still
        // route clicks to the more specific inner control on macOS.
        return Button {
            controller.selectedSpriteSegmentID = segment.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if renamingSegmentID == segment.id {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit { commitRename(segment.id) }
                    } else {
                        Text(segment.name.isEmpty ? "Segment" : segment.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                renameText        = segment.name
                                renamingSegmentID = segment.id
                            }
                    }
                    Spacer()
                    Button { duplicateSegment(segment) } label: {
                        Image(systemName: "plus.square.on.square").font(.system(size: 10)).iconHitArea(18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .modifier(LoomHoverHelp("Duplicate segment"))
                    Button { deleteSegment(segment) } label: {
                        Image(systemName: "xmark").font(.system(size: 9)).iconHitArea(18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .modifier(LoomHoverHelp("Delete segment"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .modifier(LoomHoverHelp("Click to edit this segment's own driver (oscillator, jitter, noise, or keyframes)"))
                }
                HStack(spacing: 4) {
                    Text("Start").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("", value: frameBinding(segment.id, \.startFrame), format: .number)
                        .textFieldStyle(.squareBorder).font(.system(size: 10, design: .monospaced)).frame(width: 46)
                    Text("End").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("", value: frameBinding(segment.id, \.endFrame), format: .number)
                        .textFieldStyle(.squareBorder).font(.system(size: 10, design: .monospaced)).frame(width: 46)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectedSegmentDetail(_ idx: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                controller.selectedSpriteSegmentID = nil
            } label: {
                Label(label, systemImage: "chevron.left")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Spacer()
            Text(allSegments[idx].name.isEmpty ? "Segment" : allSegments[idx].name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        Divider()

        VectorDriverEditor(label: label, driver: segmentValueBinding(idx), isCollapsed: $segDriverCollapsed)
    }

    // MARK: - Actions

    private func addSegment() {
        let frame = controller.currentTimelineFrame
        let newSegment = DriverLaneSegment(
            name: "Segment \(laneSegments.count + 1)",
            laneRawValue: laneRawValue,
            startFrame: frame,
            endFrame: frame + 120,
            value: .vector(baseDriver)
        )
        allSegments.append(newSegment)
        controller.selectedSpriteSegmentID = newSegment.id
    }

    private func duplicateSegment(_ segment: DriverLaneSegment) {
        var copy = segment
        copy.id = UUID()
        let length = max(1, segment.endFrame - segment.startFrame)
        copy.startFrame = segment.endFrame
        copy.endFrame   = segment.endFrame + length
        copy.name       = segment.name.isEmpty ? "Segment" : "\(segment.name) copy"
        allSegments.append(copy)
        controller.selectedSpriteSegmentID = copy.id
    }

    private func deleteSegment(_ segment: DriverLaneSegment) {
        allSegments.removeAll { $0.id == segment.id }
        if controller.selectedSpriteSegmentID == segment.id {
            controller.selectedSpriteSegmentID = nil
        }
    }

    private func commitRename(_ id: UUID) {
        if let idx = allSegments.firstIndex(where: { $0.id == id }) {
            allSegments[idx].name = renameText
        }
        renamingSegmentID = nil
    }

    // MARK: - Binding helpers

    private func frameBinding(_ id: UUID, _ kp: WritableKeyPath<DriverLaneSegment, Int>) -> Binding<Int> {
        Binding(
            get: { allSegments.first(where: { $0.id == id })?[keyPath: kp] ?? 0 },
            set: { v in
                guard let idx = allSegments.firstIndex(where: { $0.id == id }) else { return }
                // No cross-field (start-vs-end) clamp here — TextField(value:format:)
                // commits per keystroke, and clamping against the other bound live
                // would snap the field back mid-typing (this exact bug was found
                // and fixed in CameraDriverInspector's endFrameBinding). An inverted
                // range is harmless: the engine's active-segment check is simply
                // never true for it, not a crash.
                allSegments[idx][keyPath: kp] = max(0, v)
            }
        )
    }

    private func segmentValueBinding(_ idx: Int) -> Binding<VectorDriver> {
        Binding(
            get: {
                guard idx < allSegments.count, case .vector(let v) = allSegments[idx].value else { return .zero }
                return v
            },
            set: { newVal in
                guard idx < allSegments.count else { return }
                allSegments[idx].value = .vector(newVal)
            }
        )
    }
}

private struct DoubleDriverSegmentSection: View {
    let label: String
    let laneRawValue: Int
    @Binding var baseDriver: DoubleDriver
    @Binding var allSegments: [DriverLaneSegment]
    @Binding var isCollapsed: Bool
    var isHighlighted: Bool = false

    @EnvironmentObject private var controller: AppController
    @State private var renamingSegmentID: UUID?  = nil
    @State private var renameText:        String = ""
    @State private var segDriverCollapsed = false

    private var laneSegments: [DriverLaneSegment] {
        allSegments.filter { $0.laneRawValue == laneRawValue }
    }
    private var selectedIndex: Int? {
        guard let id = controller.selectedSpriteSegmentID else { return nil }
        return allSegments.firstIndex { $0.id == id && $0.laneRawValue == laneRawValue }
    }

    var body: some View {
        if label == "Rotation" {
            let _ = LoomLogger.info("[Segments] DoubleDriverSegmentSection(\(label)).body: selectedSpriteSegmentID=\(controller.selectedSpriteSegmentID?.uuidString ?? "nil") selectedIndex=\(selectedIndex.map(String.init) ?? "nil") laneSegments.count=\(laneSegments.count) isCollapsed(base)=\(isCollapsed)")
        }
        if let idx = selectedIndex {
            selectedSegmentDetail(idx)
        } else {
            DoubleDriverEditor(label: label, driver: $baseDriver, isCollapsed: $isCollapsed, isHighlighted: isHighlighted)
            segmentsSection
        }
    }

    @ViewBuilder
    private var segmentsSection: some View {
        InspectorSection("\(label) Segments") {
            if laneSegments.isEmpty {
                Text("No segments — \(label) uses the driver above for the whole timeline.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach(laneSegments) { segment in
                    segmentRow(segment)
                    Divider().padding(.leading, 12)
                }
            }
            Button {
                addSegment()
            } label: {
                Label("Add Segment", systemImage: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func segmentRow(_ segment: DriverLaneSegment) -> some View {
        let isSelected = controller.selectedSpriteSegmentID == segment.id
        // A real foreground Button wrapping the whole row, not a background
        // one — logging proved a Button hidden in .background() with
        // Color.clear as its label doesn't reliably receive clicks on
        // macOS/SwiftUI. This mirrors the already-working back/duplicate/
        // delete buttons elsewhere in this same row (all real foreground
        // buttons); nested Buttons/TextFields inside a Button's label still
        // route clicks to the more specific inner control on macOS.
        return Button {
            LoomLogger.info("[Segments] DoubleDriverSegmentSection(\(label)) row Button tapped, segment.id=\(segment.id)")
            controller.selectedSpriteSegmentID = segment.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if renamingSegmentID == segment.id {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit { commitRename(segment.id) }
                    } else {
                        Text(segment.name.isEmpty ? "Segment" : segment.name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                renameText        = segment.name
                                renamingSegmentID = segment.id
                            }
                    }
                    Spacer()
                    Button { duplicateSegment(segment) } label: {
                        Image(systemName: "plus.square.on.square").font(.system(size: 10)).iconHitArea(18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .modifier(LoomHoverHelp("Duplicate segment"))
                    Button { deleteSegment(segment) } label: {
                        Image(systemName: "xmark").font(.system(size: 9)).iconHitArea(18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .modifier(LoomHoverHelp("Delete segment"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .modifier(LoomHoverHelp("Click to edit this segment's own driver (oscillator, jitter, noise, or keyframes)"))
                }
                HStack(spacing: 4) {
                    Text("Start").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("", value: frameBinding(segment.id, \.startFrame), format: .number)
                        .textFieldStyle(.squareBorder).font(.system(size: 10, design: .monospaced)).frame(width: 46)
                    Text("End").font(.system(size: 9)).foregroundStyle(.tertiary)
                    TextField("", value: frameBinding(segment.id, \.endFrame), format: .number)
                        .textFieldStyle(.squareBorder).font(.system(size: 10, design: .monospaced)).frame(width: 46)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func selectedSegmentDetail(_ idx: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                LoomLogger.info("[Segments] DoubleDriverSegmentSection(\(label)) back button tapped")
                controller.selectedSpriteSegmentID = nil
            } label: {
                Label(label, systemImage: "chevron.left")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            Spacer()
            Text(allSegments[idx].name.isEmpty ? "Segment" : allSegments[idx].name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        Divider()

        let _ = LoomLogger.info("[Segments] DoubleDriverSegmentSection(\(label)) rendering selectedSegmentDetail(idx=\(idx)), segDriverCollapsed=\(segDriverCollapsed)")
        DoubleDriverEditor(label: label, driver: segmentValueBinding(idx), isCollapsed: $segDriverCollapsed)
    }

    // MARK: - Actions

    private func addSegment() {
        LoomLogger.info("[Segments] DoubleDriverSegmentSection(\(label)).addSegment() called, laneSegments.count before=\(laneSegments.count)")
        let frame = controller.currentTimelineFrame
        let newSegment = DriverLaneSegment(
            name: "Segment \(laneSegments.count + 1)",
            laneRawValue: laneRawValue,
            startFrame: frame,
            endFrame: frame + 120,
            value: .double(baseDriver)
        )
        allSegments.append(newSegment)
        LoomLogger.info("[Segments] DoubleDriverSegmentSection(\(label)) appended segment id=\(newSegment.id), allSegments.count after=\(allSegments.count)")
        controller.selectedSpriteSegmentID = newSegment.id
        LoomLogger.info("[Segments] DoubleDriverSegmentSection(\(label)) set selectedSpriteSegmentID=\(newSegment.id)")
    }

    private func duplicateSegment(_ segment: DriverLaneSegment) {
        var copy = segment
        copy.id = UUID()
        let length = max(1, segment.endFrame - segment.startFrame)
        copy.startFrame = segment.endFrame
        copy.endFrame   = segment.endFrame + length
        copy.name       = segment.name.isEmpty ? "Segment" : "\(segment.name) copy"
        allSegments.append(copy)
        controller.selectedSpriteSegmentID = copy.id
    }

    private func deleteSegment(_ segment: DriverLaneSegment) {
        allSegments.removeAll { $0.id == segment.id }
        if controller.selectedSpriteSegmentID == segment.id {
            controller.selectedSpriteSegmentID = nil
        }
    }

    private func commitRename(_ id: UUID) {
        if let idx = allSegments.firstIndex(where: { $0.id == id }) {
            allSegments[idx].name = renameText
        }
        renamingSegmentID = nil
    }

    // MARK: - Binding helpers

    private func frameBinding(_ id: UUID, _ kp: WritableKeyPath<DriverLaneSegment, Int>) -> Binding<Int> {
        Binding(
            get: { allSegments.first(where: { $0.id == id })?[keyPath: kp] ?? 0 },
            set: { v in
                guard let idx = allSegments.firstIndex(where: { $0.id == id }) else { return }
                allSegments[idx][keyPath: kp] = max(0, v)
            }
        )
    }

    private func segmentValueBinding(_ idx: Int) -> Binding<DoubleDriver> {
        Binding(
            get: {
                guard idx < allSegments.count, case .double(let d) = allSegments[idx].value else { return .zero }
                return d
            },
            set: { newVal in
                guard idx < allSegments.count else { return }
                allSegments[idx].value = .double(newVal)
            }
        )
    }
}

// MARK: - DriverSectionsView

private struct DriverSectionsView: View {
    @EnvironmentObject var controller: AppController
    let setIdx: Int
    let spriteIdx: Int

    @State private var posCollapsed  = true
    @State private var sclCollapsed  = true
    @State private var rotCollapsed  = true
    @State private var mphCollapsed  = true
    @State private var opacCollapsed = true
    @State private var shpCollapsed  = true
    @State private var subdivSetDriverCollapsed  = true
    @State private var rendSetDriverCollapsed    = true
    @State private var cycleNameDriverCollapsed  = true
    @State private var mtCollapsed  = true
    @State private var svCollapsed  = true

    var body: some View {
        let db = driversBinding()
        VStack(alignment: .leading, spacing: 0) {
            batchEyeButton
            VectorDriverSegmentSection(label: "Position", laneRawValue: 0, baseDriver: db.position,
                               allSegments: db.segments, isCollapsed: $posCollapsed,
                               isHighlighted: selectedLane == .position)
            VectorDriverSegmentSection(label: "Scale", laneRawValue: 1, baseDriver: db.scale,
                               allSegments: db.segments, isCollapsed: $sclCollapsed,
                               isHighlighted: selectedLane == .scale)
            DoubleDriverSegmentSection(label: "Rotation", laneRawValue: 2, baseDriver: db.rotation,
                               allSegments: db.segments, isCollapsed: $rotCollapsed,
                               isHighlighted: selectedLane == .rotation)
            DoubleDriverSegmentSection(label: "Opacity", laneRawValue: 4, baseDriver: db.opacity,
                               allSegments: db.segments, isCollapsed: $opacCollapsed,
                               isHighlighted: selectedLane == .opacity)
            NameDriverEditor(
                label: "Transform Set Driver",
                driver: db.subdivisionSet,
                isCollapsed: $subdivSetDriverCollapsed,
                isHighlighted: selectedLane == .subdivisionSet,
                options: controller.projectConfig?.subdivisionConfig.paramsSets.map(\.name) ?? []
            )
            NameDriverEditor(
                label: "Renderer Set Driver",
                driver: db.rendererSet,
                isCollapsed: $rendSetDriverCollapsed,
                isHighlighted: selectedLane == .rendererSet,
                options: controller.projectConfig?.renderingConfig.library.rendererSets.map(\.name) ?? []
            )
            NameDriverEditor(
                label: "Cycle Driver",
                driver: db.cycleName,
                isCollapsed: $cycleNameDriverCollapsed,
                isHighlighted: selectedLane == .cycleName,
                options: controller.projectConfig?.cycles.map(\.name) ?? []
            )
            DoubleDriverSegmentSection(label: "Morph", laneRawValue: 3, baseDriver: db.morph,
                               allSegments: db.segments, isCollapsed: $mphCollapsed,
                               isHighlighted: selectedLane == .morph)
            morphTargetsSection
            DoubleDriverEditor(label: "Shape",    driver: db.shape,    isCollapsed: $shpCollapsed,
                               isHighlighted: selectedLane == .shape)
            shapeVariantsSection
        }
        .onAppear {
            LoomLogger.info("[Segments] DriverSectionsView.onAppear (setIdx=\(setIdx) spriteIdx=\(spriteIdx)) — about to syncCollapsed()")
            syncCollapsed()
        }
        .onDisappear {
            LoomLogger.info("[Segments] DriverSectionsView.onDisappear (setIdx=\(setIdx) spriteIdx=\(spriteIdx))")
        }
    }

    private var selectedLane: TimelineLane? {
        guard let selection = controller.selectedTimelineKF,
              selection.setIdx == setIdx,
              selection.spriteIdx == spriteIdx
        else { return nil }
        return selection.lane
    }

    // MARK: - Morph Targets

    @ViewBuilder
    private var morphTargetsSection: some View {
        // Prefer layer names from the geometry file (for multi-layer editable docs).
        // Fall back to shape names if the file is XML or has no named layers.
        let layerNames = controller.morphLayerNames(setIdx: setIdx, spriteIdx: spriteIdx)
        let sprite     = controller.projectConfig?.spriteConfig.library
                             .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]
        let shapeNames = controller.projectConfig?.shapeConfig.library.shapeSets
                             .first(where: { $0.name == sprite?.shapeSetName })?
                             .shapes.map { $0.name } ?? []
        let options    = layerNames.isEmpty ? shapeNames : layerNames
        let helpText   = layerNames.isEmpty
            ? "Shape (from this sprite's shape set) to blend toward when the Morph driver reaches 1.0."
            : "Layer name within the sprite's geometry file to blend toward when the Morph driver reaches 1.0."
        let mtBinding  = morphTargetNamesBinding()
        InspectorSection("Morph Targets", isCollapsed: $mtCollapsed) {
            ForEach(mtBinding.wrappedValue.indices, id: \.self) { i in
                InspectorField("Target \(i + 1)") {
                    Picker("", selection: Binding(
                        get: { mtBinding.wrappedValue[safe: i] ?? "" },
                        set: { newVal in
                            var arr = mtBinding.wrappedValue
                            if i < arr.count { arr[i] = newVal }
                            mtBinding.wrappedValue = arr
                        }
                    )) {
                        Text("— none —").tag("")
                        ForEach(options, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    Button {
                        var arr = mtBinding.wrappedValue
                        arr.remove(at: i)
                        mtBinding.wrappedValue = arr
                    } label: {
                        Image(systemName: "minus.circle").font(.system(size: 11))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .loomHelp(helpText)
            }
            Button {
                var arr = mtBinding.wrappedValue
                arr.append(options.first(where: { !arr.contains($0) }) ?? "")
                mtBinding.wrappedValue = arr
            } label: {
                Label("Add target", systemImage: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    // MARK: - Shape Variants

    @ViewBuilder
    private var shapeVariantsSection: some View {
        let spriteSet  = controller.projectConfig?.spriteConfig.library.spriteSets[safe: setIdx]
        let selfName   = spriteSet?.sprites[safe: spriteIdx]?.name ?? ""
        let otherNames = spriteSet?.sprites.map { $0.name }.filter { $0 != selfName } ?? []
        let svBinding  = spriteVariantsBinding()
        let imgFiles   = svgSpriteFiles()
        InspectorSection("Shape Variants", isCollapsed: $svCollapsed) {
            ForEach(svBinding.wrappedValue.indices, id: \.self) { i in
                InspectorField("Variant \(i + 1)") {
                    Picker("", selection: Binding(
                        get: { svBinding.wrappedValue[safe: i]?.spriteName ?? "" },
                        set: { newVal in
                            var arr = svBinding.wrappedValue
                            if i < arr.count {
                                arr[i] = SpriteVariantEntry(spriteName: newVal,
                                                            imageFilename: arr[i].imageFilename)
                            }
                            svBinding.wrappedValue = arr
                        }
                    )) {
                        ForEach(otherNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 120)
                    if !imgFiles.isEmpty {
                        Picker("", selection: Binding(
                            get: { svBinding.wrappedValue[safe: i]?.imageFilename ?? "" },
                            set: { newVal in
                                var arr = svBinding.wrappedValue
                                if i < arr.count {
                                    arr[i] = SpriteVariantEntry(spriteName: arr[i].spriteName,
                                                                imageFilename: newVal.isEmpty ? nil : newVal)
                                }
                                svBinding.wrappedValue = arr
                            }
                        )) {
                            Text("—").tag("")
                            ForEach(imgFiles, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 120)
                    }
                    Button {
                        var arr = svBinding.wrappedValue
                        arr.remove(at: i)
                        svBinding.wrappedValue = arr
                    } label: {
                        Image(systemName: "minus.circle").font(.system(size: 11))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .loomHelp("Alternative sprite whose geometry and renderer are swapped in by the Shape driver. Optionally assign an image file to render a bitmap/SVG instead of the polygon pipeline for this variant.")
            }
            Button {
                var arr = svBinding.wrappedValue
                arr.append(SpriteVariantEntry(spriteName: otherNames.first(where: { !arr.map(\.spriteName).contains($0) }) ?? ""))
                svBinding.wrappedValue = arr
            } label: {
                Label("Add variant", systemImage: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    // MARK: - Collapse sync

    private func syncCollapsed() {
        guard let d = currentDrivers else {
            LoomLogger.info("[Segments] syncCollapsed: currentDrivers is nil, skipping")
            return
        }
        posCollapsed  = !d.position.enabled      && d.position.keyframes.isEmpty
        sclCollapsed  = !d.scale.enabled         && d.scale.keyframes.isEmpty
        rotCollapsed  = !d.rotation.enabled      && d.rotation.keyframes.isEmpty
        LoomLogger.info("[Segments] syncCollapsed: rotation.enabled=\(d.rotation.enabled) rotation.keyframes.isEmpty=\(d.rotation.keyframes.isEmpty) -> rotCollapsed=\(rotCollapsed), segments.count=\(d.segments.count)")
        mphCollapsed  = !d.morph.enabled         && d.morph.keyframes.isEmpty
        opacCollapsed = !d.opacity.enabled       && d.opacity.keyframes.isEmpty
        shpCollapsed  = !d.shape.enabled         && d.shape.keyframes.isEmpty
        subdivSetDriverCollapsed = !d.subdivisionSet.enabled && d.subdivisionSet.keyframes.isEmpty
        rendSetDriverCollapsed   = !d.rendererSet.enabled   && d.rendererSet.keyframes.isEmpty
        cycleNameDriverCollapsed = !d.cycleName.enabled     && d.cycleName.keyframes.isEmpty
        let sprite = controller.projectConfig?.spriteConfig.library
                         .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]
        mtCollapsed = sprite?.morphTargetNames.isEmpty != false
        svCollapsed = sprite?.spriteVariants.isEmpty != false
    }

    private var currentDrivers: TransformDrivers? {
        controller.projectConfig?.spriteConfig.library
            .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]?
            .animation.drivers
    }

    private var driverCollapsedCount: Int {
        [posCollapsed, sclCollapsed, rotCollapsed, mphCollapsed, opacCollapsed, shpCollapsed,
         subdivSetDriverCollapsed, rendSetDriverCollapsed, cycleNameDriverCollapsed]
            .filter { $0 }.count
    }

    private var unusedDriverCount: Int {
        guard let d = currentDrivers else { return 0 }
        return [
            !d.position.enabled      && d.position.keyframes.isEmpty      && !posCollapsed,
            !d.scale.enabled         && d.scale.keyframes.isEmpty         && !sclCollapsed,
            !d.rotation.enabled      && d.rotation.keyframes.isEmpty      && !rotCollapsed,
            !d.morph.enabled         && d.morph.keyframes.isEmpty         && !mphCollapsed,
            !d.opacity.enabled       && d.opacity.keyframes.isEmpty       && !opacCollapsed,
            !d.shape.enabled         && d.shape.keyframes.isEmpty         && !shpCollapsed,
            !d.subdivisionSet.enabled && d.subdivisionSet.keyframes.isEmpty && !subdivSetDriverCollapsed,
            !d.rendererSet.enabled   && d.rendererSet.keyframes.isEmpty   && !rendSetDriverCollapsed,
            !d.cycleName.enabled     && d.cycleName.keyframes.isEmpty     && !cycleNameDriverCollapsed,
        ].filter { $0 }.count
    }

    private func collapseUnusedDriverSections() {
        guard let d = currentDrivers else { return }
        if !d.position.enabled      && d.position.keyframes.isEmpty      { posCollapsed = true }
        if !d.scale.enabled         && d.scale.keyframes.isEmpty         { sclCollapsed = true }
        if !d.rotation.enabled      && d.rotation.keyframes.isEmpty      { rotCollapsed = true }
        if !d.morph.enabled         && d.morph.keyframes.isEmpty         { mphCollapsed = true }
        if !d.opacity.enabled       && d.opacity.keyframes.isEmpty       { opacCollapsed = true }
        if !d.shape.enabled         && d.shape.keyframes.isEmpty         { shpCollapsed = true }
        if !d.subdivisionSet.enabled && d.subdivisionSet.keyframes.isEmpty { subdivSetDriverCollapsed = true }
        if !d.rendererSet.enabled   && d.rendererSet.keyframes.isEmpty   { rendSetDriverCollapsed = true }
        if !d.cycleName.enabled     && d.cycleName.keyframes.isEmpty     { cycleNameDriverCollapsed = true }
    }

    private func expandAllDriverSections() {
        posCollapsed = false; sclCollapsed = false; rotCollapsed = false
        mphCollapsed = false; opacCollapsed = false; shpCollapsed = false
        subdivSetDriverCollapsed = false; rendSetDriverCollapsed = false; cycleNameDriverCollapsed = false
    }

    @ViewBuilder
    private var batchEyeButton: some View {
        let collapsed = driverCollapsedCount
        if collapsed > 0 {
            HStack {
                Spacer()
                Button { expandAllDriverSections() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash").font(.system(size: 10))
                        Text("\(collapsed)").font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .loomHelp("\(collapsed) driver section\(collapsed == 1 ? "" : "s") collapsed. Click to expand all.")
                .padding(.trailing, 12)
                .padding(.vertical, 4)
            }
        } else if unusedDriverCount > 0 {
            HStack {
                Spacer()
                Button { collapseUnusedDriverSections() } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .iconHitArea()
                }
                .buttonStyle(.plain)
                .loomHelp("Collapse all driver sections that are disabled and have no keyframes.")
                .padding(.trailing, 12)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Bindings

    private func driversBinding() -> Binding<TransformDrivers> {
        let ctl = controller; let si = setIdx; let pi = spriteIdx
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?
                    .animation.drivers ?? .identity
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                    else { return }
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi].animation.drivers = v
                }
            }
        )
    }

    private func morphTargetNamesBinding() -> Binding<[String]> {
        let ctl = controller; let si = setIdx; let pi = spriteIdx
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?.morphTargetNames ?? []
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                    else { return }
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi].morphTargetNames = v
                }
            }
        )
    }

    private func svgSpriteFiles() -> [String] {
        guard let url = controller.projectURL else { return [] }
        let dir = url.appendingPathComponent("svgs/sprites")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        let supported: Set<String> = ["svg", "png", "jpg", "jpeg", "tiff", "tif", "gif", "webp"]
        return entries
            .filter { supported.contains($0.pathExtension.lowercased()) }
            .map    { $0.lastPathComponent }
            .sorted()
    }

    private func spriteVariantsBinding() -> Binding<[SpriteVariantEntry]> {
        let ctl = controller; let si = setIdx; let pi = spriteIdx
        return Binding(
            get: {
                ctl.projectConfig?.spriteConfig.library
                    .spriteSets[safe: si]?.sprites[safe: pi]?.spriteVariants ?? []
            },
            set: { v in
                ctl.updateProjectConfig { cfg in
                    guard si < cfg.spriteConfig.library.spriteSets.count,
                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                    else { return }
                    cfg.spriteConfig.library.spriteSets[si].sprites[pi].spriteVariants = v
                }
            }
        )
    }
}

// MARK: - Display names

private extension AnimationType {
    var displayName: String {
        switch self {
        case .keyframe:      return "Keyframe"
        case .random:        return "Random"
        case .keyframeMorph: return "Keyframe Morph"
        case .jitterMorph:   return "Jitter Morph"
        }
    }
}

private extension LoopMode {
    var displayName: String {
        switch self {
        case .loop:     return "Loop"
        case .pingPong: return "Ping-Pong"
        case .once:     return "Once"
        }
    }
}
