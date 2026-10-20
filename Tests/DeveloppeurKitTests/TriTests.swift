import CoreGraphics
import ImageIO
import Vision
import XCTest
@testable import DeveloppeurKit

/// Version 1.9 : tri d'une séance (`cull_photos`), planche contact (`contact_sheet`), point de
/// mise au point des fichiers Fujifilm, mots-clés proposés par Vision, progression et annulation
/// des longues séries.
final class TriTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    // MARK: Images d'essai

    /// JPEG en damier de cases de `pas` px : très net (laplacien fort partout).
    static func damier(width: Int = 1200, height: Int = 800, pas: Int = 3) -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v: UInt8 = ((x / pas + y / pas) % 2 == 0) ? 230 : 25
                let i = (y * width + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
        return encode(pixels, width: width, height: height)
    }

    /// Damier seulement dans un carré centré en (cx, cy) (fractions), gris uni ailleurs.
    static func damierLocal(cx: Double, cy: Double, cote: Double, width: Int = 1200, height: Int = 800) -> Data {
        var pixels = [UInt8](repeating: 128, count: width * height * 4)
        let demi = Int(cote * Double(min(width, height)) / 2)
        let x0 = Int(cx * Double(width)), y0 = Int(cy * Double(height))
        for y in max(0, y0 - demi)..<min(height, y0 + demi) {
            for x in max(0, x0 - demi)..<min(width, x0 + demi) {
                let v: UInt8 = ((x / 3 + y / 3) % 2 == 0) ? 230 : 25
                let i = (y * width + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            }
        }
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 255 }
        return encode(pixels, width: width, height: height)
    }

    static func encode(_ pixels: [UInt8], width: Int, height: Int) -> Data {
        var copie = pixels
        let image = copie.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }!
        return PreviewImages.jpeg(image, quality: 0.95)!
    }

    /// Faux module : la commande vignettes écrit une vignette par photo (nette, ou unie pour les
    /// identifiants de `floues`), avec la description que donne le module.
    func preparerVignettes(floues: Set<Int> = [], sans: Set<Int> = [], notes: [Int: Int] = [:], drapeaux: [Int: String] = [:]) {
        let nette = Self.damier()
        let unie = TestSupport.jpeg(red: 120, green: 120, blue: 120, width: 1200, height: 800)
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "vignettes" {
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                fake.replies["vignettes"] = ["taille": params["taille"] ?? 1024, "photos": .array(ids.map { id in
                    var item: [String: JSONValue] = ["id": .number(Double(id)), "fichier": .string("DSCF\(id).RAF"),
                                                     "note": .number(Double(notes[id] ?? 0)), "drapeau": .string(drapeaux[id] ?? "aucun")]
                    if sans.contains(id) {
                        item["erreur"] = "Lightroom n'a pas rendu de vignette"
                    } else {
                        item["vignette"] = .string(TestSupport.previewFile(floues.contains(id) ? unie : nette))
                    }
                    return .object(item)
                })]
            } else if command == "apercu" {
                fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(nette))]
            }
        }
    }

    // MARK: cull_photos

    func testCullFindsBlurryPhotosProposesFlagsAndUsesThumbnailsInBatches() throws {
        preparerVignettes(floues: [3])
        let ids: [JSONValue] = (1...26).map { .number(Double($0)) }
        let result = tools.call(name: "cull_photos", arguments: ["photo_ids": .array(ids)])
        XCTAssertFalse(result.isError, result.text)
        let vignettes = fake.calls.filter { $0.command == "vignettes" }
        XCTAssertEqual(vignettes.count, 2, "par lots de \(ToolHandler.thumbnailsPerCommand)")
        XCTAssertEqual(vignettes[0].params["photos"]?.array?.count, 25)
        XCTAssertEqual(vignettes[0].params["taille"]?.int, Detail.side)
        XCTAssertFalse(fake.commands.contains("apercu"), "pas d'exportation quand le cache suffit")

        let bilan = try JSONCoding.parse(result.text)
        XCTAssertEqual(bilan["photos_analysees"]?.int, 26)
        let ratees = try XCTUnwrap(bilan["floues_ou_ratees"]?.array)
        XCTAssertEqual(ratees.map { $0["id"]?.int }, [3])
        XCTAssertTrue(ratees[0]["pourquoi"]?.string?.contains("floue") == true)
        let propositions = try XCTUnwrap(bilan["propositions"]?.array)
        let rejet = try XCTUnwrap(propositions.first { $0["flag"]?.string == "reject" })
        XCTAssertEqual(rejet["photo_ids"]?.array?.compactMap(\.int), [3])
        // 1.1 : le standard n'a que Rejeter ; les étoiles passent par propose_ratings.
        XCTAssertEqual(propositions.count, 1, "plus de pick ni de note : \(JSONCoding.line(.array(propositions)))")
        XCTAssertNil(propositions.first { $0["rating"] != nil })
        XCTAssertEqual(bilan["plafonds"]?["3"]?["note_max"]?.int, 0, "floue : plafond 0")
        XCTAssertEqual(tools.dernierTri[3]?.note, 0, "gardé pour propose_ratings")
        XCTAssertEqual(tools.dernierTri.count, 26)
        XCTAssertEqual(bilan["vignettes"]?["cache_de_lightroom"]?.int, 26)
        XCTAssertTrue(bilan["base"]?.string?.contains("set_metadata") == true)
        XCTAssertTrue(bilan["base"]?.string?.contains("propose_ratings") == true)
        XCTAssertTrue(bilan["base"]?.string?.contains("ordre de lecture") == true)
        XCTAssertNil(bilan["classement"]?.array?.first?["score"], "un ordre de lecture, pas une note")
        XCTAssertNotNil(bilan["classement"]?.array?.first?["ordre"])
    }

    func testCullFallsBackToARenderedPreviewAndLeavesClassifiedPhotos() throws {
        preparerVignettes(floues: [2], sans: [4], notes: [1: 5], drapeaux: [2: "retenue"])
        let result = tools.call(name: "cull_photos", arguments: ["photo_ids": [1, 2, 3, 4], "details": true])
        XCTAssertFalse(result.isError, result.text)
        let apercus = fake.calls.filter { $0.command == "apercu" }
        XCTAssertEqual(apercus.map { $0.params["photo"]?.int }, [4], "repli : un aperçu exporté pour la photo sans vignette")
        let bilan = try JSONCoding.parse(result.text)
        XCTAssertEqual(bilan["vignettes"]?["apercus_rendus"]?.int, 1)
        let propositions = bilan["propositions"]?.array ?? []
        XCTAssertNil(propositions.first { $0["flag"]?.string == "reject" }, "la photo floue porte déjà un drapeau : pas de proposition")
        XCTAssertNotNil(bilan["deja_classees"])
        XCTAssertEqual(bilan["photos"]?.array?.count, 4, "details : une ligne par photo")
        let ligne = try XCTUnwrap(bilan["photos"]?.array?.first)
        XCTAssertNotNil(ligne["nettete_max"])
        XCTAssertNotNil(ligne["ordre"])
        XCTAssertNil(ligne["score"])
        XCTAssertEqual(bilan["photos"]?.array?[1]["plafond"]?.int, 0, "details : le plafond de la photo floue")
    }

    /// E5 : une seule règle pour toute proposition. Une photo floue déjà notée par l'utilisateur
    /// (sans drapeau) n'est pas proposée au rejet, une photo floue retenue non plus ; une photo
    /// floue libre, oui.
    func testRejectIsOnlyProposedForPhotosWithoutRatingNorFlag() throws {
        preparerVignettes(floues: [2, 3, 5], notes: [3: 2], drapeaux: [2: "retenue"])
        let bilan = try JSONCoding.parse(tools.call(name: "cull_photos", arguments: ["photo_ids": [1, 2, 3, 4, 5]]).text)
        let rejets = (bilan["propositions"]?.array ?? []).filter { $0["flag"]?.string == "reject" }
            .flatMap { $0["photo_ids"]?.array?.compactMap(\.int) ?? [] }
        XCTAssertEqual(rejets, [5])
        XCTAssertEqual(bilan["plafonds"]?["3"]?["note_max"]?.int, 0, "le plafond reste dit, même sans proposition")
    }

    /// E4 : la qualité d'un visage ne compare que des prises d'un même visage. Dans l'ordre de
    /// lecture, un portrait ne passe pas devant un paysage aussi net ; dans une pile, le meilleur
    /// visage l'emporte.
    func testFaceQualityOnlyBreaksTiesInsideAGroup() {
        func photo(_ id: Int, visage: Double?) -> PhotoTriee {
            var p = PhotoTriee(id: id, fichier: "DSCF\(id).RAF")
            p.detail = DetailMeasurements(zones: Array(repeating: 50, count: 9), noise: 0.3, shadowNoise: nil, side: 1024)
            let faces = visage.map { [VisionReport.Face(box: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2), pupils: [], eyeWidth: nil,
                                                        quality: $0, eyeOpenness: nil)] } ?? []
            p.vision = VisionReport(faces: faces, aesthetics: 0.2, utility: false, salientArea: nil)
            p.pile = 1
            return p
        }
        let portrait = photo(1, visage: 0.9), paysage = photo(2, visage: nil)
        XCTAssertEqual(portrait.score, paysage.score, accuracy: 1e-9)
        XCTAssertGreaterThan(portrait.scoreDansGroupe, paysage.scoreDansGroupe)
        let bilan = Tri.bilan([paysage, portrait])
        XCTAssertEqual(bilan["piles"]?.array?.first?["meilleure"]?.int, 1, "dans la pile, le meilleur visage")
        XCTAssertEqual(bilan["plafonds"]?["2"]?["note_max"]?.int, 3, "pas la meilleure de sa pile : 3 au plus")
        XCTAssertNil(bilan["plafonds"]?["1"], "la meilleure, sans défaut : rien ne la borne sous 4")
    }

    func testCullTargetsSelectionCollectionAndFolder() throws {
        preparerVignettes()
        fake.replies["selection"] = ["total": 2, "photos": [["id": 7], ["id": 8]]]
        XCTAssertFalse(tools.call(name: "cull_photos", arguments: ["selection": true]).isError)
        XCTAssertEqual(fake.calls.first { $0.command == "vignettes" }?.params["photos"]?.array?.compactMap(\.int), [7, 8])

        fake.calls = []
        fake.replies["chercher"] = ["total": 1, "photos": [["id": 9]]]
        XCTAssertFalse(tools.call(name: "cull_photos", arguments: ["collection": "Vacances"]).isError)
        let recherche = try XCTUnwrap(fake.calls.first { $0.command == "chercher" })
        XCTAssertEqual(recherche.params["collection"]?.string, "Vacances")
        XCTAssertEqual(recherche.params["tri"]?.string, "date")

        fake.calls = []
        XCTAssertFalse(tools.call(name: "cull_photos", arguments: ["folder": "/Volumes/Photos/Gaspesie"]).isError)
        let dossier = try XCTUnwrap(fake.calls.first { $0.command == "chercher" })
        XCTAssertEqual(dossier.params["dossier"]?.string, "/Volumes/Photos/Gaspesie")
        XCTAssertEqual(dossier.params["sous_dossiers"]?.bool, false)

        fake.calls = []
        XCTAssertTrue(tools.call(name: "cull_photos", arguments: [:]).isError, "il faut dire quelles photos")
        fake.replies["selection"] = ["total": 900, "photos": []]
        XCTAssertTrue(tools.call(name: "cull_photos", arguments: ["selection": true]).text.contains("au plus 500"))
        XCTAssertFalse(fake.commands.contains("vignettes"))
    }

    // MARK: contact_sheet

    func testContactSheetDrawsNumberedThumbnailsWithALegend() throws {
        preparerVignettes(sans: [3])
        fake.errors["apercu"] = LightroomError.plugin("Lightroom n'a pas pu rendre l'aperçu")
        let result = tools.call(name: "contact_sheet", arguments: ["photo_ids": [1, 2, 3, 4, 5]])
        XCTAssertFalse(result.isError, result.text)
        guard case .image(let base64, let mime) = result.content.first else { return XCTFail("pas d'image") }
        XCTAssertEqual(mime, "image/jpeg")
        let image = try XCTUnwrap(PreviewImages.image(try XCTUnwrap(Data(base64Encoded: base64))))
        XCTAssertLessThanOrEqual(max(image.width, image.height), PreviewImages.maxSide)
        XCTAssertGreaterThan(image.width, image.height, "3 colonnes, 2 lignes")
        XCTAssertEqual(fake.calls.first { $0.command == "vignettes" }?.params["taille"]?.int, ToolHandler.contactSheetThumbnailSize)
        let legende = try JSONCoding.parse(result.text)
        let photos = try XCTUnwrap(legende["photos"]?.array)
        XCTAssertEqual(photos.map { $0["numero"]?.int }, [1, 2, 3, 4, 5])
        XCTAssertEqual(photos[2]["id"]?.int, 3)
        XCTAssertNotNil(photos[2]["vignette"], "vignette absente : dit dans la légende")
        XCTAssertTrue(tools.call(name: "contact_sheet", arguments: ["photo_ids": .array((1...31).map { .number(Double($0)) })]).isError)
    }

    /// 1.1 : une planche de 30 vignettes (6 colonnes, deux lots de vignettes), recompressée comme un
    /// aperçu si elle est trop lourde.
    func testContactSheetHoldsThirtyThumbnails() throws {
        preparerVignettes()
        let result = tools.call(name: "contact_sheet", arguments: ["photo_ids": .array((1...30).map { .number(Double($0)) })])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.calls.filter { $0.command == "vignettes" }.count, 2)
        guard case .image(let base64, _) = result.content.first else { return XCTFail("pas d'image") }
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertEqual(data, ToolHandler.compact(data, maxBytes: ToolHandler.maxPreviewBytes), "passée par imageContent")
        let image = try XCTUnwrap(PreviewImages.image(data))
        XCTAssertEqual(image.width, 1600)
        XCTAssertGreaterThan(image.width, image.height, "6 colonnes, 5 lignes")
        let numeros = try JSONCoding.parse(result.text)["photos"]?.array?.compactMap { $0["numero"]?.int }
        XCTAssertEqual(numeros, Array(1...30))

        // Des vignettes de bruit pur : une planche bien plus lourde que 600 Ko, recompressée.
        var graine: UInt32 = 7
        var pixels = [UInt8](repeating: 255, count: 300 * 200 * 4)
        for i in pixels.indices where i % 4 != 3 { graine = graine &* 1_664_525 &+ 1_013_904_223; pixels[i] = UInt8(graine >> 24) }
        let bruit = Self.encode(pixels, width: 300, height: 200)
        fake.onSend = { [unowned fake] command, params in
            guard let fake, command == "vignettes" else { return }
            let ids = (params["photos"]?.array ?? []).compactMap(\.int)
            fake.replies["vignettes"] = ["photos": .array(ids.map { ["id": .number(Double($0)), "fichier": .string("DSCF\($0).RAF"),
                                                                     "vignette": .string(TestSupport.previewFile(bruit))] })]
        }
        let lourde = tools.call(name: "contact_sheet", arguments: ["photo_ids": .array((1...30).map { .number(Double($0)) })])
        guard case .image(let envoye, _) = lourde.content.first else { return XCTFail("pas d'image") }
        let image300 = try XCTUnwrap(PreviewImages.image(bruit))
        let brute = try XCTUnwrap(PreviewImages.planche((1...30).map { (image300, "DSCF\($0).RAF") }))
        XCTAssertGreaterThan(brute.count, ToolHandler.maxPreviewBytes)
        XCTAssertEqual(Data(base64Encoded: envoye), ToolHandler.compact(brute, maxBytes: ToolHandler.maxPreviewBytes))
        XCTAssertLessThan(Data(base64Encoded: envoye)?.count ?? .max, brute.count, "recompressée comme un aperçu")
    }

    func testContactSheetOffsetsThroughACollection() throws {
        preparerVignettes()
        fake.replies["chercher"] = ["total": 30, "photos": .array((13...24).map { ["id": .number(Double($0))] })]
        let result = tools.call(name: "contact_sheet", arguments: ["collection": "Séance", "offset": 12])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.calls.first { $0.command == "chercher" }?.params["decalage"]?.int, 12)
        XCTAssertTrue(result.text.contains("offset = 24"))
        // Numéros suivis : la deuxième planche commence à 13, comme la treizième photo de la séance.
        let numeros = try JSONCoding.parse(result.text)["photos"]?.array?.compactMap { $0["numero"]?.int }
        XCTAssertEqual(numeros, Array(13...24))
    }

    func testPlancheLayout() throws {
        XCTAssertEqual(PreviewImages.colonnesPlanche(4), 2)
        XCTAssertEqual(PreviewImages.colonnesPlanche(9), 3)
        XCTAssertEqual(PreviewImages.colonnesPlanche(12), 4)
        XCTAssertEqual(PreviewImages.colonnesPlanche(16), 4)
        XCTAssertEqual(PreviewImages.colonnesPlanche(20), 5)
        XCTAssertEqual(PreviewImages.colonnesPlanche(25), 5)
        XCTAssertEqual(PreviewImages.colonnesPlanche(30), 6)
        let image = try XCTUnwrap(PreviewImages.image(Self.damier(width: 300, height: 200)))
        let data = try XCTUnwrap(PreviewImages.planche([(image, "un nom de fichier très très long à couper au milieu.RAF"), (nil, "absente")]))
        let planche = try XCTUnwrap(PreviewImages.image(data))
        XCTAssertEqual(planche.width, 1600)
        // Trois chiffres : la pastille s'élargit, rien ne déborde.
        XCTAssertNotNil(PreviewImages.planche([(image, "DSCF0099.RAF"), (image, "DSCF0100.RAF")], premierNumero: 99))
    }

    // MARK: Point de mise au point

    /// RAF minimal : en-tête, JPEG incorporé avec son Exif (dimensions, MakerNote de Fujifilm).
    static func fichierFujifilm(x: Int, y: Int, avertissement: Int = 0, largeur: Int = 4416, hauteur: Int = 2944,
                                raf: Bool = true) -> Data {
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16) }
        func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func be32(_ v: Int) -> [UInt8] { be16(v >> 16) + be16(v & 0xFFFF) }
        // MakerNote : « FUJIFILM », position de l'IFD (12), trois entrées petit-boutistes.
        var note = Array("FUJIFILM".utf8) + le32(12)
        note += le16(3)
        note += le16(0x1023) + le16(3) + le32(2) + le16(x) + le16(y)
        note += le16(0x1301) + le16(3) + le32(1) + le16(avertissement) + le16(0)
        note += le16(0x4100) + le16(3) + le32(1) + le16(2) + le16(0)
        note += le32(0)
        // TIFF grand-boutiste : IFD0 → Exif IFD (dimensions, MakerNote).
        var tiff = Array("MM".utf8) + be16(42) + be32(8)
        let exifIFD = 8 + 2 + 12 + 4
        let noteOffset = exifIFD + 2 + 3 * 12 + 4
        tiff += be16(1) + be16(0x8769) + be16(4) + be32(1) + be32(exifIFD) + be32(0)
        tiff += be16(3)
        tiff += be16(0xA002) + be16(4) + be32(1) + be32(largeur)
        tiff += be16(0xA003) + be16(4) + be32(1) + be32(hauteur)
        tiff += be16(0x927C) + be16(7) + be32(note.count) + be32(noteOffset)
        tiff += be32(0)
        tiff += note
        let exif = Array("Exif".utf8) + [0, 0] + tiff
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1] + be16(exif.count + 2) + exif + [0xFF, 0xD9]
        guard raf else { return Data(jpeg) }
        var fichier = Array("FUJIFILMCCD-RAW 0201FF169501X-H2S".utf8)
        fichier += [UInt8](repeating: 0, count: 84 - fichier.count)
        fichier += be32(100) + be32(jpeg.count)
        fichier += [UInt8](repeating: 0, count: 100 - fichier.count)
        return Data(fichier + jpeg)
    }

    func testFocusPointIsReadFromAFujifilmRAFAndJPEG() throws {
        let dossier = TestSupport.temporaryDirectory()
        let raf = dossier.appendingPathComponent("DSCF0001.RAF")
        try Self.fichierFujifilm(x: 2488, y: 1052).write(to: raf)
        // Valeurs relevées par exiftool sur un RAF de X-H2S : FocusPixel 2488 1052 sur 4416 × 2944.
        let point = try XCTUnwrap(PointAF.lire(fichier: raf))
        XCTAssertEqual(point.x, 2488.0 / 4416, accuracy: 1e-9)
        XCTAssertEqual(point.y, 1052.0 / 2944, accuracy: 1e-9)
        XCTAssertFalse(point.avertissement)
        XCTAssertEqual(point.visages, 2)

        let jpeg = dossier.appendingPathComponent("DSCF0002.JPG")
        try Self.fichierFujifilm(x: 100, y: 200, avertissement: 1, raf: false).write(to: jpeg)
        let flou = try XCTUnwrap(PointAF.lire(fichier: jpeg))
        XCTAssertTrue(flou.avertissement, "FocusWarning : mise au point manquée")

        let autre = dossier.appendingPathComponent("IMG.JPG")
        try TestSupport.jpeg(red: 1, green: 2, blue: 3).write(to: autre)
        XCTAssertNil(PointAF.lire(fichier: autre), "pas de MakerNote de Fujifilm")
        try Self.fichierFujifilm(x: 0, y: 0).write(to: raf)
        XCTAssertNil(PointAF.lire(fichier: raf), "pas de point rangé")
        XCTAssertNil(PointAF.lire(fichier: dossier.appendingPathComponent("absent.RAF")))
    }

    /// Constaté en 2.3 : open() d'un original peut attendre sans fin (macOS demande l'autorisation
    /// d'accéder au volume). La lecture du point AF est bornée, et la série saute la suite.
    func testAFocusPointReadThatHangsIsSkippedAndStopsTheSeries() {
        let attente = DispatchSemaphore(value: 0)
        var lectures = 0
        let verrou = NSLock()
        let lecteur = LecteurPointsAF(delai: 0.2) { _ in
            verrou.lock(); lectures += 1; verrou.unlock()
            attente.wait()
            return PointAF(x: 0.5, y: 0.5, avertissement: false, visages: nil)
        }
        let debut = Date()
        XCTAssertNil(lecteur.lire(URL(fileURLWithPath: "/Volumes/Photos/A.RAF")))
        XCTAssertLessThan(Date().timeIntervalSince(debut), 1.5, "le délai, pas l'attente sans fin")
        XCTAssertEqual(lecteur.bloque?.lastPathComponent, "A.RAF")
        XCTAssertNil(lecteur.lire(URL(fileURLWithPath: "/Volumes/Photos/B.RAF")))
        verrou.lock(); XCTAssertEqual(lectures, 1, "la suite n'est pas lue"); verrou.unlock()
        attente.signal()

        let rapide = LecteurPointsAF(delai: 1) { _ in PointAF(x: 0.25, y: 0.75, avertissement: true, visages: 1) }
        XCTAssertEqual(rapide.lire(URL(fileURLWithPath: "/tmp/C.RAF"))?.x, 0.25)
        XCTAssertNil(rapide.bloque)
    }

    /// Le passage inverse de Geometrie.point du module (Lua), recopié ici pour l'aller-retour.
    static func versFichier(_ g: GeometriePhoto, p: Double, q: Double) -> (Double, Double) {
        let (lf, hf) = g.tournee ? (g.hauteur, g.largeur) : (g.largeur, g.hauteur)
        let c = g.cadre ?? (0, 0, 1, 1, 0)
        let r = c.angle * .pi / 180
        let dx = (c.droite - c.gauche) * lf, dy = (c.bas - c.haut) * hf
        let w = dx * cos(r) + dy * sin(r), h = -dx * sin(r) + dy * cos(r)
        let (s, t): (Double, Double)
        switch g.orientation {
        case "BC": (s, t) = (q, 1 - p)
        case "CD": (s, t) = (1 - p, 1 - q)
        case "DA": (s, t) = (1 - q, p)
        default: (s, t) = (p, q)
        }
        let x = c.gauche * lf + s * w * cos(r) - t * h * sin(r)
        let y = c.haut * hf + s * w * sin(r) + t * h * cos(r)
        return (x / lf, y / hf)
    }

    func testFocusPointMapsToTheDisplayedCroppedImage() {
        for orientation in ["AB", "BC", "CD", "DA"] {
            for cadre: (gauche: Double, haut: Double, droite: Double, bas: Double, angle: Double)? in [nil, (0.1, 0.05, 0.85, 0.9, 4)] {
                let g = GeometriePhoto(largeur: orientation == "BC" || orientation == "DA" ? 4160 : 6240,
                                       hauteur: orientation == "BC" || orientation == "DA" ? 6240 : 4160, orientation: orientation, cadre: cadre)
                for (p, q) in [(0.5, 0.5), (0.2, 0.7), (0.9, 0.1)] {
                    let (x, y) = Self.versFichier(g, p: p, q: q)
                    let retour = g.versApercu(x: x, y: y)
                    XCTAssertEqual(retour.x, p, accuracy: 1e-9, "\(orientation) \(String(describing: cadre))")
                    XCTAssertEqual(retour.y, q, accuracy: 1e-9)
                }
            }
        }
        // Appareil tenu poignée en haut (DA) : le bord droit du fichier s'affiche en haut.
        let verticale = GeometriePhoto(largeur: 4160, hauteur: 6240, orientation: "DA")
        let haut = verticale.versApercu(x: 0.95, y: 0.5)
        XCTAssertEqual(haut.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(haut.y, 0.05, accuracy: 1e-9)
    }

    func testSharpnessAroundTheFocusPoint() throws {
        let image = try XCTUnwrap(PreviewImages.image(Self.damierLocal(cx: 0.25, cy: 0.3, cote: 0.2)))
        let net = try XCTUnwrap(Detail.nettete(image, autour: CGPoint(x: 0.25, y: 0.3)))
        let flou = try XCTUnwrap(Detail.nettete(image, autour: CGPoint(x: 0.75, y: 0.7)))
        XCTAssertGreaterThan(net, 35)
        XCTAssertLessThan(flou, 15)
        XCTAssertNil(Detail.nettete(image, autour: CGPoint(x: 1.2, y: 0.5)))
    }

    func testMissedFocusIsADefectOnlyWhenTheRestIsSharp() {
        var photo = PhotoTriee(id: 1, fichier: "DSCF1.RAF")
        photo.detail = DetailMeasurements(zones: Array(repeating: 60, count: 9), noise: 0.3, shadowNoise: nil, side: 1024)
        photo.af = .init(point: CGPoint(x: 0.3, y: 0.3), nettete: 8, avertissement: false)
        XCTAssertTrue(photo.defauts.first?.contains("mise au point manquée") == true)
        photo.af = .init(point: CGPoint(x: 0.3, y: 0.3), nettete: 50, avertissement: true)
        XCTAssertTrue(photo.defauts.isEmpty, "nette au point AF : l'avertissement de l'appareil ne suffit pas")
        photo.af = .init(point: CGPoint(x: 0.3, y: 0.3), nettete: 20, avertissement: true)
        XCTAssertEqual(photo.defauts, ["mise au point signalée manquée par l'appareil"])
        photo.af = nil
        photo.detail = DetailMeasurements(zones: Array(repeating: 6, count: 9), noise: 0.3, shadowNoise: nil, side: 1024)
        XCTAssertTrue(photo.defauts.first?.hasPrefix("floue") == true)
        XCTAssertLessThan(photo.score, 0)
    }

    // MARK: Mots-clés proposés

    func testEveryVisionLabelHasAFrenchKeyword() throws {
        let etiquettes = try VNClassifyImageRequest().supportedIdentifiers()
        let manquantes = etiquettes.filter { MotsClesVision.traductions[$0] == nil }
        XCTAssertTrue(manquantes.isEmpty, "étiquettes sans traduction : \(manquantes.prefix(20))")
        XCTAssertEqual(MotsClesVision.traduction("beanie"), "tuque")
        XCTAssertEqual(MotsClesVision.traduction("nouvelle_etiquette"), "nouvelle etiquette")
    }

    func testKeywordsSkipGenericLabelsAndDuplicateTranslations() {
        let mots = MotsClesVision.choisir([("animal", 0.99), ("dog", 0.95), ("canine", 0.94), ("beagle", 0.8),
                                           ("cake", 0.5), ("cake_regular", 0.49), ("grass", 0.3)], maximum: 3)
        XCTAssertEqual(mots.map(\.mot), ["chien", "beagle", "gâteau"])
        XCTAssertEqual(mots.first?.etiquette, "dog")
    }

    // MARK: Progression et annulation

    private func toolLine(id: Int, _ name: String, _ arguments: String, meta: String? = nil) -> String {
        let extra = meta.map { #","_meta":\#($0)"# } ?? ""
        return #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)\#(extra)}}"#
    }

    func testLongSeriesSendsRealProgressWithTheTotal() throws {
        preparerVignettes()
        let server = TestSupport.makeServer(fake)
        // Seule la vraie progression ici : sur une machine lente, un lot peut durer plus de 30 s, et
        // le battement (0,01 entre deux lots) partirait avant elle.
        server.progressInterval = 3600
        let verrou = NSLock()
        var notifications: [JSONValue] = []
        server.notifier = { verrou.lock(); notifications.append($0); verrou.unlock() }
        let ids = (1...26).map(String.init).joined(separator: ",")
        let reponse = try JSONCoding.parse(XCTUnwrap(server.handle(line: toolLine(id: 1, "cull_photos", #"{"photo_ids":[\#(ids)]}"#, meta: #"{"progressToken":"t"}"#))))
        XCTAssertEqual(reponse["result"]?["isError"]?.bool, false)
        verrou.lock(); defer { verrou.unlock() }
        let avancees = notifications.compactMap { $0["params"]?["progress"]?.double }
        XCTAssertEqual(avancees, [25, 26], "photo par lot, avec le total")
        XCTAssertEqual(notifications.first?["params"]?["total"]?.double, 26)
        XCTAssertTrue(notifications.first?["params"]?["message"]?.string?.contains("25 sur 26") == true)
    }

    func testCancelledSeriesStopsBetweenBatchesAndSendsNoResponse() throws {
        preparerVignettes()
        let suite = fake.onSend
        let porte = DispatchSemaphore(value: 0)
        fake.onSend = { command, params in
            suite?(command, params)
            if command == "vignettes" { _ = porte.wait(timeout: .now() + 5) }
        }
        let server = TestSupport.makeServer(fake)
        let verrou = NSLock()
        var reponses: [String] = []
        let ids = (1...60).map(String.init).joined(separator: ",")
        server.receive(line: toolLine(id: 5, "cull_photos", #"{"photo_ids":[\#(ids)]}"#, meta: #"{"progressToken":"t"}"#)) { ligne in
            verrou.lock(); reponses.append(ligne); verrou.unlock()
        }
        Thread.sleep(forTimeInterval: 0.2)
        server.receive(line: #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":5,"reason":"Échap"}}"#) { _ in }
        porte.signal()
        Thread.sleep(forTimeInterval: 1.5)
        porte.signal(); porte.signal()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(fake.calls.filter { $0.command == "vignettes" }.count, 1, "le lot suivant ne part pas")
        verrou.lock()
        XCTAssertTrue(reponses.isEmpty, "pas de réponse à un appel annulé")
        verrou.unlock()

        // Le serveur répond ensuite normalement.
        let statut = try JSONCoding.parse(XCTUnwrap(server.handle(line: toolLine(id: 6, "get_status", "{}"))))
        XCTAssertEqual(statut["result"]?["isError"]?.bool, false)
    }

    func testWaitingAnswerSaysHowFarTheSeriesIs() throws {
        preparerVignettes()
        let suite = fake.onSend
        fake.onSend = { command, params in
            suite?(command, params)
            if command == "vignettes", params["photos"]?.array?.first?.int == 26 { Thread.sleep(forTimeInterval: 1) }
        }
        let server = TestSupport.makeServer(fake)
        server.toolBudget = 0.5
        let ids = (1...26).map(String.init).joined(separator: ",")
        let reponse = try JSONCoding.parse(XCTUnwrap(server.handle(line: toolLine(id: 1, "cull_photos", #"{"photo_ids":[\#(ids)]}"#))))
        let texte = reponse["result"]?["content"]?.array?.first?["text"]?.string ?? ""
        XCTAssertTrue(texte.contains("n'est pas fini"), texte)
        XCTAssertTrue(texte.contains("où il en est") && texte.contains("sur 26 : tri des photos"), texte)
    }
}
