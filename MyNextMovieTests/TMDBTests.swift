import Foundation
import Testing

@testable import MyNextMovie

private let testAPIKey = "test-key"

/// A shortened page of popular movies, as TMDB returns it.
private let popularPageJSON = """
    {
      "page": 1,
      "results": [
        {
          "id": 603,
          "title": "The Matrix",
          "overview": "A hacker learns that the world is a simulation.",
          "release_date": "1999-03-31",
          "poster_path": "/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg",
          "vote_average": 8.2,
          "genre_ids": [28, 878]
        }
      ]
    }
    """

private let pageWithoutPosterJSON = """
    {
      "page": 1,
      "results": [
        {
          "id": 603,
          "title": "The Matrix",
          "overview": "",
          "release_date": "1999-03-31",
          "poster_path": null,
          "vote_average": 8.2,
          "genre_ids": [28, 878]
        }
      ]
    }
    """

private let errorJSON = """
    {"status_code": 7, "status_message": "Invalid API key"}
    """

@MainActor
struct TMDBTests {
    @Test func decodesSnakeCaseKeys() throws {
        let movies = try decodeTMDBMovies(Data(popularPageJSON.utf8))

        let matrix = try #require(movies.first)
        #expect(matrix.id == 603)
        #expect(matrix.releaseDate == "1999-03-31")
        #expect(matrix.posterPath == "/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg")
        #expect(matrix.voteAverage == 8.2)
        #expect(matrix.genreIds == [genreIdAction, genreIdScienceFiction])
    }

    @Test func decodesMissingPosterAsNil() throws {
        let movies = try decodeTMDBMovies(Data(pageWithoutPosterJSON.utf8))

        let matrix = try #require(movies.first)
        #expect(matrix.posterPath == nil)
    }

    @Test func decodingFailsForOtherJSON() {
        #expect(throws: DecodingError.self) {
            try decodeTMDBMovies(Data(errorJSON.utf8))
        }
    }

    @Test func popularURLHasAPIKey() {
        let popularAddress = tmdbPopularURL(apiKey: testAPIKey)
        let expectedAddress = "https://api.themoviedb.org/3/movie/popular?api_key=test-key"
        #expect(popularAddress?.absoluteString == expectedAddress)
    }

    @Test func searchWithTextUsesSearchEndpoint() throws {
        let searchURL = try #require(
            tmdbSearchURL(query: "matrix", genreId: noGenreId, apiKey: testAPIKey)
        )

        #expect(searchURL.path() == "/3/search/movie")
        #expect(queryValue(searchURL, "query") == "matrix")
        #expect(queryValue(searchURL, "api_key") == testAPIKey)
    }

    @Test func searchWithGenreOnlyUsesDiscoverEndpoint() throws {
        let searchURL = try #require(
            tmdbSearchURL(query: "", genreId: genreIdAnimation, apiKey: testAPIKey)
        )

        #expect(searchURL.path() == "/3/discover/movie")
        #expect(queryValue(searchURL, "with_genres") == String(genreIdAnimation))
    }

    @Test func searchTextIsPercentEncoded() throws {
        let searchURL = try #require(
            tmdbSearchURL(query: "pan tadeusz", genreId: noGenreId, apiKey: testAPIKey)
        )

        #expect(searchURL.absoluteString.contains("query=pan%20tadeusz"))
    }

    @Test func detailsURLAppendsEveryPart() throws {
        let detailsURL = try #require(tmdbMovieDetailsURL(movieId: 603, apiKey: testAPIKey))

        #expect(detailsURL.path() == "/3/movie/603")
        let appendedParts = queryValue(detailsURL, "append_to_response")
        for part in ["credits", "videos", "release_dates", "watch/providers", "recommendations"] {
            #expect(appendedParts.contains(part))
        }
    }

    @Test func okResponsePasses() throws {
        try checkTMDBResponse(makeResponse(statusCode: httpStatusOK))
    }

    @Test func unauthorizedResponseMentionsAPIKey() {
        let thrownError = #expect(throws: TMDBError.self) {
            try checkTMDBResponse(makeResponse(statusCode: httpStatusUnauthorized))
        }
        #expect(thrownError?.message.contains("API key") == true)
    }

    @Test func otherErrorResponseShowsStatus() {
        let thrownError = #expect(throws: TMDBError.self) {
            try checkTMDBResponse(makeResponse(statusCode: 404))
        }
        #expect(thrownError?.message.contains("404") == true)
    }
}

/// Value of one query parameter of the address, "" when it is missing.
private func queryValue(_ address: URL, _ name: String) -> String {
    let queryItems = URLComponents(url: address, resolvingAgainstBaseURL: false)?.queryItems ?? []
    for queryItem in queryItems where queryItem.name == name {
        return queryItem.value ?? ""
    }
    return ""
}

@MainActor
private func makeResponse(statusCode: Int) -> URLResponse {
    let address = tmdbPopularURL(apiKey: testAPIKey) ?? URL(fileURLWithPath: "/")
    let response = HTTPURLResponse(
        url: address,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )
    return response ?? URLResponse()
}
