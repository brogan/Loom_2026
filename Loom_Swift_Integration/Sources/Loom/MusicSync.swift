import Foundation
import LoomEngine

/// Recomputes every driver's BPM-linked rate/phase from the project's
/// `MusicSyncConfig` — the authored-project counterpart to Live's
/// `LiveSessionController.recomputeAllMusicalDrivers`, but walking the
/// static `ProjectConfig` model directly (dot-mutation, the same as every
/// other parameter editor) rather than a live-running `Engine`. See
/// `Specs/GlobalMusicSync.md`.
///
/// A driver opts in by setting `musicalMultiplier` (non-nil); recompute is a
/// no-op for every other driver. Called after any edit to `musicSync` itself
/// or to a driver's `musicalMultiplier`/`musicalPhaseOffset` — cheap enough
/// (tens of drivers per project, not thousands) to always do a full walk
/// rather than track incremental dirty state.
enum MusicSync {

    static func recomputeAll(in config: inout ProjectConfig) {
        let sync = config.musicSync

        recompute(&config.subdivisionConfig, sync: sync, targetFPS: config.globalConfig.targetFPS)
        recompute(&config.renderingConfig, sync: sync, targetFPS: config.globalConfig.targetFPS)

        // Sprite-level drivers live per-scene (each LoomScene owns its own
        // spriteConfig snapshot) — walk every scene, each against its own
        // targetFPS, not just the active one, so switching scenes never
        // shows stale rate/phase before the next edit touches them.
        for i in config.scenes.indices {
            recompute(&config.scenes[i].spriteConfig, sync: sync, targetFPS: config.scenes[i].globalConfig.targetFPS)
        }
        if let activeID = config.activeSceneID, let idx = config.scenes.firstIndex(where: { $0.id == activeID }) {
            config.spriteConfig = config.scenes[idx].spriteConfig
        }
    }

    // MARK: - Per-driver recompute

    /// Pushes the BPM-linked rate (and, for oscillator mode, phase) into one
    /// driver — a no-op unless `musicalMultiplier` is set. Mirrors
    /// `LiveSessionController.musicalRateAndPhase` exactly, then layers the
    /// user's `musicalPhaseOffset` on top of the computed baseline phase
    /// (`GlobalMusicSync.md` §6 — sync by default, offset for creative control).
    private static func recompute(_ driver: inout DoubleDriver, sync: MusicSyncConfig, targetFPS: Double) {
        guard let multiplier = driver.musicalMultiplier else { return }
        let (rate, phase) = LiveSessionController.musicalRateAndPhase(
            mode: driver.mode.rawValue, multiplier: multiplier, bpm: sync.bpm,
            beatsPerBar: sync.beatsPerBar, barReferenceFrame: sync.barReferenceFrame, targetFPS: targetFPS
        )
        if driver.mode == .noise {
            driver.period = max(1, Int(rate.rounded()))
            return
        }
        driver.freqHz = rate
        if let phase {
            let combined = phase + driver.musicalPhaseOffset
            driver.phase = combined - combined.rounded(.down)
        }
    }

    /// Vector counterpart — applies the same computed rate/phase to both X
    /// and Y (a music-linked vector driver has one shared musical rate, not
    /// independent per-axis rates; independent axes stay a manual-mode-only
    /// feature — see `VectorDriver.musicalMultiplier`'s doc comment).
    private static func recompute(_ driver: inout VectorDriver, sync: MusicSyncConfig, targetFPS: Double) {
        guard let multiplier = driver.musicalMultiplier else { return }
        let (rate, phase) = LiveSessionController.musicalRateAndPhase(
            mode: driver.mode.rawValue, multiplier: multiplier, bpm: sync.bpm,
            beatsPerBar: sync.beatsPerBar, barReferenceFrame: sync.barReferenceFrame, targetFPS: targetFPS
        )
        if driver.mode == .noise {
            driver.period = max(1, Int(rate.rounded()))
            return
        }
        driver.freqHz = Vector2D(x: rate, y: rate)
        if let phase {
            let combined = phase + driver.musicalPhaseOffset
            let wrapped = combined - combined.rounded(.down)
            driver.phase = Vector2D(x: wrapped, y: wrapped)
        }
    }

    private static func recompute(_ driver: inout ColorDriver, sync: MusicSyncConfig, targetFPS: Double) {
        guard let multiplier = driver.musicalMultiplier else { return }
        let (rate, phase) = LiveSessionController.musicalRateAndPhase(
            mode: driver.mode.rawValue, multiplier: multiplier, bpm: sync.bpm,
            beatsPerBar: sync.beatsPerBar, barReferenceFrame: sync.barReferenceFrame, targetFPS: targetFPS
        )
        if driver.mode == .noise {
            driver.period = max(1, Int(rate.rounded()))
            return
        }
        driver.freqHz = rate
        if let phase {
            let combined = phase + driver.musicalPhaseOffset
            driver.phase = combined - combined.rounded(.down)
        }
    }

