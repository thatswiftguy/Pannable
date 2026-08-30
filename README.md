# Pannable

A pannable 2D canvas for SwiftUI, built to feel like a component Apple shipped.

A canvas has a width and a height. You hand it a collection, it arranges the items with
a layout anchored wherever you choose, and the viewport pans around that space. Only the
items the viewport can actually reach are ever built, so a canvas over thousands of
items costs about what one screenful costs.

```swift
PannableCanvas(stickers, contentSize: .fixed(width: 4000, height: 3000)) { sticker in
    StickerCard(sticker: sticker)
}
.canvasLayout(.flow(horizontalSpacing: 24, verticalSpacing: 24))
.canvasContentAnchor(.center)
.canvasInitialAnchor(.center)
```

| | |
|---|---|
| **Platforms** | iOS 16 · iPadOS 16 · macOS 13 · watchOS 9 |
| **Swift** | 6.0 tools, Swift 6 language mode |
| **Dependencies** | none |

## Installation

```swift
.package(url: "https://github.com/<owner>/Pannable.git", from: "1.0.0")
```

## Usage

### Items packed around the middle of a canvas

The common case. `contentSize` sets how far the canvas can travel;
`canvasContentAnchor` decides where in that space the items cluster, and
`canvasInitialAnchor` decides where the viewport opens.

```swift
import SwiftUI
import Pannable

struct Sticker: Identifiable, Hashable {
    let id: UUID
    let title: String
}

struct BoardView: View {
    let stickers: [Sticker]

    var body: some View {
        PannableCanvas(stickers, contentSize: .fixed(width: 4000, height: 3000)) { sticker in
            StickerCard(sticker: sticker)
        }
        .canvasLayout(.flow(horizontalSpacing: 24, verticalSpacing: 24))
        .canvasContentAnchor(.center)
        .canvasInitialAnchor(.center)
        .canvasContentMargins(48)
    }
}
```

### A grid of uniform tiles

Setting `canvasItemSize` tells the canvas every item is the same size, which skips
measurement altogether. It is the fastest path and worth reaching for whenever it is
true.

```swift
PannableCanvas(photos, id: \.assetID) { photo in
    PhotoTile(photo: photo)
}
.canvasLayout(.grid(columns: 8, horizontalSpacing: 12, verticalSpacing: 12, alignment: .top))
.canvasItemSize(CGSize(width: 160, height: 160))
.canvasContentAnchor(.topLeading)
.canvasInitialAnchor(.topLeading)
.canvasScrollIndicators(.hidden)
```

### A constant range

The same shape as `ForEach`, for when the data is just a count.

```swift
PannableCanvas(0..<2_000) { index in
    Text("\(index)")
        .frame(width: 80, height: 80)
        .background(.quaternary, in: .rect(cornerRadius: 12))
}
.canvasLayout(.grid(columns: 40, horizontalSpacing: 8, verticalSpacing: 8))
.canvasItemSize(CGSize(width: 80, height: 80))
```

### Moving the viewport in code

`CanvasReader` and `CanvasProxy` pair up exactly like `ScrollViewReader` and
`ScrollViewProxy`. The id you pass is the one your data already provides.

```swift
CanvasReader { proxy in
    PannableCanvas(nodes) { NodeCard(node: $0) }
        .toolbar {
            Button("Reveal selection") { proxy.scrollTo(selection, anchor: .center) }
            Button("Back to origin") { proxy.scrollTo(.zero, anchor: .topLeading) }
        }
}
```

`scrollTo` animates by default; pass `animated: false` to jump.

### Watching the viewport

Useful for a minimap, a coordinate readout, or paging data in as it comes into range.

```swift
@State private var viewport = CanvasViewport()

PannableCanvas(nodes) { NodeCard(node: $0) }
    .canvasViewport($viewport)
    .overlay(alignment: .bottomTrailing) {
        MiniMap(visible: viewport.visibleRect, total: viewport.contentSize)
            .opacity(viewport.isMoving ? 1 : 0)
    }
```

The binding is written on every frame of a pan, so keep whatever depends on it small.
`onCanvasViewportChange` does the same without a binding, and several observers compose
rather than replacing one another.

### Writing your own layout

`CanvasLayout` is shaped after SwiftUI's `Layout` — build a cache, then place — with one
important difference: it works on **sizes**, not on live subviews. That is what lets a
canvas position ten thousand items without building ten thousand views.

A layout doesn't know the canvas exists. Place items wherever is natural, negative
coordinates included; the canvas normalizes the cluster and anchors it for you.

```swift
struct RingCanvasLayout: CanvasLayout {
    var radius: CGFloat

    func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Void) -> CanvasLayoutResult {
        let step = (2 * .pi) / CGFloat(max(items.count, 1))
        let frames = items.map { item in
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
    static func ring(radius: CGFloat) -> RingCanvasLayout { RingCanvasLayout(radius: radius) }
}
```

The call site is then indistinguishable from a built-in:

```swift
PannableCanvas(nodes) { NodeCard(node: $0) }
    .canvasLayout(.ring(radius: 600))
    .canvasContentAnchor(.center)
```

## How it works

All the layout logic — placement, anchoring, content sizing, and visibility culling — is
pure Swift with no view machinery in it. The platform hosts sit on top and stay thin:

- **iOS / iPadOS** wraps `UIScrollView`, with `UIScrollViewDelegate` driving culling and
  `UIGestureRecognizerDelegate` adding pointer drag-to-pan, which a scroll view does not
  do on its own.
- **macOS** uses `NSScrollView` over a flipped document view; clip-view bounds changes
  and the live-scroll notifications stand in for the scroll delegate callbacks.
- **watchOS** has neither type available, so it is pure SwiftUI driven by a drag gesture
  and the Digital Crown — over the same engine and the same culling.

Items are hosted from a recycling pool and measured off screen in chunks between
run-loop turns, with estimated sizes standing in until real ones arrive.

## Sizing items

| You set | What happens |
|---|---|
| `canvasItemSize(_:)` | Every item takes that size. Nothing is measured. |
| `canvasEstimatedItemSize(_:)` | Unmeasured items use this while real sizes are computed, then the layout settles once. |
| Neither | Items are measured against a default estimate. Fine for hundreds; set an estimate for thousands. |

The closer the estimate, the less the content shifts when measurements land.

## Platform notes

- **watchOS** cannot measure a SwiftUI view off screen, so items there always take their
  size from `canvasItemSize(_:)` when set and `canvasEstimatedItemSize(_:)` otherwise.
  Set one of them if your items are not all the same size.
- **macOS** bounce follows the system scroll elasticity; `canvasBounce(.never)` disables
  it, but `.always` behaves as `.automatic`.
- Right-to-left layouts mirror the cluster and flip both the content anchor and the
  leading margin, for every layout, without layouts having to handle it themselves.

## Not yet implemented

Zoom is the notable gap. The coordinate math and the scroll-delegate hooks are in place
for it, so it can arrive without an API break. Selection and drag-to-move, scroll
snapping, per-item explicit coordinates, and a freeform canvas are also still open.

## Tests

```bash
swift test
```

The layout engine, the spatial index, the sizing rules, and the update-loop guard are
all covered without needing a simulator, including randomized parity between the index
and a brute-force scan.
