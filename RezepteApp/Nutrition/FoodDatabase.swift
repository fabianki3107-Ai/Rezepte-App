import Foundation

/// Ein Lebensmittel der lokalen Nährwert-Datenbank (Werte pro 100 g, Näherungen nach BLS/USDA).
struct FoodEntry: Hashable, Identifiable {
    let name: String
    /// Kleingeschriebene Schreibweisen; längere Aliase gewinnen beim Matching.
    let aliases: [String]
    let per100g: NutritionFacts
    /// g pro ml – für Volumenangaben (Öl 0,92, Milch 1,03, Mehl lose ≈ 0,55).
    let density: Double
    /// Typisches Gewicht eines Stücks (1 Ei, 1 Zwiebel …).
    let pieceGrams: Double?
    let sliceGrams: Double?
    /// Abtropfgewicht bzw. Inhalt einer typischen Dose.
    let canGrams: Double?
    let packageGrams: Double?
    let tbspGrams: Double?
    let tspGrams: Double?
    let cupGrams: Double?

    var id: String { name }

    init(
        _ name: String,
        _ aliases: [String],
        kcal: Double, p: Double, c: Double, f: Double,
        density: Double = 1.0,
        piece: Double? = nil, slice: Double? = nil, can: Double? = nil, package: Double? = nil,
        tbsp: Double? = nil, tsp: Double? = nil, cup: Double? = nil
    ) {
        self.name = name
        self.aliases = aliases.map(FoodDatabase.normalize)
        self.per100g = NutritionFacts(calories: kcal, protein: p, carbs: c, fat: f)
        self.density = density
        self.pieceGrams = piece
        self.sliceGrams = slice
        self.canGrams = can
        self.packageGrams = package
        self.tbspGrams = tbsp
        self.tspGrams = tsp
        self.cupGrams = cup
    }

    /// Lebensmittel mit nennenswertem Energiegehalt – fehlende Mengen zählen hier als Unsicherheit.
    var isCaloric: Bool { per100g.calories >= 50 }
}

/// Lokale Lebensmittel-Datenbank mit Alias-Matching für deutsche und englische Zutatennamen.
/// Kein Netzwerk, keine externe API – bewusst kompakt und erweiterbar.
enum FoodDatabase {
    /// Zutatenname → bester Treffer. Längere Aliase (z. B. "tomatenmark") schlagen kürzere ("tomaten").
    static func match(_ ingredientName: String) -> FoodEntry? {
        let normalized = normalize(ingredientName)
        guard !normalized.isEmpty else { return nil }
        let words = normalized.split(separator: " ").map(String.init)

        var best: (entry: FoodEntry, score: Int)?
        for candidate in aliasIndex {
            let score: Int
            if candidate.alias.contains(" ") {
                // Mehrwort-Alias ("grüne bohnen") muss als Phrase vorkommen
                score = normalized.contains(candidate.alias) ? candidate.alias.count + 10 : 0
            } else {
                score = words.contains(where: { wordMatches($0, alias: candidate.alias) }) ? candidate.alias.count : 0
            }
            if score > 0, score > (best?.score ?? 0) {
                best = (candidate.entry, score)
            }
        }
        return best?.entry
    }

    /// Wort-Abgleich inklusive deutscher Komposita und einfacher Pluralformen.
    private static func wordMatches(_ word: String, alias: String) -> Bool {
        if word == alias { return true }
        // Plural/Flexion: zwiebeln → zwiebel, tomaten → tomate, kartoffeln → kartoffel
        for suffix in ["n", "en", "e", "s", "er"] where word.hasSuffix(suffix) && word.count - suffix.count >= 3 {
            if String(word.dropLast(suffix.count)) == alias { return true }
        }
        // Komposita: basmatireis → reis, weizenmehl → mehl (Alias am Wortende)
        if alias.count >= 4, word.hasSuffix(alias), word.count > alias.count { return true }
        // Komposita: knoblauchzehen → knoblauch (Alias am Wortanfang)
        if alias.count >= 5, word.hasPrefix(alias), word.count > alias.count { return true }
        return false
    }

    static func normalize(_ text: String) -> String {
        var result = text.lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "-", with: " ")
        result = result.replacingMatches(of: #"[^a-z0-9 ]"#, with: " ")
        // Zubereitungs-Adjektive entfernen, die das Lebensmittel nicht ändern (ein Regex-Durchlauf)
        result = result.replacingMatches(of: fillerPattern, with: " ")
        return result.collapsingWhitespace
    }

    private static let fillerPattern: String = #"\b(?:"# + fillerWords.joined(separator: "|") + #")\b"#

    private static let fillerWords = [
        "frische", "frischer", "frisches", "frisch", "gehackte", "gehackt", "gewuerfelt", "gewuerfelte", "fein", "grob",
        "kleine", "kleiner", "kleines", "klein", "grosse", "grosser", "grosses", "gross", "mittelgrosse", "reife", "reifer",
        "geschaelte", "geschaelt", "gekochte", "gekocht", "geriebener", "geriebene", "gerieben", "gemahlene", "gemahlen",
        "getrocknete", "getrocknet", "zimmerwarme", "zimmerwarm", "weiche", "weich", "kalte", "kalt", "lauwarme", "lauwarm",
        "bio", "vegane", "vegan", "fettarme", "fettarm", "ungesuesst", "gesalzene", "ungesalzene", "bunte", "ganze", "ganz",
        "fresh", "chopped", "diced", "minced", "large", "small", "medium", "ripe", "cooked", "grated", "ground", "dried"
    ]

