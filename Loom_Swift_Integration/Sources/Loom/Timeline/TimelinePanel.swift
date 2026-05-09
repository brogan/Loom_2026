import AppKit
import SwiftUI
import LoomEngine

// MARK: - File-private aliases / types

private typealias DriverLane = TimelineLane

private struct RowInfo {
    var spriteListIdx: Int
    var lane: DriverLane?   // nil = summary row
}

private struct TimelineNode {
    var setIdx:    Int
    var spriteIdx: Int
    var sprite:    SpriteDef
    var depth:     Int
}

private struct KFHit: Equatable {
    var spriteListIdx: Int
    var lane:          DriverLane
    var keyframeIdx:   Int
}

private struct KFDragState {
    var hit:          KFHit
    var previewFrame: Int
}

private enum DragKind { case none, seek, pan, keyframe, camera }

// MARK: - TimelinePanel

struct TimelinePanel: View {
    @EnvironmentObject private var controller: AppController
    let currentFrame: Int
    @Binding var seekFrame: Int?

    @State private var panelHeight:           CGFloat       = 180
    @State private var zoom:                  Double        = 4.0
    @State private var hOffset:               Double        = 0
    @State private var expandedSprites:       Set<String>   = []
    @State private var prevDragTranslation:   CGFloat       = 0
    @State private var isDragInitialized:     Bool          = false
    @State private var dragKind:              DragKind      = .none
    @State private var wasPlayingBeforeScrub: Bool          = false
    @State private var selectedKF:            KFHit?        = nil
    @State private var kfDragState:           KFDragState?  = nil
    @State private var cameraExpanded:        Bool          = false
    @State private var selectedCameraKFHit:   CameraKFSelection? = nil
    @State private var cameraDragState:       (lane: CameraLane, kfIdx: Int, previewFrame: Int)? = nil

    private let headerWidth:  CGFloat = 160
    private let rowHeight:    CGFloat = 22
    private let rulerHeight:  CGFloat = 20
    private let hitTolerance: CGFloat = 8

