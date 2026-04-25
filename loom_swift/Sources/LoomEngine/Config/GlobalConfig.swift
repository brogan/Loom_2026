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
    public var backgroundColor: LoomColor = .white
    public var overlayColor: LoomColor   = LoomColor(r: 0, g: 0, b: 0, a: 170)
    public var backgroundImagePath: String = ""
    public var threeD: Bool              = false
    public var cameraViewAngle: Int      = 120
    public var subdividing: Bool         = true
    /// Frame rate assumed when interpreting integer `drawCycle` keyframe values.
    /// Keyframe times in XML are frame numbers; dividing by `targetFPS` gives seconds.
    /// Default 30 matches the typical Scala Loom frame rate.
    public var targetFPS: Double          = 30.0

    public init() {}

    public static let `default` = GlobalConfig()
}
