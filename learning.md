# Pannable, explained

A walkthrough of this package for an iOS developer who knows SwiftUI and UIKit but
hasn't built an infinite-canvas component before. Every section says what the code
does, and then why it was written that way — the decisions are the point.

Read it top to bottom once. After that it works as a map.

---

## 0. What the thing actually is

`PannableCanvas` is a SwiftUI view that takes a collection, arranges the items on a
large 2D coordinate space, and lets you pan around it. Think Figma's canvas, Freeform,
a mind-map board, a photo wall.

```swift
PannableCanvas(stickers, contentSize: .fixed(width: 4000, height: 3000)) { sticker in
    StickerCard(sticker: sticker)
}
.canvasLayout(.flow(horizontalSpacing: 24, verticalSpacing: 24))
```

The hard requirement behind everything else: **10,000 items must not mean 10,000
views.** A `ScrollView` + `LazyVGrid` gets you laziness on one axis. Nothing in
SwiftUI gives you two-axis virtualization over an arbitrary layout. That gap is the
whole reason this package exists.

### The one-sentence mental model

> Compute where every item *would* go using only its **size**, index those rectangles
> spatially, and then build views for the handful of rectangles the viewport currently
> overlaps.

Everything in the codebase is a consequence of that sentence.

---

## 1. The shape of the codebase

```
Sources/Pannable/
├── Public/          ← the API surface. What users import and call.
│   ├── PannableCanvas.swift          the view itself
│   ├── PannableCanvas+Modifiers.swift  .canvasLayout(), .canvasItemSize(), …
│   ├── CanvasLayout.swift            the layout protocol
│   ├── Layouts/                      Flow + Grid implementations
│   ├── AnyCanvasLayout.swift         type erasure
│   ├── CanvasProxy.swift             CanvasReader / scrollTo
│   ├── CanvasViewport.swift          what's on screen right now
│   ├── CanvasContentSize.swift       automatic / fixed / atLeast
│   ├── CanvasBackground.swift        dots + grid backdrop
│   └── CanvasBehavior.swift          bounce, indicators, deceleration
│
├── Internal/        ← pure Swift. No UIKit, no AppKit, no SwiftUI views.
│   ├── Layout/LayoutEngine.swift     sizes → frames. The brain.
│   ├── Index/SpatialIndex.swift      "what's in this rect?" in sub-linear time
│   ├── Model/SizeCache.swift         measured sizes keyed by identity
│   ├── Model/CanvasItemSource.swift  type-erased data access
│   ├── Model/CanvasConfiguration.swift  every knob, in one Equatable value
│   └── Environment/                  environment keys + plumbing
│
└── Platform/        ← the three hosts, plus what they share
    ├── Shared/CanvasEngine.swift     the state machine all hosts drive
    ├── Shared/ViewportPublisher.swift  the loop guard (see §9)
    ├── UIKit/                        UIScrollView host
    ├── AppKit/                       NSScrollView host
    └── Watch/                        pure-SwiftUI host
```

**The decision to notice here is the `Internal/` boundary.** The layout engine and
the spatial index import `CoreGraphics` and nothing else. They take `[CGSize]` and
hand back `[CGRect]`. They cannot touch a view even by accident, because the types
aren't in scope.

Two payoffs:

1. **Tests run in seconds with no simulator.** `swift test` exercises anchoring,
   margins, RTL mirroring, culling and the size cache as plain function calls.
2. **The three platforms can't drift.** iOS, macOS and watchOS are genuinely
   different underneath — `UIScrollView`, `NSScrollView`, and a `DragGesture`. If
   each host owned its own layout math, they'd disagree within a month. They own only
   the plumbing; the math has one implementation.

> **Transferable lesson.** When a component has a hard part and a platform part,
> separate them physically, not just mentally. A directory boundary is enforced by
> the compiler. A convention isn't.

---

## 2. Layouts run on sizes, not views

This is the load-bearing idea. Start with the protocol:

```swift
public protocol CanvasLayout: Equatable, Sendable {
    associatedtype Cache = Void
    func makeCache(itemCount: Int) -> Cache
    func updateCache(_ cache: inout Cache, itemCount: Int)
    func place(_ items: CanvasLayoutItems, in proposal: CanvasProposal, cache: inout Cache) -> CanvasLayoutResult
}
```

If that looks familiar, it should — it's deliberately shaped like SwiftUI's `Layout`
protocol (`makeCache`, `sizeThatFits`, `placeSubviews`). **Mirroring a system API you
already know is a real design decision**, not laziness. It buys you an API your users
have already half-learned.

But there's a critical difference. SwiftUI's `Layout` receives `Layout.Subviews` —
live, instantiated views you can measure and place. `CanvasLayout` receives
`CanvasLayoutItems`, which is just:

```swift
public struct CanvasLayoutItem { var index: Int; var size: CGSize }
```

An index and a size. No view. **That substitution is what makes virtualization
possible.** SwiftUI's `Layout` cannot be lazy, because it holds proxies to views that
must exist. Working on sizes means the canvas knows the position of item #9,847
before any view for it has ever been created.

### Details worth understanding

**`associatedtype Cache = Void` plus a constrained extension.**

```swift
extension CanvasLayout where Cache == Void {
    public func makeCache(itemCount: Int) -> Void { () }
}
extension CanvasLayout {
    public func updateCache(_ cache: inout Cache, itemCount: Int) {}
}
```

The default associated type means a simple layout writes only `place(_:in:cache:)`
and gets the other two free. A layout that *does* need expensive precomputation
declares `typealias Cache = MyThing` and the defaults stop applying. This is the
standard Swift technique for "optional protocol requirements" — a default associated
type plus a constrained extension — and it's worth stealing.

**`CanvasProposal` uses `CGFloat?`, where `nil` means unbounded.** Same convention as
SwiftUI's `ProposedViewSize`. It matters because `.automatic` content sizing proposes
no width at all, and a flow layout has to cope. `FlowCanvasLayout` handles it by
falling back to a heuristic:

```swift
let totalArea = items.reduce(.zero) { $0 + (w + hSpacing) * (h + vSpacing) }
return max(totalArea.squareRoot(), widest)
```

Take the total area, take its square root, wrap at that width — which yields a
roughly square cluster instead of one infinitely long row. Not exact. Nothing here
needs to be exact; it needs to not be absurd.

**Static member lookup for call-site sugar.**

