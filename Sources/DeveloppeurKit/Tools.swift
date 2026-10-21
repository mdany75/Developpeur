import Foundation
import ImageIO

/// Un bloc de contenu renvoyé à Claude : du texte, ou une image en base64.
public enum ToolContent: Equatable {
    case text(String)
    case image(base64: String, mimeType: String)

    public var json: JSONValue {
        switch self {
        case .text(let text):
            return ["type": "text", "text": .string(text)]
        case .image(let data, let mimeType):
            return ["type": "image", "data": .string(data), "mimeType": .string(mimeType)]
        }
    }
}

public struct ToolResult: Equatable {
    public var content: [ToolContent]
    public var isError: Bool
    /// Le même résultat en JSON (`structuredContent` du protocole MCP 2025-06-18), pour les outils
    /// qui déclarent un `outputSchema`.
    public var structured: JSONValue?

    public init(content: [ToolContent], isError: Bool = false, structured: JSONValue? = nil) {
        self.content = content
        self.isError = isError
        self.structured = structured
    }

    public init(text: String, isError: Bool = false) {
        self.init(content: [.text(text)], isError: isError)
    }

    /// Les blocs de texte, à la suite (pour les tests et `--call`).
    public var text: String {
        content.compactMap { if case .text(let text) = $0 { return text }; return nil }.joined(separator: "\n")
    }
}

/// Les outils exposés à Claude, et leur exécution par le module Lightroom. Les outils sont
/// répartis par thème : retouche globale (Tools+Retouche), retouches locales (Tools+Locales),
/// aperçu et mesures (Tools+Analyse), profils, paramètres prédéfinis, copie et journal
/// (Tools+Gestion), Bibliothèque (Tools+Bibliotheque), tri d'une séance et planche contact
/// (Tools+Tri), notes proposées selon le standard de notation (Tools+Notation), guide de style
/// (Tools+Style), livraison en fichiers (Tools+Livraison), variantes (Tools+Variantes) et
/// harmonisation d'une série (Tools+Serie).
public final class ToolHandler {
    let lightroom: LightroomServing
    let lookProfiles: LookProfileLibrary
    /// Effets locaux de Lightroom (add_mask, effect).
    let localEffects: LocalEffectLibrary
    /// Profils d'objectif installés (apply_settings, lens_profile ; list_profiles, lens).
    let lensProfiles: LensProfileLibrary
    /// Cadres des personnes d'un aperçu (Vision) ; les tests le remplacent.
    var detecterPersonnes: (CGImage) -> [CGRect] = VisionAnalysis.people
    /// Dossier où save_preset écrit les paramètres prédéfinis (celui de Camera Raw).
    let presetFolder: URL
    /// Guide de style personnel (remember_style, ressource, invite retouche_pro).
    public let guideStyle: GuideStyle
    /// Grilles de recalage déjà calculées, par photo et empreinte de sa géométrie (nil : image trop
    /// uniforme pour en calculer une). Voir Tools+Recalage.swift.
    var recalagesConnus: [String: Recalage.Grille?] = [:]
    /// Plafond de note de chaque photo au dernier cull_photos de cette session, que propose_ratings
    /// fait respecter (Tools+Notation.swift).
    var dernierTri: [Int: Notation.Plafond] = [:]
    /// Point de mise au point de view_photo : un seul lecteur, pour qu'une lecture bloquée
    /// (autorisation de macOS) n'en lance pas d'autres ; les tests le remplacent.
    var lecteurAF = LecteurPointsAF()
    /// Contexte de l'appel en cours (progression d'une série, annulation par le client) : les
    /// appels passent un à un (FileOutils), un seul contexte à la fois.
    var contexte = ContexteAppel()
    /// La version du module a déjà été comparée à celle du serveur (une remarque par session).
    var versionSignalee = false
    /// Version de ce serveur (celle du Info.plist ; « dev » en développement : pas de comparaison).
    var versionServeur = ServerInfo.version
    /// Modèles de noms de fichiers de Lightroom et ses préférences (dossiers d'exportation récents) :
    /// ceux de l'utilisateur, ou des fichiers d'essai dans les tests.
    var filenameTemplates = FilenameTemplates()
    /// Filigranes de l'utilisateur (Édition › Modifier les filigranes), lus dans leurs fichiers.
    var filigranes = FiligranesUtilisateur()
    /// Version de Lightroom Classic, lue une fois (commande « etat ») quand un réglage récent le demande.
    var versionLightroom: String?
    var preferencesLightroom = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.adobe.LightroomClassicCC7.plist")

