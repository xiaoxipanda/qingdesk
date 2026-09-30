import Foundation
import CoreGraphics

/// Fixed-size cards, with only complete rows admitted to the visible page.
public struct LauncherGridGeometry: Sendable {
    public static let cellWidth: CGFloat = 108
    public static let cellHeight: CGFloat = 112
    public static let columnGap: CGFloat = 24
    public static let rowGap: CGFloat = 18
    public let columns: Int
    public let rows: Int
    public var capacity: Int { columns * rows }
    public var contentSize: CGSize {
        CGSize(width: CGFloat(columns) * Self.cellWidth + CGFloat(columns - 1) * Self.columnGap,
               height: CGFloat(rows) * Self.cellHeight + CGFloat(rows - 1) * Self.rowGap)
    }

    public init(availableSize: CGSize) {
        columns = max(1, min(5, Int((availableSize.width + Self.columnGap) / (Self.cellWidth + Self.columnGap))))
        rows = max(1, min(3, Int((availableSize.height + Self.rowGap) / (Self.cellHeight + Self.rowGap))))
    }
    public func pageCount(itemCount: Int) -> Int {
        max(1, (max(0, itemCount) + capacity - 1) / capacity)
    }
    public func normalizedPage(_ page: Int, itemCount: Int) -> Int {
        min(max(0, page), pageCount(itemCount: itemCount) - 1)
    }
    public func range(page: Int, itemCount: Int) -> Range<Int> {
        let count = max(0, itemCount)
        let start = normalizedPage(page, itemCount: count) * capacity
        return start..<min(start + capacity, count)
    }
}
