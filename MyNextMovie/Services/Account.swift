/// Signs in or creates an account and returns the email of the signed in user.
/// An empty string means the account waits for the confirmation of the email.
typealias AccountRequest = (_ email: String, _ password: String) async throws -> String

/// What the account view model needs from the account backend. The app passes Supabase,
/// tests pass closures, like `MovieLoader` for the movie list.
struct AccountService {
    let signedInEmail: @MainActor () -> String
    let signIn: AccountRequest
    let signUp: AccountRequest
    let signOut: () async throws -> Void
}

/// The `saved_movies` table of the signed in user, as three functions.
struct SavedMoviesCloud {
    let fetchMovies: () async throws -> [CloudSavedMovie]
    let uploadMovies: (_ cloudMovies: [CloudSavedMovie]) async throws -> Void
    let removeMovie: (_ movieId: Int) async throws -> Void
}
