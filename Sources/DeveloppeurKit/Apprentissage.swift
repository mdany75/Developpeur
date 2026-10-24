import Foundation

/// Apprendre des corrections de l'utilisateur (1.3.5, `remember_style` avec `learn`) : ses reprises
/// à la main depuis la dernière retouche de Claude (`corrections_utilisateur` du module), lues sur
/// une série. Une règle n'est proposée que si sa fréquence et son sens sont constants ; elle
/// n'entre au guide de style qu'avec l'accord de l'utilisateur (remember_style avec preference et
/// confirm). Fonctions pures.
public enum Apprentissage {
    /// Au moins `minPhotos` photos reprises sur ce réglage, sur au moins `frequenceMin` des photos
    /// reprises, dans le même sens pour au moins `sensMin` d'entre elles. Provisoires.
    static let minPhotos = 3, frequenceMin = 0.6, sensMin = 0.8
    /// Photos lues au plus par appel.
    static let maxPhotos = 200

    /// Une reprise : un réglage numérique, la valeur laissée par Claude et la valeur actuelle.
    struct Reprise: Equatable {
        var cle: String
        var claude: Double
        var maintenant: Double
    }

    struct Regle: Equatable {
        var cle: String
        var libelle: String
        var photos: Int
        var sur: Int
        var moyenne: Double
        var meme: Int
        var rubrique: String
    }

    /// Les reprises numériques d'une réponse du module (`corrections_utilisateur.changements`).
    static func reprises(_ corrections: JSONValue?) -> [Reprise] {
        (corrections?["changements"]?.array ?? []).compactMap { item in
            guard let cle = item["cle"]?.string, let avant = item["claude"]?.double, let apres = item["maintenant"]?.double,
                  avant != apres else { return nil }
            return Reprise(cle: cle, claude: avant, maintenant: apres)
        }
    }

    /// La rubrique du guide de style d'un réglage.
    static func rubrique(_ cle: String) -> String {
        let couleur = ["Temperature", "Tint", "Vibrance", "Saturation", "Hue", "Luminance", "ColorGrade", "SplitToning", "Gray"]
        let tonalite = ["Exposure", "Contrast", "Highlights", "Shadows", "Whites", "Blacks", "Clarity", "Dehaze", "Texture", "Curve"]
        if cle.hasPrefix("Grain") { return "grain" }
        if cle.hasPrefix("Crop") { return "crop" }
        if couleur.contains(where: cle.contains) { return "color" }
        if tonalite.contains(where: cle.contains) { return "tone" }
        return "other"
    }

    /// Les règles d'une série de photos reprises (une liste de reprises par photo reprise).
    static func regles(_ parPhoto: [[Reprise]]) -> [Regle] {
        let sur = parPhoto.count
        guard sur > 0 else { return [] }
        var ecarts: [String: [Double]] = [:]
        for reprises in parPhoto {
            for r in reprises { ecarts[r.cle, default: []].append(r.maintenant - r.claude) }
        }
        return ecarts.compactMap { cle, liste -> Regle? in
            let hausses = liste.filter { $0 > 0 }.count, baisses = liste.filter { $0 < 0 }.count
            let meme = max(hausses, baisses)
            guard liste.count >= minPhotos, Double(liste.count) >= frequenceMin * Double(sur),
                  Double(meme) >= sensMin * Double(liste.count) else { return nil }
            let dansLeSens = liste.filter { hausses >= baisses ? $0 > 0 : $0 < 0 }
            return Regle(cle: cle, libelle: DevelopCatalogue.label(for: cle) ?? cle, photos: liste.count, sur: sur,
                         moyenne: dansLeSens.reduce(0, +) / Double(dansLeSens.count), meme: meme, rubrique: rubrique(cle))
        }
        .sorted { $0.photos != $1.photos ? $0.photos > $1.photos : $0.cle < $1.cle }
    }

    static func nombre(_ valeur: Double) -> String {
        let absolu = abs(valeur)
        return Bilan.nombre(absolu, decimales: absolu < 1 ? 2 : (absolu < 10 ? 1 : 0))
    }

    /// Ce que remember_style rend : les règles, chacune avec la phrase à proposer, et ce qui a été lu.
    static func json(_ regles: [Regle], lues: Int, reprises: Int, videos: Int) -> JSONValue {
        var resultat: [String: JSONValue] = [
            "photos_lues": .number(Double(lues)),
            "photos_reprises": .number(Double(reprises)),
            "regles": .array(regles.map { r in
                let sens = r.moyenne > 0 ? "montes" : "baisses"
                return [
                    "reglage": .string(r.cle), "libelle": .string(r.libelle), "rubrique": .string(r.rubrique),
                    "photos": .number(Double(r.photos)), "sur": .number(Double(r.sur)), "meme_sens": .number(Double(r.meme)),
                    "ecart_moyen": .number((r.moyenne * 100).rounded() / 100),
                    "constat": .string("Tu \(sens) \(r.libelle) après Claude : sur \(r.photos) photos reprises sur \(r.sur), dans le même sens \(r.meme) fois, de \(nombre(r.moyenne)) en moyenne."),
                    "phrase_proposee": .string("\(r.libelle) : \(r.moyenne > 0 ? "plus haut" : "plus bas") que la première retouche de Claude, d'environ \(nombre(r.moyenne))."),
                ]
            }),
            "regle_de_lecture": .string("Une règle n'est proposée que pour un réglage repris sur au moins \(minPhotos) photos et \(Int(frequenceMin * 100)) % des photos reprises, dans le même sens au moins \(Int(sensMin * 100)) % du temps (seuils provisoires). Rien n'est ajouté : proposer chaque phrase à l'utilisateur, puis remember_style avec preference, category (rubrique) et confirm = true seulement après son accord."),
        ]
        if reprises == 0 {
            resultat["remarque"] = "Aucune reprise à la main sur ces photos depuis la dernière retouche de Claude : rien à apprendre."
        } else if regles.isEmpty {
            resultat["remarque"] = "Des reprises, mais aucune n'est assez fréquente ni constante pour faire une règle."
        }
        if videos > 0 { resultat["videos_ecartees"] = .string("\(videos) vidéo(s) écartée(s).") }
        return .object(resultat)
    }
}
