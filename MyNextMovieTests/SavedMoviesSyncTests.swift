import Foundation
import SwiftData
import Testing

@testable import MyNextMovie

/// Stands in for the `saved_movies` table of one account.
/// A class, so the closures in `SavedMoviesCloud` and the test see the same rows.
@MainActor
private final class TestCloud {
    var movies: [CloudSavedMovie] = []
    var isOffline = false
    var uploadCount = 0

    func makeCloud() -> SavedMoviesCloud {
        return SavedMoviesCloud(
            fetchMovies: { try self.fetchMovies() },
            uploadMovies: { cloudMovies in try self.uploadMovies(cloudMovies) },
            removeMovie: { movieId in try self.removeMovie(movieId) }
        )
    }

    var movieIds: [Int] {
        var ids: [Int] = []
        for movie in movies {
            ids.append(movie.id)
        }
        return ids.sorted()
    }

    private func fetchMovies() throws -> [CloudSavedMovie] {
        try requireOnline()
        return movies
    }

    /// Like `upsert` with `ignoreDuplicates`: a row the table has stays as it is.
    private func uploadMovies(_ cloudMovies: [CloudSavedMovie]) throws {
        try requireOnline()
        uploadCount += 1
        for cloudMovie in cloudMovies where !movieIds.contains(cloudMovie.id) {
            movies.append(cloudMovie)
        }
    }

    private func removeMovie(_ movieId: Int) throws {
        try requireOnline()
        movies.removeAll { $0.id == movieId }
    }

    private func requireOnline() throws {
        if isOffline {
            throw NoConnection()
        }
    }
}

@MainActor
struct SavedMoviesSyncTests {
    @Test func movieSavedOnDeviceGoesToAccount() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cloud = TestCloud()
        toggleSavedMovie(context, testMovies[0], now: testDate(minute: 1))

        try await syncSavedMovies(context, cloud: cloud.makeCloud())

        #expect(cloud.movieIds == [testMovies[0].id])
        #expect(savedMovieIds(context) == [testMovies[0].id])
        #expect(fetchSavedMovies(context, movieId: testMovies[0].id).first?.isInCloud == true)
    }

    @Test func movieIsSentOnlyOnce() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cloud = TestCloud()
        toggleSavedMovie(context, testMovies[0], now: testDate(minute: 1))

        try await syncSavedMovies(context, cloud: cloud.makeCloud())
        try await syncSavedMovies(context, cloud: cloud.makeCloud())

        #expect(cloud.uploadCount == 1)
        #expect(cloud.movies.count == 1)
    }

    @Test func movieFromAccountComesToDevice() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cloud = TestCloud()
        cloud.movies = [makeCloudMovie(testMovies[1], minute: 5)]

        try await syncSavedMovies(context, cloud: cloud.makeCloud())

        let savedCopy = try #require(fetchSavedMovies(context, movieId: testMovies[1].id).first)
        #expect(movieFromSaved(savedCopy) == testMovies[1])
        #expect(savedCopy.isInCloud)
        #expect(savedCopy.savedAt == testDate(minute: 5))
    }

    @Test func deviceAndAccountListsAreMerged() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cloud = TestCloud()
        cloud.movies = [makeCloudMovie(testMovies[1], minute: 1)]
        toggleSavedMovie(context, testMovies[0], now: testDate(minute: 2))

        try await syncSavedMovies(context, cloud: cloud.makeCloud())

        let expectedIds = [testMovies[0].id, testMovies[1].id].sorted()
        #expect(cloud.movieIds == expectedIds)
        #expect(savedMovieIds(context) == expectedIds)
    }

    @Test func movieRemovedOnDeviceIsRemovedFromAccount() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cloud = TestCloud()
        cloud.movies = [makeCloudMovie(testMovies[0], minute: 1)]
        context.insert(makeSavedMovieInCloud(testMovies[0], minute: 1))
        toggleSavedMovie(context, testMovies[0], now: testDate(minute: 2))

        try await syncSavedMovies(context, cloud: cloud.makeCloud())

        #expect(cloud.movies.isEmpty)
        #expect(savedMovieIds(context).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<RemovedSavedMovie>()) == 0)
    }

    @Test func movieRemovedOnAnotherDeviceIsRemovedHere() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cloud = TestCloud()
        context.insert(makeSavedMovieInCloud(testMovies[0], minute: 1))

        try await syncSavedMovies(context, cloud: cloud.makeCloud())

        #expect(savedMovieIds(context).isEmpty)
    }

    @Test func changesMadeOfflineAreSentWithTheNextSync() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cloud = TestCloud()
        cloud.movies = [makeCloudMovie(testMovies[0], minute: 1)]
        context.insert(makeSavedMovieInCloud(testMovies[0], minute: 1))

        cloud.isOffline = true
        toggleSavedMovie(context, testMovies[0], now: testDate(minute: 2))
        toggleSavedMovie(context, testMovies[1], now: testDate(minute: 3))
        await #expect(throws: NoConnection.self) {
            try await syncSavedMovies(context, cloud: cloud.makeCloud())
        }
        #expect(cloud.movieIds == [testMovies[0].id])

        cloud.isOffline = false
        try await syncSavedMovies(context, cloud: cloud.makeCloud())

        #expect(cloud.movieIds == [testMovies[1].id])
        #expect(savedMovieIds(context) == [testMovies[1].id])
        #expect(try context.fetchCount(FetchDescriptor<RemovedSavedMovie>()) == 0)
    }

    @Test func movieRemovedAndSavedAgainOfflineStays() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cloud = TestCloud()
        cloud.movies = [makeCloudMovie(testMovies[0], minute: 1)]
        context.insert(makeSavedMovieInCloud(testMovies[0], minute: 1))

        toggleSavedMovie(context, testMovies[0], now: testDate(minute: 2))
        toggleSavedMovie(context, testMovies[0], now: testDate(minute: 3))
        try await syncSavedMovies(context, cloud: cloud.makeCloud())

        #expect(cloud.movieIds == [testMovies[0].id])
        #expect(cloud.movies.first?.savedAt == testDate(minute: 3))
        let savedCopy = try #require(fetchSavedMovies(context, movieId: testMovies[0].id).first)
        #expect(savedCopy.isInCloud)
        #expect(try context.fetchCount(FetchDescriptor<RemovedSavedMovie>()) == 0)
    }
}

