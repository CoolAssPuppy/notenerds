import SwiftUI

struct TrashSidebarDropTarget: ViewModifier {
    let isEnabled: Bool
    let onDrop: ([String]) -> Bool
    @State private var isTargeted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .listRowBackground(isTargeted ? Color.red.opacity(0.14) : Color.clear)
                .dropDestination(for: String.self) { items, _ in
                    onDrop(items)
                } isTargeted: { isTargeted in
                    self.isTargeted = isTargeted
                }
        } else {
            content
        }
    }
}
