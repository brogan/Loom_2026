// MARK: - Render-change enumerations

/// Whether a render parameter steps through its palette sequentially or randomly.
public enum ChangeKind: String, Codable, Sendable, CaseIterable {
    case sequential = "SEQ"
    case random     = "RAN"
}

/// Direction the palette index moves each step.
public enum ChangeMotion: String, Codable, Sendable, CaseIterable {
    case up       = "UP"
    case down     = "DOWN"
    case pingPong = "PING_PONG"
}

/// Whether the index advances every frame or pauses for a random number of frames.
public enum ChangeCycle: String, Codable, Sendable, CaseIterable {
    case constant = "CONSTANT"
    case pausing  = "PAUSING"
}

/// Scale at which the change is applied — determines which polygon the palette
/// index is shared across.
public enum ChangeScale: String, Codable, Sendable, CaseIterable {
    case poly   = "POLY"
    case sprite = "SPRITE"
    case global = "GLOBAL"
}

// MARK: - Individual change types

/// Animated fill-colour change: steps through a `LoomColor` palette.
public struct FillColorChange: Equatable, Codable, Sendable {
    public var enabled:  Bool
    public var kind:     ChangeKind
    public var motion:   ChangeMotion
    public var cycle:    ChangeCycle
    public var scale:    ChangeScale
    public var palette:  [LoomColor]
    public var pauseMax: Int

    public init(
        enabled:  Bool         = false,
        kind:     ChangeKind   = .random,
        motion:   ChangeMotion = .pingPong,
        cycle:    ChangeCycle  = .constant,
        scale:    ChangeScale  = .poly,
        palette:  [LoomColor]  = [],
        pauseMax: Int          = 0
    ) {
        self.enabled  = enabled; self.kind    = kind
        self.motion   = motion;  self.cycle   = cycle
        self.scale    = scale;   self.palette = palette
        self.pauseMax = pauseMax
    }
}

/// Animated stroke-colour change: steps through a `LoomColor` palette.
public struct StrokeColorChange: Equatable, Codable, Sendable {
    public var enabled:  Bool
    public var kind:     ChangeKind
    public var motion:   ChangeMotion
    public var cycle:    ChangeCycle
    public var scale:    ChangeScale
    public var palette:  [LoomColor]
    public var pauseMax: Int

    public init(
        enabled:  Bool         = false,
        kind:     ChangeKind   = .sequential,
        motion:   ChangeMotion = .up,
        cycle:    ChangeCycle  = .constant,
        scale:    ChangeScale  = .poly,
        palette:  [LoomColor]  = [],
        pauseMax: Int          = 0
    ) {
        self.enabled  = enabled; self.kind    = kind
        self.motion   = motion;  self.cycle   = cycle
        self.scale    = scale;   self.palette = palette
        self.pauseMax = pauseMax
    }
}

/// Animated stroke-width change: steps through a numeric size palette.
public struct StrokeWidthChange: Equatable, Codable, Sendable {
    public var enabled:      Bool
    public var kind:         ChangeKind
    public var motion:       ChangeMotion
    public var cycle:        ChangeCycle
    public var scale:        ChangeScale
    public var sizePalette:  [Double]
    public var pauseMax:     Int

    public init(
        enabled:     Bool         = false,
        kind:        ChangeKind   = .random,
        motion:      ChangeMotion = .up,
        cycle:       ChangeCycle  = .constant,
        scale:       ChangeScale  = .poly,
        sizePalette: [Double]     = [],
        pauseMax:    Int          = 0
    ) {
        self.enabled     = enabled; self.kind       = kind
        self.motion      = motion;  self.cycle      = cycle
        self.scale       = scale;   self.sizePalette = sizePalette
        self.pauseMax    = pauseMax
    }
}

/// All render-parameter changes declared inside a single `<Renderer>`.
///
/// Each change is optional; a nil value means that parameter is static.
public struct RendererChanges: Equatable, Codable, Sendable {
    public var fillColor:    FillColorChange?
    public var strokeColor:  StrokeColorChange?
    public var strokeWidth:  StrokeWidthChange?

