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
                DriverSectionsView(setIdx: setIdx, spriteIdx: spriteIdx)
                    .environmentObject(controller)
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

// MARK: - DriverSectionsView

private struct DriverSectionsView: View {
    @EnvironmentObject var controller: AppController
    let setIdx: Int
    let spriteIdx: Int

    @State private var posCollapsed = true
    @State private var sclCollapsed = true
    @State private var rotCollapsed = true
    @State private var mphCollapsed = true
    @State private var shpCollapsed = true
    @State private var mtCollapsed  = true
    @State private var svCollapsed  = true

    var body: some View {
        let db = driversBinding()
        Group {
            VectorDriverEditor(label: "Position", driver: db.position, isCollapsed: $posCollapsed)
            VectorDriverEditor(label: "Scale",    driver: db.scale,    isCollapsed: $sclCollapsed)
            DoubleDriverEditor(label: "Rotation", driver: db.rotation, isCollapsed: $rotCollapsed)
            DoubleDriverEditor(label: "Morph",    driver: db.morph,    isCollapsed: $mphCollapsed)
            DoubleDriverEditor(label: "Shape",    driver: db.shape,    isCollapsed: $shpCollapsed)
            morphTargetsSection
            shapeVariantsSection
        }
        .onAppear { syncCollapsed() }
        .onChange(of: "\(setIdx):\(spriteIdx)") { _, _ in syncCollapsed() }
    }

    // MARK: - Morph Targets

    @ViewBuilder
    private var morphTargetsSection: some View {
        let sprite    = controller.projectConfig?.spriteConfig.library
                            .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]
        let allShapes = controller.projectConfig?.shapeConfig.library.shapeSets
                            .first(where: { $0.name == sprite?.shapeSetName })?
                            .shapes.map { $0.name } ?? []
        let mtBinding = morphTargetNamesBinding()
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
                        ForEach(allShapes, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    Button {
                        var arr = mtBinding.wrappedValue
                        arr.remove(at: i)
                        mtBinding.wrappedValue = arr
                    } label: {
                        Image(systemName: "minus.circle").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Button {
                var arr = mtBinding.wrappedValue
                arr.append(allShapes.first(where: { !arr.contains($0) }) ?? "")
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
        InspectorSection("Shape Variants", isCollapsed: $svCollapsed) {
            ForEach(svBinding.wrappedValue.indices, id: \.self) { i in
                InspectorField("Variant \(i + 1)") {
                    Picker("", selection: Binding(
                        get: { svBinding.wrappedValue[safe: i] ?? "" },
                        set: { newVal in
                            var arr = svBinding.wrappedValue
                            if i < arr.count { arr[i] = newVal }
                            svBinding.wrappedValue = arr
                        }
                    )) {
                        ForEach(otherNames, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 150)
                    Button {
                        var arr = svBinding.wrappedValue
                        arr.remove(at: i)
                        svBinding.wrappedValue = arr
                    } label: {
                        Image(systemName: "minus.circle").font(.system(size: 11))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Button {
                var arr = svBinding.wrappedValue
                arr.append(otherNames.first(where: { !arr.contains($0) }) ?? "")
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
        posCollapsed = !isVectorInUse(d.position, identity: .zero)
        sclCollapsed = !isVectorInUse(d.scale, identity: Vector2D(x: 1, y: 1))
        rotCollapsed = !isDoubleInUse(d.rotation)
        mphCollapsed = !isDoubleInUse(d.morph)
        shpCollapsed = !isDoubleInUse(d.shape)
        let sprite   = controller.projectConfig?.spriteConfig.library
                           .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]
        mtCollapsed  = sprite?.morphTargetNames.isEmpty != false
        svCollapsed  = sprite?.spriteVariants.isEmpty != false
    }

    private var currentDrivers: TransformDrivers? {
        controller.projectConfig?.spriteConfig.library
            .spriteSets[safe: setIdx]?.sprites[safe: spriteIdx]?
            .animation.drivers
    }

    private func isDoubleInUse(_ d: DoubleDriver) -> Bool {
        d.mode != .constant || !d.keyframes.isEmpty || d.base != 0
    }

    private func isVectorInUse(_ d: VectorDriver, identity: Vector2D) -> Bool {
        d.mode != .constant || !d.keyframes.isEmpty || d.base != identity
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

    private func spriteVariantsBinding() -> Binding<[String]> {
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
