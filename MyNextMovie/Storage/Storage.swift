import Foundation
import SwiftData

/// How many searches the Search screen remembers.
let maxSearchHistoryCount = 10

// MARK: - Watch later list

/// Saved copies of the movie: an empty array or one element.
func fetchSavedMovies(_ context: ModelContext, movieId: Int) -> [SavedMovie] {
    let descriptor = FetchDescriptor<SavedMovie>(
        predicate: #Predicate { savedMovie in savedMovie.movieId == movieId }
    )
    return (try? context.fetch(descriptor)) ?? []
}

func isMovieSaved(_ context: ModelContext, movieId: Int) -> Bool {
    return !fetchSavedMovies(context, movieId: movieId).isEmpty
}

/// Saves the movie, or removes it when it is already saved.
/// A removed movie the account has leaves a `RemovedSavedMovie`, so the next sync removes it there too.
/// A movie saved again before that sync keeps the mark: the sync first removes the old row
/// from the account, then uploads the new one with the new date.
func toggleSavedMovie(_ context: ModelContext, _ movie: Movie, now: Date) {
    let savedCopies = fetchSavedMovies(context, movieId: movie.id)
    if savedCopies.isEmpty {
        context.insert(SavedMovie(movie: movie, savedAt: now, isInCloud: false))
        return
    }
    for savedCopy in savedCopies {
        if savedCopy.isInCloud {
            markMovieRemoved(context, movieId: movie.id)
        }
        context.delete(savedCopy)
    }
}

func movieFromSaved(_ savedMovie: SavedMovie) -> Movie {
    return Movie(
        id: savedMovie.movieId,
        title: savedMovie.title,
        overview: savedMovie.overview,
        releaseDate: savedMovie.releaseDate,
        posterPath: savedMovie.posterPath,
        voteAverage: savedMovie.voteAverage,
        genreIds: savedMovie.genreIds
    )
}

func moviesFromSaved(_ savedMovies: [SavedMovie]) -> [Movie] {
    var movies: [Movie] = []
    for savedMovie in savedMovies {
        movies.append(movieFromSaved(savedMovie))
    }
    return movies
}

/// Removal marks of the movie: an empty array or one element.
func fetchRemovalMarks(_ context: ModelContext, movieId: Int) -> [RemovedSavedMovie] {
    let descriptor = FetchDescriptor<RemovedSavedMovie>(
        predicate: #Predicate { removedMovie in removedMovie.movieId == movieId }
    )
    return (try? context.fetch(descriptor)) ?? []
}

/// Remembers that the movie has to be removed from the account too.
func markMovieRemoved(_ context: ModelContext, movieId: Int) {
    if fetchRemovalMarks(context, movieId: movieId).isEmpty {
        context.insert(RemovedSavedMovie(movieId: movieId))
    }
}

func removeRemovalMarks(_ context: ModelContext, movieId: Int) {
    for removalMark in fetchRemovalMarks(context, movieId: movieId) {
        context.delete(removalMark)
    }
}

/// For signing out: removes every saved movie and removal mark from the device.
/// The account keeps its movies.
func clearSavedMovies(_ context: ModelContext) {
    let savedMovies = (try? context.fetch(FetchDescriptor<SavedMovie>())) ?? []
    for savedMovie in savedMovies {
        context.delete(savedMovie)
    }
    let removalMarks = (try? context.fetch(FetchDescriptor<RemovedSavedMovie>())) ?? []
    for removalMark in removalMarks {
        context.delete(removalMark)
    }
}

// MARK: - Search history

/// Remembers the search. A repeated text moves to the top instead of making a new entry.
func recordSearch(_ context: ModelContext, query: String, now: Date) {
    let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
    if trimmedQuery.isEmpty {
        return
    }
    let descriptor = FetchDescriptor<SearchHistoryEntry>(
        predicate: #Predicate { entry in entry.query == trimmedQuery }
    )
    let existingEntries = (try? context.fetch(descriptor)) ?? []
    if existingEntries.isEmpty {
        context.insert(SearchHistoryEntry(query: trimmedQuery, searchedAt: now))
    }
    for existingEntry in existingEntries {
        existingEntry.searchedAt = now
    }
    removeOldSearches(context)
}

/// Newest first, at most `maxSearchHistoryCount`.
func recentSearches(_ context: ModelContext) -> [SearchHistoryEntry] {
    var descriptor = FetchDescriptor<SearchHistoryEntry>(
        sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
    )
    descriptor.fetchLimit = maxSearchHistoryCount
    return (try? context.fetch(descriptor)) ?? []
}

func clearSearchHistory(_ context: ModelContext) {
    let entries = (try? context.fetch(FetchDescriptor<SearchHistoryEntry>())) ?? []
    for entry in entries {
        context.delete(entry)
    }
}

/// Keeps the `maxSearchHistoryCount` newest entries. Counts in a loop,
/// because `fetchOffset` skips entries that are not saved to disk yet.
private func removeOldSearches(_ context: ModelContext) {
    let descriptor = FetchDescriptor<SearchHistoryEntry>(
        sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
    )
    let entries = (try? context.fetch(descriptor)) ?? []
    for position in 0..<entries.count where position >= maxSearchHistoryCount {
        context.delete(entries[position])
    }
}

// MARK: - TMDB response cache

/// Keeps the JSON under the key. A new answer replaces the old one.
func storeCachedResponse(_ context: ModelContext, key: String, data: Data, now: Date) {
    let existingResponses = fetchCachedResponses(context, key: key)
    if existingResponses.isEmpty {
        context.insert(CachedResponse(key: key, data: data, fetchedAt: now))
    }
    for existingResponse in existingResponses {
        existingResponse.data = data
        existingResponse.fetchedAt = now
    }
}

/// The kept JSON, empty `Data` when there is none.
func cachedResponseData(_ context: ModelContext, key: String) -> Data {
    return fetchCachedResponses(context, key: key).first?.data ?? Data()
}

private func fetchCachedResponses(_ context: ModelContext, key: String) -> [CachedResponse] {
    let descriptor = FetchDescriptor<CachedResponse>(
        predicate: #Predicate { response in response.key == key }
    )
    return (try? context.fetch(descriptor)) ?? []
}

/// Calls `fetch`, keeps and returns its answer. When `fetch` fails, returns the kept answer.
/// Without a kept answer, throws the error of `fetch`.
func fetchWithCacheFallback(
    _ context: ModelContext,
    key: String,
    fetch: () async throws -> Data
) async throws -> Data {
    do {
        let data = try await fetch()
        storeCachedResponse(context, key: key, data: data, now: Date.now)
        return data
    } catch {
        let cachedData = cachedResponseData(context, key: key)
        if cachedData.isEmpty {
            throw error
        }
        return cachedData
    }
}
