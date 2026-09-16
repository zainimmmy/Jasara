import SwiftUI

/// Sign in or create an account. Used from onboarding, Friends and Settings.
/// Guests never need it for anything solo.
struct AccountView: View {
    enum Mode: Hashable { case create, signIn }

    @Environment(AppStore.self) private var store
    @Environment(Backend.self) private var backend

    @State var mode: Mode = .create
    /// Shown under the form when accounts aren't configured, so onboarding can move on.
    var onSkip: (() -> Void)?
    var onDone: () -> Void

    @State private var username = ""
    @State private var usernameProblem: String?
    @State private var checkingUsername = false
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?
    @State private var notice: String?

    private var emailLooksValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
    }

    private var canSubmit: Bool {
        guard emailLooksValid, password.count >= 8, !working else { return false }
        if mode == .create {
            return !username.isEmpty && usernameProblem == nil && !checkingUsername
        }
        return true
    }

    var body: some View {
        if !backend.isConfigured {
            notConfigured
        } else if backend.isSignedIn && backend.me == nil && !backend.isLoadingProfile {
            ClaimUsernameView(onDone: finish)
        } else {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $mode) {
                Text("Create account").tag(Mode.create)
                Text("Sign in").tag(Mode.signIn)
            }
            .pickerStyle(.segmented)

            if mode == .create {
                VStack(alignment: .leading, spacing: 4) {
                    field("username", text: $username, content: .username)
                    usernameStatus
                }
                .task(id: username) { await checkUsername() }
            }

            field("email", text: $email, content: .emailAddress, keyboard: .emailAddress)
            SecureField(mode == .create ? "password (8+ characters)" : "password", text: $password)
                .textContentType(mode == .create ? .newPassword : .password)
                .font(Face.row)
                .padding(14)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                    .strokeBorder(Ink.line, lineWidth: 1))

            if let error {
                Text(error).font(Face.caption).foregroundStyle(Palette.blush.ink)
            }
            if let notice {
                Text(notice).font(Face.caption).foregroundStyle(Palette.mint.ink)
            }

            PrimaryButton(title: working ? "One moment…" : (mode == .create ? "Create account" : "Sign in"),
                          palette: .lilac, isEnabled: canSubmit) {
                Task { await submit() }
            }

            Text(mode == .create
                 ? "Your username is how friends find you. Only people you accept can see your profile."
                 : "Signing in brings back your friends and group alarms.")
                .font(Face.caption).foregroundStyle(Ink.muted)
        }
    }

    @ViewBuilder
    private var usernameStatus: some View {
        if username.isEmpty {
            Text("3 to 20 characters: letters, numbers, _ and .")
                .font(Face.caption).foregroundStyle(Ink.muted)
        } else if checkingUsername {
            Text("Checking…").font(Face.caption).foregroundStyle(Ink.muted)
        } else if let usernameProblem {
            Text(usernameProblem).font(Face.caption).foregroundStyle(Palette.blush.ink)
        } else {
            Label("Available", systemImage: "checkmark.circle.fill")
                .font(Face.caption).foregroundStyle(Palette.mint.ink)
        }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accounts aren't switched on in this build")
                .font(Face.title(20))
            Text("Friends and group alarms need the Supabase backend. Everything else works without an account.")
                .font(Face.row).foregroundStyle(Ink.muted)
            if let onSkip {
                PrimaryButton(title: "Continue without an account", palette: .mint, action: onSkip)
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>,
                       content: UITextContentType, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(Face.row)
            .padding(14)
            .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metric.corner, style: .continuous)
                .strokeBorder(Ink.line, lineWidth: 1))
    }

    // MARK: - Actions

    /// Live availability check, debounced by `.task(id:)` restarting on each keystroke.
    private func checkUsername() async {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { usernameProblem = nil; return }
        if let local = UsernameRules.problem(with: name) {
            usernameProblem = local
            return
        }
        checkingUsername = true
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        usernameProblem = await backend.usernameProblem(name)
        checkingUsername = false
    }

    private func submit() async {
        error = nil
        notice = nil
        working = true
        defer { working = false }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        do {
            switch mode {
            case .create:
                switch try await backend.signUp(email: trimmedEmail, password: password,
                                                username: username.trimmingCharacters(in: .whitespaces)) {
                case .signedIn:
                    finish()
                case .confirmEmail:
                    notice = "Check \(trimmedEmail) for a confirmation link, then sign in here."
                    mode = .signIn
                }
            case .signIn:
                try await backend.signIn(email: trimmedEmail, password: password)
                if backend.me != nil { finish() }
            }
        } catch {
            self.error = Backend.describe(error)
        }
    }

    private func finish() {
        let profile = store.profile
        profile.isGuest = false
        if let me = backend.me {
            profile.username = me.username
            if profile.displayName.isEmpty { profile.displayName = me.displayName }
        }
        store.save()
        onDone()
    }
}

/// An account that exists without a username — for example one that confirmed
/// its email on another device — picks one before using friends.
struct ClaimUsernameView: View {
    @Environment(Backend.self) private var backend
    var onDone: () -> Void

    @State private var username = ""
    @State private var problem: String?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick a username").font(Face.title(20))
            Text("Friends find you by this exact name.").font(Face.caption).foregroundStyle(Ink.muted)
            TextField("username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Face.row)
                .padding(14)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metric.corner, style: .continuous))
                .task(id: username) {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled, !username.isEmpty else { return }
                    problem = await backend.usernameProblem(username)
                }
            if let message = error ?? problem {
                Text(message).font(Face.caption).foregroundStyle(Palette.blush.ink)
            }
            PrimaryButton(title: "Save", palette: .lilac,
                          isEnabled: !username.isEmpty && problem == nil && !working) {
                Task {
                    working = true
                    defer { working = false }
                    do {
                        try await backend.claimUsername(username)
                        onDone()
                    } catch {
                        self.error = Backend.describe(error)
                    }
                }
            }
        }
    }
}
