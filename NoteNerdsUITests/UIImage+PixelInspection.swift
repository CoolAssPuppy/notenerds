import UIKit

extension UIImage {
    func darkPixelCount(in pointRect: CGRect) -> Int {
        guard let source = cgImage else { return 0 }
        let horizontalScale = CGFloat(source.width) / size.width
        let verticalScale = CGFloat(source.height) / size.height
        let pixelRect = CGRect(
            x: pointRect.minX * horizontalScale,
            y: pointRect.minY * verticalScale,
            width: pointRect.width * horizontalScale,
            height: pointRect.height * verticalScale
        ).integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let cropped = source.cropping(to: pixelRect), pixelRect.width > 0, pixelRect.height > 0 else { return 0 }
        let width = Int(pixelRect.width)
        let height = Int(pixelRect.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels.count { $0 < 96 }
    }
}
