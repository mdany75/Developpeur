import CoreGraphics
import Foundation

/// Point de mise au point d'une photo Fujifilm, lu dans la MakerNote de son fichier (RAF, ou JPEG
/// de l'appareil), comme le module Focus Points de Lightroom le lit par exiftool. ImageIO ne
/// donne pas la MakerNote de Fujifilm (constaté sous macOS 26 sur un RAF de X-H2S) : le serveur la
/// lit lui-même, en lecture seule.
///
/// Relevé sur un RAF de X-H2S (exiftool 13.55, du module Focus Points) :
/// - en-tête « FUJIFILMCCD-RAW », position du JPEG incorporé à l'octet 84 et sa longueur à 88
///   (grand-boutiste) ; le JPEG porte l'Exif de la photo, MakerNote comprise (tag 0x927C) ;
/// - MakerNote : « FUJIFILM », puis la position de son IFD (petit-boutiste, depuis le début de la
///   MakerNote), entrées petit-boutistes, valeurs repérées depuis le début de la MakerNote ;
/// - FocusPixel (0x1023, deux entiers : x y) dans le repère du JPEG incorporé, dont l'Exif donne
///   les dimensions (ExifImageWidth et ExifImageHeight, 0xA002 et 0xA003 : 4416 × 2944 pour
///   « 2488 1052 ») ; FocusWarning (0x1301) : 0 net, 1 « Out of focus » ; FacesDetected (0x4100).
/// Ce repère est celui du fichier avant l'orientation, comme celui de Lightroom (Geometrie.lua).
/// Lecture des points AF d'une série, bornée dans le temps. Constaté en 2.3 : le serveur lancé par
/// Claude Desktop ouvrait un original du volume externe « Photos » et open() attendait que
/// l'utilisateur réponde à la demande d'autorisation de macOS (accès aux fichiers d'un volume) :
/// tout le tri restait à « 0 sur 130 », et la file des outils derrière lui. Un original qui ne
/// s'ouvre pas dans le délai est sauté, et les suivants de la série aussi (le fil bloqué reste
/// bloqué jusqu'à la réponse ; un seul par série).
public final class LecteurPointsAF {
    let delai: TimeInterval
    let lecture: (URL) -> PointAF?
    private let verrou = NSLock()
    private var bloqueSur: URL?

    public init(delai: TimeInterval = 2, lecture: @escaping (URL) -> PointAF? = PointAF.lire) {
        self.delai = delai
        self.lecture = lecture
    }

    /// Le premier original qui ne s'est pas ouvert à temps, s'il y en a un.
    public var bloque: URL? {
        verrou.lock(); defer { verrou.unlock() }
        return bloqueSur
    }

    public func lire(_ fichier: URL) -> PointAF? {
        if bloque != nil { return nil }
        final class Boite: @unchecked Sendable {
            let verrou = NSLock()
            var point: PointAF?
        }
        let boite = Boite()
        let fini = DispatchSemaphore(value: 0)
        let lecture = self.lecture
        DispatchQueue.global(qos: .utility).async {
            let point = lecture(fichier)
            boite.verrou.lock(); boite.point = point; boite.verrou.unlock()
            fini.signal()
        }
        guard fini.wait(timeout: .now() + delai) == .success else {
            verrou.lock()
            if bloqueSur == nil { bloqueSur = fichier }
            verrou.unlock()
            return nil
        }
        boite.verrou.lock(); defer { boite.verrou.unlock() }
        return boite.point
    }
}

public struct PointAF: Equatable {
    /// Position dans le fichier entier, avant l'orientation, de 0 à 1.
    public var x: Double
    public var y: Double
    /// L'appareil a signalé une mise au point manquée (FocusWarning).
    public var avertissement: Bool
    /// Visages que l'appareil a détectés, s'il le dit.
    public var visages: Int?

    /// Octets lus au début du JPEG incorporé (l'Exif tient dans les 64 premiers Ko).
    static let tailleLue = 131_072

    /// Point de mise au point du fichier, ou nil (autre marque, fichier illisible, absent).
    public static func lire(fichier: URL) -> PointAF? {
        guard let handle = try? FileHandle(forReadingFrom: fichier) else { return nil }
        defer { try? handle.close() }
        guard let debut = try? handle.read(upToCount: 96), debut.count >= 92 else { return nil }
        if debut.starts(with: Data("FUJIFILMCCD-RAW".utf8)) {
            let position = Int(lireEntier(debut, 84, 4, petit: false) ?? 0)
            guard position > 0, (try? handle.seek(toOffset: UInt64(position))) != nil,
                  let jpeg = try? handle.read(upToCount: tailleLue) else { return nil }
            return analyser(jpeg: jpeg)
        }
        guard debut.starts(with: [0xFF, 0xD8]), (try? handle.seek(toOffset: 0)) != nil,
              let jpeg = try? handle.read(upToCount: tailleLue) else { return nil }
        return analyser(jpeg: jpeg)
    }

