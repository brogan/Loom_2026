import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Greyscale PNG export

/// Export a float grid [row][col] (0.0–1.0) as a greyscale PNG at the given output dimensions.
/// The grid is resampled to (outW × outH) using nearest-neighbour scaling via CoreGraphics.
func exportGreyscalePNG(grid: [[Float]], outW: Int, outH: Int, to url: URL) throws {
    let rows = grid.count
    let cols = rows > 0 ? grid[0].count : 0
    guard rows > 0, cols > 0, outW > 0, outH > 0 else {
        throw BrushIOError.invalidDimensions
    }

    // 1. Render grid at native resolution into a greyscale CGContext.
    let cs = CGColorSpaceCreateDeviceGray()
    guard let nativeCtx = CGContext(
        data: nil, width: cols, height: rows,
        bitsPerComponent: 8, bytesPerRow: cols,
        space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { throw BrushIOError.contextCreationFailed }

    guard let buf = nativeCtx.data else { throw BrushIOError.contextCreationFailed }
    let pixels = buf.bindMemory(to: UInt8.self, capacity: rows * cols)
    for r in 0 ..< rows {
        let row = grid[r]
        for c in 0 ..< cols {
            let v = row.count > c ? row[c] : 0
            pixels[r * cols + c] = UInt8(max(0, min(255, Int((v * 255).rounded()))))
        }
    }
    guard let nativeImage = nativeCtx.makeImage() else { throw BrushIOError.imageCreationFailed }

    // 2. Resample to output dimensions.
    let finalImage: CGImage
    if outW == cols && outH == rows {
        finalImage = nativeImage
    } else {
        guard let outCtx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: 8, bytesPerRow: outW,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw BrushIOError.contextCreationFailed }
        outCtx.interpolationQuality = .medium
        outCtx.draw(nativeImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let img = outCtx.makeImage() else { throw BrushIOError.imageCreationFailed }
        finalImage = img
    }

    // 3. Write PNG.
    try writePNG(finalImage, to: url)
}

// MARK: - Greyscale PNG import

/// Load a PNG from disk and convert it to a float grid [row][col] (0.0–1.0).
/// Returns the grid at the image's native pixel dimensions.
func loadGreyscalePNG(from url: URL) throws -> (grid: [[Float]], rows: Int, cols: Int) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw BrushIOError.loadFailed(url) }

    let w = cgImg.width
    let h = cgImg.height
    guard w > 0, h > 0 else { throw BrushIOError.invalidDimensions }

    let cs = CGColorSpaceCreateDeviceGray()
    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w,
        space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { throw BrushIOError.contextCreationFailed }

    ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let buf = ctx.data else { throw BrushIOError.contextCreationFailed }
    let pixels = buf.bindMemory(to: UInt8.self, capacity: w * h)

    var grid = [[Float]](repeating: [Float](repeating: 0, count: w), count: h)
    for r in 0 ..< h {
        for c in 0 ..< w {
            grid[r][c] = Float(pixels[r * w + c]) / 255.0
        }
    }
    return (grid, h, w)
}

// MARK: - RGBA PNG export

/// Export a 2-D RGBA grid as a full-colour PNG at the given output dimensions.
func exportRGBAPNG(grid: [[RGBAPixel]], outW: Int, outH: Int, to url: URL) throws {
    let rows = grid.count
    let cols = rows > 0 ? grid[0].count : 0
    guard rows > 0, cols > 0, outW > 0, outH > 0 else {
        throw BrushIOError.invalidDimensions
    }

    let cs   = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    let bpr  = cols * 4

    guard let nativeCtx = CGContext(
        data: nil, width: cols, height: rows,
        bitsPerComponent: 8, bytesPerRow: bpr,
        space: cs, bitmapInfo: info
    ) else { throw BrushIOError.contextCreationFailed }

    guard let buf = nativeCtx.data else { throw BrushIOError.contextCreationFailed }
    let pixels = buf.bindMemory(to: UInt8.self, capacity: rows * bpr)
    for r in 0 ..< rows {
        let row = grid[r]
        for c in 0 ..< cols {
            let p = row.count > c ? row[c] : RGBAPixel()
            let base = r * bpr + c * 4
            // premultiply alpha for CGContext premultipliedLast
            let a = p.a
            let af = Float(a) / 255.0
            pixels[base]     = UInt8((Float(p.r) * af).rounded())
            pixels[base + 1] = UInt8((Float(p.g) * af).rounded())
            pixels[base + 2] = UInt8((Float(p.b) * af).rounded())
            pixels[base + 3] = a
        }
    }
    guard let nativeImage = nativeCtx.makeImage() else { throw BrushIOError.imageCreationFailed }

    let finalImage: CGImage
    if outW == cols && outH == rows {
        finalImage = nativeImage
    } else {
        guard let outCtx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: 8, bytesPerRow: outW * 4,
            space: cs, bitmapInfo: info
        ) else { throw BrushIOError.contextCreationFailed }
        outCtx.interpolationQuality = .medium
        outCtx.draw(nativeImage, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let img = outCtx.makeImage() else { throw BrushIOError.imageCreationFailed }
        finalImage = img
    }

    try writePNG(finalImage, to: url)
}

