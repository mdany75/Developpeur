import CoreGraphics
import Foundation
import ImageIO

/// La retouche générative par Fibo 2 (`generative_edit`, demandée par Dany le 29 octobre 2026) :
/// ce que Lightroom ne sait pas faire (changer un vêtement, ajouter ou retirer un objet) se fait
/// sur ce Mac par mflux (`mflux-generate-fibo2-edit`), seulement sur demande de l'utilisateur.
/// Ici, les calculs purs : taille de l'entrée de Fibo, arguments de mflux, lecture de sa
/// progression, explication de ses erreurs, masque de la zone, zone changée et recomposition en
/// pleine résolution (hors de la zone changée, les pixels de la photo restent ceux du TIFF
/// exporté). Le déroulé (exportation, mflux, importation) est dans Tools+Generatif.swift.
public enum Generatif {
    /// L'exécutable de mflux pour Fibo 2 en édition (référence : Fibo2Studio, Generator.swift).
    static let nomExecutable = "mflux-generate-fibo2-edit"
    static let depotNormal = "briaai/Fibo-2.0-dev"
    static let depotRapide = "briaai/Fibo-2.0-edit-turbo"
    /// Étapes du modèle : 50 en qualité normale, 30 en qualité équilibrée, 4 pour Turbo (qui n'en
    /// prend pas d'autre).
    static let etapesNormal = 50
    static let etapesEquilibre = 30
    static let etapesRapide = 4
    /// Qualité équilibrée : le guidage (CFG) ne tourne que sur les premiers 60 % des étapes
    /// (--cfg-end 0.6), les autres sans sa seconde passe. Mesures de mflux reprises par Fibo 2 Studio
    /// (30 étapes à 60 % : environ le rendu de 50 étapes, en deux fois moins de temps) ; le rendu reste
    /// à constater sur de vraies photos de Dany : provisoire.
    static let finGuidageEquilibre = 0.6
    /// Le guidage (--guidance) que l'appel peut donner : de 1 (sans guidage) à 10 ; absent, celui de
    /// mflux (5 pour Fibo 2 Dev). Turbo, distillé, n'en a pas.
    static let guidageMin = 1.0
    static let guidageMax = 10.0
    static let guidageParDefaut = 5.0
    /// Délai maximal d'une génération (un premier téléchargement du modèle compris).
    public static let delaiMax: TimeInterval = 900
    /// Au-delà de cette part de l'image changée, toute la sortie de Fibo est prise.
    static let partSortieEntiere = 0.6
    /// En deçà, Fibo n'a rien changé de visible : rien n'est importé.
    static let partMinimale = 0.0005
    /// Écart (sur 1, le plus grand des trois canaux, après un léger flou de 3 × 3 pixels) au-delà
    /// duquel un pixel a changé : le décodage du modèle déplace un peu tous les pixels, sans dépasser
    /// ce seuil sur une image lisse ; provisoire, à relever sur de vraies sorties de Fibo 2. Le flou
    /// reste de 3 × 3 à toute taille : plus large (5 × 5 à 1 Mpx, d'abord), il effaçait un trait d'un
    /// pixel (un fil électrique retiré, d'écart 0,5) avant le seuil.
    static let seuilEcart: Float = 0.10
    /// Marge autour de la zone donnée (part du petit côté) : le masque de Fibo déborde un peu, pour
    /// que l'objet changé ne soit pas coupé net au bord de la zone.
    static let margeRegion = 0.03
    /// Élargissement de la zone changée (part du petit côté), puis fondu (deux flous de ce rayon).
    static let elargissement = 0.02
    static let fondu = 0.005

    /// La qualité d'un appel : équilibrée par défaut (30 étapes, guidage sur 60 % d'entre elles),
    /// normale (50 étapes, guidage sur toutes), rapide (Turbo, 4 étapes, sans guidage).
    public enum Qualite: String {
        case balanced, normal, fast
        var etapes: Int {
            switch self {
            case .balanced: return Generatif.etapesEquilibre
            case .normal: return Generatif.etapesNormal
            case .fast: return Generatif.etapesRapide
            }
        }
        var texte: String {
            switch self {
            case .balanced: return "équilibrée (\(etapes) étapes, guidage sur 60 % d'entre elles)"
            case .normal: return "normale (\(etapes) étapes)"
            case .fast: return "rapide (Turbo, \(etapes) étapes)"
            }
        }
        /// Turbo est distillé pour tourner sans guidage : ni phrase d'exclusion, ni guidance, ni --cfg-end.
        var avecGuidage: Bool { self != .fast }
        /// La part des étapes avec guidage (nil : toutes).
        var finGuidage: Double? { self == .balanced ? Generatif.finGuidageEquilibre : nil }
    }

    /// La qualité par défaut d'un appel.
    static let qualiteParDefaut = Qualite.balanced

    // MARK: Arguments

    /// La zone (`region`) : x, y, width, height de 0 à 1 dans l'image que montre view_photo.
    static func region(_ objet: [String: JSONValue]?) throws -> CGRect? {
        guard let objet else { return nil }
        let cles = ["x", "y", "width", "height"]
        let valeurs = cles.map { objet[$0]?.double }
        let inconnues = objet.keys.filter { !cles.contains($0) }.sorted()
        guard inconnues.isEmpty else { throw LightroomError.invalid("« region » : x, y, width, height seulement (pas \(inconnues.joined(separator: ", "))).") }
        guard let x = valeurs[0], let y = valeurs[1], let l = valeurs[2], let h = valeurs[3] else {
            throw LightroomError.invalid("« region » : x, y, width et height, de 0 à 1 dans l'image que montre view_photo.")
        }
        guard x >= 0, y >= 0, l > 0, h > 0, x + l <= 1.0001, y + h <= 1.0001 else {
            throw LightroomError.invalid("« region » : une zone dans l'image (x, y ≥ 0 ; width, height > 0 ; x + width et y + height ≤ 1).")
        }
        return CGRect(x: x, y: y, width: min(l, 1 - x), height: min(h, 1 - y))
    }

    /// Environ un mégapixel, mêmes proportions, côtés multiples de 16 (exigés par le modèle).
    static func tailleCible(largeur: Int, hauteur: Int) -> (largeur: Int, hauteur: Int) {
        // Borne large : au-delà, mflux recadrerait la photo au centre.
        let rapport = max(0.125, min(8, Double(largeur) / Double(max(hauteur, 1))))
        let aire = 1024.0 * 1024.0
        let l = (aire * rapport).squareRoot()
        let h = l / rapport
        func multiple16(_ v: Double) -> Int { max(256, Int((v / 16).rounded()) * 16) }
        return (multiple16(l), multiple16(h))
    }

    /// Les arguments de mflux, en tableau (aucun shell) : la demande (la fiche JSON de FIBO-vlm par
    /// --prompt-file, sinon la phrase anglaise par --prompt), l'entrée (le recadrage autour de la zone,
    /// ou la photo entière sans zone) et, avec une zone, son masque (`--mask-path`, PNG RVB, accepté par
    /// mflux 0.24, constaté le 29 octobre 2026). Toujours --low-ram (constaté le 29 octobre 2026 : sans lui, mflux prenait 39 Go
    /// sur les 48 du Mac Studio et Lightroom ne répondait plus ; avec lui, 20,6 Go et la même image
    /// au pixel près). Qualités normale et équilibrée : décodage en pleine précision
    /// (--vae-full-precision, sans coût de mémoire avec --low-ram), le guidage (--guidance, s'il est
    /// donné), la phrase d'exclusion (--negative-prompt) et, en équilibrée, --cfg-end ; ces trois-là
    /// seulement avec le guidage au-dessus de 1 (à 1, mflux ne fait pas la seconde passe qui les lit).
    /// Turbo, distillé sans guidage, n'en reçoit aucun (comme Fibo 2 Studio). Jamais --quantize (-q 8 :
    /// 38 Go, et moins fidèle) ni --step-cache-ratio, qui dégradent l'image.
    static func arguments(entree: URL, masque: URL?, instruction: String, taille: (largeur: Int, hauteur: Int),
                          qualite: Qualite, graine: Int, sortie: URL, modeleRapide: URL?,
                          fiche: URL? = nil, exclusion: String? = nil, guidage: Double? = nil) -> [String] {
        var args = fiche.map { ["--prompt-file", $0.path] } ?? ["--prompt", instruction]
        args += ["--image-paths", entree.path]
        if let masque { args += ["--mask-path", masque.path] }
        switch qualite {
        case .normal, .balanced:
            args += ["--steps", String(qualite.etapes), "--vae-full-precision"]
            if let guidage { args += ["--guidance", texteNombre(guidage)] }
            if (guidage ?? guidageParDefaut) > 1 {
                if let fin = qualite.finGuidage { args += ["--cfg-end", texteNombre(fin)] }
                if let exclusion, !exclusion.isEmpty { args += ["--negative-prompt", exclusion] }
            }
        case .fast:
            // mflux 0.24 réclame une version de Turbo que Bria a retirée : la copie locale du cache.
            if let modeleRapide {
                args += ["--model", modeleRapide.path, "--base-model", "fibo2-edit-turbo"]
            } else {
                args += ["--model", "fibo2-edit-turbo"]
            }
        }
        args += ["--low-ram", "--width", String(taille.largeur), "--height", String(taille.hauteur), "--seed", String(graine), "--output", sortie.path]
        return args
    }

    /// Un nombre pour la ligne de commande : point décimal, sans zéros inutiles (« 0.6 », « 7.5 », « 5 »).
    static func texteNombre(_ valeur: Double) -> String {
        let arrondi = (valeur * 100).rounded() / 100
        return arrondi == arrondi.rounded() ? String(Int(arrondi)) : String(arrondi)
    }

    // MARK: Phrase d'exclusion

    /// Ce que Fibo 2 doit éviter, par défaut (--negative-prompt, en anglais) : le texte, les logos et
    /// filigranes qu'un modèle génératif invente, une personne ou une tête en double, des membres en
    /// trop, un corps déformé. Seulement hors Turbo. Elle **remplace** le négatif de mflux pour une
    /// retouche, la légende nulle sur laquelle Fibo 2 a été entraîné (`Fibo2PromptEncoder.NULL_CAPTION`,
    /// `negative_prompt or default` dans fibo2_core.py) : elle part donc au format de cette légende
    /// (`legendeExclusion`), ses clés vides, la liste sous `aesthetics.artifacts`, comme le négatif de
    /// la génération de la fiche du modèle (`TEXT_TO_IMAGE_NEGATIVE`), jamais en mots libres. Provisoire :
    /// son effet sur le rendu reste à constater (même graine, avec et sans).
    static let exclusionTexte = ["text", "letters", "words", "caption", "logo", "watermark", "signature"]
    static let exclusionCorps = ["duplicate person", "extra head", "extra face", "extra arms", "extra legs", "extra hands",
                                 "extra fingers", "deformed", "disfigured", "distorted anatomy"]
    /// La longueur de « avoid » (ce que l'appel ajoute).
    static let longueurExclusion = 500

    /// Une instruction qui parle de texte (« change the sign to "Open" ») : la partie texte de la
    /// phrase d'exclusion est laissée de côté, sinon elle empêcherait la demande.
    static func parleDeTexte(_ instruction: String) -> Bool {
        instruction.contains("\"") || instruction.contains("«") || instruction.contains("“")
            || instruction.range(of: #"(?i)\b(text|texts|letter|letters|lettering|word|words|writ\w*|sign|signs|signage|label|labels|logo|logos|caption|inscription|title|font)\b"#,
                                 options: .regularExpression) != nil
    }

