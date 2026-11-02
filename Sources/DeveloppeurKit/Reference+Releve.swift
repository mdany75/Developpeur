import CoreGraphics
import Foundation

// MARK: - Relevé (`mcp-developpeur --etalonnage`)

/// Le relevé qui fixe les constantes provisoires de match_look (docs/SPEC.md, Étalonnage d'après une
/// référence, À constater) :
/// - sans `balayage`, en lecture seule (aperçus comme view_photo, ou fichiers JPEG sans Lightroom) :
///   la signature de chaque image à chaque borne de `Reference.bornesReleve` (fixe `chromaZone`,
///   `partMinZone`, et vérifie les bandes noires) ;
/// - avec `balayage`, sur des copies virtuelles seulement : chaque essai de `Reference.balayage`
///   passe par preview_settings (deux étapes « Claude · essai » de l'Historique par rendu ; la photo
///   est remise comme avant), et son décalage par zone, comparé à l'aperçu de départ, donne l'angle
///   a*b* de chaque teinte (`ancresTeinte`), le gain par point de saturation (`gainDepart`), le
///   débordement sur les autres zones et la pente de la Vibrance (`vibranceParChromaDepart`).
extension Reference {
    /// Les essais du balayage, réduit (critique du plan : chaque rendu laisse deux étapes) : teintes
    /// de 60 en 60 à saturation 25 dans chaque zone (18), saturations 12, 25 et 50 à la teinte 30
    /// (9), Vibrance −30 et +30 (2) : 29 rendus, 58 étapes d'historique par photo.
    static var balayage: [(nom: String, zone: Int?, teinte: Double?, saturation: Double?, reglages: [String: Double])] {
        var essais: [(String, Int?, Double?, Double?, [String: Double])] = []
        for z in 0..<3 {
            let cles = clesZones[z]
            for teinte in stride(from: 0.0, through: 300, by: 60) {
                essais.append(("\(nomZone(z)) teinte \(Int(teinte)) sat 25", z, teinte, 25, [cles.teinte: teinte, cles.saturation: 25]))
            }
            for saturation in [12.0, 25, 50] {
                essais.append(("\(nomZone(z)) teinte 30 sat \(Int(saturation))", z, 30, saturation, [cles.teinte: 30, cles.saturation: saturation]))
            }
        }
        essais.append(("Vibrance −30", nil, nil, nil, ["Vibrance": -30]))
        essais.append(("Vibrance +30", nil, nil, nil, ["Vibrance": 30]))
        return essais
    }

