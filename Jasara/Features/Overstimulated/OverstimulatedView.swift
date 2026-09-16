import SwiftUI
import UIKit

/// A joke challenge: a gauntlet of fake "prove you're human" hoops that runs for
/// two to three minutes while the alarm keeps going. Everything here is original,
/// bundled and offline. Nothing you tap is stored, sent or agreed to.
struct OverstimulatedView: View {
    var onComplete: () -> Void

    @State private var stage = Stage.imageCaptcha(0)
    @State private var calls = FakeCallDirector()
    @State private var checkboxOrder: [Int] = Array(0..<5).shuffled()

    enum Stage: Equatable {
        case imageCaptcha(Int)      // four of them
        case checkboxesFirst
        case terms
        case checkboxesSecond
        case typedCaptcha(Int)      // two of them
        case authenticating
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                JokeBanner()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if calls.isRinging {
                FakeCallScreen(onDecline: { calls.decline() },
                               onAccept: { calls.accept() },
                               isNiceTry: calls.showingNiceTry)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: calls.isRinging)
        .task { await calls.run() }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .imageCaptcha(let index):
            ImageCaptchaView(index: index) {
                stage = index < 3 ? .imageCaptcha(index + 1) : .checkboxesFirst
            }
        case .checkboxesFirst:
            JokeCheckboxView(order: checkboxOrder, title: "Just a few confirmations") {
                checkboxOrder.shuffle()
                stage = .terms
            }
        case .terms:
            JokeTermsView { stage = .checkboxesSecond }
        case .checkboxesSecond:
            JokeCheckboxView(order: checkboxOrder, title: "Sorry — those didn't save") {
                stage = .typedCaptcha(0)
            }
        case .typedCaptcha(let index):
            TypedCaptchaView(index: index) {
                stage = index < 1 ? .typedCaptcha(index + 1) : .authenticating
            }
        case .authenticating:
            AuthenticatingView(paused: calls.isRinging, onFinish: onComplete)
        }
    }
}

/// Required by the guardrails, and honestly it's also the funniest part.
struct JokeBanner: View {
    var body: some View {
        Text("This is a joke. You aren't agreeing to anything.")
            .font(Face.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Palette.butter.fill)
            .foregroundStyle(Palette.butter.ink)
    }
}

// MARK: - Image CAPTCHA

struct ImageCaptchaView: View {
    var index: Int
    var onPass: () -> Void

    @State private var puzzle = CaptchaPuzzle.random()
    @State private var selected: Set<Int> = []
    @State private var shakeWrong = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Select all squares with")
                    .font(Face.row)
                Text(puzzle.targetName)
                    .font(Face.display(26))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.sky.fill)
            .foregroundStyle(Palette.sky.ink)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<9, id: \.self) { cell in
                    CaptchaTile(symbol: puzzle.symbols[cell],
                                tint: puzzle.tints[cell],
                                rotation: puzzle.rotations[cell],
                                isSelected: selected.contains(cell))
                    .onTapGesture {
                        if selected.contains(cell) { selected.remove(cell) } else { selected.insert(cell) }
                    }
                    .accessibilityLabel("Square \(cell + 1), \(puzzle.isTarget(cell) ? puzzle.targetName : "something else")")
                    .accessibilityAddTraits(selected.contains(cell) ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .modifier(ShakeEffect(active: shakeWrong))

            HStack(spacing: 10) {
                Button("Skip") { check(skipping: true) }
                    .font(Face.rowStrong)
                    .foregroundStyle(Ink.muted)
                    .frame(minWidth: 80, minHeight: Metric.minTarget)
                Spacer()
                PrimaryButton(title: "Verify", palette: .mint) { check(skipping: false) }
                    .frame(maxWidth: 180)
            }
            .padding(.horizontal, Metric.gutter)

            Text("Puzzle \(index + 1) of 4")
                .font(Face.caption).foregroundStyle(Ink.muted)
            Spacer(minLength: 0)
        }
    }

    private func check(skipping: Bool) {
        let correct = skipping ? puzzle.targets.isEmpty && selected.isEmpty
                               : selected == puzzle.targets && !selected.isEmpty
        if correct {
            onPass()
        } else {
            // A wrong answer loads a new puzzle, and it doesn't count.
            withAnimation { shakeWrong = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                shakeWrong = false
                puzzle = CaptchaPuzzle.random()
                selected = []
            }
        }
    }
}

