# Pannable

A pannable 2D canvas for SwiftUI. Hand it a collection and it arranges the items on a
canvas of any size, building only the ones the viewport can actually see.

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

### The basics

Give it a collection and a canvas size. `canvasContentAnchor` decides where the items
cluster, `canvasInitialAnchor` where the viewport opens.

```swift
PannableCanvas(stickers, contentSize: .fixed(width: 4000, height: 3000)) { sticker in
    StickerCard(sticker: sticker)
}
.canvasLayout(.flow(horizontalSpacing: 24, verticalSpacing: 24))
.canvasContentAnchor(.center)
.canvasInitialAnchor(.center)
```

Items are identified the way `ForEach` identifies them — `Identifiable`, an `id` key
path, or a constant range.

```swift
PannableCanvas(photos, id: \.assetID) { PhotoTile(photo: $0) }

PannableCanvas(0..<2_000) { Text("\($0)").frame(width: 80, height: 80) }
```

### Layouts

```swift
.canvasLayout(.flow(horizontalSpacing: 24, verticalSpacing: 24))
.canvasLayout(.grid(columns: 8, horizontalSpacing: 12, verticalSpacing: 12))
```

### Spacing and margins

```swift
.canvasContentMargins(48)
.canvasContentMargins(EdgeInsets(top: 40, leading: 24, bottom: 40, trailing: 24))
```

### Item sizes

Items measure themselves by default. If they are all the same size, say so — it skips
measurement entirely.

```swift
.canvasItemSize(CGSize(width: 160, height: 160))
```

### A backdrop

```swift
.canvasBackground(.dots(spacing: 24))
.canvasBackground(.grid(spacing: 40, color: .blue.opacity(0.25)))
```

### Moving the viewport in code

`CanvasReader` and `CanvasProxy` work like `ScrollViewReader` and `ScrollViewProxy`.

```swift
CanvasReader { proxy in
    PannableCanvas(nodes) { NodeCard(node: $0) }
        .toolbar {
            Button("Reveal") { proxy.scrollTo(selection) }
            Button("Origin") { proxy.scrollTo(.zero, anchor: .topLeading) }
        }
}
```

### Watching the viewport

```swift
@State private var viewport = CanvasViewport()

PannableCanvas(nodes) { NodeCard(node: $0) }
    .canvasViewport($viewport)
    .overlay(alignment: .bottomTrailing) {
        MiniMap(visible: viewport.visibleRect, total: viewport.contentSize)
    }
```

### Behavior

```swift
.canvasScrollIndicators(.hidden)
.canvasBounce(.never)
.canvasScrollDisabled(true)
.canvasDeceleration(.fast)
```

### A custom layout

`CanvasLayout` is shaped after SwiftUI's `Layout`. Place items wherever is natural —
negative coordinates included — and the canvas normalizes and anchors the result.

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

### The core is pure Swift

Placement, anchoring, content sizing, and visibility culling contain no view machinery
at all — sizes go in, frames come out. The platform hosts sit on top and stay thin,
which is what keeps their behavior from drifting apart and what lets the hard parts be
tested without a simulator.

Layouts work on **sizes**, not on live subviews. That is the whole reason a canvas can
position ten thousand items without building ten thousand views: it knows where
everything goes before anything exists.

A layout emits a cluster at the origin and knows nothing about the canvas. The engine
then normalizes that cluster, mirrors it for right-to-left, resolves the content size,
and anchors it — so every layout gets RTL and anchoring correctly without handling
either itself.

### Only what you can see is built

Frames are bucketed into a uniform grid, so asking "what is inside this rectangle?"
costs time proportional to the visible area rather than to the data size. Every pan
event runs that query and hands the result to a recycling pool of hosting controllers.

Scroll callbacks do nothing else — no measurement, no allocation, no re-layout. Those
are deferred to the moments the canvas is at rest, which is what keeps a fling smooth.

### The platform hosts

| Platform | Built on |
|---|---|
| iOS / iPadOS | `UIScrollView` via a view controller representable, since every item is a `UIHostingController` and those need a parent to be contained by. `UIScrollViewDelegate` drives culling; `UIGestureRecognizerDelegate` adds pointer drag-to-pan, which a scroll view does not do on its own. |
| macOS | `NSScrollView` over a flipped document view. Clip-view bounds changes and the live-scroll notifications stand in for the scroll delegate callbacks. |
| watchOS | Neither type exists there, so it is pure SwiftUI driven by a drag gesture and the Digital Crown — over the same engine and the same culling. |

### Measuring items

| You set | What happens |
|---|---|
| `canvasItemSize(_:)` | Every item takes that size. Nothing is measured. |
| `canvasEstimatedItemSize(_:)` | Unmeasured items use this while real sizes are computed, then the layout settles once. |
| Neither | Items are measured against a default estimate. Fine for hundreds; set an estimate for thousands. |

Measurement happens off screen in chunks between run-loop turns, so a canvas over
thousands of items still shows something on the first frame. Sizes are cached by item
identity, so they survive reordering and insertion — only genuinely new items are
measured again.

### The backdrop

Drawn as a tiling pattern anchored to the canvas origin rather than into the content
view, because a content view large enough to hold the whole canvas would need a backing
store to match — at 6000×6000 on a 3× display, over a gigabyte. Tiling one small image
costs nothing to pan and nothing in memory whatever the canvas size.

### Accessibility

Because off-screen items are not in the view hierarchy, VoiceOver cannot swipe to them —
the same situation a table view is in. The three-finger scroll gesture pages the canvas
in all four directions, keeping a sliver of the previous screen so the user keeps their
bearings. Hosted views also state their accessibility order explicitly, since subviews
otherwise accumulate in recycle order rather than data order.

## Platform notes

- **watchOS** cannot measure a SwiftUI view off screen, so items there always take their
  size from `canvasItemSize(_:)` when set and `canvasEstimatedItemSize(_:)` otherwise.
- **macOS** bounce follows the system scroll elasticity; `canvasBounce(.never)` disables
  it, but `.always` behaves as `.automatic`.
- The backdrop is a rendered bitmap, so it is redrawn when the appearance changes rather
  than adapting on its own.
- Watching the viewport writes state on every frame of a pan, so keep whatever depends
  on it small. Multiple observers compose rather than replacing one another.

## Not yet implemented

Zoom is the notable gap — the coordinate math and scroll-delegate hooks are in place for
it, so it can arrive without an API break. Selection and drag-to-move, scroll snapping,
per-item explicit coordinates, and a freeform canvas are also still open.

## Tests

```bash
swift test
```

The layout engine, spatial index, sizing rules, backdrop geometry, and the update-loop
guard are all covered without a simulator, including randomized parity between the index
and a brute-force scan.
