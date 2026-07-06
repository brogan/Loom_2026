import Foundation

// MARK: - SegmentExtractionMode

public enum SegmentExtractionMode: String, Codable, CaseIterable, Equatable, Sendable {
    case all       = "All"
    case alternate = "Alternate"
    case driven    = "Driven"
}

// MARK: - SegmentExtractionParams

/// Configuration for one pass of open-curve segment extraction.
///
/// Extraction breaks an open curve at its existing anchor points, producing
/// each selected segment as an independent open sub-curve. Operates on the
/// output of `CurveRefinementEngine` — refinement first, then extraction.
public struct SegmentExtractionParams: Equatable, Codable, Sendable {

    public var name:            String
    public var enabled:         Bool
    public var mode:            SegmentExtractionMode
    /// Alternate mode: when true, extract odd-indexed segments instead of even-indexed.
    public var alternateOffset: Bool
    /// Driven mode: DoubleDriver whose output (0..1) controls the fraction of
    /// segments extracted from the start of the curve. At 0 the curve is returned
    /// intact; at 1 all segments are individually extracted.
    public var driver:          DoubleDriver

    public init(
        name:            String                = "",
        enabled:         Bool                  = true,
        mode:            SegmentExtractionMode = .all,
        alternateOffset: Bool                  = false,
        driver:          DoubleDriver          = .zero
    ) {
        self.name            = name
        self.enabled         = enabled
        self.mode            = mode
        self.alternateOffset = alternateOffset
        self.driver          = driver
    }

    private enum CodingKeys: String, CodingKey {
        case name, enabled, mode, alternateOffset, driver
    }

    public init(from decoder: Decoder) throws {
        let d = SegmentExtractionParams()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name:            try c.decodeIfPresent(String.self,                forKey: .name)            ?? d.name,
            enabled:         try c.decodeIfPresent(Bool.self,                  forKey: .enabled)         ?? d.enabled,
            mode:            try c.decodeIfPresent(SegmentExtractionMode.self, forKey: .mode)            ?? d.mode,
            alternateOffset: try c.decodeIfPresent(Bool.self,                  forKey: .alternateOffset) ?? d.alternateOffset,
            driver:          try c.decodeIfPresent(DoubleDriver.self,          forKey: .driver)          ?? d.driver
        )
    }
}
