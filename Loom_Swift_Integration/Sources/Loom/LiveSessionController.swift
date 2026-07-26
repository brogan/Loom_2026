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
@MainActor
final class LiveSessionController: ObservableObject {

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
    }

    @Published private(set) var engine: Engine?
    @Published private(set) var loadedProjectURL: URL?
    @Published private(set) var loadError: String?

    @Published private(set) var stagedSprites: [StagedSprite] = []
    @Published var selectedStagedID: StagedSprite.ID?

    private var nextInstanceSuffix = 1

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

    /// Re-reads project config from disk before any engine call that
    /// resolves a name — sprite/renderer-set/transform-set definitions
    /// created or edited in another tab *after* this engine was constructed
    /// wouldn't otherwise be resolvable, since this engine's own `config` is
    /// a frozen snapshot by design (`LoomEngine.refreshProjectConfig`).
    /// Failures here are non-fatal: the subsequent call just falls back to
    /// whatever config was already loaded.
    private func refreshEngineConfig() {
        try? engine?.refreshProjectConfig()
    }

    // MARK: - Staging

    func stage(spriteSetName: String, spriteName: String) {
        guard let engine else { return }
        refreshEngineConfig()
        let instanceName = "live_\(spriteName)_\(nextInstanceSuffix)"
        nextInstanceSuffix += 1
        let position = Vector2D.zero
        let scale    = Vector2D(x: 1, y: 1)
        let rotation = 0.0
        do {
            try engine.showSprite(
                spriteSetName: spriteSetName, spriteName: spriteName, instanceName: instanceName,
                position: position, scale: scale, rotation: rotation
            )
            stagedSprites.append(StagedSprite(
                id: instanceName, spriteSetName: spriteSetName, spriteDefName: spriteName,
                position: position, scale: scale, rotation: rotation
            ))
            selectedStagedID = instanceName
            logStub("spriteShow \(instanceName) (\(spriteSetName)/\(spriteName))")
        } catch {
            loadError = error.localizedDescription
        }
    }

    func setVisible(_ id: StagedSprite.ID, _ visible: Bool) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        stagedSprites[idx].isVisible = visible
        if visible {
            replayShow(stagedSprites[idx], engine: engine)
            logStub("spriteShow \(id)")
        } else {
            engine.hideSprite(instanceName: id)
            logStub("spriteHide \(id)")
        }
    }

    /// Replays the compound sequence of engine calls needed to restore a
    /// staged sprite's configured pose/set/driver state after a hide→show
    /// round trip (`showSprite` is a bare instantiation with no memory of
    /// prior configuration).
    private func replayShow(_ staged: StagedSprite, engine: Engine) {
        refreshEngineConfig()
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
    }

    func updatePose(_ id: StagedSprite.ID, position: Vector2D, scale: Vector2D, rotation: Double) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        stagedSprites[idx].position = position
        stagedSprites[idx].scale    = scale
        stagedSprites[idx].rotation = rotation
        try? engine.updatePose(instanceName: id, position: position, scale: scale, rotation: rotation)
    }

    func assignRendererSet(_ id: StagedSprite.ID, name: String) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        refreshEngineConfig()
        do {
            try engine.updateRendererSet(instanceName: id, rendererSetName: name)
            stagedSprites[idx].rendererSetName = name
            logStub("rendererSetAssign \(id) -> \(name)")
        } catch {
            loadError = error.localizedDescription
        }
    }

    func assignSubdivisionSet(_ id: StagedSprite.ID, name: String) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        refreshEngineConfig()
        do {
            try engine.updateSubdivisionSet(instanceName: id, subdivisionSetName: name)
            stagedSprites[idx].subdivisionSetName = name
            logStub("transformSetAssign \(id) -> \(name)")
        } catch {
            loadError = error.localizedDescription
        }
    }

    func toggleDriver(_ id: StagedSprite.ID, _ driver: LiveDriverKey, _ enabled: Bool) {
        guard let engine, let idx = stagedSprites.firstIndex(where: { $0.id == id }) else { return }
        do {
            try engine.setDriverEnabled(instanceName: id, driver: driver, enabled: enabled)
            stagedSprites[idx].driverEnabled[driver] = enabled
            logStub("driverEnabledToggle \(id) \(driver.rawValue) -> \(enabled)")
        } catch {
            loadError = error.localizedDescription
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
