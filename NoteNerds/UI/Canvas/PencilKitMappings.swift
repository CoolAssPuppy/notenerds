import PencilKit
import UIKit

extension CanvasTool {
    var instrument: DrawingInstrument? {
        switch self {
        case .ballpoint: .ballpoint
        case .fineliner: .fineliner
        case .mechanicalPencil: .mechanicalPencil
        case .pencil: .pencil
        case .marker: .marker
        case .highlighter: .highlighter
        case .brush: .brush
        case .calligraphyPen: .calligraphyPen
        case .handwritingToText: .ballpoint
        case .eraser, .lasso: nil
        }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pencil, .mechanicalPencil: .pencil
        case .marker, .highlighter: .marker
        case .fineliner: .monoline
        case .brush, .calligraphyPen: .fountainPen
        case .ballpoint, .handwritingToText, .eraser, .lasso: .pen
        }
    }
}

extension DrawingInstrument {
    var inkType: PKInk.InkType {
        switch self {
        case .pencil, .mechanicalPencil: .pencil
        case .marker, .highlighter: .marker
        case .fineliner: .monoline
        case .brush, .calligraphyPen: .fountainPen
        case .ballpoint: .pen
        }
    }
}

extension UIColor {
    convenience init(_ color: InkColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension CanvasRect {
    var pencilKitRect: CGRect { CGRect(x: minX, y: minY, width: size.width, height: size.height) }
}
