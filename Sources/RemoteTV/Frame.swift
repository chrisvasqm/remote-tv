import AppKit
import ImageIO

/// A decoded screenshot, scaled down to the panel size off the main thread.
struct Frame: @unchecked Sendable {
    let image: NSImage
    let isNearlyBlack: Bool

    static func decode(_ data: Data) async -> Frame? {
        await Task.detached(priority: .utility) {
            // A frame read while the TV was overwriting its file is cut short: skip it.
            guard data.count > 2, data.suffix(2).elementsEqual([0xFF, 0xD9]),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      // The preview is 252 pt wide: 504 px on a Retina screen.
                      kCGImageSourceThumbnailMaxPixelSize: 560,
                  ] as CFDictionary) else { return nil }
            let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
            return Frame(image: image, isNearlyBlack: nearlyBlack(thumbnail))
        }.value
    }

    /// DRM-protected apps and HDMI inputs capture as a black frame.
    private static func nearlyBlack(_ image: CGImage) -> Bool {
        let width = 16, height = 9
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Skip the alpha byte of each RGBA pixel.
        return pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element < 12 }
    }
}
