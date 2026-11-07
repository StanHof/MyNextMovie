import SwiftData
import SwiftUI

/// The Saved tab: the watch later list, newest first.
struct SavedMoviesView: View {
    private let loadDetails: MovieDetailsLoader

    @Query(sort: \SavedMovie.savedAt, order: .reverse)
    private var savedMovies: [SavedMovie]

    init(loadDetails: @escaping MovieDetailsLoader) {
        self.loadDetails = loadDetails
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Saved")
                .navigationDestination(for: Movie.self) { movie in detailView(movie) }
        }
    }

    private func detailView(_ movie: Movie) -> some View {
        return MovieDetailView(movie: movie, loadDetails: loadDetails)
    }

    @ViewBuilder
    private var content: some View {
        if savedMovies.isEmpty {
            ContentUnavailableView(
                "No saved movies",
                systemImage: symbolNameSaved,
                description: Text("Save a movie with the bookmark on its details screen.")
            )
        } else {
            MovieGrid(title: "Watch Later", movies: moviesFromSaved(savedMovies))
        }
    }
}

/// Bookmark on the details screen. Filled when the movie is saved, tapping toggles it.
struct SaveMovieButton: View {
    let movie: Movie

    @Query private var savedCopies: [SavedMovie]
    @Environment(\.modelContext) private var modelContext

    init(movie: Movie) {
        self.movie = movie
        let movieId = movie.id
        _savedCopies = Query(filter: #Predicate { savedMovie in savedMovie.movieId == movieId })
    }

    var body: some View {
        Button {
            toggleSavedMovie(modelContext, movie, now: Date.now)
        } label: {
            Label(isSaved ? "Remove from Saved" : "Save", systemImage: symbolName)
        }
    }

    private var isSaved: Bool { return !savedCopies.isEmpty }

    private var symbolName: String { return isSaved ? symbolNameSavedFilled : symbolNameSaved }
}

#Preview {
    SavedMoviesView(loadDetails: fetchMovieDetails)
        .modelContainer(for: storedModelTypes, inMemory: true)
}
