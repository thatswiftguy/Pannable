# Pannable

A pannable 2D canvas for SwiftUI. Give it a collection — it lays items out on a big canvas and only builds what's on screen.

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
.canvasContentAnchor(.center)   // where items sit on the canvas
.canvasInitialAnchor(.center)   // where the viewport opens
```

### IDs — same as `ForEach`

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

Items self-measure. All the same size? Say so — skips measuring entirely.

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

Works like `ScrollViewReader`.

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

Like SwiftUI's `Layout`, but on sizes. Place items anywhere — negative coords are fine, the canvas normalizes and anchors.

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

- **Core is pure Swift.** Sizes in, frames out. No UIKit, AppKit or SwiftUI. Testable without a simulator.
- **Layouts take sizes, not views.** That's why 10k items don't mean 10k views — it knows where everything goes before anything exists.
- **Layouts don't know the canvas exists.** They emit a cluster at origin; the engine normalizes it, mirrors it for RTL, resolves content size, anchors it. Every layout gets RTL and anchoring for free.
- **Culling.** Frames go into a uniform grid index. "What's in this rect?" costs visible-area time, not data-size time. Every pan runs it; results go to a pool of recycled hosting controllers.
- **Scroll callbacks do nothing else.** No measuring, no allocating, no re-layout — that waits until the canvas stops. Keeps flings smooth.

### Platform hosts

| Platform | Built on |
|---|---|
| iOS / iPadOS | `UIScrollView`, via a **view controller** representable — items are `UIHostingController`s and need a parent. `UIScrollViewDelegate` drives culling. `UIGestureRecognizerDelegate` adds pointer drag-to-pan, which scroll views don't do. |
| macOS | `NSScrollView` + flipped document view. Clip-view bounds changes and live-scroll notifications replace the scroll delegate. |
| watchOS | Neither type exists. Pure SwiftUI — drag gesture + Digital Crown. Same engine, same culling. |

### Measuring

| Set | Result |
|---|---|
| `canvasItemSize` | Fixed size, nothing measured. |
| `canvasEstimatedItemSize` | Placeholder while measuring, then one reflow. |
| Neither | Default estimate. Fine for hundreds; set one for thousands. |

Measured off-screen in chunks between run-loop turns, so the first frame isn't blocked. Cached by item ID — survives reorder and insert, only new items get measured.

### Backdrop

Tiled pattern, not drawn into the content view. A 6000×6000 content view at 3× would need over a gigabyte of backing store. Tiling one small image costs nothing.

### Accessibility

Off-screen items aren't in the view hierarchy, so VoiceOver can't swipe to them — same as a table view. Three-finger scroll pages in all four directions. Hosted views declare their accessibility order, since subviews otherwise land in recycle order instead of data order.

## Gotchas

- **watchOS** can't measure views off-screen. Set `canvasItemSize` or `canvasEstimatedItemSize` if your items differ in size.
- **macOS** bounce follows system elasticity. `.never` works; `.always` behaves as `.automatic`.
- **Backdrop** is a bitmap — redrawn on appearance change, doesn't adapt on its own.
- **Viewport tracking** writes state every frame of a pan. Keep dependents small. Multiple observers compose.

## Not done yet

Zoom — math and delegate hooks are already in place, so it won't break the API. Also: selection, drag-to-move, snapping, per-item coordinates, freeform canvas.

## Tests

```bash
swift test
```

Layout engine, spatial index, sizing, backdrop geometry, update-loop guard. No simulator needed. Includes randomized parity against a brute-force scan.
