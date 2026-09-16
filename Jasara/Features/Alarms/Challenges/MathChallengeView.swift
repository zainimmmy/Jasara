import SwiftUI

struct MathChallengeView: View {
    var tier: Tier
    var rounds: Int
    var onComplete: () -> Void

    @State private var round = 0
    @State private var problem = ChallengeCatalog.MathProblem(question: "", answer: 0)
    @State private var entry = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 22) {
            ChallengeHeader(title: "Solve it", round: round, total: rounds)

            VStack(spacing: 10) {
                Text(problem.question)
                    .font(Face.display(40))
                    .monospacedDigit()
                    .accessibilityLabel("What is \(problem.question)")
                Text(entry.isEmpty ? " " : entry)
                    .font(Face.title(30))
                    .monospacedDigit()
                    .foregroundStyle(wrong ? Palette.blush.ink : Ink.primary)
                    .frame(minWidth: 120, minHeight: 44)
                    .background(Ink.surface.opacity(0.85),
                                in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                    .modifier(ShakeEffect(active: wrong))
            }

            Keypad(onDigit: { digit in
                guard entry.count < 7 else { return }
                entry.append("\(digit)")
            }, onDelete: {
                _ = entry.popLast()
            }, onSubmit: submit,
                   submitEnabled: !entry.isEmpty)
            .frame(maxWidth: 340)
        }
        .padding(.horizontal, Metric.gutter)
        .onAppear { problem = ChallengeCatalog.mathProblem(tier) }
    }

    private func submit() {
        guard Int(entry) == problem.answer else {
            withAnimation(.default) { wrong = true }
            entry = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { wrong = false }
            return
        }
        entry = ""
        round += 1
        if round >= rounds {
            onComplete()
        } else {
            problem = ChallengeCatalog.mathProblem(tier)
        }
    }
}

/// A short nudge on a wrong answer. Respects Reduce Motion by fading instead.
struct ShakeEffect: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(active ? 0.4 : 1)
        } else {
            content.offset(x: active ? -8 : 0)
                .animation(.interpolatingSpring(stiffness: 700, damping: 6), value: active)
        }
    }
}
