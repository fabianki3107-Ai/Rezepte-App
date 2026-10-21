# Rezepte – Local-First Rezept-App für iOS

Eine blitzschnelle, komplett offline arbeitende Rezept-App in SwiftUI + SwiftData.
Rezepte werden per **Screenshot/Foto (Apple Vision OCR)**, **Instagram-Link** oder Text importiert,
in einer sauberen Bibliothek verwaltet und über einen **ablenkungsfreien Koch-Modus** gekocht.

- 100 % On-Device: keine Cloud, kein Konto, keine Serverkosten (`cloudKitDatabase: .none`)
- Apple-natives Design nach HIG: `systemGroupedBackground`, `systemBlue` für Interaktion, `systemMint` für Vertrauens-Badges
- iOS 17+, Swift 5.10, Xcode 16+

## Features

| Bereich | Umsetzung |
| --- | --- |
| Import Screenshot/Foto | `VisionOCRManager` (VNRecognizeTextRequest, `.accurate`, de/en), Zeilen-Rekonstruktion in Leserichtung |
| Import Instagram-Link | `InstagramLinkParser` (Beitrag/Reel/IGTV, Tracking-Parameter entfernt) + optionaler Open-Graph-Abruf **direkt vom Gerät** |
| Share-Extension | Link, Text oder Bild aus jeder App „In Rezepte sichern“; Übergabe über App-Group-Inbox |
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
open RezepteApp.xcodeproj
```

Danach in Xcode:

1. Unter *Signing & Capabilities* für **RezepteApp** und **RezepteShareExtension** dein Team wählen.
2. Die App Group `group.de.fabian.rezepte` (siehe `ImportInbox.appGroupIdentifier`) in beiden Targets aktivieren,
   oder den Identifier in `project.yml` und `ImportInboxItem.swift` an deine Team-ID anpassen.
3. Schema **RezepteApp** auf einem Gerät oder Simulator starten (⌘R), Tests mit ⌘U.

Alternative ohne XcodeGen: Neues iOS-App-Projekt „RezepteApp“ (SwiftUI, SwiftData) anlegen, den Ordner `RezepteApp/`
als Gruppe hinzufügen, Share-Extension-Target anlegen und `RezepteShareExtension/` plus
`ImportInboxItem.swift` und `InstagramLinkParser.swift` darin einbinden. Die benötigten Info.plist-Schlüssel stehen in `project.yml`.

## Ordnerstruktur

```
RezepteApp/
├── App/            Einstieg, Tab-Navigation, Design-Tokens (AppTheme)
├── Models/         SwiftData-Modelle, Einheiten, Mengen-Formatierung, Skalierer, Beispieldaten
├── Import/
│   ├── OCR/        VisionOCRManager
│   ├── Parsing/    RecipeTextParser, IngredientLineParser, StepAnnotator, ParsedRecipeDraft
│   ├── Instagram/  InstagramLinkParser, InstagramCaptionFetcher (Open Graph)
│   ├── Inbox/      App-Group-Austausch mit der Share-Extension
│   └── ImportCoordinator.swift
├── Features/
│   ├── Library/    LibraryView, RecipeCardView, TrustBadgeView
│   ├── RecipeDetail/ RecipeDetailView, ServingsScalerView, IngredientRowView
│   ├── CookingMode/  CookingSession, CookingModeView (Timer, Zutaten-Sheet, Abschluss)
│   ├── Import/     ImportHubView, ImportReviewView, ImagePickers
│   └── Settings/   SettingsView
├── Services/       RecipeRepository, ImageProcessing, TimerNotificationService, AppSettings
├── Extensions/     Regex-/String-Hilfen
└── Resources/      Assets (AccentColor = systemBlue)
RezepteShareExtension/  ShareViewController
RezepteAppTests/        Swift-Testing-Suites für Parser, Formatierung, Instagram-Links
```

## Datenschutz-Modell

- Alle Rezepte, Bilder und Einstellungen liegen ausschließlich im App-Sandbox-Container.
- Texterkennung läuft mit Apple Vision auf dem Gerät.
- Die einzige Netzwerkfunktion ist der optionale Abruf der öffentlichen Instagram-Beitragsseite **direkt von instagram.com**
  (wie ein Browser, ephemere Session ohne Cookies). Sie lässt sich in den Einstellungen abschalten; dann wird der Link nur
  als Quelle gespeichert und der Inhalt kommt per Screenshot oder Einfügen.
- Kein Analytics, keine Crash-Reporter, keine Drittanbieter-SDKs.

Details zur Architektur und zu den Entscheidungen: [ARCHITECTURE.md](ARCHITECTURE.md).
