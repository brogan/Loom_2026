import SwiftUI
import LoomEngine

/// Reusable editor for a `DirectionalSelector` (Specs/GeometricLifecycle.md §14) —
/// shared by any inspector whose engine restricts edge/vertex targeting by
/// direction. Angle fields are shown/edited in degrees for readability; the
/// underlying model stores radians (`Vector2D.angle` / atan2 convention).
struct DirectionalSelectorEditor: View {
    let label: String
    @Binding var selector: DirectionalSelector
    @Binding var isCollapsed: Bool

    var body: some View {
        InspectorSection(label, isCollapsed: $isCollapsed) {
            InspectorField("Enabled") {
                Toggle("", isOn: $selector.enabled).labelsHidden()
            }
            .loomHelp("When on, restricts eligible edges to ones whose direction (Basis) falls within Tolerance of Target Angle — e.g. only the edge(s) facing a chosen direction, rather than every edge. Off (default): every edge is eligible, unchanged from before this existed.")

            if selector.enabled {
                InspectorField("Basis") {
                    Picker("", selection: $selector.basis) {
                        ForEach(DirectionalBasis.allCases, id: \.self) { b in
                            Text(b.rawValue).tag(b)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }
                .loomHelp("Outward Normal: compares each closed-polygon edge's outward-facing direction. Tangent: compares an open curve's direction of travel at a point.")

                InspectorField("Target angle") {
                    FloatEntryField(value: degreesBinding, width: 60)
                    Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Direction to match, in degrees. 0° = right (+x), 90° = straight up (+y), 180° = left, -90°/270° = straight down.")

                InspectorField("Tolerance") {
                    FloatEntryField(value: toleranceDegreesBinding, width: 60)
                    Text("°").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .loomHelp("Half-width of the acceptance cone, in degrees. 20° accepts edges within ±20° of Target angle. Too small a value can leave zero edges eligible for a given shape — the operator simply skips that generation/pass rather than erroring.")
            }
        }
    }

    private var degreesBinding: Binding<Double> {
        Binding(
            get: { selector.targetAngle * 180.0 / .pi },
            set: { selector.targetAngle = $0 * .pi / 180.0 }
        )
    }

    private var toleranceDegreesBinding: Binding<Double> {
        Binding(
            get: { selector.tolerance * 180.0 / .pi },
            set: { selector.tolerance = max(0, $0) * .pi / 180.0 }
        )
    }
}
