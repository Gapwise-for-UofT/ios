import Foundation
import XCTest

#if canImport(Gapwise)
    @testable import Gapwise
#else
    @testable import GapwiseCore
#endif

final class TimetableModelValidationTests: XCTestCase {
    func testInvalidCalendarDatesAreRejectedWithoutNormalization() throws {
        for (year, month, day) in [(2026, 2, 29), (2026, 4, 31), (2026, 0, 10), (0, 1, 1)] {
            XCTAssertThrowsError(try DomainTestSupport.decode(
                LocalDate.self, object: ["year": year, "month": month, "day": day]
            ))
        }
        let leapDay = try DomainTestSupport.decode(LocalDate.self, object: ["year": 2028, "month": 2, "day": 29])
        XCTAssertEqual(leapDay, LocalDate(year: 2028, month: 2, day: 29))
    }

    func testReversedTermAndMismatchedIdentityAreRejected() throws {
        let original = try DomainTestSupport.meeting()
        var object = try DomainTestSupport.object(original)
        var term = try XCTUnwrap(object["term"] as? [String: Any])
        term["endsOn"] = ["year": 2026, "month": 1, "day": 1]
        object["term"] = term
        XCTAssertThrowsError(try DomainTestSupport.decode(CourseMeeting.self, object: object))

        object = try DomainTestSupport.object(original)
        var identity = try XCTUnwrap(object["id"] as? [String: Any])
        identity["courseCode"] = "MAT102H5"
        object["id"] = identity
        XCTAssertThrowsError(try DomainTestSupport.decode(CourseMeeting.self, object: object)) { error in
            XCTAssertEqual(error as? CourseMeetingValidationError, .inconsistentIdentity)
        }
    }

    func testSourceIdentityMismatchIsRejected() throws {
        var object = try DomainTestSupport.object(DomainTestSupport.meeting())
        var origin = try XCTUnwrap(object["origin"] as? [String: Any])
        origin["sourceIdentifier"] = "different-calendar"
        object["origin"] = origin
        XCTAssertThrowsError(try DomainTestSupport.decode(CourseMeeting.self, object: object)) { error in
            XCTAssertEqual(error as? CourseMeetingValidationError, .invalidImportSource)
        }
    }

    func testLegacySnapshotMigratesWithoutLosingImportedIdentity() throws {
        let meeting = try DomainTestSupport.meeting()
        var object = try DomainTestSupport.object(meeting)
        object.removeValue(forKey: "sourceValues")
        object.removeValue(forKey: "isReservedAssessmentWindow")
        var identity = try XCTUnwrap(object["id"] as? [String: Any])
        identity.removeValue(forKey: "importSourceIdentifier")
        object["id"] = identity
        let migrated = try DomainTestSupport.decode(TimetableSnapshot.self, object: ["meetings": [object]])

        XCTAssertEqual(migrated.schemaVersion, TimetableSnapshot.currentSchemaVersion)
        XCTAssertEqual(migrated.meetings, [meeting])
        XCTAssertEqual(migrated.sources.map(\.id), ["acorn-utm"])
        XCTAssertTrue(migrated.suppressedImportedMeetings.isEmpty)
    }

    func testUnsupportedSnapshotSchemasAndMissingRecordsAreRejected() throws {
        for version in [0, -1, TimetableSnapshot.currentSchemaVersion + 1] {
            XCTAssertThrowsError(try DomainTestSupport.decode(
                TimetableSnapshot.self, object: ["schemaVersion": version, "meetings": []]
            )) { error in
                XCTAssertEqual(error as? TimetableSnapshotError, .unsupportedSchemaVersion(version))
            }
        }
        XCTAssertThrowsError(try DomainTestSupport.decode(TimetableSnapshot.self, object: [:]))
    }

    func testDuplicateUIDsAreRejectedEvenWhenCourseLabelsDiffer() throws {
        let first = try DomainTestSupport.meeting()
        let second = try DomainTestSupport.meeting(code: "MAT102H5")
        let snapshot = TimetableSnapshot(meetings: [first, second])
        XCTAssertThrowsError(try JSONEncoder().encode(snapshot)) { error in
            XCTAssertEqual(error as? TimetableSnapshotError, .duplicateMeeting)
        }
    }

    func testActiveSuppressedMeetingIsRejected() throws {
        let meeting = try DomainTestSupport.meeting()
        let snapshot = TimetableSnapshot(
            meetings: [meeting], suppressedImportedMeetings: [try XCTUnwrap(ImportedMeetingIdentity(meeting))]
        )
        XCTAssertThrowsError(try JSONEncoder().encode(snapshot)) { error in
            XCTAssertEqual(error as? TimetableSnapshotError, .suppressedMeetingPresent)
        }
    }

    func testAssessmentSourceFactPersistsAndUpdates() throws {
        let original = try DomainTestSupport.meeting()
        let incoming = try DomainTestSupport.meeting(assessment: true)
        let updated = try original.mergingImportedSource(incoming)
        XCTAssertTrue(updated.isReservedAssessmentWindow)
        XCTAssertFalse(original.hasSameImportedSource(as: incoming))
        XCTAssertEqual(try JSONDecoder().decode(CourseMeeting.self, from: JSONEncoder().encode(updated)), updated)
    }

    func testComparableIdentityIncludesCalendarSource() throws {
        let first = try DomainTestSupport.meeting(source: "calendar-a")
        let second = try DomainTestSupport.meeting(source: "calendar-b")
        XCTAssertEqual([second.id, first.id].sorted(), [first.id, second.id])
        XCTAssertFalse(first.id < first.id)
    }

    func testOnlyUTMIsSelectableWhileLegacyCampusesRemainDecodable() throws {
        XCTAssertEqual(Campus.selectableCases, [.utm])
        XCTAssertEqual(Campus.editableCases, [.utm, .unknown])
        XCTAssertEqual(UserPreferences.defaults.campusContext, .unknown)
        XCTAssertEqual(try JSONDecoder().decode(Campus.self, from: Data("\"utsg\"".utf8)), .utsg)
    }
}
