extension VisibilityRule {

    /// The string used to represent this rule in Loom project XML files.
    public var xmlName: String {
        switch self {
        case .all:           return "ALL"
        case .quads:         return "QUADS"
        case .tris:          return "TRIS"
        case .allButLast:    return "ALL_BUT_LAST"
        case .alternateOdd:  return "ALTERNATE_ODD"
        case .alternateEven: return "ALTERNATE_EVEN"
        case .firstHalf:     return "FIRST_HALF"
        case .secondHalf:    return "SECOND_HALF"
        case .everyThird:    return "EVERY_THIRD"
        case .everyFourth:   return "EVERY_FOURTH"
        case .everyFifth:    return "EVERY_FIFTH"
        case .random1in2:    return "RANDOM_1_IN_2"
        case .random1in3:    return "RANDOM_1_IN_3"
        case .random1in5:    return "RANDOM_1_IN_5"
        case .random1in7:    return "RANDOM_1_IN_7"
        case .random1in10:   return "RANDOM_1_IN_10"
        }
    }

    /// Initialise from the XML string name.  Returns `nil` for unknown strings.
    public init?(xmlName: String) {
        switch xmlName {
        case "ALL":           self = .all
        case "QUADS":         self = .quads
        case "TRIS":          self = .tris
        case "ALL_BUT_LAST":  self = .allButLast
        case "ALTERNATE_ODD": self = .alternateOdd
        case "ALTERNATE_EVEN":self = .alternateEven
        case "FIRST_HALF":    self = .firstHalf
        case "SECOND_HALF":   self = .secondHalf
        case "EVERY_THIRD":   self = .everyThird
        case "EVERY_FOURTH":  self = .everyFourth
        case "EVERY_FIFTH":   self = .everyFifth
        case "RANDOM_1_IN_2", "RANDOM_1_2": self = .random1in2
        case "RANDOM_1_IN_3", "RANDOM_1_3": self = .random1in3
        case "RANDOM_1_IN_5", "RANDOM_1_5": self = .random1in5
        case "RANDOM_1_IN_7", "RANDOM_1_7": self = .random1in7
        case "RANDOM_1_IN_10","RANDOM_1_10":self = .random1in10
        default:              return nil
        }
    }
}