/// The art is drawn in the app from shapes and symbols, so it's original, tiny
/// and works with no connection. No third-party CAPTCHA name, logo or look.
struct CaptchaPuzzle {
    var targetSymbol: String
    var targetName: String
    var symbols: [String]
    var tints: [Palette]
    var rotations: [Double]

    var targets: Set<Int> {
        Set(symbols.indices.filter { symbols[$0] == targetSymbol })
    }
    func isTarget(_ index: Int) -> Bool { symbols[index] == targetSymbol }

    private static let catalogue: [(symbol: String, name: String)] = [
        ("bicycle", "a bicycle"), ("car.fill", "a car"), ("bus.fill", "a bus"),
        ("airplane", "a plane"), ("sailboat.fill", "a boat"), ("tram.fill", "a tram"),
        ("leaf.fill", "a leaf"), ("cup.and.saucer.fill", "a cup"), ("umbrella.fill", "an umbrella"),
        ("bolt.fill", "lightning"), ("bird.fill", "a bird"), ("carrot.fill", "a carrot")
    ]

    static func random() -> CaptchaPuzzle {
        let picks = catalogue.shuffled()
        let target = picks[0]
        let distractors = Array(picks.dropFirst().prefix(3))
        // One puzzle in six has none of the target, so Skip has a real job.
        let targetCount = Int.random(in: 0...9) == 0 ? 0 : Int.random(in: 2...4)
        var cells = Array(repeating: target.symbol, count: targetCount)
        while cells.count < 9 {
            cells.append(distractors.randomElement()!.symbol)
        }
        cells.shuffle()
        return CaptchaPuzzle(targetSymbol: target.symbol,
                             targetName: target.name,
                             symbols: cells,
                             tints: (0..<9).map { _ in Palette.allCases.randomElement()! },
                             rotations: (0..<9).map { _ in Double.random(in: -14...14) })
    }
}

struct CaptchaTile: View {
    var symbol: String
    var tint: Palette
    var rotation: Double
    var isSelected: Bool

    var body: some View {
        ZStack {
            // Procedural "photo": a soft gradient with a couple of blobs behind it.
            LinearGradient(colors: [tint.fill, tint.fill.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(tint.ink.opacity(0.12))
                .frame(width: 60, height: 60)
                .offset(x: rotation * 1.6, y: -rotation)
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint.ink)
                .rotationEffect(.degrees(rotation))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Palette.mint.ink : .clear, lineWidth: 4)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.mint.ink)
                    .padding(4)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Joke checkboxes

struct JokeCheckboxView: View {
    var order: [Int]
    var title: String
    var onPass: () -> Void

    @State private var checked: Set<Int> = []

    /// Deliberately meaningless, and deliberately nothing that resembles a real
    /// age, identity or legal claim.
    private static let lines = [
        "I agree to become a morning person, eventually.",
        "Please do not send me the giraffe newsletter.",
        "I understand that the snooze button has feelings.",
        "I confirm that I am awake, or doing a convincing impression.",
        "I accept that this checkbox does nothing at all."
    ]

    private var items: [Int] { order.prefix(4).map { $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(Face.display(26)).padding(.top, 20)
            ForEach(items, id: \.self) { index in
                Button {
                    if checked.contains(index) { checked.remove(index) } else { checked.insert(index) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: checked.contains(index) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 22))
                            .foregroundStyle(checked.contains(index) ? Palette.mint.ink : Ink.muted)
                        Text(Self.lines[index])
                            .font(Face.row)
                            .foregroundStyle(Ink.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .frame(minHeight: Metric.minTarget)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(checked.contains(index) ? [.isButton, .isSelected] : .isButton)
            }
            Spacer()
            PrimaryButton(title: "Complete", palette: .mint,
                          isEnabled: checked.count == items.count) {
                onPass()
            }
        }
        .padding(Metric.gutter)
    }
}

// MARK: - Joke terms

struct JokeTermsView: View {
    var onPass: () -> Void

    @State private var reachedBottom = false
    @State private var secondsOnScreen = 0
    private let minimumSeconds = 20

    private var canContinue: Bool { reachedBottom && secondsOnScreen >= minimumSeconds }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Terms of Being Awake")
                        .font(Face.display(30))
                    ForEach(Self.clauses.indices, id: \.self) { index in
                        Text(Self.clauses[index])
                            // Very large type, as promised.
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                    }
                    Text("You have reached the end. Congratulations, legally speaking this means nothing.")
                        .font(Face.caption).foregroundStyle(Ink.muted)
                }
                .padding(Metric.gutter)
            }
            // Complete only unlocks once you have genuinely reached the bottom.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - 24
            } action: { _, atBottom in
                if atBottom { reachedBottom = true }
            }
            VStack(spacing: 6) {
                if !canContinue {
                    Text(reachedBottom
                         ? "Reading time remaining: \(max(minimumSeconds - secondsOnScreen, 0))s"
                         : "Scroll to the bottom")
                        .font(Face.caption).foregroundStyle(Ink.muted).monospacedDigit()
                }
                PrimaryButton(title: "Complete", palette: .mint, isEnabled: canContinue, action: onPass)
            }
            .padding(Metric.gutter)
        }
        .task {
            while secondsOnScreen < minimumSeconds {
                try? await Task.sleep(for: .seconds(1))
                secondsOnScreen += 1
            }
        }
    }

    private static let clauses = [
        "1. You agree that the bed is now closed and will reopen at a time nobody has specified.",
        "2. The duvet retains all rights to warmth, and licenses none of them to you.",
        "3. Any dream in progress is hereby cancelled without refund.",
        "4. You accept that 'five more minutes' is an estimate and not a contract.",
        "5. The alarm reserves the right to be extremely annoying in perpetuity.",
        "6. Clause 6 was removed for being too relaxing.",
        "7. By continuing you confirm that your feet may, at some point, touch the floor.",
        "8. These terms are governed by the laws of whoever gets up first."
    ]
}

