import CoreGraphics
import Foundation

/// La mise au point d'une photo Fujifilm en détail, pour l'onglet Focus de la fenêtre Claude
/// (demandé par Dany le 22 octobre 2026) : mode de mise au point, priorité, mode et taille de la
/// zone AF, avertissement, visages et éléments du sujet détectés par l'appareil, avec leurs
/// positions ; et, de la prise de vue, la stabilisation et le mode d'entraînement, que Lightroom ne
/// donne pas. Lue par LectureBoitier (Boitier.swift) de la même ouverture que le point et
/// l'intention.
///
/// Ce que le module Focus-Points de Lightroom (v4, Apache 2.0, FujifilmDelegates.lua) montre pour un
/// fichier Fujifilm, d'après les étiquettes d'ExifTool (Image/ExifTool/FujiFilm.pm) qu'il lit :
/// FocusMode (0x1021), AFMode (0x1022), FocusPixel (0x1023), PrioritySettings (0x102b : AF-SPriority
/// masque 0x000f, AF-CPriority 0x00f0), FocusSettings (0x102d : FocusMode2 0x0f, PreAF 0xf0,
/// AFAreaMode 0x0f00, AFAreaPointSize 0xf000, AFAreaZoneSize 0xff0000, largeur dans ses 4 bits bas
/// et hauteur au-delà du 5e), CropMode (0x104d), SequenceNumber (0x1101), DriveSettings (0x1103 :
/// DriveMode 0xff, DriveSpeed 0xff000000), FocusWarning (0x1301), ImageStabilization (0x1422 : type,
/// mode), FacesDetected (0x4100), FacePositions (0x4103), FaceElementTypes (0x4201),
/// FaceElementPositions (0x4203). Comme dans Focus-Points, les positions des visages et des
/// éléments (gauche, haut, droite, bas) sont dans le même repère que FocusPixel : le JPEG incorporé,
/// dont l'Exif donne les dimensions (ExifImageWidth et ExifImageHeight). Recoupé le 22 octobre 2026
/// sur DSCF2402.RAF (X-H2S, l'original de la copie d'essai 53709912) par l'exiftool de Focus-Points :
/// FaceElementTypes y est rangé en SHORT (int8u chez ExifTool), FocusSettings en LONG,
/// PrioritySettings en SHORT. Chaque valeur est facultative.
public struct MiseAuPointBoitier: Equatable {
    /// Le repère des positions (ExifImageWidth, ExifImageHeight).
    public var largeur: Int?
    public var hauteur: Int?
    /// FocusPixel (x, y) ; vide sans point rangé (0, 0 : mise au point manuelle, supposé).
    public var pixel: [Int]
    /// FocusMode (0x1021) : 0 auto, 1 manuel, 65535 vidéo.
    public var modeMiseAuPoint: Int?
    /// AFMode (0x1022) : 0 aucun, 1 point unique, 256 zone, 512 large / suivi.
    public var modeAF: Int?
    /// FocusSettings (0x102d), le mot entier (int32u).
    public var reglagesAF: Int?
    /// PrioritySettings (0x102b), le mot entier (int16u).
    public var priorites: Int?
    /// FocusWarning (0x1301) : 0 bonne, 1 floue.
    public var avertissement: Int?
    /// FacesDetected (0x4100) et FacePositions (0x4103 : gauche, haut, droite, bas par visage).
    public var visages: Int?
    public var positionsVisages: [Int]
    /// FaceElementTypes (0x4201) et FaceElementPositions (0x4203 : quatre nombres par élément).
    public var typesElements: [Int]
    public var positionsElements: [Int]
    /// ImageStabilization (0x1422) : type, mode, puis un nombre que Focus-Points montre sans le
    /// nommer.
    public var stabilisation: [Int]
    /// DriveSettings (0x1103), le mot entier (int32u), et SequenceNumber (0x1101).
    public var entrainement: Int?
    public var sequence: Int?
    /// CropMode (0x104d) : 1 format 35 mm sur GFX, 2 viseur sport, 4 recadrage 1,25×, 8
    /// téléconvertisseur numérique.
    public var recadrage: Int?