    /// Claude réduit toute image au-delà d'environ 1,15 mégapixel : 1344 px de grand côté
    /// (1,2 Mpx pour un 3:2) donne tout le détail utile.
    public static let defaultPreviewSize = 1344
    /// Les réponses d'outil trop lourdes sont refusées par Claude Desktop (environ 1 Mo, base64
    /// compris) : au-delà de cette taille, l'aperçu est recompressé.
    public static let maxPreviewBytes = 600_000
    public static let previewSizes = 512...2048
    public static let defaultSelectionLimit = 50
    public static let maxSelectionLimit = 500
    /// Plage de la règle Angle de l'outil Recadrage de Lightroom.
    public static let cropAngleRange = -45.0...45.0
    public static let cropSizeRange = 0.2...1.0
    public static let cropAspectRange = 0.1...10.0
    /// Délai d'undo_last et de revert_to_original : défaire un débruitage, des détails bruts ou une
    /// super résolution relance un calcul de Lightroom.
    public static let undoTimeout: TimeInterval = 660

    public init(lightroom: LightroomServing, lookProfiles: LookProfileLibrary = LookProfileLibrary(),
                presetFolder: URL = PresetXMP.defaultFolder, localEffects: LocalEffectLibrary = LocalEffectLibrary(),
                guideStyle: GuideStyle = GuideStyle(), lensProfiles: LensProfileLibrary = LensProfileLibrary()) {
        self.lightroom = lightroom
        self.lookProfiles = lookProfiles
        self.presetFolder = presetFolder
        self.localEffects = localEffects
        self.guideStyle = guideStyle
        self.lensProfiles = lensProfiles
    }

    // MARK: Définitions

    public static let toolNames = [
        "get_status", "list_selection", "view_photo", "measure_angle", "analyze_photos", "get_settings",
        "apply_settings", "preview_settings", "enhance_photo", "add_mask", "edit_mask", "retouch_spots", "copy_settings",
        "list_profiles", "list_presets", "save_preset", "undo_last", "revert_to_original", "export_journal",
        "find_photos", "set_metadata", "list_keywords", "manage_collections", "create_virtual_copy", "show_photo",
        "cull_photos", "contact_sheet", "propose_ratings", "remove_distractions", "remember_style",
        "export_photos", "compare_variants", "choose_variant", "match_series",
    ]

    var photoIDProperty: JSONValue {
        prop("integer", "Identifiant de la photo (champ « id » de list_selection). Défaut : la photo active de Lightroom.")
    }

    var targetProperties: [(String, JSONValue)] {
        [
            ("photo_ids", listProp("integer", "Identifiants des photos visées (champ « id » de list_selection). Défaut : la photo active de Lightroom.")),
            ("selection", prop("boolean", "true = toutes les photos sélectionnées dans Lightroom (au lieu de la photo active).")),
        ]
    }

    /// Paramètres communs aux outils qui écrivent : nom de l'étape, raison (pour le journal),
    /// accord de l'utilisateur.
    var writeProperties: [(String, JSONValue)] {
        [
            ("step_name", prop("string", "Nom court de l'étape, par exemple « passe 1 : lumière et couleur ».")),
            ("reason", prop("string", "Pourquoi, en une phrase : gardé dans le journal des retouches (export_journal).")),
            ("confirm", prop("boolean", "true = l'utilisateur a approuvé ces valeurs (exigé en mode « Proposer d'abord »).")),
        ]
    }

