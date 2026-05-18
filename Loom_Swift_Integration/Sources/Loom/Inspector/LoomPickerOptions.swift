import Foundation
import LoomEngine

// Protocol for enum types usable with LoomPicker.
// Conformances below add pickerLabel and pickerHelp to LoomEngine enums;
// the help strings feed into the tab-bar hover help system.
protocol LoomPickerOption: Hashable, CaseIterable {
    var pickerLabel: String { get }
    var pickerHelp:  String { get }
}

// MARK: - Driver modes

extension DoubleDriver.Mode: LoomPickerOption {
    var pickerLabel: String {
        switch self {
        case .constant:   return "Constant"
        case .jitter:     return "Jitter"
        case .noise:      return "Noise"
        case .oscillator: return "Oscillator"
        case .keyframe:   return "Keyframe"
        }
    }
    var pickerHelp: String {
        switch self {
        case .constant:   return "Fixed value — no animation"
        case .jitter:     return "Per-frame random value within Base ± Range"
        case .noise:      return "Smooth random drift between Base ± Amplitude over a Period (frames)"
        case .oscillator: return "Repeating wave (sine / triangle / square / sawtooth) at a set frequency"
        case .keyframe:   return "Animates between keyframes you place on the timeline"
        }
    }
}

extension VectorDriver.Mode: LoomPickerOption {
    var pickerLabel: String {
        switch self {
        case .constant:   return "Constant"
        case .jitter:     return "Jitter"
        case .noise:      return "Noise"
        case .oscillator: return "Oscillator"
        case .keyframe:   return "Keyframe"
        }
    }
    var pickerHelp: String {
        switch self {
        case .constant:   return "Fixed XY value — no animation"
        case .jitter:     return "Per-frame random XY offset within Base ± Range"
        case .noise:      return "Smooth random XY drift over a Period (frames)"
        case .oscillator: return "Repeating XY wave (sine / triangle / square / sawtooth) at a set frequency"
        case .keyframe:   return "Animates between XY keyframes you place on the timeline"
        }
    }
}

extension ColorDriver.Mode: LoomPickerOption {
    var pickerLabel: String {
        switch self {
        case .constant:   return "Constant"
        case .keyframe:   return "Keyframe"
        case .jitter:     return "Jitter"
        case .noise:      return "Noise"
        case .oscillator: return "Oscillator"
        }
    }
    var pickerHelp: String {
        switch self {
        case .constant:   return "Fixed colour — no animation"
        case .keyframe:   return "Animates between colour keyframes you place on the timeline"
        case .jitter:     return "Per-frame random colour between Color A and Color B"
        case .noise:      return "Smooth random colour drift between Color A and Color B"
        case .oscillator: return "Oscillates colour between Color A and Color B at a set frequency"
        }
    }
}

// MARK: - Loop mode

extension LoopMode: LoomPickerOption {
    var pickerLabel: String {
        switch self {
        case .loop:     return "Loop"
        case .once:     return "Once"
        case .pingPong: return "Ping-Pong"
        }
    }
    var pickerHelp: String {
        switch self {
        case .loop:     return "Repeats from the first keyframe after the last"
        case .once:     return "Plays once and holds the final keyframe value"
        case .pingPong: return "Alternates forward and backward through the keyframes"
        }
    }
}

// MARK: - Easing

extension EasingType: LoomPickerOption {
    var pickerLabel: String {
        switch self {
        case .linear:         return "Linear"
        case .easeInOutQuad:  return "In-Out ²"
        case .easeInQuad:     return "In ²"
        case .easeOutQuad:    return "Out ²"
        case .easeInOutCubic: return "In-Out ³"
        case .easeInCubic:    return "In ³"
        case .easeOutCubic:   return "Out ³"
        }
    }
    var pickerHelp: String {
        switch self {
        case .linear:         return "Constant speed between keyframes"
        case .easeInQuad:     return "Starts slow, accelerates toward the next keyframe (quadratic)"
        case .easeOutQuad:    return "Decelerates as it approaches the next keyframe (quadratic)"
        case .easeInOutQuad:  return "Slow start and end, fastest in the middle (quadratic)"
        case .easeInCubic:    return "Strong slow start with sharp acceleration (cubic)"
        case .easeOutCubic:   return "Sharp start with strong deceleration (cubic)"
        case .easeInOutCubic: return "Slow start and end, fastest in the middle — stronger than quadratic"
        }
    }
}

// MARK: - Wave shape

extension WaveShape: LoomPickerOption {
    var pickerLabel: String { rawValue.capitalized }
    var pickerHelp: String {
        switch self {
        case .sine:     return "Smooth S-curve oscillation"
        case .triangle: return "Linear ramp up then down — V-shape"
        case .square:   return "Snaps between high and low with no transition"
        case .sawtooth: return "Ramps up linearly then instantly resets to low"
        }
    }
}
