import Foundation
import XCTest
@testable import DeveloppeurKit

/// Le contrat de « Je le fais » (1.3) entre le serveur et le module, figé dans
/// Tests/Contrats/je-le-fais.json : pour chaque exemple, les arguments de l'outil, les params exacts
/// que le serveur envoie au module (essayer pour preview_settings avec my_turn, apercu pour
/// view_photo avec compare = claude_version) et la réponse exacte du module, copiée de la liaison
/// simulée. Ici, le serveur doit envoyer ces params et lire ces réponses (FakeLightroom les rend
/// telles quelles) ; côté Lua, essais-jelefais.lua (« contrat avec le serveur ») envoie les mêmes
/// params au module simulé, par la liaison, et vérifie qu'il rend ces réponses. Un écart de nom de
/// champ, de forme (tableau ou objet, texte ou nombre), de valeur ou de refus fait échouer l'un des
/// deux côtés.
final class ContratJeLeFaisTests: XCTestCase {
    static let fichier = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Contrats").appendingPathComponent("je-le-fais.json")

    let fine = JeLeFais.espaceMilliers, insecable = JeLeFais.espaceUnite

    func contrat() throws -> JSONValue {
        try JSONCoding.parse(String(contentsOf: Self.fichier, encoding: .utf8))
    }

    func objet(_ valeur: JSONValue?, _ quoi: String) throws -> [String: JSONValue] {
        try XCTUnwrap(valeur?.object, "contrat : \(quoi) manque")
    }

    func exemple(_ nom: String) throws -> [String: JSONValue] {
        try objet(try contrat()["exemples"]?[nom], "exemples.\(nom)")
    }

    /// Les params envoyés au module : exactement ceux du contrat. Seule `cles` (apercu : les réglages
    /// relus) peut en nommer plus : un réglage ajouté au catalogue ne change pas « Je le fais ».
    func memesParams(_ envoyes: [String: JSONValue], _ attendus: JSONValue?, _ commande: String,
                     file: StaticString = #filePath, line: UInt = #line) throws {
        var envoyes = envoyes
        var attendus = try objet(attendus, "\(commande).params")
        if let cles = attendus.removeValue(forKey: "cles")?.array {
            let envoyees = Set(envoyes.removeValue(forKey: "cles")?.array?.compactMap(\.string) ?? [])
            XCTAssertTrue(Set(cles.compactMap(\.string)).isSubset(of: envoyees), "\(commande) : cles du contrat non envoyées", file: file, line: line)
        }
        XCTAssertEqual(JSONValue.object(envoyes), .object(attendus),
                       "\(commande) : params envoyés \(JSONCoding.line(.object(envoyes)))", file: file, line: line)
    }

    /// Un faux module qui répond comme le contrat : la réponse d'essayer telle quelle ; celle
    /// d'apercu avec, à la place des chemins, deux aperçus (la version de Claude, puis celle de
    /// l'utilisateur, plus claire).
    func module(_ exemple: [String: JSONValue], claude: UInt8 = 100, vous: UInt8 = 140) throws -> FakeLightroom {
        let fake = FakeLightroom()
        fake.replies["essayer"] = try XCTUnwrap(exemple["essayer"]?["reponse"], "contrat : essayer.reponse manque")
        let apercu = try objet(exemple["apercu"]?["reponse"], "apercu.reponse")
        XCTAssertNotNil(apercu["chemin"]?.string, "le module rend chemin (celle de l'utilisateur)")
        XCTAssertNotNil(apercu["chemin_avant"]?.string, "le module rend chemin_avant (la version de Claude)")
        fake.onSend = { [unowned fake] commande, _ in
            guard commande == "apercu" else { return }
            var reponse = apercu
            reponse["chemin"] = .string(TestSupport.previewFile(TestSupport.jpeg(red: vous, green: vous, blue: vous, width: 600, height: 400)))
            reponse["chemin_avant"] = .string(TestSupport.previewFile(TestSupport.jpeg(red: claude, green: claude, blue: claude, width: 600, height: 400)))
            fake.replies["apercu"] = .object(reponse)
        }
        return fake
    }

