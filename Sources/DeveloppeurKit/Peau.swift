import Foundation

/// Le dosage de la peau, d'après Adobe : sa seule copie. La description d'effect d'add_mask (et
/// l'invite portrait) reprend `dosage`, le garde-fou d'add_mask (`maskParameter`) les seuils, et
/// LocalEffectLibrary les effets intégrés ; la fenêtre Claude (Consignes.lua) y renvoie sans chiffres.
///
/// Les doses sont celles qu'Adobe range dans ses fichiers, pas dans son aide, relevées sur ce Mac
/// (Lightroom Classic 15.6, 20 octobre 2026) :
/// - « Peau du visage lisse » (Smooth Facial Skin) : Settings/Premium/Adaptive - Portrait/Smooth
///   Face.xmp, une Correction sur MaskSubType 3, MaskSubCategoryID 2 (la peau du visage de toutes
///   les personnes : person_part face_skin), LocalTexture −0,2 et LocalClarity2012 −0,1. Ce n'est pas
///   un effet local mais un paramètre prédéfini adaptatif : le serveur le fournit en effet intégré.
///   Enhance Portrait a les mêmes valeurs ; Polished Portrait et Glamour −0,25 et −0,1.
/// - « Adoucir la peau (Lite) » (Soften Skin (Lite)) : SoftenSkin(Lite).lrtemplate de
///   localized_presets, texture −0,35 et clarity2012 −0,15 ; intégré en secours si son fichier manque.
/// - « Adoucir la peau » (Soften Skin) : SoftenSkin.lrtemplate, clarity2012 −1 et sharpness +0,25 ;
///   jamais intégré : au-delà de la dose Lite, il ne se pose qu'à la demande (smoothing_requested).
///
/// Vision ne dit ni le genre ni l'âge d'un visage (VNClassifyImageRequest n'a d'étiquettes d'âge que
/// pour l'image entière) : Claude juge à l'œil, et dans le doute prend la dose la plus faible.
public enum Peau {
    /// Une dose de lissage, sur l'échelle des curseurs du panneau Masque, intensité (amount) comprise.
    public struct Dose: Equatable {
        public var texture: Double
        public var clarte: Double
        public var nettete: Double = 0
    }

    /// « Peau du visage lisse » : la dose par défaut.
    public static let parDefaut = Dose(texture: -20, clarte: -10)
    /// « Adoucir la peau (Lite) » : la dose la plus forte que Claude pose sans demande.
    public static let lite = Dose(texture: -35, clarte: -15)
    /// « Adoucir la peau » : pour les textes seulement (son effet vient du fichier de Lightroom).
    static let forte = Dose(texture: 0, clarte: -100, nettete: 25)
    /// Intensité (amount) d'un masque de peau pour un homme ou une personne âgée : la moitié de la
    /// dose. Provisoire, à relever : la linéarité de CorrectionAmount n'est pas encore constatée
    /// (« Peau du visage lisse » à 50 contre texture −10 et clarté −5 à 100, sur une proposition) ;
    /// si elle ne tient pas, la moitié de dose s'écrit en curseurs.
    public static let intensiteReduite = 50.0
    /// Marge des comparaisons : une dose se calcule en virgule flottante (curseur × 0,01, puis
    /// × intensité × 100), et une dose pile à la limite doit passer.
    static let marge = 1e-9

    /// Les effets intégrés, ajoutés par LocalEffectLibrary après ceux des fichiers (qui l'emportent :
    /// sur le Mac de Dany, « Adoucir la peau (Lite) » vient de son .lrtemplate).
    public static let effetsIntegres: [LocalEffect] = [
        LocalEffect(name: "Peau du visage lisse", internalName: "Smooth Facial Skin", locaux: locaux(parDefaut)),
        LocalEffect(name: "Adoucir la peau (Lite)", internalName: "Soften Skin (Lite)", locaux: locaux(lite)),
    ]

