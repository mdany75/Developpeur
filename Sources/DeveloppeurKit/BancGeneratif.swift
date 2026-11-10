import Foundation

/// Le banc d'essai de la retouche générative (`mcp-developpeur --generatif-banc`, développement
/// seulement ; demandé le 10 novembre 2026 pour choisir le meilleur modèle par genre de retouche) : la
/// même retouche (même photo, même consigne, même zone, même graine) par chaque modèle branché et
/// présent sur ce Mac, l'un après l'autre (un calcul à la fois, comme generative_edit), puis une
/// planche HTML locale que Dany juge (le meilleur modèle et une note pour chacun ; le JSON du jugement
/// à copier). Chaque passage est un vrai generative_edit (exportation, masque de Lightroom, mflux,
/// SeedVR2, recomposition) avec `ToolHandler.dossierBanc` posé : le résultat reste en JPEG dans le
/// dossier de la planche, rien n'est importé, le catalogue ne change pas (les rendus témoins d'un
/// masque laissent leurs étapes « Claude · essai » dans l'Historique, comme toujours). Sur une copie
/// virtuelle de « Développeur › Essais » que Dany désigne, jamais retouchée par Claude : contrôlée
/// avant tout calcul comme la photo d'essai de la recette (`Recette.sequence`), puis remise à la fin
/// (revert_to_original, comme la recette : seul ce que Claude a fait pendant le banc est défait),
/// relue identique au départ et remise dans Essais si elle en est sortie (revue du 10 novembre 2026).
public struct BancGeneratif {
    /// Grand côté des images de la planche (photo entière) et des zones.
    static let coteImage = 2048
    static let coteZone = 1600
    static let nomPlanche = "planche-generatif.html"
    /// La graine du banc sans seed : la même pour tous les modèles.
    static let graineParDefaut = 42

    let tools: ToolHandler
    let journal: (String) -> Void

    public init(tools: ToolHandler, journal: @escaping (String) -> Void = { _ in }) {
        self.tools = tools
        self.journal = journal
    }

    /// Un passage du banc : le modèle, ce qu'il a rendu (ou pourquoi rien).
    struct Passage {
        var modele: ModeleGeneratif
        var absent: String?
        var erreur: String?
        var reponse: JSONValue?
        var secondes: Double = 0
    }