```swift
extension CanvasLayout where Self == FlowCanvasLayout {
    public static var flow: FlowCanvasLayout { FlowCanvasLayout() }
    public static func flow(horizontalSpacing: CGFloat = 8, …) -> FlowCanvasLayout { … }
}
```

That `where Self == ConcreteType` extension is how `.flow` and `.grid(columns: 6)`
work at the call site instead of `FlowCanvasLayout()`. It's how `.blue`,
`.roundedRectangle`, and `.automatic` work throughout Apple's frameworks. Users of
your package can add their own with the same three lines — see the `RingCanvasLayout`
in [Previews.swift](Sources/Pannable/Previews.swift), which extends the protocol from
outside the package and reads identically to the built-ins. That's the test of
whether an extension point is real.

---

## 3. The layout engine: normalize, mirror, size, anchor

[LayoutEngine.swift](Sources/Pannable/Internal/Layout/LayoutEngine.swift) is ~130
lines and is the most valuable file to read closely. Its contract:

> A layout returns a **cluster of frames in its own coordinate space**. The engine
> turns that into **frames in canvas coordinates**.

The pipeline:

### Step 0 — sanitize

```swift
let sizes = sizes.map(\.canvasSanitized)   // NaN/∞/negative → 0
```

A SwiftUI view that hasn't settled can report `NaN` or `.infinity` from
`sizeThatFits`. If that reaches `CGRect` math it silently poisons *every* downstream
frame — unions become `NaN`, the spatial index's grid math produces `Int(NaN)` which
traps, and you get a crash three files away from the cause. One `map` at the entrance
is much cheaper than debugging that.

> **Lesson.** Sanitize untrusted floats at the boundary of a numeric subsystem, not
> at the point of use. Same instinct as validating JSON at the decode site.

### Step 1 — normalize to origin

A layout may place items anywhere, negative coordinates included (the ring layout
puts things at `-700`). The engine takes the union of all frames and shifts the whole
cluster so its top-left sits at `(0, 0)`.

**Why let layouts use negative coordinates at all?** Because forcing every layout to
be origin-relative pushes bookkeeping into every implementation. A ring is naturally
centred on zero. A radial tree is naturally centred on its root. Normalizing once, in
one place, means layout authors get to write the math that's natural to their layout.

### Step 2 — mirror for right-to-left

```swift
guard isRightToLeft else { return normalized }
return CGRect(x: clusterSize.width - normalized.maxX, y: ..., ...)
```

Every layout gets full RTL support, and **no layout contains a single line of RTL
code.** Mirroring the finished cluster is equivalent to mirroring the algorithm, and
it's one branch instead of N implementations that each have to be reviewed for it.

Note the related subtlety a few lines above:

```swift
let leftInset  = isRightToLeft ? margins.trailing : margins.leading
let rightInset = isRightToLeft ? margins.leading  : margins.trailing
```

`EdgeInsets` uses `leading`/`trailing`, which are *sides*, not *edges*. The moment you
convert to absolute geometry you have to resolve them against the layout direction.
This bug is extremely common and invisible until someone runs your app in Arabic.

### Step 3 — resolve the content size

```swift
case .automatic:      hugging                       // canvas hugs its content
case .fixed(let s):   s                             // canvas is exactly this
case .atLeast(let s): max(floor, hugging)           // canvas is at least this
```

Three modes, because three genuinely different intentions exist: "size to fit",
"I want a 4000×3000 board", and "at least a screenful, but grow if needed."

### Step 4 — anchor the cluster

```swift
let origin = CGPoint(
    x: leftInset  + max(0, available.width  - clusterSize.width)  * anchorX,
    y: margins.top + max(0, available.height - clusterSize.height) * anchorY
)
```

Slack space × anchor fraction. `UnitPoint.center` is `(0.5, 0.5)`, so half the slack
goes before the cluster. Standard.

**The `max(0, …)` is the interesting decision.** When the cluster is *larger* than a
fixed canvas, the slack goes negative. Without clamping, a `.center` anchor would
push content to negative coordinates — off the leading edge, where **no amount of
panning can reach it**, because a scroll view's minimum offset is zero. Clamping
means the overflow spills off the far edge instead, where you *can* pan to it. Data
loss versus a visible overflow: pick the visible overflow, every time.

Two distinct anchors exist, and confusing them is easy:

| Modifier | Controls |
|---|---|
| `.canvasContentAnchor(.center)` | where the **items** sit inside the canvas |
| `.canvasInitialAnchor(.center)` | where the **viewport** opens on the canvas |

You can pack items in the corner and still open the viewport in the middle.

---

## 4. Culling: the spatial index

Every scroll event needs the answer to "which items intersect this rectangle?"

The naive version is `frames.filter { $0.intersects(rect) }` — O(n) per frame. At 120
Hz with 10,000 items that's 1.2 million rect intersections per second just to decide
what to draw. Fine at a hundred items. Ruinous at ten thousand.

[SpatialIndex.swift](Sources/Pannable/Internal/Index/SpatialIndex.swift) is a
**uniform grid**: chop the bounding box into cells, drop each frame into every cell it
touches, and answer a query by visiting only the cells the query rect covers.

```
┌────┬────┬────┬────┐
│    │ ▣  │ ▣▣ │    │      query rect covers 4 cells
├────┼──╔═╪════╪═╗──┤  →   union their contents (a few dozen items)
│ ▣  │  ║ │ ▣  │ ║  │  →   exact intersects() test on those
├────┼──╚═╪════╪═╝──┤
│    │    │  ▣ │ ▣  │      the other 9,950 items are never touched
└────┴────┴────┴────┘
```

Query cost becomes proportional to **visible area**, not to data size. That's the
whole trick, and it's the same family of structure as a quadtree or an R-tree — just
the flat, cache-friendly, no-rebalancing member of the family, which is the right
pick when your data is roughly uniformly sized (which laid-out UI items are).

### Four tuning decisions, all defensive

```swift
var cellWidth = clampExtent(median(of: widths) * 2)
```

**1. Size cells off the *median* item, doubled.** Cells that are too small mean a
query touches hundreds of cells. Cells too large mean each cell holds too many items
and you're back to a linear scan. Roughly 2× the typical item keeps the average item
in one or two buckets. The **median** rather than the mean is a deliberate choice: one
giant item shouldn't drag the whole grid coarse.

**2. Clamp cell size to `64...2048`.** Guards both degenerate ends.

