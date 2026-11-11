import Foundation

/// La recette de Lightroom Classic 16 (1.8) : la Lueur et l'étalonnage d'un masque sur la copie
/// RAW, la Projection sur la copie JPEG (sans profil d'objectif). Chaque étape est défaite, et la
/// photo vérifiée revenue comme au départ. Sous une version plus ancienne que la 16.0, les étapes
/// sont sautées avec leur raison (ces réglages y seraient refusés) ; une version illisible les fait échouer. Constats de référence :
/// docs/SPEC.md, Lightroom Classic 16 (1.8).
extension Recette {
    /// Version de Lightroom Classic qui connaît la Lueur, la Projection et l'étalonnage local.
    static let version16 = "16.0"
    /// Plus grand écart de luminance au moins (niveaux sur 255, trois fois `ecartIdentique`) entre
    /// l'aperçu sans Lueur et l'aperçu avec Glow 40. Le L* moyen ne convenait pas : la Lueur répartit
    /// la lumière autour des hautes lumières plus qu'elle n'éclaircit l'image (constaté le
    /// 10 novembre 2026 sur la copie RAW du portrait : 36,5 → 36,58).
    static let ecartLueurMin = 6.0
    /// Hauteur du trait de pinceau de l'étape de la Projection, et écart permis (part de la hauteur).
    static let hauteurTraitProjection = 0.2, ecartTraitProjection = 0.02
    /// Abscisses des points du trait : cinq, comme au constat réussi de la 1.8 (le module ne recale
    /// que les points qu'il pose, et depuis la 1.9 coupe aussi les longs traits : Geometrie.trait).
    static let pointsTraitProjection = [0.03, 0.25, 0.5, 0.75, 0.97]
    /// Colonnes où la bande du trait se mesure : bords et centre (parts de la largeur).
    static let colonnesProjection: [(nom: String, colonnes: ClosedRange<Double>)] = [
        ("bord gauche", 0.04...0.14), ("centre", 0.45...0.55), ("bord droit", 0.86...0.96),
    ]

    /// La raison de sauter une étape de la 16 (Lightroom plus ancien), ou nil. Une version illisible
    /// est un échec, jamais un saut (revue du 10 novembre 2026 : la recette aurait réussi sans rien
    /// vérifier).
    func sautAvant16() throws -> String? {
        let version = try appel("get_status", [:]).0["lightroom"]?.string ?? ""
        return try Self.raisonDeSauter16(version)
    }

    static func raisonDeSauter16(_ version: String) throws -> String? {
        if version.trimmingCharacters(in: .whitespaces).isEmpty {
            throw Echec(description: "version de Lightroom Classic illisible (get_status) : étape de la \(version16) non vérifiée")
        }
        guard ToolHandler.versionInferieure(version, version16) else { return nil }
        return "sautée : Lightroom Classic \(version) (Lueur, Projection et étalonnage local depuis la \(version16))"
    }

