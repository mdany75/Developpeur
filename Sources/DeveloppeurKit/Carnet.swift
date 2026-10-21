import CoreGraphics
import Foundation

/// Le carnet de progrès (1.3), côté connecteur : ce qui se mesure de la prise de vue, et le texte du
/// carnet pour export_journal. Le registre est tenu par le module seul (Carnet.lua, carnet.json) :
/// le serveur lui envoie ses constats (commande carnet constater), avec le vocabulaire de
/// PriseDeVue, la seule liste des défauts ; il ne garde rien.
///
/// Deux sortes de constats, sur les six défauts mesurés de PriseDeVue :
/// - une vue (`constatsVue`) : au premier view_photo entier d'une photo que Claude n'a pas encore
///   retouchée (etapes_claude.nombre == 0), les défauts cherchés et ceux trouvés : sous-exposition,
///   ciel brûlé, flou, mise au point, bruit ; l'horizon y est seulement cherché (une ligne ne se
///   trouve que mesurée), et seulement sur une géométrie intacte ;
/// - un angle (`constatHorizon`) : une ligne horizontale penchée de `horizonMin` ou plus, mesurée
///   par measure_angle ou read_composition sur une géométrie intacte (ni recadrage tourné, ni
///   Upright, ni perspective, ni distorsion manuelle : `geometrieIntacte`), même après une passe de
///   tonalité. read_composition mesure sur l'image entière, sans le cadre, mais Upright et la
///   perspective y restent.
/// Le module vérifie de nouveau (étapes de Claude, géométrie, photos d'essai, case Carnet) et peut
/// refuser (note = false) : le connecteur ne dit un constat à Claude que s'il est noté.
///
/// Pas de détecteur d'horizon : Lignes.swift dit qu'ils se sont montrés peu fiables. Fonctions pures,
/// testées telles quelles (CarnetTests), sauf `releve` (`--constats`, lecture seule).
public enum Carnet {
    // MARK: Seuils

    /// Une ligne penchée de moins ne se voit pas (la base de measure_angle : « Sous 0,5°… »).
    public static let horizonMin = 0.5
    /// Un recadrage tourné de moins que cela n'est pas tourné : le curseur de Lightroom va par
    /// 0,01°, et un cadre calculé peut garder un reste de l'ordre de 1e-12. Le même que
    /// `Carnet.ANGLE_NUL` du module, qui refuse au-delà.
    public static let angleNul = 0.005
    /// Sous-exposition : L* médian sous `medianeSousExposee` et aucune partie claire (95e centile de
    /// L* sous `p95SousExposee`). Provisoires : à relever par `--constats` (photos réussies, nuit,
    /// photo voulue sombre, RAF en DR200 ou DR400).
    public static let medianeSousExposee = 28.0
    public static let p95SousExposee = 80.0
    /// Ciel ou haut de l'image brûlé : plus de `partBlancPurHaut` % du tiers haut en blanc pur (les
    /// trois canaux à 254 ou plus, comme `PhotoMeasurements.pureWhite`), sur la réduction à 512 px
    /// des mesures. Pas de lecture du masque Ciel de Lightroom : un mur, la neige ou un fond blanc en
    /// haut de l'image comptent aussi, et le libellé le dit. Provisoire, comme les précédents.
    public static let partBlancPurHaut = 3.0
    /// Texte d'un défaut trouvé : 200 octets au plus (`Carnet.LONGUEUR_CONSTAT` du module).
    static let longueurTexte = 200
    /// Délai de la commande carnet (constater, lire) : quelques dizaines de millisecondes attendues.
    static let delaiConstat: TimeInterval = 10
    static let delaiLecture: TimeInterval = 30

    /// Réglages de la géométrie que la commande apercu doit rendre pour juger qu'elle est intacte
    /// (Recalage.transformationActive du module) ; le recadrage tourné vient de `recadrage.angle`.
    public static let clesGeometrie = ["PerspectiveUpright", "PerspectiveVertical", "PerspectiveHorizontal", "PerspectiveRotate",
                                       "PerspectiveAspect", "PerspectiveScale", "PerspectiveX", "PerspectiveY",
                                       "LensManualDistortionAmount"]

