import SwiftUI

private let signInHeaderSymbolSize: CGFloat = 56

private let confirmEmailHint = "Check your inbox and tap the link in the email, then sign in."
private let passwordLengthHint =
    "A new account needs a password of at least \(minimumPasswordLength) characters."

/// The first screen of the app: sign in or create an account.
struct SignInView: View {
    @Bindable var viewModel: AccountViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: spacingHuge) {
                header
                fields
                buttons
                status
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { fillTestAccount() }
    }

    private var header: some View {
        VStack(spacing: spacingMedium) {
            Image(systemName: symbolNameMovies)
                .font(.system(size: signInHeaderSymbolSize))
                .foregroundStyle(.secondary)
            Text("My Next Movie")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
            Text("Sign in to keep your saved movies on every device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, spacingHuge)
    }

    private var fields: some View {
        VStack(spacing: spacingMedium) {
            TextField("Email", text: $viewModel.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $viewModel.password)
                .textContentType(.password)
                .onSubmit { signIn() }
        }
        .textFieldStyle(.roundedBorder)
    }

    private var buttons: some View {
        VStack(spacing: spacingMedium) {
            Button("Sign In") { signIn() }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canSignIn)
            Button("Create Account") { signUp() }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canSignUp)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var status: some View {
        if viewModel.state == .loading {
            ProgressView()
        } else if viewModel.state == .failed {
            statusText(viewModel.errorMessage, color: .red)
        } else if viewModel.isWaitingForEmailConfirmation {
            statusText(confirmEmailHint, color: .primary)
        } else {
            statusText(passwordLengthHint, color: .secondary)
        }
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
    }

    private func signIn() {
        Task { await viewModel.signIn() }
    }

    private func signUp() {
        Task { await viewModel.signUp() }
    }

    /// Debug builds sign in with one tap. The code is left out of Release.
    private func fillTestAccount() {
        #if DEBUG
            if viewModel.email.isEmpty && viewModel.password.isEmpty {
                viewModel.email = testAccountEmail
                viewModel.password = testAccountPassword
            }
        #endif
    }
}

/// A view model without Supabase for the previews. The closures accept any email and password.
func previewAccountViewModel(signedInEmail: String) -> AccountViewModel {
    let previewAccount = AccountService(
        signedInEmail: { signedInEmail },
        signIn: { email, _ in email },
        signUp: { email, _ in email },
        signOut: {}
    )
    return AccountViewModel(account: previewAccount, syncSavedMovies: {}, clearSavedMovies: {})
}

#Preview {
    SignInView(viewModel: previewAccountViewModel(signedInEmail: ""))
}
