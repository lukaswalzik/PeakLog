# StrongTracker – Projektregeln

Dieses Dokument definiert verbindliche technische Regeln für die Entwicklung der nativen iOS-App **StrongTracker**. Alle Änderungen am Codebase müssen diese Vorgaben strikt einhalten.

## Zielgerät & Deployment Target

- **Zielgerät:** iPhone 14 Pro
- **Deployment Target:** Strikt **iOS 16.5** (`IPHONEOS_DEPLOYMENT_TARGET = 16.5`)

## Verbotene APIs (iOS 17+)

Alle APIs, Frameworks und SwiftUI-Modifier, die erst ab iOS 17.0 oder neuer eingeführt wurden, sind **strikt verboten**:

- **KEIN** `SwiftData`
- **KEIN** `@Observable` / `@Bindable` (Observation-Framework)
- **KEIN** `ContentUnavailableView`
- **KEINE** iOS-17+-SwiftUI-Modifier oder -Signaturen (z. B. neues `onChange(of:initial:_:)` mit 0 oder 2 Parametern, `scrollPosition`, `containerRelativeFrame`, `#Preview`-Makros)

## Erlaubte Technologien & APIs

- **UI:** SwiftUI (strikt iOS-16.5-kompatibel)
- **Zustandsverwaltung:** `ObservableObject`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Published`
- **Navigation:** `NavigationStack`
- **Diagramme:** Swift Charts
- **Persistenz (für spätere Ausbaustufen):** Core Data oder SQLite

## Projektverwaltung

- Die Xcode-Projektstruktur wird **ausschließlich** über **XcodeGen** (`project.yml`) verwaltet.
- Es werden **keine `.xcodeproj`-Dateien** (oder `.xcworkspace`-Dateien) in das Repository eingecheckt. Das Projekt wird lokal und in CI stets über `xcodegen generate` erzeugt.

## Bundle Identifier & Signierung

- **Feste Bundle-ID:** `com.local.strongtracker`
  - Diese Bundle-ID darf **niemals geändert** werden, damit lokale App-Daten bei Updates erhalten bleiben.
- **Distribution:** Unsignierte `.ipa` für TrollStore (`CODE_SIGNING_ALLOWED = NO`).
