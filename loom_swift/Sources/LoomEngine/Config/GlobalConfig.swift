/// Top-level project settings loaded from `configuration/global_config.xml`.
///
/// All fields have safe defaults matching the Scala `GlobalConfig` case class.
public struct GlobalConfig: Equatable, Codable, Sendable {

    public var name: String              = "default"
    public var width: Int                = 1080
    public var height: Int               = 1080
    public var qualityMultiple: Int      = 1
    public var scaleImage: Bool          = false
    public var animating: Bool           = false
    public var drawBackgroundOnce: Bool  = false
    public var fullscreen: Bool          = false
    public var borderColor: LoomColor    = .black
    public var borderWidth: Double       = 0.0
    public var backgroundColor: LoomColor = .white
    public var overlayColor: LoomColor   = .clear
    public var backgroundImagePath: String = ""
    public var threeD: Bool              = false
    public var cameraViewAngle: Int      = 120
    public var subdividing: Bool         = true
    /// Frame rate assumed when interpreting integer `drawCycle` keyframe values.
    /// Keyframe times in XML are frame numbers; dividing by `targetFPS` gives seconds.
    /// Default 30 matches the typical Scala Loom frame rate.
    public var targetFPS: Double          = 30.0
    public var note: String               = ""
    /// Project duration in frames.  0 = derive from sprite totalDraws (legacy behaviour).
    public var duration: Int              = 0
    /// Animated camera.  `camera.enabled` must be true for pan/zoom/rotation to apply.
    public var camera: CameraConfig       = .disabled

    public init() {}

    public static let `default` = GlobalConfig()

    // Custom decoder: every field uses decodeIfPresent so that old project JSON files
    // that pre-date any given field can still load with the field's default value.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name               = try c.decodeIfPresent(String.self,       forKey: .name)               ?? "default"
        width              = try c.decodeIfPresent(Int.self,           forKey: .width)              ?? 1080
        height             = try c.decodeIfPresent(Int.self,           forKey: .height)             ?? 1080
        qualityMultiple    = try c.decodeIfPresent(Int.self,           forKey: .qualityMultiple)    ?? 1
        scaleImage         = try c.decodeIfPresent(Bool.self,          forKey: .scaleImage)         ?? false
        animating          = try c.decodeIfPresent(Bool.self,          forKey: .animating)          ?? false
        drawBackgroundOnce = try c.decodeIfPresent(Bool.self,          forKey: .drawBackgroundOnce) ?? false
        fullscreen         = try c.decodeIfPresent(Bool.self,          forKey: .fullscreen)         ?? false
        borderColor        = try c.decodeIfPresent(LoomColor.self,     forKey: .borderColor)        ?? .black
        borderWidth        = try c.decodeIfPresent(Double.self,        forKey: .borderWidth)        ?? 0.0
        backgroundColor    = try c.decodeIfPresent(LoomColor.self,     forKey: .backgroundColor)    ?? .white
        overlayColor       = try c.decodeIfPresent(LoomColor.self,     forKey: .overlayColor)       ?? .clear
        backgroundImagePath = try c.decodeIfPresent(String.self,       forKey: .backgroundImagePath) ?? ""
        threeD             = try c.decodeIfPresent(Bool.self,          forKey: .threeD)             ?? false
        cameraViewAngle    = try c.decodeIfPresent(Int.self,           forKey: .cameraViewAngle)    ?? 120
        subdividing        = try c.decodeIfPresent(Bool.self,          forKey: .subdividing)        ?? true
        targetFPS          = try c.decodeIfPresent(Double.self,        forKey: .targetFPS)          ?? 30.0
        note               = try c.decodeIfPresent(String.self,        forKey: .note)               ?? ""
        duration           = try c.decodeIfPresent(Int.self,           forKey: .duration)           ?? 0
        camera             = try c.decodeIfPresent(CameraConfig.self,  forKey: .camera)             ?? .disabled
    }
}