**3. Cap total buckets at 65,536.** Scattered items (say, ten items spread over
100,000 points) would otherwise allocate a vast, mostly-empty grid. If the count
overshoots, cells are scaled by `sqrt(overshoot)` and recomputed.

**4. Dedupe, then test exactly.** An item spanning four cells appears in all four, so
candidates go through a `Set` before the real `intersects` test. The grid is a
*filter*, not the answer — it narrows the candidate set, and exact geometry decides.

### The detail that isn't about performance

```swift
return candidates.filter { frames[$0].intersects(rect) }.sorted()
```

That `.sorted()` looks like a wasted allocation. It isn't. Results come back in **data
order**, and the recycler feeds that ordering straight into
`container.accessibilityElements`. Without it, VoiceOver reads your canvas in
*hosting-controller-recycle order*, which is effectively random. A sort per scroll
event is a rounding error; an unusable screen reader experience is not.

### How it's tested

[SpatialIndexTests.swift](Tests/PannableTests/SpatialIndexTests.swift) fuzzes it: 600
randomly placed rects, 200 random queries, compared against brute force —
`frames.indices.filter { $0.intersects(rect) }.sorted()` — with a **seeded** PRNG so
any failure reproduces exactly.

> **Lesson.** When you replace an obviously-correct slow algorithm with a clever fast
> one, keep the slow one in the test target and assert they agree. This is
> property-based testing, and it is the highest-value-per-line test you can write.

---

## 5. Measurement: the estimated-size dance

Layouts need sizes. Where do sizes come from?

Three cases, in [CanvasEngine.resolve()](Sources/Pannable/Platform/Shared/CanvasEngine.swift):

| You set | What happens |
|---|---|
| `.canvasItemSize(_:)` | Every item uses it. **Nothing is ever measured.** |
| `.canvasEstimatedItemSize(_:)` | Estimate now, real measurement later, one reflow. |
| Neither | A 120×120 default estimate. Fine for hundreds. |

If you recognise this as `UITableView.estimatedRowHeight`, you've got it exactly. The
problem is identical: you must produce a scrollable content size *before* you can
afford to measure everything, so you guess, show something, and correct.

### Measuring without blocking the first frame

```swift
private func scheduleMeasurementIfNeeded() {
    guard engine.hasPendingMeasurement, !isMeasurementScheduled else { return }
    isMeasurementScheduled = true
    DispatchQueue.main.async { [weak self] in
        …
        guard !self.scrollView.isDragging, !self.scrollView.isDecelerating else {
            self.scheduleMeasurementIfNeeded()   // try again later
            return
        }
        let finished = self.engine.measureNextChunk { … }
        if finished { self.resolveAndApplyLayout() }   // one settle, at the end
        else        { self.scheduleMeasurementIfNeeded() }
    }
}
```

Four decisions stacked in twenty lines:

1. **Chunked at 200 items per pass**, hopping through `DispatchQueue.main.async`
   between chunks. Measuring 5,000 items in one go blocks the main thread for a
   visible beat. Chunking yields the run loop between batches, so the canvas paints
   immediately and fills in.
2. **Yields entirely while the canvas is moving.** Measurement is the single most
   expensive thing this component does, and doing it mid-fling competes with the
   frames the user is watching. It reschedules and resumes at rest.
3. **One reflow at the end, not per chunk.** Re-resolving after each of 25 chunks
   would make content visibly shuffle 25 times while it loads.
4. **`[weak self]`** — a scheduled block must not keep a dismissed view controller
   alive.

### Two clamps that prevent real bugs

```swift
private static var maximumMeasuredExtent: CGFloat { 10_000 }
```

A view with no intrinsic size — a bare `Color`, a `Rectangle` — reports *whatever it
was proposed*. Measurement proposes `.greatestFiniteMagnitude` for height. So an
unclamped `Color.red` item reports a height of ~1.8 × 10³⁰⁸, and your canvas's
content size is now nonsense. Clamp it.

```swift
private var proposedItemWidth: CGFloat? { LayoutEngine.proposal(for: …).width }
```

Items are measured against the canvas's **usable width**, not against infinity.
Without this, every `Text` reports a single enormous unwrapped line. With it, text
wraps the way it will actually render.

### The size cache is keyed by identity, not index

```swift
struct SizeCache { private var storage: [AnyHashable: CGSize] }
```

Key by index and every insertion, deletion or reorder invalidates everything below
the change. Key by identity and a reorder costs nothing — only genuinely new items get
measured. This is exactly why `ForEach` demands identity, and exactly why
`PannableCanvas` mirrors `ForEach`'s three initializers (`Identifiable`, key path,
constant `Range<Int>`).

`retain(_:)` prunes entries for items no longer in the data, so a long-lived canvas
over changing data can't leak. And `invalidateMeasurements()` drops everything at
once — called from `traitCollectionDidChange` when **Dynamic Type** changes, because
every text measurement taken at the old size is now wrong.

### One measurer, parented for a reason

```swift
final class ItemMeasurer<Content: View> {
    private let controller = UIHostingController<Content?>(rootView: nil)
    init(parent: UIViewController) {
        parent.addChild(controller)
        controller.view.isHidden = true
        parent.view.addSubview(controller.view)
        controller.didMove(toParent: parent)
    }
}
```

**One** hosting controller, reused for every measurement — creating one per item
would cost more than the measurement. And it is **parented and in the hierarchy**
rather than free-floating, because a detached hosting controller has the *default*
trait collection. Measure at default Dynamic Type, lay out at the user's Dynamic
Type, and every frame is subtly wrong for anyone who's changed their text size.

---

## 6. Recycling hosting controllers

[HostRecycler.swift](Sources/Pannable/Platform/UIKit/HostRecycler.swift) is
`UITableView`'s reuse pool, rebuilt for SwiftUI content.

```swift
private var active: [Int: UIHostingController<Content?>] = [:]
private var pool:   [UIHostingController<Content?>] = []

func setVisible(_ positions: [Int], content: (Int) -> Content, frame: (Int) -> CGRect?) {
    let wanted = Set(positions)
    for position in active.keys where !wanted.contains(position) { recycle(position) }
    for position in positions {
        if let host = active[position] { host.view.frame = frame }   // already on screen
        else { let host = dequeue(); host.rootView = content(position); … }
    }
    container.accessibilityElements = positions.compactMap { active[$0]?.view }
}
```

### Why pooling at all

