import SwiftUI

struct AssetsTabView: View {

    @EnvironmentObject private var controller: AppController

    private struct FolderSpec {
        let label: String
        let folder: String
        let icon: String
    }

    private let folders: [FolderSpec] = [
        .init(label: "Polygon Sets",     folder: "polygonSets",      icon: "pentagon"),
        .init(label: "Curve Sets",       folder: "curveSets",        icon: "scribble"),
        .init(label: "Point Sets",       folder: "pointSets",        icon: "circle.grid.3x3.fill"),
        .init(label: "Regular Polygons", folder: "regularPolygons",  icon: "hexagon"),
        .init(label: "Morph Targets",    folder: "morph_targets",    icon: "waveform.path"),
        .init(label: "SVG",              folder: "svg",              icon: "doc.richtext"),
        .init(label: "Stamps",           folder: "stamps",           icon: "seal"),
        .init(label: "Brushes",          folder: "brushes",          icon: "paintbrush.pointed"),
        .init(label: "Palettes",         folder: "palettes",         icon: "swatchpalette"),
        .init(label: "Stencils",         folder: "stencils",         icon: "square.dashed"),
        .init(label: "Renders",          folder: "renders",          icon: "photo.stack"),
        .init(label: "Background",       folder: "background_image", icon: "photo"),
    ]

    var body: some View {
        if controller.projectURL != nil {
            List {
                ForEach(folders, id: \.folder) { spec in
                    assetSection(spec)
                }
            }
            .listStyle(.sidebar)
        } else {
            Text("No project open")
                .foregroundStyle(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func assetSection(_ spec: FolderSpec) -> some View {
        let items = folderItems(spec.folder)
        return Group {
            if !items.isEmpty {
                Section {
                    ForEach(items, id: \.self) { item in
                        Label(item.deletingPathExtension().lastPathComponent, systemImage: spec.icon)
                            .font(.system(size: 12))
                    }
                } header: {
                    Text(spec.label)
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func folderItems(_ folder: String) -> [URL] {
        guard let base = controller.projectURL else { return [] }
        let dir = base.appendingPathComponent(folder)
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ !$0.lastPathComponent.hasPrefix(".") })
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        else { return [] }
        return contents
    }
}