    /// Tous les outils définis, par thème.
    var allDefinitions: [JSONValue] {
        let core: [JSONValue] = [
            tool("get_status",
                 "État de la liaison avec Lightroom Classic : versions, photo active, mode du module (appliquer directement ou proposer d'abord), pause, limites de sécurité. request_backup demande une sauvegarde du catalogue à la prochaine fermeture de Lightroom : la proposer avant une longue série (des centaines de photos, une harmonisation), et dire de fermer puis rouvrir Lightroom pour qu'elle garde l'état d'avant.",
                 properties: [("request_backup", prop("boolean", "true = demander à Lightroom une sauvegarde du catalogue à sa prochaine fermeture (sa fenêtre de sauvegarde ; l'utilisateur peut la passer)."))],
                 required: []),
            tool("list_selection",
                 "Liste les photos sélectionnées dans Lightroom (toutes celles du film fixe si rien n'est sélectionné), avec leurs données de prise de vue : appareil, objectif, ISO, vitesse, ouverture, focale, date, format, note, drapeau, libellé de couleur. La photo active est marquée « active ». Pour tout le catalogue : find_photos.",
                 properties: [("limit", prop("integer", "Nombre maximal de photos (défaut \(Self.defaultSelectionLimit), maximum \(Self.maxSelectionLimit))."))],
                 required: []),
            tool("undo_last",
                 "Annule la dernière retouche faite par Claude sur une photo (réglages, profil, recadrage, masques ou taches, ou classement : note, drapeau, libellé, textes, mots-clés, collection ; remet ce que cette étape avait changé).",
                 properties: targetProperties, required: []),
            tool("revert_to_original",
                 "Remet une photo dans l'état où elle était avant la première retouche de Claude (seulement ce que Claude a changé, classement dans la Bibliothèque compris), et oublie l'historique de Claude pour cette photo (le journal reste).",
                 properties: targetProperties, required: []),
        ]
        return core + analysisDefinitions + developDefinitions + localDefinitions + managementDefinitions + libraryDefinitions + cullDefinitions
            + notationDefinitions + styleDefinitions + deliveryDefinitions + variantDefinitions + seriesDefinitions
    }

    /// Titre lisible de chaque outil (annotations MCP, `title`), que le client montre à la place
    /// du nom technique.
    static let titles: [String: String] = [
        "get_status": "État de la liaison", "list_selection": "Photos sélectionnées", "view_photo": "Voir la photo",
        "measure_angle": "Mesurer un angle", "analyze_photos": "Mesurer une série", "get_settings": "Lire les réglages",
        "apply_settings": "Appliquer des réglages", "preview_settings": "Proposer des réglages", "enhance_photo": "Débruiter, détails, super résolution",
        "add_mask": "Ajouter des masques", "edit_mask": "Reprendre un masque", "retouch_spots": "Taches et yeux rouges", "copy_settings": "Copier une retouche",
        "list_profiles": "Profils", "list_presets": "Paramètres prédéfinis", "save_preset": "Créer un paramètre prédéfini",
        "undo_last": "Annuler la dernière retouche", "revert_to_original": "Revenir à l'état d'avant Claude", "export_journal": "Journal des retouches",
        "find_photos": "Chercher des photos", "set_metadata": "Classer des photos", "list_keywords": "Mots-clés",
        "manage_collections": "Collections", "create_virtual_copy": "Créer une copie virtuelle", "show_photo": "Montrer dans Lightroom",
        "cull_photos": "Trier une séance", "contact_sheet": "Planche contact", "propose_ratings": "Noter des photos",
        "remove_distractions": "Supprimer les reflets",
        "remember_style": "Guide de style", "export_photos": "Exporter des photos", "compare_variants": "Comparer des variantes",
        "choose_variant": "Choisir une variante", "match_series": "Harmoniser une série",
    ]
    /// Outils qui ne changent rien aux photos ni au catalogue (`readOnlyHint`) : le client peut les
    /// laisser passer sans demander. Une proposition (preview_settings) passe par l'Historique : pas ici ;
    /// propose_ratings non plus depuis la 1.1.1 : avec apply, il pose les notes dans le catalogue.
    /// get_status n'en est pas : il peut demander une sauvegarde du catalogue. view_photo en est,
    /// même avec compare : les deux étapes « Claude · comparaison » de l'Historique laissent la photo
    /// telle qu'elle était (choix de la 2.4, dit dans sa description).
    static let readOnlyTools: Set<String> = [
        "list_selection", "view_photo", "measure_angle", "analyze_photos", "get_settings", "list_profiles",
        "list_presets", "export_journal", "find_photos", "list_keywords", "cull_photos", "contact_sheet",
    ]
    /// Outils qui défont des retouches (`destructiveHint`) : le client peut demander confirmation.
    static let destructiveTools: Set<String> = ["revert_to_original", "undo_last"]

