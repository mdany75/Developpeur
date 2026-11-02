import CoreGraphics
import Foundation

/// `--sens-essai` (développement, pour le constat de la recherche par le sens, 1.6) : un petit lot de
/// vignettes (200 par défaut) encodé dans un index temporaire, puis des requêtes, chacune telle
/// quelle et précédée de « a photo of », et une recherche de photos semblables ; chaque résultat dit
/// les dix premières photos (id, fichier, score brut, pertinence) et le nombre au-dessus du seuil
/// provisoire, avec les temps (compilation, encodage, classement). Lecture seule : les commandes
/// `chercher` et `vignettes` du module (des lectures), ou un dossier de JPEG sans Lightroom ; rien
/// n'est écrit au catalogue, ni à l'index du catalogue (Developpeur/Index n'est pas touché).
public final class EssaiSens {
    public enum Source: Equatable {
        case collection(String)
        case dossier(String)
        case ids([Int])
        case images(URL)
    }

    public static let requetesParDefaut = [
        "a beach at sunset", "a dog", "snow in winter", "a birthday cake", "a city street at night",
        "a portrait of a child", "flowers in a garden", "a mountain landscape", "a car", "people eating at a table",
    ]
    public static let prefixe = "a photo of "

    let lightroom: LightroomServing?
    let encodeur: EncodeurSens
    let dossier: URL
    let dire: (String) -> Void

    public init(lightroom: LightroomServing?, encodeur: EncodeurSens, dossier: URL, dire: @escaping (String) -> Void = { _ in }) {
        self.lightroom = lightroom
        self.encodeur = encodeur
        self.dossier = dossier
        self.dire = dire
    }

    struct Photo {
        var id: Int
        var fichier: String
        var image: CGImage?
        var erreur: String?
    }

    /// Les photos de la source (au plus `nombre`), avec leur vignette de 1 024 px.
    func photos(_ source: Source, nombre: Int) throws -> [Photo] {
        try Self.photos(source, nombre: nombre, taille: 1024, lightroom: lightroom, option: "--sens-essai", dire: dire)
    }

