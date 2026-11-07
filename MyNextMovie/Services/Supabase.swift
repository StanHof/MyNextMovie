import Foundation
import Supabase

// The `saved_movies` table, see supabase/migrations.
private let savedMoviesTable = "saved_movies"
private let savedMoviesColumnId = "id"
private let savedMoviesColumnSavedAt = "saved_at"
private let savedMoviesPrimaryKey = "user_id,id"

/// Supabase Auth refuses shorter passwords.
let minimumPasswordLength = 6

// Account created by supabase/seed.sql. Debug builds fill the sign in screen with it.
let testAccountEmail = "test@test.test"
let testAccountPassword = "test"

let missingSupabaseKeysMessage = "Missing Supabase keys. Add them to Config/Secrets.xcconfig."

/// An error from Supabase, shown on the screen as `localizedDescription`.
nonisolated struct SupabaseError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// One row of `saved_movies`: the fields of `Movie` and the date it was saved.
/// The database fills `user_id` itself. Column names are snake_case.
nonisolated struct CloudSavedMovie: Codable, Equatable {
    let id: Int
    let title: String
    let overview: String
    let releaseDate: String
    let posterPath: String?
    let voteAverage: Double
    let genreIds: [Int]
    let savedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case voteAverage = "vote_average"
        case genreIds = "genre_ids"
        case savedAt = "saved_at"
    }
}

// MARK: - Client

/// One client for the whole app, made at the first request.
private var sharedSupabaseClient: SupabaseClient?

private func requireSupabaseClient() throws -> SupabaseClient {
    if let sharedSupabaseClient {
        return sharedSupabaseClient
    }
    let anonKey = supabaseAnonKey()
    guard let projectURL = URL(string: supabaseURL()), projectURL.host() != nil, !anonKey.isEmpty
    else {
        throw SupabaseError(message: missingSupabaseKeysMessage)
    }
    let client = SupabaseClient(supabaseURL: projectURL, supabaseKey: anonKey)
    sharedSupabaseClient = client
    return client
}

// MARK: - Account

/// Email of the user signed in last time, from the keychain. Works without the network.
func supabaseSignedInEmail() -> String {
    guard let client = try? requireSupabaseClient() else {
        return ""
    }
    return client.auth.currentUser?.email ?? ""
}

func signInToSupabase(email: String, password: String) async throws -> String {
    let client = try requireSupabaseClient()
    let session = try await client.auth.signIn(email: email, password: password)
    return session.user.email ?? email
}

/// "" when the account has to confirm its email first.
func signUpToSupabase(email: String, password: String) async throws -> String {
    let client = try requireSupabaseClient()
    let response = try await client.auth.signUp(email: email, password: password)
    guard let session = response.session else {
        return ""
    }
    return session.user.email ?? email
}

/// Signing out works without the network too, so a server error is ignored.
func signOutOfSupabase() async throws {
    let client = try requireSupabaseClient()
    try? await client.auth.signOut()
}

let supabaseAccountService = AccountService(
    signedInEmail: supabaseSignedInEmail,
    signIn: signInToSupabase,
    signUp: signUpToSupabase,
    signOut: signOutOfSupabase
)

// MARK: - Saved movies

/// Rows of the signed in user, newest first. Row Level Security hides the other users' rows.
func fetchCloudSavedMovies() async throws -> [CloudSavedMovie] {
    let client = try requireSupabaseClient()
    let cloudMovies: [CloudSavedMovie] =
        try await client
        .from(savedMoviesTable)
        .select()
        .order(savedMoviesColumnSavedAt, ascending: false)
        .execute()
        .value
    return cloudMovies
}

/// Adds rows. A row the account already has stays as it is.
func uploadCloudSavedMovies(_ cloudMovies: [CloudSavedMovie]) async throws {
    if cloudMovies.isEmpty {
        return
    }
    let client = try requireSupabaseClient()
    try await client
        .from(savedMoviesTable)
        .upsert(
            cloudMovies,
            onConflict: savedMoviesPrimaryKey,
            returning: .minimal,
            ignoreDuplicates: true
        )
        .execute()
}

func removeCloudSavedMovie(movieId: Int) async throws {
    let client = try requireSupabaseClient()
    try await client
        .from(savedMoviesTable)
        .delete(returning: .minimal)
        .eq(savedMoviesColumnId, value: movieId)
        .execute()
}

let supabaseSavedMoviesCloud = SavedMoviesCloud(
    fetchMovies: fetchCloudSavedMovies,
    uploadMovies: uploadCloudSavedMovies,
    removeMovie: removeCloudSavedMovie
)
