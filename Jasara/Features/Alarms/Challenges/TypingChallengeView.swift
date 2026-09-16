import SwiftUI

struct TypingChallengeView: View {
    var tier: Tier
    var rounds: Int
    var wordCount: Int
    /// Phrases prepared when the alarm was saved. Empty falls back to a fresh one.
    var prepared: [String]
    var onComplete: () -> Void

    @State private var round = 0
    @State private var phrase = ""
    @State private var typed = ""
    @FocusState private var focused: Bool

    private var matches: Bool { typed == phrase }

    var body: some View {
        VStack(spacing: 20) {
            ChallengeHeader(title: "Type it exactly", round: round, total: rounds)

            Text(phrase)
                .font(Face.title(20))
                .multilineTextAlignment(.center)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Ink.surface.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .textSelection(.disabled)
                .accessibilityLabel("Type this: \(phrase)")

            TextField("Type here", text: $typed, axis: .vertical)
                .font(Face.row)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Ink.surface,
                            in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                    .strokeBorder(matches ? Palette.mint.ink : Ink.line, lineWidth: 1.5))

            // Character-by-character feedback beats a red buzzer at 6am.
            HStack(spacing: 6) {
                Image(systemName: matches ? "checkmark.circle.fill" : "keyboard")
                    .foregroundStyle(matches ? Palette.mint.ink : Ink.muted)
                Text(matches ? "That's it" : "\(typed.count)/\(phrase.count) characters")
                    .font(Face.caption).monospacedDigit()
                    .foregroundStyle(Ink.primary.opacity(0.7))
            }

            PrimaryButton(title: round + 1 >= rounds ? "Done" : "Next", palette: .mint, isEnabled: matches) {
                advance()
            }
        }
        .padding(.horizontal, Metric.gutter)
        .onAppear {
            nextPhrase()
            focused = true
        }
    }

    private func nextPhrase() {
        phrase = prepared.indices.contains(round)
            ? prepared[round]
            : PhraseFactory.phrase(tier: tier, wordCount: wordCount)
        typed = ""
    }

    private func advance() {
        round += 1
        if round >= rounds {
            onComplete()
        } else {
            nextPhrase()
        }
    }
}
