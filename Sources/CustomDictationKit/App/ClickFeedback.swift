import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.2 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.4 : 0.14))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct SidebarButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        selected
                            ? Color.accentColor.opacity(configuration.isPressed ? 0.32 : 0.18)
                            : Color.primary.opacity(configuration.isPressed ? 0.14 : 0)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct FlashButton: View {
    let title: String
    let doneTitle: String
    let action: () -> Void
    @State private var done = false

    var body: some View {
        Button(done ? doneTitle : title) {
            action()
            done = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                done = false
            }
        }
        .buttonStyle(PressableButtonStyle())
    }
}
