import Foundation

/// TMDB image server addresses for actor photos and streaming service logos.
private let tmdbProfileBaseURL = "https://image.tmdb.org/t/p/w185"
private let tmdbLogoBaseURL = "https://image.tmdb.org/t/p/w92"

private let youTubeWatchBaseURL = "https://www.youtube.com/watch?v="
private let youTubeSiteName = "YouTube"
private let trailerVideoType = "Trailer"
private let directorJobName = "Director"

private let minutesPerHour = 60
private let directorSeparator = ", "

/// Country code used when the phone has none.
private let defaultWatchRegionCode = "PL"

// TMDB release types, see https://developer.themoviedb.org/reference/movie-release-dates
let releaseTypeTheatricalLimited = 2
let releaseTypeTheatrical = 3

/// How long a movie usually plays in cinemas after its premiere.
let typicalCinemaRunInDays = 42

/// Returned by `daysSinceReleaseDay` for an unreadable or future date.
let releaseDayNotPassed = -1

/// Length of "2026-10-17" at the start of a TMDB release date.
private let releaseDayLength = 10
private let secondsPerDay: TimeInterval = 24 * 60 * 60

// MARK: - Structures as TMDB returns them

/// Details of one movie with the parts added by `append_to_response`.
nonisolated struct MovieDetails: Decodable {
    let id: Int
    let tagline: String
    let runtime: Int?  // nil for announced movies
    let credits: Credits
    let videos: VideoList
    let releaseDates: ReleaseDateList
    let watchProviders: WatchProviderList
    let recommendations: TMDBMoviePage

    enum CodingKeys: String, CodingKey {
        case id
        case tagline
        case runtime
        case credits
        case videos
        case releaseDates
        case watchProviders = "watch/providers"
        case recommendations
    }
}

nonisolated struct Credits: Decodable {
    let cast: [CastMember]
    let crew: [CrewMember]
}

nonisolated struct CastMember: Decodable, Identifiable {
    let id: Int
    let name: String
    let character: String
    let profilePath: String?
}

nonisolated struct CrewMember: Decodable {
    let id: Int
    let name: String
    let job: String
}

nonisolated struct VideoList: Decodable {
    let results: [Video]
}

nonisolated struct Video: Decodable {
    let key: String
    let site: String
    let type: String
    let official: Bool
}

nonisolated struct ReleaseDateList: Decodable {
    let results: [CountryReleaseDates]
}

nonisolated struct CountryReleaseDates: Decodable {
    let countryCode: String
    let releaseDates: [ReleaseDate]

    enum CodingKeys: String, CodingKey {
        case countryCode = "iso31661"
        case releaseDates
    }
}

nonisolated struct ReleaseDate: Decodable {
    let certification: String
    let releaseDate: String  // "2026-10-17T00:00:00.000Z"
    let type: Int  // 2 and 3 are cinema premieres
}

/// Streaming services by country code, e.g. "PL".
nonisolated struct WatchProviderList: Decodable {
    let results: [String: CountryWatchProviders]
}

/// Lists are nil when the country has no service of that kind.
nonisolated struct CountryWatchProviders: Decodable {
    let link: String
    let flatrate: [WatchProvider]?
    let rent: [WatchProvider]?
    let buy: [WatchProvider]?
}

nonisolated struct WatchProvider: Decodable, Identifiable {
    let providerId: Int
    let providerName: String
    let logoPath: String?

    var id: Int { return providerId }
}

// MARK: - Constants

/// Shown until the real details arrive.
let emptyMovieDetails = MovieDetails(
    id: 0,
    tagline: "",
    runtime: nil,
    credits: Credits(cast: [], crew: []),
    videos: VideoList(results: []),
    releaseDates: ReleaseDateList(results: []),
    watchProviders: WatchProviderList(results: [:]),
    recommendations: TMDBMoviePage(results: [])
)

/// For a country TMDB has no streaming data for.
let noWatchProviders = CountryWatchProviders(link: "", flatrate: nil, rent: nil, buy: nil)

/// Country from the phone settings, Poland when there is none.
let watchRegionCode = Locale.current.region?.identifier ?? defaultWatchRegionCode

// MARK: - Functions

/// 136 -> "2h 16m", 45 -> "45m", unknown or 0 -> "".
func formattedRuntime(_ details: MovieDetails) -> String {
    let runtime = details.runtime ?? 0
    if runtime <= 0 {
        return ""
    }
    let hours = runtime / minutesPerHour
    let minutes = runtime % minutesPerHour
    if hours == 0 {
        return "\(minutes)m"
    }
    return "\(hours)h \(minutes)m"
}

/// Directors, each once, separated by ", ". TMDB lists a person once per job.
func directorNames(_ details: MovieDetails) -> String {
    var names: [String] = []
    for crewMember in details.credits.crew where crewMember.job == directorJobName {
        if !names.contains(crewMember.name) {
            names.append(crewMember.name)
        }
    }
    return names.joined(separator: directorSeparator)
}