`UIHostingController` is not cheap to create. A canvas panned across a large data set
would otherwise construct and destroy them continuously, and you'd feel it.

### The decision that makes reuse cheap

Pooled controllers **stay children of the canvas's view controller for their entire
lifetime.** Only their *views* enter and leave the content view, and only their
`rootView` changes.

```swift
private func recycle(_ position: Int) {
    host.view.removeFromSuperview()
    host.rootView = nil      // release whatever the item's view held
    pool.append(host)
}
```

Proper view-controller containment (`addChild` / `didMove(toParent:)` /
`willMove(toParent: nil)` / `removeFromParent`) is real work and involves appearance
callbacks. Skipping it on every recycle turns reuse into a single property
assignment. Setting `rootView = nil` — note the `Content?` generic parameter, which
exists purely to make `nil` expressible — releases whatever the item's view was
retaining, so a recycled controller doesn't pin an image in memory.

### `refreshContent` and the identity/content distinction

```swift
func refreshContent(_ content: (Int) -> Content) {
    for (position, host) in active { host.rootView = content(position) }
}
```

An item's **identity** can survive a data change while its **content** does not — the
same note, retitled. When the update pass decides no relayout is needed, it still
refreshes every visible root view. SwiftUI diffs old against new, so this is cheap
when nothing actually changed. Skipping it would render items from a stale snapshot.

The same reasoning explains this comment in `CanvasEngine.update`:

```swift
// The content closure captures the caller's data, so it must be replaced on
// every pass even when nothing about identity changed.
source = newSource
```

The closure has the user's array captured inside it. A stale closure means stale
pixels.

### A small Swift point

`for position in active.keys where … { recycle(position) }` mutates `active` inside a
loop over `active.keys`. That's safe here: the `for-in` evaluates `active.keys` once,
which retains the current storage; `removeValue` then triggers copy-on-write, so the
loop iterates a stable snapshot. Worth understanding rather than cargo-culting — the
equivalent with a class-based collection would be a crash.

---

## 7. Bridging into SwiftUI

### Why a view *controller* representable

```swift
struct CanvasRepresentable<Content: View>: UIViewControllerRepresentable { … }
```

`UIViewRepresentable` would be simpler. It's wrong here: every item on the canvas is a
`UIHostingController`, and hosting controllers need a **parent view controller**.
Without proper containment their trait collection, safe-area insets, and appearance
callbacks are all subtly wrong — which is exactly the bug class that makes Dynamic
Type or dark mode misbehave only in your custom container.

> **Rule of thumb.** If your representable will contain hosting controllers, it must
> be a `UIViewControllerRepresentable`.

The lifecycle you're implementing:

- `makeUIViewController` — called **once**. Build it.
- `updateUIViewController` — called on **every** SwiftUI update pass. Diff and apply.

`updateUIViewController` is hot. Doing unconditional work there is the classic
performance trap, which leads to the next two sections.

### `CanvasItemSource`: erase some generics, keep one

```swift
struct CanvasItemSource<Content: View> {
    var ids: [AnyHashable]
    var content: (Int) -> Content
}
```

`PannableCanvas` is generic over `<Data, ID, Content>` — three parameters. The
platform hosts take `CanvasItemSource<Content>` — one. `Data` and `ID` are flattened
into `[AnyHashable]` plus a closure, so `CanvasViewController` doesn't need to be
generic over the user's collection type.

**But `Content` deliberately stays generic.** Erasing it through `AnyView` would cost
a boxed allocation per item on every update pass, and would defeat SwiftUI's
structural diffing. This is the general trade: erase what only needs to be *compared*
(identity), keep concrete what needs to be *rendered* (views).

### Configuration through the environment, not the initializer

```swift
public func canvasLayout(_ layout: some CanvasLayout) -> some View {
    environment(\.canvasLayout, AnyCanvasLayout(layout))
}
```

Every knob is an environment value, applied by a modifier. The alternative — twelve
parameters on `init` — would be miserable, and more importantly it wouldn't
**cascade**. Because these are environment values, an ancestor can configure a canvas
buried anywhere beneath it, exactly the way `.listStyle` and `.buttonStyle` work.
Users already understand the idiom.

### One `Equatable` value, two kinds of change

```swift
struct CanvasConfiguration: Equatable {
    var layout: AnyCanvasLayout; var contentSize: CanvasContentSize; …

    func invalidatesLayout(comparedTo other: CanvasConfiguration) -> Bool {
        layout != other.layout || contentSize != other.contentSize
            || contentAnchor != other.contentAnchor || margins != other.margins
            || itemSize != other.itemSize || estimatedItemSize != other.estimatedItemSize
            || layoutDirection != other.layoutDirection
    }
}
```

Every knob is gathered into one comparable value, and changes are sorted into two
buckets:

- **Layout-invalidating** — layout, margins, sizes, direction. Requires the full
  pipeline: resolve → rebuild the index → recycle everything.
- **Behaviour-only** — bounce, scroll indicators, deceleration, backdrop. Requires
  poking a few `UIScrollView` properties.

```swift
let outcome = engine.update(source: source, configuration: configuration)
if outcome.needsBehaviorUpdate { applyBehavior() }
if outcome.needsLayout { recycler.recycleAll(); resolveAndApplyLayout() }
else { recycler.refreshContent(engine.content(at:)) }
```

Toggling `.canvasScrollIndicators(.hidden)` must not trigger a full re-layout of
10,000 items. Making the distinction explicit and testable, rather than implicit in a
tangle of `if` statements, is the difference between a component that stays fast and
one that mysteriously doesn't.

> **Lesson.** When a component has many inputs, model them as *one* `Equatable` value
> and write an explicit predicate for what a change actually costs.

---

## 8. `CanvasReader` and `CanvasProxy`: the environment handshake

This is how `ScrollViewReader` works internally, and it's worth learning because the
pattern solves a genuine chicken-and-egg problem.

```swift
CanvasReader { proxy in
    PannableCanvas(nodes) { NodeCard(node: $0) }
        .toolbar { Button("Reveal") { proxy.scrollTo(selection) } }
}
```

The closure receives a `proxy` for a canvas **that doesn't exist yet** — the canvas is
created *by* the closure. So the proxy can't hold the canvas. It holds an indirection:

