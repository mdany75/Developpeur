import CoreGraphics
import CoreImage
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

    /// Comme `damierLocal`, avec en plus, autour de (`fx`, `fy`), un sujet qui a de la texture (des
    /// carrés de 24 px) mais flou (gaussien de 4 px) : une vraie mise au point manquée, que la
    /// texture laisse juger (`DetailMeasurements.textureMin`, relevé le 21 octobre 2026), quand un
    /// gris uni ne se juge pas.
    static func damierLocalEtSujetFlou(cx: Double, cy: Double, cote: Double, fx: Double, fy: Double,
                                       width: Int = 1200, height: Int = 800) -> Data {
        let demi = Int(cote * Double(min(width, height)) / 2)
        let x0 = Int(fx * Double(width)), y0 = Int(fy * Double(height))
        let sujet = TestSupport.imagePixels(width: width, height: height) { x, y in
            guard abs(x - x0) < demi, abs(y - y0) < demi else { return (128, 128, 128) }
            let v: UInt8 = ((x / 24) + (y / 24)) % 2 == 0 ? 60 : 190
            return (v, v, v)
        }
        let source = CIImage(cgImage: sujet)
        let flou = CIContext().createCGImage(source.clampedToExtent().applyingGaussianBlur(sigma: 4).cropped(to: source.extent),
                                             from: source.extent)!
        let base = PreviewImages.image(damierLocal(cx: cx, cy: cy, cote: cote, width: width, height: height))!
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var flous = [UInt8](repeating: 0, count: width * height * 4)
        for (image, tampon) in [(base, 0), (flou, 1)] {
            let dessin = { (buffer: UnsafeMutableRawBufferPointer) in
                let contexte = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                contexte.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            if tampon == 0 { pixels.withUnsafeMutableBytes(dessin) } else { flous.withUnsafeMutableBytes(dessin) }
        }
        for y in max(0, y0 - demi - 12)..<min(height, y0 + demi + 12) {
            for x in max(0, x0 - demi - 12)..<min(width, x0 + demi + 12) {
                let i = (y * width + x) * 4
                pixels[i] = flous[i]; pixels[i + 1] = flous[i + 1]; pixels[i + 2] = flous[i + 2]
            }
        }
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

    /// La règle de la rafale (1.3.4) : des yeux fermés ne font proposer le rejet que si une autre vue
    /// de la rafale ou de la pile les a ouverts ; la seule vue de son moment reste à vérifier, à 2 ★.
    func testClosedEyesAreOnlyRejectedWhenAnotherViewOfTheBurstHasThemOpen() {
        func photo(_ id: Int, ouverture: Double, pile: Int?) -> PhotoTriee {
            var p = PhotoTriee(id: id, fichier: "DSCF\(id).RAF")
            p.detail = DetailMeasurements(zones: Array(repeating: 50, count: 9), noise: 0.3, shadowNoise: nil, side: 1024)
            p.vision = VisionReport(faces: [VisionReport.Face(box: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2), pupils: [], eyeWidth: nil,
                                                              quality: 0.6, eyeOpenness: ouverture)], aesthetics: 0.2, utility: false, salientArea: nil)
            p.pile = pile
            return p
        }
        let fermesDansLaPile = photo(1, ouverture: 0.05, pile: 1)
        let ouvertsDansLaPile = photo(2, ouverture: 0.4, pile: 1)
        let fermesSeule = photo(3, ouverture: 0.05, pile: nil)
        XCTAssertTrue(ouvertsDansLaPile.yeuxOuverts)
        XCTAssertFalse(fermesDansLaPile.yeuxOuverts)
        let bilan = Tri.bilan([fermesDansLaPile, ouvertsDansLaPile, fermesSeule])
        let rejets = (bilan["propositions"]?.array ?? []).filter { $0["flag"]?.string == "reject" }
            .flatMap { $0["photo_ids"]?.array?.compactMap(\.int) ?? [] }
        XCTAssertEqual(rejets, [1], "seule la vue aux yeux fermés d'une pile qui a une autre vue aux yeux ouverts")
        XCTAssertEqual(bilan["plafonds"]?["1"]?["note_max"]?.int, 0)
        XCTAssertEqual(bilan["plafonds"]?["3"]?["note_max"]?.int, 2, "la seule vue de son moment : 2 au plus")
        XCTAssertEqual(bilan["plafonds"]?["3"]?["a_verifier"]?.bool, true)
        XCTAssertEqual(bilan["yeux_fermes"]?.array?.compactMap(\.int), [1, 3], "les yeux fermés restent dits")
        // Toute la pile aux yeux fermés : aucune autre vue ne les a ouverts, aucun rejet.
        let bilanFermes = Tri.bilan([photo(4, ouverture: 0.05, pile: 4), photo(5, ouverture: 0.08, pile: 4)])
        XCTAssertTrue((bilanFermes["propositions"]?.array ?? []).isEmpty)
        XCTAssertEqual(bilanFermes["plafonds"]?["4"]?["a_verifier"]?.bool, true)
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
        let sansActive = tools.call(name: "cull_photos", arguments: [:])
        XCTAssertTrue(sansActive.isError, "sans cible ni photo active, il faut dire quelles photos")
        XCTAssertTrue(sansActive.text.contains("Photos à traiter : photo_ids, selection = true, collection ou folder"), sansActive.text)
        XCTAssertEqual(fake.commands, ["etat"])
        // 1.4 : une grande sélection n'est plus refusée, elle se trie par tranches (GroupesLumiereTests).
        fake.replies["selection"] = ["total": 2_500, "photos": []]
        XCTAssertTrue(tools.call(name: "cull_photos", arguments: ["selection": true]).text.contains("Aucune photo à trier"))
        XCTAssertFalse(fake.commands.contains("vignettes"))
    }

    /// 1.3.1 : sans photo_ids, selection, collection ni folder, le tri prend la photo active de
    /// Lightroom, comme les autres outils (dans la fenêtre Claude, la note d'abord d'une photo
    /// oubliait photo_ids 2 fois sur 4) ; la planche contact, elle, demande toujours une série.
    func testCullTakesTheActivePhotoWithoutTarget() throws {
        preparerVignettes()
        fake.replies["etat"] = ["photo_active": ["id": 42, "fichier": "DSCF42.RAF"]]
        for arguments in [[:], ["selection": false], ["photo_ids": []], ["keywords": false, "details": true]] as [[String: JSONValue]] {
            fake.calls = []
            let result = tools.call(name: "cull_photos", arguments: arguments)
            XCTAssertFalse(result.isError, result.text)
            XCTAssertEqual(fake.commands.first, "etat", "\(arguments)")
            XCTAssertFalse(fake.commands.contains("selection"), "pas la sélection : la photo active")
            XCTAssertEqual(fake.calls.first { $0.command == "vignettes" }?.params["photos"]?.array?.compactMap(\.int), [42], "\(arguments)")
            XCTAssertEqual(try JSONCoding.parse(result.text)["photos_analysees"]?.int, 1)
        }
        // Une cible donnée l'emporte : la photo active n'est pas lue.
        fake.calls = []
        XCTAssertFalse(tools.call(name: "cull_photos", arguments: ["photo_ids": [5]]).isError)
        XCTAssertFalse(fake.commands.contains("etat"))
        // Un photo_ids invalide se dit, sans prendre la photo active à sa place.
        fake.calls = []
        XCTAssertTrue(tools.call(name: "cull_photos", arguments: ["photo_ids": ["sept"]]).isError)
        XCTAssertTrue(fake.calls.isEmpty, "\(fake.commands)")
        // Le plafond de la photo active est gardé pour propose_ratings, comme pour une série.
        XCTAssertNotNil(tools.dernierTri[42])

        // La planche contact : une série, jamais la photo active seule.
        fake.calls = []
        let planche = tools.call(name: "contact_sheet", arguments: [:])
        XCTAssertTrue(planche.isError)
        XCTAssertTrue(planche.text.contains("Photos à traiter"), planche.text)
        XCTAssertTrue(fake.calls.isEmpty, "\(fake.commands)")
        // Les descriptions le disent.
        func propriete(_ outil: String, _ nom: String) -> String? {
            tools.definitions.first { $0["name"]?.string == outil }?["inputSchema"]?["properties"]?[nom]?["description"]?.string
        }
        XCTAssertTrue(propriete("cull_photos", "photo_ids")?.contains("Défaut : la photo active de Lightroom.") == true)
        XCTAssertFalse(propriete("contact_sheet", "photo_ids")?.contains("photo active") == true)
        let description = tools.definitions.first { $0["name"]?.string == "cull_photos" }?["description"]?.string ?? ""
        XCTAssertTrue(description.hasSuffix("Sans photo_ids, selection, collection ni folder : la photo active de Lightroom."), description)
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

    /// RAF minimal : en-tête, JPEG incorporé avec son Exif (dimensions, MakerNote de Fujifilm avec
    /// le point de mise au point), fabriqué par FichierFujifilm (BoitierTests).
    static func fichierFujifilm(x: Int, y: Int, avertissement: Int = 0, largeur: Int = 4416, hauteur: Int = 2944,
                                raf: Bool = true) -> Data {
        FichierFujifilm.fichier(note: FichierFujifilm.point(x: x, y: y, avertissement: avertissement),
                                largeur: largeur, hauteur: hauteur, raf: raf)
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
        let lecteur = LecteurBoitier(delai: 0.2) { _ in
            verrou.lock(); lectures += 1; verrou.unlock()
            attente.wait()
            return LectureBoitier(point: PointAF(x: 0.5, y: 0.5, avertissement: false, visages: nil), intention: nil)
        }
        let debut = Date()
        XCTAssertNil(lecteur.lire(URL(fileURLWithPath: "/Volumes/Photos/A.RAF")))
        XCTAssertLessThan(Date().timeIntervalSince(debut), 1.5, "le délai, pas l'attente sans fin")
        XCTAssertEqual(lecteur.bloque?.lastPathComponent, "A.RAF")
        XCTAssertNil(lecteur.lire(URL(fileURLWithPath: "/Volumes/Photos/B.RAF")))
        verrou.lock(); XCTAssertEqual(lectures, 1, "la suite n'est pas lue"); verrou.unlock()
        attente.signal()
        // La lecture bloquée finit (l'utilisateur a répondu à macOS) : la suite se lit de nouveau.
        let fin = Date().addingTimeInterval(2)
        while lecteur.bloque != nil, Date() < fin { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertNil(lecteur.bloque, "débloqué quand la lecture finit")
        attente.signal()
        XCTAssertEqual(lecteur.lire(URL(fileURLWithPath: "/Volumes/Photos/B.RAF"))?.point?.x, 0.5)

        let rapide = LecteurBoitier(delai: 1) { _ in
            LectureBoitier(point: PointAF(x: 0.25, y: 0.75, avertissement: true, visages: 1), intention: nil)
        }
        XCTAssertEqual(rapide.lire(URL(fileURLWithPath: "/tmp/C.RAF"))?.point?.x, 0.25)
        XCTAssertNil(rapide.bloque)
    }

    /// Au tri, le point seul compte : sans géométrie pour le placer, l'original n'est pas ouvert
    /// (une lecture de moins qui pourrait attendre l'autorisation de macOS) ; avec elle, une lecture.
    func testCullOpensNoOriginalWithoutGeometry() {
        let verrou = NSLock()
        var lectures = 0
        let lecteur = LecteurBoitier(delai: 1) { _ in
            verrou.lock(); lectures += 1; verrou.unlock()
            return LectureBoitier(point: PointAF(x: 0.5, y: 0.5, avertissement: false, visages: nil))
        }
        func comptees() -> Int { verrou.lock(); defer { verrou.unlock() }; return lectures }
        XCTAssertNil(ToolHandler.pointAF(["marque": "FUJIFILM", "chemin_original": "/Volumes/Photos/DSCF0001.RAF"], lecteur: lecteur))
        XCTAssertEqual(comptees(), 0, "pas de géométrie : rien d'ouvert")
        let place = ToolHandler.pointAF(["marque": "FUJIFILM", "chemin_original": "/Volumes/Photos/DSCF0001.RAF",
                                         "geometrie": ["largeur": 300, "hauteur": 200, "orientation": "AB"]], lecteur: lecteur)
        XCTAssertEqual(place.map { Double($0.point.x) }, 0.5)
        XCTAssertEqual(comptees(), 1)
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

    /// 1.3 : les règles de netteté (floue, mise au point manquée ou signalée) n'existent qu'à un
    /// endroit, `PhotoTriee.defautsNettete`, que le tri et le carnet de progrès reprennent : le tri
    /// rend les mêmes défauts, dans le même ordre, avant les autres (yeux fermés, presque noire…).
    func testSharpnessRulesAreSharedWithTheProgressNotebook() {
        let cas: [(nettete: Double, af: PhotoTriee.MiseAuPoint?)] = [
            (6, nil), (60, nil), (25, nil),
            (60, .init(point: .zero, nettete: 8, avertissement: false)),
            (30, .init(point: .zero, nettete: 8, avertissement: false)),
            (60, .init(point: .zero, nettete: 50, avertissement: true)),
            (60, .init(point: .zero, nettete: 20, avertissement: true)),
            (20, .init(point: .zero, nettete: nil, avertissement: true)),
            (40, .init(point: .zero, nettete: nil, avertissement: true)),
            (6, .init(point: .zero, nettete: 4, avertissement: true)),
        ]
        for (nettete, af) in cas {
            var photo = PhotoTriee(id: 1, fichier: "DSCF1.RAF")
            photo.detail = DetailMeasurements(zones: Array(repeating: nettete, count: 9), noise: 0.3, shadowNoise: nil, side: 1024)
            photo.af = af
            let partagees = PhotoTriee.defautsNettete(detail: photo.detail, af: af)
            XCTAssertEqual(photo.defautsMesures.map(\.genre), partagees.map(\.genre), "netteté \(nettete), \(String(describing: af))")
            XCTAssertEqual(photo.defauts, partagees.map(\.texte))
        }
        // Des valeurs attendues, pour que les deux ne dérivent pas ensemble.
        func genres(_ nettete: Double, _ af: PhotoTriee.MiseAuPoint?) -> [PhotoTriee.Defaut] {
            PhotoTriee.defautsNettete(detail: DetailMeasurements(zones: Array(repeating: nettete, count: 9), noise: 0.3, shadowNoise: nil, side: 1024),
                                      af: af).map(\.genre)
        }
        XCTAssertEqual(genres(6, nil), [.floue])
        XCTAssertEqual(genres(60, .init(point: .zero, nettete: 8, avertissement: false)), [.miseAuPointManquee])
        XCTAssertEqual(genres(20, .init(point: .zero, nettete: nil, avertissement: true)), [.miseAuPointSignalee])
        XCTAssertEqual(genres(40, .init(point: .zero, nettete: nil, avertissement: true)), [])
        XCTAssertEqual(PhotoTriee.defautsNettete(detail: nil, af: nil).count, 0)
        // Les autres défauts du tri viennent après ceux de la netteté.
        var sombre = PhotoTriee(id: 2, fichier: "DSCF2.RAF")
        sombre.detail = DetailMeasurements(zones: Array(repeating: 6, count: 9), noise: 0.3, shadowNoise: nil, side: 1024)
        sombre.mesures = PhotoMeasurements(meanL: 3, percentilesL: [50: 3], histogramL: Array(repeating: 10, count: 10), clippedHighlights: 0,
                                           pureWhite: 0, crushedShadows: 60, clippedChannels: [0, 0, 0], meanChroma: 1, saturatedShare: 0,
                                           neutralA: 0, neutralB: 0, neutralShare: 0, pixelCount: 100)
        XCTAssertEqual(sombre.defautsMesures.map(\.genre), [.floue, .presqueNoire])
    }

    // MARK: Mise au point sur une zone sans texture (relevé le 21 octobre 2026)

    /// Deux faux « mise au point manquée » relevés le 21 octobre 2026 : le point AF sur du sable
    /// lisse (netteté 12,6, texture 11,6 ; nette ailleurs 37,4) et sur un nuage (6,6 et 23,6 ; nette
    /// ailleurs 171,9). Sous le plancher de texture (le sable), la mise au point est non jugée et ne
    /// plafonne pas la note ; au-dessus, une vraie mise au point manquée reste un défaut majeur. Le
    /// nuage est au-dessus, mais sous `DetailMeasurements.textureDouteuse` : un doute (2, à vérifier).
    func testUnPointAFSansTextureNEstPasUneMiseAuPointManquee() throws {
        XCTAssertEqual(DetailMeasurements.textureMin, 18)
        func photo(nettete: Double, auPoint: Double, texture: Double?, avertissement: Bool = false) -> PhotoTriee {
            var p = PhotoTriee(id: 1, fichier: "DSCF1595.RAF")
            p.format = "RAW"
            p.detail = DetailMeasurements(zones: Array(repeating: nettete, count: 9), noise: 0.4, shadowNoise: nil, side: 1024)
            p.af = .init(point: CGPoint(x: 0.5, y: 0.395), nettete: auPoint, avertissement: avertissement, texture: texture)
            return p
        }
        let sable = photo(nettete: 37.4, auPoint: 12.6, texture: 11.6)
        XCTAssertFalse(try XCTUnwrap(sable.af).jugeable)
        XCTAssertEqual(sable.defautsMesures.count, 0, "\(sable.defauts)")
        XCTAssertEqual(sable.nettete, 37.4, "la netteté qui compte : la zone la plus nette")
        XCTAssertTrue(sable.pourquoi.contains("mise au point non jugée"), sable.pourquoi)
        XCTAssertEqual(sable.json["point_af"]?["mise_au_point"]?.string, "non jugée : zone sans texture autour du point")
        let plafondSable = try XCTUnwrap(Notation.plafond(sable, doublon: false))
        XCTAssertFalse(plafondSable.rejet, "pas de rejet proposé")
        XCTAssertGreaterThan(plafondSable.note, 0, plafondSable.raison)
        XCTAssertFalse(plafondSable.raison.contains("au point AF"), plafondSable.raison)

        // Le nuage (texture 23,6 à 24,1, mesurée sur les 81 blocs) reste jugé : autant de texture qu'un
        // petit visage flou (21,3 à 27,2), que le plancher doit garder jugé. Sous textureDouteuse (30),
        // sa mise au point manquée n'est qu'un doute : 2, à vérifier, sans rejet proposé ; la texture
        // d'un nuage sans relief, elle, l'écarte.
        XCTAssertEqual(DetailMeasurements.textureDouteuse, 30)
        let nuage = photo(nettete: 171.9, auPoint: 6.6, texture: 23.6)
        XCTAssertEqual(nuage.defautsMesures.map(\.genre), [.miseAuPointManquee], "relevé du 21 octobre 2026")
        XCTAssertTrue(try XCTUnwrap(nuage.af).douteuse)
        let plafondNuage = try XCTUnwrap(Notation.plafond(nuage, doublon: false))
        XCTAssertEqual(plafondNuage.note, 2, plafondNuage.raison)
        XCTAssertFalse(plafondNuage.rejet, "un doute ne propose pas de rejet")
        XCTAssertTrue(plafondNuage.aVerifier)
        XCTAssertTrue(plafondNuage.raison.contains("à vérifier par un zoom à 100 %"), plafondNuage.raison)
        XCTAssertEqual(nuage.json["point_af"]?["mise_au_point"]?.string, "à vérifier : texture faible autour du point")
        let nuageLisse = photo(nettete: 171.9, auPoint: 6.6, texture: 12)
        XCTAssertEqual(nuageLisse.defautsMesures.count, 0)
        XCTAssertEqual(try XCTUnwrap(Notation.plafond(nuageLisse, doublon: false)).note, Notation.noteMaximale)
        // Le petit visage flouté de 3 px (21,3), une vraie mise au point manquée : jugé, mais à
        // vérifier (même texture qu'un nuage) : 2 sans rejet.
        let petitVisage = photo(nettete: 60, auPoint: 1.8, texture: 21.3)
        XCTAssertEqual(petitVisage.defautsMesures.map(\.genre), [.miseAuPointManquee])
        XCTAssertEqual(try XCTUnwrap(Notation.plafond(petitVisage, doublon: false)).note, 2)

        // Un vrai sujet flou au point (de la texture) : mise au point manquée, 0 et rejet proposé.
        let manquee = photo(nettete: 60, auPoint: 8, texture: 30)
        XCTAssertEqual(manquee.defautsMesures.map(\.genre), [.miseAuPointManquee])
        XCTAssertEqual(try XCTUnwrap(Notation.plafond(manquee, doublon: false)).note, 0)
        XCTAssertTrue(try XCTUnwrap(Notation.plafond(manquee, doublon: false)).rejet, "à textureDouteuse : ferme")
        XCTAssertFalse(try XCTUnwrap(manquee.af).douteuse)
        XCTAssertNil(manquee.json["point_af"]?["mise_au_point"])
        XCTAssertEqual(photo(nettete: 60, auPoint: 8, texture: DetailMeasurements.textureMin).defautsMesures.map(\.genre), [.miseAuPointManquee],
                       "au plancher : jugée")
        // Sans texture mesurée (un ancien appel) : jugée, comme avant.
        XCTAssertEqual(photo(nettete: 60, auPoint: 8, texture: nil).defautsMesures.map(\.genre), [.miseAuPointManquee])
        // Signalée manquée par l'appareil sur une zone sans texture : confirmée par la zone la plus
        // nette (douce ailleurs : 3 ; nette ailleurs : rien).
        XCTAssertEqual(photo(nettete: 30, auPoint: 6, texture: 10, avertissement: true).defautsMesures.map(\.genre), [.miseAuPointSignalee])
        XCTAssertEqual(photo(nettete: 60, auPoint: 6, texture: 10, avertissement: true).defautsMesures.map(\.genre), [])
    }

    /// Detail.autour sur des images de synthèse : un ciel en dégradé n'a pas de texture ; un motif
    /// flou garde la sienne quand sa netteté tombe sous le seuil du flou (une vraie mise au point
    /// manquée reste jugée).
    func testLaTextureAutourDuPointSurvitAuFlouPasAuCiel() throws {
        let ciel = TestSupport.imagePixels(width: 1344, height: 896) { x, y in
            let v = UInt8(120 + (x + y) / 40)
            return (v, v, v + 20)
        }
        let mesureCiel = try XCTUnwrap(Detail.autour(ciel, point: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertLessThan(mesureCiel.texture, DetailMeasurements.textureMin)
        XCTAssertLessThan(mesureCiel.nettete, DetailMeasurements.seuilFlou)
        // Un motif de carrés de 32 px (60 et 190), net, puis flou (gaussien de 4 px à 1 344 px, 3 px
        // à la taille de la mesure : une mise au point bien manquée).
        let net = TestSupport.imagePixels(width: 1344, height: 896) { x, y in
            let v: UInt8 = ((x / 32) + (y / 32)) % 2 == 0 ? 60 : 190
            return (v, v, v)
        }
        let mesureNet = try XCTUnwrap(Detail.autour(net, point: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertGreaterThanOrEqual(mesureNet.nettete, DetailMeasurements.seuilNet)
        XCTAssertGreaterThanOrEqual(mesureNet.texture, DetailMeasurements.textureMin)
        let source = CIImage(cgImage: net)
        let floue = source.clampedToExtent().applyingGaussianBlur(sigma: 4).cropped(to: source.extent)
        let flou = try XCTUnwrap(CIContext().createCGImage(floue, from: source.extent))
        let mesureFlou = try XCTUnwrap(Detail.autour(flou, point: CGPoint(x: 0.5, y: 0.5)))
        XCTAssertLessThan(mesureFlou.nettete, DetailMeasurements.seuilFlou, "flou au point")
        XCTAssertGreaterThanOrEqual(mesureFlou.texture, DetailMeasurements.textureMin, "le motif flou garde sa texture : jugé")
        // La même mesure que Detail.nettete, et MiseAuPoint.mesuree ramène la netteté d'une vignette.
        XCTAssertEqual(Detail.nettete(flou, autour: CGPoint(x: 0.5, y: 0.5)), mesureFlou.nettete)
        let vignette = PhotoTriee.MiseAuPoint.mesuree(flou, point: CGPoint(x: 0.5, y: 0.5), avertissement: false, facteur: 1.13)
        XCTAssertEqual(try XCTUnwrap(vignette.nettete), mesureFlou.nettete * 1.13, accuracy: 1e-9)
        XCTAssertEqual(vignette.texture, mesureFlou.texture, "la texture n'est pas ramenée")
        XCTAssertNil(Detail.autour(flou, point: CGPoint(x: 1.2, y: 0.5)))
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
