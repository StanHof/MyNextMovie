import CoreLocation
import Foundation

/// Distance of a cinema before the app knows where the user is.
nonisolated let unknownDistance: CLLocationDistance = -1

/// A cinema in Wrocław, a plain struct,
/// so the views and tests do not depend on `MKMapItem`.
nonisolated struct Cinema: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String  // empty when unknown
    let phoneNumber: String  // empty when unknown
    let website: String  // empty when unknown
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    var distanceInMeters = unknownDistance
}

/// Where the user is. `isKnown` is false when the app does not know it.
nonisolated struct UserLocation: Equatable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let isKnown: Bool
}

/// Selection on the map when no cinema is selected.
let noCinemaSelected = ""

/// Returned by `positionOfCinema` when the list has no cinema with the id.
let cinemaNotFound = -1

/// Rynek, shown when the location is unknown. Not isolated, because the location
/// search in `Location.swift` returns it from a background task.
nonisolated let fallbackCoordinate = CLLocationCoordinate2D(latitude: 51.1100, longitude: 17.0320)
nonisolated let fallbackUserLocation = UserLocation(
    latitude: fallbackCoordinate.latitude,
    longitude: fallbackCoordinate.longitude,
    isKnown: false
)

/// Distances under this are shown in meters, longer ones in kilometers.
private let metersPerKilometer: CLLocationDistance = 1000
private let kilometerFormat = "%.1f km"
private let phoneURLScheme = "tel:"

// MARK: - Positions and distances

func cinemaCoordinate(_ cinema: Cinema) -> CLLocationCoordinate2D {
    return CLLocationCoordinate2D(latitude: cinema.latitude, longitude: cinema.longitude)
}

func userCoordinate(_ userLocation: UserLocation) -> CLLocationCoordinate2D {
    return CLLocationCoordinate2D(
        latitude: userLocation.latitude,
        longitude: userLocation.longitude
    )
}

/// Straight line distance in meters.
func distanceInMeters(from userLocation: UserLocation, to cinema: Cinema) -> CLLocationDistance {
    let userPoint = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
    let cinemaPoint = CLLocation(latitude: cinema.latitude, longitude: cinema.longitude)
    return userPoint.distance(from: cinemaPoint)
}

/// Every cinema with its distance from the user, closest first.
func cinemasSortedByDistance(_ cinemas: [Cinema], from userLocation: UserLocation) -> [Cinema] {
    var measuredCinemas: [Cinema] = []
    for cinema in cinemas {
        var measuredCinema = cinema
        measuredCinema.distanceInMeters = distanceInMeters(from: userLocation, to: cinema)
        measuredCinemas.append(measuredCinema)
    }
    return measuredCinemas.sorted(by: isCloser)
}

/// Closer first, by name when the distance is the same.
func isCloser(_ firstCinema: Cinema, _ secondCinema: Cinema) -> Bool {
    if firstCinema.distanceInMeters != secondCinema.distanceInMeters {
        return firstCinema.distanceInMeters < secondCinema.distanceInMeters
    }
    return firstCinema.name < secondCinema.name
}

/// Position of the cinema in the list, `cinemaNotFound` when it is not there.
func positionOfCinema(_ cinemas: [Cinema], cinemaId: String) -> Int {
    for position in 0..<cinemas.count where cinemas[position].id == cinemaId {
        return position
    }
    return cinemaNotFound
}

func containsCinema(_ cinemas: [Cinema], cinemaId: String) -> Bool {
    return positionOfCinema(cinemas, cinemaId: cinemaId) != cinemaNotFound
}

/// "850 m", "2.4 km", "" for `unknownDistance`.
func formattedDistance(_ distance: CLLocationDistance) -> String {
    if distance < 0 {
        return ""
    }
    if distance < metersPerKilometer {
        return "\(Int(distance.rounded())) m"
    }
    return String(format: kilometerFormat, distance / metersPerKilometer)
}

// MARK: - Links

/// A `tel:` link with only the digits and the plus of the number, nil without a number.
func phoneURL(_ cinema: Cinema) -> URL? {
    var dialableNumber = ""
    for character in cinema.phoneNumber where character.isNumber || character == "+" {
        dialableNumber.append(character)
    }
    if dialableNumber.isEmpty {
        return nil
    }
    return URL(string: phoneURLScheme + dialableNumber)
}

func hasPhoneNumber(_ cinema: Cinema) -> Bool {
    return phoneURL(cinema) != nil
}

func websiteURL(_ cinema: Cinema) -> URL? {
    if cinema.website.isEmpty {
        return nil
    }
    return URL(string: cinema.website)
}

func hasWebsite(_ cinema: Cinema) -> Bool {
    return websiteURL(cinema) != nil
}