    func arguments(_ exemple: [String: JSONValue], _ outil: String) throws -> [String: JSONValue] {
        try objet(exemple[outil], outil)
    }

    func ligne(_ liste: [JSONValue], _ cle: String) throws -> [String: JSONValue] {
        try XCTUnwrap(liste.first { $0["cle"]?.string == cle }?.object, "pas de ligne \(cle)")
    }

    // MARK: RAW

    /// Le RAF de l'exemple : la liste à faire tirée des changements du module, puis la comparaison
    /// tirée de son exercice (noms de champs, Look par son nom, table « changée autrement », clés
    /// dérivées, cadre en clés séparées, listes {depart, vous}, restent en clés de Lightroom).
    func testContratRaw() throws {
        let exemple = try exemple("raw")
        let fake = try module(exemple)
        let tools = ToolHandler(lightroom: fake)

        // preview_settings avec my_turn → essayer.
        let tour = tools.call(name: "preview_settings", arguments: try arguments(exemple, "preview_settings"))
        XCTAssertFalse(tour.isError, tour.text)
        XCTAssertEqual(fake.commands, ["essayer"])
        try memesParams(fake.lastParams, exemple["essayer"]?["params"], "essayer")
        XCTAssertFalse(tour.porteUneImage)
        let reponse = try objet(exemple["essayer"]?["reponse"], "essayer.reponse")
        let info = try JSONCoding.parse(tour.text)
        let faire = info["a_faire"]?.array ?? []
        XCTAssertEqual(faire.compactMap { $0["cle"]?.string }, ["Temperature", "Exposure2012", "Contrast2012", "Vibrance", "ToneCurvePV2012"],
                       "tous les changements du module, dans l'ordre des panneaux")
        XCTAssertEqual(try ligne(faire, "Temperature")["texte"],
                       .string("Réglages de base › Balance des blancs › Température : 5\(fine)350\(insecable)K → 5\(fine)600\(insecable)K"),
                       "raw de la réponse : des kelvins")
        XCTAssertEqual(try ligne(faire, "Temperature")["apres"], 5600, "la valeur brute du module")
        XCTAssertEqual(try ligne(faire, "Exposure2012")["texte"], "Réglages de base › Tonalité › Exposition : 0 → +0,35")
        XCTAssertEqual(try ligne(faire, "ToneCurvePV2012")["texte"], "Courbe des tonalités › Courbe par points › RVB : linéaire → 3 points",
                       "le résumé de la table, tel que le module l'écrit")
        XCTAssertEqual(info["instantane"], reponse["exercice"]?["instantane"])
        for cle in ["photo", "mode", "etape"] { XCTAssertEqual(info[cle], reponse[cle], cle) }
        XCTAssertNil(info["remarques"], "aucune remarque du module")

        // view_photo avec compare = claude_version → apercu.
        let vue = tools.call(name: "view_photo", arguments: try arguments(exemple, "view_photo"))
        XCTAssertFalse(vue.isError, vue.text)
        XCTAssertEqual(fake.commands, ["essayer", "apercu"])
        try memesParams(fake.lastParams, exemple["apercu"]?["params"], "apercu")
        XCTAssertTrue(vue.porteUneImage)
        let module = try objet(exemple["apercu"]?["reponse"], "apercu.reponse")
        let lue = try JSONCoding.parse(vue.text)
        XCTAssertEqual(lue["image"], "À gauche ma version (Claude), à droite la vôtre.")
        XCTAssertTrue(lue["bilan"]?["depuis"]?.string?.hasPrefix("ma version") == true)
        XCTAssertNil(lue["chemin"])
        XCTAssertNil(lue["chemin_avant"])
        XCTAssertEqual(lue["photo"], module["photo"])
        XCTAssertEqual(lue["corrections_utilisateur"], module["corrections_utilisateur"], "passé tel quel")

        let exercice = try objet(lue["exercice"], "exercice enrichi")
        let duModule = try objet(module["exercice"], "apercu.reponse.exercice")
        // Ce que le serveur n'enrichit pas passe tel quel : instantane, le, listes {depart, vous},
        // restent, rien_change.
        for (cle, valeur) in duModule where cle != "ecarts" {
            XCTAssertEqual(exercice[cle], valeur, "exercice.\(cle) passé tel quel")
        }
        XCTAssertEqual(exercice["listes"]?["masques"]?["vous"], 2)
        let ecarts = exercice["ecarts"]?.array ?? []
        XCTAssertEqual(ecarts.compactMap { $0["cle"]?.string },
                       ["Look", "WhiteBalance", "Temperature", "Exposure2012", "Contrast2012", "Clarity2012", "Vibrance", "ToneCurvePV2012", "Crop"],
                       "ordre des panneaux ; HasCrop et ToneCurveName2012 (dérivés) retirés ; le cadre en une ligne")
        let sortes = Dictionary(uniqueKeysWithValues: ecarts.compactMap { e in e["cle"]?.string.map { ($0, e["sorte"]?.string ?? "") } })
        XCTAssertEqual(sortes, [
            "Look": "ajoute", "WhiteBalance": "comme_claude", "Temperature": "comme_claude", "Exposure2012": "plus_fort",
            "Contrast2012": "oublie", "Clarity2012": "ajoute", "Vibrance": "oublie", "ToneCurvePV2012": "autre_choix", "Crop": "ajoute",
        ])
        XCTAssertEqual(try ligne(ecarts, "Look")["texte"],
                       "Réglages de base › Profil › Profil (Look) : départ Adobe Color, Claude Adobe Color, vous aucune — ajouté par vous (Claude n'y touchait pas)",
                       "la Look par son nom")
        XCTAssertEqual(try ligne(ecarts, "WhiteBalance")["texte"],
                       "Réglages de base › Balance des blancs › Préréglage : départ Telle quelle, Claude Personnalisée, vous Personnalisée — comme Claude")
        XCTAssertEqual(try ligne(ecarts, "Temperature")["texte"],
                       .string("Réglages de base › Balance des blancs › Température : départ 5\(fine)350\(insecable)K, Claude 5\(fine)600\(insecable)K, vous 5\(fine)650\(insecable)K — comme Claude"),
                       "raw d'après echelle_temperature : la tolérance d'un RAW")
        XCTAssertEqual(try ligne(ecarts, "ToneCurvePV2012")["texte"],
                       "Courbe des tonalités › Courbe par points › RVB : Claude changée, vous changée autrement — un autre choix que Claude")
        let cadre = try ligne(ecarts, "Crop")
        XCTAssertEqual(cadre["cles"], ["CropLeft", "CropRight", "CropTop"])
        XCTAssertEqual(cadre["vous"]?["CropRight"]?.double, 0.95)
        XCTAssertEqual(cadre["texte"], .string("Recadrage › Cadre : départ sans rognage ; Claude sans rognage ; vous rogné à gauche 5\(insecable)%, "
            + "en haut 2\(insecable)%, à droite 5\(insecable)% — ajouté par vous (Claude n'y touchait pas)"))
        XCTAssertEqual(exercice["comme_claude"], ["Préréglage", "Température"])
        XCTAssertEqual(exercice["resume"], "9 réglages comparés : 2 comme Claude, 1 plus fort, 2 oubliés, 3 ajoutés, 1 autre choix.")
        let aSavoir = try XCTUnwrap(exercice["a_savoir_exercice"]?.string, "restent n'est pas vide")
        XCTAssertTrue(aSavoir.contains("(masques)"), "restent en clés de Lightroom, dit en français : \(aSavoir)")
        XCTAssertEqual(exercice["ecart_principal"]?["visible"], true)
        XCTAssertEqual(exercice["ecart_principal"]?["mesure"], "exposition")
        XCTAssertEqual(exercice["ecart_principal"]?["reglage"]?["cle"], "Exposure2012")
    }

