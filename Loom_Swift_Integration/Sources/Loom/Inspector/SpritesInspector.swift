import SwiftUI
import LoomEngine

struct SpritesInspector: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        guard let spriteName = controller.selectedSpriteID,
              let (setIdx, spriteIdx) = spriteLocation(named: spriteName),
              let sprite = controller.projectConfig?.spriteConfig.library
                  .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]
        else { return AnyView(EmptyView()) }

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
                InspectorField("Subdiv set") {
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
                .loomHelp("Subdivision parameter set applied to this sprite's geometry before drawing.")
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
        let cycles = controller.projectConfig?.cycles ?? []
        let assigned = sprite.cycleName
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
                if let name = assigned {
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
        }
        .sheet(isPresented: $controller.showingCycleEditor) {
            SpriteCycleEditorView()
                .environmentObject(controller)
        }
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
        let ctl       = controller
        let allNames  = ctl.projectConfig?.spriteConfig.library.spriteSets
                            .flatMap { $0.sprites }.map { $0.name } ?? []
        let otherNames = allNames.filter { $0 != sprite.name }

        return InspectorSection("Hierarchy") {
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
            .loomHelp("Sprite that this sprite is attached to. Position/rotation changes on the parent propagate to children per the Inherit settings.")
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
                .loomHelp("Which parent transform components are inherited — Pos (position offset), Rot (rotation), Scale (scale multiplier).")
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
            VectorDriverEditor(label: "Position", driver: db.position, isCollapsed: $posCollapsed,
                               isHighlighted: selectedLane == .position)
            VectorDriverEditor(label: "Scale",    driver: db.scale,    isCollapsed: $sclCollapsed,
                               isHighlighted: selectedLane == .scale)
            DoubleDriverEditor(label: "Rotation", driver: db.rotation, isCollapsed: $rotCollapsed,
                               isHighlighted: selectedLane == .rotation)
            DoubleDriverEditor(label: "Opacity",  driver: db.opacity,  isCollapsed: $opacCollapsed,
                               isHighlighted: selectedLane == .opacity)
            NameDriverEditor(
                label: "Subdivision Set Driver",
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
            DoubleDriverEditor(label: "Morph",    driver: db.morph,    isCollapsed: $mphCollapsed,
                               isHighlighted: selectedLane == .morph)
            morphTargetsSection
            DoubleDriverEditor(label: "Shape",    driver: db.shape,    isCollapsed: $shpCollapsed,
                               isHighlighted: selectedLane == .shape)
            shapeVariantsSection
        }
        .onAppear { syncCollapsed() }
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
        guard let d = currentDrivers else { return }
        posCollapsed  = !d.position.enabled      && d.position.keyframes.isEmpty
        sclCollapsed  = !d.scale.enabled         && d.scale.keyframes.isEmpty
        rotCollapsed  = !d.rotation.enabled      && d.rotation.keyframes.isEmpty
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
