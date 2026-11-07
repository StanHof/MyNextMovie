import MapKit
import Observation

/// The cinemas on the map and in the list, closest first once the user is found.
/// A class only because SwiftUI's @Observable requires one.
@Observable
final class CinemaMapViewModel {
    private(set) var cinemas: [Cinema]
    private(set) var userLocation = fallbackUserLocation
    private(set) var selectedCinemaId = noCinemaSelected
    private(set) var isLocating = false
    var visibleRegion = wroclawMapRegion

    private let findUserLocation: UserLocationFinder
    private let lastKnownLocation: LastKnownLocationReader
    private var hasAskedForLocation = false

    init(
        cinemas: [Cinema],
        findUserLocation: @escaping UserLocationFinder,
        lastKnownLocation: @escaping LastKnownLocationReader = { fallbackUserLocation }
    ) {
        self.cinemas = cinemas.sorted(by: isCloser)
        self.findUserLocation = findUserLocation
        self.lastKnownLocation = lastKnownLocation
    }

    /// The app asked, but has no location: the user refused or it took too long.
    var isLocationUnavailable: Bool {
        return hasAskedForLocation && !isLocating && !userLocation.isKnown
    }

    /// Sorts by the last known location at once, then by a fresh one when it comes.
    /// An unknown location never replaces a known one.
    func locateUser() async {
        hasAskedForLocation = true
        isLocating = true
        useLocation(lastKnownLocation())
        useLocation(await findUserLocation())
        isLocating = false
    }

    /// Asks for the location only the first time.
    func locateUserIfNeeded() async {
        if !hasAskedForLocation {
            await locateUser()
        }
    }

    /// Selects the cinema, or clears the selection when it is already selected.
    func toggleCinema(_ cinemaId: String) {
        if selectedCinemaId == cinemaId {
            selectedCinemaId = noCinemaSelected
        } else {
            selectedCinemaId = cinemaId
        }
    }

    private func useLocation(_ location: UserLocation) {
        if !location.isKnown {
            return
        }
        userLocation = location
        cinemas = cinemasSortedByDistance(cinemas, from: location)
    }
}