// MARK: - RGBA PNG import

/// Load a PNG and return it as a 2-D RGBA grid at native resolution.
func loadRGBAPNG(from url: URL) throws -> (grid: [[RGBAPixel]], rows: Int, cols: Int) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw BrushIOError.loadFailed(url) }

    let w   = cgImg.width
    let h   = cgImg.height
    guard w > 0, h > 0 else { throw BrushIOError.invalidDimensions }

    let cs   = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    let bpr  = w * 4

    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: bpr,
        space: cs, bitmapInfo: info
    ) else { throw BrushIOError.contextCreationFailed }

    ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let buf = ctx.data else { throw BrushIOError.contextCreationFailed }
    let pixels = buf.bindMemory(to: UInt8.self, capacity: h * bpr)

    var grid = [[RGBAPixel]](repeating: [RGBAPixel](repeating: RGBAPixel(), count: w), count: h)
    for r in 0 ..< h {
        for c in 0 ..< w {
            let base = r * bpr + c * 4
            let a  = pixels[base + 3]
            // un-premultiply
            let af = a > 0 ? 255.0 / Float(a) : 0
            grid[r][c] = RGBAPixel(
                r: UInt8(min(255, Float(pixels[base])     * af)),
                g: UInt8(min(255, Float(pixels[base + 1]) * af)),
                b: UInt8(min(255, Float(pixels[base + 2]) * af)),
                a: a
            )
        }
    }
    return (grid, h, w)
}

// MARK: - Meta JSON sidecar

private let metaExtension = ".meta.json"

/// Persist grid/output dimensions alongside the PNG so the editor can reopen
/// the file at the correct working resolution.
func saveMetaJSON(forFile url: URL, gridW: Int, gridH: Int, outW: Int, outH: Int) throws {
    let meta: [String: Int] = ["grid_w": gridW, "grid_h": gridH, "out_w": outW, "out_h": outH]
    let data = try JSONEncoder().encode(meta)
    let metaURL = url.appendingPathExtension(String(metaExtension.dropFirst()))  // .meta.json
    try data.write(to: metaURL)
}

/// Load grid/output dimensions from sidecar. Returns nil when sidecar is absent.
func loadMetaJSON(forFile url: URL) -> (gridW: Int, gridH: Int, outW: Int, outH: Int)? {
    // Try both ".png.meta.json" and ".meta.json" appended forms
    let candidates = [
        url.appendingPathExtension("meta.json"),
        URL(fileURLWithPath: url.path + metaExtension)
    ]
    for metaURL in candidates {
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode([String: Int].self, from: data),
              let gw = meta["grid_w"], let gh = meta["grid_h"],
              let ow = meta["out_w"],  let oh = meta["out_h"]
        else { continue }
        return (gw, gh, ow, oh)
    }
    return nil
}

// MARK: - Shared helpers

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw BrushIOError.writeFailed(url) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw BrushIOError.writeFailed(url) }
}

// MARK: - Shared pixel type

/// Full-colour pixel used by stamp/stencil grids.
struct RGBAPixel: Equatable {
    var r: UInt8 = 0
    var g: UInt8 = 0
    var b: UInt8 = 0
    var a: UInt8 = 0  // 0 = fully transparent

    static let clear = RGBAPixel(r: 0, g: 0, b: 0, a: 0)
    static let black = RGBAPixel(r: 0, g: 0, b: 0, a: 255)
}

// MARK: - Errors

enum BrushIOError: LocalizedError {
    case invalidDimensions
    case contextCreationFailed
    case imageCreationFailed
    case loadFailed(URL)
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .invalidDimensions:       return "Grid or output dimensions are zero."
        case .contextCreationFailed:   return "Failed to create CGContext."
        case .imageCreationFailed:     return "Failed to create CGImage from context."
        case .loadFailed(let u):       return "Could not load image at \(u.lastPathComponent)."
        case .writeFailed(let u):      return "Could not write PNG to \(u.lastPathComponent)."
        }
    }
}