    public init(largeur: Int? = nil, hauteur: Int? = nil, pixel: [Int] = [], modeMiseAuPoint: Int? = nil, modeAF: Int? = nil,
                reglagesAF: Int? = nil, priorites: Int? = nil, avertissement: Int? = nil, visages: Int? = nil,
                positionsVisages: [Int] = [], typesElements: [Int] = [], positionsElements: [Int] = [],
                stabilisation: [Int] = [], entrainement: Int? = nil, sequence: Int? = nil, recadrage: Int? = nil) {
        self.largeur = largeur
        self.hauteur = hauteur
        self.pixel = pixel
        self.modeMiseAuPoint = modeMiseAuPoint
        self.modeAF = modeAF
        self.reglagesAF = reglagesAF
        self.priorites = priorites
        self.avertissement = avertissement
        self.visages = visages
        self.positionsVisages = positionsVisages
        self.typesElements = typesElements
        self.positionsElements = positionsElements
        self.stabilisation = stabilisation
        self.entrainement = entrainement
        self.sequence = sequence
        self.recadrage = recadrage
    }

    /// Au plus tant de nombres lus dans une liste de positions (16 visages ou éléments).
    static let positionsMax = 64

    /// D'après l'IFD de la MakerNote et l'IFD Exif ; nil si rien de la mise au point n'est lu.
    init?(note: [Int: LectureBoitier.Tiff.Entree], exif: [Int: LectureBoitier.Tiff.Entree]) {
        func entier(_ tag: Int) -> Int? { IntentionBoitier.entier(note[tag]) }
        func liste(_ tag: Int) -> [Int] {
            guard let entree = note[tag], [1, 3, 4, 7].contains(entree.type) else { return [] }
            return entree.entiers(Self.positionsMax)
        }
        let pixel = liste(0x1023).prefix(2)
        self.init(largeur: IntentionBoitier.entier(exif[0xA002]), hauteur: IntentionBoitier.entier(exif[0xA003]),
                  pixel: pixel.count == 2 && (pixel[0] > 0 || pixel[1] > 0) ? Array(pixel) : [],
                  modeMiseAuPoint: entier(0x1021), modeAF: entier(0x1022), reglagesAF: note[0x102d]?.mot(4),
                  priorites: note[0x102b]?.mot(2), avertissement: entier(0x1301), visages: entier(0x4100),
                  positionsVisages: liste(0x4103), typesElements: liste(0x4201), positionsElements: liste(0x4203),
                  stabilisation: liste(0x1422), entrainement: note[0x1103]?.mot(4), sequence: entier(0x1101),
                  recadrage: entier(0x104d))
        let rien = MiseAuPointBoitier(largeur: largeur, hauteur: hauteur)
        if self == rien { return nil }
    }

    // MARK: Valeurs groupées (masques d'ExifTool, décalés de leurs bits à zéro)

    /// FocusMode2 : 0 AF-M, 1 AF-S, 2 AF-C.
    public var modeMiseAuPoint2: Int? { reglagesAF.map { $0 & 0xF } }
    /// PreAF : 0 désactivé, 1 activé.
    public var preAF: Int? { reglagesAF.map { ($0 >> 4) & 0xF } }
    /// AFAreaMode : 0 point unique, 1 zone, 2 large / suivi.
    public var modeZone: Int? { reglagesAF.map { ($0 >> 8) & 0xF } }
    /// AFAreaPointSize (0 : sans objet).
    public var taillePoint: Int? { reglagesAF.map { ($0 >> 12) & 0xF }.flatMap { $0 == 0 ? nil : $0 } }
    /// AFAreaZoneSize : largeur et hauteur en cases (« 5 x 5 » chez ExifTool), nil sans objet.
    public var tailleZone: (largeur: Int, hauteur: Int)? {
        guard let reglagesAF else { return nil }
        let valeur = (reglagesAF >> 16) & 0xFF
        let largeur = valeur & 0x0F, hauteur = valeur >> 5
        guard valeur != 0, largeur > 0, hauteur > 0 else { return nil }
        return (largeur, hauteur)
    }
    /// AF-SPriority et AF-CPriority : 1 déclenchement, 2 mise au point.
    public var prioriteAFS: Int? { priorites.map { $0 & 0xF } }
    public var prioriteAFC: Int? { priorites.map { ($0 >> 4) & 0xF } }
    /// DriveMode : 0 vue par vue, 1 rafale lente, 2 rafale rapide ; DriveSpeed en images par
    /// seconde (0 : sans objet).
    public var modeEntrainement: Int? { entrainement.map { $0 & 0xFF } }
    public var cadence: Int? { entrainement.map { ($0 >> 24) & 0xFF }.flatMap { $0 == 0 ? nil : $0 } }

