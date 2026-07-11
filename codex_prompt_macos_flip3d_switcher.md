# Codex Development Prompt: macOS Flip 3D Window Switcher

You are a senior macOS engineer. Build a production-quality macOS application that recreates the spirit of Windows Vista's **Flip 3D** window switcher while feeling native on modern macOS.

The app should show open windows as a perspective-stacked 3D carousel, let the user cycle through them with a configurable keyboard shortcut, and activate the selected window when the shortcut is released or confirmed.

## Product goal

Create a lightweight macOS utility that:

- Runs primarily as a menu bar app.
- Displays a full-screen transparent overlay containing live or static previews of open windows.
- Arranges previews in a Vista-inspired 3D stack.
- Lets users move forward and backward through the stack.
- Activates the selected window cleanly.
- Supports user-defined keyboard shortcuts so the app does not conflict with native macOS shortcuts such as Command-Tab, Command-Backtick, Mission Control, Spotlight, or user-installed utilities.
- Handles permissions, multiple displays, Spaces, minimized windows, and unsupported windows gracefully.

Use Swift and native Apple frameworks. Prefer AppKit for the overlay and system integration. SwiftUI may be used for Settings and menu bar UI.

---

## Target platform

- Language: Swift
- UI: AppKit for overlay; SwiftUI acceptable for Settings
- Minimum deployment target: macOS 14 or newer
- Architecture: Apple Silicon and Intel where practical
- Distribution goal: signed and notarized direct-download app
- App type: menu bar utility with optional Dock icon
- Project format: Xcode project or Swift Package-based Xcode app project

Do not depend on private Apple APIs.

---

## Core user experience

### Showing the switcher

When the configured shortcut is pressed:

1. Enumerate eligible windows.
2. Capture a preview image for each window.
3. Show a borderless, transparent, top-level overlay.
4. Arrange window cards in a perspective stack.
5. Highlight the currently selected window.
6. Show the app icon, app name, and window title.
7. Advance the selection when the shortcut is repeated or when the user presses navigation keys.
8. Activate the selected window when the shortcut is released or when the user presses Return.
9. Dismiss without switching when the user presses Escape.

The interaction should feel immediate. Aim for a warm-start overlay time under 150 ms and smooth 60 fps animation where hardware permits.

### Navigation

Support:

- Move forward through windows.
- Move backward through windows.
- Mouse wheel navigation.
- Trackpad scrolling.
- Optional left and right arrow navigation.
- Return to confirm.
- Escape to cancel.
- Optional clicking on a window card.
- Optional search by typing an app or window name.

---

## Configurable keyboard shortcuts

This is a required feature.

Create a Settings section called **Shortcuts** where users can choose their preferred key combinations.

At minimum, provide configurable shortcuts for:

- Show switcher / next window.
- Previous window.
- Dismiss switcher.
- Optional app-only mode.
- Optional current-app window mode.

### Shortcut recorder

Implement a native-feeling shortcut recorder control that:

- Captures modifier keys and a non-modifier key.
- Supports Command, Option, Control, Shift, and Function where feasible.
- Displays shortcuts using standard macOS glyphs.
- Lets the user clear or reset a shortcut.
- Rejects invalid modifier-only combinations.
- Stores shortcuts persistently.
- Applies shortcut changes without requiring an app restart.
- Includes a **Restore Defaults** button.

Suggested defaults:

- Show / next window: Option-Tab
- Previous window: Option-Shift-Tab
- Dismiss: Escape while overlay is visible

Do not hard-code Command-Tab as the default.

### Conflict detection

Before accepting a shortcut:

- Check whether it conflicts with another shortcut inside this app.
- Warn about common macOS shortcuts, including:
  - Command-Tab
  - Command-Shift-Tab
  - Command-Space
  - Command-Backtick
  - Control-Up Arrow
  - Control-Down Arrow
  - Control-Left Arrow
  - Control-Right Arrow
- Explain that macOS or another utility may already own a global shortcut.
- Attempt to register the shortcut and report registration failure clearly.
- Preserve the previous working shortcut if the new shortcut cannot be registered.
- Allow the user to save a potentially conflicting shortcut only when technically possible, after displaying a warning.
- Never silently override a system shortcut.

Design the shortcut subsystem behind a protocol so its implementation can be replaced later.

Example interfaces:

