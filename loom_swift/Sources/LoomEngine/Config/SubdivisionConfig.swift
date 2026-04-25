/// A named, ordered list of `SubdivisionParams` — one complete subdivision recipe.
///
/// Corresponds to `<SubdivisionParamsSet>` in `subdivision.xml`.
public struct SubdivisionParamsSet: Equatable, Codable, Sendable {
    public var name: String
    public var params: [SubdivisionParams]

    public init(name: String, params: [SubdivisionParams] = []) {
        self.name = name; self.params = params
    }
}

/// Root wrapper matching the `<SubdivisionConfig>` element.
///
/// Contains all named `SubdivisionParamsSet` objects loaded from
/// `configuration/subdivision.xml`.
public struct SubdivisionConfig: Equatable, Codable, Sendable {
    public var paramsSets: [SubdivisionParamsSet]

    public init(paramsSets: [SubdivisionParamsSet] = []) {
        self.paramsSets = paramsSets
    }

    /// Look up a params set by name. Returns `nil` when not found.
    public func paramsSet(named name: String) -> SubdivisionParamsSet? {
        paramsSets.first { $0.name == name }
    }
}
