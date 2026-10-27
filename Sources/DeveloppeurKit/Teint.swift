import CoreGraphics
import Foundation
import Vision

/// Le témoin du teint (1.4, « Harmoniser par lumière ») : la peau du plus grand visage d'une photo,
/// lue sur le visage pris à la pleine résolution de l'aperçu de mesure (le zoom du visage, sans
/// autre rendu), comparée à celle de la photo de référence avant et après l'harmonisation
/// (`match_series`). Un témoin, pas la mesure de la balance : deux personnes n'ont pas la même
/// peau, et les tons neutres décident la correction. Il ne fait que dire quand la correction
/// éloigne nettement la peau de celle de la référence (`alerte`), à vérifier à l'œil. Seuils
/// provisoires, choisis hors de Lightroom, à relever sur la sortie de l'essai de la 1.4.
public enum Teint {
    /// La peau lue : médianes de L*, a* et b*, et les pixels lus.
    public struct Mesure: Equatable {
        public var l: Double
        public var a: Double
        public var b: Double
        public var pixels: Int

        public init(l: Double, a: Double, b: Double, pixels: Int) {
            self.l = l
            self.a = a
            self.b = b
            self.pixels = pixels
        }

        /// Angle de teinte en degrés (a* vers b*) : une peau va d'environ 30° (rosée) à 70° (dorée).
        public var teinte: Double { atan2(b, a) * 180 / .pi }
    }

    /// Largeur minimale du visage lu, en part de la largeur de l'image (celle de l'éclairage).
    public static let visageMin = Eclairage.visageMin
    /// Pixels de peau au moins (le visage pris à 1 024 px en a des centaines dès 4 % de largeur).
    public static let pixelsMin = 60
    /// Écart a*b* de la peau avec celle de la référence qui se voit (provisoire).
    public static let ecartVisible = 5.0
    /// Hausse de cet écart par l'harmonisation qui fait vérifier (provisoire).
    public static let hausseAlerte = 2.0

    /// Le milieu du visage, sans les yeux ni le menton : les joues et le nez (comme l'éclairage).
    static func interieur(_ visage: CGRect) -> CGRect {
        CGRect(x: visage.minX + 0.25 * visage.width, y: visage.minY + 0.45 * visage.height,
               width: 0.5 * visage.width, height: 0.4 * visage.height)
    }

