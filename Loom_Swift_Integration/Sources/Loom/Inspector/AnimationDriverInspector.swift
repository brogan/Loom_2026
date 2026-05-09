import SwiftUI
import LoomEngine

// MARK: - DoubleDriverEditor

/// Collapsible inspector section for a single scalar animation driver.
struct DoubleDriverEditor: View {
    let label: String
    @Binding var driver: DoubleDriver
    @State private var collapsed = false

    var body: some View {
        InspectorSection(label, isCollapsed: $collapsed) {
            InspectorField("Mode") {
                Picker("", selection: $driver.mode) {
                    ForEach(DoubleDriver.Mode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)
            }
            modeFields
        }
    }

    @ViewBuilder
    private var modeFields: some View {
        switch driver.mode {
        case .constant:
            floatField("Value",    $driver.base)

        case .jitter:
            floatField("Base",     $driver.base)
            floatField("Range ±",  $driver.range)
            intField("Seed",       $driver.seed)

        case .noise:
            floatField("Base",     $driver.base)
            floatField("Amplitude",$driver.amplitude)
            intField("Period (f)", $driver.period)
            intField("Seed",       $driver.seed)

        case .oscillator:
            floatField("Base",     $driver.base)
            floatField("Amplitude",$driver.amplitude)
            floatField("Freq Hz",  $driver.freqHz)
            floatField("Phase 0–1",$driver.phase)
            InspectorField("Wave") {
                Picker("", selection: $driver.wave) {
                    ForEach(WaveShape.allCases, id: \.self) { w in
                        Text(w.rawValue.capitalized).tag(w)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            }

        case .keyframe:
            InspectorField("Loop") {
                Picker("", selection: $driver.loopMode) {
                    ForEach(LoopMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 100)
            }
            DoubleKeyframeTable(keyframes: $driver.keyframes)
        }
    }

    private func floatField(_ lbl: String, _ b: Binding<Double>) -> some View {
        InspectorField(lbl) { FloatEntryField(value: b, width: 75, fractionDigits: 3, fontSize: 11) }
    }

    private func intField(_ lbl: String, _ b: Binding<Int>) -> some View {
        InspectorField(lbl) {
            TextField("", value: b, format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60)
        }
    }
}

// MARK: - VectorDriverEditor

/// Collapsible inspector section for a single 2-D vector animation driver.
struct VectorDriverEditor: View {
    let label: String
    @Binding var driver: VectorDriver
    @State private var collapsed = false

    var body: some View {
        InspectorSection(label, isCollapsed: $collapsed) {
            InspectorField("Mode") {
                Picker("", selection: $driver.mode) {
                    ForEach(VectorDriver.Mode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)
            }
            modeFields
        }
    }

    @ViewBuilder
    private var modeFields: some View {
        switch driver.mode {
        case .constant:
            vec2Field("Value",     $driver.base)

        case .jitter:
            vec2Field("Base",      $driver.base)
            vec2Field("Range ±",   $driver.range)
            intField("Seed",       $driver.seed)

        case .noise:
            vec2Field("Base",      $driver.base)
            vec2Field("Amplitude", $driver.amplitude)
            intField("Period (f)", $driver.period)
            intField("Seed",       $driver.seed)

        case .oscillator:
            vec2Field("Base",      $driver.base)
            vec2Field("Amplitude", $driver.amplitude)
            vec2Field("Freq Hz",   $driver.freqHz)
            vec2Field("Phase 0–1", $driver.phase)
            InspectorField("Wave") {
                Picker("", selection: $driver.wave) {
                    ForEach(WaveShape.allCases, id: \.self) { w in
                        Text(w.rawValue.capitalized).tag(w)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 110)
            }

        case .keyframe:
            InspectorField("Loop") {
                Picker("", selection: $driver.loopMode) {
                    ForEach(LoopMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 100)
            }
            VectorKeyframeTable(keyframes: $driver.keyframes)
        }
    }

    private func vec2Field(_ lbl: String, _ b: Binding<Vector2D>) -> some View {
        InspectorField(lbl) {
            HStack(spacing: 3) {
                Text("X").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 10)
                FloatEntryField(value: b.x, width: 48, fractionDigits: 2, fontSize: 11)
                Text("Y").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 10)
                FloatEntryField(value: b.y, width: 48, fractionDigits: 2, fontSize: 11)
            }
        }
    }

    private func intField(_ lbl: String, _ b: Binding<Int>) -> some View {
        InspectorField(lbl) {
            TextField("", value: b, format: .number)
                .textFieldStyle(.squareBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60)
        }
    }
}

// MARK: - DoubleKeyframeTable

struct DoubleKeyframeTable: View {
    @Binding var keyframes: [DoubleKeyframe]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Text("Frame").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 46, alignment: .leading)
                Text("Value").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 60, alignment: .leading)
                Text("Easing").font(.system(size: 9)).foregroundStyle(.tertiary).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 1)

            ForEach(keyframes.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    TextField("", value: $keyframes[i].frame, format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 40)
                    FloatEntryField(value: $keyframes[i].value, width: 56, fractionDigits: 2, fontSize: 10)
                    Picker("", selection: $keyframes[i].easing) {
                        ForEach(EasingType.allCases, id: \.self) { e in
                            Text(e.shortLabel).tag(e)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    Button { keyframes.remove(at: i) } label: {
                        Image(systemName: "minus.circle").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                }
                .padding(.horizontal, 12)
            }

            Button {
                keyframes.append(DoubleKeyframe(
                    frame:  (keyframes.last?.frame ?? 0) + 30,
                    value:  keyframes.last?.value ?? 0,
                    easing: .linear
                ))
            } label: {
                Label("Add keyframe", systemImage: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
    }
}

// MARK: - VectorKeyframeTable

struct VectorKeyframeTable: View {
    @Binding var keyframes: [VectorKeyframe]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Text("Frame").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 42, alignment: .leading)
                Text("X").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 48, alignment: .leading)
                Text("Y").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 48, alignment: .leading)
                Text("Ease").font(.system(size: 9)).foregroundStyle(.tertiary).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 1)

            ForEach(keyframes.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    TextField("", value: $keyframes[i].frame, format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 38)
                    FloatEntryField(value: $keyframes[i].value.x, width: 42, fractionDigits: 2, fontSize: 10)
                    FloatEntryField(value: $keyframes[i].value.y, width: 42, fractionDigits: 2, fontSize: 10)
                    Picker("", selection: $keyframes[i].easing) {
                        ForEach(EasingType.allCases, id: \.self) { e in
                            Text(e.shortLabel).tag(e)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    Button { keyframes.remove(at: i) } label: {
                        Image(systemName: "minus.circle").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                }
                .padding(.horizontal, 12)
            }

            Button {
                keyframes.append(VectorKeyframe(
                    frame:  (keyframes.last?.frame ?? 0) + 30,
                    value:  keyframes.last?.value ?? .zero,
                    easing: .linear
                ))
            } label: {
                Label("Add keyframe", systemImage: "plus").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
        }
    }
}

// MARK: - Display name extensions (private to this file)

private extension DoubleDriver.Mode {
    var label: String {
        switch self {
        case .constant:   return "Constant"
        case .jitter:     return "Jitter"
        case .noise:      return "Noise"
        case .oscillator: return "Oscillator"
        case .keyframe:   return "Keyframe"
        }
    }
}

private extension VectorDriver.Mode {
    var label: String {
        switch self {
        case .constant:   return "Constant"
        case .jitter:     return "Jitter"
        case .noise:      return "Noise"
        case .oscillator: return "Oscillator"
        case .keyframe:   return "Keyframe"
        }
    }
}

private extension LoopMode {
    var label: String {
        switch self {
        case .loop:     return "Loop"
        case .once:     return "Once"
        case .pingPong: return "Ping-Pong"
        }
    }
}

private extension EasingType {
    var shortLabel: String {
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
}
