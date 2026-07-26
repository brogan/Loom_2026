import SwiftUI
import LoomEngine

/// Right-panel inspector for the Live tab's currently selected staged
/// sprite: renderer-set / transform-set assignment (instant, non-driver
/// swap) plus the 9 `TransformDrivers` on/off toggles — `LoomLiveV1Scope.md` §2.1.
struct LiveInspector: View {

    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var liveController: LiveSessionController

    private var selectedStaged: LiveSessionController.StagedSprite? {
        guard let id = liveController.selectedStagedID else { return nil }
        return liveController.stagedSprites.first(where: { $0.id == id })
    }

    private var rendererSetNames: [String] {
        controller.projectConfig?.renderingConfig.library.rendererSets.map(\.name) ?? []
    }

    private var subdivisionSetNames: [String] {
        controller.projectConfig?.subdivisionConfig.paramsSets.map(\.name) ?? []
    }

    var body: some View {
        if let staged = selectedStaged {
            VStack(alignment: .leading, spacing: 12) {
                Text(staged.spriteDefName)
                    .font(.system(size: 13, weight: .semibold))

                setsSection(staged)

                Divider()

                driversSection(staged)

                Spacer()
            }
            .padding(12)
        } else {
            Text("Stage a sprite to configure it here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }

    // MARK: - Set assignment

    private func setsSection(_ staged: LiveSessionController.StagedSprite) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sets")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack {
                Text("Renderer").font(.system(size: 11)).frame(width: 90, alignment: .leading)
                Picker("", selection: Binding(
                    get: { staged.rendererSetName ?? "" },
                    set: { liveController.assignRendererSet(staged.id, name: $0) }
                )) {
                    Text("—").tag("")
                    ForEach(rendererSetNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            HStack {
                Text("Transform").font(.system(size: 11)).frame(width: 90, alignment: .leading)
                Picker("", selection: Binding(
                    get: { staged.subdivisionSetName ?? "" },
                    set: { liveController.assignSubdivisionSet(staged.id, name: $0) }
                )) {
                    Text("—").tag("")
                    ForEach(subdivisionSetNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: - Driver toggles + Rate/Range

    /// Only shows drivers this sprite's own authoring actually configured
    /// (`StagedSprite.configuredDrivers`) — the other driver slots exist on
    /// every sprite but do nothing when toggled (identity params), so
    /// listing all 9 regardless of relevance was just noise.
    private func driversSection(_ staged: LiveSessionController.StagedSprite) -> some View {
        let relevant = LiveDriverKey.allCases.filter { staged.configuredDrivers.contains($0) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Drivers")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if relevant.isEmpty {
                Text("This sprite has no configured drivers.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relevant, id: \.self) { key in
                    driverRow(staged, key)
                }
            }
        }
    }

    private func driverRow(_ staged: LiveSessionController.StagedSprite, _ key: LiveDriverKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(key.rawValue, isOn: Binding(
                get: { staged.driverEnabled[key] ?? false },
                set: { liveController.toggleDriver(staged.id, key, $0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))

            if let info = staged.driverControls[key] {
                rateRangeControls(staged, key, info)
                    .padding(.leading, 18)
            }
        }
    }

    /// The generalized Rate/Range sliders for one configured driver — Rate
    /// only appears for oscillator/noise modes (jitter re-rolls every frame,
    /// no periodicity to tune); Range always applies. Vector-backed drivers
    /// (position/scale) get an X and Y slider; scalar drivers get one.
    /// Dragging either slider also surfaces the real underlying field name
    /// and value in the top info bar, and a "Save to Sprite" button writes
    /// the live-tweaked values back into the project's saved sprite —
    /// building the bridge from live experimentation back to authored state.
    private func rateRangeControls(
        _ staged: LiveSessionController.StagedSprite, _ key: LiveDriverKey,
        _ info: LiveSessionController.DriverControlInfo
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if info.hasRate {
                sliderRow(
                    uiLabel: "Rate", fieldName: rateFieldName(info), bounds: info.rateBounds,
                    x: Binding(
                        get: { staged.driverControls[key]?.rateX ?? info.rateX },
                        set: { liveController.updateDriverRate(staged.id, key, x: $0, y: staged.driverControls[key]?.rateY) }
                    ),
                    y: (info.isVector && info.mode == "oscillator") ? Binding(
                        get: { staged.driverControls[key]?.rateY ?? info.rateY },
                        set: { liveController.updateDriverRate(staged.id, key, x: staged.driverControls[key]?.rateX ?? info.rateX, y: $0) }
                    ) : nil
                )
            }
            sliderRow(
                uiLabel: "Range", fieldName: rangeFieldName(info), bounds: info.rangeBounds,
                x: Binding(
                    get: { staged.driverControls[key]?.rangeX ?? info.rangeX },
                    set: { liveController.updateDriverRange(staged.id, key, x: $0, y: staged.driverControls[key]?.rangeY) }
                ),
                y: info.isVector ? Binding(
                    get: { staged.driverControls[key]?.rangeY ?? info.rangeY },
                    set: { liveController.updateDriverRange(staged.id, key, x: staged.driverControls[key]?.rangeX ?? info.rangeX, y: $0) }
                ) : nil
            )
            saveButton(staged, key)
        }
    }

    private func rateFieldName(_ info: LiveSessionController.DriverControlInfo) -> String {
        info.mode == "oscillator" ? "freqHz" : "period"
    }

    private func rangeFieldName(_ info: LiveSessionController.DriverControlInfo) -> String {
        info.mode == "jitter" ? "range" : "amplitude"
    }

    /// Wraps the caller's x/y bindings so every drag tick also writes the
    /// real serializable field name and value into the top info bar
    /// (`AppController.hoverHelpText`, the same mechanism `.loomHelp` uses
    /// elsewhere) — lets the user watch exactly what number they're
    /// producing, to build intuition for hand-editing it in the Sprites tab.
    private func sliderRow(
        uiLabel: String, fieldName: String, bounds: ClosedRange<Double>,
        x: Binding<Double>, y: Binding<Double>?
    ) -> some View {
        HStack(spacing: 4) {
            Text(uiLabel)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            Slider(value: Binding(
                get: { x.wrappedValue },
                set: { newValue in
                    x.wrappedValue = newValue
                    let suffix = y == nil ? "" : ".x"
                    controller.hoverHelpText = "\(fieldName)\(suffix) = \(String(format: "%.3f", newValue))"
                }
            ), in: bounds)
            if let y {
                Slider(value: Binding(
                    get: { y.wrappedValue },
                    set: { newValue in
                        y.wrappedValue = newValue
                        controller.hoverHelpText = "\(fieldName).y = \(String(format: "%.3f", newValue))"
                    }
                ), in: bounds)
            }
        }
    }

    // MARK: - Save to Sprite

    private func saveButton(_ staged: LiveSessionController.StagedSprite, _ key: LiveDriverKey) -> some View {
        Button {
            saveDriverToSprite(staged, key)
        } label: {
            Label("Save to Sprite", systemImage: "square.and.arrow.down")
                .font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .modifier(LoomHoverHelp("Write this driver's current live Rate/Range/enabled values back into the saved sprite."))
    }

    /// Writes the live-tweaked enabled/rate/range values for `key` back into
    /// the project's actual saved `SpriteDef`, via the same
    /// `AppController.updateProjectConfig` mutation path every other tab
    /// uses — a normal, undoable, auto-saved edit, not a Live-tab-only thing.
    private func saveDriverToSprite(_ staged: LiveSessionController.StagedSprite, _ key: LiveDriverKey) {
        let enabled = staged.driverEnabled[key] ?? false
        let info = staged.driverControls[key]
        controller.updateProjectConfig { config in
            guard let setIdx = config.spriteConfig.library.spriteSets.firstIndex(where: { $0.name == staged.spriteSetName })
            else { return }
            guard let spriteIdx = config.spriteConfig.library.spriteSets[setIdx].sprites.firstIndex(where: { $0.name == staged.spriteDefName })
            else { return }

            var sprite = config.spriteConfig.library.spriteSets[setIdx].sprites[spriteIdx]
            var drivers = sprite.animation.drivers ?? .identity

            switch key {
            case .position:
                drivers.position.enabled = enabled
                if let info {
                    drivers.position.applyRateRange(
                        rateX: info.hasRate ? info.rateX : nil, rateY: info.hasRate ? info.rateY : nil,
                        rangeX: info.rangeX, rangeY: info.rangeY
                    )
                }
            case .scale:
                drivers.scale.enabled = enabled
                if let info {
                    drivers.scale.applyRateRange(
                        rateX: info.hasRate ? info.rateX : nil, rateY: info.hasRate ? info.rateY : nil,
                        rangeX: info.rangeX, rangeY: info.rangeY
                    )
                }
            case .rotation:
                drivers.rotation.enabled = enabled
                if let info { drivers.rotation.applyRateRange(rate: info.hasRate ? info.rateX : nil, range: info.rangeX) }
            case .morph:
                drivers.morph.enabled = enabled
                if let info { drivers.morph.applyRateRange(rate: info.hasRate ? info.rateX : nil, range: info.rangeX) }
            case .opacity:
                drivers.opacity.enabled = enabled
                if let info { drivers.opacity.applyRateRange(rate: info.hasRate ? info.rateX : nil, range: info.rangeX) }
            case .shape:
                drivers.shape.enabled = enabled
                if let info { drivers.shape.applyRateRange(rate: info.hasRate ? info.rateX : nil, range: info.rangeX) }
            default:
                return // name drivers: not editable from here yet
            }

            sprite.animation.drivers = drivers
            config.spriteConfig.library.spriteSets[setIdx].sprites[spriteIdx] = sprite
        }
    }
}