    private static func recompute(_ driver: inout ColorDriver?, sync: MusicSyncConfig, targetFPS: Double) {
        guard driver != nil else { return }
        recompute(&driver!, sync: sync, targetFPS: targetFPS)
    }

    // MARK: - Config-tree walks

    private static func recompute(_ config: inout SubdivisionConfig, sync: MusicSyncConfig, targetFPS: Double) {
        for si in config.paramsSets.indices {
            for i in config.paramsSets[si].params.indices {
                guard config.paramsSets[si].params[i].drivers != nil else { continue }
                recompute(&config.paramsSets[si].params[i].drivers!.lineRatio, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.cpRatio, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.cpNormalOffset, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.insetScale, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.insetRotation, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.ranDiv, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.ptwTranslateX, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.ptwTranslateY, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.ptwScale, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].params[i].drivers!.ptwRotation, sync: sync, targetFPS: targetFPS)
            }
            for i in config.paramsSets[si].curveRefinement.indices {
                guard config.paramsSets[si].curveRefinement[i].drivers != nil else { continue }
                recompute(&config.paramsSets[si].curveRefinement[i].drivers!.displacement, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].curveRefinement[i].drivers!.cpNormalOffset, sync: sync, targetFPS: targetFPS)
            }
            for i in config.paramsSets[si].segmentExtraction.indices {
                recompute(&config.paramsSets[si].segmentExtraction[i].driver, sync: sync, targetFPS: targetFPS)
            }
            for i in config.paramsSets[si].extensionPasses.indices {
                recompute(&config.paramsSets[si].extensionPasses[i].branchAngle, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].extensionPasses[i].branchLineLength, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].extensionPasses[i].extrusionDistance, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].extensionPasses[i].structurePhase, sync: sync, targetFPS: targetFPS)
            }
            for i in config.paramsSets[si].convolutionPasses.indices {
                recompute(&config.paramsSets[si].convolutionPasses[i].twistAmount, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].convolutionPasses[i].shearAmount, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].convolutionPasses[i].bendCurvature, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].convolutionPasses[i].displacementStrength, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].convolutionPasses[i].displacementScrollRate, sync: sync, targetFPS: targetFPS)
            }
            for i in config.paramsSets[si].evolutionPasses.indices {
                recompute(&config.paramsSets[si].evolutionPasses[i].convergencePressure, sync: sync, targetFPS: targetFPS)
                recompute(&config.paramsSets[si].evolutionPasses[i].generationPhase, sync: sync, targetFPS: targetFPS)
            }
            for i in config.paramsSets[si].dissolutionPasses.indices {
                recompute(&config.paramsSets[si].dissolutionPasses[i].dissolutionPhase, sync: sync, targetFPS: targetFPS)
            }
            // fulgurationPasses excluded — no driver fields exist on FulgurationParams.
        }
    }

    private static func recompute(_ config: inout RenderingConfig, sync: MusicSyncConfig, targetFPS: Double) {
        for si in config.library.rendererSets.indices {
            for i in config.library.rendererSets[si].renderers.indices {
                guard config.library.rendererSets[si].renderers[i].drivers != nil else { continue }
                recompute(&config.library.rendererSets[si].renderers[i].drivers!.fillColor, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.rendererSets[si].renderers[i].drivers!.strokeColor, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.rendererSets[si].renderers[i].drivers!.strokeWidth, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.rendererSets[si].renderers[i].drivers!.opacity, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.rendererSets[si].renderers[i].drivers!.blur, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.rendererSets[si].renderers[i].drivers!.pointSize, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.rendererSets[si].renderers[i].drivers!.gradientBlend, sync: sync, targetFPS: targetFPS)
            }
        }
    }

    private static func recompute(_ config: inout SpriteConfig, sync: MusicSyncConfig, targetFPS: Double) {
        for si in config.library.spriteSets.indices {
            for i in config.library.spriteSets[si].sprites.indices {
                guard config.library.spriteSets[si].sprites[i].animation.drivers != nil else { continue }
                recompute(&config.library.spriteSets[si].sprites[i].animation.drivers!.position, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.spriteSets[si].sprites[i].animation.drivers!.scale, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.spriteSets[si].sprites[i].animation.drivers!.rotation, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.spriteSets[si].sprites[i].animation.drivers!.morph, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.spriteSets[si].sprites[i].animation.drivers!.opacity, sync: sync, targetFPS: targetFPS)
                recompute(&config.library.spriteSets[si].sprites[i].animation.drivers!.shape, sync: sync, targetFPS: targetFPS)
                // subdivisionSet/rendererSet/cycleName are NameDrivers — no cyclical rate to lock.
            }
        }
    }
}