    /// Le banc : `arguments` est un appel de generative_edit (photo_id exigé ; instruction et
    /// instruction_fr, region, mask ou reference, label, seed, confirm…), sans model ; `modeles` : les
    /// ids à passer (nil : tous les modèles branchés) ; `dossier` : celui de la planche et des images.
    public func lancer(arguments: [String: JSONValue], modeles: [String]? = nil, dossier: URL) throws -> JSONValue {
        guard let fibo = tools.fibo else {
            throw LightroomError.invalid("Fibo 2 n'est pas configuré : banc impossible.")
        }
        guard let photo = arguments["photo_id"]?.int else {
            throw LightroomError.invalid("Le banc d'essai exige photo_id : une copie virtuelle de « Développeur › Essais », remise à l'origine. Rien n'a été fait.")
        }
        // « model »: null compte : le banc passe chaque modèle lui-même.
        guard arguments.index(forKey: "model") == nil else {
            throw LightroomError.invalid("Le banc d'essai passe chaque modèle lui-même : sans model (--modeles pour en choisir). Rien n'a été fait.")
        }
        let liste: [ModeleGeneratif]
        if let modeles {
            liste = try modeles.map { id in
                guard let m = ModeleGeneratif(rawValue: id), m.fiche.branche else {
                    throw LightroomError.invalid("--modeles : \(ModeleGeneratif.allCases.filter { $0.fiche.branche }.map(\.rawValue).joined(separator: ", ")) (pas « \(id) »).")
                }
                return m
            }
        } else {
            liste = ModeleGeneratif.allCases.filter { $0.fiche.branche }
        }
        var appel = arguments
        if appel["seed"] == nil { appel["seed"] = .number(Double(Self.graineParDefaut)) }
        let depart = try controlerPhoto(photo)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        tools.dossierBanc = dossier
        defer { tools.dossierBanc = nil }
        var passages: [Passage] = []
        for modele in liste {
            var passage = Passage(modele: modele)
            if let raison = fibo.raisonAbsent(modele) ?? (FileManager.default.isExecutableFile(atPath: fibo.executable(pour: modele).path) ? nil
                : "la commande \(modele.fiche.executable) est introuvable sur ce Mac") {
                passage.absent = raison
                journal("\(modele.fiche.nom) : absent (\(raison))")
                passages.append(passage)
                continue
            }
            journal("\(modele.fiche.nom) : retouche en cours…")
            var args = appel
            args["model"] = .string(modele.rawValue)
            let debut = Date()
            let resultat = tools.call(name: "generative_edit", arguments: args)
            passage.secondes = Date().timeIntervalSince(debut)
            if resultat.isError {
                passage.erreur = resultat.text
                journal("\(modele.fiche.nom) : échec (\(resultat.text.prefix(200)))")
            } else {
                passage.reponse = try? JSONCoding.parse(resultat.text)
                journal("\(modele.fiche.nom) : fini en \(Int(passage.secondes.rounded())) s")
            }
            passages.append(passage)
        }
        tools.dossierBanc = nil
        let remise = remettre(photo, depart)
        let planche = dossier.appendingPathComponent(Self.nomPlanche)
        try Data(Self.planche(passages, appel: appel).utf8).write(to: planche, options: .atomic)
        return [
            "ok": .bool(passages.contains { $0.reponse != nil } && remise.ok),
            "planche": .string(planche.path),
            "graine": appel["seed"] ?? .null,
            "photo": .string(remise.texte),
            "modeles": .array(passages.map(Self.decrire)),
        ]
    }

    // MARK: Photo d'essai

    /// Ce qui doit revenir à la fin : réglages et masques, comme `Recette.Etat` les compare.
    struct Depart: Equatable {
        var reglages: JSONValue
        var masques: JSONValue
        var dansEssais: Bool
    }

    /// Un outil appelé pour le banc ; son erreur arrête le banc.
    func outil(_ nom: String, _ arguments: [String: JSONValue]) throws -> JSONValue {
        let resultat = tools.call(name: nom, arguments: arguments)
        if resultat.isError { throw LightroomError.plugin("\(nom) : \(resultat.text)") }
        return try JSONCoding.parse(resultat.text)
    }

    /// Les contrôles de la photo d'essai de la recette, avant tout calcul : une copie virtuelle (le
    /// module doit le dire), rangée dans « Développeur › Essais », que Claude n'a pas encore retouchée
    /// (le retour à l'origine de la fin effacerait ses retouches d'avant).
    func controlerPhoto(_ id: Int) throws -> Depart {
        let reglages = try outil("get_settings", ["photo_id": .number(Double(id))])
        guard let virtuelle = reglages["photo"]?["copie_virtuelle"]?.bool else {
            throw LightroomError.invalid("Le module Lightroom ne dit pas si la photo \(id) est une copie virtuelle : installer la même version que ce serveur. Rien n'a été fait.")
        }
        guard virtuelle else {
            throw LightroomError.invalid("La photo \(id) est un original : le banc d'essai ne travaille que sur une copie virtuelle de « \(Recette.collectionDeRecette) ». Rien n'a été fait.")
        }
        let essais = try outil("find_photos", ["collection": .string(Recette.collectionDeRecette), "limit": 500])
        guard let trouvee = essais["photos"]?.array?.first(where: { $0["id"]?.int == id }) else {
            throw LightroomError.invalid("La photo \(id) n'est pas dans « \(Recette.collectionDeRecette) » : le banc d'essai ne travaille que sur une copie d'essai. Rien n'a été fait.")
        }
        guard trouvee["retouchee_par_claude"]?.bool != true else {
            throw LightroomError.invalid("Claude a déjà retouché la photo \(id) : la remise à l'origine de la fin effacerait aussi ces retouches ; en prendre une autre (une nouvelle copie virtuelle, remise à l'origine). Rien n'a été fait.")
        }
        return Depart(reglages: reglages["reglages"] ?? .null, masques: reglages["masques"] ?? .array([]), dansEssais: true)
    }

