import UIKit

struct SystemFontDescriptor: Hashable, Comparable {
    let familyName: String
    let postScriptName: String
    let displayName: String

    static func < (left: SystemFontDescriptor, right: SystemFontDescriptor) -> Bool {
        if left.familyName != right.familyName {
            return left.familyName.localizedStandardCompare(right.familyName) == .orderedAscending
        }
        return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
    }
}

@MainActor
enum SystemFontCatalog {
    static let availableFonts: [SystemFontDescriptor] = UIFont.familyNames.flatMap { familyName in
        UIFont.fontNames(forFamilyName: familyName).map { postScriptName in
            let font = UIFont(name: postScriptName, size: UIFont.labelFontSize)
            let faceName = font?.fontDescriptor.object(forKey: .face) as? String
            return SystemFontDescriptor(
                familyName: familyName,
                postScriptName: postScriptName,
                displayName: faceName ?? postScriptName
            )
        }
    }.sorted()
}