    private struct AliasCandidate { let alias: String; let entry: FoodEntry }

    /// Alle Aliase, längste zuerst – so gewinnt "tomatenmark" vor "tomaten".
    private static let aliasIndex: [AliasCandidate] = {
        entries.flatMap { entry in entry.aliases.map { AliasCandidate(alias: $0, entry: entry) } }
            .sorted { $0.alias.count > $1.alias.count }
    }()

    // MARK: - Daten (kcal / Eiweiß / Kohlenhydrate / Fett pro 100 g)

    static let entries: [FoodEntry] = [
        // Backen & Grundzutaten
        FoodEntry("Weizenmehl", ["mehl", "weizenmehl", "dinkelmehl", "vollkornmehl", "flour", "type 405", "type 550"], kcal: 364, p: 10.3, c: 76, f: 1.0, density: 0.55, tbsp: 10, tsp: 3, cup: 125),
        FoodEntry("Speisestärke", ["staerke", "speisestaerke", "maisstaerke", "cornstarch", "kartoffelstaerke"], kcal: 350, p: 0.3, c: 86, f: 0.1, density: 0.6, tbsp: 9, tsp: 3),
        FoodEntry("Zucker", ["zucker", "sugar", "rohrzucker", "brauner zucker", "puderzucker", "vanillezucker", "kokosbluetenzucker", "rohrohrzucker"], kcal: 400, p: 0, c: 100, f: 0, density: 0.85, package: 8, tbsp: 12, tsp: 4, cup: 200),
        FoodEntry("Erythrit", ["erythrit", "xucker", "suessstoff", "stevia"], kcal: 0, p: 0, c: 0, f: 0, density: 0.8, tbsp: 12, tsp: 4),
        FoodEntry("Honig", ["honig", "honey"], kcal: 304, p: 0.3, c: 82, f: 0, density: 1.4, tbsp: 21, tsp: 7),
        FoodEntry("Ahornsirup", ["ahornsirup", "maple syrup", "agavendicksaft", "dattelsirup", "sirup"], kcal: 270, p: 0, c: 68, f: 0, density: 1.3, tbsp: 20, tsp: 7),
        FoodEntry("Backpulver", ["backpulver", "baking powder", "natron", "baking soda", "weinsteinbackpulver"], kcal: 50, p: 0, c: 20, f: 0, density: 0.9, package: 15, tbsp: 12, tsp: 4),
        FoodEntry("Hefe", ["hefe", "trockenhefe", "yeast", "frischhefe"], kcal: 100, p: 12, c: 10, f: 1, piece: 42, package: 7, tsp: 3),
        FoodEntry("Kakaopulver", ["kakao", "kakaopulver", "cocoa", "backkakao"], kcal: 228, p: 20, c: 58, f: 14, density: 0.5, tbsp: 7, tsp: 2.5),
        FoodEntry("Zartbitterschokolade", ["schokolade", "zartbitterschokolade", "zartbitter", "chocolate", "dark chocolate", "kuvertuere", "schokodrops", "schokotropfen"], kcal: 546, p: 5, c: 46, f: 36, piece: 100, package: 100, tbsp: 15),
        FoodEntry("Vollmilchschokolade", ["vollmilchschokolade", "milchschokolade", "milk chocolate"], kcal: 535, p: 7, c: 59, f: 30, piece: 100),
        FoodEntry("Vanilleextrakt", ["vanilleextrakt", "vanille", "vanilla", "vanillemark"], kcal: 288, p: 0, c: 13, f: 0, tbsp: 13, tsp: 4),
        FoodEntry("Gelatine", ["gelatine", "gelatin", "agar"], kcal: 340, p: 85, c: 0, f: 0, piece: 1.7, package: 9),
        FoodEntry("Puddingpulver", ["puddingpulver", "vanillepuddingpulver"], kcal: 350, p: 0.5, c: 86, f: 0.2, package: 37),
        FoodEntry("Semmelbrösel", ["semmelbroesel", "paniermehl", "panko", "breadcrumbs"], kcal: 350, p: 11, c: 72, f: 2, density: 0.4, tbsp: 7, cup: 100),
        FoodEntry("Haferflocken", ["haferflocken", "oats", "oatmeal", "haferkleie"], kcal: 372, p: 13, c: 59, f: 7, density: 0.4, tbsp: 10, cup: 90),
        FoodEntry("Müsli", ["muesli", "granola", "knuspermuesli"], kcal: 420, p: 10, c: 60, f: 15, tbsp: 12, cup: 100),
        FoodEntry("Cornflakes", ["cornflakes"], kcal: 370, p: 7, c: 84, f: 1, cup: 30),

        // Fette & Öle
        FoodEntry("Butter", ["butter"], kcal: 717, p: 0.9, c: 0.1, f: 81, density: 0.91, piece: 250, package: 250, tbsp: 14, tsp: 5),
        FoodEntry("Margarine", ["margarine", "pflanzenmargarine"], kcal: 717, p: 0.2, c: 0.7, f: 80, tbsp: 14, tsp: 5),
        FoodEntry("Butterschmalz", ["butterschmalz", "ghee"], kcal: 876, p: 0, c: 0, f: 99, tbsp: 13, tsp: 4.5),
        FoodEntry("Pflanzenöl", ["oel", "olivenoel", "rapsoel", "sonnenblumenoel", "kokosoel", "sesamoel", "pflanzenoel", "bratoel", "oil", "olive oil", "coconut oil", "avocadooel", "leinoel"], kcal: 884, p: 0, c: 0, f: 100, density: 0.92, tbsp: 13.5, tsp: 4.5, cup: 215),
        FoodEntry("Mayonnaise", ["mayonnaise", "mayo"], kcal: 680, p: 1, c: 3, f: 75, tbsp: 14, tsp: 5),
        FoodEntry("Pesto", ["pesto"], kcal: 450, p: 5, c: 6, f: 45, package: 190, tbsp: 15),

        // Eier & Milchprodukte
        FoodEntry("Ei", ["ei", "eier", "egg", "eggs", "huehnerei"], kcal: 143, p: 12.6, c: 0.7, f: 9.5, piece: 55),
        FoodEntry("Eigelb", ["eigelb", "eidotter", "egg yolk"], kcal: 322, p: 16, c: 3.6, f: 27, piece: 18),
        FoodEntry("Eiklar", ["eiklar", "eiweiss", "egg white"], kcal: 52, p: 10.9, c: 0.7, f: 0.2, piece: 33),
        FoodEntry("Milch 1,5 %", ["milch", "milk", "fettarme milch", "frischmilch", "h milch"], kcal: 47, p: 3.4, c: 4.9, f: 1.5, density: 1.03, tbsp: 15, cup: 245),
        FoodEntry("Vollmilch", ["vollmilch", "whole milk"], kcal: 64, p: 3.3, c: 4.7, f: 3.5, density: 1.03, cup: 245),
        FoodEntry("Buttermilch", ["buttermilch", "buttermilk", "kefir"], kcal: 37, p: 3.5, c: 4, f: 0.5, density: 1.03, cup: 245),
        FoodEntry("Hafermilch", ["hafermilch", "haferdrink", "oat milk", "pflanzenmilch", "pflanzendrink"], kcal: 45, p: 1, c: 7, f: 1.5, density: 1.02, cup: 240),
        FoodEntry("Mandelmilch", ["mandelmilch", "mandeldrink", "almond milk"], kcal: 24, p: 0.5, c: 3, f: 1.1, cup: 240),
        FoodEntry("Sojamilch", ["sojamilch", "sojadrink", "soy milk"], kcal: 42, p: 3.3, c: 1.5, f: 1.9, cup: 240),
        FoodEntry("Kokosmilch", ["kokosmilch", "coconut milk", "kokoscreme", "coconut cream"], kcal: 197, p: 2, c: 3, f: 20, can: 400, tbsp: 15, cup: 240),
        FoodEntry("Sahne", ["sahne", "schlagsahne", "suesse sahne", "cream", "heavy cream", "kochsahne", "sahne 30"], kcal: 292, p: 2.4, c: 3.4, f: 30, density: 1.0, package: 200, tbsp: 15, cup: 240),
        FoodEntry("Saure Sahne", ["saure sahne", "sauerrahm", "sour cream"], kcal: 116, p: 2.9, c: 3.7, f: 10, package: 200, tbsp: 15),
        FoodEntry("Schmand", ["schmand", "creme fraiche", "crème fraîche", "crema"], kcal: 260, p: 2.6, c: 3.3, f: 27, package: 200, tbsp: 15),
        FoodEntry("Joghurt", ["joghurt", "naturjoghurt", "yogurt", "yoghurt"], kcal: 64, p: 3.8, c: 4.7, f: 3.5, density: 1.03, package: 150, tbsp: 15, cup: 245),
        FoodEntry("Griechischer Joghurt", ["griechischer joghurt", "greek yogurt", "sahnejoghurt"], kcal: 97, p: 9, c: 3.8, f: 5, package: 150, tbsp: 15, cup: 245),
        FoodEntry("Skyr", ["skyr"], kcal: 63, p: 11, c: 4, f: 0.2, package: 450, cup: 245),
        FoodEntry("Magerquark", ["magerquark", "quark", "speisequark", "topfen"], kcal: 70, p: 12, c: 4, f: 0.5, package: 250, tbsp: 15, cup: 240),
        FoodEntry("Hüttenkäse", ["huettenkaese", "cottage cheese", "koerniger frischkaese"], kcal: 98, p: 11, c: 3.3, f: 4.3, package: 200),
        FoodEntry("Frischkäse", ["frischkaese", "cream cheese", "doppelrahmfrischkaese"], kcal: 250, p: 6, c: 3, f: 24, package: 200, tbsp: 15),
        FoodEntry("Mascarpone", ["mascarpone"], kcal: 429, p: 4.6, c: 4.8, f: 44, package: 250, tbsp: 15),
        FoodEntry("Ricotta", ["ricotta"], kcal: 174, p: 11, c: 3, f: 13, package: 250, tbsp: 15),
        FoodEntry("Feta", ["feta", "schafskaese", "hirtenkaese"], kcal: 264, p: 14, c: 4, f: 21, piece: 200, package: 200),
        FoodEntry("Mozzarella", ["mozzarella", "burrata"], kcal: 280, p: 18, c: 2.2, f: 22, piece: 125, package: 125),
        FoodEntry("Parmesan", ["parmesan", "parmigiano", "grana padano", "pecorino", "hartkaese"], kcal: 431, p: 38, c: 4, f: 29, tbsp: 6, cup: 100),
        FoodEntry("Käse", ["kaese", "gouda", "emmentaler", "edamer", "bergkaese", "cheese", "reibekaese", "streukaese", "pizzakaese", "raclette"], kcal: 356, p: 25, c: 2, f: 27, slice: 25, tbsp: 7, cup: 110),
        FoodEntry("Cheddar", ["cheddar"], kcal: 403, p: 25, c: 1.3, f: 33, slice: 25, cup: 110),
        FoodEntry("Halloumi", ["halloumi", "grillkaese"], kcal: 321, p: 22, c: 2, f: 25, slice: 30, package: 225),
        FoodEntry("Ziegenkäse", ["ziegenkaese", "goat cheese", "ziegenfrischkaese"], kcal: 364, p: 22, c: 0.1, f: 30, package: 150),
        FoodEntry("Blauschimmelkäse", ["gorgonzola", "blauschimmelkaese", "roquefort", "blue cheese"], kcal: 350, p: 21, c: 2, f: 29),

        // Fleisch, Fisch, Ersatz
        FoodEntry("Hähnchenbrust", ["haehnchen", "haehnchenbrust", "haehnchenbrustfilet", "huehnchen", "huhn", "chicken", "chicken breast", "haehnchenfilet", "poulet"], kcal: 110, p: 23, c: 0, f: 1.5, piece: 180),
        FoodEntry("Hähnchenschenkel", ["haehnchenschenkel", "haehnchenkeule", "chicken thigh"], kcal: 180, p: 18, c: 0, f: 12, piece: 200),
        FoodEntry("Putenbrust", ["pute", "putenbrust", "truthahn", "turkey"], kcal: 105, p: 24, c: 0, f: 1, piece: 150),
        FoodEntry("Hackfleisch", ["hackfleisch", "hack", "rinderhack", "gehacktes", "gemischtes hack", "ground beef", "minced meat", "faschiertes"], kcal: 250, p: 19, c: 0, f: 20, package: 500),
        FoodEntry("Rindfleisch", ["rind", "rindfleisch", "beef", "steak", "rinderfilet", "roastbeef", "gulasch"], kcal: 200, p: 22, c: 0, f: 12, piece: 200),
        FoodEntry("Schweinefleisch", ["schwein", "schweinefleisch", "pork", "schnitzel", "schweinefilet", "kotelett"], kcal: 215, p: 19, c: 0, f: 15, piece: 150),
        FoodEntry("Lammfleisch", ["lamm", "lammfleisch", "lamb"], kcal: 250, p: 17, c: 0, f: 20),
        FoodEntry("Speck", ["speck", "bacon", "fruehstuecksspeck", "pancetta"], kcal: 450, p: 13, c: 1, f: 44, slice: 15, package: 125),
        FoodEntry("Schinken", ["schinken", "ham", "kochschinken", "prosciutto", "serrano"], kcal: 120, p: 20, c: 1, f: 4, slice: 20, package: 100),
        FoodEntry("Salami", ["salami", "chorizo", "cabanossi"], kcal: 400, p: 22, c: 1, f: 34, slice: 8, package: 100),
        FoodEntry("Bratwurst", ["wurst", "bratwurst", "sausage", "wuerstchen", "merguez"], kcal: 300, p: 13, c: 1, f: 27, piece: 100),
        FoodEntry("Lachs", ["lachs", "salmon", "lachsfilet", "raeucherlachs"], kcal: 208, p: 20, c: 0, f: 13, piece: 150, package: 200),
        FoodEntry("Thunfisch", ["thunfisch", "tuna"], kcal: 116, p: 26, c: 0, f: 1, can: 150),
        FoodEntry("Weißfisch", ["kabeljau", "cod", "seelachs", "fisch", "fischfilet", "zander", "dorsch", "pangasius"], kcal: 82, p: 18, c: 0, f: 0.7, piece: 150),
        FoodEntry("Garnelen", ["garnelen", "shrimp", "shrimps", "prawns", "krabben"], kcal: 99, p: 24, c: 0.3, f: 0.3, package: 250),
        FoodEntry("Tofu", ["tofu", "raeuchertofu"], kcal: 76, p: 8, c: 1.9, f: 4.8, piece: 200, package: 200),
        FoodEntry("Tempeh", ["tempeh"], kcal: 192, p: 20, c: 8, f: 11, package: 200),
        FoodEntry("Seitan", ["seitan", "veggie hack", "sojahack", "sojagranulat"], kcal: 150, p: 25, c: 6, f: 2, package: 200),

        // Hülsenfrüchte, Getreide, Beilagen
        FoodEntry("Linsen", ["linsen", "lentils", "rote linsen", "berglinsen", "belugalinsen", "gelbe linsen"], kcal: 352, p: 25, c: 60, f: 1, density: 0.85, can: 240, cup: 190),
        FoodEntry("Kichererbsen", ["kichererbsen", "chickpeas"], kcal: 139, p: 7, c: 22, f: 2.6, can: 265, cup: 165),
        FoodEntry("Bohnen", ["bohnen", "kidneybohnen", "schwarze bohnen", "weisse bohnen", "beans", "black beans", "cannellini"], kcal: 110, p: 8, c: 18, f: 0.5, can: 255, cup: 180),
        FoodEntry("Grüne Bohnen", ["gruene bohnen", "green beans", "prinzessbohnen"], kcal: 31, p: 1.8, c: 7, f: 0.1, package: 300),
        FoodEntry("Erbsen", ["erbsen", "peas", "tk erbsen"], kcal: 81, p: 5.4, c: 14, f: 0.4, package: 450, cup: 150),
        FoodEntry("Edamame", ["edamame"], kcal: 121, p: 11, c: 9, f: 5, cup: 155),
        FoodEntry("Reis", ["reis", "rice", "basmatireis", "jasminreis", "risottoreis", "langkornreis", "vollkornreis", "sushireis", "milchreis"], kcal: 360, p: 7, c: 79, f: 0.6, density: 0.85, package: 500, cup: 185),
        FoodEntry("Nudeln", ["nudeln", "pasta", "spaghetti", "penne", "tagliatelle", "fusilli", "linguine", "lasagneplatten", "noodles", "makkaroni", "farfalle", "rigatoni", "bandnudeln", "orzo"], kcal: 360, p: 13, c: 72, f: 1.5, density: 0.5, package: 500, cup: 100),
        FoodEntry("Vollkornnudeln", ["vollkornnudeln", "vollkornpasta", "whole wheat pasta"], kcal: 350, p: 13, c: 65, f: 2.5, package: 500),
        FoodEntry("Gnocchi", ["gnocchi"], kcal: 150, p: 4, c: 30, f: 1.5, package: 500),
        FoodEntry("Couscous", ["couscous", "bulgur", "hirse"], kcal: 370, p: 13, c: 76, f: 1, density: 0.75, cup: 175),
        FoodEntry("Quinoa", ["quinoa"], kcal: 368, p: 14, c: 64, f: 6, density: 0.75, cup: 170),
        FoodEntry("Polenta", ["polenta", "maisgriess", "griess", "hartweizengriess"], kcal: 355, p: 9, c: 74, f: 1.5, density: 0.7, cup: 160),
        FoodEntry("Kartoffeln", ["kartoffel", "kartoffeln", "potato", "potatoes", "erdaepfel", "drillinge"], kcal: 77, p: 2, c: 17, f: 0.1, piece: 120),
        FoodEntry("Süßkartoffel", ["suesskartoffel", "suesskartoffeln", "sweet potato"], kcal: 86, p: 1.6, c: 20, f: 0.1, piece: 200),
        FoodEntry("Brot", ["brot", "bread", "toast", "toastbrot", "broetchen", "baguette", "ciabatta", "fladenbrot", "pita", "sauerteigbrot"], kcal: 250, p: 8, c: 48, f: 2, piece: 60, slice: 40),
        FoodEntry("Vollkornbrot", ["vollkornbrot", "roggenbrot", "whole grain bread", "knaeckebrot"], kcal: 220, p: 8, c: 40, f: 2, slice: 45),
        FoodEntry("Tortilla", ["tortilla", "tortillas", "wrap", "wraps", "weizentortilla"], kcal: 300, p: 8, c: 50, f: 7, piece: 60),
        FoodEntry("Blätterteig", ["blaetterteig", "puff pastry", "filoteig"], kcal: 380, p: 6, c: 36, f: 25, package: 275),
        FoodEntry("Pizzateig", ["pizzateig", "hefeteig", "flammkuchenteig", "pizza dough"], kcal: 270, p: 8, c: 45, f: 5, package: 400),
        FoodEntry("Löffelbiskuit", ["loeffelbiskuit", "butterkekse", "kekse", "biscuits", "cookies"], kcal: 430, p: 7, c: 72, f: 12, piece: 8, package: 200),

        // Nüsse, Samen, Aufstriche
        FoodEntry("Mandeln", ["mandeln", "almonds", "mandelblaettchen", "mandelstifte", "gemahlene mandeln", "mandelmehl"], kcal: 579, p: 21, c: 22, f: 50, tbsp: 9, cup: 140),
        FoodEntry("Walnüsse", ["walnuesse", "walnuss", "walnuts"], kcal: 654, p: 15, c: 14, f: 65, tbsp: 8, cup: 120),
        FoodEntry("Cashews", ["cashews", "cashewkerne", "cashewnuesse"], kcal: 553, p: 18, c: 30, f: 44, tbsp: 9, cup: 140),
        FoodEntry("Erdnüsse", ["erdnuesse", "erdnuss", "peanuts"], kcal: 567, p: 26, c: 16, f: 49, tbsp: 9, cup: 145),
        FoodEntry("Haselnüsse", ["haselnuesse", "haselnuss", "hazelnuts", "gemahlene haselnuesse"], kcal: 628, p: 15, c: 17, f: 61, tbsp: 8, cup: 135),
        FoodEntry("Pistazien", ["pistazien", "pistachios"], kcal: 560, p: 20, c: 28, f: 45, tbsp: 8),
        FoodEntry("Nüsse", ["nuesse", "nuts", "nussmix", "studentenfutter", "pekannuesse", "paranuesse", "macadamia"], kcal: 600, p: 18, c: 18, f: 55, tbsp: 9, cup: 130),
        FoodEntry("Chiasamen", ["chiasamen", "chia", "chia seeds"], kcal: 486, p: 17, c: 42, f: 31, tbsp: 12, tsp: 4),
        FoodEntry("Leinsamen", ["leinsamen", "flaxseed", "geschrotete leinsamen"], kcal: 534, p: 18, c: 29, f: 42, tbsp: 10, tsp: 3.5),
        FoodEntry("Sesam", ["sesam", "sesame", "sesamsamen"], kcal: 573, p: 18, c: 23, f: 50, tbsp: 9, tsp: 3),
        FoodEntry("Sonnenblumenkerne", ["sonnenblumenkerne", "sunflower seeds", "pinienkerne"], kcal: 584, p: 21, c: 20, f: 51, tbsp: 10),
        FoodEntry("Kürbiskerne", ["kuerbiskerne", "pumpkin seeds"], kcal: 559, p: 30, c: 11, f: 49, tbsp: 10),
        FoodEntry("Kokosraspel", ["kokosraspel", "kokosflocken", "kokoschips", "shredded coconut"], kcal: 660, p: 7, c: 24, f: 65, tbsp: 7),
        FoodEntry("Erdnussbutter", ["erdnussbutter", "erdnussmus", "peanut butter"], kcal: 590, p: 25, c: 20, f: 50, tbsp: 16, tsp: 5),
        FoodEntry("Mandelmus", ["mandelmus", "almond butter", "cashewmus", "nussmus", "haselnussmus"], kcal: 614, p: 21, c: 10, f: 55, tbsp: 16, tsp: 5),
        FoodEntry("Tahini", ["tahini", "tahin", "sesammus"], kcal: 595, p: 17, c: 21, f: 54, tbsp: 15),
        FoodEntry("Nuss-Nougat-Creme", ["nutella", "nuss nougat creme", "nuss nougat", "schokocreme"], kcal: 540, p: 6, c: 57, f: 31, tbsp: 18),
        FoodEntry("Hummus", ["hummus", "humus"], kcal: 177, p: 8, c: 14, f: 10, package: 200, tbsp: 15),
        FoodEntry("Marmelade", ["marmelade", "konfituere", "jam", "fruchtaufstrich", "gelee"], kcal: 250, p: 0.3, c: 60, f: 0, tbsp: 20, tsp: 7),

        // Obst
        FoodEntry("Banane", ["banane", "bananen", "banana", "bananas"], kcal: 89, p: 1.1, c: 23, f: 0.3, piece: 120),
        FoodEntry("Apfel", ["apfel", "aepfel", "apple", "apples"], kcal: 52, p: 0.3, c: 14, f: 0.2, piece: 150),
        FoodEntry("Birne", ["birne", "birnen", "pear"], kcal: 57, p: 0.4, c: 15, f: 0.1, piece: 170),
        FoodEntry("Orange", ["orange", "orangen", "apfelsine", "mandarine", "mandarinen", "clementine"], kcal: 47, p: 0.9, c: 12, f: 0.1, piece: 150),
        FoodEntry("Zitrone", ["zitrone", "zitronen", "lemon", "zitronensaft", "lemon juice", "zitronenabrieb"], kcal: 29, p: 1.1, c: 9, f: 0.3, piece: 60, tbsp: 15, tsp: 5),
        FoodEntry("Limette", ["limette", "limetten", "lime", "limettensaft"], kcal: 30, p: 0.7, c: 11, f: 0.2, piece: 45, tbsp: 15),
        FoodEntry("Beeren", ["beeren", "berries", "beerenmix", "tk beeren", "johannisbeeren", "brombeeren"], kcal: 45, p: 0.9, c: 10, f: 0.4, package: 300, cup: 140),
        FoodEntry("Erdbeeren", ["erdbeeren", "erdbeere", "strawberries"], kcal: 32, p: 0.7, c: 7.7, f: 0.3, piece: 15, cup: 150),
        FoodEntry("Blaubeeren", ["blaubeeren", "heidelbeeren", "blueberries"], kcal: 57, p: 0.7, c: 14, f: 0.3, package: 125, cup: 150),
        FoodEntry("Himbeeren", ["himbeeren", "raspberries"], kcal: 52, p: 1.2, c: 12, f: 0.7, package: 125, cup: 125),
        FoodEntry("Trauben", ["trauben", "weintrauben", "grapes"], kcal: 69, p: 0.7, c: 18, f: 0.2, cup: 150),
        FoodEntry("Mango", ["mango", "mangos"], kcal: 60, p: 0.8, c: 15, f: 0.4, piece: 300),
        FoodEntry("Ananas", ["ananas", "pineapple"], kcal: 50, p: 0.5, c: 13, f: 0.1, piece: 900, can: 340),
        FoodEntry("Pfirsich", ["pfirsich", "pfirsiche", "nektarine", "aprikose", "aprikosen", "peach"], kcal: 40, p: 0.9, c: 10, f: 0.3, piece: 150),
        FoodEntry("Kiwi", ["kiwi", "kiwis"], kcal: 61, p: 1.1, c: 15, f: 0.5, piece: 75),
        FoodEntry("Avocado", ["avocado", "avocados"], kcal: 160, p: 2, c: 9, f: 15, piece: 140),
        FoodEntry("Datteln", ["datteln", "dattel", "dates", "medjool"], kcal: 282, p: 2.5, c: 75, f: 0.4, piece: 8),
        FoodEntry("Rosinen", ["rosinen", "sultaninen", "raisins", "cranberries getrocknet", "trockenfruechte"], kcal: 299, p: 3, c: 79, f: 0.5, tbsp: 10, cup: 150),

        // Gemüse & Kräuter
        FoodEntry("Tomaten", ["tomate", "tomaten", "tomato", "tomatoes", "cocktailtomaten", "kirschtomaten", "cherrytomaten", "rispentomaten"], kcal: 18, p: 0.9, c: 3.9, f: 0.2, piece: 120, cup: 150),
        FoodEntry("Dosentomaten", ["dosentomaten", "stueckige tomaten", "passierte tomaten", "passata", "tomaten aus der dose", "gehackte tomaten", "pizzatomaten", "tomatensauce", "tomatensosse", "crushed tomatoes"], kcal: 24, p: 1.2, c: 4, f: 0.2, can: 400, package: 500, cup: 240),
        FoodEntry("Tomatenmark", ["tomatenmark", "tomato paste"], kcal: 82, p: 4.3, c: 14, f: 0.5, tbsp: 15, tsp: 5),
        FoodEntry("Zwiebel", ["zwiebel", "zwiebeln", "onion", "onions", "rote zwiebel", "gemuesezwiebel"], kcal: 40, p: 1.1, c: 9, f: 0.1, piece: 90),
        FoodEntry("Schalotte", ["schalotte", "schalotten", "shallot"], kcal: 72, p: 2.5, c: 17, f: 0.1, piece: 25),
        FoodEntry("Frühlingszwiebel", ["fruehlingszwiebel", "fruehlingszwiebeln", "lauchzwiebel", "lauchzwiebeln", "scallions", "spring onion"], kcal: 32, p: 1.8, c: 7, f: 0.2, piece: 15),
        FoodEntry("Knoblauch", ["knoblauch", "garlic", "knoblauchzehe", "knoblauchzehen"], kcal: 149, p: 6.4, c: 33, f: 0.5, piece: 3, tsp: 3),
        FoodEntry("Ingwer", ["ingwer", "ginger"], kcal: 80, p: 1.8, c: 18, f: 0.8, piece: 20, tbsp: 6, tsp: 2),
        FoodEntry("Paprika", ["paprika", "paprikaschote", "bell pepper", "spitzpaprika", "rote paprika", "gelbe paprika"], kcal: 31, p: 1, c: 6, f: 0.3, piece: 150),
        FoodEntry("Chili", ["chili", "chilischote", "peperoni", "jalapeno", "jalapenos"], kcal: 40, p: 2, c: 9, f: 0.2, piece: 10),
        FoodEntry("Zucchini", ["zucchini", "courgette"], kcal: 17, p: 1.2, c: 3, f: 0.3, piece: 200),
        FoodEntry("Aubergine", ["aubergine", "auberginen", "eggplant"], kcal: 25, p: 1, c: 6, f: 0.2, piece: 300),
        FoodEntry("Gurke", ["gurke", "gurken", "salatgurke", "cucumber"], kcal: 15, p: 0.7, c: 3.6, f: 0.1, piece: 400),
        FoodEntry("Karotte", ["karotte", "karotten", "moehre", "moehren", "carrot", "carrots", "rueebli"], kcal: 41, p: 0.9, c: 10, f: 0.2, piece: 70),
        FoodEntry("Brokkoli", ["brokkoli", "broccoli"], kcal: 34, p: 2.8, c: 7, f: 0.4, piece: 400),
        FoodEntry("Blumenkohl", ["blumenkohl", "cauliflower"], kcal: 25, p: 1.9, c: 5, f: 0.3, piece: 600),
        FoodEntry("Spinat", ["spinat", "blattspinat", "spinach", "babyspinat"], kcal: 23, p: 2.9, c: 3.6, f: 0.4, package: 450, cup: 30),
        FoodEntry("Grünkohl", ["gruenkohl", "kale", "mangold", "pak choi"], kcal: 45, p: 4, c: 8, f: 0.9, package: 300),
        FoodEntry("Salat", ["salat", "kopfsalat", "eisbergsalat", "romanasalat", "lettuce", "feldsalat", "rucola", "arugula", "blattsalat"], kcal: 18, p: 1.5, c: 3, f: 0.3, piece: 300, cup: 50),
        FoodEntry("Champignons", ["champignons", "champignon", "pilze", "mushrooms", "kraeuterseitlinge", "shiitake", "steinpilze"], kcal: 22, p: 3.1, c: 3.3, f: 0.3, piece: 20, package: 250),
        FoodEntry("Mais", ["mais", "corn", "maiskoerner", "zuckermais"], kcal: 86, p: 3.3, c: 19, f: 1.2, can: 285, cup: 165),
        FoodEntry("Lauch", ["lauch", "porree", "leek"], kcal: 31, p: 1.5, c: 6, f: 0.3, piece: 150),
        FoodEntry("Sellerie", ["sellerie", "staudensellerie", "knollensellerie", "celery"], kcal: 16, p: 0.7, c: 3, f: 0.2, piece: 40),
        FoodEntry("Weißkohl", ["weisskohl", "kohl", "spitzkohl", "cabbage", "wirsing", "chinakohl"], kcal: 25, p: 1.3, c: 6, f: 0.1, piece: 1000),
        FoodEntry("Rotkohl", ["rotkohl", "blaukraut", "red cabbage"], kcal: 31, p: 1.4, c: 7, f: 0.2, piece: 1000),
        FoodEntry("Spargel", ["spargel", "asparagus"], kcal: 20, p: 2.2, c: 3.9, f: 0.1, package: 500),
        FoodEntry("Kürbis", ["kuerbis", "hokkaido", "butternut", "pumpkin"], kcal: 26, p: 1, c: 6.5, f: 0.1, piece: 1200),
        FoodEntry("Rote Bete", ["rote bete", "rote beete", "beetroot"], kcal: 43, p: 1.6, c: 10, f: 0.2, piece: 100, package: 500),
        FoodEntry("Radieschen", ["radieschen", "rettich", "kohlrabi", "fenchel", "radish"], kcal: 20, p: 1, c: 4, f: 0.1, piece: 10),
        FoodEntry("Oliven", ["oliven", "olives"], kcal: 115, p: 0.8, c: 6, f: 11, piece: 4, can: 150),
        FoodEntry("Kräuter", ["kraeuter", "petersilie", "basilikum", "koriander", "dill", "schnittlauch", "minze", "thymian", "rosmarin", "oregano", "salbei", "parsley", "basil", "cilantro", "herbs", "lorbeerblatt", "lorbeer"], kcal: 36, p: 3, c: 6, f: 0.8, piece: 0.5, tbsp: 4, tsp: 1.5),

        // Würzen, Saucen, Flüssiges
        FoodEntry("Salz", ["salz", "salt", "meersalz", "fleur de sel"], kcal: 0, p: 0, c: 0, f: 0, tbsp: 18, tsp: 6),
        FoodEntry("Pfeffer", ["pfeffer", "pepper", "chiliflocken", "cayennepfeffer"], kcal: 250, p: 10, c: 64, f: 3, tbsp: 7, tsp: 2.3),
        FoodEntry("Gewürze", ["gewuerz", "gewuerze", "paprikapulver", "kreuzkuemmel", "cumin", "curry", "currypulver", "kurkuma", "zimt", "cinnamon", "muskat", "garam masala", "koriandersamen", "gewuerzmischung", "spices", "senfkoerner", "piment", "kardamom", "nelken", "fenchelsamen", "chilipulver", "knoblauchpulver", "zwiebelpulver"], kcal: 300, p: 10, c: 50, f: 10, tbsp: 7, tsp: 2.5),
        FoodEntry("Brühe", ["bruehe", "gemuesebruehe", "huehnerbruehe", "rinderbruehe", "fond", "broth", "stock", "bouillon"], kcal: 5, p: 0.5, c: 0.5, f: 0.1, piece: 10, tbsp: 12, tsp: 4, cup: 240),
        FoodEntry("Sojasauce", ["sojasauce", "sojasosse", "soy sauce", "tamari", "fischsauce", "worcestersauce", "teriyaki"], kcal: 53, p: 8, c: 5, f: 0, density: 1.1, tbsp: 16, tsp: 5.5),
        FoodEntry("Essig", ["essig", "vinegar", "weissweinessig", "apfelessig", "reisessig"], kcal: 20, p: 0, c: 0.6, f: 0, tbsp: 15, tsp: 5),
        FoodEntry("Balsamico", ["balsamico", "balsamic"], kcal: 88, p: 0.5, c: 17, f: 0, tbsp: 16, tsp: 5),
        FoodEntry("Senf", ["senf", "mustard", "dijonsenf"], kcal: 66, p: 4, c: 6, f: 3, tbsp: 15, tsp: 5),
        FoodEntry("Ketchup", ["ketchup", "bbq sauce", "barbecuesauce", "sriracha", "chilisauce", "sweet chili"], kcal: 100, p: 1, c: 24, f: 0.2, tbsp: 15, tsp: 5),
        FoodEntry("Wein", ["wein", "weisswein", "rotwein", "wine", "sekt", "prosecco"], kcal: 83, p: 0, c: 2.6, f: 0, cup: 240),
        FoodEntry("Bier", ["bier", "beer"], kcal: 43, p: 0.5, c: 3.6, f: 0, can: 500),
        FoodEntry("Wasser", ["wasser", "water", "mineralwasser", "eiswuerfel", "kaffee", "coffee", "espresso", "tee", "tea"], kcal: 0, p: 0, c: 0, f: 0, cup: 240),
        FoodEntry("Fruchtsaft", ["saft", "orangensaft", "apfelsaft", "juice", "orange juice"], kcal: 45, p: 0.5, c: 10, f: 0.1, cup: 240),

        // Sonstiges
        FoodEntry("Proteinpulver", ["proteinpulver", "whey", "protein powder", "eiweisspulver", "scoop"], kcal: 380, p: 75, c: 8, f: 5, piece: 30, tbsp: 15),
        FoodEntry("Chips", ["chips", "kartoffelchips", "nachos", "tortillachips"], kcal: 540, p: 6, c: 50, f: 35, package: 150),
        FoodEntry("Popcorn", ["popcorn", "popcornmais"], kcal: 380, p: 12, c: 75, f: 4, cup: 10)
    ]
}
