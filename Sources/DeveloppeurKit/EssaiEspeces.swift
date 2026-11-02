import CoreGraphics
import Foundation

/// `--especes-essai` (développement, pour fixer les seuils provisoires des espèces, 1.6.3) : les photos
/// d'une source d'essai (dossier de JPEG, collection, dossier du catalogue ou ids, comme
/// `--sens-essai` : `EssaiSens.photos`), chacune classée par BioCLIP 2 après la porte MobileCLIP.
/// Chaque photo dit l'espèce proposée et ses trois mesures : la porte (part « animal ou plante »), le
/// score BioCLIP de la première espèce et son écart à la deuxième. Une planche HTML (une case par
/// photo, boutons juste et faux) compose le jugement de Dany, un petit JSON ; redonné par
/// `--jugement`, il dit quels seuils sépareraient le mieux justes et faux (`EssaiEspeces.seuils`).
/// Lecture seule : les commandes `chercher` et `vignettes` du module, rien n'est écrit au catalogue.
public final class EssaiEspeces {
    public static let nomPlanche = "planche-especes.html"
    /// Grand côté des vignettes rangées dans la planche (la page reste légère : 200 photos ≈ 4 Mo).
    static let cotePlanche = 320

    let lightroom: LightroomServing?
    let classeur: ClasseurEspeces
    let dire: (String) -> Void

    public init(lightroom: LightroomServing?, classeur: ClasseurEspeces, dire: @escaping (String) -> Void = { _ in }) {
        self.lightroom = lightroom
        self.classeur = classeur
        self.dire = dire
    }

    /// Les trois mesures d'un classement, arrondies au millième : porte (nil sans porte), score de la
    /// première espèce, écart entre la première et la deuxième.
    static func mesures(_ resultat: ClasseurEspeces.Resultat) -> (porte: Double?, score: Double, ecart: Double) {
        let deux = resultat.meilleures(2)
        let premier = deux.first?.probabilite ?? 0
        let second = deux.count > 1 ? deux[1].probabilite : 0
        func arrondi(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }
        return (resultat.nature.map(arrondi), arrondi(premier), arrondi(premier - second))
    }

    /// Une case de la planche.
    struct Case {
        var id: Int
        var fichier: String
        var nom: String
        var latin: String
        var trouvee: Bool
        var porte: Double?
        var score: Double
        var ecart: Double
        var vignette: Data?
    }

    /// L'essai entier : la ligne JSON finale. `planche` : le dossier où écrire la planche HTML.
    public func lancer(source: EssaiSens.Source, nombre: Int = 200, cible: Especes.Cible? = nil, planche: URL? = nil) throws -> JSONValue {
        let photos = try EssaiSens.photos(source, nombre: nombre, taille: Especes.tailleVignette, lightroom: lightroom,
                                          option: "--especes-essai", dire: dire)
        var lignes: [JSONValue] = []
        var cases: [Case] = []
        var durees: [Double] = []
        for photo in photos {
            guard let image = photo.image else {
                lignes.append(["id": .number(Double(photo.id)), "fichier": .string(photo.fichier), "erreur": .string(photo.erreur ?? "illisible")])
                continue
            }
            let debut = Date()
            let resultat = try classeur.classer(image: image)
            durees.append(Date().timeIntervalSince(debut))
            let m = Self.mesures(resultat)
            let premiere = resultat.meilleures(1).first.map { classeur.liste.especes[$0.indice] }
            var ligne: [String: JSONValue] = [
                "id": .number(Double(photo.id)), "fichier": .string(photo.fichier), "espece": classeur.json(resultat),
                "nature": m.porte.map(JSONValue.number) ?? .null,
                "scores": ["porte": m.porte.map(JSONValue.number) ?? .null, "bioclip": .number(m.score), "ecart": .number(m.ecart)],
                "trois_premieres": .array(resultat.meilleures(3).map { p in
                    let e = classeur.liste.especes[p.indice]
                    return ["nom": .string(e.nom), "latin": .string(e.latin), "probabilite": .number((p.probabilite * 1000).rounded() / 1000)]
                }),
            ]
            if let cible {
                let indices: [Int]
                switch cible {
                case .espece(let i): indices = [i]
                case .groupe(let g): indices = classeur.liste.indices(g)
                }
                ligne["score_cherche"] = .number((resultat.somme(indices) * 1000).rounded() / 1000)
            }
            lignes.append(.object(ligne))
            if planche != nil {
                cases.append(Case(id: photo.id, fichier: photo.fichier, nom: premiere?.nom ?? "", latin: premiere?.latin ?? "",
                                  trouvee: classeur.json(resultat)["trouvee"]?.bool == true, porte: m.porte, score: m.score, ecart: m.ecart,
                                  vignette: PreviewImages.jpeg(PreviewImages.scaled(image, maxSide: Self.cotePlanche), quality: 0.8)))
            }
            dire("\(photo.fichier) : \(premiere?.nom ?? "?")")
        }
        let premiere = durees.first ?? 0
        let suivantes = durees.dropFirst()
        var resultat: [String: JSONValue] = [
            "ok": true, "modele": .string(Especes.nomModele), "especes": .number(Double(classeur.liste.especes.count)),
            "depuis_le_cache": .bool(classeur.depuisLeCache),
            "seuils_provisoires": ["confiance": .number(Especes.seuilConfianceProvisoire), "recherche": .number(Especes.seuilRechercheProvisoire),
                                   "groupe": .number(Especes.seuilGroupeProvisoire), "porte": .number(Especes.seuilPorteProvisoire)],
            "porte": .bool(classeur.aUnePorte), "photos": .number(Double(photos.count)),
            "temps": ["premiere_image_ms": .number((premiere * 1000).rounded()),
                      "image_ms_moyen": .number(suivantes.isEmpty ? 0 : (suivantes.reduce(0, +) / Double(suivantes.count) * 1000).rounded())],
            "images": .array(lignes),
        ]
        if let planche {
            try FileManager.default.createDirectory(at: planche, withIntermediateDirectories: true)
            let fichier = planche.appendingPathComponent(Self.nomPlanche)
            try Data(Self.planche(cases, aUnePorte: classeur.aUnePorte).utf8).write(to: fichier, options: .atomic)
            resultat["planche"] = .string(fichier.path)
        }
        return .object(resultat)
    }

