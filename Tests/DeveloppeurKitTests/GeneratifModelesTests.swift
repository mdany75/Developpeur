import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Le choix du modèle de la retouche générative (demande de Dany du 10 novembre 2026) : catalogue,
/// table « genre → modèle », présence sur ce Mac sans charger le modèle, Qwen-Image 2.1 Turbo dans
/// generative_edit, et le banc d'essai. Avec les faux mflux de GeneratifTests (jamais le vrai).
extension GeneratifTests {
    var scriptQwen: URL { dossier.appendingPathComponent("bin/mflux-generate-qwen-2.1-edit") }
    var cacheHF: URL { dossier.appendingPathComponent("hf") }

    /// Le faux Qwen-Image 2.1 : le faux mflux de Fibo (mêmes compteurs et arguments notés), qui lit
    /// --mask-image à la place de --mask-path.
    func fauxQwen(sortie: URL? = nil) throws {
        fauxMflux(sortie: sortie)
        let texte = try String(contentsOf: script, encoding: .utf8).replacingOccurrences(of: "--mask-path)", with: "--mask-image)")
        try texte.write(to: scriptQwen, atomically: true, encoding: .utf8)
        chmod(scriptQwen.path, 0o755)
    }

    /// Le modèle Qwen-Image 2.1 Turbo dans le faux cache : l'instantané épinglé, un fichier par dossier.
    func qwenDansLeCache(sans: String? = nil) throws {
        let f = ModeleGeneratif.qwenImage21.fiche
        let instantane = ModeleGeneratif.qwenImage21.instantane(cache: cacheHF)
        for d in f.dossiers where d != sans {
            try FileManager.default.createDirectory(at: instantane.appendingPathComponent(d), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: instantane.appendingPathComponent(d).appendingPathComponent("config.json"))
        }
    }

    /// La sortie du faux Qwen : l'entrée telle que le connecteur la prépare pour lui (le recadrage autour
    /// de `region`, à environ 1 Mpx, côtés multiples de 32), un carré rouge au milieu de la zone.
    func sortieQwen(region: CGRect) -> URL {
        let (image, _) = Generatif.lireImage(source)!
        let (cadre, _) = Generatif.recadrage(region, largeur: image.width, hauteur: image.height)
        let taille = Generatif.tailleCible(largeur: cadre.largeur, hauteur: cadre.hauteur, multiple: 32)
        var pixels = Generatif.entree(image, cadre: cadre, taille: taille)!
        for y in 0..<taille.hauteur {
            for x in 0..<taille.largeur {
                let fx = (Double(cadre.x) + (Double(x) + 0.5) * Double(cadre.largeur) / Double(taille.largeur)) / Double(image.width)
                let fy = (Double(cadre.y) + (Double(y) + 0.5) * Double(cadre.hauteur) / Double(taille.hauteur)) / Double(image.height)
                if fx > region.minX + 0.05, fx < region.maxX - 0.05, fy > region.minY + 0.1, fy < region.maxY - 0.1 { Self.rouge(&pixels, (y * taille.largeur + x) * 4) }
            }
        }
        let url = gardes.appendingPathComponent("sortie-qwen.png")
        try? Generatif.ecrirePNG(Generatif.image8(pixels, largeur: taille.largeur, hauteur: taille.hauteur)!, vers: url)
        return url
    }

    // MARK: Catalogue et table

    func testCatalogueDesModeles() {
        XCTAssertEqual(ModeleGeneratif.allCases.map(\.rawValue), ["fibo2", "qwen_image_21", "qwen_edit_2511", "flux3_klein"])
        let fibo = ModeleGeneratif.fibo2.fiche
        XCTAssertEqual(fibo.executable, "mflux-generate-fibo2-edit")
        XCTAssertEqual(fibo.optionMasque, "--mask-path")
        XCTAssertEqual(fibo.statut, .parDefaut)
        XCTAssertTrue(fibo.telechargeAuPremierUsage, "Fibo 2 : comme avant, téléchargé au premier usage")
        let qwen = ModeleGeneratif.qwenImage21.fiche
        XCTAssertEqual(qwen.nom, "Qwen-Image 2.1 Turbo")
        XCTAssertEqual(qwen.executable, "mflux-generate-qwen-2.1-edit")
        XCTAssertEqual(qwen.optionModele, ["--model", "qwen-image-2.1-turbo"])
        XCTAssertEqual(qwen.optionMasque, "--mask-image")
        XCTAssertEqual(qwen.etapes, 8)
        XCTAssertEqual(qwen.multiple, 32)
        XCTAssertEqual(qwen.depot, "Qwen/Qwen-Image-2.1-Turbo")
        XCTAssertEqual(qwen.revision, "fc13ba1986fcb905854dc8de2f52eee395f49b5b", "la révision que mflux 0.24 épingle")
        XCTAssertEqual(qwen.statut, .aDepartager)
        XCTAssertFalse(qwen.telechargeAuPremierUsage)
        for plusTard in [ModeleGeneratif.qwenEdit2511, .flux3Klein] {
            XCTAssertFalse(plusTard.fiche.branche); XCTAssertEqual(plusTard.fiche.statut, .plusTard)
            XCTAssertNil(plusTard.fiche.optionMasque, "sans masque")
        }
        XCTAssertEqual(ModeleGeneratif.idsBranches, ["auto", "fibo2", "qwen_image_21"])
        XCTAssertEqual(qwen.quantification, 8, "--quantize 8 : environ 33 Go en bf16, Lightroom ouvert sur 48 Go")
        XCTAssertNil(fibo.quantification)
        XCTAssertEqual(ModeleGeneratif.fibo2.etape, "Claude · Fibo 2", "comme avant")
        XCTAssertEqual(ModeleGeneratif.qwenImage21.etape, "Claude · Qwen-Image 2.1 Turbo")
        XCTAssertEqual(ToolHandler.nomGenere(URL(fileURLWithPath: "/t/DSCF2402.tif"), modele: .qwenImage21), "DSCF2402-Qwen")
        XCTAssertEqual(ToolHandler.nomGenere(URL(fileURLWithPath: "/t/DSCF2402-Fibo-2.tif"), modele: .qwenImage21), "DSCF2402-Qwen", "un suffixe, jamais deux")
        XCTAssertEqual(ToolHandler.nomGenere(URL(fileURLWithPath: "/t/DSCF2402-Qwen.tif")), "DSCF2402-Fibo")
        XCTAssertNil(ModeleGeneratif(rawValue: "krea2"), "Krea 2 Turbo écarté : création seulement")
    }