```swift
struct ShortcutDefinition: Codable, Hashable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers
}

protocol GlobalShortcutManaging: AnyObject {
    func register(_ shortcut: ShortcutDefinition, action: @escaping () -> Void) throws
    func unregister(_ shortcut: ShortcutDefinition)
    func unregisterAll()
}
```

Use a reliable public-API-compatible approach. If a third-party package is used, isolate it behind the protocol and document the dependency.

---

## Window discovery

Create a `WindowDiscoveryService` that:

- Reads visible and eligible application windows.
- Preserves approximate front-to-back order.
- Excludes:
  - Desktop wallpaper windows.
  - Menu bar items.
  - Dock elements.
  - The app's own overlay and settings windows.
  - Tiny utility windows below a configurable threshold.
  - Windows with no useful visual content.
- Includes normal document windows and browser windows.
- Optionally includes minimized windows.
- Associates each window with:
  - Window ID.
  - Owning process ID.
  - Application name.
  - Application bundle identifier.
  - Window title.
  - Bounds.
  - Layer.
  - App icon.
  - Preview image.
  - Eligibility state.

Model example:

```swift
struct SwitchableWindow: Identifiable {
    let id: CGWindowID
    let ownerPID: pid_t
    let appName: String
    let bundleIdentifier: String?
    let title: String
    let frame: CGRect
    let layer: Int
    let appIcon: NSImage?
    let preview: CGImage?
}
```

Keep window filtering rules centralized and unit-testable.

---

## Window previews

Implement a `WindowThumbnailService`.

Version 1 may use static snapshots captured when the switcher opens.

Requirements:

- Capture previews efficiently.
- Preserve aspect ratio.
- Downscale large windows before displaying.
- Cache thumbnails briefly.
- Avoid retaining excessive memory.
- Show a fallback card when a preview is unavailable.
- Handle protected or blank content without crashing.
- Cancel outstanding work when the overlay closes.
- Avoid blocking the main thread during image capture or scaling.

Structure the code so live previews could be added later without rewriting the overlay.

---

## Accessibility and activation

Implement an `AccessibilityWindowController` that:

- Checks whether Accessibility permission is granted.
- Guides the user to System Settings when permission is missing.
- Activates the owning application.
- Raises or focuses the selected window.
- Handles windows that have closed since enumeration.
- Handles minimized windows where possible.
- Reports recoverable failures without terminating the app.

Do not repeatedly nag the user for permission. Show a clear onboarding screen and a persistent status indicator in Settings.

---

## Screen recording permission

The app will likely require Screen Recording permission to capture other applications' windows.

Implement:

- Permission status checks.
- A first-run explanation.
- A button that opens the relevant System Settings privacy pane.
- A useful fallback when permission is not granted:
  - Show app icons and window titles.
  - Do not show blank broken previews as if they were errors.
- A notice when the app must be restarted after permission changes, if applicable.

---

## Overlay window

Create a dedicated borderless overlay window or panel.

Requirements:

- Transparent background.
- Appears above normal application windows.
- Does not become a normal app window in the switcher.
- Can join Spaces where supported.
- Supports full-screen auxiliary behavior.
- Works on multiple displays.
- Can be configured to:
  - Show on the active display only.
  - Show independently on each display.
- Dismisses cleanly when focus is lost, Escape is pressed, or the selected window is activated.
- Does not steal focus in a way that prevents keyboard navigation.

Use AppKit for window-level behavior.

---

## 3D visual treatment

Create the effect using Core Animation unless there is a compelling reason to use SceneKit or Metal.

Each window card should include:

- Window thumbnail.
- App icon.
- App name.
- Window title.
- Rounded corners.
- Subtle border.
- Drop shadow.
- Selection highlight.

Apply perspective using `CATransform3D`.

Suggested layout behavior:

- Selected card near the front and center.
- Remaining cards offset backward and diagonally.
- Slight Y-axis rotation.
- Depth-based scale and opacity.
- Smooth spring animation between selections.
- A maximum visible stack depth to avoid clutter.
- Remaining windows represented by compressed depth.

Respect **Reduce Motion**:

- Use a flatter crossfade or simple horizontal switcher when Reduce Motion is enabled.
- Avoid dramatic depth movement.
- Keep the app fully usable without animation.

Respect **Increase Contrast** and appearance changes.

