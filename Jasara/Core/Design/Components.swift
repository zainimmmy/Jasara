import SwiftUI

/// The emoji-on-a-pastel-circle that identifies every task, alarm and prayer.
struct EmojiBubble: View {
    var emoji: String
    var palette: Palette
    var size: CGFloat = 38

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(palette.fill, in: Circle())
            .accessibilityHidden(true)
    }
}

struct CheckCircle: View {
    var isDone: Bool
    var palette: Palette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? palette.ink : Ink.line, lineWidth: 2)
                    .frame(width: 24, height: 24)
                if isDone {
                    Circle().fill(palette.ink).frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.fill)
                }
            }
            .frame(width: Metric.minTarget, height: Metric.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "Completed" : "Not completed")
        .accessibilityAddTraits(.isButton)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                .strokeBorder(Ink.line, lineWidth: 1))
    }
}

/// A coloured section header with its count and a + that adds straight into it.
struct SectionHeaderRow: View {
    var title: String
    var symbol: String?
    var palette: Palette
    var count: Int
    var onAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.ink)
            }
            Text(title)
                .font(Face.sectionTitle)
                .foregroundStyle(palette.ink)
            Text("\(count)")
                .font(Face.caption.weight(.bold))
                .foregroundStyle(palette.ink.opacity(0.7))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(palette.fill, in: Capsule())
            Spacer()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .frame(width: 30, height: 30)
                        .background(palette.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(title)")
            }
        }
        .padding(.horizontal, 4)
    }
}

struct DashedAddRow: View {
    var title: String = "Add task"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text(title).font(Face.row)
                Spacer()
            }
            .foregroundStyle(Ink.muted)
            .padding(.vertical, 13).padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metric.rowCorner, style: .continuous)
                    .strokeBorder(Ink.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Dismissible hints. Never an advert, never a paywall nag.
struct TipCard: View {
    var emoji: String
    var title: String
    var message: String
    var onDismiss: () -> Void
    var onTap: (() -> Void)?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                EmojiBubble(emoji: emoji, palette: .lilac, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Face.rowStrong)
                    Text(message).font(Face.caption).foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Ink.muted)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss tip")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

struct StreakFlame: View {
    var count: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("🔥").font(.system(size: 15))
            Text("\(count)").font(Face.caption.weight(.bold)).monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Palette.blush.fill, in: Capsule())
        .foregroundStyle(Palette.blush.ink)
        .accessibilityLabel("\(count) day streak")
    }
}

struct LevelBadge: View {
    var level: Int
    var fraction: Double

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(Palette.lilac.ink.opacity(0.25), lineWidth: 3)
                Circle().trim(from: 0, to: max(0.02, fraction))
                    .stroke(Palette.lilac.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            Text("Lv \(level)").font(Face.caption.weight(.bold)).monospacedDigit()
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Palette.lilac.fill, in: Capsule())
        .foregroundStyle(Palette.lilac.ink)
        .accessibilityLabel("Level \(level), \(Int(fraction * 100)) percent to next")
    }
}

/// Big soft primary button used on sheets and the alarm screen.
struct PrimaryButton: View {
    var title: String
    var palette: Palette = .lilac
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Face.rowStrong)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(isEnabled ? palette.fill : Ink.line,
                            in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .foregroundStyle(isEnabled ? palette.ink : Ink.muted)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct ChipToggle: View {
    var title: String
    var isOn: Bool
    var palette: Palette = .sky
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Face.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(minWidth: Metric.minTarget, minHeight: 36)
                .background(isOn ? palette.fill : Ink.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? .clear : Ink.line, lineWidth: 1))
                .foregroundStyle(isOn ? palette.ink : Ink.muted)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

struct EmptyHint: View {
    var emoji: String
    var text: String
    var body: some View {
        VStack(spacing: 8) {
            Text(emoji).font(.system(size: 34))
            Text(text)
                .font(Face.caption)
                .foregroundStyle(Ink.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
