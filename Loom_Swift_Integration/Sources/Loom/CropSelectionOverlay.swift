import SwiftUI

/// Draggable, resizable crop-selection rectangle overlaid on the render
/// canvas (2026-07-14) — lets the user mark a sub-region to export via
/// `AppController.saveStillSelection()`, with a live width×height readout in
/// actual output pixels, instead of cropping in a separate app afterward.
///
/// `canvasRect` is the actual rendered-canvas sub-rect within this view's own
/// coordinate space (the caller has already applied any letterboxing/
/// aspect-fit centering) — this view is sized and positioned to exactly match
/// it. All gesture math happens in that same screen-space rect, local to this
/// view; the value actually stored (`cropRect`, bound to
/// `AppController.cropRect`) is normalized to [0, 1] within it, top-left
/// origin, so it stays valid across window resizes between drags.
struct CropSelectionOverlay: View {
    let canvasRect:      CGRect
    let canvasPixelSize: CGSize
    @Binding var cropRect: CGRect?

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    private enum DragMode {
        case creating(CGPoint)
        case moving(original: CGRect, start: CGPoint)
        case resizing(Corner, original: CGRect)
    }

    @State private var dragMode: DragMode? = nil

    private let handleRadius: CGFloat = 5
    private let hitSlop:      CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let rect = screenRect {
                dimmedScrim(around: rect)
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                ForEach(Corner.allCases, id: \.self) { corner in
                    handleView.position(point(for: corner, in: rect))
                }
                sizeLabel(for: rect)
                clearButton(for: rect)
            } else {
                Text("Drag to select a region to export")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .position(x: canvasRect.width / 2, y: canvasRect.height / 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvasRect.width, height: canvasRect.height)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    // MARK: - Screen-space selection rect (nil until a selection exists)

    private var screenRect: CGRect? {
        guard let cropRect else { return nil }
        return CGRect(
            x: cropRect.minX * canvasRect.width,
            y: cropRect.minY * canvasRect.height,
            width: cropRect.width * canvasRect.width,
            height: cropRect.height * canvasRect.height
        )
    }

    private func point(for corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private var handleView: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
            .frame(width: handleRadius * 2, height: handleRadius * 2)
    }

    private func dimmedScrim(around rect: CGRect) -> some View {
        Canvas { ctx, size in
            var path = Path(CGRect(origin: .zero, size: size))
            path.addRect(rect)
            ctx.fill(path, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }

    private func sizeLabel(for rect: CGRect) -> some View {
        let pixelW = Int((rect.width  / canvasRect.width  * canvasPixelSize.width).rounded())
        let pixelH = Int((rect.height / canvasRect.height * canvasPixelSize.height).rounded())
        let labelFitsAbove = rect.minY - 22 >= 0
        return Text("\(pixelW) × \(pixelH) px")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .position(x: rect.midX, y: labelFitsAbove ? rect.minY - 12 : rect.minY + 12)
            .allowsHitTesting(false)
    }

    private func clearButton(for rect: CGRect) -> some View {
        Button { cropRect = nil } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white, Color.black.opacity(0.6))
                .background(Circle().fill(.black.opacity(0.001)))  // generous, reliable hit target
        }
        .buttonStyle(.plain)
        .help("Clear crop selection")
        .position(x: rect.maxX, y: rect.minY)
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = startMode(at: value.startLocation)
                }
                apply(value)
            }
            .onEnded { _ in dragMode = nil }
    }

    private func startMode(at point: CGPoint) -> DragMode {
        if let rect = screenRect {
            for corner in Corner.allCases {
                let handlePoint = self.point(for: corner, in: rect)
                if hypot(handlePoint.x - point.x, handlePoint.y - point.y) <= handleRadius + hitSlop {
                    return .resizing(corner, original: rect)
                }
            }
            if rect.insetBy(dx: -hitSlop, dy: -hitSlop).contains(point) {
                return .moving(original: rect, start: point)
            }
        }
        return .creating(point)
    }

    private func apply(_ value: DragGesture.Value) {
        guard let mode = dragMode else { return }
        let bounds  = CGRect(origin: .zero, size: canvasRect.size)
        let current = clamp(value.location, in: bounds)

        switch mode {
        case .creating(let start):
            let clampedStart = clamp(start, in: bounds)
            setNormalized(CGRect(
                x: min(clampedStart.x, current.x), y: min(clampedStart.y, current.y),
                width: abs(current.x - clampedStart.x), height: abs(current.y - clampedStart.y)
            ))

        case .moving(let original, let start):
            let dx = current.x - start.x, dy = current.y - start.y
            var rect = original.offsetBy(dx: dx, dy: dy)
            if rect.minX < 0 { rect.origin.x = 0 }
            if rect.minY < 0 { rect.origin.y = 0 }
            if rect.maxX > bounds.width  { rect.origin.x = bounds.width  - rect.width }
            if rect.maxY > bounds.height { rect.origin.y = bounds.height - rect.height }
            setNormalized(rect)

        case .resizing(let corner, let original):
            let rect: CGRect
            switch corner {
            case .topLeft:
                rect = CGRect(x: min(current.x, original.maxX), y: min(current.y, original.maxY),
                               width: abs(original.maxX - current.x), height: abs(original.maxY - current.y))
            case .topRight:
                rect = CGRect(x: original.minX, y: min(current.y, original.maxY),
                               width: abs(current.x - original.minX), height: abs(original.maxY - current.y))
            case .bottomLeft:
                rect = CGRect(x: min(current.x, original.maxX), y: original.minY,
                               width: abs(original.maxX - current.x), height: abs(current.y - original.minY))
            case .bottomRight:
                rect = CGRect(x: original.minX, y: original.minY,
                               width: abs(current.x - original.minX), height: abs(current.y - original.minY))
            }
            setNormalized(rect)
        }
    }

    private func clamp(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    private func setNormalized(_ screenSpaceRect: CGRect) {
        guard canvasRect.width > 0, canvasRect.height > 0 else { return }
        cropRect = CGRect(
            x: screenSpaceRect.minX / canvasRect.width,
            y: screenSpaceRect.minY / canvasRect.height,
            width: screenSpaceRect.width / canvasRect.width,
            height: screenSpaceRect.height / canvasRect.height
        )
    }
}
