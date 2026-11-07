import MapKit
import SwiftUI

/// Where the map is shown: on its own tab, or in a sheet over a movie, which has a Done button.
enum CinemaMapPlacement {
    case tab
    case sheet
}

/// The map takes this share of the screen height, the list the rest.
private let mapHeightShare: CGFloat = 0.45
private let selectedRowBackgroundOpacity = 0.15
private let locationUnavailableHint = "Turn on location to see distances and routes."

/// The Cinemas tab: the cinemas of Wrocław on a map and in a list, closest first.
/// Tapping a pin selects its row, tapping a row moves the map to the cinema.
struct CinemaMapView: View {
    @State private var viewModel: CinemaMapViewModel
    private let findRoute: CinemaRouteFinder
    private let placement: CinemaMapPlacement

    @State private var cameraPosition = MapCameraPosition.region(wroclawMapRegion)
    @State private var selectedMarkerId: String?
    @State private var path: [Cinema] = []
    @Environment(\.dismiss) private var dismiss

    init(
        viewModel: CinemaMapViewModel,
        findRoute: @escaping CinemaRouteFinder,
        placement: CinemaMapPlacement
    ) {
        _viewModel = State(initialValue: viewModel)
        self.findRoute = findRoute
        self.placement = placement
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Cinemas")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Cinema.self) { cinema in detailView(cinema) }
                .toolbar { doneButton }
        }
        .task { await viewModel.locateUserIfNeeded() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            map
            locationHint
            cinemaList
        }
        .onChange(of: selectedMarkerId) { _, markerId in selectFromMap(markerId) }
        .onChange(of: viewModel.selectedCinemaId) { _, cinemaId in selectOnMap(cinemaId) }
    }

    private var map: some View {
        Map(position: $cameraPosition, selection: $selectedMarkerId) {
            UserAnnotation()
            ForEach(viewModel.cinemas) { cinema in cinemaMarker(cinema) }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange { context in viewModel.visibleRegion = context.region }
        .containerRelativeFrame(.vertical) { height, _ in height * mapHeightShare }
    }

    private func cinemaMarker(_ cinema: Cinema) -> some MapContent {
        Marker(cinema.name, systemImage: symbolNameCinema, coordinate: cinemaCoordinate(cinema))
            .tag(cinema.id)
    }

    @ViewBuilder
    private var locationHint: some View {
        if viewModel.isLocationUnavailable {
            Label(locationUnavailableHint, systemImage: symbolNameLocationOff)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(spacingSmall)
                .background(.quaternary)
        }
    }

    private var cinemaList: some View {
        CinemaList(
            cinemas: viewModel.cinemas,
            selectedCinemaId: viewModel.selectedCinemaId,
            selectCinema: selectFromList,
            showDetails: showDetails
        )
    }

    @ToolbarContentBuilder
    private var doneButton: some ToolbarContent {
        if placement == .sheet {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func detailView(_ cinema: Cinema) -> some View {
        let detailViewModel = CinemaDetailViewModel(
            cinema: cinema,
            userLocation: viewModel.userLocation,
            findRoute: findRoute
        )
        return CinemaDetailView(viewModel: detailViewModel)
    }

    /// A tapped pin selects the row.
    private func selectFromMap(_ markerId: String?) {
        let cinemaId = markerId ?? noCinemaSelected
        if viewModel.selectedCinemaId != cinemaId {
            viewModel.toggleCinema(cinemaId)
        }
    }

    /// A tapped row selects the pin and moves the map to the cinema.
    private func selectFromList(_ cinemaId: String) {
        viewModel.toggleCinema(cinemaId)
        moveMap(to: viewModel.selectedCinemaId)
    }

    private func selectOnMap(_ cinemaId: String) {
        let markerId: String? = cinemaId == noCinemaSelected ? nil : cinemaId
        if selectedMarkerId != markerId {
            selectedMarkerId = markerId
        }
    }

    private func moveMap(to cinemaId: String) {
        let position = positionOfCinema(viewModel.cinemas, cinemaId: cinemaId)
        if position == cinemaNotFound {
            return
        }
        let cinema = viewModel.cinemas[position]
        viewModel.visibleRegion = regionMoved(viewModel.visibleRegion, to: cinemaCoordinate(cinema))
        withAnimation {
            cameraPosition = .region(viewModel.visibleRegion)
        }
    }

    private func showDetails(_ cinema: Cinema) {
        path.append(cinema)
    }
}

/// Name, address and distance of every cinema. The selected row is highlighted
/// and the list scrolls to it when a pin selects it.
private struct CinemaList: View {
    let cinemas: [Cinema]
    let selectedCinemaId: String
    let selectCinema: (String) -> Void
    let showDetails: (Cinema) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            List(cinemas) { cinema in row(cinema) }
                .listStyle(.plain)
                .onChange(of: selectedCinemaId) { _, cinemaId in scroll(scrollProxy, to: cinemaId) }
        }
    }

    private func row(_ cinema: Cinema) -> some View {
        CinemaRow(
            cinema: cinema,
            isSelected: cinema.id == selectedCinemaId,
            select: { selectCinema(cinema.id) },
            showDetails: { showDetails(cinema) }
        )
        .id(cinema.id)
    }

    private func scroll(_ scrollProxy: ScrollViewProxy, to cinemaId: String) {
        if cinemaId == noCinemaSelected {
            return
        }
        withAnimation {
            scrollProxy.scrollTo(cinemaId, anchor: .center)
        }
    }
}

private struct CinemaRow: View {
    let cinema: Cinema
    let isSelected: Bool
    let select: () -> Void
    let showDetails: () -> Void

    var body: some View {
        HStack(spacing: spacingMedium) {
            description
            Spacer()
            detailsButton
        }
        .contentShape(Rectangle())
        .onTapGesture { select() }
        .listRowBackground(rowBackground)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: spacingTiny) {
            Text(cinema.name).font(.headline)
            Text(cinema.address)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(formattedDistance(cinema.distanceInMeters))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var detailsButton: some View {
        Button {
            showDetails()
        } label: {
            Image(systemName: symbolNameDetails).font(.title3)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Cinema details")
    }

    private var rowBackground: Color? {
        return isSelected ? Color.accentColor.opacity(selectedRowBackgroundOpacity) : nil
    }
}

#Preview {
    CinemaMapView(
        viewModel: CinemaMapViewModel(cinemas: wroclawCinemas, findUserLocation: findUserLocation),
        findRoute: findMapKitRoute,
        placement: .tab
    )
}