    // MARK: Constats

    /// Un défaut trouvé : son code (PriseDeVue), sa mesure (L*, %, netteté, bruit ou degrés) et ce
    /// qu'on en dit, en clair.
    public struct Constat: Equatable {
        public var code: String
        public var mesure: Double?
        public var texte: String

        var json: JSONValue {
            var objet: [String: JSONValue] = ["code": .string(code), "texte": .string(texte)]
            if let mesure, mesure.isFinite { objet["mesure"] = .number((mesure * 10).rounded() / 10) }
            return .object(objet)
        }
    }

    /// Les constats d'une vue entière : les défauts cherchés (dans l'ordre de PriseDeVue), et ceux
    /// trouvés parmi eux.
    public struct Vue: Equatable {
        public var cherches: [String]
        public var defauts: [Constat]

        /// La vue telle que la commande carnet constater l'attend : { cherches, defauts }.
        public var json: JSONValue {
            ["cherches": .array(cherches.map(JSONValue.string)), "defauts": .array(defauts.map(\.json))]
        }

        /// Ce que Claude lit (constats_prise_de_vue de view_photo).
        public var textes: [String] { defauts.map(\.texte) }
    }

    /// La géométrie de la photo est-elle intacte ? Ni recadrage tourné (`angleRecadrage`), ni
    /// Upright, ni perspective, ni distorsion manuelle (`reglages` : la réponse de la commande
    /// apercu, à plat ; une clé absente vaut sa valeur neutre, comme dans le module). Une ligne
    /// mesurée n'y dit plus l'inclinaison de la prise de vue sinon.
    public static func geometrieIntacte(reglages: JSONValue?, angleRecadrage: Double) -> Bool {
        guard abs(angleRecadrage) < angleNul else { return false }
        for cle in clesGeometrie {
            let neutre = cle == "PerspectiveScale" ? 100.0 : 0
            if let valeur = reglages?[cle]?.double, valeur != neutre { return false }
        }
        return true
    }

    /// Part du tiers haut de l'image en blanc pur (les trois canaux à 254 ou plus), en %. `image` :
    /// la réduction à 512 px des mesures.
    public static func blancPurHaut(_ image: CGImage) -> Double? {
        let largeur = image.width, hauteur = image.height
        let lignes = hauteur / 3
        guard largeur > 0, lignes > 0, let pixels = Measurements.rgba(image) else { return nil }
        var blancs = 0
        for i in 0..<(largeur * lignes) where pixels[i * 4] >= 254 && pixels[i * 4 + 1] >= 254 && pixels[i * 4 + 2] >= 254 {
            blancs += 1
        }
        return Double(blancs) * 100 / Double(largeur * lignes)
    }