    /// Une dose sous les clés d'une correction de masque, à l'échelle de Lightroom (−1 à +1).
    static func locaux(_ dose: Dose) -> [String: Double] {
        var resultat: [String: Double] = [:]
        if dose.texture != 0 { resultat["LocalTexture"] = dose.texture / 100 }
        if dose.clarte != 0 { resultat["LocalClarity2012"] = dose.clarte / 100 }
        if dose.nettete != 0 { resultat["LocalSharpness"] = dose.nettete / 100 }
        return resultat
    }

    /// Les parties d'une personne qui sont de la peau.
    static let parties: Set<String> = ["face_skin", "body_skin"]

    /// Le texte du dosage, tel que Claude le lit (description d'effect d'add_mask, invite portrait).
    public static let dosage = "Peau, dosée comme Adobe, sur person_part face_skin (body_skin seulement si le corps se voit beaucoup) : par défaut effect « Peau du visage lisse » (\(chiffres(parDefaut))) ; « Soften Skin (Lite) » (Adoucir la peau (Lite) : \(chiffres(lite))) pour un gros plan dont un zoom montre des pores marqués ; amount \(nombre(intensiteReduite)) pour un homme ou une personne âgée ; rien pour un enfant. Doses différentes sur une même photo : un masque par personne (kind person, person_at sur son visage, part face_skin). « Soften Skin » (Adoucir la peau : \(chiffres(forte))) seulement si l'utilisateur demande une peau plus lisse ; au-delà de la dose Lite (intensité comprise), smoothing_requested = true, sinon refus. Puis view_photo avec region sur le visage : pores encore visibles, ni cire ni plaques."

    /// La description de smoothing_requested, propriété d'un masque d'add_mask.
    static let demandeDescription = "true = l'utilisateur a demandé une peau plus lisse (dans sa demande ou son guide de style) : « Adoucir la peau », ou plus que la dose « Adoucir la peau (Lite) ». Jamais de toi-même. Sans lui, un masque de la peau (face_skin, body_skin) au-delà de texture \(nombre(lite.texture)) ou clarté \(nombre(lite.clarte)) (intensité comprise), ou à netteté négative, est refusé."

    // MARK: Garde-fou

    /// Vrai si le masque lisse de la peau : son premier composant est la peau (person_part ou person,
    /// part face_skin ou body_skin), non inversé ; ou l'un de ses composants combinés la garde : la
    /// peau ajoutée ou intersectée, non inversée, ou la peau inversée soustraite (A − non B = A ∩ B,
    /// comme Lightroom range une intersection : Locaux.combiner). La peau soustraite, ou inversée puis
    /// ajoutée ou intersectée, la retire ; un masque Sujet ou Personne entière ne compte pas.
    static func surLaPeau(_ masque: [String: JSONValue]) -> Bool {
        func peau(_ zone: [String: JSONValue]) -> Bool {
            ["person_part", "person"].contains(zone["kind"]?.string ?? "") && parties.contains(zone["part"]?.string ?? "")
        }
        if peau(masque) && masque["invert"]?.bool != true { return true }
        return (masque["combine"]?.array ?? []).contains { composant in
            guard let objet = composant.object, peau(objet) else { return false }
            let inverse = objet["invert"]?.bool == true
            switch objet["mode"]?.string {
            case "add", "intersect": return !inverse
            case "subtract": return inverse
            default: return false
            }
        }
    }

    /// La dose d'un masque : ses réglages locaux (échelle de Lightroom) × son intensité (0 à 1),
    /// ramenés sur l'échelle des curseurs.
    static func dose(_ locaux: [String: JSONValue], quantite: Double) -> Dose {
        func valeur(_ cle: String) -> Double { (locaux[cle]?.double ?? 0) * quantite * 100 }
        return Dose(texture: valeur("LocalTexture"), clarte: valeur("LocalClarity2012"), nettete: valeur("LocalSharpness"))
    }

