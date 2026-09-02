# Pannable — the techniques

The component: a pannable 2D canvas over a collection, where 10,000 items must not
mean 10,000 views. Everything below falls out of that one requirement.

---

## 1. Virtualization: lay out on sizes, not views

SwiftUI's `Layout` protocol receives `Layout.Subviews` — live views. So it can never
be lazy. `CanvasLayout` receives only an index and a size:

```swift
public struct CanvasLayoutItem { var index: Int; var size: CGSize }
```

That single substitution is the whole trick. The canvas knows where item #9,847 goes
before any view for it exists. Compute all frames → index them → build views only for
the frames the viewport overlaps.

## 2. Keep the hard part free of UIKit

`Internal/` imports `CoreGraphics` and nothing else. `[CGSize]` in, `[CGRect]` out.
Two payoffs: tests run in seconds with no simulator, and iOS/macOS/watchOS physically
cannot drift apart because they share one implementation of the math.

A directory boundary is enforced by the compiler. A convention isn't.

## 3. Sanitize floats at the boundary

```swift
let sizes = sizes.map(\.canvasSanitized)   // NaN / ∞ / negative → 0
```

An unsettled SwiftUI view reports `NaN` from `sizeThatFits`. It poisons every
downstream `CGRect`, and you crash in the spatial index — three files from the cause.
One `map` at the entrance beats debugging that.

## 4. Normalize → mirror → anchor, once

A layout returns a cluster in its own space (negative coordinates allowed — a ring is
naturally centred on zero). The engine then:

- shifts the cluster to the origin,
- mirrors it for RTL — **so no layout contains a single line of RTL code**,
- anchors it in the slack: `origin = inset + max(0, available - cluster) * anchor`.

The `max(0, …)` matters. Negative slack would push content off the leading edge where
a scroll view *cannot pan to it*. Clamping spills the overflow off the far edge
instead, where it's reachable.

Also: `EdgeInsets` uses `leading`/`trailing` — those are **sides**, not edges, so they
swap under RTL the moment you convert to absolute geometry. Very common bug,
invisible until someone runs the app in Arabic.

## 5. Spatial index: a uniform grid

`frames.filter { $0.intersects(rect) }` is O(n) per scroll event. At 120 Hz over
10,000 items that's 1.2M intersection tests per second.

A uniform grid buckets each frame into the cells it touches; a query visits only the
cells it covers. **Cost becomes proportional to visible area, not data size.** Same
family as a quadtree, but flat and cache-friendly — the right pick when items are
roughly uniformly sized, which laid-out UI is.

Four tuning decisions:

- Cell size = **median** item × 2. Median so one giant item can't coarsen the grid.
- Clamp cells to `64...2048`; cap total buckets at 65,536 (scattered items would
  otherwise allocate a vast empty grid).
- An item spanning 4 cells appears in all 4 → dedupe through a `Set`, then run the
  exact `intersects` test. The grid is a **filter**, not the answer.
- `.sorted()` on the result — not waste. It feeds `accessibilityElements`, so
  VoiceOver reads data order instead of recycle order.

## 6. Estimated sizes and chunked measurement

Same problem `UITableView.estimatedRowHeight` solves: you need a content size before
you can afford to measure everything. So guess, show, correct.

```swift
guard !scrollView.isDragging, !scrollView.isDecelerating else {
    scheduleMeasurementIfNeeded(); return          // yield entirely while moving
}
let finished = engine.measureNextChunk { … }       // 200 items per run-loop turn
if finished { resolveAndApplyLayout() }            // ONE settle, not one per chunk
```

- Chunked through `DispatchQueue.main.async` so the first frame isn't blocked.
- Suspended during a fling — measurement is the most expensive thing here.
- One reflow at the end; 25 reflows would make content visibly shuffle 25 times.

**Clamp measured sizes to 10,000pt.** A view with no intrinsic size (a bare `Color`)
reports *whatever it was proposed* — and measurement proposes
`.greatestFiniteMagnitude`.

**Propose the canvas's usable width**, not infinity, or every `Text` reports one
enormous unwrapped line.

## 7. Cache by identity, never by index

```swift
struct SizeCache { private var storage: [AnyHashable: CGSize] }
```

