import Foundation

/// A named open-curve set that references an external XML file.
///
/// Corresponds to `<OpenCurveSet>` in `curves.xml`.
public struct OpenCurveSetDef: Codable, Sendable {
    /// The name used by `ShapeDef.openCurveSetName` to reference this set.
    public var name:     String
    /// Sub-folder inside the project where the file lives.  Usually "curveSets".
    public var folder:   String
    /// Filename of the open-curve XML file.
    public var filename: String
    /// Optional target layer inside an editable JSON geometry document — the
    /// open-curve counterpart of `PolygonSetDef.editableLayerID` (2026-07-12).
    /// `nil` (default) resolves every visible layer, unchanged from before
    /// these fields existed. Both `Optional`, so Swift's synthesized `Codable`
    /// treats a missing key as `nil` on decode — existing saved projects
    /// (which never wrote these keys) are unaffected.
    public var editableLayerID: UUID?
    /// Display/fallback name for the targeted editable JSON layer.
    public var editableLayerName: String?

    public init(
        name: String,
        folder: String   = "curveSets",
        filename: String = "",
        editableLayerID: UUID? = nil,
        editableLayerName: String? = nil
    ) {
        self.name               = name
        self.folder             = folder
        self.filename            = filename
        self.editableLayerID     = editableLayerID
        self.editableLayerName   = editableLayerName
    }
}

/// The library of open-curve set definitions, loaded from `curves.xml`.
public struct OpenCurveSetLibrary: Codable, Sendable {
    public var name: String
    public var curveSets: [OpenCurveSetDef]

    public init(name: String = "", curveSets: [OpenCurveSetDef] = []) {
        self.name = name; self.curveSets = curveSets
    }
}

/// Root wrapper matching the `<CurveConfig>` element.
public struct CurveConfig: Codable, Sendable {
    public var library: OpenCurveSetLibrary

    public init(library: OpenCurveSetLibrary = OpenCurveSetLibrary()) {
        self.library = library
    }
}
