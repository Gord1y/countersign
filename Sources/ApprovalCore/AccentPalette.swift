import Foundation

public struct HexColor: Sendable, Hashable {
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init?(hex: String) {
    let scalars = Array(hex.unicodeScalars)
    guard scalars.count == 7, scalars[0] == "#" else { return nil }
    var channels: [UInt8] = []
    for index in stride(from: 1, to: 7, by: 2) {
      guard let high = Self.hexDigit(scalars[index]), let low = Self.hexDigit(scalars[index + 1])
      else { return nil }
      channels.append(high * 16 + low)
    }
    self.init(red: channels[0], green: channels[1], blue: channels[2])
  }

  public var hex: String {
    "#"
      + [red, green, blue].map { channel in
        let digits = String(channel, radix: 16, uppercase: true)
        return channel < 16 ? "0" + digits : digits
      }.joined()
  }

  public var relativeLuminance: Double {
    0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
  }

  public func contrastRatio(with other: HexColor) -> Double {
    let lighter = max(relativeLuminance, other.relativeLuminance)
    let darker = min(relativeLuminance, other.relativeLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private static func linear(_ channel: UInt8) -> Double {
    let value = Double(channel) / 255
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }

  private static func hexDigit(_ scalar: Unicode.Scalar) -> UInt8? {
    switch scalar {
    case "0"..."9": return UInt8(scalar.value - 48)
    case "a"..."f": return UInt8(scalar.value - 87)
    case "A"..."F": return UInt8(scalar.value - 55)
    default: return nil
    }
  }
}

public enum AccentPreset: String, Sendable, CaseIterable {
  case amber
  case blue
  case green
  case purple
  case pink
  case graphite

  public var title: String {
    switch self {
    case .amber: return "Amber"
    case .blue: return "Blue"
    case .green: return "Green"
    case .purple: return "Purple"
    case .pink: return "Pink"
    case .graphite: return "Graphite"
    }
  }

  public var color: HexColor {
    switch self {
    case .amber: return HexColor(red: 0xE6, green: 0xB0, blue: 0x4A)
    case .blue: return HexColor(red: 0x5B, green: 0x9C, blue: 0xF6)
    case .green: return HexColor(red: 0x4C, green: 0xC3, blue: 0x8A)
    case .purple: return HexColor(red: 0xA7, green: 0x8B, blue: 0xFA)
    case .pink: return HexColor(red: 0xF4, green: 0x72, blue: 0xB6)
    case .graphite: return HexColor(red: 0xA1, green: 0xA1, blue: 0xAA)
    }
  }

  public static func name(of color: HexColor) -> String {
    allCases.first { $0.color == color }?.title ?? color.hex
  }
}

public struct AccentPalette: Sendable, Equatable {
  public static let minimumTextContrast = 4.5
  public static let darkLabel = HexColor(red: 0x1D, green: 0x1B, blue: 0x18)
  public static let lightLabel = HexColor(red: 0xFF, green: 0xFF, blue: 0xFF)
  public static let lightBackground = HexColor(red: 0xFF, green: 0xFF, blue: 0xFF)
  public static let darkBackground = HexColor(red: 0x1E, green: 0x1E, blue: 0x1E)
  static let amberLightText = HexColor(red: 0x9A, green: 0x6B, blue: 0x12)
  static let lightnessStep = 0.005

  public let fill: HexColor
  public let label: HexColor
  public let lightText: HexColor
  public let darkText: HexColor

  public init(accent: HexColor) {
    fill = accent
    label =
      accent.contrastRatio(with: Self.darkLabel) >= accent.contrastRatio(with: Self.lightLabel)
      ? Self.darkLabel : Self.lightLabel
    lightText =
      accent == AccentPreset.amber.color
      ? Self.amberLightText
      : Self.readable(accent, on: Self.lightBackground, towardLightness: 0)
    darkText = Self.readable(accent, on: Self.darkBackground, towardLightness: 1)
  }

  static func readable(_ color: HexColor, on background: HexColor, towardLightness target: Double)
    -> HexColor
  {
    let hsl = HSLColor(color)
    var lightness = hsl.lightness
    var candidate = color
    while candidate.contrastRatio(with: background) < minimumTextContrast, lightness != target {
      lightness =
        target < lightness
        ? max(target, lightness - lightnessStep) : min(target, lightness + lightnessStep)
      candidate = hsl.color(lightness: lightness)
    }
    return candidate
  }
}

struct HSLColor: Equatable {
  let hue: Double
  let saturation: Double
  let lightness: Double

  init(_ color: HexColor) {
    let red = Double(color.red) / 255
    let green = Double(color.green) / 255
    let blue = Double(color.blue) / 255
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    lightness = (maximum + minimum) / 2
    guard delta > 0 else {
      hue = 0
      saturation = 0
      return
    }
    saturation =
      lightness > 0.5 ? delta / (2 - maximum - minimum) : delta / (maximum + minimum)
    let sector: Double
    if maximum == red {
      sector = (green - blue) / delta + (green < blue ? 6 : 0)
    } else if maximum == green {
      sector = (blue - red) / delta + 2
    } else {
      sector = (red - green) / delta + 4
    }
    hue = sector / 6
  }

  func color(lightness: Double) -> HexColor {
    guard saturation > 0 else {
      let gray = Self.channel(lightness)
      return HexColor(red: gray, green: gray, blue: gray)
    }
    let upper =
      lightness < 0.5
      ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
    let lower = 2 * lightness - upper
    return HexColor(
      red: Self.channel(Self.component(lower, upper, hue + 1.0 / 3)),
      green: Self.channel(Self.component(lower, upper, hue)),
      blue: Self.channel(Self.component(lower, upper, hue - 1.0 / 3)))
  }

  private static func component(_ lower: Double, _ upper: Double, _ shiftedHue: Double) -> Double {
    var turn = shiftedHue
    if turn < 0 { turn += 1 }
    if turn > 1 { turn -= 1 }
    if turn < 1.0 / 6 { return lower + (upper - lower) * 6 * turn }
    if turn < 1.0 / 2 { return upper }
    if turn < 2.0 / 3 { return lower + (upper - lower) * (2.0 / 3 - turn) * 6 }
    return lower
  }

  private static func channel(_ value: Double) -> UInt8 {
    UInt8((min(max(value, 0), 1) * 255).rounded())
  }
}
