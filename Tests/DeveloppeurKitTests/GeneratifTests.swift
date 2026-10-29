import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import DeveloppeurKit

/// generative_edit (Fibo 2, 29 octobre 2026) : un faux mflux et un faux SeedVR2 (scripts shell), un
/// faux module qui exporte un vrai petit TIFF 16 bits et reçoit importerGeneree, des dossiers
/// temporaires. Jamais le vrai mflux, ni le vrai SeedVR2, ni le vrai Lightroom, ni une vraie photo.
final class GeneratifTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!
    var dossier: URL!
    var racine: URL { dossier.appendingPathComponent("racine") }
    var gardes: URL { dossier.appendingPathComponent("gardes") }
    var script: URL { dossier.appendingPathComponent("bin/mflux-generate-fibo2-edit") }
    /// Le faux SeedVR2, à côté du faux mflux (là où Fibo le cherche par défaut) ; absent sauf essai.
    var scriptSeedVR: URL { dossier.appendingPathComponent("bin/mflux-upscale-seedvr2") }
    /// Le TIFF que le faux module exporte (le « développé » de la photo 7).
    var source: URL { dossier.appendingPathComponent("source.tif") }
    /// Copie du TIFF final reçu par importerGeneree (le dossier temporaire est effacé après).
    var importe: URL { gardes.appendingPathComponent("importe.tif") }
    var largeur = 600, hauteur = 400
    /// Un mflux lancé hors du serveur (Fibo 2 Studio) : jamais le vrai pgrep dans les tests.
    var autreCalcul = false

    override func setUp() {
        dossier = TestSupport.temporaryDirectory()
        for sous in [racine, gardes, script.deletingLastPathComponent()] {
            try? FileManager.default.createDirectory(at: sous, withIntermediateDirectories: true)
        }
        ecrireSource(largeur: 600, hauteur: 400)
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake, guideStyle: GuideStyle(fichier: dossier.appendingPathComponent("guide.md")))
        tools.fibo = Fibo(executable: script, cacheHF: dossier.appendingPathComponent("hf"), racine: racine, delaiMax: 60,
                          delaiReessaiImport: 0.05, autreCalcul: { [unowned self] in self.autreCalcul })
        fake.replies["etat"] = ["mode": "appliquer directement", "pause": false, "photo_active": ["id": 7]]
        fake.replies["importerGeneree"] = ["id": 99, "fichier": "DSCF2402-Fibo.tif", "chemin": "/Volumes/Photos/2026/DSCF2402-Fibo.tif",
                                           "empilee": true, "active": true]
        fake.onSend = { [unowned self] commande, params in
            switch commande {
            case "exporter":
                let cible = URL(fileURLWithPath: params["dossier"]?.string ?? "/nulle-part").appendingPathComponent("DSCF2402.tif")
                try? FileManager.default.copyItem(at: self.source, to: cible)
                self.fake.replies["exporter"] = ["dossier": .string(cible.deletingLastPathComponent().path), "format": "TIFF",
                                                 "fichiers": [["photo": ["id": 7, "fichier": "DSCF2402.RAF"], "chemin": .string(cible.path), "octets": 1000]]]
            case "importerGeneree":
                try? FileManager.default.removeItem(at: self.importe)
                try? FileManager.default.copyItem(atPath: params["chemin"]?.string ?? "", toPath: self.importe.path)
            default: break
            }
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dossier)
    }

    // MARK: Aides

    /// Le TIFF « développé » de la photo 7, en dégradé, à la taille donnée.
    func ecrireSource(largeur l: Int, hauteur h: Int) {
        largeur = l; hauteur = h
        try? FileManager.default.removeItem(at: source)
        Self.ecrireTIFF16(source, largeur: l, hauteur: h) { x, y in
            (UInt16(x * 65535 / l), UInt16(y * 65535 / h), UInt16((x + y) * 65535 / (l + h)))
        }
    }

    /// Un TIFF RGB 16 bits Adobe RGB, avec Exif, IPTC, GPS et TIFF, comme une exportation de Lightroom,
    /// et des champs qui n'existent qu'en XMP (libellé, mots-clés hiérarchiques de Lightroom).
    static func ecrireTIFF16(_ url: URL, largeur: Int, hauteur: Int, _ couleur: (Int, Int) -> (UInt16, UInt16, UInt16)) {
        var pixels = [UInt16](repeating: 0, count: largeur * hauteur * 3)
        for y in 0..<hauteur {
            for x in 0..<largeur {
                let i = (y * largeur + x) * 3
                (pixels[i], pixels[i + 1], pixels[i + 2]) = couleur(x, y)
            }
        }
        let donnees = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        let image = CGImage(width: largeur, height: hauteur, bitsPerComponent: 16, bitsPerPixel: 48, bytesPerRow: largeur * 6,
                            space: CGColorSpace(name: CGColorSpace.adobeRGB1998)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                            provider: CGDataProvider(data: donnees as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let proprietes: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:20 14:30:00", kCGImagePropertyExifLensModel: "XF23mmF1.4 R"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCaptionAbstract: "Légende d'essai", kCGImagePropertyIPTCKeywords: ["essai", "Fibo"]],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 45.5, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 73.6, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "FUJIFILM", kCGImagePropertyTIFFModel: "X-H2S"],
        ]
        let xmp = CGImageMetadataCreateMutable()
        CGImageMetadataSetValueWithPath(xmp, nil, "xmp:Label" as CFString, "Rouge" as CFString)
        CGImageMetadataRegisterNamespaceForPrefix(xmp, "http://ns.adobe.com/lightroom/1.0/" as CFString, "lr" as CFString, nil)
        CGImageMetadataSetValueWithPath(xmp, nil, "lr:hierarchicalSubject" as CFString, ["Lieux|Montréal"] as CFArray)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)!
        CGImageDestinationAddImageAndMetadata(destination, image, xmp, proprietes as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// Les pixels RGB 16 bits d'un TIFF, dessinés dans son propre espace (aucune conversion).
    static func pixels16(_ url: URL) -> (largeur: Int, hauteur: Int, pixels: [UInt16])? {
        guard let (image, _) = Generatif.lireImage(url), let espace = image.colorSpace,
              let contexte = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 16, bytesPerRow: image.width * 8,
                                       space: espace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue) else { return nil }
        contexte.interpolationQuality = .none
        contexte.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let n = image.width * image.height * 4
        let p = contexte.data!.bindMemory(to: UInt16.self, capacity: n)
        return (image.width, image.height, Array(UnsafeBufferPointer(start: p, count: n)))
    }

    /// Un pixel (x, y depuis le haut gauche) de pixels16.
    static func pixel(_ lu: (largeur: Int, hauteur: Int, pixels: [UInt16]), _ x: Int, _ y: Int) -> [UInt16] {
        let i = (y * lu.largeur + x) * 4
        return Array(lu.pixels[i..<i + 3])
    }

    /// L'entrée de Fibo telle que le connecteur la prépare (sRGB 8 bits ; la photo entière à ~1 Mpx,
    /// ou le recadrage autour de `region`), changée par `changer` (fx, fy : la position dans la photo
    /// entière, de 0 à 1), écrite en PNG : ce que le faux mflux rendra.
    func sortiePreparee(region: CGRect? = nil, nom: String = "preparee.png", _ changer: (Double, Double, inout [UInt8], Int) -> Void) -> URL {
        let (image, _) = Generatif.lireImage(source)!
        let cadre: Generatif.Pixels, taille: (largeur: Int, hauteur: Int)
        if let region {
            (cadre, taille) = Generatif.recadrage(region, largeur: image.width, hauteur: image.height)
        } else {
            cadre = Generatif.Pixels(x: 0, y: 0, largeur: image.width, hauteur: image.height)
            taille = Generatif.tailleCible(largeur: image.width, hauteur: image.height)
        }
        var pixels = Generatif.entree(image, cadre: region == nil ? nil : cadre, taille: taille)!
        for y in 0..<taille.hauteur {
            for x in 0..<taille.largeur {
                let fx = (Double(cadre.x) + (Double(x) + 0.5) * Double(cadre.largeur) / Double(taille.largeur)) / Double(image.width)
                let fy = (Double(cadre.y) + (Double(y) + 0.5) * Double(cadre.hauteur) / Double(taille.hauteur)) / Double(image.height)
                changer(fx, fy, &pixels, (y * taille.largeur + x) * 4)
            }
        }
        let url = gardes.appendingPathComponent(nom)
        try? Generatif.ecrirePNG(Generatif.image8(pixels, largeur: taille.largeur, hauteur: taille.hauteur)!, vers: url)
        return url
    }

    /// Le faux mflux : compte ses appels, note ses arguments (un par ligne, dans arguments.txt et
    /// arguments-<n>.txt), garde le masque, écrit une barre tqdm, puis copie vers --output la sortie
    /// préparée de cet appel (`sorties`, une par appel), sinon `sortie`, sinon sa dernière image
    /// d'entrée ; `fin` remplace la fin du script.
    func fauxMflux(sortie: URL? = nil, sorties: [URL] = [], fin: String? = nil) {
        for (rang, url) in sorties.enumerated() {
            let cible = gardes.appendingPathComponent("sortie-\(rang + 1).png")
            try? FileManager.default.removeItem(at: cible)
            try? FileManager.default.copyItem(at: url, to: cible)
        }
        let commune = gardes.appendingPathComponent("sortie.png")
        try? FileManager.default.removeItem(at: commune)
        if let sortie { try? FileManager.default.copyItem(at: sortie, to: commune) }
        let g = gardes.path
        let texte = """
        #!/bin/sh
        n=$(cat "\(g)/compte" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "\(g)/compte"
        printf '%s\\n' "$@" > "\(g)/arguments-$n.txt"
        cp "\(g)/arguments-$n.txt" "\(g)/arguments.txt"
        echo $$ > "\(g)/pid.txt"
        out=""; img=""; mask=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --output) out="$2"; shift ;;
            --image-paths) img="$2"; shift ;;
            --mask-path) mask="$2"; shift ;;
          esac
          shift
        done
        [ -n "$mask" ] && cp "$mask" "\(g)/masque.png"
        \(fin ?? """
        printf '  0/50 [00:00\\r 25/50 [00:01\\r 50/50 [00:02\\n' >&2
        if [ -f "\(g)/sortie-$n.png" ]; then cp "\(g)/sortie-$n.png" "$out"
        elif [ -f "\(g)/sortie.png" ]; then cp "\(g)/sortie.png" "$out"
        else cp "$img" "$out"; fi
        """)
        """
        try? texte.write(to: script, atomically: true, encoding: .utf8)
        chmod(script.path, 0o755)
        try? FileManager.default.removeItem(at: gardes.appendingPathComponent("compte"))
    }

    /// Le faux SeedVR2 : note ses arguments, puis copie son image d'entrée vers --output (ou `fin`).
    func fauxSeedVR(fin: String? = nil) {
        let g = gardes.path
        let texte = """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(g)/seedvr-arguments.txt"
        out=""; img=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --output) out="$2"; shift ;;
            --image-path) img="$2"; shift ;;
          esac
          shift
        done
        \(fin ?? """
        printf ' 1/1 [00:01\\n' >&2
        cp "$img" "$out"
        """)
        """
        try? texte.write(to: scriptSeedVR, atomically: true, encoding: .utf8)
        chmod(scriptSeedVR.path, 0o755)
    }

    var argumentsSeedVR: [String]? {
        (try? String(contentsOf: gardes.appendingPathComponent("seedvr-arguments.txt"), encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast().map { $0 }
    }

    func valeurSeedVR(_ option: String) -> String? {
        guard let args = argumentsSeedVR else { return nil }
        return args.firstIndex(of: option).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    func argumentsDeLAppel(_ n: Int) -> [String] {
        (try? String(contentsOf: gardes.appendingPathComponent("arguments-\(n).txt"), encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast().map { $0 } ?? []
    }

    var appelsDeMflux: Int {
        Int((try? String(contentsOf: gardes.appendingPathComponent("compte"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    var argumentsPasses: [String] {
        (try? String(contentsOf: gardes.appendingPathComponent("arguments.txt"), encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast().map { $0 } ?? []
    }

    func valeur(_ option: String) -> String? {
        let args = argumentsPasses
        return args.firstIndex(of: option).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    /// generative_edit, avec une traduction française d'office pour une instruction simple.
    func editer(_ arguments: [String: JSONValue]) -> ToolResult {
        var args = arguments
        if args["instruction"] != nil, args["instruction_fr"] == nil { args["instruction_fr"] = "traduction de l'instruction" }
        return tools.call(name: "generative_edit", arguments: args)
    }

    var dossiersTemporairesRestants: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: racine.appendingPathComponent("Temporaire/Fibo").path)) ?? []
    }

    /// Un carré rouge au milieu de la photo (de 40 à 60 % en largeur, de 35 à 65 % en hauteur).
    func carreRouge(_ fx: Double, _ fy: Double, _ p: inout [UInt8], _ i: Int) {
        if fx > 0.4, fx < 0.6, fy > 0.35, fy < 0.65 { p[i] = 230; p[i + 1] = 20; p[i + 2] = 20 }
    }

    static func rouge(_ p: inout [UInt8], _ i: Int) { p[i] = 230; p[i + 1] = 20; p[i + 2] = 20 }
    static func bleu(_ p: inout [UInt8], _ i: Int) { p[i] = 20; p[i + 1] = 20; p[i + 2] = 230 }

    // MARK: Calculs purs

    func testTailleCibleUnMegapixelMultipleDe16() {
        for (l, h) in [(6240, 4160), (4160, 6240), (600, 400), (8000, 1000), (1000, 1000)] {
            let t = Generatif.tailleCible(largeur: l, hauteur: h)
            XCTAssertEqual(t.largeur % 16, 0); XCTAssertEqual(t.hauteur % 16, 0)
            XCTAssertEqual(Double(t.largeur * t.hauteur), 1_048_576, accuracy: 120_000, "\(l)×\(h) → \(t)")
            XCTAssertEqual(Double(t.largeur) / Double(t.hauteur), Double(l) / Double(h), accuracy: 0.03 * Double(l) / Double(h), "même proportion, aux multiples de 16 près")
        }
        XCTAssertTrue(Generatif.tailleCible(largeur: 6240, hauteur: 4160) == (1248, 832))
    }

    func testProgressionEtLignes() {
        XCTAssertEqual(Generatif.progression(" 12/50 [00:30<01:40,  2.0s/it]", etapes: 50), 12)
        XCTAssertNil(Generatif.progression(" 12/50 [00:30", etapes: 4), "une autre barre (téléchargement)")
        XCTAssertNil(Generatif.progression("Loading 3 files", etapes: 50))
        var lignes = Generatif.Lignes()
        XCTAssertEqual(lignes.ajouter("  1/4 [00:01\r  2/4 [00"), ["  1/4 [00:01"])
        XCTAssertEqual(lignes.ajouter(":02\nfin"), ["  2/4 [00:02"])
        XCTAssertEqual(lignes.finir(), ["fin"])
    }

    func testUneBarreDeTelechargementNEstPasUnAccesRefuse() {
        let journal = "model.safetensors:   4%|▍         | 401M/9.95G [00:10<03:58, 40.1MB/s]\nRuntimeError: out of memory 403 blocks"
        let texte = Generatif.expliquer(journal: journal, code: 1, rapide: false)
        XCTAssertFalse(texte.contains("accès au modèle refusé"), texte)
        XCTAssertTrue(texte.contains("code 1") && texte.contains("out of memory"), texte)
        XCTAssertTrue(Generatif.expliquer(journal: "requests.exceptions.HTTPError: 401 Client Error: Unauthorized for url", code: 1, rapide: false)
            .contains("accès au modèle refusé"))
    }

    /// Un trait d'un pixel retiré (un fil électrique, écart 0,5) entre dans la zone changée.
    func testTraitFinRetireDansLaZoneChangee() {
        // À la taille de l'entrée de Fibo (~1 Mpx), où l'ancien flou de 5 × 5 l'effaçait.
        let l = 1248, h = 832
        var entree = [UInt8](repeating: 0, count: l * h * 4)
        for i in 0..<(l * h) { entree[i * 4] = 120; entree[i * 4 + 1] = 160; entree[i * 4 + 2] = 220 }
        let sortie = entree
        for x in 100..<1100 {
            let i = (400 * l + x) * 4
            entree[i] = 120 - 100; entree[i + 1] = 160 - 120; entree[i + 2] = 220 - 120   // le fil (écart 0,47), sur l'entrée
        }
        let zone = Generatif.zoneChangee(entree: entree, sortie: sortie, largeur: l, hauteur: h, region: nil)
        XCTAssertGreaterThan(zone[400 * l + 600], 0.5, "le fil retiré est dans la zone changée")
        XCTAssertGreaterThan(Generatif.part(zone), Generatif.partMinimale)
        XCTAssertEqual(zone[50 * l + 600], 0, "loin du fil, rien")
    }

    /// Avec une zone donnée, la recomposition prend toute la zone (Fibo n'a travaillé que là) ; sans
    /// zone, la zone changée, ou toute l'image au-delà de 60 %, avec sa remarque en part de l'image.
    func testZoneDeMelange() {
        let l = 200, h = 100
        let changee = [Float](repeating: 0, count: l * h)
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let (avecZone, entiere) = Generatif.zoneDeMelange(changee: changee, region: region, largeur: l, hauteur: h)
        XCTAssertFalse(entiere)
        XCTAssertEqual(avecZone[50 * l + 100], 1, accuracy: 0.001, "toute la zone donnée, même sans changement mesuré")
        XCTAssertEqual(avecZone[2 * l + 2], 0, "hors de la zone, rien")
        XCTAssertEqual(Generatif.zoneDeMelange(changee: changee, region: nil, largeur: l, hauteur: h).zone, changee)
        let presqueTout = [Float](repeating: 1, count: l * h)
        XCTAssertTrue(Generatif.zoneDeMelange(changee: presqueTout, region: nil, largeur: l, hauteur: h).sortieEntiere)
        XCTAssertFalse(Generatif.zoneDeMelange(changee: presqueTout, region: region, largeur: l, hauteur: h).sortieEntiere)
        let remarque = Generatif.remarqueSortieEntiere(partChangee: 0.7, sortieEntiere: true) ?? ""
        XCTAssertTrue(remarque.contains("70 % de l'image"), remarque)
        XCTAssertNil(Generatif.remarqueSortieEntiere(partChangee: 0.7, sortieEntiere: false))
    }

    func testCeQuIlFautSavoirDeLaNouvellePhoto() {
        XCTAssertTrue(ToolHandler.aSavoir(["empilee": true, "active": true], id: 99).contains("empilée au-dessus de lui et devient la photo active"))
        let essai = ToolHandler.aSavoir(["empilee": false, "essai": true], id: 99)
        XCTAssertTrue(essai.contains("Développeur › Essais") && essai.contains("sans pile"), essai)
        let copie = ToolHandler.aSavoir(["empilee": true, "copie_virtuelle": true, "photo_fibo": 98], id: 99)
        XCTAssertTrue(copie.contains("sa copie virtuelle devient la photo active") && copie.contains("par son id 99"), copie)
    }

    func testErreursExpliquees() {
        XCTAssertTrue(Generatif.expliquer(journal: "huggingface_hub.errors.GatedRepoError: 403", code: 1, rapide: false).contains("huggingface.co/briaai/Fibo-2.0-dev"))
        XCTAssertTrue(Generatif.expliquer(journal: "RevisionNotFound", code: 1, rapide: true).contains("hf download briaai/Fibo-2.0-edit-turbo"))
        XCTAssertTrue(Generatif.expliquer(journal: "ConnectionError: Max retries", code: 1, rapide: false).contains("connexion Internet"))
        let autre = Generatif.expliquer(journal: "a\nb\nc\nValueError: boom", code: 2, rapide: false)
        XCTAssertTrue(autre.contains("code 2") && autre.contains("b\nc\nValueError: boom") && !autre.contains("a\n"), autre)
    }

    func testNomDeLaNouvellePhoto() {
        XCTAssertEqual(ToolHandler.nomGenere(URL(fileURLWithPath: "/t/DSCF2402.tif")), "DSCF2402-Fibo")
        XCTAssertEqual(ToolHandler.nomGenere(URL(fileURLWithPath: "/t/DSCF2402-Fibo-2.tif")), "DSCF2402-Fibo", "pas de « -Fibo-Fibo »")
    }

    func testMasqueDeLaRegionElargi() {
        let masque = Generatif.masqueRegion(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), largeur: 400, hauteur: 200)
        XCTAssertEqual(masque.count, 80_000)
        XCTAssertEqual(masque[150 * 400 + 200], 255, "dans la zone")
        XCTAssertEqual(masque[98 * 400 + 200], 255, "dans la marge (6 px)")
        XCTAssertEqual(masque[50 * 400 + 200], 0, "loin au-dessus")
        XCTAssertEqual(masque[150 * 400 + 10], 0, "loin à gauche")
    }

    // MARK: L'outil

    func testDefinitionAnnotationsEtDescription() throws {
        XCTAssertTrue(ToolHandler.toolNames.contains("generative_edit"))
        let outil = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "generative_edit" })
        XCTAssertEqual(outil["annotations"]?["readOnlyHint"]?.bool, false)
        XCTAssertEqual(outil["annotations"]?["destructiveHint"]?.bool, false)
        XCTAssertEqual(outil["title"]?.string, "Retouche générative (Fibo 2)")
        let description = try XCTUnwrap(outil["description"]?.string)
        XCTAssertLessThanOrEqual(description.count, 1200, "\(description.count) caractères")
        XCTAssertTrue(description.hasPrefix("Retouche générative par Fibo 2"))
        for attendu in ["seulement sur demande explicite de l'utilisateur", "jamais d'initiative", "changer un vêtement", "en anglais", "region", "Quelques minutes",
                        "puis les finitions", "confirm = true", "instruction_fr", "edits", "pose, lumière, reste du corps", "add_mask"] {
            XCTAssertTrue(description.contains(attendu), attendu)
        }
        for mot in ["photoshop", "firefly", "agrandissement"] {
            XCTAssertFalse(JSONCoding.line(outil).lowercased().contains(mot), mot)
        }
        XCTAssertEqual(outil["inputSchema"]?["required"], [], "instruction ou edits")
        let proprietes = try XCTUnwrap(outil["inputSchema"]?["properties"]?.object)
        XCTAssertEqual(Set(proprietes.keys), ["photo_id", "instruction", "instruction_fr", "region", "label", "edits", "upscale", "quality", "seed", "confirm", "reason"])
        XCTAssertEqual(proprietes["edits"]?["maxItems"]?.int, 4)
        XCTAssertEqual(proprietes["edits"]?["items"]?["required"], ["instruction", "instruction_fr", "region"])
        XCTAssertTrue(ServerInfo.instructions.contains("generative_edit, sur sa demande"))
        XCTAssertFalse(ServerInfo.instructions.contains("suppression générative"))
    }

    /// Un ToolHandler neuf ne connaît pas Fibo 2 : jamais le vrai mflux dans un essai.
    func testSansFiboConfigureRienNeSeLance() {
        let neuf = ToolHandler(lightroom: fake, guideStyle: GuideStyle(fichier: dossier.appendingPathComponent("guide.md")))
        XCTAssertNil(neuf.fibo)
        let resultat = neuf.call(name: "generative_edit", arguments: ["instruction": "replace the trousers with a skirt"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("Fibo 2 n'est pas configuré"), resultat.text)
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
    }

    /// Une photo d'essai et « Copies virtuelles seulement » : la réponse du module passe à Claude.
    func testReponseDuModulePourUnEssaiEtUneCopie() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        fake.replies["importerGeneree"] = ["id": 100, "fichier": "DSCF2402-Fibo.tif", "chemin": "/Volumes/Photos/2026/DSCF2402-Fibo.tif",
                                           "empilee": false, "essai": true, "active": true, "copie_virtuelle": true, "photo_fibo": 99]
        let resultat = editer(["instruction": "add a red bag"])
        XCTAssertFalse(resultat.isError, resultat.text)
        let reponse = try JSONCoding.parse(resultat.text)
        XCTAssertEqual(reponse["nouvelle_photo"]?["id"]?.int, 100)
        XCTAssertEqual(reponse["nouvelle_photo"]?["essai"]?.bool, true)
        XCTAssertEqual(reponse["nouvelle_photo"]?["empilee"]?.bool, false)
        XCTAssertEqual(reponse["nouvelle_photo"]?["photo_fibo"]?.int, 99)
        let aSavoir = reponse["a_savoir"]?.string ?? ""
        XCTAssertTrue(aSavoir.contains("Développeur › Essais") && aSavoir.contains("copie virtuelle"), aSavoir)
        XCTAssertFalse(aSavoir.contains("empilée au-dessus"), aSavoir)
    }

    /// L'arrêt du serveur (fin de l'entrée) arrête mflux et efface le dossier de l'appel.
    func testArretDuServeurArreteMflux() throws {
        fauxMflux(fin: "exec sleep 30")
        let fini = expectation(description: "fin de l'appel")
        DispatchQueue.global().async {
            _ = self.tools.call(name: "generative_edit", arguments: ["instruction": "x", "instruction_fr": "x"])
            fini.fulfill()
        }
        let pidFichier = gardes.appendingPathComponent("pid.txt")
        let attente = Date().addingTimeInterval(10)
        while (!FileManager.default.fileExists(atPath: pidFichier.path) || tools.travailFibo.enCours == nil), Date() < attente { usleep(50_000) }
        let pid = try XCTUnwrap(Int32((try? String(contentsOf: pidFichier, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
        XCTAssertEqual(dossiersTemporairesRestants.count, 1)
        tools.travailFibo.arreter()
        XCTAssertNotEqual(kill(pid, 0), 0, "mflux est arrêté")
        XCTAssertEqual(dossiersTemporairesRestants, [], "le dossier de l'appel est effacé")
        wait(for: [fini], timeout: 15)
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
    }

    func testExecutableAbsentRefuseSansRienEnvoyer() {
        let resultat = editer(["instruction": "replace the trousers with a skirt"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("uv tool install mflux"), resultat.text)
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
    }

    func testArgumentsInvalides() {
        fauxMflux()
        XCTAssertTrue(editer([:]).isError)
        XCTAssertTrue(editer(["instruction": "  "]).text.contains("instruction"))
        XCTAssertTrue(editer(["instruction": "x", "quality": "max"]).text.contains("normal ou fast"))
        XCTAssertTrue(editer(["instruction": "x", "region": ["x": 0.8, "y": 0, "width": 0.5, "height": 0.5]]).text.contains("region"))
        XCTAssertTrue(editer(["instruction": "x", "seed": -1]).text.contains("seed"))
        XCTAssertTrue(tools.call(name: "generative_edit", arguments: ["instruction": "x"]).text.contains("instruction_fr"), "traduction exigée")
        // Le mode à deux images est retiré (essai du 29 octobre 2026) : « context » est un paramètre
        // inconnu comme un autre, refusé avant tout envoi.
        let contexte = editer(["instruction": "x", "region": ["x": 0.3, "y": 0.4, "width": 0.2, "height": 0.3], "context": "full_and_crop"])
        XCTAssertTrue(contexte.isError && contexte.text.contains("context"), contexte.text)
        XCTAssertTrue(editer(["edits": []]).text.contains("de 1 à 4"))
        let cinq: [JSONValue] = (0..<5).map { k in ["instruction": "x", "instruction_fr": "x", "region": ["x": .number(0.18 * Double(k)), "y": 0, "width": 0.1, "height": 0.1]] }
        XCTAssertTrue(editer(["edits": .array(cinq)]).text.contains("de 1 à 4"))
        XCTAssertTrue(editer(["edits": [["instruction": "x", "instruction_fr": "x", "couleur": "rouge"]]]).text.contains("couleur"))
        // Une zone en texte JSON (ou en liste) n'est jamais prise pour une absence de zone.
        let enTexte = editer(["instruction": "x", "region": "{\"x\":0.3,\"y\":0.4,\"width\":0.2,\"height\":0.3}"])
        XCTAssertTrue(enTexte.isError && enTexte.text.contains("un objet { x, y, width, height }"), enTexte.text)
        XCTAssertTrue(editer(["instruction": "x", "region": [0.3, 0.4, 0.2, 0.3]]).text.contains("un objet { x, y, width, height }"))
        XCTAssertTrue(editer(["edits": [["instruction": "x", "instruction_fr": "x", "region": "0.3 0.4 0.2 0.3"]]]).text.contains("un objet { x, y, width, height }"))
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
    }

    func testProposerDAbordExigeConfirm() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        fake.replies["etat"] = ["mode": "proposer d'abord", "pause": false, "photo_active": ["id": 7]]
        let refus = editer(["instruction": "replace the trousers with a skirt"])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("confirm = true"), refus.text)
        XCTAssertEqual(fake.commands, ["etat"])
        let accord = editer(["instruction": "replace the trousers with a skirt", "confirm": true])
        XCTAssertFalse(accord.isError, accord.text)
        XCTAssertEqual(fake.calls.first { $0.command == "exporter" }?.params["confirme"]?.bool, true)
        XCTAssertEqual(fake.calls.first { $0.command == "importerGeneree" }?.params["confirme"]?.bool, true)

        fake.replies["etat"] = ["mode": "appliquer directement", "pause": true, "photo_active": ["id": 7]]
        XCTAssertTrue(editer(["instruction": "x", "confirm": true]).text.contains("pause"))
    }

    /// Le déroulé entier : exportation demandée telle quelle, arguments de mflux, recomposition
    /// (hors de la zone changée, les pixels du TIFF exporté ; dans la zone, la sortie de Fibo),
    /// métadonnées gardées, importerGeneree conforme au contrat, dossier temporaire effacé.
    func testRetoucheEntiere() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        let resultat = editer(["photo_id": 7, "instruction": "replace the trousers with a knee-length navy skirt", "seed": 42,
                               "instruction_fr": "remplacer le pantalon par une jupe marine aux genoux", "label": "jupe",
                               "reason": "Dany veut une jupe à la place du pantalon."])
        XCTAssertFalse(resultat.isError, resultat.text)
        let reponse = try JSONCoding.parse(resultat.text)

        // L'exportation : TIFF 16 bits Adobe RGB, taille réelle, toutes les métadonnées, sans filigrane ni réimportation.
        let exporter = try XCTUnwrap(fake.calls.first { $0.command == "exporter" }).params
        XCTAssertEqual(exporter["photos"], [7])
        XCTAssertEqual(exporter["reglages"], ["format": "TIFF", "espace": "AdobeRGB", "profondeur": 16, "metadonnees": "all", "sans_lieu": false])
        XCTAssertEqual(exporter["confirme"]?.bool, false)
        // L'étape et la consigne, que la fenêtre de la liaison montre avec une demande d'accord.
        XCTAssertEqual(exporter["etape"]?.string, "Claude · Fibo 2")
        XCTAssertEqual(exporter["raison"]?.string, "remplacer le pantalon par une jupe marine aux genoux — Dany veut une jupe à la place du pantalon.",
                       "le texte français, pour Dany")
        let dossierExport = try XCTUnwrap(exporter["dossier"]?.string)
        XCTAssertTrue(dossierExport.hasPrefix(racine.appendingPathComponent("Temporaire/Fibo").path + "/"), dossierExport)

        // mflux : qualité normale, 50 étapes, pleine précision, graine, taille multiple de 16, pas de
        // masque ; jamais --quantize ni --step-cache-ratio.
        let taille = Generatif.tailleCible(largeur: largeur, hauteur: hauteur)
        XCTAssertEqual(valeur("--prompt"), "replace the trousers with a knee-length navy skirt")
        XCTAssertEqual(valeur("--steps"), "50")
        XCTAssertTrue(argumentsPasses.contains("--vae-full-precision"), "\(argumentsPasses)")
        XCTAssertTrue(argumentsPasses.contains("--low-ram"), "\(argumentsPasses)")
        XCTAssertFalse(argumentsPasses.contains("--quantize") || argumentsPasses.contains("-q") || argumentsPasses.contains("--step-cache-ratio"))
        XCTAssertEqual(valeur("--seed"), "42")
        XCTAssertEqual(valeur("--width"), String(taille.largeur)); XCTAssertEqual(valeur("--height"), String(taille.hauteur))
        XCTAssertEqual(Int(valeur("--width")!)! % 16, 0); XCTAssertEqual(Int(valeur("--height")!)! % 16, 0)
        XCTAssertEqual(URL(fileURLWithPath: valeur("--image-paths")!).lastPathComponent, "entree-1.png")
        XCTAssertNil(valeur("--mask-path")); XCTAssertNil(valeur("--model"))
        XCTAssertTrue(valeur("--output")!.hasPrefix(dossierExport))

        // importerGeneree : le contrat.
        let importer = try XCTUnwrap(fake.calls.first { $0.command == "importerGeneree" }).params
        XCTAssertEqual(Set(importer.keys), ["photo", "chemin", "nom", "consigne", "confirme"])
        XCTAssertEqual(importer["photo"]?.int, 7)
        XCTAssertEqual(importer["nom"]?.string, "DSCF2402-Fibo")
        XCTAssertEqual(importer["chemin"]?.string, dossierExport + "/DSCF2402-Fibo.tif")
        XCTAssertEqual(importer["consigne"]?.string, "remplacer le pantalon par une jupe marine aux genoux — Dany veut une jupe à la place du pantalon.")
        XCTAssertEqual(importer["confirme"]?.bool, false)
        XCTAssertEqual(fake.commands, ["etat", "exporter", "importerGeneree"])

        // La réponse.
        XCTAssertEqual(reponse["nouvelle_photo"]?["id"]?.int, 99)
        XCTAssertEqual(reponse["nouvelle_photo"]?["active"]?.bool, true)
        XCTAssertEqual(reponse["graine"]?.int, 42)
        XCTAssertNil(reponse["sortie_entiere"])
        let modification = try XCTUnwrap(reponse["modifications"]?.array?.first)
        XCTAssertEqual(reponse["modifications"]?.array?.count, 1)
        XCTAssertEqual(modification["label"]?.string, "jupe")
        XCTAssertEqual(modification["instruction"]?.string, "replace the trousers with a knee-length navy skirt")
        XCTAssertEqual(modification["instruction_fr"]?.string, "remplacer le pantalon par une jupe marine aux genoux")
        XCTAssertEqual(modification["seedvr2"]?.bool, false)
        XCTAssertEqual(modification["reprise"]?.bool, true)
        let part = try XCTUnwrap(modification["part_changee_pct"]?.double)
        XCTAssertGreaterThan(part, 5); XCTAssertLessThan(part, 25)
        XCTAssertTrue(reponse["a_savoir"]?.string?.contains("undo_last ne la retire pas") == true)
        XCTAssertTrue(modification["resolution_zone"]?.string?.contains("\(taille.largeur) × \(taille.hauteur)") == true)
        // La barre : exportation, chargement du modèle, recomposition ; de 0 à 100.
        let messages = fake.progressions.compactMap { $0["message"]?.string }
        XCTAssertTrue(messages.first?.hasPrefix("Fibo 2 : exportation de la photo en TIFF, 0 %") == true, "\(messages)")
        XCTAssertTrue(messages.contains { $0.hasPrefix("Fibo 2 : jupe, ") && $0.hasSuffix("— chargement du modèle") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.hasPrefix("Fibo 2 : recomposition et importation, 94 %") }, "\(messages)")
        XCTAssertTrue(fake.progressions.allSatisfy { $0["total"]?.int == 100 || $0["fin"] != nil })

        // Le TIFF final : pleine taille, 16 bits, pixels d'origine hors de la zone, rouge dans le carré.
        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        XCTAssertEqual(apres.largeur, largeur); XCTAssertEqual(apres.hauteur, hauteur)
        var identiques = 0, compares = 0
        for y in stride(from: 0, to: hauteur, by: 3) {
            for x in stride(from: 0, to: largeur, by: 3) {
                let fx = Double(x) / Double(largeur), fy = Double(y) / Double(hauteur)
                guard fx < 0.3 || fx > 0.7 || fy < 0.25 || fy > 0.75 else { continue }
                compares += 1
                if Self.pixel(avant, x, y) == Self.pixel(apres, x, y) { identiques += 1 }
            }
        }
        XCTAssertEqual(identiques, compares, "hors de la zone changée, les pixels du TIFF exporté")
        let centre = Self.pixel(apres, largeur / 2, hauteur / 2)
        XCTAssertGreaterThan(centre[0], 45_000, "\(centre)"); XCTAssertLessThan(centre[1], 15_000, "\(centre)")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(importe as CFURL, nil))
        let proprietes = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(proprietes[kCGImagePropertyDepth] as? Int, 16)
        XCTAssertEqual((proprietes[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:10:20 14:30:00")
        XCTAssertEqual((proprietes[kCGImagePropertyIPTCDictionary] as? [CFString: Any])?[kCGImagePropertyIPTCCaptionAbstract] as? String, "Légende d'essai")
        XCTAssertEqual((proprietes[kCGImagePropertyGPSDictionary] as? [CFString: Any])?[kCGImagePropertyGPSLatitude] as? Double ?? 0, 45.5, accuracy: 0.001)
        XCTAssertEqual((proprietes[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] as? String, "X-H2S")
        XCTAssertTrue((proprietes[kCGImagePropertyProfileName] as? String ?? "").contains("Adobe RGB"), "\(proprietes[kCGImagePropertyProfileName] ?? "")")
        // Ce qui n'existe qu'en XMP (libellé, mots-clés hiérarchiques) reste ; compression Deflate.
        let xmp = try XCTUnwrap(CGImageSourceCopyMetadataAtIndex(source, 0, nil))
        XCTAssertEqual(CGImageMetadataCopyStringValueWithPath(xmp, nil, "xmp:Label" as CFString) as String?, "Rouge")
        XCTAssertNotNil(CGImageMetadataCopyTagWithPath(xmp, nil, "lr:hierarchicalSubject" as CFString), "lr:hierarchicalSubject gardé")
        XCTAssertEqual((proprietes[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFCompression] as? Int, 8, "Deflate, pas LZW")

        XCTAssertEqual(dossiersTemporairesRestants, [], "le dossier temporaire est effacé")
    }

    /// Avec region : Fibo reçoit le recadrage autour de la zone, à sa taille native (petit), avec le
    /// masque dans son repère ; un changement hors de la zone n'est pas repris.
    func testRegionDonneLeRecadrageEtBorneLeMelange() throws {
        fauxSeedVR()
        let region = CGRect(x: 0.05, y: 0.2, width: 0.3, height: 0.6)
        fauxMflux(sortie: sortiePreparee(region: region) { fx, fy, p, i in
            if fx > 0.1, fx < 0.3, fy > 0.3, fy < 0.7 { Self.rouge(&p, i) }   // dans la zone
            if fx > 0.4, fx < 0.48, fy > 0.3, fy < 0.7 { Self.bleu(&p, i) }   // dans le recadrage, hors de la zone
        })
        let resultat = editer(["instruction": "add a red bag", "region": ["x": 0.05, "y": 0.2, "width": 0.3, "height": 0.6], "quality": "normal"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(fake.calls.first { $0.command == "importerGeneree" }?.params["photo"]?.int, 7, "la photo active")
        // Recadrage : 600 × 400, zone de 180 × 240 px ; marge de 50 % de chaque côté, coupé aux bords,
        // resserré à 288 × 400 (multiples de 16), à sa taille native.
        let (cadre, taille) = Generatif.recadrage(region, largeur: largeur, hauteur: hauteur)
        XCTAssertEqual(cadre, Generatif.Pixels(x: 6, y: 0, largeur: 288, hauteur: 400))
        XCTAssertTrue(taille == (288, 400))
        XCTAssertEqual(valeur("--width"), "288"); XCTAssertEqual(valeur("--height"), "400")
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(valeur("--mask-path"))).lastPathComponent, "masque-1.png")
        let masque = try XCTUnwrap(Self.pixels8(gardes.appendingPathComponent("masque.png")))
        XCTAssertEqual(masque.largeur, 288); XCTAssertEqual(masque.hauteur, 400)
        XCTAssertEqual(masque.valeur(115, 200), 255, "dans la zone, dans le repère du recadrage")
        XCTAssertEqual(masque.valeur(273, 200), 0, "à droite de la zone")
        XCTAssertNil(argumentsSeedVR, "taille native : pas de SeedVR2")

        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        XCTAssertEqual(Self.pixel(apres, 270, 200), Self.pixel(avant, 270, 200), "hors de la zone, rien n'est repris")
        XCTAssertEqual(Self.pixel(apres, 500, 200), Self.pixel(avant, 500, 200), "hors du recadrage")
        XCTAssertGreaterThan(Self.pixel(apres, Int(0.2 * Double(largeur)), hauteur / 2)[0], 45_000)
        let reponse = try JSONCoding.parse(resultat.text)
        let modification = try XCTUnwrap(reponse["modifications"]?.array?.first)
        XCTAssertEqual(modification["region"]?["width"]?.double ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(modification["recadrage_px"]?["width"]?.int, 288)
        XCTAssertTrue(modification["resolution_zone"]?.string?.contains("taille native") == true, resultat.text)
        XCTAssertEqual(modification["seedvr2"]?.bool, false)
    }

    func testSortieEntiereAuDelaDeSoixantePourCent() throws {
        fauxMflux(sortie: sortiePreparee { _, _, p, i in p[i] = 255 - p[i]; p[i + 1] = 255 - p[i + 1]; p[i + 2] = 255 - p[i + 2] })
        let resultat = editer(["instruction": "turn it into a night scene"])
        XCTAssertFalse(resultat.isError, resultat.text)
        let reponse = try JSONCoding.parse(resultat.text)
        XCTAssertEqual(reponse["sortie_entiere"]?.bool, true)
        XCTAssertTrue(reponse["remarque"]?.string?.contains("toute la sortie de Fibo 2") == true, resultat.text)
        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        XCTAssertNotEqual(Self.pixel(apres, 5, 5), Self.pixel(avant, 5, 5), "même le coin vient de la sortie")

        // Avec une zone donnée, toute la zone est prise de toute façon : ni sortie entière, ni part « de la zone ».
        fauxMflux(sortie: sortiePreparee(region: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)) { _, _, p, i in
            p[i] = 255 - p[i]; p[i + 1] = 255 - p[i + 1]; p[i + 2] = 255 - p[i + 2]
        })
        let avecZone = editer(["instruction": "turn it into a night scene", "region": ["x": 0.1, "y": 0.1, "width": 0.8, "height": 0.8]])
        XCTAssertFalse(avecZone.isError, avecZone.text)
        let reponseZone = try JSONCoding.parse(avecZone.text)
        XCTAssertNil(reponseZone["sortie_entiere"])
        XCTAssertFalse(avecZone.text.contains("de la zone"), avecZone.text)
        XCTAssertTrue(reponseZone["modifications"]?.array?.first?["resolution_zone"]?.string?.hasPrefix("La zone vient de la sortie de Fibo 2") == true, avecZone.text)
    }

    func testRienDeChangeRienDImporte() {
        fauxMflux()
        let resultat = editer(["instruction": "do nothing"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("rien changé de visible"), resultat.text)
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    func testQualiteRapideTurbo() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        XCTAssertFalse(editer(["instruction": "x", "quality": "fast"]).isError)
        XCTAssertEqual(valeur("--model"), "fibo2-edit-turbo")
        XCTAssertNil(valeur("--steps")); XCTAssertNil(valeur("--base-model"))
        XCTAssertFalse(argumentsPasses.contains("--vae-full-precision"), "pleine précision en qualité normale seulement")
        XCTAssertFalse(argumentsPasses.contains("--quantize") || argumentsPasses.contains("--step-cache-ratio"))
        XCTAssertNotNil(Int(valeur("--seed") ?? ""), "une graine au hasard, toujours passée")

        // Le modèle Turbo du cache Hugging Face : sa copie locale.
        let depot = dossier.appendingPathComponent("hf/models--briaai--Fibo-2.0-edit-turbo")
        let instantane = depot.appendingPathComponent("snapshots/abc123")
        try FileManager.default.createDirectory(at: instantane, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: depot.appendingPathComponent("refs"), withIntermediateDirectories: true)
        try "abc123\n".write(to: depot.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        try "{}".write(to: instantane.appendingPathComponent("model_index.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(editer(["instruction": "x", "quality": "fast"]).isError)
        XCTAssertEqual(valeur("--model"), instantane.path)
        XCTAssertEqual(valeur("--base-model"), "fibo2-edit-turbo")
        XCTAssertNil(valeur("--steps"))
    }

    func testEchecDeMfluxExplique() {
        fauxMflux(fin: "echo 'huggingface_hub.errors.GatedRepoError: 403 Client Error' >&2\nexit 1")
        var resultat = editer(["instruction": "x"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("accès au modèle refusé") && resultat.text.contains("huggingface.co/briaai/Fibo-2.0-dev"), resultat.text)
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
        XCTAssertEqual(dossiersTemporairesRestants, [])

        fauxMflux(fin: "printf 'Traceback\\nligne a\\nligne b\\nValueError: boom\\n'\nexit 2")
        resultat = editer(["instruction": "x"])
        XCTAssertTrue(resultat.text.contains("code 2") && resultat.text.contains("ValueError: boom"), resultat.text)
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    func testAnnulationArreteMflux() throws {
        fauxMflux(fin: "exec sleep 30")
        let contexte = ContexteAppel()
        var resultat: ToolResult?
        let fini = expectation(description: "fin de l'appel")
        let debut = Date()
        DispatchQueue.global().async {
            resultat = self.tools.call(name: "generative_edit", arguments: ["instruction": "x", "instruction_fr": "x"], contexte: contexte)
            fini.fulfill()
        }
        let pidFichier = gardes.appendingPathComponent("pid.txt")
        let attente = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: pidFichier.path), Date() < attente { usleep(50_000) }
        let pid = try XCTUnwrap(Int32((try? String(contentsOf: pidFichier, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
        contexte.annuler()
        wait(for: [fini], timeout: 15)
        XCTAssertLessThan(Date().timeIntervalSince(debut), 12)
        XCTAssertEqual(resultat?.isError, true)
        XCTAssertTrue(resultat?.text.contains("annulé") == true, resultat?.text ?? "")
        XCTAssertNotEqual(kill(pid, 0), 0, "mflux est arrêté")
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    func testDelaiMaximalArreteMflux() {
        fauxMflux(fin: "exec sleep 30")
        tools.fibo?.delaiMax = 1
        let resultat = editer(["instruction": "x"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("n'a pas fini"), resultat.text)
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    func testExportationEchoueeRienDeLance() {
        fauxMflux()
        fake.onSend = nil
        fake.replies["exporter"] = ["fichiers": [["photo": ["id": 7, "fichier": "DSCF2402.RAF"], "erreur": "original introuvable"]]]
        let resultat = editer(["instruction": "x"])
        XCTAssertTrue(resultat.text.contains("original introuvable"), resultat.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gardes.appendingPathComponent("arguments.txt").path), "mflux n'est pas lancé")
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    // MARK: Recadrage, plusieurs modifications, SeedVR2, progression

    /// Le recadrage autour d'une zone : marge de 50 % de chaque côté, au moins 35 % du petit côté,
    /// coupé aux bords, ~1 Mpx au-delà (jamais plus grand que natif), la zone dans son repère.
    func testRecadrageAutourDeLaZone() {
        // Une petite zone au milieu d'une photo de 6 000 × 4 000 : au moins 35 % du petit côté (1 400 px).
        var (cadre, taille) = Generatif.recadrage(CGRect(x: 0.5, y: 0.5, width: 0.05, height: 0.05), largeur: 6000, hauteur: 4000)
        XCTAssertEqual(cadre.largeur, 1400, accuracy: 1); XCTAssertEqual(cadre.hauteur, 1400, accuracy: 1)
        XCTAssertEqual(Double(cadre.x) + Double(cadre.largeur) / 2, 3150, accuracy: 1, "centré sur la zone")
        XCTAssertEqual(taille.largeur % 16, 0); XCTAssertEqual(taille.hauteur % 16, 0)
        XCTAssertLessThan(taille.largeur, cadre.largeur, "~1 Mpx, plus petit que le recadrage de 1,96 Mpx")
        XCTAssertEqual(Double(taille.largeur * taille.hauteur), 1_048_576, accuracy: 60_000)
        // Une grande zone : marge de 50 % de sa taille de chaque côté (1 200 → 2 400 px).
        (cadre, _) = Generatif.recadrage(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), largeur: 6000, hauteur: 4000)
        XCTAssertEqual(cadre, Generatif.Pixels(x: 1800, y: 1200, largeur: 2400, hauteur: 1600))
        // Contre un bord : coupé, pas déplacé.
        (cadre, _) = Generatif.recadrage(CGRect(x: 0, y: 0.8, width: 0.1, height: 0.2), largeur: 6000, hauteur: 4000)
        XCTAssertEqual(cadre.x, 0); XCTAssertEqual(cadre.y + cadre.hauteur, 4000)
        XCTAssertEqual(cadre.largeur, 1000, accuracy: 1, "1 400 px (35 % du petit côté) centrés sur 300 : de −400 à 1 000, coupé à 0")
        // Petit recadrage : sa taille native, resserrée aux multiples de 16, la zone gardée entière.
        (cadre, taille) = Generatif.recadrage(CGRect(x: 0.05, y: 0.2, width: 0.3, height: 0.6), largeur: 600, hauteur: 400)
        XCTAssertTrue(taille == (cadre.largeur, cadre.hauteur), "jamais plus grand que natif")
        XCTAssertEqual(cadre.largeur % 16, 0); XCTAssertEqual(cadre.hauteur % 16, 0)
        XCTAssertLessThanOrEqual(cadre.x, 30); XCTAssertGreaterThanOrEqual(cadre.x + cadre.largeur, 210)
        // La zone dans le repère du recadrage, et son masque.
        let dedans = Generatif.regionDansRecadrage(CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                                                   cadre: Generatif.Pixels(x: 1800, y: 1200, largeur: 2400, hauteur: 1600), largeur: 6000, hauteur: 4000)
        XCTAssertEqual(dedans.minX, 0.25, accuracy: 1e-9); XCTAssertEqual(dedans.width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(dedans.minY, 0.25, accuracy: 1e-9); XCTAssertEqual(dedans.height, 0.5, accuracy: 1e-9)
        let masque = Generatif.masqueRegion(dedans, largeur: 400, hauteur: 200)
        XCTAssertEqual(masque[100 * 400 + 200], 255); XCTAssertEqual(masque[100 * 400 + 20], 0)
    }

    func testPourcentageEtTempsRestant() {
        let deux = Generatif.Avancement(seedVR: [false, false])
        XCTAssertEqual(deux.pourcentage(.export), 0)
        XCTAssertEqual(deux.pourcentage(.chargement(0)), 1, "3 sur 168")
        XCTAssertEqual(deux.pourcentage(.etapes(0, fait: 25, sur: 50)), 28, "(3 + 10 + 35) sur 168")
        XCTAssertEqual(deux.pourcentage(.chargement(1)), 49, "(3 + 80) sur 168")
        XCTAssertEqual(deux.pourcentage(.etapes(1, fait: 50, sur: 50)), 97)
        XCTAssertEqual(deux.pourcentage(.fin), 97)
        let avecSeedVR = Generatif.Avancement(seedVR: [true])
        XCTAssertEqual(avecSeedVR.pourcentage(.etapes(0, fait: 50, sur: 50)), 80, "(3 + 80) sur 103")
        XCTAssertEqual(avecSeedVR.pourcentage(.seedVR(0, fraction: 0.5)), 87)
        XCTAssertEqual(avecSeedVR.pourcentage(.fin), 95)
        XCTAssertEqual(Generatif.Avancement(seedVR: [false]).pourcentage(.etapes(0, fait: 99, sur: 50)), 94, "borné")

        // Rien avant deux étapes ; puis le rythme des étapes faites.
        XCTAssertNil(Generatif.tempsRestant(etape: 1, sur: 50, premiere: 0, secondesDepuisPremiere: 4, chargement: 30, suivantes: 0))
        XCTAssertNil(Generatif.tempsRestant(etape: 2, sur: 50, premiere: 1, secondesDepuisPremiere: 4, chargement: 30, suivantes: 0))
        XCTAssertEqual(Generatif.tempsRestant(etape: 10, sur: 50, premiere: 0, secondesDepuisPremiere: 20, chargement: 30, suivantes: 0) ?? 0, 80, accuracy: 1e-9)
        XCTAssertEqual(Generatif.tempsRestant(etape: 10, sur: 50, premiere: 0, secondesDepuisPremiere: 20, chargement: 30, suivantes: 1) ?? 0, 210, accuracy: 1e-9,
                       "la modification suivante : son chargement et ses 50 étapes")
        XCTAssertEqual(Generatif.texteTempsRestant(210), "environ 4 min restantes")
        XCTAssertEqual(Generatif.texteTempsRestant(75), "environ 1 min restante")
        XCTAssertEqual(Generatif.texteTempsRestant(20), "moins d'une minute restante")
        XCTAssertEqual(Generatif.texteProgression("jupe", rang: 1, sur: 2, pourcentage: 24, detail: "environ 3 min restantes"),
                       "Fibo 2 : jupe (1 sur 2), 24 % — environ 3 min restantes")
        XCTAssertEqual(Generatif.texteProgression("jupe", rang: 1, sur: 1, pourcentage: 5, detail: "chargement du modèle"), "Fibo 2 : jupe, 5 % — chargement du modèle")
        XCTAssertTrue(Generatif.progressionLibre(" 3/8 [00:02").map { $0.fait == 3 && $0.total == 8 } == true)
    }

    func testDeuxModificationsPixelsHorsDesZonesIdentiques() throws {
        let jupe = CGRect(x: 0.05, y: 0.1, width: 0.25, height: 0.3), sac = CGRect(x: 0.6, y: 0.55, width: 0.3, height: 0.35)
        fauxMflux(sorties: [sortiePreparee(region: jupe, nom: "jupe.png") { _, _, p, i in Self.rouge(&p, i) },
                            sortiePreparee(region: sac, nom: "sac.png") { _, _, p, i in Self.bleu(&p, i) }])
        func zone(_ r: CGRect) -> JSONValue { ["x": .number(r.minX), "y": .number(r.minY), "width": .number(r.width), "height": .number(r.height)] }
        let resultat = tools.call(name: "generative_edit", arguments: ["edits": [
            ["label": "jupe", "instruction": "replace the trousers with a skirt, keep the pose", "instruction_fr": "remplacer le pantalon par une jupe", "region": zone(jupe)],
            ["label": "sac", "instruction": "add a blue bag", "instruction_fr": "ajouter un sac bleu", "region": zone(sac)],
        ], "seed": 7])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(appelsDeMflux, 2, "un passage de Fibo par modification")
        XCTAssertEqual(fake.commands, ["etat", "exporter", "importerGeneree"], "un seul export, une seule importation")
        // Chaque passage part du même TIFF exporté, avec son recadrage et sa consigne.
        XCTAssertEqual(argumentsDeLAppel(1)[1], "replace the trousers with a skirt, keep the pose")
        XCTAssertEqual(argumentsDeLAppel(2)[1], "add a blue bag")
        XCTAssertTrue(argumentsDeLAppel(2).contains { $0.hasSuffix("entree-2.png") })
        let consigne = "jupe : remplacer le pantalon par une jupe ; sac : ajouter un sac bleu"
        XCTAssertEqual(fake.calls.first { $0.command == "importerGeneree" }?.params["consigne"]?.string, consigne)
        XCTAssertEqual(fake.calls.first { $0.command == "exporter" }?.params["raison"]?.string, consigne)

        // Hors des deux zones (élargies de la marge et du fondu), chaque pixel au bit près.
        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        let bord = 0.08 * Double(min(largeur, hauteur))
        func pres(_ r: CGRect, _ x: Int, _ y: Int) -> Bool {
            Double(x) > r.minX * Double(largeur) - bord && Double(x) < r.maxX * Double(largeur) + bord
                && Double(y) > r.minY * Double(hauteur) - bord && Double(y) < r.maxY * Double(hauteur) + bord
        }
        var differents = 0, compares = 0
        for y in 0..<hauteur {
            for x in 0..<largeur where !pres(jupe, x, y) && !pres(sac, x, y) {
                compares += 1
                if Self.pixel(avant, x, y) != Self.pixel(apres, x, y) { differents += 1 }
            }
        }
        XCTAssertGreaterThan(compares, 150_000)
        XCTAssertEqual(differents, 0, "hors des zones, les pixels du TIFF exporté, au bit près")
        let rouge = Self.pixel(apres, Int(0.175 * Double(largeur)), Int(0.25 * Double(hauteur)))
        let bleu = Self.pixel(apres, Int(0.75 * Double(largeur)), Int(0.725 * Double(hauteur)))
        XCTAssertGreaterThan(rouge[0], 45_000, "\(rouge)"); XCTAssertLessThan(rouge[2], 15_000, "\(rouge)")
        XCTAssertGreaterThan(bleu[2], 45_000, "\(bleu)"); XCTAssertLessThan(bleu[0], 15_000, "\(bleu)")

        let reponse = try JSONCoding.parse(resultat.text)
        let modifications = try XCTUnwrap(reponse["modifications"]?.array)
        XCTAssertEqual(modifications.map { $0["label"]?.string }, ["jupe", "sac"])
        XCTAssertEqual(modifications.map { $0["instruction_fr"]?.string }, ["remplacer le pantalon par une jupe", "ajouter un sac bleu"])
        XCTAssertTrue(modifications.allSatisfy { $0["reprise"]?.bool == true && $0["resolution_zone"]?.string != nil && $0["seedvr2"]?.bool == false })
        let messages = fake.progressions.compactMap { $0["message"]?.string }
        XCTAssertTrue(messages.contains { $0.hasPrefix("Fibo 2 : jupe (1 sur 2), ") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.hasPrefix("Fibo 2 : sac (2 sur 2), ") }, "\(messages)")
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    func testPlusieursModificationsRefusAvantToutEnvoi() {
        fauxMflux()
        let jupe: JSONValue = ["x": 0.1, "y": 0.1, "width": 0.3, "height": 0.3]
        // Deux zones qui se chevauchent : deux appels successifs.
        let chevauchement = tools.call(name: "generative_edit", arguments: ["edits": [
            ["label": "jupe", "instruction": "a", "instruction_fr": "a", "region": jupe],
            ["label": "sac", "instruction": "b", "instruction_fr": "b", "region": ["x": 0.3, "y": 0.3, "width": 0.2, "height": 0.2]],
        ]])
        XCTAssertTrue(chevauchement.isError)
        XCTAssertTrue(chevauchement.text.contains("« jupe » et de « sac » se chevauchent") && chevauchement.text.contains("deux appels successifs"), chevauchement.text)
        // Plusieurs modifications : chacune sa zone.
        let sansZone = tools.call(name: "generative_edit", arguments: ["edits": [
            ["label": "jupe", "instruction": "a", "instruction_fr": "a", "region": jupe],
            ["label": "ciel", "instruction": "b", "instruction_fr": "b"],
        ]])
        XCTAssertTrue(sansZone.text.contains("« ciel » : sans region"), sansZone.text)
        // edits et instruction ensemble.
        let ensemble = tools.call(name: "generative_edit", arguments: ["instruction": "a", "instruction_fr": "a",
                                                                       "edits": [["instruction": "b", "instruction_fr": "b", "region": jupe]]])
        XCTAssertTrue(ensemble.text.contains("« edits » et « instruction"), ensemble.text)
        // La traduction est exigée dans chaque modification.
        let sansFrancais = tools.call(name: "generative_edit", arguments: ["edits": [["instruction": "b", "region": jupe]]])
        XCTAssertTrue(sansFrancais.text.contains("instruction_fr"), sansFrancais.text)
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
        XCTAssertEqual(appelsDeMflux, 0)
        // Deux zones qui se touchent sans se chevaucher : pas d'aire commune, mais leurs bords fondus se
        // recouvriraient (vu d'après la taille de la photo).
        let chemise = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.3), basse = CGRect(x: 0.4, y: 0.5, width: 0.2, height: 0.3)
        XCTAssertNil(Generatif.chevauchement([chemise, basse]))
        XCTAssertTrue(Generatif.zonesTropProches([chemise, basse], largeur: 6000, hauteur: 4000).map { $0 == (0, 1) } == true)
        // Proches de 1 % du petit côté : encore trop proches ; loin l'une de l'autre : acceptées.
        XCTAssertNotNil(Generatif.zonesTropProches([chemise, CGRect(x: 0.4, y: 0.51, width: 0.2, height: 0.3)], largeur: 6000, hauteur: 4000))
        XCTAssertNil(Generatif.zonesTropProches([chemise, CGRect(x: 0.4, y: 0.75, width: 0.2, height: 0.2)], largeur: 6000, hauteur: 4000))
    }

    /// Deux zones qui se touchent : refusées après l'exportation (la taille de la photo), avant Fibo.
    func testZonesQuiSeTouchentRefuseesAvantFibo() {
        fauxMflux()
        let resultat = tools.call(name: "generative_edit", arguments: ["edits": [
            ["label": "chemise", "instruction": "a", "instruction_fr": "a", "region": ["x": 0.4, "y": 0.2, "width": 0.2, "height": 0.3]],
            ["label": "jupe", "instruction": "b", "instruction_fr": "b", "region": ["x": 0.4, "y": 0.5, "width": 0.2, "height": 0.3]],
        ]])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("« chemise » et de « jupe » se touchent ou sont trop proches") && resultat.text.contains("deux appels successifs"), resultat.text)
        XCTAssertEqual(appelsDeMflux, 0)
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// Une zone qui touche les deux bords de la photo : le recadrage la garde entière (jamais une bande
    /// coupée au bord, qui laisserait une couture), l'entrée de Fibo au multiple de 16 inférieur.
    func testZonePleineLargeurGardeSesBords() throws {
        let region = CGRect(x: 0, y: 0.4, width: 1, height: 0.2)
        let (cadre, taille) = Generatif.recadrage(region, largeur: 1000, hauteur: 700)
        XCTAssertEqual(cadre.x, 0); XCTAssertEqual(cadre.largeur, 1000)
        XCTAssertEqual(taille.largeur, 992, "à peine réduite, jamais plus grande que native")
        XCTAssertEqual(taille.hauteur % 16, 0); XCTAssertEqual(taille.hauteur, cadre.hauteur)
        XCTAssertLessThanOrEqual(Double(cadre.y), 0.4 * 700 - 20); XCTAssertGreaterThanOrEqual(Double(cadre.y + cadre.hauteur), 0.6 * 700 + 20)
        // Agrandi jusqu'au multiple suivant quand la photo le permet (d'un côté seulement, contre un bord).
        let (a, b, t) = Generatif.ajuster16(0, 200, zone: 0, 200, limite: 1000)
        XCTAssertEqual(a, 0); XCTAssertEqual(b, 208); XCTAssertEqual(t, 208)

        ecrireSource(largeur: 1000, hauteur: 700)
        fauxMflux(sortie: sortiePreparee(region: region) { _, _, p, i in Self.rouge(&p, i) })
        let resultat = editer(["instruction": "remove the wire", "region": ["x": 0, "y": 0.4, "width": 1, "height": 0.2]])
        XCTAssertFalse(resultat.isError, resultat.text)
        let apres = try XCTUnwrap(Self.pixels16(importe))
        for x in [0, 3, 7, 500, 996, 999] {
            XCTAssertGreaterThan(Self.pixel(apres, x, 350)[0], 45_000, "colonne \(x) : changée jusqu'au bord")
        }
    }

    /// Un recadrage plus allongé que 8:1 grandit sur son petit côté (dans la photo) plutôt que d'être
    /// déformé ; l'entrée n'est jamais plus grande que native.
    func testRecadrageJamaisPlusAllongeQueHuitSurUn() {
        let (cadre, taille) = Generatif.recadrage(CGRect(x: 0, y: 0, width: 1, height: 0.01), largeur: 12000, hauteur: 4000)
        XCTAssertLessThanOrEqual(Double(cadre.largeur) / Double(cadre.hauteur), 8.0001)
        XCTAssertEqual(cadre.y, 0)
        let fx = Double(cadre.largeur) / Double(taille.largeur), fy = Double(cadre.hauteur) / Double(taille.hauteur)
        XCTAssertEqual(fx, fy, accuracy: 0.1, "même échelle sur les deux côtés : pas de déformation")
        let (cadre2, taille2) = Generatif.recadrage(CGRect(x: 0, y: 0, width: 1, height: 0.01), largeur: 4380, hauteur: 1565)
        XCTAssertLessThanOrEqual(taille2.largeur, cadre2.largeur); XCTAssertLessThanOrEqual(taille2.hauteur, cadre2.hauteur)
    }

    /// SeedVR2 borné : jamais sans zone, au plus × 4 et 16 Mpx ; sinon la raison.
    func testSeedVRBorne() {
        let petit = (largeur: 1024, hauteur: 1024)
        XCTAssertTrue(Generatif.seedVR(cadre: Generatif.Pixels(x: 0, y: 0, largeur: 2048, hauteur: 2048), taille: petit, avecRegion: true, demande: true).lancer)
        XCTAssertFalse(Generatif.seedVR(cadre: Generatif.Pixels(x: 0, y: 0, largeur: 2048, hauteur: 2048), taille: petit, avecRegion: true, demande: false).lancer)
        let sansRegion = Generatif.seedVR(cadre: Generatif.Pixels(x: 0, y: 0, largeur: 2048, hauteur: 2048), taille: petit, avecRegion: false, demande: true)
        XCTAssertFalse(sansRegion.lancer); XCTAssertTrue(sansRegion.raison?.contains("Sans region") == true)
        let grande = Generatif.seedVR(cadre: Generatif.Pixels(x: 0, y: 0, largeur: 7728, hauteur: 5152), taille: (1248, 832), avecRegion: true, demande: true)
        XCTAssertFalse(grande.lancer); XCTAssertTrue(grande.raison?.contains("trop grande") == true, grande.raison ?? "")
        let sousLeSeuil = Generatif.seedVR(cadre: Generatif.Pixels(x: 0, y: 0, largeur: 1200, hauteur: 1200), taille: petit, avecRegion: true, demande: true)
        XCTAssertFalse(sousLeSeuil.lancer); XCTAssertNil(sousLeSeuil.raison, "× 1,17 : rien à dire")
    }

    /// Une source plus grande (1 600 × 1 200) : le recadrage de toute la photo (1,92 Mpx) revient de
    /// ~1 Mpx, agrandi de 1,35 fois : SeedVR2 d'abord (côté court natif, 7B, par tuiles).
    func testSeedVRAuDelaDeUnVirguleVingtCinq() throws {
        ecrireSource(largeur: 1600, hauteur: 1200)
        fauxSeedVR()
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        fauxMflux(sortie: sortiePreparee(region: region, carreRouge))
        let (cadre, taille) = Generatif.recadrage(region, largeur: 1600, hauteur: 1200)
        XCTAssertEqual(cadre, Generatif.Pixels(x: 0, y: 0, largeur: 1600, hauteur: 1200))
        XCTAssertGreaterThan(Generatif.facteur(cadre: cadre, taille: taille), 1.25)
        let resultat = editer(["instruction": "add a red square", "region": ["x": 0.25, "y": 0.25, "width": 0.5, "height": 0.5], "seed": 3])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(valeurSeedVR("--model"), "seedvr2-7b")
        XCTAssertEqual(valeurSeedVR("--resolution"), "1200", "le côté court natif du recadrage")
        XCTAssertEqual(valeurSeedVR("--seed"), "3")
        XCTAssertTrue(argumentsSeedVR?.contains("--low-ram") == true, "\(argumentsSeedVR ?? [])")
        XCTAssertFalse(argumentsSeedVR?.contains("--vae-tiling") == true, "impliqué par --low-ram")
        XCTAssertTrue(valeurSeedVR("--image-path")?.hasSuffix("sortie-1.png") == true)
        let modification = try XCTUnwrap(try JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertEqual(modification["seedvr2"]?.bool, true)
        XCTAssertTrue(modification["resolution_zone"]?.string?.contains("SeedVR2") == true, resultat.text)
        XCTAssertTrue(fake.progressions.contains { $0["message"]?.string?.hasSuffix("— agrandissement (SeedVR2)") == true })
        let apres = try XCTUnwrap(Self.pixels16(importe))
        XCTAssertEqual(apres.largeur, 1600)
        XCTAssertGreaterThan(Self.pixel(apres, 800, 600)[0], 45_000)

        // upscale = false : mise à la taille ordinaire, SeedVR2 jamais lancé.
        try FileManager.default.removeItem(at: gardes.appendingPathComponent("seedvr-arguments.txt"))
        let sansSeedVR = editer(["instruction": "add a red square", "region": ["x": 0.25, "y": 0.25, "width": 0.5, "height": 0.5], "upscale": false])
        XCTAssertFalse(sansSeedVR.isError, sansSeedVR.text)
        XCTAssertNil(argumentsSeedVR)
        XCTAssertEqual(try JSONCoding.parse(sansSeedVR.text)["modifications"]?.array?.first?["seedvr2"]?.bool, false)
    }

    /// SeedVR2 absent ou en échec : mise à la taille ordinaire, dite dans la réponse ; l'outil réussit.
    func testSansSeedVRRepliDitDansLaReponse() throws {
        ecrireSource(largeur: 1600, hauteur: 1200)
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        fauxMflux(sortie: sortiePreparee(region: region, carreRouge))
        let zone: JSONValue = ["x": 0.25, "y": 0.25, "width": 0.5, "height": 0.5]
        var resultat = editer(["instruction": "add a red square", "region": zone])
        XCTAssertFalse(resultat.isError, resultat.text)
        var modification = try XCTUnwrap(try JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertEqual(modification["seedvr2"]?.bool, false)
        XCTAssertTrue(modification["remarque_seedvr2"]?.string?.contains("SeedVR2 est absent") == true, resultat.text)
        XCTAssertTrue(modification["resolution_zone"]?.string?.contains("mise à la taille ordinaire") == true, resultat.text)
        XCTAssertTrue(fake.commands.contains("importerGeneree"))

        fauxSeedVR(fin: "echo 'RuntimeError: out of memory' >&2\nexit 1")
        resultat = editer(["instruction": "add a red square", "region": zone])
        XCTAssertFalse(resultat.isError, resultat.text)
        modification = try XCTUnwrap(try JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertEqual(modification["seedvr2"]?.bool, false)
        XCTAssertTrue(modification["remarque_seedvr2"]?.string?.contains("code 1") == true, resultat.text)
        XCTAssertTrue(modification["remarque_seedvr2"]?.string?.contains("mise à la taille ordinaire") == true, resultat.text)
        XCTAssertEqual(fake.commands.filter { $0 == "importerGeneree" }.count, 2)
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// SeedVR2 présent, mais une sortie de Fibo à sa taille native (facteur 1) : jamais lancé.
    func testSeedVRPasLanceSousUnVirguleVingtCinq() throws {
        fauxSeedVR()
        let region = CGRect(x: 0.05, y: 0.2, width: 0.3, height: 0.6)
        fauxMflux(sortie: sortiePreparee(region: region) { _, _, p, i in Self.rouge(&p, i) })
        let resultat = editer(["instruction": "x", "region": ["x": 0.05, "y": 0.2, "width": 0.3, "height": 0.6]])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertNil(argumentsSeedVR, "SeedVR2 n'est pas lancé")
        let modification = try XCTUnwrap(try JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertEqual(modification["seedvr2"]?.bool, false)
        XCTAssertNil(modification["remarque_seedvr2"])
    }

    /// Sans region, SeedVR2 n'est jamais lancé (il agrandirait toute la photo) : la réponse le dit.
    func testSansRegionPasDeSeedVR() throws {
        ecrireSource(largeur: 1600, hauteur: 1200)
        fauxSeedVR()
        fauxMflux(sortie: sortiePreparee(carreRouge))
        let taille = Generatif.tailleCible(largeur: 1600, hauteur: 1200)
        XCTAssertGreaterThan(Double(1200) / Double(taille.hauteur), 1.25, "l'ancien code aurait lancé SeedVR2")
        let resultat = editer(["instruction": "add a red square"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertNil(argumentsSeedVR, "SeedVR2 n'est pas lancé sans region")
        let modification = try XCTUnwrap(try JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertEqual(modification["seedvr2"]?.bool, false)
        XCTAssertTrue(modification["remarque_seedvr2"]?.string?.contains("Sans region") == true, resultat.text)
        XCTAssertFalse(fake.progressions.contains { $0["message"]?.string?.contains("SeedVR2") == true }, "la barre ne lui réserve rien")
    }

    /// La croix de Lightroom se lit pendant un chargement muet du modèle (la même progression renvoyée
    /// toutes les quelques secondes) : mflux arrêté, rien d'importé.
    func testCroixLuePendantLeChargementDuModele() throws {
        fauxMflux(fin: "exec sleep 30")
        let pidFichier = gardes.appendingPathComponent("pid.txt")
        fake.reponseAPart = { commande, _ in
            commande == "progression" && FileManager.default.fileExists(atPath: pidFichier.path) ? ["annulee": true] : nil
        }
        let debut = Date()
        let resultat = editer(["instruction": "x"])
        XCTAssertLessThan(Date().timeIntervalSince(debut), 12)
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("Arrêté dans Lightroom"), resultat.text)
        let pid = try XCTUnwrap(Int32((try? String(contentsOf: pidFichier, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
        XCTAssertNotEqual(kill(pid, 0), 0, "mflux est arrêté")
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// La croix cliquée pendant la recomposition : relue juste avant l'importation ; rien d'importé.
    func testCroixLueAvantLImportation() {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        final class Compte { var n = 0 }
        let compte = Compte()
        fake.reponseAPart = { commande, params in
            guard commande == "progression", params["message"]?.string?.contains("recomposition") == true else { return nil }
            compte.n += 1
            return compte.n >= 2 ? ["annulee": true] : nil
        }
        let resultat = editer(["instruction": "x"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("Arrêté dans Lightroom"), resultat.text)
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// La barre ne recule jamais (une barre de chargement de même total n'est pas lue comme des
    /// étapes) et finit à 100 %.
    func testBarreSansReculJusquACent() {
        fauxMflux(sortie: sortiePreparee(carreRouge), fin: """
        printf 'Loading checkpoint shards: 100%%| 4/4 [00:01\\n' >&2
        sleep 0.4
        printf '  0/4 [00:00\\n' >&2
        sleep 0.4
        printf '  2/4 [00:01\\n  4/4 [00:02\\n' >&2
        cp "\(gardes.path)/sortie.png" "$out"
        """)
        let resultat = editer(["instruction": "x", "quality": "fast"])
        XCTAssertFalse(resultat.isError, resultat.text)
        let faits = fake.progressions.compactMap { $0["fait"]?.int }
        XCTAssertEqual(faits, faits.sorted(), "jamais de recul : \(faits)")
        XCTAssertEqual(faits.last, 100, "\(faits)")
        XCTAssertTrue(fake.progressions.contains { $0["message"]?.string == "Fibo 2 : terminé, 100 %" })
    }

    func testLignesDeChargementEtNouvelleBarre() {
        XCTAssertNil(Generatif.progression("Fetching 4 files: 100%|██████| 4/4 [00:03<00:00", etapes: 4))
        XCTAssertNil(Generatif.progression("Loading checkpoint shards:  50%|█| 2/4 [00:01", etapes: 4))
        XCTAssertEqual(Generatif.progression(" 50%|█████     | 2/4 [00:01<00:01", etapes: 4), 2)
        XCTAssertNil(Generatif.progressionLibre("Fetching 3 files: 100%| 3/3 [00:03"))
        XCTAssertNil(Generatif.progressionLibre("Downloading model.safetensors: 3/3 [00:03"))
        let suivi = SuiviProcessus()
        suivi.noterEtape(4)
        usleep(20_000)
        suivi.noterEtape(0)
        XCTAssertEqual(suivi.etat.premiere?.etape, 0, "une nouvelle barre : le rythme repart d'elle")
        suivi.noterFraction(fait: 3, total: 3)
        suivi.noterFraction(fait: 1, total: 20)
        XCTAssertEqual(suivi.etat.fraction, 0.05, accuracy: 1e-9, "une barre d'un autre total remplace la fraction")
        suivi.noterFraction(fait: 10, total: 20)
        XCTAssertEqual(suivi.etat.fraction, 0.5, accuracy: 1e-9)
    }

    /// Le serveur terminé par un signal : mflux arrêté, le dossier de l'appel effacé (SIGUSR1 ici,
    /// pour ne pas toucher aux signaux du processus des essais).
    func testUnSignalArreteMflux() throws {
        let travail = TravailFibo()
        let dossierAppel = dossier.appendingPathComponent("appel")
        try FileManager.default.createDirectory(at: dossierAppel, withIntermediateDirectories: true)
        travail.commencer(dossier: dossierAppel)
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/bin/sleep")
        processus.arguments = ["30"]
        try processus.run()
        travail.lancer(processus)
        let sorti = expectation(description: "sortie")
        let sources = travail.arreterAuxSignaux([SIGUSR1]) { numero in
            XCTAssertEqual(numero, SIGUSR1)
            sorti.fulfill()
        }
        defer { sources.forEach { $0.cancel() }; signal(SIGUSR1, SIG_DFL) }
        kill(getpid(), SIGUSR1)
        wait(for: [sorti], timeout: 10)
        XCTAssertFalse(processus.isRunning, "mflux est arrêté")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dossierAppel.path), "le dossier de l'appel est effacé")
    }

    // MARK: --low-ram, un seul calcul et résultat gardé (constat du 29 octobre 2026)

    /// --low-ram toujours (normal et rapide), --vae-full-precision en normal seulement, jamais -q ;
    /// SeedVR2 avec --low-ram, sans --vae-tiling (impliqué).
    func testArgumentsToujoursLowRam() {
        let e = URL(fileURLWithPath: "/tmp/e.png"), s = URL(fileURLWithPath: "/tmp/s.png")
        let normal = Generatif.arguments(entree: e, masque: nil, instruction: "x", taille: (1024, 1024), qualite: .normal, graine: 1, sortie: s, modeleRapide: nil)
        let rapide = Generatif.arguments(entree: e, masque: nil, instruction: "x", taille: (1024, 1024), qualite: .fast, graine: 1, sortie: s, modeleRapide: nil)
        let masque = Generatif.arguments(entree: e, masque: URL(fileURLWithPath: "/tmp/m.png"), instruction: "x", taille: (1024, 1024), qualite: .normal,
                                         graine: 1, sortie: s, modeleRapide: nil)
        XCTAssertEqual(Array(masque.prefix(6)), ["--prompt", "x", "--image-paths", "/tmp/e.png", "--mask-path", "/tmp/m.png"], "une seule image, son masque")
        for args in [normal, rapide, masque] {
            XCTAssertEqual(args.filter { $0 == "--low-ram" }.count, 1, "\(args)")
            XCTAssertFalse(args.contains("-q") || args.contains("--quantize"), "\(args)")
        }
        XCTAssertTrue(normal.contains("--vae-full-precision"))
        XCTAssertFalse(rapide.contains("--vae-full-precision"))
        let seedVR = Generatif.argumentsSeedVR(entree: e, resolution: 1200, graine: 1, sortie: s)
        XCTAssertTrue(seedVR.contains("--low-ram"))
        XCTAssertFalse(seedVR.contains("--vae-tiling"))
    }

    /// Aucune garde de mémoire (retirée le 29 octobre 2026, à la demande de Dany : « le Mac créera du
    /// swap au besoin ») : deux modifications lancées, SeedVR2 aussi, et la réponse ne dit rien de la
    /// mémoire.
    func testAucuneGardeDeMemoire() throws {
        ecrireSource(largeur: 3000, hauteur: 2000)
        fauxSeedVR()
        let gauche = CGRect(x: 0.05, y: 0.1, width: 0.3, height: 0.35), droite = CGRect(x: 0.6, y: 0.55, width: 0.3, height: 0.35)
        fauxMflux(sorties: [sortiePreparee(region: gauche, nom: "gauche.png") { _, _, p, i in Self.rouge(&p, i) },
                            sortiePreparee(region: droite, nom: "droite.png") { _, _, p, i in Self.bleu(&p, i) }])
        func zone(_ r: CGRect) -> JSONValue { ["x": .number(r.minX), "y": .number(r.minY), "width": .number(r.width), "height": .number(r.height)] }
        let resultat = tools.call(name: "generative_edit", arguments: ["edits": [
            ["label": "rouge", "instruction": "add a red square", "instruction_fr": "ajouter un carré rouge", "region": zone(gauche)],
            ["label": "bleu", "instruction": "add a blue square", "instruction_fr": "ajouter un carré bleu", "region": zone(droite)],
        ]])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(appelsDeMflux, 2)
        XCTAssertNotNil(argumentsSeedVR, "SeedVR2 lancé")
        XCTAssertEqual(fake.commands, ["etat", "exporter", "importerGeneree"])
        let reponse = try JSONCoding.parse(resultat.text)
        for cle in ["memoire_libre_go", "memoire_minimale_go", "remarque_memoire", "remarque_garde_memoire"] {
            XCTAssertNil(reponse[cle], cle)
        }
        for modification in try XCTUnwrap(reponse["modifications"]?.array) {
            XCTAssertEqual(modification["reprise"]?.bool, true, resultat.text)
            XCTAssertNil(modification["memoire_libre_go"])
        }
        XCTAssertFalse(resultat.text.contains("Mémoire libre"), resultat.text)
    }

    /// importerGeneree refusé par le module : pas de second essai ; le TIFF final est déplacé dans
    /// « Fibo non importées » (nom libre, -2 au suivant), l'erreur le dit avec son chemin.
    func testTIFFGardeApresUnEchecDImportation() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        fake.errors["importerGeneree"] = LightroomError.plugin("Accord refusé dans Lightroom.")
        let gardees = racine.appendingPathComponent("Fibo non importées")
        for rang in 1...2 {
            let resultat = editer(["instruction": "add a red square"])
            XCTAssertTrue(resultat.isError)
            let nom = rang == 1 ? "DSCF2402-Fibo.tif" : "DSCF2402-Fibo-2.tif"
            let garde = gardees.appendingPathComponent(nom)
            XCTAssertTrue(FileManager.default.fileExists(atPath: garde.path), resultat.text)
            XCTAssertTrue(resultat.text.contains(garde.path), resultat.text)
            XCTAssertTrue(resultat.text.contains("Fichier › Importer"), resultat.text)
            XCTAssertTrue(resultat.text.contains("Accord refusé dans Lightroom."), resultat.text)
            XCTAssertEqual(fake.commands.filter { $0 == "importerGeneree" }.count, rang, "un refus du module ne se réessaie pas")
            XCTAssertEqual(dossiersTemporairesRestants, [], "déplacé, pas copié ; le dossier temporaire effacé")
        }
        let lu = try XCTUnwrap(Self.pixels16(gardees.appendingPathComponent("DSCF2402-Fibo.tif")))
        XCTAssertEqual(lu.largeur, largeur)
        XCTAssertGreaterThan(Self.pixel(lu, 300, 200)[0], 45_000, "le résultat de Fibo, recomposé")
    }

    /// Lightroom injoignable (la commande n'est jamais partie) : un second essai (après le délai),
    /// qui réussit.
    func testImportationReessayeeUneFoisQuandLightroomNeRepondPas() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        var essais = 0
        let precedent = fake.onSend
        fake.onSend = { [unowned self] commande, params in
            precedent?(commande, params)
            guard commande == "importerGeneree" else { return }
            essais += 1
            self.fake.errors["importerGeneree"] = essais == 1 ? LightroomError.unreachable(LightroomBridge.unreachableMessage) : nil
        }
        let resultat = editer(["instruction": "add a red square"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(fake.commands.filter { $0 == "importerGeneree" }.count, 2)
        XCTAssertEqual(try JSONCoding.parse(resultat.text)["nouvelle_photo"]?["id"]?.int, 99)
        XCTAssertFalse(FileManager.default.fileExists(atPath: racine.appendingPathComponent("Fibo non importées").path))
    }

    /// Lightroom muet aux deux essais : le TIFF gardé ; et Lightroom muet pendant le calcul (la barre
    /// refusée de suite, 3 fois au moins) : dit dans l'erreur.
    func testImportationAbandonneeApresDeuxEssais() {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        fake.errors["importerGeneree"] = LightroomError.unreachable(LightroomBridge.unreachableMessage)
        fake.errors["progression"] = LightroomError.timeout("Lightroom n'a pas répondu à temps (commande « progression »).")
        let resultat = editer(["instruction": "add a red square"])
        XCTAssertTrue(resultat.isError)
        XCTAssertEqual(fake.commands.filter { $0 == "importerGeneree" }.count, 2, "un seul second essai")
        XCTAssertTrue(FileManager.default.fileExists(atPath: racine.appendingPathComponent("Fibo non importées/DSCF2402-Fibo.tif").path), resultat.text)
        XCTAssertTrue(resultat.text.contains("Lightroom ne répondait plus pendant le calcul"), resultat.text)
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// La barre refusée de suite pendant le calcul : la réponse le signale, sans arrêter Fibo.
    func testLightroomMuetPendantLeCalculSignale() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        fake.errors["progression"] = LightroomError.timeout("Lightroom n'a pas répondu à temps (commande « progression »).")
        let resultat = editer(["instruction": "add a red square"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertGreaterThanOrEqual(fake.progressions.count, BarreFibo.echecsSignales)
        let remarque = try XCTUnwrap(try JSONCoding.parse(resultat.text)["remarque_lightroom"]?.string, resultat.text)
        XCTAssertTrue(remarque.contains("Lightroom ne répondait plus pendant le calcul") && remarque.contains("mémoire ?"), remarque)
        XCTAssertTrue(fake.commands.contains("importerGeneree"))
    }

    /// Commande partie sans réponse (délai, liaison coupée) : jamais rejouée (une écriture : la photo
    /// serait importée deux fois) ; le TIFF gardé, et l'erreur dit de vérifier la pile de l'original
    /// avant de l'importer.
    func testImportationSansReponseJamaisRejouee() {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        for erreur in [LightroomError.timeout("Lightroom n'a pas répondu à temps (commande « importerGeneree »)."),
                       LightroomError.interrupted("La liaison avec Lightroom a été coupée pendant la commande « importerGeneree ».")] {
            fake.calls = []
            fake.errors["importerGeneree"] = erreur
            let resultat = editer(["instruction": "add a red square"])
            XCTAssertTrue(resultat.isError)
            XCTAssertEqual(fake.commands.filter { $0 == "importerGeneree" }.count, 1, "jamais rejouée : \(erreur)")
            XCTAssertTrue(resultat.text.contains("Fibo non importées"), resultat.text)
            XCTAssertTrue(resultat.text.contains("peut-être déjà au catalogue") && resultat.text.contains("pile de l'original"), resultat.text)
            XCTAssertEqual(dossiersTemporairesRestants, [])
        }
    }

    /// Délai dépassé, mais le module a importé la photo et effacé le TIFF temporaire : jamais « rien
    /// n'a été importé », l'erreur dit qu'elle l'a sans doute été (la chercher avant de relancer).
    func testImportationSansReponseTIFFParti() {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        let precedent = fake.onSend
        fake.onSend = { commande, params in
            precedent?(commande, params)
            if commande == "importerGeneree" { try? FileManager.default.removeItem(atPath: params["chemin"]?.string ?? "") }
        }
        fake.errors["importerGeneree"] = LightroomError.timeout("Lightroom n'a pas répondu à temps (commande « importerGeneree »).")
        let resultat = editer(["instruction": "add a red square"])
        XCTAssertTrue(resultat.isError)
        XCTAssertEqual(fake.commands.filter { $0 == "importerGeneree" }.count, 1)
        XCTAssertTrue(resultat.text.contains("sans doute importée") && resultat.text.contains("avant de relancer generative_edit"), resultat.text)
        XCTAssertFalse(resultat.text.contains("rien n'a été importé"), resultat.text)
        XCTAssertFalse(resultat.text.contains("rien n'a pu être gardé"), resultat.text)
    }

    /// Le déplacement vers « Fibo non importées » impossible (un fichier à sa place) : le TIFF final
    /// reste dans le dossier de l'appel, seul (jamais effacé), et l'erreur donne son chemin.
    func testTIFFLaisseSurPlaceSiLeDeplacementEchoue() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        try Data("pas un dossier".utf8).write(to: racine.appendingPathComponent("Fibo non importées"))
        fake.errors["importerGeneree"] = LightroomError.plugin("Accord refusé dans Lightroom.")
        let resultat = editer(["instruction": "add a red square"])
        XCTAssertTrue(resultat.isError)
        XCTAssertEqual(dossiersTemporairesRestants.count, 1, resultat.text)
        let appel = racine.appendingPathComponent("Temporaire/Fibo").appendingPathComponent(dossiersTemporairesRestants[0])
        let restants = try FileManager.default.contentsOfDirectory(atPath: appel.path)
        XCTAssertEqual(restants, ["DSCF2402-Fibo.tif"], "le TIFF final seul, le reste effacé")
        XCTAssertTrue(resultat.text.contains(appel.appendingPathComponent("DSCF2402-Fibo.tif").path), resultat.text)
        XCTAssertTrue(resultat.text.contains("prochain chargement du module"), resultat.text)
    }

    /// Un nom pris dans « Fibo non importées » : le rang suivant, d'un coup (renamex_np, RENAME_EXCL),
    /// sans jamais écraser.
    func testGarderNonImporteeNEcraseJamais() throws {
        let gardees = racine.appendingPathComponent("Fibo non importées")
        try FileManager.default.createDirectory(at: gardees, withIntermediateDirectories: true)
        try Data("premier".utf8).write(to: gardees.appendingPathComponent("A-Fibo.tif"))
        try Data("deuxième".utf8).write(to: gardees.appendingPathComponent("A-Fibo-2.tif"))
        let fichier = dossier.appendingPathComponent("final.tif")
        try Data("nouveau".utf8).write(to: fichier)
        let garde = try ToolHandler.garderNonImportee(fichier, nom: "A-Fibo", dans: gardees)
        XCTAssertEqual(garde.lastPathComponent, "A-Fibo-3.tif")
        XCTAssertEqual(try String(contentsOf: gardees.appendingPathComponent("A-Fibo.tif"), encoding: .utf8), "premier")
        XCTAssertEqual(try String(contentsOf: garde, encoding: .utf8), "nouveau")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fichier.path), "déplacé, pas copié")
    }

    /// mflux en erreur pendant que Lightroom ne répondait plus : l'erreur le dit ; tué par un signal
    /// (le système, faute de mémoire) : dit aussi.
    func testErreurDeMfluxAvecLightroomMuetEtSignal() {
        fake.errors["progression"] = LightroomError.timeout("Lightroom n'a pas répondu à temps (commande « progression »).")
        fauxMflux(fin: "printf '  0/50 [00:00\\n'; sleep 4; echo 'ValueError: boom'; exit 2")
        var resultat = editer(["instruction": "x"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("code 2") && resultat.text.contains("Lightroom ne répondait plus pendant le calcul"), resultat.text)

        fake.errors["progression"] = nil
        fauxMflux(fin: "kill -9 $$")
        resultat = editer(["instruction": "x"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("signal 9") && resultat.text.contains("faute de mémoire"), resultat.text)
        XCTAssertFalse(resultat.text.contains("Lightroom ne répondait plus"), resultat.text)
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// Un autre calcul de Fibo 2 en cours sur ce Mac (le verrou tenu par une autre ouverture) : refus
    /// avant tout envoi ; le verrou rendu, l'appel suivant passe.
    func testUnSeulCalculDeFiboALaFois() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        let fibo = try XCTUnwrap(tools.fibo)
        try FileManager.default.createDirectory(at: fibo.fichierVerrou.deletingLastPathComponent(), withIntermediateDirectories: true)
        let autre = open(fibo.fichierVerrou.path, O_CREAT | O_RDWR, 0o600)
        XCTAssertGreaterThanOrEqual(autre, 0)
        XCTAssertEqual(flock(autre, LOCK_EX | LOCK_NB), 0)
        var resultat = editer(["instruction": "add a red square"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("Un autre calcul de Fibo 2 est en cours"), resultat.text)
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
        XCTAssertEqual(appelsDeMflux, 0)
        close(autre)
        resultat = editer(["instruction": "add a red square"])
        XCTAssertFalse(resultat.isError, resultat.text)
        // Rendu à la fin de l'appel : un autre le prend aussitôt.
        let suivant = try XCTUnwrap(fibo.prendreVerrou())
        close(suivant)
    }

    /// Un mflux lancé hors du serveur (Fibo 2 Studio, le Terminal) : refus avant tout envoi
    /// (constaté le 29 octobre 2026 : deux calculs ensemble ont gelé le Mac).
    func testFiboStudioQuiCalculeDejaRefuse() {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        autreCalcul = true
        var resultat = editer(["instruction": "add a red square"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("Fibo 2 calcule déjà sur ce Mac"), resultat.text)
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
        XCTAssertEqual(appelsDeMflux, 0)
        autreCalcul = false
        resultat = editer(["instruction": "add a red square"])
        XCTAssertFalse(resultat.isError, resultat.text)
    }

    /// Les pixels d'un PNG (canal rouge), pour lire le masque.
    static func pixels8(_ url: URL) -> (largeur: Int, hauteur: Int, valeur: (Int, Int) -> UInt8)? {
        guard let (image, _) = Generatif.lireImage(url), let pixels = Generatif.pixelsRGBA8(image, largeur: image.width, hauteur: image.height) else { return nil }
        let l = image.width
        return (l, image.height, { x, y in pixels[(y * l + x) * 4] })
    }
}
