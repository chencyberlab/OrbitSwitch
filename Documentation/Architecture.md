# Architecture

## Overview

OrbitSwitch is a Swift Package with two production targets:

- `OrbitSwitchCore` contains settings, shortcut definitions and conflict rules, window filtering, and the layout math for both overlay styles. It has no dependency on the app lifecycle and is covered by unit tests.
- `OrbitSwitch` is the macOS executable. SwiftUI owns the menu bar, Settings, and onboarding scenes; AppKit and Core Animation own overlay behavior.

`build.sh` compiles the executable and assembles the standard `.app` bundle from the committed `Resources/Info.plist`. This avoids generated project and user-scheme files.

The build accepts a persistent code-signing identity and version/build numbers. Stable signing is important because macOS TCC associates Screen Recording and Accessibility grants with the bundle identifier, installed path, and signing requirement. Ad-hoc signatures remain available for disposable builds and are identified in the Permissions UI.

## Runtime flow

1. `AppState` loads typed `AppSettings`, installs the global hotkey event handler, and registers enabled shortcuts.
2. A forward, reverse, app-only, or current-app shortcut asks `SwitcherOverlayController` to enter `preparing`. Current-app mode snapshots and scopes discovery to the frontmost process at invocation time and disables grouping, so a slow discovery cannot switch targets and a global grouping preference cannot collapse that app to one window.
3. `WindowDiscoveryService` reads ordered Core Graphics window metadata, enriches off-screen entries with the public Accessibility minimized attribute when permitted, and applies the pure `WindowFilter` rules. Core Graphics reports that a window is off screen but never why, so `MinimizedStateResolver` reconciles the two lists — by window ID, which is exact, falling back to titles only for an element whose ID cannot be read. A window it cannot identify stays unknown and is dropped, because listing a background helper surface as switchable is worse than omitting a real window. Regular foreground applications are the baseline; hidden apps and low-layer utility panels are admitted only by their explicit settings, while ambiguous background entries are dropped.
4. The overlay appears immediately with title/icon fallback cards.
5. When Screen Recording permission exists, ScreenCaptureKit asynchronously captures bounded static thumbnails. Shareable-content enumeration is prefetched alongside metadata discovery, and captures run three at a time in stack order, each visible card cross-fading its image in as it arrives. A small bounded in-memory cache retains the latest thumbnails between invocations, so a reopened overlay shows real previews on its first frame and fresh captures fade in over them. Cache reads are permission-gated, and observed Screen Recording revocation purges both cached and visible previews. A transient content-enumeration failure receives one short retry. The selected window is always on screen in both styles, so a selection that moves past the captured prefix triggers a debounced on-demand capture for that one window rather than keeping its fallback card.
6. The overlay surface asks its layout for wrapped selection geometry and applies `CATransform3D` transforms. Selection changes run as critically damped `CASpringAnimation`s re-targeted from each layer's live presentation value, so held-down keys interrupt and redirect motion mid-flight; overlay arrival and dismissal share one scale-and-fade path. System Reduce Motion removes depth rotation and replaces movement with a cross-fade, Reduce Transparency swaps the position indicator's vibrancy for a solid surface, and Increase Contrast strengthens card and indicator borders.
7. Releasing the chord key keeps the overlay visible. Releasing its anchor modifier, Return, or a second click confirms. `AccessibilityWindowController` activates the application and raises the matching public Accessibility window. Escape or the configured dismiss binding cancels.
8. Closing or confirming the overlay cancels outstanding capture work and releases the session's window list. A bounded in-memory cache keeps the sixteen most recent thumbnails for the next invocation's first frame; all other thumbnail references are released and nothing is persisted to disk. Session lock and display-sleep notifications dismiss the overlay and purge that cache, making both events hard privacy boundaries.

## Overlay styles

`SwitcherSurfaceView` owns everything the two styles share: the scrim, empty state, position capsule, keyboard and scroll navigation, transform-aware hit testing, and the spring animation used for every card move. Subclasses supply only the arrangement.

