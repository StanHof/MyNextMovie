import MapKit

/// Any function that finds a fresh location of the user.
typealias UserLocationFinder = () async -> UserLocation

/// Any function that returns the last location at once.
typealias LastKnownLocationReader = () -> UserLocation

enum TravelMode {
    case walking
    case driving
}

/// Any function that finds a route from the user to a cinema.
typealias CinemaRouteFinder = (UserLocation, Cinema, TravelMode) async throws -> CinemaRoute

/// A route to a cinema: the line for the map, its length and how long it takes.
struct CinemaRoute {
    let line: MKPolyline
    let distanceInMeters: CLLocationDistance
    let travelTime: TimeInterval
}

/// Shown before a route is found.
let noRoute = CinemaRoute(line: MKPolyline(), distanceInMeters: 0, travelTime: 0)

struct NoRouteFound: LocalizedError {
    var errorDescription: String? { "Maps found no way to this cinema." }
}

/// The first route MapKit finds. A `CinemaRouteFinder`.
func findMapKitRoute(
    userLocation: UserLocation,
    cinema: Cinema,
    travelMode: TravelMode
) async throws -> CinemaRoute {
    let request = MKDirections.Request()
    request.source = mapItemForUser(userLocation)
    request.destination = mapItemForCinema(cinema)
    request.transportType = transportTypeForMapKit(travelMode)
    let response = try await MKDirections(request: request).calculate()
    guard let route = response.routes.first else {
        throw NoRouteFound()
    }
    return CinemaRoute(
        line: route.polyline,
        distanceInMeters: route.distance,
        travelTime: route.expectedTravelTime
    )
}

/// The cinema as Apple Maps knows a place: position, name and address.
func mapItemForCinema(_ cinema: Cinema) -> MKMapItem {
    let location = CLLocation(latitude: cinema.latitude, longitude: cinema.longitude)
    let address = MKAddress(fullAddress: cinema.address, shortAddress: cinema.address)
    let mapItem = MKMapItem(location: location, address: address)
    mapItem.name = cinema.name
    return mapItem
}

private func mapItemForUser(_ userLocation: UserLocation) -> MKMapItem {
    let location = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
    return MKMapItem(location: location, address: nil)
}

func transportTypeForMapKit(_ travelMode: TravelMode) -> MKDirectionsTransportType {
    switch travelMode {
    case .walking:
        return .walking
    case .driving:
        return .automobile
    }
}

/// Opens Apple Maps with directions to the cinema.
func openCinemaInMaps(_ cinema: Cinema, travelMode: TravelMode) {
    let directionsMode =
        travelMode == .walking
        ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeDriving
    let launchOptions = [MKLaunchOptionsDirectionsModeKey: directionsMode]
    mapItemForCinema(cinema).openInMaps(launchOptions: launchOptions)
}

/// Street level imagery of the cinema, nil when Apple Maps has none.
func findLookAroundScene(_ cinema: Cinema) async -> MKLookAroundScene? {
    let request = MKLookAroundSceneRequest(coordinate: cinemaCoordinate(cinema))
    return try? await request.scene
}