```swift
public struct CanvasReader<Content: View>: View {
    @StateObject private var connection = CanvasConnection()
    public var body: some View {
        content(CanvasProxy(connection: connection))
            .environment(\.canvasConnection, connection)
    }
}

final class CanvasConnection: ObservableObject {
    weak var host: (any CanvasHostControlling)?
    @Published var viewport = CanvasViewport()
}
```

1. The reader creates an empty `CanvasConnection` and puts it in the environment.
2. It hands a proxy wrapping that same connection to the closure.
3. The canvas, built inside the closure, reads the connection out of the environment
   and registers itself as `connection.host`.
4. `proxy.scrollTo(…)` forwards through `connection.host`, which by then is real.

Three details:

**`weak var host`.** The connection outlives any particular view controller. A strong
reference would keep a dismissed canvas alive forever.

**The host registers on `viewDidAppear`, not on `init`.** SwiftUI can construct more
than one host for a given canvas (during transitions, in a `TabView`, on state
churn), and only the one actually on screen has a viewport worth reporting.
Symmetrically, on disappear:

```swift
if connection?.host === self { connection?.host = nil }
```

Only surrender the connection if you still hold it — a newly appeared host may have
taken over already. Identity comparison (`===`) rather than a bare nil-out. This is
the kind of ordering bug that shows up once a month in production and never in
testing.

**The protocol is deliberately tiny.**

```swift
@MainActor protocol CanvasHostControlling: AnyObject {
    func scrollTo(rect: CGRect, anchor: UnitPoint, animated: Bool)
    func frame(forItemWith id: AnyHashable) -> CGRect?
    var currentViewport: CanvasViewport { get }
}
```

Three requirements. A `UIScrollView`, an `NSScrollView` and a SwiftUI `@Published`
offset can all answer them, so `CanvasProxy` is written once and works everywhere.
The narrower the protocol, the more implementations it fits.

### Reporting the viewport *up* the tree

The viewport needs to travel from the canvas to an ancestor. The environment flows
*down*. `PreferenceKey` flows up — and is the wrong tool here:

> A preference would flow the right direction but would push a view update through
> the whole ancestor chain on every frame of a fling.

So instead, a **closure** is passed down through the environment, and the canvas calls
it. The cost lands only on whoever asked.

That creates a new problem: environment values overwrite. Two observers means the
second silently wins. The fix is a modifier that **composes** rather than replaces:

```swift
private struct CanvasViewportActionModifier: ViewModifier {
    @Environment(\.canvasViewportAction) private var existing
    func body(content: Content) -> some View {
        content.environment(\.canvasViewportAction, CanvasViewportAction { [existing, action] viewport in
            existing?.handler(viewport)   // chain onto whatever was already in scope
            action(viewport)
        })
    }
}
```

Read the existing value, wrap it, install the wrapper. Now `.canvasViewport($binding)`
and `.onCanvasViewportChange { … }` can both be applied and both fire. **Composing
environment values by chaining is a genuinely useful trick** — reach for it any time
"last one wins" is the wrong semantic.

---

## 9. The bug worth studying: the update loop

Read the header of
[ViewportPublisher.swift](Sources/Pannable/Platform/Shared/ViewportPublisher.swift).
The fix has its own commit, `84fbd15` — *"Stop the canvas driving itself in an
update loop."*

The cycle:

```
scroll event
   → publish viewport
   → writes SwiftUI state (a @Binding or the connection's @Published)
   → SwiftUI re-evaluates body
   → calls updateUIViewController
   → host updates, publishes viewport again
   → writes state again
   → ⟳ forever
```

Result: the canvas spins in an unbounded update loop and **stops responding to input
entirely.** Not a dropped frame — a hang.

The fix is nine lines:

```swift
struct ViewportPublisher {
    private var lastPublished: CanvasViewport?
    mutating func shouldPublish(_ viewport: CanvasViewport) -> Bool {
        guard viewport != lastPublished else { return false }
        lastPublished = viewport
        return true
    }
}
```

Three things about this are worth internalising.

**1. It is correctness, not optimisation.** The doc comment says so explicitly, and
it matters — someone doing a cleanup pass will delete a "redundant equality check"
that has no test around it. It has tests around it.

**2. It is extracted into a shared struct.** All three hosts could have kept a
`lastViewport` property. Extracting it means the invariant is stated **once**, and
`ViewportPublisherTests` can verify it with no view hierarchy at all — including a
parameterised test asserting that *every field* of `CanvasViewport` participates in
the comparison, so a future field addition can't silently break the guard.

**3. This is the defining hazard of UIKit↔SwiftUI bridging.** Any representable that
writes SwiftUI state from a delegate callback has this shape. The general rule:

> **Never write SwiftUI state unconditionally from a callback that SwiftUI can
> trigger. Always compare first.**

---

## 10. Type erasure, and the `Equatable` trick

`AnyCanvasLayout` exists because environment values need a **concrete** type — you
can't store `any CanvasLayout` in an `EnvironmentKey` and still get `Equatable`.

```swift
public struct AnyCanvasLayout: CanvasLayout {
    private let base: any CanvasLayout
    private let _place: @Sendable (CanvasLayoutItems, CanvasProposal) -> CanvasLayoutResult

    public init<L: CanvasLayout>(_ layout: L) {
        if let erased = layout as? AnyCanvasLayout { self = erased; return }  // don't nest
        self.base = layout
        self._place = { items, proposal in
            var cache = layout.makeCache(itemCount: items.count)
            layout.updateCache(&cache, itemCount: items.count)
            return layout.place(items, in: proposal, cache: &cache)
        }
    }
}
```

The standard recipe: capture the concrete value in a closure that has the generics
already resolved. The cache is created inside the closure because `Cache` is an
associated type and can't survive erasure.

The **`==` implementation** is the part most people haven't seen:

```swift
public static func == (lhs: AnyCanvasLayout, rhs: AnyCanvasLayout) -> Bool {
    func isEqual<L: CanvasLayout>(_ lhsBase: L) -> Bool {
        guard let rhsBase = rhs.base as? L else { return false }
        return lhsBase == rhsBase
    }
    return isEqual(lhs.base)
}
```

You cannot write `lhs.base == rhs.base` — `Equatable` has a `Self` requirement, so an
existential can't satisfy it. Calling a **generic function with an existential
argument** opens the box and binds `L` to the concrete type; inside, `==` is available
because `L: CanvasLayout: Equatable`. This is "opening an existential," and it's the
standard workaround. Swift 5.7+ does some of this implicitly, but the explicit form
is clearer and works everywhere.

