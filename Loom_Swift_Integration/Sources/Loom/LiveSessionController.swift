import Foundation
import LoomEngine

/// Owns the Live tab's own independent `Engine` instance, entirely separate
/// from `AppController.engine` — see `PerformanceArchitecture.md` §0.1 and
/// `LoomLiveV1Scope.md` §2.1. Ordinary inspector edits elsewhere still go
/// through `AppController`'s save→reload cycle, which only ever replaces
/// `AppController.engine`; this controller's `engine` is untouched by that,
/// so sprites staged here are never silently discarded by unrelated edits.
///
/// Also owns the semantic "staged sprite" model. `LoomEngine.hideSprite` is
/// destructive (array removal), so it can't remember a sprite's pose/set/
/// driver state across a hide→show round trip — this controller keeps that
/// richer record and replays the right sequence of engine calls to restore
/// it. The engine mutators stay dumb, minimal scene-mutation primitives.
///
/// ### Threading
/// `Engine`/`LoomEngine` are explicitly not thread-safe, and the same
/// `Engine` instance driving this tab's canvas is mutated/read every frame
/// on `RenderSurfaceNSView.sharedRenderQueue` (`RenderSurfaceNSView.tick()`).
/// Every engine call below therefore runs on that same serial queue rather
/// than directly on the caller's (main) thread, so a live mutation can never
/// race the render loop's concurrent `update`/`makeFrame`. UI-facing
/// `@Published` state is only ever updated back on the main actor, after the
/// engine call completes.
@MainActor
final class LiveSessionController: ObservableObject {

    /// A configured driver's live-tunable "Rate"/"Range" controls. "Rate"
    /// applies only to oscillator/noise modes (jitter re-rolls every frame
    /// with no periodicity); "Range" applies to all three. Bounds are
    /// captured once at stage time, scaled from whatever the driver's own
    /// authored value already was, so the slider stays sensibly scoped
    /// without needing the user to set a range first.
    struct DriverControlInfo: Equatable {
        var mode: String       // DoubleDriver.Mode/VectorDriver.Mode rawValue: "oscillator"/"noise"/"jitter"
        var isVector: Bool
        var hasRate: Bool
        var rateX: Double = 0
        var rateY: Double = 0  // meaningful only when isVector && mode == "oscillator"
        var rangeX: Double = 0
        var rangeY: Double = 0 // meaningful only when isVector
        var rateBounds: ClosedRange<Double> = 0...10
        var rangeBounds: ClosedRange<Double> = 0...10
    }

    struct StagedSprite: Identifiable, Equatable {
        let id: String                  // == engine instanceName, unique per stage action
        var spriteSetName: String
        var spriteDefName: String       // source SpriteDef.name as picked from the browser
        var isVisible: Bool = true
        var position: Vector2D
        var scale: Vector2D
        var rotation: Double
        var rendererSetName: String? = nil
        var subdivisionSetName: String? = nil
        var driverEnabled: [LiveDriverKey: Bool] = [:]
        /// Drivers the *project's own sprite authoring* actually configured
        /// (enabled or with non-default parameters) — used to show only
        /// drivers relevant to this sprite rather than all 9 possible slots.
        /// Fixed at stage time; doesn't change as the user toggles things
        /// live, since it reflects authoring, not current live state.
        var configuredDrivers: Set<LiveDriverKey> = []
        /// Rate/Range control info for configured drivers whose mode supports
        /// it (oscillator/noise/jitter). Absent for constant/keyframe modes —
        /// editing those isn't in scope for the Live tab yet.
        var driverControls: [LiveDriverKey: DriverControlInfo] = [:]
    }

    @Published private(set) var engine: Engine?
    @Published private(set) var loadedProjectURL: URL?
    @Published private(set) var loadError: String?

    @Published private(set) var stagedSprites: [StagedSprite] = []
    @Published var selectedStagedID: StagedSprite.ID?

