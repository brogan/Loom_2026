import SwiftUI

struct ProjectTabView: View {

    @EnvironmentObject private var controller: AppController

    var body: some View {
        List {
            if let url = controller.projectURL {
                projectSection(label: "Polygon Sets",  folder: "polygonSets",    icon: "pentagon")
                projectSection(label: "Curve Sets",    folder: "curveSets",       icon: "scribble")
                projectSection(label: "Point Sets",    folder: "pointSets",       icon: "circle.grid.3x3.fill")
                projectSection(label: "Regular Polygons", folder: "regularPolygons", icon: "hexagon")
                projectSection(label: "Brushes",       folder: "brushes",         icon: "paintbrush.pointed")
                projectSection(label: "Stencils",      folder: "stencils",        icon: "seal")
                projectSection(label: "Renders",       folder: "renders",         icon: "photo.stack")
                projectSection(label: "Background",    folder: "background_image",icon: "photo")
            } else {
                Text("No project open")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .listStyle(.sidebar)
    }

    private func projectSection(label: String, folder: String, icon: String) -> some View {
        let url = controller.projectURL!.appendingPathComponent(folder)
        let fm  = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter({ !$0.lastPathComponent.hasPrefix(".") })
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        else { return AnyView(EmptyView()) }

        return AnyView(
            Section {
                ForEach(items, id: \.self) { item in
                    Label(item.deletingPathExtension().lastPathComponent, systemImage: icon)
                        .font(.system(size: 12))
                }
            } header: {
                Text(label)
            }
        )
    }
}
