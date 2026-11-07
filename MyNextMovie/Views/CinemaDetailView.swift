import MapKit
import SwiftUI

private let detailMapHeight: CGFloat = 220
private let lookAroundHeight: CGFloat = 180
private let detailMapSpanInMeters: CLLocationDistance = 1500
private let routeLineWidth: CGFloat = 5
/// Room around the route, as a share of its size.
private let routePaddingShare = 0.25

/// One cinema: the map with the route, the address, the way there, links and Look Around.
struct CinemaDetailView: View {
    @State private var viewModel: CinemaDetailViewModel
    @State private var cameraPosition: MapCameraPosition
    @State private var lookAroundScene: MKLookAroundScene?

    init(viewModel: CinemaDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
        let cinemaRegion = MKCoordinateRegion(
            center: cinemaCoordinate(viewModel.cinema),
            latitudinalMeters: detailMapSpanInMeters,
            longitudinalMeters: detailMapSpanInMeters
        )
        _cameraPosition = State(initialValue: .region(cinemaRegion))
    }

    var body: some View {
        List {
            mapSection
            addressSection
            routeSection
            linksSection
            lookAroundSection
        }
        .navigationTitle(viewModel.cinema.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.travelMode) { await viewModel.loadRoute() }
        .task { lookAroundScene = await findLookAroundScene(viewModel.cinema) }
        .onChange(of: viewModel.routeState) { _, routeState in showRoute(routeState) }
    }

    private var mapSection: some View {
        Section {
            map
                .frame(height: detailMapHeight)
                .listRowInsets(EdgeInsets())
        }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            cinemaMarker
            if viewModel.routeState == .loaded {
                MapPolyline(viewModel.route.line).stroke(.blue, lineWidth: routeLineWidth)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    private var cinemaMarker: some MapContent {
        Marker(
            viewModel.cinema.name,
            systemImage: symbolNameCinema,
            coordinate: cinemaCoordinate(viewModel.cinema)
        )
    }

    private var addressSection: some View {
        Section {
            Text(viewModel.cinema.address)
            distance
        }
    }

    @ViewBuilder
    private var distance: some View {
        let distanceText = formattedDistance(viewModel.cinema.distanceInMeters)
        if !distanceText.isEmpty {
            Text(distanceText + " from you").foregroundStyle(.secondary)
        }
    }

    private var routeSection: some View {
        Section("Way There") {
            travelModePicker
            routeSummary
        }
    }

    private var travelModePicker: some View {
        Picker("Travel mode", selection: $viewModel.travelMode) {
            Label("Walk", systemImage: symbolNameWalking).tag(TravelMode.walking)
            Label("Drive", systemImage: symbolNameDriving).tag(TravelMode.driving)
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var routeSummary: some View {
        if !viewModel.canFindRoute {
            Text("Turn on location to see the route.").foregroundStyle(.secondary)
        } else {
            routeState
        }
    }

    @ViewBuilder
    private var routeState: some View {
        switch viewModel.routeState {
        case .idle, .loading:
            ProgressView()
        case .loaded:
            Text(viewModel.routeSummary(viewModel.route))
        case .failed:
            Text(viewModel.errorMessage).foregroundStyle(.red)
        }
    }

    private var linksSection: some View {
        Section {
            Button {
                openCinemaInMaps(viewModel.cinema, travelMode: viewModel.travelMode)
            } label: {
                Label("Directions in Maps", systemImage: symbolNameDirections)
            }
            phoneLink
            websiteLink
        }
    }

    @ViewBuilder
    private var phoneLink: some View {
        if let phoneAddress = phoneURL(viewModel.cinema) {
            Link(destination: phoneAddress) {
                Label(viewModel.cinema.phoneNumber, systemImage: symbolNamePhone)
            }
        }
    }

    @ViewBuilder
    private var websiteLink: some View {
        if let websiteAddress = websiteURL(viewModel.cinema) {
            Link(destination: websiteAddress) {
                Label("Website", systemImage: symbolNameWebsite)
            }
        }
    }

    @ViewBuilder
    private var lookAroundSection: some View {
        if let lookAroundScene {
            Section("Look Around") { lookAroundPreview(lookAroundScene) }
        }
    }

    private func lookAroundPreview(_ scene: MKLookAroundScene) -> some View {
        LookAroundPreview(initialScene: scene)
            .frame(height: lookAroundHeight)
            .listRowInsets(EdgeInsets())
    }

    /// Zooms the map out to the whole route once it is found.
    private func showRoute(_ routeState: LoadState) {
        if routeState != .loaded {
            return
        }
        let routeRect = viewModel.route.line.boundingMapRect
        let paddedRect = routeRect.insetBy(
            dx: -routeRect.size.width * routePaddingShare,
            dy: -routeRect.size.height * routePaddingShare
        )
        withAnimation {
            cameraPosition = .rect(paddedRect)
        }
    }
}

#Preview {
    NavigationStack {
        CinemaDetailView(
            viewModel: CinemaDetailViewModel(
                cinema: wroclawCinemas[0],
                userLocation: fallbackUserLocation,
                findRoute: findMapKitRoute
            )
        )
    }
}
