import Testing

@testable import MyNextMovie

/// Stands in for Supabase: the account, the network and the sync of one user.
@MainActor
private final class TestAccount {
    var signedInEmail = ""
    var isOffline = false
    var needsEmailConfirmation = false
    var isSyncFailing = false
    var syncCount = 0
    var clearCount = 0
    var receivedEmail = ""
    var receivedPassword = ""
    /// What happened in which order, e.g. ["sync", "clear"].
    var events: [String] = []

    func makeViewModel() -> AccountViewModel {
        return AccountViewModel(
            account: makeAccountService(),
            syncSavedMovies: { try self.sync() },
            clearSavedMovies: { self.clear() }
        )
    }

    private func makeAccountService() -> AccountService {
        return AccountService(
            signedInEmail: { self.signedInEmail },
            signIn: { email, password in try self.signIn(email, password) },
            signUp: { email, password in try self.signUp(email, password) },
            signOut: { self.signedInEmail = "" }
        )
    }

    private func signIn(_ email: String, _ password: String) throws -> String {
        try requireOnline()
        receivedEmail = email
        receivedPassword = password
        signedInEmail = email
        return email
    }

    private func signUp(_ email: String, _ password: String) throws -> String {
        try requireOnline()
        if needsEmailConfirmation {
            return ""
        }
        signedInEmail = email
        return email
    }

    private func sync() throws {
        syncCount += 1
        events.append("sync")
        if isSyncFailing {
            throw NoConnection()
        }
    }

    private func clear() {
        clearCount += 1
        events.append("clear")
    }

    private func requireOnline() throws {
        if isOffline {
            throw NoConnection()
        }
    }
}

@MainActor
struct AccountViewModelTests {
    @Test func startsSignedOut() {
        let viewModel = TestAccount().makeViewModel()

        #expect(!viewModel.isSignedIn)
        #expect(viewModel.state == .idle)
    }

    @Test func newAccountNeedsLongEnoughPassword() {
        let viewModel = TestAccount().makeViewModel()
        viewModel.email = "new@test.test"
        viewModel.password = "abc"

        #expect(viewModel.canSignIn)
        #expect(!viewModel.canSignUp)

        viewModel.password = "abcdef"
        #expect(viewModel.canSignUp)
    }

    @Test func signInTrimsEmailClearsPasswordAndSyncs() async {
        let account = TestAccount()
        let viewModel = account.makeViewModel()
        viewModel.email = "  test@test.test  "
        viewModel.password = "test"

        await viewModel.signIn()

        #expect(account.receivedEmail == "test@test.test")
        #expect(account.receivedPassword == "test")
        #expect(viewModel.isSignedIn)
        #expect(viewModel.signedInEmail == "test@test.test")
        #expect(viewModel.password.isEmpty)
        #expect(viewModel.state == .loaded)
        #expect(account.syncCount == 1)
    }

    @Test func showsErrorWhenSignInFails() async {
        let account = TestAccount()
        account.isOffline = true
        let viewModel = account.makeViewModel()
        viewModel.email = "test@test.test"
        viewModel.password = "test"

        await viewModel.signIn()

        #expect(viewModel.state == .failed)
        #expect(viewModel.errorMessage == "No connection")
        #expect(!viewModel.isSignedIn)
        #expect(account.syncCount == 0)
    }

    @Test func signUpSignsInWhenNoConfirmationIsNeeded() async {
        let account = TestAccount()
        let viewModel = account.makeViewModel()
        viewModel.email = "new@test.test"
        viewModel.password = "abcdef"

        await viewModel.signUp()

        #expect(viewModel.isSignedIn)
        #expect(!viewModel.isWaitingForEmailConfirmation)
        #expect(account.syncCount == 1)
    }

    @Test func signUpWaitsForEmailConfirmation() async {
        let account = TestAccount()
        account.needsEmailConfirmation = true
        let viewModel = account.makeViewModel()
        viewModel.email = "new@test.test"
        viewModel.password = "abcdef"

        await viewModel.signUp()

        #expect(viewModel.isWaitingForEmailConfirmation)
        #expect(!viewModel.isSignedIn)
        #expect(viewModel.state == .loaded)
    }

    @Test func userFromLastTimeIsSignedInAtOnce() {
        let account = TestAccount()
        account.signedInEmail = "test@test.test"

        let viewModel = account.makeViewModel()

        #expect(viewModel.isSignedIn)
        #expect(viewModel.signedInEmail == "test@test.test")
    }

    @Test func doesNotSyncWhenSignedOut() async {
        let account = TestAccount()
        let viewModel = account.makeViewModel()

        await viewModel.syncSavedMovies()

        #expect(account.syncCount == 0)
        #expect(viewModel.syncState == .idle)
    }

    @Test func showsErrorWhenSyncFails() async {
        let account = TestAccount()
        account.signedInEmail = "test@test.test"
        account.isSyncFailing = true
        let viewModel = account.makeViewModel()

        await viewModel.syncSavedMovies()

        #expect(viewModel.syncState == .failed)
        #expect(viewModel.syncErrorMessage == "No connection")
    }

    @Test func syncWorksAgainAfterFailure() async {
        let account = TestAccount()
        account.signedInEmail = "test@test.test"
        account.isSyncFailing = true
        let viewModel = account.makeViewModel()
        await viewModel.syncSavedMovies()

        account.isSyncFailing = false
        await viewModel.syncSavedMovies()

        #expect(viewModel.syncState == .loaded)
        #expect(account.syncCount == 2)
    }

    @Test func signOutSyncsThenClearsDevice() async {
        let account = TestAccount()
        account.signedInEmail = "test@test.test"
        let viewModel = account.makeViewModel()

        await viewModel.signOut()

        #expect(account.events == ["sync", "clear"])
        #expect(account.signedInEmail.isEmpty)
        #expect(!viewModel.isSignedIn)
    }
}
