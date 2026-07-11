import AppKit
import ApplicationServices
import CoreGraphics
import OrbitSwitchCore
import ScreenCaptureKit

struct SwitchableWindow: Identifiable {
    let metadata: WindowMetadata
    let appIcon: NSImage?
    var preview: CGImage?

    var id: CGWindowID { metadata.id }
}

protocol WindowDiscovering {
    func discover(settings: AppSettings, capturePreviews: Bool) async -> [SwitchableWindow]
    func capturePreviews(
        for windows: [SwitchableWindow],
        settings: AppSettings,
        onPreview: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) async
}

final class WindowDiscoveryService: WindowDiscovering {
    func discover(settings: AppSettings, capturePreviews: Bool) async -> [SwitchableWindow] {
        let options: CGWindowListOption = settings.currentSpaceOnly && !settings.includeMinimized
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll, .excludeDesktopElements]
        guard let dictionaries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }

        var metadata = dictionaries.compactMap(Self.metadata(from:))
        let minimizedWindows = Self.accessibilityWindowStates(for: Set(metadata.map(\.ownerPID)))
        for index in metadata.indices where !metadata[index].isOnScreen {
            let states = minimizedWindows[metadata[index].ownerPID] ?? []
            if let matchingState = states.first(where: { $0.title == metadata[index].title }) {
                metadata[index].isMinimized = matchingState.isMinimized
            }
        }
        let eligible = WindowFilter.filtered(metadata, settings: settings, ownPID: getpid())
        var windows = eligible.map { item in
            let app = NSRunningApplication(processIdentifier: item.ownerPID)
            return SwitchableWindow(metadata: item, appIcon: app?.icon, preview: nil)
        }
        guard capturePreviews else { return windows }

        do {
            let content = try await Self.shareableContent(settings: settings)
            let sharedWindows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
            for index in windows.indices.prefix(16) {
                guard !Task.isCancelled else { return windows }
                guard let sharedWindow = sharedWindows[windows[index].id] else { continue }
                windows[index].preview = try? await Self.capture(sharedWindow, maximumWidth: settings.thumbnailQuality.maximumWidth)
            }
        } catch {
            Log.windows.error("Preview discovery failed: \(error.localizedDescription, privacy: .public)")
        }
        return windows
    }

    func capturePreviews(
        for windows: [SwitchableWindow],
        settings: AppSettings,
        onPreview: @escaping @MainActor (CGWindowID, CGImage) -> Void
    ) async {
        do {
            let content = try await Self.shareableContent(settings: settings)
            let sharedWindows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })
            for window in windows.prefix(16) {
                guard !Task.isCancelled else { return }
                guard let sharedWindow = sharedWindows[window.id],
                      let preview = try? await Self.capture(sharedWindow, maximumWidth: settings.thumbnailQuality.maximumWidth) else {
                    continue
                }
                await onPreview(window.id, preview)
            }
        } catch {
            Log.windows.error("Progressive preview capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

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
        configuration.ignoreShadowsSingleWindow = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private static func shareableContent(settings: AppSettings) async throws -> SCShareableContent {
        let onScreenOnly = settings.currentSpaceOnly && !settings.includeMinimized
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenOnly)
        } catch {
            try await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { throw CancellationError() }
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: onScreenOnly)
        }
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
