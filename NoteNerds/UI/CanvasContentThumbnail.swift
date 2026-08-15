import SwiftUI

struct CanvasContentThumbnail: View {
    let canvas: Canvas

    var body: some View {
        ZStack {
            PaperPreview(paperType: canvas.template)
            GeometryReader { proxy in
                Image(uiImage: CanvasThumbnailCache.image(for: canvas, size: proxy.size))
                    .resizable()
                    .interpolation(.medium)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.secondary.opacity(0.2))
        }
    }
}