    /// Une instruction qui ajoute une personne (« add a man walking in the background », « a second
    /// person ») : « duplicate person » est laissé de côté, sinon la passe négative pousserait contre
    /// la demande. Une instruction qui parle seulement d'une personne déjà là (« the woman's trousers »)
    /// le garde : c'est là qu'une tête en double s'est vue (essai du 29 octobre 2026).
    static func ajouteUnePersonne(_ instruction: String) -> Bool {
        let personne = #"(person|persons|people|man|men|woman|women|boy|boys|girl|girls|child|children|kid|kids|baby|babies|someone|somebody|crowd|pedestrian|pedestrians|passerby|passersby|couple|family|friend|friends|figure|figures)"#
        // Le verbe, puis la personne à deux mots au plus (« add a young woman », « add two people ») :
        // jamais « put a hat on the woman », qui ne fait que l'habiller.
        let motifs = [#"(?i)\b(add|adds|adding|insert|inserting|put|place|include|including)\s+((a|an|one|some)\s+)?(\w+\s+){0,2}"# + personne + #"\b"#,
                      #"(?i)\b(another|second|third|more|two|three|four|several|extra)\s+(\w+\s+)?"# + personne + #"\b"#]
        return motifs.contains { instruction.range(of: $0, options: .regularExpression) != nil }
    }

    /// Les termes de la phrase d'exclusion d'une modification : la liste par défaut (sans sa partie
    /// texte si l'instruction parle de texte, sans « duplicate person » si elle ajoute une personne),
    /// puis « avoid » de l'appel.
    static func termesExclusion(instruction: String, avoid: String?) -> [String] {
        var termes = (parleDeTexte(instruction) ? [] : exclusionTexte) + exclusionCorps
        if ajouteUnePersonne(instruction) { termes.removeAll { $0 == "duplicate person" } }
        if let avoid = avoid?.trimmingCharacters(in: .whitespacesAndNewlines), !avoid.isEmpty { termes.append(avoid) }
        return termes
    }

    /// La légende négative passée à --negative-prompt : la légende nulle de mflux (mêmes clés, même
    /// ordre, toutes vides), les termes sous `aesthetics.artifacts`, en JSON compact comme mflux
    /// l'écrit (l'ordre des clés est celui de l'entraînement : écrite à la main, jamais par
    /// JSONCoding, qui trie les clés).
    static func legendeExclusion(_ termes: [String]) -> String {
        let liste = termes.map { JSONCoding.line(.string($0)) }.joined(separator: ",")
        return #"{"short_description":"","objects":[],"background_setting":"","lighting":{},"#
            + #""aesthetics":{"artifacts":["# + liste + #"]},"photographic_characteristics":{},"style_medium":"","#
            + #""context":"","artistic_style":""}"#
    }

    /// La phrase d'exclusion d'une modification, telle que mflux la reçoit (`legendeExclusion`).
    static func exclusion(instruction: String, avoid: String?) -> String {
        legendeExclusion(termesExclusion(instruction: instruction, avoid: avoid))
    }

    // MARK: Fiche JSON (FIBO-vlm)

    /// FIBO-vlm (briaai/FIBO-vlm, environ 8 Go) rédige sur ce Mac, avant chaque passage de Fibo, une
    /// fiche structurée (VGL) de la modification : la légende du résultat et l'instruction
    /// (edit_instruction), que mflux lit par --prompt-file (fibo2 edit accepte un objet JSON avec
    /// « edit_instruction » et la légende, mflux/models/fibo2/README.md). Lancé par le Python de mflux
    /// (`-I`, sans shell) sur un script du connecteur écrit dans le dossier de l'appel (`scriptFiche`).
    /// Son processus est fini avant le lancement de mflux : jamais les deux en mémoire ensemble.
    static let depotVLM = "briaai/FIBO-vlm"
    /// La révision de FIBO-vlm que mflux 0.24 charge, épinglée (`ModelRevisions.PINNED` de
    /// mflux/models/common/resolution/model_revisions.py) : hors ligne, il ne lit que cet instantané du
    /// cache (`path_resolution`, `revision`, `local_files_only`), jamais celui de `refs/main`. À relire
    /// à chaque mise à jour de mflux.
    static let revisionVLM = "bd13da5e0b73c808014d6260963e311c8cdf0d8b"
    /// La version de mflux sur laquelle le script de la fiche a été réglé et mesuré : il se sert de
    /// détails internes de mflux (`FiboVLM._generate_internal`, `FiboVLM._normalize_edit_output`,
    /// `Qwen3VLUtil.sample_top_p`), à revérifier à chaque mise à jour.
    static let versionMfluxFiche = "0.24.0"
    /// Ce que le script écrit sur sa sortie quand la version de mflux installée n'est pas
    /// `versionMfluxFiche` (suivi de la version lue) : le connecteur la reprend en remarque.
    static let marqueVersionFiche = "version de mflux :"
    /// La version de mflux qu'une ligne du script dit après `marqueVersionFiche` (jusqu'à la
    /// parenthèse : « 0.25.0 », ou « inconnue ») ; nil sans la marque.
    static func versionDite(_ ligne: String) -> String? {
        guard let marque = ligne.range(of: marqueVersionFiche) else { return nil }
        let suite = ligne[marque.upperBound...].prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
        return suite.isEmpty ? nil : String(suite.prefix(40))
    }
    /// La remarque d'une autre version de mflux que celle du réglage du script.
    static func remarqueVersion(_ lue: String) -> String {
        "mflux installé : \(lue) ; le script de la fiche est réglé sur \(versionMfluxFiche) : à revérifier."
    }
    /// Le téléchargement du modèle à conseiller : la révision que mflux charge.
    static var conseilVLM: String { "hf download \(depotVLM) --revision \(revisionVLM)" }
    /// Le nom du script (que Fibo.motifAutreCalcul reconnaît aussi).
    static let nomScriptFiche = "fiche-fibo-vlm.py"
    /// Délai de la rédaction d'une fiche (chargement du modèle compris) ; au-delà, arrêtée, et Fibo 2
    /// reçoit la phrase seule. Mesuré le 29 octobre 2026 avec le réglage léger : 33 à 45 s avec une
    /// zone, 58 s sans zone.
    public static let delaiFiche: TimeInterval = 180
    /// Durée attendue d'une fiche, pour la barre seulement (mesurée : 33 à 45 s avec une zone ; 58 s
    /// sans zone, où la barre attend une dizaine de secondes à 95 %).
    static let dureeFicheEstimee: TimeInterval = 45
    /// Le gris de mflux (Fibo2EditImages.grey_out) dans la zone à régénérer.
    static let grisMasque: UInt8 = 128

    /// Le script Python que le connecteur écrit dans le dossier de l'appel, en réglage léger (mesuré le
    /// 29 octobre 2026 sur le Mac de 48 Go, Lightroom ouvert, un calcul à la fois : 33 à 45 s et 15,6 à
    /// 16,0 Go en pointe en mode masqué, deux graines, et 58 s et 16,7 Go sans zone, au lieu de 402 s et
    /// 39,7 Go par `FiboVLM.edit`) :
    /// le cache de tampons de MLX borné à 4 Go avant le chargement (sans borne, il gardait 32,7 Go de
    /// tampons libérés : `lm_head` recopié en float32 à chaque jeton) ; le modèle quantifié en 8 bits
    /// (5,5 Go actifs au lieu de 8,9, fiche aussi fidèle ; 4 et 6 bouclent) ; 1 536 jetons au plus (une
    /// fiche en fait de 568 à 1 012 ; une boucle était coupée vers 115 s) ; une seule génération
    /// (`_generate_internal`), sans les replis de `FiboVLM.edit`. En mode masqué, FIBO-vlm n'écrit jamais
    /// edit_instruction : après text_render, il recommence des clés jusqu'à la borne ou ferme l'objet au
    /// hasard (la cause de « Masked edit prompt generation failed ») ; le script s'arrête dès que
    /// `"text_render":[…]` est fermé (cherché hors des chaînes JSON, `fin_text_render` : un crochet dans
    /// un texte à rendre ne compte pas ; relu tous les 4 jetons, puis sur le texte final), ferme l'objet
    /// et pose lui-même edit_instruction (« Fill the masked area: » et l'instruction). Sans zone, la
    /// génération va à son terme (edit_instruction vient après text_render). Une accolade fermée trop
    /// tôt se répare (`reparer` : seulement si la suite reprend par une clé, et gardée seulement si le
    /// texte se lit alors en entier ; sinon le texte d'origine, que la normalisation de mflux lit). La fiche s'écrit dans l'ordre des clés de
    /// FIBO-vlm (celui des légendes de l'entraînement de Fibo 2 : le connecteur ne la réécrit pas). Code
    /// 0 et la fiche dans --output ; toute exception, code 1 et le message sur la sortie (le connecteur
    /// passe alors à la phrase seule). Une autre version de mflux que `versionMfluxFiche` est dite
    /// (`marqueVersionFiche`).
    static let scriptFiche = #"""
    """fiche-fibo-vlm.py — fiche JSON (VGL) d'une modification pour Fibo 2, rédigée sur ce Mac par
    FIBO-vlm (via mflux), pour generative_edit du Développeur. Écrit par le connecteur dans le dossier
    de l'appel, lancé par le Python de mflux en -I, effacé avec ce dossier.
      --image entree.png --instruction "texte anglais" --output fiche.json [--seed N] [--use-mask]

    Réglage léger, mesuré le 29 octobre 2026 (Mac de 48 Go, Lightroom ouvert) : 33 à 45 s et environ
    16 Go en pointe en mode masqué, 58 s et 16,7 Go sans zone, au lieu de 402 s et 39,7 Go par
    FiboVLM.edit.
    Réglé sur mflux \#(versionMfluxFiche) : il se sert de ses détails internes (FiboVLM._generate_internal,
    FiboVLM._normalize_edit_output, Qwen3VLUtil.sample_top_p) ; une autre version est dite sur la sortie.
    """

    import argparse
    import json
    import sys
    from pathlib import Path

    VERSION_RELEVEE = "\#(versionMfluxFiche)"
    MARQUE_VERSION = "\#(marqueVersionFiche)"
    # Sans borne, le cache de MLX gardait 32,7 Go de tampons libérés (lm_head recopié en float32 à
    # chaque jeton) : borné avant le chargement du modèle.
    CACHE_MLX = 4 * 1024 ** 3
    # 8 bits : 5,5 Go actifs au lieu de 8,9, fiche aussi fidèle ; 4 et 6 bouclent.
    QUANTIZE = 8
    # Une fiche fait de 568 à 1 012 jetons ; une génération qui boucle s'arrête là.
    MAX_JETONS = 1536
    # Tous les combien de jetons le texte partiel est relu (en mode masqué).
    PAS_RELECTURE = 4


    class FicheFermee(Exception):
        """Levée pendant la génération, en mode masqué, dès que text_render est fermé : porte la fiche."""


    def verifier_version() -> None:
        """Dit sur la sortie une version de mflux autre que celle du réglage (le connecteur la reprend)."""
        try:
            from importlib.metadata import version
            lue = version("mflux")
        except Exception:
            lue = "inconnue"
        if lue != VERSION_RELEVEE:
            print(f"{MARQUE_VERSION} {lue} (script réglé sur {VERSION_RELEVEE})", flush=True)


    def fin_text_render(texte: str):
        """La position juste après le « ] » qui ferme la liste "text_render" (la dernière clé que
        FIBO-vlm écrit en mode masqué), ou None tant qu'elle n'est pas fermée. Le texte se parcourt
        en JSON : chaînes et échappements sautés (un crochet dans un texte à rendre, « OPEN [24h] »,
        ne compte pas), la clé cherchée au premier niveau de l'objet seulement."""
        if '"text_render"' not in texte:
            return None
        profondeur = 0
        attendre = False  # la clé text_render et ses deux-points lus : sa valeur vient
        cible = None      # la profondeur de la liste text_render, une fois ouverte
        i, n = 0, len(texte)
        while i < n:
            c = texte[i]
            if c == '"':
                j, echappe = i + 1, False
                while j < n:
                    if echappe:
                        echappe = False
                    elif texte[j] == "\\":
                        echappe = True
                    elif texte[j] == '"':
                        break
                    j += 1
                if j >= n:
                    return None  # chaîne pas encore fermée
                if cible is None and profondeur <= 1 and texte[i + 1:j] == "text_render":
                    k = j + 1
                    while k < n and texte[k].isspace():
                        k += 1
                    attendre = texte[k:k + 1] == ":"
                i = j + 1
                continue
            if attendre and not c.isspace() and c != ":":
                attendre = False
                if c == "[":
                    cible = profondeur + 1
            if c in "[{":
                profondeur += 1
            elif c in "]}":
                profondeur -= 1
                if c == "]" and cible is not None and profondeur == cible - 1:
                    return i + 1
            i += 1
        return None


    def reparer(texte: str) -> str:
        """FIBO-vlm ferme parfois l'objet trop tôt (« …"artistic_style":"x"} ,"context":… ») : retire
        l'accolade de trop quand la suite reprend par une clé (une virgule puis un guillemet, blancs
        permis ; cinq fois au plus). La réparation n'est gardée que si le texte se lit alors en entier ;
        sinon le texte d'origine, dont la normalisation de mflux choisit le meilleur objet (une fiche
        complète suivie d'un second objet commencé reste ainsi lisible)."""
        origine = texte = texte.strip()
        for _ in range(6):
            try:
                json.loads(texte)
                return texte
            except json.JSONDecodeError as e:
                avant = texte[:e.pos].rstrip()
                apres = texte[e.pos + 1:].lstrip()
                if (e.msg != "Extra data" or texte[e.pos:e.pos + 1] != "," or not avant.endswith("}")
                        or not apres.startswith('"')):
                    return origine
                texte = avant[:-1] + texte[e.pos:]
        return origine


    def rediger(args) -> tuple:
        """Une seule génération de FIBO-vlm (tâche edit) ; rend son texte brut (None s'il n'y en a pas),
        le nombre de jetons tirés, la normalisation de mflux et l'erreur levée, s'il y en a une."""
        import mlx.core as mx
        mx.set_cache_limit(CACHE_MLX)

        from mflux.models.common_models.qwen3_vl.qwen3_vl_util import Qwen3VLUtil
        from mflux.models.fibo_vlm.model.fibo_vlm import FiboVLM
        from mflux.models.fibo_vlm.model.util import FiboVLMUtil

        vlm = FiboVLM(quantize=QUANTIZE)
        jetons = []
        tirer = Qwen3VLUtil.sample_top_p

        # Chaque jeton tiré est gardé ; en mode masqué, le texte partiel est relu, et la génération
        # s'arrête dès que text_render est fermé (FIBO-vlm n'écrirait plus rien d'utile).
        def tirer_et_surveiller(logits, top_p, temperature=1.0):
            jeton = tirer(logits, top_p, temperature)
            jetons.append(int(jeton.item()))
            if args.use_mask and len(jetons) % PAS_RELECTURE == 0:
                partiel = vlm.processor.tokenizer.decode(jetons, skip_special_tokens=True)
                fin = fin_text_render(partiel)
                if fin is not None:
                    raise FicheFermee(partiel[:fin] + "}")
            return jeton

        # _generate_internal normalise sa sortie et lève si edit_instruction manque : le texte brut
        # est gardé au passage, pour être réparé et complété ici.
        normaliser = FiboVLM._normalize_edit_output
        brut = None
        erreur = None
        fermee_par_le_script = False

        def garder_brut(texte, fallback_edit_instruction=None):
            nonlocal brut
            brut = texte
            return normaliser(texte, fallback_edit_instruction)

        Qwen3VLUtil.sample_top_p = staticmethod(tirer_et_surveiller)
        FiboVLM._normalize_edit_output = staticmethod(garder_brut)
        try:
            vlm._generate_internal(task="edit", image=FiboVLMUtil.load_image(args.image),
                                   editing_instructions=args.instruction, top_p=0.9, temperature=0.2,
                                   max_tokens=MAX_JETONS, stop=["<|im_end|>", "<|end_of_text|>"],
                                   seed=args.seed, use_mask=args.use_mask)
        except FicheFermee as fermee:
            brut = str(fermee)
            fermee_par_le_script = True
        except ValueError as exc:
            # Sortie sans edit_instruction, ou mal fermée : le texte brut est gardé. Levée avant la
            # normalisation (MLX, image), brut reste None et l'erreur est dite telle quelle.
            erreur = exc
        finally:
            Qwen3VLUtil.sample_top_p = staticmethod(tirer)
            FiboVLM._normalize_edit_output = staticmethod(normaliser)
        # En mode masqué, la génération a pu finir juste après text_render, entre deux relectures,
        # sans fermer l'objet (ou couper une boucle à la borne) : coupé et fermé de même.
        if args.use_mask and brut is not None and not fermee_par_le_script:
            try:
                json.loads(brut.strip())
            except ValueError:
                fin = fin_text_render(brut)
                if fin is not None:
                    brut = brut[:fin] + "}"
        return brut, len(jetons), normaliser, erreur


    def main() -> int:
        parser = argparse.ArgumentParser(description="Fiche JSON Fibo 2 par FIBO-vlm (tâche edit, réglage léger)")
        parser.add_argument("--image", type=Path, required=True)
        parser.add_argument("--instruction", required=True)
        parser.add_argument("--output", type=Path, required=True)
        parser.add_argument("--seed", type=int, default=42)
        parser.add_argument("--use-mask", action="store_true", help="l'image a une zone grisée à régénérer")
        args = parser.parse_args()

        verifier_version()
        brut, jetons, normaliser, erreur = rediger(args)
        if brut is None:
            print(f"erreur FIBO-vlm : {erreur}" if erreur else "erreur FIBO-vlm : aucune réponse", flush=True)
            return 1
        # edit_instruction : celle de FIBO-vlm s'il en a écrit une, sinon posée ici (en mode masqué,
        # il n'en écrit jamais).
        consigne = ("Fill the masked area: " if args.use_mask else "") + args.instruction.strip()
        try:
            fiche = json.loads(normaliser(reparer(brut), consigne))
        except ValueError as exc:
            print(f"erreur FIBO-vlm : fiche illisible ({exc})", flush=True)
            return 1
        if not isinstance(fiche, dict):
            print("erreur FIBO-vlm : la fiche n'est pas un objet JSON", flush=True)
            return 1
        args.output.write_text(json.dumps(fiche, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"fiche écrite : {args.output} ({jetons} jetons)", flush=True)
        return 0


    if __name__ == "__main__":
        try:
            sys.exit(main())
        except Exception as exc:  # un message lisible pour le connecteur, pas une trace Python
            print(f"erreur FIBO-vlm : {exc}", flush=True)
            sys.exit(1)
    """#

    /// Les arguments du Python de mflux pour une fiche : -I (isolé : ni variables PYTHON*, ni dossier
    /// du script dans le chemin des modules), le script, l'image, l'instruction, la sortie, la graine
    /// de l'appel et, avec une zone (`masque`), --use-mask (le prompt système EDIT_WITH_MASK de
    /// FiboVLM attend une image à zones grises).
    static func argumentsFiche(script: URL, image: URL, instruction: String, sortie: URL, graine: Int, masque: Bool) -> [String] {
        var args = ["-I", script.path, "--image", image.path, "--instruction", instruction, "--output", sortie.path, "--seed", String(graine)]
        if masque { args.append("--use-mask") }
        return args
    }

    /// L'image que FIBO-vlm reçoit avec une zone : l'entrée de Fibo grisée dans le masque exactement
    /// comme mflux le fait avant de l'encoder (Fibo2EditImages.grey_out : le masque rendu binaire à 128,
    /// un gris plat de 128) ; pixels RGBA 8 bits, masque d'un octet par pixel, même taille.
    static func griser(_ pixels: [UInt8], masque: [UInt8]) -> [UInt8] {
        guard masque.count * 4 <= pixels.count else { return pixels }
        var sortie = pixels
        for i in masque.indices where masque[i] >= 128 {
            sortie[i * 4] = grisMasque; sortie[i * 4 + 1] = grisMasque; sortie[i * 4 + 2] = grisMasque
        }
        return sortie
    }

    /// Le modèle FIBO-vlm complet dans le cache Hugging Face : l'instantané de la révision que mflux
    /// charge (`revisionVLM`, jamais celui de `refs/main`, qu'un téléchargement plus récent déplace), sa
    /// configuration, son index de poids et chaque fichier de poids qu'il nomme ; nil s'il manque quoi
    /// que ce soit.
    static func vlmLocal(cache: URL, revision: String = revisionVLM) -> URL? {
        let dossier = cache.appendingPathComponent("models--" + depotVLM.replacingOccurrences(of: "/", with: "--"))
        let instantane = dossier.appendingPathComponent("snapshots/" + revision)
        guard FileManager.default.fileExists(atPath: instantane.appendingPathComponent("config.json").path),
              let donnees = try? Data(contentsOf: instantane.appendingPathComponent("model.safetensors.index.json")),
              let index = try? JSONCoding.parse(donnees), let poids = index["weight_map"]?.object else { return nil }
        let fichiers = Set(poids.values.compactMap(\.string))
        guard !fichiers.isEmpty, fichiers.allSatisfy({ FileManager.default.fileExists(atPath: instantane.appendingPathComponent($0).path) }) else { return nil }
        return instantane
    }

    /// La fiche écrite par FIBO-vlm, lue : un objet JSON, son edit_instruction non vide (l'instruction
    /// donnée sinon, comme le script) ; nil si elle est illisible.
    static func lireFiche(_ donnees: Data, instruction: String) -> [String: JSONValue]? {
        guard let valeur = try? JSONCoding.parse(donnees), var fiche = valeur.object, !fiche.isEmpty else { return nil }
        if (fiche["edit_instruction"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty {
            fiche["edit_instruction"] = .string(instruction)
        }
        return fiche
    }

    /// Un court résumé de la fiche pour la réponse (quelques champs, jamais tout le JSON) : l'instruction
    /// réécrite, la description, l'arrière-plan, la lumière, le nombre d'objets décrits.
    static func resumeFiche(_ fiche: [String: JSONValue]) -> JSONValue {
        func court(_ texte: String?, _ n: Int) -> JSONValue? {
            guard let texte = texte?.trimmingCharacters(in: .whitespacesAndNewlines), !texte.isEmpty else { return nil }
            return .string(texte.count > n ? String(texte.prefix(n - 1)) + "…" : texte)
        }
        var resume: [String: JSONValue] = ["redigee_par": "FIBO-vlm"]
        resume["edit_instruction"] = court(fiche["edit_instruction"]?.string, 400)
        resume["description"] = court(fiche["short_description"]?.string, 300)
        resume["arriere_plan"] = court(fiche["background_setting"]?.string, 200)
        resume["lumiere"] = court(fiche["lighting"]?["conditions"]?.string, 120)
        if let objets = fiche["objects"]?.array { resume["objets_decrits"] = .number(Double(objets.count)) }
        return .object(resume)
    }

    /// mflux a refusé la fiche : seulement les messages de refus de `Fibo2CaptionCheck` et de
    /// `Fibo2PromptEncoder.check_edit_prompt` (le format de légende que Fibo 2 lit, un JSON mal formé,
    /// une edit_instruction absente ou qui n'est pas un texte), que mflux vérifie avant de charger le
    /// modèle ; l'appel la remplace alors par la phrase seule, une fois. Jamais un simple mot
    /// (« edit_instruction ») : la trace Python d'une autre erreur (mémoire pendant l'encodage de la
    /// légende) montre les lignes de source qui le contiennent.
    static let refusDeFiche = ["The JSON caption does not have the format FIBO 2 reads",
                               "The prompt starts like a JSON caption but is not valid JSON",
                               "\"edit_instruction\" has to be a string",
                               "A JSON edit prompt needs an \"edit_instruction\" key",
                               "A \"structured_caption\" must hold the whole caption"]
    static func ficheRefusee(_ journal: String) -> Bool {
        refusDeFiche.contains(where: journal.contains)
    }

    /// La fiche telle que FIBO-vlm l'a écrite, à passer à mflux sans la réécrire (l'ordre des clés est
    /// celui des légendes de l'entraînement ; JSONCoding les trierait) ; sans edit_instruction non vide
    /// (le script en garantit une), l'instruction donnée est jointe à la fin du texte, l'ordre gardé
    /// (Python garde la dernière valeur d'une clé en double). Nil si ce n'est pas un objet JSON.
    static func ficheAvecInstruction(_ texte: String, instruction: String) -> String? {
        guard let valeur = try? JSONCoding.parse(Data(texte.utf8)), let fiche = valeur.object, !fiche.isEmpty else { return nil }
        if !(fiche["edit_instruction"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty { return texte }
        let net = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard net.hasSuffix("}") else { return nil }
        let corps = net.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        return corps + ",\n  \"edit_instruction\": " + JSONCoding.line(.string(instruction)) + "\n}\n"
    }

    /// La dernière ligne non vide d'un journal, bornée (pour une remarque).
    static func derniereLigne(_ journal: String) -> String {
        let ligne = journal.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return ligne.map { String($0.prefix(300)) } ?? "sans message"
    }

    /// Pourquoi la fiche n'a pas été rédigée (FIBO-vlm en échec), en mots simples, d'après son journal.
    static func expliquerFiche(journal: String, code: Int32) -> String {
        if ["requires approval", "GatedRepo", "Unauthorized", "Forbidden"].contains(where: journal.contains) {
            return "accès au modèle \(depotVLM) refusé (le demander sur huggingface.co/\(depotVLM))"
        }
        let erreur = journal.split(separator: "\n").last { $0.contains("erreur FIBO-vlm") }
            ?? journal.split(separator: "\n").last
        return erreur.map { String($0.prefix(300)) } ?? "code \(code)"
    }

    /// Le dossier du modèle dans le cache Hugging Face (version « main » téléchargée), s'il est complet.
    static func modeleLocal(depot: String, cache: URL) -> URL? {
        let dossier = cache.appendingPathComponent("models--" + depot.replacingOccurrences(of: "/", with: "--"))
        guard let ref = try? String(contentsOf: dossier.appendingPathComponent("refs/main"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty else { return nil }
        let instantane = dossier.appendingPathComponent("snapshots/" + ref)
        return FileManager.default.fileExists(atPath: instantane.appendingPathComponent("model_index.json").path) ? instantane : nil
    }

    // MARK: Modifications

    /// Une modification demandée : son nom court en français (« jupe »), l'instruction donnée à Fibo 2
    /// (en anglais), sa traduction pour l'utilisateur, et la zone à changer.
    struct Modification {
        var label: String
        var instruction: String
        var instructionFr: String
        var region: CGRect?
    }

    static let maxModifications = 4
    static let longueurLabel = 40

    /// Les modifications d'un appel : `edits` (1 à 4), ou les arguments simples (instruction,
    /// instruction_fr, region, label) pour une seule ; jamais les deux. Avec plus d'une
    /// modification, chaque zone est exigée, et deux zones ne se chevauchent pas.
    static func modifications(_ raw: [String: JSONValue]) throws -> [Modification] {
        let simples = ["instruction", "instruction_fr", "region", "label"].filter { raw[$0].map { !$0.isNull } ?? false }
        // Un masque de Lightroom (mask) : une seule modification, sans region (l'un ou l'autre).
        if let masque = raw["mask"], !masque.isNull {
            if let edits = raw["edits"], !edits.isNull {
                throw LightroomError.invalid("« mask » et « edits » ensemble : un masque de Lightroom vaut pour une seule modification (instruction, instruction_fr, mask) ; les autres changements dans un second appel, sur la nouvelle photo. Rien n'a été fait.")
            }
            if let region = raw["region"], !region.isNull {
                throw LightroomError.invalid("« mask » et « region » ensemble : l'un ou l'autre (mask, un masque calculé par Lightroom : l'arrière-plan, le ciel, une personne ; region, un rectangle). Rien n'a été fait.")
            }
        }
        var liste: [Modification] = []
        if let edits = raw["edits"], !edits.isNull {
            guard simples.isEmpty else {
                throw LightroomError.invalid("« edits » et « \(simples.joined(separator: " », « ")) » ensemble : soit edits (une liste de modifications), soit instruction, instruction_fr et region pour une seule. Rien n'a été fait.")
            }
            guard let elements = edits.array, (1...maxModifications).contains(elements.count) else {
                throw LightroomError.invalid("« edits » : une liste de 1 à \(maxModifications) modifications { label, instruction, instruction_fr, region }. Rien n'a été fait.")
            }
            for (rang, element) in elements.enumerated() {
                guard let objet = element.object else {
                    throw LightroomError.invalid("« edits » : chaque modification est un objet { label, instruction, instruction_fr, region }. Rien n'a été fait.")
                }
                if objet["mask"] != nil {
                    throw LightroomError.invalid("« edits » : pas de mask dans une liste de modifications ; un masque de Lightroom vaut pour une seule modification par appel (instruction, instruction_fr, mask). Rien n'a été fait.")
                }
                let inconnues = objet.keys.filter { !["label", "instruction", "instruction_fr", "region"].contains($0) }.sorted()
                guard inconnues.isEmpty else {
                    throw LightroomError.invalid("« edits » : label, instruction, instruction_fr et region seulement (pas \(inconnues.joined(separator: ", "))). Rien n'a été fait.")
                }
                liste.append(try modification(objet, rang: rang + 1, nombre: elements.count))
            }
        } else {
            liste = [try modification(raw.filter { ["instruction", "instruction_fr", "region", "label"].contains($0.key) }, rang: 1, nombre: 1)]
        }
        if liste.count > 1 {
            for modif in liste where modif.region == nil {
                throw LightroomError.invalid("« \(modif.label) » : sans region. Avec plusieurs modifications, chacune a sa zone (region). Rien n'a été fait.")
            }
            if let (a, b) = chevauchement(liste.compactMap(\.region)) {
                throw LightroomError.invalid("Les zones de « \(liste[a].label) » et de « \(liste[b].label) » se chevauchent : les faire en deux appels successifs (le second sur la nouvelle photo, par son id). Rien n'a été fait.")
            }
        }
        return liste
    }

    private static func modification(_ objet: [String: JSONValue], rang: Int, nombre: Int) throws -> Modification {
        let nom = nombre > 1 ? "modification \(rang)" : "modification"
        guard let instruction = objet["instruction"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty else {
            throw LightroomError.invalid("« instruction »\(nombre > 1 ? " (\(nom))" : "") : la modification à faire, en anglais, précise (ce qui change et ce qui reste). Rien n'a été fait.")
        }
        guard instruction.count <= 2000 else { throw LightroomError.invalid("« instruction » : 2 000 caractères au plus. Rien n'a été fait.") }
        guard let francais = objet["instruction_fr"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !francais.isEmpty else {
            throw LightroomError.invalid("« instruction_fr »\(nombre > 1 ? " (\(nom))" : "") : la traduction française de l'instruction, montrée à l'utilisateur. Rien n'a été fait.")
        }
        guard francais.count <= 2000 else { throw LightroomError.invalid("« instruction_fr » : 2 000 caractères au plus. Rien n'a été fait.") }
        var label = objet["label"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if label.isEmpty { label = nom }
        if label.count > longueurLabel { label = String(label.prefix(longueurLabel)).trimmingCharacters(in: .whitespaces) }
        // Une zone mal formée (un texte JSON, un tableau [x, y, w, h]) n'est jamais prise pour une
        // absence de zone : Fibo travaillerait sur toute la photo.
        if let brute = objet["region"], !brute.isNull, brute.object == nil {
            throw LightroomError.invalid("« region »\(nombre > 1 ? " (\(nom))" : "") : un objet { x, y, width, height } de 0 à 1 dans l'image que montre view_photo (pas un texte ni une liste). Rien n'a été fait.")
        }
        return Modification(label: label, instruction: instruction, instructionFr: francais, region: try region(objet["region"]?.object))
    }

    /// Les deux premières zones qui se chevauchent (une aire commune), s'il y en a : vu avant tout
    /// envoi, sans la taille de la photo.
    static func chevauchement(_ regions: [CGRect]) -> (Int, Int)? {
        for i in regions.indices {
            for j in regions.indices where j > i {
                let commun = regions[i].intersection(regions[j])
                if !commun.isNull, commun.width > 1e-9, commun.height > 1e-9 { return (i, j) }
            }
        }
        return nil
    }

    /// Jusqu'où la zone de mélange d'une pièce déborde de sa zone donnée, en pixels de l'entrée de
    /// Fibo (de petit côté `petit`) : la marge du masque (`masqueRegion`, arrondie vers l'extérieur),
    /// les deux flous de son demi-rayon (`masqueRegionDoux`), et l'interpolation de la recomposition.
    static func etendueMelange(petit: Int) -> Double {
        let p = Double(petit)
        return (margeRegion * p).rounded(.up) + 2 * Double(max(1, Int(p * margeRegion / 2))) + 2
    }

    /// La zone de mélange d'une modification dans la photo (en pixels) : sa zone élargie de
    /// `etendueMelange`, dans son recadrage.
    static func zoneDeMelangeDansLaPhoto(_ region: CGRect, largeur: Int, hauteur: Int) -> CGRect {
        let (cadre, taille) = recadrage(region, largeur: largeur, hauteur: hauteur)
        let e = etendueMelange(petit: min(taille.largeur, taille.hauteur))
        let ex = e * Double(cadre.largeur) / Double(max(1, taille.largeur)), ey = e * Double(cadre.hauteur) / Double(max(1, taille.hauteur))
        let l = Double(largeur), h = Double(hauteur)
        return CGRect(x: region.minX * l - ex, y: region.minY * h - ey, width: region.width * l + 2 * ex, height: region.height * h + 2 * ey)
            .intersection(cadre.rect)
    }

    /// Les deux premières modifications dont les zones de mélange se recouvrent (zones qui se
    /// touchent ou presque) : la seconde pièce, recollée après la première, en effacerait le bord
    /// (sa sortie y montre l'ancien contenu). Vu après l'exportation, d'après la taille de la photo.
    static func zonesTropProches(_ regions: [CGRect], largeur: Int, hauteur: Int) -> (Int, Int)? {
        let zones = regions.map { zoneDeMelangeDansLaPhoto($0, largeur: largeur, hauteur: hauteur) }
        for i in zones.indices {
            for j in zones.indices where j > i {
                let commun = zones[i].intersection(zones[j])
                if !commun.isNull, commun.width > 0, commun.height > 0 { return (i, j) }
            }
        }
        return nil
    }

    /// La consigne que le module garde au journal de la nouvelle photo et montre avec une demande
    /// d'accord : le texte français de chaque modification (avec son nom s'il y en a plusieurs), et
    /// la raison donnée.
    static func consigneJournal(_ modifications: [Modification], raison: String?) -> String {
        var texte = modifications.count == 1
            ? modifications[0].instructionFr
            : modifications.map { "\($0.label) : \($0.instructionFr)" }.joined(separator: " ; ")
        if let raison { texte += " — " + raison }
        return texte
    }

    // MARK: Recadrage autour d'une zone

    /// Marge de contexte autour d'une zone, de chaque côté, en part de sa taille.
    static let margeContexte = 0.5
    /// Côté minimal du recadrage, en part du petit côté de la photo.
    static let contexteMin = 0.35
    static let aireCible = 1024.0 * 1024.0

    /// Un rectangle en pixels de la photo (origine en haut à gauche).
    struct Pixels: Equatable {
        var x: Int, y: Int, largeur: Int, hauteur: Int
        var rect: CGRect { CGRect(x: x, y: y, width: largeur, height: hauteur) }
    }

    /// Le recadrage autour d'une zone (de 0 à 1) d'une photo de `largeur` × `hauteur` : la zone
    /// agrandie de `margeContexte` de sa taille de chaque côté, et d'au moins `contexteMin` du petit
    /// côté de la photo, centrée sur elle, coupée aux bords (sans être déplacée : contre un bord, le
    /// recadrage reste petit et garde plus souvent sa taille native), jamais plus allongé que 8:1
    /// (son petit côté grandit alors dans la photo, plutôt que l'entrée de Fibo soit déformée) ; et
    /// la taille de l'entrée de Fibo (`taille`) : environ 1 Mpx (`tailleCible`, chaque côté borné à
    /// la taille native) pour un grand recadrage ; pour un petit, sa taille native, le recadrage
    /// ramené aux multiples de 16 (`ajuster16`) : jamais plus grand que la taille native.
    static func recadrage(_ region: CGRect, largeur: Int, hauteur: Int) -> (cadre: Pixels, taille: (largeur: Int, hauteur: Int)) {
        let l = Double(largeur), h = Double(hauteur)
        let rx0 = region.minX * l, rx1 = region.maxX * l, ry0 = region.minY * h, ry1 = region.maxY * h
        let minimum = contexteMin * Double(min(largeur, hauteur))
        let cl = max((rx1 - rx0) * (1 + 2 * margeContexte), minimum), ch = max((ry1 - ry0) * (1 + 2 * margeContexte), minimum)
        let cx = (rx0 + rx1) / 2, cy = (ry0 + ry1) / 2
        // Les arrondis vers l'extérieur, à un millionième de pixel près (0,4 × 6 000 = 2 400,000…05).
        func bas(_ v: Double) -> Int { Int((v + 1e-6).rounded(.down)) }
        func haut(_ v: Double) -> Int { Int((v - 1e-6).rounded(.up)) }
        var x0 = max(0, bas(cx - cl / 2)), x1 = min(largeur, haut(cx + cl / 2))
        var y0 = max(0, bas(cy - ch / 2)), y1 = min(hauteur, haut(cy + ch / 2))
        // Jamais plus allongé que 8:1 (la borne de tailleCible) : une zone fine coupée par un bord.
        if x1 - x0 > Int(rapportMax) * (y1 - y0) {
            (y0, y1) = elargir(y0, y1, jusqua: Int((Double(x1 - x0) / rapportMax).rounded(.up)), limite: hauteur)
        } else if y1 - y0 > Int(rapportMax) * (x1 - x0) {
            (x0, x1) = elargir(x0, x1, jusqua: Int((Double(y1 - y0) / rapportMax).rounded(.up)), limite: largeur)
        }
        let lc = x1 - x0, hc = y1 - y0
        if Double(lc * hc) > aireCible {
            let t = tailleCible(largeur: lc, hauteur: hc)
            return (Pixels(x: x0, y: y0, largeur: lc, hauteur: hc), (min(t.largeur, max(16, lc / 16 * 16)), min(t.hauteur, max(16, hc / 16 * 16))))
        }
        // Le resserrement ne mord ni dans la zone ni dans son fondu (`etendueMelange`).
        let e = etendueMelange(petit: min(lc, hc))
        let (ax0, ax1, tl) = ajuster16(x0, x1, zone: rx0 - e, rx1 + e, limite: largeur)
        let (ay0, ay1, th) = ajuster16(y0, y1, zone: ry0 - e, ry1 + e, limite: hauteur)
        return (Pixels(x: ax0, y: ay0, largeur: ax1 - ax0, hauteur: ay1 - ay0), (tl, th))
    }

    /// Le rapport des côtés le plus allongé d'une entrée de Fibo (au-delà, tailleCible déforme).
    static let rapportMax = 8.0

    /// Un intervalle [debut, fin) agrandi jusqu'à `cible` de part et d'autre, ramené dans [0, limite).
    private static func elargir(_ debut: Int, _ fin: Int, jusqua cible: Int, limite: Int) -> (Int, Int) {
        let manque = cible - (fin - debut)
        guard manque > 0 else { return (debut, fin) }
        var a = debut - manque / 2, b = fin + (manque - manque / 2)
        if a < 0 { b -= a; a = 0 }
        if b > limite { a -= b - limite; b = limite }
        return (max(0, a), b)
    }

    /// Un intervalle [debut, fin) du petit recadrage ramené à une longueur multiple de 16, et la
    /// taille de l'entrée de Fibo sur cet axe : resserré hors de la zone (et de son fondu), du côté où
    /// elle laisse le plus de place ; sinon agrandi jusqu'au multiple suivant, dans la photo ; sinon
    /// (la zone touche les deux bords de la photo) gardé entier, l'entrée au multiple de 16 inférieur
    /// (à peine réduite) : jamais une bande de la zone laissée hors du recadrage.
    static func ajuster16(_ debut: Int, _ fin: Int, zone z0: Double, _ z1: Double, limite: Int) -> (Int, Int, Int) {
        let longueur = fin - debut
        let retrait = longueur % 16
        guard retrait > 0 else { return (debut, fin, longueur) }
        let placeAvant = max(0, Int(z0.rounded(.down)) - debut), placeApres = max(0, fin - Int(z1.rounded(.up)))
        if longueur > 16, placeAvant + placeApres >= retrait {
            var avant = min(placeAvant, retrait / 2)
            let apres = min(placeApres, retrait - avant)
            avant = retrait - apres
            return (debut + avant, fin - apres, longueur - retrait)
        }
        let ajout = 16 - retrait, libreAvant = debut, libreApres = limite - fin
        if libreAvant + libreApres >= ajout {
            var avant = min(libreAvant, ajout / 2)
            let apres = min(libreApres, ajout - avant)
            avant = ajout - apres
            return (debut - avant, fin + apres, longueur + ajout)
        }
        return (debut, fin, max(16, longueur / 16 * 16))
    }

    /// La zone (de 0 à 1 dans la photo) dans le repère du recadrage (de 0 à 1 dans lui), coupée à lui.
    static func regionDansRecadrage(_ region: CGRect, cadre: Pixels, largeur: Int, hauteur: Int) -> CGRect {
        let x0 = max(0, (region.minX * Double(largeur) - Double(cadre.x)) / Double(cadre.largeur))
        let x1 = min(1, (region.maxX * Double(largeur) - Double(cadre.x)) / Double(cadre.largeur))
        let y0 = max(0, (region.minY * Double(hauteur) - Double(cadre.y)) / Double(cadre.hauteur))
        let y1 = min(1, (region.maxY * Double(hauteur) - Double(cadre.y)) / Double(cadre.hauteur))
        return CGRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }

    /// L'entrée de Fibo : la partie `cadre` de la photo (toute la photo sans cadre), en pixels RGBA 8
    /// bits sRGB à la `taille` donnée.
    static func entree(_ origine: CGImage, cadre: Pixels?, taille: (largeur: Int, hauteur: Int)) -> [UInt8]? {
        let source = cadre.flatMap { origine.cropping(to: $0.rect) } ?? origine
        if let cadre, source.width != cadre.largeur || source.height != cadre.hauteur { return nil }
        return pixelsRGBA8(source, largeur: taille.largeur, hauteur: taille.hauteur)
    }

    // MARK: SeedVR2

    /// L'exécutable de mflux pour SeedVR2 (mise à l'échelle par un modèle), à côté de celui de Fibo.
    static let nomSeedVR = "mflux-upscale-seedvr2"
    static let modeleSeedVR = "seedvr2-7b"
    /// Au-delà de ce facteur (sortie de Fibo → taille native de sa zone), SeedVR2 la remet à la taille.
    static let seuilSeedVR = 1.25

    /// Le facteur de mise à la taille d'une sortie de Fibo de `taille` vers son recadrage natif.
    static func facteur(cadre: Pixels, taille: (largeur: Int, hauteur: Int)) -> Double {
        max(Double(cadre.largeur) / Double(max(1, taille.largeur)), Double(cadre.hauteur) / Double(max(1, taille.hauteur)))
    }

    /// SeedVR2 7B ne découpe en tuiles que son décodeur : au-delà de ce facteur ou de cette taille de
    /// sortie, mémoire et durée sortent de l'échelle d'un Mac (et il inventerait le détail de toute
    /// la zone) ; provisoires, à relever sur de vrais passages.
    static let facteurMaxSeedVR = 4.0
    static let pixelsMaxSeedVR = 16_000_000

    /// SeedVR2 pour une zone, et sinon pourquoi (quand l'agrandissement le demanderait) : seulement
    /// avec une zone donnée (sans elle, il agrandirait toute la photo), si la sortie de Fibo doit être
    /// agrandie de plus de `seuilSeedVR` sur ses deux côtés, au plus `facteurMaxSeedVR` fois, vers
    /// `pixelsMaxSeedVR` au plus.
    /// Avec un masque de Lightroom (`avecMasque`), une zone trop grande le dit sans conseiller region :
    /// un arrière-plan ou un ciel entier dépasse d'ordinaire ce que SeedVR2 agrandit, et region ne
    /// suivrait pas le bord du sujet.
    static func seedVR(cadre: Pixels, taille: (largeur: Int, hauteur: Int), avecRegion: Bool, demande: Bool, avecMasque: Bool = false) -> (lancer: Bool, raison: String?) {
        let fx = Double(cadre.largeur) / Double(max(1, taille.largeur)), fy = Double(cadre.hauteur) / Double(max(1, taille.hauteur))
        guard demande, min(fx, fy) > seuilSeedVR else { return (false, nil) }
        guard avecRegion else {
            return (false, "Sans region, SeedVR2 n'est pas lancé (il agrandirait toute la photo) : mise à la taille ordinaire. Pour plus de détail, redemander avec region sur la seule partie à changer.")
        }
        let pixels = cadre.largeur * cadre.hauteur
        guard max(fx, fy) <= facteurMaxSeedVR, pixels <= pixelsMaxSeedVR else {
            if avecMasque {
                return (false, "Masque trop étendu pour SeedVR2 (× \(ToolHandler.nombre(max(fx, fy))), \(ToolHandler.nombre(Double(pixels) / 1_000_000)) Mpx ; × \(Int(facteurMaxSeedVR)) et \(pixelsMaxSeedVR / 1_000_000) Mpx au plus) : mise à la taille ordinaire, moins de détail dans ce qu'il couvre. C'est attendu pour un arrière-plan ou un ciel entier ; le masque garde le bord du sujet.")
            }
            return (false, "Zone trop grande pour SeedVR2 (× \(ToolHandler.nombre(max(fx, fy))), \(ToolHandler.nombre(Double(pixels) / 1_000_000)) Mpx ; × \(Int(facteurMaxSeedVR)) et \(pixelsMaxSeedVR / 1_000_000) Mpx au plus) : mise à la taille ordinaire, moins de détail. Une region plus juste en garde davantage.")
        }
        return (true, nil)
    }

    /// Les arguments de SeedVR2 : le côté court natif du recadrage, --low-ram (comme Fibo ; il
    /// implique le décodage par tuiles, --vae-tiling, qui n'est donc plus passé).
    static func argumentsSeedVR(entree: URL, resolution: Int, graine: Int, sortie: URL) -> [String] {
        ["--model", modeleSeedVR, "--image-path", entree.path, "--resolution", String(resolution),
         "--seed", String(graine), "--output", sortie.path, "--low-ram"]
    }

    // MARK: Progression

    /// Une barre de 0 à 100 % pour tout l'appel, par poids : exportation, puis, par modification, le
    /// chargement du modèle (avant la première étape), les étapes de Fibo et SeedVR2 (s'il tourne),
    /// enfin la recomposition et l'importation.
    struct Avancement {
        static let poidsExport = 3.0, poidsFiche = 10.0, poidsChargement = 10.0, poidsEtapes = 70.0, poidsSeedVR = 15.0, poidsFin = 5.0
        /// SeedVR2 prévu, par modification.
        var seedVR: [Bool]
        /// La fiche de FIBO-vlm prévue, par modification (avant le chargement de Fibo 2).
        var fiche: [Bool]

        init(seedVR: [Bool], fiche: [Bool]? = nil) {
            self.seedVR = seedVR
            self.fiche = fiche ?? seedVR.map { _ in false }
        }

        enum Phase {
            case export
            /// La fiche de FIBO-vlm en cours (sa fraction, d'après sa durée attendue).
            case fiche(Int, fraction: Double)
            case chargement(Int)
            case etapes(Int, fait: Int, sur: Int)
            case seedVR(Int, fraction: Double)
            case fin
        }

        private func poidsFiche(_ rang: Int) -> Double { rang < fiche.count && fiche[rang] ? Self.poidsFiche : 0 }
        private func poids(_ rang: Int) -> Double {
            poidsFiche(rang) + Self.poidsChargement + Self.poidsEtapes + (seedVR[rang] ? Self.poidsSeedVR : 0)
        }
        private var total: Double { Self.poidsExport + seedVR.indices.reduce(0) { $0 + poids($1) } + Self.poidsFin }
        private func avant(_ rang: Int) -> Double { Self.poidsExport + (0..<rang).reduce(0) { $0 + poids($1) } }

        /// Le pourcentage fait au début de la phase (et dans elle), de 0 à 99 avant la fin.
        func pourcentage(_ phase: Phase) -> Int {
            let fait: Double
            switch phase {
            case .export: fait = 0
            case .fiche(let rang, let fraction): fait = avant(rang) + poidsFiche(rang) * min(1, max(0, fraction))
            case .chargement(let rang): fait = avant(rang) + poidsFiche(rang)
            case .etapes(let rang, let etape, let sur):
                fait = avant(rang) + poidsFiche(rang) + Self.poidsChargement + Self.poidsEtapes * min(1, max(0, Double(etape) / Double(max(1, sur))))
            case .seedVR(let rang, let fraction):
                fait = avant(rang) + poidsFiche(rang) + Self.poidsChargement + Self.poidsEtapes + Self.poidsSeedVR * min(1, max(0, fraction))
            case .fin: fait = total - Self.poidsFin
            }
            return min(99, Int((fait / total * 100).rounded(.down)))
        }
    }

    /// Le temps restant d'après le rythme des étapes déjà faites de la modification en cours (rien
    /// avant deux étapes) : ses étapes restantes, puis, pour chaque modification suivante, la même
    /// fiche de FIBO-vlm (`fiche` : la durée de la dernière, 0 sans fiche), le même chargement du
    /// modèle et toutes ses étapes. SeedVR2 n'y compte pas (aucun rythme connu).
    static func tempsRestant(etape: Int, sur: Int, premiere: Int, secondesDepuisPremiere: TimeInterval,
                             chargement: TimeInterval, suivantes: Int, fiche: TimeInterval = 0) -> TimeInterval? {
        let faites = etape - premiere
        guard faites >= 2, secondesDepuisPremiere > 0 else { return nil }
        let parEtape = secondesDepuisPremiere / Double(faites)
        return Double(max(0, sur - etape)) * parEtape + Double(suivantes) * (fiche + chargement + Double(sur) * parEtape)
    }

    /// « environ 3 min restantes », « environ 1 min restante », « moins d'une minute restante ».
    static func texteTempsRestant(_ secondes: TimeInterval) -> String {
        guard secondes >= 60 else { return "moins d'une minute restante" }
        let minutes = Int((secondes / 60).rounded())
        return minutes <= 1 ? "environ 1 min restante" : "environ \(minutes) min restantes"
    }

    /// Le texte de la barre : « Fibo 2 : jupe (1 sur 2), 24 % — environ 3 min restantes ».
    static func texteProgression(_ quoi: String, rang: Int?, sur: Int, pourcentage: Int, detail: String?) -> String {
        var texte = "Fibo 2 : " + quoi
        if let rang, sur > 1 { texte += " (\(rang) sur \(sur))" }
        texte += ", \(pourcentage) %"
        if let detail { texte += " — " + detail }
        return texte
    }

    /// Une barre de téléchargement ou de chargement (« Fetching 4 files: 4/4 [ », « Loading
    /// checkpoint shards: 2/4 [ ») : jamais lue comme des étapes ni comme l'avancée de SeedVR2.
    static func estUnChargement(_ ligne: String) -> Bool {
        ligne.range(of: #"(?i)fetching|loading|download"#, options: .regularExpression) != nil
    }

    /// L'avancée d'une barre tqdm quelconque (« 3/8 [ »), pour SeedVR2.
    static func progressionLibre(_ ligne: String) -> (fait: Int, total: Int)? {
        guard !estUnChargement(ligne) else { return nil }
        let plage = NSRange(ligne.startIndex..., in: ligne)
        guard let trouve = motifProgression.firstMatch(in: ligne, range: plage),
              let r1 = Range(trouve.range(at: 1), in: ligne), let r2 = Range(trouve.range(at: 2), in: ligne),
              let fait = Int(ligne[r1]), let total = Int(ligne[r2]), total > 0 else { return nil }
        return (fait, total)
    }

    // MARK: Sortie de mflux

    /// Les lignes de la sortie de mflux, reçue par morceaux : tqdm réécrit sa ligne avec \r.
    struct Lignes {
        private var reste = ""
        mutating func ajouter(_ texte: String) -> [String] {
            reste += texte
            var parties = reste.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            reste = parties.removeLast()
            return parties.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        mutating func finir() -> [String] {
            defer { reste = "" }
            return reste.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [reste]
        }
    }

    private static let motifProgression = try! NSRegularExpression(pattern: #"(\d+)/(\d+) \["#)

    /// L'étape d'une barre tqdm (« 12/50 [ »), si la ligne en porte une avec le nombre d'étapes voulu.
    static func progression(_ ligne: String, etapes: Int) -> Int? {
        guard !estUnChargement(ligne) else { return nil }
        let plage = NSRange(ligne.startIndex..., in: ligne)
        guard let trouve = motifProgression.firstMatch(in: ligne, range: plage),
              let r1 = Range(trouve.range(at: 1), in: ligne), let r2 = Range(trouve.range(at: 2), in: ligne),
              let etape = Int(ligne[r1]), let total = Int(ligne[r2]), total == etapes else { return nil }
        return etape
    }

    /// Une erreur de mflux, en mots simples, d'après son journal. Un accès refusé se reconnaît à des
    /// motifs précis (« 401 Client Error », « Unauthorized »…), jamais à « 401 » ou « 403 » seuls,
    /// qu'une barre de téléchargement écrit aussi (« 401M/9.95G »).
    static func expliquer(journal: String, code: Int32, rapide: Bool) -> String {
        let depot = rapide ? depotRapide : depotNormal
        if ["requires approval", "GatedRepo", "Unauthorized", "Forbidden"].contains(where: journal.contains)
            || journal.range(of: #"\b40[13] Client Error\b"#, options: .regularExpression) != nil {
            return "Fibo 2 : accès au modèle refusé. Demander l'accès sur huggingface.co/\(depot), puis vérifier la connexion avec « hf auth login » dans le Terminal."
        }
        if journal.contains("RevisionNotFound") {
            return "Fibo 2 : le modèle n'est pas complet sur ce Mac. Le télécharger une fois dans le Terminal : hf download \(depot)"
        }
        if ["ConnectionError", "Max retries", "Temporary failure", "LocalEntryNotFound"].contains(where: journal.contains) {
            return "Fibo 2 : impossible de joindre Hugging Face (le modèle se télécharge au premier usage). Vérifier la connexion Internet, puis réessayer."
        }
        let fin = journal.split(separator: "\n").suffix(3).joined(separator: "\n")
        return "Fibo 2 (mflux) s'est arrêté avec une erreur (code \(code))." + (fin.isEmpty ? "" : "\n" + fin)
    }

    // MARK: Masques

    /// Le masque de Fibo : blanc dans la zone élargie de la marge, noir ailleurs (0 ou 255 par pixel).
    static func masqueRegion(_ region: CGRect, largeur: Int, hauteur: Int) -> [UInt8] {
        let marge = margeRegion * Double(min(largeur, hauteur))
        let x0 = max(0, Int((region.minX * Double(largeur) - marge).rounded(.down)))
        let x1 = min(largeur, Int((region.maxX * Double(largeur) + marge).rounded(.up)))
        let y0 = max(0, Int((region.minY * Double(hauteur) - marge).rounded(.down)))
        let y1 = min(hauteur, Int((region.maxY * Double(hauteur) + marge).rounded(.up)))
        var masque = [UInt8](repeating: 0, count: largeur * hauteur)
        guard x0 < x1, y0 < y1 else { return masque }
        for y in y0..<y1 {
            for x in x0..<x1 { masque[y * largeur + x] = 255 }
        }
        return masque
    }

    /// Flou en boîte séparable (sommes glissantes), bords répétés.
    static func flouBoite(_ valeurs: [Float], largeur: Int, hauteur: Int, rayon: Int) -> [Float] {
        guard rayon > 0, largeur > 0, hauteur > 0 else { return valeurs }
        let fenetre = Float(2 * rayon + 1)
        var tmp = [Float](repeating: 0, count: valeurs.count)
        var sortie = [Float](repeating: 0, count: valeurs.count)
        for y in 0..<hauteur {
            let base = y * largeur
            var somme: Float = 0
            for k in -rayon...rayon { somme += valeurs[base + min(max(k, 0), largeur - 1)] }
            for x in 0..<largeur {
                tmp[base + x] = somme / fenetre
                somme += valeurs[base + min(x + rayon + 1, largeur - 1)] - valeurs[base + max(x - rayon, 0)]
            }
        }
        for x in 0..<largeur {
            var somme: Float = 0
            for k in -rayon...rayon { somme += tmp[min(max(k, 0), hauteur - 1) * largeur + x] }
            for y in 0..<hauteur {
                sortie[y * largeur + x] = somme / fenetre
                somme += tmp[min(y + rayon + 1, hauteur - 1) * largeur + x] - tmp[max(y - rayon, 0) * largeur + x]
            }
        }
        return sortie
    }

    /// La zone changée par Fibo (de 0 à 1 par pixel, à la petite taille) : l'écart entre l'entrée et
    /// la sortie (pixels RGBA 8 bits, même taille), lissé, seuillé, débarrassé des points isolés,
    /// élargi puis fondu ; coupée par la zone donnée (élargie de la marge, fondue), s'il y en a une.
    /// Avec une zone donnée, elle ne sert qu'à mesurer ce qui a changé : la recomposition prend la
    /// zone entière (`zoneDeMelange`).
    static func zoneChangee(entree: [UInt8], sortie: [UInt8], largeur: Int, hauteur: Int, region: CGRect?, borne: [Float]? = nil) -> [Float] {
        let n = largeur * hauteur
        guard n > 0, entree.count >= n * 4, sortie.count >= n * 4 else { return [] }
        var ecart = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var plus: Int32 = 0
            for c in 0..<3 { plus = max(plus, abs(Int32(entree[i * 4 + c]) - Int32(sortie[i * 4 + c]))) }
            ecart[i] = Float(plus) / 255
        }
        let petit = Double(min(largeur, hauteur))
        let lisse = flouBoite(ecart, largeur: largeur, hauteur: hauteur, rayon: 1)
        var binaire = lisse.map { $0 > seuilEcart ? Float(1) : 0 }
        // Points isolés : un pixel n'en est que si la majorité de son voisinage (5 × 5) l'est aussi ;
        // une bande de 3 pixels, ce que le flou fait d'un trait d'un pixel, la garde.
        binaire = flouBoite(binaire, largeur: largeur, hauteur: hauteur, rayon: 2).map { $0 > 0.5 ? 1 : 0 }
        let elargi = flouBoite(binaire, largeur: largeur, hauteur: hauteur, rayon: max(1, Int(petit * elargissement)))
            .map { $0 > 0.0001 ? Float(1) : 0 }
        let rayonFondu = max(1, Int(petit * fondu))
        var zone = flouBoite(flouBoite(elargi, largeur: largeur, hauteur: hauteur, rayon: rayonFondu), largeur: largeur, hauteur: hauteur, rayon: rayonFondu)
        if let borne, borne.count == n {
            for i in 0..<n { zone[i] *= borne[i] }
        } else if let region {
            let borne = masqueRegionDoux(region, largeur: largeur, hauteur: hauteur)
            for i in 0..<n { zone[i] *= borne[i] }
        }
        return zone
    }

    /// La zone de mélange : avec une zone donnée, toute la sortie de Fibo dans cette zone (élargie de
    /// la marge, fondue) : Fibo n'a travaillé que là, sous son masque, et un changement fin ou peu
    /// contrasté que la mesure manquerait y est repris quand même ; sans zone, la zone changée
    /// mesurée, ou toute l'image si elle dépasse `partSortieEntiere`. Rend aussi si toute la sortie
    /// est prise (sans zone donnée seulement).
    static func zoneDeMelange(changee: [Float], region: CGRect?, largeur: Int, hauteur: Int) -> (zone: [Float], sortieEntiere: Bool) {
        if let region {
            return (masqueRegionDoux(region, largeur: largeur, hauteur: hauteur), false)
        }
        if part(changee) > partSortieEntiere {
            return ([Float](repeating: 1, count: largeur * hauteur), true)
        }
        return (changee, false)
    }

    /// La remarque d'une sortie prise entière (sans zone donnée : avec une zone, c'est toujours la
    /// zone entière, sans remarque) ; la part est celle de l'image.
    static func remarqueSortieEntiere(partChangee: Double, sortieEntiere: Bool) -> String? {
        guard sortieEntiere else { return nil }
        return "La zone changée couvrait \(Int((partChangee * 100).rounded())) % de l'image : toute la sortie de Fibo 2 est prise, à sa résolution d'environ 1 Mpx : moins de détail partout. Pour garder le détail, redemander avec region sur la seule partie à changer."
    }

    /// La zone donnée élargie de la marge et fondue (de 0 à 1), pour borner le mélange.
    static func masqueRegionDoux(_ region: CGRect, largeur: Int, hauteur: Int) -> [Float] {
        let dur = masqueRegion(region, largeur: largeur, hauteur: hauteur).map { Float($0) / 255 }
        let rayon = max(1, Int(Double(min(largeur, hauteur)) * margeRegion / 2))
        return flouBoite(flouBoite(dur, largeur: largeur, hauteur: hauteur, rayon: rayon), largeur: largeur, hauteur: hauteur, rayon: rayon)
    }

    /// La part de l'image dans la zone (pixels à plus de 0,5).
    static func part(_ zone: [Float]) -> Double {
        guard !zone.isEmpty else { return 0 }
        return Double(zone.reduce(0) { $0 + ($1 > 0.5 ? 1 : 0) }) / Double(zone.count)
    }

    // MARK: Masque de Lightroom (mask)

    /// Les deux effets témoins du masque de Fibo, aux clés d'une correction de masque, rendus l'un après
    /// l'autre (deux commandes essayer) : un pixel est dans le masque si l'un des deux le change.
    /// Aucun ne mêle deux réglages de sens contraire (−2 IL et des noirs relevés s'annulaient dans une
    /// plage de tons sombres, qui échappait au masque). Le sombre, −2 IL (LocalExposure2012 de −0,5)
    /// et une température plus froide, change tous les tons, blancs brûlés compris, sauf le noir pur et
    /// les tons les plus sombres (moins de 6 niveaux d'écart) ; le clair, +1,5 IL (comme la carte
    /// d'add_mask, CarteMasque.temoin), les noirs relevés (+30) et la même température, change ceux-là,
    /// mais plus un blanc brûlé. Provisoires : reste à constater dans Lightroom sur un noir pur, un fond
    /// très sombre et un blanc brûlé.
    static let temoinSombre: [String: JSONValue] = ["LocalExposure2012": .number(-0.5), "LocalTemperature": .number(-0.4)]
    static let temoinClair: [String: JSONValue] = ["LocalExposure2012": .number(0.375), "LocalBlacks2012": .number(0.3),
                                                    "LocalTemperature": .number(-0.4)]
    static let temoinsMasque = [temoinSombre, temoinClair]
    /// Le nom du masque témoin (et de l'étape d'essai, qui n'est pas gardée).
    static let nomMasqueTemoin = "Claude · masque pour Fibo 2"
    /// Écart d'un canal (sur 255) entre l'état actuel et un témoin à partir duquel un pixel est dans le
    /// masque : celui de la carte d'add_mask (les blocs JPEG au bord du masque bougent de 1 à 3).
    static let seuilMasque = CarteMasque.seuilEcart
    /// Un masque qui couvre moins que cette part de la photo est vide (Lightroom n'y a rien trouvé) ;
    /// un masque qui en laisse moins hors de lui couvre toute la photo (inversé, ou aucun sujet trouvé).
    /// 0,01 % : environ 2 600 px à 26 Mpx (51 × 51) ; un petit sujet (un oiseau de 0,4 % du cadre, et
    /// l'arrière-plan à 99,6 %) passe. Provisoire.
    static let partMasqueMin = 0.0001
    /// Le nettoyage retire du masque chaque îlot et bouche chaque trou (composantes connexes, en
    /// 8-connexité) de moins de pixels qu'un carré du grand côté de la photo divisé par ce nombre
    /// (13 px de côté, 169 px, pour une photo de 6 240 px) : les points du bruit JPEG ; un trait fin
    /// mais long (une mèche, une sangle, le jour entre le bras et le corps) est une grande composante,
    /// gardé au pixel. Provisoire.
    static let grilleNettoyage = 512
    /// Élargissement du masque donné à Fibo (part du petit côté de son entrée), pour qu'il redessine
    /// aussi le bord : environ 10 px à 1 Mpx. Provisoire.
    static let margeMasque = 0.01
    /// Fondu du masque binaire (`fonduBinaire`), en pleine résolution (part du petit côté de la photo,
    /// au moins 2 px : 6 px pour une photo de 4 160 px de haut), sans élargissement : le repli de
    /// l'opacité là où les témoins ne disent rien. Provisoire.
    static let fonduMasque = 0.0015

    // Le bord doux : l'opacité du masque de Lightroom (`OpaciteDuMasque`), lue dans l'écart entre
    // l'état actuel et les deux témoins. Relevé du 29 octobre 2026 sur l'essai réel (portrait
    // DSCF2402, 6 240 × 4 160, arrière-plan remplacé par Times Square, cheveux bruns, poncho noir) :
    // le bord du masque binaire tombait là où l'opacité de Lightroom n'est que de 0 à 20 %, et les
    // mèches fines passaient entières à Fibo (« photo collée ») ; le masque IA de Lightroom est une
    // rampe lisse d'environ 20 px autour des cheveux, presque toute dans le masque binaire (des pixels
    // partiels jusqu'à 48 px du bord, aucun au-delà de 64). Comparé au labo à trois autres bords
    // (fondu large asymétrique, filtre guidé, opacité décontaminée) : le seul net au poncho, sans
    // bloc ni liseré, mèches gardées sur le nouveau fond ; il reste un léger voile de l'ancien fond là
    // où Lightroom met lui-même une opacité moyenne. Tous provisoires : un seul portrait, à éprouver
    // sur un sujet clair devant un fond sombre et sur un ciel.

    /// La rampe renforcée de l'opacité : sous `opaciteBas`, 0 ; à `opaciteHaut` ou plus, pleine ; entre
    /// les deux, une courbe douce (smoothstep). Une rampe de 0,12 à 0,85 laissait un voile gris de
    /// l'ancien fond entre les mèches ; de 0,03 à 0,35, nettement moins. Provisoires.
    static let opaciteBas = 0.03
    static let opaciteHaut = 0.35
    /// Poids du masque binaire en a priori dans les moindres carrés (λ) : là où les témoins changent
    /// peu un pixel (noir pur au témoin sombre, blanc brûlé au clair), le binaire reprend la main.
    /// Provisoire.
    static let opaciteAPriori: Float = 0.3
    /// ε de log2(lumière linéaire + ε) : les écarts se lisent en lumière linéaire, où l'effet d'une
    /// exposition locale est proportionnel à l'opacité. Provisoire.
    static let opaciteEpsilon = 0.002
    /// Intérieur sûr (où l'effet plein se relève) : les pixels du masque binaire à plus de cette part
    /// du petit côté de tout pixel hors de lui (au moins 2 px ; 12 px à 4 160 px). Provisoire.
    static let opaciteErosion = 0.003
    /// Le calcul de l'opacité s'étend de ce nombre de pixels hors du masque binaire (le lissage d'un
    /// pixel, deux passages) ; le repli (`opaciteAppui`) s'étend de toute l'étendue du fondu binaire
    /// si elle est plus large (`margeOpacite`) ; au-delà, la zone vaut exactement 0 : la photo garde
    /// ses pixels au bit près.
    static let opaciteMarge = 2
    /// Sous cette somme des carrés des effets pleins (Σ f²), les témoins ne disent presque rien d'un
    /// pixel : l'opacité y glisse vers le masque binaire fondu (`fonduBinaire`), comme avant le
    /// 29 octobre 2026, sur toute la largeur de ce fondu ; rien n'en devient plus dur qu'avant. Un ton
    /// moyen en donne une quarantaine. Provisoire.
    static let opaciteAppui: Float = 1

    /// L'étendue du fondu binaire (`fonduBinaire`) de part et d'autre du bord, en pixels : deux boîtes
    /// de la moitié du rayon (`fonduMasque` du petit côté, au moins 2 px) ; 2 px à 1 000 px, 6 px à
    /// 4 160 px.
    static func etendueFondu(largeur l: Int, hauteur h: Int) -> Int {
        let rayon = max(2, Int((Double(min(l, h)) * fonduMasque).rounded()))
        return 2 * max(1, rayon / 2)
    }

    /// Jusqu'où la zone peut s'étendre hors du masque binaire : `opaciteMarge`, ou l'étendue du fondu
    /// binaire si elle est plus large (le repli garde ainsi tout l'ancien bord ; l'opacité lue, elle,
    /// s'arrête à `opaciteMarge`).
    static func margeOpacite(largeur l: Int, hauteur h: Int) -> Int {
        max(opaciteMarge, etendueFondu(largeur: l, hauteur: h))
    }

    /// Le masque témoin à rendre : la zone (kind, inversion, composants), un effet témoin seul
    /// (`temoinsMasque`), à pleine intensité.
    static func masqueTemoin(_ zone: [String: JSONValue], locaux: [String: JSONValue]) -> JSONValue {
        var objet = zone
        objet["locaux"] = .object(locaux)
        objet["quantite"] = .number(1)
        objet["nom"] = .string(nomMasqueTemoin)
        return .object(objet)
    }

    /// Ajoute au masque binaire (1 dedans, 0 dehors) les pixels où un canal s'écarte d'au moins
    /// `seuilMasque` entre l'état actuel et un témoin (pixels RGBA 8 bits, même taille).
    static func ajouterAuMasque(_ masque: inout [UInt8], actuel: [UInt8], temoin: [UInt8]) {
        let nombre = masque.count
        guard nombre > 0, actuel.count >= nombre * 4, temoin.count >= nombre * 4 else { return }
        let seuil = Int16(seuilMasque)
        actuel.withUnsafeBufferPointer { a in
            temoin.withUnsafeBufferPointer { t in
                masque.withUnsafeMutableBufferPointer { m in
                    for i in 0..<nombre where m[i] == 0 {
                        let k = i * 4
                        if abs(Int16(a[k]) - Int16(t[k])) >= seuil || abs(Int16(a[k + 1]) - Int16(t[k + 1])) >= seuil
                            || abs(Int16(a[k + 2]) - Int16(t[k + 2])) >= seuil { m[i] = 1 }
                    }
                }
            }
        }
    }

    /// Le masque binaire d'un seul témoin.
    static func masqueBinaire(actuel: [UInt8], temoin: [UInt8], nombre: Int) -> [UInt8] {
        guard nombre > 0, actuel.count >= nombre * 4, temoin.count >= nombre * 4 else { return [] }
        var masque = [UInt8](repeating: 0, count: nombre)
        ajouterAuMasque(&masque, actuel: actuel, temoin: temoin)
        return masque
    }

    /// Le masque binaire de l'état actuel et des témoins (tous de même taille) : l'union de leurs
    /// écarts, nettoyée ; et son opacité au bord (`OpaciteDuMasque`), de 0 à 255 ; nil si les rendus
    /// n'ont pas la même taille ou ne se lisent pas. Les témoins se décodent l'un après l'autre (un
    /// seul rendu de 26 Mpx de plus en mémoire à la fois) ; le dernier sert encore à l'opacité, les
    /// autres s'y décodent une seconde fois (le binaire doit être fini avant).
    static func masqueDesRendus(actuel: CGImage, temoins: [CGImage])
        -> (masque: [UInt8], opacite: [UInt8], largeur: Int, hauteur: Int)? {
        let l = actuel.width, h = actuel.height
        guard l > 0, h > 0, !temoins.isEmpty, temoins.allSatisfy({ $0.width == l && $0.height == h }),
              var a = pixelsRGBA8(actuel, largeur: l, hauteur: h) else { return nil }
        var masque = [UInt8](repeating: 0, count: l * h)
        var dernier: [UInt8] = []
        for (rang, temoin) in temoins.enumerated() {
            guard let t = pixelsRGBA8(temoin, largeur: l, hauteur: h) else { return nil }
            ajouterAuMasque(&masque, actuel: a, temoin: t)
            if rang == temoins.count - 1 { dernier = t }
        }
        nettoyer(&masque, largeur: l, hauteur: h)
        var opacite = OpaciteDuMasque(binaire: masque, largeur: l, hauteur: h)
        opacite.ajouter(actuel: a, temoin: dernier)
        dernier = []
        for temoin in temoins.dropLast() {
            guard let t = pixelsRGBA8(temoin, largeur: l, hauteur: h) else { return nil }
            opacite.ajouter(actuel: a, temoin: t)
        }
        a = []
        return (masque, opacite.opacite(binaire: masque), l, h)
    }

    /// L'aire (en pixels) sous laquelle une composante du masque est retirée (îlot) ou bouchée (trou).
    static func aireNettoyage(largeur l: Int, hauteur h: Int) -> Int {
        let cote = max(1, Int((Double(max(l, h)) / Double(grilleNettoyage)).rounded(.up)))
        return cote * cote
    }

    /// Le nettoyage d'un masque binaire : les îlots (composantes de 1), puis les trous (composantes de
    /// 0), en 8-connexité, de moins de `aireNettoyage` pixels changent de valeur ; tout le reste garde
    /// ses pixels. En temps borné : chaque composante n'est suivie que jusqu'à cette aire, ou jusqu'à
    /// une composante déjà jugée grande ; un pixel n'est ainsi parcouru qu'un nombre borné de fois, et
    /// la mémoire tient en un octet par pixel et une liste de l'aire.
    static func nettoyer(_ masque: inout [UInt8], largeur l: Int, hauteur h: Int) {
        guard l > 0, h > 0, masque.count == l * h else { return }
        let aire = aireNettoyage(largeur: l, hauteur: h)
        guard aire > 1 else { return }
        // 0 : pas encore vu ; 1 : dans la composante suivie ; 2 : d'une grande composante (gardée).
        var etat = [UInt8](repeating: 0, count: l * h)
        var suivis = [Int](repeating: 0, count: aire)
        // Les huit voisins, par leur décalage dans l'image (loin des bords) et leur pas en x et en y.
        let pasX = [-1, 0, 1, -1, 1, -1, 0, 1], pasY = [-1, -1, -1, 0, 0, 1, 1, 1]
        let decalages = (0..<8).map { pasY[$0] * l + pasX[$0] }
        masque.withUnsafeMutableBufferPointer { m in
            etat.withUnsafeMutableBufferPointer { e in
                suivis.withUnsafeMutableBufferPointer { liste in
                    for valeur in [UInt8(1), 0] {
                        for i in 0..<(l * h) { e[i] = 0 }
                        var depart = 0
                        while depart < l * h {
                            defer { depart += 1 }
                            guard m[depart] == valeur, e[depart] == 0 else { continue }
                            // Suivi en largeur : la liste sert de file, jusqu'à `aire` pixels.
                            var nombre = 1, lu = 0, grande = false
                            liste[0] = depart
                            e[depart] = 1
                            while lu < nombre, !grande {
                                let p = liste[lu]
                                lu += 1
                                let x = p % l, y = p / l
                                let interieur = x > 0 && x < l - 1 && y > 0 && y < h - 1
                                var k = 0
                                while k < 8 {
                                    let q: Int
                                    if interieur {
                                        q = p + decalages[k]
                                    } else {
                                        let nx = x + pasX[k], ny = y + pasY[k]
                                        guard nx >= 0, nx < l, ny >= 0, ny < h else { k += 1; continue }
                                        q = ny * l + nx
                                    }
                                    k += 1
                                    guard m[q] == valeur else { continue }
                                    let eq = e[q]
                                    if eq == 2 { grande = true; break }
                                    if eq == 0 {
                                        e[q] = 1
                                        liste[nombre] = q
                                        nombre += 1
                                        if nombre == aire { grande = true; break }
                                    }
                                }
                            }
                            if grande {
                                for k in 0..<nombre { e[liste[k]] = 2 }
                            } else {
                                // Une petite composante : elle change de valeur (et n'est plus suivie).
                                for k in 0..<nombre { m[liste[k]] = 1 - valeur; e[liste[k]] = 2 }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Le masque remis à une autre taille (celle du TIFF exporté), au plus proche voisin.
    static func redimensionner(_ masque: [UInt8], largeur l: Int, hauteur h: Int, versLargeur nl: Int, versHauteur nh: Int) -> [UInt8] {
        guard l > 0, h > 0, nl > 0, nh > 0, masque.count == l * h else { return [] }
        if l == nl, h == nh { return masque }
        let colonne = (0..<nl).map { min(l - 1, Int((Double($0) + 0.5) * Double(l) / Double(nl))) }
        var sortie = [UInt8](repeating: 0, count: nl * nh)
        for y in 0..<nh {
            let sy = min(h - 1, Int((Double(y) + 0.5) * Double(h) / Double(nh)))
            let base = sy * l, o = y * nl
            for x in 0..<nl { sortie[o + x] = masque[base + colonne[x]] }
        }
        return sortie
    }

    /// L'opacité du masque (de 0 à 255) remise à une autre taille, en bilinéaire (le plus proche voisin
    /// referait des marches au bord doux) ; puis 0 exactement hors du masque binaire déjà remis à cette
    /// taille (`binaire`) et élargi de `margeOpacite` à cette taille, comme à la lecture.
    static func redimensionnerOpacite(_ opacite: [UInt8], largeur l: Int, hauteur h: Int, binaire: [UInt8],
                                      versLargeur nl: Int, versHauteur nh: Int) -> [UInt8] {
        guard l > 0, h > 0, nl > 0, nh > 0, opacite.count == l * h, binaire.count == nl * nh else { return [] }
        if l == nl, h == nh { return opacite }
        // Les deux voisins et le poids de chaque colonne (centres de pixels alignés, bords répétés).
        func voisins(_ i: Int, _ n: Int, _ nn: Int) -> (Int, Int, Float) {
            let s = max(0, min(Double(n - 1), (Double(i) + 0.5) * Double(n) / Double(nn) - 0.5))
            let a = Int(s.rounded(.down))
            return (a, min(n - 1, a + 1), Float(s - Double(a)))
        }
        let colonnes = (0..<nl).map { voisins($0, l, nl) }
        let marge = UInt8(margeOpacite(largeur: nl, hauteur: nh))
        let dehors = distanceEchiquier(binaire, largeur: nl, hauteur: nh, dedans: false, plafond: Int(marge) + 1)
        var sortie = [UInt8](repeating: 0, count: nl * nh)
        opacite.withUnsafeBufferPointer { o in
            sortie.withUnsafeMutableBufferPointer { s in
                for y in 0..<nh {
                    let (y0, y1, v) = voisins(y, h, nh)
                    let l0 = y0 * l, l1 = y1 * l, base = y * nl
                    for x in 0..<nl where dehors[base + x] <= marge {
                        let (x0, x1, u) = colonnes[x]
                        let haut = Float(o[l0 + x0]) * (1 - u) + Float(o[l0 + x1]) * u
                        let bas = Float(o[l1 + x0]) * (1 - u) + Float(o[l1 + x1]) * u
                        s[base + x] = UInt8(min(255, max(0, (haut * (1 - v) + bas * v).rounded())))
                    }
                }
            }
        }
        return sortie
    }

    /// La part de la photo couverte par le masque (de 0 à 1) et son cadre englobant (de 0 à 1 depuis
    /// le coin haut gauche ; nil s'il est vide).
    static func cadreDuMasque(_ masque: [UInt8], largeur l: Int, hauteur h: Int) -> (part: Double, cadre: CGRect?) {
        guard l > 0, h > 0, masque.count == l * h else { return (0, nil) }
        var compte = 0, x0 = l, x1 = -1, y0 = h, y1 = -1
        masque.withUnsafeBufferPointer { m in
            for y in 0..<h {
                let base = y * l
                var premier = -1, dernier = -1
                for x in 0..<l where m[base + x] != 0 {
                    compte += 1
                    if premier < 0 { premier = x }
                    dernier = x
                }
                if premier >= 0 {
                    x0 = min(x0, premier); x1 = max(x1, dernier)
                    y0 = min(y0, y); y1 = y
                }
            }
        }
        guard compte > 0 else { return (0, nil) }
        let cadre = CGRect(x: Double(x0) / Double(l), y: Double(y0) / Double(h),
                           width: Double(x1 - x0 + 1) / Double(l), height: Double(y1 - y0 + 1) / Double(h))
        return (Double(compte) / Double(l * h), cadre)
    }

    /// Le refus d'un masque presque vide ou presque total (nil s'il convient), avant tout calcul de
    /// Fibo 2 : moins de `partMasqueMin` de la photo dans le masque, ou hors de lui. `peint` : le nom
    /// d'un masque que l'utilisateur a peint (mask.existing) ; ce n'est pas Lightroom qui a calculé sa
    /// zone, le refus le dit sans renvoyer à un masque calculé (kind, add_mask), qui le remplacerait.
    static func refusMasque(part: Double, peint: String? = nil) -> String? {
        let texte = CarteMasque.pourcent(part * 100)
        if let nom = peint {
            if part < partMasqueMin {
                return "Le masque « \(nom) » peint dans Lightroom ne couvre presque rien de la photo (\(texte)) : le repeindre plus large dans le panneau Masquage, ou donner region. Rien n'a été fait."
            }
            if 1 - part < partMasqueMin {
                return "Le masque « \(nom) » peint dans Lightroom couvre toute la photo (\(texte)) : inversé dans le panneau Masquage ? Pour changer toute la photo, ni mask ni region. Rien n'a été fait."
            }
            return nil
        }
        if part < partMasqueMin {
            return "Le masque de Lightroom ne couvre presque rien de la photo (\(texte)) : Lightroom n'y a sans doute rien trouvé (kind, part, person ?), ou le sujet est minuscule. Le vérifier avec add_mask et mask_map, ou donner region. Rien n'a été fait."
        }
        if 1 - part < partMasqueMin {
            return "Le masque de Lightroom couvre toute la photo (\(texte)) : inversé, ou Lightroom n'a trouvé aucun sujet ? Pour un sujet minuscule, donner region ; pour changer toute la photo, ni mask ni region. Rien n'a été fait."
        }
        return nil
    }

    /// Le masque donné à Fibo, à la taille de son entrée (0 ou 255 par pixel) : la part couverte de
    /// chaque pixel d'entrée (la moyenne des pixels de la photo qu'il couvre, dans le recadrage),
    /// blanc à la moitié ou plus, puis élargi de `margeMasque` du petit côté de l'entrée, pour que
    /// Fibo redessine aussi le bord. mflux grise lui-même la zone blanche (comme à l'entraînement).
    static func masquePourFibo(_ masque: [UInt8], largeurPhoto: Int, cadre: Pixels, taille: (largeur: Int, hauteur: Int)) -> [UInt8] {
        let tl = taille.largeur, th = taille.hauteur, cl = cadre.largeur, ch = cadre.hauteur
        guard tl > 0, th > 0, cl > 0, ch > 0, masque.count >= (cadre.y + ch) * largeurPhoto else { return [] }
        let colonne = (0..<cl).map { min(tl - 1, $0 * tl / cl) }
        var compte = [Int32](repeating: 0, count: tl * th), aire = [Int32](repeating: 0, count: tl * th)
        masque.withUnsafeBufferPointer { m in
            for y in 0..<ch {
                let iy = min(th - 1, y * th / ch), base = (cadre.y + y) * largeurPhoto + cadre.x, ligne = iy * tl
                for x in 0..<cl {
                    let i = ligne + colonne[x]
                    aire[i] += 1
                    if m[base + x] != 0 { compte[i] += 1 }
                }
            }
        }
        let binaire = (0..<(tl * th)).map { aire[$0] > 0 && 2 * compte[$0] >= aire[$0] ? Float(1) : 0 }
        let rayon = max(1, Int((Double(min(tl, th)) * margeMasque).rounded()))
        return flouBoite(binaire, largeur: tl, hauteur: th, rayon: rayon).map { $0 > 0.0001 ? 255 : 0 }
    }

    /// Le masque binaire fondu, en pleine résolution, dans le recadrage : fondu de `fonduMasque` du
    /// petit côté de la photo (au moins 2 px), sans élargissement ; hors du masque et de ce fondu, 0
    /// exactement. C'était la zone de mélange jusqu'au 29 octobre 2026 (un bord net mais découpé, les
    /// mèches fines mangées) ; c'est le repli de l'opacité (`OpaciteDuMasque`) là où les témoins ne
    /// disent rien.
    static func fonduBinaire(_ masque: [UInt8], largeurPhoto: Int, hauteurPhoto: Int, cadre: Pixels) -> [Float] {
        let cl = cadre.largeur, ch = cadre.hauteur
        guard cl > 0, ch > 0, masque.count >= (cadre.y + ch) * largeurPhoto else { return [] }
        var zone = [Float](repeating: 0, count: cl * ch)
        masque.withUnsafeBufferPointer { m in
            zone.withUnsafeMutableBufferPointer { z in
                for y in 0..<ch {
                    let base = (cadre.y + y) * largeurPhoto + cadre.x, o = y * cl
                    for x in 0..<cl where m[base + x] != 0 { z[o + x] = 1 }
                }
            }
        }
        // Deux flous en boîte de la moitié du rayon : le fondu s'étend de `etendueFondu` de part et
        // d'autre du bord.
        let etendue = etendueFondu(largeur: largeurPhoto, hauteur: hauteurPhoto)
        sommeBoiteEnPlace(&zone, largeur: cl, hauteur: ch, rayon: etendue / 2, passages: 2)
        return zone
    }

    /// La zone de mélange d'un masque de Lightroom, en pleine résolution, dans le recadrage : son
    /// opacité (`OpaciteDuMasque.opacite`, de 0 à 255) ramenée de 0 à 1. Hors du masque binaire
    /// élargi de `margeOpacite`, elle vaut exactement 0 (la photo garde ses pixels au bit près).
    static func zoneDuMasque(_ opacite: [UInt8], largeurPhoto: Int, cadre: Pixels) -> [Float] {
        let cl = cadre.largeur, ch = cadre.hauteur
        guard cl > 0, ch > 0, opacite.count >= (cadre.y + ch) * largeurPhoto else { return [] }
        var zone = [Float](repeating: 0, count: cl * ch)
        opacite.withUnsafeBufferPointer { o in
            zone.withUnsafeMutableBufferPointer { z in
                for y in 0..<ch {
                    let base = (cadre.y + y) * largeurPhoto + cadre.x, ligne = y * cl
                    for x in 0..<cl where o[base + x] != 0 { z[ligne + x] = Float(o[base + x]) / 255 }
                }
            }
        }
        return zone
    }

    /// La distance (en échiquier : un voisin, en diagonale compris, est à 1) de chaque pixel d'une
    /// classe (`dedans` : le masque ; sinon hors de lui) au plus proche pixel de l'autre classe,
    /// plafonnée ; 0 pour les pixels de l'autre classe. Le bord de l'image n'est pas une frontière.
    /// Deux parcours, en avant puis en arrière : exact pour cette distance.
    static func distanceEchiquier(_ masque: [UInt8], largeur l: Int, hauteur h: Int, dedans: Bool, plafond: Int) -> [UInt8] {
        guard l > 0, h > 0, masque.count == l * h else { return [] }
        let cap = UInt8(max(1, min(255, plafond)))
        var d = [UInt8](repeating: 0, count: l * h)
        masque.withUnsafeBufferPointer { m in
            d.withUnsafeMutableBufferPointer { p in
                for i in 0..<(l * h) where (m[i] != 0) == dedans { p[i] = cap }
                func plus(_ v: UInt8) -> UInt8 { v == 255 ? 255 : v + 1 }
                for y in 0..<h {
                    for x in 0..<l {
                        let i = y * l + x
                        var v = p[i]
                        guard v != 0 else { continue }
                        if x > 0 { v = min(v, plus(p[i - 1])) }
                        if y > 0 {
                            v = min(v, plus(p[i - l]))
                            if x > 0 { v = min(v, plus(p[i - l - 1])) }
                            if x < l - 1 { v = min(v, plus(p[i - l + 1])) }
                        }
                        p[i] = v
                    }
                }
                for y in stride(from: h - 1, through: 0, by: -1) {
                    for x in stride(from: l - 1, through: 0, by: -1) {
                        let i = y * l + x
                        var v = p[i]
                        guard v != 0 else { continue }
                        if x < l - 1 { v = min(v, plus(p[i + 1])) }
                        if y < h - 1 {
                            v = min(v, plus(p[i + l]))
                            if x < l - 1 { v = min(v, plus(p[i + l + 1])) }
                            if x > 0 { v = min(v, plus(p[i + l - 1])) }
                        }
                        p[i] = v
                    }
                }
            }
        }
        return d
    }

    /// Le lissage de l'opacité, en place : deux flous en boîte de rayon 1 (le noyau 1, 2, 3, 2, 1 dans
    /// chaque sens, en entiers, arrondi) ; un pixel loin de toute valeur non nulle reste 0, loin de
    /// toute valeur sous 255 reste 255. Un anneau de cinq lignes filtrées en largeur, sans copie de
    /// l'image.
    static func lisserOpacite(_ v: inout [UInt8], largeur l: Int, hauteur h: Int) {
        guard l > 0, h > 0, v.count == l * h else { return }
        var anneau = [UInt16](repeating: 0, count: 5 * l)
        v.withUnsafeMutableBufferPointer { p in
            anneau.withUnsafeMutableBufferPointer { a in
                // La ligne y (bornée) filtrée en largeur, rangée à sa place dans l'anneau.
                func filtrer(_ y: Int) {
                    let source = min(max(y, 0), h - 1) * l, cible = ((y % 5) + 5) % 5 * l
                    for x in 0..<l {
                        func q(_ k: Int) -> UInt16 { UInt16(p[source + min(max(x + k, 0), l - 1)]) }
                        a[cible + x] = q(-2) + 2 * q(-1) + 3 * q(0) + 2 * q(1) + q(2)
                    }
                }
                for y in -2...1 { filtrer(y) }
                for y in 0..<h {
                    filtrer(y + 2)   // la ligne y + 2 n'est pas encore réécrite
                    let base = y * l
                    // Les lignes y − 2 à y + 2 dans l'anneau (rangées par y modulo 5).
                    let r = (0..<5).map { (((y + $0 - 2) % 5) + 5) % 5 * l }
                    let (r0, r1, r2, r3, r4) = (r[0], r[1], r[2], r[3], r[4])
                    for x in 0..<l {
                        let s = UInt32(a[r0 + x]) + 2 * UInt32(a[r1 + x]) + 3 * UInt32(a[r2 + x]) + 2 * UInt32(a[r3 + x]) + UInt32(a[r4 + x])
                        p[base + x] = UInt8(min(255, (s + 40) / 81))
                    }
                }
            }
        }
    }

    /// L'opacité du masque de Lightroom au bord, lue dans les rendus témoins : là où le masque IA est
    /// doux (cheveux), l'effet d'un témoin n'est qu'une part de l'effet plein. Pour chaque témoin,
    /// l'écart d = log2(linéaire du témoin + ε) − log2(linéaire de l'état actuel + ε), canal par canal ;
    /// l'effet plein f, la médiane de d dans l'intérieur sûr du masque binaire, par canal et par valeur
    /// de l'état actuel (une table de 256, qui tient compte de la courbe de tonalité, des noirs relevés
    /// et des blancs écrêtés) ; puis α = (Σ d·f + λ·binaire) / (Σ f² + λ), les moindres carrés sur les
    /// témoins et les trois canaux (un canal noir ou écrêté, f ≈ 0, ne compte presque pas).
    /// Le calcul couvre tout le masque binaire, élargi de `opaciteMarge` : l'opacité se lit partout,
    /// jamais forcée pleine à une profondeur fixe (un radial, un dégradé ou un bord affiné peuvent
    /// rester partiels sur des centaines de pixels ; une profondeur pleine y faisait une marche). Un
    /// octet par pixel pour la classe, et huit par pixel calculé (les deux sommes des moindres
    /// carrés, rangées dans l'ordre des pixels, sans liste d'indices). Au-delà, jusqu'à
    /// `margeOpacite`, seul le repli peut prolonger l'ancien bord. Les témoins s'ajoutent l'un
    /// après l'autre (`ajouter`) : un seul rendu de 26 Mpx de plus en mémoire à la fois.
    struct OpaciteDuMasque {
        let largeur: Int, hauteur: Int
        /// 0 : hors du masque élargi ; 1 : calculé ; 2 : calculé, dans l'intérieur sûr (où se relève
        /// l'effet plein) ; 3 : hors du calcul, où seul le repli prolonge le fondu binaire (de
        /// `opaciteMarge` à `margeOpacite` hors du masque binaire).
        private(set) var classe: [UInt8]
        /// Les sommes des moindres carrés de chaque pixel calculé (classe 1 ou 2), dans l'ordre des
        /// pixels de la photo.
        private(set) var numerateur: [Float]
        private(set) var denominateur: [Float]

        /// log2(linéaire + ε) d'une valeur sRGB 8 bits.
        static let logLineaire: [Float] = (0..<256).map { v in
            let c = Double(v) / 255
            let lineaire = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            return Float(log2(lineaire + Generatif.opaciteEpsilon))
        }
        /// L'histogramme des écarts : 256 cases de −5 à +3 (en IL), centrées sur les multiples du pas
        /// (un écart nul tombe sur 0 exactement), un pixel sur `pasEchantillon` de
        /// l'intérieur sûr, au moins `echantillonsMin` par valeur pour une médiane.
        static let cases = 256, ecartMin: Float = -5, pasCase: Float = 8 / 256
        static let pasEchantillon = 7, echantillonsMin: Int32 = 40

        /// L'érosion de l'intérieur sûr en pixels, d'après le petit côté de la photo.
        static func erosion(largeur l: Int, hauteur h: Int) -> Int {
            min(250, max(2, Int((Double(min(l, h)) * Generatif.opaciteErosion).rounded())))
        }

        init(binaire: [UInt8], largeur l: Int, hauteur h: Int) {
            largeur = l; hauteur = h
            let n = l * h
            guard l > 0, h > 0, binaire.count == n else {
                classe = []; numerateur = []; denominateur = []
                return
            }
            let erosion = Self.erosion(largeur: l, hauteur: h), margeOpacite = Generatif.margeOpacite(largeur: l, hauteur: h)
            var classe = Generatif.distanceEchiquier(binaire, largeur: l, hauteur: h, dedans: true, plafond: erosion + 1)
            let dehors = Generatif.distanceEchiquier(binaire, largeur: l, hauteur: h, dedans: false, plafond: margeOpacite + 1)
            var nombre = 0
            let marge = UInt8(Generatif.opaciteMarge), margeRepli = UInt8(margeOpacite), e = UInt8(erosion)
            classe.withUnsafeMutableBufferPointer { cl in
                dehors.withUnsafeBufferPointer { de in
                    for i in 0..<n {
                        let d = cl[i]
                        let c: UInt8
                        if d == 0 { c = de[i] <= marge ? 1 : de[i] <= margeRepli ? 3 : 0 } else if d > e { c = 2 } else { c = 1 }
                        cl[i] = c
                        if c == 1 || c == 2 { nombre += 1 }
                    }
                }
            }
            self.classe = classe
            numerateur = [Float](repeating: 0, count: nombre)
            denominateur = [Float](repeating: 0, count: nombre)
        }

        /// L'effet plein d'un témoin (`ecart` → f), par canal et par valeur de l'état actuel (3 × 256),
        /// tiré de l'intérieur sûr : la médiane ; une valeur sans assez d'échantillons prend
        /// l'interpolation de ses voisines connues (aux bouts, la plus proche) ; puis une moyenne
        /// mobile de sept valeurs. Toute la table vaut 0 si l'intérieur sûr est vide.
        func table(actuel a: UnsafeBufferPointer<UInt8>, temoin t: UnsafeBufferPointer<UInt8>) -> [Float] {
            let cases = Self.cases
            var histo = [Int32](repeating: 0, count: 3 * 256 * cases)
            Self.logLineaire.withUnsafeBufferPointer { logv in
            classe.withUnsafeBufferPointer { c in
                histo.withUnsafeMutableBufferPointer { hi in
                    var i = 0
                    while i < c.count {
                        if c[i] == 2 {
                            for k in 0..<3 {
                                let va = Int(a[i * 4 + k])
                                let d = logv[Int(t[i * 4 + k])] - logv[va]
                                let b = min(cases - 1, max(0, Int(((d - Self.ecartMin) / Self.pasCase).rounded())))
                                hi[(k * 256 + va) * cases + b] += 1
                            }
                        }
                        i += Self.pasEchantillon
                    }
                }
            }
            }
            var table = [Float](repeating: 0, count: 3 * 256)
            for k in 0..<3 {
                var connues: [Int] = []
                for v in 0..<256 {
                    let base = (k * 256 + v) * cases
                    var total: Int32 = 0
                    for b in 0..<cases { total += histo[base + b] }
                    guard total >= Self.echantillonsMin else { continue }
                    var cumul: Int32 = 0
                    for b in 0..<cases {
                        cumul += histo[base + b]
                        if 2 * cumul >= total { table[k * 256 + v] = Self.ecartMin + Float(b) * Self.pasCase; break }
                    }
                    connues.append(v)
                }
                guard let premiere = connues.first, let derniere = connues.last else { continue }
                var rang = 0
                for v in 0..<256 {
                    while rang + 1 < connues.count, connues[rang + 1] <= v { rang += 1 }
                    if v < premiere { table[k * 256 + v] = table[k * 256 + premiere]; continue }
                    if v > derniere { table[k * 256 + v] = table[k * 256 + derniere]; continue }
                    let g = connues[rang]
                    guard g != v, rang + 1 < connues.count else { continue }
                    let d = connues[rang + 1], u = Float(v - g) / Float(d - g)
                    table[k * 256 + v] = table[k * 256 + g] * (1 - u) + table[k * 256 + d] * u
                }
                let brute = Array(table[(k * 256)..<(k * 256 + 256)])
                for v in 0..<256 {
                    var s: Float = 0, nombre = 0
                    for w in max(0, v - 3)...min(255, v + 3) { s += brute[w]; nombre += 1 }
                    table[k * 256 + v] = s / Float(nombre)
                }
            }
            return table
        }

        /// Ajoute un témoin (pixels RGBA 8 bits sRGB de l'état actuel et du témoin, de la taille du
        /// masque) aux moindres carrés des pixels calculés.
        mutating func ajouter(actuel: [UInt8], temoin: [UInt8]) {
            let n = largeur * hauteur
            guard n > 0, actuel.count >= n * 4, temoin.count >= n * 4, !numerateur.isEmpty else { return }
            actuel.withUnsafeBufferPointer { a in
                temoin.withUnsafeBufferPointer { t in
                    let table = table(actuel: a, temoin: t)
                    table.withUnsafeBufferPointer { f in
                    Self.logLineaire.withUnsafeBufferPointer { logv in
                    classe.withUnsafeBufferPointer { c in
                        numerateur.withUnsafeMutableBufferPointer { nu in
                            denominateur.withUnsafeMutableBufferPointer { de in
                                var j = 0
                                for p in 0..<n where c[p] == 1 || c[p] == 2 {
                                    let i = p * 4
                                    var sn: Float = 0, sd: Float = 0
                                    for k in 0..<3 {
                                        let va = Int(a[i + k])
                                        let d = logv[Int(t[i + k])] - logv[va], effet = f[k * 256 + va]
                                        sn += d * effet
                                        sd += effet * effet
                                    }
                                    nu[j] += sn
                                    de[j] += sd
                                    j += 1
                                }
                            }
                        }
                    }
                    }
                    }
                }
            }
        }

        /// L'opacité finale, de 0 à 255 par pixel de la photo : α par la rampe renforcée
        /// (`opaciteBas`, `opaciteHaut`, en smoothstep), lissé (`lisserOpacite`), et glissé vers le
        /// masque binaire fondu là où les témoins ne disent presque rien (`opaciteAppui`), sur toute
        /// la largeur de ce fondu (la part de repli des pixels calculés, étendue en carré jusqu'à
        /// `margeOpacite`) ; pleine seulement là où α atteint l'opacité haute ; 0 exactement hors du
        /// masque élargi.
        func opacite(binaire: [UInt8]) -> [UInt8] {
            let n = largeur * hauteur
            guard n > 0, binaire.count == n, classe.count == n else { return [] }
            var v = [UInt8](repeating: 0, count: n)
            let lambda = Generatif.opaciteAPriori, bas = Float(Generatif.opaciteBas)
            let etendue = max(Float(0.01), Float(Generatif.opaciteHaut) - bas)
            var sansAppui = false
            classe.withUnsafeBufferPointer { c in
                binaire.withUnsafeBufferPointer { b in
                    numerateur.withUnsafeBufferPointer { nu in
                        denominateur.withUnsafeBufferPointer { de in
                            v.withUnsafeMutableBufferPointer { o in
                                var j = 0
                                for i in 0..<n where c[i] == 1 || c[i] == 2 {
                                    let alpha = (nu[j] + lambda * Float(b[i])) / (de[j] + lambda)
                                    let t = min(1, max(0, (alpha - bas) / etendue))
                                    o[i] = UInt8((t * t * (3 - 2 * t) * 255).rounded())
                                    if de[j] < Generatif.opaciteAppui { sansAppui = true }
                                    j += 1
                                }
                            }
                        }
                    }
                }
            }
            Generatif.lisserOpacite(&v, largeur: largeur, hauteur: hauteur)
            if sansAppui {
                let appui = Generatif.opaciteAppui
                let repli = Generatif.fonduBinaire(binaire, largeurPhoto: largeur, hauteurPhoto: hauteur,
                                                   cadre: Pixels(x: 0, y: 0, largeur: largeur, hauteur: hauteur))
                // La part de repli (1 − w) de chaque pixel calculé, de 0 à 255.
                var manque = [UInt8](repeating: 0, count: n)
                var j = 0
                for i in 0..<n where classe[i] == 1 || classe[i] == 2 {
                    defer { j += 1 }
                    guard denominateur[j] < appui else { continue }
                    let w = max(0, denominateur[j]) / appui
                    v[i] = UInt8(min(255, max(0, (w * Float(v[i]) + (1 - w) * repli[i] * 255).rounded())))
                    manque[i] = UInt8(((1 - w) * 255).rounded())
                }
                // Au-delà du calcul, jusqu'à `margeOpacite` : le fondu binaire, dans la part de repli la
                // plus forte des pixels calculés voisins.
                let rayon = Generatif.margeOpacite(largeur: largeur, hauteur: hauteur) - Generatif.opaciteMarge
                if rayon > 0 {
                    Generatif.maximumCarre(&manque, largeur: largeur, hauteur: hauteur, rayon: rayon)
                    for i in 0..<n where classe[i] == 3 {
                        v[i] = UInt8(min(255, max(0, (Float(manque[i]) * repli[i]).rounded())))
                    }
                }
            }
            classe.withUnsafeBufferPointer { c in
                v.withUnsafeMutableBufferPointer { o in
                    for i in 0..<n where c[i] == 0 || (c[i] == 3 && !sansAppui) { o[i] = 0 }
                }
            }
            return v
        }
    }

    /// Le maximum de chaque carré de côté 2 × rayon + 1, en place (séparable : en largeur puis en
    /// hauteur ; bords répétés).
    static func maximumCarre(_ v: inout [UInt8], largeur l: Int, hauteur h: Int, rayon r: Int) {
        guard r > 0, l > 0, h > 0, v.count == l * h else { return }
        var ligne = [UInt8](repeating: 0, count: l)
        for y in 0..<h {
            let base = y * l
            for x in 0..<l { ligne[x] = v[base + x] }
            for x in 0..<l {
                var m: UInt8 = 0
                for k in max(0, x - r)...min(l - 1, x + r) where ligne[k] > m { m = ligne[k] }
                v[base + x] = m
            }
        }
        // En hauteur, ligne à ligne (une colonne à la fois serait lente sur 26 Mpx), depuis une copie.
        let copie = v
        copie.withUnsafeBufferPointer { c in
            v.withUnsafeMutableBufferPointer { o in
                for y in 0..<h {
                    let base = y * l
                    for k in max(0, y - r)...min(h - 1, y + r) where k != y {
                        let autre = k * l
                        for x in 0..<l where c[autre + x] > o[base + x] { o[base + x] = c[autre + x] }
                    }
                }
            }
        }
    }

    /// Flou en boîte séparable, en place, répété `passages` fois : les sommes restent entières (exactes
    /// en Float jusqu'à 2^24), divisées une seule fois à la fin ; une valeur loin de tout 1 reste donc
    /// exactement 0. Bords répétés. Le passage vertical garde les lignes d'origine encore utiles dans
    /// un anneau de `rayon + 1` lignes, et lit la mémoire ligne à ligne (une colonne à la fois, sur
    /// 26 Mpx, prenait dix fois plus de temps).
    static func sommeBoiteEnPlace(_ valeurs: inout [Float], largeur l: Int, hauteur h: Int, rayon r: Int, passages: Int) {
        guard r > 0, l > 0, h > 0, passages > 0, valeurs.count == l * h else { return }
        var ligne = [Float](repeating: 0, count: l)
        var anneau = [Float](repeating: 0, count: (r + 1) * l)
        var somme = [Float](repeating: 0, count: l)
        valeurs.withUnsafeMutableBufferPointer { p in
            ligne.withUnsafeMutableBufferPointer { li in
                anneau.withUnsafeMutableBufferPointer { an in
                    somme.withUnsafeMutableBufferPointer { so in
                        for _ in 0..<passages {
                            // En largeur : une ligne de travail.
                            for y in 0..<h {
                                let base = y * l
                                for x in 0..<l { li[x] = p[base + x] }
                                var s: Float = 0
                                for k in -r...r { s += li[min(max(k, 0), l - 1)] }
                                for x in 0..<l {
                                    p[base + x] = s
                                    s += li[min(x + r + 1, l - 1)] - li[max(x - r, 0)]
                                }
                            }
                            // En hauteur : la somme des lignes y − r à y + r, mise à jour ligne à ligne.
                            for x in 0..<l { so[x] = 0 }
                            for k in -r...r {
                                let base = min(max(k, 0), h - 1) * l
                                for x in 0..<l { so[x] += p[base + x] }
                            }
                            for y in 0..<h {
                                let base = y * l, garde = (y % (r + 1)) * l
                                for x in 0..<l { an[garde + x] = p[base + x] }
                                for x in 0..<l { p[base + x] = so[x] }
                                guard y + 1 < h else { break }
                                let entre = min(y + r + 1, h - 1) * l
                                let sort = (max(y - r, 0) % (r + 1)) * l
                                for x in 0..<l { so[x] += p[entre + x] - an[sort + x] }
                            }
                        }
                        let fenetre = Float(2 * r + 1)
                        var diviseur: Float = 1
                        for _ in 0..<(2 * passages) { diviseur *= fenetre }
                        for i in 0..<p.count { p[i] = min(1, p[i] / diviseur) }
                    }
                }
            }
        }
    }

    // MARK: Images

    /// Les pixels RGBA 8 bits sRGB d'une image dessinée à la taille donnée.
    static func pixelsRGBA8(_ image: CGImage, largeur: Int, hauteur: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: largeur * hauteur * 4)
        let ok = pixels.withUnsafeMutableBytes { tampon -> Bool in
            guard let contexte = CGContext(data: tampon.baseAddress, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: largeur * 4,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            contexte.interpolationQuality = .high
            contexte.draw(image, in: CGRect(x: 0, y: 0, width: largeur, height: hauteur))
            return true
        }
        return ok ? pixels : nil
    }

    /// Une image RGB 8 bits sRGB (PNG de l'entrée), ou en niveaux de gris (masque).
    static func image8(_ pixels: [UInt8], largeur: Int, hauteur: Int, gris: Bool = false) -> CGImage? {
        let composantes = gris ? 1 : 4
        guard pixels.count >= largeur * hauteur * composantes, let fournisseur = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: largeur, height: hauteur, bitsPerComponent: 8, bitsPerPixel: 8 * composantes, bytesPerRow: largeur * composantes,
                       space: gris ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: gris ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: fournisseur, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Le masque de Fibo, blanc sur noir, en image RGB (comme une photo : mflux le lit ainsi sans doute).
    static func imageMasque(_ masque: [UInt8], largeur: Int, hauteur: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: largeur * hauteur * 4)
        for i in 0..<(largeur * hauteur) { rgba[i * 4] = masque[i]; rgba[i * 4 + 1] = masque[i]; rgba[i * 4 + 2] = masque[i] }
        return image8(rgba, largeur: largeur, hauteur: hauteur)
    }

    static func ecrirePNG(_ image: CGImage, vers url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw LightroomError.plugin("PNG impossible à écrire : \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw LightroomError.plugin("PNG impossible à écrire : \(url.path)") }
    }

    static func lireImage(_ url: URL) -> (image: CGImage, proprietes: [CFString: Any])? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let proprietes = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return (image, proprietes)
    }

    /// Le paquet XMP d'une image (tous ses champs, ceux qu'ImageIO ne fait correspondre ni à l'Exif,
    /// ni à l'IPTC, ni au TIFF compris : libellé, texte alternatif, mots-clés hiérarchiques de
    /// Lightroom…), pour le recopier tel quel dans le TIFF final.
    static func lireMetadonnees(_ url: URL) -> CGImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyMetadataAtIndex(source, 0, nil)
    }

    /// Une sortie de Fibo à remettre dans la photo : l'image (sortie de Fibo, ou de SeedVR2), la zone
    /// de mélange (de 0 à 1, à sa petite taille) et la place de son recadrage dans la photo.
    struct Piece {
        var generee: CGImage
        var zone: [Float]
        var largeurZone: Int
        var hauteurZone: Int
        var cadre: Pixels
    }

    /// La recomposition en pleine résolution : chaque sortie de Fibo mise à la taille de son recadrage,
    /// mêlée à la photo selon sa zone (lue en bilinéaire depuis la petite taille), l'une après l'autre ;
    /// hors des zones (0), les pixels de la photo restent tels quels, au bit près. Image RGB 16 bits
    /// dans l'espace de la photo (Adobe RGB).
    static func recomposer(origine: CGImage, pieces: [Piece]) -> CGImage? {
        let l = origine.width, h = origine.height
        guard l > 0, h > 0 else { return nil }
        let espace = origine.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        let info = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        func dessiner(_ image: CGImage, largeur: Int, hauteur: Int, qualite: CGInterpolationQuality) -> CGContext? {
            guard let contexte = CGContext(data: nil, width: largeur, height: hauteur, bitsPerComponent: 16, bytesPerRow: largeur * 8, space: espace, bitmapInfo: info) else { return nil }
            contexte.interpolationQuality = qualite
            contexte.draw(image, in: CGRect(x: 0, y: 0, width: largeur, height: hauteur))
            return contexte
        }
        guard let fond = dessiner(origine, largeur: l, hauteur: h, qualite: .none),
              let pf = fond.data?.bindMemory(to: UInt16.self, capacity: l * h * 4) else { return nil }
        var sortie = [UInt16](repeating: 0, count: l * h * 3)
        for i in 0..<(l * h) {
            sortie[i * 3] = pf[i * 4]; sortie[i * 3 + 1] = pf[i * 4 + 1]; sortie[i * 3 + 2] = pf[i * 4 + 2]
        }
        for piece in pieces {
            let c = piece.cadre, lz = piece.largeurZone, hz = piece.hauteurZone
            guard c.largeur > 0, c.hauteur > 0, c.x >= 0, c.y >= 0, c.x + c.largeur <= l, c.y + c.hauteur <= h,
                  lz > 0, hz > 0, piece.zone.count == lz * hz,
                  let dessus = dessiner(piece.generee, largeur: c.largeur, hauteur: c.hauteur, qualite: .high),
                  let pd = dessus.data?.bindMemory(to: UInt16.self, capacity: c.largeur * c.hauteur * 4) else { return nil }
            let ex = Double(lz) / Double(c.largeur), ey = Double(hz) / Double(c.hauteur)
            for y in 0..<c.hauteur {
                let fy = max(0, min(Double(hz - 1), (Double(y) + 0.5) * ey - 0.5))
                let y0 = Int(fy), y1 = min(y0 + 1, hz - 1)
                let ty = Float(fy - Double(y0))
                for x in 0..<c.largeur {
                    let fx = max(0, min(Double(lz - 1), (Double(x) + 0.5) * ex - 0.5))
                    let x0 = Int(fx), x1 = min(x0 + 1, lz - 1)
                    let tx = Float(fx - Double(x0))
                    let haut = piece.zone[y0 * lz + x0] * (1 - tx) + piece.zone[y0 * lz + x1] * tx
                    let bas = piece.zone[y1 * lz + x0] * (1 - tx) + piece.zone[y1 * lz + x1] * tx
                    let m = min(1, max(0, haut * (1 - ty) + bas * ty))
                    guard m > 0 else { continue }
                    let i = (y * c.largeur + x) * 4, o = ((y + c.y) * l + x + c.x) * 3
                    if m >= 1 {
                        sortie[o] = pd[i]; sortie[o + 1] = pd[i + 1]; sortie[o + 2] = pd[i + 2]
                    } else {
                        for k in 0..<3 {
                            sortie[o + k] = UInt16((Float(sortie[o + k]) * (1 - m) + Float(pd[i + k]) * m).rounded())
                        }
                    }
                }
            }
        }
        let donnees = sortie.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let fournisseur = CGDataProvider(data: donnees as CFData) else { return nil }
        return CGImage(width: l, height: h, bitsPerComponent: 16, bitsPerPixel: 48, bytesPerRow: l * 6, space: espace,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                       provider: fournisseur, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// La compression du TIFF final : Deflate (Adobe, 8), comme les exportations TIFF de Lightroom
    /// (ZIP). Le LZW sans prédicteur grossissait un TIFF 16 bits bruité d'environ 30 % (mesuré le
    /// 29 octobre 2026 par la relecture : 23,8 Mo contre 18,0 sans compression et 17,6 en Deflate).
    static let compressionTIFF = 8

    /// Écrit le TIFF final (16 bits, Deflate), avec les métadonnées du TIFF exporté : le paquet XMP
    /// entier (`metadonnees`, par CGImageDestinationAddImageAndMetadata : sans lui, ce qui n'existe
    /// qu'en XMP se perdait, libellé et texte alternatif compris) et les dictionnaires Exif, IPTC, GPS
    /// et TIFF ; les dimensions et la profondeur sont celles de l'image. Avec le paquet XMP,
    /// ImageIO ne lit la compression qu'au premier niveau des options (constaté le 29 octobre 2026 :
    /// dans le dictionnaire TIFF, elle était ignorée).
    static func ecrireTIFF(_ image: CGImage, proprietes: [CFString: Any], metadonnees: CGImageMetadata? = nil, vers url: URL) throws {
        var gardees = proprietes
        for cle in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth, kCGImagePropertyHasAlpha,
                    kCGImagePropertyColorModel, kCGImagePropertyProfileName, kCGImagePropertyIsFloat, kCGImagePropertyIsIndexed] {
            gardees.removeValue(forKey: cle)
        }
        var tiff = gardees[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        tiff[kCGImagePropertyTIFFCompression] = compressionTIFF
        gardees[kCGImagePropertyTIFFDictionary] = tiff
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw LightroomError.plugin("TIFF impossible à écrire : \(url.path)")
        }
        if let metadonnees {
            gardees[kCGImagePropertyTIFFCompression] = compressionTIFF
            CGImageDestinationAddImageAndMetadata(destination, image, metadonnees, gardees as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, gardees as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw LightroomError.plugin("TIFF impossible à écrire : \(url.path)") }
    }
}
