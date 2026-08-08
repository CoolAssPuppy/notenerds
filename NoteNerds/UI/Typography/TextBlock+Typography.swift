import UIKit

extension TextBlock {
    var uiFont: UIFont {
        if let fontName, let font = UIFont(name: fontName, size: fontSize) {
            return font
        }
        return UIFont.preferredFont(forTextStyle: .body).withSize(fontSize)
    }
}
