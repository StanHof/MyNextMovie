import Foundation
import MapKit
import Testing

@testable import MyNextMovie

@MainActor
struct CinemaTests {
    @Test func sortsCinemasClosestFirst() {
        let sortedCinemas = cinemasSortedByDistance(testCinemas, from: testUserLocation)

        let expectedNames = [
            "DCF", "Kino Nowe Horyzonty", "Multikino Pasaż Grunwaldzki", "Helios Magnolia",
        ]
        #expect(namesOf(sortedCinemas) == expectedNames)
    }

    @Test func measuresDistanceOfEveryCinema() {
        let sortedCinemas = cinemasSortedByDistance(testCinemas, from: testUserLocation)

        #expect(sortedCinemas.count == testCinemas.count)
        for cinema in sortedCinemas {
            #expect(cinema.distanceInMeters > 0)
        }
        let dcfDistance = distanceInMeters(from: testUserLocation, to: testCinemaDCF)
        #expect(dcfDistance > 700 && dcfDistance < 900)
    }

    @Test func sortsCinemasAtTheSameDistanceByName() {
        var zeta = testCinemaDCF
        zeta.distanceInMeters = 500
        var alpha = testCinemaHelios
        alpha.distanceInMeters = 500

        #expect(isCloser(alpha, zeta) == (alpha.name < zeta.name))
        #expect(!isCloser(zeta, alpha) == (alpha.name < zeta.name))

        let sortedCinemas = [zeta, alpha].sorted(by: isCloser)
        #expect(namesOf(sortedCinemas) == ["DCF", "Helios Magnolia"])
    }

    @Test func findsPositionOfCinema() {
        #expect(positionOfCinema(testCinemas, cinemaId: "dcf") == 2)
        #expect(positionOfCinema(testCinemas, cinemaId: "no-such-cinema") == cinemaNotFound)
        #expect(containsCinema(testCinemas, cinemaId: "helios-magnolia"))
        #expect(!containsCinema(testCinemas, cinemaId: "no-such-cinema"))
    }

    @Test func unknownDistanceIsEmptyText() {
        #expect(formattedDistance(unknownDistance) == "")
        #expect(formattedDistance(850) == "850 m")
        #expect(formattedDistance(2400) == "2.4 km")
    }

    @Test func phoneLinkHasOnlyDigits() {
        #expect(phoneURL(testCinemaNoweHoryzonty) == URL(string: "tel:+48717864566"))
        #expect(hasPhoneNumber(testCinemaNoweHoryzonty))
    }

    @Test func noPhoneOrWebsiteMeansNoLink() {
        #expect(phoneURL(testCinemaHelios) == nil)
        #expect(!hasPhoneNumber(testCinemaHelios))
        #expect(websiteURL(testCinemaHelios) == nil)
        #expect(!hasWebsite(testCinemaHelios))

        #expect(websiteURL(testCinemaNoweHoryzonty) == URL(string: "https://kinonh.pl"))
        #expect(hasWebsite(testCinemaNoweHoryzonty))
    }
}

@MainActor
struct WroclawCinemasTests {
    @Test func everyCinemaIsOnTheStartMap() {
        for cinema in wroclawCinemas {
            #expect(isInRegion(wroclawMapRegion, cinemaCoordinate(cinema)), "\(cinema.name)")
        }
    }

    @Test func idsAreUnique() {
        var ids: Set<String> = []
        for cinema in wroclawCinemas {
            ids.insert(cinema.id)
        }
        #expect(ids.count == wroclawCinemas.count)
    }

    @Test func everyCinemaHasAddressAndWebsite() {
        for cinema in wroclawCinemas {
            #expect(!cinema.address.isEmpty, "\(cinema.name)")
            #expect(hasWebsite(cinema), "\(cinema.name)")
        }
    }

    @Test func pointOutsideRegionIsNotOnTheMap() {
        let warsaw = CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122)
        #expect(!isInRegion(wroclawMapRegion, warsaw))
        #expect(isInRegion(wroclawMapRegion, fallbackCoordinate))
    }
}

@MainActor
struct MapKitConversionTests {
    @Test func mapItemForCinemaKeepsNameAndPosition() {
        let mapItem = mapItemForCinema(testCinemaDCF)

        #expect(mapItem.name == testCinemaDCF.name)
        #expect(mapItem.location.coordinate.latitude == testCinemaDCF.latitude)
        #expect(mapItem.location.coordinate.longitude == testCinemaDCF.longitude)
    }

    @Test func travelModeBecomesMapKitTransportType() {
        #expect(transportTypeForMapKit(.walking) == .walking)
        #expect(transportTypeForMapKit(.driving) == .automobile)
    }
}
