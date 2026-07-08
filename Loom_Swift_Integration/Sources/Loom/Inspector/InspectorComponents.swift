import SwiftUI

// TextField(value:format:) reverts on every keystroke that doesn't fully parse, making it
// impossible to type negative values (the leading "-" is rejected before you can finish).
// FloatEntryField buffers edits in local state and commits to the model only on Return or focus loss.
//
// onCommit: optional callback fired with the committed value.  After onCommit returns, `text`
// is synchronously reset to formatted(value) so that a subsequent focus-loss commit reads the
// already-updated text rather than the stale pre-commit text — preventing double-application.
struct FloatEntryField: View {
    @Binding var value: Double
    var width: CGFloat
    var fractionDigits: Int = 3
    var fontSize: CGFloat = 12
    var help: String = ""
    var onCommit: ((Double) -> Void)? = nil

    @State private var text = ""
    @State private var isEditing = false  // true only while keystrokes are in-flight; cleared on commit
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.squareBorder)
            .font(.system(size: fontSize, design: .monospaced))
            .frame(width: width)
            .focused($focused)
            .onAppear { text = formatted(value) }
            .onChange(of: text) { _, _ in
                if focused { isEditing = true }
            }
            .onChange(of: value) { _, newVal in
                // Only block external updates (slider, layer switch) while keystrokes
                // are actually in-flight. After Return, isEditing is false so the
                // slider and selection changes can update the display normally.
                if !isEditing { text = formatted(newVal) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    commit()
                    isEditing = false
                }
            }
            .onSubmit {
                commit()
                isEditing = false
            }
            .loomHelp(help)
    }

    private func commit() {
        // formatted(_:) below inserts thousands separators for display (e.g.
        // "1,234"); without stripping them back out here, pasting a value copied
        // from this same field's own display — or from anywhere else formatted
        // the same way — would fail to parse and silently leave `value` unchanged.
        guard let d = Double(sanitizedForParsing(text)) else { return }
        value = d
        onCommit?(d)
        text = formatted(value)
    }

    private func formatted(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }
}

private func sanitizedForParsing(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: ",", with: "")
}

/// Like `FloatEntryField` but for `Int` values that may span the full 64-bit range —
/// e.g. hash-derived seeds. Bridging such a value through `Double` for editing (as
/// `FloatEntryField` does) silently loses precision beyond ~15-17 significant
/// digits and rounds it to a *different* integer, defeating the point of pasting
/// in an exact seed to reproduce a specific result. Parses/formats `Int` natively,
/// no floating-point step at all.
struct IntEntryField: View {
    @Binding var value: Int
    var width: CGFloat
    var fontSize: CGFloat = 12
    var help: String = ""
    var onCommit: ((Int) -> Void)? = nil

    @State private var text = ""
    @State private var isEditing = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.squareBorder)
            .font(.system(size: fontSize, design: .monospaced))
            .frame(width: width)
            .focused($focused)
            .onAppear { text = String(value) }
            .onChange(of: text) { _, _ in
                if focused { isEditing = true }
            }
            .onChange(of: value) { _, newVal in
                if !isEditing { text = String(newVal) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    commit()
                    isEditing = false
                }
            }
            .onSubmit {
                commit()
                isEditing = false
            }
            .loomHelp(help)
    }

    private func commit() {
        guard let i = Int(sanitizedForParsing(text)) else { return }
        value = i
        onCommit?(i)
        text = String(value)
    }
}

// MARK: - LoomPicker

// Custom dropdown with per-option hover help shown in the tab bar.
// T must conform to LoomPickerOption (see LoomPickerOptions.swift).
// Environment objects do not automatically cross popover boundaries on macOS,
// so LoomPicker explicitly forwards the controller into its popover content.
struct LoomPicker<T: LoomPickerOption>: View {
    @EnvironmentObject private var controller: AppController
    @Binding var selection: T
    var maxWidth: CGFloat = 130
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 3) {
                Text(selection.pickerLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    LoomPickerRow(
                        option:     option,
                        isSelected: option == selection,
                        onSelect:   { selection = option; isOpen = false }
                    )
                }
            }
            .padding(4)
            .frame(minWidth: max(110, maxWidth))
            .environmentObject(controller)
        }
    }
}

private struct LoomPickerRow<T: LoomPickerOption>: View {
    @EnvironmentObject private var controller: AppController
    let option: T
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 13)
                Text(option.pickerLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovered ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                controller.hoverHelpText = option.pickerHelp
            } else if controller.hoverHelpText == option.pickerHelp {
                controller.hoverHelpText = ""
            }
        }
    }
}

// Slider that resets to `defaultValue` on double-click.
// Uses NSViewRepresentable + NSClickGestureRecognizer because SwiftUI's
// simultaneousGesture(TapGesture(count:2)) is consumed by NSSlider's own
// mouse-tracking loop and never fires reliably on macOS.
struct ResettableSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var defaultValue: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value,
                              minValue: range.lowerBound,
                              maxValue: range.upperBound,
                              target: context.coordinator,
                              action: #selector(Coordinator.sliderChanged(_:)))
        slider.isContinuous = true
        let dbl = NSClickGestureRecognizer(target: context.coordinator,
                                           action: #selector(Coordinator.doubleClicked(_:)))
        dbl.numberOfClicksRequired = 2
        slider.addGestureRecognizer(dbl)
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.doubleValue = value
        nsView.minValue    = range.lowerBound
        nsView.maxValue    = range.upperBound
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: ResettableSlider
        init(_ parent: ResettableSlider) { self.parent = parent }

        @objc func sliderChanged(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }

        @objc func doubleClicked(_ sender: NSClickGestureRecognizer) {
            parent.value = parent.defaultValue
        }
    }
}

// MARK: - ResizableSplitPane

// A hand-rolled top/bottom split rather than the stock VSplitView (NSSplitView
// bridge): VSplitView's native divider is a near-invisible hairline, easy to miss
// as a grab affordance. This draws a deliberately prominent divider bar with a
// visible grip glyph and a resize cursor on hover, at the cost of implementing the
// drag-to-resize math by hand instead of getting it for free from AppKit.
struct ResizableSplitPane<Top: View, Bottom: View>: View {
    @Binding var topHeight: Double
    var minTop:    CGFloat = 100
    var minBottom: CGFloat = 100
    @ViewBuilder var top:    () -> Top
    @ViewBuilder var bottom: () -> Bottom

    @State private var dragStartHeight: Double?

    var body: some View {
        GeometryReader { geo in
            let clampedTop = clamped(topHeight, in: geo.size.height)
            VStack(spacing: 0) {
                top()
                    .frame(height: clampedTop)
                    .clipped()

                divider(totalHeight: geo.size.height)

                bottom()
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
        }
    }

    private func clamped(_ height: Double, in totalHeight: CGFloat) -> CGFloat {
        let maxTop = max(minTop, totalHeight - minBottom)
        return min(max(CGFloat(height), minTop), maxTop)
    }

    private func divider(totalHeight: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = dragStartHeight ?? topHeight
                    if dragStartHeight == nil { dragStartHeight = topHeight }
                    let proposed = start + value.translation.height
                    topHeight = Double(clamped(proposed, in: totalHeight))
                }
                .onEnded { _ in dragStartHeight = nil }
        )
    }
}
