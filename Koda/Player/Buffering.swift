import SwiftUI

/// An arc that circles a control while the song it controls is loading.
struct BufferingRing: View {
    var lineWidth: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // The arc turns steadily and breathes in length, so it reads as busy rather than stuck.
            let length = 0.18 + 0.14 * (1 + sin(t * 2.4)) / 2
            Circle()
                .trim(from: 0, to: reduceMotion ? 0.3 : length)
                .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(reduceMotion ? 0 : (t * 300).truncatingRemainder(dividingBy: 360)))
        }
        .opacity(reduceMotion ? 0.6 : 0.9)
        .accessibilityHidden(true)
    }
}

/// A band of light that sweeps across the content while something loads.
struct Sheen: ViewModifier {
    var isActive: Bool
    var period: Double = 1.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if isActive {
                GeometryReader { geometry in
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                        let width = geometry.size.width
                        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0),
                                               .init(color: .white.opacity(reduceMotion ? 0.08 : 0.22), location: 0.5),
                                               .init(color: .white.opacity(0), location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: width * 0.6)
                            .rotationEffect(.degrees(20))
                            .offset(x: -width * 0.8 + phase * width * 2.2)
                            .frame(width: width, height: geometry.size.height, alignment: .leading)
                            .blendMode(.plusLighter)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }
}

extension View {
    func sheen(_ isActive: Bool, period: Double = 1.6) -> some View {
        modifier(Sheen(isActive: isActive, period: period))
    }
}
