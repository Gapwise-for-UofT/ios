import Foundation

struct TimetableImporter: Sendable {
    private let calendar: Calendar
    private let courseParser = CourseDescriptorParser()
    private let locationParser = UniversityLocationParser()
    private let campusDetector = CampusDetector()

    init(calendar: Calendar = .gapwiseToronto) {
        self.calendar = calendar
    }

    func interpret(
        _ document: ICalendarDocument,
        suggestedFileName: String?,
        campusContext: Campus? = nil
    ) throws -> TimetableImportDraft {
        let sourceIdentifier = CalendarImportSourceIdentifier.make(
            calendarName: document.calendarName,
            productIdentifier: document.productIdentifier,
            suggestedFileName: suggestedFileName
        )
        var meetings: [CourseMeeting] = []
        var warnings: [TimetableImportWarning] = []
        var skippedEvents: [SkippedCalendarEvent] = []
        var ignoredEventCount = 0
        var seenUIDs: Set<String> = []
        var acceptedOrRemovedUIDs: Set<String> = []
        var allowsMissingEventRemoval = document.calendarName != nil
        let eventsByUID = Dictionary(grouping: document.events.compactMap { event in
            event.uid.map { ($0, event) }
        }, by: { $0.0 })
        let conflictingUIDs = Set(eventsByUID.compactMap { uid, entries in
            entries.contains { $0.1 != entries[0].1 } ? uid : nil
        })

        for (index, event) in document.events.enumerated() {
            let fallbackIdentifier = "event-\(index + 1)"
            let eventIdentifier = event.uid ?? fallbackIdentifier

            if let uid = event.uid, conflictingUIDs.contains(uid) {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .conflictingUID))
                continue
            }
            // A standalone cancellation may omit SUMMARY and timing properties.
            if event.status == "CANCELLED", event.issues.isEmpty,
                event.unsupportedRecurrenceProperties.isEmpty, let uid = event.uid {
                acceptedOrRemovedUIDs.insert(uid)
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .cancelled))
                continue
            }

            guard let descriptor = courseParser.parse(summary: event.summary, description: event.description) else {
                if courseParser.containsCourseCode(summary: event.summary, description: event.description) {
                    skippedEvents.append(
                        skipped(event, fallbackID: fallbackIdentifier, reason: .missingMeetingSection)
                    )
                } else {
                    ignoredEventCount += 1
                }
                continue
            }

            guard event.issues.allSatisfy({ !$0.blocksImport }) else {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .malformedRequiredProperty))
                continue
            }
            guard !event.issues.contains(where: \.isDateFailure) else {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .malformedDate))
                continue
            }
            guard let uid = event.uid else {
                allowsMissingEventRemoval = false
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .missingUID))
                continue
            }
            guard let startValue = event.start else {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .missingStartTime))
                continue
            }
            guard let endValue = event.end else {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .missingEndTime))
                continue
            }
            guard case let .dateTime(startDateTime) = startValue, case let .dateTime(endDateTime) = endValue else {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .allDayEvent))
                continue
            }

            let startDate = LocalDate(date: startDateTime.instant, calendar: calendar)
            let endDate = LocalDate(date: endDateTime.instant, calendar: calendar)
            let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDateTime.instant)
            let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDateTime.instant)
            guard
                startDate == endDate,
                startComponents.second == 0, endComponents.second == 0,
                endDateTime.instant > startDateTime.instant,
                let startTime = LocalTime(hour: startComponents.hour ?? -1, minute: startComponents.minute ?? -1),
                let endTime = LocalTime(hour: endComponents.hour ?? -1, minute: endComponents.minute ?? -1),
                endTime > startTime
            else {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .invalidTimeRange))
                continue
            }

            if let unsupportedProperty = event.unsupportedRecurrenceProperties.sorted().first {
                skippedEvents.append(
                    skipped(
                        event,
                        fallbackID: fallbackIdentifier,
                        reason: .unsupportedRecurrence(unsupportedProperty)
                    )
                )
                continue
            }

            let recurrence: WeeklyRecurrence
            if let rule = event.recurrenceRule {
                guard [startDateTime, endDateTime].allSatisfy({
                    $0.isFloating || $0.timeZoneIdentifier == calendar.timeZone.identifier
                }) else {
                    skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .unsupportedTimeZoneRecurrence))
                    continue
                }
                do {
                    recurrence = try RecurrenceRuleInterpreter(calendar: calendar).interpret(
                        rule,
                        startingAt: startDateTime.instant
                    )
                } catch let reason as SkippedEventReason {
                    skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: reason))
                    continue
                }
            } else if let weekday = Weekday(date: startDateTime.instant, calendar: calendar) {
                recurrence = WeeklyRecurrence(days: [weekday], endsOn: startDate)
            } else {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .malformedDate))
                continue
            }

            guard seenUIDs.insert(uid).inserted else {
                warnings.append(
                    TimetableImportWarning(
                        kind: .duplicateUID,
                        courseCode: descriptor.courseCode,
                        eventIdentifier: eventIdentifier
                    )
                )
                continue
            }

            let location = locationParser.parse(event.location)
            let campus = campusDetector.detect(
                calendarName: document.calendarName,
                productIdentifier: document.productIdentifier,
                location: location,
                description: event.description,
                importContext: campusContext,
                courseCode: descriptor.courseCode
            ).campus
            guard campus == .utm || campus == .unknown else {
                acceptedOrRemovedUIDs.insert(uid)
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .unsupportedCampus))
                continue
            }
            let term = AcademicTerm(
                id: .init(rawValue: "ics:\(startDate.iso8601String):\(recurrence.endsOn.iso8601String)"),
                displayName: "Imported \(startDate.iso8601String) to \(recurrence.endsOn.iso8601String)",
                startsOn: startDate,
                endsOn: recurrence.endsOn
            )

            do {
                let meeting = try CourseMeeting(
                    campus: campus,
                    courseCode: descriptor.courseCode,
                    courseTitle: descriptor.courseTitle,
                    term: term,
                    meetingType: descriptor.meetingType,
                    meetingSection: descriptor.meetingSection,
                    days: recurrence.days,
                    startTime: startTime,
                    endTime: endTime,
                    location: location,
                    instructor: descriptor.instructor,
                    sourceIdentifier: uid,
                    origin: .calendarImport(sourceIdentifier: sourceIdentifier),
                    isReservedAssessmentWindow: isReservedAssessmentWindow(event)
                )
                meetings.append(meeting)
                acceptedOrRemovedUIDs.insert(uid)
            } catch {
                skippedEvents.append(skipped(event, fallbackID: fallbackIdentifier, reason: .invalidTimeRange))
                continue
            }

            warnings.append(
                contentsOf: warningsForEvent(event, descriptor: descriptor, location: location, campus: campus))
        }

        guard !meetings.isEmpty else { throw TimetableImportError.noSupportedEvents }

        return TimetableImportDraft(
            sourceIdentifier: sourceIdentifier,
            sourceName: document.calendarName ?? suggestedFileName,
            meetings: meetings,
            warnings: warnings.removingDuplicateIDs(),
            skippedEvents: skippedEvents,
            ignoredEventCount: ignoredEventCount,
            totalEventCount: document.events.count,
            retainedEventUIDs: Set(document.events.compactMap(\.uid)).subtracting(acceptedOrRemovedUIDs),
            allowsMissingEventRemoval: allowsMissingEventRemoval
        )
    }

    private func isReservedAssessmentWindow(_ event: ICalendarEvent) -> Bool {
        // Exact ACORN evidence convention from Gapwise core ics-parser.ts.
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
            location.range(of: #"^ZZ\s+TBA$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        return event.description?.split(separator: "\n", omittingEmptySubsequences: false).contains {
            $0.count >= 6 && $0.allSatisfy { $0 == "*" }
        } ?? false
    }

    private func warningsForEvent(
        _ event: ICalendarEvent,
        descriptor: ParsedCourseDescriptor,
        location: MeetingLocation?,
        campus: Campus
    ) -> [TimetableImportWarning] {
        let eventIdentifier = event.uid ?? descriptor.meetingSection
        var warnings: [TimetableImportWarning] = []

        if event.temporalValues.contains(where: { $0.isFloating }) {
            warnings.append(
                TimetableImportWarning(
                    kind: .assumedTorontoTime,
                    courseCode: descriptor.courseCode,
                    eventIdentifier: eventIdentifier
                )
            )
        }
        if descriptor.courseTitle == nil {
            warnings.append(
                TimetableImportWarning(
                    kind: .missingCourseTitle,
                    courseCode: descriptor.courseCode,
                    eventIdentifier: eventIdentifier
                )
            )
        }
        if location == nil {
            warnings.append(
                TimetableImportWarning(
                    kind: .missingLocation,
                    courseCode: descriptor.courseCode,
                    eventIdentifier: eventIdentifier
                )
            )
        }
        if descriptor.meetingType == .other {
            warnings.append(
                TimetableImportWarning(
                    kind: .unknownMeetingType(descriptor.rawMeetingType),
                    courseCode: descriptor.courseCode,
                    eventIdentifier: eventIdentifier
                )
            )
        }
        if campus == .unknown {
            warnings.append(
                TimetableImportWarning(
                    kind: .unknownCampus,
                    courseCode: descriptor.courseCode,
                    eventIdentifier: eventIdentifier
                )
            )
        }
        if location?.kind == .unknown {
            warnings.append(
                TimetableImportWarning(
                    kind: .unrecognizedLocation,
                    courseCode: descriptor.courseCode,
                    eventIdentifier: eventIdentifier
                )
            )
        }
        for issue in event.issues {
            if let property = issue.optionalPropertyName {
                warnings.append(
                    TimetableImportWarning(
                        kind: .malformedOptionalProperty(property),
                        courseCode: descriptor.courseCode,
                        eventIdentifier: eventIdentifier
                    )
                )
            }
        }
        return warnings
    }

    private func skipped(
        _ event: ICalendarEvent,
        fallbackID: String,
        reason: SkippedEventReason
    ) -> SkippedCalendarEvent {
        SkippedCalendarEvent(
            id: "\(fallbackID)|\(event.uid ?? "missing-uid")",
            title: event.summary ?? "Untitled event",
            reason: reason
        )
    }
}

