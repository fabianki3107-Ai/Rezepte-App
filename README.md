# Kochlog – Local-First Rezept-Import & Kalorien-Tracker für iOS

Eine blitzschnelle, komplett offline arbeitende 2-in-1-App in SwiftUI + SwiftData:
Rezepte werden per **Screenshot/Foto (Apple Vision OCR)**, **Instagram-/TikTok-Link** oder Text importiert,
die **Nährwerte pro Portion lokal geschätzt**, mit **einem Tap ins Kalorien-Tagebuch** geloggt und
optional in **Apple Health** geschrieben. Gekocht wird über einen ablenkungsfreien Koch-Modus.

- 100 % On-Device: keine Cloud, kein Konto, keine Serverkosten (`cloudKitDatabase: .none`)
- Apple-natives Design nach HIG: `systemGroupedBackground`, `systemBlue` für Interaktion, `systemMint` für Vertrauens-Badges,
  Kalorienring und Makro-Balken mit Swift Charts / `ProgressView`
- iOS 17+, Swift 5, Xcode 16+

## Features

| Bereich | Umsetzung |
| --- | --- |
| Import Screenshot/Foto | `VisionOCRManager` (VNRecognizeTextRequest, `.accurate`, de/en), Zeilen-Rekonstruktion in Leserichtung |
| Import Instagram-/TikTok-Link | `SocialLinkParser` (Instagram Beitrag/Reel/IGTV, TikTok Video/Kurzlink) + optionaler Open-Graph-Abruf **direkt vom Gerät** |
| Nährwert-Schätzung | `LocalNutritionParser`: Zutaten → lokale `FoodDatabase` (170+ Lebensmittel) → Gramm → kcal/Eiweiß/KH/Fett pro Portion, deklarierte Werte im Text haben Vorrang |
| Kalorien-Tagebuch | `NutritionLogService`: 1-Tap-Log aus dem Rezept, Portionen anpassen, `DailyLog`/`LogEntry` mit Snapshot |
| Dashboard | `DashboardView`: Kalorienring (`SectorMark`), Makro-Balken, 7-Tage-Chart, heutige Einträge |
| Apple Health | `HealthKitManager`: Energie + Makros als `HKCorrelation(.food)`, Update/Löschen über Sync-Identifier |
| Share-Extension | Link, Text oder Bild aus jeder App „In Kochlog sichern“; Übergabe über App-Group-Inbox |
| Parser | `RecipeTextParser` erkennt Titel, Portionen, Zeiten, Zutaten-Gruppen, Schritte, Timer, Temperaturen, Tags |
| Review | `ImportReviewView`: alle Felder editierbar, Warnungen, OCR-Konfidenz-Badge, Originaltext einsehbar |
| Bibliothek | `@Query`-Suche über Titel, Zutaten, Tags; Sortierung; Favoriten; Swipe-Aktionen |
| Detail | Portionen-Skalierer mit Kochbuch-Brüchen (½, 1 ½), interaktive Zutaten zum Abhaken, Vertrauens-Badge |
| Koch-Modus | Ein Schritt pro Seite, große Schrift, Schritt-Timer mit lokaler Mitteilung, relevante Zutaten pro Schritt, Bildschirm bleibt an |
| Daten | SwiftData lokal, Bilder via `.externalStorage`, JSON-Export als Datei, „Alle löschen“ |

## Projekt erzeugen

