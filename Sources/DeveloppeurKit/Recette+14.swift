import Foundation

/// La recette de la 1.4 (une sortie entière) : les groupes de lumière sur les copies d'Essais
/// données à la recette, en lecture seule (`match_series` avec `groups` : rien d'écrit), et la
/// prise de vue en nombres que le module lit pour eux (`prise_de_vue` de la description des
/// vignettes : ouverture, vitesse, compensation et flash de `getRawMetadata`, d'après la référence
/// du SDK : à constater dans Lightroom).
extension Recette {
    func sequenceLumiere(_ ids: [Int]) throws {
        var photos: [Int] = []
        for id in ids where !photos.contains(id) { photos.append(id) }
        guard photos.count >= 2 else { return }
        let liste = JSONValue.array(photos.map { .number(Double($0)) })
        try etape("sortie \(photos.map(String.init).joined(separator: ", "))", "groupes de lumière (match_series, groups), rien d'écrit") {
            let avant = try photos.map { try etat($0) }
            // La prise de vue telle que le module la décrit ; les vignettes rendues s'effacent.
            let reponse = try tools.lightroom.send("vignettes", ["photos": liste, "taille": 256], timeout: 120)
            let decrites = reponse["photos"]?.array ?? []
            for photo in decrites { _ = try? ToolHandler.readPreview(photo["vignette"]?.string) }
            let lues = decrites.filter { $0["prise_de_vue"]?["ouverture"]?.double != nil && $0["prise_de_vue"]?["vitesse"]?.double != nil }
            let flashs = decrites.map { photo -> String in
                switch photo["prise_de_vue"]?["flash"]?.bool {
                case true?: return "oui"
                case false?: return "non"
                case nil: return "inconnu"
                }
            }
            let (plan, _) = try appel("match_series", ["groups": true, "photo_ids": liste])
            for (id, etatAvant) in zip(photos, avant) { try verifierEgal(try etat(id), etatAvant) }
            let groupes = plan["groupes"]?.array ?? [], seules = plan["photos_seules"]?.array ?? []
            let comptees = groupes.reduce(0) { $0 + ($1["nombre"]?.int ?? 0) } + seules.count
            try verifier(plan["photos_analysees"]?.int == photos.count && comptees == photos.count,
                         "photos comptées \(comptees) sur \(photos.count) : \(JSONCoding.line(plan))")
            try verifier(!lues.isEmpty, "prise de vue en nombres absente des vignettes : \(JSONCoding.line(.array(decrites)))")
            let coupures = (groupes.map { $0["commence"]?.string } + seules.map { $0["pourquoi"]?.string }).compactMap { $0 }
            return "\(groupes.count) groupe(s), \(seules.count) photo(s) seule(s) (\(coupures.joined(separator: " ; "))) ; prise de vue lue sur \(lues.count) photo(s) sur \(photos.count), flash : \(flashs.joined(separator: ", ")) ; rien d'écrit"
        }
    }
}
