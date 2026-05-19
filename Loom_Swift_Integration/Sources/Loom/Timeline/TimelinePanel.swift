import AppKit
import SwiftUI
import LoomEngine

// MARK: - File-private aliases / types

private typealias DriverLane = TimelineLane

private struct RowInfo {
    var spriteListIdx: Int
    var lane: DriverLane?   // nil = summary row
    var rendererLane: RendererTimelineLane? = nil
    var rendererSetIdx: Int? = nil
    var rendererItemIdx: Int? = nil
}

private struct TimelineNode {
    var setIdx:    Int
    var spriteIdx: Int
    var sprite:    SpriteDef
    var depth:     Int
}

private struct RendererTimelineRow {
    var rendererSetIdx: Int
    var rendererItemIdx: Int
    var rendererName: String
    var lane: RendererTimelineLane

    var id: String { "\(rendererSetIdx)-\(rendererItemIdx)-\(lane.rawValue)" }
    var label: String { "\(rendererName) \(lane.label)" }
}

private struct KFHit: Equatable {
    var spriteListIdx: Int
    var lane:          DriverLane
    var keyframeIdx:   Int
}

private enum TimelineSelectionItem: Hashable {
    case sprite(spriteListIdx: Int, lane: DriverLane, keyframeIdx: Int)
    case renderer(spriteListIdx: Int, rendererSetIdx: Int, rendererItemIdx: Int, lane: RendererTimelineLane, keyframeIdx: Int)
    case camera(lane: CameraLane, keyframeIdx: Int)
}

private enum CopiedTimelineKeyframe {
    case spriteVector(spriteListIdx: Int, lane: DriverLane, offset: Int, value: VectorKeyframe)
    case spriteDouble(spriteListIdx: Int, lane: DriverLane, offset: Int, value: DoubleKeyframe)
    case rendererColor(spriteListIdx: Int, rendererSetIdx: Int, rendererItemIdx: Int, lane: RendererTimelineLane, offset: Int, value: ColorKeyframe)
    case rendererDouble(spriteListIdx: Int, rendererSetIdx: Int, rendererItemIdx: Int, lane: RendererTimelineLane, offset: Int, value: DoubleKeyframe)
    case cameraVector(lane: CameraLane, offset: Int, value: VectorKeyframe)
    case cameraDouble(lane: CameraLane, offset: Int, value: DoubleKeyframe)

    var offset: Int {
        switch self {
        case .spriteVector(_, _, let offset, _),
             .spriteDouble(_, _, let offset, _),
             .rendererColor(_, _, _, _, let offset, _),
             .rendererDouble(_, _, _, _, let offset, _),
             .cameraVector(_, let offset, _),
             .cameraDouble(_, let offset, _):
            return offset
        }
    }
}

private struct KFDragState {
    var hit:          KFHit
    var previewFrame: Int
}

private struct RendererKFHit: Equatable {
    var spriteListIdx:   Int
    var rendererSetIdx:  Int
    var rendererItemIdx: Int
    var lane:            RendererTimelineLane
    var keyframeIdx:     Int
}

private struct RendererKFDragState {
    var hit:          RendererKFHit
    var previewFrame: Int
}

private enum DragKind { case none, seek, pan, rubberBand, keyframe, rendererKeyframe, camera }

// MARK: - TimelinePanel

struct TimelinePanel: View {
    @EnvironmentObject private var controller: AppController
    let currentFrame: Int
    @Binding var seekFrame: Int?
    @Binding var isCollapsed: Bool
    var windowHeight: CGFloat = 800

    @State private var panelHeight:           CGFloat       = 180
    @State private var resizeStartPanelHeight: CGFloat?     = nil
    @State private var zoom:                  Double        = 4.0
    @State private var hOffset:               Double        = 0
    @State private var expandedSprites:       Set<String>   = []
    @State private var prevDragTranslation:   CGFloat       = 0
    @State private var isDragInitialized:     Bool          = false
    @State private var dragKind:              DragKind      = .none
    @State private var wasPlayingBeforeScrub: Bool          = false
    @State private var selectedKF:            KFHit?        = nil
    @State private var kfDragState:           KFDragState?  = nil
    @State private var selectedRendererKF:    RendererKFHit? = nil
    @State private var rendererKFDragState:   RendererKFDragState? = nil
    @State private var selectedItems:         Set<TimelineSelectionItem> = []
    @State private var copiedItems:           [CopiedTimelineKeyframe] = []
    @State private var rubberBandStart:       CGPoint? = nil
    @State private var rubberBandEnd:         CGPoint? = nil
    @State private var rubberBandAdditive:    Bool = false
    @State private var timelineUndoStack:     [ProjectConfig] = []
    @State private var timelineRedoStack:     [ProjectConfig] = []
    @State private var cameraExpanded:        Bool          = false
    @State private var selectedCameraKFHit:   CameraKFSelection? = nil
    @State private var cameraDragState:       (lane: CameraLane, kfIdx: Int, previewFrame: Int)? = nil
    @State private var hiddenLanes:           Set<String>   = []

    private let headerWidth:  CGFloat = 160
    private let rowHeight:    CGFloat = 22
    private let rulerHeight:  CGFloat = 28
    private let hitTolerance: CGFloat = 8
    private let minPanelHeight:    CGFloat = 80
    private var maxPanelHeight:    CGFloat { windowHeight / 2 }
    private let resizeHandleHeight: CGFloat = 26
    private let bottomPadding:     CGFloat = 16

