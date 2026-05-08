import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DefaultBrushes {

    static func write(to directory: URL) {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let size = 64

        func makeCtx() -> CGContext? {
            CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                      bytesPerRow: 0, space: cs, bitmapInfo: bitmapInfo.rawValue)
        }

        func savePNG(_ image: CGImage, name: String) {
            let url = directory.appendingPathComponent(name) as CFURL
            guard let dest = CGImageDestinationCreateWithURL(
                url, UTType.png.identifier as CFString, 1, nil
            ) else { return }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }

        // circle.png — hard-edged white circle on black
        if let ctx = makeCtx() {
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx.fillEllipse(in: CGRect(x: 4, y: 4, width: size - 8, height: size - 8))
            if let img = ctx.makeImage() { savePNG(img, name: "circle.png") }
        }

        // soft_circle.png — radial gradient white-to-black
        if let ctx = makeCtx() {
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let center = CGPoint(x: Double(size) / 2, y: Double(size) / 2)
            let locs: [CGFloat] = [0, 1]
            let cols = [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                        CGColor(red: 0, green: 0, blue: 0, alpha: 1)] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: cols, locations: locs) {
                ctx.drawRadialGradient(grad,
                    startCenter: center, startRadius: 0,
                    endCenter:   center, endRadius: Double(size) / 2.0 - 1,
                    options: .drawsAfterEndLocation)
            }
            if let img = ctx.makeImage() { savePNG(img, name: "soft_circle.png") }
        }

        // scatter.png — small white dots at seeded positions on black
        if let ctx = makeCtx() {
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            var seed: UInt64 = 0xCAFE_BABE_1234_5678
            func rnd() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(seed >> 33) / Double(1 << 31)
            }
            for _ in 0..<20 {
                let x = rnd() * Double(size - 8) + 4
                let y = rnd() * Double(size - 8) + 4
                let r = rnd() * 2.5 + 1.5
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            if let img = ctx.makeImage() { savePNG(img, name: "scatter.png") }
        }
    }
}
