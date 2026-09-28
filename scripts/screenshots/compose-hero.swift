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
  fail("usage: swift compose-hero.swift <snapshot.png> <hero.png>")
}
let inputURL = URL(fileURLWithPath: arguments[0])
let outputURL = URL(fileURLWithPath: arguments[1])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
  let panel = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  fail("error: could not read \(arguments[0])")
}

let pixelsPerPoint: CGFloat = 2
let panelCornerRadius = 18 * pixelsPerPoint
let canvasCornerRadius = 24 * pixelsPerPoint
let panelWidth = CGFloat(panel.width)
let panelHeight = CGFloat(panel.height)
let horizontalMargin = (panelWidth * 0.2).rounded()
let verticalMargin = (panelWidth * 0.14).rounded()
let canvas = CGRect(
  x: 0, y: 0, width: panelWidth + 2 * horizontalMargin, height: panelHeight + 2 * verticalMargin)
let panelRect = CGRect(
  x: horizontalMargin, y: verticalMargin, width: panelWidth, height: panelHeight)

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

context.addPath(
  CGPath(
    roundedRect: canvas, cornerWidth: canvasCornerRadius, cornerHeight: canvasCornerRadius,
    transform: nil))
context.clip()
context.drawLinearGradient(
  background, start: CGPoint(x: canvas.minX, y: canvas.minY),
  end: CGPoint(x: canvas.maxX, y: canvas.maxY), options: [])
context.drawRadialGradient(
  glow, startCenter: CGPoint(x: canvas.midX, y: canvas.midY), startRadius: 0,
  endCenter: CGPoint(x: canvas.midX, y: canvas.midY), endRadius: canvas.width * 0.42, options: [])

context.saveGState()
context.setShadow(
  offset: CGSize(width: 0, height: -12 * pixelsPerPoint), blur: 40 * pixelsPerPoint,
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

guard let hero = context.makeImage(),
  let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
  fail("error: could not encode the hero image")
}
let dotsPerInch = 72 * pixelsPerPoint
CGImageDestinationAddImage(
  destination, hero,
  [kCGImagePropertyDPIWidth: dotsPerInch, kCGImagePropertyDPIHeight: dotsPerInch] as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
  fail("error: could not write \(arguments[1])")
}