    /// Fibo 2 par défaut pour chaque genre ; Qwen-Image 2.1 à départager là où il y a une zone.
    func testTableDesModelesParGenre() {
        XCTAssertEqual(Set(Generatif.tableDesModeles.keys), Set(Generatif.Genre.allCases))
        for (genre, ligne) in Generatif.tableDesModeles {
            XCTAssertEqual(ligne.modele, .fibo2, genre.rawValue)
            XCTAssertEqual(ligne.aDepartager, genre == .photoEntiere ? [] : [.qwenImage21], genre.rawValue)
        }
    }

    /// Revue du 10 novembre 2026 : le statut de chaque fiche suit la table. auto ne choisit, pour aucun
    /// genre, un modèle « à départager » ni « plus tard » ; un modèle à départager est branché ; un
    /// modèle « plus tard » n'est nulle part dans la table.
    func testStatutDesFichesLieALaTable() throws {
        for genre in Generatif.Genre.allCases {
            let choix = try Generatif.choisirModele(nil, genre: genre, absent: { _ in nil })
            XCTAssertEqual(choix.modele.fiche.statut, .parDefaut, genre.rawValue)
            let ligne = try XCTUnwrap(Generatif.tableDesModeles[genre])
            XCTAssertEqual(ligne.modele.fiche.statut, .parDefaut, genre.rawValue)
            for m in ligne.aDepartager {
                XCTAssertEqual(m.fiche.statut, .aDepartager, "\(genre.rawValue) : \(m.rawValue)")
                XCTAssertTrue(m.fiche.branche, m.rawValue)
            }
        }
        let dansLaTable = Set(Generatif.tableDesModeles.values.flatMap { [$0.modele] + $0.aDepartager })
        for m in ModeleGeneratif.allCases {
            switch m.fiche.statut {
            case .parDefaut: XCTAssertTrue(m.fiche.branche, m.rawValue)
            case .aDepartager: XCTAssertTrue(dansLaTable.contains(m), "\(m.rawValue) à départager mais absent de la table")
            case .plusTard: XCTAssertFalse(dansLaTable.contains(m), m.rawValue); XCTAssertFalse(m.fiche.branche, m.rawValue)
            }
        }
    }

    /// « Grey area » de Fibo devient « masked area » pour Qwen, quelle que soit la casse.
    func testZoneGriseDiteMasqueeSansCasse() {
        XCTAssertEqual(Generatif.instructionPourQwen("Grey area: a red bag"), "masked area: a red bag")
        XCTAssertEqual(Generatif.instructionPourQwen("Fill the GRAY AREA of <image_1>"), "Fill the masked area of image 1")
        XCTAssertEqual(Generatif.instructionPourQwen("replace the gray area"), "replace the masked area")
        XCTAssertEqual(Generatif.instructionPourQwen("a stingray area"), "a stingray area", "un mot entier seulement")
    }

