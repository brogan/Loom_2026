import SwiftUI

// TextField(value:format:) reverts on every keystroke that doesn't fully parse, making it
// impossible to type negative values (the leading "-" is rejected before you can finish).
// FloatEntryField buffers edits in local state and commits to the model only on Return or focus loss.
struct FloatEntryField: View {
    @Binding var value: Double
    var width: CGFloat
    var fractionDigits: Int = 3
    var fontSize: CGFloat = 12

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
    }

    private func commit() {
        if let d = Double(text) { value = d }
    }

    private func formatted(_ d: Double) -> String {
        d.formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }
}
