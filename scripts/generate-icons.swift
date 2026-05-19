#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("walky-talky-logo.png")
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("WalkyTalkyIcon.iconset", isDirectory: true)
let icns = resources.appendingPathComponent("WalkyTalkyIcon.icns")
let blackLogo = resources.appendingPathComponent("WalkyTalkyLogoBlack.png")
let whiteLogo = resources.appendingPathComponent("WalkyTalkyLogoWhite.png")
let templateLogo = resources.appendingPathComponent("WalkyTalkyLogoTemplate.png")

guard let sourceImage = NSImage(contentsOf: source), let sourceRep = bitmap(from: sourceImage) else {
    fatalError("could not read \(source.path)")
}

let mask = extractLogoMask(from: sourceRep)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

try renderTransparentLogo(mask: mask, size: 1024, color: Pixel(r: 0, g: 0, b: 0, a: 255)).write(to: blackLogo)
try renderTransparentLogo(mask: mask, size: 1024, color: Pixel(r: 255, g: 255, b: 255, a: 255)).write(to: whiteLogo)
try renderTransparentLogo(mask: mask, size: 256, color: Pixel(r: 0, g: 0, b: 0, a: 255)).write(to: templateLogo)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let data = renderAppIcon(mask: mask, size: size)
    try data.write(to: iconset.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fatalError("iconutil failed")
}

print(icns.path)

struct Pixel {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

struct LogoMask {
    let width: Int
    let height: Int
    let alpha: [UInt8]
    let bounds: CGRect

    func alphaAt(x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return alpha[(y * width) + x]
    }
}

func bitmap(from image: NSImage) -> NSBitmapImageRep? {
    guard let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
}

func extractLogoMask(from rep: NSBitmapImageRep) -> LogoMask {
    let width = rep.pixelsWide
    let height = rep.pixelsHigh
    var alpha = Array(repeating: UInt8(0), count: width * height)
    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0

    for y in 0..<height {
        for x in 0..<width {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let luminance = (0.2126 * color.redComponent) + (0.7152 * color.greenComponent) + (0.0722 * color.blueComponent)
            let darkness = max(0, min(1, (0.34 - luminance) / 0.24)) * color.alphaComponent
            let value = darkness > 0.08 ? UInt8(min(255, max(0, darkness * 255))) : 0
            alpha[(y * width) + x] = value

            if value > 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    guard minX < maxX, minY < maxY else {
        fatalError("could not isolate logo mark")
    }

    return LogoMask(
        width: width,
        height: height,
        alpha: alpha,
        bounds: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    )
}

func renderTransparentLogo(mask: LogoMask, size: Int, color: Pixel) -> Data {
    render(mask: mask, size: size, background: nil, logoColor: color, padding: 0.14)
}

func renderAppIcon(mask: LogoMask, size: Int) -> Data {
    render(
        mask: mask,
        size: size,
        background: Pixel(r: 3, g: 3, b: 3, a: 255),
        logoColor: Pixel(r: 255, g: 255, b: 255, a: 255),
        padding: 0.22
    )
}

func render(mask: LogoMask, size: Int, background: Pixel?, logoColor: Pixel, padding: Double) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    )!

    let raw = rep.bitmapData!
    for y in 0..<size {
        for x in 0..<size {
            let offset = (y * rep.bytesPerRow) + (x * 4)
            let base = backgroundAlpha(atX: x, y: y, size: size, background: background)
            raw[offset + 0] = base.r
            raw[offset + 1] = base.g
            raw[offset + 2] = base.b
            raw[offset + 3] = base.a
        }
    }

    let targetWidth = Double(size) * (1 - (padding * 2))
    let targetHeight = targetWidth * (mask.bounds.height / mask.bounds.width)
    let targetX = (Double(size) - targetWidth) / 2
    let targetY = (Double(size) - targetHeight) / 2

    for y in max(0, Int(targetY))..<min(size, Int(ceil(targetY + targetHeight))) {
        for x in max(0, Int(targetX))..<min(size, Int(ceil(targetX + targetWidth))) {
            let normalizedX = (Double(x) - targetX) / targetWidth
            let normalizedY = (Double(y) - targetY) / targetHeight
            let sourceX = Int(mask.bounds.minX + (normalizedX * mask.bounds.width))
            let sourceY = Int(mask.bounds.minY + (normalizedY * mask.bounds.height))
            let sourceAlpha = mask.alphaAt(x: sourceX, y: sourceY)
            guard sourceAlpha > 0 else { continue }

            let offset = (y * rep.bytesPerRow) + (x * 4)
            raw[offset + 0] = logoColor.r
            raw[offset + 1] = logoColor.g
            raw[offset + 2] = logoColor.b
            raw[offset + 3] = sourceAlpha
        }
    }

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not render png")
    }
    return data
}

func backgroundAlpha(atX x: Int, y: Int, size: Int, background: Pixel?) -> Pixel {
    guard let background else {
        return Pixel(r: 0, g: 0, b: 0, a: 0)
    }

    let dimension = Double(size)
    let radius = dimension * 0.205
    let center = dimension / 2
    let half = dimension / 2
    let pixelX = Double(x) + 0.5
    let pixelY = Double(y) + 0.5
    let qx = abs(pixelX - center) - (half - radius)
    let qy = abs(pixelY - center) - (half - radius)
    let outsideX = max(qx, 0)
    let outsideY = max(qy, 0)
    let outsideDistance = hypot(outsideX, outsideY)
    let insideDistance = min(max(qx, qy), 0)
    let signedDistance = outsideDistance + insideDistance - radius
    let antialiasWidth = max(1.0, dimension / 512)
    let alpha = UInt8(max(0, min(255, (0.5 - (signedDistance / antialiasWidth)) * 255)))

    return Pixel(r: background.r, g: background.g, b: background.b, a: alpha)
}
