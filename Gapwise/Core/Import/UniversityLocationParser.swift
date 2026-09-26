import Foundation

enum UniversityBuildingCatalog {
    // Recognition-only snapshot of Gapwise Data. No geometry, entrance, floor or access claims.
    // https://github.com/GapwiseHQ/data/blob/4325a2fa05e54c5ae69355c5fca2d2312485850c/data/utm/building-registry.ts
    // Public code aliases come from normalizePublicBuildingCode, not officialCodes evidence.
    static let utmBuildingNames: [String: String] = [
        "MN": "Maanjiwe nendamowinan",
        "DH": "Deerfield Hall",
        "IB": "Instructional Centre",
        "DV": "William G. Davis Building",
        "CCT": "Communication, Culture and Technology Building",
        "HM": "Hazel McCallion Academic Learning Centre",
        "KN": "Kaneff Centre",
        "IC": "Innovation Complex",
        "RAWC": "Recreation, Athletics and Wellness Centre",
        "XR": "Student Centre",
        "HB": "Terrence Donnelly Health Sciences Complex",
        "AX": "Academic Annex",
        "WC": "Alumni House",
        "CUP": "Central Utilities Plant",
        "DW": "Erindale Studio Theatre",
        "FCSH": "Forensic Crime Scene House",
        "GF": "Grounds Building",
        "NSB": "New Science Building",
        "PL": "Paleomagnetism Lab",
        "BG": "Research Greenhouse",
        "LH": "The Principal's Residence: Lislehurst",
        "EH": "Erindale Hall",
        "LL": "Leacock Lane",
        "MV": "MaGrath Valley",
        "MC": "McLuhan Court",
        "OPH": "Oscar Peterson Hall",
        "PP": "Putnam Place",
        "RIH": "Roy Ivor Hall",
        "SW": "Schreiberwood",
        "NRB": "New Residence Building",
    ]
    private static let publicAliases = ["CC": "CCT", "RA": "RAWC", "R": "LL", "SB": "NSB"]

    static func canonicalCode(_ code: String) -> String? {
        let normalized = code.uppercased()
        return utmBuildingNames[normalized] != nil ? normalized : publicAliases[normalized]
    }

    static func isKnownUTMCode(_ code: String) -> Bool {
        canonicalCode(code) != nil
    }
}

struct UniversityLocationParser: Sendable {
    func parse(_ rawValue: String?) -> MeetingLocation? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.uppercased()
        if containsAny(normalized, values: ["ONLINE", "REMOTE", "VIRTUAL", "ZOOM", "ASYNCHRONOUS"]) {
            return MeetingLocation(displayName: "Online", rawLocation: trimmed, kind: .online)
        }
        if normalized.hasPrefix("ZZ") || normalized == "N/A"
            || containsAny(normalized, values: ["TBA", "TBD", "TO BE ANNOUNCED", "TO BE DETERMINED"]) {
            return MeetingLocation(displayName: "TBA", rawLocation: trimmed, kind: .toBeAnnounced)
        }

        if let components = buildingAndRoom(in: trimmed) {
            return MeetingLocation(
                displayName: trimmed,
                rawLocation: trimmed,
                buildingCode: components.building,
                room: components.room,
                kind: .physical
            )
        }

        return MeetingLocation(displayName: trimmed, rawLocation: trimmed, kind: .unknown)
    }

    private func containsAny(_ value: String, values: [String]) -> Bool {
        let words = Set(value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return values.contains { $0.contains(" ") ? value.contains($0) : words.contains($0) }
    }

    private func buildingAndRoom(in location: String) -> (building: String, room: String)? {
        let rawTokens = location.split(whereSeparator: { $0.isWhitespace || ",;/()-".contains($0) }).map(String.init)

        for (index, rawToken) in rawTokens.enumerated() {
            let letterPrefix = rawToken.prefix(while: \.isLetter)
            let token = letterPrefix.uppercased()
            let suffix = rawToken.dropFirst(letterPrefix.count)

            if let canonicalCode = UniversityBuildingCatalog.canonicalCode(token), suffix.first?.isNumber == true {
                return (canonicalCode, String(suffix))
            }

            guard
                let canonicalCode = UniversityBuildingCatalog.canonicalCode(token),
                suffix.isEmpty,
                index + 1 < rawTokens.count
            else {
                continue
            }

            let nextToken = rawTokens[index + 1].trimmingCharacters(in: .punctuationCharacters)
            if nextToken.first?.isNumber == true {
                return (canonicalCode, nextToken)
            }
        }

        return nil
    }
}