    /// Les annotations MCP d'un outil (protocole 2025-03-26 et suivants).
    static func annotations(_ name: String) -> JSONValue {
        let lecture = readOnlyTools.contains(name)
        var annotations: [String: JSONValue] = [
            "readOnlyHint": .bool(lecture),
            "openWorldHint": false,
        ]
        if let title = titles[name] { annotations["title"] = .string(title) }
        if !lecture { annotations["destructiveHint"] = .bool(destructiveTools.contains(name)) }
        return .object(annotations)
    }

    /// Les outils exposés, dans l'ordre de `toolNames` (un outil défini mais absent de la liste
    /// n'est pas montré à Claude : les tests vérifient qu'il n'y en a pas), avec leurs annotations.
    public var definitions: [JSONValue] {
        let all = allDefinitions
        return Self.toolNames.compactMap { name in
            guard var definition = all.first(where: { $0["name"]?.string == name })?.object else { return nil }
            definition["annotations"] = Self.annotations(name)
            if let schema = Self.outputSchemas[name] { definition["outputSchema"] = schema }
            if let title = Self.titles[name] { definition["title"] = .string(title) }
            return .object(definition)
        }
    }

    func prop(_ type: String, _ description: String) -> JSONValue {
        ["type": .string(type), "description": .string(description)]
    }

    func listProp(_ itemType: String, _ description: String) -> JSONValue {
        ["type": "array", "items": ["type": .string(itemType)], "description": .string(description)]
    }

    func enumProp(_ values: [String], _ description: String) -> JSONValue {
        ["type": "string", "enum": .array(values.map(JSONValue.string)), "description": .string(description)]
    }