- `Flip3DView` places cards with `Flip3DLayout`: a perspective staircase receding toward a vanishing point.
- `SidebarView` places compact tiles with `SidebarLayout`: a strip docked to the configured screen edge. It derives its safe area from the difference between the target screen's `frame` and `visibleFrame`, so the strip clears the menu bar and the Dock, including a Dock on the same edge.

`SidebarLayout` separates three pure decisions: `metrics` fits the requested tile count into the room available along the strip (narrowing tiles first, dropping tiles only once they reach a legible minimum, then re-widening the survivors), `viewport` slides a window over the full list to keep the selection visible, and `placements` turns that into per-tile offset, scale, and opacity. Selection wrapping is shared with the stack through `Flip3DLayout.wrappedIndex`, so Tab keeps looping through every window regardless of how many tiles are on screen; tiles beyond either end of the viewport are parked just past that end at zero opacity so scrolling animates instead of teleporting.

The four edges are two orientations of one layout, not four cases. `SidebarEdge.axis` reports whether the strip is a vertical column (left, right) or a horizontal row (top, bottom), and `SidebarLayout` takes that axis: tile width drives both dimensions, so a column is bounded lengthwise by the display height and crosswise by its width, and a row the other way around. `SidebarPlacement.offset` is one signed distance along whichever axis is in play, and only `SidebarView` maps it back onto x or y. The viewport, boundary fading, and off-viewport parking are axis-independent and shared verbatim.

Because the strip covers only part of the display, a click that misses every tile dismisses the sidebar overlay; the same click is ignored by the orbit stack, which fills the screen.

Both styles are chosen per invocation from `AppSettings.overlayStyle`, so a style change in Settings applies the next time the switcher opens. `WindowCardView` is shared and takes a `CardMetrics` value, with `.regular` proportions for the stack and `.compact` for the strip.

The controller uses explicit `idle`, `preparing`, `visible`, `activating`, and `dismissing` states. Repeated hotkey events received during preparation are accumulated, and a release received before enumeration completes is applied when the window list is ready. Overlay presentation is revision-guarded so a deferred first-frame reveal cannot resurrect a dismissed panel.

## Dock peek

Dock peek is a second, mouse-first entry point into the same window list. Hovering a running application's Dock icon opens a small panel of that application's windows beside the icon. It is off by default and is gated on Accessibility permission, because it works by asking the Dock's own Accessibility tree what the pointer is over.

The flow is deliberately built out of the parts the switcher already has. `WindowDiscoveryService` supplies the window list and the thumbnails, `AccessibilityWindowController` supplies raise, close, minimize, and zoom, and `WindowCardView` supplies the card. `AppState` constructs one discovery actor and one activator and injects both into `SwitcherOverlayController` and `DockPeekController`, so the whole app shares a single bounded `PreviewCache` and a single purge path rather than two of each. Dock Peek passes the hovered process ID into discovery, which preserves Core Graphics ordering while avoiding application lookups and Accessibility enrichment for windows it would immediately discard. The two pickers are never on screen together: the overlay controller reports state changes through `onStateChange`, and any state other than `idle` suppresses peek and stops its global monitor.

Three pieces are new:

- `DockItemLocator` resolves the pointer to a Dock item. It converts `NSEvent.mouseLocation` into Accessibility's top-left coordinate space through `AXGeometry`, calls `AXUIElementCopyElementAtPosition` on the Dock's application element, and accepts the result only when its subrole is `AXApplicationDockItem` — which is what excludes Trash, stacks, folders, and the minimized-window items. The application is identified by the bundle URL in the item's `AXURL` attribute matched against `NSRunningApplication.bundleURL`; title matching is a fallback only, because Dock titles are localized and frequently differ from the process name. The Dock element is cached and dropped on the first failed query, since the Dock restarts often enough that a stale element would otherwise disable the feature until relaunch. Every attribute it reads is documented and public; the app's one private Accessibility symbol is isolated separately in `AXWindowBridge`.
- `DockHoverMonitor` debounces one global `mouseMoved` monitor into enter and exit events. Because it sees every mouse move on the system, two filters run before any Accessibility work: a pointer outside the band of screen the Dock can occupy is rejected on arithmetic alone, and what survives is rate limited to one query per 40 ms. Leaving is confirmed both by the panel's tracking areas and geometrically against the panel's frame, so a missed event cannot strand a panel under the pointer.
- `DockHoverMachine` decides *when* a panel opens and closes, and is a pure value type in the core rather than state inside the monitor. That split is not tidiness: the bookkeeping was wrong twice while it lived inside the event monitor, where nothing could test it — once a click cleared the hover without asking anything to close, leaving the panel on screen with no pending exit and nothing able to arm one. The machine states the invariant it exists to hold: the panel is open exactly while `shown` is set, and every transition that clears `shown` while a panel is up emits `.closePanel`. One test asserts that over every transition, so a new one cannot reintroduce the same class of bug. `forget` is the single deliberate exception, for a caller already tearing the panel down itself. The monitor keeps only what genuinely needs AppKit: watching, throttling, and running the timers the machine asks for.
- `DockPeekLayout` is the pure geometry, unit tested alongside the other layouts. Everything is derived from the Dock item's own frame rather than from the screen's `visibleFrame` insets, which is what makes an auto-hidden Dock work: it reserves no screen area, so the insets say nothing about where the Dock is. `edge` picks the nearest of bottom, left, and right; `availableSpace` measures the room past the icon; `metrics` fits the cards into it; and `frame` centers the panel on the icon and clamps it fully on screen.

  `metrics` is where a peek stays a peek. Cards narrow toward a legible minimum before the row is allowed to wrap, because a smaller card still shows the window while a second row costs the pointer a longer trip. The panel is then bounded to `maximumWidthFraction` of the room beside the Dock and `maximumVisibleRows` rows, and anything past that scrolls: `visibleRows` is what the panel shows, `totalRows` is what the list needs, and `documentSize` exceeds `contentSize` by exactly the scroll range. Windows are never dropped to make a list fit — silently hiding part of a window list is the one outcome a window picker cannot have. Two refinements follow from the bound: a grid that holds the whole list balances its rows rather than filling the first one to the edge, and the tile widens again afterward to reclaim the room those shorter rows freed.

`DockPeekView` scrolls by moving the card frames rather than by hosting an `NSScrollView`: the panel is never the key window and its cards are hit-tested and hover-tracked by hand, so interposing a scroll view's clip and event handling would complicate both to save an offset subtraction. Card tracking areas are clipped to the panel so a scrolled-away card cannot report hover, and are rebuilt whenever the grid moves. The view reports newly visible IDs to the controller, which coalesces them into progressive capture batches. It keeps one row of image overscan and releases decoded previews farther away, so scrolling through a hundred windows fills the viewport without retaining a hundred images. The position chip reports the visible range as well as the total.

`DockPeekPanel` and `DockPeekView` present the result. The panel is built like `SwitcherOverlayWindow` but can never become key, so the pointer is the only way in and nothing steals focus. The view is a plain `NSView`, not a `SwitcherSurfaceView` subclass: peek cards sit at ordinary untransformed frames, so hit testing is `frame.contains` and hover is a tracking area, and none of the scrim, capsule, empty state, or transform-aware hit testing that class exists for would earn its keep. `WindowCardView` is reused unchanged — it already reveals its controls for a card that is both selected and hovered, which is what a peek hover sets.

Peek deliberately ignores `currentSpaceOnly`, `includeMinimized`, and `includeHiddenApps`: the point of hovering a Dock icon is to reach any window that application has, including one parked on another Desktop. The minimum-size and excluded-bundle filters still apply, so a window the user deliberately filtered out stays out. Closing a window uses Core Graphics verification because `AXPress` returning success means the request was delivered, not accepted. Either surface removes a card only after the window disappears; if it remains after the normal close interval, OrbitSwitch dismisses and activates that window so an unsaved-document sheet or other decision is brought forward rather than hidden behind the picker.

## Service boundaries