    private var cameraRowCount: Int { cameraExpanded ? 1 + visibleCameraLanes().count : 1 }
    private var spriteStartY: CGFloat { rulerHeight + CGFloat(cameraRowCount) * rowHeight }
    private var timelineContentHeight: CGFloat {
        rulerHeight + CGFloat(cameraRowCount + spriteTimelineRowCount) * rowHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            if !isCollapsed {
            GeometryReader { outer in
                ScrollView(.vertical) {
                    HStack(spacing: 0) {
                        laneHeaderColumn
                            .frame(width: headerWidth, height: timelineContentHeight, alignment: .top)
                        Divider()
                        GeometryReader { geo in
                            timelineCanvas(size: CGSize(width: geo.size.width, height: timelineContentHeight))
                                .frame(width: geo.size.width, height: timelineContentHeight)
                        }
                        .frame(height: timelineContentHeight)
                    }
                    .frame(height: timelineContentHeight + bottomPadding)
                    .frame(minWidth: outer.size.width, alignment: .leading)
                }
            }
            .frame(height: max(0, panelHeight - resizeHandleHeight))
            }
        }
        .frame(height: isCollapsed ? resizeHandleHeight : panelHeight)
        .background(Color(NSColor.controlBackgroundColor))
        .background(timelineCommandButtons.frame(width: 0, height: 0).opacity(0))
        .onChange(of: selectedKF) { _, newKF in syncSelection(newKF) }
        .onChange(of: selectedRendererKF) { _, newKF in syncRendererSelection(newKF) }
        .onChange(of: selectedCameraKFHit) { _, hit in controller.selectedCameraKF = hit }
        .onChange(of: controller.selectedSpriteID) { _, id in if id != nil { selectedCameraKFHit = nil } }
        .onChange(of: controller.projectURL) { _, _ in
            clearTimelineSelection()
            copiedItems.removeAll()
            timelineUndoStack.removeAll()
            timelineRedoStack.removeAll()
        }
    }

    private var timelineCommandButtons: some View {
        Group {
            Button("Timeline Copy") { copySelectedKeyframes() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(activeSelectionItems.isEmpty)
            Button("Timeline Paste") { pasteCopiedKeyframes() }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(copiedItems.isEmpty)
            Button("Timeline Undo") { undoTimelineChange() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(timelineUndoStack.isEmpty)
            Button("Timeline Redo") { redoTimelineChange() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(timelineRedoStack.isEmpty)
            Button("Timeline Delete") { deleteSelectedKeyframes() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(activeSelectionItems.isEmpty)
        }
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        ZStack {
            Color.clear
            Color(NSColor.separatorColor)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
            HStack(spacing: 5) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .semibold))
                Capsule()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 64, height: 5)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
            )
        }
        .frame(height: resizeHandleHeight)
        .contentShape(Rectangle())
        .onHover { if $0 { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if isCollapsed {
                        isCollapsed = false
                        resizeStartPanelHeight = max(panelHeight, minPanelHeight)
                    }
                    let startHeight = resizeStartPanelHeight ?? panelHeight
                    resizeStartPanelHeight = startHeight
                    panelHeight = max(minPanelHeight, min(maxPanelHeight, startHeight - value.translation.height))
                }
                .onEnded { _ in
                    resizeStartPanelHeight = nil
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    isCollapsed.toggle()
                    if !isCollapsed {
                        panelHeight = max(panelHeight, minPanelHeight)
                    }
                }
        )
    }

    // MARK: - Lane header column

    private var laneHeaderColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Button { zoom = max(1, zoom / 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass").font(.system(size: 12))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button { zoom = min(64, zoom * 1.5) } label: {
                    Image(systemName: "plus.magnifyingglass").font(.system(size: 12))
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                if !activeSelectionItems.isEmpty {
                    Button {
                        deleteSelectedKeyframes()
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.8))
                }
            }
            .frame(height: rulerHeight)
            .padding(.horizontal, 6)

            // Camera block
            HStack(spacing: 4) {
                Button {
                    cameraExpanded.toggle()
                    controller.selectedSpriteID = nil
                    selectedKF = nil
                    selectedRendererKF = nil
                } label: {
                    Image(systemName: cameraExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9)).frame(width: 10)
                }
                .buttonStyle(.plain)
                Image(systemName: "camera")
                    .font(.system(size: 9)).foregroundStyle(.teal)
                Text("Camera").font(.system(size: 11, weight: .medium))
                Spacer()
                let hiddenCamCount = CameraLane.allCases.filter { hiddenLanes.contains(cameraLaneID($0)) }.count
                let unusedCamCount: Int = {
                    guard let cam = controller.projectConfig?.globalConfig.camera else { return 0 }
                    return CameraLane.allCases.filter { lane in
                        guard !hiddenLanes.contains(cameraLaneID(lane)) else { return false }
                        let enabled: Bool = {
                            switch lane {
                            case .tracking: return cam.tracking.enabled
                            case .pan:      return cam.pan.enabled
                            case .zoom:     return cam.zoom.enabled
                            case .rotation: return cam.rotation.enabled
                            }
                        }()
                        return !enabled && lane.keyframeFrames(from: cam).isEmpty
                    }.count
                }()
                if hiddenCamCount > 0 {
                    Button {
                        CameraLane.allCases.forEach { hiddenLanes.remove(cameraLaneID($0)) }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "eye.slash").font(.system(size: 8))
                            Text("\(hiddenCamCount)").font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                } else if unusedCamCount > 0 {
                    Button {
                        guard let cam = controller.projectConfig?.globalConfig.camera else { return }
                        CameraLane.allCases.forEach { lane in
                            let enabled: Bool = {
                                switch lane {
                                case .tracking: return cam.tracking.enabled
                                case .pan:      return cam.pan.enabled
                                case .zoom:     return cam.zoom.enabled
                                case .rotation: return cam.rotation.enabled
                                }
                            }()
                            if !enabled && lane.keyframeFrames(from: cam).isEmpty {
                                hiddenLanes.insert(cameraLaneID(lane))
                            }
                        }
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                }
            }
            .frame(height: rowHeight)
            .padding(.leading, 4)
            if cameraExpanded {
                let cam = controller.projectConfig?.globalConfig.camera
                ForEach(visibleCameraLanes(), id: \.rawValue) { lane in
                    let hasKF  = !(lane.keyframeFrames(from: cam ?? .disabled).isEmpty)
                    let isEnab: Bool = {
                        switch lane {
                        case .tracking: return cam?.tracking.enabled ?? false
                        case .pan:      return cam?.pan.enabled      ?? false
                        case .zoom:     return cam?.zoom.enabled     ?? false
                        case .rotation: return cam?.rotation.enabled ?? false
                        }
                    }()
                    driverHeaderRow(lane.label, color: lane.color,
                                    isEnabled: isEnab, hasKeyframes: hasKF, isHidden: false,
                                    onTap: { selectCameraLane(lane, additive: shiftModifierActive) },
                                    onToggleEnabled: {
                                        controller.updateProjectConfig { cfg in
                                            switch lane {
                                            case .tracking: cfg.globalConfig.camera.tracking.enabled.toggle()
                                            case .pan:      cfg.globalConfig.camera.pan.enabled.toggle()
                                            case .zoom:     cfg.globalConfig.camera.zoom.enabled.toggle()
                                            case .rotation: cfg.globalConfig.camera.rotation.enabled.toggle()
                                            }
                                        }
                                    },
                                    onToggleHidden: { hiddenLanes.insert(cameraLaneID(lane)) })
                }
            }

            // Sprite block
            ForEach(timelineNodes, id: \.sprite.name) { node in
                spriteHeaderRow(node)
                if expandedSprites.contains(node.sprite.name) {
                    let si = timelineNodes.firstIndex { $0.sprite.name == node.sprite.name } ?? 0
                    let drivers = node.sprite.animation.drivers
                    ForEach(visibleSpriteLanes(for: node), id: \.rawValue) { lane in
                        let hasKF   = !(lane.keyframeFrames(from: drivers ?? .identity).isEmpty)
                        let isEnab: Bool = {
                            guard let d = drivers else { return false }
                            switch lane {
                            case .position: return d.position.enabled
                            case .scale:    return d.scale.enabled
                            case .rotation: return d.rotation.enabled
                            case .morph:    return d.morph.enabled
                            case .opacity:  return d.opacity.enabled
                            case .shape:    return d.shape.enabled
                            }
                        }()
                        driverHeaderRow(lane.label, color: lane.color,
                                        isEnabled: isEnab, hasKeyframes: hasKF, isHidden: false,
                                        onTap: { selectSpriteLane(spriteListIdx: si, lane: lane,
                                                                   additive: shiftModifierActive) },
                                        onToggleEnabled: {
                                            controller.updateProjectConfig { cfg in
                                                withDrivers(in: &cfg, si: node.setIdx, pi: node.spriteIdx) { d in
                                                    switch lane {
                                                    case .position: d.position.enabled.toggle()
                                                    case .scale:    d.scale.enabled.toggle()
                                                    case .rotation: d.rotation.enabled.toggle()
                                                    case .morph:    d.morph.enabled.toggle()
                                                    case .opacity:  d.opacity.enabled.toggle()
                                                    case .shape:    d.shape.enabled.toggle()
                                                    }
                                                }
                                            }
                                        },
                                        onToggleHidden: {
                                            hiddenLanes.insert(spriteLaneID(spriteName: node.sprite.name, lane: lane))
                                        })
                    }
                    ForEach(visibleRendererRows(for: node), id: \.id) { row in
                        let rend    = renderer(atSet: row.rendererSetIdx, item: row.rendererItemIdx)
                        let hasKF   = !(row.lane.keyframeFrames(from: rend?.drivers).isEmpty)
                        let isEnab: Bool = {
                            guard let d = rend?.drivers else { return false }
                            switch row.lane {
                            case .fillColor:   return d.fillColor?.enabled   ?? false
                            case .strokeColor: return d.strokeColor?.enabled ?? false
                            case .strokeWidth: return d.strokeWidth.enabled
                            case .opacity:     return d.opacity.enabled
                            }
                        }()
                        driverHeaderRow(row.label, color: row.lane.color, isRenderer: true,
                                        isEnabled: isEnab, hasKeyframes: hasKF, isHidden: false,
                                        onTap: { selectRendererLane(spriteListIdx: si, row: row,
                                                                     additive: shiftModifierActive) },
                                        onToggleEnabled: {
                                            controller.updateProjectConfig { cfg in
                                                withRendererDrivers(in: &cfg, setIdx: row.rendererSetIdx,
                                                                    itemIdx: row.rendererItemIdx) { d, _ in
                                                    switch row.lane {
                                                    case .fillColor:   d.fillColor?.enabled.toggle()
                                                    case .strokeColor: d.strokeColor?.enabled.toggle()
                                                    case .strokeWidth: d.strokeWidth.enabled.toggle()
                                                    case .opacity:     d.opacity.enabled.toggle()
                                                    }
                                                }
                                            }
                                        },
                                        onToggleHidden: {
                                            hiddenLanes.insert(rendererLaneID(row))
                                        })
                    }
                }
            }
        }
        .clipped()
    }

    private func spriteHeaderRow(_ node: TimelineNode) -> some View {
        let sprite     = node.sprite
        let expanded   = expandedSprites.contains(sprite.name)
        let hasDrivers = hasTimelineRows(for: node)
        let isSelected = controller.selectedSpriteID == sprite.name
        return HStack(spacing: 4) {
            if node.depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
            }
            Button {
                guard hasDrivers else { return }
                if expanded { expandedSprites.remove(sprite.name) }
                else        { expandedSprites.insert(sprite.name) }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9)).frame(width: 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(hasDrivers ? .primary : .tertiary)
            Circle()
                .fill(hasDrivers ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(sprite.name).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
            Spacer()
            let rendRows = rendererRows(for: node)
            let hiddenCount =
                DriverLane.allCases.filter { hiddenLanes.contains(spriteLaneID(spriteName: sprite.name, lane: $0)) }.count
                + rendRows.filter { hiddenLanes.contains(rendererLaneID($0)) }.count
            let unusedCount: Int = {
                let d = node.sprite.animation.drivers
                let spriteUnused = DriverLane.allCases.filter { lane in
                    guard !hiddenLanes.contains(spriteLaneID(spriteName: sprite.name, lane: lane)) else { return false }
                    guard let d else { return false }
                    let en: Bool = {
                        switch lane {
                        case .position: return d.position.enabled
                        case .scale:    return d.scale.enabled
                        case .rotation: return d.rotation.enabled
                        case .morph:    return d.morph.enabled
                        case .opacity:  return d.opacity.enabled
                        case .shape:    return d.shape.enabled
                        }
                    }()
                    return !en && lane.keyframeFrames(from: d).isEmpty
                }.count
                let rendUnused = rendRows.filter { row in
                    guard !hiddenLanes.contains(rendererLaneID(row)) else { return false }
                    let drivers = renderer(atSet: row.rendererSetIdx, item: row.rendererItemIdx)?.drivers
                    let en: Bool = {
                        guard let drivers else { return false }
                        switch row.lane {
                        case .fillColor:   return drivers.fillColor?.enabled   ?? false
                        case .strokeColor: return drivers.strokeColor?.enabled ?? false
                        case .strokeWidth: return drivers.strokeWidth.enabled
                        case .opacity:     return drivers.opacity.enabled
                        }
                    }()
                    return !en && row.lane.keyframeFrames(from: drivers).isEmpty
                }.count
                return spriteUnused + rendUnused
            }()
            if hiddenCount > 0 {
                Button {
                    DriverLane.allCases.forEach { hiddenLanes.remove(spriteLaneID(spriteName: sprite.name, lane: $0)) }
                    rendRows.forEach { hiddenLanes.remove(rendererLaneID($0)) }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "eye.slash").font(.system(size: 8))
                        Text("\(hiddenCount)").font(.system(size: 9))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            } else if unusedCount > 0 {
                Button {
                    if let d = node.sprite.animation.drivers {
                        DriverLane.allCases.forEach { lane in
                            let en: Bool = {
                                switch lane {
                                case .position: return d.position.enabled
                                case .scale:    return d.scale.enabled
                                case .rotation: return d.rotation.enabled
                                case .morph:    return d.morph.enabled
                                case .opacity:  return d.opacity.enabled
                                case .shape:    return d.shape.enabled
                                }
                            }()
                            if !en && lane.keyframeFrames(from: d).isEmpty {
                                hiddenLanes.insert(spriteLaneID(spriteName: sprite.name, lane: lane))
                            }
                        }
                    }
                    rendRows.forEach { row in
                        let drivers = renderer(atSet: row.rendererSetIdx, item: row.rendererItemIdx)?.drivers
                        let en: Bool = {
                            guard let drivers else { return false }
                            switch row.lane {
                            case .fillColor:   return drivers.fillColor?.enabled   ?? false
                            case .strokeColor: return drivers.strokeColor?.enabled ?? false
                            case .strokeWidth: return drivers.strokeWidth.enabled
                            case .opacity:     return drivers.opacity.enabled
                            }
                        }()
                        if !en && row.lane.keyframeFrames(from: drivers).isEmpty {
                            hiddenLanes.insert(rendererLaneID(row))
                        }
                    }
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
        }
        .frame(height: rowHeight)
        .padding(.leading, CGFloat(node.depth) * 12 + 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.selectedSpriteID = sprite.name
            clearTimelineSelection()
        }
    }

    private func driverHeaderRow(
        _ label: String,
        color: Color,
        isRenderer: Bool = false,
        isEnabled: Bool,
        hasKeyframes: Bool,
        isHidden: Bool,
        onTap: (() -> Void)? = nil,
        onToggleEnabled: @escaping () -> Void,
        onToggleHidden: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 14)
            Circle().fill(color.opacity(0.5)).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(isEnabled ? .secondary : .tertiary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Circle()
                .fill(hasKeyframes ? Color.green : Color.white.opacity(0.45))
                .overlay(Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 0.5))
                .frame(width: 6, height: 6)
            Button(action: onToggleEnabled) {
                Image(systemName: isEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            Button(action: onToggleHidden) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 6)
        .frame(height: rowHeight)
        .padding(.leading, 14)
        .background(isRenderer
                    ? Color.black.opacity(0.12)
                    : Color(NSColor.windowBackgroundColor).opacity(0.35))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    // MARK: - Timeline canvas

    private func timelineCanvas(size: CGSize) -> some View {
        Canvas { ctx, sz in
            self.drawBackground(&ctx, size: sz)
            self.drawRuler(&ctx, size: sz)
            self.drawKeyframes(&ctx, size: sz)
            self.drawRubberBand(&ctx)
            self.drawPlayhead(&ctx, size: sz)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in onDragChanged(v) }
                .onEnded   { v in onDragEnded(v)   }
        )
        .clipped()
        .background(TimelineKeyCaptureView { event in handleKeyEvent(event) })
    }

    // MARK: - Gesture

    private func onDragChanged(_ v: DragGesture.Value) {
        if !isDragInitialized {
            isDragInitialized   = true
            prevDragTranslation = 0
            if v.startLocation.y < rulerHeight {
                dragKind              = .seek
                wasPlayingBeforeScrub = controller.playbackState == .playing
                controller.pause()
            } else if isCameraArea(v.startLocation) {
                if let camHit = cameraHitTest(at: v.startLocation) {
                    dragKind                    = .camera
                    selectCameraKeyframe(camHit, additive: shiftModifierActive)
                    selectedCameraKFHit         = camHit
                    seekFrame                   = storedCameraFrame(camHit)
                    controller.selectedSpriteID = nil
                    cameraDragState             = (camHit.lane, camHit.keyframeIdx,
                                                  storedCameraFrame(camHit))
                } else {
                    dragKind = .pan
                }
            } else if let hit = hitTest(at: v.startLocation) {
                dragKind            = .keyframe
                selectSpriteKeyframe(hit, additive: shiftModifierActive)
                seekFrame           = storedFrame(hit)
                kfDragState         = KFDragState(hit: hit, previewFrame: storedFrame(hit))
            } else if let hit = rendererHitTest(at: v.startLocation) {
                dragKind            = .rendererKeyframe
                selectRendererKeyframe(hit, additive: shiftModifierActive)
                seekFrame           = storedRendererFrame(hit)
                rendererKFDragState = RendererKFDragState(hit: hit, previewFrame: storedRendererFrame(hit))
            } else {
                let row = rowInfo(at: v.startLocation)
                let onLaneRow = row?.lane != nil || row?.rendererLane != nil
                if optionModifierActive || onLaneRow {
                    dragKind = .pan
                } else {
                    dragKind = .rubberBand
                    rubberBandStart = v.startLocation
                    rubberBandEnd = v.location
                    rubberBandAdditive = shiftModifierActive
                }
            }
        }

        switch dragKind {
        case .seek:
            let f = Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded())
            seekFrame = max(0, min(controller.maxScrubFrames, f))
        case .keyframe:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            if let s = kfDragState { kfDragState = KFDragState(hit: s.hit, previewFrame: f) }
        case .rendererKeyframe:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            if let s = rendererKFDragState { rendererKFDragState = RendererKFDragState(hit: s.hit, previewFrame: f) }
        case .camera:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            if let s = cameraDragState { cameraDragState = (s.lane, s.kfIdx, f) }
        case .pan:
            let delta           = v.translation.width - prevDragTranslation
            hOffset             = max(0, hOffset - delta)
            prevDragTranslation = v.translation.width
        case .rubberBand:
            rubberBandEnd = v.location
        case .none: break
        }
    }

    private func onDragEnded(_ v: DragGesture.Value) {
        let isTap = abs(v.translation.width) < 4 && abs(v.translation.height) < 4

        switch dragKind {
        case .seek:
            if wasPlayingBeforeScrub { controller.play() }

        case .keyframe:
            if !isTap, let state = kfDragState { commitDrag(state) }
            kfDragState = nil

        case .rendererKeyframe:
            if !isTap, let state = rendererKFDragState { commitRendererDrag(state) }
            rendererKFDragState = nil

        case .camera:
            if !isTap, let state = cameraDragState { commitCameraDrag(state) }
            cameraDragState = nil

        case .pan:
            if isTap {
                let f = max(0, Int(((v.startLocation.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
                if let lane = cameraLaneAt(v.startLocation) {
                    addCameraKeyframe(lane: lane, frame: f)
                } else if let row = rowInfo(at: v.startLocation) {
                    if let lane = row.lane {
                        addKeyframe(spriteListIdx: row.spriteListIdx, lane: lane, frame: f)
                    } else if let lane = row.rendererLane,
                              let setIdx = row.rendererSetIdx,
                              let itemIdx = row.rendererItemIdx {
                        addRendererKeyframe(spriteListIdx: row.spriteListIdx, setIdx: setIdx, itemIdx: itemIdx, lane: lane, frame: f)
                    }
                } else {
                    clearTimelineSelection()
                }
            }

        case .rubberBand:
            if let start = rubberBandStart, let end = rubberBandEnd {
                selectKeyframes(in: CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(start.x - end.x),
                    height: abs(start.y - end.y)
                ), additive: rubberBandAdditive)
            }
            rubberBandStart = nil
            rubberBandEnd = nil

        case .none: break
        }

        isDragInitialized   = false
        prevDragTranslation = 0
    }

    // MARK: - Selection sync

    private func syncSelection(_ hit: KFHit?) {
        guard let hit = hit, let loc = spriteLocation(listIdx: hit.spriteListIdx) else {
            controller.selectedTimelineKF = nil
            return
        }
        controller.selectedRendererTimelineKF = nil
        controller.selectedSpriteID = timelineNodes[safe: hit.spriteListIdx]?.sprite.name
        controller.requestTabSelection(.sprites)
        controller.selectedTimelineKF = TimelineKFSelection(
            setIdx:      loc.setIdx,
            spriteIdx:   loc.spriteIdx,
            lane:        hit.lane,
            keyframeIdx: hit.keyframeIdx
        )
    }

    private func syncRendererSelection(_ hit: RendererKFHit?) {
        guard let hit else {
            controller.selectedRendererTimelineKF = nil
            return
        }
        controller.selectedTimelineKF = nil
        controller.selectedRendererIndex = hit.rendererSetIdx
        controller.selectedRendererItemIndex = hit.rendererItemIdx
        controller.requestTabSelection(.rendering)
        controller.selectedRendererTimelineKF = RendererTimelineKFSelection(
            rendererSetIdx: hit.rendererSetIdx,
            rendererItemIdx: hit.rendererItemIdx,
            lane: hit.lane,
            keyframeIdx: hit.keyframeIdx
        )
    }

    // MARK: - Drawing

    private func drawBackground(_ ctx: inout GraphicsContext, size: CGSize) {
        // Camera block
        ctx.fill(Path(CGRect(x: 0, y: rulerHeight, width: size.width, height: rowHeight)),
                 with: .color(Color(NSColor.windowBackgroundColor).opacity(0.55)))
        if cameraExpanded {
            var camY = rulerHeight + rowHeight
            for j in 0..<visibleCameraLanes().count {
                ctx.fill(Path(CGRect(x: 0, y: camY, width: size.width, height: rowHeight)),
                         with: .color(j.isMultiple(of: 2)
                             ? Color(NSColor.windowBackgroundColor).opacity(0.35)
                             : Color(NSColor.windowBackgroundColor).opacity(0.25)))
                camY += rowHeight
            }
        }
        // Sprite block
        let pxPerFrame = CGFloat(zoom)
        var rowY = spriteStartY
        for (i, node) in timelineNodes.enumerated() {
            let sprite = node.sprite
            ctx.fill(
                Path(CGRect(x: 0, y: rowY, width: size.width, height: rowHeight)),
                with: .color(i.isMultiple(of: 2)
                    ? Color(NSColor.controlBackgroundColor)
                    : Color(NSColor.controlBackgroundColor).opacity(0.8))
            )
            rowY += rowHeight
            let visSpriteLanes   = visibleSpriteLanes(for: node)
            let visRendererRows  = visibleRendererRows(for: node)
            let laneCount = visSpriteLanes.count + visRendererRows.count
            if expandedSprites.contains(sprite.name) {
                for j in 0..<visSpriteLanes.count {
                    ctx.fill(
                        Path(CGRect(x: 0, y: rowY, width: size.width, height: rowHeight)),
                        with: .color(j.isMultiple(of: 2)
                            ? Color(NSColor.windowBackgroundColor).opacity(0.5)
                            : Color(NSColor.windowBackgroundColor).opacity(0.35))
                    )
                    rowY += rowHeight
                }
                for j in 0..<visRendererRows.count {
                    ctx.fill(
                        Path(CGRect(x: 0, y: rowY, width: size.width, height: rowHeight)),
                        with: .color(j.isMultiple(of: 2)
                            ? Color.black.opacity(0.13)
                            : Color.black.opacity(0.18))
                    )
                    rowY += rowHeight
                }
                // Gate overlay: dim inactive regions across all visible lane rows.
                let gs = sprite.gateStart, ge = sprite.gateEnd
                if gs > 0 || ge > 0 {
                    let laneBlockY = rowY - CGFloat(laneCount) * rowHeight
                    let laneBlockH = CGFloat(laneCount) * rowHeight
                    let gateColor  = Color.black.opacity(0.18)
                    if gs > 0 {
                        let endX = CGFloat(gs) * pxPerFrame - CGFloat(hOffset)
                        if endX > 0 {
                            ctx.fill(Path(CGRect(x: 0, y: laneBlockY,
                                                  width: min(endX, size.width), height: laneBlockH)),
                                     with: .color(gateColor))
                        }
                    }
                    if ge > 0 {
                        let startX = CGFloat(ge) * pxPerFrame - CGFloat(hOffset)
                        if startX < size.width {
                            ctx.fill(Path(CGRect(x: max(startX, 0), y: laneBlockY,
                                                  width: size.width - max(startX, 0), height: laneBlockH)),
                                     with: .color(gateColor))
                        }
                    }
                }
            }
        }
    }

    private func drawRuler(_ ctx: inout GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: rulerHeight)),
                 with: .color(Color(NSColor.windowBackgroundColor)))

        let (major, minor) = tickIntervals()
        let pxPerFrame     = CGFloat(zoom)
        let firstTick      = (Int(CGFloat(hOffset) / pxPerFrame) / minor) * minor
        let lastFrame      = Int((CGFloat(hOffset) + size.width) / pxPerFrame) + major

        var f = firstTick
        while f <= lastFrame {
            let x = CGFloat(f) * pxPerFrame - CGFloat(hOffset)
            guard x >= 0 && x <= size.width else { f += minor; continue }
            let isMajor = f % major == 0
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: x, y: rulerHeight - (isMajor ? 10 : 5)))
                p.addLine(to: CGPoint(x: x, y: rulerHeight))
            }, with: .color(isMajor ? Color.secondary.opacity(0.6) : Color.secondary.opacity(0.25)),
               lineWidth: 1)
            if isMajor {
                ctx.draw(Text("\(f)").font(.system(size: 8)).foregroundStyle(Color.secondary),
                         at: CGPoint(x: x + 2, y: rulerHeight - 12), anchor: .bottomLeading)
            }
            f += minor
        }
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 0, y: rulerHeight))
            p.addLine(to: CGPoint(x: size.width, y: rulerHeight))
        }, with: .color(Color.secondary.opacity(0.2)), lineWidth: 0.5)
    }

    private func drawKeyframes(_ ctx: inout GraphicsContext, size: CGSize) {
        let pxPerFrame = CGFloat(zoom)
        drawCameraKeyframes(&ctx, size: size)
        var rowY = spriteStartY

        for (si, node) in timelineNodes.enumerated() {
            let sprite = node.sprite
            let midY = rowY + rowHeight / 2
            if let drivers = sprite.animation.drivers {
                for frame in allKeyframeFrames(drivers: drivers) {
                    let x = CGFloat(frame) * pxPerFrame - CGFloat(hOffset)
                    guard x > -6 && x < size.width + 6 else { continue }
                    drawDiamond(&ctx, x: x, y: midY, size: 5,
                                color: Color.accentColor, selected: false, dragging: false)
                }
            }
            for frame in allRendererKeyframeFrames(for: node) {
                let x = CGFloat(frame) * pxPerFrame - CGFloat(hOffset)
                guard x > -6 && x < size.width + 6 else { continue }
                drawDiamond(&ctx, x: x, y: midY, size: 5,
                            color: Color.orange, selected: false, dragging: false)
            }
            rowY += rowHeight

            if expandedSprites.contains(sprite.name) {
                for lane in visibleSpriteLanes(for: node) {
                    let midLaneY = rowY + rowHeight / 2
                    if let drivers = sprite.animation.drivers {
                        for (ki, frame) in lane.keyframeFrames(from: drivers).enumerated() {
                            let hit        = KFHit(spriteListIdx: si, lane: lane, keyframeIdx: ki)
                            let isDragging = kfDragState?.hit == hit
                            let isSelected = selectedItems.contains(.sprite(spriteListIdx: si, lane: lane, keyframeIdx: ki)) && !isDragging
                            let drawFrame  = isDragging ? (kfDragState?.previewFrame ?? frame) : frame
                            let x = CGFloat(drawFrame) * pxPerFrame - CGFloat(hOffset)
                            guard x > -8 && x < size.width + 8 else { continue }
                            drawDiamond(&ctx, x: x, y: midLaneY, size: 4,
                                        color: lane.color, selected: isSelected, dragging: isDragging)
                        }
                    }
                    rowY += rowHeight
                }
                for row in visibleRendererRows(for: node) {
                    let midLaneY = rowY + rowHeight / 2
                    let renderer = renderer(atSet: row.rendererSetIdx, item: row.rendererItemIdx)
                    for (ki, frame) in row.lane.keyframeFrames(from: renderer?.drivers).enumerated() {
                        let hit = RendererKFHit(
                            spriteListIdx: si,
                            rendererSetIdx: row.rendererSetIdx,
                            rendererItemIdx: row.rendererItemIdx,
                            lane: row.lane,
                            keyframeIdx: ki
                        )
                        let isDragging = rendererKFDragState?.hit == hit
                        let isSelected = selectedItems.contains(.renderer(spriteListIdx: si, rendererSetIdx: row.rendererSetIdx, rendererItemIdx: row.rendererItemIdx, lane: row.lane, keyframeIdx: ki)) && !isDragging
                        let drawFrame = isDragging ? (rendererKFDragState?.previewFrame ?? frame) : frame
                        let x = CGFloat(drawFrame) * pxPerFrame - CGFloat(hOffset)
                        guard x > -8 && x < size.width + 8 else { continue }
                        drawDiamond(&ctx, x: x, y: midLaneY, size: 4,
                                    color: row.lane.color, selected: isSelected, dragging: isDragging)
                    }
                    rowY += rowHeight
                }
            }
        }
    }

    private func drawPlayhead(_ ctx: inout GraphicsContext, size: CGSize) {
        let x = CGFloat(currentFrame) * CGFloat(zoom) - CGFloat(hOffset)
        guard x >= 0 && x <= size.width else { return }
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
        }, with: .color(Color.red.opacity(0.75)), lineWidth: 1.5)
        ctx.fill(Path { p in
            p.move(to: CGPoint(x: x - 5, y: 0))
            p.addLine(to: CGPoint(x: x + 5, y: 0))
            p.addLine(to: CGPoint(x: x,     y: 9))
            p.closeSubpath()
        }, with: .color(Color.red.opacity(0.75)))
    }

    private func drawDiamond(_ ctx: inout GraphicsContext,
                              x: CGFloat, y: CGFloat, size: CGFloat,
                              color: Color, selected: Bool, dragging: Bool) {
        let s    = dragging ? size * 1.35 : size
        let path = Path { p in
            p.move(to:    CGPoint(x: x,     y: y - s))
            p.addLine(to: CGPoint(x: x + s, y: y))
            p.addLine(to: CGPoint(x: x,     y: y + s))
            p.addLine(to: CGPoint(x: x - s, y: y))
            p.closeSubpath()
        }
        ctx.fill(path, with: .color(color.opacity(dragging ? 1.0 : 0.8)))
        if selected {
            ctx.stroke(path, with: .color(Color.green), lineWidth: 2.0)
        } else {
            ctx.stroke(path, with: .color(color), lineWidth: dragging ? 1.0 : 0.5)
        }
    }

    private func drawRubberBand(_ ctx: inout GraphicsContext) {
        guard let start = rubberBandStart, let end = rubberBandEnd else { return }
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
        guard rect.width > 2 || rect.height > 2 else { return }
        let path = Path(rect)
        ctx.fill(path, with: .color(Color.accentColor.opacity(0.12)))
        ctx.stroke(path, with: .color(Color.accentColor.opacity(0.75)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    // MARK: - Selection helpers

    private var activeSelectionItems: Set<TimelineSelectionItem> {
        if !selectedItems.isEmpty { return selectedItems }
        if let selectedKF {
            return [.sprite(spriteListIdx: selectedKF.spriteListIdx, lane: selectedKF.lane, keyframeIdx: selectedKF.keyframeIdx)]
        }
        if let selectedRendererKF {
            return [.renderer(spriteListIdx: selectedRendererKF.spriteListIdx,
                              rendererSetIdx: selectedRendererKF.rendererSetIdx,
                              rendererItemIdx: selectedRendererKF.rendererItemIdx,
                              lane: selectedRendererKF.lane,
                              keyframeIdx: selectedRendererKF.keyframeIdx)]
        }
        if let selectedCameraKFHit {
            return [.camera(lane: selectedCameraKFHit.lane, keyframeIdx: selectedCameraKFHit.keyframeIdx)]
        }
        return []
    }

    private var shiftModifierActive: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }

    private var optionModifierActive: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    private func clearTimelineSelection() {
        selectedItems.removeAll()
        selectedKF = nil
        selectedRendererKF = nil
        selectedCameraKFHit = nil
        controller.selectedTimelineKF = nil
        controller.selectedRendererTimelineKF = nil
        controller.selectedCameraKF = nil
    }

    private func selectSpriteKeyframe(_ hit: KFHit, additive: Bool) {
        let item = TimelineSelectionItem.sprite(spriteListIdx: hit.spriteListIdx, lane: hit.lane, keyframeIdx: hit.keyframeIdx)
        updateSelection(with: item, additive: additive)
        selectedRendererKF = nil
        selectedCameraKFHit = nil
        selectedKF = hit
    }

    private func selectRendererKeyframe(_ hit: RendererKFHit, additive: Bool) {
        let item = TimelineSelectionItem.renderer(spriteListIdx: hit.spriteListIdx,
                                                  rendererSetIdx: hit.rendererSetIdx,
                                                  rendererItemIdx: hit.rendererItemIdx,
                                                  lane: hit.lane,
                                                  keyframeIdx: hit.keyframeIdx)
        updateSelection(with: item, additive: additive)
        selectedKF = nil
        selectedCameraKFHit = nil
        selectedRendererKF = hit
    }

    private func selectCameraKeyframe(_ hit: CameraKFSelection, additive: Bool) {
        let item = TimelineSelectionItem.camera(lane: hit.lane, keyframeIdx: hit.keyframeIdx)
        updateSelection(with: item, additive: additive)
        selectedKF = nil
        selectedRendererKF = nil
        selectedCameraKFHit = hit
    }

    private func updateSelection(with item: TimelineSelectionItem, additive: Bool) {
        if additive {
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
        } else {
            selectedItems = [item]
        }
    }

    private func selectSpriteLane(spriteListIdx: Int, lane: DriverLane, additive: Bool) {
        guard let drivers = timelineNodes[safe: spriteListIdx]?.sprite.animation.drivers else { return }
        let items = Set(lane.keyframeFrames(from: drivers).indices.map {
            TimelineSelectionItem.sprite(spriteListIdx: spriteListIdx, lane: lane, keyframeIdx: $0)
        })
        setSelection(items, additive: additive)
        if let first = items.sorted(by: { selectionSort($0, $1) }).first,
           case .sprite(let spriteListIdx, let lane, let keyframeIdx) = first {
            selectedKF = KFHit(spriteListIdx: spriteListIdx, lane: lane, keyframeIdx: keyframeIdx)
        }
    }

    private func selectRendererLane(spriteListIdx: Int, row: RendererTimelineRow, additive: Bool) {
        let frames = row.lane.keyframeFrames(from: renderer(atSet: row.rendererSetIdx, item: row.rendererItemIdx)?.drivers)
        let items = Set(frames.indices.map {
            TimelineSelectionItem.renderer(spriteListIdx: spriteListIdx,
                                           rendererSetIdx: row.rendererSetIdx,
                                           rendererItemIdx: row.rendererItemIdx,
                                           lane: row.lane,
                                           keyframeIdx: $0)
        })
        setSelection(items, additive: additive)
        if let first = items.sorted(by: { selectionSort($0, $1) }).first,
           case .renderer(let spriteListIdx, let rendererSetIdx, let rendererItemIdx, let lane, let keyframeIdx) = first {
            selectedRendererKF = RendererKFHit(spriteListIdx: spriteListIdx, rendererSetIdx: rendererSetIdx,
                                               rendererItemIdx: rendererItemIdx, lane: lane, keyframeIdx: keyframeIdx)
        }
    }

    private func selectCameraLane(_ lane: CameraLane, additive: Bool) {
        let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
        let items = Set(lane.keyframeFrames(from: cam).indices.map {
            TimelineSelectionItem.camera(lane: lane, keyframeIdx: $0)
        })
        setSelection(items, additive: additive)
        if let first = items.sorted(by: { selectionSort($0, $1) }).first,
           case .camera(let lane, let keyframeIdx) = first {
            selectedCameraKFHit = CameraKFSelection(lane: lane, keyframeIdx: keyframeIdx)
        }
    }

    private func setSelection(_ items: Set<TimelineSelectionItem>, additive: Bool) {
        if additive {
            selectedItems.formUnion(items)
        } else {
            selectedItems = items
            selectedKF = nil
            selectedRendererKF = nil
            selectedCameraKFHit = nil
        }
    }

    private func selectKeyframes(in rect: CGRect, additive: Bool) {
        guard rect.width > 2 || rect.height > 2 else {
            if !additive { clearTimelineSelection() }
            return
        }
        let items = Set(keyframeLocations().compactMap { location -> TimelineSelectionItem? in
            rect.contains(location.point) ? location.item : nil
        })
        setSelection(items, additive: additive)
        syncPrimarySelectionFromSet()
    }

    private func syncPrimarySelectionFromSet() {
        guard let first = selectedItems.sorted(by: { selectionSort($0, $1) }).first else {
            selectedKF = nil
            selectedRendererKF = nil
            selectedCameraKFHit = nil
            return
        }
        switch first {
        case .sprite(let spriteListIdx, let lane, let keyframeIdx):
            selectedRendererKF = nil
            selectedCameraKFHit = nil
            selectedKF = KFHit(spriteListIdx: spriteListIdx, lane: lane, keyframeIdx: keyframeIdx)
        case .renderer(let spriteListIdx, let rendererSetIdx, let rendererItemIdx, let lane, let keyframeIdx):
            selectedKF = nil
            selectedCameraKFHit = nil
            selectedRendererKF = RendererKFHit(spriteListIdx: spriteListIdx,
                                               rendererSetIdx: rendererSetIdx,
                                               rendererItemIdx: rendererItemIdx,
                                               lane: lane,
                                               keyframeIdx: keyframeIdx)
        case .camera(let lane, let keyframeIdx):
            selectedKF = nil
            selectedRendererKF = nil
            selectedCameraKFHit = CameraKFSelection(lane: lane, keyframeIdx: keyframeIdx)
        }
        // Seek the playhead to the earliest frame in the selection.
        if let earliest = selectedItems.map({ itemFrame($0) }).min() {
            seekFrame = max(0, min(controller.maxScrubFrames, earliest))
        }
    }

    private func selectionSort(_ lhs: TimelineSelectionItem, _ rhs: TimelineSelectionItem) -> Bool {
        itemFrame(lhs) == itemFrame(rhs) ? itemSortKey(lhs) < itemSortKey(rhs) : itemFrame(lhs) < itemFrame(rhs)
    }

    private func itemSortKey(_ item: TimelineSelectionItem) -> String {
        switch item {
        case .camera(let lane, let keyframeIdx):
            return "0-\(lane.rawValue)-\(keyframeIdx)"
        case .sprite(let spriteListIdx, let lane, let keyframeIdx):
            return "1-\(spriteListIdx)-\(lane.rawValue)-\(keyframeIdx)"
        case .renderer(let spriteListIdx, let rendererSetIdx, let rendererItemIdx, let lane, let keyframeIdx):
            return "2-\(spriteListIdx)-\(rendererSetIdx)-\(rendererItemIdx)-\(lane.rawValue)-\(keyframeIdx)"
        }
    }

    private func deletionSort(_ lhs: TimelineSelectionItem, _ rhs: TimelineSelectionItem) -> Bool {
        switch (lhs, rhs) {
        case let (.sprite(ls, ll, li), .sprite(rs, rl, ri)):
            let left = (ls, ll.rawValue)
            let right = (rs, rl.rawValue)
            return left == right ? li > ri : "\(left)" > "\(right)"
        case let (.renderer(ls, lrs, lri, ll, li), .renderer(rs, rrs, rri, rl, ri)):
            let left = (ls, lrs, lri, ll.rawValue)
            let right = (rs, rrs, rri, rl.rawValue)
            return left == right ? li > ri : "\(left)" > "\(right)"
        case let (.camera(ll, li), .camera(rl, ri)):
            return ll == rl ? li > ri : ll.rawValue > rl.rawValue
        default:
            return itemSortKey(lhs) > itemSortKey(rhs)
        }
    }

    // MARK: - Hit testing

    private func rowInfo(at point: CGPoint) -> RowInfo? {
        var rowY = spriteStartY
        for (i, node) in timelineNodes.enumerated() {
            let sprite = node.sprite
            if point.y >= rowY && point.y < rowY + rowHeight {
                return RowInfo(spriteListIdx: i, lane: nil)
            }
            rowY += rowHeight
            if expandedSprites.contains(sprite.name) {
                for lane in visibleSpriteLanes(for: node) {
                    if point.y >= rowY && point.y < rowY + rowHeight {
                        return RowInfo(spriteListIdx: i, lane: lane)
                    }
                    rowY += rowHeight
                }
                for row in visibleRendererRows(for: node) {
                    if point.y >= rowY && point.y < rowY + rowHeight {
                        return RowInfo(
                            spriteListIdx: i,
                            lane: nil,
                            rendererLane: row.lane,
                            rendererSetIdx: row.rendererSetIdx,
                            rendererItemIdx: row.rendererItemIdx
                        )
                    }
                    rowY += rowHeight
                }
            }
        }
        return nil
    }

    private func hitTest(at point: CGPoint) -> KFHit? {
        guard let row = rowInfo(at: point), let lane = row.lane else { return nil }
        let nodes = timelineNodes
        guard row.spriteListIdx < nodes.count,
              let drivers = nodes[row.spriteListIdx].sprite.animation.drivers else { return nil }

        let clickFrame = Double(point.x + CGFloat(hOffset)) / zoom
        let tolerance  = Double(hitTolerance) / zoom
        let frames     = lane.keyframeFrames(from: drivers)
        guard !frames.isEmpty else { return nil }

        guard let (idx, _) = frames.enumerated()
            .min(by: { abs(Double($0.element) - clickFrame) < abs(Double($1.element) - clickFrame) }),
              abs(Double(frames[idx]) - clickFrame) <= tolerance
        else { return nil }

        return KFHit(spriteListIdx: row.spriteListIdx, lane: lane, keyframeIdx: idx)
    }

    private func rendererHitTest(at point: CGPoint) -> RendererKFHit? {
        guard let row = rowInfo(at: point),
              let lane = row.rendererLane,
              let setIdx = row.rendererSetIdx,
              let itemIdx = row.rendererItemIdx
        else { return nil }
        let clickFrame = Double(point.x + CGFloat(hOffset)) / zoom
        let tolerance  = Double(hitTolerance) / zoom
        let frames = lane.keyframeFrames(from: renderer(atSet: setIdx, item: itemIdx)?.drivers)
        guard !frames.isEmpty else { return nil }
        guard let (idx, _) = frames.enumerated()
            .min(by: { abs(Double($0.element) - clickFrame) < abs(Double($1.element) - clickFrame) }),
              abs(Double(frames[idx]) - clickFrame) <= tolerance
        else { return nil }
        return RendererKFHit(
            spriteListIdx: row.spriteListIdx,
            rendererSetIdx: setIdx,
            rendererItemIdx: itemIdx,
            lane: lane,
            keyframeIdx: idx
        )
    }

    private func storedFrame(_ hit: KFHit) -> Int {
        let frames = hit.lane.keyframeFrames(
            from: timelineNodes[safe: hit.spriteListIdx]?.sprite.animation.drivers ?? .identity
        )
        return frames[safe: hit.keyframeIdx] ?? 0
    }

    private func storedRendererFrame(_ hit: RendererKFHit) -> Int {
        hit.lane.keyframeFrames(from: renderer(atSet: hit.rendererSetIdx, item: hit.rendererItemIdx)?.drivers)[safe: hit.keyframeIdx] ?? 0
    }

    private func itemFrame(_ item: TimelineSelectionItem) -> Int {
        switch item {
        case .sprite(let spriteListIdx, let lane, let keyframeIdx):
            let drivers = timelineNodes[safe: spriteListIdx]?.sprite.animation.drivers ?? .identity
            return lane.keyframeFrames(from: drivers)[safe: keyframeIdx] ?? 0
        case .renderer(_, let rendererSetIdx, let rendererItemIdx, let lane, let keyframeIdx):
            return lane.keyframeFrames(from: renderer(atSet: rendererSetIdx, item: rendererItemIdx)?.drivers)[safe: keyframeIdx] ?? 0
        case .camera(let lane, let keyframeIdx):
            let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
            return lane.keyframeFrames(from: cam)[safe: keyframeIdx] ?? 0
        }
    }

    private func keyframeLocations() -> [(item: TimelineSelectionItem, point: CGPoint)] {
        let pxPerFrame = CGFloat(zoom)
        var result: [(TimelineSelectionItem, CGPoint)] = []
        if cameraExpanded {
            let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
            var rowY = rulerHeight + rowHeight
            for lane in visibleCameraLanes() {
                let midY = rowY + rowHeight / 2
                for (ki, frame) in lane.keyframeFrames(from: cam).enumerated() {
                    result.append((.camera(lane: lane, keyframeIdx: ki),
                                   CGPoint(x: CGFloat(frame) * pxPerFrame - CGFloat(hOffset), y: midY)))
                }
                rowY += rowHeight
            }
        }

        var rowY = spriteStartY
        for (si, node) in timelineNodes.enumerated() {
            rowY += rowHeight
            if expandedSprites.contains(node.sprite.name) {
                for lane in visibleSpriteLanes(for: node) {
                    let midY = rowY + rowHeight / 2
                    if let drivers = node.sprite.animation.drivers {
                        for (ki, frame) in lane.keyframeFrames(from: drivers).enumerated() {
                            result.append((.sprite(spriteListIdx: si, lane: lane, keyframeIdx: ki),
                                           CGPoint(x: CGFloat(frame) * pxPerFrame - CGFloat(hOffset), y: midY)))
                        }
                    }
                    rowY += rowHeight
                }
                for row in visibleRendererRows(for: node) {
                    let midY = rowY + rowHeight / 2
                    for (ki, frame) in row.lane.keyframeFrames(from: renderer(atSet: row.rendererSetIdx, item: row.rendererItemIdx)?.drivers).enumerated() {
                        result.append((.renderer(spriteListIdx: si,
                                                 rendererSetIdx: row.rendererSetIdx,
                                                 rendererItemIdx: row.rendererItemIdx,
                                                 lane: row.lane,
                                                 keyframeIdx: ki),
                                       CGPoint(x: CGFloat(frame) * pxPerFrame - CGFloat(hOffset), y: midY)))
                    }
                    rowY += rowHeight
                }
            }
        }
        return result
    }

    // MARK: - Data mutations

    private func recordTimelineUndoSnapshot() {
        guard let config = controller.projectConfig else { return }
        timelineUndoStack.append(config)
        if timelineUndoStack.count > 50 {
            timelineUndoStack.removeFirst(timelineUndoStack.count - 50)
        }
        timelineRedoStack.removeAll()
    }

    private func undoTimelineChange() {
        guard let previous = timelineUndoStack.popLast(),
              let current = controller.projectConfig else { return }
        timelineRedoStack.append(current)
        clearTimelineSelection()
        controller.updateProjectConfig { cfg in cfg = previous }
    }

    private func redoTimelineChange() {
        guard let next = timelineRedoStack.popLast(),
              let current = controller.projectConfig else { return }
        timelineUndoStack.append(current)
        clearTimelineSelection()
        controller.updateProjectConfig { cfg in cfg = next }
    }

    private func copySelectedKeyframes() {
        let items = activeSelectionItems.sorted(by: { selectionSort($0, $1) })
        guard let baseFrame = items.map(itemFrame).min() else { return }
        copiedItems = items.compactMap { item in
            let frameOffset = itemFrame(item) - baseFrame
            switch item {
            case .sprite(let spriteListIdx, let lane, let keyframeIdx):
                guard let drivers = timelineNodes[safe: spriteListIdx]?.sprite.animation.drivers else { return nil }
                switch lane {
                case .position:
                    guard let value = drivers.position.keyframes[safe: keyframeIdx] else { return nil }
                    return .spriteVector(spriteListIdx: spriteListIdx, lane: lane, offset: frameOffset, value: value)
                case .scale:
                    guard let value = drivers.scale.keyframes[safe: keyframeIdx] else { return nil }
                    return .spriteVector(spriteListIdx: spriteListIdx, lane: lane, offset: frameOffset, value: value)
                case .rotation:
                    guard let value = drivers.rotation.keyframes[safe: keyframeIdx] else { return nil }
                    return .spriteDouble(spriteListIdx: spriteListIdx, lane: lane, offset: frameOffset, value: value)
                case .morph:
                    guard let value = drivers.morph.keyframes[safe: keyframeIdx] else { return nil }
                    return .spriteDouble(spriteListIdx: spriteListIdx, lane: lane, offset: frameOffset, value: value)
                case .opacity:
                    guard let value = drivers.opacity.keyframes[safe: keyframeIdx] else { return nil }
                    return .spriteDouble(spriteListIdx: spriteListIdx, lane: lane, offset: frameOffset, value: value)
                case .shape:
                    guard let value = drivers.shape.keyframes[safe: keyframeIdx] else { return nil }
                    return .spriteDouble(spriteListIdx: spriteListIdx, lane: lane, offset: frameOffset, value: value)
                }

            case .renderer(let spriteListIdx, let rendererSetIdx, let rendererItemIdx, let lane, let keyframeIdx):
                guard let drivers = renderer(atSet: rendererSetIdx, item: rendererItemIdx)?.drivers else { return nil }
                switch lane {
                case .fillColor:
                    guard let value = drivers.fillColor?.keyframes[safe: keyframeIdx] else { return nil }
                    return .rendererColor(spriteListIdx: spriteListIdx, rendererSetIdx: rendererSetIdx, rendererItemIdx: rendererItemIdx, lane: lane, offset: frameOffset, value: value)
                case .strokeColor:
                    guard let value = drivers.strokeColor?.keyframes[safe: keyframeIdx] else { return nil }
                    return .rendererColor(spriteListIdx: spriteListIdx, rendererSetIdx: rendererSetIdx, rendererItemIdx: rendererItemIdx, lane: lane, offset: frameOffset, value: value)
                case .strokeWidth:
                    guard let value = drivers.strokeWidth.keyframes[safe: keyframeIdx] else { return nil }
                    return .rendererDouble(spriteListIdx: spriteListIdx, rendererSetIdx: rendererSetIdx, rendererItemIdx: rendererItemIdx, lane: lane, offset: frameOffset, value: value)
                case .opacity:
                    guard let value = drivers.opacity.keyframes[safe: keyframeIdx] else { return nil }
                    return .rendererDouble(spriteListIdx: spriteListIdx, rendererSetIdx: rendererSetIdx, rendererItemIdx: rendererItemIdx, lane: lane, offset: frameOffset, value: value)
                }

            case .camera(let lane, let keyframeIdx):
                let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
                switch lane {
                case .tracking:
                    guard let value = cam.tracking.keyframes[safe: keyframeIdx] else { return nil }
                    return .cameraVector(lane: lane, offset: frameOffset, value: value)
                case .pan:
                    guard let value = cam.pan.keyframes[safe: keyframeIdx] else { return nil }
                    return .cameraVector(lane: lane, offset: frameOffset, value: value)
                case .zoom:
                    guard let value = cam.zoom.keyframes[safe: keyframeIdx] else { return nil }
                    return .cameraDouble(lane: lane, offset: frameOffset, value: value)
                case .rotation:
                    guard let value = cam.rotation.keyframes[safe: keyframeIdx] else { return nil }
                    return .cameraDouble(lane: lane, offset: frameOffset, value: value)
                }
            }
        }
    }

    private func pasteCopiedKeyframes() {
        guard !copiedItems.isEmpty else { return }
        recordTimelineUndoSnapshot()
        let insertFrame = currentFrame
        controller.updateProjectConfig { cfg in
            for copied in copiedItems {
                let targetFrame = max(0, insertFrame + copied.offset)
                switch copied {
                case .spriteVector(let spriteListIdx, let lane, _, var value):
                    guard let loc = spriteLocation(listIdx: spriteListIdx) else { continue }
                    value.frame = targetFrame
                    withDrivers(in: &cfg, si: loc.setIdx, pi: loc.spriteIdx) { drivers in
                        switch lane {
                        case .position:
                            drivers.position.mode = .keyframe
                            drivers.position.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.position.keyframes.append(value)
                            drivers.position.keyframes.sort { $0.frame < $1.frame }
                        case .scale:
                            drivers.scale.mode = .keyframe
                            drivers.scale.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.scale.keyframes.append(value)
                            drivers.scale.keyframes.sort { $0.frame < $1.frame }
                        default:
                            break
                        }
                    }

                case .spriteDouble(let spriteListIdx, let lane, _, var value):
                    guard let loc = spriteLocation(listIdx: spriteListIdx) else { continue }
                    value.frame = targetFrame
                    withDrivers(in: &cfg, si: loc.setIdx, pi: loc.spriteIdx) { drivers in
                        switch lane {
                        case .rotation:
                            drivers.rotation.mode = .keyframe
                            drivers.rotation.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.rotation.keyframes.append(value)
                            drivers.rotation.keyframes.sort { $0.frame < $1.frame }
                        case .morph:
                            drivers.morph.mode = .keyframe
                            drivers.morph.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.morph.keyframes.append(value)
                            drivers.morph.keyframes.sort { $0.frame < $1.frame }
                        case .opacity:
                            drivers.opacity.mode = .keyframe
                            drivers.opacity.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.opacity.keyframes.append(value)
                            drivers.opacity.keyframes.sort { $0.frame < $1.frame }
                        case .shape:
                            drivers.shape.mode = .keyframe
                            drivers.shape.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.shape.keyframes.append(value)
                            drivers.shape.keyframes.sort { $0.frame < $1.frame }
                        default:
                            break
                        }
                    }

                case .rendererColor(_, let rendererSetIdx, let rendererItemIdx, let lane, _, var value):
                    value.frame = targetFrame
                    withRendererDrivers(in: &cfg, setIdx: rendererSetIdx, itemIdx: rendererItemIdx) { drivers, renderer in
                        switch lane {
                        case .fillColor:
                            if drivers.fillColor == nil { drivers.fillColor = .constant(renderer.fillColor) }
                            drivers.fillColor!.mode = .keyframe
                            drivers.fillColor!.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.fillColor!.keyframes.append(value)
                            drivers.fillColor!.keyframes.sort { $0.frame < $1.frame }
                        case .strokeColor:
                            if drivers.strokeColor == nil { drivers.strokeColor = .constant(renderer.strokeColor) }
                            drivers.strokeColor!.mode = .keyframe
                            drivers.strokeColor!.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.strokeColor!.keyframes.append(value)
                            drivers.strokeColor!.keyframes.sort { $0.frame < $1.frame }
                        default:
                            break
                        }
                    }

                case .rendererDouble(_, let rendererSetIdx, let rendererItemIdx, let lane, _, var value):
                    value.frame = targetFrame
                    withRendererDrivers(in: &cfg, setIdx: rendererSetIdx, itemIdx: rendererItemIdx) { drivers, _ in
                        switch lane {
                        case .strokeWidth:
                            drivers.strokeWidth.mode = .keyframe
                            drivers.strokeWidth.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.strokeWidth.keyframes.append(value)
                            drivers.strokeWidth.keyframes.sort { $0.frame < $1.frame }
                        case .opacity:
                            drivers.opacity.mode = .keyframe
                            drivers.opacity.keyframes.removeAll { $0.frame == targetFrame }
                            drivers.opacity.keyframes.append(value)
                            drivers.opacity.keyframes.sort { $0.frame < $1.frame }
                        case .fillColor, .strokeColor:
                            break
                        }
                    }

                case .cameraVector(let lane, _, var value):
                    value.frame = targetFrame
                    cfg.globalConfig.camera.enabled = true
                    if lane == .tracking {
                        cfg.globalConfig.camera.tracking.mode = .keyframe
                        cfg.globalConfig.camera.tracking.keyframes.removeAll { $0.frame == targetFrame }
                        cfg.globalConfig.camera.tracking.keyframes.append(value)
                        cfg.globalConfig.camera.tracking.keyframes.sort { $0.frame < $1.frame }
                    } else if lane == .pan {
                        cfg.globalConfig.camera.pan.mode = .keyframe
                        cfg.globalConfig.camera.pan.keyframes.removeAll { $0.frame == targetFrame }
                        cfg.globalConfig.camera.pan.keyframes.append(value)
                        cfg.globalConfig.camera.pan.keyframes.sort { $0.frame < $1.frame }
                    }

                case .cameraDouble(let lane, _, var value):
                    value.frame = targetFrame
                    cfg.globalConfig.camera.enabled = true
                    switch lane {
                    case .zoom:
                        cfg.globalConfig.camera.zoom.mode = .keyframe
                        cfg.globalConfig.camera.zoom.keyframes.removeAll { $0.frame == targetFrame }
                        cfg.globalConfig.camera.zoom.keyframes.append(value)
                        cfg.globalConfig.camera.zoom.keyframes.sort { $0.frame < $1.frame }
                    case .rotation:
                        cfg.globalConfig.camera.rotation.mode = .keyframe
                        cfg.globalConfig.camera.rotation.keyframes.removeAll { $0.frame == targetFrame }
                        cfg.globalConfig.camera.rotation.keyframes.append(value)
                        cfg.globalConfig.camera.rotation.keyframes.sort { $0.frame < $1.frame }
                    default:
                        break
                    }
                }
            }
        }
        selectPastedKeyframes(insertFrame: insertFrame)
    }

    private func selectPastedKeyframes(insertFrame: Int) {
        var items = Set<TimelineSelectionItem>()
        for copied in copiedItems {
            let targetFrame = max(0, insertFrame + copied.offset)
            switch copied {
            case .spriteVector(let spriteListIdx, let lane, _, _),
                 .spriteDouble(let spriteListIdx, let lane, _, _):
                if let drivers = timelineNodes[safe: spriteListIdx]?.sprite.animation.drivers,
                   let idx = lane.keyframeFrames(from: drivers).firstIndex(of: targetFrame) {
                    items.insert(.sprite(spriteListIdx: spriteListIdx, lane: lane, keyframeIdx: idx))
                }
            case .rendererColor(let spriteListIdx, let rendererSetIdx, let rendererItemIdx, let lane, _, _),
                 .rendererDouble(let spriteListIdx, let rendererSetIdx, let rendererItemIdx, let lane, _, _):
                if let idx = lane.keyframeFrames(from: renderer(atSet: rendererSetIdx, item: rendererItemIdx)?.drivers).firstIndex(of: targetFrame) {
                    items.insert(.renderer(spriteListIdx: spriteListIdx, rendererSetIdx: rendererSetIdx,
                                           rendererItemIdx: rendererItemIdx, lane: lane, keyframeIdx: idx))
                }
            case .cameraVector(let lane, _, _),
                 .cameraDouble(let lane, _, _):
                let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
                if let idx = lane.keyframeFrames(from: cam).firstIndex(of: targetFrame) {
                    items.insert(.camera(lane: lane, keyframeIdx: idx))
                }
            }
        }
        selectedItems = items
        syncPrimarySelectionFromSet()
    }

    private func deleteSelectedKeyframes() {
        let items = activeSelectionItems
        guard !items.isEmpty else { return }
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            for item in items.sorted(by: { deletionSort($0, $1) }) {
                switch item {
                case .sprite(let spriteListIdx, let lane, let keyframeIdx):
                    guard let loc = spriteLocation(listIdx: spriteListIdx) else { continue }
                    withDrivers(in: &cfg, si: loc.setIdx, pi: loc.spriteIdx) { drivers in
                        switch lane {
                        case .position:
                            if keyframeIdx < drivers.position.keyframes.count { drivers.position.keyframes.remove(at: keyframeIdx) }
                        case .scale:
                            if keyframeIdx < drivers.scale.keyframes.count { drivers.scale.keyframes.remove(at: keyframeIdx) }
                        case .rotation:
                            if keyframeIdx < drivers.rotation.keyframes.count { drivers.rotation.keyframes.remove(at: keyframeIdx) }
                        case .morph:
                            if keyframeIdx < drivers.morph.keyframes.count { drivers.morph.keyframes.remove(at: keyframeIdx) }
                        case .opacity:
                            if keyframeIdx < drivers.opacity.keyframes.count { drivers.opacity.keyframes.remove(at: keyframeIdx) }
                        case .shape:
                            if keyframeIdx < drivers.shape.keyframes.count { drivers.shape.keyframes.remove(at: keyframeIdx) }
                        }
                    }
                case .renderer(_, let rendererSetIdx, let rendererItemIdx, let lane, let keyframeIdx):
                    withRendererDrivers(in: &cfg, setIdx: rendererSetIdx, itemIdx: rendererItemIdx) { drivers, _ in
                        switch lane {
                        case .fillColor:
                            if keyframeIdx < (drivers.fillColor?.keyframes.count ?? 0) { drivers.fillColor!.keyframes.remove(at: keyframeIdx) }
                        case .strokeColor:
                            if keyframeIdx < (drivers.strokeColor?.keyframes.count ?? 0) { drivers.strokeColor!.keyframes.remove(at: keyframeIdx) }
                        case .strokeWidth:
                            if keyframeIdx < drivers.strokeWidth.keyframes.count { drivers.strokeWidth.keyframes.remove(at: keyframeIdx) }
                        case .opacity:
                            if keyframeIdx < drivers.opacity.keyframes.count { drivers.opacity.keyframes.remove(at: keyframeIdx) }
                        }
                    }
                case .camera(let lane, let keyframeIdx):
                    switch lane {
                    case .tracking:
                        if keyframeIdx < cfg.globalConfig.camera.tracking.keyframes.count { cfg.globalConfig.camera.tracking.keyframes.remove(at: keyframeIdx) }
                    case .pan:
                        if keyframeIdx < cfg.globalConfig.camera.pan.keyframes.count { cfg.globalConfig.camera.pan.keyframes.remove(at: keyframeIdx) }
                    case .zoom:
                        if keyframeIdx < cfg.globalConfig.camera.zoom.keyframes.count { cfg.globalConfig.camera.zoom.keyframes.remove(at: keyframeIdx) }
                    case .rotation:
                        if keyframeIdx < cfg.globalConfig.camera.rotation.keyframes.count { cfg.globalConfig.camera.rotation.keyframes.remove(at: keyframeIdx) }
                    }
                }
            }
        }
        clearTimelineSelection()
    }

    private func commitDrag(_ state: KFDragState) {
        guard let loc = spriteLocation(listIdx: state.hit.spriteListIdx) else { return }
        let lane     = state.hit.lane
        let kfIdx    = state.hit.keyframeIdx
        let newFrame = state.previewFrame
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            withDrivers(in: &cfg, si: loc.setIdx, pi: loc.spriteIdx) { drivers in
                switch lane {
                case .position:
                    guard kfIdx < drivers.position.keyframes.count else { return }
                    drivers.position.keyframes[kfIdx].frame = newFrame
                    drivers.position.keyframes.sort { $0.frame < $1.frame }
                case .scale:
                    guard kfIdx < drivers.scale.keyframes.count else { return }
                    drivers.scale.keyframes[kfIdx].frame = newFrame
                    drivers.scale.keyframes.sort { $0.frame < $1.frame }
                case .rotation:
                    guard kfIdx < drivers.rotation.keyframes.count else { return }
                    drivers.rotation.keyframes[kfIdx].frame = newFrame
                    drivers.rotation.keyframes.sort { $0.frame < $1.frame }
                case .morph:
                    guard kfIdx < drivers.morph.keyframes.count else { return }
                    drivers.morph.keyframes[kfIdx].frame = newFrame
                    drivers.morph.keyframes.sort { $0.frame < $1.frame }
                case .opacity:
                    guard kfIdx < drivers.opacity.keyframes.count else { return }
                    drivers.opacity.keyframes[kfIdx].frame = newFrame
                    drivers.opacity.keyframes.sort { $0.frame < $1.frame }
                case .shape:
                    guard kfIdx < drivers.shape.keyframes.count else { return }
                    drivers.shape.keyframes[kfIdx].frame = newFrame
                    drivers.shape.keyframes.sort { $0.frame < $1.frame }
                }
            }
        }
        let newIdx = lane.keyframeFrames(
            from: controller.projectConfig?.spriteConfig.library
                .spriteSets[safe: loc.setIdx]?.sprites[safe: loc.spriteIdx]?
                .animation.drivers ?? .identity
        ).firstIndex(of: newFrame)
        selectedKF = newIdx.map { KFHit(spriteListIdx: state.hit.spriteListIdx, lane: lane, keyframeIdx: $0) }
        selectedKF.map { selectSpriteKeyframe($0, additive: false) }
        seekFrame = max(0, min(controller.maxScrubFrames, newFrame))
    }

    private func addKeyframe(spriteListIdx: Int, lane: DriverLane, frame: Int) {
        guard let loc = spriteLocation(listIdx: spriteListIdx) else { return }
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            // Auto-initialize drivers if this sprite has none yet (mirrors camera behaviour)
            if cfg.spriteConfig.library.spriteSets[safe: loc.setIdx]?
                  .sprites[safe: loc.spriteIdx]?.animation.drivers == nil {
                cfg.spriteConfig.library.spriteSets[loc.setIdx].sprites[loc.spriteIdx].animation.drivers = .identity
            }
            withDrivers(in: &cfg, si: loc.setIdx, pi: loc.spriteIdx) { drivers in
                switch lane {
                case .position:
                    drivers.position.mode = .keyframe
                    drivers.position.enabled = true
                    let v = interpolateVector(drivers.position.keyframes, at: frame, neutral: .zero)
                    drivers.position.keyframes.append(VectorKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.position.keyframes.sort { $0.frame < $1.frame }
                case .scale:
                    drivers.scale.mode = .keyframe
                    drivers.scale.enabled = true
                    let v = interpolateVector(drivers.scale.keyframes, at: frame, neutral: Vector2D(x: 1, y: 1))
                    drivers.scale.keyframes.append(VectorKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.scale.keyframes.sort { $0.frame < $1.frame }
                case .rotation:
                    drivers.rotation.mode = .keyframe
                    drivers.rotation.enabled = true
                    let v = interpolateDouble(drivers.rotation.keyframes, at: frame, neutral: 0)
                    drivers.rotation.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.rotation.keyframes.sort { $0.frame < $1.frame }
                case .morph:
                    drivers.morph.mode = .keyframe
                    drivers.morph.enabled = true
                    let v = interpolateDouble(drivers.morph.keyframes, at: frame, neutral: 0)
                    drivers.morph.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.morph.keyframes.sort { $0.frame < $1.frame }
                case .opacity:
                    drivers.opacity.mode = .keyframe
                    drivers.opacity.enabled = true
                    let v = interpolateDouble(drivers.opacity.keyframes, at: frame, neutral: 1)
                    drivers.opacity.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.opacity.keyframes.sort { $0.frame < $1.frame }
                case .shape:
                    drivers.shape.mode = .keyframe
                    drivers.shape.enabled = true
                    let v = interpolateDouble(drivers.shape.keyframes, at: frame, neutral: 0)
                    drivers.shape.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.shape.keyframes.sort { $0.frame < $1.frame }
                }
            }
        }
        let newIdx = lane.keyframeFrames(
            from: controller.projectConfig?.spriteConfig.library
                .spriteSets[safe: loc.setIdx]?.sprites[safe: loc.spriteIdx]?
                .animation.drivers ?? .identity
        ).firstIndex(of: frame)
        selectedKF = newIdx.map { KFHit(spriteListIdx: spriteListIdx, lane: lane, keyframeIdx: $0) }
        selectedKF.map { selectSpriteKeyframe($0, additive: false) }
    }

    private func commitRendererDrag(_ state: RendererKFDragState) {
        let hit = state.hit
        let newFrame = state.previewFrame
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            withRendererDrivers(in: &cfg, setIdx: hit.rendererSetIdx, itemIdx: hit.rendererItemIdx) { drivers, _ in
                switch hit.lane {
                case .fillColor:
                    guard hit.keyframeIdx < (drivers.fillColor?.keyframes.count ?? 0) else { return }
                    drivers.fillColor!.keyframes[hit.keyframeIdx].frame = newFrame
                    drivers.fillColor!.keyframes.sort { $0.frame < $1.frame }
                case .strokeColor:
                    guard hit.keyframeIdx < (drivers.strokeColor?.keyframes.count ?? 0) else { return }
                    drivers.strokeColor!.keyframes[hit.keyframeIdx].frame = newFrame
                    drivers.strokeColor!.keyframes.sort { $0.frame < $1.frame }
                case .strokeWidth:
                    guard hit.keyframeIdx < drivers.strokeWidth.keyframes.count else { return }
                    drivers.strokeWidth.keyframes[hit.keyframeIdx].frame = newFrame
                    drivers.strokeWidth.keyframes.sort { $0.frame < $1.frame }
                case .opacity:
                    guard hit.keyframeIdx < drivers.opacity.keyframes.count else { return }
                    drivers.opacity.keyframes[hit.keyframeIdx].frame = newFrame
                    drivers.opacity.keyframes.sort { $0.frame < $1.frame }
                }
            }
        }
        let frames = hit.lane.keyframeFrames(from: renderer(atSet: hit.rendererSetIdx, item: hit.rendererItemIdx)?.drivers)
        selectedRendererKF = frames.firstIndex(of: newFrame).map {
            RendererKFHit(spriteListIdx: hit.spriteListIdx, rendererSetIdx: hit.rendererSetIdx,
                          rendererItemIdx: hit.rendererItemIdx, lane: hit.lane, keyframeIdx: $0)
        }
        selectedRendererKF.map { selectRendererKeyframe($0, additive: false) }
        seekFrame = max(0, min(controller.maxScrubFrames, newFrame))
    }

    private func addRendererKeyframe(spriteListIdx: Int,
                                     setIdx: Int,
                                     itemIdx: Int,
                                     lane: RendererTimelineLane,
                                     frame: Int) {
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            withRendererDrivers(in: &cfg, setIdx: setIdx, itemIdx: itemIdx) { drivers, renderer in
                switch lane {
                case .fillColor:
                    if drivers.fillColor == nil { drivers.fillColor = ColorDriver.constant(renderer.fillColor) }
                    let value = interpolateColor(drivers.fillColor?.keyframes ?? [], at: frame, neutral: renderer.fillColor)
                    drivers.fillColor!.mode = .keyframe
                    drivers.fillColor!.enabled = true
                    drivers.fillColor!.keyframes.append(ColorKeyframe(frame: frame, value: value, easing: .linear))
                    drivers.fillColor!.keyframes.sort { $0.frame < $1.frame }
                case .strokeColor:
                    if drivers.strokeColor == nil { drivers.strokeColor = ColorDriver.constant(renderer.strokeColor) }
                    let value = interpolateColor(drivers.strokeColor?.keyframes ?? [], at: frame, neutral: renderer.strokeColor)
                    drivers.strokeColor!.mode = .keyframe
                    drivers.strokeColor!.enabled = true
                    drivers.strokeColor!.keyframes.append(ColorKeyframe(frame: frame, value: value, easing: .linear))
                    drivers.strokeColor!.keyframes.sort { $0.frame < $1.frame }
                case .strokeWidth:
                    let value = interpolateDouble(drivers.strokeWidth.keyframes, at: frame, neutral: renderer.strokeWidth)
                    drivers.strokeWidth.mode = .keyframe
                    drivers.strokeWidth.enabled = true
                    drivers.strokeWidth.keyframes.append(DoubleKeyframe(frame: frame, value: value, easing: .linear))
                    drivers.strokeWidth.keyframes.sort { $0.frame < $1.frame }
                case .opacity:
                    let value = interpolateDouble(drivers.opacity.keyframes, at: frame, neutral: 1)
                    drivers.opacity.mode = .keyframe
                    drivers.opacity.enabled = true
                    drivers.opacity.keyframes.append(DoubleKeyframe(frame: frame, value: value, easing: .linear))
                    drivers.opacity.keyframes.sort { $0.frame < $1.frame }
                }
            }
        }
        let frames = lane.keyframeFrames(from: renderer(atSet: setIdx, item: itemIdx)?.drivers)
        selectedRendererKF = frames.firstIndex(of: frame).map {
            RendererKFHit(spriteListIdx: spriteListIdx, rendererSetIdx: setIdx,
                          rendererItemIdx: itemIdx, lane: lane, keyframeIdx: $0)
        }
        selectedRendererKF.map { selectRendererKeyframe($0, additive: false) }
    }

    private func deleteRendererKeyframe(hit: RendererKFHit) {
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            withRendererDrivers(in: &cfg, setIdx: hit.rendererSetIdx, itemIdx: hit.rendererItemIdx) { drivers, _ in
                switch hit.lane {
                case .fillColor:
                    guard hit.keyframeIdx < (drivers.fillColor?.keyframes.count ?? 0) else { return }
                    drivers.fillColor!.keyframes.remove(at: hit.keyframeIdx)
                case .strokeColor:
                    guard hit.keyframeIdx < (drivers.strokeColor?.keyframes.count ?? 0) else { return }
                    drivers.strokeColor!.keyframes.remove(at: hit.keyframeIdx)
                case .strokeWidth:
                    guard hit.keyframeIdx < drivers.strokeWidth.keyframes.count else { return }
                    drivers.strokeWidth.keyframes.remove(at: hit.keyframeIdx)
                case .opacity:
                    guard hit.keyframeIdx < drivers.opacity.keyframes.count else { return }
                    drivers.opacity.keyframes.remove(at: hit.keyframeIdx)
                }
            }
        }
        selectedRendererKF = nil
    }

    private func deleteKeyframe(hit: KFHit) {
        guard let loc = spriteLocation(listIdx: hit.spriteListIdx) else { return }
        let lane = hit.lane; let kfIdx = hit.keyframeIdx
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            withDrivers(in: &cfg, si: loc.setIdx, pi: loc.spriteIdx) { drivers in
                switch lane {
                case .position:
                    guard kfIdx < drivers.position.keyframes.count else { return }
                    drivers.position.keyframes.remove(at: kfIdx)
                case .scale:
                    guard kfIdx < drivers.scale.keyframes.count else { return }
                    drivers.scale.keyframes.remove(at: kfIdx)
                case .rotation:
                    guard kfIdx < drivers.rotation.keyframes.count else { return }
                    drivers.rotation.keyframes.remove(at: kfIdx)
                case .morph:
                    guard kfIdx < drivers.morph.keyframes.count else { return }
                    drivers.morph.keyframes.remove(at: kfIdx)
                case .opacity:
                    guard kfIdx < drivers.opacity.keyframes.count else { return }
                    drivers.opacity.keyframes.remove(at: kfIdx)
                case .shape:
                    guard kfIdx < drivers.shape.keyframes.count else { return }
                    drivers.shape.keyframes.remove(at: kfIdx)
                }
            }
        }
        selectedKF = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)

        if cmd && key == "z" {
            if shift { redoTimelineChange() }
            else { undoTimelineChange() }
            return true
        }
        if cmd && key == "c" {
            copySelectedKeyframes()
            return true
        }
        if cmd && key == "v" {
            pasteCopiedKeyframes()
            return true
        }
        if !cmd && (event.keyCode == 51 || event.keyCode == 117) {
            deleteSelectedKeyframes()
            return true
        }
        return false
    }

    // MARK: - Interpolation helpers

    private func interpolateDouble(_ kfs: [DoubleKeyframe], at frame: Int, neutral: Double) -> Double {
        guard !kfs.isEmpty else { return neutral }
        let s = kfs.sorted { $0.frame < $1.frame }
        if frame <= s.first!.frame { return s.first!.value }
        if frame >= s.last!.frame  { return s.last!.value }
        let before = s.last  { $0.frame <= frame }!
        let after  = s.first { $0.frame >  frame }!
        let t = Double(frame - before.frame) / Double(after.frame - before.frame)
        return before.value + t * (after.value - before.value)
    }

    private func interpolateVector(_ kfs: [VectorKeyframe], at frame: Int, neutral: Vector2D) -> Vector2D {
        guard !kfs.isEmpty else { return neutral }
        let s = kfs.sorted { $0.frame < $1.frame }
        if frame <= s.first!.frame { return s.first!.value }
        if frame >= s.last!.frame  { return s.last!.value }
        let before = s.last  { $0.frame <= frame }!
        let after  = s.first { $0.frame >  frame }!
        let t = Double(frame - before.frame) / Double(after.frame - before.frame)
        return Vector2D(x: before.value.x + t * (after.value.x - before.value.x),
                        y: before.value.y + t * (after.value.y - before.value.y))
    }

    private func interpolateColor(_ kfs: [ColorKeyframe], at frame: Int, neutral: LoomColor) -> LoomColor {
        guard !kfs.isEmpty else { return neutral }
        let s = kfs.sorted { $0.frame < $1.frame }
        if frame <= s.first!.frame { return s.first!.value }
        if frame >= s.last!.frame { return s.last!.value }
        let before = s.last { $0.frame <= frame }!
        let after = s.first { $0.frame > frame }!
        let t = Double(frame - before.frame) / Double(after.frame - before.frame)
        func lerp(_ a: Int, _ b: Int) -> Int {
            Int((Double(a) + (Double(b) - Double(a)) * t).rounded())
        }
        return LoomColor(
            r: lerp(before.value.r, after.value.r),
            g: lerp(before.value.g, after.value.g),
            b: lerp(before.value.b, after.value.b),
            a: lerp(before.value.a, after.value.a)
        )
    }

    private func spriteLocation(listIdx: Int) -> (setIdx: Int, spriteIdx: Int)? {
        guard let node = timelineNodes[safe: listIdx] else { return nil }
        return (node.setIdx, node.spriteIdx)
    }

    // MARK: - Camera helpers

    private func isCameraArea(_ point: CGPoint) -> Bool {
        point.y >= rulerHeight && point.y < rulerHeight + CGFloat(cameraRowCount) * rowHeight
    }

    private func cameraLaneAt(_ point: CGPoint) -> CameraLane? {
        guard cameraExpanded else { return nil }
        var rowY = rulerHeight + rowHeight
        for lane in visibleCameraLanes() {
            if point.y >= rowY && point.y < rowY + rowHeight { return lane }
            rowY += rowHeight
        }
        return nil
    }

    private func cameraHitTest(at point: CGPoint) -> CameraKFSelection? {
        guard let lane = cameraLaneAt(point),
              let cam  = controller.projectConfig?.globalConfig.camera else { return nil }
        let clickFrame = Double(point.x + CGFloat(hOffset)) / zoom
        let tolerance  = Double(hitTolerance) / zoom
        let frames     = lane.keyframeFrames(from: cam)
        guard !frames.isEmpty,
              let (idx, _) = frames.enumerated()
                .min(by: { abs(Double($0.element) - clickFrame) < abs(Double($1.element) - clickFrame) }),
              abs(Double(frames[idx]) - clickFrame) <= tolerance
        else { return nil }
        return CameraKFSelection(lane: lane, keyframeIdx: idx)
    }

    private func storedCameraFrame(_ hit: CameraKFSelection) -> Int {
        let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
        return hit.lane.keyframeFrames(from: cam)[safe: hit.keyframeIdx] ?? 0
    }

    private func addCameraKeyframe(lane: CameraLane, frame: Int) {
        controller.selectedSpriteID = nil
        selectedKF = nil
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            cfg.globalConfig.camera.enabled = true
            switch lane {
            case .tracking:
                let v = interpolateVector(cfg.globalConfig.camera.tracking.keyframes, at: frame, neutral: .zero)
                cfg.globalConfig.camera.tracking.mode = .keyframe
                cfg.globalConfig.camera.tracking.enabled = true
                cfg.globalConfig.camera.tracking.keyframes.append(VectorKeyframe(frame: frame, value: v, easing: .linear))
                cfg.globalConfig.camera.tracking.keyframes.sort { $0.frame < $1.frame }
            case .pan:
                let v = interpolateVector(cfg.globalConfig.camera.pan.keyframes, at: frame, neutral: .zero)
                cfg.globalConfig.camera.pan.mode = .keyframe
                cfg.globalConfig.camera.pan.enabled = true
                cfg.globalConfig.camera.pan.keyframes.append(VectorKeyframe(frame: frame, value: v, easing: .linear))
                cfg.globalConfig.camera.pan.keyframes.sort { $0.frame < $1.frame }
            case .zoom:
                let v = interpolateDouble(cfg.globalConfig.camera.zoom.keyframes, at: frame, neutral: 1.0)
                cfg.globalConfig.camera.zoom.mode = .keyframe
                cfg.globalConfig.camera.zoom.enabled = true
                cfg.globalConfig.camera.zoom.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                cfg.globalConfig.camera.zoom.keyframes.sort { $0.frame < $1.frame }
            case .rotation:
                let v = interpolateDouble(cfg.globalConfig.camera.rotation.keyframes, at: frame, neutral: 0.0)
                cfg.globalConfig.camera.rotation.mode = .keyframe
                cfg.globalConfig.camera.rotation.enabled = true
                cfg.globalConfig.camera.rotation.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                cfg.globalConfig.camera.rotation.keyframes.sort { $0.frame < $1.frame }
            }
        }
        let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
        if let idx = lane.keyframeFrames(from: cam).firstIndex(of: frame) {
            selectedCameraKFHit = CameraKFSelection(lane: lane, keyframeIdx: idx)
            selectCameraKeyframe(CameraKFSelection(lane: lane, keyframeIdx: idx), additive: false)
        }
    }

    private func deleteCameraKeyframe(hit: CameraKFSelection) {
        let kfIdx = hit.keyframeIdx
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            switch hit.lane {
            case .tracking:
                guard kfIdx < cfg.globalConfig.camera.tracking.keyframes.count else { return }
                cfg.globalConfig.camera.tracking.keyframes.remove(at: kfIdx)
                if cfg.globalConfig.camera.tracking.keyframes.isEmpty {
                    cfg.globalConfig.camera.tracking = .zero
                }
            case .pan:
                guard kfIdx < cfg.globalConfig.camera.pan.keyframes.count else { return }
                cfg.globalConfig.camera.pan.keyframes.remove(at: kfIdx)
                if cfg.globalConfig.camera.pan.keyframes.isEmpty {
                    cfg.globalConfig.camera.pan = .zero
                }
            case .zoom:
                guard kfIdx < cfg.globalConfig.camera.zoom.keyframes.count else { return }
                cfg.globalConfig.camera.zoom.keyframes.remove(at: kfIdx)
                if cfg.globalConfig.camera.zoom.keyframes.isEmpty {
                    cfg.globalConfig.camera.zoom = .constant(1.0)
                }
            case .rotation:
                guard kfIdx < cfg.globalConfig.camera.rotation.keyframes.count else { return }
                cfg.globalConfig.camera.rotation.keyframes.remove(at: kfIdx)
                if cfg.globalConfig.camera.rotation.keyframes.isEmpty {
                    cfg.globalConfig.camera.rotation = .zero
                }
            }
            let cam = cfg.globalConfig.camera
            if cam.tracking.keyframes.isEmpty && cam.pan.keyframes.isEmpty && cam.zoom.keyframes.isEmpty && cam.rotation.keyframes.isEmpty {
                cfg.globalConfig.camera.enabled = false
            }
        }
        selectedCameraKFHit = nil
    }

    private func commitCameraDrag(_ state: (lane: CameraLane, kfIdx: Int, previewFrame: Int)) {
        let (lane, kfIdx, newFrame) = state
        recordTimelineUndoSnapshot()
        controller.updateProjectConfig { cfg in
            switch lane {
            case .tracking:
                guard kfIdx < cfg.globalConfig.camera.tracking.keyframes.count else { return }
                cfg.globalConfig.camera.tracking.keyframes[kfIdx].frame = newFrame
                cfg.globalConfig.camera.tracking.keyframes.sort { $0.frame < $1.frame }
            case .pan:
                guard kfIdx < cfg.globalConfig.camera.pan.keyframes.count else { return }
                cfg.globalConfig.camera.pan.keyframes[kfIdx].frame = newFrame
                cfg.globalConfig.camera.pan.keyframes.sort { $0.frame < $1.frame }
            case .zoom:
                guard kfIdx < cfg.globalConfig.camera.zoom.keyframes.count else { return }
                cfg.globalConfig.camera.zoom.keyframes[kfIdx].frame = newFrame
                cfg.globalConfig.camera.zoom.keyframes.sort { $0.frame < $1.frame }
            case .rotation:
                guard kfIdx < cfg.globalConfig.camera.rotation.keyframes.count else { return }
                cfg.globalConfig.camera.rotation.keyframes[kfIdx].frame = newFrame
                cfg.globalConfig.camera.rotation.keyframes.sort { $0.frame < $1.frame }
            }
        }
        let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
        if let idx = lane.keyframeFrames(from: cam).firstIndex(of: newFrame) {
            selectedCameraKFHit = CameraKFSelection(lane: lane, keyframeIdx: idx)
            selectCameraKeyframe(CameraKFSelection(lane: lane, keyframeIdx: idx), additive: false)
        }
        seekFrame = max(0, min(controller.maxScrubFrames, newFrame))
    }

    private func drawCameraKeyframes(_ ctx: inout GraphicsContext, size: CGSize) {
        guard let cam = controller.projectConfig?.globalConfig.camera else { return }
        let pxPerFrame = CGFloat(zoom)

        // Summary row: union of all lane frames
        let summaryMidY = rulerHeight + rowHeight / 2
        let allFrames   = Array(Set(CameraLane.allCases.flatMap { $0.keyframeFrames(from: cam) })).sorted()
        for frame in allFrames {
            let x = CGFloat(frame) * pxPerFrame - CGFloat(hOffset)
            guard x > -6 && x < size.width + 6 else { continue }
            drawDiamond(&ctx, x: x, y: summaryMidY, size: 5,
                        color: Color.teal, selected: false, dragging: false)
        }

        guard cameraExpanded else { return }
        var rowY = rulerHeight + rowHeight
        for lane in visibleCameraLanes() {
            let midY = rowY + rowHeight / 2
            for (ki, frame) in lane.keyframeFrames(from: cam).enumerated() {
                let isDragging = cameraDragState.map { $0.lane == lane && $0.kfIdx == ki } ?? false
                let isSelected = !isDragging && selectedItems.contains(.camera(lane: lane, keyframeIdx: ki))
                let drawFrame  = isDragging ? (cameraDragState?.previewFrame ?? frame) : frame
                let x = CGFloat(drawFrame) * pxPerFrame - CGFloat(hOffset)
                guard x > -8 && x < size.width + 8 else { continue }
                drawDiamond(&ctx, x: x, y: midY, size: 4,
                            color: lane.color, selected: isSelected, dragging: isDragging)
            }
            rowY += rowHeight
        }
    }

    // MARK: - Canvas helpers

    private func tickIntervals() -> (major: Int, minor: Int) {
        let pairs: [(major: Int, minor: Int)] = [
            (1, 1), (2, 1), (5, 1), (10, 2), (20, 5),
            (50, 10), (100, 20), (200, 50), (500, 100), (1000, 200)
        ]
        return pairs.first { Double($0.major) * zoom >= 60 } ?? (1000, 200)
    }

    private func allKeyframeFrames(drivers: TransformDrivers) -> [Int] {
        var frames = Set<Int>()
        drivers.position.keyframes.forEach { frames.insert($0.frame) }
        drivers.scale.keyframes.forEach    { frames.insert($0.frame) }
        drivers.rotation.keyframes.forEach { frames.insert($0.frame) }
        drivers.morph.keyframes.forEach    { frames.insert($0.frame) }
        drivers.opacity.keyframes.forEach  { frames.insert($0.frame) }
        drivers.shape.keyframes.forEach    { frames.insert($0.frame) }
        return frames.sorted()
    }

    private func allRendererKeyframeFrames(for node: TimelineNode) -> [Int] {
        var frames = Set<Int>()
        for row in rendererRows(for: node) {
            row.lane.keyframeFrames(from: renderer(atSet: row.rendererSetIdx, item: row.rendererItemIdx)?.drivers)
                .forEach { frames.insert($0) }
        }
        return frames.sorted()
    }

    private func hasTimelineRows(for node: TimelineNode) -> Bool {
        node.sprite.animation.drivers != nil || !rendererRows(for: node).isEmpty
    }

    private func rendererRows(for node: TimelineNode) -> [RendererTimelineRow] {
        guard let setIdx = rendererSetIndex(named: node.sprite.rendererSetName),
              let renderers = controller.projectConfig?.renderingConfig.library.rendererSets[safe: setIdx]?.renderers
        else { return [] }
        var rows: [RendererTimelineRow] = []
        for (itemIdx, renderer) in renderers.enumerated() {
            guard renderer.enabled else { continue }
            for lane in RendererTimelineLane.allCases {
                rows.append(RendererTimelineRow(
                    rendererSetIdx: setIdx,
                    rendererItemIdx: itemIdx,
                    rendererName: renderer.name.isEmpty ? "Renderer \(itemIdx + 1)" : renderer.name,
                    lane: lane
                ))
            }
        }
        return rows
    }

    private func rendererSetIndex(named name: String) -> Int? {
        controller.projectConfig?.renderingConfig.library.rendererSets.firstIndex { $0.name == name }
    }

    private func renderer(atSet setIdx: Int, item itemIdx: Int) -> Renderer? {
        controller.projectConfig?.renderingConfig.library.rendererSets[safe: setIdx]?.renderers[safe: itemIdx]
    }

    // MARK: - Lane visibility helpers

    private func spriteLaneID(spriteName: String, lane: DriverLane) -> String {
        "s:\(spriteName):\(lane.rawValue)"
    }
    private func rendererLaneID(_ row: RendererTimelineRow) -> String {
        "r:\(row.rendererSetIdx):\(row.rendererItemIdx):\(row.lane.rawValue)"
    }
    private func cameraLaneID(_ lane: CameraLane) -> String {
        "c:\(lane.rawValue)"
    }
    private func visibleSpriteLanes(for node: TimelineNode) -> [DriverLane] {
        DriverLane.allCases.filter { !hiddenLanes.contains(spriteLaneID(spriteName: node.sprite.name, lane: $0)) }
    }
    private func visibleRendererRows(for node: TimelineNode) -> [RendererTimelineRow] {
        rendererRows(for: node).filter { !hiddenLanes.contains(rendererLaneID($0)) }
    }
    private func visibleCameraLanes() -> [CameraLane] {
        CameraLane.allCases.filter { !hiddenLanes.contains(cameraLaneID($0)) }
    }

    private var spriteTimelineRowCount: Int {
        timelineNodes.reduce(0) { count, node in
            var rows = count + 1
            if expandedSprites.contains(node.sprite.name) {
                rows += visibleSpriteLanes(for: node).count
                rows += visibleRendererRows(for: node).count
            }
            return rows
        }
    }

    private var timelineNodes: [TimelineNode] {
        guard let sets = controller.projectConfig?.spriteConfig.library.spriteSets else { return [] }
        var nameToLoc: [String: (Int, Int)] = [:]
        for (si, set) in sets.enumerated() {
            for (pi, sprite) in set.sprites.enumerated() { nameToLoc[sprite.name] = (si, pi) }
        }
        var result:  [TimelineNode] = []
        var visited = Set<String>()
        func visit(si: Int, pi: Int, depth: Int) {
            let sprite = sets[si].sprites[pi]
            guard !visited.contains(sprite.name) else { return }
            visited.insert(sprite.name)
            result.append(TimelineNode(setIdx: si, spriteIdx: pi, sprite: sprite, depth: depth))
            for (csi, cset) in sets.enumerated() {
                for (cpi, child) in cset.sprites.enumerated() {
                    if child.parentName == sprite.name { visit(si: csi, pi: cpi, depth: depth + 1) }
                }
            }
        }
        for (si, set) in sets.enumerated() {
            for (pi, sprite) in set.sprites.enumerated() {
                guard !visited.contains(sprite.name) else { continue }
                let isRoot = sprite.parentName == nil || nameToLoc[sprite.parentName!] == nil
                if isRoot { visit(si: si, pi: pi, depth: 0) }
            }
        }
        for (si, set) in sets.enumerated() {
            for (pi, sprite) in set.sprites.enumerated() {
                if !visited.contains(sprite.name) { visit(si: si, pi: pi, depth: 0) }
            }
        }
        return result
    }
}

private struct TimelineKeyCaptureView: NSViewRepresentable {
    var handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.handle = handle
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.handle = handle
    }

    final class KeyView: NSView {
        var handle: ((NSEvent) -> Bool)?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
        }

        override func keyDown(with event: NSEvent) {
            if handle?(event) == true { return }
            super.keyDown(with: event)
        }
    }
}