Why it matters here: without a real `==`, every environment update would look like a
layout change, and every layout change triggers a full re-resolve of every frame.

---

## 11. Three platforms, one behaviour

| Platform | Built on | Scroll signal |
|---|---|---|
| iOS / iPadOS | `UIScrollView` in a `UIViewControllerRepresentable` | `UIScrollViewDelegate` |
| macOS | `NSScrollView` over a **flipped** document view | `NSNotification` (clip-view bounds + live scroll) |
| watchOS | Pure SwiftUI: `ZStack` + `.offset` | `DragGesture` + Digital Crown |

Same `CanvasEngine`, same `SpatialIndex`, same `LayoutEngine`. Only the plumbing
differs.

### The generic-class / `@objc`-protocol constraint

```swift
final class CanvasScrollCoordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var handler: (any CanvasScrollHandling)?
}
```

Why isn't `CanvasViewController<Content>` its own delegate? Because **Swift forbids a
generic class from conforming to an `@objc` protocol in an extension**. And there's a
second benefit noted in the source: the coordinator is non-generic, so there's *one*
of it rather than one per `Content` specialization. The bridge is a plain Swift
protocol (`CanvasScrollHandling`) that the generic controller adopts in an extension —
which *is* allowed, because that protocol isn't `@objc`.

> **Lesson.** When Objective-C interop and generics collide, put the `@objc`
> conformance on a small non-generic class and route back through a Swift protocol.

### Scroll callbacks do almost nothing

```swift
func scrollViewDidScroll(_ scrollView: UIScrollView) { handler?.canvasDidScroll() }
```

…which is one index query and a frame assignment per visible item. No measuring, no
allocation, no re-layout. Everything expensive is deferred to `canvasMotionChanged(isAtRest: true)`.
**This is the entire secret to a smooth fling**, and it's a discipline, not a
technique — it only survives if you keep enforcing it.

### Pointer drag-to-pan

A scroll view handles the wheel and two-finger trackpad scrolling. It does **not**
handle dragging the canvas with a mouse — which on iPad and macOS is the first thing
anyone tries on a canvas. So a `UIPanGestureRecognizer` restricted to
`.indirectPointer` touches is added, with three delegate methods doing real work:

```swift
recognizer.setTranslation(.zero, in: scrollView)   // consume each pass, so deltas accumulate
```

- `gestureRecognizerShouldBegin` — refuse if there's nowhere to pan.
- `shouldRecognizeSimultaneouslyWith` — run alongside the scroll view's own pan, so
  trackpad scrolling keeps working during a pointer drag.
- `shouldReceive touch:` — walk up the view hierarchy from the touched view; if it
  passes through a `UIControl`, the drag belongs to that control, not the canvas.

That last one is the difference between "I can drag the canvas" and "I can't press
the buttons on my canvas."

Also note:

```swift
scrollView.contentInsetAdjustmentBehavior = .never
scrollView.panGestureRecognizer.allowedScrollTypesMask = .all
```

The first stops UIKit shifting the coordinate space out from under a canvas that
positions everything itself. The second makes two-finger trackpad swipes pan on iPad
instead of moving the pointer.

### macOS specifics

`NSScrollView` has no delegate, so the coordinator subscribes to notifications —
`boundsDidChangeNotification` stands in for `scrollViewDidScroll`, and
`willStartLiveScroll` / `didEndLiveScroll` give the same began/ended pair that lets
measurement be deferred exactly as on iOS.

And the document view is **flipped**:

```swift
final class FlippedCanvasContentView: NSView { override var isFlipped: Bool { true } }
```

AppKit's origin is bottom-left. Flipping it means canvas coordinates mean the same
thing on all three platforms, so the shared engine's output is used verbatim rather
than mirrored on macOS alone. One override instead of a conditional in every
coordinate calculation.

### watchOS

No `UIScrollView`, no `UIHostingController`. So: a `ZStack` of `.offset` views, a
`DragGesture`, and `.digitalCrownRotation` on the vertical axis. Culling still comes
from the same `SpatialIndex` — only the *transport* changed.

Two details worth stealing:

```swift
@State private var dragAnchor: CGPoint?
let base = dragAnchor ?? controller.origin
controller.setOrigin(CGPoint(x: base.x - value.translation.width, …))
```

`DragGesture.translation` is cumulative from the gesture's start, so you must apply it
to a **fixed base captured at `onChanged` first fire**, not to the current origin —
otherwise every frame compounds and the canvas rockets away.

```swift
.canvasOnChange(of: crownPosition) { position in
    guard dragAnchor == nil else { return }   // ignore the echo from our own drag
    controller.setOrigin(…)
}
```

The drag writes `crownPosition` to keep the crown in sync, which fires the crown's
`onChange`, which would move the canvas again. A one-line guard breaks the feedback
loop — the same class of bug as §9, in miniature.

---

## 12. The backdrop: why it's a pattern, not a drawing

The naive implementation draws dots into the content view. Do the arithmetic:

> A 6000 × 6000 point content view on a 3× display needs
> `18000 × 18000 × 4 bytes` ≈ **1.2 GB** of backing store.

That's an instant jetsam kill. The fix is a **tiling pattern colour**:

```swift
let image = UIGraphicsImageRenderer(size: tile, format: format).image { context in
    drawTile(in: context.cgContext, size: tileSize, resolvedColor: resolved)
}
return UIColor(patternImage: image)   // e.g. a single 24×24 tile
```

Core Graphics repeats one small tile across an arbitrarily large area at effectively
zero cost, in constant memory.

Two geometry decisions live in `CanvasBackground.tileShapes(size:)`, shared by all
three platforms and unit-tested:

- A **dot** is drawn at the *centre* of its tile, so it's never clipped at a tile
  seam.
- A **grid** tile draws only its top edge and its left edge; neighbouring tiles
  complete the lines. Drawing all four would double-draw every interior line.

Platform specifics:

- **macOS** sets `context.patternPhase = convert(NSPoint.zero, to: nil)` in `draw(_:)`.
  Pattern phase is window-relative by default; anchoring it to the view's own origin
  keeps the pattern fixed to *canvas* coordinates while you pan.
- **watchOS** has no pattern colour, so `Canvas` draws tiles directly — but only over
  the viewport, phase-shifted by `origin.truncatingRemainder(dividingBy: tile)`,
  starting one tile early so a partially-scrolled tile doesn't pop in.

