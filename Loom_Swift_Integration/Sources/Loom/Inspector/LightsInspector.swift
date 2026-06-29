import SwiftUI
import LoomEngine

struct LightsInspector: View {

    @EnvironmentObject private var controller: AppController

    @State private var posCollapsed      = false
    @State private var intensityCollapsed = false
    @State private var shapeCollapsed    = false
    @State private var posXDrvCollapsed  = true
    @State private var posYDrvCollapsed  = true
    @State private var intDrvCollapsed   = true
    @State private var radDrvCollapsed   = true
    @State private var dirDrvCollapsed   = true
    @State private var coneDrvCollapsed  = true
    @State private var wDrvCollapsed     = true
    @State private var hDrvCollapsed     = true
    @State private var rotDrvCollapsed   = true

    var body: some View {
        guard let idx = controller.selectedLightIndex,
              let lights = controller.projectConfig?.lightingConfig.lights,
              lights.indices.contains(idx)
        else { return AnyView(EmptyView()) }

        let light = lights[idx]

        return AnyView(VStack(alignment: .leading, spacing: 0) {

            // MARK: Light header
            InspectorSection(light.type.displayName) {
                InspectorField("Name") {
                    TextField("", text: bindName(idx))
                        .textFieldStyle(.squareBorder)
                        .font(.system(size: 12))
                }
                InspectorField("Enabled") {
                    Toggle("", isOn: bindBool(idx, \.isEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.75)
                }
                InspectorField("Colour") {
                    lightColourSwatch(idx: idx, light: light)
                }
                InspectorField("Falloff") {
                    FloatEntryField(
                        value: bindDouble(idx, \.falloff),
                        width: 44, fractionDigits: 1
                    )
                }
            }

            // MARK: Position
            InspectorSection("Position", isCollapsed: $posCollapsed) {
                InspectorField("X") {
                    Slider(value: bindDriverBase(idx, \.positionXDriver), in: -1...1)
                    FloatEntryField(
                        value: bindDriverBase(idx, \.positionXDriver),
                        width: 44, fractionDigits: 3
                    )
                }
                DoubleDriverEditor(label: "X Driver",
                                   driver: bindDriver(idx, \.positionXDriver),
                                   isCollapsed: $posXDrvCollapsed)
                    .environmentObject(controller)

                InspectorField("Y") {
                    Slider(value: bindDriverBase(idx, \.positionYDriver), in: -1...1)
                    FloatEntryField(
                        value: bindDriverBase(idx, \.positionYDriver),
                        width: 44, fractionDigits: 3
                    )
                }
                DoubleDriverEditor(label: "Y Driver",
                                   driver: bindDriver(idx, \.positionYDriver),
                                   isCollapsed: $posYDrvCollapsed)
                    .environmentObject(controller)
            }

            // MARK: Intensity
            InspectorSection("Intensity", isCollapsed: $intensityCollapsed) {
                InspectorField("Intensity") {
                    Slider(value: bindDriverBase(idx, \.intensityDriver), in: 0...1)
                    FloatEntryField(
                        value: bindDriverBase(idx, \.intensityDriver),
                        width: 44, fractionDigits: 2
                    )
                }
                DoubleDriverEditor(label: "Driver",
                                   driver: bindDriver(idx, \.intensityDriver),
                                   isCollapsed: $intDrvCollapsed)
                    .environmentObject(controller)
            }

            // MARK: Shape (type-specific)
            InspectorSection("Shape", isCollapsed: $shapeCollapsed) {
                switch light.type {
                case .omni:
                    omniFields(idx: idx)
                case .spot:
                    spotFields(idx: idx)
                case .area:
                    areaFields(idx: idx)
                }
            }
        })
    }

    // MARK: - Shape sub-sections

    @ViewBuilder
    private func omniFields(idx: Int) -> some View {
        InspectorField("Radius") {
            Slider(value: bindDriverBase(idx, \.radiusDriver), in: 0.01...1.5)
            FloatEntryField(
                value: bindDriverBase(idx, \.radiusDriver),
                width: 44, fractionDigits: 3
            )
        }
        DoubleDriverEditor(label: "Radius Driver",
                           driver: bindDriver(idx, \.radiusDriver),
                           isCollapsed: $radDrvCollapsed)
            .environmentObject(controller)
    }

    @ViewBuilder
    private func spotFields(idx: Int) -> some View {
        InspectorField("Radius") {
            Slider(value: bindDriverBase(idx, \.radiusDriver), in: 0.01...1.5)
            FloatEntryField(
                value: bindDriverBase(idx, \.radiusDriver),
                width: 44, fractionDigits: 3
            )
        }
        DoubleDriverEditor(label: "Radius Driver",
                           driver: bindDriver(idx, \.radiusDriver),
                           isCollapsed: $radDrvCollapsed)
            .environmentObject(controller)

        InspectorField("Direction") {
            Slider(value: bindDriverBase(idx, \.directionDriver), in: -.pi ... .pi)
            FloatEntryField(
                value: bindDriverBase(idx, \.directionDriver),
                width: 44, fractionDigits: 2
            )
        }
        DoubleDriverEditor(label: "Dir Driver",
                           driver: bindDriver(idx, \.directionDriver),
                           isCollapsed: $dirDrvCollapsed)
            .environmentObject(controller)

        InspectorField("Cone °") {
            Slider(value: bindDriverBase(idx, \.coneAngleDriver), in: 0.05 ... .pi/2)
            FloatEntryField(
                value: Binding(
                    get: { (controller.projectConfig?.lightingConfig.lights[safe: idx]?
                                .coneAngleDriver.base ?? .pi/6) * 180 / .pi },
                    set: { deg in controller.updateLightingConfig { cfg in
                        guard cfg.lights.indices.contains(idx) else { return }
                        cfg.lights[idx].coneAngleDriver.base = deg * .pi / 180
                    }}
                ),
                width: 44, fractionDigits: 1
            )
        }
        DoubleDriverEditor(label: "Cone Driver",
                           driver: bindDriver(idx, \.coneAngleDriver),
                           isCollapsed: $coneDrvCollapsed)
            .environmentObject(controller)

        InspectorField("Penumbra °") {
            Slider(value: bindDouble(idx, \.penumbraAngle), in: 0 ... .pi/4)
            FloatEntryField(
                value: Binding(
                    get: { (controller.projectConfig?.lightingConfig.lights[safe: idx]?.penumbraAngle ?? .pi/12) * 180 / .pi },
                    set: { deg in controller.updateLightingConfig { cfg in
                        guard cfg.lights.indices.contains(idx) else { return }
                        cfg.lights[idx].penumbraAngle = deg * .pi / 180
                    }}
                ),
                width: 44, fractionDigits: 1
            )
        }
    }

    @ViewBuilder
    private func areaFields(idx: Int) -> some View {
        InspectorField("Width") {
            Slider(value: bindDriverBase(idx, \.widthDriver), in: 0.01...2)
            FloatEntryField(
                value: bindDriverBase(idx, \.widthDriver),
                width: 44, fractionDigits: 3
            )
        }
        DoubleDriverEditor(label: "W Driver",
                           driver: bindDriver(idx, \.widthDriver),
                           isCollapsed: $wDrvCollapsed)
            .environmentObject(controller)

        InspectorField("Height") {
            Slider(value: bindDriverBase(idx, \.heightDriver), in: 0.01...2)
            FloatEntryField(
                value: bindDriverBase(idx, \.heightDriver),
                width: 44, fractionDigits: 3
            )
        }
        DoubleDriverEditor(label: "H Driver",
                           driver: bindDriver(idx, \.heightDriver),
                           isCollapsed: $hDrvCollapsed)
            .environmentObject(controller)

        InspectorField("Rotation") {
            Slider(value: bindDriverBase(idx, \.rotationDriver), in: -.pi ... .pi)
            FloatEntryField(
                value: bindDriverBase(idx, \.rotationDriver),
                width: 44, fractionDigits: 2
            )
        }
        DoubleDriverEditor(label: "Rot Driver",
                           driver: bindDriver(idx, \.rotationDriver),
                           isCollapsed: $rotDrvCollapsed)
            .environmentObject(controller)

        InspectorField("Softness") {
            Slider(value: bindDouble(idx, \.edgeSoftness), in: 0...0.2)
            FloatEntryField(
                value: bindDouble(idx, \.edgeSoftness),
                width: 44, fractionDigits: 3
            )
        }
    }

    // MARK: - Colour swatch

    @ViewBuilder
    private func lightColourSwatch(idx: Int, light: LoomLight) -> some View {
        let c = light.color
        ColorPicker("", selection: Binding(
            get: { Color(red: c.rF, green: c.gF, blue: c.bF, opacity: 1) },
            set: { newColor in
                guard let resolved = NSColor(newColor).usingColorSpace(.deviceRGB) else { return }
                controller.updateLightingConfig { cfg in
                    guard cfg.lights.indices.contains(idx) else { return }
                    cfg.lights[idx].color = LoomColor(
                        r: Int((resolved.redComponent   * 255).rounded()),
                        g: Int((resolved.greenComponent * 255).rounded()),
                        b: Int((resolved.blueComponent  * 255).rounded())
                    )
                }
            }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 40)
    }

    // MARK: - Bindings

    private func bindName(_ idx: Int) -> Binding<String> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.lightingConfig.lights[safe: idx]?.name ?? "" },
            set: { v in ctl.updateLightingConfig { cfg in
                guard cfg.lights.indices.contains(idx) else { return }
                cfg.lights[idx].name = v
            }}
        )
    }

    private func bindBool(_ idx: Int, _ kp: WritableKeyPath<LoomLight, Bool>) -> Binding<Bool> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.lightingConfig.lights[safe: idx]?[keyPath: kp] ?? true },
            set: { v in ctl.updateLightingConfig { cfg in
                guard cfg.lights.indices.contains(idx) else { return }
                cfg.lights[idx][keyPath: kp] = v
            }}
        )
    }

    private func bindDouble(_ idx: Int, _ kp: WritableKeyPath<LoomLight, Double>) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.lightingConfig.lights[safe: idx]?[keyPath: kp] ?? 0 },
            set: { v in ctl.updateLightingConfig { cfg in
                guard cfg.lights.indices.contains(idx) else { return }
                cfg.lights[idx][keyPath: kp] = v
            }}
        )
    }

    private func bindDriver(_ idx: Int, _ kp: WritableKeyPath<LoomLight, DoubleDriver>) -> Binding<DoubleDriver> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.lightingConfig.lights[safe: idx]?[keyPath: kp] ?? .zero },
            set: { v in ctl.updateLightingConfig { cfg in
                guard cfg.lights.indices.contains(idx) else { return }
                cfg.lights[idx][keyPath: kp] = v
            }}
        )
    }

    /// Binding that reads/writes only the `base` value of a DoubleDriver field.
    private func bindDriverBase(_ idx: Int, _ kp: WritableKeyPath<LoomLight, DoubleDriver>) -> Binding<Double> {
        let ctl = controller
        return Binding(
            get: { ctl.projectConfig?.lightingConfig.lights[safe: idx]?[keyPath: kp].base ?? 0 },
            set: { v in ctl.updateLightingConfig { cfg in
                guard cfg.lights.indices.contains(idx) else { return }
                cfg.lights[idx][keyPath: kp].base = v
            }}
        )
    }
}
