import SwiftUI

extension CanvasTool {
    var label: String {
        switch self {
        case .ballpoint: "Ballpoint"
        case .fineliner: "Fineliner"
        case .mechanicalPencil: "Mechanical pencil"
        case .pencil: "Pencil"
        case .marker: "Marker"
        case .highlighter: "Highlighter"
        case .brush: "Brush"
        case .calligraphyPen: "Calligraphy pen"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        case .handwritingToText: "Handwriting to text"
        }
    }

    var symbol: String {
        switch self {
        case .ballpoint: "pencil.tip"
        case .fineliner: "pencil.tip.crop.circle"
        case .mechanicalPencil: "pencil.circle"
        case .pencil: "pencil"
        case .marker: "highlighter.fill"
        case .highlighter: "highlighter"
        case .brush: "paintbrush.pointed"
        case .calligraphyPen: "paintbrush.pointed.fill"
        case .eraser: "eraser"
        case .lasso: "lasso"
        case .handwritingToText: "character.cursor.ibeam"
        }
    }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .ballpoint: "b"
        case .fineliner: "f"
        case .mechanicalPencil: "m"
        case .pencil: "p"
        case .marker: "k"
        case .highlighter: "h"
        case .brush: "r"
        case .calligraphyPen: "g"
        case .eraser: "e"
        case .lasso: "l"
        case .handwritingToText: "t"
        }
    }
}
