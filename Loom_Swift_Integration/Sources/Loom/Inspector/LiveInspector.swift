import SwiftUI
import LoomEngine

/// Right-panel inspector for the Live tab's currently selected staged
/// sprite, split into two portions per the navigator/control conception:
/// a top navigator to pick any configured driver — the sprite's own, or one
/// nested inside its assigned transform-set passes or renderer entries —
/// and a bottom panel with shared Rate/Range controls for whichever driver
/// is currently selected. See `LiveDriverTarget.swift` for the addressing
/// scheme and `LoomLiveV1Scope.md` §2.1 for the feature's scope.
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
            VStack(alignment: .leading, spacing: 0) {
                Text(staged.spriteDefName)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(12)

                setsSection(staged)
                    .padding(.horizontal, 12)

                Divider().padding(.top, 10)

                // Top: navigator across sprite/transform-set/renderer-set drivers.
                ScrollView {
                    navigatorSection(staged)
                        .padding(12)
                }
                .frame(maxHeight: .infinity)

                Divider()

                // Bottom: shared Rate/Range controls for whatever's selected above.
                controlsPanel(staged)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    // MARK: - Top: driver navigator

    /// Groups the sprite's configured drivers by section (Sprite / one
    /// heading per transform-pipeline stage / Renderer) — each row is a
    /// leaf driver field (its label already includes the owning pass/
    /// renderer's name, e.g. "myExtensionPass — Branch Angle"), tappable to
    /// select it for the bottom controls panel.
    private func navigatorSection(_ staged: LiveSessionController.StagedSprite) -> some View {
        let bySection = Dictionary(grouping: staged.driverTargets, by: { $0.section })
        return VStack(alignment: .leading, spacing: 12) {
            if staged.driverTargets.isEmpty {
                Text("This sprite has no configured drivers.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(LiveDriverSection.allCases, id: \.self) { section in
                    if let targets = bySection[section], !targets.isEmpty {
                        sectionGroup(staged, section, targets)
                    }
                }
            }
        }
    }

    private func sectionGroup(
        _ staged: LiveSessionController.StagedSprite, _ section: LiveDriverSection, _ targets: [LiveDriverTarget]
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.sectionLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(targets, id: \.self) { target in
                navigatorRow(staged, target)
            }
        }
    }

    private func navigatorRow(_ staged: LiveSessionController.StagedSprite, _ target: LiveDriverTarget) -> some View {
        let isSelected = liveController.selectedDriverTarget == target
        return HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { staged.driverEnabled[target] ?? false },
                set: { liveController.toggleDriver(staged.id, target, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Text(staged.driverLabels[target] ?? target.field)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { liveController.selectedDriverTarget = target }
    }

    // MARK: - Bottom: shared Rate/Range controls

    @ViewBuilder
    private func controlsPanel(_ staged: LiveSessionController.StagedSprite) -> some View {
        if let target = liveController.selectedDriverTarget {
            if let info = staged.driverControls[target] {
                VStack(alignment: .leading, spacing: 6) {
                    Text(staged.driverLabels[target] ?? target.field)
                        .font(.system(size: 12, weight: .semibold))
                    rateRangeControls(staged, target, info)
                    saveButton(staged, target)
                }
            } else {
                Text("This driver has no Rate/Range controls (name-based override — only on/off applies).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Select a driver above to adjust it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    /// The generalized Rate/Range sliders for one selected driver — Rate
    /// only appears for oscillator/noise modes (jitter re-rolls every frame,
    /// no periodicity to tune); Range always applies. Vector-backed drivers
    /// (position/scale) get an X and Y slider; scalar drivers get one.
    /// Dragging either slider also surfaces the real underlying field name
    /// and value in the top info bar.
    private func rateRangeControls(
        _ staged: LiveSessionController.StagedSprite, _ target: LiveDriverTarget,
        _ info: LiveSessionController.DriverControlInfo
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if info.hasRate {
                musicalRateControls(staged, target, info)
            }
            sliderRow(
                uiLabel: "Range", fieldName: rangeFieldName(info), bounds: info.rangeBounds,
                x: Binding(
                    get: { staged.driverControls[target]?.rangeX ?? info.rangeX },
                    set: { liveController.updateDriverRange(staged.id, target, x: $0, y: staged.driverControls[target]?.rangeY) }
                ),
                y: info.isVector ? Binding(
                    get: { staged.driverControls[target]?.rangeY ?? info.rangeY },
                    set: { liveController.updateDriverRange(staged.id, target, x: staged.driverControls[target]?.rangeX ?? info.rangeX, y: $0) }
                ) : nil
            )
        }
    }

    /// Cycles/bar options offered for BPM-linked Rate — `LoomLiveV1Scope.md`
    /// §2.6. Manual mode (the plain slider) stays the default; this is
    /// opt-in per driver.
    private static let musicalMultiplierOptions: [Double] = [0.0625, 0.125, 0.25, 0.5, 1, 2, 4, 8, 16]

    private func musicalMultiplierLabel(_ m: Double) -> String {
        m >= 1 ? "\(Int(m)) / bar" : "1 / \(Int(1 / m)) bars"
    }

    /// Rate's Manual/Musical switch — Manual keeps the plain slider
    /// unchanged; Musical replaces it with a cycles/bar picker whose
    /// `freqHz`/`phase` are computed from the shared BPM/time-signature/tap
    /// state (`LiveTabView`'s Music Sync section) rather than dragged directly.
    private func musicalRateControls(
        _ staged: LiveSessionController.StagedSprite, _ target: LiveDriverTarget,
        _ info: LiveSessionController.DriverControlInfo
    ) -> some View {
        let currentMultiplier = staged.driverControls[target]?.musicalMultiplier
        return VStack(alignment: .leading, spacing: 3) {
            Picker("", selection: Binding(
                get: { currentMultiplier != nil ? "musical" : "manual" },
                set: { newMode in
                    liveController.setMusicalMultiplier(
                        staged.id, target, newMode == "musical" ? (currentMultiplier ?? 1.0) : nil
                    )
                }
            )) {
                Text("Manual").tag("manual")
                Text("Musical").tag("musical")
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            if let multiplier = currentMultiplier {
                HStack(spacing: 4) {
                    Text("Rate").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { multiplier },
                        set: { liveController.setMusicalMultiplier(staged.id, target, $0) }
                    )) {
                        ForEach(Self.musicalMultiplierOptions, id: \.self) { m in
                            Text(musicalMultiplierLabel(m)).tag(m)
                        }
                    }
                    .labelsHidden()
                }
            } else {
                sliderRow(
                    uiLabel: "Rate", fieldName: rateFieldName(info), bounds: info.rateBounds,
                    x: Binding(
                        get: { staged.driverControls[target]?.rateX ?? info.rateX },
                        set: { liveController.updateDriverRate(staged.id, target, x: $0, y: staged.driverControls[target]?.rateY) }
                    ),
                    y: (info.isVector && info.mode == "oscillator") ? Binding(
                        get: { staged.driverControls[target]?.rateY ?? info.rateY },
                        set: { liveController.updateDriverRate(staged.id, target, x: staged.driverControls[target]?.rateX ?? info.rateX, y: $0) }
                    ) : nil
                )
            }
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
    //
    // Currently only wired for `.sprite`-section targets. Saving a
    // transform-set-pass or renderer-entry driver back into the project's
    // saved `SubdivisionParamsSet`/`RendererSet` (rather than the sprite) is
    // a natural follow-up, not yet built — flagged here rather than
    // silently doing nothing.

    private func saveButton(_ staged: LiveSessionController.StagedSprite, _ target: LiveDriverTarget) -> some View {
        Group {
            if target.section == .sprite {
                Button {
                    saveDriverToSprite(staged, target)
                } label: {
                    Label("Save to Sprite", systemImage: "square.and.arrow.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .modifier(LoomHoverHelp("Write this driver's current live Rate/Range/enabled values back into the saved sprite."))
            } else {
                Text("Saving transform-set/renderer-set drivers back to the project isn't available yet — this is a live-only edit for now.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Writes the live-tweaked enabled/rate/range values for a sprite-level
    /// `target` back into the project's actual saved `SpriteDef`, via the
    /// same `AppController.updateProjectConfig` mutation path every other
    /// tab uses — a normal, undoable, auto-saved edit, not a Live-tab-only thing.
    private func saveDriverToSprite(_ staged: LiveSessionController.StagedSprite, _ target: LiveDriverTarget) {
        guard target.section == .sprite else { return }
        let enabled = staged.driverEnabled[target] ?? false
        let info = staged.driverControls[target]
        controller.updateProjectConfig { config in
            guard let setIdx = config.spriteConfig.library.spriteSets.firstIndex(where: { $0.name == staged.spriteSetName })
            else { return }
            guard let spriteIdx = config.spriteConfig.library.spriteSets[setIdx].sprites.firstIndex(where: { $0.name == staged.spriteDefName })
            else { return }

            var sprite = config.spriteConfig.library.spriteSets[setIdx].sprites[spriteIdx]
            var drivers = sprite.animation.drivers ?? .identity

            func applyDouble(_ kp: WritableKeyPath<TransformDrivers, DoubleDriver>) {
                drivers[keyPath: kp].enabled = enabled
                if let info { drivers[keyPath: kp].applyRateRange(rate: info.hasRate ? info.rateX : nil, range: info.rangeX) }
            }
            func applyVector(_ kp: WritableKeyPath<TransformDrivers, VectorDriver>) {
                drivers[keyPath: kp].enabled = enabled
                if let info {
                    drivers[keyPath: kp].applyRateRange(
                        rateX: info.hasRate ? info.rateX : nil, rateY: info.hasRate ? info.rateY : nil,
                        rangeX: info.rangeX, rangeY: info.rangeY
                    )
                }
            }

            switch target.field {
            case "position": applyVector(\.position)
            case "scale":    applyVector(\.scale)
            case "rotation": applyDouble(\.rotation)
            case "morph":    applyDouble(\.morph)
            case "opacity":  applyDouble(\.opacity)
            case "shape":    applyDouble(\.shape)
            default: return // name drivers: not editable from here yet
            }

            sprite.animation.drivers = drivers
            config.spriteConfig.library.spriteSets[setIdx].sprites[spriteIdx] = sprite
        }
    }
}
