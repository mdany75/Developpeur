import Foundation
import XCTest
@testable import DeveloppeurKit

/// Le contrat de « Composition lue » (1.3) entre le serveur et le module, figé dans
/// Tests/Contrats/composition.json : pour chaque exemple, les arguments de l'outil, les params exacts
/// que le serveur envoie au module (apercu avec entier pour read_composition, essayer avec entier
/// pour preview_settings avec crop) et la réponse exacte du module, copiée de la liaison simulée.
/// Ici, le serveur doit envoyer ces params et lire ces réponses (FakeLightroom les rend telles
/// quelles, des aperçus à la place des chemins) ; côté Lua, essais-composition.lua (« contrat »)
/// envoie les mêmes params au module simulé, par la liaison, et vérifie qu'il rend ces réponses. Un
/// écart de nom de champ, de forme, de valeur ou de refus fait échouer l'un des deux côtés.
final class ContratCompositionTests: XCTestCase {
    static let fichier = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Contrats").appendingPathComponent("composition.json")

    func contrat() throws -> JSONValue {
        try JSONCoding.parse(String(contentsOf: Self.fichier, encoding: .utf8))
    }

    func objet(_ valeur: JSONValue?, _ quoi: String) throws -> [String: JSONValue] {
        try XCTUnwrap(valeur?.object, "contrat : \(quoi) manque")
    }

    func exemple(_ nom: String) throws -> [String: JSONValue] {
        try objet(try contrat()["exemples"]?[nom], "exemples.\(nom)")
    }

    /// Les params envoyés au module : exactement ceux du contrat.
    func memesParams(_ envoyes: [String: JSONValue], _ attendus: JSONValue?, _ commande: String,
                     file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(JSONValue.object(envoyes), .object(try objet(attendus, "\(commande).params")),
                       "\(commande) : params envoyés \(JSONCoding.line(.object(envoyes)))", file: file, line: line)
    }

    /// La réponse du module, avec à la place de ses chemins des aperçus écrits pour l'essai.
    func reponse(_ exemple: [String: JSONValue], _ commande: String, chemins: [String: Data]) throws -> JSONValue {
        var reponse = try objet(exemple[commande]?["reponse"], "\(commande).reponse")
        for (cle, image) in chemins {
            XCTAssertNotNil(reponse[cle]?.string, "le module rend \(cle)")
            reponse[cle] = .string(TestSupport.previewFile(image))
        }
        return .object(reponse)
    }

    static func gris(_ niveau: UInt8, largeur: Int = 1344, hauteur: Int = 896) -> Data {
        TestSupport.jpeg(red: niveau, green: niveau, blue: niveau, width: largeur, height: hauteur)
    }

    // MARK: read_composition