    /// La zone AF d'après AFAreaMode, sinon AFMode : 'point', 'zone', 'large', 'aucune'.
    public var zone: String? {
        if let modeZone { return [0: "point", 1: "zone", 2: "large"][modeZone] }
        return modeAF.flatMap { [0: "aucune", 1: "point", 256: "zone", 512: "large"][$0] }
    }

    /// Mise au point manuelle : FocusMode2 AF-M, ou FocusMode manuel.
    public var manuelle: Bool { modeMiseAuPoint2 == 0 || modeMiseAuPoint == 1 }

    // MARK: Textes (en français simple ; les noms d'ExifTool sont dans valeursLues)

    static let modes2: [Int: String] = [0: "Manuelle (MF)", 1: "AF-S (ponctuel)", 2: "AF-C (continu)"]
    static let modes: [Int: String] = [0: "Autofocus", 1: "Manuelle", 65535: "Vidéo"]
    static let prioritesTextes: [Int: String] = [1: "Déclenchement", 2: "Mise au point"]
    static let zones: [String: String] = ["point": "Point unique", "zone": "Zone", "large": "Large / suivi", "aucune": "Aucun"]
    static let avertissements: [Int: String] = [0: "Bonne", 1: "Floue (mise au point manquée)"]
    /// FaceElementTypes, en minuscules : « tête, visage, œil gauche, œil droit ».
    static let elements: [Int: String] = [
        1: "visage", 2: "œil gauche", 3: "œil droit", 7: "corps", 8: "tête", 9: "les deux yeux", 11: "deux-roues",
        12: "carrosserie", 13: "avant de voiture", 14: "corps d'animal", 15: "tête d'animal", 16: "face d'animal",
        17: "œil gauche d'animal", 18: "œil droit d'animal", 19: "corps d'oiseau", 20: "tête d'oiseau",
        21: "œil gauche d'oiseau", 22: "œil droit d'oiseau", 23: "avion", 25: "cockpit d'avion", 26: "avant de train",
        27: "cabine de train", 28: "tête d'animal", 29: "corps d'animal",
    ]
    static let stabilisations: [Int: String] = [0: "aucune", 1: "optique", 2: "capteur", 3: "objectif (OIS)",
                                                258: "capteur et objectif, plus numérique", 512: "numérique"]
    static let modesStabilisation: [Int: String] = [0: "désactivée", 1: "active (mode 1, en continu)",
                                                    2: "active (mode 2, à la prise de vue seulement)"]
    static let entrainements: [Int: String] = [0: "Vue par vue", 1: "Rafale lente (CL)", 2: "Rafale rapide (CH)"]
    static let recadrages: [Int: String] = [1: "Format 35 mm sur GFX", 2: "Viseur sport", 4: "Recadrage 1,25× (obturateur électronique)",
                                            8: "Téléconvertisseur numérique"]

    /// Le nom d'un élément du sujet (« œil droit »).
    public static func nomElement(_ type: Int) -> String { elements[type] ?? "élément \(type)" }

    static func majuscule(_ texte: String) -> String { texte.prefix(1).uppercased() + texte.dropFirst() }

    /// Une ligne de la carte Focus : son titre et sa valeur.
    public struct Ligne: Equatable {
        public var titre: String
        public var valeur: String
        public init(_ titre: String, _ valeur: String) {
            self.titre = titre
            self.valeur = valeur
        }
    }