    /// Copie RAW de --recette : la Lueur, puis l'étalonnage dans un masque radial.
    func sequenceLightroom16(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        try etape(photo, "Lueur (Glow 40, style 2) relue en entiers, rendu changé, annulée") {
            if let saut = try sautAvant16() { return saut }
            let avant = try etat(id)
            let (_, imagesAvant) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            try ecrire("apply_settings", id, ["settings": ["Glow": 40, "GlowStyle": 2]])
            let tous = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]
            let (_, imagesApres) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            if let first = imagesApres.first { garder(first, "recette-lueur.jpg") }
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), avant)
            let glow = tous?["Glow"]?.double, style = tous?["GlowStyle"]?.double
            try verifier(glow == 40 && style == 2,
                         "Lueur relue : Glow \(glow.map(Self.nombre) ?? "absent"), GlowStyle \(style.map(Self.nombre) ?? "absent") au lieu de 40 et 2")
            guard let a = imagesAvant.first, let b = imagesApres.first, let ecart = Self.ecartMax(a, b) else {
                throw Echec(description: "aperçu illisible avant ou après la Lueur")
            }
            let part = Self.partChangee(a, b)
            try verifier(ecart >= Self.ecartLueurMin,
                         "rendu inchangé par la Lueur : écart maximal de \(Self.nombre(ecart)) niveaux, \(Self.nombre(part * 100)) % des pixels changés")
            return "Glow 40 et GlowStyle 2 relus ; écart maximal de \(Self.nombre(ecart)) niveaux, \(Self.nombre(part * 100)) % des pixels changés ; annulée"
        }
        try etape(photo, "étalonnage dans un masque radial (ombres 220, 30), relu en entiers, annulé") {
            if let saut = try sautAvant16() { return saut }
            let avant = try etat(id)
            try ecrire("add_mask", id, ["masks": [["kind": "radial", "name": "Recette étalonnage local", "center_x": 0.5, "center_y": 0.5,
                                                   "radius_x": 0.3, "adjustments": ["ColorGradeShadowHue": 220, "ColorGradeShadowSat": 30]]]])
            let apres = try etat(id)
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), avant)
            try verifier(apres.nombreMasques == avant.nombreMasques + 1, "\(apres.nombreMasques) masques au lieu de \(avant.nombreMasques + 1)")
            let locaux = apres.masques.array?.last?["reglages_locaux"]
            let teinte = locaux?["LocalColorGradeShadowHue"]?.double, saturation = locaux?["LocalColorGradeShadowSat"]?.double
            try verifier(teinte == 220 && saturation == 30,
                         "étalonnage relu dans le masque : \(locaux.map(JSONCoding.line) ?? "aucun réglage") au lieu de LocalColorGradeShadowHue 220 et LocalColorGradeShadowSat 30")
            return "LocalColorGradeShadowHue 220 et LocalColorGradeShadowSat 30 relus ; annulé"
        }
    }

    /// Copie --jpeg (sans profil d'objectif) : la Projection 100, puis un trait de pinceau droit à
    /// 0,2 de la hauteur, qui doit rester droit sur le rendu (le serveur recale les positions sous
    /// la Projection depuis la 1.8 : de 0,184 à 0,209 constaté, 0,170 à 0,236 sans recalage).
    func etapeProjection(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let y = Self.hauteurTraitProjection
        try etape(photo, "Projection 100 : trait de pinceau à 0,2 de la hauteur, droit au centre et aux bords, annulés") {
            if let saut = try sautAvant16() { return saut }
            let avant = try etat(id)
            try ecrire("apply_settings", id, ["settings": ["ReshapeAmount": 100]])
            let projection = Self.valeur(try etat(id), "ReshapeAmount")
            let (_, imagesAvant) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            try ecrire("add_mask", id, ["masks": [["kind": "brush", "name": "Recette pinceau Projection", "adjustments": ["Exposure": -2],
                                                   "strokes": [["points": .array(Self.pointsTraitProjection.map { [.number($0), .number(y)] }),
                                                                 "size": 0.01, "feather": 0]]]]])
            let (vue, imagesApres) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            if let first = imagesApres.first { garder(first, "recette-projection.jpg") }
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), avant)
            try verifier(projection == 100, "ReshapeAmount relu \(projection.map(Self.nombre) ?? "absent") au lieu de 100")
            guard let a = imagesAvant.first, let b = imagesApres.first else { throw Echec(description: "aucun aperçu") }
            var lus: [String] = [], ecarts: [String] = []
            for (nom, colonnes) in Self.colonnesProjection {
                guard let bande = Self.bandeAssombrie(avant: a, apres: b, colonnes: colonnes) else {
                    throw Echec(description: "aucune bande assombrie trouvée (\(nom))\(vue["a_savoir"]?.string.map { " : " + $0 } ?? "")")
                }
                lus.append("\(nom) \(Self.nombre(bande.centre))")
                if abs(bande.centre - y) >= Self.ecartTraitProjection { ecarts.append("\(nom) à \(Self.nombre(bande.centre))") }
            }
            try verifier(ecarts.isEmpty, "trait courbé sous la Projection (attendu à \(Self.nombre(y)) de la hauteur) : \(ecarts.joined(separator: ", ")) ; lu : \(lus.joined(separator: ", "))")
            return "bande à \(lus.joined(separator: ", ")) de la hauteur (attendue \(Self.nombre(y))) ; annulés"
        }
    }
}
