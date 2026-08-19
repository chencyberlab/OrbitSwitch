import CoreGraphics
import Foundation

/// Bounded store of the most recently captured thumbnails, keyed by window ID.
/// A refreshed window moves to the back of the recency order, so a thumbnail
/// the user just selected or zoomed cannot be evicted as though it were still
/// the oldest capture. Entries for closed windows simply age out. In-memory
/// only: nothing is persisted. Not thread-safe —
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
        if images[id] != nil { insertionOrder.removeAll { $0 == id } }
        insertionOrder.append(id)
        images[id] = image
        while insertionOrder.count > limit {
            images.removeValue(forKey: insertionOrder.removeFirst())
        }
    }

    /// Drops every retained thumbnail immediately. Permission revocation and
    /// session-lock boundaries use this instead of waiting for normal bounded
    /// eviction, because an image captured under an earlier permission state
    /// must never be shown after that state changes.
    public func removeAll() {
        images.removeAll(keepingCapacity: false)
        insertionOrder.removeAll(keepingCapacity: false)
    }
}