    /// Le bloc Image : le recadrage du boîtier, s'il y en a un (CropMode non nul).
    public var lignesImage: [Ligne] {
        guard let recadrage, recadrage != 0 else { return [] }
        return [Ligne("Recadrage du boîtier", Self.recadrages[recadrage] ?? "code \(recadrage)")]
    }

    /// Le bloc Prise de vue : ce que Lightroom ne donne pas, la stabilisation et le mode
    /// d'entraînement.
    public var lignesPriseDeVue: [Ligne] {
        var lignes: [Ligne] = []
        if let type = stabilisation.first {
            var texte = Self.stabilisations[type] ?? "type \(type)"
            if type != 0, stabilisation.count >= 2 {
                texte += ", " + (Self.modesStabilisation[stabilisation[1]] ?? "mode \(stabilisation[1])")
            }
            lignes.append(Ligne("Stabilisation", Self.majuscule(texte)))
        }
        if let mode = modeEntrainement {
            var texte = Self.entrainements[mode] ?? "mode \(mode)"
            if let cadence { texte += ", \(cadence) im/s" }
            if let sequence, sequence > 0 { texte += ", vue \(sequence) de la rafale" }
            lignes.append(Ligne("Mode d'entraînement", texte))
        }
        return lignes
    }

    /// Le bloc Mise au point. `horsDuCadre` : le point est lu, mais hors du cadre actuel de la
    /// photo (recadrage).
    public func lignesMiseAuPoint(horsDuCadre: Bool = false) -> [Ligne] {
        var lignes: [Ligne] = []
        let lus = !pixel.isEmpty && (largeur ?? 0) > 0 && (hauteur ?? 0) > 0
        lignes.append(Ligne("Points de mise au point", lus ? (horsDuCadre ? "lus, hors du cadre actuel" : "lus")
                                                             : (manuelle ? "non lus (mise au point manuelle)" : "non lus")))
        if let mode = modeMiseAuPoint2.flatMap({ Self.modes2[$0] }) ?? modeMiseAuPoint.flatMap({ Self.modes[$0] }) {
            lignes.append(Ligne("Mode de mise au point", mode))
        }
        if modeMiseAuPoint2 == 1, let priorite = prioriteAFS.flatMap({ Self.prioritesTextes[$0] }) {
            lignes.append(Ligne("Priorité AF-S", priorite))
        } else if modeMiseAuPoint2 == 2, let priorite = prioriteAFC.flatMap({ Self.prioritesTextes[$0] }) {
            lignes.append(Ligne("Priorité AF-C", priorite))
        }
        if !manuelle, let zone, let texte = Self.zones[zone] {
            lignes.append(Ligne("Mode AF", texte))
            if zone == "point", let taillePoint {
                lignes.append(Ligne("Taille du point AF", "\(taillePoint)"))
            } else if zone == "zone", let tailleZone {
                lignes.append(Ligne("Taille de la zone AF", "\(tailleZone.largeur) × \(tailleZone.hauteur)"))
            }
        }
        if let avertissement {
            lignes.append(Ligne("Avertissement de mise au point", Self.avertissements[avertissement] ?? "code \(avertissement)"))
        }
        if let visages {
            lignes.append(Ligne("Visages détectés", visages == 0 ? "aucun" : "\(visages)"))
        }
        if !typesElements.isEmpty {
            lignes.append(Ligne("Éléments du sujet détectés", typesElements.map(Self.nomElement).joined(separator: ", ")))
        }
        return lignes
    }