    private var cameraRowCount: Int { cameraExpanded ? 1 + CameraLane.allCases.count : 1 }
    private var spriteStartY: CGFloat { rulerHeight + CGFloat(cameraRowCount) * rowHeight }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            HStack(spacing: 0) {
                laneHeaderColumn.frame(width: headerWidth)
                Divider()
                GeometryReader { geo in timelineCanvas(size: geo.size) }
            }
        }
        .frame(height: panelHeight)
        .background(Color(NSColor.controlBackgroundColor))
        .onChange(of: selectedKF) { _, newKF in syncSelection(newKF) }
        .onChange(of: selectedCameraKFHit) { _, hit in controller.selectedCameraKF = hit }
        .onChange(of: controller.selectedSpriteID) { _, id in if id != nil { selectedCameraKFHit = nil } }
        .onChange(of: controller.projectURL) { _, _ in selectedKF = nil; selectedCameraKFHit = nil }
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        ZStack {
            Color(NSColor.separatorColor).frame(height: 1)
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 36, height: 3)
        }
        .frame(height: 8)
        .contentShape(Rectangle())
        .onHover { if $0 { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
        .gesture(DragGesture(minimumDistance: 0).onChanged {
            panelHeight = max(80, min(320, panelHeight - $0.translation.height))
        })
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
                if selectedKF != nil || selectedCameraKFHit != nil {
                    Button {
                        if let hit = selectedKF             { deleteKeyframe(hit: hit) }
                        else if let hit = selectedCameraKFHit { deleteCameraKeyframe(hit: hit) }
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
                } label: {
                    Image(systemName: cameraExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9)).frame(width: 10)
                }
                .buttonStyle(.plain)
                Image(systemName: "camera")
                    .font(.system(size: 9)).foregroundStyle(.teal)
                Text("Camera").font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .frame(height: rowHeight)
            .padding(.leading, 4)
            if cameraExpanded {
                ForEach(CameraLane.allCases, id: \.rawValue) { lane in
                    driverHeaderRow(lane.label, color: lane.color)
                }
            }

            // Sprite block
            ForEach(timelineNodes, id: \.sprite.name) { node in
                spriteHeaderRow(node)
                if expandedSprites.contains(node.sprite.name) {
                    ForEach(DriverLane.allCases, id: \.rawValue) { lane in
                        driverHeaderRow(lane.label, color: lane.color)
                    }
                }
            }
            Spacer()
        }
        .clipped()
    }

    private func spriteHeaderRow(_ node: TimelineNode) -> some View {
        let sprite     = node.sprite
        let expanded   = expandedSprites.contains(sprite.name)
        let hasDrivers = sprite.animation.drivers != nil
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
        }
        .frame(height: rowHeight)
        .padding(.leading, CGFloat(node.depth) * 12 + 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            controller.selectedSpriteID = sprite.name
            selectedKF          = nil
            selectedCameraKFHit = nil
        }
    }

    private func driverHeaderRow(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Color.clear.frame(width: 14)
            Circle().fill(color.opacity(0.5)).frame(width: 5, height: 5)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(height: rowHeight)
        .padding(.leading, 14)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.35))
    }

    // MARK: - Timeline canvas

    private func timelineCanvas(size: CGSize) -> some View {
        Canvas { ctx, sz in
            self.drawBackground(&ctx, size: sz)
            self.drawRuler(&ctx, size: sz)
            self.drawKeyframes(&ctx, size: sz)
            self.drawPlayhead(&ctx, size: sz)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in onDragChanged(v) }
                .onEnded   { v in onDragEnded(v)   }
        )
        .clipped()
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
                    selectedKF                  = nil
                    selectedCameraKFHit         = camHit
                    controller.selectedSpriteID = nil
                    cameraDragState             = (camHit.lane, camHit.keyframeIdx,
                                                  storedCameraFrame(camHit))
                } else {
                    dragKind = .pan
                }
            } else if let hit = hitTest(at: v.startLocation) {
                dragKind            = .keyframe
                selectedCameraKFHit = nil
                selectedKF          = hit
                kfDragState         = KFDragState(hit: hit, previewFrame: storedFrame(hit))
            } else {
                dragKind = .pan
            }
        }

        switch dragKind {
        case .seek:
            let f = Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded())
            seekFrame = max(0, min(controller.maxScrubFrames, f))
        case .keyframe:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            if let s = kfDragState { kfDragState = KFDragState(hit: s.hit, previewFrame: f) }
        case .camera:
            let f = max(0, Int(((v.location.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
            if let s = cameraDragState { cameraDragState = (s.lane, s.kfIdx, f) }
        case .pan:
            let delta           = v.translation.width - prevDragTranslation
            hOffset             = max(0, hOffset - delta)
            prevDragTranslation = v.translation.width
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

        case .camera:
            if !isTap, let state = cameraDragState { commitCameraDrag(state) }
            cameraDragState = nil

        case .pan:
            if isTap {
                let f = max(0, Int(((v.startLocation.x + CGFloat(hOffset)) / CGFloat(zoom)).rounded()))
                if let lane = cameraLaneAt(v.startLocation) {
                    addCameraKeyframe(lane: lane, frame: f)
                } else if let row = rowInfo(at: v.startLocation), let lane = row.lane {
                    addKeyframe(spriteListIdx: row.spriteListIdx, lane: lane, frame: f)
                } else {
                    selectedKF = nil
                    selectedCameraKFHit = nil
                }
            }

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
        controller.selectedTimelineKF = TimelineKFSelection(
            setIdx:      loc.setIdx,
            spriteIdx:   loc.spriteIdx,
            lane:        hit.lane,
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
            for j in 0..<CameraLane.allCases.count {
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
            let laneCount = DriverLane.allCases.count
            if expandedSprites.contains(sprite.name) {
                for j in 0..<laneCount {
                    ctx.fill(
                        Path(CGRect(x: 0, y: rowY, width: size.width, height: rowHeight)),
                        with: .color(j.isMultiple(of: 2)
                            ? Color(NSColor.windowBackgroundColor).opacity(0.5)
                            : Color(NSColor.windowBackgroundColor).opacity(0.35))
                    )
                    rowY += rowHeight
                }
                // Gate overlay: dim inactive regions across all lane rows.
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
            rowY += rowHeight

            if expandedSprites.contains(sprite.name) {
                for lane in DriverLane.allCases {
                    let midLaneY = rowY + rowHeight / 2
                    if let drivers = sprite.animation.drivers {
                        for (ki, frame) in lane.keyframeFrames(from: drivers).enumerated() {
                            let hit        = KFHit(spriteListIdx: si, lane: lane, keyframeIdx: ki)
                            let isDragging = kfDragState?.hit == hit
                            let isSelected = selectedKF == hit && !isDragging
                            let drawFrame  = isDragging ? (kfDragState?.previewFrame ?? frame) : frame
                            let x = CGFloat(drawFrame) * pxPerFrame - CGFloat(hOffset)
                            guard x > -8 && x < size.width + 8 else { continue }
                            drawDiamond(&ctx, x: x, y: midLaneY, size: 4,
                                        color: lane.color, selected: isSelected, dragging: isDragging)
                        }
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
                for lane in DriverLane.allCases {
                    if point.y >= rowY && point.y < rowY + rowHeight {
                        return RowInfo(spriteListIdx: i, lane: lane)
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

    private func storedFrame(_ hit: KFHit) -> Int {
        let frames = hit.lane.keyframeFrames(
            from: timelineNodes[safe: hit.spriteListIdx]?.sprite.animation.drivers ?? .identity
        )
        return frames[safe: hit.keyframeIdx] ?? 0
    }

    // MARK: - Data mutations

    private func commitDrag(_ state: KFDragState) {
        guard let loc = spriteLocation(listIdx: state.hit.spriteListIdx) else { return }
        let lane     = state.hit.lane
        let kfIdx    = state.hit.keyframeIdx
        let newFrame = state.previewFrame
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
    }

    private func addKeyframe(spriteListIdx: Int, lane: DriverLane, frame: Int) {
        guard let loc = spriteLocation(listIdx: spriteListIdx) else { return }
        controller.updateProjectConfig { cfg in
            withDrivers(in: &cfg, si: loc.setIdx, pi: loc.spriteIdx) { drivers in
                switch lane {
                case .position:
                    let v = interpolateVector(drivers.position.keyframes, at: frame, neutral: .zero)
                    drivers.position.keyframes.append(VectorKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.position.keyframes.sort { $0.frame < $1.frame }
                case .scale:
                    let v = interpolateVector(drivers.scale.keyframes, at: frame, neutral: Vector2D(x: 1, y: 1))
                    drivers.scale.keyframes.append(VectorKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.scale.keyframes.sort { $0.frame < $1.frame }
                case .rotation:
                    let v = interpolateDouble(drivers.rotation.keyframes, at: frame, neutral: 0)
                    drivers.rotation.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.rotation.keyframes.sort { $0.frame < $1.frame }
                case .morph:
                    let v = interpolateDouble(drivers.morph.keyframes, at: frame, neutral: 0)
                    drivers.morph.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                    drivers.morph.keyframes.sort { $0.frame < $1.frame }
                case .shape:
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
    }

    private func deleteKeyframe(hit: KFHit) {
        guard let loc = spriteLocation(listIdx: hit.spriteListIdx) else { return }
        let lane = hit.lane; let kfIdx = hit.keyframeIdx
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
                case .shape:
                    guard kfIdx < drivers.shape.keyframes.count else { return }
                    drivers.shape.keyframes.remove(at: kfIdx)
                }
            }
        }
        selectedKF = nil
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
        for lane in CameraLane.allCases {
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
        controller.updateProjectConfig { cfg in
            cfg.globalConfig.camera.enabled = true
            switch lane {
            case .pan:
                let v = interpolateVector(cfg.globalConfig.camera.pan.keyframes, at: frame, neutral: .zero)
                cfg.globalConfig.camera.pan.mode = .keyframe
                cfg.globalConfig.camera.pan.keyframes.append(VectorKeyframe(frame: frame, value: v, easing: .linear))
                cfg.globalConfig.camera.pan.keyframes.sort { $0.frame < $1.frame }
            case .zoom:
                let v = interpolateDouble(cfg.globalConfig.camera.zoom.keyframes, at: frame, neutral: 1.0)
                cfg.globalConfig.camera.zoom.mode = .keyframe
                cfg.globalConfig.camera.zoom.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                cfg.globalConfig.camera.zoom.keyframes.sort { $0.frame < $1.frame }
            case .rotation:
                let v = interpolateDouble(cfg.globalConfig.camera.rotation.keyframes, at: frame, neutral: 0.0)
                cfg.globalConfig.camera.rotation.mode = .keyframe
                cfg.globalConfig.camera.rotation.keyframes.append(DoubleKeyframe(frame: frame, value: v, easing: .linear))
                cfg.globalConfig.camera.rotation.keyframes.sort { $0.frame < $1.frame }
            }
        }
        let cam = controller.projectConfig?.globalConfig.camera ?? .disabled
        if let idx = lane.keyframeFrames(from: cam).firstIndex(of: frame) {
            selectedCameraKFHit = CameraKFSelection(lane: lane, keyframeIdx: idx)
        }
    }

    private func deleteCameraKeyframe(hit: CameraKFSelection) {
        let kfIdx = hit.keyframeIdx
        controller.updateProjectConfig { cfg in
            switch hit.lane {
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
            if cam.pan.keyframes.isEmpty && cam.zoom.keyframes.isEmpty && cam.rotation.keyframes.isEmpty {
                cfg.globalConfig.camera.enabled = false
            }
        }
        selectedCameraKFHit = nil
    }

    private func commitCameraDrag(_ state: (lane: CameraLane, kfIdx: Int, previewFrame: Int)) {
        let (lane, kfIdx, newFrame) = state
        controller.updateProjectConfig { cfg in
            switch lane {
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
        }
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
        for lane in CameraLane.allCases {
            let midY = rowY + rowHeight / 2
            for (ki, frame) in lane.keyframeFrames(from: cam).enumerated() {
                let isDragging = cameraDragState.map { $0.lane == lane && $0.kfIdx == ki } ?? false
                let isSelected = !isDragging && (selectedCameraKFHit.map { $0.lane == lane && $0.keyframeIdx == ki } ?? false)
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
        drivers.shape.keyframes.forEach    { frames.insert($0.frame) }
        return frames.sorted()
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