Das Repository enthält Quellcode und eine [XcodeGen](https://github.com/yonaskolb/XcodeGen)-Spezifikation statt einer `.xcodeproj`
(weniger Merge-Konflikte, reproduzierbar).

```bash
brew install xcodegen
xcodegen generate
open Kochlog.xcodeproj
```

Danach in Xcode:

1. Unter *Signing & Capabilities* für **Kochlog** und **KochlogShareExtension** dein Team wählen.
2. Die App Group `group.de.fabian.rezepte` (siehe `ImportInbox.appGroupIdentifier`) in beiden Targets aktivieren,
   oder den Identifier in `project.yml` und `ImportInboxItem.swift` an deine Team-ID anpassen.
   Die HealthKit-Capability ist in `project.yml` hinterlegt; sie braucht ein bezahltes Developer-Team.
3. Schema **Kochlog** auf einem Gerät oder Simulator starten (⌘R), Tests mit ⌘U.

Alternative ohne XcodeGen: Neues iOS-App-Projekt „Kochlog“ (SwiftUI, SwiftData) anlegen, den Ordner `Kochlog/`
als Gruppe hinzufügen, Share-Extension-Target anlegen und `KochlogShareExtension/` plus
`ImportInboxItem.swift` und `InstagramLinkParser.swift` darin einbinden. Die benötigten Info.plist-Schlüssel stehen in `project.yml`.

## Ordnerstruktur

```
Kochlog/
├── App/            Einstieg, Tab-Navigation, Design-Tokens (AppTheme)
├── Models/         SwiftData-Modelle (RecipeItem, Ingredient, CookingStep, Tag, DailyLog, LogEntry), Einheiten, Skalierer
│   └── Nutrition/  NutritionFacts, Macro, NutritionGoals, NutritionSource
├── Nutrition/      FoodDatabase (lokal), LocalNutritionParser, GramsEstimator, NutritionTextExtractor
├── Import/
│   ├── OCR/        VisionOCRManager
│   ├── Parsing/    RecipeTextParser, IngredientLineParser, StepAnnotator, ParsedRecipeDraft
│   ├── Instagram/  InstagramLinkParser, TikTokLinkParser, SocialLinkParser, SocialCaptionFetcher (Open Graph)
│   ├── Inbox/      App-Group-Austausch mit der Share-Extension
│   └── ImportCoordinator.swift
├── Features/
│   ├── Dashboard/  DashboardView, CalorieRingView, MacroBarsView, WeeklyCaloriesChart, LogEntryRow
│   ├── Library/    LibraryView, RecipeCardView, TrustBadgeView
│   ├── RecipeDetail/ RecipeDetailView, NutritionCardsView, NutritionEditSheet, ServingsScalerView, IngredientRowView
│   ├── CookingMode/  CookingSession, CookingModeView (Timer, Zutaten-Sheet, Abschluss)
│   ├── Import/     ImportHubView, ImportReviewView, ImagePickers
│   └── Settings/   SettingsView
├── Services/       RecipeRepository, NutritionLogService, HealthKitManager, ImageProcessing, TimerNotificationService, AppSettings
├── Extensions/     Regex-/String-Hilfen
└── Resources/      Assets (AccentColor = systemBlue)
KochlogShareExtension/  ShareViewController
KochlogTests/        Swift-Testing-Suites für Parser, Nährwert-Schätzung, Formatierung, Instagram-/TikTok-Links
```

## Datenschutz-Modell

- Alle Rezepte, Bilder und Einstellungen liegen ausschließlich im App-Sandbox-Container.
- Texterkennung läuft mit Apple Vision auf dem Gerät.
- Nährwerte werden aus einer eingebauten Lebensmittel-Tabelle geschätzt – keine Food-API, kein Upload von Zutaten.
- Apple Health wird nur beschrieben (Ernährungsdaten), nie gelesen; die Option ist standardmäßig aus.
- Die einzige Netzwerkfunktion ist der optionale Abruf der öffentlichen Beitragsseite **direkt von instagram.com / tiktok.com**
  (wie ein Browser, ephemere Session ohne Cookies). Sie lässt sich in den Einstellungen abschalten; dann wird der Link nur
  als Quelle gespeichert und der Inhalt kommt per Screenshot oder Einfügen.
- Kein Analytics, keine Crash-Reporter, keine Drittanbieter-SDKs.

Details zur Architektur und zu den Entscheidungen: [ARCHITECTURE.md](ARCHITECTURE.md).

## TestFlight

Der Workflow `.github/workflows/testflight.yml` baut die App auf einem macOS-Runner und lädt sie nach TestFlight hoch.
Er startet nur manuell über **Actions → TestFlight → Run workflow**.

Vorher einmalig nötig:

1. Mitgliedschaft im Apple Developer Program und die Team-ID notieren.
2. In App Store Connect eine App mit der Bundle-ID `de.fabian.rezepte.app` und dem Namen Kochlog anlegen. Ohne diesen Datensatz lehnt Apple den Upload ab.
3. Unter Users and Access → Integrations → Team Keys einen API-Schlüssel mit der Rolle App Manager erzeugen. Die `.p8`-Datei lässt sich nur einmal herunterladen.
4. In den GitHub-Repository-Secrets diese Werte hinterlegen:
   - `APPLE_TEAM_ID`: die Team-ID
   - `ASC_KEY_ID`: die Key-ID des API-Schlüssels
   - `ASC_ISSUER_ID`: die Issuer-ID aus derselben Seite
   - `ASC_KEY_P8_BASE64`: der Inhalt der `.p8`-Datei, base64-kodiert (`base64 -i AuthKey_XXXX.p8`)

Die Build-Nummer ist die GitHub-Run-Nummer, die Version steht in `project.yml` (`MARKETING_VERSION`).
