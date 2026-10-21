import Testing
@testable import Kochlog

@Suite("RecipeTextParser")
struct RecipeTextParserTests {
    let instagramCaption = """
    Cremige Tomatenpasta 🍝 in 20 Minuten!
    Speichert euch das Rezept für später 👇
    Zutaten für 2 Personen:
    250 g Spaghetti
    1 Dose Tomaten (400 g)
    2 Knoblauchzehen
    100 ml Sahne
    Salz, Pfeffer
    Zubereitung:
    1. Nudeln nach Packungsanleitung 9 Minuten kochen.
    2. Knoblauch anbraten, Tomaten zugeben und 10 Minuten köcheln lassen.
    3. Sahne unterrühren, mit den Nudeln vermengen und servieren.
    Folgt mir für mehr Rezepte!
    #pasta #vegetarisch #rezept #food
    """

    @Test("Titel, Portionen, Zutaten und Schritte aus Instagram-Caption")
    func parsesCaption() {
        let draft = RecipeTextParser.parse(instagramCaption, source: .instagram(URL(string: "https://www.instagram.com/p/abc123/")!))
        #expect(draft.title == "Cremige Tomatenpasta in 20 Minuten!")
        #expect(draft.servings == 2)
        #expect(draft.ingredients.count == 5)
        #expect(draft.ingredients.first?.name == "Spaghetti")
        #expect(draft.steps.count == 3)
        #expect(draft.steps[0].durationSeconds == 9 * 60)
        #expect(draft.steps[1].durationSeconds == 10 * 60)
        #expect(draft.steps[0].text.hasPrefix("Nudeln"))
        #expect(draft.tags == ["Pasta", "Vegetarisch"])
        #expect(!draft.warnings.contains(.servingsGuessed))
    }

    @Test("Rauschen wie Hashtags, Handles und 'Folgt mir' wird entfernt")
    func noiseFiltering() {
        #expect(RecipeTextParser.isNoise("#pasta #vegetarisch"))
        #expect(RecipeTextParser.isNoise("@kochliebe"))
        #expect(RecipeTextParser.isNoise("Folgt mir für mehr Rezepte!"))
        #expect(RecipeTextParser.isNoise("Gefällt 1.234 Mal"))
        #expect(RecipeTextParser.isNoise("12:34"))
        #expect(!RecipeTextParser.isNoise("250 g Spaghetti"))
    }

    @Test("Ohne Überschriften werden Abschnitte über die Zeilenform erkannt")
    func parsesWithoutHeaders() {
        let text = """
        Schnelles Omelett
        3 Eier
        1 EL Butter
        Salz
        Eier verquirlen und salzen. Butter in der Pfanne schmelzen, Eier hineingeben und bei mittlerer Hitze 3 Minuten stocken lassen.
        """
        let draft = RecipeTextParser.parse(text)
        #expect(draft.title == "Schnelles Omelett")
        #expect(draft.ingredients.map(\.name) == ["Eier", "Butter", "Salz"])
        #expect(draft.steps.count == 1)
        #expect(draft.steps.first?.durationSeconds == 180)
        #expect(draft.warnings.contains(.servingsGuessed))
        #expect(draft.servings == 4)
    }

    @Test("Zutatengruppen über Doppelpunkt-Zeilen")
    func ingredientGroups() {
        let text = """
        Pancakes
        Zutaten
        Für den Teig:
        250 g Mehl
        2 Eier
        Zum Servieren:
        Ahornsirup
        Zubereitung
        Alles verrühren und ausbacken.
        """
        let draft = RecipeTextParser.parse(text)
        #expect(draft.ingredients.count == 3)
        #expect(draft.ingredients[0].group == "Für den Teig")
        #expect(draft.ingredients[2].group == "Zum Servieren")
    }

    @Test("Zeiten aus Metadaten")
    func times() {
        let times = RecipeTextParser.extractTimes(from: "Zubereitungszeit: 15 Min · Backzeit: 1,5 Std")
        #expect(times.prep == 15)
        #expect(times.cook == 90)
    }

    @Test("Portionen in verschiedenen Schreibweisen")
    func servings() {
        #expect(RecipeTextParser.extractServings(from: "Für 4 Personen") == 4)
        #expect(RecipeTextParser.extractServings(from: "ergibt 12 Stück") == 12)
        #expect(RecipeTextParser.extractServings(from: "Serves 6") == 6)
        #expect(RecipeTextParser.extractServings(from: "Portionen: 3") == 3)
        #expect(RecipeTextParser.extractServings(from: "für 10 Minuten backen") == nil)
    }

    @Test("Langer Fließtext wird in Schritte zerlegt")
    func splitsParagraph() {
        let text = """
        Ofenkartoffeln
        1 kg Kartoffeln
        3 EL Öl
        Zubereitung
        Den Ofen auf 200 °C vorheizen. Kartoffeln waschen, vierteln und mit Öl vermengen. Auf ein Blech geben und 35 Minuten backen, bis sie goldbraun sind. Mit Salz bestreuen und heiß servieren.
        """
        let draft = RecipeTextParser.parse(text)
        #expect(draft.steps.count == 4)
        #expect(draft.steps[0].temperatureCelsius == 200)
        #expect(draft.steps[2].durationSeconds == 35 * 60)
    }

    @Test("Niedrige OCR-Konfidenz erzeugt Warnung")
    func lowConfidenceWarning() {
        let draft = RecipeTextParser.parse("Suppe\n1 l Brühe\nAlles aufkochen und 10 Minuten ziehen lassen, dann abschmecken.", source: .screenshot, ocrConfidence: 0.6)
        #expect(draft.warnings.contains(.lowConfidence(0.6)))
    }
}

@Suite("StepAnnotator")
struct StepAnnotatorTests {
    @Test("Dauer in Minuten, Sekunden, Stunden und Bereichen")
    func durations() {
        #expect(StepAnnotator.duration(in: "5 Minuten anschwitzen") == 300)
        #expect(StepAnnotator.duration(in: "30 Sek. pürieren") == 30)
        #expect(StepAnnotator.duration(in: "2 Std ruhen lassen") == 7200)
        #expect(StepAnnotator.duration(in: "10–15 Minuten backen") == 900)
        #expect(StepAnnotator.duration(in: "eine halbe Stunde ziehen lassen") == 1800)
        #expect(StepAnnotator.duration(in: "1 Handvoll Rucola unterheben") == nil)
    }

    @Test("Temperatur in Celsius und Fahrenheit")
    func temperatures() {
        #expect(StepAnnotator.temperature(in: "bei 180 °C backen") == 180)
        #expect(StepAnnotator.temperature(in: "auf 200 Grad vorheizen") == 200)
        #expect(StepAnnotator.temperature(in: "bake at 350°F") == 175)
        #expect(StepAnnotator.temperature(in: "15 Minuten köcheln") == nil)
    }
}
