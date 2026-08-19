# OrbitSwitch

OrbitSwitch is a native macOS menu bar utility inspired by the spatial feel of classic 3D window switchers. It presents eligible windows either as an original perspective stack or as a Stage Manager-style strip along one edge of the display, supports configurable global shortcuts, and keeps all window data on the Mac.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer with the macOS SDK and command-line tools
- Apple Silicon or Intel Mac

## Build

From the repository root:

```sh
./build.sh
```

The script builds the release executable with Swift Package Manager, strips compiler debug metadata from the packaged executable, creates `OrbitSwitch.app` in the repository root, and applies an ad-hoc signature for local testing. The package scratch directory, compiler caches, temporary directory, and generated app all stay inside the repository and are ignored by Git.

To use a separate repository-local scratch directory or debug configuration:

```sh
SCRATCH_PATH="$PWD/.build-debug" CONFIGURATION=debug ./build.sh
```

`SCRATCH_PATH` is canonicalized and rejected if it resolves outside the repository. Add any custom scratch directory to `.gitignore` before using it. The script validates the generated plist and code signature before reporting success.

`BUILD_ARCH` accepts `native` (the default), `arm64`, `x86_64`, or `universal`. For example, a release build containing Apple Silicon and Intel slices is:

```sh
BUILD_ARCH=universal ./build.sh
```

### Preserve macOS permissions across updates

Screen Recording and Accessibility grants are tied to the app's code-signing requirement. The default ad-hoc signature changes identity when the executable changes, so development rebuilds can require removing and re-adding OrbitSwitch under Privacy & Security.

For repeatable local updates, use the same code-signing certificate for every build:

```sh
SIGNING_IDENTITY="Apple Development: Example (TEAMID)" \
APP_VERSION=1.1.0 \
BUILD_NUMBER=2 \
BUILD_ARCH=universal \
./build.sh
```

Available signing identities can be listed with `security find-identity -v -p codesigning`. Quit OrbitSwitch before replacing the copy in `/Applications`, always replace it at the same path, and do not modify the bundle after signing. Switching an existing installation from ad-hoc to stable signing normally requires granting both permissions one final time; subsequent builds signed with that same identity should retain them.

Run the unit tests with repository-local caches:

```sh
HOME="$PWD/.build/home" \
TMPDIR="$PWD/.build/tmp" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache/clang" \
SWIFT_MODULE_CACHE_PATH="$PWD/.build/module-cache/swift" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache/swiftpm" \
swift test --disable-sandbox \
  --scratch-path "$PWD/.build" \
  --cache-path "$PWD/.build/swiftpm-cache" \
  --config-path "$PWD/.build/swiftpm-config" \
  --security-path "$PWD/.build/swiftpm-security"
```

## First launch and permissions

Open `OrbitSwitch.app`. The onboarding window explains two optional macOS permissions:

- **Accessibility** lets OrbitSwitch raise the exact selected window, restore it when minimized, and use the optional Dock Peek feature. Without it, OrbitSwitch can still activate the owning application.
- **Screen Recording** lets OrbitSwitch create window thumbnails. Without it, the overlay intentionally uses app icons, names, and titles instead of broken previews.

Permission state and direct links to Privacy & Security are available under **Settings → Permissions**. macOS may require the app to be restarted after a permission changes.

The default forward shortcut is Option-Tab and the reverse shortcut is Option-Shift-Tab. Hold Option and press Tab repeatedly to cycle; releasing Tab keeps the switcher open, while releasing Option activates the selected window. Command-Tab is deliberately not used. Record new shortcuts under **Settings → Shortcuts**; press Delete while recording to clear a binding.

## Switcher styles

**Settings → Appearance** chooses how the switcher looks. Both styles use the same window list, shortcuts, mouse and scroll navigation, and window controls; only the arrangement differs, and the choice applies the next time the switcher opens.

- **Orbit** is the perspective staircase: one large card front and center with the rest receding toward a vanishing point.
- **Sidebar** is a strip of compact tiles docked to one edge of the display, in the spirit of Stage Manager. Choose the **left**, **right**, **top**, or **bottom** edge, how many windows are on screen at once (3–12), and the tile width. The side edges stack the tiles into a column, the top and bottom lay them out in a row; everything else about the style is identical. The strip appears on the display the switcher opened on, and stays clear of the menu bar and the Dock.

Tab keeps cycling through every window in both styles. In Sidebar, when more windows are open than tiles fit, the strip scrolls to keep the selection in view and the tiles at each end fade to show that the list continues. When the display is short for a column or narrow for a row, OrbitSwitch narrows the tiles to honor the requested count, and shows fewer tiles only when they would otherwise become unreadably small.

## Dock peek

**Settings → Dock Peek** turns on an optional, mouse-first way into the same window list. Rest the pointer on a running application's icon in the Dock and OrbitSwitch shows every window that application has in a compact row or scrolling grid. Click one to bring that exact window forward. Hovering a preview reveals the same close, minimize, and zoom buttons the switcher uses.

It is off by default, and it needs **Accessibility** permission: OrbitSwitch asks the Dock which icon the pointer is over, which macOS allows only with that permission. Screen Recording is optional here as it is elsewhere — without it the previews are the usual title and icon cards.