    /// Les défauts de la prise de vue mesurés sur l'aperçu entier de view_photo, avant le carré du
    /// point de mise au point : `mesures` et `reduite` (512 px), `detail` (1024 px ; ses seuils ne
    /// valent qu'à cette taille : sous elle, ni netteté ni bruit ne sont cherchés), `af` (point de
    /// mise au point de l'appareil et netteté autour ; mise_au_point n'est cherché que s'il est lu),
    /// `intention` (Fujifilm : une compensation de −0,6 IL ou moins, ou une scène de nuit, disent une
    /// photo voulue sombre, jamais sous-exposée), `geometrieIntacte` (sinon l'horizon n'est pas
    /// cherché : la base compterait droite une photo déjà redressée).
    public static func constatsVue(mesures: PhotoMeasurements?, detail: DetailMeasurements?, reduite: CGImage?,
                                   af: PhotoTriee.MiseAuPoint?, intention: IntentionBoitier?, geometrieIntacte: Bool) -> Vue {
        var cherches: Set<String> = [], trouves: [Constat] = []
        func trouve(_ code: String, _ mesure: Double?, _ detailTexte: String) {
            trouves.append(Constat(code: code, mesure: mesure, texte: borner(detailTexte)))
        }
        if geometrieIntacte { cherches.insert("horizon_penche") }

        if let mesures {
            cherches.insert("sous_exposition")
            let p95 = mesures.percentilesL[95] ?? mesures.medianL
            let voulueSombre = (intention?.compensation).map { $0 <= IntentionBoitier.seuilSombreVoulue } == true || intention?.nuit == true
            if !voulueSombre, mesures.medianL < medianeSousExposee, p95 < p95SousExposee {
                trouve("sous_exposition", mesures.medianL,
                       "sous-exposée : L* médian \(Bilan.nombre(mesures.medianL)), aucune partie claire (95e centile \(Bilan.nombre(p95)))")
            }
        }
        if let reduite, let part = blancPurHaut(reduite) {
            cherches.insert("ciel_brule")
            if part > partBlancPurHaut {
                trouve("ciel_brule", part, "ciel ou haut de l'image brûlé : \(Bilan.nombre(part)) % du tiers haut en blanc pur")
            }
        }
        // Netteté et bruit : seulement à la taille où leurs seuils ont été relevés.
        if let detail, detail.side >= Detail.side {
            cherches.insert("flou")
            cherches.insert("bruit")
            if af != nil { cherches.insert("mise_au_point") }
            for defaut in PhotoTriee.defautsNettete(detail: detail, af: af) {
                switch defaut.genre {
                case .floue: trouve("flou", detail.sharpest, defaut.texte)
                case .miseAuPointManquee, .miseAuPointSignalee: trouve("mise_au_point", af?.nettete, defaut.texte)
                default: break
                }
            }
            let bruit = max(detail.noise, detail.shadowNoise ?? 0)
            if bruit >= DetailMeasurements.bruitFort {
                trouve("bruit", bruit, "bruit fort : \(Bilan.nombre(bruit, decimales: 2)) (seuil \(Bilan.nombre(DetailMeasurements.bruitFort)))")
            }
        }
        // L'ordre de PriseDeVue, pour les cherchés comme pour les trouvés.
        let ordre = PriseDeVue.mesures.map(\.code)
        return Vue(cherches: ordre.filter(cherches.contains),
                   defauts: trouves.sorted { (ordre.firstIndex(of: $0.code) ?? .max) < (ordre.firstIndex(of: $1.code) ?? .max) })
    }

    /// Une ligne horizontale penchée (measure_angle, read_composition), comptée au carnet : de
    /// `horizonMin` ou plus, sur une géométrie intacte (`geometrieIntacte`). Nil sinon : une ligne
    /// verticale (un poteau penché peut venir de la perspective), une ligne presque droite, une
    /// photo déjà redressée, ou passée par Upright ou la perspective.
    public static func constatHorizon(tilt: Double, vertical: Bool, angleActuel: Double, reglages: JSONValue?) -> Constat? {
        guard !vertical, tilt.isFinite, abs(tilt) >= horizonMin,
              geometrieIntacte(reglages: reglages, angleRecadrage: angleActuel) else { return nil }
        return Constat(code: "horizon_penche", mesure: tilt,
                       texte: "horizon ou ligne penchée de \(Bilan.nombre(abs(tilt)))° (\(tilt > 0 ? "monte" : "descend") vers la droite)")
    }

    /// L'angle tel que la commande carnet constater l'attend : { inclinaison, code, source }.
    static func angleJSON(_ constat: Constat, source: String) -> JSONValue {
        ["inclinaison": .number(((constat.mesure ?? 0) * 100).rounded() / 100), "code": .string(constat.code), "source": .string(source)]
    }

    /// Un texte borné en octets (UTF-8), coupé sur un caractère entier.
    static func borner(_ texte: String) -> String {
        guard texte.utf8.count > longueurTexte else { return texte }
        var coupe = ""
        for caractere in texte {
            guard coupe.utf8.count + String(caractere).utf8.count <= longueurTexte - 3 else { break }
            coupe.append(caractere)
        }
        return coupe + "…"
    }

    // MARK: export_journal