Do not copy Microsoft's assets or branding. Recreate the interaction concept using original visual design.

---

## Settings

Create a Settings window with these sections:

### General

- Launch at login.
- Show menu bar icon.
- Show Dock icon.
- Start at login status.
- Check for updates placeholder or integration point.
- Reset onboarding.

### Shortcuts

- Shortcut recorder for each action.
- Conflict warnings.
- Registration status.
- Restore defaults.

### Appearance

- Perspective strength.
- Stack angle.
- Card spacing.
- Animation duration.
- Thumbnail quality.
- Background blur amount.
- Show app icon.
- Show app name.
- Show window title.
- Reduce-motion override only when appropriate.
- Theme: System, Light, Dark.

### Window filtering

- Current Space only.
- Include minimized windows.
- Include hidden apps.
- Exclude apps list.
- Minimum window width and height.
- Group windows by application.
- Include untitled windows.
- Ignore transient utility panels.

### Displays

- Active display only.
- Display containing the pointer.
- All displays.
- Remember per-display preference.

Persist settings using a typed settings store rather than scattering `UserDefaults` access throughout the app.

---

## Menu bar menu

Provide:

- Open Switcher.
- Settings.
- Permissions status.
- Pause shortcuts.
- About.
- Quit.

When shortcuts are paused, clearly indicate that state.

---

## Architecture

Use a modular structure similar to:

```text
FlipSwitcher/
├── App/
│   ├── FlipSwitcherApp.swift
│   ├── AppDelegate.swift
│   └── AppState.swift
├── Models/
│   ├── SwitchableWindow.swift
│   ├── ShortcutDefinition.swift
│   └── AppSettings.swift
├── Services/
│   ├── WindowDiscoveryService.swift
│   ├── WindowThumbnailService.swift
│   ├── AccessibilityWindowController.swift
│   ├── PermissionService.swift
│   ├── GlobalShortcutManager.swift
│   └── DisplayService.swift
├── Overlay/
│   ├── SwitcherOverlayController.swift
│   ├── SwitcherOverlayWindow.swift
│   ├── Flip3DView.swift
│   ├── WindowCardLayer.swift
│   └── Flip3DLayoutEngine.swift
├── Settings/
│   ├── SettingsView.swift
│   ├── GeneralSettingsView.swift
│   ├── ShortcutSettingsView.swift
│   ├── AppearanceSettingsView.swift
│   ├── FilteringSettingsView.swift
│   └── ShortcutRecorderView.swift
├── MenuBar/
│   └── MenuBarController.swift
├── Utilities/
│   ├── Logger.swift
│   ├── Debouncer.swift
│   └── ImageScaling.swift
└── Tests/
    ├── WindowFilteringTests.swift
    ├── ShortcutConflictTests.swift
    ├── Flip3DLayoutTests.swift
    └── SettingsStoreTests.swift
```

Use dependency injection for services that access system APIs.

Avoid massive view controllers and singleton-heavy design.

---

## State machine

Model the switcher lifecycle explicitly.

Suggested states:

```swift
enum SwitcherState {
    case idle
    case preparing
    case visible(selection: Int)
    case activating
    case dismissing
    case permissionBlocked
}
```

Prevent duplicate overlays, stale activation requests, and overlapping animations.

---

## Performance requirements

- Do not capture full-resolution screenshots unnecessarily.
- Perform thumbnail scaling off the main thread.
- Keep animation work on Core Animation where possible.
- Debounce repeated window enumeration.
- Cancel obsolete capture tasks.
- Limit cache size.
- Avoid strong-reference cycles.
- Profile memory use with 30 or more open windows.
- Continue functioning when a window closes during switching.

---

## Reliability requirements

Handle these cases:

- No eligible windows.
- Only one eligible window.
- Selected window closes.
- Owning app terminates.
- Permission denied.
- Shortcut registration fails.
- Display is disconnected.
- User changes Spaces.
- Full-screen application is active.
- Protected content cannot be captured.
- Screen locks while overlay is open.
- Fast repeated shortcut presses.
- Settings changed while overlay is visible.

Use structured logging with privacy-conscious messages.

---

## Testing

Add unit tests for:

- Window filtering.
- Shortcut equality and persistence.
- Shortcut conflict detection.
- Shortcut migration from older settings.
- Stack geometry and selection wrapping.
- Empty and single-window behavior.
- Settings defaults.
- Permission-dependent fallback state.

