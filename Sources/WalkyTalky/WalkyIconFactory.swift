import AppKit

enum WalkyIconFactory {
    static func menuBarIcon() -> NSImage {
        let image = loadLogo(
            named: "WalkyTalkyLogoTemplate",
            fallbackSize: 18,
            displaySize: NSSize(width: 18, height: 16.2),
            trimsTransparentPadding: true
        )
        image.isTemplate = true
        image.accessibilityDescription = "walky talky"
        return image
    }

    static func popoverIcon() -> NSImage {
        loadLogo(
            named: "WalkyTalkyLogoWhite",
            fallbackSize: 64,
            displaySize: NSSize(width: 64, height: 64)
        )
    }

    private static func loadLogo(
        named name: String,
        fallbackSize: CGFloat,
        displaySize: NSSize,
        trimsTransparentPadding: Bool = false
    ) -> NSImage {
        if let image = NSImage(named: name) {
            return prepared(image, to: displaySize, trimsTransparentPadding: trimsTransparentPadding)
        }

        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return prepared(image, to: displaySize, trimsTransparentPadding: trimsTransparentPadding)
        }

        return fallbackLogo(size: fallbackSize)
    }

    private static func prepared(
        _ image: NSImage,
        to size: NSSize,
        trimsTransparentPadding: Bool
    ) -> NSImage {
        let source = trimsTransparentPadding ? trimmedTransparentPadding(from: image) : image
        return resized(source, to: size)
    }

    private static func resized(_ image: NSImage, to size: NSSize) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = size
        return copy
    }

    private static func trimmedTransparentPadding(from image: NSImage) -> NSImage {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else {
            return image
        }

        var minX = rep.pixelsWide
        var minY = rep.pixelsHigh
        var maxX = 0
        var maxY = 0

        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.03 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard minX < maxX, minY < maxY else {
            return image
        }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        guard let cropped = rep.cgImage?.cropping(to: cropRect) else {
            return image
        }

        return NSImage(cgImage: cropped, size: cropRect.size)
    }

    private static func fallbackLogo(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        NSColor.labelColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = max(2, size * 0.08)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: size * 0.18, y: size * 0.54))
        path.curve(
            to: NSPoint(x: size * 0.42, y: size * 0.48),
            controlPoint1: NSPoint(x: size * 0.24, y: size * 0.76),
            controlPoint2: NSPoint(x: size * 0.30, y: size * 0.28)
        )
        path.curve(
            to: NSPoint(x: size * 0.82, y: size * 0.52),
            controlPoint1: NSPoint(x: size * 0.54, y: size * 0.72),
            controlPoint2: NSPoint(x: size * 0.58, y: size * 0.44)
        )
        path.stroke()

        image.unlockFocus()
        return image
    }
}
