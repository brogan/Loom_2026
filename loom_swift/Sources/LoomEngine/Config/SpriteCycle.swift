import Foundation

// MARK: - SpriteCycleLoopMode

public enum SpriteCycleLoopMode: String, Codable, CaseIterable, Sendable {
    case loop     = "loop"
    case pingPong = "pingPong"
    case once     = "once"
    case holdLast = "holdLast"

    public var displayName: String {
        switch self {
        case .loop:     return "Loop"
        case .pingPong: return "Ping-Pong"
        case .once:     return "Once"
        case .holdLast: return "Hold Last"
        }
    }
}

// MARK: - SpritePoseOverride

/// An absolute world-space transform for one sprite within a cycle state.
/// Replaces the sprite's `def.position`, `def.rotation`, and `def.scale` for that state;
/// animation drivers (keyframe, noise, etc.) still apply on top as deltas.
public struct SpritePoseOverride: Codable, Equatable, Sendable {
    /// Absolute world-space position (same units as `SpriteDef.position`).
    public var position: Vector2D
    /// Absolute rotation in degrees.
    public var rotation: Double
    /// Absolute per-axis scale multiplier.
    public var scale:    Vector2D

    public init(position: Vector2D = .zero,
                rotation: Double   = 0,
                scale:    Vector2D = Vector2D(x: 1, y: 1)) {
        self.position = position
        self.rotation = rotation
        self.scale    = scale
    }

    public init(from decoder: Decoder) throws {
        let c    = try decoder.container(keyedBy: CodingKeys.self)
        position = try c.decodeIfPresent(Vector2D.self, forKey: .position) ?? .zero
        rotation = try c.decodeIfPresent(Double.self,   forKey: .rotation) ?? 0
        scale    = try c.decodeIfPresent(Vector2D.self, forKey: .scale)    ?? Vector2D(x: 1, y: 1)
    }
}

// MARK: - SpriteCycleState

/// One frame-state in a SpriteCycle — defines which geometry and renderer to show,
/// for how long, and how to cross-fade into the next state.
public struct SpriteCycleState: Codable, Equatable, Sendable {
    /// Optional display label for this state (shown in the editor list).
    public var name:             String
    /// Shape set (references `shapeConfig.library.shapeSets` by name).
    public var shapeSetName:     String
    /// Shape name within `shapeSetName`.
    public var shapeName:        String
    /// Renderer set override. `nil` = inherit from the sprite's own rendererSetName.
    public var rendererSetName:  String?
    /// Filename of an SVG in the project's `svgs/sprites/` directory.
    /// When non-nil this state renders the SVG image and the shape/renderer fields are ignored.
    public var svgFilename:      String?
    /// Frames this state is fully shown (minimum 1).
    public var holdFrames:       Int
    /// Frames to cross-fade into the next state (0 = hard cut).
    public var transitionFrames: Int
    /// Easing applied to the cross-fade progress value.
    public var easing:           EasingType
    /// When true and transitionFrames > 0, renderer colours lerp between the from/to sets.
    public var styleTween:       Bool
    // Per-state registration offsets (canvas units, additive to sprite transform).
    public var offsetX:          Double
    public var offsetY:          Double
    public var rotation:         Double  // degrees, additive
    public var scaleX:           Double  // multiplicative
    public var scaleY:           Double  // multiplicative

    /// Per-sprite absolute pose overrides for this state, keyed by sprite name.
    /// When a sprite's name appears here its def.position/rotation/scale are replaced
    /// by these values for the duration of the state (animation drivers still apply on top).
    /// Empty = no pose overrides; all sprites use their base def transforms.
    public var poseOverrides:    [String: SpritePoseOverride]

    public init(
        name:             String     = "",
        shapeSetName:     String     = "",
        shapeName:        String     = "",
        rendererSetName:  String?    = nil,
        svgFilename:      String?    = nil,
        holdFrames:       Int        = 4,
        transitionFrames: Int        = 0,
        easing:           EasingType = .easeInOutCubic,
        styleTween:       Bool       = false,
        offsetX:          Double     = 0,
        offsetY:          Double     = 0,
        rotation:         Double     = 0,
        scaleX:           Double     = 1,
        scaleY:           Double     = 1,
        poseOverrides:    [String: SpritePoseOverride] = [:]
    ) {
        self.name             = name
        self.shapeSetName     = shapeSetName
        self.shapeName        = shapeName
        self.rendererSetName  = rendererSetName
        self.svgFilename      = svgFilename
        self.holdFrames       = holdFrames
        self.transitionFrames = transitionFrames
        self.easing           = easing
        self.styleTween       = styleTween
        self.offsetX          = offsetX
        self.offsetY          = offsetY
        self.rotation         = rotation
        self.scaleX           = scaleX
        self.scaleY           = scaleY
        self.poseOverrides    = poseOverrides
    }