**The cost of the choice**, and it's a real one: a bitmap can't adapt to appearance
changes. So both hosts explicitly redraw:

```swift
if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle
    || previous?.displayScale != traitCollection.displayScale { applyBackground() }
```

and on macOS, `viewDidChangeEffectiveAppearance()`. If you bake a dynamic colour into
a bitmap, you own its lifecycle.

---

## 13. Accessibility under virtualization

Virtualization creates an accessibility problem that's easy to ship without noticing:
**items outside the viewport aren't in the view hierarchy, so VoiceOver can't swipe to
them.** They don't exist.

`UITableView` has exactly this problem and solves it the same way — the three-finger
scroll gesture pages the content. The default implementation only handles the
vertical axis, and a canvas needs four directions:

```swift
override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
    let page = CGSize(width: bounds.width * 0.85, height: bounds.height * 0.85)
    …
    guard clamped != contentOffset else { return false }   // at the edge
    setContentOffset(clamped, animated: false)
    UIAccessibility.post(notification: .pageScrolled, argument: nil)
    return true
}
```

- **15% overlap** between pages, so the user keeps their bearings.
- **Returning `false` at the edge** is what makes VoiceOver announce the boundary.
  Silently doing nothing leaves the user stuck with no feedback.
- **Posting `.pageScrolled`** is what makes VoiceOver read the new content.

And the ordering fix mentioned back in §4:

```swift
container.accessibilityElements = positions.compactMap { active[$0]?.view }
```

Subviews accumulate in *recycle* order. Stating the accessibility order explicitly is
what makes VoiceOver read items in the order the data declares them.

---

## 14. Swift 6 concurrency, in practice

The package builds under `swiftLanguageModes: [.v6]`, i.e. full strict concurrency
checking. Here's what that forced, and why.

**Value types are `Sendable`; UI types are `@MainActor`.**

```swift
public struct CanvasViewport: Equatable, Sendable { … }
public protocol CanvasLayout: Equatable, Sendable { … }

@MainActor public struct PannableCanvas<…>: View { … }
@MainActor final class CanvasEngine<Content: View> { … }
```

The pure-data half of the package crosses actor boundaries freely. The view half is
pinned to the main actor. That split falls out naturally from the `Internal/` vs
`Platform/` structure — which is a good sign that the structure was right.

**`@preconcurrency` on an `EnvironmentKey` conformance:**

```swift
private struct CanvasConnectionKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: CanvasConnection? = nil
}
```

`EnvironmentKey.defaultValue` is a non-isolated static requirement, but the value's
type is main-actor bound. `@preconcurrency` on the *conformance* downgrades that
mismatch to a warning-free compile. This exact pattern comes up constantly when
adopting Swift 6 against pre-concurrency framework protocols.

**`nonisolated init()`:**

```swift
final class CanvasConnection: ObservableObject {
    nonisolated init() {}
}
```

`@StateObject private var connection = CanvasConnection()` evaluates its autoclosure
in a context that isn't guaranteed main-actor. Constructing an empty connection
touches no isolated state, so marking the initializer `nonisolated` is both safe and
necessary.

**`MainActor.assumeIsolated`:**

```swift
} completionHandler: { [weak self] in
    MainActor.assumeIsolated { self?.publishViewport(); self?.resumeDeferredWork() }
}
```

`NSAnimationContext`'s completion handler carries no isolation in its signature, but
AppKit always calls it on the main thread. `assumeIsolated` asserts that at runtime
rather than hopping through `Task { @MainActor in … }`, which would delay the work by
a turn and reorder it relative to the surrounding code.

**Selector-based notification observation:**

```swift
// Selector-based observation rather than the block API: the block form demands a
// `@Sendable` closure, and this coordinator is main-actor state by nature.
center.addObserver(self, selector: #selector(clipViewBoundsDidChange), …)
```

An honest workaround, and the comment says exactly why — which is the right way to
document a concession to a compiler constraint.

**`weak` vs `unowned`, chosen deliberately:**

```swift
weak var host: (any CanvasHostControlling)?   // connection outlives the host
private unowned let parent: UIViewController  // recycler is owned by the parent
```

`weak` where the reference genuinely may go away first; `unowned` where the owner
strictly outlives the reference (and `unowned` avoids the ARC side-table cost). Not
interchangeable, and picking by reasoning rather than by habit is the point.

---

## 15. How this gets tested

`swift test`. No simulator, no host app, seconds not minutes. Five files:

| File | What it locks in |
|---|---|
| `LayoutEngineTests` | Anchoring, margins, normalization, RTL mirroring, content-size modes |
| `SpatialIndexTests` | Query correctness, fuzzed against brute force |
| `CanvasLayoutTests` | Flow wrapping and grid cell sizing |
| `CanvasBackgroundTests` | Tile geometry, clamping of degenerate inputs |
| `VirtualizationTests` | The core promise, plus the update-loop guard |

Four techniques worth copying:

**1. A stub that makes the subject observable.**

```swift
struct StubCanvasLayout: CanvasLayout {
    var frames: [CGRect]
    func place(…) -> CanvasLayoutResult { CanvasLayoutResult(frames: frames) }
}
```

To test *anchoring*, you must not also be testing a real layout's arithmetic. Feed in
known frames and read the transform off the output.

**2. Parameterised tests instead of nine copy-pasted ones.**

```swift
@Test("Every unit point anchors the cluster where it says", arguments: [
    (UnitPoint.topLeading, CGPoint(x: 0, y: 0)),
    (.center, CGPoint(x: 450, y: 450)),
    …
])
func anchoring(anchor: UnitPoint, expectedOrigin: CGPoint) { … }
```

This is swift-testing (`@Suite`, `@Test`, `#expect`, `arguments:`) rather than
XCTest. Each argument reports as a separate case, so a failure names the exact input.

**3. Float comparison with tolerance.** `expectClose(_:_:tolerance:)` in
`TestSupport.swift`, taking `SourceLocation = #_sourceLocation` so failures point at
the *call site*, not at the helper. Never `==` on `CGFloat` derived from geometry.

**4. Testing the promise, not the implementation.**

```swift
@Test("A viewport panned across thousands of items never sees more than a screenful")
func visibleCountTracksViewportNotDataSize() {
    // 5,000 items, 200 viewport positions
    #expect(observedMaximum <= theoreticalMaximum)
    #expect(observedMaximum * 100 < Self.itemCount,
            "hosting \(observedMaximum) of \(Self.itemCount) items is not virtualization")
}

@Test("Every item is reachable by panning; none are stranded off-canvas")
func fullSweepReachesEveryItem() { … #expect(seen.count == Self.itemCount) }
```