    /// Le carnet en Markdown (export_journal avec notebook), d'après le résumé que rend la commande
    /// carnet lire (Carnet.resumer du module) : ses titres et ses phrases tels quels, et le tableau
    /// des défauts par mois de prise de vue (« n/sur » : photos où le défaut a été trouvé, sur
    /// celles où il a été cherché ; « — » sans photo).
    public static func markdown(_ resume: JSONValue) -> String {
        let titres = resume["titres"]
        func titre(_ cle: String, _ defaut: String) -> String { titres?[cle]?.string ?? defaut }
        func cellule(_ texte: String) -> String { texte.replacingOccurrences(of: "|", with: "\\|") }
        var lignes = ["# \(titre("carnet", "Carnet de progrès"))", ""]
        if let note = resume["note"]?.string, !note.isEmpty { lignes += [note, ""] }
        if let remarque = resume["remarque"]?.string, !remarque.isEmpty { lignes += [remarque, ""] }
        let mois = resume["mois"]?.array ?? []
        let defauts = resume["defauts"]?.array ?? []
        func texte() -> String {
            while lignes.last == "" { lignes.removeLast() }
            return lignes.joined(separator: "\n")
        }
        guard resume["vide"]?.bool != true, !mois.isEmpty else { return texte() }

        // Le tableau : une colonne par mois (l'année dite quand les mois en changent).
        let annees = Set(mois.compactMap { $0["annee"]?.int })
        let entetes = mois.map { m -> String in
            let court = m["court"]?.string ?? m["nom"]?.string ?? m["cle"]?.string ?? "?"
            return annees.count > 1 ? "\(court) \(m["annee"]?.int.map(String.init) ?? "")".trimmingCharacters(in: .whitespaces) : court
        }
        lignes.append("| \(cellule(titre("defaut", "Défaut"))) | \(entetes.map(cellule).joined(separator: " | ")) |")
        lignes.append("| --- |\(String(repeating: " --- |", count: entetes.count))")
        for defaut in defauts {
            let parMois = defaut["par_mois"]?.array ?? []
            let cellules = mois.indices.map { i -> String in
                guard i < parMois.count, let sur = parMois[i]["sur"]?.int, sur > 0 else { return "—" }
                return "\(parMois[i]["n"]?.int ?? 0)/\(sur)"
            }
            let libelle = defaut["libelle"]?.string ?? defaut["code"]?.string ?? "?"
            lignes.append("| \(cellule(libelle)) | \(cellules.joined(separator: " | ")) |")
        }
        lignes.append("")

        func section(_ titreSection: String, _ elements: [JSONValue], texte: (JSONValue) -> String?) -> Bool {
            let puces = elements.compactMap(texte).filter { !$0.isEmpty }
            guard !puces.isEmpty else { return false }
            lignes += ["## \(titreSection)", ""] + puces.map { "- \($0)" } + [""]
            return true
        }
        let progresse = section(titre("progresse", "Ce qui progresse"), resume["progresse"]?.array ?? []) { $0["texte"]?.string }
        let recule = section(titre("recule", "Ce qui recule"), resume["recule"]?.array ?? []) { $0["texte"]?.string }
        if !progresse, !recule, let aucune = resume["aucune_tendance"]?.string, !aucune.isEmpty {
            lignes += ["## \(titre("progresse", "Ce qui progresse"))", "", aucune, ""]
        }
        let travailler = section(titre("a_travailler", "À travailler à la prochaine sortie"), resume["a_travailler"]?.array ?? []) { item in
            guard let texte = item["texte"]?.string else { return nil }
            return [texte, item["prise_de_vue"]?.string].compactMap { $0 }.joined(separator: " ")
        }
        if !travailler, let rien = resume["rien_a_travailler"]?.string, !rien.isEmpty {
            lignes += ["## \(titre("a_travailler", "À travailler à la prochaine sortie"))", "", rien, ""]
        }
        return texte()
    }

    // MARK: Relevé (--constats)

    /// Une ligne sur stderr avec `DEVELOPPEUR_VERBOSE=1` (jamais sur stdout, réservé au protocole).
    static func journaliser(_ message: String, environnement: [String: String] = ProcessInfo.processInfo.environment) {
        guard environnement["DEVELOPPEUR_VERBOSE"] == "1" else { return }
        FileHandle.standardError.write(Data("[mcp-developpeur] \(message)\n".utf8))
    }

