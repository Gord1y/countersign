import ApprovalCore
import SwiftUI

struct FirstRunTourView: View {
  let step: FirstRunTourStep
  var onSkip: () -> Void = {}
  var onBack: () -> Void = {}
  var onNext: () -> Void = {}

  private static let width: CGFloat = 420

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text(step.title)
          .font(.system(size: 16, weight: .semibold))
        FirstRunTourBodyView(segments: step.bodySegments)
          .foregroundStyle(.secondary)
      }
      HStack(alignment: .center) {
        FirstRunTourDots(current: step)
        Spacer(minLength: 12)
        HStack(spacing: 8) {
          if step != FirstRunTourStep.allCases.last {
            Button("Skip", action: onSkip)
              .buttonStyle(LinkButtonStyle())
          }
          if step != FirstRunTourStep.allCases.first {
            Button("Back", action: onBack)
              .buttonStyle(LinkButtonStyle())
          }
          Button(step == FirstRunTourStep.allCases.last ? "Done" : "Next", action: onNext)
            .buttonStyle(PrimaryButtonStyle())
        }
      }
    }
    .padding(24)
    .frame(width: Self.width, alignment: .leading)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

private struct FirstRunTourBodyView: View {
  let segments: [FirstRunTourSegment]

  private enum Token {
    case word(String)
    case key(String)
  }

  private var tokens: [Token] {
    segments.flatMap { segment in
      switch segment {
      case .text(let text):
        return text.split(separator: " ").map { Token.word(String($0)) }
      case .key(let key):
        return [Token.key(key)]
      }
    }
  }

  var body: some View {
    KeyHintFlowLayout(spacing: 5) {
      ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
        switch token {
        case .word(let word):
          Text(word)
            .font(PanelTypography.body)
        case .key(let key):
          KeyHint(key, placement: .link)
        }
      }
    }
  }
}

private struct FirstRunTourDots: View {
  let current: FirstRunTourStep

  var body: some View {
    HStack(spacing: 6) {
      ForEach(FirstRunTourStep.allCases, id: \.self) { step in
        Circle()
          .fill(step == current ? CountersignPalette.accentText : Color.primary.opacity(0.18))
          .frame(width: 6, height: 6)
      }
    }
  }
}
