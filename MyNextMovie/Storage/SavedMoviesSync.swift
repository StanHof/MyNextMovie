import Foundation
import SwiftData

/// Makes the device and the account hold the same saved movies, in three steps:
/// 1. movies removed on the device are removed from the account,
/// 2. the account list is taken as the truth for movies the account knew,
/// 3. movies new on the device are sent to the account.
///
/// When a request fails the function throws. Unsent changes stay marked and go with the next sync.
/// The user may save or remove a movie during an `await`, so the database is read again
/// after every `await` and only movie ids cross it.
func syncSavedMovies(_ context: ModelContext, cloud: SavedMoviesCloud) async throws {
    try await sendRemovals(context, cloud: cloud)
    try await takeAccountList(context, cloud: cloud)
    try await sendNewMovies(context, cloud: cloud)
}

/// A row to send to the account.
func cloudMovieFromSaved(_ savedMovie: SavedMovie) -> CloudSavedMovie {
    return CloudSavedMovie(
        id: savedMovie.movieId,
        title: savedMovie.title,
        overview: savedMovie.overview,
        releaseDate: savedMovie.releaseDate,
        posterPath: savedMovie.posterPath,
        voteAverage: savedMovie.voteAverage,
        genreIds: savedMovie.genreIds,
        savedAt: savedMovie.savedAt
    )
}

func movieFromCloud(_ cloudMovie: CloudSavedMovie) -> Movie {
    return Movie(
        id: cloudMovie.id,
        title: cloudMovie.title,
        overview: cloudMovie.overview,
        releaseDate: cloudMovie.releaseDate,
        posterPath: cloudMovie.posterPath,
        voteAverage: cloudMovie.voteAverage,
        genreIds: cloudMovie.genreIds
    )
}

// MARK: - Steps

/// Step 1: every `RemovedSavedMovie` is removed from the account, then the mark is deleted.
private func sendRemovals(_ context: ModelContext, cloud: SavedMoviesCloud) async throws {
    let removalMarks = (try? context.fetch(FetchDescriptor<RemovedSavedMovie>())) ?? []
    var removedMovieIds: [Int] = []
    for removalMark in removalMarks {
        removedMovieIds.append(removalMark.movieId)
    }
    for movieId in removedMovieIds {
        try await cloud.removeMovie(movieId)
        removeRemovalMarks(context, movieId: movieId)
    }
}

/// Step 2: a movie the account dropped leaves the device, a movie the account has comes to
/// the device or gets `isInCloud`. A movie marked as removed does not come back.
private func takeAccountList(_ context: ModelContext, cloud: SavedMoviesCloud) async throws {
    let cloudMovies = try await cloud.fetchMovies()
    var cloudMovieIds: Set<Int> = []
    for cloudMovie in cloudMovies {
        cloudMovieIds.insert(cloudMovie.id)
    }
    removeMoviesDroppedByAccount(context, cloudMovieIds: cloudMovieIds)
    for cloudMovie in cloudMovies {
        takeMovieFromAccount(context, cloudMovie)
    }
}

private func removeMoviesDroppedByAccount(_ context: ModelContext, cloudMovieIds: Set<Int>) {
    let savedMovies = (try? context.fetch(FetchDescriptor<SavedMovie>())) ?? []
    for savedMovie in savedMovies {
        if savedMovie.isInCloud && !cloudMovieIds.contains(savedMovie.movieId) {
            context.delete(savedMovie)
        }
    }
}

private func takeMovieFromAccount(_ context: ModelContext, _ cloudMovie: CloudSavedMovie) {
    if !fetchRemovalMarks(context, movieId: cloudMovie.id).isEmpty {
        return
    }
    let savedCopies = fetchSavedMovies(context, movieId: cloudMovie.id)
    if savedCopies.isEmpty {
        let movie = movieFromCloud(cloudMovie)
        context.insert(SavedMovie(movie: movie, savedAt: cloudMovie.savedAt, isInCloud: true))
    }
    for savedCopy in savedCopies {
        savedCopy.isInCloud = true
    }
}

/// Step 3: every `SavedMovie` without `isInCloud` goes to the account in one request.
/// A movie removed while the request ran gets a removal mark, so it leaves the account too.
private func sendNewMovies(_ context: ModelContext, cloud: SavedMoviesCloud) async throws {
    let newMovies = fetchMoviesNotInCloud(context)
    if newMovies.isEmpty {
        return
    }
    var cloudMovies: [CloudSavedMovie] = []
    var sentMovieIds: [Int] = []
    for newMovie in newMovies {
        cloudMovies.append(cloudMovieFromSaved(newMovie))
        sentMovieIds.append(newMovie.movieId)
    }
    try await cloud.uploadMovies(cloudMovies)
    for movieId in sentMovieIds {
        markMovieAsInCloud(context, movieId: movieId)
    }
}

private func fetchMoviesNotInCloud(_ context: ModelContext) -> [SavedMovie] {
    let descriptor = FetchDescriptor<SavedMovie>(
        predicate: #Predicate { savedMovie in savedMovie.isInCloud == false }
    )
    return (try? context.fetch(descriptor)) ?? []
}

private func markMovieAsInCloud(_ context: ModelContext, movieId: Int) {
    let savedCopies = fetchSavedMovies(context, movieId: movieId)
    if savedCopies.isEmpty {
        markMovieRemoved(context, movieId: movieId)
    }
    for savedCopy in savedCopies {
        savedCopy.isInCloud = true
    }
}