    /// Ce qui se mesure d'une photo pour le relevé : l'aperçu décodé et ce que la commande apercu en
    /// dit (nil pour un fichier mesuré sans Lightroom).
    struct AMesurer {
        var nom: String
        var entete: String
        var image: CGImage
        var reponse: JSONValue?
    }

    /// Relevé des seuils du carnet (`--constats <id>… [<fichier.jpg>…]`), en lecture seule : la
    /// commande apercu comme view_photo (point_af, 1 344 px), sans jamais envoyer carnet constater ni
    /// rien écrire ; un fichier JPEG se mesure sans Lightroom (sans point de mise au point ni
    /// intention). Pour chaque photo : L* médian et 95e centile, blanc pur du tiers haut, netteté (au
    /// point de mise au point aussi), bruit, ce que dit le boîtier, la géométrie, les étapes de Claude,
    /// puis les défauts cherchés et retenus ; un résumé à la fin. Les lignes en échec commencent par ✘.
    public static func releve(lightroom: LightroomServing, ids: [Int], fichiers: [URL], lecteur: LecteurBoitier = LecteurBoitier(),
                              sortie: (String) -> Void = { _ in }) -> [String] {
        var lignes: [String] = []
        func dire(_ ligne: String) { lignes.append(ligne); sortie(ligne) }
        func n(_ valeur: Double?, _ decimales: Int = 1) -> String { valeur.map { Bilan.nombre($0, decimales: decimales) } ?? "—" }
        dire("Relevé des constats du carnet (lecture seule, rien n'est noté) : sous-exposition si L* médian < \(n(medianeSousExposee, 0)) "
            + "et 95e centile < \(n(p95SousExposee, 0)), ciel brûlé au-delà de \(n(partBlancPurHaut, 0)) % de blanc pur dans le tiers haut "
            + "(provisoires) ; netteté \(n(DetailMeasurements.seuilFlou, 0)) et \(n(DetailMeasurements.seuilNet, 0)), bruit fort "
            + "\(n(DetailMeasurements.bruitFort)) (relevés) ; horizon de \(n(horizonMin))° ou plus, par measure_angle ou read_composition seulement")
        var resume: [String] = []
        let sources: [(nom: String, charger: () throws -> AMesurer)] =
            ids.map { id in ("\(id)", { try apercu(id: id, lightroom: lightroom) }) }
            + fichiers.map { fichier in (fichier.lastPathComponent, { try lire(fichier) }) }
        for source in sources {
            let photo: AMesurer
            do {
                photo = try source.charger()
            } catch {
                dire("✘ \(source.nom) : \(error.localizedDescription)")
                continue
            }
            dire("")
            dire("■ " + photo.entete)
            let reduite = PreviewImages.scaled(photo.image, maxSide: Measurements.maxSide)
            guard let mesures = Measurements.analyze(reduite) else {
                dire("✘ \(photo.nom) : pixels illisibles")
                continue
            }
            let detail = Detail.analyze(PreviewImages.scaled(photo.image, maxSide: Detail.side))
            let reponse = photo.reponse
            let lecture = reponse.flatMap { ToolHandler.lectureBoitier($0["photo"], lecteur: lecteur) }
            var af: PhotoTriee.MiseAuPoint?
            if let point = ToolHandler.pointAF(lecture, description: reponse?["photo"]) {
                af = PhotoTriee.MiseAuPoint(point: point.point, nettete: Detail.nettete(photo.image, autour: point.point),
                                            avertissement: point.avertissement)
            }
            let intention = lecture?.intention
            let blanc = blancPurHaut(reduite)
            let p95 = mesures.percentilesL[95]
            dire("  L* médian \(n(mesures.medianL)) ; 95e centile \(n(p95)) ; blanc pur du tiers haut \(n(blanc)) % ; "
                + "netteté max \(n(detail?.sharpest))" + (detail.map { $0.side < Detail.side ? " (mesurée à \($0.side) px : sous les \(Detail.side) px des seuils)" : "" } ?? "")
                + " ; bruit \(n(detail?.noise, 2))" + (detail?.shadowNoise.map { " (ombres \(n($0, 2)))" } ?? ""))
            if reponse != nil {
                var point = "  Point de mise au point : "
                if let af {
                    point += "x \(n(Double(af.point.x), 3)) y \(n(Double(af.point.y), 3)), netteté autour \(n(af.nettete))"
                        + (af.avertissement ? ", signalé manqué par l'appareil" : "")
                } else {
                    point += "non lu (autre marque, original absent ou lecture trop longue)"
                }
                dire(point)
                if let intention {
                    var boitier = ["compensation " + (intention.compensation.map { Bilan.nombre($0, signe: true) + " IL" } ?? "non lue"),
                                   "nuit : " + (intention.nuit ? "oui" : "non")]
                    if let plage = intention.plageDynamique { boitier.append("plage dynamique DR\(plage.pourcent) (\(plage.auto ? "auto" : "réglée"))") }
                    dire("  Boîtier : " + boitier.joined(separator: " ; "))
                } else {
                    dire("  Boîtier : rien de lu (Fujifilm seulement)")
                }
            }
            var geometrie = true
            if let reponse {
                let angle = reponse["recadrage"]?["angle"]?.double ?? 0
                geometrie = geometrieIntacte(reglages: reponse["reglages"], angleRecadrage: angle)
                let etapes = reponse["etapes_claude"]?["nombre"]?.int
                dire("  Géométrie : \(geometrie ? "intacte" : "touchée (recadrage tourné, Upright, perspective ou distorsion)") ; étapes de Claude : "
                    + (etapes.map { $0 == 0 ? "aucune (view_photo la noterait)" : "\($0) (view_photo ne la noterait plus)" } ?? "inconnues"))
            }
            let vue = constatsVue(mesures: mesures, detail: detail, reduite: reduite, af: af, intention: intention, geometrieIntacte: geometrie)
            dire("  Cherchés : \(vue.cherches.joined(separator: ", "))")
            dire("  Retenus : " + (vue.defauts.isEmpty ? "aucun" : vue.defauts.map(\.texte).joined(separator: " ; ")))
            resume.append([photo.nom, n(mesures.medianL), n(p95), n(blanc), n(detail?.sharpest), n(af?.nettete),
                           n(detail.map { max($0.noise, $0.shadowNoise ?? 0) }, 2),
                           vue.defauts.isEmpty ? "—" : vue.defauts.map(\.code).joined(separator: ",")].joined(separator: "\t"))
        }
        if !resume.isEmpty {
            dire("")
            dire("Résumé (photo, L* médian, 95e centile, blanc pur du tiers haut %, netteté max, netteté au point AF, bruit, retenus) :")
            for ligne in resume { dire(ligne) }
        }
        return lignes
    }

