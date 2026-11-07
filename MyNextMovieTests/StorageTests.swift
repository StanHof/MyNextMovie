import Foundation
import SwiftData
import Testing

@testable import MyNextMovie

/// An empty database in memory. Keep the container in a variable until the end of the test.
@MainActor
func makeTestContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Schema(storedModelTypes), configurations: [configuration])
}

/// 1 January 1970 plus the minutes. Tests use it to know which date is newer.
func testDate(minute: Double) -> Date {
    return Date(timeIntervalSince1970: 0).addingTimeInterval(60 * minute)
}

@MainActor
struct SavedMovieTests {
    @Test func toggleSavesThenRemoves() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let matrix = testMovies[0]

        toggleSavedMovie(context, matrix, now: testDate(minute: 1))
        #expect(isMovieSaved(context, movieId: matrix.id))

        toggleSavedMovie(context, matrix, now: testDate(minute: 2))
        #expect(!isMovieSaved(context, movieId: matrix.id))
    }

    @Test func savedCopyKeepsEveryField() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let matrix = testMovies[0]

        toggleSavedMovie(context, matrix, now: testDate(minute: 1))

        let savedMovies = try context.fetch(FetchDescriptor<SavedMovie>())
        #expect(moviesFromSaved(savedMovies) == [matrix])
    }

    @Test func removingMovieTheAccountHasLeavesAMark() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let matrix = testMovies[0]
        context.insert(SavedMovie(movie: matrix, savedAt: testDate(minute: 1), isInCloud: true))

        toggleSavedMovie(context, matrix, now: testDate(minute: 2))

        #expect(!isMovieSaved(context, movieId: matrix.id))
        let removalMarks = try context.fetch(FetchDescriptor<RemovedSavedMovie>())
        #expect(removalMarks.count == 1)
        #expect(removalMarks.first?.movieId == matrix.id)
    }

    @Test func removingMovieOnlyOnDeviceLeavesNoMark() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let matrix = testMovies[0]

        toggleSavedMovie(context, matrix, now: testDate(minute: 1))
        toggleSavedMovie(context, matrix, now: testDate(minute: 2))

        #expect(!isMovieSaved(context, movieId: matrix.id))
        #expect(try context.fetchCount(FetchDescriptor<RemovedSavedMovie>()) == 0)
    }

    @Test func clearRemovesMoviesAndMarks() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let movieInCloud = SavedMovie(
            movie: testMovies[0],
            savedAt: testDate(minute: 1),
            isInCloud: true
        )
        let movieOnDevice = SavedMovie(
            movie: testMovies[1],
            savedAt: testDate(minute: 2),
            isInCloud: false
        )
        context.insert(movieInCloud)
        context.insert(movieOnDevice)
        context.insert(RemovedSavedMovie(movieId: testMovies[2].id))

        clearSavedMovies(context)

        #expect(try context.fetchCount(FetchDescriptor<SavedMovie>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RemovedSavedMovie>()) == 0)
    }
}

@MainActor
struct SearchHistoryTests {
    @Test func newestSearchComesFirst() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        recordSearch(context, query: "matrix", now: testDate(minute: 1))
        recordSearch(context, query: "alien", now: testDate(minute: 2))

        #expect(queriesOf(recentSearches(context)) == ["alien", "matrix"])
    }

    @Test func repeatedSearchMovesToTop() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        recordSearch(context, query: "matrix", now: testDate(minute: 1))
        recordSearch(context, query: "alien", now: testDate(minute: 2))
        recordSearch(context, query: "matrix", now: testDate(minute: 3))

        #expect(queriesOf(recentSearches(context)) == ["matrix", "alien"])
    }

    @Test func emptyAndSpacesAreNotRecorded() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        recordSearch(context, query: "", now: testDate(minute: 1))
        recordSearch(context, query: "   ", now: testDate(minute: 2))
        recordSearch(context, query: "  dune  ", now: testDate(minute: 3))

        #expect(queriesOf(recentSearches(context)) == ["dune"])
    }

    @Test func keepsOnlyRecentSearches() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let searchCount = 13

        for searchNumber in 1...searchCount {
            let searchedAt = testDate(minute: Double(searchNumber))
            recordSearch(context, query: "movie \(searchNumber)", now: searchedAt)
        }

        let entries = recentSearches(context)
        #expect(entries.count == maxSearchHistoryCount)
        #expect(entries.first?.query == "movie \(searchCount)")
        let storedCount = try context.fetchCount(FetchDescriptor<SearchHistoryEntry>())
        #expect(storedCount == maxSearchHistoryCount)
    }

    @Test func clearRemovesEverything() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        recordSearch(context, query: "matrix", now: testDate(minute: 1))
        recordSearch(context, query: "alien", now: testDate(minute: 2))

        clearSearchHistory(context)

        #expect(recentSearches(context).isEmpty)
    }
}

@MainActor
struct ResponseCacheTests {
    @Test func missingKeyGivesEmptyData() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        #expect(cachedResponseData(context, key: "popular").isEmpty)
    }

    @Test func storingAgainReplacesData() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let oldData = Data("old".utf8)
        let newData = Data("new".utf8)
        storeCachedResponse(context, key: "popular", data: oldData, now: testDate(minute: 1))
        storeCachedResponse(context, key: "popular", data: newData, now: testDate(minute: 2))

        #expect(cachedResponseData(context, key: "popular") == newData)
        #expect(try context.fetchCount(FetchDescriptor<CachedResponse>()) == 1)
    }

    @Test func freshAnswerIsReturnedAndCached() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let data = try await fetchWithCacheFallback(context, key: "popular") { Data("fresh".utf8) }

        #expect(data == Data("fresh".utf8))
        #expect(cachedResponseData(context, key: "popular") == Data("fresh".utf8))
    }

    @Test func cachedAnswerIsReturnedWhenOffline() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let cachedData = Data("cached".utf8)
        storeCachedResponse(context, key: "popular", data: cachedData, now: testDate(minute: 1))

        let data = try await fetchWithCacheFallback(context, key: "popular") {
            throw NoConnection()
        }

        #expect(data == cachedData)
    }

    @Test func errorIsRethrownWhenNothingCached() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        await #expect(throws: NoConnection.self) {
            try await fetchWithCacheFallback(context, key: "popular") {
                throw NoConnection()
            }
        }
    }
}

private func queriesOf(_ entries: [SearchHistoryEntry]) -> [String] {
    var queries: [String] = []
    for entry in entries {
        queries.append(entry.query)
    }
    return queries
}