    // MARK: JPEG

    /// Le JPEG de l'exemple : la balance relative, sous Temperature et Tint dans les changements
    /// comme dans les écarts (jamais IncrementalTemperature), raw faux des deux côtés.
    func testContratJpeg() throws {
        let exemple = try exemple("jpeg")
        let fake = try module(exemple)
        let tools = ToolHandler(lightroom: fake)

        let tour = tools.call(name: "preview_settings", arguments: try arguments(exemple, "preview_settings"))
        XCTAssertFalse(tour.isError, tour.text)
        try memesParams(fake.lastParams, exemple["essayer"]?["params"], "essayer")
        let faire = try JSONCoding.parse(tour.text)["a_faire"]?.array ?? []
        XCTAssertEqual(faire.compactMap { $0["cle"]?.string }, ["Temperature", "Tint"])
        XCTAssertEqual(try ligne(faire, "Temperature")["texte"], "Réglages de base › Balance des blancs › Température : 0 → +12",
                       "raw faux : relative")
        XCTAssertEqual(try ligne(faire, "Tint")["a"], "−4")

        let vue = tools.call(name: "view_photo", arguments: try arguments(exemple, "view_photo"))
        XCTAssertFalse(vue.isError, vue.text)
        try memesParams(fake.lastParams, exemple["apercu"]?["params"], "apercu")
        let exercice = try objet(try JSONCoding.parse(vue.text)["exercice"], "exercice enrichi")
        let ecarts = exercice["ecarts"]?.array ?? []
        XCTAssertEqual(ecarts.compactMap { $0["cle"]?.string }, ["WhiteBalance", "Temperature", "Tint", "Shadows2012"])
        XCTAssertEqual(ecarts.compactMap { $0["sorte"]?.string }, ["comme_claude", "plus_fort", "oublie", "ajoute"])
        XCTAssertEqual(try ligne(ecarts, "Temperature")["texte"],
                       "Réglages de base › Balance des blancs › Température : départ 0, Claude +12, vous +20 — plus fort que Claude",
                       "raw faux d'après echelle_temperature : relative, tolérance de 3")
        XCTAssertEqual(exercice["listes"], try objet(exemple["apercu"]?["reponse"]?["exercice"], "exercice")["listes"])
        XCTAssertNil(exercice["a_savoir_exercice"], "restent est vide")
        XCTAssertEqual(exercice["ecart_principal"]?["reglage"]?["cle"], "Shadows2012", "plus clair : les Ombres relevées l'expliquent")
    }

