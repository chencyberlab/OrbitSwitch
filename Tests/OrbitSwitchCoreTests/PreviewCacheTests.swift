import CoreGraphics
import XCTest
@testable import OrbitSwitchCore

final class PreviewCacheTests: XCTestCase {
    private func makeImage(width: Int = 8, height: Int = 8) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func testInsertBeyondLimitEvictsOldestFirst() {
        let cache = PreviewCache(limit: 4)
        for id: CGWindowID in 1...10 { cache.insert(makeImage(), for: id) }
        XCTAssertEqual(cache.count, 4)
        for id: CGWindowID in 1...6 { XCTAssertNil(cache.image(for: id), "id \(id) should have been evicted") }
        for id: CGWindowID in 7...10 { XCTAssertNotNil(cache.image(for: id), "id \(id) should still be cached") }
    }

    func testReinsertingExistingIDReplacesWithoutGrowing() {
        let cache = PreviewCache(limit: 3)
        cache.insert(makeImage(), for: 1)
        cache.insert(makeImage(width: 16), for: 1)
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.image(for: 1)?.width, 16)
    }

    func testRefreshingExistingIDMakesItMostRecentForEviction() {
        let cache = PreviewCache(limit: 2)
        cache.insert(makeImage(), for: 1)
        cache.insert(makeImage(), for: 2)
        cache.insert(makeImage(width: 16), for: 1)

        cache.insert(makeImage(), for: 3)

        XCTAssertNotNil(cache.image(for: 1), "the thumbnail just refreshed should survive")
        XCTAssertNil(cache.image(for: 2), "the least-recent capture should be evicted")
        XCTAssertNotNil(cache.image(for: 3))
    }

    /// The invariant the overlay relies on for long uptimes: no matter how many
    /// distinct windows are seen across repeated sessions, the cache stays bounded.
    func testCountNeverExceedsLimitAcrossManyDistinctWindows() {
        let cache = PreviewCache()
        for round: CGWindowID in 0..<5 {
            for id: CGWindowID in 1...40 {
                cache.insert(makeImage(), for: round * 1000 + id)
            }
            XCTAssertLessThanOrEqual(cache.count, PreviewCache.defaultLimit)
        }
        XCTAssertEqual(cache.count, PreviewCache.defaultLimit)
    }

    func testMissingIDReturnsNil() {
        let cache = PreviewCache(limit: 2)
        XCTAssertNil(cache.image(for: 42))
    }

    func testRemoveAllDropsEveryRetainedImageAndResetsEvictionOrder() {
        let cache = PreviewCache(limit: 2)
        cache.insert(makeImage(), for: 1)
        cache.insert(makeImage(), for: 2)

        cache.removeAll()

        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.image(for: 1))
        XCTAssertNil(cache.image(for: 2))

        cache.insert(makeImage(), for: 3)
        cache.insert(makeImage(), for: 4)
        XCTAssertEqual(cache.count, 2)
        XCTAssertNotNil(cache.image(for: 3))
        XCTAssertNotNil(cache.image(for: 4))
    }
}
