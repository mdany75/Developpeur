import CoreGraphics
import Foundation
import ImageIO

/// La retouche générative par Fibo 2 (`generative_edit`, demandée par Dany le 29 octobre 2026) :
/// ce que Lightroom ne sait pas faire (changer un vêtement, ajouter ou retirer un objet) se fait
/// sur ce Mac par mflux (`mflux-generate-fibo2-edit`), seulement sur demande de l'utilisateur.
/// Ici, les calculs purs : taille de l'entrée de Fibo, arguments de mflux, lecture de sa
/// progression, explication de ses erreurs, masque de la zone, zone changée et recomposition en
/// pleine résolution (hors de la zone changée, les pixels de la photo restent ceux du TIFF
/// exporté). Le déroulé (exportation, mflux, importation) est dans Tools+Generatif.swift.
public enum Generatif {
    /// L'exécutable de mflux pour Fibo 2 en édition (référence : Fibo2Studio, Generator.swift).
    static let nomExecutable = "mflux-generate-fibo2-edit"
    static let depotNormal = "briaai/Fibo-2.0-dev"
    static let depotRapide = "briaai/Fibo-2.0-edit-turbo"
    /// Étapes du modèle : 50 en qualité normale, 4 pour Turbo (qui n'en prend pas d'autre).
    static let etapesNormal = 50
    static let etapesRapide = 4
    /// Délai maximal d'une génération (un premier téléchargement du modèle compris).
    public static let delaiMax: TimeInterval = 900
    /// Au-delà de cette part de l'image changée, toute la sortie de Fibo est prise.
    static let partSortieEntiere = 0.6
    /// En deçà, Fibo n'a rien changé de visible : rien n'est importé.
    static let partMinimale = 0.0005
    /// Écart (sur 1, le plus grand des trois canaux, après un léger flou de 3 × 3 pixels) au-delà
    /// duquel un pixel a changé : le décodage du modèle déplace un peu tous les pixels, sans dépasser
    /// ce seuil sur une image lisse ; provisoire, à relever sur de vraies sorties de Fibo 2. Le flou
    /// reste de 3 × 3 à toute taille : plus large (5 × 5 à 1 Mpx, d'abord), il effaçait un trait d'un
    /// pixel (un fil électrique retiré, d'écart 0,5) avant le seuil.
    static let seuilEcart: Float = 0.10
    /// Marge autour de la zone donnée (part du petit côté) : le masque de Fibo déborde un peu, pour
    /// que l'objet changé ne soit pas coupé net au bord de la zone.
    static let margeRegion = 0.03
    /// Élargissement de la zone changée (part du petit côté), puis fondu (deux flous de ce rayon).
    static let elargissement = 0.02
    static let fondu = 0.005

    public enum Qualite: String {
        case normal, fast
        var etapes: Int { self == .normal ? Generatif.etapesNormal : Generatif.etapesRapide }
        var texte: String { self == .normal ? "normale (\(etapes) étapes)" : "rapide (Turbo, \(etapes) étapes)" }
    }

    // MARK: Arguments

    /// La zone (`region`) : x, y, width, height de 0 à 1 dans l'image que montre view_photo.
    static func region(_ objet: [String: JSONValue]?) throws -> CGRect? {
        guard let objet else { return nil }
        let cles = ["x", "y", "width", "height"]
        let valeurs = cles.map { objet[$0]?.double }
        let inconnues = objet.keys.filter { !cles.contains($0) }.sorted()
        guard inconnues.isEmpty else { throw LightroomError.invalid("« region » : x, y, width, height seulement (pas \(inconnues.joined(separator: ", "))).") }
        guard let x = valeurs[0], let y = valeurs[1], let l = valeurs[2], let h = valeurs[3] else {
            throw LightroomError.invalid("« region » : x, y, width et height, de 0 à 1 dans l'image que montre view_photo.")
        }
        guard x >= 0, y >= 0, l > 0, h > 0, x + l <= 1.0001, y + h <= 1.0001 else {
            throw LightroomError.invalid("« region » : une zone dans l'image (x, y ≥ 0 ; width, height > 0 ; x + width et y + height ≤ 1).")
        }
        return CGRect(x: x, y: y, width: min(l, 1 - x), height: min(h, 1 - y))
    }

    /// Environ un mégapixel, mêmes proportions, côtés multiples de 16 (exigés par le modèle).
    static func tailleCible(largeur: Int, hauteur: Int) -> (largeur: Int, hauteur: Int) {
        // Borne large : au-delà, mflux recadrerait la photo au centre.
        let rapport = max(0.125, min(8, Double(largeur) / Double(max(hauteur, 1))))
        let aire = 1024.0 * 1024.0
        let l = (aire * rapport).squareRoot()
        let h = l / rapport
        func multiple16(_ v: Double) -> Int { max(256, Int((v / 16).rounded()) * 16) }
        return (multiple16(l), multiple16(h))
    }

    /// Les arguments de mflux, en tableau (aucun shell). Avec `contexte` (mode full_and_crop), deux
    /// images : <image_1> la photo entière, pour le contexte, <image_2> le recadrage à modifier ; la
    /// consigne est enveloppée (`consigneDeuxImages`) et sans masque (mflux ne le permet qu'avec une
    /// seule image). Qualité normale : décodage en pleine précision (--vae-full-precision) ; jamais
    /// --quantize ni --step-cache-ratio, qui dégradent l'image.
    static func arguments(entree: URL, masque: URL?, instruction: String, taille: (largeur: Int, hauteur: Int),
                          qualite: Qualite, graine: Int, sortie: URL, modeleRapide: URL?, contexte: URL? = nil) -> [String] {
        var args: [String]
        if let contexte {
            args = ["--prompt", consigneDeuxImages(instruction), "--image-paths", contexte.path, entree.path]
        } else {
            args = ["--prompt", instruction, "--image-paths", entree.path]
            if let masque { args += ["--mask-path", masque.path] }
        }
        switch qualite {
        case .normal:
            args += ["--steps", String(etapesNormal), "--vae-full-precision"]
        case .fast:
            // mflux 0.24 réclame une version de Turbo que Bria a retirée : la copie locale du cache.
            if let modeleRapide {
                args += ["--model", modeleRapide.path, "--base-model", "fibo2-edit-turbo"]
            } else {
                args += ["--model", "fibo2-edit-turbo"]
            }
        }
        args += ["--width", String(taille.largeur), "--height", String(taille.hauteur), "--seed", String(graine), "--output", sortie.path]
        return args
    }