    public init(from decoder: Decoder) throws {
        let c            = try decoder.container(keyedBy: CodingKeys.self)
        name             = try c.decodeIfPresent(String.self,     forKey: .name)             ?? ""
        shapeSetName     = try c.decodeIfPresent(String.self,     forKey: .shapeSetName)     ?? ""
        shapeName        = try c.decodeIfPresent(String.self,     forKey: .shapeName)        ?? ""
        rendererSetName  = try c.decodeIfPresent(String.self,     forKey: .rendererSetName)
        svgFilename      = try c.decodeIfPresent(String.self,     forKey: .svgFilename)
        holdFrames       = try c.decodeIfPresent(Int.self,        forKey: .holdFrames)       ?? 4
        transitionFrames = try c.decodeIfPresent(Int.self,        forKey: .transitionFrames) ?? 0
        easing           = try c.decodeIfPresent(EasingType.self, forKey: .easing)           ?? .easeInOutCubic
        styleTween       = try c.decodeIfPresent(Bool.self,       forKey: .styleTween)       ?? false
        offsetX          = try c.decodeIfPresent(Double.self,     forKey: .offsetX)          ?? 0
        offsetY          = try c.decodeIfPresent(Double.self,     forKey: .offsetY)          ?? 0
        rotation         = try c.decodeIfPresent(Double.self,     forKey: .rotation)         ?? 0
        scaleX           = try c.decodeIfPresent(Double.self,     forKey: .scaleX)           ?? 1
        scaleY           = try c.decodeIfPresent(Double.self,     forKey: .scaleY)           ?? 1
        poseOverrides    = try c.decodeIfPresent([String: SpritePoseOverride].self,
                                                 forKey: .poseOverrides)                     ?? [:]
    }
}

// MARK: - SpriteCycleRenderLayer

/// One draw layer produced by `SpriteCycle.renderLayers(atFrame:)`.
/// During a hard-cut frame there is a single layer at alpha 1.0.
/// During a cross-fade there are two layers at complementary alphas.
public struct SpriteCycleRenderLayer: Sendable {
    /// Index into `SpriteCycle.states`.
    public let stateIndex: Int
    /// Draw opacity 0…1.
    public let alpha:      Double
    /// When true, the caller may lerp renderer colours between outgoing and incoming styles.
    public let styleTween: Bool
}

// MARK: - SpriteCycle

/// A named, reusable walk-cycle/animation asset.  Assigned to a `SpriteDef`
/// via `SpriteDef.cycleName`; when set it overrides the sprite's `shapeSetName`
/// and any legacy `shapeSequence` cycling.
public struct SpriteCycle: Codable, Equatable, Sendable {
    public var name:           String
    public var loopMode:       SpriteCycleLoopMode
    public var states:         [SpriteCycleState]
    /// Index of the state used as the fallback pose for any sprite not overridden in
    /// another state.  `nil` means fall back to `def.rotation / def.position / def.scale`.
    /// Typical usage: mark the "neutral" state so other states only need to specify
    /// the joints that actually change.
    public var baseStateIndex: Int?

    public init(
        name:           String                = "Cycle",
        loopMode:       SpriteCycleLoopMode   = .loop,
        states:         [SpriteCycleState]    = [],
        baseStateIndex: Int?                  = nil
    ) {
        self.name           = name
        self.loopMode       = loopMode
        self.states         = states
        self.baseStateIndex = baseStateIndex
    }

    // MARK: - Frame counts

    /// Total frames in one forward pass, including transition periods.
    public var totalForwardFrames: Int {
        states.reduce(0) { $0 + max(1, $1.holdFrames) + max(0, $1.transitionFrames) }
    }

