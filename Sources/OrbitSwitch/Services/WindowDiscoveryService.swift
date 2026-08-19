import AppKit
import ApplicationServices
import CoreGraphics
import OrbitSwitchCore
// ScreenCaptureKit predates strict concurrency: SCShareableContent and SCWindow
// carry no Sendable annotations even though they are safe to hand between the
// capture tasks here.
@preconcurrency import ScreenCaptureKit

struct SwitchableWindow: Identifiable {
    var metadata: WindowMetadata
    let appIcon: NSImage?
    var preview: CGImage?

    var id: CGWindowID { metadata.id }
}

protocol WindowDiscovering: Sendable {
    /// `ownerPID` scopes metadata and Accessibility enrichment at the source.
    /// The switcher passes nil; Dock Peek already knows which app was hovered.
    func discover(settings: AppSettings, ownerPID: pid_t?) async -> [SwitchableWindow]
    func capturePreviews(
        for windows: [SwitchableWindow],
        settings: AppSettings,
        maximumCount: Int,
        onPreview: @escaping @Sendable @MainActor (CGWindowID, CGImage) -> Void
    ) async
    func purgePreviews() async
}

/// An actor, not a class: the overlay runs several capture passes against this
/// service at once — the one that fills the stack when it opens, an on-demand
/// selection or visible Dock Peek batch, and the refresh after a zoom. They all
/// execute off the main actor, so the preview cache and the prefetched content
/// handle need an isolation domain of their own. The expensive work stays off
/// the main thread, which is the whole reason this is not `@MainActor`.
actor WindowDiscoveryService: WindowDiscovering {
    /// Thumbnails from the previous invocation, keyed by window ID. They let a
    /// new overlay open with real previews on its first frame; fresh captures
    /// then fade in over whatever has changed.
    private let previewCache = PreviewCache()
    /// Shareable-content enumeration is slow (~100ms+), so it is prefetched
    /// alongside window metadata discovery instead of sitting between the
    /// overlay's first frame and the first capture.
    private var prefetchedContent: Task<SCShareableContent, Error>?

    func discover(settings: AppSettings, ownerPID: pid_t?) async -> [SwitchableWindow] {
        let canUsePreviews = PermissionService.status.screenRecording
        prefetchedContent?.cancel()
        if !canUsePreviews { previewCache.removeAll() }
        prefetchedContent = canUsePreviews
            ? Task { try await Self.shareableContent(settings: settings) }
            : nil
        let options: CGWindowListOption = Self.usesOnScreenWindowsOnly(settings)
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        guard let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let relevantDictionaries: [[String: Any]]
        if let ownerPID {
            relevantDictionaries = dictionaries.filter { dictionary in
                guard let number = dictionary[kCGWindowOwnerPID as String] as? NSNumber else { return false }
                return pid_t(number.intValue) == ownerPID
            }
        } else {
            relevantDictionaries = dictionaries
        }

        // The window list holds every layer on screen — often a few hundred
        // entries across a couple of dozen processes — and each entry needs its
        // owning application twice (policy and bundle ID during filtering, icon
        // afterward). Memoizing per PID keeps that to one lookup per process on
        // the path that runs before the overlay's first frame.
        var applicationsByPID: [pid_t: NSRunningApplication] = [:]
        var lookedUpApplicationPIDs = Set<pid_t>()
        func application(for pid: pid_t) -> NSRunningApplication? {
            if lookedUpApplicationPIDs.contains(pid) { return applicationsByPID[pid] }
            lookedUpApplicationPIDs.insert(pid)
            let application = NSRunningApplication(processIdentifier: pid)
            if let application { applicationsByPID[pid] = application }
            return application
        }
        var iconsByPID: [pid_t: NSImage] = [:]
        var lookedUpIconPIDs = Set<pid_t>()
        func icon(for pid: pid_t) -> NSImage? {
            if lookedUpIconPIDs.contains(pid) { return iconsByPID[pid] }
            lookedUpIconPIDs.insert(pid)
            let icon = application(for: pid)?.icon
            if let icon { iconsByPID[pid] = icon }
            return icon
        }

        var metadata: [WindowMetadata] = []
        metadata.reserveCapacity(relevantDictionaries.count)
        for dictionary in relevantDictionaries {
            guard let number = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                  let item = Self.metadata(
                      from: dictionary,
                      runningApplication: application(for: pid_t(number.intValue))
                  ) else { continue }
            metadata.append(item)
        }
        let states = Self.accessibilityWindowStates(
            for: Set(metadata.lazy.filter {
                !$0.isOnScreen && $0.ownerPID != getpid() && $0.isRegularApplication && $0.layer == 0
            }.map(\.ownerPID))
        )
        MinimizedStateResolver.apply(
            to: &metadata,
            minimizedByWindowID: states.minimizedByWindowID,
            unidentifiedByPID: states.unidentifiedByPID
        )
        let eligible = WindowFilter.filtered(metadata, settings: settings, ownPID: getpid())
        var discovered: [SwitchableWindow] = []
        discovered.reserveCapacity(eligible.count)
        for item in eligible {
            discovered.append(SwitchableWindow(
                metadata: item,
                appIcon: icon(for: item.ownerPID),
                preview: canUsePreviews ? previewCache.image(for: item.id) : nil
            ))
        }
        if discovered.isEmpty {
            // There will be no capture pass to consume the speculative content
            // enumeration. Do not retain it after hovering an app with no
            // eligible windows (or opening an empty switcher).
            prefetchedContent?.cancel()
            prefetchedContent = nil
        }
        return discovered
    }

    func purgePreviews() async {
        prefetchedContent?.cancel()
        prefetchedContent = nil
        previewCache.removeAll()
    }

    /// Captures with bounded concurrency: strictly sequential captures leave
    /// later cards empty for over a second, while unbounded parallelism just
    /// contends on the Window Server. Three in flight keeps the front of the
    /// stack arriving first without starving any single capture.
    func capturePreviews(
        for windows: [SwitchableWindow],
        settings: AppSettings,
        maximumCount: Int,
        onPreview: @escaping @Sendable @MainActor (CGWindowID, CGImage) -> Void
    ) async {
        guard maximumCount > 0, !windows.isEmpty else { return }
        guard PermissionService.status.screenRecording else {
            prefetchedContent?.cancel()
            prefetchedContent = nil
            previewCache.removeAll()
            return
        }
        do {
            let content: SCShareableContent
            if let prefetchedContent {
                self.prefetchedContent = nil
                content = try await prefetchedContent.value
            } else {
                content = try await Self.shareableContent(settings: settings)
            }
            let sharedWindows = Dictionary(content.windows.map { ($0.windowID, $0) }) { existing, _ in existing }
            let targets = windows.prefix(max(0, maximumCount)).compactMap { window -> (CGWindowID, SCWindow)? in
                guard let shared = sharedWindows[window.id] else { return nil }
                return (window.id, shared)
            }
            let maximumWidth = settings.thumbnailQuality.maximumWidth
            await withTaskGroup(of: (CGWindowID, CGImage)?.self) { group in
                func deliver(_ result: (CGWindowID, CGImage)?) async {
                    guard !Task.isCancelled, PermissionService.status.screenRecording,
                          let (id, image) = result else {
                        // The actor is reentrant while capture awaits
                        // ScreenCaptureKit, so a revocation purge can run and
                        // finish before this result returns. Never let that
                        // stale result repopulate the cache afterward.
                        if !PermissionService.status.screenRecording { previewCache.removeAll() }
                        return
                    }
                    previewCache.insert(image, for: id)
                    await onPreview(id, image)
                }
                var pending = targets[...]
                var inFlight = 0
                while !pending.isEmpty {
                    if inFlight == Self.maxConcurrentCaptures {
                        guard let result = await group.next() else { break }
                        inFlight -= 1
                        await deliver(result)
                    }
                    let target = pending.removeFirst()
                    let added = group.addTaskUnlessCancelled {
                        guard let image = try? await Self.capture(target.1, maximumWidth: maximumWidth) else { return nil }
                        return (target.0, image)
                    }
                    guard added else { break }
                    inFlight += 1
                }
                while let result = await group.next() {
                    guard !Task.isCancelled else { break }
                    await deliver(result)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            Log.windows.error("Progressive preview capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let maxConcurrentCaptures = 3

    private static func metadata(
        from dictionary: [String: Any],
        runningApplication: NSRunningApplication?
    ) -> WindowMetadata? {
        guard let number = dictionary[kCGWindowNumber as String] as? NSNumber,
              let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
        let windowID = CGWindowID(number.uint32Value)
        guard windowID != kCGNullWindowID else { return nil }
        return WindowMetadata(
            id: windowID,
            ownerPID: pid_t(ownerPID.intValue),
            appName: ownerName,
            bundleIdentifier: runningApplication?.bundleIdentifier,
            title: dictionary[kCGWindowName as String] as? String ?? "",
            frame: frame,
            layer: (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            isOnScreen: (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
            isRegularApplication: runningApplication?.activationPolicy == .regular,
            isApplicationHidden: runningApplication?.isHidden ?? false
        )
    }

    private static func capture(_ window: SCWindow, maximumWidth: Int) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = min(1, CGFloat(maximumWidth) / max(window.frame.width, 1))
        configuration.width = max(1, Int(window.frame.width * scale))
        configuration.height = max(1, Int(window.frame.height * scale))
        configuration.showsCursor = false
        // Shadowless captures are cheaper to composite and crop tighter to the
        // window's real content; the card draws its own shadow anyway.
        configuration.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private static func shareableContent(settings: AppSettings) async throws -> SCShareableContent {
        let onScreenOnly = usesOnScreenWindowsOnly(settings)
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenOnly)
        } catch {
            try await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { throw CancellationError() }
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenOnly)
        }
    }

    private static func usesOnScreenWindowsOnly(_ settings: AppSettings) -> Bool {
        settings.currentSpaceOnly && !settings.includeMinimized && !settings.includeHiddenApps
    }

    /// What Accessibility could tell us about each off-screen window. How these
    /// two are reconciled against the Core Graphics list lives in
    /// `MinimizedStateResolver`, which is where the reasoning is written down.
    private struct AccessibilityWindowStates {
        var minimizedByWindowID: [CGWindowID: Bool] = [:]
        var unidentifiedByPID: [pid_t: [AccessibilityWindowState]] = [:]
    }

    private static func accessibilityWindowStates(for processIDs: Set<pid_t>) -> AccessibilityWindowStates {
        guard AXIsProcessTrusted() else { return AccessibilityWindowStates() }
        var result = AccessibilityWindowStates()
        for processID in processIDs {
            let application = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(application, 0.2)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement] else { continue }
            for window in windows {
                var minimizedValue: CFTypeRef?
                // A failed or unsupported attribute read is unknown, not
                // "not minimized". Recording false here would admit ambiguous
                // off-screen helper surfaces whenever Current Space is off.
                guard AXUIElementCopyAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    &minimizedValue
                ) == .success,
                    let isMinimized = minimizedValue as? Bool else { continue }
                if let windowID = AXWindowBridge.windowID(of: window) {
                    result.minimizedByWindowID[windowID] = isMinimized
                    continue
                }
                var titleValue: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                result.unidentifiedByPID[processID, default: []].append(
                    AccessibilityWindowState(
                        title: titleValue as? String ?? "",
                        isMinimized: isMinimized
                    )
                )
            }
        }
        return result
    }
}
