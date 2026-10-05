import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(1)
}

func load(_ path: String) -> CGImage {
  guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else {
    fail("error: could not read \(path)")
  }
  return image
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3 else {
  fail("usage: swift compose-stack.swift <top.png> <bottom.png> <stack.png>")
}
guard arguments[2].hasSuffix(".png") else {
  fail("error: output path must end in .png")
}

let top = load(arguments[0])
let bottom = load(arguments[1])
let gap = 48
let width = max(top.width, bottom.width)
let height = top.height + gap + bottom.height

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
  fail("error: could not create the drawing context")
}

context.draw(
  bottom,
  in: CGRect(x: (width - bottom.width) / 2, y: 0, width: bottom.width, height: bottom.height))
context.draw(
  top,
  in: CGRect(
    x: (width - top.width) / 2, y: bottom.height + gap, width: top.width, height: top.height))

guard let image = context.makeImage(),
  let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
  fail("error: could not create \(arguments[2])")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
  fail("error: could not write \(arguments[2])")
}
