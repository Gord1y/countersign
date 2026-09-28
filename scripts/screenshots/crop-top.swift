import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3, let height = Int(arguments[1]) else {
  fail("usage: swift crop-top.swift <in.png> <height-in-pixels> <out.png>")
}
let inputURL = URL(fileURLWithPath: arguments[0])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  fail("error: could not read \(arguments[0])")
}

guard height > 0 else {
  fail("error: height \(height) is not positive")
}
guard height <= image.height else {
  fail("error: height \(height) is larger than \(arguments[0])'s height \(image.height)")
}

let cropRect = CGRect(x: 0, y: 0, width: image.width, height: height)
guard let cropped = image.cropping(to: cropRect) else {
  fail("error: could not crop \(arguments[0])")
}

guard
  let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
  fail("error: could not write \(arguments[2])")
}
CGImageDestinationAddImage(destination, cropped, nil)
guard CGImageDestinationFinalize(destination) else {
  fail("error: could not write \(arguments[2])")
}
