import AppKit
import ApplicationServices
import CoreGraphics
import OrbitSwitchCore
import ScreenCaptureKit

struct SwitchableWindow: Identifiable {
    var metadata: WindowMetadata
    let appIcon: NSImage?
    var preview: CGImage?

    var id: CGWindowID { metadata.id }
}

protocol WindowDiscovering {
    func discover(settings: AppSettings) async -> [SwitchableWindow]
    func capturePreviews(
        for windows: [SwitchableWindow],
        settings: AppSettings,
        onPreview: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) async
}

final class WindowDiscoveryService: WindowDiscovering {
    /// Thumbnails from the previous invocation, keyed by window ID. They let a
    /// new overlay open with real previews on its first frame; fresh captures
    /// then fade in over whatever has changed.
    private let previewCache = PreviewCache()
    /// Shareable-content enumeration is slow (~100ms+), so it is prefetched
    /// alongside window metadata discovery instead of sitting between the
    /// overlay's first frame and the first capture.
    private var prefetchedContent: Task<SCShareableContent, Error>?

    func discover(settings: AppSettings) async -> [SwitchableWindow] {
        prefetchedContent?.cancel()
        prefetchedContent = PermissionService.status.screenRecording
            ? Task { try await Self.shareableContent(settings: settings) }
            : nil
        let options: CGWindowListOption = Self.usesOnScreenWindowsOnly(settings)
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        guard let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }

        var metadata = dictionaries.compactMap(Self.metadata(from:))
        var minimizedWindows = Self.accessibilityWindowStates(
            for: Set(metadata.lazy.filter {
                !$0.isOnScreen && $0.ownerPID != getpid() && $0.isRegularApplication && $0.layer == 0
            }.map(\.ownerPID))
        )
        for index in metadata.indices where !metadata[index].isOnScreen {
            let states = minimizedWindows[metadata[index].ownerPID] ?? []
            if let stateIndex = states.firstIndex(where: { $0.title == metadata[index].title }) {
                let matchingState = states[stateIndex]
                metadata[index].isMinimized = matchingState.isMinimized
                minimizedWindows[metadata[index].ownerPID]?.remove(at: stateIndex)
            }
        }
        let eligible = WindowFilter.filtered(metadata, settings: settings, ownPID: getpid())
        return eligible.map { item in
            let app = NSRunningApplication(processIdentifier: item.ownerPID)
            return SwitchableWindow(metadata: item, appIcon: app?.icon, preview: previewCache.image(for: item.id))
        }
    }

    /// Captures with bounded concurrency: strictly sequential captures leave
    /// later cards empty for over a second, while unbounded parallelism just
    /// contends on the Window Server. Three in flight keeps the front of the
    /// stack arriving first without starving any single capture.
    func capturePreviews(
        for windows: [SwitchableWindow],
        settings: AppSettings,
        onPreview: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) async {
        do {
            let content: SCShareableContent
            if let prefetchedContent {
                self.prefetchedContent = nil
                content = try await prefetchedContent.value
            } else {
                content = try await Self.shareableContent(settings: settings)
            }
            let sharedWindows = Dictionary(content.windows.map { ($0.windowID, $0) }) { existing, _ in existing }
            let targets = windows.prefix(16).compactMap { window -> (CGWindowID, SCWindow)? in
                guard let shared = sharedWindows[window.id] else { return nil }
                return (window.id, shared)
            }
            let maximumWidth = settings.thumbnailQuality.maximumWidth
            await withTaskGroup(of: (CGWindowID, CGImage)?.self) { group in
                func deliver(_ result: (CGWindowID, CGImage)?) async {
                    guard !Task.isCancelled, let (id, image) = result else { return }
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
                    _ = group.addTaskUnlessCancelled {
                        guard let image = try? await Self.capture(target.1, maximumWidth: maximumWidth) else { return nil }
                        return (target.0, image)
                    }
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

    private static func metadata(from dictionary: [String: Any]) -> WindowMetadata? {
        guard let number = dictionary[kCGWindowNumber as String] as? NSNumber,
              let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
        let runningApp = NSRunningApplication(processIdentifier: pid_t(ownerPID.intValue))
        return WindowMetadata(
            id: CGWindowID(number.uint32Value),
            ownerPID: pid_t(ownerPID.intValue),
            appName: ownerName,
            bundleIdentifier: runningApp?.bundleIdentifier,
            title: dictionary[kCGWindowName as String] as? String ?? "",
            frame: frame,
            layer: (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
            isOnScreen: (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false,
            isRegularApplication: runningApp?.activationPolicy == .regular,
            isApplicationHidden: runningApp?.isHidden ?? false
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

    private struct AccessibilityWindowState {
        let title: String
        let isMinimized: Bool
    }

    private static func accessibilityWindowStates(for processIDs: Set<pid_t>) -> [pid_t: [AccessibilityWindowState]] {
        guard AXIsProcessTrusted() else { return [:] }
        var result: [pid_t: [AccessibilityWindowState]] = [:]
        for processID in processIDs {
            let application = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(application, 0.2)
            var windowsValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement] else { continue }
            result[processID] = windows.map { window in
                var titleValue: CFTypeRef?
                var minimizedValue: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
                AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
                return AccessibilityWindowState(
                    title: titleValue as? String ?? "",
                    isMinimized: minimizedValue as? Bool ?? false
                )
            }
        }
        return result
    }
}
