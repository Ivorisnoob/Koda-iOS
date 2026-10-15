import KodaCore
import SwiftUI

/// Cover art at a fixed size: square, rounded, or a circle for artists.
///
/// A video thumbnail (16:9) is cropped to the square, so every row and card
/// keeps the same shape whatever YouTube served.
struct ArtworkView: View {
    var artwork: Artwork?
    var size: CGFloat
    var cornerRadius: CGFloat = 8
    var circle = false
    /// Fill whatever frame it is given instead of `size`, which then only sets the pixels loaded.
    var fillsFrame = false

    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    private var pixels: Int { Int((size * scale).rounded(.up)) }
    private var url: URL? { artwork?.url(pixels: max(pixels, 120)) }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: circle ? "music.mic" : "music.note")
                            .font(.system(size: size * 0.3, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: fillsFrame ? nil : size, height: fillsFrame ? nil : size)
        .frame(maxWidth: fillsFrame ? .infinity : nil, maxHeight: fillsFrame ? .infinity : nil)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let hit = ImagePipeline.shared.cached(url, pixels: pixels) {
                image = hit
                return
            }
            let loaded = await ImagePipeline.shared.image(url, pixels: pixels)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
        .accessibilityHidden(true)
    }

    private var shape: AnyInsettableShape {
        circle ? AnyInsettableShape(Circle()) : AnyInsettableShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// A type-erased insettable shape, so one view can be clipped by a circle or a rounded square.
struct AnyInsettableShape: InsettableShape {
    private let pathBuilder: @Sendable (CGRect) -> Path
    private let insetBuilder: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
        insetBuilder = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { insetBuilder(amount) }
}
