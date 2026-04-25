import CoreGraphics

extension LoomColor {
    /// A `CGColor` in the device RGB color space.
    public var cgColor: CGColor {
        CGColor(
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            components: [
                CGFloat(r) / 255.0,
                CGFloat(g) / 255.0,
                CGFloat(b) / 255.0,
                CGFloat(a) / 255.0
            ]
        )!
    }
}
