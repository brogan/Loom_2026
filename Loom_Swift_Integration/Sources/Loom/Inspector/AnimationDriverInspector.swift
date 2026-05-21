import AppKit
import SwiftUI
import LoomEngine

// MARK: - DoubleDriverEditor

/// Collapsible inspector section for a single scalar animation driver.
struct DoubleDriverEditor: View {
    @EnvironmentObject private var controller: AppController

    let label: String
    @Binding var driver: DoubleDriver
    @Binding var isCollapsed: Bool
    var isHighlighted: Bool = false

    var body: some View {
        DriverSection(label, isCollapsed: $isCollapsed,
                      hasKeyframes: !driver.keyframes.isEmpty,
                      isEnabled: $driver.enabled,
                      isHighlighted: isHighlighted) {
            InspectorField("Mode") {
                LoomPicker(selection: $driver.mode, maxWidth: 120)
            }
            .loomHelp("Animation mode — Constant (fixed value), Jitter (random per-frame noise), Noise (smooth random), Oscillator (periodic wave), Keyframe (interpolated between saved values).")
            modeFields
        }
        .onChange(of: driver.keyframes.count) { old, new in
            if new > 0 && !driver.enabled { driver.enabled = true }
        }
    }

    @ViewBuilder
    private var modeFields: some View {
        switch driver.mode {
        case .constant:
            floatField("Value",    $driver.base)
            .loomHelp("Fixed scalar value output every frame.")

        case .jitter:
            floatField("Base",     $driver.base)
            .loomHelp("Centre value around which random jitter is applied each frame.")
            floatField("Range ±",  $driver.range)
            .loomHelp("Maximum deviation from Base — the output is a random value in [Base−Range, Base+Range] each frame.")
            intField("Seed",       $driver.seed)
            .loomHelp("Random seed for reproducible jitter. Change to get a different noise sequence.")

        case .noise:
            floatField("Base",     $driver.base)
            .loomHelp("Centre value of the smooth noise output.")
            floatField("Amplitude",$driver.amplitude)
            .loomHelp("Maximum deviation from Base produced by the smooth noise function.")
            intField("Period (f)", $driver.period)
            .loomHelp("Length in frames of one full noise cycle. Larger values = slower, smoother variation.")
            intField("Seed",       $driver.seed)
            .loomHelp("Random seed for reproducible smooth noise. Change to get a different noise shape.")

        case .oscillator:
            floatField("Base",     $driver.base)
            .loomHelp("Centre value that the oscillator wave is offset from.")
            floatField("Amplitude",$driver.amplitude)
            .loomHelp("Peak deviation from Base — the wave swings between Base−Amplitude and Base+Amplitude.")
            floatField("Freq Hz",  $driver.freqHz)
            .loomHelp("Oscillation frequency in cycles per second. Higher values = faster oscillation.")
            floatField("Phase 0–1",$driver.phase)
            .loomHelp("Starting phase offset of the wave (0 = start at centre crossing, 0.25 = start at peak).")
            InspectorField("Wave") {
                LoomPicker(selection: $driver.wave, maxWidth: 110)
            }
            .loomHelp("Wave shape — Sine (smooth), Triangle (linear ramp), Square (stepped), Sawtooth (rising ramp).")

        case .keyframe:
            InspectorField("Loop") {
                LoomPicker(selection: $driver.loopMode, maxWidth: 100)
            }
            .loomHelp("What happens after the last keyframe — Loop (wrap to start), Ping-Pong (reverse), Once (hold at last value).")
            DoubleKeyframeTable(
                keyframes: $driver.keyframes,
                firstFrame: controller.currentTimelineFrame,
                firstValue: driver.base
            )
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
    @EnvironmentObject private var controller: AppController

    let label: String
    @Binding var driver: VectorDriver
    @Binding var isCollapsed: Bool
    var isHighlighted: Bool = false

    var body: some View {
        DriverSection(label, isCollapsed: $isCollapsed,
                      hasKeyframes: !driver.keyframes.isEmpty,
                      isEnabled: $driver.enabled,
                      isHighlighted: isHighlighted) {
            InspectorField("Mode") {
                LoomPicker(selection: $driver.mode, maxWidth: 120)
            }
            .loomHelp("Animation mode — Constant (fixed XY), Jitter (random per-frame XY noise), Noise (smooth random XY), Oscillator (periodic XY wave), Keyframe (interpolated XY between saved values).")
            modeFields
        }
        .onChange(of: driver.keyframes.count) { old, new in
            if new > 0 && !driver.enabled { driver.enabled = true }
        }
    }

    @ViewBuilder
    private var modeFields: some View {
        switch driver.mode {
        case .constant:
            vec2Field("Value",     $driver.base)
            .loomHelp("Fixed XY value output every frame.")

        case .jitter:
            vec2Field("Base",      $driver.base)
            .loomHelp("Centre XY value around which random jitter is applied each frame.")
            vec2Field("Range ±",   $driver.range)
            .loomHelp("Maximum per-axis deviation from Base — each axis is independently randomised within ±Range each frame.")
            intField("Seed",       $driver.seed)
            .loomHelp("Random seed for reproducible XY jitter. Change to get a different noise sequence.")

        case .noise:
            vec2Field("Base",      $driver.base)
            .loomHelp("Centre XY value of the smooth noise output.")
            vec2Field("Amplitude", $driver.amplitude)
            .loomHelp("Maximum per-axis deviation from Base produced by the smooth noise function.")
            intField("Period (f)", $driver.period)
            .loomHelp("Length in frames of one full noise cycle per axis. Larger values = slower, smoother variation.")
            intField("Seed",       $driver.seed)
            .loomHelp("Random seed for reproducible smooth XY noise. Change to get a different noise shape.")

        case .oscillator:
            vec2Field("Base",      $driver.base)
            .loomHelp("Centre XY value that the oscillator waves are offset from.")
            vec2Field("Amplitude", $driver.amplitude)
            .loomHelp("Peak per-axis deviation from Base — each axis swings between Base−Amplitude and Base+Amplitude.")
            vec2Field("Freq Hz",   $driver.freqHz)
            .loomHelp("Per-axis oscillation frequency in cycles per second. Set X and Y differently for elliptical paths.")
            vec2Field("Phase 0–1", $driver.phase)
            .loomHelp("Per-axis starting phase offset of the wave (0–1). Offset X and Y by 0.25 for a circular orbit.")
            InspectorField("Wave") {
                LoomPicker(selection: $driver.wave, maxWidth: 110)
            }
            .loomHelp("Wave shape applied to both axes — Sine (smooth), Triangle (linear ramp), Square (stepped), Sawtooth (rising ramp).")

        case .keyframe:
            InspectorField("Loop") {
                LoomPicker(selection: $driver.loopMode, maxWidth: 100)
            }
            .loomHelp("What happens after the last keyframe — Loop (wrap to start), Ping-Pong (reverse), Once (hold at last value).")
            VectorKeyframeTable(
                keyframes: $driver.keyframes,
                firstFrame: controller.currentTimelineFrame,
                firstValue: driver.base
            )
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
    var firstFrame: Int
    var firstValue: Double

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
                    frame:  keyframes.isEmpty ? max(0, firstFrame) : (keyframes.last?.frame ?? 0) + 30,
                    value:  keyframes.last?.value ?? firstValue,
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
    var firstFrame: Int
    var firstValue: Vector2D

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
                    frame:  keyframes.isEmpty ? max(0, firstFrame) : (keyframes.last?.frame ?? 0) + 30,
                    value:  keyframes.last?.value ?? firstValue,
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

// MARK: - ColorDriverEditor

struct ColorDriverEditor: View {
    @EnvironmentObject private var controller: AppController

    let label: String
    @Binding var driver: ColorDriver
    @Binding var isCollapsed: Bool
    var isHighlighted: Bool = false

    var body: some View {
        DriverSection(label, isCollapsed: $isCollapsed,
                      hasKeyframes: !driver.keyframes.isEmpty,
                      isEnabled: $driver.enabled,
                      isHighlighted: isHighlighted) {
            InspectorField("Mode") {
                LoomPicker(selection: $driver.mode, maxWidth: 120)
            }
            .loomHelp("Animation mode — Constant (fixed colour), Keyframe (interpolated), Jitter (random per-frame flicker), Noise (smooth colour transition), Oscillator (periodic colour cycling).")
            switch driver.mode {
            case .constant:
                LoomColorField(label: "Value", color: $driver.base)
                .loomHelp("Fixed colour output every frame.")

            case .keyframe:
                InspectorField("Loop") {
                    LoomPicker(selection: $driver.loopMode, maxWidth: 100)
                }
                .loomHelp("What happens after the last keyframe — Loop (wrap to start), Ping-Pong (reverse), Once (hold last colour).")
                ColorKeyframeTable(
                    keyframes: $driver.keyframes,
                    firstFrame: controller.currentTimelineFrame,
                    firstValue: driver.base
                )

            case .jitter:
                LoomColorField(label: "Color A", color: $driver.base)
                .loomHelp("Base colour. Each frame the output is randomly shifted toward or away from Color B.")
                LoomColorField(label: "Color B", color: $driver.colorB)
                .loomHelp("Target colour for random jitter. The output oscillates between Color A and Color B.")
                InspectorField("Range") {
                    FloatEntryField(value: $driver.range, width: 55, fractionDigits: 2)
                    Text("0–0.5").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .loomHelp("Maximum random colour component deviation from Color A toward Color B (0–0.5).")
                InspectorField("Seed") {
                    TextField("", value: $driver.seed, format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50)
                }
                .loomHelp("Random seed for reproducible colour jitter. Change to get a different flicker pattern.")

            case .noise:
                LoomColorField(label: "Color A", color: $driver.base)
                .loomHelp("Base colour. The smooth noise output blends between Color A and Color B.")
                LoomColorField(label: "Color B", color: $driver.colorB)
                .loomHelp("Target colour blended toward by the smooth noise function.")
                InspectorField("Amplitude") {
                    FloatEntryField(value: $driver.amplitude, width: 55, fractionDigits: 2)
                    Text("0–0.5").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .loomHelp("Maximum smooth colour deviation from Color A toward Color B (0–0.5).")
                InspectorField("Period") {
                    TextField("", value: $driver.period, format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50)
                    Text("frames").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .loomHelp("Length in frames of one full smooth colour noise cycle. Larger values = slower transitions.")
                InspectorField("Seed") {
                    TextField("", value: $driver.seed, format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 50)
                }
                .loomHelp("Random seed for reproducible smooth colour noise. Change to get a different noise shape.")

            case .oscillator:
                LoomColorField(label: "Color A", color: $driver.base)
                .loomHelp("First colour in the oscillation cycle (wave trough).")
                LoomColorField(label: "Color B", color: $driver.colorB)
                .loomHelp("Second colour in the oscillation cycle (wave peak).")
                InspectorField("Freq (Hz)") {
                    FloatEntryField(value: $driver.freqHz, width: 55, fractionDigits: 3)
                }
                .loomHelp("Colour oscillation frequency in cycles per second. Higher values = faster cycling.")
                InspectorField("Phase") {
                    FloatEntryField(value: $driver.phase, width: 55, fractionDigits: 3)
                    Text("0–1").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .loomHelp("Starting phase offset of the colour wave (0 = start at Color A, 0.5 = start at Color B).")
                InspectorField("Wave") {
                    LoomPicker(selection: $driver.wave, maxWidth: 110)
                }
                .loomHelp("Wave shape controlling the blend between Color A and Color B — Sine (smooth), Triangle, Square (hard switch), Sawtooth.")
            }
        }
        .onChange(of: driver.keyframes.count) { old, new in
            if new > 0 && !driver.enabled { driver.enabled = true }
        }
    }
}

struct ColorKeyframeTable: View {
    @Binding var keyframes: [ColorKeyframe]
    var firstFrame: Int
    var firstValue: LoomColor

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Text("Frame").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 46, alignment: .leading)
                Text("Color").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 54, alignment: .leading)
                Text("Ease").font(.system(size: 9)).foregroundStyle(.tertiary).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 1)

            ForEach(keyframes.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    TextField("", value: $keyframes[i].frame, format: .number)
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 40)
                    ColorPicker("", selection: colorBinding(i), supportsOpacity: true)
                        .labelsHidden()
                        .frame(width: 42, height: 22)
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
                keyframes.append(ColorKeyframe(
                    frame: keyframes.isEmpty ? max(0, firstFrame) : (keyframes.last?.frame ?? 0) + 30,
                    value: keyframes.last?.value ?? firstValue,
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

    private func colorBinding(_ index: Int) -> Binding<Color> {
        Binding {
            let c = keyframes[safe: index]?.value ?? .black
            return Color(red: c.rF, green: c.gF, blue: c.bF, opacity: c.aF)
        } set: { newColor in
            guard index < keyframes.count else { return }
            let ns = NSColor(newColor).usingColorSpace(.deviceRGB) ?? NSColor.black
            keyframes[index].value = LoomColor(
                r: clamp255(ns.redComponent),
                g: clamp255(ns.greenComponent),
                b: clamp255(ns.blueComponent),
                a: clamp255(ns.alphaComponent)
            )
        }
    }

    private func clamp255(_ v: CGFloat) -> Int {
        Int(max(0, min(255, (v * 255 + 0.5).rounded(.down))))
    }
}

// MARK: - DriverSection

private struct DriverSection<Content: View>: View {
    let label: String
    @Binding var isCollapsed: Bool
    let hasKeyframes: Bool
    @Binding var isEnabled: Bool
    let isHighlighted: Bool
    let content: Content

    init(_ label: String, isCollapsed: Binding<Bool>, hasKeyframes: Bool,
         isEnabled: Binding<Bool>, isHighlighted: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.label         = label
        self._isCollapsed  = isCollapsed
        self.hasKeyframes  = hasKeyframes
        self._isEnabled    = isEnabled
        self.isHighlighted = isHighlighted
        self.content       = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Button { isCollapsed = !isCollapsed } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Image(systemName: hasKeyframes ? "circle.fill" : "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(hasKeyframes ? Color.green : Color.secondary.opacity(0.4))
                    .loomHelp("Green when this driver has keyframes; hollow when no keyframes exist. The indicator updates automatically.")
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .loomHelp("Enable or disable this driver. When disabled the driver outputs its identity value (zero offset, scale 1, etc.) regardless of mode or keyframes. Drivers start disabled; adding a keyframe in the timeline enables the driver automatically.")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            if !isCollapsed {
                content
            }
            Divider().padding(.top, isCollapsed ? 0 : 4)
        }
        .background(isHighlighted ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

// MARK: - Display name extensions (private to this file)

private extension EasingType {
    var shortLabel: String {
        switch self {
        case .linear:          return "Linear"
        case .easeInQuad:      return "In ²"
        case .easeOutQuad:     return "Out ²"
        case .easeInOutQuad:   return "In-Out ²"
        case .easeInCubic:     return "In ³"
        case .easeOutCubic:    return "Out ³"
        case .easeInOutCubic:  return "In-Out ³"
        case .easeInSine:      return "In sin"
        case .easeOutSine:     return "Out sin"
        case .easeInOutSine:   return "In-Out sin"
        case .easeInExpo:      return "In exp"
        case .easeOutExpo:     return "Out exp"
        case .easeInOutExpo:   return "In-Out exp"
        case .easeInBack:      return "In back"
        case .easeOutBack:     return "Out back"
        case .easeInOutBack:   return "In-Out back"
        }
    }
}