    /// La photo remise comme au départ : revert_to_original (ce que Claude y a fait pendant le banc),
    /// réglages et masques relus identiques, puis remise dans Essais, que le retour à l'origine défait
    /// aussi (mémoire Bibliotheque). Les étapes « Claude · essai » restent des lignes de l'Historique
    /// de Lightroom, qu'un module ne retire pas ; la photo, elle, est revenue.
    func remettre(_ id: Int, _ depart: Depart) -> (ok: Bool, texte: String) {
        do {
            _ = try outil("revert_to_original", ["photo_ids": [.number(Double(id))]])
            let relue = try outil("get_settings", ["photo_id": .number(Double(id))])
            guard relue["reglages"] ?? .null == depart.reglages, relue["masques"] ?? .array([]) == depart.masques else {
                return (false, "photo \(id) PAS revenue comme au départ après revert_to_original : la vérifier dans Lightroom (⌘Z, ou Développement › Réinitialiser).")
            }
            let essais = try outil("find_photos", ["collection": .string(Recette.collectionDeRecette), "limit": 500])
            if !(essais["photos"]?.array ?? []).contains(where: { $0["id"]?.int == id }) {
                _ = try outil("manage_collections", ["action": "add", "collection": .string(Recette.collectionDeRecette),
                                                     "photo_ids": [.number(Double(id))], "step_name": "banc d'essai", "confirm": true])
            }
            return (true, "photo \(id) remise comme au départ (revert_to_original, réglages et masques relus)")
        } catch {
            return (false, "photo \(id) : remise impossible (\(error)) ; la vérifier dans Lightroom.")
        }
    }

    static func decrire(_ p: Passage) -> JSONValue {
        var objet: [String: JSONValue] = ["id": .string(p.modele.rawValue), "nom": .string(p.modele.fiche.nom),
                                          "statut": .string(p.modele.fiche.statut.rawValue)]
        if let absent = p.absent { objet["absent"] = .string(absent) }
        if let erreur = p.erreur { objet["erreur"] = .string(erreur) }
        if let r = p.reponse {
            objet["duree_s"] = .number(p.secondes.rounded())
            objet["duree_calcul_s"] = r["duree_fibo_s"] ?? .null
            objet["images"] = r["banc"] ?? .null
            objet["part_changee_pct"] = .array((r["modifications"]?.array ?? []).map { $0["part_changee_pct"] ?? .null })
        }
        return .object(objet)
    }

    // MARK: Planche

    /// Ce que le modèle a reçu comme consigne : Fibo 2, la fiche de FIBO-vlm quand elle a été rédigée
    /// (sinon la phrase seule) ; tout autre modèle, la phrase seule (la fiche est propre à Fibo 2), ce
    /// qui pèse dans le jugement de la planche.
    static func consigneRecue(_ modele: ModeleGeneratif, _ reponse: JSONValue) -> String {
        guard modele == .fibo2 else { return "la phrase seule (la fiche de FIBO-vlm est propre à Fibo 2)" }
        return reponse["fiche_fibo_vlm"]?.bool == true ? "la fiche détaillée de FIBO-vlm" : "la phrase seule (sans fiche de FIBO-vlm)"
    }

    static func echapper(_ texte: String) -> String { EssaiEspeces.echapper(texte) }