    // MARK: Refus

    /// Les refus du module passent tels quels, et les params qui les causent sont ceux du contrat.
    func testContratRefus() throws {
        let refus = try objet(try contrat()["refus"], "refus")
        let rien = try objet(refus["rien_a_faire"], "refus.rien_a_faire")
        let fake = FakeLightroom()
        let texte = try XCTUnwrap(rien["essayer"]?["erreur"]?.string)
        XCTAssertTrue(texte.hasPrefix("Rien à faire"), texte)
        fake.errors["essayer"] = LightroomError.plugin(texte)
        let tour = ToolHandler(lightroom: fake).call(name: "preview_settings", arguments: try arguments(rien, "preview_settings"))
        XCTAssertTrue(tour.isError)
        XCTAssertEqual(tour.text, texte, "le refus du module, tel quel")
        try memesParams(fake.lastParams, rien["essayer"]?["params"], "essayer")
        XCTAssertNil(fake.lastParams["raison"], "sans step_name, pas de raison")

        let sans = try objet(refus["sans_version"], "refus.sans_version")
        let message = try XCTUnwrap(sans["apercu"]?["erreur"]?.string)
        XCTAssertTrue(message.contains("my_turn = true"), message)
        fake.errors["apercu"] = LightroomError.plugin(message)
        let vue = ToolHandler(lightroom: fake).call(name: "view_photo", arguments: try arguments(sans, "view_photo"))
        XCTAssertTrue(vue.isError)
        XCTAssertEqual(vue.text, message)
        try memesParams(fake.lastParams, sans["apercu"]?["params"], "apercu")
    }
}