    /// Le dossier du modèle dans le cache Hugging Face (version « main » téléchargée), s'il est complet.
    static func modeleLocal(depot: String, cache: URL) -> URL? {
        let dossier = cache.appendingPathComponent("models--" + depot.replacingOccurrences(of: "/", with: "--"))
        guard let ref = try? String(contentsOf: dossier.appendingPathComponent("refs/main"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else { return nil }
        let instantane = dossier.appendingPathComponent("snapshots/" + ref)
        return FileManager.default.fileExists(atPath: instantane.appendingPathComponent("model_index.json").path) ? instantane : nil
    }

    /// La consigne du mode à deux images (full_and_crop).
    static func consigneDeuxImages(_ instruction: String) -> String {
        "Edit <image_2> only: \(instruction). <image_1> shows the whole scene for context (light, colors, style); do not copy it."
    }

    // MARK: Modifications

    /// Une modification demandée : son nom court en français (« jupe »), l'instruction donnée à Fibo 2
    /// (en anglais), sa traduction pour l'utilisateur, et la zone à changer.
    struct Modification {
        var label: String
        var instruction: String
        var instructionFr: String
        var region: CGRect?
    }

    /// Le mode de l'entrée de Fibo pour une zone : le recadrage seul (crop, par défaut), ou la photo
    /// entière en plus, pour le contexte (full_and_crop).
    enum ModeContexte: String {
        case crop
        case fullAndCrop = "full_and_crop"
    }

    static let maxModifications = 4
    static let longueurLabel = 40

    /// Les modifications d'un appel : `edits` (1 à 4), ou les arguments simples (instruction,
    /// instruction_fr, region, label) pour une seule ; jamais les deux. Avec plus d'une
    /// modification, chaque zone est exigée, et deux zones ne se chevauchent pas.
    static func modifications(_ raw: [String: JSONValue]) throws -> [Modification] {
        let simples = ["instruction", "instruction_fr", "region", "label"].filter { raw[$0].map { !$0.isNull } ?? false }
        var liste: [Modification] = []
        if let edits = raw["edits"], !edits.isNull {
            guard simples.isEmpty else {
                throw LightroomError.invalid("« edits » et « \(simples.joined(separator: " », « ")) » ensemble : soit edits (une liste de modifications), soit instruction, instruction_fr et region pour une seule. Rien n'a été fait.")
            }
            guard let elements = edits.array, (1...maxModifications).contains(elements.count) else {
                throw LightroomError.invalid("« edits » : une liste de 1 à \(maxModifications) modifications { label, instruction, instruction_fr, region }. Rien n'a été fait.")
            }
            for (rang, element) in elements.enumerated() {
                guard let objet = element.object else {
                    throw LightroomError.invalid("« edits » : chaque modification est un objet { label, instruction, instruction_fr, region }. Rien n'a été fait.")
                }
                let inconnues = objet.keys.filter { !["label", "instruction", "instruction_fr", "region"].contains($0) }.sorted()
                guard inconnues.isEmpty else {
                    throw LightroomError.invalid("« edits » : label, instruction, instruction_fr et region seulement (pas \(inconnues.joined(separator: ", "))). Rien n'a été fait.")
                }
                liste.append(try modification(objet, rang: rang + 1, nombre: elements.count))
            }
        } else {
            liste = [try modification(raw.filter { ["instruction", "instruction_fr", "region", "label"].contains($0.key) }, rang: 1, nombre: 1)]
        }
        if liste.count > 1 {
            for modif in liste where modif.region == nil {
                throw LightroomError.invalid("« \(modif.label) » : sans region. Avec plusieurs modifications, chacune a sa zone (region). Rien n'a été fait.")
            }
            if let (a, b) = chevauchement(liste.compactMap(\.region)) {
                throw LightroomError.invalid("Les zones de « \(liste[a].label) » et de « \(liste[b].label) » se chevauchent : les faire en deux appels successifs (le second sur la nouvelle photo, par son id). Rien n'a été fait.")
            }
        }
        return liste
    }

    private static func modification(_ objet: [String: JSONValue], rang: Int, nombre: Int) throws -> Modification {
        let nom = nombre > 1 ? "modification \(rang)" : "modification"
        guard let instruction = objet["instruction"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty else {
            throw LightroomError.invalid("« instruction »\(nombre > 1 ? " (\(nom))" : "") : la modification à faire, en anglais, précise (ce qui change et ce qui reste). Rien n'a été fait.")
        }
        guard instruction.count <= 2000 else { throw LightroomError.invalid("« instruction » : 2 000 caractères au plus. Rien n'a été fait.") }
        guard let francais = objet["instruction_fr"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !francais.isEmpty else {
            throw LightroomError.invalid("« instruction_fr »\(nombre > 1 ? " (\(nom))" : "") : la traduction française de l'instruction, montrée à l'utilisateur. Rien n'a été fait.")
        }
        guard francais.count <= 2000 else { throw LightroomError.invalid("« instruction_fr » : 2 000 caractères au plus. Rien n'a été fait.") }
        var label = objet["label"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if label.isEmpty { label = nom }
        if label.count > longueurLabel { label = String(label.prefix(longueurLabel)).trimmingCharacters(in: .whitespaces) }
        // Une zone mal formée (un texte JSON, un tableau [x, y, w, h]) n'est jamais prise pour une
        // absence de zone : Fibo travaillerait sur toute la photo.
        if let brute = objet["region"], !brute.isNull, brute.object == nil {
            throw LightroomError.invalid("« region »\(nombre > 1 ? " (\(nom))" : "") : un objet { x, y, width, height } de 0 à 1 dans l'image que montre view_photo (pas un texte ni une liste). Rien n'a été fait.")
        }
        return Modification(label: label, instruction: instruction, instructionFr: francais, region: try region(objet["region"]?.object))
    }

    /// Les deux premières zones qui se chevauchent (une aire commune), s'il y en a : vu avant tout
    /// envoi, sans la taille de la photo.
    static func chevauchement(_ regions: [CGRect]) -> (Int, Int)? {
        for i in regions.indices {
            for j in regions.indices where j > i {
                let commun = regions[i].intersection(regions[j])
                if !commun.isNull, commun.width > 1e-9, commun.height > 1e-9 { return (i, j) }
            }
        }
        return nil
    }

    /// Jusqu'où la zone de mélange d'une pièce déborde de sa zone donnée, en pixels de l'entrée de
    /// Fibo (de petit côté `petit`) : la marge du masque (`masqueRegion`, arrondie vers l'extérieur),
    /// les deux flous de son demi-rayon (`masqueRegionDoux`), et l'interpolation de la recomposition.
    static func etendueMelange(petit: Int) -> Double {
        let p = Double(petit)
        return (margeRegion * p).rounded(.up) + 2 * Double(max(1, Int(p * margeRegion / 2))) + 2
    }

    /// La zone de mélange d'une modification dans la photo (en pixels) : sa zone élargie de
    /// `etendueMelange`, dans son recadrage.
    static func zoneDeMelangeDansLaPhoto(_ region: CGRect, largeur: Int, hauteur: Int) -> CGRect {
        let (cadre, taille) = recadrage(region, largeur: largeur, hauteur: hauteur)
        let e = etendueMelange(petit: min(taille.largeur, taille.hauteur))
        let ex = e * Double(cadre.largeur) / Double(max(1, taille.largeur)), ey = e * Double(cadre.hauteur) / Double(max(1, taille.hauteur))
        let l = Double(largeur), h = Double(hauteur)
        return CGRect(x: region.minX * l - ex, y: region.minY * h - ey, width: region.width * l + 2 * ex, height: region.height * h + 2 * ey)
            .intersection(cadre.rect)
    }

    /// Les deux premières modifications dont les zones de mélange se recouvrent (zones qui se
    /// touchent ou presque) : la seconde pièce, recollée après la première, en effacerait le bord
    /// (sa sortie y montre l'ancien contenu). Vu après l'exportation, d'après la taille de la photo.
    static func zonesTropProches(_ regions: [CGRect], largeur: Int, hauteur: Int) -> (Int, Int)? {
        let zones = regions.map { zoneDeMelangeDansLaPhoto($0, largeur: largeur, hauteur: hauteur) }
        for i in zones.indices {
            for j in zones.indices where j > i {
                let commun = zones[i].intersection(zones[j])
                if !commun.isNull, commun.width > 0, commun.height > 0 { return (i, j) }
            }
        }
        return nil
    }

    /// La consigne que le module garde au journal de la nouvelle photo et montre avec une demande
    /// d'accord : le texte français de chaque modification (avec son nom s'il y en a plusieurs), et
    /// la raison donnée.
    static func consigneJournal(_ modifications: [Modification], raison: String?) -> String {
        var texte = modifications.count == 1
            ? modifications[0].instructionFr
            : modifications.map { "\($0.label) : \($0.instructionFr)" }.joined(separator: " ; ")
        if let raison { texte += " — " + raison }
        return texte
    }

    // MARK: Recadrage autour d'une zone

    /// Marge de contexte autour d'une zone, de chaque côté, en part de sa taille.
    static let margeContexte = 0.5
    /// Côté minimal du recadrage, en part du petit côté de la photo.
    static let contexteMin = 0.35
    static let aireCible = 1024.0 * 1024.0

    /// Un rectangle en pixels de la photo (origine en haut à gauche).
    struct Pixels: Equatable {
        var x: Int, y: Int, largeur: Int, hauteur: Int
        var rect: CGRect { CGRect(x: x, y: y, width: largeur, height: hauteur) }
    }

    /// Le recadrage autour d'une zone (de 0 à 1) d'une photo de `largeur` × `hauteur` : la zone
    /// agrandie de `margeContexte` de sa taille de chaque côté, et d'au moins `contexteMin` du petit
    /// côté de la photo, centrée sur elle, coupée aux bords (sans être déplacée : contre un bord, le
    /// recadrage reste petit et garde plus souvent sa taille native), jamais plus allongé que 8:1
    /// (son petit côté grandit alors dans la photo, plutôt que l'entrée de Fibo soit déformée) ; et
    /// la taille de l'entrée de Fibo (`taille`) : environ 1 Mpx (`tailleCible`, chaque côté borné à
    /// la taille native) pour un grand recadrage ; pour un petit, sa taille native, le recadrage
    /// ramené aux multiples de 16 (`ajuster16`) : jamais plus grand que la taille native.
    static func recadrage(_ region: CGRect, largeur: Int, hauteur: Int) -> (cadre: Pixels, taille: (largeur: Int, hauteur: Int)) {
        let l = Double(largeur), h = Double(hauteur)
        let rx0 = region.minX * l, rx1 = region.maxX * l, ry0 = region.minY * h, ry1 = region.maxY * h
        let minimum = contexteMin * Double(min(largeur, hauteur))
        let cl = max((rx1 - rx0) * (1 + 2 * margeContexte), minimum), ch = max((ry1 - ry0) * (1 + 2 * margeContexte), minimum)
        let cx = (rx0 + rx1) / 2, cy = (ry0 + ry1) / 2
        // Les arrondis vers l'extérieur, à un millionième de pixel près (0,4 × 6 000 = 2 400,000…05).
        func bas(_ v: Double) -> Int { Int((v + 1e-6).rounded(.down)) }
        func haut(_ v: Double) -> Int { Int((v - 1e-6).rounded(.up)) }
        var x0 = max(0, bas(cx - cl / 2)), x1 = min(largeur, haut(cx + cl / 2))
        var y0 = max(0, bas(cy - ch / 2)), y1 = min(hauteur, haut(cy + ch / 2))
        // Jamais plus allongé que 8:1 (la borne de tailleCible) : une zone fine coupée par un bord.
        if x1 - x0 > Int(rapportMax) * (y1 - y0) {
            (y0, y1) = elargir(y0, y1, jusqua: Int((Double(x1 - x0) / rapportMax).rounded(.up)), limite: hauteur)
        } else if y1 - y0 > Int(rapportMax) * (x1 - x0) {
            (x0, x1) = elargir(x0, x1, jusqua: Int((Double(y1 - y0) / rapportMax).rounded(.up)), limite: largeur)
        }
        let lc = x1 - x0, hc = y1 - y0
        if Double(lc * hc) > aireCible {
            let t = tailleCible(largeur: lc, hauteur: hc)
            return (Pixels(x: x0, y: y0, largeur: lc, hauteur: hc), (min(t.largeur, max(16, lc / 16 * 16)), min(t.hauteur, max(16, hc / 16 * 16))))
        }
        // Le resserrement ne mord ni dans la zone ni dans son fondu (`etendueMelange`).
        let e = etendueMelange(petit: min(lc, hc))
        let (ax0, ax1, tl) = ajuster16(x0, x1, zone: rx0 - e, rx1 + e, limite: largeur)
        let (ay0, ay1, th) = ajuster16(y0, y1, zone: ry0 - e, ry1 + e, limite: hauteur)
        return (Pixels(x: ax0, y: ay0, largeur: ax1 - ax0, hauteur: ay1 - ay0), (tl, th))
    }

    /// Le rapport des côtés le plus allongé d'une entrée de Fibo (au-delà, tailleCible déforme).
    static let rapportMax = 8.0

    /// Un intervalle [debut, fin) agrandi jusqu'à `cible` de part et d'autre, ramené dans [0, limite).
    private static func elargir(_ debut: Int, _ fin: Int, jusqua cible: Int, limite: Int) -> (Int, Int) {
        let manque = cible - (fin - debut)
        guard manque > 0 else { return (debut, fin) }
        var a = debut - manque / 2, b = fin + (manque - manque / 2)
        if a < 0 { b -= a; a = 0 }
        if b > limite { a -= b - limite; b = limite }
        return (max(0, a), b)
    }

    /// Un intervalle [debut, fin) du petit recadrage ramené à une longueur multiple de 16, et la
    /// taille de l'entrée de Fibo sur cet axe : resserré hors de la zone (et de son fondu), du côté où
    /// elle laisse le plus de place ; sinon agrandi jusqu'au multiple suivant, dans la photo ; sinon
    /// (la zone touche les deux bords de la photo) gardé entier, l'entrée au multiple de 16 inférieur
    /// (à peine réduite) : jamais une bande de la zone laissée hors du recadrage.
    static func ajuster16(_ debut: Int, _ fin: Int, zone z0: Double, _ z1: Double, limite: Int) -> (Int, Int, Int) {
        let longueur = fin - debut
        let retrait = longueur % 16
        guard retrait > 0 else { return (debut, fin, longueur) }
        let placeAvant = max(0, Int(z0.rounded(.down)) - debut), placeApres = max(0, fin - Int(z1.rounded(.up)))
        if longueur > 16, placeAvant + placeApres >= retrait {
            var avant = min(placeAvant, retrait / 2)
            let apres = min(placeApres, retrait - avant)
            avant = retrait - apres
            return (debut + avant, fin - apres, longueur - retrait)
        }
        let ajout = 16 - retrait, libreAvant = debut, libreApres = limite - fin
        if libreAvant + libreApres >= ajout {
            var avant = min(libreAvant, ajout / 2)
            let apres = min(libreApres, ajout - avant)
            avant = ajout - apres
            return (debut - avant, fin + apres, longueur + ajout)
        }
        return (debut, fin, max(16, longueur / 16 * 16))
    }

    /// La zone (de 0 à 1 dans la photo) dans le repère du recadrage (de 0 à 1 dans lui), coupée à lui.
    static func regionDansRecadrage(_ region: CGRect, cadre: Pixels, largeur: Int, hauteur: Int) -> CGRect {
        let x0 = max(0, (region.minX * Double(largeur) - Double(cadre.x)) / Double(cadre.largeur))
        let x1 = min(1, (region.maxX * Double(largeur) - Double(cadre.x)) / Double(cadre.largeur))
        let y0 = max(0, (region.minY * Double(hauteur) - Double(cadre.y)) / Double(cadre.hauteur))
        let y1 = min(1, (region.maxY * Double(hauteur) - Double(cadre.y)) / Double(cadre.hauteur))
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    /// L'entrée de Fibo : la partie `cadre` de la photo (toute la photo sans cadre), en pixels RGBA 8
    /// bits sRGB à la `taille` donnée.
    static func entree(_ origine: CGImage, cadre: Pixels?, taille: (largeur: Int, hauteur: Int)) -> [UInt8]? {
        let source = cadre.flatMap { origine.cropping(to: $0.rect) } ?? origine
        if let cadre, source.width != cadre.largeur || source.height != cadre.hauteur { return nil }
        return pixelsRGBA8(source, largeur: taille.largeur, hauteur: taille.hauteur)
    }

    // MARK: SeedVR2

    /// L'exécutable de mflux pour SeedVR2 (mise à l'échelle par un modèle), à côté de celui de Fibo.
    static let nomSeedVR = "mflux-upscale-seedvr2"
    static let modeleSeedVR = "seedvr2-7b"
    /// Au-delà de ce facteur (sortie de Fibo → taille native de sa zone), SeedVR2 la remet à la taille.
    static let seuilSeedVR = 1.25

    /// Le facteur de mise à la taille d'une sortie de Fibo de `taille` vers son recadrage natif.
    static func facteur(cadre: Pixels, taille: (largeur: Int, hauteur: Int)) -> Double {
        max(Double(cadre.largeur) / Double(max(1, taille.largeur)), Double(cadre.hauteur) / Double(max(1, taille.hauteur)))
    }

    /// SeedVR2 7B ne découpe en tuiles que son décodeur : au-delà de ce facteur ou de cette taille de
    /// sortie, mémoire et durée sortent de l'échelle d'un Mac (et il inventerait le détail de toute
    /// la zone) ; provisoires, à relever sur de vrais passages.
    static let facteurMaxSeedVR = 4.0
    static let pixelsMaxSeedVR = 16_000_000

    /// SeedVR2 pour une zone, et sinon pourquoi (quand l'agrandissement le demanderait) : seulement
    /// avec une zone donnée (sans elle, il agrandirait toute la photo), si la sortie de Fibo doit être
    /// agrandie de plus de `seuilSeedVR` sur ses deux côtés, au plus `facteurMaxSeedVR` fois, vers
    /// `pixelsMaxSeedVR` au plus.
    static func seedVR(cadre: Pixels, taille: (largeur: Int, hauteur: Int), avecRegion: Bool, demande: Bool) -> (lancer: Bool, raison: String?) {
        let fx = Double(cadre.largeur) / Double(max(1, taille.largeur)), fy = Double(cadre.hauteur) / Double(max(1, taille.hauteur))
        guard demande, min(fx, fy) > seuilSeedVR else { return (false, nil) }
        guard avecRegion else {
            return (false, "Sans region, SeedVR2 n'est pas lancé (il agrandirait toute la photo) : mise à la taille ordinaire. Pour plus de détail, redemander avec region sur la seule partie à changer.")
        }
        let pixels = cadre.largeur * cadre.hauteur
        guard max(fx, fy) <= facteurMaxSeedVR, pixels <= pixelsMaxSeedVR else {
            return (false, "Zone trop grande pour SeedVR2 (× \(ToolHandler.nombre(max(fx, fy))), \(ToolHandler.nombre(Double(pixels) / 1_000_000)) Mpx ; × \(Int(facteurMaxSeedVR)) et \(pixelsMaxSeedVR / 1_000_000) Mpx au plus) : mise à la taille ordinaire, moins de détail. Une region plus juste en garde davantage.")
        }
        return (true, nil)
    }

    /// Les arguments de SeedVR2 : le côté court natif du recadrage, décodage par tuiles.
    static func argumentsSeedVR(entree: URL, resolution: Int, graine: Int, sortie: URL) -> [String] {
        ["--model", modeleSeedVR, "--image-path", entree.path, "--resolution", String(resolution),
         "--seed", String(graine), "--output", sortie.path, "--vae-tiling"]
    }

    // MARK: Progression

    /// Une barre de 0 à 100 % pour tout l'appel, par poids : exportation, puis, par modification, le
    /// chargement du modèle (avant la première étape), les étapes de Fibo et SeedVR2 (s'il tourne),
    /// enfin la recomposition et l'importation.
    struct Avancement {
        static let poidsExport = 3.0, poidsChargement = 10.0, poidsEtapes = 70.0, poidsSeedVR = 15.0, poidsFin = 5.0
        /// SeedVR2 prévu, par modification.
        var seedVR: [Bool]

        enum Phase {
            case export
            case chargement(Int)
            case etapes(Int, fait: Int, sur: Int)
            case seedVR(Int, fraction: Double)
            case fin
        }

        private func poids(_ rang: Int) -> Double { Self.poidsChargement + Self.poidsEtapes + (seedVR[rang] ? Self.poidsSeedVR : 0) }
        private var total: Double { Self.poidsExport + seedVR.indices.reduce(0) { $0 + poids($1) } + Self.poidsFin }
        private func avant(_ rang: Int) -> Double { Self.poidsExport + (0..<rang).reduce(0) { $0 + poids($1) } }

        /// Le pourcentage fait au début de la phase (et dans elle), de 0 à 99 avant la fin.
        func pourcentage(_ phase: Phase) -> Int {
            let fait: Double
            switch phase {
            case .export: fait = 0
            case .chargement(let rang): fait = avant(rang)
            case .etapes(let rang, let etape, let sur):
                fait = avant(rang) + Self.poidsChargement + Self.poidsEtapes * min(1, max(0, Double(etape) / Double(max(1, sur))))
            case .seedVR(let rang, let fraction):
                fait = avant(rang) + Self.poidsChargement + Self.poidsEtapes + Self.poidsSeedVR * min(1, max(0, fraction))
            case .fin: fait = total - Self.poidsFin
            }
            return min(99, Int((fait / total * 100).rounded(.down)))
        }
    }

    /// Le temps restant d'après le rythme des étapes déjà faites de la modification en cours (rien
    /// avant deux étapes) : ses étapes restantes, puis, pour chaque modification suivante, le même
    /// chargement du modèle et toutes ses étapes. SeedVR2 n'y compte pas (aucun rythme connu).
    static func tempsRestant(etape: Int, sur: Int, premiere: Int, secondesDepuisPremiere: TimeInterval,
                             chargement: TimeInterval, suivantes: Int) -> TimeInterval? {
        let faites = etape - premiere
        guard faites >= 2, secondesDepuisPremiere > 0 else { return nil }
        let parEtape = secondesDepuisPremiere / Double(faites)
        return Double(max(0, sur - etape)) * parEtape + Double(suivantes) * (chargement + Double(sur) * parEtape)
    }

    /// « environ 3 min restantes », « environ 1 min restante », « moins d'une minute restante ».
    static func texteTempsRestant(_ secondes: TimeInterval) -> String {
        guard secondes >= 60 else { return "moins d'une minute restante" }
        let minutes = Int((secondes / 60).rounded())
        return minutes <= 1 ? "environ 1 min restante" : "environ \(minutes) min restantes"
    }

    /// Le texte de la barre : « Fibo 2 : jupe (1 sur 2), 24 % — environ 3 min restantes ».
    static func texteProgression(_ quoi: String, rang: Int?, sur: Int, pourcentage: Int, detail: String?) -> String {
        var texte = "Fibo 2 : " + quoi
        if let rang, sur > 1 { texte += " (\(rang) sur \(sur))" }
        texte += ", \(pourcentage) %"
        if let detail { texte += " — " + detail }
        return texte
    }

    /// Une barre de téléchargement ou de chargement (« Fetching 4 files: 4/4 [ », « Loading
    /// checkpoint shards: 2/4 [ ») : jamais lue comme des étapes ni comme l'avancée de SeedVR2.
    static func estUnChargement(_ ligne: String) -> Bool {
        ligne.range(of: #"(?i)fetching|loading|download"#, options: .regularExpression) != nil
    }

    /// L'avancée d'une barre tqdm quelconque (« 3/8 [ »), pour SeedVR2.
    static func progressionLibre(_ ligne: String) -> (fait: Int, total: Int)? {
        guard !estUnChargement(ligne) else { return nil }
        let plage = NSRange(ligne.startIndex..., in: ligne)
        guard let trouve = motifProgression.firstMatch(in: ligne, range: plage),
              let r1 = Range(trouve.range(at: 1), in: ligne), let r2 = Range(trouve.range(at: 2), in: ligne),
              let fait = Int(ligne[r1]), let total = Int(ligne[r2]), total > 0 else { return nil }
        return (fait, total)
    }

    // MARK: Sortie de mflux

    /// Les lignes de la sortie de mflux, reçue par morceaux : tqdm réécrit sa ligne avec \r.
    struct Lignes {
        private var reste = ""
        mutating func ajouter(_ texte: String) -> [String] {
            reste += texte
            var parties = reste.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            reste = parties.removeLast()
            return parties.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        mutating func finir() -> [String] {
            defer { reste = "" }
            return reste.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [reste]
        }
    }

    private static let motifProgression = try! NSRegularExpression(pattern: #"(\d+)/(\d+) \["#)

    /// L'étape d'une barre tqdm (« 12/50 [ »), si la ligne en porte une avec le nombre d'étapes voulu.
    static func progression(_ ligne: String, etapes: Int) -> Int? {
        guard !estUnChargement(ligne) else { return nil }
        let plage = NSRange(ligne.startIndex..., in: ligne)
        guard let trouve = motifProgression.firstMatch(in: ligne, range: plage),
              let r1 = Range(trouve.range(at: 1), in: ligne), let r2 = Range(trouve.range(at: 2), in: ligne),
              let etape = Int(ligne[r1]), let total = Int(ligne[r2]), total == etapes else { return nil }
        return etape
    }

    /// Une erreur de mflux, en mots simples, d'après son journal. Un accès refusé se reconnaît à des
    /// motifs précis (« 401 Client Error », « Unauthorized »…), jamais à « 401 » ou « 403 » seuls,
    /// qu'une barre de téléchargement écrit aussi (« 401M/9.95G »).
    static func expliquer(journal: String, code: Int32, rapide: Bool) -> String {
        let depot = rapide ? depotRapide : depotNormal
        if ["requires approval", "GatedRepo", "Unauthorized", "Forbidden"].contains(where: journal.contains)
            || journal.range(of: #"\b40[13] Client Error\b"#, options: .regularExpression) != nil {
            return "Fibo 2 : accès au modèle refusé. Demander l'accès sur huggingface.co/\(depot), puis vérifier la connexion avec « hf auth login » dans le Terminal."
        }
        if journal.contains("RevisionNotFound") {
            return "Fibo 2 : le modèle n'est pas complet sur ce Mac. Le télécharger une fois dans le Terminal : hf download \(depot)"
        }
        if ["ConnectionError", "Max retries", "Temporary failure", "LocalEntryNotFound"].contains(where: journal.contains) {
            return "Fibo 2 : impossible de joindre Hugging Face (le modèle se télécharge au premier usage). Vérifier la connexion Internet, puis réessayer."
        }
        let fin = journal.split(separator: "\n").suffix(3).joined(separator: "\n")
        return "Fibo 2 (mflux) s'est arrêté avec une erreur (code \(code))." + (fin.isEmpty ? "" : "\n" + fin)
    }

    // MARK: Masques

    /// Le masque de Fibo : blanc dans la zone élargie de la marge, noir ailleurs (0 ou 255 par pixel).
    static func masqueRegion(_ region: CGRect, largeur: Int, hauteur: Int) -> [UInt8] {
        let marge = margeRegion * Double(min(largeur, hauteur))
        let x0 = max(0, Int((region.minX * Double(largeur) - marge).rounded(.down)))
        let x1 = min(largeur, Int((region.maxX * Double(largeur) + marge).rounded(.up)))
        let y0 = max(0, Int((region.minY * Double(hauteur) - marge).rounded(.down)))
        let y1 = min(hauteur, Int((region.maxY * Double(hauteur) + marge).rounded(.up)))
        var masque = [UInt8](repeating: 0, count: largeur * hauteur)
        guard x0 < x1, y0 < y1 else { return masque }
        for y in y0..<y1 {
            for x in x0..<x1 { masque[y * largeur + x] = 255 }
        }
        return masque
    }

    /// Flou en boîte séparable (sommes glissantes), bords répétés.
    static func flouBoite(_ valeurs: [Float], largeur: Int, hauteur: Int, rayon: Int) -> [Float] {
        guard rayon > 0, largeur > 0, hauteur > 0 else { return valeurs }
        let fenetre = Float(2 * rayon + 1)
        var tmp = [Float](repeating: 0, count: valeurs.count)
        var sortie = [Float](repeating: 0, count: valeurs.count)
        for y in 0..<hauteur {
            let base = y * largeur
            var somme: Float = 0
            for k in -rayon...rayon { somme += valeurs[base + min(max(k, 0), largeur - 1)] }
            for x in 0..<largeur {
                tmp[base + x] = somme / fenetre
                somme += valeurs[base + min(x + rayon + 1, largeur - 1)] - valeurs[base + max(x - rayon, 0)]
            }
        }
        for x in 0..<largeur {
            var somme: Float = 0
            for k in -rayon...rayon { somme += tmp[min(max(k, 0), hauteur - 1) * largeur + x] }
            for y in 0..<hauteur {
                sortie[y * largeur + x] = somme / fenetre
                somme += tmp[min(y + rayon + 1, hauteur - 1) * largeur + x] - tmp[max(y - rayon, 0) * largeur + x]
            }
        }
        return sortie
    }

    /// La zone changée par Fibo (de 0 à 1 par pixel, à la petite taille) : l'écart entre l'entrée et
    /// la sortie (pixels RGBA 8 bits, même taille), lissé, seuillé, débarrassé des points isolés,
    /// élargi puis fondu ; coupée par la zone donnée (élargie de la marge, fondue), s'il y en a une.
    /// Avec une zone donnée, elle ne sert qu'à mesurer ce qui a changé : la recomposition prend la
    /// zone entière (`zoneDeMelange`).
    static func zoneChangee(entree: [UInt8], sortie: [UInt8], largeur: Int, hauteur: Int, region: CGRect?) -> [Float] {
        let n = largeur * hauteur
        guard n > 0, entree.count >= n * 4, sortie.count >= n * 4 else { return [] }
        var ecart = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var plus: Int32 = 0
            for c in 0..<3 { plus = max(plus, abs(Int32(entree[i * 4 + c]) - Int32(sortie[i * 4 + c]))) }
            ecart[i] = Float(plus) / 255
        }
        let petit = Double(min(largeur, hauteur))
        let lisse = flouBoite(ecart, largeur: largeur, hauteur: hauteur, rayon: 1)
        var binaire = lisse.map { $0 > seuilEcart ? Float(1) : 0 }
        // Points isolés : un pixel n'en est que si la majorité de son voisinage (5 × 5) l'est aussi ;
        // une bande de 3 pixels, ce que le flou fait d'un trait d'un pixel, la garde.
        binaire = flouBoite(binaire, largeur: largeur, hauteur: hauteur, rayon: 2).map { $0 > 0.5 ? 1 : 0 }
        let elargi = flouBoite(binaire, largeur: largeur, hauteur: hauteur, rayon: max(1, Int(petit * elargissement)))
            .map { $0 > 0.0001 ? Float(1) : 0 }
        let rayonFondu = max(1, Int(petit * fondu))
        var zone = flouBoite(flouBoite(elargi, largeur: largeur, hauteur: hauteur, rayon: rayonFondu), largeur: largeur, hauteur: hauteur, rayon: rayonFondu)
        if let region {
            let borne = masqueRegionDoux(region, largeur: largeur, hauteur: hauteur)
            for i in 0..<n { zone[i] *= borne[i] }
        }
        return zone
    }

    /// Au-delà de cette part du pourtour changée (mode full_and_crop, sans masque), la sortie de
    /// Fibo ne s'aligne pas sur le recadrage (reprise de <image_1>, sujet cadré autrement) : rien
    /// n'en est repris. Provisoire, à relever sur de vraies sorties.
    static let partPourtourMax = 0.3

    /// La part du pourtour de la zone (le recadrage hors de la zone élargie de la marge et du fondu)
    /// que Fibo a changée ; nil si ce pourtour est trop petit pour en juger.
    static func partDuPourtourChangee(entree: [UInt8], sortie: [UInt8], largeur: Int, hauteur: Int, region: CGRect) -> Double? {
        let changee = zoneChangee(entree: entree, sortie: sortie, largeur: largeur, hauteur: hauteur, region: nil)
        let borne = masqueRegionDoux(region, largeur: largeur, hauteur: hauteur)
        guard changee.count == borne.count else { return nil }
        var dehors = 0, change = 0
        for i in borne.indices where borne[i] < 1e-4 {
            dehors += 1
            if changee[i] > 0.5 { change += 1 }
        }
        guard dehors >= max(256, borne.count / 100) else { return nil }
        return Double(change) / Double(dehors)
    }

    /// La zone de mélange : avec une zone donnée, toute la sortie de Fibo dans cette zone (élargie de
    /// la marge, fondue) : Fibo n'a travaillé que là, sous son masque, et un changement fin ou peu
    /// contrasté que la mesure manquerait y est repris quand même ; sans zone, la zone changée
    /// mesurée, ou toute l'image si elle dépasse `partSortieEntiere`. Rend aussi si toute la sortie
    /// est prise (sans zone donnée seulement).
    static func zoneDeMelange(changee: [Float], region: CGRect?, largeur: Int, hauteur: Int) -> (zone: [Float], sortieEntiere: Bool) {
        if let region {
            return (masqueRegionDoux(region, largeur: largeur, hauteur: hauteur), false)
        }
        if part(changee) > partSortieEntiere {
            return ([Float](repeating: 1, count: largeur * hauteur), true)
        }
        return (changee, false)
    }

    /// La remarque d'une sortie prise entière (sans zone donnée : avec une zone, c'est toujours la
    /// zone entière, sans remarque) ; la part est celle de l'image.
    static func remarqueSortieEntiere(partChangee: Double, sortieEntiere: Bool) -> String? {
        guard sortieEntiere else { return nil }
        return "La zone changée couvrait \(Int((partChangee * 100).rounded())) % de l'image : toute la sortie de Fibo 2 est prise, à sa résolution d'environ 1 Mpx : moins de détail partout. Pour garder le détail, redemander avec region sur la seule partie à changer."
    }

    /// La zone donnée élargie de la marge et fondue (de 0 à 1), pour borner le mélange.
    static func masqueRegionDoux(_ region: CGRect, largeur: Int, hauteur: Int) -> [Float] {
        let dur = masqueRegion(region, largeur: largeur, hauteur: hauteur).map { Float($0) / 255 }
        let rayon = max(1, Int(Double(min(largeur, hauteur)) * margeRegion / 2))
        return flouBoite(flouBoite(dur, largeur: largeur, hauteur: hauteur, rayon: rayon), largeur: largeur, hauteur: hauteur, rayon: rayon)
    }

    /// La part de l'image dans la zone (pixels à plus de 0,5).
    static func part(_ zone: [Float]) -> Double {
        guard !zone.isEmpty else { return 0 }
        return Double(zone.reduce(0) { $0 + ($1 > 0.5 ? 1 : 0) }) / Double(zone.count)
    }

    // MARK: Images

    /// Les pixels RGBA 8 bits sRGB d'une image dessinée à la taille donnée.
    static func pixelsRGBA8(_ image: CGImage, largeur: Int, hauteur: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: largeur * hauteur * 4)
        let ok = pixels.withUnsafeMutableBytes { tampon -> Bool in
            guard let contexte = CGContext(data: tampon.baseAddress, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: largeur * 4,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            contexte.interpolationQuality = .high
            contexte.draw(image, in: CGRect(x: 0, y: 0, width: largeur, height: hauteur))
            return true
        }
        return ok ? pixels : nil
    }

    /// Une image RGB 8 bits sRGB (PNG de l'entrée), ou en niveaux de gris (masque).
    static func image8(_ pixels: [UInt8], largeur: Int, hauteur: Int, gris: Bool = false) -> CGImage? {
        let composantes = gris ? 1 : 4
        guard pixels.count >= largeur * hauteur * composantes, let fournisseur = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: largeur, height: hauteur, bitsPerComponent: 8, bitsPerPixel: 8 * composantes, bytesPerRow: largeur * composantes,
                       space: gris ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: gris ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: fournisseur, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Le masque de Fibo, blanc sur noir, en image RGB (comme une photo : mflux le lit ainsi sans doute).
    static func imageMasque(_ masque: [UInt8], largeur: Int, hauteur: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: largeur * hauteur * 4)
        for i in 0..<(largeur * hauteur) { rgba[i * 4] = masque[i]; rgba[i * 4 + 1] = masque[i]; rgba[i * 4 + 2] = masque[i] }
        return image8(rgba, largeur: largeur, hauteur: hauteur)
    }

    static func ecrirePNG(_ image: CGImage, vers url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw LightroomError.plugin("PNG impossible à écrire : \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw LightroomError.plugin("PNG impossible à écrire : \(url.path)") }
    }

    static func lireImage(_ url: URL) -> (image: CGImage, proprietes: [CFString: Any])? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let proprietes = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return (image, proprietes)
    }

    /// Le paquet XMP d'une image (tous ses champs, ceux qu'ImageIO ne fait correspondre ni à l'Exif,
    /// ni à l'IPTC, ni au TIFF compris : libellé, texte alternatif, mots-clés hiérarchiques de
    /// Lightroom…), pour le recopier tel quel dans le TIFF final.
    static func lireMetadonnees(_ url: URL) -> CGImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyMetadataAtIndex(source, 0, nil)
    }

    /// Une sortie de Fibo à remettre dans la photo : l'image (sortie de Fibo, ou de SeedVR2), la zone
    /// de mélange (de 0 à 1, à sa petite taille) et la place de son recadrage dans la photo.
    struct Piece {
        var generee: CGImage
        var zone: [Float]
        var largeurZone: Int
        var hauteurZone: Int
        var cadre: Pixels
    }

    /// La recomposition en pleine résolution : chaque sortie de Fibo mise à la taille de son recadrage,
    /// mêlée à la photo selon sa zone (lue en bilinéaire depuis la petite taille), l'une après l'autre ;
    /// hors des zones (0), les pixels de la photo restent tels quels, au bit près. Image RGB 16 bits
    /// dans l'espace de la photo (Adobe RGB).
    static func recomposer(origine: CGImage, pieces: [Piece]) -> CGImage? {
        let l = origine.width, h = origine.height
        guard l > 0, h > 0 else { return nil }
        let espace = origine.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        let info = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        func dessiner(_ image: CGImage, largeur: Int, hauteur: Int, qualite: CGInterpolationQuality) -> CGContext? {
            guard let contexte = CGContext(data: nil, width: largeur, height: hauteur, bitsPerComponent: 16, bytesPerRow: largeur * 8, space: espace, bitmapInfo: info) else { return nil }
            contexte.interpolationQuality = qualite
            contexte.draw(image, in: CGRect(x: 0, y: 0, width: largeur, height: hauteur))
            return contexte
        }
        guard let fond = dessiner(origine, largeur: l, hauteur: h, qualite: .none),
              let pf = fond.data?.bindMemory(to: UInt16.self, capacity: l * h * 4) else { return nil }
        var sortie = [UInt16](repeating: 0, count: l * h * 3)
        for i in 0..<(l * h) {
            sortie[i * 3] = pf[i * 4]; sortie[i * 3 + 1] = pf[i * 4 + 1]; sortie[i * 3 + 2] = pf[i * 4 + 2]
        }
        for piece in pieces {
            let c = piece.cadre, lz = piece.largeurZone, hz = piece.hauteurZone
            guard c.largeur > 0, c.hauteur > 0, c.x >= 0, c.y >= 0, c.x + c.largeur <= l, c.y + c.hauteur <= h,
                  lz > 0, hz > 0, piece.zone.count == lz * hz,
                  let dessus = dessiner(piece.generee, largeur: c.largeur, hauteur: c.hauteur, qualite: .high),
                  let pd = dessus.data?.bindMemory(to: UInt16.self, capacity: c.largeur * c.hauteur * 4) else { return nil }
            let ex = Double(lz) / Double(c.largeur), ey = Double(hz) / Double(c.hauteur)
            for y in 0..<c.hauteur {
                let fy = max(0, min(Double(hz - 1), (Double(y) + 0.5) * ey - 0.5))
                let y0 = Int(fy), y1 = min(y0 + 1, hz - 1)
                let ty = Float(fy - Double(y0))
                for x in 0..<c.largeur {
                    let fx = max(0, min(Double(lz - 1), (Double(x) + 0.5) * ex - 0.5))
                    let x0 = Int(fx), x1 = min(x0 + 1, lz - 1)
                    let tx = Float(fx - Double(x0))
                    let haut = piece.zone[y0 * lz + x0] * (1 - tx) + piece.zone[y0 * lz + x1] * tx
                    let bas = piece.zone[y1 * lz + x0] * (1 - tx) + piece.zone[y1 * lz + x1] * tx
                    let m = min(1, max(0, haut * (1 - ty) + bas * ty))
                    guard m > 0 else { continue }
                    let i = (y * c.largeur + x) * 4, o = ((y + c.y) * l + x + c.x) * 3
                    if m >= 1 {
                        sortie[o] = pd[i]; sortie[o + 1] = pd[i + 1]; sortie[o + 2] = pd[i + 2]
                    } else {
                        for k in 0..<3 {
                            sortie[o + k] = UInt16((Float(sortie[o + k]) * (1 - m) + Float(pd[i + k]) * m).rounded())
                        }
                    }
                }
            }
        }
        let donnees = sortie.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let fournisseur = CGDataProvider(data: donnees as CFData) else { return nil }
        return CGImage(width: l, height: h, bitsPerComponent: 16, bitsPerPixel: 48, bytesPerRow: l * 6, space: espace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                       provider: fournisseur, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// La compression du TIFF final : Deflate (Adobe, 8), comme les exportations TIFF de Lightroom
    /// (ZIP). Le LZW sans prédicteur grossissait un TIFF 16 bits bruité d'environ 30 % (mesuré le
    /// 29 octobre 2026 par la relecture : 23,8 Mo contre 18,0 sans compression et 17,6 en Deflate).
    static let compressionTIFF = 8

    /// Écrit le TIFF final (16 bits, Deflate), avec les métadonnées du TIFF exporté : le paquet XMP
    /// entier (`metadonnees`, par CGImageDestinationAddImageAndMetadata : sans lui, ce qui n'existe
    /// qu'en XMP se perdait, libellé et texte alternatif compris) et les dictionnaires Exif, IPTC, GPS
    /// et TIFF ; les dimensions et la profondeur sont celles de l'image. Avec le paquet XMP,
    /// ImageIO ne lit la compression qu'au premier niveau des options (constaté le 29 octobre 2026 :
    /// dans le dictionnaire TIFF, elle était ignorée).
    static func ecrireTIFF(_ image: CGImage, proprietes: [CFString: Any], metadonnees: CGImageMetadata? = nil, vers url: URL) throws {
        var gardees = proprietes
        for cle in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth, kCGImagePropertyHasAlpha,
                    kCGImagePropertyColorModel, kCGImagePropertyProfileName, kCGImagePropertyIsFloat, kCGImagePropertyIsIndexed] {
            gardees.removeValue(forKey: cle)
        }
        var tiff = gardees[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFCompression] = compressionTIFF
        gardees[kCGImagePropertyTIFFDictionary] = tiff
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw LightroomError.plugin("TIFF impossible à écrire : \(url.path)")
        }
        if let metadonnees {
            gardees[kCGImagePropertyTIFFCompression] = compressionTIFF
            CGImageDestinationAddImageAndMetadata(destination, image, metadonnees, gardees as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, gardees as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw LightroomError.plugin("TIFF impossible à écrire : \(url.path)") }
    }
}