    /// Les valeurs lues sous les noms et numéros d'exiftool (`mcp-developpeur --boitier`), à
    /// comparer à `exiftool -a -G1 -s`.
    public var valeursLues: [String: JSONValue] {
        var valeurs: [String: JSONValue] = [:]
        func nombre(_ nom: String, _ valeur: Int?) {
            if let valeur { valeurs[nom] = .number(Double(valeur)) }
        }
        func nombres(_ nom: String, _ liste: [Int]) {
            if !liste.isEmpty { valeurs[nom] = .array(liste.map { .number(Double($0)) }) }
        }
        nombre("ExifImageWidth (0xA002)", largeur)
        nombre("ExifImageHeight (0xA003)", hauteur)
        nombres("FocusPixel (0x1023)", pixel)
        nombre("FocusMode (0x1021)", modeMiseAuPoint)
        nombre("AFMode (0x1022)", modeAF)
        nombre("AF-SPriority (0x102b)", prioriteAFS)
        nombre("AF-CPriority (0x102b)", prioriteAFC)
        nombre("FocusMode2 (0x102d)", modeMiseAuPoint2)
        nombre("PreAF (0x102d)", preAF)
        nombre("AFAreaMode (0x102d)", modeZone)
        nombre("AFAreaPointSize (0x102d)", taillePoint)
        if let tailleZone { valeurs["AFAreaZoneSize (0x102d)"] = .string("\(tailleZone.largeur) x \(tailleZone.hauteur)") }
        nombre("CropMode (0x104d)", recadrage)
        nombre("SequenceNumber (0x1101)", sequence)
        nombre("DriveMode (0x1103)", modeEntrainement)
        nombre("DriveSpeed (0x1103, im/s)", cadence)
        nombre("FocusWarning (0x1301)", avertissement)
        nombres("ImageStabilization (0x1422)", stabilisation)
        nombre("FacesDetected (0x4100)", visages)
        nombres("FacePositions (0x4103)", positionsVisages)
        nombres("FaceElementTypes (0x4201)", typesElements)
        nombres("FaceElementPositions (0x4203)", positionsElements)
        return valeurs
    }

    // MARK: Cadres

    /// Un cadre dans le repère des positions (pixels du JPEG incorporé) : gauche, haut, droite, bas.
    struct Rectangle: Equatable {
        var gauche, haut, droite, bas: Double
    }

    /// Le cadre de la mise au point, à sa taille d'après le mode AF, autour de FocusPixel ; nil sans
    /// point.
    var cadreAF: Rectangle? {
        guard pixel.count == 2, let largeur, let hauteur, largeur > 0, hauteur > 0 else { return nil }
        let (l, h) = Focus.tailleCadreAF(self, largeur: Double(largeur), hauteur: Double(hauteur))
        let x = Double(pixel[0]), y = Double(pixel[1])
        return Rectangle(gauche: x - l / 2, haut: y - h / 2, droite: x + l / 2, bas: y + h / 2)
    }

    /// Les visages et les éléments du sujet, chacun avec son nom ; un visage dont le cadre est déjà
    /// celui d'un élément (la tête, chez le X-H2S) n'est pas repris.
    var cadresSujet: [(nom: String, cadre: Rectangle)] {
        func rectangles(_ liste: [Int]) -> [Rectangle] {
            stride(from: 0, to: liste.count - 3, by: 4).map {
                Rectangle(gauche: Double(liste[$0]), haut: Double(liste[$0 + 1]), droite: Double(liste[$0 + 2]), bas: Double(liste[$0 + 3]))
            }
        }
        let elements = rectangles(positionsElements).enumerated().map { (k, r) in
            (nom: k < typesElements.count ? Self.nomElement(typesElements[k]) : "élément", cadre: r)
        }
        let visages = rectangles(positionsVisages).prefix(max(0, visages ?? Int.max))
            .filter { r in !elements.contains { $0.cadre == r } }
            .map { (nom: "visage", cadre: $0) }
        return Array(visages) + elements
    }
}

/// L'onglet Focus de la fenêtre Claude : les cadres de la mise au point dessinés sur la vignette de
/// la photo active, et ce que l'appareil en dit, en une ligne JSON (`mcp-developpeur --focus`).
/// Le cadre AF à sa taille d'après le mode AF, en rouge ; les visages et les éléments du sujet en
/// coins jaunes, comme Focus-Points. L'aperçu de la photo active des autres onglets et le carré de
/// `--marquer-af` ne changent pas.
public enum Focus {
    /// Un cadre dans l'image affichée : ses coins (haut gauche, haut droit, bas droit, bas gauche
    /// du fichier, passés par l'orientation et le cadre de Lightroom), de 0 à 1 depuis le coin haut
    /// gauche de l'image affichée.
    public struct Cadre: Equatable {
        public enum Genre: String { case pointAF = "point_af", sujet }
        public var genre: Genre
        public var nom: String
        public var coins: [CGPoint]
    }

