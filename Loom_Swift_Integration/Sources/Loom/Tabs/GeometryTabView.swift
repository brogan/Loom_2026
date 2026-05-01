import SwiftUI

// Left-panel list view for the Geometry tab.
// Shows geometry sets grouped by type; + button on each group creates a new set.
struct GeometryTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        List(selection: $controller.selectedGeometryKey) {
            geometryGroup(label: "Algorithmic",    folder: "regularPolygons", icon: "hexagon")
            geometryGroup(label: "Polygon Sets",   folder: "polygonSets",     icon: "pentagon")
            geometryGroup(label: "Curve Sets",     folder: "curveSets",       icon: "scribble")
            geometryGroup(label: "Point Sets",     folder: "pointSets",       icon: "circle.grid.3x3.fill")
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func geometryGroup(label: String, folder: String, icon: String) -> some View {
        let items = geometryItems(folder: folder)
        Section {
            if items.isEmpty {
                Text("None")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            } else {
                ForEach(items, id: \.self) { name in
                    HStack {
                        Label(name, systemImage: icon)
                            .font(.system(size: 12))
                        Spacer()
                        // Phase 2: sprite count badge
                    }
                    .tag("\(folder)/\(name)")
                    .contextMenu {
                        Button("Rename…") { }
                        Button("Duplicate") { }
                        Divider()
                        Button("Delete", role: .destructive) { }
                    }
                }
            }
        } header: {
            HStack {
                Text(label)
                Spacer()
                Button { } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("New \(label)")
            }
        }
    }

    private func geometryItems(folder: String) -> [String] {
        guard let base = controller.projectURL else { return [] }
        let dir = base.appendingPathComponent(folder)
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ !$0.lastPathComponent.hasPrefix(".") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        else { return [] }
        return contents.map { $0.deletingPathExtension().lastPathComponent }
    }
}

// Center-panel main view for the Geometry tab.
// Defaults to wireframe; switches to Bezier editor when editing.
struct GeometryMainView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        if controller.selectedGeometryKey != nil {
            // Phase 2: wireframe rendering of selected geometry set
            ZStack {
                Color.black
                Text("Wireframe preview — Phase 2")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } else {
            // No selection: show live scene as reference
            if let engine = controller.engine {
                RenderSurfaceView(
                    engine:        engine,
                    playbackState: controller.playbackState,
                    onFrameTick:   { _ in }
                )
            } else {
                Color.black
            }
        }
    }
}