    /// La page HTML : la consigne, la photo avant, puis une carte par modèle (avant et après de la zone
    /// côte à côte, la photo entière en lien, durée, part changée, remarques), un choix « le meilleur »
    /// et une note par modèle, qui composent le JSON du jugement à copier.
    static func planche(_ passages: [Passage], appel: [String: JSONValue]) -> String {
        let consigne = appel["instruction_fr"]?.string ?? appel["edits"]?.array?.compactMap { $0["instruction_fr"]?.string }.joined(separator: " ; ") ?? ""
        let instruction = appel["instruction"]?.string ?? appel["edits"]?.array?.compactMap { $0["instruction"]?.string }.joined(separator: " ; ") ?? ""
        let zone: String = appel["mask"] != nil ? "masque de Lightroom" : appel["region"] != nil ? "region" : appel["edits"] != nil ? "plusieurs regions" : "toute la photo"
        var cartes = ""
        for p in passages {
            let f = p.modele.fiche
            var contenu: String
            if let absent = p.absent {
                contenu = "<p class=\"vide\">Absent de ce Mac : \(echapper(absent))</p>"
            } else if let erreur = p.erreur {
                contenu = "<p class=\"vide\">Échec : \(echapper(String(erreur.prefix(600))))</p>"
            } else if let r = p.reponse {
                let banc = r["banc"]
                func img(_ cle: String, _ legende: String) -> String {
                    guard let chemin = banc?[cle]?.string else { return "" }
                    return "<figure><a href=\"\(echapper(chemin))\"><img src=\"\(echapper(chemin))\" alt=\"\(echapper(legende))\" loading=\"lazy\"></a><figcaption>\(echapper(legende))</figcaption></figure>"
                }
                let images = banc?["zone"] != nil
                    ? img("avant_zone", "avant (zone)") + img("zone", "après (zone)")
                    : img("avant", "avant") + img("image", "après")
                let parts = (r["modifications"]?.array ?? []).compactMap { $0["part_changee_pct"]?.double }.map { Bilan.nombre($0, decimales: 1) + " %" }
                let remarques = ["remarque_modele", "remarque_zones", "remarque", "remarque_lightroom"].compactMap { r[$0]?.string }
                    + (r["modifications"]?.array ?? []).flatMap { m in ["remarque_seedvr2", "a_verifier", "remarque_transparence"].compactMap { m[$0]?.string } }
                contenu = """
                <div class="paire">\(images)</div>
                <p class="lien"><a href="\(echapper(banc?["image"]?.string ?? ""))">photo entière après</a></p>
                <dl><dt>durée</dt><dd>\(Int(p.secondes.rounded())) s (calcul \(r["duree_fibo_s"]?.int ?? 0) s)</dd><dt>part changée</dt><dd>\(parts.joined(separator: ", "))</dd><dt>qualité</dt><dd>\(echapper(r["qualite"]?.string ?? ""))</dd><dt>consigne reçue</dt><dd>\(echapper(Self.consigneRecue(p.modele, r)))</dd></dl>
                \(remarques.map { "<p class=\"remarque\">\(echapper($0))</p>" }.joined())
                <label class="choix"><input type="radio" name="meilleur" value="\(p.modele.rawValue)"> le meilleur</label>
                <textarea class="note" data-id="\(p.modele.rawValue)" placeholder="Note (raccord, fidélité, détail, visage…)"></textarea>
                """
            } else {
                contenu = "<p class=\"vide\">Réponse illisible.</p>"
            }
            cartes += """
            <section class="carte">
              <h2>\(echapper(f.nom)) <span class="statut">\(echapper(f.statut.rawValue))</span></h2>
              <p class="doux">\(echapper(f.pourQuoi))</p>
              \(contenu)
            </section>

            """
        }
        let photo = appel["photo_id"]?.int ?? 0
        let graine = appel["seed"]?.int ?? graineParDefaut
        let entete = JSONCoding.line(["photo_id": .number(Double(photo)), "instruction": .string(instruction), "graine": .number(Double(graine)),
                                      "zone": .string(zone)]).replacingOccurrences(of: "</", with: "<\\/")
        let avant = passages.compactMap { $0.reponse?["banc"]?["avant"]?.string }.first
        return """
        <!doctype html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Banc des modèles</title>
        <style>
        :root { --fond: #f6f5f2; --carte: #ffffff; --texte: #1d1d1b; --doux: #6b6a66; --bord: #dcdad4; --accent: #2f6d9e; }
        @media (prefers-color-scheme: dark) { :root { --fond: #1b1b1a; --carte: #262624; --texte: #ecebe7; --doux: #a3a19b; --bord: #3a3936; --accent: #7fb3dd; } }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 16px; background: var(--fond); color: var(--texte); font: 14px/1.45 -apple-system, system-ui, sans-serif; }
        h1 { font-size: 20px; margin: 0 0 4px; } h2 { font-size: 16px; margin: 0 0 4px; }
        .doux, .statut, figcaption { color: var(--doux); } .statut { font-weight: 400; font-size: 13px; }
        .consigne { max-width: 60em; margin: 0 0 12px; }
        .avant img { max-width: 100%; max-height: 50vh; border-radius: 6px; }
        .carte { background: var(--carte); border: 1px solid var(--bord); border-radius: 8px; padding: 12px; margin: 12px 0; }
        .paire { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 8px; }
        figure { margin: 0; } figure img { display: block; width: 100%; height: auto; border-radius: 4px; background: #000; }
        dl { display: grid; grid-template-columns: auto 1fr; gap: 0 8px; margin: 8px 0; font-variant-numeric: tabular-nums; }
        dd { margin: 0; } .remarque { color: var(--doux); font-size: 13px; margin: 4px 0; }
        .vide { color: var(--doux); }
        .choix { display: inline-flex; gap: 6px; align-items: center; font-weight: 600; margin: 6px 0; }
        textarea { width: 100%; min-height: 3em; font: inherit; background: var(--fond); color: var(--texte); border: 1px solid var(--bord); border-radius: 6px; padding: 6px; }
        #json { height: 6em; font: 12px ui-monospace, monospace; }
        .jugement { position: sticky; top: 0; z-index: 1; background: var(--fond); padding: 8px 0; }
        button { padding: 6px 12px; border-radius: 6px; border: 1px solid var(--bord); background: transparent; color: var(--texte); font: inherit; cursor: pointer; }
        a { color: var(--accent); }
        </style>
        </head>
        <body>
        <h1>Banc des modèles de retouche générative</h1>
        <p class="consigne"><strong>\(echapper(consigne))</strong><br><span class="doux">\(echapper(instruction)) — photo \(photo), \(echapper(zone)), graine \(graine) pour tous les modèles.</span></p>
        <p class="doux">Choisir le meilleur rendu (raccord invisible, rien d'autre de changé, détail, fidélité à la consigne), noter chaque modèle, puis copier le jugement pour Claude.</p>
        \(avant.map { "<figure class=\"avant\"><img src=\"\(echapper($0))\" alt=\"avant\"><figcaption>la photo avant</figcaption></figure>" } ?? "")
        <div class="jugement">
        <textarea id="json" readonly></textarea>
        <button type="button" id="copier">Copier le jugement</button>
        </div>
        \(cartes)
        <script>
        const ENTETE = \(entete);
        function rendre() {
          const choisi = document.querySelector('input[name="meilleur"]:checked');
          const notes = {};
          document.querySelectorAll('textarea.note').forEach(t => { if (t.value.trim()) notes[t.dataset.id] = t.value.trim(); });
          document.getElementById('json').value = JSON.stringify(Object.assign({}, ENTETE, { meilleur: choisi ? choisi.value : null, notes: notes }));
        }
        document.querySelectorAll('input[name="meilleur"], textarea.note').forEach(e => e.addEventListener('input', rendre));
        document.getElementById('copier').addEventListener('click', () => {
          const zone = document.getElementById('json');
          zone.select();
          try { navigator.clipboard.writeText(zone.value); } catch (e) { try { document.execCommand('copy'); } catch (e2) {} }
        });
        rendre();
        </script>
        </body>
        </html>

        """
    }
}