Index keys invalidate everything below an insertion. Identity keys survive reorders —
only genuinely new items get measured. This is exactly why `ForEach` demands identity.

Two lifecycle hooks that matter: `retain(_:)` prunes dropped items so a long-lived
canvas can't leak, and `invalidateMeasurements()` drops everything at once when
**Dynamic Type** changes, since every text measurement is now wrong.

## 8. Recycling hosting controllers

`UIHostingController` is expensive to create. Pool them — but the key decision:
**pooled controllers stay children of the parent VC for their entire lifetime.** Only
their views enter/leave the container, and only `rootView` changes.

```swift
host.view.removeFromSuperview()
host.rootView = nil        // releases what the item's view held
pool.append(host)
```

Proper containment (`addChild`/`didMove`/`removeFromParent`) is real work with
appearance callbacks. Skipping it on recycle makes reuse a property assignment. The
`UIHostingController<Content?>` generic exists purely so `nil` is expressible.

Identity can survive a data change while **content** doesn't (same note, retitled), so
visible root views are refreshed every update pass. SwiftUI diffs them, so it's cheap.

## 9. Measure with one hosting controller, parented

One reused measurer, not one per item — and it must be **added as a child and in the
view hierarchy**. A detached hosting controller has the *default* trait collection:
measure at default Dynamic Type, lay out at the user's, and every frame is wrong for
anyone who changed their text size.

## 10. Use `UIViewControllerRepresentable`, not `UIViewRepresentable`

If your representable will contain hosting controllers, it must vend a view
controller — they need a parent, or their traits, safe area and appearance callbacks
are all subtly wrong.

`makeUIViewController` runs once. `updateUIViewController` runs on **every** SwiftUI
update pass — it's hot, so it must diff before doing anything.

## 11. Config as one `Equatable` value, with an explicit cost predicate

```swift
func invalidatesLayout(comparedTo other: CanvasConfiguration) -> Bool {
    layout != other.layout || margins != other.margins || itemSize != other.itemSize || …
}
```

Every knob in one comparable struct, and changes sorted into two buckets: needs a full
re-resolve, or just needs a few `UIScrollView` properties poked. Toggling scroll
indicators must not re-layout 10,000 items.

Related: configure via **environment modifiers**, not `init` parameters — so config
cascades from an ancestor, exactly like `.listStyle`.

## 12. ⚠️ The update loop (the bug worth knowing)

```
scroll → publish viewport → writes SwiftUI state → body re-evaluates
       → updateUIViewController → publishes again → ⟳ forever
```

Not a dropped frame — a **hang**. The fix is nine lines:

```swift
mutating func shouldPublish(_ viewport: CanvasViewport) -> Bool {
    guard viewport != lastPublished else { return false }
    lastPublished = viewport
    return true
}
```

This is correctness, not optimization — label it as such, or someone deletes the
"redundant" equality check. The general rule:

> **Never write SwiftUI state unconditionally from a callback SwiftUI can trigger.
> Compare first.**

The watchOS host has the same bug in miniature: the drag writes `crownPosition` to
keep the crown in sync, which fires the crown's `onChange`, which moves the canvas
again. Broken by `guard dragAnchor == nil else { return }`.

## 13. The `ScrollViewReader` handshake

The closure gets a proxy for a canvas that doesn't exist yet — the closure *creates*
it. So the proxy holds an indirection, not the canvas:

1. Reader makes an empty `CanvasConnection`, puts it in the environment, hands a proxy
   wrapping it to the closure.
2. The canvas reads it out of the environment and sets `connection.host = self`.

Details: `weak var host` (the connection outlives any view controller); registration
on **`viewDidAppear`**, not `init`, because SwiftUI can build several hosts and only
the on-screen one has a real viewport; and on disappear, `if connection?.host === self`
— only surrender if you still hold it, since a new host may already have taken over.

Keep the host protocol tiny (here: 3 requirements). A `UIScrollView`, an
`NSScrollView` and a SwiftUI offset can all satisfy it, so the proxy is written once.

## 14. Composing environment values instead of overwriting

Viewport data must flow *up*. `PreferenceKey` flows the right way but pushes a view
update through the whole ancestor chain on every frame of a fling — so instead a
**closure** is passed down and called by the canvas.

