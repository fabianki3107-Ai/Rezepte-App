# Architektur

## Leitprinzipien

1. **Local-First, Offline-Only.** Ein einziger lokaler SwiftData-Store, explizit ohne CloudKit. Es gibt keinen Backend-Code,
   weil es kein Backend gibt. Die einzige Netzwerkoperation (Instagram-Open-Graph) ist optional und läuft Gerät → instagram.com.
2. **Werttypen für Logik, Referenztypen für Zustand.** Parsing, Skalierung und Formatierung arbeiten auf `struct`s
   (`Measure`, `ParsedRecipeDraft`, `StepTimer`) und sind ohne ModelContext testbar. SwiftData-Klassen sind reine Persistenz.
3. **Eine Schreibstelle.** Views lesen über `@Query`, schreiben nur über `RecipeRepository`.
4. **HIG statt Eigenbau.** Systemfarben, `List`/`Form`, `ContentUnavailableView`, `sensoryFeedback`, Dynamic Type, 44-pt-Ziele.

## Schichten

```
┌──────────────────────────────────────────────────────────────────┐
│ Features (SwiftUI)                                               │
│  Library · RecipeDetail · CookingMode · Import · Settings        │
├──────────────────────────────────────────────────────────────────┤
│ Koordination / Zustand (@Observable, @MainActor)                 │
│  ImportCoordinator · CookingSession · AppSettings                │
├──────────────────────────────────────────────────────────────────┤
│ Domänenlogik (reine Werttypen, testbar)                          │
│  RecipeTextParser · IngredientLineParser · StepAnnotator         │
│  ServingsScaler · QuantityFormatter · InstagramLinkParser        │
│  OpenGraphParser                                                 │
├──────────────────────────────────────────────────────────────────┤
│ Services                                                         │
│  VisionOCRManager (actor) · InstagramCaptionFetcher (actor)      │
│  RecipeRepository · ImageProcessing · TimerNotificationService   │
├──────────────────────────────────────────────────────────────────┤
│ Persistenz                                                       │
│  SwiftData: Recipe ─< Ingredient, Recipe ─< CookingStep,         │
│             Recipe >─< Tag · App-Group-Inbox (JSON + Bild)       │
└──────────────────────────────────────────────────────────────────┘
```

## Datenmodell

| Modell | Zweck | Besonderheiten |
| --- | --- | --- |
| `Recipe` | Rezeptkopf, Herkunft, Vertrauen, Bilder | Enums als `String`-Rohwerte (prädikatfähig), `heroImageData` in `.externalStorage`, `thumbnailData` klein im Store für flüssige Listen |
| `Ingredient` | Zutat mit strukturierter Menge | `quantity`/`quantityUpperBound` (Bereiche), `unit`, `group`, `isScalable`, `isOptional`; `sortIndex` für stabile Reihenfolge |
| `CookingStep` | Schritt mit erkannter Dauer/Temperatur | Grundlage für Timer im Koch-Modus |
| `Tag` | Schlagwort, dedupliziert über `@Attribute(.unique)` | Normalisierung in `Tag.normalized` |

Relationen sind in SwiftData ungeordnet, daher `sortedIngredients` / `sortedSteps`. `deleteRule: .cascade` räumt Zutaten
und Schritte beim Löschen eines Rezepts auf. Das Schema ist in `RecipeSchemaV1` gebündelt; eine spätere Migration
erhält `RecipeSchemaV2` + `SchemaMigrationPlan`.

## Import-Pipeline

```
Screenshot/Foto ─► VisionOCRManager ─► OCRResult(text, confidence)
Instagram-Link  ─► InstagramLinkParser ─► InstagramCaptionFetcher ─► caption, author, og:image
Text/Share      ─► (direkt)
                                          │
                                          ▼
                                  RecipeTextParser
                      ┌──────────────────┼──────────────────┐
                 Rauschfilter      Abschnitts-          Metadaten
                 (#tags, UI)       erkennung            (Portionen, Zeiten, Tags)
                                   │         │
                          IngredientLineParser  StepAnnotator
                                          │
                                          ▼
                                ParsedRecipeDraft (+ Warnings)
                                          │
                                          ▼
                                 ImportReviewView (Nutzer prüft)
                                          │
                                          ▼
                              RecipeRepository.save(draft:)
```

### OCR (Apple Vision)

- `VNRecognizeTextRequest` mit `.accurate`, Sprachkorrektur, Sprachen `de-DE`, `en-US`, automatische Spracherkennung.
- `minimumTextHeight` filtert Statusleisten-Reste aus Screenshots.
- Beobachtungen werden nach `top`/`left` sortiert und bei ≥ 50 % vertikaler Überlappung zu einer Zeile verschmolzen,
  damit zweispaltige Zutatenlisten („200 g | Mehl“) als eine Zeile beim Parser ankommen.
- Konfidenz wird zeichen-gewichtet gemittelt und am Rezept gespeichert → Vertrauens-Badge
  (≥ 85 % Mint „Gut erkannt“, darunter Orange „Bitte prüfen“).

### Parser-Heuristiken

- **Rauschen:** Hashtag-Zeilen, Handles, „Folgt mir“, „Gefällt … Mal“, Uhrzeiten, reine Symbolzeilen.
- **Abschnitte:** Überschriften (de/en) haben Vorrang. Fehlen sie, eröffnet die erste Zeile mit Mengenangabe den
  Zutatenteil; Fließtext (≥ 8 Wörter oder nummeriert) beendet ihn.
