# Pannable

A pannable 2D canvas for SwiftUI. You give it a collection, it lays the items out on a large canvas, and it only builds the ones that are on screen.

![iOS 16+](https://img.shields.io/badge/iOS-16.0+-1575F9)
![iPadOS 16+](https://img.shields.io/badge/iPadOS-16.0+-1575F9)
![macOS 13+](https://img.shields.io/badge/macOS-13.0+-1575F9)
![watchOS 9+](https://img.shields.io/badge/watchOS-9.0+-1575F9)
![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138)
![No dependencies](https://img.shields.io/badge/dependencies-none-2EA043)

```swift
.package(url: "https://github.com/thatswiftguy/Pannable.git", from: "1.0.0")
```

## Usage

### Basics

```swift
PannableCanvas(stickers, contentSize: .fixed(width: 4000, height: 3000)) { sticker in
    StickerCard(sticker: sticker)
}
.canvasLayout(.flow(horizontalSpacing: 24, verticalSpacing: 24))
.canvasContentAnchor(.center)   // where the items sit on the canvas
.canvasInitialAnchor(.center)   // where the viewport opens
```

### IDs work like `ForEach`

```swift
PannableCanvas(stickers) { ... }                 // Identifiable
PannableCanvas(photos, id: \.assetID) { ... }    // key path
PannableCanvas(0..<2_000) { ... }                // range
```

### Layouts

```swift
.canvasLayout(.flow(horizontalSpacing: 24, verticalSpacing: 24))
.canvasLayout(.grid(columns: 8, horizontalSpacing: 12, verticalSpacing: 12))
```

### Margins

```swift
.canvasContentMargins(48)
.canvasContentMargins(EdgeInsets(top: 40, leading: 24, bottom: 40, trailing: 24))
```

### Item size

Items measure themselves. If they are all the same size, set it and nothing gets measured.

```swift
.canvasItemSize(CGSize(width: 160, height: 160))
.canvasEstimatedItemSize(CGSize(width: 120, height: 90))   // otherwise
```

### Backdrop

```swift
.canvasBackground(.dots(spacing: 24))
.canvasBackground(.grid(spacing: 40, color: .blue.opacity(0.25)))
```

### Scroll to something

This works the same way as `ScrollViewReader`.

```swift
CanvasReader { proxy in
    PannableCanvas(nodes) { NodeCard(node: $0) }
        .toolbar {
            Button("Reveal") { proxy.scrollTo(selection) }
            Button("Origin") { proxy.scrollTo(.zero, anchor: .topLeading) }
        }
}
```

### Track the viewport

```swift
@State private var viewport = CanvasViewport()

PannableCanvas(nodes) { NodeCard(node: $0) }
    .canvasViewport($viewport)   // .visibleRect, .contentSize, .isMoving
```

### Behavior

```swift
.canvasScrollIndicators(.hidden)
.canvasBounce(.never)
.canvasScrollDisabled(true)
.canvasDeceleration(.fast)
```

### Custom layout

This works like SwiftUI's `Layout`, except it runs on sizes instead of views. You can place items anywhere. Negative coordinates are fine, because the canvas normalizes and anchors the result for you.

```swift
struct RingCanvasLayout: CanvasLayout {
    var radius: CGFloat

    func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Void) -> CanvasLayoutResult {
        let step = (2 * .pi) / CGFloat(max(items.count, 1))
        return CanvasLayoutResult(frames: items.map { item in
            let angle = step * CGFloat(item.index)
            return CGRect(
                x: radius * cos(angle) - item.size.width / 2,
                y: radius * sin(angle) - item.size.height / 2,
                width: item.size.width,
                height: item.size.height
            )
        })
    }
}

extension CanvasLayout where Self == RingCanvasLayout {
    static func ring(radius: CGFloat) -> RingCanvasLayout { RingCanvasLayout(radius: radius) }
}
```

```swift
.canvasLayout(.ring(radius: 600))
```

## How it works

**The core is plain Swift.** It takes sizes and gives back frames. It never touches UIKit, AppKit or SwiftUI, so you can test it without a simulator.

**Layouts run on sizes, not views.** The canvas knows where every item goes before a single view is created. That is why 10,000 items do not mean 10,000 views.

**A layout does not know about the canvas.** It returns a cluster of frames starting at the origin. The engine then normalizes it, mirrors it for right to left, works out the content size and anchors it. So every layout gets right to left support and anchoring without doing any work for it.

**Culling uses a grid index.** All the frames go into a uniform grid. Asking which items are inside a rectangle costs time based on the visible area, not on how much data there is. Every pan runs that query, and the result goes to a pool of recycled hosting controllers.

**Scroll callbacks do nothing else.** Measuring, allocating and re-layout all wait until the canvas stops moving. That is what keeps a fling smooth.

### Platform hosts

| Platform | Built on |
|---|---|
| iOS / iPadOS | `UIScrollView`, wrapped in a view controller representable because each item is a `UIHostingController` and needs a parent. `UIScrollViewDelegate` drives the culling. `UIGestureRecognizerDelegate` adds drag to pan with a pointer, which a scroll view does not do on its own. |
| macOS | `NSScrollView` with a flipped document view. Clip view bounds changes and the live scroll notifications take the place of the scroll delegate. |
| watchOS | Neither type exists there, so it is pure SwiftUI with a drag gesture and the Digital Crown. Same engine and same culling as the others. |

### Measuring

| What you set | What happens |
|---|---|
| `canvasItemSize` | Every item uses that size and nothing is measured. |
| `canvasEstimatedItemSize` | Items use the estimate while they are measured, then the layout settles once. |
| Neither | A default estimate is used. That is fine for hundreds of items. Set one for thousands. |

Measuring happens off screen in chunks between run loop turns, so the first frame is not blocked. Sizes are cached by item ID, so they survive reordering and inserting. Only new items get measured.

### Backdrop

The backdrop is a tiled pattern rather than something drawn into the content view. A 6000 by 6000 content view on a 3x display would need over a gigabyte of backing store. Tiling one small image costs nothing.

### Accessibility

Items that are off screen are not in the view hierarchy, so VoiceOver cannot swipe to them. A table view has the same problem. The three finger scroll gesture pages the canvas in all four directions instead. Hosted views also declare their accessibility order, because subviews otherwise end up in recycle order rather than data order.

## Gotchas

- On watchOS you cannot measure a view off screen. Set `canvasItemSize` or `canvasEstimatedItemSize` if your items are different sizes.
- On macOS bounce follows the system elasticity. `.never` works, but `.always` behaves the same as `.automatic`.
- The backdrop is a bitmap. It is redrawn when the appearance changes, it does not adapt on its own.
- Tracking the viewport writes state on every frame of a pan, so keep whatever depends on it small. Several observers can watch at once.

## Not done yet

Zoom is missing. The math and the delegate hooks are already there, so adding it will not break the API. Selection, drag to move, snapping, per item coordinates and a freeform canvas are also still open.

## Tests

```bash
swift test
```

These cover the layout engine, the spatial index, sizing, backdrop geometry and the update loop guard. No simulator needed. There is also a randomized check of the index against a brute force scan.