These two are a matched pair, and together they're the specification:
**few enough to be fast, all of them reachable.** A performance test that only checks
speed can be passed by rendering nothing. Assert both halves.

---

## 16. Transferable API-design decisions

Independent of canvases, this package makes choices worth reusing:

**Mirror the framework the user already knows.** `PannableCanvas` has `ForEach`'s
three initializers. `CanvasReader`/`CanvasProxy` is `ScrollViewReader`/`ScrollViewProxy`.
`CanvasLayout` is `Layout`. `CanvasProposal` is `ProposedViewSize`, `nil` and all.
Novelty in an API is a cost paid by every user; spend it only where you're actually
doing something new.

**Configure with modifiers, not initializer parameters.** Cascades, composes, reads
like SwiftUI, and keeps `init` to the two things that are genuinely per-instance.

**Label an argument to kill an ambiguity.**

```swift
public func scrollTo(_ point: CGPoint, …)
public func scrollTo(region: CGRect, …)   // labelled on purpose
```

The comment explains it: an unlabelled `CGRect` overload would make `scrollTo(.zero)`
ambiguous at every call site. Two overloads that are individually reasonable can be
collectively unusable.

**Clamp inputs rather than trapping or documenting.** `max(1, columns)`,
`max(1, spacing)`, `max(0, margin)`, `max(0.5, radius)`. A library that crashes on
`columns: 0` is a library that crashes in someone's production app because a value
came from a server.

**Defaults that work with zero configuration.** Flow layout, 120×120 estimate, 128pt
overscan, centre anchors. `PannableCanvas(items) { … }` on its own does something
sensible.

**Comment the *why*, never the *what*.** Every comment in this codebase explains a
decision or a hazard:

> *"This is load-bearing, not an optimization."*
> *"Reporting failure at the edge is what tells VoiceOver to announce the boundary."*
> *"A drag that starts on a control belongs to that control, not to the canvas."*

None of them restate the code. That's the standard to hold yourself to.

**Previews as executable documentation.** [Previews.swift](Sources/Pannable/Previews.swift)
is `#if DEBUG` and covers flow, a 5,000-item grid, a custom ring layout defined
*outside* the package's own types, and the reader/proxy. It's a compile-checked demo
of every major feature, and the custom-layout preview proves the extension point is
genuinely usable from outside.

---

## 17. Known limits and loose ends

Straight from the README, plus a couple visible in the source:

- **No zoom.** The delegate hooks (`viewForZooming`, `scrollViewDidZoom`) and the
  transform-safe `canvasVisibleRect` are already in place, so adding it shouldn't
  break the API — but it isn't implemented.
- **watchOS can't measure off screen.** No `UIHostingController` there, so set
  `.canvasItemSize` or `.canvasEstimatedItemSize` if items differ in size.
- **macOS bounce is partial.** AppKit has elasticity, not a bounce toggle. `.never`
  works; `.always` behaves like `.automatic`.
- **The backdrop is a bitmap**, redrawn on appearance change rather than adapting.
- **Viewport tracking writes state every frame of a pan.** Keep dependent views small.
- **`EnvironmentValues.canvasConfiguration`** (bottom of `CanvasConfiguration.swift`)
  is unreferenced — `PannableCanvas` assembles its configuration from individual
  environment reads instead. Dead code.
- **`ViewportPublisher.reset()`** is only called from tests. Harmless, but it's API
  with no production caller.

Still open: selection, drag-to-move, snapping, per-item coordinates, freeform
placement.

---

## 18. Suggested reading order

If you want to actually absorb the codebase rather than skim it:

1. **`Public/CanvasLayout.swift`** — the central abstraction. Sizes, not views.
2. **`Internal/Layout/LayoutEngine.swift`** — the four-step pipeline. Read every
   comment.
3. **`Internal/Index/SpatialIndex.swift`** — then read `SpatialIndexTests` to see how
   you'd prove such a thing correct.
4. **`Platform/Shared/CanvasEngine.swift`** — the state machine the hosts drive.
5. **`Platform/UIKit/CanvasViewController.swift`** — how it all lands in UIKit.
   `HostRecycler` and `ItemMeasurer` alongside it.
6. **`Platform/Shared/ViewportPublisher.swift`** — nine lines, one whole class of bug.
7. **`Public/CanvasProxy.swift` + `Internal/Model/CanvasConnection.swift`** — the
   environment handshake.
8. Then skim the AppKit and Watch hosts and note what's *the same*.

### Exercises, in increasing difficulty

1. **Write a layout.** A spiral or a masonry column layout. ~20 lines, plus three
   lines of `where Self ==` extension. You'll immediately feel why the engine
   normalizes and anchors for you.
2. **Add `.canvasOverscan(600)` to the 5,000-item preview** and watch `activeCount`
   grow. Then set it to `0` and watch items pop in at the edges. The trade-off
   becomes obvious in about ten seconds.
3. **Break the loop guard on purpose.** Make `ViewportPublisher.shouldPublish` always
   return `true`, attach a `.canvasViewport($binding)`, and pan. Feeling a hang once
   is worth more than reading §9 three times.
4. **Add zoom.** Enable `minimumZoomScale`/`maximumZoomScale`, and work out what
   `canvasVisibleRect` and the overscan inset need to become at scale ≠ 1. The
   scaffolding is deliberately already there.
5. **Add selection.** Where does selection state live so that recycling a hosting
   controller doesn't lose it? (Hint: not in the hosted view. Look at how
   `SizeCache` keys by identity, and do the same.)

---

## The five ideas to keep

If you remember nothing else:

1. **Separate the hard part from the platform part with a directory.** Pure logic
   in, pure logic out — then it's testable in seconds and can't drift across
   platforms.
2. **Lay out on data, not on views.** The moment your layout needs live views, you
   can never be lazy again.
3. **Do nothing expensive during a scroll callback.** Defer measurement, allocation
   and re-layout to the moment motion stops.
4. **Never write SwiftUI state unconditionally from a UIKit callback.** Compare
   first, or you'll build an infinite update loop that presents as a hang.
5. **Key caches by identity, not by index.** Then a reorder costs nothing.
