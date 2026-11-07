import SwiftData
import SwiftUI

@main
struct MyNextMovieApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: storedModelTypes)
    }
}

/// Has the SwiftData context and wraps the functions that need it: the TMDB cache and the sync.
/// The view models get plain function types.
private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var account: AccountViewModel?

    var body: some View {
        if let account {
            AppTabs(
                account: account,
                loadMovies: loadPopularMoviesWithCache,
                loadDetails: loadDetailsWithCache
            )
        } else {
            ProgressView().onAppear { makeAccountViewModel() }
        }
    }

    /// Made here, not in `init`, because the context comes from the environment.
    private func makeAccountViewModel() {
        let context = modelContext
        account = AccountViewModel(
            account: supabaseAccountService,
            syncSavedMovies: { try await syncSavedMoviesWithSupabase(context) },
            clearSavedMovies: { clearSavedMovies(context) }
        )
    }

    private func syncSavedMoviesWithSupabase(_ context: ModelContext) async throws {
        try await syncSavedMovies(context, cloud: supabaseSavedMoviesCloud)
    }

    private func loadPopularMoviesWithCache() async throws -> [Movie] {
        return try await loadPopularMovies(cache: modelContext)
    }

    private func loadDetailsWithCache(movieId: Int) async throws -> MovieDetails {
        return try await loadTMDBMovieDetails(movieId: movieId, cache: modelContext)
    }
}

/// The tabs for a signed in user, the sign in screen for everybody else.
/// Syncs the saved movies at start, when the app comes back and after every unsent change.
struct AppTabs: View {
    let account: AccountViewModel
    let loadMovies: MovieLoader
    let loadDetails: MovieDetailsLoader

    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<SavedMovie> { savedMovie in savedMovie.isInCloud == false })
    private var moviesNotInCloud: [SavedMovie]
    @Query private var removedMovies: [RemovedSavedMovie]

    var body: some View {
        if account.isSignedIn {
            tabs
        } else {
            SignInView(viewModel: account)
        }
    }

    private var tabs: some View {
        TabView {
            Tab("Movies", systemImage: symbolNameMovies) { movieList }
            Tab("Saved", systemImage: symbolNameSaved) { savedMovies }
            Tab("Cinemas", systemImage: symbolNameCinema) { cinemaMap }
            Tab("Account", systemImage: symbolNameAccount) { accountView }
            Tab("Search", systemImage: symbolNameSearch, role: .search) { search }
        }
        .task { await account.syncSavedMovies() }
        .onChange(of: scenePhase) { _, newPhase in syncWhenActive(newPhase) }
        .onChange(of: unsentChangeCount) { oldCount, newCount in syncWhenGrown(oldCount, newCount) }
    }

    private var movieList: some View {
        let viewModel = MovieListViewModel(loadMovies: loadMovies)
        return MovieListView(viewModel: viewModel, loadDetails: loadDetails)
    }

    private var savedMovies: some View {
        SavedMoviesView(loadDetails: loadDetails)
    }

    private var cinemaMap: some View {
        let viewModel = CinemaMapViewModel(
            cinemas: wroclawCinemas,
            findUserLocation: findUserLocation,
            lastKnownLocation: lastKnownUserLocation
        )
        return CinemaMapView(viewModel: viewModel, findRoute: findMapKitRoute, placement: .tab)
    }

    private var accountView: some View {
        AccountView(viewModel: account)
    }

    private var search: some View {
        let viewModel = SearchViewModel(searchMovies: searchTMDBMovies)
        return SearchView(viewModel: viewModel, loadDetails: loadDetails)
    }

    /// Saved movies the account does not have yet plus removals it does not know yet.
    private var unsentChangeCount: Int {
        return moviesNotInCloud.count + removedMovies.count
    }

    private func syncWhenActive(_ phase: ScenePhase) {
        if phase == .active {
            Task { await account.syncSavedMovies() }
        }
    }

    /// A drop of the count is the result of a sync and needs no other one.
    private func syncWhenGrown(_ oldCount: Int, _ newCount: Int) {
        if newCount > oldCount {
            Task { await account.syncSavedMovies() }
        }
    }
}
