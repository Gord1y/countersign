import Testing

@testable import ApprovalCore

@Suite struct AccentPaletteTests {
  private static let customColors = [
    HexColor(red: 0x1A, green: 0x23, blue: 0x7E),
    HexColor(red: 0x80, green: 0x80, blue: 0x80),
    HexColor(red: 0xFF, green: 0xEB, blue: 0x3B),
  ]

  @Test func defaultAmberKeepsTodaysFourColors() {
    #expect(Settings.defaultAccentColor == AccentPreset.amber.color)
    let palette = AccentPalette(accent: Settings.defaultAccentColor)
    #expect(palette.fill.hex == "#E6B04A")
    #expect(palette.label.hex == "#1D1B18")
    #expect(palette.lightText.hex == "#9A6B12")
    #expect(palette.darkText.hex == "#E6B04A")
  }

  @Test func everyPresetsTextReadsInBothAppearancesUnderTheHigherContrastLabel() {
    #expect(
      AccentPreset.allCases.map(\.color.hex) == [
        "#E6B04A", "#5B9CF6", "#4CC38A", "#A78BFA", "#F472B6", "#A1A1AA",
      ])
    #expect(
      AccentPreset.allCases.map(\.title) == [
        "Amber", "Blue", "Green", "Purple", "Pink", "Graphite",
      ])
    for color in AccentPreset.allCases.map(\.color) + Self.customColors {
      let palette = AccentPalette(accent: color)
      #expect(palette.fill == color)
      #expect(
        palette.lightText.contrastRatio(with: AccentPalette.lightBackground)
          >= AccentPalette.minimumTextContrast)
      #expect(
        palette.darkText.contrastRatio(with: AccentPalette.darkBackground)
          >= AccentPalette.minimumTextContrast)
      let other =
        palette.label == AccentPalette.darkLabel
        ? AccentPalette.lightLabel : AccentPalette.darkLabel
      #expect([AccentPalette.darkLabel, AccentPalette.lightLabel].contains(palette.label))
      #expect(color.contrastRatio(with: palette.label) >= color.contrastRatio(with: other))
    }
    #expect(AccentPalette(accent: Self.customColors[0]).label == AccentPalette.lightLabel)
    #expect(AccentPalette(accent: AccentPreset.blue.color).lightText.hex == "#1270F2")
    #expect(AccentPalette(accent: Self.customColors[0]).darkText.hex == "#737DE2")
  }

  @Test func readsOnlyHashAndSixHexDigits() {
    #expect(HexColor(hex: "#E6B04A") == AccentPreset.amber.color)
    #expect(HexColor(hex: "#e6b04a") == AccentPreset.amber.color)
    #expect(HexColor(hex: "#0a0B0c")?.hex == "#0A0B0C")
    for invalid in [
      "", "#", "E6B04A", "#E6B04", "#E6B04A0", "#E6B04G", "#+6B04A", " #E6B04A", "#E6B04A ",
      "#E6B", "#Ｅ6B04A",
    ] {
      #expect(HexColor(hex: invalid) == nil, "\(invalid)")
    }
    #expect(AccentPreset.name(of: AccentPreset.blue.color) == "Blue")
    #expect(AccentPreset.name(of: HexColor(red: 1, green: 2, blue: 3)) == "#010203")
  }
}