    /// Les visages que Vision voit (cadres en fractions, depuis le haut gauche), du plus large au
    /// plus petit, sans ceux à l'envers (`Composition.visagePlausible`).
    public static func visages(_ image: CGImage) -> [CGRect] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let requete = VNDetectFaceRectanglesRequest()
        guard (try? handler.perform([requete])) != nil else { return [] }
        return (requete.results ?? [])
            .map { visage in
                VisionReport.Face(box: CGRect(x: visage.boundingBox.minX, y: 1 - visage.boundingBox.maxY,
                                              width: visage.boundingBox.width, height: visage.boundingBox.height),
                                  pupils: [], eyeWidth: nil, quality: nil, eyeOpenness: nil,
                                  yaw: visage.yaw.map { Double(truncating: $0) }, roll: visage.roll.map { Double(truncating: $0) })
            }
            .filter(Composition.visagePlausible)
            .map(\.box)
            .sorted { $0.width > $1.width }
    }

    /// La peau du plus grand visage assez large de `visages` (fractions, depuis le haut gauche),
    /// lue dans `image` sans la réduire : seulement le milieu du visage, pris à part. Peau : les
    /// bornes de l'éclairage (`Eclairage.peauLumineux`, `peauChroma`), pixels non écrêtés. Nil sans
    /// visage assez large ou sans assez de peau.
    public static func mesurer(_ image: CGImage, visages: [CGRect]) -> Mesure? {
        guard let visage = visages.filter({ Double($0.width) >= visageMin && Eclairage.fini($0) }).max(by: { $0.width < $1.width })
        else { return nil }
        let zone = interieur(visage)
        let largeur = Double(image.width), hauteur = Double(image.height)
        let pixels = CGRect(x: (zone.minX * largeur).rounded(.down), y: (zone.minY * hauteur).rounded(.down),
                            width: (zone.width * largeur).rounded(.up), height: (zone.height * hauteur).rounded(.up))
            .intersection(CGRect(x: 0, y: 0, width: largeur, height: hauteur))
        guard !pixels.isNull, pixels.width >= 2, pixels.height >= 2, let zoom = image.cropping(to: pixels),
              let rgba = Measurements.rgba(zoom) else { return nil }
        var ls: [Double] = [], as_: [Double] = [], bs: [Double] = []
        for i in 0..<(zoom.width * zoom.height) {
            let rouge = rgba[i * 4], vert = rgba[i * 4 + 1], bleu = rgba[i * 4 + 2]
            guard max(rouge, vert, bleu) < Eclairage.composanteMax else { continue }
            let lab = Measurements.lab(rouge, vert, bleu)
            let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            guard Eclairage.peauLumineux.contains(lab.l), Eclairage.peauChroma.contains(chroma) else { continue }
            ls.append(lab.l); as_.append(lab.a); bs.append(lab.b)
        }
        guard ls.count >= pixelsMin else { return nil }
        return Mesure(l: Eclairage.mediane(ls), a: Eclairage.mediane(as_), b: Eclairage.mediane(bs), pixels: ls.count)
    }

    /// La peau d'une image : ses visages par Vision, puis `mesurer`.
    public static func lire(_ image: CGImage) -> Mesure? {
        mesurer(image, visages: visages(image))
    }

    /// Écart a*b* entre deux peaux.
    public static func ecart(_ peau: Mesure, _ reference: Mesure) -> Double {
        hypot(peau.a - reference.a, peau.b - reference.b)
    }

    /// L'harmonisation éloigne-t-elle la peau de celle de la référence ? Seulement si l'écart, après,
    /// se voit (`ecartVisible`) et a grandi d'au moins `hausseAlerte`.
    public static func alerte(avant: Double, apres: Double) -> Bool {
        apres >= ecartVisible && apres - avant >= hausseAlerte
    }

    /// Le témoin d'une photo, pour le résultat de `match_series` : la peau de la référence et
    /// l'écart avant et après (`apres` nil : plan seulement), et ce qu'il faut vérifier.
    static func json(reference: Mesure?, avant: Mesure?, apres: Mesure?) -> JSONValue? {
        guard let reference else { return nil }
        guard let avant else {
            return ["lu": false, "pourquoi": "pas de visage assez grand pour lire la peau sur cette photo"]
        }
        func r(_ valeur: Double) -> JSONValue { .number((valeur * 10).rounded() / 10) }
        let ecartAvant = ecart(avant, reference)
        var objet: [String: JSONValue] = ["ecart_avant": r(ecartAvant), "teinte_avant_deg": .number(avant.teinte.rounded())]
        if let apres {
            let ecartApres = ecart(apres, reference)
            objet["ecart_apres"] = r(ecartApres)
            objet["teinte_apres_deg"] = .number(apres.teinte.rounded())
            if alerte(avant: ecartAvant, apres: ecartApres) {
                objet["a_verifier"] = .string("La peau s'éloigne de celle de la référence (écart a*b* de \(PhotoTriee.r(ecartAvant)) à \(PhotoTriee.r(ecartApres))) : si c'est la même personne, ou la même lumière sur la peau, la balance des tons neutres ne lui convient pas. Vérifier à l'œil, view_photo avec region sur le visage.")
            }
        }
        return .object(objet)
    }

    /// La peau de la référence, pour le résultat.
    static func jsonReference(_ peau: Mesure?) -> JSONValue {
        guard let peau else { return ["lu": false, "pourquoi": "pas de visage assez grand sur la référence : pas de témoin du teint"] }
        func r(_ valeur: Double) -> JSONValue { .number((valeur * 10).rounded() / 10) }
        return ["L": r(peau.l), "a": r(peau.a), "b": r(peau.b), "teinte_deg": .number(peau.teinte.rounded())]
    }
}
