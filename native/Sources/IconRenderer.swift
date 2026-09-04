import AppKit

struct RenderedIcon {
    let data: Data
    let pixels: Int
}

enum IconError: Error, LocalizedError {
    case notAnImage

    var errorDescription: String? {
        switch self {
        case .notAnImage:
            return "The downloaded data isn't a valid image."
        }
    }
}

nonisolated enum IconRenderer {
    static func render(
        _ data: Data, size: Int, upscale: Bool, output: Int? = nil
    ) async throws -> RenderedIcon {
        guard let image = NSBitmapImageRep(data: data) else {
            throw IconError.notAnImage
        }
        if let output, output != image.pixelsWide {
            guard let scaled = resize(image, to: output) else { throw IconError.notAnImage }
            return RenderedIcon(data: scaled, pixels: output)
        }
        if upscale, image.pixelsWide < size, let scaled = resize(image, to: size) {
            return RenderedIcon(data: scaled, pixels: size)
        }
        guard let png = image.representation(using: .png, properties: [:]) else {
            throw IconError.notAnImage
        }
        return RenderedIcon(data: png, pixels: image.pixelsWide)
    }

    private static func resize(_ image: NSBitmapImageRep, to size: Int) -> Data? {
        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        target.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        return target.representation(using: .png, properties: [:])
    }
}
