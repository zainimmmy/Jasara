import SwiftUI

/// Apple's privacy rules say an app without significant account-based features
/// must be usable without logging in — and the whole solo app (tasks, calendar,
/// alarms, timer, prayers) is exactly that. So "Continue without an account" is
/// a first-class path, not a dark corner. An account only buys friends, group
/// alarms, calendar sharing and backup, and a guest can create one later without
/// losing anything.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(Backend.self) private var backend
    @State private var step = 0
    @State private var wantsAccount = false
    @State private var confirmedAge = false

    var body: some View {
        ZStack {
            Ink.dawn.ignoresSafeArea()
            VStack(spacing: 0) {
                switch step {
                case 0: welcome
                case 1: ageCheck
                default: createAccount
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Wake up, plan the day,\nkeep each other on time.")
                .font(Face.display(32))
                .foregroundStyle(Ink.primary)
            Text("An alarm that makes you earn it, a calm day plan, and a focus timer — in one place, working with or without a signal.")
                .font(Face.row)
                .foregroundStyle(Ink.primary.opacity(0.8))
            HStack(spacing: 8) {
                ForEach(["⏰ 6:30", "🕌 Fajr", "✅ 3 tasks", "🔥 12 days"], id: \.self) { chip in
                    Text(chip)
                        .font(Face.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Ink.surface.opacity(0.9), in: Capsule())
                }
            }
            Spacer()
            VStack(spacing: 10) {
                PrimaryButton(title: "Create an account", palette: .lilac) {
                    wantsAccount = true
                    step = 1
                }
                Button("Continue without an account") {
                    wantsAccount = false
                    step = 1
                }
                .font(Face.rowStrong)
                .foregroundStyle(Ink.primary)
                .padding(.vertical, 6)
            }
            Text("You can add an account later and keep everything you've made.")
                .font(Face.caption)
                .foregroundStyle(Ink.primary.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 16)
        }
    }

    private var ageCheck: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Quick check").font(Face.display(30))
            Text("This app is for people aged 13 and over. On devices that provide it, we read Apple's Declared Age Range instead of asking.")
                .font(Face.row).foregroundStyle(Ink.primary.opacity(0.85))
            Toggle(isOn: $confirmedAge) {
                Text("I'm 13 or older").font(Face.rowStrong)
            }
            .tint(Palette.mint.ink)
            .padding(14)
            .background(Ink.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: Metric.corner))
            Spacer()
            PrimaryButton(title: "Continue", palette: .mint, isEnabled: confirmedAge) {
                step = 2
                if !wantsAccount { finish() }
            }
            .padding(.bottom, 20)
        }
    }

    /// Real sign-up. If this build has no backend configured, AccountView says so
    /// and lets the person carry on as a guest.
    private var createAccount: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create your account").font(Face.display(30)).padding(.top, 40)
                AccountView(mode: .create,
                            onSkip: { wantsAccount = false; finish() },
                            onDone: { finish(username: backend.me?.username) })
                    .padding(16)
                    .background(Ink.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: Metric.corner))
            }
            .padding(.bottom, 30)
        }
    }

    // MARK: - Finishing

    private func finish(username: String? = nil) {
        let profile = store.profile
        profile.isGuest = !wantsAccount
        profile.username = username ?? ""
        profile.displayName = username ?? ""
        profile.hasOnboarded = true
        store.save()
        // Permissions are asked for at first use, with a reason, never in a row here.
    }
}

enum UsernameRules {
    static let reserved = ["admin", "support", "jasara", "help", "root", "moderator"]

    /// Returns nil when the name is fine, or the reason it isn't.
    static func problem(with name: String) -> String? {
        let lower = name.lowercased()
        if lower.count < 3 { return "Usernames are at least 3 characters." }
        if lower.count > 20 { return "Usernames are at most 20 characters." }
        if lower.contains(where: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }) {
            return "Letters, numbers, underscores and dots only."
        }
        if reserved.contains(lower) { return "That name is reserved." }
        if ProfanityFilter.isBlocked(lower) { return "Pick something else." }
        return nil
    }
}

/// Deliberately small and conservative: it blocks the obvious, and reporting plus
/// review handles the rest. A real filter list ships with the backend.
enum ProfanityFilter {
    private static let blocked = ["fuck", "shit", "bitch", "nigg", "cunt", "rape", "nazi"]
    static func isBlocked(_ text: String) -> Bool {
        let lower = text.lowercased()
        return blocked.contains { lower.contains($0) }
    }
}
