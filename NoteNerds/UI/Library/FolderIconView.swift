import SwiftUI
import UIKit

struct FolderIconView: View {
    let icon: FolderIcon
    let color: FolderIconColor?
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch icon {
            case let .systemSymbol(symbol):
                Image(systemName: symbol.rawValue)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color?.swiftUIColor ?? Color.accentColor)
            case let .emoji(emoji):
                Text(emoji.value)
                    .font(.system(size: size * 0.92))
            case let .customPNG(image):
                if let uiImage = UIImage(data: image.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    defaultFolderIcon
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var defaultFolderIcon: some View {
        Image(systemName: FolderSystemSymbol.folder.rawValue)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.accentColor)
    }
}

extension FolderIconColor {
    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    @MainActor
    init(swiftUIColor: Color) {
        let resolved = UIColor(swiftUIColor).resolvedColor(with: UITraitCollection.current)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.init(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            alpha: Double(alpha)
        )
    }
}

extension FolderSystemSymbol {
    var displayName: String {
        switch self {
        case .folder: "Folder"
        case .briefcase: "Briefcase"
        case .personGroup: "People"
        case .house: "Home"
        case .book: "Book"
        case .graduationCap: "School"
        case .heart: "Heart"
        case .star: "Star"
        case .lightbulb: "Idea"
        case .calendar: "Calendar"
        case .checklist: "Checklist"
        case .archive: "Archive"
        case .tray: "Tray"
        case .document: "Document"
        case .chart: "Chart"
        case .tools: "Tools"
        case .art: "Art"
        case .travel: "Travel"
        case .shopping: "Shopping"
        case .finance: "Finance"
        case .health: "Health"
        case .building: "Building"
        case .globe: "World"
        }
    }
}

extension FolderIcon {
    var accessibilityDescription: String {
        switch self {
        case let .systemSymbol(symbol): "\(symbol.displayName) icon"
        case let .emoji(emoji): "\(emoji.value) icon"
        case .customPNG: "Custom image"
        }
    }
}