    func objectProp(_ description: String, _ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": "object",
            "description": .string(description),
            "properties": .object(properties),
            "additionalProperties": false,
        ]
        if !required.isEmpty { object["required"] = .array(required.map(JSONValue.string)) }
        return .object(object)
    }

    func tool(_ name: String, _ description: String, properties: [(String, JSONValue)], required: [String]) -> JSONValue {
        var props: [String: JSONValue] = [:]
        for (key, value) in properties { props[key] = value }
        return [
            "name": .string(name),
            "description": .string(description),
            "inputSchema": [
                "type": "object",
                "properties": .object(props),
                "required": .array(required.map(JSONValue.string)),
                "additionalProperties": false,
            ],
        ]
    }

    // MARK: Exécution

    public func call(name: String, arguments: [String: JSONValue], contexte: ContexteAppel = ContexteAppel()) -> ToolResult {
        self.contexte = contexte
        var result = execute(name: name, arguments: arguments)
        fermerBarre()
        if let remarque = remarqueVersion() {
            result.content.append(.text(remarque))
        }
        return result
    }

    /// Une avancée d'une longue série : au client (progression MCP) et dans Lightroom, par sa barre de
    /// progression (commande progression, LrProgressScope), dont la croix arrête la série.
    func avancer(_ fait: Int, sur total: Int, _ message: String, titre: String?) {
        contexte.avancer(fait, sur: total, message)
        guard let titre, total > 1 else { return }
        let params: [String: JSONValue] = ["id": .string(contexte.identifiant), "titre": .string(titre), "fait": .number(Double(fait)),
                                           "total": .number(Double(total)), "message": .string(message)]
        guard let reponse = try? lightroom.send("progression", params, timeout: 10) else { return }
        contexte.barreOuverte = true
        if reponse["annulee"]?.bool == true { contexte.arreterDansLightroom() }
    }

    /// La barre de progression de Lightroom se ferme à la fin de l'appel.
    func fermerBarre() {
        guard contexte.barreOuverte else { return }
        contexte.barreOuverte = false
        _ = try? lightroom.send("progression", ["id": .string(contexte.identifiant), "fin": true], timeout: 10)
    }

    /// Le serveur et le module n'ont pas la même version : une installation partielle (un module
    /// encore chargé dans Lightroom, un serveur gardé par Claude Desktop). Dit une fois par session,
    /// après le premier échange ; get_status le redit.
    func remarqueVersion() -> String? {
        guard !versionSignalee, let module = lightroom.moduleVersion else { return nil }
        versionSignalee = true
        return Self.ecartVersions(serveur: versionServeur, module: module)
    }

    static func ecartVersions(serveur: String, module: String) -> String? {
        guard serveur != "dev", module != serveur else { return nil }
        return "Attention : le serveur MCP-Développeur est en version \(serveur) et le module de Lightroom en version \(module). Relancer Lightroom (module) ou Claude Desktop (serveur) après une installation ; sinon, des outils peuvent manquer ou échouer."
    }

    /// Paramètres déclarés de chaque outil (son `inputSchema`), calculés une fois : un paramètre
    /// inconnu est refusé plutôt qu'ignoré. Constaté : `photo_id` donné à un outil qui attend
    /// `photo_ids` (ou l'inverse) retouchait la photo active sans un mot, le client ne vérifiant
    /// pas toujours `additionalProperties: false`.
    lazy var parametresParOutil: [String: Set<String>] = {
        var table: [String: Set<String>] = [:]
        for definition in definitions {
            guard let name = definition["name"]?.string else { continue }
            table[name] = Set(definition["inputSchema"]?["properties"]?.object?.keys.map { $0 } ?? [])
        }
        return table
    }()

    /// L'erreur pour des paramètres que l'outil ne déclare pas, ou nil s'ils sont tous connus.
    func parametresInconnus(_ name: String, _ arguments: [String: JSONValue]) -> LightroomError? {
        guard let connus = parametresParOutil[name] else { return nil }
        let inconnus = arguments.keys.filter { !connus.contains($0) }.sorted()
        guard !inconnus.isEmpty else { return nil }
        let proches = [("photo_id", "photo_ids"), ("photo_ids", "photo_id"), ("photos", "photo_ids"), ("step", "step_name")]
        let detail = inconnus.map { cle in
            if let (_, bonne) = proches.first(where: { $0.0 == cle && connus.contains($0.1) }) { return "\(cle) (ici : « \(bonne) »)" }
            return cle
        }.joined(separator: ", ")
        return .invalid("Paramètres inconnus pour \(name) : \(detail). Rien n'a été fait. Paramètres acceptés : \(connus.sorted().joined(separator: ", ")).")
    }

    private func execute(name: String, arguments: [String: JSONValue]) -> ToolResult {
        let args = Arguments(raw: arguments)
        if let erreur = parametresInconnus(name, arguments) {
            return ToolResult(text: erreur.localizedDescription, isError: true)
        }
        do {
            switch name {
            case "get_status": return json(try status(args))
            case "list_selection": return json(try listSelection(args))
            case "view_photo": return try viewPhoto(args)
            case "measure_angle": return json(try measureAngle(args))
            case "analyze_photos": return json(try analyzePhotos(args))
            case "get_settings": return json(try getSettings(args))
            case "apply_settings": return json(try applySettings(args))
            case "preview_settings": return try previewSettings(args)
            case "enhance_photo": return json(try enhancePhoto(args))
            case "remove_distractions": return json(try removeDistractions(args))
            case "remember_style": return json(try rememberStyle(args))
            case "export_photos": return json(try exportPhotos(args))
            case "compare_variants": return try compareVariants(args)
            case "choose_variant": return json(try chooseVariant(args))
            case "match_series": return json(try matchSeries(args))
            case "add_mask": return try addMask(args)
            case "edit_mask": return json(try editMask(args))
            case "retouch_spots": return try retouchSpots(args)
            case "copy_settings": return json(try copySettings(args))
            case "list_profiles": return json(try listProfiles(args))
            case "list_presets": return json(try listPresets(args))
            case "save_preset": return json(try savePreset(args))
            // Défaire un débruitage relance un calcul de Lightroom (trois minutes au plus).
            case "undo_last": return json(try lightroom.send("annuler", try targets(args), timeout: Self.undoTimeout))
            case "revert_to_original": return json(try lightroom.send("revenir", try targets(args), timeout: Self.undoTimeout))
            case "export_journal": return json(try exportJournal(args))
            default:
                if let result = try callLibrary(name, args) { return result }
                if let result = try callCull(name, args) { return result }
                if let result = try callNotation(name, args) { return result }
                return ToolResult(text: "Outil inconnu : \(name)", isError: true)
            }
        } catch {
            return ToolResult(text: error.localizedDescription, isError: true)
        }
    }

    /// État de la liaison, avec la version du serveur et l'écart éventuel avec celle du module.
    private func status(_ args: Arguments) throws -> JSONValue {
        var etat = try lightroom.send("etat", args.bool("request_backup") == true ? ["sauvegarde": true] : [:], timeout: 10).object ?? [:]
        etat["version_serveur"] = .string(versionServeur)
        if let module = etat["version_module"]?.string, let ecart = Self.ecartVersions(serveur: versionServeur, module: module) {
            etat["avertissement_version"] = .string(ecart)
            versionSignalee = true
        }
        return .object(etat)
    }

    func json(_ value: JSONValue) -> ToolResult {
        ToolResult(content: [.text(JSONCoding.pretty(value))], structured: value.object != nil ? value : nil)
    }

    /// Schémas de sortie (`outputSchema`) des outils dont le résultat se lit en JSON structuré : le
    /// texte JSON reste envoyé pour les clients qui ne lisent pas la forme structurée. Schémas
    /// ouverts (les champs principaux décrits, d'autres permis) : le client vérifie le résultat
    /// contre eux.
    static let outputSchemas: [String: JSONValue] = {
        func schema(_ description: String, _ properties: [String: JSONValue]) -> JSONValue {
            ["type": "object", "description": .string(description), "properties": .object(properties), "additionalProperties": true]
        }
        let objet: JSONValue = ["type": "object"], liste: JSONValue = ["type": "array"]
        let texte: JSONValue = ["type": "string"], nombre: JSONValue = ["type": "number"]
        let ecriture = schema("Résultat d'une écriture : par photo, les changements et les remarques.",
                              ["mode": texte, "resultats": liste, "remarques_serveur": liste])
        return [
            "get_settings": schema("Réglages groupés comme dans le module Développement, profil, recadrage, masques, classement.",
                                   ["reglages": objet, "photo": objet, "profil": ["type": ["string", "object", "null"]], "recadrage": objet,
                                    "masques": liste, "classement": objet]),
            "list_selection": schema("Photos sélectionnées dans Lightroom.", ["total": nombre, "renvoyees": nombre, "photos": liste]),
            "analyze_photos": schema("Mesures de chaque photo, photos semblables, écarts avec une référence.",
                                     ["photos": liste, "photos_semblables": liste, "reference": objet]),
            "find_photos": schema("Photos du catalogue qui répondent aux critères, par page.", ["total": nombre, "photos": liste]),
            "cull_photos": schema("Bilan d'une séance : photos à défaut, rafales, ordre de lecture, plafonds de note mesurés, proposition de rejet.",
                                  ["photos_analysees": nombre, "floues_ou_ratees": liste, "rafales": liste, "classement": liste,
                                   "plafonds": objet, "propositions": liste, "vignettes": objet]),
            "propose_ratings": schema("Propositions rangées pour la carte Note, et posées avec apply ; ou le standard de notation.",
                                      ["propositions": liste, "refusees": liste, "posees": liste, "erreur_pose": ["type": ["string", "null"]],
                                       "standard": texte]),
            "apply_settings": ecriture,
            "add_mask": ecriture,
            "edit_mask": schema("Masques de la photo, ou résultat d'une écriture.", ["mode": texte, "resultats": liste, "masques": liste]),
            "set_metadata": ecriture,
            "export_photos": schema("Livraison : dossier, fichiers livrés, échecs ; ou, avec list, les livraisons types, modèles de noms et filigranes.",
                                    ["dossier": texte, "livrees": nombre, "fichiers": liste, "echecs": liste, "profils": liste, "modeles_noms": liste]),
            "match_series": schema("Harmonisation : écarts avec la référence, corrections proposées ou faites, écarts après.",
                                   ["reference": objet, "photos": liste]),
            "choose_variant": schema("Variante posée, ou variantes de la photo.", ["etape": texte, "instantane": texte, "changements": liste, "variantes": liste]),
        ]
    }()

    private func listSelection(_ args: Arguments) throws -> JSONValue {
        let limit = args.int("limit") ?? Self.defaultSelectionLimit
        guard limit > 0 else { throw LightroomError.invalid("« limit » doit être positif.") }
        return try lightroom.send("selection", ["limite": .number(Double(min(limit, Self.maxSelectionLimit)))], timeout: 30)
    }

    /// Les photos visées : `photo_ids`, ou `selection`, ou (rien) la photo active.
    func targets(_ args: Arguments) throws -> [String: JSONValue] {
        if let ids = try args.intList("photo_ids"), !ids.isEmpty {
            return ["photos": .array(ids.map { .number(Double($0)) })]
        }
        if args.bool("selection") == true {
            return ["selection": true]
        }
        return [:]
    }

    /// Nom de l'étape, raison et accord, tels que les attend le module.
    func writeParameters(_ args: Arguments, defaultStep: String) -> [String: JSONValue] {
        let stepName = (args.string("step_name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var params: [String: JSONValue] = [
            "etape": .string(stepName.isEmpty ? defaultStep : String(stepName.prefix(60))),
            "confirme": .bool(args.bool("confirm") ?? false),
        ]
        if let reason = args.string("reason")?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            params["raison"] = .string(String(reason.prefix(300)))
        }
        return params
    }

    /// Ajoute le libellé français à chaque changement renvoyé par le module.
    static func labelChanges(_ photo: JSONValue) -> JSONValue {
        guard var object = photo.object, let changes = object["changements"]?.array else { return photo }
        object["changements"] = .array(changes.map { change in
            guard var item = change.object, let key = item["cle"]?.string,
                  let label = DevelopCatalogue.label(for: key) else { return change }
            item["libelle"] = .string(label)
            return .object(item)
        })
        return .object(object)
    }

    /// Réponse d'une commande d'écriture : remarques du serveur et libellés des changements.
    static func withLabels(_ result: JSONValue, notes: [JSONValue] = []) -> JSONValue {
        var object = result.object ?? [:]
        if !notes.isEmpty { object["remarques_serveur"] = .array(notes) }
        if let photos = object["resultats"]?.array { object["resultats"] = .array(photos.map(labelChanges)) }
        return .object(object)
    }

    /// Réglages groupés comme dans le module Développement, dans l'ordre du catalogue.
    /// Valeur que Lightroom range pour un réglage automatique pas encore calculé (constaté dans
    /// Lightroom Classic 15.6 juste après la tonalité automatique : Saturation, Vibrance, Contraste…
    /// valent −999999 jusqu'à ce que Lightroom affiche la photo dans le module Développement ; un
    /// aperçu exporté ne les calcule pas : constaté en 2.5).
    static let pendingAutoValue = -999_999.0
    static let pendingAutoText = "auto (calculé quand Lightroom affiche la photo dans le module Développement)"

    /// `raw` : les valeurs par défaut propres aux RAW (`rawDefaults`) ne comptent pas comme des
    /// changements ; les curseurs HDR ne se montrent qu'en mode HDR (HDREditMode à 1 : sinon
    /// Lightroom range une limite de 2,3 sans effet).
    static func grouped(_ settings: [String: JSONValue], onlyChanged: Bool, raw: Bool = false) -> JSONValue {
        var groups: [String: JSONValue] = [:]
        let hdr = (settings["HDREditMode"]?.double ?? 0) != 0
        for group in DevelopCatalogue.groups {
            var items: [String: JSONValue] = [:]
            for setting in DevelopCatalogue.all where setting.group == group {
                guard var value = settings[setting.key], !value.isNull else { continue }
                if onlyChanged, value.double == setting.neutral { continue }
                if onlyChanged, raw, let defaut = DevelopCatalogue.rawDefaults[setting.key], value.double == defaut { continue }
                if onlyChanged, !hdr, group == "HDR" { continue }
                if value.double == Self.pendingAutoValue { value = .string(Self.pendingAutoText) }
                items[setting.key] = value
            }
            if !items.isEmpty { groups[group] = .object(items) }
        }
        return .object(groups)
    }

    static func format(_ value: Double) -> String {
        DevelopCatalogue.format(value).replacingOccurrences(of: "-", with: "−")
    }

    /// Lit le JPEG rendu par le module, puis l'efface avec son dossier temporaire.
    public static func readPreview(_ path: String?) throws -> Data {
        guard let path, !path.isEmpty else { throw LightroomError.plugin("Lightroom n'a pas fourni d'aperçu.") }
        let url = URL(fileURLWithPath: path)
        defer { removePreview(at: url) }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LightroomError.plugin("Aperçu illisible (\(path)) : \(error.localizedDescription)")
        }
    }

    /// Recompresse un JPEG trop lourd, de plus en plus fort, sans changer ses dimensions.
    /// Renvoie l'original s'il est assez léger ou illisible.
    static func compact(_ data: Data, maxBytes: Int) -> Data {
        guard data.count > maxBytes, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
        var smallest = data
        for quality in [0.75, 0.6, 0.45] {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { break }
            CGImageDestinationAddImageFromSource(destination, source, 0,
                                                 [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { break }
            if output.length < smallest.count { smallest = output as Data }
            if output.length <= maxBytes { break }
        }
        return smallest
    }

    static func imageContent(_ data: Data) -> ToolContent {
        .image(base64: compact(data, maxBytes: maxPreviewBytes).base64EncodedString(), mimeType: "image/jpeg")
    }

    private static func removePreview(at url: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: url)
        // Le module rend chaque aperçu dans son propre dossier temporaire.
        let folder = url.deletingLastPathComponent()
        if let rest = try? fileManager.contentsOfDirectory(atPath: folder.path), rest.isEmpty {
            try? fileManager.removeItem(at: folder)
        }
    }
}

/// Lecture des arguments d'un outil.
struct Arguments {
    let raw: [String: JSONValue]

    func string(_ key: String) -> String? { raw[key]?.string }
    func bool(_ key: String) -> Bool? { raw[key]?.bool }
    func object(_ key: String) -> [String: JSONValue]? { raw[key]?.object }
    func array(_ key: String) -> [JSONValue]? { raw[key]?.array }
    func has(_ key: String) -> Bool { raw[key].map { !$0.isNull } ?? false }

    func double(_ key: String) -> Double? {
        if let value = raw[key]?.double { return value }
        if let text = raw[key]?.string { return Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = raw[key]?.int { return value }
        if let text = raw[key]?.string { return Int(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func intList(_ key: String) throws -> [Int]? {
        guard let value = raw[key], !value.isNull else { return nil }
        if let single = value.int { return [single] }
        guard let items = value.array else { throw LightroomError.invalid("« \(key) » doit être une liste d'identifiants.") }
        return try items.map { item in
            guard let id = item.int ?? item.string.flatMap({ Int($0) }) else {
                throw LightroomError.invalid("« \(key) » contient un identifiant invalide : \(JSONCoding.line(item)).")
            }
            return id
        }
    }
}