But environment values overwrite, so two observers means the second silently wins. Fix:

```swift
@Environment(\.canvasViewportAction) private var existing
content.environment(\.canvasViewportAction, .init { [existing, action] viewport in
    existing?.handler(viewport)   // chain onto what's already in scope
    action(viewport)
})
```

Read, wrap, install. Useful any time "last one wins" is the wrong semantic.

## 15. Type erasure, and `==` via existential opening

Environment values need a concrete type. Standard recipe: capture the concrete value
in a closure with the generics already resolved. The interesting half is equality —
you *cannot* write `lhs.base == rhs.base`, because `Equatable` has a `Self`
requirement an existential can't satisfy:

```swift
public static func == (lhs: AnyCanvasLayout, rhs: AnyCanvasLayout) -> Bool {
    func isEqual<L: CanvasLayout>(_ lhsBase: L) -> Bool {
        guard let rhsBase = rhs.base as? L else { return false }
        return lhsBase == rhsBase
    }
    return isEqual(lhs.base)          // calling a generic fn opens the box
}
```

Passing an existential to a generic function binds `L` to the concrete type, and `==`
becomes available inside. Without a real `==` here, every environment update would
look like a layout change and trigger a full re-resolve.

## 16. Protocol design: optional requirements and dot-syntax

```swift
associatedtype Cache = Void                              // default associated type
extension CanvasLayout where Cache == Void { … }         // + constrained extension
extension CanvasLayout where Self == FlowCanvasLayout {  // → `.flow`, `.grid(columns:)`
    public static var flow: FlowCanvasLayout { … }
}
```

The first pair is Swift's idiom for "optional protocol requirements." The second is
how `.blue` and `.automatic` work across Apple's frameworks — and users can add their
own layouts with the same three lines, which is the test of whether an extension point
is real.

Also worth copying: `CanvasProposal` uses `CGFloat?` where `nil` means *unbounded*,
matching `ProposedViewSize`.

## 17. Generic classes can't conform to `@objc` protocols in extensions

Which is why the scroll delegate is a separate **non-generic** `NSObject`, talking to
the generic view controller through a plain Swift protocol (which *can* be adopted in
an extension). Bonus: one coordinator instance instead of one per `Content`
specialization.

## 18. Do nothing expensive in a scroll callback

```swift
func scrollViewDidScroll(_ scrollView: UIScrollView) { handler?.canvasDidScroll() }
```

One index query plus frame assignments. No measuring, no allocation, no re-layout —
all deferred to `isAtRest`. This is the entire secret to a smooth fling, and it's a
discipline rather than a technique.

Two settings that aren't obvious:

```swift
scrollView.contentInsetAdjustmentBehavior = .never          // don't shift my coordinate space
scrollView.panGestureRecognizer.allowedScrollTypesMask = .all  // iPad trackpad two-finger pan
```

## 19. Pointer drag-to-pan

A scroll view handles wheel and two-finger trackpad scrolling, but **not** dragging
the canvas with a mouse — the first thing anyone tries. Add a `UIPanGestureRecognizer`
limited to `.indirectPointer`, plus three delegate methods that each do real work:

- `shouldBegin` → refuse when there's nowhere to pan.
- `shouldRecognizeSimultaneouslyWith` → keep trackpad scrolling alive alongside it.
- `shouldReceive touch:` → walk up the hierarchy; if it passes a `UIControl`, the drag
  belongs to that control. This is the difference between "I can drag the canvas" and
  "I can't press the buttons on it."

And consume the translation each pass, or you re-apply the whole drag every event:

```swift
recognizer.setTranslation(.zero, in: scrollView)
```

## 20. Platform equivalents worth knowing

- **AppKit has no scroll delegate.** `boundsDidChangeNotification` stands in for
  `scrollViewDidScroll`; `willStartLiveScroll`/`didEndLiveScroll` give the same
  began/ended pair that lets work be deferred.
- **Flip the document view** (`override var isFlipped: Bool { true }`). AppKit's
  origin is bottom-left; one override means the shared engine's output is used
  verbatim instead of mirrored on macOS alone.
- **`DragGesture.translation` is cumulative** from the gesture's start. Apply it to a
  base captured on first `onChanged`, not to the current origin, or every frame
  compounds.