    /// Une case de la grille AF de l'appareil : 1/13 du grand côté, carrée (la grille de 117
    /// points, 13 × 9, du X-H2S et des X-Trans récents ; ses cases font 340 × 327 pixels dans le
    /// repère de 4 416 × 2 944). Une zone de 5 × 5 en couvre 5 × 5. Provisoire : la grille d'un
    /// boîtier plus ancien (91 points en 13 × 7) n'est pas relevée.
    static let colonnesGrille = 13.0
    /// Le carré d'un point unique, d'un mode large / suivi ou d'un point sans taille lue : 4 % du
    /// petit côté, la taille « Medium » par défaut de Focus-Points (FocusPointPrefs.focusBoxSize,
    /// DefaultPointRenderer.createFocusFrame), la référence de Dany. Constaté le 22 octobre 2026 sur
    /// DSCF2402 : le modèle d'avant (taille n = n/6 d'une case de la grille) dessinait la taille 6
    /// trois fois plus grande que Focus-Points, presque la taille du visage. La taille lue reste
    /// dite dans la carte (« Taille du point AF »).
    static let carreParDefaut = 0.04

    /// Largeur et hauteur du cadre AF, en pixels du repère.
    static func tailleCadreAF(_ m: MiseAuPointBoitier, largeur: Double, hauteur: Double) -> (Double, Double) {
        let caseAF = max(largeur, hauteur) / colonnesGrille
        if m.zone == "zone", let zone = m.tailleZone {
            return (caseAF * Double(zone.largeur), caseAF * Double(zone.hauteur))
        }
        let cote = carreParDefaut * min(largeur, hauteur)
        return (cote, cote)
    }

    /// Les cadres dans l'image affichée (le point AF d'abord), sans ceux qui tombent entièrement
    /// hors du cadre ; et si le point AF y tombe.
    public static func cadres(_ m: MiseAuPointBoitier, geometrie g: GeometriePhoto) -> (cadres: [Cadre], pointDansLeCadre: Bool?) {
        guard let largeur = m.largeur, let hauteur = m.hauteur, largeur > 0, hauteur > 0 else { return ([], nil) }
        let lf = Double(largeur), hf = Double(hauteur)
        func coins(_ r: MiseAuPointBoitier.Rectangle) -> [CGPoint] {
            [(r.gauche, r.haut), (r.droite, r.haut), (r.droite, r.bas), (r.gauche, r.bas)].map { g.versApercu(x: $0.0 / lf, y: $0.1 / hf) }
        }
        func visible(_ points: [CGPoint]) -> Bool {
            let xs = points.map(\.x), ys = points.map(\.y)
            return (xs.max() ?? -1) > 0 && (xs.min() ?? 2) < 1 && (ys.max() ?? -1) > 0 && (ys.min() ?? 2) < 1
        }
        var cadres: [Cadre] = []
        var dansLeCadre: Bool?
        if let r = m.cadreAF {
            let centre = g.versApercu(x: Double(m.pixel[0]) / lf, y: Double(m.pixel[1]) / hf)
            dansLeCadre = (0...1).contains(centre.x) && (0...1).contains(centre.y)
            let c = coins(r)
            if visible(c) { cadres.append(Cadre(genre: .pointAF, nom: "point AF", coins: c)) }
        }
        for sujet in m.cadresSujet {
            let c = coins(sujet.cadre)
            if visible(c) { cadres.append(Cadre(genre: .sujet, nom: sujet.nom, coins: c)) }
        }
        return (cadres, dansLeCadre)
    }