- **Zutatenzeile:** Menge (Dezimal, Bruch, Unicode-Bruch, gemischt, Bereich, Zahlwort, Multiplikator „2x“), Einheit
  (umfangreiche Alias-Tabelle, Modifikatoren wie „gestr.“), Name, Hinweis (Komma/Klammer), optional, Trailing-Layout
  „Mehl 250 g“.
- **Schritte:** Nummerierung entfernt, umbrochene Zeilen zusammengeführt (Kleinbuchstabe/Komma als Fortsetzung),
  ein einzelner langer Absatz wird in Sätze zerlegt. `StepAnnotator` zieht Dauer (Obergrenze bei Bereichen) und
  Temperatur (°F → °C).
- **Metadaten:** Portionen („für 4 Personen“, „ergibt 12 Stück“, „Serves 6“), Zeiten („Zubereitungszeit: 15 Min“,
  „Backzeit: 1,5 Std“), Tags aus Hashtags minus Generika.

Alle Heuristiken sind in `RezepteAppTests` abgedeckt; Erweiterungen sollten mit einem Beispiel dort starten.

### Instagram-Link

Instagram bietet keine serverlose API für Captions. Zwei Stufen:

1. **Direkt-Abruf** der öffentlichen Beitragsseite vom Gerät (ephemere `URLSession`, 12 s Timeout). Die Open-Graph-Tags
   `og:title`/`og:description` enthalten die Caption im Format `… on Instagram: "…"`. `OpenGraphParser` extrahiert sie
   per Regex und dekodiert Entities. Scheitert der Abruf (Login-Wand, offline), bleibt der Link als Quelle gespeichert.
2. **Fallback:** Screenshot-OCR oder Einfügen der Caption. Die Share-Extension liefert beides aus der Instagram-App.

Der Direkt-Abruf ist in den Einstellungen abschaltbar (`AppSettings.loadInstagramPreview`).

### Share-Extension

`ShareViewController` schreibt `ImportInboxItem` (JSON) plus optionales Bild atomar in den App-Group-Ordner.
Die App leert den Eingang bei `scenePhase == .active` und startet den passenden Import. Kein IPC, kein Netzwerk.

## Portionen-Skalierer

`ServingsScaler(baseServings:targetServings:)` liefert einen Faktor; `Measure.scaled(by:)` skaliert nur, wenn
`isScalable` (Gewürze/„nach Geschmack“ nicht). `QuantityFormatter` rundet kontextabhängig:

- Stückmaße snappen auf Küchenbrüche ⅛ ¼ ⅓ ½ ⅔ ¾ („1 ½ Tassen“), sonst eine Nachkommastelle.
- Kontinuierliche Einheiten: < 10 in halben Schritten, < 100 ganzzahlig, ≥ 100 auf 5er gerundet.
- Bereiche („2–3 EL“) und Plurale („2 Zehen“) werden korrekt dargestellt.

Der abgehakte Zustand der Zutaten ist bewusst flüchtig (UI-State), wandert aber in die `CookingSession` und zurück.

## Koch-Modus

- `fullScreenCover`, `TabView(.page)` je Schritt, `interactiveDismissDisabled`, Schriftgröße `.title` mit `rounded`-Design.
- `TimelineView(.periodic)` treibt die Uhr; `StepTimer` rechnet mit Enddaten statt Zählern und überlebt Hintergrundphasen.
- Lokale Mitteilung (`UNTimeIntervalNotificationTrigger`, time-sensitive) beim Timer-Start; Berechtigung wird erst im
  Kontext angefragt (HIG).
- `isIdleTimerDisabled` nur während des Koch-Modus und nur, wenn in den Einstellungen gewünscht.
- Zutaten pro Schritt per Wortstamm-Abgleich („Zwiebeln“ ↔ „Zwiebel“) mit skalierten Mengen eingeblendet.
- Abschluss setzt `lastCookedAt` und `verification = .cooked` → Mint-Badge „Gekocht“.

## Design-System

`AppTheme` kapselt semantische Systemfarben (`systemGroupedBackground`, `systemBlue`, `systemMint`, `systemOrange`
für „bitte prüfen“), 8-pt-Abstände, Radien und die 44-pt-Mindestgröße. Es werden keine Hex-Farben verwendet, damit
Dark Mode, erhöhter Kontrast und reduzierte Transparenz automatisch funktionieren.

## Testen

Swift Testing (`import Testing`) für die reine Logik: Zutatenzeilen, Gesamt-Parser, Annotator, Formatierung,
Skalierer, Instagram-Links, Open Graph. UI und OCR werden über Previews mit `RecipeSchemaV1.previewContainer()` geprüft.

## Erweiterungspunkte

- **Schema-Migration:** `RecipeSchemaV2` + `SchemaMigrationPlan`, `ModelContainer(for:migrationPlan:)`.
- **Weitere Quellen:** Neuer `ImportSource.Kind` + ein Einstieg im `ImportCoordinator`; der Parser bleibt gleich.
- **Spracherkennung im Koch-Modus:** `SFSpeechRecognizer` (on-device) für „Weiter“/„Zurück“ – passt ins Offline-Modell.
- **iPad:** `NavigationSplitView` in `LibraryView`, Layout ist bereits adaptiv.
