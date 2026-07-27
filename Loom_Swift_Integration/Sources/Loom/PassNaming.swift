import Foundation

/// Generates the next unused default name for a newly-created transform pass
/// or renderer entry, so it's never left blank — `"conv_01"`, `"conv_02"`, …
/// per family. The user can always rename afterward; the point is that an
/// untouched pass is never actually nameless, which matters once passes are
/// addressed by name rather than array position (`LiveDriverTarget`,
/// `SessionWorkflow.md` §3.2) — a blank/duplicate name is the one case that
/// needs a fallback tiebreaker there, so minimizing how often that happens
/// is worth doing at creation time.
func defaultPassName(abbrev: String, existing: [String]) -> String {
    var i = 1
    while true {
        let candidate = String(format: "%@_%02d", abbrev, i)
        if !existing.contains(candidate) { return candidate }
        i += 1
    }
}