    /// Ce que l'onglet Focus montre d'un original Fujifilm (`mcp-developpeur --focus`) : la vignette
    /// `entree` (dans l'image affichée et recadrée, `geometrie` comme Vignettes.decrireVignette la
    /// décrit) avec ses cadres, écrite dans `sortie`, et une ligne JSON : `lue`, les lignes des
    /// blocs `image`, `prise_de_vue` et `mise_au_point` (paires titre, valeur, en français),
    /// `point_af` (x, y dans l'image affichée, `dans_le_cadre`), `cadres` (point AF et sujets
    /// dessinés) et `dessinee` (la vignette écrite). Nil : pas un fichier Fujifilm, rien de lu,
    /// original qui ne s'ouvre pas à temps. Une géométrie ou une vignette illisible donne les
    /// valeurs sans dessin.
    public static func marquer(original: URL, geometrie: JSONValue?, entree: URL, sortie: URL,
                               lecteur: LecteurBoitier = LecteurBoitier()) -> JSONValue? {
        guard let lecture = lecteur.lire(original) else { return nil }
        let m = lecture.miseAuPoint ?? MiseAuPointBoitier()
        var json: [String: JSONValue] = ["lue": true]
        var dessinee = false
        var horsDuCadre = false
        if let g = GeometriePhoto(geometrie) {
            let (cadres, dansLeCadre) = Self.cadres(m, geometrie: g)
            horsDuCadre = dansLeCadre == false
            if let r = m.cadreAF, let largeur = m.largeur, let hauteur = m.hauteur {
                let centre = g.versApercu(x: (r.gauche + r.droite) / 2 / Double(largeur), y: (r.haut + r.bas) / 2 / Double(hauteur))
                json["point_af"] = ["x": .number((Double(centre.x) * 1000).rounded() / 1000), "y": .number((Double(centre.y) * 1000).rounded() / 1000),
                                    "dans_le_cadre": .bool(dansLeCadre == true)]
            }
            json["cadres"] = ["point_af": .number(Double(cadres.filter { $0.genre == .pointAF }.count)),
                              "sujets": .number(Double(cadres.filter { $0.genre == .sujet }.count))]
            if let donnees = try? Data(contentsOf: entree), let image = PreviewImages.image(donnees),
               let marquee = PreviewImages.marquerFocus(image, cadres: cadres), (try? marquee.write(to: sortie)) != nil {
                dessinee = true
            }
        }
        func lignes(_ liste: [MiseAuPointBoitier.Ligne]) -> JSONValue {
            .array(liste.map { .array([.string($0.titre), .string($0.valeur)]) })
        }
        json["image"] = lignes(m.lignesImage)
        json["prise_de_vue"] = lignes(m.lignesPriseDeVue)
        json["mise_au_point"] = lignes(m.lignesMiseAuPoint(horsDuCadre: horsDuCadre))
        json["dessinee"] = .bool(dessinee)
        return .object(json)
    }

    /// La ligne JSON de `mcp-developpeur --focus` : celle de `marquer`, sinon `{"lue": false,
    /// "raison": …}` (code 1), pour que la carte Focus dise pourquoi rien n'est lu (`nonLue`).
    public static func lire(original: URL, geometrie: JSONValue?, entree: URL, sortie: URL,
                            lecteur: LecteurBoitier = LecteurBoitier()) -> JSONValue {
        marquer(original: original, geometrie: geometrie, entree: entree, sortie: sortie, lecteur: lecteur)
            ?? nonLue(original: original, lecteur: lecteur)
    }

    /// Pourquoi rien n'est lu, après la lecture de `lecteur` : « delai » (l'original ne s'est pas
    /// ouvert à temps : il n'est plus touché), « introuvable » (pas de fichier à ce chemin), sinon
    /// « illisible » (ouvert à temps, sans rien que `LectureBoitier` sache lire : un HEIF de
    /// l'appareil, un fichier sans la MakerNote de Fujifilm).
    public static func nonLue(original: URL, lecteur: LecteurBoitier) -> JSONValue {
        let raison: String
        if lecteur.bloque != nil {
            raison = "delai"
        } else if !FileManager.default.fileExists(atPath: original.path) {
            raison = "introuvable"
        } else {
            raison = "illisible"
        }
        return ["lue": false, "raison": .string(raison)]
    }
}

