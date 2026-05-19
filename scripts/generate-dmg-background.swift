#!/usr/bin/env swift
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("usage: generate-dmg-background.swift <output.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: args[1])
let size = NSSize(width: 760, height: 480)
let image = NSImage(size: size)

func roundedFont(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.rounded),
       let font = NSFont(descriptor: descriptor, size: size) {
        return font
    }
    return base
}

func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center, width: CGFloat = 680) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: font.pointSize * 0.01
    ]
    let rect = NSRect(x: point.x, y: point.y, width: width, height: 80)
    NSString(string: text).draw(in: rect, withAttributes: attributes)
}

func drawRoundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func drawArrow(from start: NSPoint, to end: NSPoint) {
    let path = NSBezierPath()
    path.move(to: start)
    path.curve(to: end, controlPoint1: NSPoint(x: start.x + 72, y: start.y + 28), controlPoint2: NSPoint(x: end.x - 72, y: end.y + 28))
    NSColor(calibratedRed: 0.84, green: 0.95, blue: 0.84, alpha: 0.9).setStroke()
    path.lineWidth = 5
    path.lineCapStyle = .round
    path.stroke()

    let angle = atan2(end.y - start.y, end.x - start.x)
    let head = NSBezierPath()
    head.move(to: end)
    head.line(to: NSPoint(x: end.x - 18 * cos(angle - .pi / 7), y: end.y - 18 * sin(angle - .pi / 7)))
    head.move(to: end)
    head.line(to: NSPoint(x: end.x - 18 * cos(angle + .pi / 7), y: end.y - 18 * sin(angle + .pi / 7)))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.stroke()
}

image.lockFocus()

NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.063, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.38, green: 0.80, blue: 0.46, alpha: 0.24),
    NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.063, alpha: 0)
])
glow?.draw(in: NSBezierPath(ovalIn: NSRect(x: 220, y: 80, width: 320, height: 220)), angle: 0)

drawRoundedRect(
    NSRect(x: 22, y: 24, width: 716, height: 432),
    radius: 28,
    fill: NSColor(calibratedRed: 0.075, green: 0.075, blue: 0.086, alpha: 0.84),
    stroke: NSColor(calibratedRed: 0.19, green: 0.19, blue: 0.21, alpha: 1),
    lineWidth: 1.5
)

drawText(
    "walky talky",
    at: NSPoint(x: 40, y: 374),
    font: roundedFont(34, weight: .bold),
    color: .white,
    width: 680
)

drawText(
    "drag the app into applications",
    at: NSPoint(x: 40, y: 333),
    font: roundedFont(17, weight: .semibold),
    color: NSColor(calibratedRed: 0.72, green: 0.72, blue: 0.77, alpha: 1),
    width: 680
)

drawArrow(from: NSPoint(x: 280, y: 218), to: NSPoint(x: 480, y: 218))

drawRoundedRect(
    NSRect(x: 84, y: 72, width: 592, height: 56),
    radius: 16,
    fill: NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.115, alpha: 1),
    stroke: NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.22, alpha: 1)
)

drawText(
    "open from applications. keep whisper models outside the app.",
    at: NSPoint(x: 112, y: 91),
    font: roundedFont(14, weight: .medium),
    color: NSColor(calibratedRed: 0.66, green: 0.66, blue: 0.70, alpha: 1),
    width: 536
)

drawText(
    "walky talky",
    at: NSPoint(x: 116, y: 143),
    font: roundedFont(15, weight: .semibold),
    color: NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.90, alpha: 1),
    width: 180
)

drawText(
    "applications",
    at: NSPoint(x: 466, y: 143),
    font: roundedFont(15, weight: .semibold),
    color: NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.90, alpha: 1),
    width: 180
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render dmg background\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
