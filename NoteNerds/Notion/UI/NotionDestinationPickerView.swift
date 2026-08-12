import SwiftUI

struct NotionDestinationPickerView: View {
    @ObservedObject var model: NotionIntegrationModel
    let library: LibraryState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List(model.pages) { page in
            Button {
                dismiss()
                Task {
                    await model.selectDestination(parentPage: page, library: library)
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.title)
                        Text("Create the Note Nerds database here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.state == .selectingDestination)
        }
        .navigationTitle("Choose Notion location")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search pages")
        .onSubmit(of: .search) { Task { await model.reloadPages(query: query) } }
        .overlay {
            if model.state == .selectingDestination {
                ProgressView("Creating database")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else if model.pages.isEmpty {
                ContentUnavailableView(
                    "No accessible pages",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Share a Notion page with Note Nerds, then try again.")
                )
            }
        }
    }
}
