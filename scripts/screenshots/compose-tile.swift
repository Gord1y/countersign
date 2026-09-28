import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(1)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
  fail("usage: swift compose-tile.swift <snapshot.png> <tile.jpg>")
}
guard arguments[1].hasSuffix(".jpg") else {
  fail("error: output path must end in .jpg")
}
let inputURL = URL(fileURLWithPath: arguments[0])
let outputURL = URL(fileURLWithPath: arguments[1])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
  let panel = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  fail("error: could not read \(arguments[0])")
}

let canvasWidth: CGFloat = 1600
let canvasHeight: CGFloat = 1200
let maxContentWidth: CGFloat = 1360
let maxContentHeight: CGFloat = 1008
let pixelsPerPoint: CGFloat = 2
let panelWidth = CGFloat(panel.width)
let panelHeight = CGFloat(panel.height)
let scale = min(1, min(maxContentWidth / panelWidth, maxContentHeight / panelHeight))
let scaledWidth = (panelWidth * scale).rounded()
let scaledHeight = (panelHeight * scale).rounded()
let panelCornerRadius = 18 * pixelsPerPoint * scale
let canvas = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
let panelRect = CGRect(
  x: ((canvasWidth - scaledWidth) / 2).rounded(), y: ((canvasHeight - scaledHeight) / 2).rounded(),
  width: scaledWidth, height: scaledHeight)

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
  let context = CGContext(
    data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8,
    bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
  let background = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0x241833), color(0x8A3B2A), color(0xE6B04A)] as CFArray,
    locations: [0, 0.55, 1]),
  let glow = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(0xFFFFFF, alpha: 0.14), color(0xFFFFFF, alpha: 0)] as CFArray,
    locations: [0, 1])
else {
  fail("error: could not create the drawing context")
}

context.drawLinearGradient(
  background, start: CGPoint(x: canvas.minX, y: canvas.minY),
  end: CGPoint(x: canvas.maxX, y: canvas.maxY), options: [])
context.drawRadialGradient(
  glow, startCenter: CGPoint(x: canvas.midX, y: canvas.midY), startRadius: 0,
  endCenter: CGPoint(x: canvas.midX, y: canvas.midY), endRadius: canvas.width * 0.42, options: [])

context.saveGState()
context.setShadow(
  offset: CGSize(width: 0, height: -12 * pixelsPerPoint * scale), blur: 40 * pixelsPerPoint * scale,
  color: color(0x000000, alpha: 0.45))
context.beginTransparencyLayer(auxiliaryInfo: nil)
context.addPath(
  CGPath(
    roundedRect: panelRect, cornerWidth: panelCornerRadius, cornerHeight: panelCornerRadius,
    transform: nil))
context.clip()
context.draw(panel, in: panelRect)
context.endTransparencyLayer()
context.restoreGState()

guard let tile = context.makeImage(),
  let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
else {
  fail("error: could not encode the tile image")
}
let dotsPerInch = 72 * pixelsPerPoint
CGImageDestinationAddImage(
  destination, tile,
  [
    kCGImagePropertyDPIWidth: dotsPerInch, kCGImagePropertyDPIHeight: dotsPerInch,
    kCGImageDestinationLossyCompressionQuality: 0.92,
  ] as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
  fail("error: could not write \(arguments[1])")
}