extension PreviewImages {
    /// L'image avec les cadres de l'onglet Focus (Focus.cadres) : le cadre AF en rouge, à sa
    /// taille, avec un point au centre ; les visages et les éléments du sujet en coins jaunes (un
    /// quart de chaque côté), comme Focus-Points ; un liseré sombre sous chaque trait le garde
    /// visible sur un fond clair. Épaisseur proportionnelle au grand côté (`traitFocusPart`), pour
    /// rester lisible réduite dans l'aperçu de la fenêtre (498 points) ; un cadre minuscule (point
    /// AF de taille 1) garde au moins `coteMinFocus` pixels.
    public static func marquerFocus(_ source: CGImage, cadres: [Focus.Cadre]) -> Data? {
        let image = scaled(source, maxSide: maxSide)
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let grand = Double(max(width, height))
        let trait = max(2, grand * traitFocusPart)
        // Le repère de CoreGraphics part du bas.
        func points(_ cadre: Focus.Cadre) -> [CGPoint] {
            var p = cadre.coins.map { CGPoint(x: Double($0.x) * Double(width), y: (1 - Double($0.y)) * Double(height)) }
            // Un cadre trop petit pour se voir grandit autour de son centre.
            let cx = p.map { Double($0.x) }.reduce(0, +) / 4, cy = p.map { Double($0.y) }.reduce(0, +) / 4
            let cote = max(hypot(Double(p[1].x - p[0].x), Double(p[1].y - p[0].y)), hypot(Double(p[3].x - p[0].x), Double(p[3].y - p[0].y)))
            if cote > 0, cote < coteMinFocus {
                let k = coteMinFocus / cote
                p = p.map { CGPoint(x: cx + (Double($0.x) - cx) * k, y: cy + (Double($0.y) - cy) * k) }
            }
            return p
        }
        func entre(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: Double(a.x) + (Double(b.x) - Double(a.x)) * t, y: Double(a.y) + (Double(b.y) - Double(a.y)) * t)
        }
        func tracer(_ chemins: [[CGPoint]], couleur: CGColor, fermes: Bool) {
            for (largeur, teinte) in [(trait + 2, CGColor(red: 0, green: 0, blue: 0, alpha: 0.6)), (trait, couleur)] {
                context.setStrokeColor(teinte)
                context.setLineWidth(largeur)
                for chemin in chemins {
                    context.addLines(between: chemin)
                    if fermes { context.closePath() }
                }
                context.strokePath()
            }
        }
        context.setLineJoin(.miter)
        context.setLineCap(.square)
        // Les sujets d'abord : le cadre AF reste dessus.
        let jaune = CGColor(red: 1, green: 0.84, blue: 0.1, alpha: 1)
        for cadre in cadres where cadre.genre == .sujet {
            let p = points(cadre)
            let coins = (0..<4).map { k in [entre(p[k], p[(k + 3) % 4], 0.25), p[k], entre(p[k], p[(k + 1) % 4], 0.25)] }
            tracer(coins, couleur: jaune, fermes: false)
        }
        let rouge = CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
        for cadre in cadres where cadre.genre == .pointAF {
            let p = points(cadre)
            tracer([p], couleur: rouge, fermes: true)
            let cx = p.map { Double($0.x) }.reduce(0, +) / 4, cy = p.map { Double($0.y) }.reduce(0, +) / 4
            let r = trait * 1.2
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
            context.fillEllipse(in: CGRect(x: cx - r - 1, y: cy - r - 1, width: 2 * r + 2, height: 2 * r + 2))
            context.setFillColor(rouge)
            context.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        guard let dessinee = context.makeImage() else { return nil }
        return jpeg(dessinee)
    }

    /// Épaisseur des cadres de l'onglet Focus, en part du grand côté (0,3 % : 3 pixels sur la
    /// vignette de 1 024, environ 1,5 point dans l'aperçu de 498). À juger à l'écran.
    static let traitFocusPart = 0.003
    /// Côté minimal d'un cadre dessiné, en pixels de l'image dessinée.
    static let coteMinFocus = 12.0
}
