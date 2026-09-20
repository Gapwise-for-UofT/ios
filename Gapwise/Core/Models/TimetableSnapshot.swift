import Foundation

struct TimetableSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2
    static let empty = TimetableSnapshot()

    var meetings: [CourseMeeting]
    var sources: [TimetableSource]
    var suppressedImportedMeetings: Set<ImportedMeetingIdentity>
    var lastModified: Date?
    let schemaVersion: Int

    init(
        meetings: [CourseMeeting] = [],
        sources: [TimetableSource] = [],
        suppressedImportedMeetings: Set<ImportedMeetingIdentity> = [],
        lastModified: Date? = nil
    ) {
        self.meetings = meetings
        self.sources = sources
        self.suppressedImportedMeetings = suppressedImportedMeetings
        self.lastModified = lastModified
        schemaVersion = Self.currentSchemaVersion
    }

    var courseCount: Int {
        Set(meetings.map(CourseIdentity.init)).count
    }

    var campuses: Set<Campus> {
        Set(meetings.map(\.campus))
    }

    private enum CodingKeys: String, CodingKey {
        case meetings
        case sources
        case suppressedImportedMeetings
        case lastModified
        case schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentSchemaVersion).contains(storedVersion) else {
            throw TimetableSnapshotError.unsupportedSchemaVersion(storedVersion)
        }
        let meetings = try container.decode([CourseMeeting].self, forKey: .meetings)
        let lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified)
        let storedSources = try container.decodeIfPresent([TimetableSource].self, forKey: .sources)

        self.meetings = meetings
        sources = storedSources ?? Self.migratedSources(from: meetings, lastModified: lastModified)
        suppressedImportedMeetings =
            try container.decodeIfPresent(Set<ImportedMeetingIdentity>.self, forKey: .suppressedImportedMeetings) ?? []
        self.lastModified = lastModified
        schemaVersion = Self.currentSchemaVersion
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(meetings, forKey: .meetings)
        try container.encode(sources, forKey: .sources)
        try container.encode(suppressedImportedMeetings.sorted {
            if $0.sourceIdentifier != $1.sourceIdentifier { return $0.sourceIdentifier < $1.sourceIdentifier }
            return $0.eventUID < $1.eventUID
        }, forKey: .suppressedImportedMeetings)
        try container.encodeIfPresent(lastModified, forKey: .lastModified)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }

    func validate() throws {
        guard Set(meetings.map(\.id)).count == meetings.count else {
            throw TimetableSnapshotError.duplicateMeeting
        }
        let importedIdentities = meetings.compactMap(ImportedMeetingIdentity.init)
        guard Set(importedIdentities).count == importedIdentities.count else {
            throw TimetableSnapshotError.duplicateMeeting
        }
        guard Set(sources.map(\.id)).count == sources.count else {
            throw TimetableSnapshotError.duplicateSource
        }
        guard sources.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
            suppressedImportedMeetings.allSatisfy({
                !$0.sourceIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.eventUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { throw TimetableSnapshotError.invalidSourceIdentity }
        guard Set(importedIdentities).isDisjoint(with: suppressedImportedMeetings) else {
            throw TimetableSnapshotError.suppressedMeetingPresent
        }
    }

    private static func migratedSources(from meetings: [CourseMeeting], lastModified: Date?) -> [TimetableSource] {
        let identifiers = Set(meetings.compactMap { meeting -> String? in
            guard meeting.origin.kind == .calendarImport else { return nil }
            return meeting.origin.sourceIdentifier
        })
        return identifiers.sorted().map {
            TimetableSource(
                id: $0,
                kind: .calendarFile,
                displayName: nil,
                lastImportedAt: lastModified ?? .distantPast
            )
        }
    }
}

enum TimetableSnapshotError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case duplicateMeeting
    case duplicateSource
    case invalidSourceIdentity
    case suppressedMeetingPresent

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            "This timetable was saved in an unsupported format. Its file has been preserved."
        case .duplicateMeeting, .duplicateSource, .invalidSourceIdentity, .suppressedMeetingPresent:
            "The saved timetable contains inconsistent records. Its file has been preserved."
        }
    }
}

enum AppearancePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct UserPreferences: Codable, Equatable, Sendable {
    var appearance: AppearancePreference
    var campusContext: Campus

    static let defaults = UserPreferences(appearance: .system, campusContext: .unknown)
}
