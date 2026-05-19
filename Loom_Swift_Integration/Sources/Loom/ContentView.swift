import AppKit
import SwiftUI
import LoomEngine

private enum SpriteViewMode { case wireframe, parallax, preview }

struct ContentView: View {

    @EnvironmentObject private var controller: AppController
    @State private var currentFrame:      Int  = 0
    @State private var seekFrame:         Int? = nil
    @State private var spriteViewMode: SpriteViewMode = .wireframe
    @State private var subdivisionPreviewMode: Bool = false
    @State private var timelineCollapsed: Bool = false
    @State private var newProjectName: String = "MyProject"
    @State private var renderProgress: Double? = nil

    var body: some View {
        if controller.engine != nil || controller.projectConfig != nil {
            mainLayout
        } else {
            landingView
        }
    }

    // MARK: - Main layout (project open)

    private var mainLayout: some View {
        GeometryReader { geo in
        VStack(spacing: 0) {
            if controller.engine == nil, controller.loadError != nil {
                missingFileBanner
            }

            RunControlBar(currentFrame: $currentFrame, seekFrame: $seekFrame)
                .environmentObject(controller)

            Divider()

            tabBar

            Divider()

            contentArea

            TimelinePanel(currentFrame: currentFrame,
                          seekFrame: $seekFrame,
                          isCollapsed: $timelineCollapsed,
                          windowHeight: geo.size.height)
                .environmentObject(controller)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $controller.showingExportSheet) {
            if let engine = controller.engine {
                ExportSheet(engine: engine)
                    .environmentObject(controller)
            }
        }
        .alert(
            controller.geometryEditorLeaveWarningTitle,
            isPresented: $controller.showingGeometryEditorLeaveWarning
        ) {
            Button("Save & Leave") {
                controller.saveAndContinueAfterGeometryEditorWarning()
            }
            Button("Discard Changes", role: .destructive) {
                controller.discardAndContinueAfterGeometryEditorWarning()
            }
            Button("Cancel", role: .cancel) {
                controller.cancelGeometryEditorLeaveWarning()
            }
        } message: {
            Text(controller.geometryEditorLeaveWarningMessage)
        }
        .onChange(of: controller.projectURL) { _, _ in
            currentFrame = 0
            seekFrame = nil
            spriteViewMode = .wireframe
            subdivisionPreviewMode = false
            timelineCollapsed = shouldDefaultCollapseTimeline
        }
        .onAppear {
            timelineCollapsed = shouldDefaultCollapseTimeline
        }
        .onChange(of: currentFrame) { _, frame in controller.currentTimelineFrame = frame }
        .onChange(of: controller.selectedTab) { _, _ in
            timelineCollapsed = shouldDefaultCollapseTimeline
        }
    }

    private var shouldDefaultCollapseTimeline: Bool {
        controller.selectedTab == .geometry || controller.selectedTab == .subdivision
    }

    private var missingFileBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text("One or more geometry files are missing. Use the Geometry tab to re-link them, then the project will reload.")
                .font(.system(size: 11))
                .foregroundStyle(.primary)
            Spacer()
            Button("Geometry") { controller.requestTabSelection(.geometry) }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    controller.requestTabSelection(tab)
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
                .modifier(LoomHoverHelp(tab.label))
            }
            Spacer()
            hoverHelpField
            if let renderProgress {
                Text("Rendering \(Int((renderProgress * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Rendering progress")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
    }

    private var hoverHelpField: some View {
        Text(controller.hoverHelpText.isEmpty ? " " : controller.hoverHelpText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 520, maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(controller.hoverHelpText.isEmpty ? 0 : 0.045))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .layoutPriority(1)
            .animation(.easeOut(duration: 0.08), value: controller.hoverHelpText)
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
            GlobalProjectInfoView()
        case .geometry:
            GeometryTabView()
        case .subdivision:
            SubdivisionTabView()
        case .sprites:
            SpritesTabView()
        case .rendering:
            RenderingTabView()
        }
    }

    @ViewBuilder
    private var mainPanel: some View {
        switch controller.selectedTab {
        case .geometry:
            GeometryMainView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .sprites:
            ZStack(alignment: .topTrailing) {
                switch spriteViewMode {
                case .wireframe:
                    SpriteWireframeView(parallaxMode: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .parallax:
                    SpriteWireframeView(parallaxMode: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .preview:
                    liveCanvas
                }
                HStack(spacing: 4) {
                    spriteViewButton(.wireframe, label: "Edit",     icon: "pencil")
                    spriteViewButton(.parallax,  label: "Parallax", icon: "square.3.layers.3d")
                    spriteViewButton(.preview,   label: "Preview",  icon: "play.rectangle")
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .subdivision:
            ZStack(alignment: .topTrailing) {
                if subdivisionPreviewMode {
                    liveCanvas
                } else {
                    SubdivisionWireframeView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Button {
                    subdivisionPreviewMode.toggle()
                } label: {
                    Label(subdivisionPreviewMode ? "Edit" : "Preview",
                          systemImage: subdivisionPreviewMode ? "pencil" : "play.rectangle")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(subdivisionPreviewMode ? "Switch to wireframe editor" : "Switch to live preview")
                .modifier(LoomHoverHelp(subdivisionPreviewMode ? "Switch to wireframe editor" : "Switch to live preview"))
                .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            liveCanvas
        }
    }

    private func spriteViewButton(_ mode: SpriteViewMode, label: String, icon: String) -> some View {
        let isActive = spriteViewMode == mode
        return Button { spriteViewMode = mode } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isActive
                            ? Color.accentColor.opacity(0.35)
                            : Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isActive ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Switch to \(label.lowercased()) view")
        .modifier(LoomHoverHelp("Switch to \(label.lowercased()) view"))
    }

    private var liveCanvas: some View {
        ZStack {
            Color.black
            if let engine = controller.engine {
                let size   = controller.engineCanvasSize
                let aspect = size.width / max(size.height, 1)
                RenderSurfaceView(
                    engine:              engine,
                    playbackState:       controller.isExporting ? .paused : controller.playbackState,
                    seekFrame:           seekFrame,
                    onFrameTick:         {
                        currentFrame = $0
                        controller.currentTimelineFrame = $0
                    },
                    onAnimationComplete: { controller.animationDidComplete() },
                    onRenderProgress:    { renderProgress = $0 }
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

            VStack(spacing: 8) {
                TextField("Project name", text: $newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                HStack(spacing: 10) {
                    Button("New Project") {
                        controller.createProject(named: newProjectName)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Project…") { controller.presentOpenPanel() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("o", modifiers: .command)
                }
            }

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
