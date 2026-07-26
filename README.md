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

- **Accessibility** lets OrbitSwitch raise the exact selected window and restore it when minimized. Without it, OrbitSwitch can still activate the owning application.
- **Screen Recording** lets OrbitSwitch create window thumbnails. Without it, the overlay intentionally uses app icons, names, and titles instead of broken previews.

Permission state and direct links to Privacy & Security are available under **Settings → Permissions**. macOS may require the app to be restarted after a permission changes.

The default forward shortcut is Option-Tab and the reverse shortcut is Option-Shift-Tab. Hold Option and press Tab repeatedly to cycle; releasing Tab keeps the switcher open, while releasing Option activates the selected window. Command-Tab is deliberately not used. Record new shortcuts under **Settings → Shortcuts**; press Delete while recording to clear a binding.

## Switcher styles

**Settings → Appearance** chooses how the switcher looks. Both styles use the same window list, shortcuts, mouse and scroll navigation, and window controls; only the arrangement differs, and the choice applies the next time the switcher opens.

- **Orbit** is the perspective staircase: one large card front and center with the rest receding toward a vanishing point.
- **Sidebar** is a strip of compact tiles docked to one edge of the display, in the spirit of Stage Manager. Choose the **left**, **right**, **top**, or **bottom** edge, how many windows are on screen at once (3–12), and the tile width. The side edges stack the tiles into a column, the top and bottom lay them out in a row; everything else about the style is identical. The strip appears on the display the switcher opened on, and stays clear of the menu bar and the Dock.

Tab keeps cycling through every window in both styles. In Sidebar, when more windows are open than tiles fit, the strip scrolls to keep the selection in view and the tiles at each end fade to show that the list continues. When the display is short for a column or narrow for a row, OrbitSwitch narrows the tiles to honor the requested count, and shows fewer tiles only when they would otherwise become unreadably small.

## Privacy and security

- Window titles and thumbnails are processed locally and never transmitted.
- Thumbnails are held in memory only, limited to the first visible stack entries, and discarded when the overlay closes.
- The app has no analytics, networking, or update telemetry.
- No captured image is written to disk.
- Only Apple frameworks are used, all public: AppKit, Core Graphics, ScreenCaptureKit, Accessibility, Carbon HIToolbox, SwiftUI, and ServiceManagement. One undocumented Accessibility symbol, `_AXUIElementGetWindow`, is used to match a window element to its window ID because no public equivalent exists; it is confined to `AccessibilityWindowController` and falls back to title matching. See [Architecture.md](Documentation/Architecture.md).

## Distribution signing

`build.sh` uses an ad-hoc signature unless `SIGNING_IDENTITY` is supplied. A direct-download release should use the same Developer ID Application identity for every version, add a trusted timestamp, submit the finished archive to Apple for notarization, and staple the notarization ticket. Permission grants are signature-sensitive, so test the final signed artifact before release.

## Known limitations

- Protected video and DRM content may return no preview; OrbitSwitch shows its normal fallback card.
- Static thumbnails refresh progressively when the switcher opens rather than streaming continuously; protected or unavailable windows retain their title/icon fallback. Beyond the first sixteen windows a preview is captured when that window is selected, so it appears a moment after the selection lands.
- Minimized windows are included by default and can be disabled under **Settings → Windows**. Accessibility permission lets OrbitSwitch positively identify them; without it, unknown off-screen windows are excluded to avoid listing background utilities and menu-bar-only apps.
- ScreenCaptureKit may not provide snapshots for minimized windows, so those entries can use title/icon fallback cards until restored.
- Accessibility identifies a target window by its public title attribute. Untitled or identically titled windows can fall back to application activation.
- macOS and third-party utilities can reserve a global shortcut. OrbitSwitch reports registration failures and preserves the last working shortcut.
- “All Displays” mirrors the same stack on each display. It does not create a different window set per display.
- In the Sidebar style, clicking the uncovered desktop dismisses the switcher, because most of the screen is not part of the strip.
- Background Dimming is a percentage-based translucent overlay. OrbitSwitch intentionally avoids a live system blur because full-screen blur redraws caused visible flicker during navigation.
- Launch at Login registration can be unavailable for an ad-hoc development bundle and should be validated in a Developer ID signed release.

See [Architecture.md](Documentation/Architecture.md) and [Manual-QA.md](Documentation/Manual-QA.md) for implementation and test details.