    /// Full cycle length. PingPong back-pass uses hold frames only (transitions forward only).
    public var totalCycleFrames: Int {
        let fwd = totalForwardFrames
        guard fwd > 0 else { return 1 }
        switch loopMode {
        case .loop, .once, .holdLast:
            return fwd
        case .pingPong:
            guard states.count > 1 else { return fwd }
            let back = states.dropLast().reduce(0) { $0 + max(1, $1.holdFrames) }
            return fwd + back
        }
    }

    // MARK: - Primary API

    /// Returns 1 or 2 render layers for the given frame.
    ///
    /// Hard-cut state: one layer at alpha 1.0.
    /// Transition period: two layers — outgoing at (1 − progress), incoming at progress.
    public func renderLayers(atFrame frame: Int) -> [SpriteCycleRenderLayer] {
        guard !states.isEmpty else { return [] }
        guard let f = effectiveFrame(frame) else {
            let lastIdx = states.count - 1
            return [SpriteCycleRenderLayer(stateIndex: lastIdx, alpha: 1.0, styleTween: false)]
        }
        let (primaryIdx, secondaryIdx, progress) = stateAtFrame(f)
        if let nextIdx = secondaryIdx, progress > 0 {
            let tween = states[primaryIdx].styleTween
            return [
                SpriteCycleRenderLayer(stateIndex: primaryIdx, alpha: 1.0 - progress, styleTween: tween),
                SpriteCycleRenderLayer(stateIndex: nextIdx,    alpha: progress,        styleTween: tween)
            ]
        }
        return [SpriteCycleRenderLayer(stateIndex: primaryIdx, alpha: 1.0, styleTween: false)]
    }

    // MARK: - Private helpers

    private func effectiveFrame(_ frame: Int) -> Int? {
        let total = totalForwardFrames
        guard total > 0 else { return nil }
        switch loopMode {
        case .loop:
            return ((frame % total) + total) % total
        case .pingPong:
            guard states.count > 1 else { return 0 }
            let fwdPairs = states.map { max(1, $0.holdFrames) + max(0, $0.transitionFrames) }
            let bwdHolds = Array(states.dropLast().map { max(1, $0.holdFrames) }.reversed())
            let back     = bwdHolds.reduce(0, +)
            let cycle    = total + back
            let r        = ((frame % cycle) + cycle) % cycle
            if r < total { return r }
            return pingPongBack(offset: r - total, backHolds: bwdHolds, fwdPairs: fwdPairs)
        case .once, .holdLast:
            if frame >= total { return nil }
            return max(0, frame)
        }
    }

    private func pingPongBack(offset: Int, backHolds: [Int], fwdPairs: [Int]) -> Int {
        var cursor = 0
        for (i, hold) in backHolds.enumerated() {
            let stateIdx = states.count - 2 - i
            if stateIdx < 0 { break }
            if offset < cursor + hold {
                return fwdPairs[0..<stateIdx].reduce(0, +) + (offset - cursor)
            }
            cursor += hold
        }
        return 0
    }

    /// Maps an effective forward-pass frame to (primaryIdx, secondaryIdx?, easedProgress).
    private func stateAtFrame(_ f: Int) -> (Int, Int?, Double) {
        var cursor = 0
        for (i, state) in states.enumerated() {
            let hold  = max(1, state.holdFrames)
            let trans = max(0, state.transitionFrames)
            if f < cursor + hold {
                return (i, nil, 0)
            }
            if trans > 0 && f < cursor + hold + trans {
                let rawT   = Double(f - (cursor + hold)) / Double(trans)
                let easedT = EasingMath.ease(rawT, type: state.easing)
                let nextIdx = (i + 1) % states.count
                return (i, nextIdx, easedT)
            }
            cursor += hold + trans
        }
        return (states.count - 1, nil, 0)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let c           = try decoder.container(keyedBy: CodingKeys.self)
        name            = try c.decodeIfPresent(String.self,              forKey: .name)           ?? "Cycle"
        loopMode        = try c.decodeIfPresent(SpriteCycleLoopMode.self, forKey: .loopMode)       ?? .loop
        states          = try c.decodeIfPresent([SpriteCycleState].self,  forKey: .states)         ?? []
        baseStateIndex  = try c.decodeIfPresent(Int.self,                 forKey: .baseStateIndex)
    }
}
