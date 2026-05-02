import AppKit
import SwiftUI
import LoomEngine

struct ContentView: View {

    @EnvironmentObject private var controller: AppController
    @State private var currentFrame: Int = 0

    var body: some View {
        if controller.engine != nil {
            mainLayout
        } else {
            landingView
        }
    }

    // MARK: - Main layout (project open)

    private var mainLayout: some View {
        VStack(spacing: 0) {
            RunControlBar(currentFrame: $currentFrame)
                .environmentObject(controller)

            Divider()

            tabBar

            Divider()

            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $controller.showingExportSheet) {
            if let engine = controller.engine {
                ExportSheet(engine: engine)
                    .environmentObject(controller)
            }
        }
        .onChange(of: controller.projectURL) { _, _ in currentFrame = 0 }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    controller.selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 11))
                        Text(tab.label)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        controller.selectedTab == tab
                            ? Color.primary.opacity(0.1)
                            : Color.clear
                    )
                    .foregroundStyle(
                        controller.selectedTab == tab ? Color.primary : Color.secondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }

    // MARK: - Three-column content area

    private var contentArea: some View {
        HStack(spacing: 0) {
            // Left: list panel (hidden for global tab)
            if controller.selectedTab.hasListPanel {
                listPanel
                    .frame(width: 240)
                Divider()
            }

            // Centre: main view
            mainPanel

            Divider()

            // Right: inspector
            InspectorPanel()
                .environmentObject(controller)
                .frame(width: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var listPanel: some View {
        switch controller.selectedTab {
        case .global:
            EmptyView()
        case .assets:
            AssetsTabView()
                .environmentObject(controller)
        case .geometry:
            GeometryTabView()
                .environmentObject(controller)
        case .subdivision:
            SubdivisionTabView()
                .environmentObject(controller)
        case .sprites:
            SpritesTabView()
                .environmentObject(controller)
        case .rendering:
            RenderingTabView()
                .environmentObject(controller)
        }
    }

    @ViewBuilder
    private var mainPanel: some View {
        switch controller.selectedTab {
        case .geometry:
            GeometryMainView()
                .environmentObject(controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sprites:
            SpriteWireframeView()
                .environmentObject(controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .subdivision:
            SubdivisionWireframeView()
                .environmentObject(controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            liveCanvas
        }
    }

    private var liveCanvas: some View {
        ZStack {
            Color.black
            if let engine = controller.engine {
                let size   = engine.canvasSize
                let aspect = size.width / max(size.height, 1)
                RenderSurfaceView(
                    engine:              engine,
                    playbackState:       controller.isExporting ? .paused : controller.playbackState,
                    onFrameTick:         { currentFrame = $0 },
                    onAnimationComplete: { controller.animationDidComplete() }
                )
                .aspectRatio(aspect, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Landing view (no project open)

    private var landingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Loom")
                .font(.largeTitle.bold())

            if let error = controller.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal)
            }

            Button("Open Project…") { controller.presentOpenPanel() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)

            if !controller.recentProjects.isEmpty {
                recentProjectsList
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var recentProjectsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Projects")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            ForEach(controller.recentProjects, id: \.self) { url in
                HStack {
                    Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.lastPathComponent).font(.body)
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { controller.open(projectDirectory: url) }
            }
        }
        .padding(.horizontal)
    }

}
