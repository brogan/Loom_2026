import Foundation
import LoomEngine

/// Drives an `Engine` frame-by-frame from a recorded `LiveEvent` log —
/// the replay half of `SessionWorkflow.md` §3.3's "one mutation API, two
/// callers" principle. Meant to be used as `VideoExporter`'s new
/// `onBeforeFrame` hook: at each exported frame, apply whatever macro
/// events have become due and push the interpolated Rate/Range for every
/// active automation curve — reusing `LiveSessionController`'s own
/// mutator-dispatch helpers directly rather than re-implementing them.
///
/// Not `@MainActor` and not thread-safety-hardened the way the Live tab's
/// controller is — this class owns its `Engine` exclusively for the
/// duration of one export, with nothing else (no on-screen render loop)
/// touching it concurrently, so none of that machinery is needed here.
final class SessionReplayer: @unchecked Sendable {

    /// Identifies one automation curve — a driver's Rate *or* Range,
    /// independent of axis (a vector driver's X/Y values are merged into
    /// one curve's points, not two separate curves).
    private struct CurveKey: Hashable {
        let instanceName: String
        let target: LiveDriverTarget
        let quantity: String // "rate" or "range"
    }

    private struct MusicalKey: Hashable {
        let instanceName: String
        let target: LiveDriverTarget
    }

    let engine: Engine
    /// The last frame any event in the log occurs at — the natural basis
    /// for a replay export's default end frame.
    let maxEventFrame: Int

    /// Non-fatal failures encountered while applying events (e.g. a sprite
    /// or set renamed/deleted since the session was recorded) — collected
    /// rather than aborting the whole render, surfaced as a summary after
    /// export completes.
    private(set) var skippedEventDescriptions: [String] = []

    private var macroEvents: [LiveEvent]
    private var nextMacroIndex = 0
    private var curves: [CurveKey: [(t: Int, x: Double, y: Double?)]]
    /// Per-curve "last bracketing index" cursor — `applyFrame` is always
    /// called with non-decreasing frame numbers, so each curve's bracketing
    /// pair only ever moves forward; this avoids re-scanning every point
    /// from the start on every single exported frame.
    private var curveCursors: [CurveKey: Int] = [:]

    // Musical-rate replay state — mirrors LiveSessionController's own
    // bpm/beatsPerBar/barReferenceFrame/per-target-multiplier state, but
    // driven by replayed bpmSet/tapSync/driverMusicalRateAssign events
    // instead of live UI input.
    private var bpm: Double = 120
    private var beatsPerBar: Int = 4
    private var barReferenceFrame: Int?
    private var musicalMultipliers: [MusicalKey: Double] = [:]

    init(engine: Engine, events: [LiveEvent]) {
        self.engine = engine
        self.maxEventFrame = events.map(\.t).max() ?? 0

        self.macroEvents = events.filter {
            if case .driverAutomationPoint = $0 { return false }
            return true
        }.sorted { $0.t < $1.t }

        // Group driverAutomationPoint events into curves — dropping `axis`
        // from the key and instead combining the "x" (or axis-less scalar)
        // and "y" points recorded at the *same* frame into one point, since
        // LiveSessionController.recordAutomationPoint always emits both at
        // an identical `t` for a vector target.
        //
        // Builds via the chained `dict[key, default:][key2, default:] = ...`
        // subscript form deliberately, not `var byFrame = buckets[key] ?? [:];
        // ...; buckets[key] = byFrame` — the latter looks equivalent but
        // defeats copy-on-write: `buckets` still holds a reference to the old
        // inner dictionary while `byFrame` mutates its own copy, so every
        // single insertion into a growing curve re-copies everything
        // accumulated so far (O(n²) over a session's automation points,
        // measured in minutes for a few thousand points on one curve — not a
        // theoretical concern, an actual reported hang). The chained form
        // mutates in place via Swift's `_modify` accessor instead.
        var buckets: [CurveKey: [Int: (x: Double?, y: Double?)]] = [:]
        for event in events {
            guard case .driverAutomationPoint(let t, let instanceName, let target, let quantity, let axis, let value) = event
            else { continue }
            let key = CurveKey(instanceName: instanceName, target: target, quantity: quantity)
            if axis == "y" {
                buckets[key, default: [:]][t, default: (x: nil, y: nil)].y = value
            } else {
                buckets[key, default: [:]][t, default: (x: nil, y: nil)].x = value
            }
        }
        var built: [CurveKey: [(t: Int, x: Double, y: Double?)]] = [:]
        for (key, byFrame) in buckets {
            built[key] = byFrame.compactMap { t, entry -> (t: Int, x: Double, y: Double?)? in
                guard let x = entry.x else { return nil }
                return (t, x, entry.y)
            }.sorted { $0.t < $1.t }
        }
        self.curves = built
    }

