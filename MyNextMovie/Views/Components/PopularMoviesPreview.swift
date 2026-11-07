import SwiftUI

/// Fetches the popular movies from TMDB for a preview that needs a real movie.
/// Needs the TMDB key in `Config/Secrets.xcconfig`, like the app.
struct PopularMoviesPreview<Content: View>: View {
    @ViewBuilder let content: ([Movie]) -> Content

    @State private var movies: [Movie] = []
    @State private var errorMessage = ""
    @State private var isLoading = true

    var body: some View {
        loadedContent
            .task { await loadMovies() }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if isLoading {
            ProgressView()
        } else if !errorMessage.isEmpty {
            Text(errorMessage)
        } else {
            content(movies)
        }
    }

    private func loadMovies() async {
        do {
            movies = try await fetchPopularMovies()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    PopularMoviesPreview { movies in
        Text(movies[0].title)
    }
}
