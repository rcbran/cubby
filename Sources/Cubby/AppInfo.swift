import AppKit
import ImageIO

/// App icons and their signature colors, which tint each card's header.
@MainActor
enum AppInfo {
    private static var icons: [String: NSImage] = [:]
    private static var colors: [String: NSColor] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    /// The icon's most vivid color, darkened enough for white text on top.
    static func color(for bundleID: String?) -> NSColor {
        guard let bundleID else { return .systemGray }
        if let cached = colors[bundleID] { return cached }
        let color = icon(for: bundleID).flatMap(dominantColor) ?? .systemGray
        colors[bundleID] = color
        return color
    }

    private static func dominantColor(of image: NSImage) -> NSColor? {
        let size = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        // Weight each pixel by how vivid it is, so white backgrounds and black outlines don't win.
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for x in 0..<size {
            for y in 0..<size {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { continue }
                let weight = c.saturationComponent * c.saturationComponent * c.brightnessComponent
                r += c.redComponent * weight
                g += c.greenComponent * weight
                b += c.blueComponent * weight
                total += weight
            }
        }
        guard total > 2 else { return nil }  // a gray or monochrome icon
        let mix = NSColor(srgbRed: r / total, green: g / total, blue: b / total, alpha: 1)
        return NSColor(hue: mix.hueComponent,
                       saturation: min(max(mix.saturationComponent, 0.45), 0.85),
                       brightness: min(max(mix.brightnessComponent, 0.45), 0.72),
                       alpha: 1)
    }
}

/// Downsized copies of clipboard images, so cards don't decode full screenshots on every redraw.
@MainActor
enum Thumbnails {
    private static var cache: [URL: NSImage] = [:]

    static func image(at url: URL) -> NSImage? {
        if let cached = cache[url] { return cached }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: 520,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = NSImage(cgImage: cg, size: .zero)
        cache[url] = image
        return image
    }

    static func pixelSize(at url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }
}