    /// Ce qui dépasse la dose Lite (« texture −50, clarté −100 », les seuls réglages fautifs), ou nil.
    /// La netteté ne descend jamais sous 0 : Adobe ne la baisse dans aucune de ses doses.
    static func depassement(_ dose: Dose) -> String? {
        var fautifs = Dose(texture: 0, clarte: 0)
        if dose.texture < lite.texture - marge { fautifs.texture = dose.texture }
        if dose.clarte < lite.clarte - marge { fautifs.clarte = dose.clarte }
        if dose.nettete < -marge { fautifs.nettete = dose.nettete }
        return fautifs == Dose(texture: 0, clarte: 0) ? nil : chiffres(fautifs)
    }

    /// Vrai si la dose lisse plus que « Peau du visage lisse » (sans dépasser la dose Lite, par exemple).
    static func auDessusDuDefaut(_ dose: Dose) -> Bool {
        dose.texture < parDefaut.texture - marge || dose.clarte < parDefaut.clarte - marge
    }

    /// Le refus d'un masque de peau trop lisse, sans demande.
    static func refus(_ chemin: String, exces: String) -> String {
        "« \(chemin) » : peau lissée au-delà de la dose « Adoucir la peau (Lite) » (\(chiffres(lite)), intensité comprise, netteté jamais négative ; ici \(exces)). Par défaut : effect « Peau du visage lisse » (\(chiffres(parDefaut))), amount \(nombre(intensiteReduite)) pour un homme ou une personne âgée, rien pour un enfant. Plus lisse seulement si l'utilisateur l'a demandé (ou son guide de style) : smoothing_requested = true. Rien n'a été fait."
    }

    /// Vérifie un masque d'add_mask : lève le refus s'il lisse la peau au-delà de la dose Lite sans
    /// smoothing_requested. Appelé avant tout envoi au module : un refus n'envoie aucune commande.
    static func verifier(_ masque: [String: JSONValue], locaux: [String: JSONValue], quantite: Double, chemin: String) throws {
        guard surLaPeau(masque), masque["smoothing_requested"]?.bool != true,
              let exces = depassement(dose(locaux, quantite: quantite)) else { return }
        throw LightroomError.invalid(refus(chemin, exces: exces))
    }

    /// La remarque d'un masque de peau accepté (numéro à partir de 1), ou nil : au-delà de la dose
    /// Lite à la demande de l'utilisateur, ou au-dessus de la dose par défaut.
    static func remarque(_ masque: [String: JSONValue], locaux: [String: JSONValue], quantite: Double, numero: Int) -> String? {
        guard surLaPeau(masque) else { return nil }
        let posee = dose(locaux, quantite: quantite)
        if let exces = depassement(posee) {
            guard masque["smoothing_requested"]?.bool == true else { return nil }
            return "Peau (masque \(numero)) : \(exces), au-delà de la dose « Adoucir la peau (Lite) », à la demande de l'utilisateur (smoothing_requested) : vérifier par view_photo avec region sur le visage (pores, cire, plaques)."
        }
        guard auDessusDuDefaut(posee) else { return nil }
        return "Peau (masque \(numero)) : \(chiffres(posee)), au-dessus de la dose par défaut « Peau du visage lisse » : pour un gros plan aux pores marqués ; vérifier par view_photo avec region sur le visage."
    }

    // MARK: Textes

    /// « texture −20, clarté −10 » : les réglages non nuls d'une dose, à la française.
    static func chiffres(_ dose: Dose) -> String {
        [("texture", dose.texture), ("clarté", dose.clarte), ("netteté", dose.nettete)]
            .filter { $0.1 != 0 }
            .map { "\($0.0) \($0.1 > 0 ? "+" : "")\(nombre($0.1))" }
            .joined(separator: ", ")
    }

    /// Un nombre arrondi au centième, avec le signe moins typographique et la virgule.
    static func nombre(_ valeur: Double) -> String {
        ToolHandler.format(valeur).replacingOccurrences(of: ".", with: ",")
    }
}
