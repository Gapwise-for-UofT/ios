import Foundation

enum TimetableImportError: Error, Equatable, LocalizedError {
    case documentTooLarge(maximumBytes: Int)
    case invalidTextEncoding
    case missingCalendar
    case malformedCalendar
    case tooManyEvents(maximum: Int)
    case noSupportedEvents

    var errorDescription: String? {
        switch self {
        case let .documentTooLarge(maximumBytes):
            "The selected file is larger than the \(maximumBytes / 1_048_576) MB import limit."
        case .invalidTextEncoding:
            "The selected file is not a valid UTF-8 calendar."
        case .missingCalendar:
            "The selected file does not contain a supported iCalendar."
        case .malformedCalendar:
            "The selected calendar has an invalid structure and could not be read safely."
        case let .tooManyEvents(maximum):
            "The selected calendar contains more than the supported limit of \(maximum) events."
        case .noSupportedEvents:
            "The selected file does not contain any supported timetable events."
        }
    }
}

enum TimetableImportWarningKind: Hashable, Sendable {
    case assumedTorontoTime
    case duplicateUID
    case malformedOptionalProperty(String)
    case missingCourseTitle
    case missingLocation
    case unknownCampus
    case unknownMeetingType(String)
    case unrecognizedLocation
}

struct TimetableImportWarning: Hashable, Identifiable, Sendable {
    let id: String
    let kind: TimetableImportWarningKind
    let courseCode: CourseCode?

    init(kind: TimetableImportWarningKind, courseCode: CourseCode? = nil, eventIdentifier: String) {
        self.kind = kind
        self.courseCode = courseCode
        id = "\(eventIdentifier)|\(String(describing: kind))"
    }

    var message: String {
        let course = courseCode?.rawValue

        switch kind {
        case .assumedTorontoTime:
            return course.map { "Floating event time for \($0) was interpreted in Toronto time." }
                ?? "A floating event time was interpreted in Toronto time."
        case .duplicateUID:
            return "A duplicate calendar event was ignored."
        case let .malformedOptionalProperty(property):
            return course.map { "\($0) contains a malformed optional \(property) value." }
                ?? "An event contains a malformed optional \(property) value."
        case .missingCourseTitle:
            return course.map { "No course title was found for \($0)." } ?? "A course title was not available."
        case .missingLocation:
            return course.map { "No location was found for \($0)." } ?? "A class location was not available."
        case .unknownCampus:
            return course.map { "Campus could not be determined for \($0)." }
                ?? "A class has an unresolved campus."
        case let .unknownMeetingType(value):
            return course.map { "Meeting type \(value) for \($0) was kept as Other." }
                ?? "Meeting type \(value) was kept as Other."
        case .unrecognizedLocation:
            return course.map { "The location for \($0) was preserved but not recognized." }
                ?? "A location was preserved but not recognized."
        }
    }
}

enum SkippedEventReason: Error, Hashable, Sendable {
    case allDayEvent
    case conflictingUID
    case unsupportedCampus
    case unsupportedTimeZoneRecurrence
    case cancelled
    case invalidTimeRange
    case malformedDate
    case malformedRequiredProperty
    case missingEndTime
    case missingMeetingSection
    case missingStartTime
    case missingUID
    case unsupportedRecurrence(String)

    var message: String {
        switch self {
        case .allDayEvent: "All-day events are not timetable meetings."
        case .conflictingUID: "Conflicting events share a UID; the whole series needs review."
        case .unsupportedCampus: "This iOS version can currently import UTM timetable events only."
        case .unsupportedTimeZoneRecurrence:
            "Repeating events must use Toronto or floating local time to preserve their time across daylight saving changes."
        case .cancelled: "A cancelled event was ignored."
        case .invalidTimeRange: "An event ends before it starts or crosses a day boundary."
        case .malformedDate: "An event contains a date that could not be read."
        case .malformedRequiredProperty: "A required calendar property is malformed or appears more than once."
        case .missingEndTime: "An event has no end time."
        case .missingMeetingSection: "A course event has no recognizable meeting section."
        case .missingStartTime: "An event has no start time."
        case .missingUID: "A course event has no stable UID."
        case .unsupportedRecurrence: "A course event uses a recurrence pattern Gapwise does not support yet."
        }
    }
}

struct SkippedCalendarEvent: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let reason: SkippedEventReason
}

struct TimetableImportDraft: Sendable {
    let sourceIdentifier: String
    let sourceName: String?
    let meetings: [CourseMeeting]
    let warnings: [TimetableImportWarning]
    let skippedEvents: [SkippedCalendarEvent]
    let ignoredEventCount: Int
    let totalEventCount: Int
    // Rejected UIDs are evidence of unreadable updates, not evidence of deletion.
    var retainedEventUIDs: Set<String> = []
    var allowsMissingEventRemoval = true

    var courseCount: Int {
        Set(meetings.map { ImportedCourseIdentity(campus: $0.campus, courseCode: $0.courseCode) }).count
    }

    var campuses: Set<Campus> {
        Set(meetings.map(\.campus))
    }

    var unresolvedCampusCount: Int {
        meetings.lazy.filter { $0.campus == .unknown }.count
    }
}

private struct ImportedCourseIdentity: Hashable {
    let campus: Campus
    let courseCode: CourseCode
}

struct TimetableImportChanges: Equatable, Sendable {
    let added: Int
    let updated: Int
    let unchanged: Int
    let removedFromSource: Int
    let suppressed: Int
    let unresolved: Int
    var retainedForReview: Int = 0
}

struct TimetableImportPlan: Identifiable, Sendable {
    var id: String { draft.sourceIdentifier }

    let draft: TimetableImportDraft
    let changes: TimetableImportChanges
    let previewMeetings: [CourseMeeting]
    let resultingSnapshot: TimetableSnapshot
}
