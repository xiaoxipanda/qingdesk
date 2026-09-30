import Foundation
import CoreGraphics

public enum LayoutGeometry {
    /// AX coordinates have their origin at the primary display's top-left.
    public static func frames(for preset: LayoutPreset, in bounds: CGRect,
                              gap: CGFloat = 12, margin: CGFloat = 12) throws -> [CGRect] {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width > 0, bounds.height > 0, gap.isFinite, margin.isFinite,
              gap >= 0, margin >= 0, gap <= 80, margin <= 80 else {
            throw WorkbenchFailure("invalid_geometry", "显示器尺寸或窗口间距无效。")
        }
        let box = bounds.insetBy(dx: margin, dy: margin)
        guard box.width > gap + 100, box.height > gap + 100 else {
            throw WorkbenchFailure("screen_too_small", "显示器可用区域不足以放置窗口。")
        }
        let w = (box.width - gap) / 2, h = (box.height - gap) / 2
        switch preset {
        case .single: return [box]
        case .topBottom:
            return [CGRect(x: box.minX, y: box.minY, width: box.width, height: h),
                    CGRect(x: box.minX, y: box.minY + h + gap, width: box.width, height: h)]
        case .grid:
            return [CGRect(x: box.minX, y: box.minY, width: w, height: h),
                    CGRect(x: box.minX + w + gap, y: box.minY, width: w, height: h),
                    CGRect(x: box.minX, y: box.minY + h + gap, width: w, height: h),
                    CGRect(x: box.minX + w + gap, y: box.minY + h + gap, width: w, height: h)]
        case .leftRight, .focusLeft, .focusRight:
            let ratio: CGFloat = preset == .focusLeft ? 0.65 : preset == .focusRight ? 0.35 : 0.5
            let left = (box.width - gap) * ratio
            return [CGRect(x: box.minX, y: box.minY, width: left, height: box.height),
                    CGRect(x: box.minX + left + gap, y: box.minY,
                           width: box.width - left - gap, height: box.height)]
        }
    }
    public static func axRect(cocoaRect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: cocoaRect.minX, y: primaryTop - cocoaRect.maxY,
               width: cocoaRect.width, height: cocoaRect.height)
    }
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