    /// Un fichier JPEG (ou toute image lisible par ImageIO), mesuré sans Lightroom.
    static func lire(_ fichier: URL) throws -> AMesurer {
        let data = try Data(contentsOf: fichier)
        guard let image = PreviewImages.image(data) else { throw LightroomError.plugin("image illisible") }
        return AMesurer(nom: fichier.lastPathComponent,
                        entete: "\(fichier.lastPathComponent) · \(image.width) × \(image.height) (fichier, sans Lightroom ni point de mise au point)",
                        image: image, reponse: nil)
    }

    /// L'aperçu d'une photo de Lightroom, comme view_photo l'entier : 1 344 px, point_af (description
    /// pour le point de mise au point, étapes de Claude), les clés de la géométrie. Lecture seule.
    static func apercu(id: Int, lightroom: LightroomServing) throws -> AMesurer {
        let reponse = try lightroom.send("apercu", ["photo": .number(Double(id)), "taille": .number(Double(ToolHandler.defaultPreviewSize)),
                                                    "cles": .array(clesGeometrie.map(JSONValue.string)), "point_af": true], timeout: 120)
        let data = try ToolHandler.readPreview(reponse["chemin"]?.string)
        guard let image = PreviewImages.image(data) else { throw LightroomError.plugin("aperçu illisible") }
        let fichier = reponse["photo"]?["fichier"]?.string ?? "photo"
        return AMesurer(nom: "\(id)", entete: "\(fichier) (id \(id)) · \(image.width) × \(image.height)", image: image, reponse: reponse)
    }
}
