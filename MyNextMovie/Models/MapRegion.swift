import MapKit

/// The part of Wrocław with every cinema on it.
let wroclawMapRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 51.0956, longitude: 17.0230),
    latitudinalMeters: 15500,
    longitudinalMeters: 14000
)

/// The same size of the region around a new center.
func regionMoved(
    _ region: MKCoordinateRegion,
    to center: CLLocationCoordinate2D
) -> MKCoordinateRegion {
    return MKCoordinateRegion(center: center, span: region.span)
}

/// Whether the point is inside the region.
func isInRegion(_ region: MKCoordinateRegion, _ coordinate: CLLocationCoordinate2D) -> Bool {
    let latitudeDifference = abs(coordinate.latitude - region.center.latitude)
    let longitudeDifference = abs(coordinate.longitude - region.center.longitude)
    return latitudeDifference <= region.span.latitudeDelta / 2
        && longitudeDifference <= region.span.longitudeDelta / 2
}
