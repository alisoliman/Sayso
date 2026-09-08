import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draw directly into an opaque bitmap. AppKit's implicit graphics state can
// silently leave an empty bitmap when this generator runs without a window.
let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(srgbRed: 0.965, green: 0.955, blue: 0.94, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(CGColor(srgbRed: 0.30, green: 0.22, blue: 0.43, alpha: 1))
let heights: [CGFloat] = [102, 214, 344, 470, 344, 214, 102]
for (index, height) in heights.enumerated() {
    let x = CGFloat(index) * 78 + 257
    let rect = CGRect(x: x, y: (1024 - height) / 2, width: 42, height: height)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 21, cornerHeight: 21, transform: nil))
    context.fillPath()
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write the icon.") }