    /// Revue du 10 novembre 2026 : une sortie PNG RGBA de Qwen avec un alpha sous 255 se dessinait sur
    /// un tampon noir. Elle est mise à plat sur l'entrée, et la réponse le dit.
    func testSortieTransparenteMiseAPlatSurLEntree() throws {
        let l = 64, h = 32
        func rgba(_ couleur: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
            var p = [UInt8](repeating: 0, count: l * h * 4)
            for y in 0..<h { for x in 0..<l { let c = couleur(x, y), i = (y * l + x) * 4; (p[i], p[i + 1], p[i + 2], p[i + 3]) = c } }
            return CGImage(width: l, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: l * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: CGDataProvider(data: Data(p) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
        // À gauche transparent, à droite rouge opaque ; l'entrée est verte.
        let sortie = rgba { x, _ in x < l / 2 ? (0, 0, 0, 0) : (255, 0, 0, 255) }
        let entree = Generatif.image8([UInt8](repeating: 0, count: l * h * 4).enumerated().map { $0.offset % 4 == 1 ? 200 : 0 }, largeur: l, hauteur: h)!
        let noire = try XCTUnwrap(Generatif.pixelsRGBA8(sortie, largeur: l, hauteur: h))
        XCTAssertEqual(Array(noire[(h / 2 * l + 4) * 4 ..< (h / 2 * l + 4) * 4 + 3]), [0, 0, 0], "sans mise à plat : noir à gauche (le défaut)")
        let (plate, transparente) = Generatif.aplatir(sortie, sur: entree)
        XCTAssertTrue(transparente)
        let p = try XCTUnwrap(Generatif.pixelsRGBA8(plate, largeur: l, hauteur: h))
        XCTAssertEqual(Array(p[(h / 2 * l + 4) * 4 ..< (h / 2 * l + 4) * 4 + 3]), [0, 200, 0], "transparent : l'entrée")
        XCTAssertEqual(Array(p[(h / 2 * l + l - 4) * 4 ..< (h / 2 * l + l - 4) * 4 + 3]), [255, 0, 0], "opaque : la sortie")
        // Opaque partout (ou sans alpha) : rendue telle quelle.
        let opaque = rgba { _, _ in (10, 20, 30, 255) }
        XCTAssertFalse(Generatif.aplatir(opaque, sur: entree).transparence)
        XCTAssertFalse(Generatif.aplatir(entree, sur: opaque).transparence)
    }

    /// De bout en bout : un PNG RGBA de Qwen à moitié transparent ne noircit pas la photo, et la
    /// réponse dit la transparence.
    func testQwenSortieRGBANeNoircitPas() throws {
        let region = CGRect(x: 0.05, y: 0.2, width: 0.3, height: 0.6)
        let opaque = try XCTUnwrap(Generatif.lireImage(sortieQwen(region: region))?.image)
        let l = opaque.width, h = opaque.height
        var p = try XCTUnwrap(Generatif.pixelsRGBA8(opaque, largeur: l, hauteur: h))
        for y in 0..<h { for x in 0..<(l / 2) { let i = (y * l + x) * 4; (p[i], p[i + 1], p[i + 2], p[i + 3]) = (0, 0, 0, 0) } }
        let transparente = CGImage(width: l, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: l * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: CGDataProvider(data: Data(p) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let url = gardes.appendingPathComponent("sortie-qwen-rgba.png")
        try Generatif.ecrirePNG(transparente, vers: url)
        try fauxQwen(sortie: url)
        try qwenDansLeCache()
        let resultat = editer(["instruction": "replace the bag with a red one", "model": "qwen_image_21", "seed": 7, "upscale": false,
                               "region": ["x": 0.05, "y": 0.2, "width": 0.3, "height": 0.6]])
        XCTAssertFalse(resultat.isError, resultat.text)
        let reponse = try JSONCoding.parse(resultat.text)
        XCTAssertTrue(reponse["modifications"]?.array?.first?["remarque_transparence"]?.string?.contains("portait de la transparence") == true, resultat.text)
        // La moitié gauche du recadrage, transparente : la photo d'origine (passée par l'entrée sRGB
        // 8 bits : le rouge, hors de la gamme sRGB ici, ne revient pas au bit près), jamais du noir.
        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        let x = Int(0.08 * Double(largeur)), y = hauteur / 2
        for c in 1..<3 { XCTAssertEqual(Double(Self.pixel(apres, x, y)[c]), Double(Self.pixel(avant, x, y)[c]), accuracy: 1500, "canal \(c)") }
    }

    func testGenreDeLaRetouche() {
        XCTAssertEqual(Generatif.genre(instruction: "remove the wire", avecZone: true, avecReference: false), .retirer)
        XCTAssertEqual(Generatif.genre(instruction: "Erase the person on the left", avecZone: true, avecReference: false), .retirer)
        XCTAssertEqual(Generatif.genre(instruction: "get rid of the bin", avecZone: true, avecReference: false), .retirer)
        XCTAssertEqual(Generatif.genre(instruction: "replace the trousers with a skirt", avecZone: true, avecReference: false), .changer)
        XCTAssertEqual(Generatif.genre(instruction: "remove the sky", avecZone: true, avecReference: true), .remplirAvecReference)
        XCTAssertEqual(Generatif.genre(instruction: "remove the snow", avecZone: false, avecReference: false), .photoEntiere)
    }

    func testChoixDuModele() throws {
        let present: (ModeleGeneratif) -> String? = { _ in nil }
        let auto = try Generatif.choisirModele(nil, genre: .retirer, absent: present)
        XCTAssertEqual(auto.modele, .fibo2); XCTAssertTrue(auto.auto)
        XCTAssertTrue(auto.pourquoi.contains("Fibo 2, le modèle de la table pour « retirer dans une zone »"), auto.pourquoi)
        XCTAssertTrue(auto.pourquoi.contains("Qwen-Image 2.1 Turbo à départager"), auto.pourquoi)
        XCTAssertEqual(try Generatif.choisirModele("AUTO", genre: .photoEntiere, absent: present).modele, .fibo2)
        let demande = try Generatif.choisirModele("qwen_image_21", genre: .changer, absent: present)
        XCTAssertEqual(demande.modele, .qwenImage21); XCTAssertFalse(demande.auto)
        XCTAssertTrue(demande.pourquoi.hasPrefix("demandé (model = qwen_image_21)"), demande.pourquoi)

        // Une table qui choisirait Qwen, absent : Fibo 2 à sa place, dit.
        let table: [Generatif.Genre: (modele: ModeleGeneratif, aDepartager: [ModeleGeneratif])] = [.retirer: (.qwenImage21, [])]
        let repli = try Generatif.choisirModele(nil, genre: .retirer, table: table, absent: { $0 == .qwenImage21 ? "pas dans le cache" : nil })
        XCTAssertEqual(repli.modele, .fibo2)
        XCTAssertTrue(repli.pourquoi.contains("manque ici (pas dans le cache)"), repli.pourquoi)
        XCTAssertEqual(try Generatif.choisirModele(nil, genre: .retirer, table: table, absent: present).modele, .qwenImage21)

        for (id, attendu) in [("krea2", "auto, fibo2, qwen_image_21"), ("flux3_klein", "pas encore branché"), ("qwen_edit_2511", "pas encore branché")] {
            XCTAssertThrowsError(try Generatif.choisirModele(id, genre: .changer, absent: present), id) { erreur in
                XCTAssertTrue(erreur.localizedDescription.contains(attendu), erreur.localizedDescription)
            }
        }
        XCTAssertThrowsError(try Generatif.choisirModele("qwen_image_21", genre: .changer, absent: { _ in "la commande manque" })) { erreur in
            XCTAssertTrue(erreur.localizedDescription.contains("ne peut pas tourner sur ce Mac : la commande manque"), erreur.localizedDescription)
        }
    }

    /// La présence d'un modèle, lue sans le charger : sa commande, puis l'instantané épinglé complet.
    func testPresenceDUnModeleSansLeCharger() throws {
        let bin = script.deletingLastPathComponent()
        let qwen = ModeleGeneratif.qwenImage21
        XCTAssertTrue(qwen.raisonAbsent(dossierBin: bin, cache: cacheHF)?.contains("commande mflux-generate-qwen-2.1-edit est introuvable") == true)
        try fauxQwen()
        XCTAssertTrue(qwen.raisonAbsent(dossierBin: bin, cache: cacheHF)?.contains("révision fc13ba19 absente du cache") == true,
                      qwen.raisonAbsent(dossierBin: bin, cache: cacheHF) ?? "")
        try qwenDansLeCache(sans: "vae")
        let sansVAE = qwen.raisonAbsent(dossierBin: bin, cache: cacheHF) ?? ""
        XCTAssertTrue(sansVAE.contains("dossier vae absent ou vide"), sansVAE)
        XCTAssertTrue(sansVAE.contains("hf download Qwen/Qwen-Image-2.1-Turbo --revision fc13ba1986fcb905854dc8de2f52eee395f49b5b"), sansVAE)
        try qwenDansLeCache()
        XCTAssertNil(qwen.raisonAbsent(dossierBin: bin, cache: cacheHF))
        let blobs = cacheHF.appendingPathComponent("models--Qwen--Qwen-Image-2.1-Turbo/blobs")
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        try Data().write(to: blobs.appendingPathComponent("abc.incomplete"))
        XCTAssertTrue(qwen.raisonAbsent(dossierBin: bin, cache: cacheHF)?.contains("téléchargement interrompu") == true)
        // Fibo 2 : sa commande seulement (le modèle se télécharge au premier usage, comme avant).
        XCTAssertNil(tools.fibo?.raisonAbsent(.fibo2))
        XCTAssertTrue(ModeleGeneratif.flux3Klein.raisonAbsent(dossierBin: bin, cache: cacheHF)?.contains("pas encore branché") == true)
        let catalogue = Generatif.catalogueJSON(dossierBin: bin, cache: cacheHF).array ?? []
        XCTAssertEqual(catalogue.count, 4)
        XCTAssertEqual(catalogue[1]["present"]?.bool, false, "téléchargement interrompu")
        XCTAssertEqual(catalogue[1]["commande"]?.string, "mflux-generate-qwen-2.1-edit")
        XCTAssertTrue(catalogue[1]["chemin_cache"]?.string?.hasSuffix("models--Qwen--Qwen-Image-2.1-Turbo/snapshots/fc13ba1986fcb905854dc8de2f52eee395f49b5b") == true)
    }

    // MARK: Qwen-Image 2.1 Turbo

    func testArgumentsDeQwen() {
        let e = URL(fileURLWithPath: "/t/entree-1.png"), m = URL(fileURLWithPath: "/t/masque-1.png"), s = URL(fileURLWithPath: "/t/sortie-1.png")
        XCTAssertEqual(Generatif.argumentsQwen(entree: e, masque: m, instruction: "remove the bin", taille: (1024, 768), graine: 42, sortie: s),
                       ["--model", "qwen-image-2.1-turbo", "--prompt", "remove the bin", "--image-paths", "/t/entree-1.png",
                        "--mask-image", "/t/masque-1.png", "--steps", "8", "--quantize", "8", "--low-ram", "--width", "1024", "--height", "768",
                        "--seed", "42", "--output", "/t/sortie-1.png"])
        let r = URL(fileURLWithPath: "/t/reference.png")
        let avecRef = Generatif.argumentsQwen(entree: e, masque: m, instruction: "Replace the grey area of <image_1> with the beach of <image_2>",
                                              taille: (1024, 768), graine: 1, sortie: s, reference: r)
        XCTAssertEqual(Array(avecRef[4...7]), ["--image-paths", "/t/entree-1.png", "/t/reference.png", "--mask-image"], "le masque va sur la première image")
        XCTAssertEqual(avecRef[3], "Replace the masked area of image 1 with the beach of image 2")
        XCTAssertEqual(Generatif.argumentsQwen(entree: e, masque: nil, instruction: "x", taille: (1024, 1024), graine: 1, sortie: s).filter { $0 == "--mask-image" }, [])
        let t = Generatif.tailleCible(largeur: 600, hauteur: 400, multiple: 32)
        XCTAssertEqual(t.largeur % 32, 0); XCTAssertEqual(t.hauteur % 32, 0)
        XCTAssertEqual(Double(t.largeur * t.hauteur), 1024 * 1024, accuracy: 60_000)
        XCTAssertTrue(Generatif.tailleCible(largeur: 600, hauteur: 400, multiple: 16) == Generatif.tailleCible(largeur: 600, hauteur: 400))
    }

    /// model = qwen_image_21 : sa commande, son masque, 8 étapes, rien de propre à Fibo 2 ; la réponse dit
    /// le modèle et pourquoi ; la nouvelle photo entre au catalogue comme avec Fibo 2.
    func testRetoucheParQwenDeBoutEnBout() throws {
        let region = CGRect(x: 0.05, y: 0.2, width: 0.3, height: 0.6)
        try fauxQwen(sortie: sortieQwen(region: region))
        try qwenDansLeCache()
        let resultat = editer(["instruction": "replace the bag with a red one", "instruction_fr": "un sac rouge", "model": "qwen_image_21",
                               "region": ["x": 0.05, "y": 0.2, "width": 0.3, "height": 0.6], "seed": 7, "quality": "normal", "avoid": "logos",
                               "reason": "Dany veut un sac rouge."])
        XCTAssertFalse(resultat.isError, resultat.text)
        let args = argumentsPasses
        XCTAssertEqual(appelsDeMflux, 1)
        XCTAssertEqual(Array(args.prefix(4)), ["--model", "qwen-image-2.1-turbo", "--prompt", "replace the bag with a red one"])
        XCTAssertEqual(valeur("--steps"), "8")
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(valeur("--mask-image"))).lastPathComponent, "masque-1.png")
        for propre in ["--mask-path", "--cfg-end", "--negative-prompt", "--vae-full-precision", "--prompt-file", "--guidance"] {
            XCTAssertFalse(args.contains(propre), propre)
        }
        XCTAssertTrue(args.contains("--low-ram"))
        XCTAssertEqual(valeur("--quantize"), "8", "environ 33 Go en bf16 : trop avec Lightroom ouvert")
        // La sortie de Qwen est un PNG (mflux écrit le format de --output ; « image.png » par défaut).
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(valeur("--output"))).pathExtension, "png")
        XCTAssertEqual(Int(try XCTUnwrap(valeur("--width")))! % 32, 0); XCTAssertEqual(Int(try XCTUnwrap(valeur("--height")))! % 32, 0)
        XCTAssertEqual(valeur("--seed"), "7")
        let masque = try XCTUnwrap(Self.pixels8(gardes.appendingPathComponent("masque.png")))
        XCTAssertEqual(String(masque.largeur), valeur("--width"), "le masque à la taille de l'entrée")

        let reponse = try JSONCoding.parse(resultat.text)
        XCTAssertEqual(reponse["modele"]?["id"]?.string, "qwen_image_21")
        XCTAssertEqual(reponse["modele"]?["nom"]?.string, "Qwen-Image 2.1 Turbo")
        XCTAssertEqual(reponse["modele"]?["choisi"]?.string, "demandé")
        XCTAssertEqual(reponse["modele"]?["genre"]?.string, "changer")
        XCTAssertTrue(reponse["modele"]?["pourquoi"]?.string?.contains("demandé (model = qwen_image_21)") == true, resultat.text)
        XCTAssertEqual(reponse["qualite"]?.string, "Qwen-Image 2.1 Turbo, 8 étapes, sans guidage")
        XCTAssertNil(reponse["guidage"])
        XCTAssertEqual(reponse["remarque_modele"]?.string, "quality, avoid : propres à Fibo 2, sans effet sur Qwen-Image 2.1 Turbo (8 étapes, sans guidage ni fiche).")
        XCTAssertNil(reponse["remarque_fiche"], "pas de fiche de FIBO-vlm à attendre")
        XCTAssertNil(reponse["modifications"]?.array?.first?["exclusion"])
        XCTAssertEqual(reponse["nouvelle_photo"]?["id"]?.int, 99)
        let importer = try XCTUnwrap(fake.calls.first { $0.command == "importerGeneree" }).params
        XCTAssertEqual(importer["consigne"]?.string, "un sac rouge — Dany veut un sac rouge.", "l'étape nomme le modèle, la consigne ne le redit pas")
        // L'étape et le fichier nomment le modèle employé (revue du 10 novembre 2026), pas Fibo 2.
        XCTAssertEqual(importer["etape"]?.string, "Claude · Qwen-Image 2.1 Turbo")
        XCTAssertEqual(importer["nom"]?.string, "DSCF2402-Qwen")
        XCTAssertEqual(fake.calls.first { $0.command == "exporter" }?.params["etape"]?.string, "Claude · Qwen-Image 2.1 Turbo")
        XCTAssertFalse(resultat.text.contains("Fibo 2 a") || resultat.text.contains("sortie de Fibo 2"), resultat.text)
        XCTAssertTrue(reponse["modifications"]?.array?.first?["resolution_zone"]?.string?.contains("sortie de Qwen-Image 2.1 Turbo") == true, resultat.text)
        XCTAssertTrue(fake.progressions.contains { $0["message"]?.string?.hasPrefix("Qwen-Image 2.1 Turbo : ") == true }, "la barre nomme le modèle")
        // Hors de la zone, la photo garde ses pixels.
        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        XCTAssertEqual(Self.pixel(apres, 500, 200), Self.pixel(avant, 500, 200))
        XCTAssertGreaterThan(Self.pixel(apres, Int(0.2 * Double(largeur)), hauteur / 2)[0], 45_000)
    }

    /// Avec une photo de référence : deux images, le masque sur la première, et l'entrée jamais grisée
    /// (Qwen repeint la zone blanche du masque ; le gris est propre à Fibo 2).
    func testQwenAvecReferenceSansGris() throws {
        masqueRendu = { fx, _ in fx < 0.3 }
        fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 30, green: 160, blue: 220)))]
        try fauxQwen()
        try qwenDansLeCache()
        let resultat = editer(["instruction": "Replace the grey area of <image_1> with the beach of <image_2>", "mask": ["kind": "background"],
                               "reference": ["photo_id": 12], "model": "qwen_image_21"])
        // Le faux rend son entrée : rien de changé, refusé après le calcul ; ce qui compte, c'est ce qu'il a reçu.
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("Qwen-Image 2.1 Turbo n'a rien changé de visible"), resultat.text)
        let args = argumentsPasses
        let i = try XCTUnwrap(args.firstIndex(of: "--image-paths"))
        XCTAssertEqual(URL(fileURLWithPath: args[i + 1]).lastPathComponent, "entree-1.png")
        XCTAssertEqual(URL(fileURLWithPath: args[i + 2]).lastPathComponent, "reference.png")
        XCTAssertNotNil(valeur("--mask-image"))
        XCTAssertEqual(valeur("--prompt"), "Replace the masked area of image 1 with the beach of image 2")
        let entree = try XCTUnwrap(Self.pixels8(gardes.appendingPathComponent("entree-recue-1.png")))
        XCTAssertNotEqual(entree.valeur(2, entree.hauteur / 2), 128, "dans le masque, jamais grisé pour Qwen")
    }

    /// Un modèle demandé absent de ce Mac : refusé avec sa raison, avant tout envoi à Lightroom.
    func testModeleAbsentRefuseAvantToutEnvoi() throws {
        fauxMflux()
        var resultat = editer(["instruction": "remove the bin", "region": ["x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2], "model": "qwen_image_21"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("Qwen-Image 2.1 Turbo ne peut pas tourner sur ce Mac : la commande mflux-generate-qwen-2.1-edit est introuvable"), resultat.text)
        try fauxQwen()
        resultat = editer(["instruction": "remove the bin", "region": ["x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2], "model": "qwen_image_21"])
        XCTAssertTrue(resultat.text.contains("n'est pas complet sur ce Mac"), resultat.text)
        resultat = editer(["instruction": "remove the bin", "model": "flux3_klein"])
        XCTAssertTrue(resultat.text.contains("FLUX 3 Klein n'est pas encore branché"), resultat.text)
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
        XCTAssertEqual(appelsDeMflux, 0)
    }

    /// Sans model : la table (Fibo 2), et la réponse dit le modèle, le genre et pourquoi.
    func testAutoDitLeModeleEtPourquoi() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        let resultat = editer(["instruction": "remove the red square", "seed": 3])
        XCTAssertFalse(resultat.isError, resultat.text)
        let reponse = try JSONCoding.parse(resultat.text)
        XCTAssertEqual(reponse["modele"]?["id"]?.string, "fibo2")
        XCTAssertEqual(reponse["modele"]?["choisi"]?.string, "auto")
        XCTAssertEqual(reponse["modele"]?["genre"]?.string, "photo_entiere")
        XCTAssertEqual(reponse["modele"]?["pourquoi"]?.string, "auto : Fibo 2, le modèle de la table pour « toute la photo, sans zone »")
        XCTAssertNil(reponse["remarque_modele"])
        XCTAssertNil(valeur("--model"), "Fibo 2 : sa commande, comme avant")
        XCTAssertEqual(argumentsDeLAppel(1).first, "--prompt")
        XCTAssertTrue(fake.progressions.contains { $0["message"]?.string?.hasPrefix("Fibo 2 : ") == true })
        // Un model qui n'est pas un texte : refusé.
        XCTAssertTrue(editer(["instruction": "x", "model": 3]).text.contains("« model » : auto, fibo2, qwen_image_21"))
    }

    // MARK: Banc d'essai

    /// La photo 7 en copie virtuelle d'Essais, jamais retouchée par Claude (ce que le banc contrôle).
    func photoDEssai(virtuelle: JSONValue = true, dansEssais: Bool = true, retouchee: Bool = false) {
        fake.replies["reglages"] = ["photo": ["id": 7, "fichier": "DSCF2402.RAF (Essai)", "copie_virtuelle": virtuelle],
                                    "reglages": ["Exposure2012": 0], "masques": []]
        fake.replies["chercher"] = ["photos": .array(dansEssais ? [["id": 7, "copie_virtuelle": virtuelle, "retouchee_par_claude": .bool(retouchee)]] : []),
                                    "total": dansEssais ? 1 : 0]
    }

    /// Le banc : la même retouche par chaque modèle branché et présent, même graine, rien d'importé, une
    /// planche HTML avec les images de chacun.
    func testBancDEssaiSansRienImporter() throws {
        let region = CGRect(x: 0.05, y: 0.2, width: 0.3, height: 0.6)
        let sortieFibo = sortiePreparee(region: region) { fx, fy, p, i in if fx > 0.1, fx < 0.3, fy > 0.3, fy < 0.7 { Self.rouge(&p, i) } }
        try fauxQwen()
        fauxMflux(sorties: [sortieFibo, sortieQwen(region: region)])
        // fauxMflux a réécrit le script de Fibo : celui de Qwen (copié avant) garde les mêmes sorties numérotées.
        try qwenDansLeCache()
        let planche = dossier.appendingPathComponent("banc")
        photoDEssai()
        let resultat = try BancGeneratif(tools: tools).lancer(arguments: ["photo_id": 7, "instruction": "add a red bag", "instruction_fr": "un sac rouge",
                                                                          "region": ["x": 0.05, "y": 0.2, "width": 0.3, "height": 0.6], "upscale": false],
                                                              dossier: planche)
        XCTAssertEqual(resultat["ok"]?.bool, true, JSONCoding.line(resultat))
        XCTAssertEqual(appelsDeMflux, 2)
        XCTAssertEqual(argumentsDeLAppel(1).first, "--prompt", "Fibo 2 d'abord")
        XCTAssertEqual(Array(argumentsDeLAppel(2).prefix(2)), ["--model", "qwen-image-2.1-turbo"])
        for n in [1, 2] {
            let a = argumentsDeLAppel(n)
            XCTAssertEqual(a[a.firstIndex(of: "--seed")! + 1], "42", "même graine pour tous")
        }
        XCTAssertFalse(fake.commands.contains("importerGeneree"), "rien d'importé : \(fake.commands)")
        XCTAssertNil(tools.dossierBanc, "le banc fini, generative_edit importe de nouveau")
        let modeles = try XCTUnwrap(resultat["modeles"]?.array)
        XCTAssertEqual(modeles.compactMap { $0["id"]?.string }, ["fibo2", "qwen_image_21"])
        for m in modeles {
            let images = try XCTUnwrap(m["images"]?.object, JSONCoding.line(m))
            for cle in ["avant", "image", "zone", "avant_zone"] {
                let fichier = try XCTUnwrap(images[cle]?.string, cle)
                XCTAssertNotNil(PreviewImages.image(try Data(contentsOf: planche.appendingPathComponent(fichier))), fichier)
            }
        }
        let html = try String(contentsOf: URL(fileURLWithPath: try XCTUnwrap(resultat["planche"]?.string)), encoding: .utf8)
        for attendu in ["Fibo 2", "Qwen-Image 2.1 Turbo", "un sac rouge", "graine 42", "fibo2-zone.jpg", "qwen_image_21-zone.jpg",
                        "name=\"meilleur\" value=\"qwen_image_21\"", "Copier le jugement", "prefers-color-scheme: dark"] {
            XCTAssertTrue(html.contains(attendu), attendu)
        }
        XCTAssertFalse(html.contains("http://") || html.contains("https://"), "une page locale, sans rien chargé d'ailleurs")
        // Ce que chaque modèle a reçu : la fiche de FIBO-vlm est propre à Fibo 2.
        XCTAssertTrue(html.contains("la phrase seule (la fiche de FIBO-vlm est propre à Fibo 2)"), "Qwen")
        XCTAssertTrue(html.contains("la phrase seule (sans fiche de FIBO-vlm)") || html.contains("la fiche détaillée de FIBO-vlm"), "Fibo 2")
        // La photo remise à la fin, comme la recette : revert_to_original, puis relue.
        XCTAssertEqual(fake.commands.filter { $0 == "revenir" }.count, 1, "\(fake.commands)")
        XCTAssertTrue(resultat["photo"]?.string?.contains("remise comme au départ") == true, JSONCoding.line(resultat))
    }

    /// Revue du 10 novembre 2026 : le banc contrôle la photo avant tout calcul, comme la recette (une
    /// copie virtuelle d'Essais que Claude n'a pas retouchée), et « model »: null compte comme un model.
    func testBancRefuseUnePhotoQuiNEstPasUneCopieDEssai() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        let planche = dossier.appendingPathComponent("banc")
        let appel: [String: JSONValue] = ["photo_id": 7, "instruction": "add a red square"]
        for (cas, attendu) in [("original", "est un original"), ("hors d'Essais", "n'est pas dans"), ("retouchée", "Claude a déjà retouché"),
                               ("module ancien", "installer la même version")] {
            photoDEssai(virtuelle: cas == "original" ? false : cas == "module ancien" ? .null : true,
                        dansEssais: cas != "hors d'Essais", retouchee: cas == "retouchée")
            if cas == "module ancien" {
                fake.replies["reglages"] = ["photo": ["id": 7, "fichier": "DSCF2402.RAF"], "reglages": [:], "masques": []]
            }
            XCTAssertThrowsError(try BancGeneratif(tools: tools).lancer(arguments: appel, dossier: planche), cas) { erreur in
                XCTAssertTrue(erreur.localizedDescription.contains(attendu), "\(cas) : \(erreur.localizedDescription)")
            }
        }
        XCTAssertEqual(appelsDeMflux, 0, "aucun calcul")
        XCTAssertFalse(fake.commands.contains { ["exporter", "essayer", "revenir"].contains($0) }, "\(fake.commands)")
        photoDEssai()
        XCTAssertThrowsError(try BancGeneratif(tools: tools).lancer(arguments: ["photo_id": 7, "model": .null], dossier: planche)) { erreur in
            XCTAssertTrue(erreur.localizedDescription.contains("sans model"), erreur.localizedDescription)
        }
    }

    /// Une photo pas revenue comme au départ : le banc le dit (ok faux), il ne s'en tait pas.
    func testBancDitUnePhotoPasRevenue() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        photoDEssai()
        var lectures = 0
        let avant = fake.onSend
        fake.onSend = { [unowned self] commande, params in
            avant?(commande, params)
            if commande == "reglages" {
                lectures += 1
                if lectures > 1 { self.fake.replies["reglages"] = ["photo": ["id": 7, "copie_virtuelle": true], "reglages": ["Exposure2012": 1], "masques": []] }
            }
        }
        let resultat = try BancGeneratif(tools: tools).lancer(arguments: ["photo_id": 7, "instruction": "add a red square"],
                                                              modeles: ["fibo2"], dossier: dossier.appendingPathComponent("banc"))
        XCTAssertEqual(resultat["ok"]?.bool, false, JSONCoding.line(resultat))
        XCTAssertTrue(resultat["photo"]?.string?.contains("PAS revenue") == true, JSONCoding.line(resultat))
    }

    /// Un modèle absent : dit sur la planche, les autres passent ; le banc exige photo_id et refuse model.
    func testBancAvecUnModeleAbsentEtRefus() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        photoDEssai()
        let planche = dossier.appendingPathComponent("banc")
        let resultat = try BancGeneratif(tools: tools).lancer(arguments: ["photo_id": 7, "instruction": "add a red square", "instruction_fr": "carré"],
                                                              dossier: planche)
        XCTAssertEqual(resultat["ok"]?.bool, true)
        XCTAssertEqual(appelsDeMflux, 1)
        XCTAssertTrue(resultat["modeles"]?.array?[1]["absent"]?.string?.contains("mflux-generate-qwen-2.1-edit est introuvable") == true,
                      JSONCoding.line(resultat))
        let html = try String(contentsOf: planche.appendingPathComponent(BancGeneratif.nomPlanche), encoding: .utf8)
        XCTAssertTrue(html.contains("Absent de ce Mac"))
        XCTAssertThrowsError(try BancGeneratif(tools: tools).lancer(arguments: ["instruction": "x"], dossier: planche))
        XCTAssertThrowsError(try BancGeneratif(tools: tools).lancer(arguments: ["photo_id": 7, "model": "fibo2"], dossier: planche))
        XCTAssertThrowsError(try BancGeneratif(tools: tools).lancer(arguments: ["photo_id": 7], modeles: ["flux3_klein"], dossier: planche))
    }
}