    // MARK: - Loading

    /// Parses a `.jsonl` session log — one flat JSON object per line, no
    /// enclosing array (`LiveSessionController.recordEvent`'s on-disk
    /// format). A line that fails to decode is skipped rather than failing
    /// the whole load — matches the "append-only, resilient" spirit of the
    /// recording side.
    static func loadEvents(from url: URL) throws -> [LiveEvent] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return contents.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(LiveEvent.self, from: data)
        }
    }

    // MARK: - Playback

    /// Applies everything due at `frame` — call once per exported frame,
    /// in increasing order, before `engine.update(deltaTime:)` (see
    /// `VideoExporter`'s `onBeforeFrame` hook).
    func applyFrame(_ frame: Int) {
        while nextMacroIndex < macroEvents.count, macroEvents[nextMacroIndex].t <= frame {
            apply(macroEvents[nextMacroIndex])
            nextMacroIndex += 1
        }
        for (key, points) in curves {
            let cursor = curveCursors[key] ?? 0
            guard let (x, y, newCursor) = Self.interpolate(points, at: frame, from: cursor) else { continue }
            curveCursors[key] = newCursor
            if key.quantity == "rate" {
                LiveSessionController.applyRateRange(key.target, engine: engine, instanceName: key.instanceName, rateX: x, rateY: y)
            } else {
                LiveSessionController.applyRateRange(key.target, engine: engine, instanceName: key.instanceName, rangeX: x, rangeY: y)
            }
        }
    }

    private func apply(_ event: LiveEvent) {
        switch event {
        case .spriteShow(_, let instanceName, let spriteSetName, let spriteName, let position, let scale, let rotation):
            do {
                try engine.showSprite(
                    spriteSetName: spriteSetName, spriteName: spriteName, instanceName: instanceName,
                    position: position, scale: scale, rotation: rotation
                )
            } catch {
                skippedEventDescriptions.append("spriteShow '\(instanceName)': \(error.localizedDescription)")
            }
        case .spriteHide(_, let instanceName):
            engine.hideSprite(instanceName: instanceName)
        case .poseUpdate(_, let instanceName, let position, let scale, let rotation):
            try? engine.updatePose(instanceName: instanceName, position: position, scale: scale, rotation: rotation)
        case .rendererSetAssign(_, let instanceName, let rendererSetName):
            do {
                try engine.updateRendererSet(instanceName: instanceName, rendererSetName: rendererSetName)
            } catch {
                skippedEventDescriptions.append("rendererSetAssign '\(instanceName)' -> '\(rendererSetName)': \(error.localizedDescription)")
            }
        case .transformSetAssign(_, let instanceName, let subdivisionSetName):
            do {
                try engine.updateSubdivisionSet(instanceName: instanceName, subdivisionSetName: subdivisionSetName)
            } catch {
                skippedEventDescriptions.append("transformSetAssign '\(instanceName)' -> '\(subdivisionSetName)': \(error.localizedDescription)")
            }
        case .driverEnabledToggle(_, let instanceName, let target, let enabled):
            LiveSessionController.applyEnabled(target, engine: engine, instanceName: instanceName, enabled: enabled)
        case .bpmSet(_, let newBPM, let newBeatsPerBar):
            bpm = newBPM
            beatsPerBar = newBeatsPerBar
            recomputeMusicalTargets()
        case .tapSync(_, let referenceFrame):
            barReferenceFrame = referenceFrame
            recomputeMusicalTargets()
        case .driverMusicalRateAssign(_, let instanceName, let target, let multiplier):
            let key = MusicalKey(instanceName: instanceName, target: target)
            if let multiplier {
                musicalMultipliers[key] = multiplier
                applyMusicalRate(instanceName: instanceName, target: target, multiplier: multiplier)
            } else {
                musicalMultipliers.removeValue(forKey: key)
            }
        case .driverAutomationPoint:
            break // handled continuously via `curves`, not as a discrete event
        }
    }

    private func recomputeMusicalTargets() {
        for (key, multiplier) in musicalMultipliers {
            applyMusicalRate(instanceName: key.instanceName, target: key.target, multiplier: multiplier)
        }
    }

    /// Mirrors `LiveSessionController.applyMusicalRate`, but reads the
    /// driver's current mode directly off the engine instance instead of a
    /// cached `DriverControlInfo` (this replayer doesn't keep one).
    private func applyMusicalRate(instanceName: String, target: LiveDriverTarget, multiplier: Double) {
        guard let instance = engine.spriteInstances.first(where: { $0.def.name == instanceName }) else { return }
        let mode: String
        let isVector: Bool
        if let kp = target.doubleKeyPath(in: instance) {
            mode = instance[keyPath: kp].mode.rawValue
            isVector = false
        } else if let kp = target.vectorKeyPath(in: instance) {
            mode = instance[keyPath: kp].mode.rawValue
            isVector = true
        } else {
            return
        }
        let (rate, phase) = LiveSessionController.musicalRateAndPhase(
            mode: mode, multiplier: multiplier, bpm: bpm, beatsPerBar: beatsPerBar,
            barReferenceFrame: barReferenceFrame, targetFPS: engine.globalConfig.targetFPS
        )
        LiveSessionController.applyRateRange(
            target, engine: engine, instanceName: instanceName,
            rateX: rate, rateY: isVector ? rate : nil,
            phaseX: phase, phaseY: isVector ? phase : nil
        )
    }

    /// Piecewise-linear interpolation between recorded points — holds at
    /// the first/last value outside the recorded range. A raw drag is
    /// honestly piecewise-linear; no smoothing/easing is applied.
    ///
    /// `from` is the bracketing index found last time (0 on first call);
    /// since `applyFrame` only ever advances `frame`, the correct bracket
    /// can never be *before* that cursor, so the scan resumes there instead
    /// of restarting from the beginning — O(1) amortized across a whole
    /// export rather than O(points) per frame.
    private static func interpolate(
        _ points: [(t: Int, x: Double, y: Double?)], at frame: Int, from cursor: Int
    ) -> (x: Double, y: Double?, cursor: Int)? {
        guard let first = points.first, let last = points.last else { return nil }
        if frame <= first.t { return (first.x, first.y, 0) }
        if frame >= last.t { return (last.x, last.y, points.count - 1) }
        var i = min(cursor, points.count - 2)
        while i < points.count - 1 && points[i + 1].t < frame { i += 1 }
        let a = points[i], b = points[i + 1]
        if a.t == b.t || frame <= a.t { return (a.x, a.y, i) }
        let ratio = Double(frame - a.t) / Double(b.t - a.t)
        let x = a.x + (b.x - a.x) * ratio
        let y: Double? = (a.y != nil && b.y != nil) ? a.y! + (b.y! - a.y!) * ratio : nil
        return (x, y, i)
    }
}
