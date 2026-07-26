# Architecture

## Overview

OrbitSwitch is a Swift Package with two production targets:

- `OrbitSwitchCore` contains settings, shortcut definitions and conflict rules, window filtering, and the layout math for both overlay styles. It has no dependency on the app lifecycle and is covered by unit tests.
- `OrbitSwitch` is the macOS executable. SwiftUI owns the menu bar, Settings, and onboarding scenes; AppKit and Core Animation own overlay behavior.

`build.sh` compiles the executable and assembles the standard `.app` bundle from the committed `Resources/Info.plist`. This avoids generated project and user-scheme files.

The build accepts a persistent code-signing identity and version/build numbers. Stable signing is important because macOS TCC associates Screen Recording and Accessibility grants with the bundle identifier, installed path, and signing requirement. Ad-hoc signatures remain available for disposable builds and are identified in the Permissions UI.

## Runtime flow

1. `AppState` loads typed `AppSettings`, installs the global hotkey event handler, and registers enabled shortcuts.
2. A forward, reverse, app-only, or current-app shortcut asks `SwitcherOverlayController` to enter `preparing`.
3. `WindowDiscoveryService` reads ordered Core Graphics window metadata, enriches off-screen entries with the public Accessibility minimized attribute when permitted, and applies the pure `WindowFilter` rules. Regular foreground applications are the baseline; hidden apps and low-layer utility panels are admitted only by their explicit settings, while ambiguous background entries are dropped.
4. The overlay appears immediately with title/icon fallback cards.
5. When Screen Recording permission exists, ScreenCaptureKit asynchronously captures bounded static thumbnails. Shareable-content enumeration is prefetched alongside metadata discovery, and captures run three at a time in stack order, each visible card cross-fading its image in as it arrives. A small bounded in-memory cache retains the latest thumbnails between invocations, so a reopened overlay shows real previews on its first frame and fresh captures fade in over them. Cache reads are permission-gated, and revoking Screen Recording purges both cached and visible previews immediately. A transient content-enumeration failure receives one short retry. The selected window is always on screen in both styles, so a selection that moves past the captured prefix triggers a debounced on-demand capture for that one window rather than keeping its fallback card.
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

## Service boundaries

- `GlobalShortcutManaging` isolates Carbon `RegisterEventHotKey`. Replacing the backend does not affect Settings or overlay code.
- `WindowDiscovering` isolates window metadata and ScreenCaptureKit. Its implementation is an actor because the overlay runs up to three capture passes against it at once — the opening one, the on-demand one for a selection past the captured prefix, and the post-zoom refresh — and all of them execute off the main actor so window enumeration never blocks the first frame.
- `WindowActivating` isolates Accessibility and application activation.
- `SettingsPersistence` is the only component that encodes settings into `UserDefaults`.
- `PermissionService` owns permission checks, explicit requests, and System Settings links.

No private framework is linked, and every Accessibility attribute read is a documented one. There is a single exception, isolated to `AccessibilityWindowController`: `_AXUIElementGetWindow` maps an `AXUIElement` to its `CGWindowID`. Apple exposes no public equivalent, and matching on titles alone misidentifies windows — Chrome, for example, appends its profile name to AX titles but not to `CGWindowList` titles. The symbol is long-standing and shared by AltTab, yabai, and Amethyst; the code treats it as best-effort and falls back to title matching when it fails. It is compatible with notarized direct distribution but would need replacing for the Mac App Store.

## Shortcut transactions

Recorder changes go through `AppState.applyShortcut`. The candidate is checked for a required global modifier, an internal duplicate, and known macOS conflicts. Known system conflicts require explicit confirmation. OrbitSwitch then attempts to register the complete candidate set. If any registration fails, it unregisters the partial candidate and restores the previous complete set before reporting the error; only a successfully registered candidate is persisted.

The configurable dismiss shortcut is local to the overlay and is not registered globally. Registering an unmodified Escape key globally would interfere with unrelated applications.

Pause/resume uses the same transaction rule: the persisted pause state changes only after the complete candidate set is registered or removed successfully. Launch at Login similarly rolls its toggle back when `SMAppService` rejects a change, surfaces the error beside the system status, and reconciles stale persisted state at startup.

## Performance and memory

Metadata discovery happens before thumbnail capture so permission fallbacks and first paint remain fast. Captures are downscaled by the selected quality setting and limited to sixteen windows on open, plus one debounced capture per selection that lands beyond them. Core Animation performs transforms and opacity changes. The discovery task is cancelled and session thumbnail references are removed whenever the overlay closes; permission revocation, session lock, and display sleep additionally clear the bounded cross-invocation cache.

## Repository layout

```text
Sources/
├── OrbitSwitchCore/       Models, filtering, conflicts, persistence, stack and strip layout
└── OrbitSwitch/
    ├── App/               Lifecycle and typed settings store
    ├── MenuBar/           Menu commands and status
    ├── Overlay/           Panel, cards, shared surface, stack and sidebar styles, state controller
    ├── Services/          Shortcuts, windows, permissions, activation
    ├── Settings/          Settings tabs, onboarding, shortcut recorder
    └── Utilities/         Logging, strings, shortcut presentation
Tests/OrbitSwitchCoreTests/ Pure-logic unit tests
Documentation/             Architecture and manual QA
Resources/                 App bundle metadata
```
