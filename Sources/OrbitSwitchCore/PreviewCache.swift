import CoreGraphics
import Foundation

/// Bounded store of the most recently captured thumbnails, keyed by window ID.
/// Eviction is insertion-order past the limit, which matches the count capture
/// itself uses (16); entries for closed windows are never looked up again and
/// simply age out. In-memory only: nothing is persisted. Not thread-safe —
/// confine to a single actor (the app keeps it inside its discovery actor,
/// which runs several capture passes concurrently).
public final class PreviewCache {
    public static let defaultLimit = 16

    private var images: [CGWindowID: CGImage] = [:]
    private var insertionOrder: [CGWindowID] = []
    private let limit: Int

    public init(limit: Int = defaultLimit) {
        self.limit = max(1, limit)
    }

    public var count: Int { images.count }

    public func image(for id: CGWindowID) -> CGImage? { images[id] }

    public func insert(_ image: CGImage, for id: CGWindowID) {
        if images[id] == nil { insertionOrder.append(id) }
        images[id] = image
        while insertionOrder.count > limit {
            images.removeValue(forKey: insertionOrder.removeFirst())
        }
    }
}