    /// Le point d'après le début d'un JPEG qui porte l'Exif de l'appareil.
    static func analyser(jpeg: Data) -> PointAF? {
        guard let tiff = segmentExif(jpeg), let exif = Tiff(tiff) else { return nil }
        guard let ifd0 = exif.ifd(at: exif.premierIFD),
              let pointeur = ifd0[0x8769]?.entier, let exifIFD = exif.ifd(at: Int(pointeur)) else { return nil }
        guard let largeur = exifIFD[0xA002]?.entier, let hauteur = exifIFD[0xA003]?.entier, largeur > 0, hauteur > 0,
              let note = exifIFD[0x927C], note.position + 12 <= tiff.count else { return nil }
        let debutNote = note.position
        guard tiff.subdata(in: debutNote..<(debutNote + 8)) == Data("FUJIFILM".utf8),
              let decalage = lireEntier(tiff, debutNote + 8, 4, petit: true) else { return nil }
        let fuji = Tiff(donnees: tiff.subdata(in: debutNote..<tiff.count), petit: true)
        guard let ifd = fuji.ifd(at: Int(decalage)), let point = ifd[0x1023]?.entiers(2), point.count == 2 else { return nil }
        // (0, 0) : pas de point rangé (mise au point manuelle, supposé).
        guard point[0] > 0 || point[1] > 0 else { return nil }
        return PointAF(x: min(max(Double(point[0]) / Double(largeur), 0), 1),
                       y: min(max(Double(point[1]) / Double(hauteur), 0), 1),
                       avertissement: (ifd[0x1301]?.entier ?? 0) != 0,
                       visages: ifd[0x4100]?.entier.map(Int.init))
    }

    /// Le contenu TIFF du segment APP1 « Exif » d'un JPEG.
    static func segmentExif(_ jpeg: Data) -> Data? {
        let octets = [UInt8](jpeg)
        guard octets.count > 4, octets[0] == 0xFF, octets[1] == 0xD8 else { return nil }
        var i = 2
        while i + 4 <= octets.count, octets[i] == 0xFF {
            let marqueur = octets[i + 1]
            let longueur = Int(octets[i + 2]) << 8 | Int(octets[i + 3])
            guard longueur >= 2 else { return nil }
            if marqueur == 0xE1, i + 10 <= octets.count, Array(octets[(i + 4)..<(i + 10)]) == [0x45, 0x78, 0x69, 0x66, 0, 0] {
                let fin = min(i + 2 + longueur, octets.count)
                guard i + 10 < fin else { return nil }
                return Data(octets[(i + 10)..<fin])
            }
            if marqueur == 0xDA { return nil }   // début de l'image : pas d'Exif avant
            i += 2 + longueur
        }
        return nil
    }

    static func lireEntier(_ d: Data, _ position: Int, _ taille: Int, petit: Bool) -> UInt32? {
        guard position >= 0, position + taille <= d.count else { return nil }
        var valeur: UInt32 = 0
        for k in 0..<taille {
            let octet = UInt32(d[d.startIndex + position + (petit ? taille - 1 - k : k)])
            valeur = valeur << 8 | octet
        }
        return valeur
    }

    /// Un fichier TIFF (ou une MakerNote de même forme) : ses IFD, entrée par entrée.
    struct Tiff {
        struct Entree {
            var type: Int
            var nombre: Int
            /// Position de la valeur dans les données (dans l'entrée même si elle tient en 4 octets).
            var position: Int
            let tiff: Tiff

            var entier: UInt32? { entiers(1).first.map(UInt32.init) }

            func entiers(_ combien: Int) -> [Int] {
                let taille = type == 3 ? 2 : (type == 4 ? 4 : (type == 1 || type == 7 ? 1 : 0))
                guard taille > 0 else { return [] }
                return (0..<min(combien, nombre)).compactMap { k in
                    lireEntier(tiff.donnees, position + k * taille, taille, petit: tiff.petit).map(Int.init)
                }
            }
        }

        let donnees: Data
        let petit: Bool

        init(donnees: Data, petit: Bool) {
            self.donnees = donnees
            self.petit = petit
        }

