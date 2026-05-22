import SwiftUI

// TextField(value:format:) reverts on every keystroke that doesn't fully parse, making it
// impossible to type negative values (the leading "-" is rejected before you can finish).
// FloatEntryField buffers edits in local state and commits to the model only on Return or focus loss.
struct FloatEntryField: View {
    @Binding var value: Double
    var width: CGFloat
    var fractionDigits: Int = 3
    var fontSize: CGFloat = 12
    var help: String = ""

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.squareBorder)
            .font(.system(size: fontSize, design: .monospaced))
            .frame(width: width)
            .focused($focused)
            .onAppear { text = formatted(value) }
            .onChange(of: value) { _, newVal in
                if !focused { text = formatted(newVal) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    commit()
                    text = formatted(value)
                }
            }
            .onSubmit { commit() }
            .loomHelp(help)
    }

    private func commit() {
        if let d = Double(text) { value = d }
    }

    private func formatted(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(0...fractionDigits)))
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
struct ResettableSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var defaultValue: Double

    var body: some View {
        Slider(value: $value, in: range)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { value = defaultValue }
            )
    }
}
