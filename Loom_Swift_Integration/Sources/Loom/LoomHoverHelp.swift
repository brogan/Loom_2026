import SwiftUI

struct LoomHoverHelp: ViewModifier {
    @EnvironmentObject private var controller: AppController
    let text: String

    init(_ text: String) {
        self.text = text
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if text.isEmpty {
            content
        } else {
            content
                .onHover { hovering in
                    if hovering {
                        controller.hoverHelpText = text
                    } else if controller.hoverHelpText == text {
                        controller.hoverHelpText = ""
                    }
                }
        }
    }
}

extension View {
    func loomHelp(_ text: String) -> some View {
        modifier(LoomHoverHelp(text))
    }

    /// Expands the tappable area of a small icon to a comfortable minimum hit target.
    /// Apply inside the button label, after any font/color modifiers.
    func iconHitArea(_ side: CGFloat = 22) -> some View {
        self.frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
    }
}
