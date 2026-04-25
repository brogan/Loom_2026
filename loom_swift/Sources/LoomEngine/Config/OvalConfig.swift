/// A named oval set that references an external XML file.
///
/// Corresponds to `<OvalSet>` in `ovals.xml`.
public struct OvalSetDef: Codable, Sendable {
    /// The name used by `ShapeDef.ovalSetName` to reference this set.
    public var name:     String
    /// Sub-folder inside the project where the file lives.  Usually "ovalSets".
    public var folder:   String
    /// Filename of the oval XML file.
    public var filename: String

    public init(name: String, folder: String = "ovalSets", filename: String = "") {
        self.name = name; self.folder = folder; self.filename = filename
    }
}

/// The library of oval set definitions, loaded from `ovals.xml`.
public struct OvalSetLibrary: Codable, Sendable {
    public var name:     String
    public var ovalSets: [OvalSetDef]

    public init(name: String = "", ovalSets: [OvalSetDef] = []) {
        self.name = name; self.ovalSets = ovalSets
    }
}

/// Root wrapper matching the `<OvalConfig>` element.
public struct OvalConfig: Codable, Sendable {
    public var library: OvalSetLibrary

    public init(library: OvalSetLibrary = OvalSetLibrary()) {
        self.library = library
    }
}
