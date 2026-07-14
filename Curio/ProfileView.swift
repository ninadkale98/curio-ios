import SwiftUI
import AuthenticationServices

// MARK: - ProfileView
// Title, an account section (sign in with Apple / signed-in state), and a
// Bookmarks section — left empty by design for now, no story list wired up.
struct ProfileView: View {
    let vm: FeedViewModel
    let auth: AuthViewModel
    private let theme: Palette = .dark

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Profile")
                .font(CurioFont.display(28, weight: .bold))
                .foregroundColor(theme.text)
                .padding(.top, 12)

            accountSection
            bookmarksSection

            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.pageBg.ignoresSafeArea())
    }

    // MARK: Account
    @ViewBuilder
    private var accountSection: some View {
        if auth.isSignedIn {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Signed in")
                        .font(CurioFont.body(14, weight: .semibold))
                        .foregroundColor(theme.text)
                    if let email = auth.session?.email {
                        Text(email)
                            .font(CurioFont.body(12))
                            .foregroundColor(theme.faint)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task { await auth.signOut() }
                } label: {
                    Text("Sign out")
                        .font(CurioFont.body(13, weight: .semibold))
                        .foregroundColor(theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in to sync your bookmarks across devices.")
                    .font(CurioFont.body(13))
                    .foregroundColor(theme.sub)
                AppleSignInButton { Task { await auth.signInWithApple() } }
                    .frame(height: 44)
                if let message = auth.errorMessage {
                    Text(message)
                        .font(CurioFont.body(12))
                        .foregroundColor(.red)
                }
            }
        }
    }

    // MARK: Bookmarks
    private var bookmarksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Bookmarks", systemImage: "bookmark.fill")
                .font(CurioFont.body(13, weight: .semibold))
                .foregroundColor(theme.sub)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 8) {
                Image(systemName: "bookmark")
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(theme.faint)
                Text("No bookmarks yet")
                    .font(CurioFont.body(15, weight: .semibold))
                    .foregroundColor(theme.text)
                Text("Save stories from the feed to find them here.")
                    .font(CurioFont.body(13))
                    .foregroundColor(theme.sub)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - AppleSignInButton (native ASAuthorizationAppleIDButton)
private struct AppleSignInButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.cornerRadius = 10
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}

#Preview {
    ProfileView(vm: FeedViewModel(service: MockNewsService()), auth: AuthViewModel())
}
