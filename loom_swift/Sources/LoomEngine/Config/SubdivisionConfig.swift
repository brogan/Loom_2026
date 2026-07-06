/// A named, ordered list of `SubdivisionParams` — one complete subdivision recipe.
///
/// Corresponds to `<SubdivisionParamsSet>` in `subdivision.xml`.
/// A set may also carry `curveRefinement` passes for `.openSpline` polygons.
public struct SubdivisionParamsSet: Equatable, Codable, Sendable {
    public var name:             String
    public var params:           [SubdivisionParams]
    public var curveRefinement:  [CurveRefinementParams]

    public init(
        name:            String                  = "",
        params:          [SubdivisionParams]     = [],
        curveRefinement: [CurveRefinementParams] = []
    ) {
        self.name            = name
        self.params          = params
        self.curveRefinement = curveRefinement
    }

    private enum CodingKeys: String, CodingKey {
        case name, params, curveRefinement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name:            try c.decode(String.self,                      forKey: .name),
            params:          try c.decode([SubdivisionParams].self,         forKey: .params),
            curveRefinement: try c.decodeIfPresent([CurveRefinementParams].self, forKey: .curveRefinement) ?? []
        )
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