// MARK: - Typed CAPTCHA

struct TypedCaptchaView: View {
    var index: Int
    var onPass: () -> Void

    @State private var code = TypedCaptcha.make()
    @State private var typed = ""
    @State private var wrong = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("Type the characters in the picture")
                .font(Face.row)
                .padding(.top, 20)

            DistortedCodeView(code: code)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                    .strokeBorder(Ink.line, lineWidth: 1))
                .padding(.horizontal, Metric.gutter)
                // The point of the joke is the hoop, not excluding anyone.
                .accessibilityLabel("The characters are \(code.map(String.init).joined(separator: " "))")

            TextField("Characters", text: $typed)
                .font(Face.title(22))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding(14)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                    .strokeBorder(wrong ? Palette.blush.ink : Ink.line, lineWidth: 1.5))
                .padding(.horizontal, Metric.gutter)
                .modifier(ShakeEffect(active: wrong))

            Text("Not case sensitive. Puzzle \(index + 1) of 2.")
                .font(Face.caption).foregroundStyle(Ink.muted)

            PrimaryButton(title: "Verify", palette: .mint, isEnabled: !typed.isEmpty, action: check)
                .padding(.horizontal, Metric.gutter)
            Spacer()
        }
        .onAppear { focused = true }
    }

    private func check() {
        let expected = String(code).replacingOccurrences(of: " ", with: "").lowercased()
        let given = typed.replacingOccurrences(of: " ", with: "").lowercased()
        if expected == given {
            onPass()
        } else {
            withAnimation { wrong = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                wrong = false
                typed = ""
                code = TypedCaptcha.make()      // a wrong answer earns a new code
            }
        }
    }
}

enum TypedCaptcha {
    /// l, 1, I, O and 0 are never used, because a squint at 6am is punishment enough.
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    static func make() -> [Character] {
        let group = { (0..<3).map { _ in alphabet.randomElement()! } }
        return group() + [" "] + group()
    }
}

struct DistortedCodeView: View {
    var code: [Character]

