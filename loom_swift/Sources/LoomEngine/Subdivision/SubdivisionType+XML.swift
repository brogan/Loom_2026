extension SubdivisionType {

    /// The string used to represent this algorithm in Loom project XML files.
    public var xmlName: String {
        switch self {
        case .quad:               return "QUAD"
        case .quadBord:           return "QUAD_BORD"
        case .quadBordEcho:       return "QUAD_BORD_ECHO"
        case .quadBordDouble:     return "QUAD_BORD_DOUBLE"
        case .quadBordDoubleEcho: return "QUAD_BORD_DOUBLE_ECHO"
        case .tri:                return "TRI"
        case .triBordA:           return "TRI_BORD_A"
        case .triBordAEcho:       return "TRI_BORD_A_ECHO"
        case .triBordB:           return "TRI_BORD_B"
        case .triBordBEcho:       return "TRI_BORD_B_ECHO"
        case .triBordC:           return "TRI_BORD_C"
        case .triBordCEcho:       return "TRI_BORD_C_ECHO"
        case .triStar:            return "TRI_STAR"
        case .triStarFill:        return "TRI_STAR_FILL"
        case .splitVert:          return "SPLIT_VERT"
        case .splitHoriz:         return "SPLIT_HORIZ"
        case .splitDiag:          return "SPLIT_DIAG"
        case .echo:               return "ECHO"
        case .echoAbsCenter:      return "ECHO_ABS_CENTER"
        }
    }

    /// Initialise from the XML string name.  Returns `nil` for unknown strings.
    public init?(xmlName: String) {
        switch xmlName {
        case "QUAD":                   self = .quad
        case "QUAD_BORD":              self = .quadBord
        case "QUAD_BORD_ECHO":         self = .quadBordEcho
        case "QUAD_BORD_DOUBLE":       self = .quadBordDouble
        case "QUAD_BORD_DOUBLE_ECHO":  self = .quadBordDoubleEcho
        case "TRI":                    self = .tri
        case "TRI_BORD_A":             self = .triBordA
        case "TRI_BORD_A_ECHO":        self = .triBordAEcho
        case "TRI_BORD_B":             self = .triBordB
        case "TRI_BORD_B_ECHO":        self = .triBordBEcho
        case "TRI_BORD_C":             self = .triBordC
        case "TRI_BORD_C_ECHO":        self = .triBordCEcho
        case "TRI_STAR":               self = .triStar
        case "TRI_STAR_FILL":          self = .triStarFill
        case "SPLIT_VERT":             self = .splitVert
        case "SPLIT_HORIZ":            self = .splitHoriz
        case "SPLIT_DIAG":             self = .splitDiag
        case "ECHO":                   self = .echo
        case "ECHO_ABS_CENTER":        self = .echoAbsCenter
        default:                       return nil
        }
    }
}
