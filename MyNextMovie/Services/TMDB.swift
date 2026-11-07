import Foundation
import SwiftData

// Parts of every TMDB address.
private let tmdbScheme = "https"
private let tmdbHost = "api.themoviedb.org"
private let tmdbPopularPath = "/3/movie/popular"
private let tmdbSearchPath = "/3/search/movie"
private let tmdbDiscoverPath = "/3/discover/movie"
private let tmdbMoviePath = "/3/movie/"

// Query parameter names.
private let tmdbParameterAPIKey = "api_key"
private let tmdbParameterQuery = "query"
private let tmdbParameterGenres = "with_genres"
private let tmdbParameterAppendToResponse = "append_to_response"

/// Extra parts of the movie details, fetched in the same request as the details.
private let tmdbDetailsAppendedParts =
    "credits,videos,release_dates,watch/providers,recommendations"

let httpStatusOK = 200
let httpStatusUnauthorized = 401

let missingTMDBAPIKeyMessage = "Missing TMDB API key. Add it to Config/Secrets.xcconfig."
private let invalidTMDBAPIKeyMessage = "TMDB rejected the API key. Check Config/Secrets.xcconfig."
private let invalidTMDBAddressMessage = "Could not build the TMDB address."

// Keys of the responses kept on the device, see `fetchWithCacheFallback`.
let popularMoviesCacheKey = "popular"
let movieDetailsCacheKeyPrefix = "movie/"

/// One page of a movie list from TMDB.
nonisolated struct TMDBMoviePage: Decodable {
    let results: [Movie]
}

/// An error from TMDB, shown on the screen as `localizedDescription`.
nonisolated struct TMDBError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

// MARK: - Addresses

/// Address of a TMDB request: the API key first, then `parameters`.
func tmdbURL(path: String, parameters: [URLQueryItem], apiKey: String) -> URL? {
    var components = URLComponents()
    components.scheme = tmdbScheme
    components.host = tmdbHost
    components.path = path
    components.queryItems = [URLQueryItem(name: tmdbParameterAPIKey, value: apiKey)] + parameters
    return components.url
}

func tmdbPopularURL(apiKey: String) -> URL? {
    return tmdbURL(path: tmdbPopularPath, parameters: [], apiKey: apiKey)
}

/// With a query the search endpoint, which cannot filter by genre.
/// Without one the discover endpoint, which lists movies of a genre.
func tmdbSearchURL(query: String, genreId: Int, apiKey: String) -> URL? {
    let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
    if trimmedQuery.isEmpty {
        let genreParameter = URLQueryItem(name: tmdbParameterGenres, value: String(genreId))
        return tmdbURL(path: tmdbDiscoverPath, parameters: [genreParameter], apiKey: apiKey)
    }
    let queryParameter = URLQueryItem(name: tmdbParameterQuery, value: trimmedQuery)
    return tmdbURL(path: tmdbSearchPath, parameters: [queryParameter], apiKey: apiKey)
}

func tmdbMovieDetailsURL(movieId: Int, apiKey: String) -> URL? {
    let appendParameter = URLQueryItem(
        name: tmdbParameterAppendToResponse,
        value: tmdbDetailsAppendedParts
    )
    let path = tmdbMoviePath + String(movieId)
    return tmdbURL(path: path, parameters: [appendParameter], apiKey: apiKey)
}

// MARK: - Decoding

private func makeTMDBDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}

func decodeTMDBMovies(_ data: Data) throws -> [Movie] {
    return try makeTMDBDecoder().decode(TMDBMoviePage.self, from: data).results
}

func decodeTMDBMovieDetails(_ data: Data) throws -> MovieDetails {
    return try makeTMDBDecoder().decode(MovieDetails.self, from: data)
}

// MARK: - Requests

/// Throws for every status other than 200. `URLSession` itself does not.
func checkTMDBResponse(_ response: URLResponse) throws {
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? httpStatusOK
    if statusCode == httpStatusUnauthorized {
        throw TMDBError(message: invalidTMDBAPIKeyMessage)
    }
    if statusCode != httpStatusOK {
        throw TMDBError(message: "TMDB answered with status \(statusCode).")
    }
}

/// The key from `Config/Secrets.xcconfig`, or an error that tells where to put it.
private func requireTMDBAPIKey() throws -> String {
    let apiKey = tmdbAPIKey()
    if apiKey.isEmpty {
        throw TMDBError(message: missingTMDBAPIKeyMessage)
    }
    return apiKey
}

/// Sends the request, checks the status and returns the body. Every TMDB request goes through here.
private func fetchTMDBData(_ address: URL?) async throws -> Data {
    guard let address else {
        throw TMDBError(message: invalidTMDBAddressMessage)
    }
    let (data, response) = try await URLSession.shared.data(from: address)
    try checkTMDBResponse(response)
    return data
}

/// A `MovieLoader` that asks TMDB for the popular movies.
func fetchPopularMovies() async throws -> [Movie] {
    let apiKey = try requireTMDBAPIKey()
    let data = try await fetchTMDBData(tmdbPopularURL(apiKey: apiKey))
    return try decodeTMDBMovies(data)
}

/// A `MovieSearch` that asks TMDB. The search endpoint ignores the genre,
/// so the result is filtered by genre here.
func searchTMDBMovies(query: String, genreId: Int) async throws -> [Movie] {
    let apiKey = try requireTMDBAPIKey()
    let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
    let address = tmdbSearchURL(query: trimmedQuery, genreId: genreId, apiKey: apiKey)
    let foundMovies = try decodeTMDBMovies(try await fetchTMDBData(address))
    return filterMovies(foundMovies, query: "", genreId: genreId)
}

/// A `MovieDetailsLoader` that asks TMDB.
func fetchMovieDetails(movieId: Int) async throws -> MovieDetails {
    let apiKey = try requireTMDBAPIKey()
    let data = try await fetchTMDBData(tmdbMovieDetailsURL(movieId: movieId, apiKey: apiKey))
    return try decodeTMDBMovieDetails(data)
}

// MARK: - Requests with the cache

/// Like `fetchPopularMovies`, but keeps the last answer and shows it when the request fails.
func loadPopularMovies(cache: ModelContext) async throws -> [Movie] {
    let data = try await fetchWithCacheFallback(cache, key: popularMoviesCacheKey) {
        let apiKey = try requireTMDBAPIKey()
        return try await fetchTMDBData(tmdbPopularURL(apiKey: apiKey))
    }
    return try decodeTMDBMovies(data)
}

/// Like `fetchMovieDetails`, but keeps the last answer and shows it when the request fails.
func loadTMDBMovieDetails(movieId: Int, cache: ModelContext) async throws -> MovieDetails {
    let cacheKey = movieDetailsCacheKeyPrefix + String(movieId)
    let data = try await fetchWithCacheFallback(cache, key: cacheKey) {
        let apiKey = try requireTMDBAPIKey()
        return try await fetchTMDBData(tmdbMovieDetailsURL(movieId: movieId, apiKey: apiKey))
    }
    return try decodeTMDBMovieDetails(data)
}