    public init(
        fillColor:   FillColorChange?   = nil,
        strokeColor: StrokeColorChange? = nil,
        strokeWidth: StrokeWidthChange? = nil
    ) {
        self.fillColor   = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
    }

    /// True when no changes are defined.
    public var isEmpty: Bool {
        fillColor == nil && strokeColor == nil && strokeWidth == nil
    }
}

// MARK: - Renderer mode

/// Rendering output mode for a `Renderer`.
public enum RendererMode: String, CaseIterable, Codable, Sendable {
    case points        = "POINTS"
    case stroked       = "STROKED"
    case filled        = "FILLED"
    case filledStroked = "FILLED_STROKED"
    case brushed       = "BRUSHED"
    case stenciled     = "STENCILED"
    case stamped       = "STAMPED"
}

/// How a `RendererSet` cycles through its renderers.
public enum PlaybackMode: String, Codable, Sendable {
    case `static`  = "STATIC"
    case sequential = "SEQUENTIAL"
    case random    = "RANDOM"
    case all       = "ALL"
}

/// Controls playback behaviour of a `RendererSet`.
public struct RendererPlaybackConfig: Equatable, Codable, Sendable {
    public var mode: PlaybackMode             = .sequential
    public var preferredRenderer: String      = ""
    public var preferredProbability: Double   = 50.0
    public var modifyInternalParameters: Bool = false

    public init() {}
}

/// A single rendering style.
///
/// Corresponds to `<Renderer>` in `rendering.xml`.
/// `changes` holds any animated parameter variations declared in `<Changes>`.
public struct Renderer: Equatable, Codable, Sendable {
    public var name: String
    public var enabled: Bool
    public var mode: RendererMode
    public var strokeWidth: Double
    public var strokeColor: LoomColor
    public var fillColor: LoomColor
    public var pointSize: Double
    public var holdLength: Int
    /// Animated render-parameter changes. Empty when the renderer is static.
    public var changes: RendererChanges
    /// Non-nil when `mode == .brushed`.
    public var brushConfig: BrushConfig?
    /// Non-nil when `mode == .stamped` (or `.stenciled`).
    public var stencilConfig: StencilConfig?

    public init(
        name: String              = "",
        enabled: Bool             = true,
        mode: RendererMode        = .stroked,
        strokeWidth: Double       = 1.0,
        strokeColor: LoomColor    = .black,
        fillColor: LoomColor      = .black,
        pointSize: Double         = 2.0,
        holdLength: Int           = 1,
        changes: RendererChanges  = RendererChanges(),
        brushConfig: BrushConfig?   = nil,
        stencilConfig: StencilConfig? = nil
    ) {
        self.name = name; self.enabled = enabled; self.mode = mode
        self.strokeWidth = strokeWidth; self.strokeColor = strokeColor
        self.fillColor = fillColor; self.pointSize = pointSize
        self.holdLength = holdLength; self.changes = changes
        self.brushConfig = brushConfig; self.stencilConfig = stencilConfig
    }
}

/// A named collection of renderers with playback configuration.
public struct RendererSet: Equatable, Codable, Sendable {
    public var name: String
    public var playbackConfig: RendererPlaybackConfig
    public var renderers: [Renderer]

    public init(name: String, playbackConfig: RendererPlaybackConfig = .init(), renderers: [Renderer] = []) {
        self.name = name; self.playbackConfig = playbackConfig; self.renderers = renderers
    }
}

/// All renderer sets loaded from `rendering.xml`.
public struct RendererSetLibrary: Equatable, Codable, Sendable {
    public var name: String
    public var rendererSets: [RendererSet]

    public init(name: String = "", rendererSets: [RendererSet] = []) {
        self.name = name; self.rendererSets = rendererSets
    }

    /// Look up a renderer set by name. Returns `nil` when not found.
    public func rendererSet(named name: String) -> RendererSet? {
        rendererSets.first { $0.name == name }
    }
}

/// Root wrapper matching the `<RenderingConfig>` element.
public struct RenderingConfig: Equatable, Codable, Sendable {
    public var library: RendererSetLibrary

    public init(library: RendererSetLibrary = RendererSetLibrary()) {
        self.library = library
    }
}
