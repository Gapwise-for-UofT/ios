import SwiftUI

struct CampusMapView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            switch appModel.campusIntegration {
            case .notIntegrated:
                ContentUnavailableView {
                    Label("Campus Map Unavailable", systemImage: "map")
                } description: {
                    Text("Campus maps and walking directions are not available in this version. Imported classroom locations are shown in Timetable.")
                } actions: {
                    Button("View Timetable") { appModel.selectedTab = .timetable }
                }
                .padding(.vertical, GapwiseSpacing.spacious)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Map")
    }
}
