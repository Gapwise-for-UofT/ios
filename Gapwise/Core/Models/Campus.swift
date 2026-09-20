import Foundation

enum Campus: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case utm
    case utsg
    case utsc
    case unknown

    var id: Self { self }

    // The domain keeps every U of T campus explicit; this early client currently accepts UTM imports.
    static let selectableCases: [Self] = [.utm]
    static let editableCases: [Self] = [.utm, .unknown]

    var shortName: String {
        switch self {
        case .utm: "UTM"
        case .utsg: "UTSG"
        case .utsc: "UTSC"
        case .unknown: "Unknown"
        }
    }

    var fullName: String {
        switch self {
        case .utm: "University of Toronto Mississauga"
        case .utsg: "University of Toronto St. George"
        case .utsc: "University of Toronto Scarborough"
        case .unknown: "Campus not determined"
        }
    }

    var selectionName: String {
        switch self {
        case .unknown: "Unknown / Unspecified"
        default: shortName
        }
    }
}