Where system APIs are difficult to test directly, define protocols and mock them.

Add a lightweight manual QA checklist covering:

- Multiple displays.
- Multiple Spaces.
- Full-screen apps.
- Accessibility disabled.
- Screen Recording disabled.
- Keyboard layouts other than US English.
- Reduce Motion enabled.
- Dark and light appearance.
- Shortcut conflicts.
- Thirty or more open windows.

---

## Security and privacy

- Do not transmit window titles, screenshots, or usage data.
- Keep all processing local.
- Do not write captured previews to disk.
- Clear in-memory previews when the overlay closes.
- Document all requested permissions and why they are needed.
- Do not use private frameworks or accessibility APIs beyond the app's stated purpose.

---

## Deliverables

Produce:

1. A compilable Xcode project.
2. A clean README with build and permission instructions.
3. A brief architecture document.
4. Unit tests.
5. A permissions onboarding flow.
6. A Settings window with working shortcut recording and conflict handling.
7. A functional 3D window-switching overlay.
8. A known-limitations section.
9. A manual QA checklist.
10. Clear comments only where the code is not self-explanatory.

---

## Implementation sequence

Work in small, verifiable milestones.

### Milestone 1: App shell

- Create the menu bar app.
- Add Settings.
- Add typed settings storage.
- Add logging.

### Milestone 2: Shortcut system

- Implement shortcut model.
- Implement recorder UI.
- Implement global registration.
- Add conflict detection.
- Add persistence and live re-registration.
- Add tests.

### Milestone 3: Window model

- Enumerate and filter windows.
- Display a debug list in a temporary internal view.
- Add unit tests for filtering.

### Milestone 4: Permissions

- Add Accessibility and Screen Recording checks.
- Add onboarding and System Settings links.
- Add fallback behavior.

### Milestone 5: Basic overlay

- Show a transparent overlay.
- Render static window cards.
- Support next, previous, confirm, and cancel.

### Milestone 6: 3D stack

- Add perspective transforms.
- Add spring animations.
- Add selection labels and icons.
- Add Reduce Motion mode.

### Milestone 7: Activation

- Activate and raise the selected window.
- Handle minimized and stale windows.
- Test across common apps.

### Milestone 8: Polish

- Multiple displays.
- Filtering preferences.
- Performance profiling.
- Error handling.
- README and QA documentation.

After each milestone:

- Build the project.
- Run tests.
- Fix warnings.
- Summarize what changed.
- List known issues.
- Do not proceed while the project is in a non-compiling state.

---

## Coding standards

- Use modern Swift concurrency where appropriate.
- Mark UI-bound code with `@MainActor`.
- Avoid detached tasks unless justified.
- Prefer value types for models.
- Use protocols around system services.
- Keep methods focused.
- Use clear names rather than excessive comments.
- Treat compiler warnings as defects.
- Do not force unwrap unless the invariant is genuinely guaranteed and documented.
- Provide useful error types.
- Keep accessibility labels on all controls.
- Localize user-facing strings through a central mechanism.

---

## Acceptance criteria

The implementation is accepted when:

- The app builds successfully on the stated macOS target.
- The menu bar app launches without showing an unnecessary main window.
- A user can assign a custom global shortcut.
- A conflicting or unavailable shortcut produces a clear warning.
- Changing the shortcut takes effect immediately.
- The default shortcut does not interfere with Command-Tab.
- Invoking the shortcut shows eligible windows in a 3D stack.
- Repeated shortcut presses change the selection.
- Reverse navigation works.
- Releasing or confirming activates the selected window.
- Escape cancels.
- The overlay remains responsive with at least 30 windows.
- Permission-denied states are understandable and recoverable.
- Reduce Motion is respected.
- No screenshots or window metadata leave the device.
- Core filtering, shortcut, settings, and layout logic has automated tests.

---

## First response expected from Codex

Before writing code, respond with:

1. The proposed technical architecture.
2. The exact public APIs or packages planned for global shortcut registration.
3. The permission strategy.
4. The planned shortcut conflict-detection behavior.
5. The project file structure.
6. The first milestone to implement.
7. Any technical risks or macOS limitations that may affect the design.

Then begin Milestone 1 and continue incrementally.
