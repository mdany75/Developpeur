import CoreGraphics
import ImageIO
import XCTest
@testable import DeveloppeurKit

/// Livraison : JPEG XL, AVIF, PSD et sortie HDR, poids maximal, filigrane, réimportation, dossier
/// choisi dans une fenêtre, noms exacts, aperçus dynamiques, livraisons types lues dans les
/// services Disque dur ; ni Photoshop ni galeries.
final class Version25Tests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!
    var dossier: URL!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
        dossier = TestSupport.temporaryDirectory()
        tools.filigranes = FiligranesUtilisateur(folder: dossier.appendingPathComponent("Watermarks"))
        tools.filenameTemplates = FilenameTemplates(folder: dossier.appendingPathComponent("Filename Templates"))
        tools.preferencesLightroom = dossier.appendingPathComponent("absent.plist")
        fake.onSend = { [unowned fake] command, params in
            guard command == "exporter" else { return }
            let fichiers: [JSONValue] = (params["photos"]?.array ?? []).compactMap(\.int).map { id in
                ["photo": ["id": .number(Double(id)), "fichier": .string("DSCF\(id).RAF")], "chemin": .string("/Volumes/Photos/Web/DSCF\(id).avif"),
                 "octets": 1000]
            }
            fake?.replies["exporter"] = ["dossier": "/Volumes/Photos/Web", "fichiers": .array(fichiers)]
        }
    }

    private func livrer(_ arguments: [String: JSONValue]) -> ToolResult {
        tools.call(name: "export_photos", arguments: arguments)
    }

    private func reglagesEnvoyes() throws -> JSONValue {
        try XCTUnwrap(fake.calls.last { $0.command == "exporter" }?.params["reglages"])
    }

    // MARK: Formats et HDR

    func testAvifHdrGoesToTheModuleWithItsColorSpaceAndCompatibility() throws {
        let result = livrer(["photo_ids": [1], "folder": "/Volumes/Photos/Web", "format": "avif", "hdr": true, "quality": 75,
                             "maximize_compatibility": false])
        XCTAssertFalse(result.isError, result.text)
        let r = try reglagesEnvoyes()
        XCTAssertEqual(r["format"]?.string, "AVIF")
        XCTAssertEqual(r["hdr"]?.bool, true)
        XCTAssertEqual(r["espace"]?.string, "p3_hdr", "HDR P3 par défaut")
        XCTAssertEqual(r["qualite"]?.int, 75)
        XCTAssertEqual(r["compatibilite"]?.bool, false)
        let resume = try JSONCoding.parse(result.text)["reglages"]?.string ?? ""
        XCTAssertTrue(resume.hasPrefix("AVIF, HDR, qualité 75, HDR P3"), resume)

        XCTAssertFalse(livrer(["photo_ids": [1], "folder": "/x", "format": "jxl", "hdr": true, "color_space": "rec2020", "lossless": true]).isError)
        let jxl = try reglagesEnvoyes()
        XCTAssertEqual(jxl["espace"]?.string, "Rec2020_hdr")
        XCTAssertEqual(jxl["sans_perte"]?.bool, true)
    }

    func testHdrRulesFollowLightroom() {
        let avant = fake.calls.count
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "hdr": true, "color_space": "rec2020"]).text.contains("pas en JPEG"),
                      "HDR Rec. 2020 : pas en JPEG (relevé dans Lightroom)")
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "hdr": true, "color_space": "adobe_rgb"]).isError)
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "format": "original", "hdr": true]).isError)
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "maximize_compatibility": true, "hdr": true]).text.contains("carte de gain"),
                      "le JPEG HDR a toujours sa carte de gain")
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "format": "tiff", "bit_depth": 32]).text.contains("HDR seulement"))
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "format": "avif", "bit_depth": 16]).isError, "AVIF : 10 bits imposés")
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "format": "png", "hdr": true, "bit_depth": 8]).isError)
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "format": "tiff", "quality": 80]).isError, "pas de qualité en TIFF")
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "lossless": true]).isError, "sans perte : JPEG XL seulement")
        XCTAssertEqual(fake.calls.filter { $0.command == "exporter" }.count, fake.calls.prefix(avant).filter { $0.command == "exporter" }.count)
        XCTAssertFalse(livrer(["photo_ids": [1], "folder": "/x", "format": "psd", "hdr": true, "bit_depth": 32]).isError)
        XCTAssertEqual(try reglagesEnvoyes()["profondeur"]?.int, 32)
    }

    func testJpegHdrUsesSrgbOrP3AndSaysItHasAGainMap() throws {
        let result = livrer(["photo_ids": [1], "folder": "/x", "hdr": true, "color_space": "srgb"])
        XCTAssertEqual(try reglagesEnvoyes()["espace"]?.string, "sRGB_hdr")
        XCTAssertTrue(try JSONCoding.parse(result.text)["reglages"]?.string?.contains("HDR avec carte de gain") == true)
    }

    // MARK: Poids maximal et filigrane

    func testMaximumFileSizeIsForJpegOnly() throws {
        XCTAssertFalse(livrer(["photo_ids": [1], "folder": "/x", "max_size_kb": 500, "long_edge": 2048]).isError)
        XCTAssertEqual(try reglagesEnvoyes()["poids_max_ko"]?.int, 500)
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "format": "png", "max_size_kb": 500]).text.contains("JPEG seulement"))
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "max_size_kb": 2]).isError)
    }

    /// Constaté en 2.5 : à 1600 px, 60 Ko n'est pas atteignable ; Lightroom livre alors le plus petit
    /// fichier possible (74 Ko).
    func testFilesAboveTheMaximumSizeAreReported() throws {
        fake.onSend = { [unowned fake] command, _ in
            guard command == "exporter" else { return }
            fake?.replies["exporter"] = ["dossier": "/x", "fichiers": [
                ["photo": ["fichier": "IMG_2580.JPEG"], "chemin": "/x/IMG_2580.jpg", "octets": 75401],
                ["photo": ["fichier": "IMG_2581.JPEG"], "chemin": "/x/IMG_2581.jpg", "octets": 58818],
            ]]
        }
        let reponse = try JSONCoding.parse(livrer(["photo_ids": [1, 2], "folder": "/x", "max_size_kb": 60, "long_edge": 1600]).text)
        let note = try XCTUnwrap(reponse["au_dessus_du_poids"]?.string)
        XCTAssertTrue(note.hasPrefix("1 fichier au-dessus de 60 Ko (IMG_2580.jpg : 74 Ko)"), note)
        XCTAssertNil(try JSONCoding.parse(livrer(["photo_ids": [1, 2], "folder": "/x", "max_size_kb": 100]).text)["au_dessus_du_poids"])
    }

    func testWatermarksAreReadFromLightroomFiles() throws {
        let watermarks = dossier.appendingPathComponent("Watermarks")
        try FileManager.default.createDirectory(at: watermarks, withIntermediateDirectories: true)
        let fichier = """
        s = {
        \tid = "8A6E-ESSAI",
        \tinternalName = "Signature",
        \ttitle = "Signature Dany",
        \ttype = "WatermarkingPreset",
        \tvalue = {
        \t\titems = {
        \t\t\t{
        \t\t\t\tanchor = "bottomright",
        \t\t\t\tkind = "text",
        \t\t\t\ttext = "© Dany Ménard",
        \t\t\t},
        \t\t},
        \t},
        \tversion = 0,
        }
        """
        try fichier.write(to: watermarks.appendingPathComponent("Signature Dany.lrtemplate"), atomically: true, encoding: .utf8)
        XCTAssertEqual(tools.filigranes.all(), [Filigrane(id: "8A6E-ESSAI", nom: "Signature Dany", description: "texte « © Dany Ménard »")])

        let result = livrer(["photo_ids": [1], "folder": "/x", "watermark": "signature dany"])
        XCTAssertEqual(try reglagesEnvoyes()["filigrane"]?.string, "8A6E-ESSAI")
        XCTAssertTrue(try JSONCoding.parse(result.text)["reglages"]?.string?.contains("filigrane « Signature Dany »") == true)
        XCTAssertFalse(livrer(["photo_ids": [1], "folder": "/x", "watermark": "copyright"]).isError)
        XCTAssertEqual(try reglagesEnvoyes()["filigrane"]?.string, "<simpleCopyrightWatermark>")
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "watermark": "logo"]).text.contains("« Signature Dany »"), "les filigranes offerts sont nommés")
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "format": "dng", "watermark": "copyright"]).isError)

        fake.replies["livraison"] = ["services_publication": []]
        let liste = try JSONCoding.parse(livrer(["list": true]).text)
        XCTAssertEqual(liste["filigranes"]?.array?.map { $0["nom"]?.string }, ["copyright", "Signature Dany"])
    }

    // MARK: Réimportation

    func testStackedReimportGoesNextToTheOriginalWithoutAFolder() throws {
        fake.onSend = { [unowned fake] command, _ in
            guard command == "exporter" else { return }
            fake?.replies["exporter"] = ["dossier": "/Volumes/Photos/2025/Gaspesie", "reimportees": true, "empilees": true, "fichiers": [
                ["photo": ["fichier": "DSCF1.RAF"], "chemin": "/Volumes/Photos/2025/Gaspesie/DSCF1.tif", "octets": 1000, "reimportee": 777],
            ]]
        }
        let result = livrer(["photo_ids": [1], "format": "tiff", "bit_depth": 16, "reimport": "stack"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertNil(fake.calls.last { $0.command == "exporter" }?.params["dossier"], "pas de dossier : celui de l'original")
        XCTAssertEqual(try reglagesEnvoyes()["reimporter"]?.string, "pile")
        let reponse = try JSONCoding.parse(result.text)
        XCTAssertEqual(reponse["reimportees"]?.array?.first?["id"]?.int, 777)
        XCTAssertTrue(reponse["a_savoir"]?.string?.contains("undo_last ne les retire pas") == true)
        XCTAssertEqual(reponse["dossier"]?.string, "le dossier de chaque original")
        XCTAssertTrue(livrer(["photo_ids": [1], "reimport": "stack", "subfolder": "x"]).isError)
        XCTAssertTrue(livrer(["photo_ids": [1], "reimport": "catalog"]).text.contains("folder"), "catalog : le dossier reste exigé")
    }

    // MARK: Dossier, noms exacts

    func testFolderIsChosenInAWindowAndReadBackLater() throws {
        fake.replies["choisirDossier"] = ["en_attente": true]
        let attente = try JSONCoding.parse(livrer(["choose_folder": true]).text)
        XCTAssertEqual(attente["en_attente"]?.bool, true)
        XCTAssertTrue(attente["a_savoir"]?.string?.contains("choose_folder = true") == true)
        fake.replies["choisirDossier"] = ["dossier": "/Volumes/Photos/Gaspésie 2026"]
        XCTAssertEqual(try JSONCoding.parse(livrer(["choose_folder": true]).text)["dossier"]?.string, "/Volumes/Photos/Gaspésie 2026")
        fake.replies["choisirDossier"] = ["annule": true]
        XCTAssertEqual(try JSONCoding.parse(livrer(["choose_folder": true]).text)["annule"]?.bool, true)
        XCTAssertFalse(fake.commands.contains("exporter"))
    }

    func testExactFileNamesComeFromLightroomWithTakenNamesFlagged() throws {
        try FileManager.default.createDirectory(at: dossier.appendingPathComponent("Livraison"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dossier.appendingPathComponent("Livraison/Gaspesie-001.avif").path, contents: Data())
        fake.replies["nomsFichiers"] = ["modele": "Nom personnalisé - Séquence", "noms": [
            ["photo": ["fichier": "DSCF1.RAF"], "nom": "Gaspesie-001"], ["photo": ["fichier": "DSCF2.RAF"], "nom": "Gaspesie-002"],
        ]]
        let reponse = try JSONCoding.parse(livrer(["list": true, "photo_ids": [1, 2], "filename_template": "Nom personnalisé - Séquence",
                                                   "custom_text": "Gaspesie", "format": "avif", "folder": .string(dossier.appendingPathComponent("Livraison").path)]).text)
        XCTAssertEqual(fake.lastParams["modele"]?.string, "Nom personnalisé - Séquence")
        XCTAssertEqual(fake.lastParams["texte_perso"]?.string, "Gaspesie")
        let noms = reponse["noms"]?.array ?? []
        XCTAssertEqual(noms.map { $0["nom"]?.string }, ["Gaspesie-001.avif", "Gaspesie-002.avif"])
        XCTAssertNotNil(noms[0]["deja_pris"])
        XCTAssertNil(noms[1]["deja_pris"])
    }

    // MARK: Aperçus dynamiques

    func testSmartPreviewsAreBuiltInBatches() throws {
        fake.onSend = { [unowned fake] command, params in
            guard command == "apercusDynamiques" else { return }
            let noms = (params["photos"]?.array ?? []).compactMap(\.int).map { JSONValue.string("DSCF\($0).RAF") }
            fake?.replies["apercusDynamiques"] = ["crees": .array(noms), "existants": [], "echecs": [], "sans_original": [], "taille_mo": 1.5]
        }
        let ids: [JSONValue] = (1...30).map { .number(Double($0)) }
        let reponse = try JSONCoding.parse(livrer(["photo_ids": .array(ids), "smart_previews": "build"]).text)
        let lots = fake.calls.filter { $0.command == "apercusDynamiques" }
        XCTAssertEqual(lots.map { $0.params["photos"]?.array?.count }, [25, 5])
        XCTAssertEqual(reponse["crees"]?.array?.count, 30)
        XCTAssertEqual(reponse["taille_mo"]?.double, 3)
        XCTAssertNil(reponse["echecs"], "les listes vides ne sont pas montrées")
        XCTAssertFalse(fake.commands.contains("exporter"))
        _ = livrer(["photo_ids": [1], "smart_previews": "delete"])
        XCTAssertEqual(fake.lastParams["retirer"]?.bool, true)
        XCTAssertTrue(livrer(["photo_ids": [1], "smart_previews": "oui"]).isError)
    }

    // MARK: Ni Photoshop ni galeries

    /// Développeur ne parle qu'à Lightroom : ni ouverture dans Photoshop, ni galerie (collection
    /// publiée) créée, retirée, remplie ou relue. Ces paramètres sont refusés sans rien envoyer.
    func testPhotoshopAndGalleriesAreGone() throws {
        for arguments: [String: JSONValue] in [
            ["photo_ids": [4], "photoshop": true, "confirm": true],
            ["create_gallery": ["service": 1, "name": "Vacances"], "photo_ids": [1], "confirm": true],
            ["delete_gallery": 900, "confirm": true],
            ["photo_ids": [1], "publish_collection": 7, "confirm": true],
            ["list": true, "publish_collection": 900],
        ] {
            let result = livrer(arguments)
            XCTAssertTrue(result.isError, JSONCoding.line(.object(arguments)))
            XCTAssertTrue(result.text.contains("Paramètres inconnus"), result.text)
        }
        XCTAssertTrue(fake.calls.isEmpty, "rien n'est envoyé au module : \(fake.commands)")
        let schema = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "export_photos" })
        let texte = JSONCoding.line(schema).lowercased()
        for mot in ["photoshop", "galerie", "gallery", "publish_collection", "concours", "client"] {
            XCTAssertFalse(texte.contains(mot), "export_photos parle encore de « \(mot) »")
        }
    }

    // MARK: Livraisons types lues dans les services

    static let serviceWeb: JSONValue = ["id": 49283849, "nom": "Lightroom Export 5 Megapixels", "module": "com.adobe.ag.export.file",
        "reglages": ["LR_format": "JPEG", "LR_jpeg_quality": 1, "LR_export_colorSpace": "sRGB", "LR_export_bitDepth": 8,
                     "LR_size_doConstrain": true, "LR_size_resizeType": "megapixels", "LR_size_megapixels": 5, "LR_outputSharpeningOn": false,
                     "LR_embeddedMetadataOption": "all", "LR_removeLocationMetadata": true,
                     "LR_export_destinationPathPrefix": "/Volumes/Photos/Lightroom Export 5 Megapixels"]]

    func testProfilesFollowTheUsersHardDriveServices() throws {
        let profil = try XCTUnwrap(ToolHandler.profilService(Self.serviceWeb))
        XCTAssertEqual(profil.nom, "Lightroom Export 5 Megapixels")
        XCTAssertEqual(profil.reglages["qualite"]?.int, 100)
        XCTAssertEqual(profil.reglages["taille"]?["valeur"]?.double, 5)
        XCTAssertNil(profil.reglages["nettete"])
        XCTAssertEqual(profil.dossierHabituel, "/Volumes/Photos/Lightroom Export 5 Megapixels")
        XCTAssertNil(ToolHandler.profilService(["nom": "Flickr", "module": "com.adobe.lightroom.export.flickr"]), "pas de réglages lus")

        fake.replies["livraison"] = ["services_publication": [Self.serviceWeb]]
        let liste = try JSONCoding.parse(livrer(["list": true]).text)
        XCTAssertEqual(liste["profils"]?.array?.map { $0["nom"]?.string }, ["Lightroom Export 5 Megapixels"], "au lieu des profils par défaut")
        XCTAssertNil(liste["services_publication"], "les services ne servent qu'aux livraisons types : pas listés")
        XCTAssertTrue(livrer(["photo_ids": [1], "profile": "web_5mp", "folder": "/x"]).text.contains("Lightroom Export 5 Megapixels"))
        XCTAssertFalse(livrer(["photo_ids": [1], "profile": "lightroom export 5 megapixels", "folder": "/x", "watermark": "copyright"]).isError)
        let r = try reglagesEnvoyes()
        XCTAssertEqual(r["taille"]?["type"]?.string, "megapixels")
        XCTAssertEqual(r["filigrane"]?.string, "<simpleCopyrightWatermark>", "le réglage donné s'ajoute au profil")
        XCTAssertTrue(livrer(["photo_ids": [1], "profile": "lightroom export 5 megapixels"]).text.contains("/Volumes/Photos/Lightroom Export 5 Megapixels"),
                      "dossier habituel du service rappelé")
    }

    func testAServiceInHdrOrWithAnUnknownSizeIsConvertedWithRemarks() throws {
        let service: JSONValue = ["id": 1, "nom": "HDR web", "reglages": ["LR_format": "AVIF", "LR_avif_quality": 0.7, "LR_enableHDRDisplay": true,
            "LR_export_colorSpace": "p3_hdr", "LR_maximumCompatibility": true, "LR_size_doConstrain": true, "LR_size_resizeType": "wh",
            "LR_size_maxWidth": 2048, "LR_size_maxHeight": 1600, "LR_useWatermark": true, "LR_watermarking_id": "<simpleCopyrightWatermark>"]]
        let profil = try XCTUnwrap(ToolHandler.profilService(service))
        XCTAssertEqual(profil.reglages["hdr"]?.bool, true)
        XCTAssertEqual(profil.reglages["qualite"]?.int, 70)
        XCTAssertEqual(profil.reglages["taille"]?["valeur"]?.double, 2048)
        XCTAssertEqual(profil.remarques.count, 1, "la taille « wh » devient un grand côté, dit")
        XCTAssertTrue(profil.description.contains("filigrane des droits d'auteur"), profil.description)
        XCTAssertNil(ToolHandler.profilService(["nom": "PSB", "reglages": ["LR_format": "PSB"]]), "un format que le connecteur ne livre pas")
    }

    // MARK: Fichier relu

    func testDeliveredFileIsReadBackWithoutHdr() throws {
        let chemin = TestSupport.previewFile(TestSupport.jpeg(red: 100, green: 120, blue: 140))
        let lecture = try XCTUnwrap(ToolHandler.lectureFichier(chemin))
        XCTAssertEqual(lecture["dimensions"]?.string, "300 × 200 px (0,1 Mpx)")
        XCTAssertEqual(lecture["hdr"]?.bool, false)
        XCTAssertEqual(lecture["profondeur"]?.int, 8)
    }
}
