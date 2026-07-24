import Foundation
import CoreGraphics

/// A greyscale image sampled at arbitrary continuous (u, v) coordinates for
/// Convolution's Displacement Map operation (Specs/Convolution.md §3.4).
/// Loaded once per project (see `SpriteScene.loadDisplacementMaps`) and
/// converted to a cached row-major brightness grid so repeated point-sampling
/// never re-decodes the source image.
///
/// `u`/`v` are always tiled — wrapped via modulo into `[0, 1)` before
/// sampling — because the whole point of this type is to support a pattern
/// that repeats across a shape any number of times (including an animated
/// scroll offset that accumulates past 1.0 over time), not a single
/// non-repeating placement.
public struct DisplacementMapImage: Sendable, Equatable {
    public let width:  Int
    public let height: Int
    /// Row-major, 0 (black) ... 1 (white). `count == width * height`.
    public let grid: [Double]

    public init(width: Int, height: Int, grid: [Double]) {
        self.width  = width
        self.height = height
        self.grid   = grid
    }

    /// Bilinear-sampled brightness at (u, v). Always wraps both coordinates
    /// into `[0, 1)` first, so values far outside that range (e.g. a scroll
    /// offset many cycles deep) tile seamlessly rather than needing a
    /// separate clamp or edge case.
    public func sample(u: Double, v: Double) -> Double {
        guard width > 0, height > 0, grid.count == width * height else { return 0.5 }

        let fx = wrapUnit(u) * Double(width)
        let fy = wrapUnit(v) * Double(height)
        let x0 = min(Int(fx), width - 1)
        let y0 = min(Int(fy), height - 1)
        let x1 = (x0 + 1) % width
        let y1 = (y0 + 1) % height
        let tx = fx - Double(x0)
        let ty = fy - Double(y0)

        let v00 = grid[y0 * width + x0]
        let v10 = grid[y0 * width + x1]
        let v01 = grid[y1 * width + x0]
        let v11 = grid[y1 * width + x1]
        let top = v00 + (v10 - v00) * tx
        let bot = v01 + (v11 - v01) * tx
        return top + (bot - top) * ty
    }

    private func wrapUnit(_ v: Double) -> Double {
        let m = v.truncatingRemainder(dividingBy: 1.0)
        return m < 0 ? m + 1.0 : m
    }

    /// Decodes `cgImage` into a cached greyscale grid, using the same
    /// draw-into-a-DeviceGray-context approach as `LoomEngine.brushMaskImage`
    /// — no separate luminance-weighting pass is needed since the context
    /// itself does the RGB-to-grey conversion during the draw.
    public static func load(from cgImage: CGImage) -> DisplacementMapImage? {
        let width  = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: width * height)
        let created: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else { return nil }

        let grid = buffer.map { Double($0) / 255.0 }
        return DisplacementMapImage(width: width, height: height, grid: grid)
    }
}
