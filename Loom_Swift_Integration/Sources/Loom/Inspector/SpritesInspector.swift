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
            transformSection(setIdx: setIdx, spriteIdx: spriteIdx)
            animationSection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
            if sprite.animation.drivers != nil {
                driverSections(setIdx: setIdx, spriteIdx: spriteIdx)
            }
            hierarchySection(sprite: sprite, setIdx: setIdx, spriteIdx: spriteIdx)
        })
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
            }
        }
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

    private func transformSection(setIdx: Int, spriteIdx: Int) -> some View {
        InspectorSection("Transform") {
            vec2Field("Position",
                      xKP: \.position.x, yKP: \.position.y,
                      setIdx: setIdx, spriteIdx: spriteIdx)
            vec2Field("Scale",
                      xKP: \.scale.x, yKP: \.scale.y,
                      setIdx: setIdx, spriteIdx: spriteIdx)
            InspectorField("Rotation") {
                FloatEntryField(value: bindS(setIdx, spriteIdx, \.rotation), width: 65, fractionDigits: 2)
                Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
            }
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
            InspectorField("Gate start") {
                TextField("", value: bindSprite(setIdx, spriteIdx, \.gateStart), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 55)
                Text("0=off").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            InspectorField("Gate end") {
                TextField("", value: bindSprite(setIdx, spriteIdx, \.gateEnd), format: .number)
                    .textFieldStyle(.squareBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 55)
                Text("0=off").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
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
                InspectorField("Loop") {
                    Picker("", selection: bindA(setIdx, spriteIdx, \.loopMode)) {
                        ForEach(LoopMode.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 100)
                }
                InspectorField("Total draws") {
                    TextField("", value: bindA(setIdx, spriteIdx, \.totalDraws), format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 55)
                    Text("0=∞").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                rangeField("Transl X",
                           minKP: \.translationRange.x.min, maxKP: \.translationRange.x.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                rangeField("Transl Y",
                           minKP: \.translationRange.y.min, maxKP: \.translationRange.y.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                rangeField("Scale X",
                           minKP: \.scaleRange.x.min, maxKP: \.scaleRange.x.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                rangeField("Scale Y",
                           minKP: \.scaleRange.y.min, maxKP: \.scaleRange.y.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
                rangeField("Rotation",
                           minKP: \.rotationRange.min, maxKP: \.rotationRange.max,
                           setIdx: setIdx, spriteIdx: spriteIdx)
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
                }
            }
        }
    }

    // MARK: - Driver sections

    @ViewBuilder
    private func driverSections(setIdx si: Int, spriteIdx pi: Int) -> some View {
        let db = driversBinding(si, pi)
        VectorDriverEditor(label: "Position", driver: db.position)
        VectorDriverEditor(label: "Scale",    driver: db.scale)
        DoubleDriverEditor(label: "Rotation", driver: db.rotation)
        DoubleDriverEditor(label: "Morph",    driver: db.morph)
        DoubleDriverEditor(label: "Shape",    driver: db.shape)
        morphTargetsSection(setIdx: si, spriteIdx: pi)
        spriteVariantsSection(setIdx: si, spriteIdx: pi)
    }

    @ViewBuilder
    private func spriteVariantsSection(setIdx si: Int, spriteIdx pi: Int) -> some View {
        let sameSetSprites = controller.projectConfig?.spriteConfig.library
            .spriteSets[safe: si]?.sprites ?? []
        let currentName = sameSetSprites[safe: pi]?.name ?? ""
        let variants = controller.projectConfig?.spriteConfig.library
            .spriteSets[safe: si]?.sprites[safe: pi]?.spriteVariants ?? []

        if !variants.isEmpty || !sameSetSprites.filter({ $0.name != currentName }).isEmpty {
            InspectorSection("Shape Variants") {
                ForEach(variants.indices, id: \.self) { idx in
                    InspectorField("[\(idx + 1)]") {
                        Text(variants[idx])
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            controller.updateProjectConfig { cfg in
                                guard si < cfg.spriteConfig.library.spriteSets.count,
                                      pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                                else { return }
                                cfg.spriteConfig.library.spriteSets[si].sprites[pi].spriteVariants.remove(at: idx)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                let addable = sameSetSprites.filter { s in
                    s.name != currentName && !variants.contains(s.name)
                }
                if !addable.isEmpty {
                    InspectorField("Add") {
                        Picker("", selection: Binding<String>(
                            get: { "" },
                            set: { name in
                                guard !name.isEmpty else { return }
                                controller.updateProjectConfig { cfg in
                                    guard si < cfg.spriteConfig.library.spriteSets.count,
                                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                                    else { return }
                                    cfg.spriteConfig.library.spriteSets[si].sprites[pi].spriteVariants.append(name)
                                }
                            }
                        )) {
                            Text("—").tag("")
                            ForEach(addable, id: \.name) { s in
                                Text(s.name).tag(s.name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 130)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func morphTargetsSection(setIdx si: Int, spriteIdx pi: Int) -> some View {
        let shapeSetName = controller.projectConfig?.spriteConfig.library
            .spriteSets[safe: si]?.sprites[safe: pi]?.shapeSetName ?? ""
        let baseShapeName = controller.projectConfig?.spriteConfig.library
            .spriteSets[safe: si]?.sprites[safe: pi]?.shapeName ?? ""
        let allShapeNames = controller.projectConfig?.shapeConfig.library
            .shapeSets.first(where: { $0.name == shapeSetName })?
            .shapes.map(\.name) ?? []
        let targets = controller.projectConfig?.spriteConfig.library
            .spriteSets[safe: si]?.sprites[safe: pi]?.morphTargetNames ?? []

        if !targets.isEmpty || allShapeNames.filter({ $0 != baseShapeName }).count > 0 {
            InspectorSection("Morph Targets") {
                ForEach(targets.indices, id: \.self) { idx in
                    InspectorField("[\(idx + 1)]") {
                        Text(targets[idx])
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            controller.updateProjectConfig { cfg in
                                guard si < cfg.spriteConfig.library.spriteSets.count,
                                      pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                                else { return }
                                cfg.spriteConfig.library.spriteSets[si].sprites[pi].morphTargetNames.remove(at: idx)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                let addable = allShapeNames.filter { n in
                    n != baseShapeName && !targets.contains(n)
                }
                if !addable.isEmpty {
                    InspectorField("Add") {
                        Picker("", selection: Binding<String>(
                            get: { "" },
                            set: { name in
                                guard !name.isEmpty else { return }
                                controller.updateProjectConfig { cfg in
                                    guard si < cfg.spriteConfig.library.spriteSets.count,
                                          pi < cfg.spriteConfig.library.spriteSets[si].sprites.count
                                    else { return }
                                    cfg.spriteConfig.library.spriteSets[si].sprites[pi].morphTargetNames.append(name)
                                }
                            }
                        )) {
                            Text("—").tag("")
                            ForEach(addable, id: \.self) { n in
                                Text(n).tag(n)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 130)
                    }
                }
            }
        }
    }

    private func driversBinding(_ si: Int, _ pi: Int) -> Binding<TransformDrivers> {
        let ctl = controller
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