private extension [TimetableImportWarning] {
    func removingDuplicateIDs() -> Self {
        var seen: Set<TimetableImportWarning.ID> = []
        return filter { seen.insert($0.id).inserted }
    }
}

private enum CalendarImportSourceIdentifier {
    static func make(calendarName: String?, productIdentifier: String?, suggestedFileName: String?) -> String {
        let source = [productIdentifier, calendarName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        // File-provider renames (e.g. "timetable (2).ics") must not create a new source.
        // Metadata-less files share one neutral local import slot; filenames are presentation only.
        return "ics-\(fnv1a64(source.isEmpty ? "calendar" : source))"
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private extension LocalDate {
    var iso8601String: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private extension ICalendarEventIssue {
    var blocksImport: Bool {
        let requiredProperties = ["UID", "SUMMARY", "DTSTART", "DTEND", "RRULE", "STATUS", "EXDATE", "RDATE", "RECURRENCE-ID"]
        switch self {
        case let .duplicateProperty(property): return requiredProperties.contains(property)
        case let .malformedProperty(property): return property.map(requiredProperties.contains) ?? false
        case .invalidDate, .unknownTimeZone: return false
        }
    }

    var isDateFailure: Bool {
        switch self {
        case .invalidDate, .unknownTimeZone: true
        case .duplicateProperty, .malformedProperty: false
        }
    }

    var optionalPropertyName: String? {
        switch self {
        case let .duplicateProperty(property): property
        case let .malformedProperty(property): property ?? "property"
        case .invalidDate, .unknownTimeZone: nil
        }
    }
}

private extension ICalendarTemporalValue {
    var isFloating: Bool {
        guard case let .dateTime(value) = self else { return false }
        return value.isFloating
    }
}

private extension ICalendarEvent {
    var temporalValues: [ICalendarTemporalValue] {
        [start, end].compactMap { $0 }
    }
}
