#if DEBUG

import SwiftUI

// Previews double as the package's worked examples. `PreviewProvider` rather than the
// `#Preview` macro, whose expansion requires a deployment target above this package's
// floor.

private struct PreviewSticker: Identifiable, Hashable {
    let id: Int
    let title: String
    let size: CGSize
    let hue: Double

    static func sample(_ count: Int) -> [PreviewSticker] {
        (0..<count).map { index in
            let width: CGFloat = CGFloat(110 + (index * 37) % 90)
            let height: CGFloat = CGFloat(64 + (index * 53) % 60)
            return PreviewSticker(
                id: index,
                title: "Note \(index)",
                size: CGSize(width: width, height: height),
                hue: Double(index % 12) / 12.0
            )
        }
    }
}

private struct PreviewCard: View {
    let sticker: PreviewSticker

    var body: some View {
        Text(sticker.title)
            .font(.headline)
            .padding(8)
            .frame(width: sticker.size.width, height: sticker.size.height, alignment: .topLeading)
            .background(
                Color(hue: sticker.hue, saturation: 0.35, brightness: 0.95),
                in: RoundedRectangle(cornerRadius: 12)
            )
    }
}

/// Self-measured items packed around the middle of a fixed canvas.
struct PannableCanvas_Flow_Previews: PreviewProvider {
    static var previews: some View {
        PannableCanvas(PreviewSticker.sample(120), contentSize: .fixed(width: 3000, height: 2400)) { sticker in
            PreviewCard(sticker: sticker)
        }
        .canvasLayout(.flow(horizontalSpacing: 20, verticalSpacing: 20, alignment: .top))
        .canvasContentAnchor(.center)
        .canvasInitialAnchor(.center)
        .canvasContentMargins(40)
        .previewDisplayName("Flow, centered")
    }
}

/// A uniform grid, which skips measurement entirely.
struct PannableCanvas_Grid_Previews: PreviewProvider {
    static var previews: some View {
        PannableCanvas(0..<5_000) { index in
            Text("\(index)")
                .font(.system(size: 13, design: .rounded))
                .frame(width: 76, height: 76)
                .background(
                    Color(hue: Double(index % 12) / 12.0, saturation: 0.5, brightness: 0.9),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .canvasLayout(.grid(columns: 71, horizontalSpacing: 8, verticalSpacing: 8))
        .canvasItemSize(CGSize(width: 76, height: 76))
        .canvasContentAnchor(.topLeading)
        .canvasInitialAnchor(.topLeading)
        .previewDisplayName("Grid, 5000 items")
    }
}

/// A custom layout, reached through static member lookup exactly like the built-ins.
private struct RingCanvasLayout: CanvasLayout {
    var radius: CGFloat

    func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Void) -> CanvasLayoutResult {
        let step = (2 * .pi) / CGFloat(max(items.count, 1))
        let frames = items.map { item -> CGRect in
            let angle = step * CGFloat(item.index)
            return CGRect(
                x: radius * cos(angle) - item.size.width / 2,
                y: radius * sin(angle) - item.size.height / 2,
                width: item.size.width,
                height: item.size.height
            )
        }
        return CanvasLayoutResult(frames: frames)
    }
}

extension CanvasLayout where Self == RingCanvasLayout {
    fileprivate static func ring(radius: CGFloat) -> RingCanvasLayout { RingCanvasLayout(radius: radius) }
}

struct PannableCanvas_CustomLayout_Previews: PreviewProvider {
    static var previews: some View {
        PannableCanvas(PreviewSticker.sample(40), contentSize: .automatic) { sticker in
            PreviewCard(sticker: sticker)
        }
        .canvasLayout(.ring(radius: 700))
        .canvasContentAnchor(.center)
        .canvasInitialAnchor(.center)
        .canvasContentMargins(60)
        .previewDisplayName("Custom ring layout")
    }
}

/// Programmatic movement through `CanvasProxy`.
struct PannableCanvas_Reader_Previews: PreviewProvider {
    static var previews: some View {
        CanvasReader { proxy in
            ZStack(alignment: .bottom) {
                PannableCanvas(PreviewSticker.sample(400), contentSize: .fixed(width: 4000, height: 4000)) { sticker in
                    PreviewCard(sticker: sticker)
                }
                .canvasLayout(.flow(horizontalSpacing: 16, verticalSpacing: 16))
                .canvasContentAnchor(.center)
                .canvasInitialAnchor(.center)

                HStack {
                    Button("First") { proxy.scrollTo(0) }
                    Button("Last") { proxy.scrollTo(399) }
                    Button("Origin") { proxy.scrollTo(.zero, anchor: .topLeading) }
                }
                .padding()
            }
        }
        .previewDisplayName("Reader and proxy")
    }
}

#endif