    private var nextInstanceSuffix = 1
    /// Coalesces rapid slider-drag updates: a new call cancels any not-yet-
    /// fired update for the same (sprite, driver, quantity), so a fast drag
    /// collapses to "latest value wins" with a ~1-frame debounce, instead of
    /// flooding the render queue with every intermediate drag position.
    private var pendingDriverTasks: [String: Task<Void, Never>] = [:]

    /// (Re)builds the Live tab's engine from `projectURL` if it isn't already
    /// pointed at that project. A no-op when called again for the same URL,
    /// so it's safe to call from `.onAppear` every time the tab is shown.
    func ensureEngine(projectURL: URL) {
        guard loadedProjectURL != projectURL else { return }
        do {
            let newEngine = try Engine(projectDirectory: projectURL)
            // Start from a blank stage — the Live tab works against the
            // project's sprite/transform/renderer *sets*, not whatever the
            // project's own sprites.xml happens to place on canvas by default.
            for instance in newEngine.spriteInstances {
                newEngine.hideSprite(instanceName: instance.def.name)
            }
            engine = newEngine
            loadedProjectURL = projectURL
            loadError = nil
            stagedSprites = []
            selectedStagedID = nil
        } catch {
            engine = nil
            loadedProjectURL = nil
            loadError = error.localizedDescription
        }
    }

    // MARK: - Staging