    /// Les photos d'une source d'essai (au plus `nombre`), avec leur vignette de `taille` px : un
    /// dossier de JPEG sans Lightroom, ou les commandes `chercher` et `vignettes` du module (des
    /// lectures seulement, vidéos sautées). Partagé par `--sens-essai` et `--especes-essai`.
    static func photos(_ source: Source, nombre: Int, taille: Int, lightroom: LightroomServing?, option: String,
                       dire: (String) -> Void) throws -> [Photo] {
        if case .images(let dossierImages) = source {
            let fichiers = ((try? FileManager.default.contentsOfDirectory(at: dossierImages, includingPropertiesForKeys: nil)) ?? [])
                .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .prefix(nombre)
            return fichiers.enumerated().map { i, url in
                let image = (try? Data(contentsOf: url)).flatMap(PreviewImages.image)
                return Photo(id: i + 1, fichier: url.lastPathComponent, image: image, erreur: image == nil ? "illisible" : nil)
            }
        }
        guard let lightroom else { throw LightroomError.invalid("\(option) : Lightroom est nécessaire pour cette source.") }
        var ids: [Int] = []
        var fichiers: [Int: String] = [:]
        switch source {
        case .ids(let liste):
            ids = Array(liste.prefix(nombre))
        case .collection, .dossier:
            var decalage = 0
            while ids.count < nombre {
                var params: [String: JSONValue] = ["tri": "aucun", "limite": .number(Double(min(500, nombre - ids.count))),
                                                   "decalage": .number(Double(decalage))]
                if case .collection(let nom) = source { params["collection"] = .string(nom) }
                if case .dossier(let chemin) = source { params["dossier"] = .string(chemin) }
                let page = try lightroom.send("chercher", params, timeout: 180)["photos"]?.array ?? []
                if page.isEmpty { break }
                for p in page {
                    guard let id = p["id"]?.int, p["video"]?.bool != true else { continue }
                    ids.append(id)
                    fichiers[id] = p["fichier"]?.string
                }
                decalage += page.count
            }
            ids = Array(ids.prefix(nombre))
        case .images:
            break
        }
        var photos: [Photo] = []
        for debut in stride(from: 0, to: ids.count, by: 50) {
            let lot = Array(ids[debut..<min(debut + 50, ids.count)])
            let reponse = try lightroom.send("vignettes", ["photos": .array(lot.map { .number(Double($0)) }), "taille": .number(Double(taille))], timeout: 120)
            for item in reponse["photos"]?.array ?? [] {
                guard let id = item["id"]?.int else { continue }
                let image = item["vignette"]?.string.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }.flatMap(PreviewImages.image)
                photos.append(Photo(id: id, fichier: item["fichier"]?.string ?? fichiers[id] ?? "photo \(id)", image: image,
                                    erreur: image == nil ? (item["erreur"]?.string ?? "sans vignette") : nil))
            }
            dire("vignettes : \(photos.count) sur \(ids.count)")
        }
        return photos
    }

    /// L'essai entier : la ligne JSON finale.
    public func lancer(source: Source, nombre: Int = 200, requetes: [String] = requetesParDefaut) throws -> JSONValue {
        let photos = try self.photos(source, nombre: nombre)
        let index = try IndexSens(ecrire: dossier, modele: encodeur.modele, dimension: encodeur.dimension)
        var durees: [Double] = []
        var erreurs: [JSONValue] = []
        var noms: [Int: String] = [:]
        for photo in photos {
            noms[photo.id] = photo.fichier
            guard let image = photo.image else {
                erreurs.append(["id": .number(Double(photo.id)), "erreur": .string(photo.erreur ?? "sans image")])
                continue
            }
            let debut = Date()
            do {
                let v = try encodeur.vecteur(image: image)
                durees.append(Date().timeIntervalSince(debut))
                try index.ranger(uuid: "essai-\(photo.id)", id: photo.id, jour: nil, vecteur: v)
            } catch {
                erreurs.append(["id": .number(Double(photo.id)), "erreur": .string(error.localizedDescription)])
            }
        }
        dire("encodées : \(durees.count) sur \(photos.count)")

        func classer(_ vecteur: [Float], sauf: Int? = nil) -> (JSONValue, Double) {
            let debut = Date()
            let classees = index.classer(vecteur).filter { $0.ligne.id != sauf }
            let ms = Date().timeIntervalSince(debut) * 1000
            guard let meilleur = classees.first?.score else { return (["premieres": [], "au_dessus_du_seuil": 0], ms) }
            let mediane = classees[classees.count / 2].score
            func pertinence(_ s: Float) -> Double { meilleur > mediane ? Double((s - mediane) / (meilleur - mediane)) : 1 }
            let premieres: [JSONValue] = classees.prefix(10).map { c in
                ["id": .number(Double(c.ligne.id)), "fichier": .string(noms[c.ligne.id] ?? ""),
                 "score": .number((Double(c.score) * 1000).rounded() / 1000), "pertinence": .number((pertinence(c.score) * 100).rounded() / 100)]
            }
            let dessus = classees.filter { pertinence($0.score) >= Sens.seuilPertinenceProvisoire }.count
            return (["premieres": .array(premieres), "au_dessus_du_seuil": .number(Double(dessus)),
                     "score_median": .number((Double(mediane) * 1000).rounded() / 1000)], ms)
        }

        var resultats: [JSONValue] = []
        var classements: [Double] = []
        for requete in requetes {
            var r: [String: JSONValue] = ["requete": .string(requete)]
            for (cle, texte) in [("telle_quelle", requete), ("avec_prefixe", requete.hasPrefix(Self.prefixe) ? requete : Self.prefixe + requete)] {
                do {
                    let (c, ms) = classer(try encodeur.vecteur(texte: texte))
                    r[cle] = c
                    classements.append(ms)
                } catch {
                    r[cle] = ["erreur": .string(error.localizedDescription)]
                }
            }
            resultats.append(.object(r))
            dire("requête : \(requete)")
        }
        var semblables: JSONValue = .null
        if let premiere = index.lignes().first, let v = index.vecteur(id: premiere.id) {
            semblables = ["photo": .number(Double(premiere.id)), "fichier": .string(noms[premiere.id] ?? ""), "classement": classer(v, sauf: premiere.id).0]
        }
        let moyenne = durees.isEmpty ? 0 : durees.reduce(0, +) / Double(durees.count)
        return [
            "ok": true, "modele": .string(encodeur.modele), "dimension": .number(Double(encodeur.dimension)),
            "photos": .number(Double(photos.count)), "indexees": .number(Double(index.nombre)), "erreurs": .array(erreurs),
            "seuil_pertinence_provisoire": .number(Sens.seuilPertinenceProvisoire),
            "temps": ["encodage_ms_moyen": .number((moyenne * 10000).rounded() / 10), "encodage_ms_max": .number(((durees.max() ?? 0) * 10000).rounded() / 10),
                      "classement_ms_moyen": .number(classements.isEmpty ? 0 : (classements.reduce(0, +) / Double(classements.count) * 10).rounded() / 10)],
            "requetes": .array(resultats), "semblables": semblables, "index": .string(dossier.path),
        ]
    }
}
