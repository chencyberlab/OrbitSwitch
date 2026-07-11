# OrbitSwitch

OrbitSwitch is a native macOS menu bar utility inspired by the spatial feel of classic 3D window switchers. It presents eligible windows in an original perspective stack, supports configurable global shortcuts, and keeps all window data on the Mac.

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

## Privacy and security

- Window titles and thumbnails are processed locally and never transmitted.
- Thumbnails are held in memory only, limited to the first visible stack entries, and discarded when the overlay closes.
- The app has no analytics, networking, or update telemetry.
- No captured image is written to disk.
- Only public Apple frameworks are used: AppKit, Core Graphics, ScreenCaptureKit, Accessibility, Carbon HIToolbox, SwiftUI, and ServiceManagement.

## Distribution signing

`build.sh` uses an ad-hoc signature unless `SIGNING_IDENTITY` is supplied. A direct-download release should use the same Developer ID Application identity for every version, add a trusted timestamp, submit the finished archive to Apple for notarization, and staple the notarization ticket. Permission grants are signature-sensitive, so test the final signed artifact before release.

## Known limitations

- Protected video and DRM content may return no preview; OrbitSwitch shows its normal fallback card.
- Static thumbnails refresh progressively when the switcher opens rather than streaming continuously; protected or unavailable windows retain their title/icon fallback.
- Minimized windows are included by default and can be disabled under **Settings → Windows**. Accessibility permission lets OrbitSwitch positively identify them; without it, unknown off-screen windows are excluded to avoid listing background utilities and menu-bar-only apps.
- ScreenCaptureKit may not provide snapshots for minimized windows, so those entries can use title/icon fallback cards until restored.
- Accessibility identifies a target window by its public title attribute. Untitled or identically titled windows can fall back to application activation.
- macOS and third-party utilities can reserve a global shortcut. OrbitSwitch reports registration failures and preserves the last working shortcut.
- “All Displays” mirrors the same stack on each display. It does not create a different window set per display.
- Background Dimming is a percentage-based translucent overlay. OrbitSwitch intentionally avoids a live system blur because full-screen blur redraws caused visible flicker during navigation.
- Launch at Login registration can be unavailable for an ad-hoc development bundle and should be validated in a Developer ID signed release.

See [Architecture.md](Documentation/Architecture.md) and [Manual-QA.md](Documentation/Manual-QA.md) for implementation and test details.