        init?(_ donnees: Data) {
            guard donnees.count >= 8 else { return nil }
            let entete = [UInt8](donnees.prefix(4))
            if entete == [0x49, 0x49, 0x2A, 0x00] { petit = true }
            else if entete == [0x4D, 0x4D, 0x00, 0x2A] { petit = false }
            else { return nil }
            self.donnees = donnees
        }

        var premierIFD: Int { Int(lireEntier(donnees, 4, 4, petit: petit) ?? 0) }

        func ifd(at position: Int) -> [Int: Entree]? {
            guard position > 0, let nombre = lireEntier(donnees, position, 2, petit: petit), nombre < 1000 else { return nil }
            var entrees: [Int: Entree] = [:]
            for k in 0..<Int(nombre) {
                let p = position + 2 + 12 * k
                guard let tag = lireEntier(donnees, p, 2, petit: petit), let type = lireEntier(donnees, p + 2, 2, petit: petit),
                      let compte = lireEntier(donnees, p + 4, 4, petit: petit) else { break }
                let taille = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8][Int(type)] ?? 1
                let enLigne = Int(compte) * taille <= 4
                let valeur = enLigne ? p + 8 : Int(lireEntier(donnees, p + 8, 4, petit: petit) ?? 0)
                entrees[Int(tag)] = Entree(type: Int(type), nombre: Int(compte), position: valeur, tiff: self)
            }
            return entrees
        }
    }
}

/// Ce que le module dit de la géométrie d'une photo (commande vignettes) : dimensions affichées
/// non recadrées, orientation de Lightroom, cadre (absent : le fichier entier).
public struct GeometriePhoto: Equatable {
    public var largeur: Double
    public var hauteur: Double
    public var orientation: String
    public var cadre: (gauche: Double, haut: Double, droite: Double, bas: Double, angle: Double)?

    public static func == (a: GeometriePhoto, b: GeometriePhoto) -> Bool {
        a.largeur == b.largeur && a.hauteur == b.hauteur && a.orientation == b.orientation
            && a.cadre?.gauche == b.cadre?.gauche && a.cadre?.haut == b.cadre?.haut && a.cadre?.droite == b.cadre?.droite
            && a.cadre?.bas == b.cadre?.bas && a.cadre?.angle == b.cadre?.angle
    }

    public init(largeur: Double, hauteur: Double, orientation: String,
                cadre: (gauche: Double, haut: Double, droite: Double, bas: Double, angle: Double)? = nil) {
        self.largeur = largeur
        self.hauteur = hauteur
        self.orientation = orientation
        self.cadre = cadre
    }

    init?(_ json: JSONValue?) {
        guard let json, let largeur = json["largeur"]?.double, let hauteur = json["hauteur"]?.double, largeur > 0, hauteur > 0 else { return nil }
        self.largeur = largeur
        self.hauteur = hauteur
        orientation = json["orientation"]?.string ?? "AB"
        if let c = json["cadre"], c.object != nil {
            cadre = (c["CropLeft"]?.double ?? 0, c["CropTop"]?.double ?? 0, c["CropRight"]?.double ?? 1,
                     c["CropBottom"]?.double ?? 1, c["CropAngle"]?.double ?? 0)
        }
    }

    var tournee: Bool { orientation == "BC" || orientation == "DA" }

    /// Point du fichier (avant l'orientation, de 0 à 1) → point de l'image affichée, recadrée
    /// (de 0 à 1 depuis le coin haut gauche ; hors de 0…1 : hors du cadre). L'inverse exact de
    /// `Geometrie.point` du module, sans la grille de recalage (le point de l'appareil n'a pas de
    /// correction d'objectif à suivre).
    public func versApercu(x: Double, y: Double) -> CGPoint {
        let (lf, hf) = tournee ? (hauteur, largeur) : (largeur, hauteur)
        let c = cadre ?? (0, 0, 1, 1, 0)
        let r = c.angle * .pi / 180
        let dx = (c.droite - c.gauche) * lf, dy = (c.bas - c.haut) * hf
        let w = dx * cos(r) + dy * sin(r)
        let h = -dx * sin(r) + dy * cos(r)
        let ex = x * lf - c.gauche * lf, ey = y * hf - c.haut * hf
        let s = (ex * cos(r) + ey * sin(r)) / w
        let t = (-ex * sin(r) + ey * cos(r)) / h
        switch orientation {
        case "BC": return CGPoint(x: 1 - t, y: s)
        case "CD": return CGPoint(x: 1 - s, y: 1 - t)
        case "DA": return CGPoint(x: t, y: 1 - s)
        default: return CGPoint(x: s, y: t)
        }
    }
}