## 21. Big backgrounds: tile, don't draw

A 6000×6000pt content view at 3× needs `18000 × 18000 × 4` ≈ **1.2 GB** of backing
store. Instant jetsam. Instead render one small tile and use
`UIColor(patternImage:)` / `NSColor(patternImage:)` — constant memory, arbitrary size.

- Draw a dot at the **centre** of its tile so it's never clipped at a seam; draw a grid
  tile's **top and left edges only** and let neighbours complete the lines.
- macOS: set `context.patternPhase = convert(.zero, to: nil)`. Pattern phase is
  window-relative by default; anchor it to the view so the pattern stays fixed to
  canvas coordinates while panning.
- The cost: a bitmap can't adapt. You now own its lifecycle — redraw on
  `userInterfaceStyle`/`displayScale` change and on `viewDidChangeEffectiveAppearance`.

## 22. Accessibility under virtualization

Off-screen items aren't in the view hierarchy, so **VoiceOver cannot swipe to them.**
`UITableView` has the same problem and solves it the same way — override
`accessibilityScroll(_:)` so the three-finger gesture pages the content (the default
only handles the vertical axis).

```swift
guard clamped != contentOffset else { return false }   // false ⇒ announce the boundary
setContentOffset(clamped, animated: false)
UIAccessibility.post(notification: .pageScrolled, argument: nil)
```

Returning `false` at the edge is what makes VoiceOver announce it instead of silently
doing nothing. And set `accessibilityElements` explicitly — subviews accumulate in
recycle order, which is effectively random.

## 23. Swift 6 concurrency, the patterns that came up

```swift
private struct CanvasConnectionKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: CanvasConnection? = nil
}
```
`@preconcurrency` on the *conformance* — for a main-actor value behind a non-isolated
protocol requirement. Comes up constantly against pre-concurrency framework protocols.

```swift
nonisolated init() {}                     // @StateObject evaluates its autoclosure off-actor
MainActor.assumeIsolated { … }            // AppKit completion handler: always main, no isolation in the signature
center.addObserver(self, selector: …)     // block API demands a @Sendable closure
```

`weak` vs `unowned` by reasoning, not habit: `weak var host` (the connection outlives
the host), `unowned let parent` (the parent strictly outlives the recycler).

## 24. Testing

- **Stub the collaborator so the subject is observable.** To test *anchoring*, feed a
  layout that returns fixed frames — otherwise you're testing a layout's arithmetic too.
- **Fuzz the fast algorithm against the slow, obviously-correct one.** 600 random
  rects, 200 random queries, compared to `filter { $0.intersects(rect) }`, with a
  **seeded** PRNG so failures reproduce. Highest value-per-line test you can write.
- **Assert the promise, in both directions.** "Never more than a screenful of items
  built" *and* "every item is reachable by panning." A perf test that only checks
  speed is passed by rendering nothing.
- Parameterised `@Test(arguments:)` over nine copy-pasted cases; float comparison with
  tolerance, and pass `SourceLocation = #_sourceLocation` so failures point at the
  call site rather than the helper.

## 25. Small API rules the code follows

- **Mirror what users already know**: `ForEach`'s three inits, `ScrollViewReader`,
  `Layout`, `ProposedViewSize`. Novelty is a cost every user pays.
- **Label an argument to kill an ambiguity**: `scrollTo(region:)` is labelled because
  an unlabelled `CGRect` overload would make `scrollTo(.zero)` ambiguous everywhere.
- **Clamp inputs, don't trap**: `max(1, columns)`, `max(0, margin)`. A library that
  crashes on `columns: 0` crashes in production when the value came from a server.
- **Comment the *why*, never the *what***: *"This is load-bearing, not an
  optimization."*

---

## The five to keep

1. **Lay out on data, not views** — the moment layout needs live views, laziness is gone.
2. **Keep the hard part free of UIKit** — testable in seconds, can't drift across platforms.
3. **Do nothing expensive in a scroll callback** — defer to the moment motion stops.
4. **Never write SwiftUI state unconditionally from a UIKit callback** — compare first,
   or you ship a hang.
5. **Key caches by identity, not index** — then a reorder costs nothing.