    /// L'image entière d'une photo recadrée en 4:5, tournée de 2° : le serveur lit le cadre actuel du
    /// module (Recadrage.lire, largeur en pixels) et le redit en crop équivalent, celui qui avait été
    /// posé. Le sujet est donné : Vision n'est pas appelée.
    func testContratLire() throws {
        let exemple = try exemple("lire")
        let fake = FakeLightroom()
        fake.replies["apercu"] = try reponse(exemple, "apercu", chemins: ["chemin": Self.gris(120)])
        let tools = ToolHandler(lightroom: fake)
        let result = tools.call(name: "read_composition", arguments: try objet(exemple["read_composition"], "read_composition"))
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.commands, ["apercu"])
        try memesParams(fake.lastParams, exemple["apercu"]?["params"], "apercu")
        let info = try JSONCoding.parse(result.text)
        let actuel = try objet(info["cadre_actuel"], "cadre_actuel du serveur")
        XCTAssertEqual(actuel["aspect"]?.string, "4:5")
        XCTAssertEqual(actuel["angle"]?.double, 2)
        XCTAssertEqual(try XCTUnwrap(actuel["size"]?.double), 0.7, accuracy: 1e-3, "la taille posée, relue")
        XCTAssertEqual(try XCTUnwrap(actuel["center_x"]?.double), 0.4, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(actuel["center_y"]?.double), 0.5, accuracy: 1e-4)
        XCTAssertEqual(info["image_entiere"]?["largeur"]?.int, 6240)
        XCTAssertEqual(info["image_entiere"]?["hauteur"]?.int, 4160)
        XCTAssertEqual(info["photo"], fake.replies["apercu"]?["photo"])
        XCTAssertEqual(info["sujet"]?["source"]?.string, "donne")
        XCTAssertNotNil(info["crop"])
    }

    /// Le refus d'une photo agrandie passe tel quel.
    func testContratRefusAgrandie() throws {
        let refus = try objet(try contrat()["refus"]?["agrandie"], "refus.agrandie")
        let texte = try XCTUnwrap(refus["apercu"]?["erreur"]?.string)
        XCTAssertTrue(texte.hasPrefix("Photo agrandie"), texte)
        let fake = FakeLightroom()
        fake.errors["apercu"] = LightroomError.plugin(texte)
        let result = ToolHandler(lightroom: fake).call(name: "read_composition", arguments: try objet(refus["read_composition"], "read_composition"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, texte, "le refus du module, tel quel")
        try memesParams(fake.lastParams, refus["apercu"]?["params"], "apercu")
    }

    // MARK: preview_settings avec crop

    /// La proposition d'un 3:2 redressé de 1,4° : le serveur envoie entier, lit le cadre que Lightroom
    /// a gardé et le dessine sur l'image entière ; ce cadre redonne le crop demandé.
    func testContratProposer() throws {
        let exemple = try exemple("proposer")
        let fake = FakeLightroom()
        fake.replies["essayer"] = try reponse(exemple, "essayer", chemins: [
            "chemin": TestSupport.jpeg(red: 200, green: 200, blue: 200, width: 600, height: 400),
            "chemin_entier": Self.gris(128),
        ])
        let tools = ToolHandler(lightroom: fake)
        let result = tools.call(name: "preview_settings", arguments: try objet(exemple["preview_settings"], "preview_settings"))
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.commands, ["geometrie", "essayer"], "les grilles du recadrage (aucune ici), puis l'essai")
        try memesParams(fake.lastParams, exemple["essayer"]?["params"], "essayer")
        guard case .image(let base64, _) = result.content.first, let data = Data(base64Encoded: base64),
              let image = PreviewImages.image(data) else { return XCTFail("image attendue") }
        XCTAssertEqual(image.width, 1344, "l'image entière dessinée, pas la proposition recadrée")
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["resume_cadre"]?.string, "3:2 (format d'origine), redressé de 1,4°, 79 % de la largeur gardée")
        XCTAssertTrue(info["image"]?.string?.hasPrefix("L'image entière : le cadre proposé en pointillés") == true)
        XCTAssertNil(info["chemin_entier"])
        XCTAssertNil(info["dimensions"])
        XCTAssertNil(info["remarque_cadre"])
        // Le cadre gardé, relu par le module, redonne la demande (le dessin dit vrai).
        let module = try objet(fake.replies["essayer"]?["cadre_propose"], "essayer.reponse.cadre_propose")
        let cadre = try XCTUnwrap(Composition.Cadre(module: .object(module), dimensions: fake.replies["essayer"]?["dimensions"]))
        let crop = Composition.crop(cadre, aspectImage: 1.5, aspect: "3:2")
        XCTAssertEqual(try XCTUnwrap(crop["size"]?.double), 0.82, accuracy: 1e-3)
        XCTAssertEqual(crop["angle"]?.double, -1.4)
        XCTAssertEqual(try XCTUnwrap(crop["center_x"]?.double), 0.48, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(crop["center_y"]?.double), 0.52, accuracy: 1e-4)
        XCTAssertEqual(try XCTUnwrap(info["cadre_propose"]?["largeur"]?.double), cadre.largeur, accuracy: 1e-3)
    }

    /// L'image entière n'a pas pu se rendre : la proposition recadrée reste montrée, le cadre gardé
    /// se dit quand même (la fenêtre Claude en tire sa ligne « Cadre : … »), et la remarque du module
    /// passe telle quelle.
    func testContratProposerSansImageEntiere() throws {
        let exemple = try exemple("proposer_sans_image_entiere")
        let attendue = try objet(exemple["essayer"]?["reponse"], "essayer.reponse")
        XCTAssertNil(attendue["chemin_entier"], "le module ne rend pas de chemin_entier")
        let remarque = try XCTUnwrap(attendue["remarques"]?.array?.first?.string)
        XCTAssertTrue(remarque.hasPrefix("Image entière non rendue : "), remarque)
        let fake = FakeLightroom()
        fake.replies["essayer"] = try reponse(exemple, "essayer", chemins: [
            "chemin": TestSupport.jpeg(red: 200, green: 200, blue: 200, width: 600, height: 400),
        ])
        let result = ToolHandler(lightroom: fake).call(name: "preview_settings", arguments: try objet(exemple["preview_settings"], "preview_settings"))
        XCTAssertFalse(result.isError, result.text)
        try memesParams(fake.lastParams, exemple["essayer"]?["params"], "essayer")
        guard case .image(let base64, _) = result.content.first, let data = Data(base64Encoded: base64),
              let image = PreviewImages.image(data) else { return XCTFail("image attendue") }
        XCTAssertEqual(image.width, 600, "la proposition recadrée")
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["resume_cadre"]?.string, "3:2 (format d'origine), redressé de 1,4°, 79 % de la largeur gardée")
        XCTAssertNotNil(info["cadre_propose"])
        XCTAssertNil(info["image"], "pas d'image entière annoncée")
        XCTAssertNil(info["remarque_cadre"], "la raison est dans les remarques du module")
        XCTAssertEqual(info["remarques"]?.array?.compactMap(\.string), [remarque])
    }
}
