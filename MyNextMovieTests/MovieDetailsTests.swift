import Foundation
import Testing

@testable import MyNextMovie

/// 6 November 2026, the "today" of the cinema tests.
private let testToday = Date(timeIntervalSince1970: 1_793_923_200)

/// Details of The Matrix, shortened. On purpose: an actor without a photo, a director listed
/// twice, an unofficial trailer before the official one, a Polish release with an empty
/// certification before the one with "16", and a streaming and a rental service in Poland.
private let matrixDetailsJSON = """
    {
      "id": 603,
      "tagline": "Believe the unbelievable.",
      "runtime": 136,
      "credits": {
        "cast": [
          {"id": 6384, "name": "Keanu Reeves", "character": "Neo", "profile_path": "/8RZL.jpg"},
          {"id": 2975, "name": "Laurence Fishburne", "character": "Morpheus", "profile_path": null}
        ],
        "crew": [
          {"id": 9340, "name": "Lana Wachowski", "job": "Director"},
          {"id": 9340, "name": "Lana Wachowski", "job": "Writer"},
          {"id": 9339, "name": "Lilly Wachowski", "job": "Director"}
        ]
      },
      "videos": {
        "results": [
          {"key": "unofficial", "site": "YouTube", "type": "Trailer", "official": false},
          {"key": "vKQi3bBA1y8", "site": "YouTube", "type": "Trailer", "official": true}
        ]
      },
      "release_dates": {
        "results": [
          {
            "iso_3166_1": "PL",
            "release_dates": [
              {"certification": "", "release_date": "1999-06-04T00:00:00.000Z", "type": 1},
              {"certification": "16", "release_date": "1999-06-04T00:00:00.000Z", "type": 3}
            ]
          },
          {
            "iso_3166_1": "US",
            "release_dates": [
              {"certification": "R", "release_date": "1999-03-31T00:00:00.000Z", "type": 3}
            ]
          }
        ]
      },
      "watch/providers": {
        "results": {
          "PL": {
            "link": "https://www.themoviedb.org/movie/603-the-matrix/watch?locale=PL",
            "flatrate": [
              {"provider_id": 119, "provider_name": "Amazon Prime Video", "logo_path": "/gMZd.png"}
            ],
            "rent": [
              {"provider_id": 2, "provider_name": "Apple TV", "logo_path": "/peURlLlr8jggOwK53fJ5wdQl05y.jpg"}
            ]
          }
        }
      },
      "recommendations": {
        "results": [
          {
            "id": 604,
            "title": "The Matrix Reloaded",
            "overview": "Neo and the rebel leaders have 72 hours left.",
            "release_date": "2003-05-15",
            "poster_path": "/9TGHDvWrqKBzwDxDodHYXEmOE6J.jpg",
            "vote_average": 7.0,
            "genre_ids": [12, 28, 53, 878]
          }
        ]
      }
    }
    """

/// An announced movie: no runtime yet and nothing appended.
private let announcedMovieDetailsJSON = """
    {
      "id": 1,
      "tagline": "",
      "runtime": null,
      "credits": {"cast": [], "crew": []},
      "videos": {"results": []},
      "release_dates": {"results": []},
      "watch/providers": {"results": {}},
      "recommendations": {"results": []}
    }
    """

@MainActor
private func decodeMatrixDetails() throws -> MovieDetails {
    return try decodeTMDBMovieDetails(Data(matrixDetailsJSON.utf8))
}

@MainActor
struct MovieDetailsDecodingTests {
    @Test func decodesTaglineAndRuntime() throws {
        let details = try decodeMatrixDetails()

        #expect(details.id == 603)
        #expect(details.tagline == "Believe the unbelievable.")
        #expect(details.runtime == 136)
    }

    @Test func decodesCastWithAndWithoutPhoto() throws {
        let details = try decodeMatrixDetails()

        #expect(details.credits.cast.count == 2)
        #expect(details.credits.cast[0].profilePath == "/8RZL.jpg")
        #expect(details.credits.cast[1].profilePath == nil)
    }

    @Test func decodesWatchProvidersUnderSlashKey() throws {
        let details = try decodeMatrixDetails()

        let polishProviders = try #require(details.watchProviders.results["PL"])
        #expect(polishProviders.flatrate?.first?.providerName == "Amazon Prime Video")
        #expect(polishProviders.rent?.count == 1)
        #expect(polishProviders.buy == nil)
    }