@MainActor
struct CloudSavedMovieTests {
    @Test func encodesColumnNamesInSnakeCase() throws {
        let cloudMovie = makeCloudMovie(testMovies[0], minute: 1)

        let json = try JSONEncoder().encode(cloudMovie)
        let jsonObject = try JSONSerialization.jsonObject(with: json) as? [String: Any]

        let keys = Set(jsonObject?.keys ?? [:].keys)
        for columnName in ["release_date", "poster_path", "vote_average", "genre_ids", "saved_at"] {
            #expect(keys.contains(columnName))
        }
    }

    @Test func cloudCopyKeepsEveryMovieField() {
        let savedMovie = makeSavedMovieInCloud(testMovies[0], minute: 1)

        let cloudMovie = cloudMovieFromSaved(savedMovie)

        #expect(movieFromCloud(cloudMovie) == testMovies[0])
        #expect(cloudMovie.savedAt == testDate(minute: 1))
    }
}

@MainActor
private func makeCloudMovie(_ movie: Movie, minute: Double) -> CloudSavedMovie {
    return CloudSavedMovie(
        id: movie.id,
        title: movie.title,
        overview: movie.overview,
        releaseDate: movie.releaseDate,
        posterPath: movie.posterPath,
        voteAverage: movie.voteAverage,
        genreIds: movie.genreIds,
        savedAt: testDate(minute: minute)
    )
}

/// A movie the account already has, as the device remembers it.
@MainActor
private func makeSavedMovieInCloud(_ movie: Movie, minute: Double) -> SavedMovie {
    return SavedMovie(movie: movie, savedAt: testDate(minute: minute), isInCloud: true)
}

/// Ids of every saved movie on the device, sorted.
@MainActor
private func savedMovieIds(_ context: ModelContext) -> [Int] {
    let savedMovies = (try? context.fetch(FetchDescriptor<SavedMovie>())) ?? []
    var ids: [Int] = []
    for savedMovie in savedMovies {
        ids.append(savedMovie.movieId)
    }
    return ids.sorted()
}
