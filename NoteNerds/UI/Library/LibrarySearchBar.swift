import SwiftUI

struct LibrarySearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> UISearchTextField {
        let searchField = UISearchTextField()
        searchField.delegate = context.coordinator
        searchField.placeholder = "Search notes and handwriting"
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.clearButtonMode = .whileEditing
        searchField.returnKeyType = .search
        searchField.accessibilityIdentifier = "Library search"
        searchField.accessibilityLabel = "Search notes and handwriting"
        searchField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.searchTextChanged(_:)),
            for: .editingChanged
        )
        return searchField
    }

    func updateUIView(_ searchField: UISearchTextField, context: Context) {
        if searchField.text != text { searchField.text = text }
        if isFocused, !searchField.isFirstResponder {
            searchField.becomeFirstResponder()
        } else if !isFocused, searchField.isFirstResponder {
            searchField.resignFirstResponder()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        private let debouncer = SearchQueryDebouncer()

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        @objc func searchTextChanged(_ searchField: UISearchTextField) {
            let value = searchField.text ?? ""
            if value.isEmpty {
                text = value
                return
            }
            debouncer.submit(value) { [weak self] latest in
                self?.text = latest
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFocused = false
        }
    }
}

struct LibrarySearchControl: View {
    @Binding var text: String
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled

    var body: some View {
        Group {
            if isExpanded {
                LibrarySearchBar(text: $text, isFocused: $isExpanded)
                    .frame(width: 240)
                    .transition(isReduceMotionEnabled ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Button("Search", systemImage: AppSymbol.search) {
                    withAnimation(searchAnimation) { isExpanded = true }
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("Library search button")
                .accessibilityValue(text.isEmpty ? "" : text)
            }
        }
    }

    private var searchAnimation: Animation? {
        isReduceMotionEnabled ? nil : .snappy(duration: 0.22)
    }
}