    @Test func decodesCountryCodeOfReleaseDates() throws {
        let details = try decodeMatrixDetails()

        #expect(details.releaseDates.results.first?.countryCode == "PL")
    }

    @Test func decodesRecommendationsAsMovies() throws {
        let details = try decodeMatrixDetails()

        let recommendedMovie = try #require(details.recommendations.results.first)
        #expect(recommendedMovie.id == 604)
        #expect(recommendedMovie.title == "The Matrix Reloaded")
        #expect(recommendedMovie.releaseDate == "2003-05-15")
    }

    @Test func decodesAnnouncedMovieWithoutRuntime() throws {
        let details = try decodeTMDBMovieDetails(Data(announcedMovieDetailsJSON.utf8))

        #expect(details.runtime == nil)
        #expect(formattedRuntime(details) == "")
        #expect(!hasWatchProviders(watchProviders(details, regionCode: "PL")))
    }
}

@MainActor
struct MovieDetailsTests {
    @Test func runtimeInHoursAndMinutes() {
        #expect(formattedRuntime(makeMovieDetails(runtime: 136)) == "2h 16m")
        #expect(formattedRuntime(makeMovieDetails(runtime: 120)) == "2h 0m")
    }

    @Test func runtimeUnderAnHourHasOnlyMinutes() {
        #expect(formattedRuntime(makeMovieDetails(runtime: 45)) == "45m")
    }

    @Test func runtimeIsEmptyWhenUnknown() {
        #expect(formattedRuntime(makeMovieDetails(runtime: nil)) == "")
        #expect(formattedRuntime(makeMovieDetails(runtime: 0)) == "")
    }

    @Test func directorsAreListedOnceEach() throws {
        let details = try decodeMatrixDetails()

        #expect(directorNames(details) == "Lana Wachowski, Lilly Wachowski")
    }

    @Test func directorsAreEmptyWithoutDirector() {
        let writerOnly = [CrewMember(id: 1, name: "Someone", job: "Writer")]
        #expect(directorNames(makeMovieDetails(crew: writerOnly)) == "")
    }

    @Test func certificationSkipsEmptyOnes() throws {
        let details = try decodeMatrixDetails()

        #expect(ageCertification(details, regionCode: "PL") == "16")
        #expect(ageCertification(details, regionCode: "US") == "R")
    }

    @Test func certificationIsEmptyForOtherCountry() throws {
        let details = try decodeMatrixDetails()

        #expect(ageCertification(details, regionCode: "DE") == "")
    }

    @Test func officialTrailerWins() throws {
        let details = try decodeMatrixDetails()

        #expect(trailerKey(details) == "vKQi3bBA1y8")
    }

    @Test func unofficialTrailerWhenNoOfficial() {
        let videos = [
            Video(key: "teaser", site: "YouTube", type: "Teaser", official: true),
            Video(key: "fan-trailer", site: "YouTube", type: "Trailer", official: false),
        ]
        #expect(trailerKey(makeMovieDetails(videos: videos)) == "fan-trailer")
    }

    @Test func trailerOnOtherSiteIsSkipped() {
        let videos = [Video(key: "vimeo-key", site: "Vimeo", type: "Trailer", official: true)]
        let details = makeMovieDetails(videos: videos)

        #expect(trailerKey(details) == "")
        #expect(trailerURL(details) == nil)
        #expect(!hasTrailer(details))
    }

    @Test func trailerURLPointsToYouTube() throws {
        let details = try decodeMatrixDetails()

        #expect(trailerURL(details) == URL(string: "https://www.youtube.com/watch?v=vKQi3bBA1y8"))
        #expect(hasTrailer(details))
    }

    @Test func factsLineAddsRuntimeAndCertification() throws {
        let details = try decodeMatrixDetails()
        let matrix = makeMovie(releaseDate: "1999-03-31", voteAverage: 8.2)

        #expect(movieFactsLine(matrix, details, regionCode: "PL") == "1999 · ★ 8.2 · 2h 16m · 16")
    }

