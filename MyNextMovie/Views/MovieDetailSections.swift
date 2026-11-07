import SwiftUI

private let maxCastMembers = 15
private let castPhotoSize: CGFloat = 72
private let castMemberWidth: CGFloat = 88
private let castTextMaxLines = 2
private let providerLogoSize: CGFloat = 44
private let recommendedCardWidth: CGFloat = 140

/// Required by the TMDB terms for the streaming data.
private let justWatchAttribution = "Streaming data from JustWatch"

/// Trailer, cast, streaming services and recommended movies under the overview.
/// Every section is shown only when it has data.
struct MovieDetailSections: View {
    let details: MovieDetails

    var body: some View {
        VStack(alignment: .leading, spacing: spacingExtraLarge) {
            trailerButton
            castSection
            watchProvidersSection
            recommendationsSection
        }
    }

    @ViewBuilder
    private var trailerButton: some View {
        if let trailerAddress = trailerURL(details) {
            Link(destination: trailerAddress) { trailerLabel }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
        }
    }

    private var trailerLabel: some View {
        Label("Watch Trailer", systemImage: symbolNameTrailer)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var castSection: some View {
        if !details.credits.cast.isEmpty {
            CastRow(cast: Array(details.credits.cast.prefix(maxCastMembers)))
        }
    }

    @ViewBuilder
    private var watchProvidersSection: some View {
        let countryProviders = watchProviders(details, regionCode: watchRegionCode)
        if hasWatchProviders(countryProviders) {
            WatchProvidersSection(countryProviders: countryProviders)
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        if !details.recommendations.results.isEmpty {
            RecommendationsRow(movies: details.recommendations.results)
        }
    }
}

/// Header of a section, aligned with the text of the screen.
private struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal)
    }
}

/// Actors in one row that scrolls sideways.
private struct CastRow: View {
    let cast: [CastMember]

    var body: some View {
        VStack(alignment: .leading, spacing: spacingMedium) {
            SectionTitle(title: "Cast")
            row
        }
    }

    private var row: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: spacingMedium) {
                ForEach(cast) { castMember in CastMemberView(castMember: castMember) }
            }
            .padding(.horizontal)
        }
    }
}

/// Round photo of the actor with the name and the character under it.
private struct CastMemberView: View {
    let castMember: CastMember

    var body: some View {
        VStack(spacing: spacingSmall) {
            photo
            caption
        }
        .frame(width: castMemberWidth)
    }

    private var photo: some View {
        AsyncImage(url: profileURL(castMember)) { loadedImage in
            loadedImage.resizable().scaledToFill()
        } placeholder: {
            photoPlaceholder
        }
        .frame(width: castPhotoSize, height: castPhotoSize)
        .clipShape(Circle())
    }

    private var photoPlaceholder: some View {
        Image(systemName: symbolNamePerson)
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
    }

    private var caption: some View {
        VStack(spacing: spacingTiny) {
            Text(castMember.name)
                .font(.caption.weight(.semibold))
                .lineLimit(castTextMaxLines)
            Text(castMember.character)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(castTextMaxLines)
        }
        .multilineTextAlignment(.center)
    }
}

/// Streaming services in the user's country, grouped by how the movie is available.
private struct WatchProvidersSection: View {
    let countryProviders: CountryWatchProviders

    var body: some View {
        VStack(alignment: .leading, spacing: spacingMedium) {
            SectionTitle(title: "Where to Watch")
            WatchProviderGroup(title: "Stream", providers: countryProviders.flatrate ?? [])
            WatchProviderGroup(title: "Rent", providers: countryProviders.rent ?? [])
            WatchProviderGroup(title: "Buy", providers: countryProviders.buy ?? [])
            attribution
        }
    }

    private var attribution: some View {
        Text(justWatchAttribution)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }
}

/// One kind of availability, e.g. "Stream", as a row of services that scrolls sideways.
private struct WatchProviderGroup: View {
    let title: String
    let providers: [WatchProvider]

    var body: some View {
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: spacingSmall) {
                groupTitle
                providerRow
            }
        }
    }

    private var groupTitle: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }

    private var providerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacingMedium) {
                ForEach(providers) { provider in WatchProviderView(provider: provider) }
            }
            .padding(.horizontal)
        }
    }
}

/// Logo and name of one streaming service.
private struct WatchProviderView: View {
    let provider: WatchProvider

    var body: some View {
        HStack(spacing: spacingSmall) {
            logo
            Text(provider.providerName).font(.subheadline)
        }
        .padding(.trailing, spacingSmall)
        .background(.quaternary, in: Capsule())
    }

    private var logo: some View {
        AsyncImage(url: logoURL(provider)) { loadedImage in
            loadedImage.resizable().scaledToFit()
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .frame(width: providerLogoSize, height: providerLogoSize)
        .clipShape(Circle())
    }
}

/// Recommended movies as cards in one row that scrolls sideways. Tapping a card opens its details.
private struct RecommendationsRow: View {
    let movies: [Movie]

    var body: some View {
        VStack(alignment: .leading, spacing: spacingMedium) {
            SectionTitle(title: "More Like This")
            row
        }
    }

    private var row: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: spacingLarge) {
                ForEach(movies) { movie in RecommendedMovieItem(movie: movie) }
            }
            .padding(.horizontal)
        }
    }
}

private struct RecommendedMovieItem: View {
    let movie: Movie

    var body: some View {
        NavigationLink(value: movie) {
            MovieCardView(movie: movie)
        }
        .buttonStyle(.plain)
        .frame(width: recommendedCardWidth)
    }
}
