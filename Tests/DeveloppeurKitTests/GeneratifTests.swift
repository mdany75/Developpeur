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
    /// Le masque que le faux module « calcule » pour essayer (fx, fy de 0 à 1 dans la photo) : le
    /// rendu témoin s'écarte de l'état actuel là seulement. Et la taille de ses deux rendus (celle
    /// du TIFF par défaut).
    var masqueRendu: (Double, Double) -> Bool = { _, _ in false }
    var tailleRendu: (largeur: Int, hauteur: Int)?
    /// Ce que le faux module dit des personnes non reconnues (Rendu.essayer avec temoin).
    var personnesNonReconnues: JSONValue?

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
            case "essayer":
                // Comme Rendu.essayer, en pleine taille : l'état actuel (avec comparer) et le témoin, en PNG
                // (sans perte : le bord du masque est exact). L'état actuel a, dans l'arrière-plan, un noir
                // pur (en bas à gauche) et un blanc pur (en bas à droite) : le témoin sombre (−2 IL) ne
                // change pas le noir pur, le clair (+1,5 IL, noirs relevés) pas le blanc pur ; seule leur
                // union fait le masque entier.
                let (l, h) = self.tailleRendu ?? (self.largeur, self.hauteur)
                let sombre = (params["masques"]?.array?.first?["locaux"]?["LocalExposure2012"]?.double ?? 0) < 0
                func couleur(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
                    if y >= h * 8 / 10, x < l / 10 { return (0, 0, 0) }
                    if y >= h * 8 / 10, x >= l * 9 / 10 { return (255, 255, 255) }
                    return (UInt8(60 + x * 120 / l), UInt8(80 + y * 100 / h), 120)
                }
                let temoin = Self.png(largeur: l, hauteur: h) { x, y in
                    let (r, g, b) = couleur(x, y)
                    guard self.masqueRendu((Double(x) + 0.5) / Double(l), (Double(y) + 0.5) / Double(h)) else { return (r, g, b) }
                    func clair(_ v: UInt8) -> UInt8 { UInt8(min(255, 2 * Int(v) + 30)) }
                    return sombre ? (r / 3, g / 3, b / 3) : (clair(r), clair(g), clair(b))
                }
                var reponse: [String: JSONValue] = ["chemin": .string(TestSupport.previewFile(temoin)), "etape": "Claude · essai : masque pour Fibo 2"]
                if params["comparer"]?.bool == true {
                    reponse["chemin_actuel"] = .string(TestSupport.previewFile(Self.png(largeur: l, hauteur: h, couleur)))
                }
                if let personnes = self.personnesNonReconnues { reponse["personnes_non_reconnues"] = personnes }
                self.fake.replies["essayer"] = .object(reponse)
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

    /// Une image sRGB en PNG (sans perte), comme un rendu du module dont le bord se lit au pixel.
    static func png(largeur: Int, hauteur: Int, _ couleur: (Int, Int) -> (UInt8, UInt8, UInt8)) -> Data {
        let image = TestSupport.imagePixels(width: largeur, height: hauteur, couleur)
        let sortie = NSMutableData()
        let destination = CGImageDestinationCreateWithData(sortie, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return sortie as Data
    }

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
        out=""; img=""; mask=""; fiche=""; etapes=4
        while [ $# -gt 0 ]; do
          case "$1" in
            --output) out="$2"; shift ;;
            --image-paths) img="$2"; shift ;;
            --mask-path) mask="$2"; shift ;;
            --prompt-file) fiche="$2"; shift ;;
            --steps) etapes="$2"; shift ;;
          esac
          shift
        done
        [ -n "$mask" ] && cp "$mask" "\(g)/masque.png"
        [ -n "$fiche" ] && cp "$fiche" "\(g)/fiche-recue-$n.json"
        # FIBO-vlm (le faux Python) : fini avant mflux, jamais vivant en même temps.
        if [ -f "\(g)/vlm-pid" ] && kill -0 "$(cat "\(g)/vlm-pid")" 2>/dev/null; then echo vivant > "\(g)/vlm-vivant-$n"; fi
        [ -f "\(g)/vlm-fin" ] && echo oui > "\(g)/vlm-fini-avant-$n"
        \(fin ?? """
        printf "  0/$etapes [00:00\\r $((etapes / 2))/$etapes [00:01\\r $etapes/$etapes [00:02\\n" >&2
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
        XCTAssertEqual(Set(proprietes.keys), ["photo_id", "instruction", "instruction_fr", "region", "label", "mask", "edits", "upscale", "quality",
                                              "structured_prompt", "avoid", "guidance", "seed", "confirm", "reason"])
        XCTAssertEqual(proprietes["quality"]?["enum"], ["balanced", "normal", "fast"])
        XCTAssertTrue(proprietes["quality"]?["description"]?.string?.hasPrefix("balanced (défaut)") == true)
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

        // mflux : qualité équilibrée par défaut (30 étapes, guidage arrêté à 60 %), pleine précision,
        // phrase d'exclusion par défaut, graine, taille multiple de 16, pas de masque ; jamais
        // --quantize ni --step-cache-ratio. Sans FIBO-vlm sur ce Mac (les essais), la phrase seule.
        let taille = Generatif.tailleCible(largeur: largeur, hauteur: hauteur)
        XCTAssertEqual(valeur("--prompt"), "replace the trousers with a knee-length navy skirt")
        XCTAssertNil(valeur("--prompt-file"))
        XCTAssertEqual(valeur("--steps"), "30")
        XCTAssertEqual(valeur("--cfg-end"), "0.6")
        XCTAssertNil(valeur("--guidance"), "le guidage de mflux, sans guidance donné")
        XCTAssertEqual(valeur("--negative-prompt"), Generatif.exclusion(instruction: "replace the trousers with a knee-length navy skirt", avoid: nil))
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
        XCTAssertEqual(reponse["qualite"]?.string, "équilibrée (30 étapes, guidage sur 60 % d'entre elles)")
        XCTAssertEqual(reponse["guidage"]?.double, 5)
        XCTAssertEqual(reponse["fiche_fibo_vlm"]?.bool, false)
        // Fiche demandée par défaut, mais pas de FIBO-vlm dans ce test : la phrase seule, dite.
        XCTAssertTrue(reponse["remarque_fiche"]?.string?.contains("phrase seule") == true, resultat.text)
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

    // MARK: Masque de Lightroom (mask)

    /// Une personne au milieu de la photo (de 40 à 60 % en largeur, de 30 à 70 % en hauteur) ;
    /// l'arrière-plan est tout le reste.
    static func dansLaPersonne(_ fx: Double, _ fy: Double) -> Bool { fx > 0.4 && fx < 0.6 && fy > 0.3 && fy < 0.7 }

    func testMasqueBinaireAuSeuil() {
        let actuel: [UInt8] = [100, 100, 100, 255, 100, 100, 100, 255, 100, 100, 100, 255]
        let temoin: [UInt8] = [100, 100, 100, 255, 105, 98, 100, 255, 100, 100, 94, 255]
        XCTAssertEqual(Generatif.masqueBinaire(actuel: actuel, temoin: temoin, nombre: 3), [0, 0, 1], "un canal à 6 de l'état actuel : dans le masque")
        XCTAssertEqual(Generatif.seuilMasque, CarteMasque.seuilEcart)
        XCTAssertEqual(Generatif.temoinSombre["LocalExposure2012"]?.double ?? 0, -0.5, accuracy: 1e-9, "−2 IL : les blancs brûlés changent aussi")
    }

    /// Les deux témoins : aucun ne mêle deux réglages de sens contraire (−2 IL et des noirs relevés
    /// s'annulaient dans une plage de tons sombres) ; le masque est l'union de leurs écarts : le noir
    /// pur (que le sombre ne change pas) et le blanc pur (que le clair ne change pas) y sont.
    func testUnionDesDeuxTemoins() {
        for temoin in Generatif.temoinsMasque {
            let signes = ["LocalExposure2012", "LocalBlacks2012", "LocalShadows2012", "LocalWhites2012", "LocalHighlights2012"]
                .compactMap { temoin[$0]?.double }.filter { $0 != 0 }.map { $0 > 0 }
            XCTAssertTrue(Set(signes).count <= 1, "réglages de tons du même sens : \(temoin)")
        }
        XCTAssertNil(Generatif.temoinSombre["LocalBlacks2012"])
        XCTAssertGreaterThan(Generatif.temoinClair["LocalBlacks2012"]?.double ?? 0, 0, "le noir pur change dans le clair")
        // Noir pur, gris foncé, blanc pur, gris moyen hors du masque.
        let actuel: [UInt8] = [0, 0, 0, 255, 12, 12, 12, 255, 255, 255, 255, 255, 128, 128, 128, 255]
        let sombre: [UInt8] = [0, 0, 0, 255, 4, 4, 4, 255, 85, 85, 85, 255, 128, 128, 128, 255]
        let clair: [UInt8] = [30, 30, 30, 255, 54, 54, 54, 255, 255, 255, 255, 255, 128, 128, 128, 255]
        XCTAssertEqual(Generatif.masqueBinaire(actuel: actuel, temoin: sombre, nombre: 4), [0, 1, 1, 0])
        XCTAssertEqual(Generatif.masqueBinaire(actuel: actuel, temoin: clair, nombre: 4), [1, 1, 0, 0])
        var masque = [UInt8](repeating: 0, count: 4)
        Generatif.ajouterAuMasque(&masque, actuel: actuel, temoin: sombre)
        Generatif.ajouterAuMasque(&masque, actuel: actuel, temoin: clair)
        XCTAssertEqual(masque, [1, 1, 1, 0], "l'union")
    }

    /// Le nettoyage retire les petites composantes (îlots et trous), jamais un trait fin mais long :
    /// le jour entre le bras et le corps, une mèche, une sangle gardent leurs pixels.
    func testNettoyageDuMasque() {
        let l = 2600, h = 1000
        XCTAssertEqual(Generatif.aireNettoyage(largeur: l, hauteur: h), 36, "un carré de 6 px (2 600 / 512)")
        var masque = [UInt8](repeating: 0, count: l * h)
        func poser(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ v: UInt8) {
            for y in y0..<y1 { for x in x0..<x1 { masque[y * l + x] = v } }
        }
        poser(0, 1300, 0, h, 1)                          // le masque (l'arrière-plan) à gauche
        poser(1300, 1302, 300, 301, 1)                   // une dent au bord
        poser(2000, 2003, 500, 503, 1)                   // un point isolé de 9 px dans le vide
        poser(2100, 2105, 500, 505, 1)                   // un îlot de 25 px
        poser(200, 202, 200, 202, 0)                     // un petit trou de 4 px dans le plein
        poser(600, 610, 600, 610, 0)                     // un vrai trou de 100 px (entre deux doigts)
        poser(900, 905, 100, 900, 0)                     // le jour de 5 px entre le bras et le corps : du vide dans le plein
        poser(1300, 2500, 700, 702, 1)                   // une sangle de 2 px, attachée au masque
        for k in 0..<200 { masque[(100 + k) * l + 1500 + k] = 1 } // une mèche d'un pixel, en diagonale, seule
        Generatif.nettoyer(&masque, largeur: l, hauteur: h)
        func v(_ x: Int, _ y: Int) -> UInt8 { masque[y * l + x] }
        XCTAssertEqual(v(2001, 501), 0, "point isolé retiré"); XCTAssertEqual(v(2102, 502), 0, "petit îlot retiré")
        XCTAssertEqual(v(200, 200), 1, "petit trou bouché"); XCTAssertEqual(v(201, 201), 1)
        XCTAssertEqual(v(605, 605), 0, "un trou plus grand que l'aire reste")
        for x in 900..<905 { XCTAssertEqual(v(x, 500), 0, "le jour entre le bras et le corps reste, au pixel (x \(x))") }
        XCTAssertEqual(v(899, 500), 1); XCTAssertEqual(v(905, 500), 1)
        for x in stride(from: 1300, to: 2500, by: 50) { XCTAssertEqual(v(x, 700), 1, "la sangle reste (x \(x))"); XCTAssertEqual(v(x, 702), 0) }
        for k in stride(from: 0, to: 200, by: 7) { XCTAssertEqual(v(1500 + k, 100 + k), 1, "la mèche en diagonale reste") }
        XCTAssertEqual(v(1501, 100), 0)
        XCTAssertEqual(v(1301, 300), 1, "le bord garde son détail au pixel"); XCTAssertEqual(v(1301, 301), 0)
        XCTAssertEqual(v(1299, 301), 1); XCTAssertEqual(v(1303, 300), 0)
    }

    func testRedimensionnementEtCadreDuMasque() {
        let petit: [UInt8] = [1, 0,
                              0, 0]
        XCTAssertEqual(Generatif.redimensionner(petit, largeur: 2, hauteur: 2, versLargeur: 4, versHauteur: 4),
                       [1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "au plus proche voisin")
        let (part, cadre) = Generatif.cadreDuMasque([0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0], largeur: 4, hauteur: 3)
        XCTAssertEqual(part, 3.0 / 12, accuracy: 1e-9)
        XCTAssertEqual(cadre, CGRect(x: 0, y: 1.0 / 3, width: 0.5, height: 2.0 / 3))
        XCTAssertNil(Generatif.cadreDuMasque([0, 0], largeur: 2, hauteur: 1).cadre)
        XCTAssertTrue(Generatif.refusMasque(part: 0.00005)?.contains("ne couvre presque rien") == true)
        XCTAssertTrue(Generatif.refusMasque(part: 0.99995)?.contains("couvre toute la photo") == true)
        XCTAssertTrue(Generatif.refusMasque(part: 0.99995)?.contains("sujet minuscule") == true)
        XCTAssertNil(Generatif.refusMasque(part: 0.5))
        // Un petit sujet (un oiseau de 0,4 % du cadre) : son arrière-plan (99,6 %) et lui passent ; une
        // personne lointaine de 0,04 % aussi.
        XCTAssertNil(Generatif.refusMasque(part: 0.996))
        XCTAssertNil(Generatif.refusMasque(part: 0.004))
        XCTAssertNil(Generatif.refusMasque(part: 0.0004))
    }

    /// Le masque donné à Fibo : la part couverte de chaque pixel d'entrée (à moitié : blanc), élargi
    /// de margeMasque ; dans le repère du recadrage.
    func testMasqueDonneAFiboElargi() {
        let l = 200, h = 100
        var masque = [UInt8](repeating: 0, count: l * h)
        for y in 0..<h { for x in 100..<150 { masque[y * l + x] = 1 } }
        let cadre = Generatif.Pixels(x: 50, y: 0, largeur: 100, hauteur: 100)
        let entree = Generatif.masquePourFibo(masque, largeurPhoto: l, cadre: cadre, taille: (50, 50))
        XCTAssertEqual(entree.count, 2500)
        XCTAssertEqual(entree[25 * 50 + 40], 255, "dans le masque")
        XCTAssertEqual(entree[25 * 50 + 24], 255, "élargi d'un pixel (1 % de 50)")
        XCTAssertEqual(entree[25 * 50 + 22], 0, "hors du masque et de sa marge")
    }

    /// Le masque binaire fondu (le repli de l'opacité) : 1 dans le masque, 0 exactement hors du fondu.
    func testFonduBinaireSansElargissement() {
        let l = 2000, h = 1400
        var masque = [UInt8](repeating: 0, count: l * h)
        for y in 0..<h { for x in 1000..<l { masque[y * l + x] = 1 } }
        let cadre = Generatif.Pixels(x: 800, y: 100, largeur: 1200, hauteur: 1200)
        let zone = Generatif.fonduBinaire(masque, largeurPhoto: l, hauteurPhoto: h, cadre: cadre)
        XCTAssertEqual(zone.count, 1200 * 1200)
        let rayon = max(2, Int((Double(h) * Generatif.fonduMasque).rounded()))
        XCTAssertEqual(rayon, 2)
        func z(_ x: Int) -> Float { zone[600 * 1200 + x - 800] }
        XCTAssertEqual(z(1000 - rayon - 1), 0, "hors du masque et du fondu : exactement 0")
        XCTAssertEqual(z(850), 0)
        XCTAssertEqual(z(1000 + rayon + 1), 1, "dans le masque, loin du bord : 1")
        XCTAssertGreaterThan(z(1000), 0.4); XCTAssertLessThan(z(999), 0.6)
        XCTAssertGreaterThan(z(999), 0, "le fondu passe le bord")
    }

    // MARK: Le bord doux (opacité du masque de Lightroom)

    /// Un bord doux de Lightroom, comme les cheveux : un sujet (brun) à gauche, l'ancien fond à droite,
    /// du gris foncé en haut au gris clair en bas (toutes les valeurs de l'état actuel se voient aussi
    /// pleines, comme sur une vraie photo) ; l'opacité du masque d'arrière-plan monte de 0 à 1 sur dix
    /// pixels, de x 600 à 610, et l'état actuel y mêle les deux (des mèches sur le fond). Les témoins
    /// appliquent −2 IL et +1,5 IL en lumière linéaire, en proportion de l'opacité, comme un réglage
    /// local de Lightroom.
    static func bordDoux(largeur l: Int, hauteur h: Int, avecEffet: Bool = true) -> (actuel: [UInt8], temoins: [[UInt8]], opacite: (Int) -> Double) {
        func opacite(_ x: Int) -> Double { min(1, max(0, (Double(x) + 0.5 - 600) / 10)) }
        func lin(_ v: Double) -> Double { let c = v / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func srgb(_ v: Double) -> UInt8 {
            let c = min(1, max(0, v))
            let e = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
            return UInt8((e * 255).rounded())
        }
        let sujet: [Double] = [70, 50, 40]
        var actuel = [UInt8](repeating: 255, count: l * h * 4)
        var temoins = [actuel, actuel]
        for y in 0..<h {
            let gris = 40 + 150 * Double(y) / Double(h)
            let fond = [gris, gris, gris - 8]
            for x in 0..<l {
                let o = opacite(x), i = (y * l + x) * 4
                for k in 0..<3 {
                    let a = srgb(lin(sujet[k]) * (1 - o) + lin(fond[k]) * o)
                    actuel[i + k] = a
                    temoins[0][i + k] = avecEffet ? srgb(lin(Double(a)) * pow(2, -2 * o)) : a
                    temoins[1][i + k] = avecEffet ? srgb(lin(Double(a)) * pow(2, 1.5 * o)) : a
                }
            }
        }
        return (actuel, temoins, opacite)
    }

    /// Le masque binaire de ces rendus, comme le connecteur le fait (seuil, union, nettoyage).
    static func binaire(_ actuel: [UInt8], _ temoins: [[UInt8]], largeur l: Int, hauteur h: Int) -> [UInt8] {
        var masque = [UInt8](repeating: 0, count: l * h)
        for t in temoins { Generatif.ajouterAuMasque(&masque, actuel: actuel, temoin: t) }
        Generatif.nettoyer(&masque, largeur: l, hauteur: h)
        return masque
    }

    /// L'opacité lue suit le bord doux de Lightroom : là où il ne met qu'un peu de fond (une mèche à
    /// 15 % d'opacité), la photo garde l'essentiel de ses pixels, alors que l'ancien bord dur (le
    /// masque binaire fondu) y mettait Fibo presque entier (« photo collée ») ; pleine dès que
    /// Lightroom dépasse l'opacité haute ; 0 exactement à plus de deux pixels hors du masque binaire.
    func testOpaciteSuitLeBordDouxDeLightroom() {
        let l = 1200, h = 1000
        let (actuel, temoins, vraie) = Self.bordDoux(largeur: l, hauteur: h)
        let masque = Self.binaire(actuel, temoins, largeur: l, hauteur: h)
        let premier = (0..<l).first { masque[500 * l + $0] != 0 }!
        XCTAssertEqual(premier, 601, "le seuil du binaire prend déjà le pixel à 15 % d'opacité")
        var calcul = Generatif.OpaciteDuMasque(binaire: masque, largeur: l, hauteur: h)
        XCTAssertEqual(Generatif.OpaciteDuMasque.erosion(largeur: l, hauteur: h), 3)
        XCTAssertEqual(Generatif.margeOpacite(largeur: l, hauteur: h), Generatif.opaciteMarge, "à 1 000 px, le fondu binaire ne dépasse pas 2 px")
        for t in temoins { calcul.ajouter(actuel: actuel, temoin: t) }
        let doux = calcul.opacite(binaire: masque)
        let cadre = Generatif.Pixels(x: 0, y: 0, largeur: l, hauteur: h)
        let zone = Generatif.zoneDuMasque(doux, largeurPhoto: l, cadre: cadre)
        let ancien = Generatif.fonduBinaire(masque, largeurPhoto: l, hauteurPhoto: h, cadre: cadre)
        func z(_ x: Int) -> Float { zone[500 * l + x] }
        func a(_ x: Int) -> Float { ancien[500 * l + x] }
        // Le bord suit la rampe renforcée de l'opacité de Lightroom (à un lissage d'un pixel près) ;
        // l'ancien bord dur, non : à x 601 (15 % d'opacité), il mettait déjà Fibo aux deux tiers, et
        // presque entier à x 602 (25 %).
        func attendu(_ x: Int) -> Float {
            let t = Float(min(1, max(0, (vraie(x) - Generatif.opaciteBas) / (Generatif.opaciteHaut - Generatif.opaciteBas))))
            return t * t * (3 - 2 * t)
        }
        XCTAssertEqual(vraie(601), 0.15, accuracy: 1e-9)
        XCTAssertGreaterThan(a(601), 0.6, "l'ancien bord dur : Fibo aux deux tiers sur une mèche à 15 %")
        XCTAssertGreaterThan(a(602), 0.85)
        for x in 601...603 {
            XCTAssertEqual(z(x), attendu(x), accuracy: 0.12, "le bord doux suit Lightroom (x \(x))")
        }
        XCTAssertGreaterThan(abs(a(601) - attendu(601)), 0.25, "l'ancien bord dur ne le suivait pas")
        XCTAssertLessThan(z(601), 0.45, "une mèche à 15 % garde plus de la moitié de ses pixels")
        XCTAssertLessThan(z(600), z(601)); XCTAssertLessThan(z(601), z(602))
        for x in 605..<640 { XCTAssertGreaterThan(z(x), 0.97, "au-delà de l'opacité haute, plein (x \(x))") }
        for x in 700..<l { XCTAssertEqual(z(x), 1, "intérieur profond (x \(x))") }
        for x in 0..<(600 - Generatif.opaciteMarge) { XCTAssertEqual(z(x), 0, "hors du masque élargi : 0 exactement (x \(x))") }
        XCTAssertGreaterThan(z(600 - 1), 0, "le lissage passe le bord d'un pixel")
        // La même chose sur toute la hauteur : aucun pixel du sujet loin du masque n'est touché.
        for i in 0..<(l * h) where i % l < 598 { if zone[i] != 0 { XCTFail("sujet touché en \(i)"); break } }
    }

    /// Des témoins qui ne disent rien du bord (aucun effet dans la bande : un canal noir ou écrêté
    /// partout, ou aucun intérieur sûr) : l'opacité retombe sur l'ancien bord, le masque binaire
    /// fondu, jamais plus dur ; l'intérieur profond reste plein, le dehors à 0.
    func testOpaciteSansAppuiRetombeSurLeFonduBinaire() {
        let l = 1200, h = 1000
        let (actuel, temoins, _) = Self.bordDoux(largeur: l, hauteur: h)
        let masque = Self.binaire(actuel, temoins, largeur: l, hauteur: h)
        let (_, muets, _) = Self.bordDoux(largeur: l, hauteur: h, avecEffet: false)
        var calcul = Generatif.OpaciteDuMasque(binaire: masque, largeur: l, hauteur: h)
        for t in muets { calcul.ajouter(actuel: actuel, temoin: t) }
        XCTAssertTrue(calcul.denominateur.allSatisfy { $0 == 0 }, "un écart nul tombe sur 0 dans la table")
        let doux = calcul.opacite(binaire: masque)
        let repli = Generatif.fonduBinaire(masque, largeurPhoto: l, hauteurPhoto: h, cadre: Generatif.Pixels(x: 0, y: 0, largeur: l, hauteur: h))
        for x in 590..<640 {
            let i = 500 * l + x
            if x < 600 - Generatif.opaciteMarge { XCTAssertEqual(doux[i], 0, "x \(x)"); continue }
            XCTAssertEqual(Float(doux[i]) / 255, repli[i], accuracy: 1 / 255 + 1e-6, "le repli : le fondu binaire (x \(x))")
        }
        XCTAssertEqual(doux[500 * l + 900], 255)
    }

    /// La table de l'effet plein relevée dans l'intérieur sûr : −2 IL et +1,5 IL en lumière linéaire,
    /// à la valeur du fond ; une valeur jamais vue prend la plus proche.
    func testTableDeLEffetPlein() {
        let l = 1200, h = 1000
        let (actuel, temoins, _) = Self.bordDoux(largeur: l, hauteur: h)
        let masque = Self.binaire(actuel, temoins, largeur: l, hauteur: h)
        let calcul = Generatif.OpaciteDuMasque(binaire: masque, largeur: l, hauteur: h)
        let fond = Int(actuel[(500 * l + 1000) * 4])
        for (t, attendu) in zip(temoins, [-2.0, 1.5]) {
            let table = actuel.withUnsafeBufferPointer { a in t.withUnsafeBufferPointer { calcul.table(actuel: a, temoin: $0) } }
            XCTAssertEqual(Double(table[fond]), attendu, accuracy: 0.08, "l'effet plein au fond (\(fond))")
            XCTAssertEqual(Double(table[10]), Double(table[40]), accuracy: 0.05, "une valeur jamais vue en bas : la plus proche")
            XCTAssertEqual(Double(table[250]), Double(table[190]), accuracy: 0.05, "en haut aussi")
        }
    }

    /// Des rendus témoins d'un bord doux quelconque : l'opacité de Lightroom en chaque pixel (x, y),
    /// le sujet (brun) mêlé au fond (un gris par ligne, `fond`) en proportion de l'opacité ; chaque
    /// témoin applique, canal par canal, un effet plein f(canal, valeur de l'état actuel) en IL de
    /// lumière linéaire, en proportion de l'opacité (écrêté à 255 en sRGB, comme un rendu).
    static func rendusDoux(largeur l: Int, hauteur h: Int, opacite: (Int, Int) -> Double, fond: (Int) -> Double,
                           effets: [(Int, Int) -> Double]) -> (actuel: [UInt8], temoins: [[UInt8]]) {
        func lin(_ v: Double) -> Double { let c = v / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func srgb(_ v: Double) -> UInt8 {
            let c = min(1, max(0, v))
            let e = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
            return UInt8((e * 255).rounded())
        }
        let sujet: [Double] = [70, 50, 40]
        var actuel = [UInt8](repeating: 255, count: l * h * 4)
        var temoins = [[UInt8]](repeating: actuel, count: effets.count)
        for y in 0..<h {
            let gris = fond(y), couleurFond = [gris, gris, max(0, gris - 8)]
            for x in 0..<l {
                let o = opacite(x, y), i = (y * l + x) * 4
                for k in 0..<3 {
                    let a = srgb(lin(sujet[k]) * (1 - o) + lin(couleurFond[k]) * o)
                    actuel[i + k] = a
                    for (t, effet) in effets.enumerated() { temoins[t][i + k] = srgb(lin(Double(a)) * pow(2, o * effet(k, Int(a)))) }
                }
            }
        }
        return (actuel, temoins)
    }

    /// La zone de mélange de ces rendus, comme le connecteur la fait (binaire, opacité).
    static func zoneDesRendus(_ actuel: [UInt8], _ temoins: [[UInt8]], largeur l: Int, hauteur h: Int) -> [Float] {
        let masque = binaire(actuel, temoins, largeur: l, hauteur: h)
        var calcul = Generatif.OpaciteDuMasque(binaire: masque, largeur: l, hauteur: h)
        for t in temoins { calcul.ajouter(actuel: actuel, temoin: t) }
        return Generatif.zoneDuMasque(calcul.opacite(binaire: masque), largeurPhoto: l, cadre: Generatif.Pixels(x: 0, y: 0, largeur: l, hauteur: h))
    }

    /// La rampe renforcée attendue pour une opacité de Lightroom.
    static func rampe(_ o: Double) -> Float {
        let t = Float(min(1, max(0, (o - Generatif.opaciteBas) / (Generatif.opaciteHaut - Generatif.opaciteBas))))
        return t * t * (3 - 2 * t)
    }

    /// Un masque de Lightroom partiel sur des centaines de pixels (un radial ou un dégradé fondus, un
    /// bord affiné) : l'opacité se lit sur toute la rampe, sans marche à l'intérieur du masque binaire ;
    /// elle n'est jamais forcée pleine à une profondeur fixe (une profondeur de 6 px, ici, mettait Fibo
    /// entier là où Lightroom n'en met que 12 %, une marche d'environ 55 % le long du contour). Le
    /// binaire ne commence qu'à environ 10 % d'opacité (le seuil de 6 niveaux), d'où un saut de départ
    /// au bord du binaire, comme avant ; et l'effet plein, relevé dans un intérieur sûr qui a ici des
    /// pixels partiels, y est sous-estimé : la zone monte plus tôt que Lightroom, sans marche.
    func testOpaciteSansMarcheSurUneLongueRampe() {
        let l = 1600, h = 300
        func o(_ x: Int, _ y: Int) -> Double { min(1, max(0, (Double(x) + 0.5 - 400) / 400)) }
        let (actuel, temoins) = Self.rendusDoux(largeur: l, hauteur: h, opacite: o, fond: { 20 + 220 * Double($0) / Double(h) },
                                                effets: [{ _, _ in -2 }, { _, _ in 1.5 }])
        let zone = Self.zoneDesRendus(actuel, temoins, largeur: l, hauteur: h)
        let masque = Self.binaire(actuel, temoins, largeur: l, hauteur: h)
        for y in [60, 150, 240] {
            func z(_ x: Int) -> Float { zone[y * l + x] }
            let bord = (0..<l).first { masque[y * l + $0] != 0 }!
            XCTAssertEqual(o(bord, y), 0.1, accuracy: 0.03, "le binaire commence vers 10 % d'opacité (y \(y))")
            XCTAssertLessThan(z(bord), 0.45, "un départ doux au bord du binaire (y \(y))")
            var sautMax: Float = 0
            for x in (bord + 4)..<1200 {
                sautMax = max(sautMax, abs(z(x + 1) - z(x)))
                XCTAssertGreaterThanOrEqual(z(x + 1), z(x) - 0.01, "la zone monte avec l'opacité (x \(x), y \(y))")
            }
            XCTAssertLessThan(sautMax, 0.04, "aucune marche dans le masque (y \(y))")
            XCTAssertLessThan(z(bord + 6), 0.6, "jamais plein à quelques pixels du bord : Lightroom n'y met que 12 % (y \(y))")
            XCTAssertLessThan(z(480), 0.95, "ni à 20 % d'opacité (y \(y))")
            for x in stride(from: 650, to: l, by: 50) { XCTAssertGreaterThan(z(x), 0.97, "plein là où Lightroom l'est presque (x \(x))") }
        }
    }

    /// L'effet plein se lit par canal et par valeur de l'état actuel : des témoins dont l'effet change
    /// avec la valeur (une courbe de tonalité : le sombre baisse plus les tons clairs ; des noirs
    /// relevés : le clair monte plus les tons sombres, et s'écrête au blanc), et plus froids (le bleu
    /// monte, le rouge baisse). L'opacité suit Lightroom sur une ligne sombre comme sur une ligne où le
    /// témoin clair s'écrête ; une table lue par la valeur du témoin s'en écarterait.
    func testOpaciteSuitUnEffetQuiDependDeLaValeur() {
        let l = 1200, h = 1000
        func o(_ x: Int, _ y: Int) -> Double { min(1, max(0, (Double(x) + 0.5 - 600) / 10)) }
        func froid(_ k: Int) -> Double { k == 2 ? 0.4 : k == 0 ? -0.4 : 0 }
        let sombre: (Int, Int) -> Double = { k, v in -1.2 - 2.8 * Double(v) / 255 + froid(k) }
        let clair: (Int, Int) -> Double = { k, v in 0.4 + 4 * pow(1 - Double(v) / 255, 3) + froid(k) }
        let (actuel, temoins) = Self.rendusDoux(largeur: l, hauteur: h, opacite: o, fond: { 12 + 233 * Double($0) / Double(h - 1) },
                                                effets: [sombre, clair])
        // Le témoin clair s'écrête au blanc dans le fond des lignes claires.
        XCTAssertEqual(temoins[1][(950 * l + 1000) * 4 + 2], 255)
        let zone = Self.zoneDesRendus(actuel, temoins, largeur: l, hauteur: h)
        for y in [60, 120, 500, 900, 960] {
            for x in 601...603 {
                XCTAssertEqual(zone[y * l + x], Self.rampe(o(x, y)), accuracy: 0.12, "x \(x), y \(y)")
            }
            XCTAssertEqual(zone[y * l + 900], 1, "plein dans le fond (y \(y))")
            XCTAssertEqual(zone[y * l + 590], 0, "hors du masque élargi (y \(y))")
        }
    }

    /// Le repli (des témoins muets) garde tout l'ancien bord, même là où le fondu binaire dépasse les
    /// deux pixels du calcul (4 px pour une photo de 2 400 px de côté, 6 px à 4 160 px) : jamais plus
    /// dur que lui.
    func testRepliSurToutLaLargeurDuFonduBinaire() {
        let l = 2400, h = 2400
        XCTAssertEqual(Generatif.etendueFondu(largeur: l, hauteur: h), 4)
        XCTAssertGreaterThan(Generatif.margeOpacite(largeur: l, hauteur: h), Generatif.opaciteMarge)
        var masque = [UInt8](repeating: 0, count: l * h)
        for y in 0..<h { for x in 1200..<l { masque[y * l + x] = 1 } }
        let actuel = [UInt8](repeating: 128, count: l * h * 4)
        var calcul = Generatif.OpaciteDuMasque(binaire: masque, largeur: l, hauteur: h)
        calcul.ajouter(actuel: actuel, temoin: actuel)
        calcul.ajouter(actuel: actuel, temoin: actuel)
        let doux = calcul.opacite(binaire: masque)
        let repli = Generatif.fonduBinaire(masque, largeurPhoto: l, hauteurPhoto: h, cadre: Generatif.Pixels(x: 0, y: 0, largeur: l, hauteur: h))
        let ligne = 1200 * l
        XCTAssertGreaterThan(repli[ligne + 1200 - 3], 0, "le fondu binaire passe les deux pixels")
        for x in 1185..<1215 {
            XCTAssertEqual(Float(doux[ligne + x]) / 255, repli[ligne + x], accuracy: 1 / 255 + 1e-6, "le repli : tout le fondu binaire (x \(x))")
        }
        XCTAssertEqual(doux[ligne + 1200 - 5], 0, "au-delà du fondu, 0")
    }

    /// L'opacité remise à une autre taille (rendus plus petits que le TIFF) reste douce : bilinéaire,
    /// sans marche plus haute que la moitié d'un pas d'origine ; 0 hors du binaire remis à la taille et
    /// élargi.
    func testOpaciteRemiseALaTailleEnDouceur() {
        let l = 300, h = 200, nl = 600, nh = 400
        var opacite = [UInt8](repeating: 0, count: l * h), masque = [UInt8](repeating: 0, count: l * h)
        for y in 0..<h {
            for x in 0..<l {
                opacite[y * l + x] = UInt8(min(255, max(0, (x - 140) * 255 / 20)))
                masque[y * l + x] = x >= 141 ? 1 : 0
            }
        }
        let binaire = Generatif.redimensionner(masque, largeur: l, hauteur: h, versLargeur: nl, versHauteur: nh)
        let grande = Generatif.redimensionnerOpacite(opacite, largeur: l, hauteur: h, binaire: binaire, versLargeur: nl, versHauteur: nh)
        XCTAssertEqual(grande.count, nl * nh)
        let ligne = 200 * nl
        var saut = 0, intermediaires = 0
        for x in 0..<(nl - 1) {
            let a = Int(grande[ligne + x]), b = Int(grande[ligne + x + 1])
            XCTAssertGreaterThanOrEqual(b, a, "monotone (x \(x))")
            saut = max(saut, b - a)
            if a > 0 && a < 255 { intermediaires += 1 }
        }
        XCTAssertLessThanOrEqual(saut, 8, "au plus proche voisin, une marche de 12 tous les deux pixels")
        XCTAssertGreaterThan(intermediaires, 30)
        let premier = (0..<nl).first { binaire[ligne + $0] != 0 }!
        for x in 0..<(premier - Generatif.margeOpacite(largeur: nl, hauteur: nh)) { XCTAssertEqual(grande[ligne + x], 0, "x \(x)") }
        XCTAssertEqual(grande[ligne + nl - 1], 255)
    }

    /// La distance en échiquier (dedans et dehors), et le lissage entier qui garde 0 et 255 loin de
    /// tout bord.
    func testDistanceEchiquierEtLissage() {
        let l = 7, h = 5
        var masque = [UInt8](repeating: 0, count: l * h)
        for y in 0..<h { for x in 3..<l { masque[y * l + x] = 1 } }
        let dedans = Generatif.distanceEchiquier(masque, largeur: l, hauteur: h, dedans: true, plafond: 10)
        XCTAssertEqual(Array(dedans[(2 * l)..<(3 * l)]), [0, 0, 0, 1, 2, 3, 4], "le bord de l'image n'est pas une frontière")
        let dehors = Generatif.distanceEchiquier(masque, largeur: l, hauteur: h, dedans: false, plafond: 2)
        XCTAssertEqual(Array(dehors[(2 * l)..<(3 * l)]), [2, 2, 1, 0, 0, 0, 0], "plafonnée")
        var v = [UInt8](repeating: 0, count: 20 * 20)
        for y in 0..<20 { for x in 10..<20 { v[y * 20 + x] = 255 } }
        Generatif.lisserOpacite(&v, largeur: 20, hauteur: 20)
        XCTAssertEqual(Array(v[(10 * 20 + 6)..<(10 * 20 + 14)]), [0, 0, 28, 85, 170, 227, 255, 255])
    }

    /// Le flou en place (sommes entières, un anneau de lignes) rend le même fondu que deux flous en
    /// boîte ordinaires.
    func testFlouEnPlaceCommeDeuxFlousEnBoite() {
        let l = 37, h = 23
        var valeurs = (0..<(l * h)).map { Float(($0 * 7919) % 13 < 5 ? 1 : 0) }
        let attendu = Generatif.flouBoite(Generatif.flouBoite(valeurs, largeur: l, hauteur: h, rayon: 3), largeur: l, hauteur: h, rayon: 3)
        Generatif.sommeBoiteEnPlace(&valeurs, largeur: l, hauteur: h, rayon: 3, passages: 2)
        for i in 0..<(l * h) { XCTAssertEqual(valeurs[i], attendu[i], accuracy: 1e-5, "\(i)") }
    }

    /// 26 Mpx (une photo de X-H2S) : masque binaire des deux témoins, nettoyage, masque de Fibo et zone
    /// de mélange en temps borné. La durée est dite dans le journal des tests ; la borne n'est stricte
    /// que compilé pour la publication (la machine virtuelle des tests GitHub, en débogage, est
    /// plusieurs fois plus lente que le Mac Studio).
    func testMasqueDeVingtSixMegapixelsEnTempsBorne() {
        let l = 6240, h = 4160, n = l * h
        var actuel = [UInt8](repeating: 128, count: n * 4)
        var sombre = actuel, clair = actuel
        for y in 0..<h {
            for x in 0..<l where hypot(Double(x - 3120), Double(y - 2080)) > 1500 {
                let i = (y * l + x) * 4
                sombre[i] = 40; sombre[i + 2] = 170
                clair[i] = 200
            }
        }
        // Du bruit : des points isolés hors du masque, et des trous d'un pixel dans lui.
        for k in 0..<20_000 {
            let i = (k * 7_919 % n) * 4
            if hypot(Double((i / 4) % l - 3120), Double((i / 4) / l - 2080)) < 1400 { sombre[i] = 120 } else { sombre[i] = 128; clair[i] = 128 }
        }
        var debut = Date()
        var masque = [UInt8](repeating: 0, count: n)
        Generatif.ajouterAuMasque(&masque, actuel: actuel, temoin: sombre)
        Generatif.ajouterAuMasque(&masque, actuel: actuel, temoin: clair)
        actuel = []; sombre = []; clair = []
        let dureeBinaire = Date().timeIntervalSince(debut)
        debut = Date()
        Generatif.nettoyer(&masque, largeur: l, hauteur: h)
        let dureeNettoyage = Date().timeIntervalSince(debut)
        let (part, cadreRelatif) = Generatif.cadreDuMasque(masque, largeur: l, hauteur: h)
        XCTAssertEqual(part, 1 - Double.pi * 1500 * 1500 / Double(n), accuracy: 0.002)
        let (cadre, taille) = Generatif.recadrage(cadreRelatif!, largeur: l, hauteur: h)
        debut = Date()
        let entree = Generatif.masquePourFibo(masque, largeurPhoto: l, cadre: cadre, taille: taille)
        let dureeEntree = Date().timeIntervalSince(debut)
        // L'opacité du bord : les témoins refaits (le sombre, puis le clair), l'un après l'autre.
        debut = Date()
        var opacite = Generatif.OpaciteDuMasque(binaire: masque, largeur: l, hauteur: h)
        for sombre in [true, false] {
            var actuel = [UInt8](repeating: 128, count: n * 4), temoin = actuel
            temoin.withUnsafeMutableBufferPointer { t in
                masque.withUnsafeBufferPointer { m in
                    for p in 0..<n where m[p] != 0 {
                        if sombre { t[p * 4] = 40; t[p * 4 + 2] = 170 } else { t[p * 4] = 200 }
                    }
                }
            }
            opacite.ajouter(actuel: actuel, temoin: temoin)
            actuel = []; temoin = []
        }
        let doux = opacite.opacite(binaire: masque)
        let dureeOpacite = Date().timeIntervalSince(debut)
        let dansLeMasque = masque.withUnsafeBufferPointer { m in (0..<n).reduce(0) { $0 + Int(m[$1]) } }
        XCTAssertGreaterThanOrEqual(opacite.numerateur.count, dansLeMasque, "tout le masque binaire, jamais forcé plein en profondeur")
        XCTAssertLessThan(opacite.numerateur.count, dansLeMasque + n / 100, "et le bord hors de lui, de deux pixels")
        debut = Date()
        let zone = Generatif.zoneDuMasque(doux, largeurPhoto: l, cadre: cadre)
        let dureeZone = Date().timeIntervalSince(debut) + dureeOpacite
        XCTAssertEqual(zone[100 * cadre.largeur + 100], 1, "l'arrière-plan, loin du sujet : plein")
        XCTAssertEqual(zone.count, cadre.largeur * cadre.hauteur)
        XCTAssertEqual(entree.count, taille.largeur * taille.hauteur)
        XCTAssertEqual(zone[2080 * cadre.largeur + 3120 - cadre.x], 0, "le centre (le sujet) reste hors du masque")
        let total = dureeBinaire + dureeNettoyage + dureeEntree + dureeZone
        print("Masque de 26 Mpx : binaire \(Self.secondes(dureeBinaire)), nettoyage \(Self.secondes(dureeNettoyage)), masque de Fibo \(Self.secondes(dureeEntree)), opacité du bord et zone de mélange \(Self.secondes(dureeZone)) (dont témoins refaits), en tout \(Self.secondes(total))")
        #if DEBUG
        XCTAssertLessThan(total, 240, "temps borné, compilé pour le débogage (machine virtuelle lente comprise)")
        #else
        XCTAssertLessThan(total, 30, "temps borné")
        #endif
    }

    static func secondes(_ t: TimeInterval) -> String { String(format: "%.2f s", t) }

    /// mask : le masque calculé par Lightroom (l'arrière-plan) remplace region ; il est lu après
    /// l'exportation (l'accord de Lightroom s'y demande d'abord) par deux essayer (taille 0, temoin ;
    /// l'état actuel avec le premier, le témoin sombre puis le clair) ; Fibo reçoit ce masque, élargi ;
    /// hors du masque (la personne), les pixels du TIFF exporté restent au bit près, même si Fibo l'a
    /// changée, jusqu'au fondu du bord (pas jusqu'à l'élargissement donné à Fibo).
    func testMasqueDeLightroomDeBoutEnBout() throws {
        masqueRendu = { !Self.dansLaPersonne($0, $1) }
        fauxMflux(sortie: sortiePreparee(region: CGRect(x: 0, y: 0, width: 1, height: 1)) { _, _, p, i in Self.bleu(&p, i) })
        let resultat = editer(["instruction": "replace the background with a plain blue studio backdrop, keep the person unchanged",
                               "mask": ["kind": "background"], "label": "fond"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(fake.commands, ["etat", "exporter", "essayer", "essayer", "importerGeneree"],
                       "l'exportation (et son accord) d'abord, puis les deux témoins ; aucun recalage pour un masque IA")
        let essais = fake.calls.filter { $0.command == "essayer" }.map(\.params)
        for essai in essais {
            XCTAssertEqual(essai["taille"]?.int, 0, "pleine résolution")
            XCTAssertEqual(essai["temoin"]?.bool, true, "aucun accord demandé dans Lightroom")
            XCTAssertEqual(essai["action"]?.string, "masquer")
            XCTAssertEqual(essai["photo"]?.int, 7)
        }
        XCTAssertEqual(essais.map { $0["comparer"]?.bool }, [true, false], "l'état actuel une seule fois")
        XCTAssertEqual(essais.map { $0["masques"]?.array?.first?["locaux"] }, Generatif.temoinsMasque.map { JSONValue.object($0) },
                       "le témoin sombre, puis le clair")
        let temoin = try XCTUnwrap(essais.first?["masques"]?.array?.first)
        XCTAssertEqual(temoin["type"]?.string, "ia"); XCTAssertEqual(temoin["soustype"]?.int, 0); XCTAssertEqual(temoin["categorie"]?.int, 22)
        XCTAssertEqual(temoin["quantite"]?.double, 1)
        XCTAssertEqual(temoin["inverser"]?.bool, false)
        XCTAssertEqual(temoin["nom"]?.string, "Claude · masque pour Fibo 2")

        // Le masque donné à Fibo : l'arrière-plan, élargi ; la personne en noir.
        let (_, taille) = Generatif.recadrage(CGRect(x: 0, y: 0, width: 1, height: 1), largeur: largeur, hauteur: hauteur)
        XCTAssertEqual(valeur("--width"), String(taille.largeur))
        let masque = try XCTUnwrap(Self.pixels8(gardes.appendingPathComponent("masque.png")))
        XCTAssertEqual(masque.largeur, taille.largeur); XCTAssertEqual(masque.hauteur, taille.hauteur)
        XCTAssertEqual(masque.valeur(10, 10), 255, "l'arrière-plan")
        XCTAssertEqual(masque.valeur(taille.largeur / 2, taille.hauteur / 2), 0, "la personne")
        let bordGauche = Int(0.4 * Double(taille.largeur))
        XCTAssertEqual(masque.valeur(bordGauche + 2, taille.hauteur / 2), 255, "élargi : Fibo redessine aussi le bord")
        XCTAssertNil(argumentsSeedVR)

        // Le TIFF final : la personne (x de 240 à 359, y de 120 à 279), hors du fondu du bord (2 px),
        // au bit près, jusqu'à 3 px du bord : l'élargissement donné à Fibo (environ 4 px) n'y revient pas.
        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        var identiques = 0, compares = 0
        for y in 0..<hauteur {
            for x in 0..<largeur {
                guard x >= 240 + 3, x <= 359 - 3, y >= 120 + 3, y <= 279 - 3 else { continue }
                compares += 1
                if Self.pixel(avant, x, y) == Self.pixel(apres, x, y) { identiques += 1 }
            }
        }
        XCTAssertGreaterThan(compares, 15_000)
        XCTAssertEqual(identiques, compares, "hors du masque, les pixels du TIFF exporté, même là où Fibo a tout repeint")
        for (x, y) in [(20, 20), (20, 380), (580, 380)] {
            let p = Self.pixel(apres, x, y)
            XCTAssertGreaterThan(p[2], 40_000, "repeint par Fibo en (\(x), \(y)), noir pur et blanc pur du fond compris : \(p)")
            XCTAssertLessThan(p[0], 15_000, "\(p)")
        }
        XCTAssertNotEqual(Self.pixel(apres, 237, 200), Self.pixel(avant, 237, 200), "le fond, juste hors de la personne")

        // La réponse : le bloc masque, sans region, le recadrage.
        let reponse = try JSONCoding.parse(resultat.text)
        let bloc = try XCTUnwrap(reponse["masque"])
        XCTAssertEqual(bloc["kind"]?.string, "background")
        XCTAssertEqual(bloc["inverse"]?.bool, false)
        XCTAssertEqual(bloc["calcule_par"]?.string, "Lightroom")
        XCTAssertEqual(bloc["part_de_la_photo_pct"]?.double ?? 0, 92, accuracy: 1)
        XCTAssertEqual(bloc["cadre"]?["width"]?.double, 1)
        XCTAssertTrue(bloc["lecture"]?.string?.contains("garde ses pixels") == true)
        XCTAssertNil(bloc["remarques"])
        let modification = try XCTUnwrap(reponse["modifications"]?.array?.first)
        XCTAssertNil(modification["region"])
        XCTAssertNotNil(modification["recadrage_px"])
        XCTAssertEqual(modification["reprise"]?.bool, true)
        XCTAssertTrue(modification["resolution_zone"]?.string?.hasPrefix("La zone vient de la sortie de Fibo 2") == true, resultat.text)
        let messages = fake.progressions.compactMap { $0["message"]?.string }
        XCTAssertTrue(messages.contains { $0.hasPrefix("Fibo 2 : masque de Lightroom (rendu en pleine taille), 0 %") }, "\(messages)")
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// Des rendus d'une autre taille que le TIFF exporté : le masque est remis à sa taille.
    func testMasqueRemisALaTailleDuTIFF() throws {
        tailleRendu = (300, 200)
        masqueRendu = { !Self.dansLaPersonne($0, $1) }
        fauxMflux(sortie: sortiePreparee(region: CGRect(x: 0, y: 0, width: 1, height: 1)) { _, _, p, i in Self.bleu(&p, i) })
        let resultat = editer(["instruction": "replace the background", "mask": ["kind": "background"]])
        XCTAssertFalse(resultat.isError, resultat.text)
        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        XCTAssertEqual(Self.pixel(apres, 300, 200), Self.pixel(avant, 300, 200), "la personne, au milieu")
        XCTAssertGreaterThan(Self.pixel(apres, 20, 20)[2], 40_000)
        XCTAssertEqual(try JSONCoding.parse(resultat.text)["masque"]?["part_de_la_photo_pct"]?.double ?? 0, 92, accuracy: 2)
    }

    /// Développement (`DEVELOPPEUR_FIBO_GARDER`) : les fichiers de chaque appel sont copiés dans un
    /// sous-dossier à son nom, rendus du masque compris ; un témoin qui ne se lit pas n'est pas écrit
    /// (jamais le précédent sous son nom).
    func testFichiersGardesPourLeDeveloppement() throws {
        let garde = dossier.appendingPathComponent("garde")
        tools.fibo?.garderDans = garde
        masqueRendu = { !Self.dansLaPersonne($0, $1) }
        fauxMflux(sortie: sortiePreparee(region: CGRect(x: 0, y: 0, width: 1, height: 1)) { _, _, p, i in Self.bleu(&p, i) })
        let resultat = editer(["instruction": "replace the background", "mask": ["kind": "background"]])
        XCTAssertFalse(resultat.isError, resultat.text)
        let appels = try FileManager.default.contentsOfDirectory(atPath: garde.path)
        XCTAssertEqual(appels.count, 1)
        let fichiers = Set(try FileManager.default.contentsOfDirectory(atPath: garde.appendingPathComponent(appels[0]).path))
        for nom in ["masque-actuel.jpg", "masque-temoin-1.jpg", "masque-temoin-2.jpg", "DSCF2402.tif"] {
            XCTAssertTrue(fichiers.contains(nom), "\(nom) dans \(fichiers.sorted())")
        }
        XCTAssertEqual(dossiersTemporairesRestants, [], "le dossier de l'appel est effacé comme toujours")

        // Le second témoin ne se lit pas : le premier n'est pas écrit sous son nom.
        let precedent = fake.onSend
        fake.onSend = { [unowned self] commande, params in
            precedent?(commande, params)
            if commande == "essayer", params["comparer"]?.bool == false, var reponse = self.fake.replies["essayer"]?.object {
                reponse["chemin"] = .string(self.dossier.appendingPathComponent("absent.jpg").path)
                self.fake.replies["essayer"] = .object(reponse)
            }
        }
        let echec = editer(["instruction": "replace the background", "mask": ["kind": "background"]])
        XCTAssertTrue(echec.isError && echec.text.contains("n'a pas pu se lire"), echec.text)
        let second = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: garde.path).first { $0 != appels[0] })
        let lus = Set(try FileManager.default.contentsOfDirectory(atPath: garde.appendingPathComponent(second).path))
        XCTAssertTrue(lus.contains("masque-temoin-1.jpg"), "\(lus.sorted())")
        XCTAssertFalse(lus.contains("masque-temoin-2.jpg"), "\(lus.sorted())")
    }

    /// Un masque presque vide ou presque total est refusé avant tout calcul de Fibo 2 (après
    /// l'exportation, où l'accord se demande) ; mflux ne tourne pas, rien n'est importé.
    func testMasqueVideOuTotalRefuseSansCalculer() {
        fauxMflux()
        masqueRendu = { _, _ in false }
        let vide = editer(["instruction": "replace the sky", "mask": ["kind": "sky"]])
        XCTAssertTrue(vide.isError); XCTAssertTrue(vide.text.contains("ne couvre presque rien") && vide.text.contains("Rien n'a été fait"), vide.text)
        XCTAssertEqual(fake.commands, ["etat", "exporter", "essayer", "essayer"])
        masqueRendu = { _, _ in true }
        fake.calls = []
        let total = editer(["instruction": "replace the background", "mask": ["kind": "background"]])
        XCTAssertTrue(total.isError); XCTAssertTrue(total.text.contains("couvre toute la photo"), total.text)
        XCTAssertEqual(fake.commands, ["etat", "exporter", "essayer", "essayer"])
        XCTAssertEqual(appelsDeMflux, 0)
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// « Proposer d'abord » avec l'accord dans Lightroom : l'accord se demande à l'exportation, avant
    /// tout rendu du masque (rendus avant, ils se perdaient et se refaisaient au rappel).
    func testMasqueApresLAccordDeLExportation() {
        fauxMflux()
        masqueRendu = { !Self.dansLaPersonne($0, $1) }
        fake.replies["etat"] = ["mode": "proposer d'abord", "pause": false, "photo_active": ["id": 7]]
        fake.errors["exporter"] = LightroomError.plugin("Proposition en attente de votre accord : rien n'a été écrit. L'utilisateur accepte la proposition dans la fenêtre de la liaison de Lightroom (bouton Accepter, ouverte pour lui) ; ensuite, rappeler generative_edit avec confirm = true.")
        let resultat = editer(["instruction": "replace the background", "mask": ["kind": "background"], "confirm": true])
        XCTAssertTrue(resultat.isError && resultat.text.contains("en attente de votre accord"), resultat.text)
        XCTAssertEqual(fake.commands, ["etat", "exporter"], "aucun rendu du masque avant l'accord")
        XCTAssertEqual(appelsDeMflux, 0)
    }

    /// Une personne précise : ses cadres (Vision, sur l'aperçu) partent avec le masque témoin, et ses
    /// recalages ; une personne que Lightroom n'a pas reconnue est refusée dès le premier rendu.
    func testMasqueDUnePersonne() throws {
        fauxMflux(sortie: sortiePreparee(region: CGRect(x: 0, y: 0, width: 1, height: 1)) { _, _, p, i in Self.bleu(&p, i) })
        masqueRendu = { Self.dansLaPersonne($0, $1) }
        tools.detecterPersonnes = { _ in [CGRect(x: 0.1, y: 0.3, width: 0.15, height: 0.6), CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.4),
                                          CGRect(x: 0.7, y: 0.3, width: 0.15, height: 0.6)] }
        fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 120, green: 120, blue: 120)))]
        let resultat = editer(["instruction": "replace the jacket with a red sweater", "mask": ["kind": "person", "person": 2]])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(fake.commands, ["etat", "exporter", "apercu", "geometrie", "essayer", "essayer", "importerGeneree"],
                       "l'aperçu de Vision et les recalages avant les rendus")
        let apercu = try XCTUnwrap(fake.calls.first { $0.command == "apercu" }).params
        XCTAssertEqual(apercu["photo"]?.int, 7)
        for essai in fake.calls.filter({ $0.command == "essayer" }) {
            let temoin = try XCTUnwrap(essai.params["masques"]?.array?.first)
            XCTAssertEqual(temoin["type"]?.string, "personne")
            XCTAssertEqual(temoin["numero"]?.int, 2)
            XCTAssertEqual(temoin["cadres"]?.array?.count, 3, "les cadres de toutes les personnes (InstanceBounds)")
        }
        XCTAssertEqual(try JSONCoding.parse(resultat.text)["masque"]?["kind"]?.string, "person")

        // Lightroom ne la reconnaît pas : refusée avant le second rendu, sans Fibo 2.
        fake.calls = []
        let avant = appelsDeMflux
        personnesNonReconnues = [["numero": 2, "trouvees": 3, "masque": "Claude · masque pour Fibo 2"]]
        fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 120, green: 120, blue: 120)))]
        let refus = editer(["instruction": "replace the jacket with a red sweater", "mask": ["kind": "person", "person": 2]])
        XCTAssertTrue(refus.isError && refus.text.contains("n'a pas reconnu la personne 2 (sur 3 trouvées par Vision)") && refus.text.contains("Rien n'a été fait"), refus.text)
        XCTAssertEqual(fake.commands, ["etat", "exporter", "apercu", "geometrie", "essayer"])
        XCTAssertEqual(appelsDeMflux, avant)
        XCTAssertEqual(dossiersTemporairesRestants, [])
    }

    /// Une zone positionnée (un dégradé radial) : recalée comme dans add_mask ; les remarques du module
    /// reviennent dans le bloc masque (sauf celle, sans objet, d'une clé sans valeur d'avant).
    func testMasqueRadialRecaleEtRemarques() throws {
        fauxMflux(sortie: sortiePreparee(region: CGRect(x: 0, y: 0, width: 1, height: 1)) { _, _, p, i in Self.bleu(&p, i) })
        masqueRendu = { hypot($0 - 0.5, $1 - 0.5) < 0.2 }
        let precedent = fake.onSend
        fake.onSend = { [unowned self] commande, params in
            precedent?(commande, params)
            if commande == "essayer", var reponse = self.fake.replies["essayer"]?.object {
                reponse["remarques"] = ["MaskGroupBasedCorrections n'avait pas de valeur : il garde celle de la proposition.",
                                        "La photo est redressée par Upright : positions recalées."]
                self.fake.replies["essayer"] = .object(reponse)
            }
        }
        let resultat = editer(["instruction": "replace the vase with a bowl of oranges",
                               "mask": ["kind": "radial", "center_x": 0.5, "center_y": 0.5, "radius_x": 0.2, "radius_y": 0.2]])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(fake.commands, ["etat", "exporter", "geometrie", "essayer", "essayer", "importerGeneree"])
        XCTAssertEqual(fake.calls.first { $0.command == "essayer" }?.params["masques"]?.array?.first?["type"]?.string, "radial")
        let remarques = try XCTUnwrap(JSONCoding.parse(resultat.text)["masque"]?["remarques"]?.array)
        XCTAssertEqual(remarques, ["La photo est redressée par Upright : positions recalées."], "une fois, sans la remarque sans objet")
    }

    /// refine (affinage de Lightroom 15.5) : refusé avant tout envoi sur une version plus ancienne,
    /// comme add_mask.
    func testMasqueAffineRefuseAvantLightroom155() {
        fauxMflux()
        fake.replies["etat"] = ["mode": "appliquer directement", "pause": false, "photo_active": ["id": 7], "lightroom": "15.4"]
        let refus = editer(["instruction": "replace the background", "mask": ["kind": "background", "refine": ["feather": 40]]])
        XCTAssertTrue(refus.isError && refus.text.contains("refine (depuis la 15.5)"), refus.text)
        XCTAssertEqual(fake.commands, ["etat"], "ni exportation ni rendu")
    }

    /// SeedVR2 et un masque trop étendu (un arrière-plan entier) : la remarque ne conseille jamais
    /// region, qui ne suivrait pas le bord du sujet.
    func testSeedVRAvecUnMasqueTropEtendu() {
        let cadre = Generatif.Pixels(x: 0, y: 0, largeur: 6240, hauteur: 4160)
        let avecMasque = Generatif.seedVR(cadre: cadre, taille: (1248, 832), avecRegion: true, demande: true, avecMasque: true)
        XCTAssertFalse(avecMasque.lancer)
        let raison = avecMasque.raison ?? ""
        XCTAssertTrue(raison.contains("arrière-plan") && raison.contains("Masque trop étendu"), raison)
        XCTAssertFalse(raison.contains("region"), raison)
        let avecRegion = Generatif.seedVR(cadre: cadre, taille: (1248, 832), avecRegion: true, demande: true)
        XCTAssertTrue(avecRegion.raison?.contains("Une region plus juste") == true)
    }

    /// mask : avec region, dans edits ou avec edits, avec un effet ou un réglage : refusé avant tout envoi.
    func testMasqueRefusAvantToutEnvoi() {
        fauxMflux()
        let avecRegion = editer(["instruction": "x", "mask": ["kind": "background"], "region": ["x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2]])
        XCTAssertTrue(avecRegion.isError && avecRegion.text.contains("l'un ou l'autre"), avecRegion.text)
        let dansEdits = editer(["edits": [["instruction": "x", "instruction_fr": "x", "mask": ["kind": "sky"]]]])
        XCTAssertTrue(dansEdits.isError && dansEdits.text.contains("pas de mask"), dansEdits.text)
        let avecEdits = editer(["mask": ["kind": "sky"], "edits": [["instruction": "x", "instruction_fr": "x", "region": ["x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2]]]])
        XCTAssertTrue(avecEdits.isError && avecEdits.text.contains("une seule modification"), avecEdits.text)
        for (cle, valeur) in [("effect", JSONValue.string("Peau du visage lisse")), ("adjustments", ["Exposure": 0.5]), ("amount", 50)] {
            let refus = editer(["instruction": "x", "mask": ["kind": "background", .init(stringLiteral: cle): valeur]])
            XCTAssertTrue(refus.isError && refus.text.contains("sans effet ni réglage") && refus.text.contains(cle), refus.text)
        }
        XCTAssertTrue(editer(["instruction": "x", "mask": ["part": "hair"]]).text.contains("kind"))
        XCTAssertTrue(editer(["instruction": "x", "mask": ["kind": "landscape", "part": "hair"]]).text.contains("part"))
        XCTAssertTrue(editer(["instruction": "x", "mask": "background"]).text.contains("un objet"))
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
    }

    /// Le schéma : mask décrit comme une zone d'add_mask, et ce qu'il faut savoir pour choisir.
    func testMaskDansLeSchema() throws {
        let outil = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "generative_edit" })
        let masque = try XCTUnwrap(outil["inputSchema"]?["properties"]?["mask"])
        let description = try XCTUnwrap(masque["description"]?.string)
        XCTAssertTrue(description.hasPrefix("Changer l'arrière-plan, le ciel, une personne : mask (masque de Lightroom) plutôt que region"), description)
        XCTAssertTrue(description.contains("existing, un masque que l'utilisateur a peint"), description)
        let cles = Set(masque["properties"]?.object?.keys.map { $0 } ?? [])
        XCTAssertTrue(cles.isSuperset(of: ["kind", "part", "person", "person_at", "invert", "combine", "box", "strokes", "existing"]), "\(cles)")
        XCTAssertTrue(cles.isDisjoint(with: ["effect", "adjustments", "amount", "name", "tone_curve", "point_colors"]), "\(cles)")
        XCTAssertTrue((masque["required"]?.array ?? []).isEmpty, "kind ou existing")
        XCTAssertTrue(outil["description"]?.string?.contains("Changer l'arrière-plan, le ciel, une personne, ou la zone que l'utilisateur a peinte : mask plutôt que region") == true)
    }

    // MARK: Fiche de FIBO-vlm, qualité équilibrée, exclusion, guidage, masque peint (29 octobre 2026)

    /// Le faux Python de mflux (jamais le vrai, ni le vrai FIBO-vlm) : note ses arguments et son
    /// environnement, garde l'image reçue, écrit son pid, puis (sauf `fin`) une fiche JSON dans --output
    /// et le marqueur de sa fin. Et le modèle FIBO-vlm du faux cache Hugging Face, complet.
    var fauxPython: URL { dossier.appendingPathComponent("python/bin/python") }

    func fauxVLM(fin: String? = nil, fiche: String? = nil, avecModele: Bool = true) {
        let g = gardes.path
        let json = fiche ?? #"{"short_description": "A woman in a navy knee-length skirt on a city street.", "objects": [{"description": "a woman"}], "background_setting": "a city street", "lighting": {"conditions": "overcast daylight", "direction": "front-lit"}, "edit_instruction": "Change the trousers in the masked region to a knee-length navy skirt."}"#
        try? json.write(to: gardes.appendingPathComponent("fiche-modele.json"), atomically: true, encoding: .utf8)
        let texte = """
        #!/bin/sh
        n=$(cat "\(g)/vlm-compte" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "\(g)/vlm-compte"
        printf '%s\\n' "$@" > "\(g)/vlm-arguments-$n.txt"
        echo "$HF_HUB_OFFLINE|$HF_HUB_CACHE" > "\(g)/vlm-env.txt"
        echo $$ > "\(g)/vlm-pid"
        rm -f "\(g)/vlm-fin"
        out=""; img=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --output) out="$2"; shift ;;
            --image) img="$2"; shift ;;
          esac
          shift
        done
        cp "$img" "\(g)/vlm-image-$n.png"
        \(fin ?? """
        cp "\(g)/fiche-modele.json" "$out"
        echo "fiche écrite : $out"
        """)
        touch "\(g)/vlm-fin"
        """
        try? FileManager.default.createDirectory(at: fauxPython.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? texte.write(to: fauxPython, atomically: true, encoding: .utf8)
        chmod(fauxPython.path, 0o755)
        tools.fibo?.python = fauxPython
        if avecModele { Self.modeleVLM(dans: dossier.appendingPathComponent("hf")) }
    }

    /// Un modèle FIBO-vlm complet (refs/main, config, index des poids et ses fichiers) dans un cache,
    /// sous la révision donnée (par défaut celle que mflux épingle), `refs/main` pointant sur `main`.
    static func modeleVLM(dans cache: URL, revision: String = Generatif.revisionVLM, main: String? = nil) {
        let depot = cache.appendingPathComponent("models--briaai--FIBO-vlm")
        let instantane = depot.appendingPathComponent("snapshots/" + revision)
        try? FileManager.default.createDirectory(at: instantane, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: depot.appendingPathComponent("refs"), withIntermediateDirectories: true)
        try? ((main ?? revision) + "\n").write(to: depot.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        try? "{}".write(to: instantane.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try? #"{"weight_map": {"a": "model-00001-of-00002.safetensors", "b": "model-00002-of-00002.safetensors"}}"#
            .write(to: instantane.appendingPathComponent("model.safetensors.index.json"), atomically: true, encoding: .utf8)
        for nom in ["model-00001-of-00002.safetensors", "model-00002-of-00002.safetensors"] {
            try? "poids".write(to: instantane.appendingPathComponent(nom), atomically: true, encoding: .utf8)
        }
    }

    func argumentsVLM(_ n: Int) -> [String] {
        (try? String(contentsOf: gardes.appendingPathComponent("vlm-arguments-\(n).txt"), encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast().map { $0 } ?? []
    }

    var appelsDuVLM: Int {
        Int((try? String(contentsOf: gardes.appendingPathComponent("vlm-compte"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    func existe(_ nom: String) -> Bool { FileManager.default.fileExists(atPath: gardes.appendingPathComponent(nom).path) }

    /// La fiche de FIBO-vlm, avant mflux : l'image grisée dans la zone comme mflux la grise, --use-mask,
    /// l'instruction anglaise et la graine ; le Python en -I, hors ligne ; mflux reçoit la fiche par
    /// --prompt-file (sans --prompt), et le processus du VLM est fini avant son lancement.
    func testFicheDeFiboVLMAvantMflux() throws {
        fauxVLM()
        let region = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4)
        fauxMflux(sortie: sortiePreparee(region: region) { fx, fy, p, i in if fx > 0.35, fx < 0.55, fy > 0.35, fy < 0.65 { Self.rouge(&p, i) } })
        let resultat = editer(["structured_prompt": true, "instruction": "replace the trousers with a knee-length navy skirt", "label": "jupe", "seed": 42,
                               "region": ["x": 0.3, "y": 0.3, "width": 0.3, "height": 0.4]])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(appelsDuVLM, 1)
        XCTAssertEqual(appelsDeMflux, 1)
        let args = argumentsVLM(1)
        XCTAssertEqual(args.first, "-I", "Python isolé")
        XCTAssertEqual(URL(fileURLWithPath: args[1]).lastPathComponent, "fiche-fibo-vlm.py")
        func apres(_ option: String) -> String? { args.firstIndex(of: option).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        XCTAssertEqual(apres("--instruction"), "replace the trousers with a knee-length navy skirt")
        XCTAssertEqual(apres("--seed"), "42")
        XCTAssertTrue(args.contains("--use-mask"))
        XCTAssertFalse(args.contains("--image-originale"), "plus de repli sans masque : une seule génération, en mode masqué")
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(apres("--image"))).lastPathComponent, "fiche-entree-1.png")
        XCTAssertEqual((try? String(contentsOf: gardes.appendingPathComponent("vlm-env.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines),
                       "1|" + dossier.appendingPathComponent("hf").path, "hors ligne, le cache où le modèle a été vu")
        // L'image du VLM : l'entrée de Fibo, grisée (128) dans le masque, intacte ailleurs.
        let image = try XCTUnwrap(Generatif.lireImage(gardes.appendingPathComponent("vlm-image-1.png"))?.image)
        let pixels = try XCTUnwrap(Generatif.pixelsRGBA8(image, largeur: image.width, hauteur: image.height))
        let masque = try XCTUnwrap(Self.pixels8(gardes.appendingPathComponent("masque.png")))
        XCTAssertEqual(image.width, masque.largeur); XCTAssertEqual(image.height, masque.hauteur)
        var grises = 0, hors = 0
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let i = (y * image.width + x) * 4
                if masque.valeur(x, y) >= 128 {
                    XCTAssertEqual([pixels[i], pixels[i + 1], pixels[i + 2]], [128, 128, 128]); grises += 1
                } else if pixels[i] != 128 || pixels[i + 1] != 128 || pixels[i + 2] != 128 { hors += 1 }
            }
        }
        XCTAssertGreaterThan(grises, 100); XCTAssertGreaterThan(hors, 100)
        // mflux : la fiche, sans la phrase ; le VLM fini avant.
        XCTAssertEqual(URL(fileURLWithPath: try XCTUnwrap(valeur("--prompt-file"))).lastPathComponent, "fiche-1.json")
        XCTAssertNil(valeur("--prompt"))
        let recue = try JSONCoding.parse(Data(contentsOf: gardes.appendingPathComponent("fiche-recue-1.json")))
        XCTAssertEqual(recue["edit_instruction"]?.string, "Change the trousers in the masked region to a knee-length navy skirt.")
        // Telle que FIBO-vlm l'a écrite, octet pour octet : l'ordre de ses clés (celui des légendes de
        // l'entraînement de Fibo 2) n'est jamais retrié.
        XCTAssertEqual(try String(contentsOf: gardes.appendingPathComponent("fiche-recue-1.json"), encoding: .utf8),
                       try String(contentsOf: gardes.appendingPathComponent("fiche-modele.json"), encoding: .utf8))
        XCTAssertEqual(recue["short_description"]?.string, "A woman in a navy knee-length skirt on a city street.")
        XCTAssertTrue(existe("vlm-fini-avant-1"), "FIBO-vlm a fini avant le lancement de mflux")
        XCTAssertFalse(existe("vlm-vivant-1"), "jamais les deux en mémoire ensemble")
        // La réponse : un court résumé de la fiche, pas tout le JSON.
        let reponse = try JSONCoding.parse(resultat.text)
        XCTAssertEqual(reponse["fiche_fibo_vlm"]?.bool, true)
        XCTAssertNil(reponse["remarque_fiche"])
        let fiche = try XCTUnwrap(reponse["modifications"]?.array?.first?["fiche"])
        XCTAssertEqual(fiche["redigee_par"]?.string, "FIBO-vlm")
        XCTAssertEqual(fiche["edit_instruction"]?.string, "Change the trousers in the masked region to a knee-length navy skirt.")
        XCTAssertEqual(fiche["lumiere"]?.string, "overcast daylight")
        XCTAssertEqual(fiche["objets_decrits"]?.int, 1)
        XCTAssertNil(fiche["objects"]); XCTAssertNil(fiche["lighting"])
        // La barre : la fiche avant le chargement du modèle.
        let messages = fake.progressions.compactMap { $0["message"]?.string }
        let iFiche = try XCTUnwrap(messages.firstIndex { $0.hasPrefix("Fibo 2 : jupe, ") && $0.hasSuffix("— fiche (FIBO-vlm)") }, "\(messages)")
        let iChargement = try XCTUnwrap(messages.firstIndex { $0.hasSuffix("— chargement du modèle") }, "\(messages)")
        XCTAssertLessThan(iFiche, iChargement)
        XCTAssertEqual(dossiersTemporairesRestants, [], "le script et la fiche partent avec le dossier de l'appel")

        // Sans zone : l'image entière, sans gris ni --use-mask.
        fauxMflux(sortie: sortiePreparee(carreRouge))
        XCTAssertFalse(editer(["structured_prompt": true, "instruction": "add a red scarf"]).isError)
        XCTAssertFalse(argumentsVLM(2).contains("--use-mask"))
        XCTAssertFalse(argumentsVLM(2).contains("--image-originale"))
    }

    /// FIBO-vlm en échec, hors délai, ou fiche illisible : jamais bloquant ; la phrase seule, et la
    /// réponse le dit.
    func testFicheEnEchecPhraseSeule() throws {
        fauxVLM(fin: "echo 'erreur FIBO-vlm : boom'\nexit 1")
        fauxMflux(sortie: sortiePreparee(carreRouge))
        var resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(valeur("--prompt"), "add a red scarf"); XCTAssertNil(valeur("--prompt-file"))
        var modification = try XCTUnwrap(JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertTrue(modification["remarque_fiche"]?.string?.contains("boom") == true, resultat.text)
        XCTAssertTrue(modification["remarque_fiche"]?.string?.contains("phrase seule") == true, resultat.text)
        XCTAssertNil(modification["fiche"])

        // Une fiche qui n'est pas un objet JSON.
        fauxVLM(fiche: "pas du JSON")
        resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertNil(valeur("--prompt-file"))
        modification = try XCTUnwrap(JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertTrue(modification["remarque_fiche"]?.string?.contains("sans fiche lisible") == true, resultat.text)

        // Une fiche sans edit_instruction : l'instruction donnée y est jointe.
        fauxVLM(fiche: #"{"short_description": "a red scarf"}"#)
        resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertFalse(resultat.isError, resultat.text)
        let n = appelsDeMflux
        XCTAssertEqual(try JSONCoding.parse(Data(contentsOf: gardes.appendingPathComponent("fiche-recue-\(n).json")))["edit_instruction"]?.string, "add a red scarf")
        // Jointe à la fin, l'ordre des clés gardé.
        let texte = try String(contentsOf: gardes.appendingPathComponent("fiche-recue-\(n).json"), encoding: .utf8)
        let iDescription = try XCTUnwrap(texte.range(of: "short_description")), iConsigne = try XCTUnwrap(texte.range(of: "edit_instruction"))
        XCTAssertLessThan(iDescription.lowerBound, iConsigne.lowerBound, texte)

        // Hors délai : arrêté, puis mflux avec la phrase.
        tools.fibo?.delaiFiche = 0.5
        fauxVLM(fin: "sleep 30")
        let debut = Date()
        resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertLessThan(Date().timeIntervalSince(debut), 20)
        XCTAssertEqual(valeur("--prompt"), "add a red scarf")
        modification = try XCTUnwrap(JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertTrue(modification["remarque_fiche"]?.string?.contains("n'a pas fini") == true, resultat.text)
        XCTAssertFalse(existe("vlm-vivant-\(appelsDeMflux)"), "le VLM arrêté avant mflux")
    }

    /// Sans le Python de mflux, ou sans le modèle dans le cache : la phrase seule, le VLM jamais lancé ;
    /// structured_prompt = false : la phrase seule, sans remarque.
    func testSansFiboVLMPhraseSeule() throws {
        fauxVLM(avecModele: false)
        fauxMflux(sortie: sortiePreparee(carreRouge))
        var resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(appelsDuVLM, 0)
        XCTAssertTrue(try JSONCoding.parse(resultat.text)["remarque_fiche"]?.string?.contains("hf download briaai/FIBO-vlm") == true, resultat.text)

        Self.modeleVLM(dans: dossier.appendingPathComponent("hf"))
        tools.fibo?.python = dossier.appendingPathComponent("absent/python")
        resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertTrue(try JSONCoding.parse(resultat.text)["remarque_fiche"]?.string?.contains("Python de mflux") == true, resultat.text)

        fauxVLM()
        resultat = editer(["instruction": "add a red scarf", "structured_prompt": false])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(appelsDuVLM, 0, "la phrase seule, demandée")
        XCTAssertNil(try JSONCoding.parse(resultat.text)["remarque_fiche"])
        XCTAssertEqual(valeur("--prompt"), "add a red scarf")
        XCTAssertTrue(editer(["instruction": "x", "structured_prompt": "oui"]).text.contains("structured_prompt"))

        // Le Python par défaut : à côté du vrai exécutable de mflux (son lien suivi), jamais un autre.
        let lien = dossier.appendingPathComponent("lien/mflux-generate-fibo2-edit")
        try FileManager.default.createDirectory(at: lien.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: lien, withDestinationURL: script)
        XCTAssertEqual(Fibo(executable: lien).python?.resolvingSymlinksInPath().path,
                       script.deletingLastPathComponent().appendingPathComponent("python").resolvingSymlinksInPath().path)
    }

    /// Une fiche que mflux refuse (format de légende) : la phrase seule, une fois, et la réponse le dit.
    func testFicheRefuseeParMfluxPhraseSeule() throws {
        fauxVLM()
        let preparee = sortiePreparee(carreRouge)
        fauxMflux(sortie: preparee, fin: """
        if [ -n "$fiche" ]; then echo "ValueError: The JSON caption does not have the format FIBO 2 reads:" >&2; exit 2; fi
        cp "\(gardes.path)/sortie.png" "$out"
        """)
        let resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(appelsDeMflux, 2)
        XCTAssertNotNil(argumentsDeLAppel(1).firstIndex(of: "--prompt-file"))
        XCTAssertEqual(argumentsDeLAppel(2).firstIndex(of: "--prompt").map { argumentsDeLAppel(2)[$0 + 1] }, "add a red scarf")
        let modification = try XCTUnwrap(JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertTrue(modification["remarque_fiche"]?.string?.contains("mflux a refusé la fiche") == true, resultat.text)
        XCTAssertNil(modification["fiche"])
    }

    /// Fibo 2 Studio (fibo_vlm_tool.py) ou le script de fiche d'un autre serveur : vus comme un calcul en cours.
    func testAutreCalculVoitLeVLM() throws {
        let motif = try NSRegularExpression(pattern: Fibo.motifAutreCalcul)
        func voit(_ ligne: String) -> Bool { motif.firstMatch(in: ligne, range: NSRange(ligne.startIndex..., in: ligne)) != nil }
        XCTAssertTrue(voit("/Users/x/.local/share/uv/tools/mflux/bin/python -I /Applications/Fibo 2 Studio.app/Contents/Resources/fibo_vlm_tool.py edit --image a.png"))
        XCTAssertTrue(voit("/Users/x/.local/share/uv/tools/mflux/bin/python -I /x/Temporaire/Fibo/ABC/fiche-fibo-vlm.py --image a.png"))
        XCTAssertTrue(voit("/Users/x/.local/share/uv/tools/mflux/bin/python /Users/x/.local/bin/mflux-generate-fibo2-edit --prompt x"))
        XCTAssertTrue(voit("mflux-upscale-seedvr2 --model seedvr2-7b"))
        XCTAssertFalse(voit("/usr/bin/python3 autre.py"))
        XCTAssertFalse(voit("fibo_vlm_toolXpy"), "le point est littéral")
        autreCalcul = true
        fauxVLM()
        fauxMflux()
        let refus = editer(["structured_prompt": true, "instruction": "x"])
        XCTAssertTrue(refus.isError && refus.text.contains("Fibo 2 calcule déjà"), refus.text)
        XCTAssertEqual(appelsDuVLM, 0)
        XCTAssertTrue(fake.commands.isEmpty, "\(fake.commands)")
    }

    /// Les arguments de mflux par qualité : équilibrée (30 étapes, --cfg-end 0.6), normale (50, sans
    /// --cfg-end), rapide (Turbo : ni guidage, ni exclusion, ni --cfg-end) ; le guidage et l'exclusion ;
    /// à guidance 1, ni exclusion ni --cfg-end ; la fiche à la place de la phrase.
    func testArgumentsParQualite() {
        let e = URL(fileURLWithPath: "/tmp/e.png"), s = URL(fileURLWithPath: "/tmp/s.png"), f = URL(fileURLWithPath: "/tmp/fiche.json")
        func args(_ q: Generatif.Qualite, fiche: URL? = nil, exclusion: String? = "text, logo", guidage: Double? = nil) -> [String] {
            Generatif.arguments(entree: e, masque: nil, instruction: "x", taille: (1024, 1024), qualite: q, graine: 1, sortie: s, modeleRapide: nil,
                                fiche: fiche, exclusion: exclusion, guidage: guidage)
        }
        func valeur(_ a: [String], _ o: String) -> String? { a.firstIndex(of: o).map { a[$0 + 1] } }
        let equilibre = args(.balanced)
        XCTAssertEqual(valeur(equilibre, "--steps"), "30"); XCTAssertEqual(valeur(equilibre, "--cfg-end"), "0.6")
        XCTAssertEqual(valeur(equilibre, "--negative-prompt"), "text, logo"); XCTAssertNil(valeur(equilibre, "--guidance"))
        XCTAssertTrue(equilibre.contains("--vae-full-precision") && equilibre.contains("--low-ram"))
        let normal = args(.normal, guidage: 7.5)
        XCTAssertEqual(valeur(normal, "--steps"), "50"); XCTAssertNil(valeur(normal, "--cfg-end"))
        XCTAssertEqual(valeur(normal, "--guidance"), "7.5"); XCTAssertEqual(valeur(normal, "--negative-prompt"), "text, logo")
        let rapide = args(.fast, guidage: 7)
        for option in ["--steps", "--cfg-end", "--negative-prompt", "--guidance", "--vae-full-precision"] {
            XCTAssertFalse(rapide.contains(option), option)
        }
        let sansGuidage = args(.balanced, guidage: 1)
        XCTAssertEqual(valeur(sansGuidage, "--guidance"), "1")
        XCTAssertNil(valeur(sansGuidage, "--negative-prompt")); XCTAssertNil(valeur(sansGuidage, "--cfg-end"))
        let avecFiche = args(.balanced, fiche: f)
        XCTAssertEqual(valeur(avecFiche, "--prompt-file"), "/tmp/fiche.json"); XCTAssertFalse(avecFiche.contains("--prompt"))
        XCTAssertEqual(Array(args(.fast, fiche: f).prefix(2)), ["--prompt-file", "/tmp/fiche.json"], "la fiche sert aussi au Turbo")
        XCTAssertEqual(Generatif.texteNombre(5), "5"); XCTAssertEqual(Generatif.texteNombre(0.6), "0.6"); XCTAssertEqual(Generatif.texteNombre(7.25), "7.25")
        XCTAssertEqual(Generatif.qualiteParDefaut, .balanced)
        XCTAssertEqual(Generatif.Qualite.balanced.etapes, 30)
    }

    /// avoid et guidance : validés avant tout envoi, passés hors Turbo ; en Turbo, la réponse dit qu'ils
    /// n'ont pas servi. La phrase d'exclusion laisse sa partie texte quand l'instruction parle de texte.
    func testExclusionEtGuidage() throws {
        fauxMflux(sortie: sortiePreparee(carreRouge))
        let resultatExclusion = editer(["instruction": "add a red scarf", "avoid": "sunglasses, a second dog", "guidance": 7.5])
        XCTAssertFalse(resultatExclusion.isError, resultatExclusion.text)
        XCTAssertEqual(valeur("--guidance"), "7.5")
        // La légende négative remplace la légende nulle de mflux : au format de cette légende (mêmes clés,
        // même ordre, toutes vides), les termes sous aesthetics.artifacts ; jamais des mots libres.
        let exclusion = try XCTUnwrap(valeur("--negative-prompt"))
        XCTAssertTrue(exclusion.hasPrefix(#"{"short_description":"","objects":[],"background_setting":"","lighting":{},"aesthetics":{"artifacts":["text","letters","words""#), exclusion)
        XCTAssertTrue(exclusion.hasSuffix(#""sunglasses, a second dog"]},"photographic_characteristics":{},"style_medium":"","context":"","artistic_style":""}"#), exclusion)
        let legende = try JSONCoding.parse(Data(exclusion.utf8))
        let artefacts = try XCTUnwrap(legende["aesthetics"]?["artifacts"]?.array?.compactMap(\.string))
        XCTAssertTrue(artefacts.contains("duplicate person") && artefacts.contains("extra head") && artefacts.contains("deformed"), exclusion)
        XCTAssertEqual(artefacts.last, "sunglasses, a second dog")
        XCTAssertEqual(Set(legende.object?.keys.map { $0 } ?? []),
                       ["short_description", "objects", "background_setting", "lighting", "aesthetics", "photographic_characteristics", "style_medium", "context", "artistic_style"],
                       "les clés de la légende nulle de mflux (Fibo2PromptEncoder.NULL_CAPTION)")
        XCTAssertEqual(try JSONCoding.parse(resultatExclusion.text)["modifications"]?.array?.first?["exclusion"]?.string?.hasSuffix("distorted anatomy, sunglasses, a second dog"), true)
        for (cle, valeurRefusee) in [("guidance", JSONValue.number(11)), ("guidance", 0.5), ("guidance", "fort"), ("avoid", "  "),
                                     ("avoid", .string(String(repeating: "a", count: 501)))] {
            let refus = editer(["instruction": "x", .init(stringLiteral: cle): valeurRefusee])
            XCTAssertTrue(refus.isError && refus.text.contains(cle), refus.text)
        }
        XCTAssertTrue(editer(["instruction": "x", "guidance": 11]).text.contains("de 1 à 10"))
        let avant = fake.commands.count
        _ = editer(["instruction": "x", "guidance": 0])
        XCTAssertEqual(fake.commands.count, avant, "refusé avant tout envoi")

        // En Turbo : rien de cela, et la réponse le dit.
        let turbo = editer(["instruction": "add a red scarf", "quality": "fast", "avoid": "sunglasses", "guidance": 8])
        XCTAssertFalse(turbo.isError, turbo.text)
        XCTAssertNil(valeur("--negative-prompt")); XCTAssertNil(valeur("--guidance"))
        let reponse = try JSONCoding.parse(turbo.text)
        XCTAssertTrue(reponse["remarque_guidage"]?.string?.contains("avoid et guidance n'ont pas servi") == true, turbo.text)
        XCTAssertNil(reponse["guidage"])
        XCTAssertNil(reponse["modifications"]?.array?.first?["exclusion"])

        // Sans avoid ni guidance en Turbo : pas de remarque.
        XCTAssertNil(try JSONCoding.parse(editer(["instruction": "add a red scarf", "quality": "fast"]).text)["remarque_guidage"])

        // Une instruction qui parle de texte : la partie texte de l'exclusion est laissée de côté.
        XCTAssertFalse(Generatif.termesExclusion(instruction: #"change the sign to "Open""#, avoid: nil).contains("letters"))
        XCTAssertFalse(Generatif.termesExclusion(instruction: "write HELLO on the mug", avoid: nil).contains("text"))
        XCTAssertEqual(Array(Generatif.termesExclusion(instruction: "replace the trousers with a skirt", avoid: nil).prefix(2)), ["text", "letters"])
        // Une instruction qui ajoute une personne : sans « duplicate person », qui pousserait contre elle ;
        // une personne déjà là (l'habiller) le garde.
        for ajout in ["Add a person walking in the background", "add two people on the bench", "Insert a young woman near the door",
                      "a second man behind the car", "add another child"] {
            XCTAssertFalse(Generatif.termesExclusion(instruction: ajout, avoid: nil).contains("duplicate person"), ajout)
            XCTAssertTrue(Generatif.termesExclusion(instruction: ajout, avoid: nil).contains("extra head"), ajout)
        }
        for habiller in ["replace the woman's trousers with a skirt", "put a hat on the man", "make the person's jacket red"] {
            XCTAssertTrue(Generatif.termesExclusion(instruction: habiller, avoid: nil).contains("duplicate person"), habiller)
        }
        // Un terme avec des guillemets reste du JSON valide.
        XCTAssertEqual(try JSONCoding.parse(Data(Generatif.exclusion(instruction: "x", avoid: #"a "logo""#).utf8))["aesthetics"]?["artifacts"]?.array?.last?.string, #"a "logo""#)
        XCTAssertFalse(Generatif.parleDeTexte("redesign the garden"), "design n'est pas sign")
    }

    func testAvancementAvecFiche() {
        let sans = Generatif.Avancement(seedVR: [false])
        let avec = Generatif.Avancement(seedVR: [false], fiche: [true])
        XCTAssertEqual(avec.pourcentage(.fiche(0, fraction: 0)), sans.pourcentage(.chargement(0)), "la fiche commence où commençait le chargement")
        XCTAssertGreaterThan(avec.pourcentage(.chargement(0)), avec.pourcentage(.fiche(0, fraction: 0.5)))
        XCTAssertGreaterThan(avec.pourcentage(.fiche(0, fraction: 0.5)), avec.pourcentage(.fiche(0, fraction: 0)))
        XCTAssertEqual(avec.pourcentage(.fin), 94)
        let deux = Generatif.Avancement(seedVR: [false, false], fiche: [true, true])
        XCTAssertGreaterThan(deux.pourcentage(.fiche(1, fraction: 0)), deux.pourcentage(.etapes(0, fait: 30, sur: 30)) - 1)
        // Le temps restant compte la fiche de chaque modification suivante.
        XCTAssertEqual(Generatif.tempsRestant(etape: 10, sur: 50, premiere: 0, secondesDepuisPremiere: 20, chargement: 30, suivantes: 1, fiche: 60) ?? 0,
                       270, accuracy: 1e-9)
    }

    /// Le gris de mflux (Fibo2EditImages.grey_out : binaire à 128, gris plat de 128) ; le modèle complet
    /// du cache ; la fiche lue et résumée.
    func testGriserLireEtResumerLaFiche() throws {
        let pixels: [UInt8] = [10, 20, 30, 255, 40, 50, 60, 255, 70, 80, 90, 255]
        XCTAssertEqual(Generatif.griser(pixels, masque: [0, 127, 128]), [10, 20, 30, 255, 40, 50, 60, 255, 128, 128, 128, 255])
        let cache = dossier.appendingPathComponent("cache")
        XCTAssertNil(Generatif.vlmLocal(cache: cache))
        Self.modeleVLM(dans: cache)
        XCTAssertNotNil(Generatif.vlmLocal(cache: cache))
        try FileManager.default.removeItem(at: cache.appendingPathComponent("models--briaai--FIBO-vlm/snapshots/\(Generatif.revisionVLM)/model-00002-of-00002.safetensors"))
        XCTAssertNil(Generatif.vlmLocal(cache: cache), "un fichier de poids manque")
        XCTAssertNil(Generatif.lireFiche(Data("[1, 2]".utf8), instruction: "x"))
        XCTAssertNil(Generatif.lireFiche(Data("{}".utf8), instruction: "x"))
        let fiche = try XCTUnwrap(Generatif.lireFiche(Data(#"{"short_description": "\#(String(repeating: "a", count: 500))", "edit_instruction": " "}"#.utf8), instruction: "add a hat"))
        XCTAssertEqual(fiche["edit_instruction"]?.string, "add a hat")
        let resume = Generatif.resumeFiche(fiche)
        XCTAssertEqual(resume["description"]?.string?.count, 300)
        XCTAssertTrue(resume["description"]?.string?.hasSuffix("…") == true)
        // Le réglage léger : une seule génération, cache de MLX borné, 8 bits, 1 536 jetons au plus.
        let script = Generatif.scriptFiche
        XCTAssertTrue(script.contains("vlm._generate_internal(") && script.contains("use_mask=args.use_mask"))
        XCTAssertFalse(script.contains("vlm.edit("), "ni FiboVLM.edit ni ses replis")
        XCTAssertFalse(script.contains("--image-originale"))
        XCTAssertTrue(script.contains("mx.set_cache_limit(CACHE_MLX)") && script.contains("CACHE_MLX = 4 * 1024 ** 3"))
        XCTAssertTrue(script.contains("QUANTIZE = 8") && script.contains("FiboVLM(quantize=QUANTIZE)"))
        XCTAssertTrue(script.contains("MAX_JETONS = 1536"))
        XCTAssertTrue(script.contains(#"VERSION_RELEVEE = "0.24.0""#) && script.contains(#"MARQUE_VERSION = "\#(Generatif.marqueVersionFiche)""#),
                      "le script écrit la marque que le connecteur lit")
        XCTAssertFalse(script.contains("/private/tmp") || script.contains("scratchpad"), "aucun chemin du dossier temporaire")
        XCTAssertEqual(Generatif.delaiFiche, 180); XCTAssertEqual(Generatif.dureeFicheEstimee, 45)
        XCTAssertTrue(Generatif.ficheRefusee("ValueError: The JSON caption does not have the format FIBO 2 reads:"))
        XCTAssertTrue(Generatif.ficheRefusee("mflux-generate-fibo2-edit: error: The prompt starts like a JSON caption but is not valid JSON: Expecting ',' at line 3, column 2."))
        XCTAssertTrue(Generatif.ficheRefusee(#"error: "edit_instruction" has to be a string, not a list."#))
        XCTAssertFalse(Generatif.ficheRefusee("RuntimeError: out of memory"))
        // La trace d'une autre erreur, qui montre une ligne de source avec edit_instruction : pas un refus.
        XCTAssertFalse(Generatif.ficheRefusee("""
        Traceback (most recent call last):
          File "/x/mflux/models/fibo2/model/fibo2_text_encoder/prompt_encoder.py", line 68, in edit_prompt
            edit["edit_instruction"] = instruction
          File "/x/mflux/models/fibo2/variants/fibo2_core.py", line 109, in generate_image
            negative_embeds = self._encode_prompt(negative_prompt or default)
        RuntimeError: [metal::malloc] Attempting to allocate 9663676416 bytes which is greater than the maximum allowed buffer size; structured_caption
        """))
        // La fiche passée telle quelle (l'ordre de ses clés gardé), l'instruction jointe à la fin s'il en manque.
        let ecrite = "{\n  \"short_description\": \"a hat\",\n  \"objects\": [],\n  \"edit_instruction\": \"Add a hat.\"\n}\n"
        XCTAssertEqual(Generatif.ficheAvecInstruction(ecrite, instruction: "x"), ecrite)
        let jointe = try XCTUnwrap(Generatif.ficheAvecInstruction(#"{"short_description": "a hat", "background_setting": "a park"}"#, instruction: "add a hat"))
        XCTAssertEqual(jointe, "{\"short_description\": \"a hat\", \"background_setting\": \"a park\",\n  \"edit_instruction\": \"add a hat\"\n}\n")
        XCTAssertEqual(try JSONCoding.parse(Data(jointe.utf8))["edit_instruction"]?.string, "add a hat")
        XCTAssertNil(Generatif.ficheAvecInstruction("[1]", instruction: "x"))
        XCTAssertNil(Generatif.ficheAvecInstruction("{}", instruction: "x"))
    }

    /// FIBO-vlm : mflux le charge à sa révision épinglée, hors ligne ; le cache se juge sur cet
    /// instantané, jamais sur refs/main, et le conseil de téléchargement la nomme.
    func testModeleVLMALaRevisionEpinglee() throws {
        let cache = dossier.appendingPathComponent("cache-revision")
        // refs/main sur une version plus récente, la révision épinglée absente : pas de modèle.
        Self.modeleVLM(dans: cache, revision: "f00dcafe")
        XCTAssertNil(Generatif.vlmLocal(cache: cache), "refs/main ne compte pas")
        // La révision épinglée présente, refs/main ailleurs : le modèle est là.
        Self.modeleVLM(dans: cache, main: "f00dcafe")
        XCTAssertEqual(Generatif.vlmLocal(cache: cache)?.lastPathComponent, Generatif.revisionVLM)
        XCTAssertEqual(Generatif.revisionVLM, "bd13da5e0b73c808014d6260963e311c8cdf0d8b", "ModelRevisions.PINNED de mflux 0.24")
        XCTAssertTrue(Generatif.conseilVLM.hasSuffix("--revision bd13da5e0b73c808014d6260963e311c8cdf0d8b"))
        // La réponse conseille ce téléchargement-là.
        tools.fibo?.cacheHF = dossier.appendingPathComponent("hf-vide")
        fauxVLM(avecModele: false)
        fauxMflux(sortie: sortiePreparee(carreRouge))
        let resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertTrue(try JSONCoding.parse(resultat.text)["remarque_fiche"]?.string?.contains("--revision \(Generatif.revisionVLM)") == true, resultat.text)
    }

    /// Le vrai script de fiche (Generatif.scriptFiche), lancé par un Python de Homebrew sur de faux
    /// paquets mlx et mflux (jamais le vrai FIBO-vlm) qui imitent ce qu'il touche de mflux 0.24 :
    /// `mx.set_cache_limit`, `FiboVLM(quantize:)`, `_generate_internal` (un jeton par caractère, tiré
    /// par `Qwen3VLUtil.sample_top_p`), `_normalize_edit_output` calqué sur celui de mflux 0.24 (le
    /// meilleur objet parmi plusieurs, les valeurs vides retirées, `aesthetics` complété, et qui lève
    /// sans edit_instruction), et la version du paquet ; à la sortie, il note si les deux attributs
    /// remplacés par le script sont revenus. Sauté sans Python 3 sur ce Mac.
    func testScriptDeFicheReglageLeger() throws {
        guard let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("pas de Python 3 (Homebrew) sur ce Mac")
        }
        let racinePaquet = dossier.appendingPathComponent("faux-mflux")
        for sous in ["mlx", "mflux", "mflux/models", "mflux/models/common_models", "mflux/models/common_models/qwen3_vl",
                     "mflux/models/fibo_vlm", "mflux/models/fibo_vlm/model"] {
            try FileManager.default.createDirectory(at: racinePaquet.appendingPathComponent(sous), withIntermediateDirectories: true)
            try "".write(to: racinePaquet.appendingPathComponent(sous + "/__init__.py"), atomically: true, encoding: .utf8)
        }
        try """
        import os

        def set_cache_limit(n):
            with open(os.environ["FAUX_VLM_JOURNAL"], "a") as f:
                f.write(f"cache {n}\\n")
            return 0
        """.write(to: racinePaquet.appendingPathComponent("mlx/core.py"), atomically: true, encoding: .utf8)
        try """
        class Jeton:
            def __init__(self, n):
                self.n = n

            def item(self):
                return self.n


        class Qwen3VLUtil:
            @staticmethod
            def sample_top_p(logits, top_p, temperature=1.0):
                return Jeton(logits)  # le « logit » du faux modèle est déjà le jeton
        """.write(to: racinePaquet.appendingPathComponent("mflux/models/common_models/qwen3_vl/qwen3_vl_util.py"), atomically: true, encoding: .utf8)
        try """
        import atexit
        import json
        import os
        from mflux.models.common_models.qwen3_vl.qwen3_vl_util import Qwen3VLUtil


        def journal(ligne):
            with open(os.environ["FAUX_VLM_JOURNAL"], "a") as f:
                f.write(ligne + "\\n")


        class Tokenizer:
            def decode(self, jetons, skip_special_tokens=True):
                return "".join(chr(j) for j in jetons)


        class Processor:
            tokenizer = Tokenizer()


        class FiboVLM:
            def __init__(self, quantize=None):
                journal(f"quantize {quantize}")
                self.processor = Processor()

            def edit(self, *args, **kwargs):
                raise AssertionError("FiboVLM.edit ne sert plus")

            def _generate_internal(self, task, *, image=None, editing_instructions=None, top_p=0.9, temperature=0.2,
                                   max_tokens=4096, stop=None, seed=None, use_mask=False, **autres):
                journal(f"generer {task}|{image}|{editing_instructions}|{max_tokens}|{seed}|{use_mask}")
                with open(os.environ["FAUX_VLM_TEXTE"], encoding="utf-8") as f:
                    texte = f.read()
                if texte == "LEVER":
                    raise ValueError("forme incompatible (MLX)")  # avant toute normalisation
                jetons = [int(Qwen3VLUtil.sample_top_p(ord(c), top_p, temperature).item()) for c in texte[:max_tokens]]
                journal(f"tires {len(jetons)}")
                return FiboVLM._normalize_edit_output(self.processor.tokenizer.decode(jetons))

            # Calqués sur mflux 0.24 (fibo_vlm.py) : le meilleur objet JSON complet du texte, les valeurs
            # vides retirées, aesthetics complété, edit_instruction exigée (ou celle de repli).
            @staticmethod
            def _normalize_edit_output(text, fallback_edit_instruction=None):
                payload = FiboVLM._extract_single_json_object(text)
                aesthetics = payload.setdefault("aesthetics", {})
                if not isinstance(aesthetics, dict):
                    raise ValueError("VLM edit output must contain an object at `aesthetics`.")
                aesthetics.setdefault("preference_score", "very high")
                aesthetics.setdefault("aesthetic_score", "very high")
                payload = FiboVLM._remove_empty_values(payload)
                consigne = payload.get("edit_instruction")
                if not isinstance(consigne, str) or not consigne.strip():
                    repli = (fallback_edit_instruction or "").strip()
                    if not repli:
                        raise ValueError("VLM edit output must include a non-empty `edit_instruction`.")
                    payload["edit_instruction"] = repli[0].upper() + repli[1:]
                return "\\n" + json.dumps(payload, indent=2, ensure_ascii=False) + "\\n"

            @staticmethod
            def _extract_single_json_object(text):
                candidat = text.strip()
                try:
                    lu = json.loads(candidat)
                except json.JSONDecodeError:
                    lu = None
                if isinstance(lu, dict):
                    return lu
                objets, debut, profondeur, chaine, echappe = [], None, 0, False, False
                for i, c in enumerate(candidat):
                    if chaine:
                        if echappe:
                            echappe = False
                        elif c == "\\\\":
                            echappe = True
                        elif c == '"':
                            chaine = False
                        continue
                    if c == '"':
                        chaine = True
                    elif c == "{":
                        if profondeur == 0:
                            debut = i
                        profondeur += 1
                    elif c == "}" and profondeur > 0:
                        profondeur -= 1
                        if profondeur == 0 and debut is not None:
                            try:
                                lu = json.loads(candidat[debut:i + 1])
                            except json.JSONDecodeError:
                                lu = None
                            if isinstance(lu, dict):
                                objets.append(lu)
                            debut = None
                if not objets:
                    raise ValueError("VLM edit output must contain exactly one JSON object.")
                return max(objets, key=FiboVLM._score)

            @staticmethod
            def _score(c):
                score = 10 if isinstance(c.get("edit_instruction"), str) and c["edit_instruction"].strip() else 0
                score += 3 if isinstance(c.get("short_description"), str) and c["short_description"].strip() else 0
                score += 2 if isinstance(c.get("objects"), list) else 0
                score += 2 if isinstance(c.get("lighting"), dict) else 0
                score += 3 if isinstance(c.get("aesthetics"), dict) else 0
                return score, len(json.dumps(c, ensure_ascii=False))

            @staticmethod
            def _remove_empty_values(v):
                vides = (None, "", {}, [])
                if isinstance(v, dict):
                    net = {k: FiboVLM._remove_empty_values(x) for k, x in v.items() if x not in vides}
                    return {k: x for k, x in net.items() if x not in vides}
                if isinstance(v, list):
                    return [x for x in (FiboVLM._remove_empty_values(y) for y in v) if x not in vides]
                return v


        # À la sortie du script : les attributs qu'il remplace pendant la génération sont-ils revenus ?
        ORIGINAUX = (FiboVLM.__dict__["_normalize_edit_output"].__func__, Qwen3VLUtil.__dict__["sample_top_p"].__func__)


        def remis():
            actuels = (FiboVLM.__dict__["_normalize_edit_output"].__func__, Qwen3VLUtil.__dict__["sample_top_p"].__func__)
            journal(f"remis {actuels == ORIGINAUX}")


        atexit.register(remis)
        """.write(to: racinePaquet.appendingPathComponent("mflux/models/fibo_vlm/model/fibo_vlm.py"), atomically: true, encoding: .utf8)
        try """
        class FiboVLMUtil:
            @staticmethod
            def load_image(path):
                return str(path)
        """.write(to: racinePaquet.appendingPathComponent("mflux/models/fibo_vlm/model/util.py"), atomically: true, encoding: .utf8)
        func version(_ v: String?) throws {
            for ancienne in (try? FileManager.default.contentsOfDirectory(atPath: racinePaquet.path)) ?? [] where ancienne.hasSuffix(".dist-info") {
                try FileManager.default.removeItem(at: racinePaquet.appendingPathComponent(ancienne))
            }
            guard let v else { return }
            let info = racinePaquet.appendingPathComponent("mflux-\(v).dist-info")
            try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
            try "Metadata-Version: 2.1\nName: mflux\nVersion: \(v)\n".write(to: info.appendingPathComponent("METADATA"), atomically: true, encoding: .utf8)
        }
        let script = dossier.appendingPathComponent("fiche-fibo-vlm.py")
        try Generatif.scriptFiche.write(to: script, atomically: true, encoding: .utf8)
        let journal = dossier.appendingPathComponent("faux-vlm.log"), modele = dossier.appendingPathComponent("faux-vlm.txt")
        let image = dossier.appendingPathComponent("grisee.png"), sortie = dossier.appendingPathComponent("fiche.json")
        /// Le script sur le texte que le faux FIBO-vlm écrira ; sans -I (les faux paquets passent par
        /// PYTHONPATH), les mêmes arguments que le connecteur sinon.
        func lancer(texte: String, masque: Bool) throws -> (code: Int32, sortie: String, journal: [String]) {
            try? FileManager.default.removeItem(at: journal); try? FileManager.default.removeItem(at: sortie)
            try texte.write(to: modele, atomically: true, encoding: .utf8)
            let processus = Process()
            processus.executableURL = URL(fileURLWithPath: python)
            let arguments = Generatif.argumentsFiche(script: script, image: image, instruction: "add a red hat", sortie: sortie, graine: 7, masque: masque)
            XCTAssertEqual(arguments.first, "-I")
            processus.arguments = Array(arguments.dropFirst())
            var environnement = ProcessInfo.processInfo.environment
            environnement["PYTHONPATH"] = racinePaquet.path
            environnement["FAUX_VLM_JOURNAL"] = journal.path
            environnement["FAUX_VLM_TEXTE"] = modele.path
            processus.environment = environnement
            let tuyau = Pipe()
            processus.standardOutput = tuyau; processus.standardError = tuyau
            try processus.run()
            let donnees = tuyau.fileHandleForReading.readDataToEndOfFile()
            processus.waitUntilExit()
            let lignes = ((try? String(contentsOf: journal, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            return (processus.terminationStatus, String(decoding: donnees, as: UTF8.self), lignes)
        }
        func jetonsTires(_ texte: String) -> Int? {
            guard let r = texte.range(of: #"\((\d+) jetons\)"#, options: .regularExpression) else { return nil }
            return Int(texte[r].dropFirst().prefix { $0.isNumber })
        }
        func cles(_ fiche: String) throws -> [String] {
            try ["short_description", "objects", "background_setting", "artistic_style", "aesthetics", "text_render", "context", "edit_instruction"]
                .filter { fiche.contains("\"\($0)\"") }
                .sorted { try XCTUnwrap(fiche.range(of: "\"\($0)\"")).lowerBound < XCTUnwrap(fiche.range(of: "\"\($1)\"")).lowerBound }
        }
        func lireFiche() throws -> JSONValue { try JSONCoding.parse(Data(contentsOf: sortie)) }
        let boucleApres = String(repeating: #","context":"a park again""#, count: 300)

        // Mode masqué : FIBO-vlm n'écrit pas edit_instruction et boucle après text_render. Le script
        // s'arrête dès que text_render est fermé, ferme l'objet et pose edit_instruction lui-même.
        try version("0.24.0")
        let debut = #"{"short_description":"a hat on a woman","objects":[{"description":"a woman"}],"background_setting":"a park","text_render":[{"text":"PARK","location":"a sign"}]"#
        let boucle = debut + boucleApres
        XCTAssertGreaterThan(boucle.count, 1536, "sans l'arrêt, la borne de jetons couperait au milieu d'une clé")
        var resultat = try lancer(texte: boucle, masque: true)
        XCTAssertEqual(resultat.code, 0, resultat.sortie)
        XCTAssertFalse(resultat.sortie.contains(Generatif.marqueVersionFiche), "mflux 0.24.0 : rien à dire")
        XCTAssertEqual(Array(resultat.journal.prefix(3)), ["cache \(4 * 1024 * 1024 * 1024)", "quantize 8", "generer edit|\(image.path)|add a red hat|1536|7|True"],
                       "cache de MLX borné avant le chargement, 8 bits, une seule génération de 1 536 jetons au plus")
        XCTAssertFalse(resultat.journal.contains { $0.hasPrefix("tires ") }, "arrêtée avant sa fin : \(resultat.journal)")
        XCTAssertEqual(resultat.journal.last, "remis True", "sample_top_p et _normalize_edit_output remis après la génération")
        let tires = try XCTUnwrap(jetonsTires(resultat.sortie), resultat.sortie)
        XCTAssertGreaterThanOrEqual(tires, debut.count); XCTAssertLessThan(tires, debut.count + 4, "relu tous les 4 jetons")
        var fiche = try String(contentsOf: sortie, encoding: .utf8)
        var lue = try JSONCoding.parse(Data(fiche.utf8))
        XCTAssertEqual(lue["edit_instruction"]?.string, "Fill the masked area: add a red hat")
        XCTAssertNil(lue["context"], "rien de la boucle")
        XCTAssertEqual(lue["text_render"]?.array?.first?["text"]?.string, "PARK")
        XCTAssertEqual(try cles(fiche), ["short_description", "objects", "background_setting", "text_render", "aesthetics", "edit_instruction"],
                       "l'ordre de FIBO-vlm, puis ce que la normalisation de mflux ajoute : \(fiche)")

        // Mode masqué, des crochets dans un texte à rendre : la fin de text_render se cherche hors des
        // chaînes (ni boucle jusqu'à la borne, ni coupe au milieu d'un texte).
        for texte in ["OPEN [24h]", "Sale]", "[SALE", #"a \"quoted\" [x]"#] {
            let avecCrochets = #"{"short_description":"a shop","objects":[{"description":"a sign"}],"text_render":[{"text":"\#(texte)","location":"[left]"}]"#
            resultat = try lancer(texte: avecCrochets + boucleApres, masque: true)
            XCTAssertEqual(resultat.code, 0, "\(texte) : \(resultat.sortie)")
            XCTAssertFalse(resultat.journal.contains { $0.hasPrefix("tires ") }, "\(texte) : arrêtée avant la borne")
            XCTAssertLessThan(try XCTUnwrap(jetonsTires(resultat.sortie)), avecCrochets.count + 4, texte)
            lue = try lireFiche()
            XCTAssertEqual(lue["text_render"]?.array?.first?["text"]?.string, texte.replacingOccurrences(of: #"\""#, with: "\""))
            XCTAssertEqual(lue["text_render"]?.array?.first?["location"]?.string, "[left]")
            XCTAssertNil(lue["context"], texte)
        }

        // Mode masqué, la génération finit juste après text_render, sans fermer l'objet, à chacun des
        // quatre alignements de la relecture : le texte final se coupe et se ferme de même.
        for remplissage in 0..<4 {
            let fini = #"{"short_description":"a hat\#(String(repeating: " ", count: remplissage))","text_render":[{"text":"HI"}]"#
            resultat = try lancer(texte: fini, masque: true)
            XCTAssertEqual(resultat.code, 0, "remplissage \(remplissage) : \(resultat.sortie)")
            lue = try lireFiche()
            XCTAssertEqual(lue["edit_instruction"]?.string, "Fill the masked area: add a red hat", "remplissage \(remplissage)")
            XCTAssertEqual(lue["text_render"]?.array?.first?["text"]?.string, "HI")
        }

        // Mode masqué, une accolade fermée trop tôt, puis la boucle après text_render : arrêt et réparation
        // ensemble ; les clés d'après l'accolade gardées.
        let tropTotMasque = #"{"short_description":"a hat","aesthetics":{"composition":"centered"}},"background_setting":"a park","text_render":[{"text":"HI"}]"#
        resultat = try lancer(texte: tropTotMasque + boucleApres, masque: true)
        XCTAssertEqual(resultat.code, 0, resultat.sortie)
        lue = try lireFiche()
        XCTAssertEqual(lue["background_setting"]?.string, "a park", "réparée : \(resultat.sortie)")
        XCTAssertEqual(lue["aesthetics"]?["composition"]?.string, "centered")
        XCTAssertEqual(lue["edit_instruction"]?.string, "Fill the masked area: add a red hat")
        XCTAssertNil(lue["context"])

        // Sans zone : la génération va à son terme (edit_instruction vient après text_render), et une
        // accolade fermée trop tôt se répare ; edit_instruction de FIBO-vlm gardée. Une autre version
        // de mflux est dite sur la sortie.
        try version("0.25.0")
        let tropTot = #"{"short_description":"a hat","objects":[{"description":"a woman"}],"artistic_style":"photo"},"text_render":[{"text":"HI"}],"edit_instruction":"Add a red hat to the woman."}"#
        resultat = try lancer(texte: tropTot, masque: false)
        XCTAssertEqual(resultat.code, 0, resultat.sortie)
        XCTAssertTrue(resultat.sortie.contains("\(Generatif.marqueVersionFiche) 0.25.0 (script réglé sur 0.24.0)"), resultat.sortie)
        XCTAssertTrue(resultat.journal.contains("generer edit|\(image.path)|add a red hat|1536|7|False"), "\(resultat.journal)")
        XCTAssertTrue(resultat.journal.contains("tires \(tropTot.count)"), "pas d'arrêt sans zone : \(resultat.journal)")
        XCTAssertEqual(resultat.journal.last, "remis True")
        fiche = try String(contentsOf: sortie, encoding: .utf8)
        lue = try JSONCoding.parse(Data(fiche.utf8))
        XCTAssertEqual(lue["edit_instruction"]?.string, "Add a red hat to the woman.")
        XCTAssertEqual(lue["artistic_style"]?.string, "photo")
        XCTAssertEqual(try cles(fiche), ["short_description", "objects", "artistic_style", "text_render", "edit_instruction", "aesthetics"], fiche)

        // Sans zone, un blanc entre l'accolade de trop et la virgule : réparée aussi (les clés d'après
        // gardées, edit_instruction de FIBO-vlm comprise).
        resultat = try lancer(texte: #"{"short_description":"a","aesthetics":{"x":"y"}} ,"edit_instruction":"Add a hat."}"#, masque: false)
        XCTAssertEqual(resultat.code, 0, resultat.sortie)
        XCTAssertEqual(try lireFiche()["edit_instruction"]?.string, "Add a hat.")
        resultat = try lancer(texte: "{\"short_description\":\"a\",\"aesthetics\":{\"x\":\"y\"}}\n  ,\n \"edit_instruction\":\"Add a hat.\"}", masque: false)
        XCTAssertEqual(try lireFiche()["edit_instruction"]?.string, "Add a hat.", resultat.sortie)

        // Sans zone, une fiche complète suivie d'un second objet commencé : rien n'est « réparé » (la
        // suite ne reprend pas par une clé) ; la normalisation de mflux garde la fiche complète.
        let deuxObjets = #"{"short_description":"a","objects":[{"description":"x"}],"edit_instruction":"Add a hat."},{"short_description":"b","objects":[{"d"#
        resultat = try lancer(texte: deuxObjets, masque: false)
        XCTAssertEqual(resultat.code, 0, resultat.sortie)
        lue = try lireFiche()
        XCTAssertEqual(lue["edit_instruction"]?.string, "Add a hat.")
        XCTAssertEqual(lue["short_description"]?.string, "a")

        // Une réparation qui ne mène pas à un texte lisible : le texte d'origine, dont la normalisation
        // choisit l'objet complet (ici le premier, fermé trop tôt), sans lever.
        resultat = try lancer(texte: #"{"short_description":"a","objects":[{"description":"x"}]},"edit_instruction":"Add a hat.","context":"#, masque: false)
        XCTAssertEqual(resultat.code, 0, resultat.sortie)
        lue = try lireFiche()
        XCTAssertEqual(lue["short_description"]?.string, "a")
        XCTAssertEqual(lue["edit_instruction"]?.string, "Add a red hat", "l'instruction donnée, la suite étant illisible")

        // Sans zone, sans edit_instruction : l'instruction donnée, sans « Fill the masked area ».
        resultat = try lancer(texte: #"{"short_description":"a hat","text_render":[]}"#, masque: false)
        XCTAssertEqual(resultat.code, 0, resultat.sortie)
        XCTAssertEqual(try lireFiche()["edit_instruction"]?.string, "Add a red hat")

        // Une erreur levée avant toute normalisation (MLX) : dite telle quelle, code 1, pas de fiche.
        resultat = try lancer(texte: "LEVER", masque: true)
        XCTAssertEqual(resultat.code, 1, resultat.sortie)
        XCTAssertTrue(resultat.sortie.contains("erreur FIBO-vlm : forme incompatible (MLX)"), resultat.sortie)
        XCTAssertFalse(resultat.sortie.contains("aucune réponse"), resultat.sortie)
        XCTAssertEqual(resultat.journal.last, "remis True")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sortie.path))

        // Une sortie illisible : code 1 et un message lisible, sans fiche ; une version introuvable est dite.
        try version(nil)
        resultat = try lancer(texte: "pas du JSON", masque: false)
        XCTAssertEqual(resultat.code, 1, resultat.sortie)
        XCTAssertTrue(resultat.sortie.contains("erreur FIBO-vlm : fiche illisible"), resultat.sortie)
        XCTAssertTrue(resultat.sortie.contains("\(Generatif.marqueVersionFiche) inconnue"), resultat.sortie)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sortie.path))
        XCTAssertEqual(Generatif.expliquerFiche(journal: resultat.sortie, code: 1).prefix(15), "erreur FIBO-vlm")
    }

    /// Une autre version de mflux que celle du réglage du script : la fiche sert, et la réponse le dit.
    func testVersionDeMfluxDiteDansLaReponse() throws {
        fauxVLM(fin: """
        echo "\(Generatif.marqueVersionFiche) 0.25.0 (script réglé sur \(Generatif.versionMfluxFiche))"
        cp "\(gardes.path)/fiche-modele.json" "$out"
        """)
        let region = CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4)
        fauxMflux(sortie: sortiePreparee(region: region) { fx, fy, p, i in if fx > 0.35, fx < 0.55, fy > 0.35, fy < 0.65 { Self.rouge(&p, i) } })
        var resultat = editer(["structured_prompt": true, "instruction": "replace the trousers with a skirt", "region": ["x": 0.3, "y": 0.3, "width": 0.3, "height": 0.4]])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertNotNil(valeur("--prompt-file"), "la fiche sert")
        var modification = try XCTUnwrap(JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        XCTAssertNotNil(modification["fiche"])
        let remarque = try XCTUnwrap(modification["remarque_fiche"]?.string, resultat.text)
        XCTAssertEqual(remarque, "mflux installé : 0.25.0 ; le script de la fiche est réglé sur 0.24.0 : à revérifier.",
                       "la version lue seule, sans la ligne du script recopiée ni FIBO-vlm nommé")
        XCTAssertEqual(Generatif.versionDite("\(Generatif.marqueVersionFiche) inconnue (script réglé sur 0.24.0)"), "inconnue")
        XCTAssertNil(Generatif.versionDite("fiche écrite : x (12 jetons)"))

        // Avec un échec : les deux dans la même remarque.
        fauxVLM(fin: """
        echo "\(Generatif.marqueVersionFiche) 0.25.0 (script réglé sur \(Generatif.versionMfluxFiche))"
        echo "erreur FIBO-vlm : boom"
        exit 1
        """)
        fauxMflux(sortie: sortiePreparee(carreRouge))
        resultat = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(valeur("--prompt"), "add a red scarf")
        modification = try XCTUnwrap(JSONCoding.parse(resultat.text)["modifications"]?.array?.first)
        let echec = try XCTUnwrap(modification["remarque_fiche"]?.string, resultat.text)
        XCTAssertTrue(echec.contains("boom") && echec.contains("phrase seule") && echec.contains("0.25.0"), echec)
    }

    /// Un calcul lancé ailleurs pendant l'appel (Fibo 2 Studio, après la fiche) : l'appel s'arrête avant
    /// le lancement suivant ; jamais deux calculs ensemble, rien d'importé.
    func testAutreCalculVuAvantChaqueLancement() throws {
        fauxVLM()
        fauxMflux(sortie: sortiePreparee(carreRouge))
        // Vrai dès que la fiche est finie (le faux VLM touche vlm-fin à sa fin).
        let fin = gardes.appendingPathComponent("vlm-fin")
        tools.fibo?.autreCalcul = { FileManager.default.fileExists(atPath: fin.path) }
        let refus = editer(["structured_prompt": true, "instruction": "add a red scarf"])
        XCTAssertTrue(refus.isError && refus.text.contains("lancé pendant cet appel") && refus.text.contains("avant Fibo 2"), refus.text)
        XCTAssertEqual(appelsDuVLM, 1)
        XCTAssertEqual(appelsDeMflux, 0, "mflux jamais lancé")
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
        XCTAssertEqual(dossiersTemporairesRestants, [])

        // Avant SeedVR2 : vrai dès que mflux a écrit sa sortie.
        try? FileManager.default.removeItem(at: fin)
        fauxSeedVR()
        ecrireSource(largeur: 1600, hauteur: 1200)
        let region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        fauxMflux(sortie: sortiePreparee(region: region, carreRouge))
        let compte = gardes.appendingPathComponent("compte")
        tools.fibo?.autreCalcul = { FileManager.default.fileExists(atPath: compte.path) }
        let refusSeedVR = editer(["instruction": "add a red square", "structured_prompt": false,
                                  "region": ["x": 0.25, "y": 0.25, "width": 0.5, "height": 0.5]])
        XCTAssertTrue(refusSeedVR.isError && refusSeedVR.text.contains("avant SeedVR2"), refusSeedVR.text)
        XCTAssertNil(argumentsSeedVR, "SeedVR2 jamais lancé")
        XCTAssertFalse(fake.commands.contains("importerGeneree"))
    }

    /// Un masque que l'utilisateur a peint (mask.existing) : cherché par son nom avant l'exportation
    /// (casse indifférente), repris dans le témoin par son nom exact ; absent ou en double : refusé avec
    /// les noms, rien d'exporté ; existing seul dans mask.
    func testMasquePeintDansLightroom() throws {
        fake.replies["masques"] = ["masques": [["numero": 1, "nom": "Ciel"], ["numero": 2, "nom": "Fibo"]]]
        masqueRendu = { Self.dansLaPersonne($0, $1) }
        fauxMflux(sortie: sortiePreparee(region: CGRect(x: 0, y: 0, width: 1, height: 1)) { _, _, p, i in Self.bleu(&p, i) })
        let resultat = editer(["instruction": "replace the jacket with a red raincoat", "mask": ["existing": "  fibo "], "label": "imperméable"])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(fake.commands, ["etat", "masques", "exporter", "essayer", "essayer", "importerGeneree"],
                       "le masque cherché avant l'exportation, en lecture seule")
        XCTAssertEqual(fake.calls.first { $0.command == "masques" }?.params["photo"]?.int, 7)
        XCTAssertNil(fake.calls.first { $0.command == "masques" }?.params["action"], "lister, rien d'autre")
        for essai in fake.calls.filter({ $0.command == "essayer" }).map(\.params) {
            let temoin = try XCTUnwrap(essai["masques"]?.array?.first)
            XCTAssertEqual(temoin["type"]?.string, "existant")
            XCTAssertEqual(temoin["masque"]?.string, "Fibo", "le nom exact")
            XCTAssertEqual(temoin["nom"]?.string, "Claude · masque pour Fibo 2")
            XCTAssertEqual(essai["temoin"]?.bool, true)
        }
        let bloc = try XCTUnwrap(JSONCoding.parse(resultat.text)["masque"])
        XCTAssertEqual(bloc["kind"]?.string, "existing")
        XCTAssertEqual(bloc["nom"]?.string, "Fibo")
        XCTAssertEqual(bloc["calcule_par"]?.string, "l'utilisateur, dans Lightroom")
        XCTAssertTrue(bloc["lecture"]?.string?.contains("ni changé ni retiré") == true, resultat.text)
        // Le TIFF : la zone peinte repeinte, le reste au bit près.
        let avant = try XCTUnwrap(Self.pixels16(source)), apres = try XCTUnwrap(Self.pixels16(importe))
        XCTAssertEqual(Self.pixel(apres, 30, 30), Self.pixel(avant, 30, 30))
        XCTAssertGreaterThan(Self.pixel(apres, largeur / 2, hauteur / 2)[2], 40_000)

        // Absent : refusé avec les noms, avant l'exportation.
        fake.calls.removeAll()
        let absent = editer(["instruction": "x", "mask": ["existing": "Peinture"]])
        XCTAssertTrue(absent.isError && absent.text.contains("Aucun masque « Peinture »") && absent.text.contains("« Ciel », « Fibo »"), absent.text)
        XCTAssertEqual(fake.commands, ["etat", "masques"])
        // Deux masques du même nom.
        fake.replies["masques"] = ["masques": [["nom": "Fibo"], ["nom": "FIBO"]]]
        fake.calls.removeAll()
        let double = editer(["instruction": "x", "mask": ["existing": "Fibo"]])
        XCTAssertTrue(double.isError && double.text.contains("2 masques s'appellent « Fibo »"), double.text)
        XCTAssertFalse(fake.commands.contains("exporter"))
        // Aucun masque sur la photo.
        fake.replies["masques"] = ["masques": []]
        XCTAssertTrue(editer(["instruction": "x", "mask": ["existing": "Fibo"]]).text.contains("elle n'a aucun masque"))
        // existing seul ; un nom vide.
        fake.calls.removeAll()
        let avecKind = editer(["instruction": "x", "mask": ["existing": "Fibo", "kind": "background"]])
        XCTAssertTrue(avecKind.isError && avecKind.text.contains("sans kind"), avecKind.text)
        XCTAssertTrue(editer(["instruction": "x", "mask": ["existing": "Fibo", "invert": true]]).text.contains("sans invert"))
        XCTAssertTrue(editer(["instruction": "x", "mask": ["existing": " "]]).text.contains("le nom exact"))
        XCTAssertTrue(fake.commands.isEmpty, "refusés avant tout envoi : \(fake.commands)")
        XCTAssertEqual(try ToolHandler.masqueExistant("ciel", parmi: [["nom": "Ciel"]]), "Ciel")
    }

    /// Un masque peint vidé (ses traits effacés) : refusé avant l'exportation et l'accord, d'après les
    /// composants que la commande masques liste ; un masque peint presque vide ou total : refusé avec un
    /// texte pour un masque peint (le repeindre, region), jamais celui d'un masque calculé (kind, add_mask).
    func testMasquePeintVideOuPresqueVide() throws {
        fake.replies["masques"] = ["masques": [["numero": 1, "nom": "Ciel", "composants": [["type": "Image"]]],
                                               ["numero": 2, "nom": "Fibo", "composants": []]]]
        fake.replies["etat"] = ["mode": "proposer d'abord", "pause": false, "photo_active": ["id": 7]]
        fauxMflux()
        let vide = editer(["instruction": "x", "mask": ["existing": "fibo"], "confirm": true])
        XCTAssertTrue(vide.isError && vide.text.contains("Le masque « Fibo » n'a aucun composant") && vide.text.contains("Rien n'a été fait"), vide.text)
        XCTAssertEqual(fake.commands, ["etat", "masques"], "ni exportation, ni accord demandé")
        XCTAssertEqual(appelsDeMflux, 0)

        // Peint, mais presque rien : le texte d'un masque peint.
        fake.replies["etat"] = ["mode": "appliquer directement", "pause": false, "photo_active": ["id": 7]]
        fake.replies["masques"] = ["masques": [["numero": 1, "nom": "Fibo", "composants": [["type": "Paint"]]]]]
        masqueRendu = { fx, fy in fx < 0.004 && fy < 0.004 }
        let petit = editer(["instruction": "x", "mask": ["existing": "Fibo"]])
        XCTAssertTrue(petit.isError && petit.text.contains("Le masque « Fibo » peint dans Lightroom ne couvre presque rien"), petit.text)
        XCTAssertTrue(petit.text.contains("le repeindre plus large") && petit.text.contains("region"), petit.text)
        XCTAssertFalse(petit.text.contains("add_mask") || petit.text.contains("kind"), petit.text)
        XCTAssertEqual(appelsDeMflux, 0)
        // Peint sur toute la photo (inversé ?).
        masqueRendu = { _, _ in true }
        let total = editer(["instruction": "x", "mask": ["existing": "Fibo"]])
        XCTAssertTrue(total.isError && total.text.contains("peint dans Lightroom couvre toute la photo") && total.text.contains("inversé dans le panneau Masquage"), total.text)
        XCTAssertFalse(total.text.contains("Lightroom n'a trouvé aucun sujet"), total.text)
        // Un masque calculé garde son texte.
        XCTAssertTrue(Generatif.refusMasque(part: 0.00005)?.contains("add_mask") == true)
        XCTAssertNil(Generatif.refusMasque(part: 0.5, peint: "Fibo"))
    }

    /// Les pixels d'un PNG (canal rouge), pour lire le masque.
    static func pixels8(_ url: URL) -> (largeur: Int, hauteur: Int, valeur: (Int, Int) -> UInt8)? {
        guard let (image, _) = Generatif.lireImage(url), let pixels = Generatif.pixelsRGBA8(image, largeur: image.width, hauteur: image.height) else { return nil }
        let l = image.width
        return (l, image.height, { x, y in pixels[(y * l + x) * 4] })
    }
}
