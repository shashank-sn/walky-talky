#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("voice grey.icns")
let output = root
    .appendingPathComponent("Resources", isDirectory: true)
    .appendingPathComponent("WalkyTalkyLogoTemplate.png")

guard let image = NSImage(contentsOf: source),
      let tiff = image.tiffRepresentation,
      let input = NSBitmapImageRep(data: tiff)
else {
    fatalError("could not read \(source.path)")
}

let width = input.pixelsWide
let height = input.pixelsHigh
var alpha = Array(repeating: UInt8(0), count: width * height)

for y in 0..<height {
    for x in 0..<width {
        guard let color = input.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let luminance = (0.2126 * color.redComponent)
            + (0.7152 * color.greenComponent)
            + (0.0722 * color.blueComponent)
        let bubble = max(0, min(1, (luminance - 0.62) / 0.18)) * color.alphaComponent
        let value = bubble > 0.08 ? UInt8(min(255, max(0, bubble * 255))) : 0
        alpha[(y * width) + x] = value

    }
}

let component = centeredComponent(alpha: alpha, width: width, height: height)
alpha = component.alpha

guard let bounds = component.bounds else {
    fatalError("could not isolate chat bubble")
}

let minX = bounds.minX
let minY = bounds.minY
let maxX = bounds.maxX
let maxY = bounds.maxY

let padding = 28
let cropMinX = max(0, minX - padding)
let cropMinY = max(0, minY - padding)
let cropMaxX = min(width - 1, maxX + padding)
let cropMaxY = min(height - 1, maxY + padding)
let cropWidth = cropMaxX - cropMinX + 1
let cropHeight = cropMaxY - cropMinY + 1

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: cropWidth,
    pixelsHigh: cropHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: cropWidth * 4,
    bitsPerPixel: 32
)!

let raw = rep.bitmapData!
for y in 0..<cropHeight {
    for x in 0..<cropWidth {
        let sourceX = cropMinX + x
        let sourceY = cropMinY + y
        let value = alpha[(sourceY * width) + sourceX]
        let offset = (y * rep.bytesPerRow) + (x * 4)
        raw[offset + 0] = 0
        raw[offset + 1] = 0
        raw[offset + 2] = 0
        raw[offset + 3] = value
    }
}

guard let data = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not write png")
}

try data.write(to: output)
print(output.path)

struct Bounds {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
}

func centeredComponent(alpha: [UInt8], width: Int, height: Int) -> (alpha: [UInt8], bounds: Bounds?) {
    var visited = Array(repeating: false, count: width * height)
    var bestPixels: [Int] = []
    var bestScore = Double.greatestFiniteMagnitude
    let centerX = Double(width) / 2
    let centerY = Double(height) / 2

    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width) + x
            guard alpha[index] > 0, !visited[index] else { continue }

            var queue = [index]
            var cursor = 0
            visited[index] = true
            var pixels: [Int] = []
            var sumX = 0
            var sumY = 0

            while cursor < queue.count {
                let current = queue[cursor]
                cursor += 1
                pixels.append(current)
                let px = current % width
                let py = current / width
                sumX += px
                sumY += py

                for neighbor in neighbors(x: px, y: py, width: width, height: height) {
                    guard alpha[neighbor] > 0, !visited[neighbor] else { continue }
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }

            guard pixels.count > 500 else { continue }
            let centroidX = Double(sumX) / Double(pixels.count)
            let centroidY = Double(sumY) / Double(pixels.count)
            let centerDistance = hypot(centroidX - centerX, centroidY - centerY)
            let score = centerDistance - (Double(pixels.count) / 10_000)
            if score < bestScore {
                bestScore = score
                bestPixels = pixels
            }
        }
    }

    guard !bestPixels.isEmpty else {
        return (Array(repeating: 0, count: width * height), nil)
    }

    var result = Array(repeating: UInt8(0), count: width * height)
    var minX = width
    var minY = height
    var maxX = 0
    var maxY = 0

    for index in bestPixels {
        result[index] = alpha[index]
        let x = index % width
        let y = index / width
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }

    return (result, Bounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY))
}

func neighbors(x: Int, y: Int, width: Int, height: Int) -> [Int] {
    var values: [Int] = []
    for dy in -1...1 {
        for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = x + dx
            let ny = y + dy
            if nx >= 0, ny >= 0, nx < width, ny < height {
                values.append((ny * width) + nx)
            }
        }
    }
    return values
}