    var body: some View {
        ZStack {
            // Scratchy background lines, drawn not downloaded.
            Canvas { context, size in
                for index in 0..<6 {
                    var path = Path()
                    let y = size.height * Double(index + 1) / 7
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addCurve(to: CGPoint(x: size.width, y: y + Double.random(in: -12...12)),
                                  control1: CGPoint(x: size.width * 0.3, y: y + Double.random(in: -20...20)),
                                  control2: CGPoint(x: size.width * 0.7, y: y - Double.random(in: -20...20)))
                    context.stroke(path, with: .color(.gray.opacity(0.25)), lineWidth: 1)
                }
            }
            HStack(spacing: 2) {
                ForEach(code.indices, id: \.self) { index in
                    Text(String(code[index]))
                        .font(.system(size: 40, weight: .heavy, design: .serif))
                        .rotationEffect(.degrees(Double((index * 37) % 31) - 15))
                        .offset(y: Double((index * 53) % 17) - 8)
                        .scaleEffect(x: 1, y: 1 + Double((index * 29) % 5) / 10)
                        .foregroundStyle(Ink.primary.opacity(0.85))
                }
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

// MARK: - Authenticating

struct AuthenticatingView: View {
    var paused: Bool
    var onFinish: () -> Void

    @State private var progress: Double = 0
    @State private var lineIndex = 0

    /// Exactly fifteen seconds, and it cannot be skipped.
    private let duration: Double = 15
    private let step = 0.05

    private static let lines = [
        "Waking the servers…",
        "Negotiating with your duvet…",
        "Counting the sheep back in…",
        "Checking you are, in fact, vertical…",
        "Applying the finishing touches…"
    ]

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("Authenticating").font(Face.display(30))
            Text(Self.lines[min(lineIndex, Self.lines.count - 1)])
                .font(Face.row)
                .foregroundStyle(Ink.muted)
                .animation(.easeInOut, value: lineIndex)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.line)
                    Capsule().fill(Palette.mint.ink)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 16)
            .padding(.horizontal, Metric.gutter)

            Text("\(Int(progress * 100))%")
                .font(Face.title(20)).monospacedDigit()
            if paused {
                Text("Paused — deal with the call first.")
                    .font(Face.caption).foregroundStyle(Palette.butter.ink)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Authenticating, \(Int(progress * 100)) percent")
        // Restarted whenever a call starts or ends, so the bar genuinely pauses.
        .task(id: paused) {
            guard !paused else { return }
            while progress < 1 {
                try? await Task.sleep(for: .seconds(step))
                if Task.isCancelled { return }
                progress = min(1, progress + step / duration)
                lineIndex = Int(progress * Double(Self.lines.count))
            }
            onFinish()
        }
    }
}

// MARK: - Fake calls

/// An in-app screen in the app's own style, clearly labelled. It deliberately
/// does not imitate the iOS call screen or ringtone, and it never touches CallKit.
@Observable
@MainActor
final class FakeCallDirector {
    private(set) var isRinging = false
    private(set) var showingNiceTry = false
    private var remaining = 3

    /// Three calls, at random points, at least twenty seconds apart.
    func run() async {
        while remaining > 0 {
            try? await Task.sleep(for: .seconds(Double.random(in: 20...45)))
            guard remaining > 0 else { return }
            isRinging = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            while isRinging {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func decline() {
        showingNiceTry = false
        isRinging = false
        remaining -= 1
    }

    /// Tapping accept shows a "nice try" and the call rings straight back. That
    /// repeat does not count toward the three.
    func accept() {
        showingNiceTry = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            showingNiceTry = false
        }
    }
}

struct FakeCallScreen: View {
    var onDecline: () -> Void
    var onAccept: () -> Void
    var isNiceTry: Bool

    var body: some View {
        ZStack {
            Ink.background.opacity(0.98).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Fake call")
                    .font(Face.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Palette.butter.fill, in: Capsule())
                    .foregroundStyle(Palette.butter.ink)
                    .padding(.top, 40)
                Spacer()
                Text("📞").font(.system(size: 54))
                Text(isNiceTry ? "Nice try" : "Unknown caller")
                    .font(Face.display(30))
                Text(isNiceTry ? "It's ringing again." : "Decline to carry on.")
                    .font(Face.row).foregroundStyle(Ink.muted)
                Spacer()
                HStack(spacing: 24) {
                    callButton("Decline", palette: .blush, symbol: "phone.down.fill", action: onDecline)
                    callButton("Accept", palette: .mint, symbol: "phone.fill", action: onAccept)
                }
                .padding(.bottom, 50)
            }
            .padding(.horizontal, Metric.gutter)
        }
    }

    private func callButton(_ title: String, palette: Palette, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 68, height: 68)
                    .background(palette.fill, in: Circle())
                    .foregroundStyle(palette.ink)
                Text(title).font(Face.caption).foregroundStyle(Ink.muted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