- `GlobalShortcutManaging` isolates Carbon `RegisterEventHotKey`. Replacing the backend does not affect Settings or overlay code.
- `WindowDiscovering` isolates window metadata and ScreenCaptureKit. Its implementation is an actor because the overlay can run the opening pass, an on-demand selection or visible-peek pass, and a post-zoom refresh at once; all execute off the main actor so window enumeration never blocks the first frame. Each caller supplies its capture bound: sixteen for the switcher's opening prefix, one for selection/zoom refresh, and the current viewport size for Dock Peek.
- `WindowActivating` isolates Accessibility and application activation. `AXGeometry` holds the Accessibility/AppKit coordinate flip that both it and `DockItemLocator` depend on, so the two cannot drift apart on it.
- `SettingsPersistence` is the only component that encodes settings into `UserDefaults`.
- `PermissionService` owns permission checks, explicit requests, and System Settings links.

No private framework is linked, and every Accessibility attribute read is a documented one. There is a single exception, isolated to `AXWindowBridge`: `_AXUIElementGetWindow` maps an `AXUIElement` to its `CGWindowID`. Apple exposes no public equivalent, and matching on titles alone does not merely lose precision, it is wrong for real applications — Chrome reports one window as `"Home | Salesforce - Google Chrome (Incognito)"` to Accessibility and `"Home | Salesforce"` to Core Graphics, so the two never compare equal. Two callers depend on it: `AccessibilityWindowController` to raise the exact selected window, and `WindowDiscoveryService` to tell a minimized window apart from a helper surface. The symbol is long-standing and shared by AltTab, yabai, and Amethyst; both callers treat it as best-effort and fall back to title matching when it fails. It is compatible with notarized direct distribution but would need replacing for the Mac App Store.

## Shortcut transactions

Recorder changes go through `AppState.applyShortcut`. The candidate is checked for a required global modifier, an internal duplicate, and known macOS conflicts. Known system conflicts require explicit confirmation. OrbitSwitch then attempts to register the complete candidate set. If any registration fails, it unregisters the partial candidate and restores the previous complete set before reporting the error; only a successfully registered candidate is persisted.

The configurable dismiss shortcut is local to the overlay and is not registered globally. Registering an unmodified Escape key globally would interfere with unrelated applications.

Pause/resume uses the same transaction rule: the persisted pause state changes only after the complete candidate set is registered or removed successfully. Launch at Login similarly rolls its toggle back when `SMAppService` rejects a change, surfaces the error beside the system status, and reconciles stale persisted state at startup.

## Performance and memory

Metadata discovery happens before thumbnail capture so permission fallbacks and first paint remain fast. Switcher captures are downscaled by the selected quality setting and limited to sixteen windows on open, plus one debounced capture per selection that lands beyond them. Dock Peek instead captures its visible viewport in coalesced batches and releases images well outside it. Core Animation performs transforms and opacity changes. Discovery and refresh tasks are cancelled and session thumbnail references are removed whenever a surface closes; permission revocation, session lock, and display sleep additionally clear the bounded cross-invocation cache. Dock peek shares that cache and those boundaries, and its own hot path — one global mouse monitor — is filtered by screen-edge geometry and rate limited before it is allowed to make an Accessibility round trip.

## Repository layout

```text
Sources/
├── OrbitSwitchCore/       Models, filtering, minimized-state matching, conflicts, persistence, layouts
└── OrbitSwitch/
    ├── App/               Lifecycle and typed settings store
    ├── MenuBar/           Menu commands and status
    ├── DockPeek/          Hover panel, its view, and the peek state controller
    ├── Overlay/           Panel, cards, shared surface, stack and sidebar styles, state controller
    ├── Services/          Shortcuts, windows, permissions, activation, Dock hover
    ├── Settings/          Settings tabs, onboarding, shortcut recorder
    └── Utilities/         Logging, strings, shortcut presentation
Tests/OrbitSwitchCoreTests/ Pure-logic unit tests
Documentation/             Architecture and manual QA
Resources/                 App bundle metadata
```