/// First non-empty certification in the country, "" when there is none.
func ageCertification(_ details: MovieDetails, regionCode: String) -> String {
    for releaseDate in releaseDatesInCountry(details, regionCode: regionCode) {
        if !releaseDate.certification.isEmpty {
            return releaseDate.certification
        }
    }
    return ""
}

private func releaseDatesInCountry(_ details: MovieDetails, regionCode: String) -> [ReleaseDate] {
    for countryReleaseDates in details.releaseDates.results {
        if countryReleaseDates.countryCode == regionCode {
            return countryReleaseDates.releaseDates
        }
    }
    return []
}

/// YouTube key of the trailer. An official trailer wins, otherwise the first one. "" without any.
func trailerKey(_ details: MovieDetails) -> String {
    var firstTrailerKey = ""
    for video in details.videos.results {
        if video.site != youTubeSiteName || video.type != trailerVideoType {
            continue
        }
        if video.official {
            return video.key
        }
        if firstTrailerKey.isEmpty {
            firstTrailerKey = video.key
        }
    }
    return firstTrailerKey
}

func trailerURL(_ details: MovieDetails) -> URL? {
    let key = trailerKey(details)
    if key.isEmpty {
        return nil
    }
    return URL(string: youTubeWatchBaseURL + key)
}

func hasTrailer(_ details: MovieDetails) -> Bool {
    return trailerURL(details) != nil
}

/// "1999 · ★ 8.2 · 2h 16m · 16", without the parts that are unknown.
func movieFactsLine(_ movie: Movie, _ details: MovieDetails, regionCode: String) -> String {
    var parts = [yearAndRating(movie)]
    let runtime = formattedRuntime(details)
    if !runtime.isEmpty {
        parts.append(runtime)
    }
    let certification = ageCertification(details, regionCode: regionCode)
    if !certification.isEmpty {
        parts.append(certification)
    }
    return parts.joined(separator: textSeparator)
}

/// Streaming services in the country, `noWatchProviders` when TMDB has none.
func watchProviders(_ details: MovieDetails, regionCode: String) -> CountryWatchProviders {
    return details.watchProviders.results[regionCode] ?? noWatchProviders
}

func hasWatchProviders(_ countryProviders: CountryWatchProviders) -> Bool {
    let providerCount =
        (countryProviders.flatrate ?? []).count + (countryProviders.rent ?? []).count
        + (countryProviders.buy ?? []).count
    return providerCount > 0
}

/// Photo of the actor, nil when TMDB has none.
func profileURL(_ castMember: CastMember) -> URL? {
    let profilePath = castMember.profilePath ?? ""
    if profilePath.isEmpty {
        return nil
    }
    return URL(string: tmdbProfileBaseURL + profilePath)
}

/// Logo of the streaming service, nil when TMDB has none.
func logoURL(_ provider: WatchProvider) -> URL? {
    let logoPath = provider.logoPath ?? ""
    if logoPath.isEmpty {
        return nil
    }
    return URL(string: tmdbLogoBaseURL + logoPath)
}

// MARK: - Cinemas

/// Whether the movie had a cinema premiere in the country at most `typicalCinemaRunInDays` ago.
func isInCinemas(_ details: MovieDetails, regionCode: String, today: Date) -> Bool {
    for releaseDate in releaseDatesInCountry(details, regionCode: regionCode) {
        if !isTheatricalRelease(releaseDate) {
            continue
        }
        let daysSincePremiere = daysSinceReleaseDay(releaseDate.releaseDate, today: today)
        if daysSincePremiere != releaseDayNotPassed && daysSincePremiere <= typicalCinemaRunInDays {
            return true
        }
    }
    return false
}

private func isTheatricalRelease(_ releaseDate: ReleaseDate) -> Bool {
    return releaseDate.type == releaseTypeTheatrical
        || releaseDate.type == releaseTypeTheatricalLimited
}

/// Whole days from the release day to `today`, `releaseDayNotPassed` for an unreadable or future date.
/// Only the day counts: the first 10 characters of "2026-10-17T00:00:00.000Z".
func daysSinceReleaseDay(_ releaseDate: String, today: Date) -> Int {
    if releaseDate.count < releaseDayLength {
        return releaseDayNotPassed
    }
    let dayText = String(releaseDate.prefix(releaseDayLength))
    let dayFormat = Date.ISO8601FormatStyle().year().month().day()
    guard let releaseDay = try? dayFormat.parse(dayText) else {
        return releaseDayNotPassed
    }
    let secondsSinceRelease = today.timeIntervalSince(releaseDay)
    if secondsSinceRelease < 0 {
        return releaseDayNotPassed
    }
    return Int(secondsSinceRelease / secondsPerDay)
}
