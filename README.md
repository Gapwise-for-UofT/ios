<div align="center">

<img src="assets/gapwise-ios.svg" width="116" alt="Gapwise for iOS logo" />

# Gapwise for iOS

### The native iOS client for Gapwise.

**A privacy-first Swift + SwiftUI app for University of Toronto timetables and campus context, designed around fast local interaction and canonical Gapwise data boundaries.**

[![iOS](https://img.shields.io/badge/iOS-Native-000000?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-Native-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://www.swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-Native_UI-0D96F6?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![MIT](https://img.shields.io/badge/License-MIT-111111?style=for-the-badge)](LICENSE)

<sub>Swift · SwiftUI · Apple platform APIs · privacy-first local state</sub>

<br />

**[Gapwise](https://gapwise.ca)** · **[Android](https://github.com/Gapwise-for-UofT/android)** · **[iOS](https://github.com/Gapwise-for-UofT/ios)** · **[AI](https://ai.gapwise.ca)** · **[Data](https://data.gapwise.ca)** · **[Docs](https://docs.gapwise.ca)** · **[Status](https://status.gapwise.ca)**

</div>

---

## What Gapwise for iOS is

Gapwise for iOS is the native iPhone client for **Gapwise**, a privacy-first timetable, gap-planning, and campus-intelligence project for University of Toronto students.

The current iOS implementation can import UTM timetable events and preserve unresolved campus information; it does not yet provide a UTSG, UTSC, or mixed-campus native experience. That is a client implementation limit, not the identity of Gapwise. Campus facts, entrances, accessibility evidence, and geometry remain owned by the canonical Gapwise Data boundary rather than by hand-maintained iOS constants.

The goal is a real native iOS application rather than a WebView wrapper: navigation, storage, rendering, accessibility, interactions, and platform integration are designed for iPhone while staying aligned with the wider Gapwise repository ecosystem.

---

## Current status

The repository contains a working early native foundation: an iPhone SwiftUI target, local `.ics` timetable import with review-before-save, local timetable persistence, deterministic timetable/reconciliation logic, date-aware Today and Timetable views, a Gaps surface backed by portable schedule arithmetic, a currently UTM-specific Map integration boundary, Settings, portable domain tests, and GitHub Actions for Linux-portable and macOS/iOS validation.

This remains an **early implementation**, not a shipped client. Import compatibility is validated against synthetic standards-based fixtures rather than every producer or a live ACORN export. Native UTM map rendering, production routing, account continuity, remote integrations, and broader timetable editing remain future work. The production app starts from local user data rather than seeded demo data.

---

## Product direction

The native iOS experience follows the same principles as the rest of Gapwise:

- **Fast to open and easy to understand.** The important parts of the day should be immediately visible.
- **Honest native coverage.** The current client accepts UTM timetable events while retaining the tri-campus domain model and unresolved-campus state needed for broader support.
- **Campus-data honesty.** Map and routing features only claim facts supported by canonical Gapwise Data evidence.
- **Local-first timetable handling.** Import and core schedule use work without unnecessary network transmission.
- **Optional account continuity.** A Gapwise account should enhance continuity rather than gate core timetable use.
- **Deterministic planning.** Timetable arithmetic, gaps, route timing, and feasibility should remain explicit and testable.
- **Native interaction.** Navigation, gestures, sheets, system pickers, accessibility, appearance, and lifecycle behavior should feel natural on iOS.

---

## App surface

The current foundation includes:

- **Today**, derived from the local timetable with current/next-class context and truthful empty states;
- **Timetable**, with local schedule browsing, import, review, and meeting details;
- **Gaps**, using deterministic portable schedule arithmetic rather than heuristic suggestions;
- **Map**, currently an honest UTM-specific integration boundary rather than fabricated tri-campus routing coverage;
- **Settings**, for implemented local preferences, timetable management, privacy information, and ecosystem links;
- native document picking and import preview for compatible `.ics` files;
- atomic local JSON persistence behind an async repository boundary;
- light/dark appearance, Dynamic Type-friendly layouts, VoiceOver-minded labels, and native navigation.

Planned work includes broader import compatibility, richer timetable editing, canonical UTM map consumption and routing, exports/integrations, and optional account continuity.

---

## Technology

Gapwise for iOS uses modern native Apple tooling:

- **Swift**
- **SwiftUI**
- Foundation persistence and Apple lifecycle APIs
- platform-secure storage such as **Keychain** when secret material is eventually required
- a native UTM map layer consuming canonical Gapwise data/contracts rather than inventing a parallel source of truth
- optional Gapwise account integration only after its security boundary is implemented and reviewed

Portable domain models, iCalendar parsing, timetable interpretation, reconciliation, and schedule arithmetic are kept separate from persistence and SwiftUI presentation.

### Timetable import

Gapwise accepts user-selected `.ics` files through the system document picker. Parsing, interpretation, preview, and persistence happen locally. The original calendar file is not retained as an application data source and timetable contents are not uploaded as part of ordinary import.

The parser supports the timetable-oriented iCalendar subset exercised by the repository fixtures, including `VCALENDAR`, `VEVENT`, `DTSTART`, `DTEND`, `SUMMARY`, `LOCATION`, `DESCRIPTION`, `UID`, bounded weekly `RRULE` values, folded lines, escaped text, UTF-8 input, UTC/system timezone identifiers, and floating timestamps.

Course/campus interpretation is deliberately conservative. UTM building evidence can establish UTM identity; conflicting or insufficient evidence remains unknown. UTSG and UTSC remain explicit domain values rather than being recast as UTM, although this early iOS version does not yet accept those meetings into its saved timetable.

Repeated imports reconcile by source identity and event `UID` so unchanged meetings are not duplicated. Existing local data is not silently discarded simply because a later import omits an event.

Current limitations include unsupported recurrence-exception families and incomplete building recognition. Import is not ACORN login, credential access, scraping, or account/API integration.

---

## Privacy and security

The iOS client follows the wider Gapwise security posture:

- minimize collection and transmission of student timetable data;
- keep calendar handling local where practical;
- never embed privileged service credentials in the application;
- distinguish local-only features from optional account/cloud behavior;
- use platform-backed secret storage when secret material is introduced;
- preserve uncertainty instead of inventing location/accessibility certainty;
- keep permissions narrow, understandable, and revocable.

The current timetable store uses local application storage behind an explicit repository boundary. Calendar import is designed to run on-device without requiring networking or telemetry. No account sync or production map/routing capability is claimed by this foundation.

---

## Development

The app targets iPhone on iOS 17 or later and uses an Xcode project with no third-party runtime dependency requirement in the current foundation.

```bash
git clone https://github.com/Gapwise-for-UofT/ios.git
cd ios
```

On macOS, open `Gapwise.xcodeproj`, select the `Gapwise` scheme, and build/test on an iPhone simulator or device.

The portable Swift core can also be validated on Linux. The repository CI uses Swift 6.3.3 on Ubuntu Noble for the portable package:

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.3.3-noble swift package describe
docker run --rm -v "$PWD:/workspace" -w /workspace swift:6.3.3-noble swift test
```

Linux cannot validate SwiftUI, the system document picker, Apple security-scoped URL behavior, signing, simulator lifecycle, or other Apple-only integration. Those remain macOS/Xcode validation responsibilities.

---

## Gapwise ecosystem

| Repository | Role | Primary surface |
| --- | --- | --- |
| **[`gapwise`](https://github.com/Gapwise-for-UofT/gapwise)** | Core web/PWA, canonical timetable/gap/routing semantics, public API, OpenAPI, and SDK source | [gapwise.ca](https://gapwise.ca) / [api.gapwise.ca](https://api.gapwise.ca/v1) |
| **[`android`](https://github.com/Gapwise-for-UofT/android)** | Native Kotlin + Jetpack Compose Android client | Android app |
| **[`ios`](https://github.com/Gapwise-for-UofT/ios)** | Native Swift + SwiftUI iOS client | iOS app |
| **[`ai`](https://github.com/Gapwise-for-UofT/ai)** | OAuth/MCP layer for explicitly delegated student context and bounded actions | [ai.gapwise.ca](https://ai.gapwise.ca) |
| **[`data`](https://github.com/Gapwise-for-UofT/data)** | Canonical public University of Toronto campus data, provenance, schemas, validation, and distribution | [data.gapwise.ca](https://data.gapwise.ca) |
| **[`docs`](https://github.com/Gapwise-for-UofT/docs)** | Canonical public developer documentation | [docs.gapwise.ca](https://docs.gapwise.ca) |
| **[`status`](https://github.com/Gapwise-for-UofT/status)** | Independent service-health monitoring and incident communication | [status.gapwise.ca](https://status.gapwise.ca) |

The repositories are separate implementation and trust boundaries, but they form one product. Native clients should consume canonical Gapwise behavior rather than silently becoming independent timetable, routing, or campus-data engines.

---

## Independent project

> **Gapwise is an independent student software project created by Andrew Muratov. It is not affiliated with, endorsed by, or an official service of the University of Toronto.**

## License

Original project code and documentation are available under the [MIT License](LICENSE).

<div align="center">

**Built for the spaces between classes — coming natively to iOS.**

[Open Gapwise →](https://gapwise.ca)

</div>
