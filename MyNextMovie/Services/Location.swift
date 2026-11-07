import CoreLocation

/// How long the app waits for a fresh location before it gives up.
private let locationTimeout = Duration.seconds(10)

/// A fresh location of the user. `fallbackUserLocation` after a refusal or after 10 seconds.
/// Two tasks race: the location updates and a timer. The first one to finish wins.
func findUserLocation() async -> UserLocation {
    return await withTaskGroup(of: UserLocation.self) { group in
        group.addTask { await firstLocationUpdate() }
        group.addTask {
            try? await Task.sleep(for: locationTimeout)
            return fallbackUserLocation
        }
        let firstResult = await group.next() ?? fallbackUserLocation
        group.cancelAll()
        return firstResult
    }
}

/// The location Core Location remembers, at once and without asking.
func lastKnownUserLocation() -> UserLocation {
    guard let location = CLLocationManager().location else {
        return fallbackUserLocation
    }
    return userLocation(from: location)
}

/// Asks for the permission when needed and waits for the first location.
private func firstLocationUpdate() async -> UserLocation {
    let session = CLServiceSession(authorization: .whenInUse)
    defer { session.invalidate() }
    do {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return userLocation(from: location)
            }
            if update.authorizationDenied || update.authorizationDeniedGlobally {
                return fallbackUserLocation
            }
        }
    } catch {
        return fallbackUserLocation
    }
    return fallbackUserLocation
}

private nonisolated func userLocation(from location: CLLocation) -> UserLocation {
    return UserLocation(
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude,
        isKnown: true
    )
}