    func stage(spriteSetName: String, spriteName: String) {
        guard let engine else { return }
        let instanceName = "live_\(spriteName)_\(nextInstanceSuffix)"
        nextInstanceSuffix += 1
        let position = Vector2D.zero
        let scale    = Vector2D(x: 1, y: 1)
        let rotation = 0.0

        RenderSurfaceNSView.sharedRenderQueue.async {
            do {
                try? engine.refreshProjectConfig()
                try engine.showSprite(
                    spriteSetName: spriteSetName, spriteName: spriteName, instanceName: instanceName,
                    position: position, scale: scale, rotation: rotation
                )
                // Read back the actual resolved drivers so the Live tab
                // reflects reality — which drivers this sprite's own
                // authoring configured, and their real current enabled
                // state — rather than a UI-only guess.
                let drivers = engine.spriteInstances
                    .first(where: { $0.def.name == instanceName })?.def.animation.drivers ?? .identity
                var driverEnabled: [LiveDriverKey: Bool] = [:]
                var configuredDrivers: Set<LiveDriverKey> = []
                var driverControls: [LiveDriverKey: DriverControlInfo] = [:]
                for key in LiveDriverKey.allCases {
                    driverEnabled[key] = key.enabled(in: drivers)
                    if key.isConfigured(in: drivers) { configuredDrivers.insert(key) }
                    if let info = Self.controlInfo(for: key, in: drivers) { driverControls[key] = info }
                }
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.stagedSprites.append(StagedSprite(
                            id: instanceName, spriteSetName: spriteSetName, spriteDefName: spriteName,
                            position: position, scale: scale, rotation: rotation,
                            driverEnabled: driverEnabled, configuredDrivers: configuredDrivers,
                            driverControls: driverControls
                        ))
                        self.selectedStagedID = instanceName
                        self.logStub("spriteShow \(instanceName) (\(spriteSetName)/\(spriteName))")
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.loadError = error.localizedDescription }
                }
            }
        }
    }

    func setVisible(_ id: StagedSprite.ID, _ visible: Bool) {
        guard let engine, let staged = stagedSprites.first(where: { $0.id == id }) else { return }
        stagedSprites[stagedSprites.firstIndex(where: { $0.id == id })!].isVisible = visible
        logStub(visible ? "spriteShow \(id)" : "spriteHide \(id)")
        RenderSurfaceNSView.sharedRenderQueue.async {
            if visible {
                Self.replayShow(staged, engine: engine)
            } else {
                engine.hideSprite(instanceName: id)
            }
        }
    }

    /// Replays the compound sequence of engine calls needed to restore a
    /// staged sprite's configured pose/set/driver state after a hide→show
    /// round trip (`showSprite` is a bare instantiation with no memory of
    /// prior configuration). Runs entirely on the caller's queue — callers
    /// are responsible for already being on `RenderSurfaceNSView.sharedRenderQueue`.
    nonisolated private static func replayShow(_ staged: StagedSprite, engine: Engine) {
        try? engine.refreshProjectConfig()
        try? engine.showSprite(
            spriteSetName: staged.spriteSetName, spriteName: staged.spriteDefName, instanceName: staged.id,
            position: staged.position, scale: staged.scale, rotation: staged.rotation
        )
        if let rendererSetName = staged.rendererSetName {
            try? engine.updateRendererSet(instanceName: staged.id, rendererSetName: rendererSetName)
        }
        if let subdivisionSetName = staged.subdivisionSetName {
            try? engine.updateSubdivisionSet(instanceName: staged.id, subdivisionSetName: subdivisionSetName)
        }
        for (driver, enabled) in staged.driverEnabled {
            try? engine.setDriverEnabled(instanceName: staged.id, driver: driver, enabled: enabled)
        }
        for (driver, info) in staged.driverControls {
            if info.isVector {
                try? engine.updateVectorDriverRateRange(
                    instanceName: staged.id, driver: driver,
                    rateX: info.hasRate ? info.rateX : nil, rateY: info.hasRate ? info.rateY : nil,
                    rangeX: info.rangeX, rangeY: info.rangeY
                )
            } else {
                try? engine.updateDoubleDriverRateRange(
                    instanceName: staged.id, driver: driver,
                    rate: info.hasRate ? info.rateX : nil, range: info.rangeX
                )
            }
        }
    }

    /// Derives a driver's initial Rate/Range control info from its actual
    /// resolved config, or `nil` if its mode doesn't support Rate/Range
    /// (constant/keyframe) or the key isn't a value driver (name drivers).
    nonisolated private static func controlInfo(
        for key: LiveDriverKey, in drivers: TransformDrivers
    ) -> DriverControlInfo? {
        func bounds(_ current: Double) -> ClosedRange<Double> {
            let upper = current > 0 ? current * 2 : 10
            return 0...max(upper, 0.001)
        }
        switch key {
        case .rotation, .morph, .opacity, .shape:
            let d: DoubleDriver
            switch key {
            case .rotation: d = drivers.rotation
            case .morph:    d = drivers.morph
            case .opacity:  d = drivers.opacity
            default:        d = drivers.shape
            }
            guard d.mode == .oscillator || d.mode == .noise || d.mode == .jitter else { return nil }
            let rate  = d.mode == .oscillator ? d.freqHz : Double(d.period)
            let range = d.mode == .jitter ? d.range : d.amplitude
            return DriverControlInfo(
                mode: d.mode.rawValue, isVector: false, hasRate: d.mode != .jitter,
                rateX: rate, rangeX: range,
                rateBounds: bounds(rate), rangeBounds: bounds(range)
            )
        case .position, .scale:
            let d: VectorDriver = key == .position ? drivers.position : drivers.scale
            guard d.mode == .oscillator || d.mode == .noise || d.mode == .jitter else { return nil }
            let rateX  = d.mode == .oscillator ? d.freqHz.x : Double(d.period)
            let rateY  = d.mode == .oscillator ? d.freqHz.y : Double(d.period)
            let rangeX = d.mode == .jitter ? d.range.x : d.amplitude.x
            let rangeY = d.mode == .jitter ? d.range.y : d.amplitude.y
            return DriverControlInfo(
                mode: d.mode.rawValue, isVector: true, hasRate: d.mode != .jitter,
                rateX: rateX, rateY: rateY, rangeX: rangeX, rangeY: rangeY,
                rateBounds: bounds(max(rateX, rateY)), rangeBounds: bounds(max(rangeX, rangeY))
            )
        default:
            return nil
        }
    }

    func updatePose(_ id: StagedSprite.ID, position: Vector2D, scale: Vector2D, rotation: Double) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        stagedSprites[idx].position = position
        stagedSprites[idx].scale    = scale
        stagedSprites[idx].rotation = rotation
        RenderSurfaceNSView.sharedRenderQueue.async {
            try? engine.updatePose(instanceName: id, position: position, scale: scale, rotation: rotation)
        }
    }

    func assignRendererSet(_ id: StagedSprite.ID, name: String) {
        guard let engine, stagedSprites.contains(where: { $0.id == id }) else { return }
        RenderSurfaceNSView.sharedRenderQueue.async {
            try? engine.refreshProjectConfig()
            do {
                try engine.updateRendererSet(instanceName: id, rendererSetName: name)
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, let idx = self.stagedSprites.firstIndex(where: { $0.id == id }) else { return }
                        self.stagedSprites[idx].rendererSetName = name
                        self.logStub("rendererSetAssign \(id) -> \(name)")
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.loadError = error.localizedDescription }
                }
            }
        }
    }

    func assignSubdivisionSet(_ id: StagedSprite.ID, name: String) {
        guard let engine, stagedSprites.contains(where: { $0.id == id }) else { return }
        RenderSurfaceNSView.sharedRenderQueue.async {
            try? engine.refreshProjectConfig()
            do {
                try engine.updateSubdivisionSet(instanceName: id, subdivisionSetName: name)
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, let idx = self.stagedSprites.firstIndex(where: { $0.id == id }) else { return }
                        self.stagedSprites[idx].subdivisionSetName = name
                        self.logStub("transformSetAssign \(id) -> \(name)")
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.loadError = error.localizedDescription }
                }
            }
        }
    }

    func toggleDriver(_ id: StagedSprite.ID, _ driver: LiveDriverKey, _ enabled: Bool) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        stagedSprites[idx].driverEnabled[driver] = enabled
        logStub("driverEnabledToggle \(id) \(driver.rawValue) -> \(enabled)")
        RenderSurfaceNSView.sharedRenderQueue.async {
            try? engine.setDriverEnabled(instanceName: id, driver: driver, enabled: enabled)
        }
    }

    /// Drags `key`'s Rate slider(s) live. `x` is always supplied; `y` only
    /// for a vector driver's oscillator mode (independent per-axis frequency).
    func updateDriverRate(_ id: StagedSprite.ID, _ key: LiveDriverKey, x: Double, y: Double? = nil) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }),
              var info = stagedSprites[idx].driverControls[key] else { return }
        info.rateX = x
        if let y { info.rateY = y }
        stagedSprites[idx].driverControls[key] = info
        let isVector = info.isVector
        scheduleDriverUpdate(token: "\(id)|\(key.rawValue)|rate") {
            if isVector {
                try? engine.updateVectorDriverRateRange(instanceName: id, driver: key, rateX: x, rateY: y)
            } else {
                try? engine.updateDoubleDriverRateRange(instanceName: id, driver: key, rate: x)
            }
        }
    }

    /// Drags `key`'s Range slider(s) live.
    func updateDriverRange(_ id: StagedSprite.ID, _ key: LiveDriverKey, x: Double, y: Double? = nil) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }),
              var info = stagedSprites[idx].driverControls[key] else { return }
        info.rangeX = x
        if let y { info.rangeY = y }
        stagedSprites[idx].driverControls[key] = info
        let isVector = info.isVector
        scheduleDriverUpdate(token: "\(id)|\(key.rawValue)|range") {
            if isVector {
                try? engine.updateVectorDriverRateRange(instanceName: id, driver: key, rangeX: x, rangeY: y)
            } else {
                try? engine.updateDoubleDriverRateRange(instanceName: id, driver: key, range: x)
            }
        }
    }

    private func scheduleDriverUpdate(token: String, _ work: @escaping @Sendable () -> Void) {
        pendingDriverTasks[token]?.cancel()
        pendingDriverTasks[token] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard !Task.isCancelled else { return }
            RenderSurfaceNSView.sharedRenderQueue.async { work() }
            self?.pendingDriverTasks[token] = nil
        }
    }

    // MARK: - Recording seam (stub)

    /// Console-only stand-in for the future `SessionWorkflow.md` §3.2 event
    /// log — proves the recording seam is wired at every mutator call site
    /// without yet building real persistence (deferred, see `LoomLiveV1Scope.md` §3).
    private func logStub(_ action: String) {
        print("[LoomLive] \(action)")
    }
}
