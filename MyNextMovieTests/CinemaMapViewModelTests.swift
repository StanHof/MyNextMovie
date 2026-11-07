import MapKit
import Testing

@testable import MyNextMovie

/// A known location near Helios Magnolia, to tell the last known location from a fresh one.
@MainActor
private let testLocationNearHelios = UserLocation(
    latitude: 51.1188,
    longitude: 16.9906,
    isKnown: true
)

/// A view model that never finds the user.
@MainActor
private func makeViewModelWithoutLocation() -> CinemaMapViewModel {
    return CinemaMapViewModel(cinemas: testCinemas, findUserLocation: { fallbackUserLocation })
}

@MainActor
struct CinemaMapViewModelTests {
    @Test func showsCinemasAtOnceByName() {
        let viewModel = makeViewModelWithoutLocation()

        let expectedNames = [
            "DCF", "Helios Magnolia", "Kino Nowe Horyzonty", "Multikino Pasaż Grunwaldzki",
        ]
        #expect(namesOf(viewModel.cinemas) == expectedNames)
        #expect(!viewModel.userLocation.isKnown)
        #expect(!viewModel.isLocationUnavailable)
    }

    @Test func sortsByDistanceOnceUserIsFound() async {
        let viewModel = CinemaMapViewModel(
            cinemas: testCinemas,
            findUserLocation: { testUserLocation }
        )

        await viewModel.locateUser()

        #expect(viewModel.cinemas.first?.name == "DCF")
        #expect(viewModel.userLocation == testUserLocation)
        #expect(!viewModel.isLocating)
    }

    @Test func lastKnownLocationIsUsedWhenNoFreshOneComes() async {
        let viewModel = CinemaMapViewModel(
            cinemas: testCinemas,
            findUserLocation: { fallbackUserLocation },
            lastKnownLocation: { testUserLocation }
        )

        await viewModel.locateUser()

        #expect(viewModel.userLocation == testUserLocation)
        #expect(viewModel.cinemas.first?.name == "DCF")
        #expect(!viewModel.isLocationUnavailable)
    }

    @Test func freshLocationReplacesLastKnownOne() async {
        let viewModel = CinemaMapViewModel(
            cinemas: testCinemas,
            findUserLocation: { testUserLocation },
            lastKnownLocation: { testLocationNearHelios }
        )

        await viewModel.locateUser()

        #expect(viewModel.userLocation == testUserLocation)
        #expect(viewModel.cinemas.first?.name == "DCF")
    }

    @Test func saysWhenLocationIsUnavailable() async {
        let viewModel = makeViewModelWithoutLocation()

        await viewModel.locateUser()

        #expect(viewModel.isLocationUnavailable)
        #expect(viewModel.cinemas.first?.name == "DCF")
    }

    @Test func asksForLocationOnlyOnce() async {
        var locationRequestCount = 0
        let viewModel = CinemaMapViewModel(
            cinemas: testCinemas,
            findUserLocation: {
                locationRequestCount += 1
                return testUserLocation
            }
        )

        await viewModel.locateUserIfNeeded()
        await viewModel.locateUserIfNeeded()

        #expect(locationRequestCount == 1)
    }

    @Test func togglesSelection() {
        let viewModel = makeViewModelWithoutLocation()

        viewModel.toggleCinema("dcf")
        #expect(viewModel.selectedCinemaId == "dcf")

        viewModel.toggleCinema("helios-magnolia")
        #expect(viewModel.selectedCinemaId == "helios-magnolia")

        viewModel.toggleCinema("helios-magnolia")
        #expect(viewModel.selectedCinemaId == noCinemaSelected)
    }
}

@MainActor
struct CinemaDetailViewModelTests {
    @Test func findsNoRouteWithoutLocation() async {
        var routeRequestCount = 0
        let viewModel = CinemaDetailViewModel(
            cinema: testCinemaDCF,
            userLocation: fallbackUserLocation,
            findRoute: { _, _, _ in
                routeRequestCount += 1
                return makeTestRoute()
            }
        )

        await viewModel.loadRoute()

        #expect(!viewModel.canFindRoute)
        #expect(viewModel.routeState == .idle)
        #expect(routeRequestCount == 0)
    }

    @Test func findsRouteForSelectedTravelMode() async {
        var requestedTravelMode = TravelMode.walking
        let viewModel = CinemaDetailViewModel(
            cinema: testCinemaDCF,
            userLocation: testUserLocation,
            findRoute: { _, _, travelMode in
                requestedTravelMode = travelMode
                return makeTestRoute()
            }
        )
        viewModel.travelMode = .driving

        await viewModel.loadRoute()

        #expect(viewModel.canFindRoute)
        #expect(requestedTravelMode == .driving)
        #expect(viewModel.routeState == .loaded)
        #expect(viewModel.route.distanceInMeters == 950)
    }

    @Test func showsErrorWhenRouteFails() async {
        let viewModel = CinemaDetailViewModel(
            cinema: testCinemaDCF,
            userLocation: testUserLocation,
            findRoute: { _, _, _ in throw NoRouteFound() }
        )

        await viewModel.loadRoute()

        #expect(viewModel.routeState == .failed)
        #expect(viewModel.errorMessage == "Maps found no way to this cinema.")
    }

    @Test func routeSummaryHasTimeAndDistance() {
        let viewModel = CinemaDetailViewModel(
            cinema: testCinemaDCF,
            userLocation: testUserLocation,
            findRoute: { _, _, _ in makeTestRoute() }
        )

        #expect(viewModel.formattedTravelTime(makeTestRoute()) == "12 min")
        #expect(viewModel.routeSummary(makeTestRoute()) == "12 min · 950 m")
    }
}

/// A 12 minute walk of 950 meters.
@MainActor
private func makeTestRoute() -> CinemaRoute {
    return CinemaRoute(line: MKPolyline(), distanceInMeters: 950, travelTime: 12 * 60)
}