    public static func releve(lightroom: LightroomServing, ids: [Int], fichiers: [URL], balayage avecBalayage: Bool,
                              visages lireVisages: (CGImage) -> [CGRect] = Teint.visages, sortie: (String) -> Void = { _ in }) -> [String] {
        var lignes: [String] = []
        func dire(_ ligne: String) { lignes.append(ligne); sortie(ligne) }
        let e = Eclairage.texte
        dire("Relevé de l'étalonnage : zones L* < \(Int(limites[0])), \(Int(limites[0])) à \(Int(limites[1])), > \(Int(limites[1])) ; "
            + "chromaZone \(Eclairage.nombre(chromaZone)) ; bornes \(bornesReleve.map(Eclairage.nombre).joined(separator: ", "))"
            + (avecBalayage ? " ; balayage de \(balayage.count) rendus par photo (deux étapes « Claude · essai » chacun, copies virtuelles seulement)" : " ; lecture seule"))
        if avecBalayage, !fichiers.isEmpty { dire("(le balayage ne vaut que pour les photos de Lightroom : les fichiers sont lus tels quels)") }

        func zonesTexte(_ s: Signature) -> String {
            (0..<3).map { z in
                s.zones[z].map { "\(nomZone(z)) a* \(e($0.a, 1)) b* \(e($0.b, 1)) (\(e($0.part, 0)) %)" } ?? "\(nomZone(z)) non lue"
            }.joined(separator: " · ")
        }
        func signatureTexte(_ s: Signature) -> String {
            let bandes = s.bandes.enumerated().filter { $0.element >= 10 }.sorted { $0.element > $1.element }
                .map { "\(PhotoMeasurements.bandes[$0.offset].nom) \(e($0.element, 0)) %" }.joined(separator: ", ")
            return zonesTexte(s) + " ; chroma médiane \(e(s.chromaMediane, 1)), P90 \(e(s.chromaP90, 1)), couleurs vives \(s.chromaCouleurs.map { e($0, 1) } ?? "non lue") ; L* P5 \(e(s.centiles[5] ?? 0, 1)) P50 \(e(s.mediane, 1)) P95 \(e(s.centiles[95] ?? 0, 1))"
                + (bandes.isEmpty ? "" : " ; bandes \(bandes)") + (s.remarques.isEmpty ? "" : " ; " + s.remarques.joined(separator: " ; "))
        }

        // Lecture seule : la signature de chaque image à chaque borne.
        let sources: [(nom: String, charger: () throws -> (CGImage, JSONValue?))] =
            ids.map { id in ("\(id)", { try apercuReleve(id, lightroom: lightroom) }) }
            + fichiers.map { f in (f.lastPathComponent, {
                guard let image = PreviewImages.image(try Data(contentsOf: f)) else { throw LightroomError.plugin("image illisible") }
                return (image, nil)
            }) }
        var bases: [Int: (CGImage, [CGRect])] = [:]
        for (index, source) in sources.enumerated() {
            let image: CGImage, reponse: JSONValue?
            do { (image, reponse) = try source.charger() } catch { dire("✘ \(source.nom) : \(error.localizedDescription)"); continue }
            let visages = lireVisages(image)
            dire("")
            dire("■ \(source.nom)" + (reponse?["photo"]?["fichier"]?.string.map { " · \($0)" } ?? "") + " · \(image.width) × \(image.height) · \(visages.count) visage(s)")
            for borne in bornesReleve {
                guard let s = lire(image, visages: visages, chromaZone: borne) else { dire("  ✘ borne \(Eclairage.nombre(borne)) : illisible"); continue }
                dire("  C* < \(Eclairage.nombre(borne)) : " + signatureTexte(s))
            }
            if index < ids.count { bases[ids[index]] = (image, visages) }
        }
        guard avecBalayage else { return lignes }

        // Le balayage, sur chaque copie virtuelle.
        for id in ids {
            guard let (image, visages) = bases[id], let depart = lire(image, visages: visages) else { continue }
            do {
                let lue = try lightroom.send("reglages", ["photo": .number(Double(id)), "cles": .array(clesLues.map(JSONValue.string))], timeout: 30)
                guard lue["photo"]?["copie_virtuelle"]?.bool == true else {
                    dire("✘ \(id) : balayage seulement sur une copie virtuelle (les copies d'essai de « Développeur › Essais ») : c'est un original")
                    continue
                }
                let deja = clesZones.contains { (lue["reglages"]?[$0.saturation]?.double ?? 0) != 0 }
                if deja { dire("⚠ \(id) : un étalonnage est déjà posé : remettre la copie à l'origine d'abord, sinon les décalages se lisent mal") }
            } catch {
                dire("✘ \(id) : \(error.localizedDescription)")
                continue
            }
            dire("")
            dire("■ Balayage de \(id) (décalages a*b* par zone, par rapport à l'aperçu de départ ; « dans sa zone » : angle et gain par point de saturation)")
            var resume: [String] = []
            for essai in balayage {
                let capture = Eclairage.Capture(lightroom)
                let resultat = ToolHandler(lightroom: capture).call(name: "preview_settings", arguments: [
                    "photo_id": .number(Double(id)), "step_name": "relevé étalonnage",
                    "settings": .object(essai.reglages.mapValues { .number($0) }),
                ])
                guard !resultat.isError, let data = capture.apercu, let rendu = PreviewImages.image(data), let s = lire(rendu, visages: visages) else {
                    dire("  ✘ \(essai.nom) : \(resultat.isError ? resultat.text : "aperçu illisible")")
                    continue
                }
                var morceaux: [String] = []
                var propre = "—"
                for z in 0..<3 {
                    guard let p = depart.zones[z], let q = s.zones[z] else { morceaux.append("\(nomZone(z)) —"); continue }
                    let d = Vecteur(a: q.a - p.a, b: q.b - p.b)
                    let angle = (atan2(d.b, d.a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                    morceaux.append("\(nomZone(z)) Δa \(e(d.a, 1)) Δb \(e(d.b, 1)) (\(e(angle, 0))°, \(e(d.norme, 1)))")
                    if essai.zone == z, let sat = essai.saturation, sat > 0 {
                        propre = "angle \(e(angle, 0))°, gain \(e(d.norme / sat, 3))"
                    }
                }
                // La Vibrance se juge sur les couleurs vives (Signature.chromaCouleurs), comme match_look.
                let chroma = (s.chromaCouleurs ?? 0) - (depart.chromaCouleurs ?? 0)
                dire("  \(essai.nom) : " + morceaux.joined(separator: " · ") + " ; Δ chroma des couleurs vives \(depart.chromaCouleurs == nil ? "non lue" : e(chroma, 2))"
                    + (essai.zone != nil ? " ; dans sa zone : \(propre)" : ""))
                if essai.zone != nil {
                    resume.append("\(essai.nom)\t\(propre)")
                } else if let v = essai.reglages["Vibrance"], depart.chromaCouleurs != nil, abs(chroma) > 0.01 {
                    resume.append("\(essai.nom)\tvibranceParChroma \(e(v / chroma, 2))")
                }
            }
            dire("")
            dire("Résumé de \(id) (essai, ce qu'il fixe ; ancresTeinte = angles lus à saturation 25, gainDepart = gains, vibranceParChromaDepart) :")
            for ligne in resume { dire(ligne) }
        }
        return lignes
    }

    /// L'aperçu d'une photo, en lecture seule (commande « apercu », comme view_photo).
    static func apercuReleve(_ id: Int, lightroom: LightroomServing) throws -> (CGImage, JSONValue?) {
        let reponse = try lightroom.send("apercu", ["photo": .number(Double(id)), "taille": .number(Double(ToolHandler.defaultPreviewSize)),
                                                    "cles": .array(clesLues.map(JSONValue.string))], timeout: 120)
        let data = try ToolHandler.readPreview(reponse["chemin"]?.string)
        guard let image = PreviewImages.image(data) else { throw LightroomError.plugin("aperçu illisible") }
        return (image, reponse)
    }
}