- The **hover delay** sets how long the pointer must rest before the panel opens; moving along the Dock while a panel is already open switches to the next application faster than the first open.
- The **preview size** sets how large each card is. A long window list narrows the cards to keep them on one row, and wraps into an evenly balanced grid only once they would become unreadable; the cards then widen again to use the room the shorter rows freed.
- However many windows an application has, the panel stays a peek: it never spans more than four fifths of the room beside the Dock, and never grows past three rows. A list longer than that **scrolls** — trackpad or wheel, with the visible range and total shown in the corner — so hovering an app with a hundred windows gives a readable grid you scroll, not a screen-filling wall, and no window is ever left out of it. Visible cards receive thumbnails progressively as you scroll; images well outside the viewport are released so a huge list does not retain a huge decoded-image set.
- The **labels** — app icon, app name, window title, and window controls — are configured for Dock peek separately from the switcher's own labels under Appearance. Dock peek shows the window title and hides the app name by default, because the app name is redundant on a panel opened by pointing at that app's icon. Turning every label off gives the space back to the preview image.
- Leaving both the icon and the panel closes it, with a short grace period so a diagonal move from the icon to the panel does not drop it. Clicking anywhere else closes it immediately.
- Dock peek shows **every** window of the hovered application, including ones **minimized into the Dock**, ones parked on **another Desktop**, and ones belonging to a **hidden** application. Those are the windows hardest to reach any other way, so Current Space only, Include minimized, and Include hidden apps are all overridden here regardless of how they are set for the switcher. Clicking a minimized window's preview un-minimizes and raises it.
- The minimum window size and excluded bundle identifiers under **Settings → Windows** still apply, because those are you saying a window is not one you want to see, and that does not change with how you went looking for it.
- The panel is a non-activating panel and never becomes the key window, so it cannot take focus from whatever you were typing in. It is mouse-driven only.
- Only the Tab switcher or a Dock peek is on screen at a time; opening the switcher closes any peek.

## Privacy and security

- Window titles and thumbnails are processed locally and never transmitted.
- Thumbnails are held in memory only. Session card references are discarded when the overlay closes; a bounded sixteen-image cache accelerates the next invocation and is purged when Screen Recording revocation is observed, or immediately when the session locks or displays sleep.
- Dock peek uses the same discovery and capture path, the same in-memory cache, and the same purge boundaries as the switcher; hovering a Dock icon writes nothing to disk and transmits nothing.
- The app has no analytics, networking, or update telemetry.
- No captured image is written to disk.
- Only Apple frameworks are used, all public: AppKit, Core Graphics, ScreenCaptureKit, Accessibility, Carbon HIToolbox, SwiftUI, and ServiceManagement. One undocumented Accessibility symbol, `_AXUIElementGetWindow`, is isolated in `AXWindowBridge` and used to match a window element to its window ID because no public equivalent exists; callers fall back to title matching when needed. See [Architecture.md](Documentation/Architecture.md).

## Distribution signing

`build.sh` uses an ad-hoc signature unless `SIGNING_IDENTITY` is supplied. A direct-download release should use the same Developer ID Application identity for every version, add a trusted timestamp, submit the finished archive to Apple for notarization, and staple the notarization ticket. Permission grants are signature-sensitive, so test the final signed artifact before release.

## Known limitations

- Protected video and DRM content may return no preview; OrbitSwitch shows its normal fallback card.
- Static thumbnails refresh progressively when the switcher opens rather than streaming continuously; protected or unavailable windows retain their title/icon fallback. In the keyboard switcher, beyond the first sixteen windows a preview is captured when that window is selected, so it appears a moment after the selection lands.
- Minimized windows are included by default and can be disabled under **Settings → Windows**. They are matched to their Accessibility state by window ID; before that they were matched by title, which silently dropped every minimized window of an application whose two titles differ for the same window, Chrome among them. Accessibility permission lets OrbitSwitch positively identify them; without it, unknown off-screen windows are excluded to avoid listing background utilities and menu-bar-only apps.
- ScreenCaptureKit may not provide snapshots for minimized windows, so those entries can use title/icon fallback cards until restored.
- Accessibility identifies a target window by its Core Graphics window ID. If that private best-effort bridge ever fails, a unique public title is used as a fallback; untitled or duplicate-titled windows then fall back to application activation rather than risking the wrong window.
- macOS and third-party utilities can reserve a global shortcut. OrbitSwitch reports registration failures and preserves the last working shortcut.
- “All Displays” mirrors the same stack on each display. It does not create a different window set per display.
- In the Sidebar style, clicking the uncovered desktop dismisses the switcher, because most of the screen is not part of the strip.
- Background Dimming is a percentage-based translucent overlay. OrbitSwitch intentionally avoids a live system blur because full-screen blur redraws caused visible flicker during navigation.
- Launch at Login registration can be unavailable for an ad-hoc development bundle and should be validated in a Developer ID signed release.
- Dock peek requires Accessibility permission and does nothing without it; the setting explains this rather than failing silently. It reads only the Dock's public Accessibility attributes and identifies an icon by the application bundle URL it carries.
- Dock peek covers application icons only. Trash, stacks, folders, and the minimized-window items on the far side of the Dock are ignored, as is an icon whose application is not running or has no eligible windows.
- Dock Peek captures cards as they enter the visible scroll viewport. A protected or otherwise unavailable window keeps its title/icon fallback, and returning to a far-away row may refresh its thumbnail because off-viewport images are deliberately released to bound memory.
- A minimized window usually cannot be captured by ScreenCaptureKit, so its card shows the thumbnail from before it was minimized if one is still cached, and the title/icon fallback otherwise.
- Identifying a minimized window relies on mapping its Accessibility element to its Core Graphics window ID. In the rare case that mapping fails, OrbitSwitch falls back to comparing titles, and a window it still cannot identify is left off rather than risking a background helper surface being listed as a window. The same rule governs the switcher.

See [Architecture.md](Documentation/Architecture.md) and [Manual-QA.md](Documentation/Manual-QA.md) for implementation and test details.
