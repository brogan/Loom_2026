import Foundation
import SwiftUI
import LoomEngine

struct GlobalProjectInfoView: View {
    @EnvironmentObject private var controller: AppController

    @State private var geometryExpanded = false
    @State private var subdivisionExpanded = false
    @State private var spritesExpanded = false
    @State private var renderersExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let cfg = controller.projectConfig {
                    infoSection("Geometry", isExpanded: $geometryExpanded) {
                        geometryRows(cfg)
                    }
                    infoSection("Transform", isExpanded: $subdivisionExpanded) {
                        subdivisionRows(cfg)
                    }
                    infoSection("Sprites", isExpanded: $spritesExpanded) {
                        spriteRows(cfg)
                    }
                    infoSection("Renderers", isExpanded: $renderersExpanded) {
                        rendererRows(cfg)
                    }

                    Divider().padding(.vertical, 8)
                    statsRows(cfg)
                } else {
                    Text("No project open")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(12)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: controller.projectURL) { _, _ in
            geometryExpanded    = false
            subdivisionExpanded = false
            spritesExpanded     = false
            renderersExpanded   = false
        }
    }

    @ViewBuilder
    private func infoSection<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 3) {
                content()
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.bottom, 6)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func geometryRows(_ cfg: ProjectConfig) -> some View {
        let rows = geometryItems(cfg)
        if rows.isEmpty {
            emptyRow("No geometry")
        } else {
            ForEach(rows, id: \.id) { row in
                itemRow(row.name, detail: row.detail)
            }
        }
    }

    private func geometryItems(_ cfg: ProjectConfig) -> [(id: String, name: String, detail: String)] {
        let pointRows = cfg.pointConfig.library.pointSets.map {
            (id: "point-\($0.name)", name: displayName($0.name, fallback: $0.filename), detail: "Point set")
        }
        let curveRows = cfg.curveConfig.library.curveSets.map {
            (id: "curve-\($0.name)", name: displayName($0.name, fallback: $0.filename), detail: "Open curve")
        }
        let polygonRows = cfg.polygonConfig.library.polygonSets.map { def in
            let type: String
            if def.regularParams != nil {
                type = "Regular polygon"
            } else if def.filename.lowercased().hasSuffix(".json") {
                type = "Editable geometry"
            } else {
                type = def.polygonType == .linePolygon ? "Line polygon" : "Spline polygon"
            }
            return (id: "polygon-\(def.name)", name: displayName(def.name, fallback: def.filename), detail: type)
        }
        return pointRows + curveRows + polygonRows
    }

    @ViewBuilder
    private func subdivisionRows(_ cfg: ProjectConfig) -> some View {
        let sets = cfg.subdivisionConfig.paramsSets
        if sets.isEmpty {
            emptyRow("No subdivision sets")
        } else {
            ForEach(sets, id: \.name) { set in
                itemRow(displayName(set.name, fallback: "Unnamed set"), detail: "\(set.params.count) params")
            }
        }
    }

    @ViewBuilder
    private func spriteRows(_ cfg: ProjectConfig) -> some View {
        let sets = cfg.spriteConfig.library.spriteSets
        if sets.isEmpty {
            emptyRow("No sprite sets")
        } else {
            ForEach(sets, id: \.name) { set in
                groupRow(displayName(set.name, fallback: "Unnamed set"), count: set.sprites.count)
                ForEach(set.sprites, id: \.name) { sprite in
                    childRow(displayName(sprite.name, fallback: "Unnamed sprite"))
                }
            }
        }
    }

    @ViewBuilder
    private func rendererRows(_ cfg: ProjectConfig) -> some View {
        let sets = cfg.renderingConfig.library.rendererSets
        if sets.isEmpty {
            emptyRow("No renderer sets")
        } else {
            ForEach(sets, id: \.name) { set in
                groupRow(displayName(set.name, fallback: "Unnamed set"), count: set.renderers.count)
                ForEach(set.renderers, id: \.name) { renderer in
                    childRow(displayName(renderer.name, fallback: renderer.mode.label))
                }
            }
        }
    }

    @ViewBuilder
    private func statsRows(_ cfg: ProjectConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Project Files")
            statRow("Background image", backgroundImageName(cfg))
            statRow("Stamps", "\(countFiles(in: "stamps"))")
            statRow("Point sets", "\(countFiles(in: "pointSets"))")
            statRow("Curve sets", "\(countFiles(in: "curveSets"))")
            statRow("Polygon sets", "\(countFiles(in: "polygonSets"))")
            statRow("Regular polygons", "\(countFiles(in: "regularPolygons"))")
            statRow("Morph targets", "\(countFiles(in: "morphTargets"))")
            statRow("Still renders", "\(countFiles(in: "renders/stills"))")
            statRow("Animation renders", "\(countFiles(in: "renders/animations"))")
            statRow("SVGs", "\(countFiles(in: "svgs"))")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }

    private func itemRow(_ name: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(": \(detail)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func groupRow(_ name: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(": \(count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func childRow(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 10)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(label):")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    private func backgroundImageName(_ cfg: ProjectConfig) -> String {
        let path = cfg.globalConfig.backgroundImagePath
        guard !path.isEmpty else { return "None" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func countFiles(in relativePath: String) -> Int {
        guard let projectURL = controller.projectURL else { return 0 }
        let url = projectURL.appendingPathComponent(relativePath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.count
    }

    private func displayName(_ value: String, fallback: String) -> String {
        if !value.isEmpty { return value }
        if !fallback.isEmpty { return fallback }
        return "Unnamed"
    }
}

private extension RendererMode {
    var label: String {
        switch self {
        case .points:               return "Points"
        case .stroked:              return "Stroked"
        case .filled:               return "Filled"
        case .filledStroked:        return "Filled/stroked"
        case .gradientFilled:       return "Gradient filled"
        case .gradientFilledStroked: return "Gradient filled/stroked"
        case .brushed:              return "Brushed"
        case .stenciled:            return "Stenciled"
        case .stamped:              return "Stamped"
        }
    }
}
