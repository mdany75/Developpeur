import CoreGraphics
import Foundation

/// Point de mise au point d'une photo Fujifilm, lu dans la MakerNote de son fichier (RAF, ou JPEG
/// de l'appareil) par LectureBoitier (Boitier.swift), d'une seule ouverture avec l'intention de la
/// prise de vue ; LecteurBoitier borne cette lecture dans le temps.
///
/// Relevé sur un RAF de X-H2S (exiftool 13.55, du module Focus Points) : FocusPixel (0x1023, deux
/// entiers : x y) dans le repère du JPEG incorporé, dont l'Exif donne les dimensions
/// (ExifImageWidth et ExifImageHeight, 0xA002 et 0xA003 : 4416 × 2944 pour « 2488 1052 ») ;
/// FocusWarning (0x1301) : 0 net, 1 « Out of focus » ; FacesDetected (0x4100).
/// Ce repère est celui du fichier avant l'orientation, comme celui de Lightroom (Geometrie.lua).
public struct PointAF: Equatable {
    /// Le point de mise au point de l'original dessiné sur une vignette de la photo (aperçu de la
    /// photo active de la fenêtre Claude, `mcp-developpeur --marquer-af`) : `geometrie` comme la
    /// décrit le module (Vignettes.decrireVignette : dimensions affichées, orientation, cadre), la
    /// vignette dans l'image affichée et recadrée. Écrit `sortie` et rend le point (de 0 à 1 dans
    /// l'image affichée), ou nil : pas un fichier Fujifilm, point illisible ou hors du cadre, original
    /// qui ne s'ouvre pas à temps.
    public static func marquer(original: URL, geometrie: JSONValue, entree: URL, sortie: URL,
                               lecteur: LecteurBoitier = LecteurBoitier()) -> (x: Double, y: Double, avertissement: Bool)? {
        guard let g = GeometriePhoto(geometrie), let lecture = lecteur.lire(original), let af = lecture.point else { return nil }
        let point = g.versApercu(x: af.x, y: af.y)
        guard (0...1).contains(point.x), (0...1).contains(point.y),
              let donnees = try? Data(contentsOf: entree), let image = PreviewImages.image(donnees) else { return nil }
        // Le cadre AF comme l'onglet Focus : rouge, à la taille de Focus-Points, un point au centre
        // (demandé par Dany le 22 octobre 2026, à reprendre dans la prochaine version) ; sans cadre
        // lu, le carré d'avant.
        let cadresAF = lecture.miseAuPoint.map { Focus.cadres($0, geometrie: g).cadres.filter { $0.genre == .pointAF } } ?? []
        guard let marquee = cadresAF.isEmpty ? PreviewImages.marquerPoint(image, point, manque: af.avertissement)
                                             : PreviewImages.marquerFocus(image, cadres: cadresAF),
              (try? marquee.write(to: sortie)) != nil else { return nil }
        return (Double(point.x), Double(point.y), af.avertissement)
    }

    /// Position dans le fichier entier, avant l'orientation, de 0 à 1.
    public var x: Double
    public var y: Double
    /// L'appareil a signalé une mise au point manquée (FocusWarning).
    public var avertissement: Bool
    /// Visages que l'appareil a détectés, s'il le dit.
    public var visages: Int?

    /// Point de mise au point du fichier, ou nil (autre marque, fichier illisible, absent, pas de
    /// point rangé).
    public static func lire(fichier: URL) -> PointAF? {
        LectureBoitier.lire(fichier: fichier)?.point
    }

    /// Le point d'après l'IFD de la MakerNote et les dimensions de l'Exif ; nil sans dimensions ou
    /// sans point rangé.
    static func depuis(note ifd: [Int: LectureBoitier.Tiff.Entree], largeur: UInt32?, hauteur: UInt32?) -> PointAF? {
        guard let largeur, let hauteur, largeur > 0, hauteur > 0,
              let point = ifd[0x1023]?.entiers(2), point.count == 2 else { return nil }
        // (0, 0) : pas de point rangé (mise au point manuelle, supposé).
        guard point[0] > 0 || point[1] > 0 else { return nil }
        return PointAF(x: min(max(Double(point[0]) / Double(largeur), 0), 1),
                       y: min(max(Double(point[1]) / Double(hauteur), 0), 1),
                       avertissement: (ifd[0x1301]?.entier ?? 0) != 0,
                       visages: ifd[0x4100]?.entier.map(Int.init))
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
