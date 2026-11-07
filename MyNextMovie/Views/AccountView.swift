import SwiftUI

/// The Account tab: who is signed in, the state of the sync and the sign out button.
struct AccountView: View {
    let viewModel: AccountViewModel

    var body: some View {
        NavigationStack {
            form.navigationTitle("Account")
        }
    }

    private var form: some View {
        Form {
            Section("Signed in as") {
                Text(viewModel.signedInEmail)
            }
            Section("Saved movies") {
                syncStatus
            }
            Section {
                Button("Sign Out", role: .destructive) { signOut() }
            } footer: {
                Text("Your saved movies stay on your account and are removed from this device.")
            }
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch viewModel.syncState {
        case .idle, .loading:
            Label("Syncing with your account", systemImage: symbolNameSavedFilled)
        case .loaded:
            Label("In sync with your account", systemImage: symbolNameSavedFilled)
        case .failed:
            syncError
        }
    }

    private var syncError: some View {
        VStack(alignment: .leading, spacing: spacingSmall) {
            Label(viewModel.syncErrorMessage, systemImage: symbolNameError)
            Button("Try again") { syncSavedMovies() }
        }
    }

    private func syncSavedMovies() {
        Task { await viewModel.syncSavedMovies() }
    }

    private func signOut() {
        Task { await viewModel.signOut() }
    }
}

#Preview {
    AccountView(viewModel: previewAccountViewModel(signedInEmail: testAccountEmail))
}
