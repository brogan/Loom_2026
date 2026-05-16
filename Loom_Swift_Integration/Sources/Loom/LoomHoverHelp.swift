import SwiftUI

struct LoomHoverHelp: ViewModifier {
    @EnvironmentObject private var controller: AppController
    let text: String

    init(_ text: String) {
        self.text = text
    }

    func body(content: Content) -> some View {
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

