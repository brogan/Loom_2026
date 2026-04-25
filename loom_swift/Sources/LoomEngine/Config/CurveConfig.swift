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

    public init(name: String, folder: String = "curveSets", filename: String = "") {
        self.name = name; self.folder = folder; self.filename = filename
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
