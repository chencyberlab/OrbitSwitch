# Architecture

## Overview

OrbitSwitch is a Swift Package with two production targets:

- `OrbitSwitchCore` contains settings, shortcut definitions and conflict rules, window filtering, and 3D layout math. It has no dependency on the app lifecycle and is covered by unit tests.
- `OrbitSwitch` is the macOS executable. SwiftUI owns the menu bar, Settings, and onboarding scenes; AppKit and Core Animation own overlay behavior.

`build.sh` compiles the executable and assembles the standard `.app` bundle from the committed `Resources/Info.plist`. This avoids generated project and user-scheme files.

The build accepts a persistent code-signing identity and version/build numbers. Stable signing is important because macOS TCC associates Screen Recording and Accessibility grants with the bundle identifier, installed path, and signing requirement. Ad-hoc signatures remain available for disposable builds and are identified in the Permissions UI.

## Runtime flow

1. `AppState` loads typed `AppSettings`, installs the global hotkey event handler, and registers enabled shortcuts.
2. A forward, reverse, app-only, or current-app shortcut asks `SwitcherOverlayController` to enter `preparing`.
3. `WindowDiscoveryService` reads ordered Core Graphics window metadata, enriches off-screen entries with the public Accessibility minimized attribute when permitted, and applies the pure `WindowFilter` rules. Regular foreground applications are the baseline; hidden apps and low-layer utility panels are admitted only by their explicit settings, while ambiguous background entries are dropped.
4. The overlay appears immediately with title/icon fallback cards.
5. When Screen Recording permission exists, ScreenCaptureKit asynchronously captures bounded static thumbnails. Shareable-content enumeration is prefetched alongside metadata discovery, and captures run three at a time in stack order, each visible card cross-fading its image in as it arrives. A small bounded in-memory cache retains the latest thumbnails between invocations, so a reopened overlay shows real previews on its first frame and fresh captures fade in over them. A transient content-enumeration failure receives one short retry.
6. `Flip3DView` asks `Flip3DLayout` for wrapped selection geometry and applies perspective `CATransform3D` transforms. Selection changes run as critically damped `CASpringAnimation`s re-targeted from each layer's live presentation value, so held-down keys interrupt and redirect motion mid-flight; overlay arrival and dismissal share one scale-and-fade path. System Reduce Motion removes depth rotation and replaces movement with a cross-fade, Reduce Transparency swaps the position indicator's vibrancy for a solid surface, and Increase Contrast strengthens card and indicator borders.
7. Releasing the chord key keeps the overlay visible. Releasing its anchor modifier, Return, or a second click confirms. `AccessibilityWindowController` activates the application and raises the matching public Accessibility window. Escape or the configured dismiss binding cancels.
8. Closing or confirming the overlay cancels outstanding capture work and releases the session's window list. A bounded in-memory cache keeps the sixteen most recent thumbnails for the next invocation's first frame; all other thumbnail references are released and nothing is persisted to disk. Session lock and display-sleep notifications dismiss the overlay automatically.

The controller uses explicit `idle`, `preparing`, `visible`, `activating`, `dismissing`, and `permissionBlocked` states. Repeated hotkey events received during preparation are accumulated, and a release received before enumeration completes is applied when the window list is ready. Overlay presentation is revision-guarded so a deferred first-frame reveal cannot resurrect a dismissed panel.

## Service boundaries

- `GlobalShortcutManaging` isolates Carbon `RegisterEventHotKey`. Replacing the backend does not affect Settings or overlay code.
- `WindowDiscovering` isolates window metadata and ScreenCaptureKit.
- `WindowActivating` isolates Accessibility and application activation.
- `SettingsPersistence` is the only component that encodes settings into `UserDefaults`.
- `PermissionService` owns permission checks, explicit requests, and System Settings links.

No private framework or undocumented Accessibility attribute is used.

## Shortcut transactions

Recorder changes go through `AppState.applyShortcut`. The candidate is checked for a required global modifier, an internal duplicate, and known macOS conflicts. Known system conflicts require explicit confirmation. OrbitSwitch then attempts to register the complete candidate set. If any registration fails, it unregisters the partial candidate and restores the previous complete set before reporting the error; only a successfully registered candidate is persisted.

The configurable dismiss shortcut is local to the overlay and is not registered globally. Registering an unmodified Escape key globally would interfere with unrelated applications.

## Performance and memory

Metadata discovery happens before thumbnail capture so permission fallbacks and first paint remain fast. Captures are downscaled by the selected quality setting and limited to sixteen visible-depth windows. Core Animation performs transforms and opacity changes. The discovery task is cancelled and thumbnail references are removed whenever the overlay closes.

## Repository layout

```text
Sources/
├── OrbitSwitchCore/       Models, filtering, conflicts, persistence, layout
└── OrbitSwitch/
    ├── App/               Lifecycle and typed settings store
    ├── MenuBar/           Menu commands and status
    ├── Overlay/           Panel, cards, 3D view, state controller
    ├── Services/          Shortcuts, windows, permissions, activation
    ├── Settings/          Settings tabs, onboarding, shortcut recorder
    └── Utilities/         Logging, strings, shortcut presentation
Tests/OrbitSwitchCoreTests/ Pure-logic unit tests
Documentation/             Architecture and manual QA
Resources/                 App bundle metadata
```
