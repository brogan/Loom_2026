/// Identifies which subdivision algorithm is applied to a polygon.
///
/// Raw values match the Scala `Subdivision` companion object constants so
/// that XML files written by the Python/Scala tools decode without mapping.
/// Note: value 15 is unassigned in the Scala codebase.
public enum SubdivisionType: Int, CaseIterable, Codable, Sendable {

    // MARK: - Quad family
    case quad               = 0
    case quadBord           = 1
    case quadBordEcho       = 2
    case quadBordDouble     = 3
    case quadBordDoubleEcho = 4

    // MARK: - Tri family
    case tri                = 5
    case triBordA           = 6
    case triBordAEcho       = 7
    case triBordB           = 8
    case triStar            = 9
    case triBordC           = 10
    case triBordCEcho       = 11

    // MARK: - Split family
    case splitVert          = 12
    case splitHoriz         = 13
    case splitDiag          = 14

    // MARK: - Echo family (16/17; 15 is unused)
    case echo               = 16
    case echoAbsCenter      = 17

    // MARK: - Additional variants
    case triBordBEcho       = 18
    case triStarFill        = 19

    // MARK: - Output counts

    /// Number of child polygons produced from a polygon with `sidesTotal` sides.
    public func outputCount(sidesTotal n: Int) -> Int {
        switch self {
        case .quad:               return n
        case .quadBord:           return n
        case .quadBordEcho:       return n + 1
        case .quadBordDouble:     return n * 2
        case .quadBordDoubleEcho: return n * 2 + 1
        case .tri:                return n
        case .triBordA:           return n
        case .triBordAEcho:       return n + 1
        case .triBordB:           return n
        case .triBordBEcho:       return n + 1
        case .triBordC:           return n * 3
        case .triBordCEcho:       return n * 3 + 1
        case .triStar:            return n + 1   // N star tris + 1 inner polygon
        case .triStarFill:        return n * 2 + 1  // N star + N fill + 1 inner
        case .splitVert,
             .splitHoriz,
             .splitDiag:          return 2
        case .echo,
             .echoAbsCenter:      return 1
        }
    }
}
