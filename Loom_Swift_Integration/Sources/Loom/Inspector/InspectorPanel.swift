import SwiftUI
import LoomEngine

// Right-side inspector panel (280 px).
// Content is driven by the selected tab and the selected item within that tab.
struct InspectorPanel: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inspectorContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch controller.selectedTab {
        case .global:
            GlobalInspector()
                .environmentObject(controller)
        case .project:
            placeholderInspector("Select a project item to preview it.")
        case .geometry:
            if controller.selectedGeometryKey != nil {
                placeholderInspector("Geometry parameters — Phase 3")
            } else {
                placeholderInspector("Select a geometry set.")
            }
        case .subdivision:
            if controller.selectedSubdivisionIndex != nil {
                placeholderInspector("Subdivision parameters — Phase 3")
            } else {
                placeholderInspector("Select a subdivision set.")
            }
        case .sprites:
            if controller.selectedSpriteID != nil {
                placeholderInspector("Sprite parameters — Phase 3")
            } else {
                placeholderInspector("Select a sprite.")
            }
        case .rendering:
            if controller.selectedRendererIndex != nil {
                placeholderInspector("Renderer parameters — Phase 3")
            } else {
                placeholderInspector("Select a renderer set.")
            }
        }
    }

    private func placeholderInspector(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Global inspector
// Shows GlobalConfig fields. Editing support added in Phase 3.

private struct GlobalInspector: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        if let engine = controller.engine {
            let g = engine.globalConfig
            VStack(alignment: .leading, spacing: 0) {
                inspectorSection("Canvas") {
                    row("Name",    value: g.name.isEmpty ? "(none)" : g.name)
                    row("Width",   value: "\(g.width) px")
                    row("Height",  value: "\(g.height) px")
                    row("Quality", value: "\(g.qualityMultiple)×")
                }
                inspectorSection("Playback") {
                    row("FPS",        value: "\(Int(g.targetFPS))")
                    row("Animating",  value: g.animating ? "Yes" : "No")
                    row("BG once",    value: g.drawBackgroundOnce ? "Yes" : "No")
                }
                inspectorSection("Output") {
                    row("Project",    value: controller.projectURL?.lastPathComponent ?? "—")
                }
            }
        } else {
            Text("No project open")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(16)
        }
    }

    private func inspectorSection<Content: View>(_ title: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            content()

            Divider()
                .padding(.top, 4)
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}
