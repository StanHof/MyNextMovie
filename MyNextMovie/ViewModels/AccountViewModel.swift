import Foundation
import Observation

/// State of the account and of the sync of the saved movies.
/// A class only because SwiftUI's @Observable requires one.
@Observable
final class AccountViewModel {
    var email = ""
    var password = ""

    private(set) var signedInEmail: String
    private(set) var state = LoadState.idle
    private(set) var errorMessage = ""
    private(set) var isWaitingForEmailConfirmation = false
    private(set) var syncState = LoadState.idle
    private(set) var syncErrorMessage = ""

    private let account: AccountService
    private let syncSavedMoviesWithAccount: () async throws -> Void
    private let clearSavedMoviesOnDevice: @MainActor () -> Void

    /// A sync asked for during another one runs after it, never at the same time.
    private var isSyncing = false
    private var isAnotherSyncRequested = false

    init(
        account: AccountService,
        syncSavedMovies: @escaping () async throws -> Void,
        clearSavedMovies: @escaping @MainActor () -> Void
    ) {
        self.account = account
        self.syncSavedMoviesWithAccount = syncSavedMovies
        self.clearSavedMoviesOnDevice = clearSavedMovies
        // Read at once, so a signed in user never sees the sign in screen.
        self.signedInEmail = account.signedInEmail()
    }

    var isSignedIn: Bool { return !signedInEmail.isEmpty }

    var canSignIn: Bool {
        return !trimmedEmail.isEmpty && !password.isEmpty && state != .loading
    }

    var canSignUp: Bool {
        return canSignIn && password.count >= minimumPasswordLength
    }

    private var trimmedEmail: String {
        return email.trimmingCharacters(in: .whitespaces)
    }

    func signIn() async {
        await submit(account.signIn)
    }

    func signUp() async {
        await submit(account.signUp)
    }

    /// Signing in and creating an account differ only in the request.
    private func submit(_ request: AccountRequest) async {
        state = .loading
        errorMessage = ""
        isWaitingForEmailConfirmation = false
        do {
            let returnedEmail = try await request(trimmedEmail, password)
            if returnedEmail.isEmpty {
                isWaitingForEmailConfirmation = true
            } else {
                signedInEmail = returnedEmail
                password = ""
            }
            state = .loaded
        } catch {
            errorMessage = error.localizedDescription
            state = .failed
        }
        await syncSavedMovies()
    }

    /// Syncs the saved movies with the account. Does nothing when nobody is signed in.
    func syncSavedMovies() async {
        if !isSignedIn {
            return
        }
        if isSyncing {
            isAnotherSyncRequested = true
            return
        }
        isSyncing = true
        repeat {
            isAnotherSyncRequested = false
            await syncOnce()
        } while isAnotherSyncRequested
        isSyncing = false
    }

    private func syncOnce() async {
        syncState = .loading
        do {
            try await syncSavedMoviesWithAccount()
            syncState = .loaded
        } catch {
            syncErrorMessage = error.localizedDescription
            syncState = .failed
        }
    }

    /// Sends the last changes, signs out and clears the device. The account keeps its movies.
    func signOut() async {
        await syncSavedMovies()
        try? await account.signOut()
        signedInEmail = ""
        state = .idle
        syncState = .idle
        clearSavedMoviesOnDevice()
    }
}