    @Test func factsLineBeforeDetailsLoad() {
        let matrix = makeMovie(releaseDate: "1999-03-31", voteAverage: 8.2)

        #expect(movieFactsLine(matrix, emptyMovieDetails, regionCode: "PL") == "1999 · ★ 8.2")
    }

    @Test func profileURLIsNilWithoutPhoto() {
        let withPhoto = CastMember(id: 1, name: "Keanu", character: "Neo", profilePath: "/8RZL.jpg")
        let withoutPhoto = CastMember(id: 2, name: "Someone", character: "Agent", profilePath: nil)

        #expect(profileURL(withPhoto) == URL(string: "https://image.tmdb.org/t/p/w185/8RZL.jpg"))
        #expect(profileURL(withoutPhoto) == nil)
    }
}

@MainActor
struct InCinemasTests {
    @Test func recentCinemaPremiereIsInCinemas() {
        let details = makeMovieDetails(releaseDates: [
            makeCountryReleaseDates("PL", "2026-10-17T00:00:00.000Z", releaseTypeTheatrical)
        ])
        #expect(isInCinemas(details, regionCode: "PL", today: testToday))
    }

    @Test func limitedReleaseCountsToo() {
        let details = makeMovieDetails(releaseDates: [
            makeCountryReleaseDates("PL", "2026-11-06T00:00:00.000Z", releaseTypeTheatricalLimited)
        ])
        #expect(isInCinemas(details, regionCode: "PL", today: testToday))
    }

    @Test func oldPremiereIsNotInCinemas() {
        let details = makeMovieDetails(releaseDates: [
            makeCountryReleaseDates("PL", "2026-09-01T00:00:00.000Z", releaseTypeTheatrical)
        ])
        #expect(!isInCinemas(details, regionCode: "PL", today: testToday))
    }

    @Test func futurePremiereIsNotInCinemasYet() {
        let details = makeMovieDetails(releaseDates: [
            makeCountryReleaseDates("PL", "2026-12-25T00:00:00.000Z", releaseTypeTheatrical)
        ])
        #expect(!isInCinemas(details, regionCode: "PL", today: testToday))
        #expect(daysSinceReleaseDay("2026-12-25T00:00:00.000Z", today: testToday) == -1)
    }

    @Test func digitalReleaseIsNotCinema() {
        let digitalReleaseType = 4
        let details = makeMovieDetails(releaseDates: [
            makeCountryReleaseDates("PL", "2026-10-17T00:00:00.000Z", digitalReleaseType)
        ])
        #expect(!isInCinemas(details, regionCode: "PL", today: testToday))
    }

    @Test func premiereInAnotherCountryDoesNotCount() {
        let details = makeMovieDetails(releaseDates: [
            makeCountryReleaseDates("US", "2026-10-17T00:00:00.000Z", releaseTypeTheatrical)
        ])
        #expect(!isInCinemas(details, regionCode: "PL", today: testToday))
    }

    @Test func unreadableDateIsNotInCinemas() {
        let details = makeMovieDetails(releaseDates: [
            makeCountryReleaseDates("PL", "soon", releaseTypeTheatrical)
        ])
        #expect(!isInCinemas(details, regionCode: "PL", today: testToday))
        #expect(daysSinceReleaseDay("soon", today: testToday) == -1)
        #expect(daysSinceReleaseDay("2026-10-17T00:00:00.000Z", today: testToday) == 20)
    }
}

/// Short details for the function tests, like `makeMovie` in `MovieTests.swift`.
private func makeMovieDetails(
    runtime: Int? = nil,
    crew: [CrewMember] = [],
    videos: [Video] = [],
    releaseDates: [CountryReleaseDates] = []
) -> MovieDetails {
    return MovieDetails(
        id: 1,
        tagline: "",
        runtime: runtime,
        credits: Credits(cast: [], crew: crew),
        videos: VideoList(results: videos),
        releaseDates: ReleaseDateList(results: releaseDates),
        watchProviders: WatchProviderList(results: [:]),
        recommendations: TMDBMoviePage(results: [])
    )
}

private func makeCountryReleaseDates(
    _ countryCode: String,
    _ releaseDate: String,
    _ type: Int
) -> CountryReleaseDates {
    return CountryReleaseDates(
        countryCode: countryCode,
        releaseDates: [ReleaseDate(certification: "", releaseDate: releaseDate, type: type)]
    )
}
