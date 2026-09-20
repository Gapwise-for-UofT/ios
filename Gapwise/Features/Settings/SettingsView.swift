import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isConfirmingTimetableRemoval = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { appModel.preferences.appearance },
                        set: { appModel.setAppearance($0) }
                    )
                ) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
            }

            Section("Timetable") {
                if appModel.loadState == .failed {
                    Text("Saved data could not be opened. Retry loading, or remove the saved timetable to start again.")
                    Button("Retry Loading") { Task { await appModel.load() } }
                }

                Button {
                    appModel.requestTimetableImport()
                } label: {
                    if appModel.isPreparingImport {
                        HStack {
                            ProgressView()
                            Text("Reading Calendar")
                        }
                    } else {
                        Label("Import Calendar File", systemImage: "square.and.arrow.down")
                    }
                }
                .disabled(!appModel.canImport)

                LabeledContent("Saved meetings", value: "\(appModel.timetable.meetings.count)")

                if let lastModified = appModel.timetable.lastModified {
                    LabeledContent(
                        "Last updated",
                        value: lastModified.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                Button("Remove Saved Timetable", role: .destructive) {
                    isConfirmingTimetableRemoval = true
                }
                .disabled(!appModel.canRemoveTimetable)
            }

            Section("Campus") {
                LabeledContent("Current timetable coverage", value: "UTM")
                Text("Class times are shown in Toronto time.")
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Label("Timetable data stays in this app's local container.", systemImage: "lock.shield")
                Text("Gapwise does not require an account for the basic timetable experience.")
                    .foregroundStyle(.secondary)
            }

            Section("Gapwise") {
                if let website = AppLinks.website {
                    Link(destination: website) {
                        Label("Website", systemImage: "safari")
                    }
                }
                if let documentation = AppLinks.documentation {
                    Link(destination: documentation) {
                        Label("Documentation", systemImage: "book.closed")
                    }
                }
                if let status = AppLinks.status {
                    Link(destination: status) {
                        Label("Service Status", systemImage: "waveform.path.ecg")
                    }
                }
            }

            Section("About") {
                Image("GapwiseBrand")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 96)
                    .accessibilityLabel("Gapwise for iOS")
                LabeledContent("Version", value: AppInformation.versionDescription)
                Text(
                    "Gapwise is an independent student software project and is not affiliated with or endorsed by the University of Toronto."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Remove your saved timetable?",
            isPresented: $isConfirmingTimetableRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove Timetable", role: .destructive) {
                Task {
                    await appModel.clearTimetable()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the local timetable, import history, and saved removal choices. The original calendar file is unchanged.")
        }
    }
}

private enum AppLinks {
    static let website = URL(string: "https://gapwise.ca")
    static let documentation = URL(string: "https://docs.gapwise.ca")
    static let status = URL(string: "https://status.gapwise.ca")
}

private enum AppInformation {
    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return build
        case (.none, .none):
            return "Development"
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            SettingsView()
                .environment(PreviewData.appModel())
        }
    }
#endif
