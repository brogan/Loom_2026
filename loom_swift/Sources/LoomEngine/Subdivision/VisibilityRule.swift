/// Controls which child polygons are marked visible after subdivision.
///
/// Invisible polygons are pruned between generations, so rules compose
/// multiplicatively: `alternateOdd` applied twice leaves ≈25% of polygons.
/// Raw values match the Scala `Subdivision` constants for XML compatibility.
public enum VisibilityRule: Int, CaseIterable, Codable, Sendable {
    case all           = 0
    case quads         = 1   // only 4-sided polygons
    case tris          = 2   // only 3-sided polygons
    case allButLast    = 3
    case alternateOdd  = 4   // indices 1, 3, 5, …
    case alternateEven = 5   // indices 0, 2, 4, …
    case firstHalf     = 6   // indices 0 ..< N/2
    case secondHalf    = 7   // indices > N/2
    case everyThird    = 8   // indices divisible by 3
    case everyFourth   = 9
    case everyFifth    = 10
    case random1in2    = 11
    case random1in3    = 12
    case random1in5    = 13
    case random1in7    = 14
    case random1in10   = 15
}
