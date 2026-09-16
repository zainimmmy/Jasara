import SwiftUI

/// Shared chrome for every challenge: what it is, how far through you are.
struct ChallengeHeader: View {
    var title: String
    var round: Int
    var total: Int

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(Face.title(18))
                .foregroundStyle(Ink.primary.opacity(0.85))
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < round ? Palette.mint.ink : Ink.primary.opacity(0.15))
                        .frame(height: 5)
                }
            }
            .frame(maxWidth: 260)
            Text("Round \(min(round + 1, total)) of \(total)")
                .font(Face.caption)
                .foregroundStyle(Ink.primary.opacity(0.7))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), round \(min(round + 1, total)) of \(total)")
    }
}

/// Number pad built in the app so the challenge never depends on the system
/// keyboard appearing over a full-screen alarm.
struct Keypad: View {
    var onDigit: (Int) -> Void
    var onDelete: () -> Void
    var onSubmit: () -> Void
    var submitEnabled: Bool

    private let rows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { digit in
                        key("\(digit)") { onDigit(digit) }
                    }
                }
            }
            HStack(spacing: 10) {
                key("⌫", action: onDelete)
                key("0") { onDigit(0) }
                Button(action: onSubmit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(submitEnabled ? Palette.mint.fill : Ink.line,
                                    in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                        .foregroundStyle(submitEnabled ? Palette.mint.ink : Ink.muted)
                }
                .buttonStyle(.plain)
                .disabled(!submitEnabled)
                .accessibilityLabel("Submit answer")
            }
        }
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Face.title(24))
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Ink.surface.opacity(0.9),
                            in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .foregroundStyle(Ink.primary)
        }
        .buttonStyle(.plain)
    }
}