    // MARK: Planche

    static func echapper(_ texte: String) -> String {
        texte.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// La page HTML : une case par photo (vignette, espèce proposée, porte, score, écart) et deux
    /// boutons, juste et faux, qui composent le JSON du jugement à copier (`--jugement`).
    static func planche(_ cases: [Case], aUnePorte: Bool) -> String {
        let donnees: [JSONValue] = cases.map { c in
            ["id": .number(Double(c.id)), "fichier": .string(c.fichier), "espece": .string(c.nom), "latin": .string(c.latin),
             "porte": c.porte.map(JSONValue.number) ?? .null, "score": .number(c.score), "ecart": .number(c.ecart)]
        }
        let json = JSONCoding.line(.array(donnees)).replacingOccurrences(of: "</", with: "<\\/")
        var corps = ""
        for (i, c) in cases.enumerated() {
            let image = c.vignette.map { "<img src=\"data:image/jpeg;base64,\($0.base64EncodedString())\" alt=\"\(echapper(c.fichier))\">" }
                ?? "<div class=\"vide\">sans vignette</div>"
            let porte = c.porte.map { Bilan.nombre($0, decimales: 2) } ?? "—"
            corps += """
            <figure class="case" data-i="\(i)">
              \(image)
              <figcaption>
                <div class="fichier">\(echapper(c.fichier))</div>
                <div class="nom\(c.trouvee ? "" : " incertaine")">\(echapper(c.nom))</div>
                <div class="latin">\(echapper(c.latin))</div>
                <dl><dt>porte</dt><dd>\(porte)</dd><dt>score</dt><dd>\(Bilan.nombre(c.score, decimales: 2))</dd><dt>écart</dt><dd>\(Bilan.nombre(c.ecart, decimales: 2))</dd></dl>
                <div class="boutons"><button type="button" class="juste" data-i="\(i)" data-v="1">Juste</button><button type="button" class="faux" data-i="\(i)" data-v="0">Faux</button></div>
              </figcaption>
            </figure>

            """
        }
        return """
        <!doctype html>
        <html lang="fr">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Planche des espèces</title>
        <style>
        :root { --fond: #f6f5f2; --carte: #ffffff; --texte: #1d1d1b; --doux: #6b6a66; --bord: #dcdad4; --juste: #2f7d4f; --faux: #b23a3a; }
        @media (prefers-color-scheme: dark) { :root { --fond: #1b1b1a; --carte: #262624; --texte: #ecebe7; --doux: #a3a19b; --bord: #3a3936; --juste: #5fbf86; --faux: #e07b7b; } }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 16px; background: var(--fond); color: var(--texte); font: 14px/1.4 -apple-system, system-ui, sans-serif; }
        h1 { font-size: 20px; margin: 0 0 4px; }
        p.aide { color: var(--doux); margin: 0 0 12px; max-width: 60em; }
        .grille { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; }
        .case { margin: 0; background: var(--carte); border: 2px solid var(--bord); border-radius: 8px; overflow: hidden; }
        .case.j1 { border-color: var(--juste); } .case.j0 { border-color: var(--faux); }
        .case img, .vide { display: block; width: 100%; aspect-ratio: 1; object-fit: contain; background: #000; }
        .vide { color: #aaa; display: grid; place-items: center; }
        figcaption { padding: 8px; }
        .fichier, .latin { color: var(--doux); font-size: 12px; overflow-wrap: anywhere; }
        .nom { font-weight: 600; } .nom.incertaine::after { content: " (sous le seuil)"; font-weight: 400; color: var(--doux); }
        .latin { font-style: italic; }
        dl { display: grid; grid-template-columns: auto 1fr; gap: 0 8px; margin: 6px 0; font-variant-numeric: tabular-nums; }
        dt { color: var(--doux); } dd { margin: 0; }
        .boutons { display: flex; gap: 6px; }
        button { flex: 1; padding: 6px; border-radius: 6px; border: 1px solid var(--bord); background: transparent; color: var(--texte); font: inherit; cursor: pointer; }
        .case.j1 button.juste { background: var(--juste); color: #fff; } .case.j0 button.faux { background: var(--faux); color: #fff; }
        .jugement { position: sticky; top: 0; z-index: 1; background: var(--fond); padding: 8px 0 12px; }
        textarea { width: 100%; height: 6em; font: 12px ui-monospace, monospace; background: var(--carte); color: var(--texte); border: 1px solid var(--bord); border-radius: 6px; }
        .ligne { display: flex; gap: 8px; align-items: center; margin-top: 6px; } .ligne button { flex: 0 0 auto; padding: 6px 12px; }
        </style>
        </head>
        <body>
        <h1>Planche des espèces (\(cases.count) photos)</h1>
        <p class="aide">Pour chaque photo, « Juste » si l'espèce proposée est la bonne, « Faux » sinon. Copier ensuite le jugement dans un fichier JSON et le redonner : <code>mcp-developpeur --especes-essai --jugement &lt;fichier.json&gt;</code>. Porte : part « animal ou plante » (MobileCLIP\(aUnePorte ? "" : ", absente de cet essai")) ; score : BioCLIP 2 pour la première espèce ; écart : sa marge sur la deuxième.</p>
        <div class="jugement">
        <textarea id="json" readonly></textarea>
        <div class="ligne"><button type="button" id="copier">Copier le jugement</button><span id="compte"></span></div>
        </div>
        <div class="grille">
        \(corps)</div>
        <script>
        const PHOTOS = \(json);
        const jugements = {};
        function rendre() {
          const liste = PHOTOS.map((p, i) => i in jugements ? Object.assign({}, p, { juste: jugements[i] }) : null).filter(Boolean);
          document.getElementById('json').value = JSON.stringify({ modele: '\(Especes.nomModele)', jugements: liste });
          const justes = liste.filter(j => j.juste).length;
          document.getElementById('compte').textContent = liste.length + ' sur ' + PHOTOS.length + ' jugées : ' + justes + ' justes, ' + (liste.length - justes) + ' faux';
        }
        document.querySelectorAll('.boutons button').forEach(b => b.addEventListener('click', () => {
          const i = Number(b.dataset.i), v = b.dataset.v === '1';
          if (jugements[i] === v) delete jugements[i]; else jugements[i] = v;
          const fig = document.querySelector('figure[data-i="' + i + '"]');
          fig.classList.remove('j1', 'j0');
          if (i in jugements) fig.classList.add(jugements[i] ? 'j1' : 'j0');
          rendre();
        }));
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

    // MARK: Seuils d'après le jugement

    /// Les seuils qui sépareraient le mieux justes et faux, mesure par mesure (porte, score, écart) :
    /// une photo est gardée si sa mesure atteint le seuil. Le meilleur seuil garde le plus de justes et
    /// écarte le plus de faux ensemble (à égalité, le plus bas : il perd le moins de justes) ; le seuil
    /// provisoire en usage est jugé de même. `jugement` : le JSON de la planche (ou sa seule liste).
    public static func seuils(_ jugement: JSONValue) -> JSONValue {
        let liste = jugement["jugements"]?.array ?? jugement.array ?? []
        let juges = liste.compactMap { j -> (JSONValue, Bool)? in j["juste"]?.bool.map { (j, $0) } }
        let justes = juges.filter(\.1).count
        let faux = juges.count - justes
        var resultat: [String: JSONValue] = ["ok": true, "jugees": .number(Double(juges.count)), "justes": .number(Double(justes)),
                                             "faux": .number(Double(faux))]
        guard justes > 0, faux > 0 else {
            resultat["remarque"] = "Il faut au moins une espèce juste et une fausse pour placer un seuil."
            return .object(resultat)
        }
        let provisoires: [String: Double] = ["porte": Especes.seuilPorteProvisoire, "score": Especes.seuilConfianceProvisoire]
        let noms = ["porte": "porte MobileCLIP", "score": "score BioCLIP", "ecart": "écart au 2e"]
        var mesures: [String: JSONValue] = [:]
        var phrases: [String] = []
        var meilleure: (cle: String, exactitude: Double)?
        for cle in ["porte", "score", "ecart"] {
            let paires = juges.compactMap { j, v -> (Double, Bool)? in j[cle]?.double.map { ($0, v) } }
            let j = paires.filter(\.1).count, f = paires.count - j
            guard j > 0, f > 0 else {
                mesures[cle] = ["remarque": "Pas mesurée, ou sans juste et faux à la fois."]
                continue
            }
            func juger(_ seuil: Double) -> (justesGardes: Int, fauxEcartes: Int) {
                (paires.filter { $0.1 && $0.0 >= seuil }.count, paires.filter { !$0.1 && $0.0 < seuil }.count)
            }
            let valeurs = Array(Set(paires.map(\.0))).sorted()
            var candidats = [valeurs[0]]
            for (a, b) in zip(valeurs, valeurs.dropFirst()) { candidats.append((a + b) / 2) }
            candidats.append(valeurs[valeurs.count - 1] + 0.001)
            var choisi = (seuil: candidats[0], j: 0, f: 0)
            var meilleurTotal = -1
            for s in candidats {
                let r = juger(s)
                if r.justesGardes + r.fauxEcartes > meilleurTotal {
                    meilleurTotal = r.justesGardes + r.fauxEcartes
                    choisi = (s, r.justesGardes, r.fauxEcartes)
                }
            }
            let exactitude = Double(choisi.j + choisi.f) / Double(paires.count)
            let minJuste = paires.filter(\.1).map(\.0).min() ?? 0
            let maxFaux = paires.filter { !$0.1 }.map(\.0).max() ?? 0
            var bloc: [String: JSONValue] = [
                "seuil": .number((choisi.seuil * 1000).rounded() / 1000), "justes_gardes": .number(Double(choisi.j)), "justes": .number(Double(j)),
                "faux_ecartes": .number(Double(choisi.f)), "faux": .number(Double(f)), "exactitude": .number((exactitude * 1000).rounded() / 1000),
                "separation_nette": .bool(maxFaux < minJuste),
            ]
            var phrase = "\(noms[cle] ?? cle) : seuil \(Bilan.nombre(choisi.seuil, decimales: 2)), garde \(choisi.j) justes sur \(j) et écarte \(choisi.f) faux sur \(f)"
            if let provisoire = provisoires[cle] {
                let r = juger(provisoire)
                bloc["provisoire"] = ["seuil": .number(provisoire), "justes_gardes": .number(Double(r.justesGardes)), "faux_ecartes": .number(Double(r.fauxEcartes))]
                phrase += " (le seuil provisoire \(Bilan.nombre(provisoire, decimales: 2)) : \(r.justesGardes) et \(r.fauxEcartes))"
            }
            mesures[cle] = .object(bloc)
            phrases.append(phrase + ".")
            if meilleure == nil || exactitude > meilleure!.exactitude { meilleure = (cle, exactitude) }
        }
        resultat["mesures"] = .object(mesures)
        if let meilleure {
            resultat["la_plus_separatrice"] = .string(meilleure.cle)
            phrases.append("La mesure qui sépare le mieux : \(noms[meilleure.cle] ?? meilleure.cle).")
        }
        resultat["resume"] = .string(phrases.joined(separator: " "))
        return .object(resultat)
    }
}
