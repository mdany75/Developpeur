import Foundation

/// Profils, paramètres prédéfinis, copie de réglages entre photos, journal des retouches et carnet de
/// progrès (export_journal avec notebook, 1.3).
extension ToolHandler {
    /// Ce qu'on peut copier ou mettre dans un paramètre prédéfini, en plus des groupes de réglages.
    static let inclusions: [(name: String, module: String, label: String, copyDefault: Bool)] = [
        ("include_profile", "profil", "le profil (et sa Look)", true),
        ("include_tone_curve", "courbes", "les courbes par points", true),
        ("include_point_colors", "couleurs", "les couleurs ponctuelles", true),
        ("include_crop", "recadrage", "le recadrage et l'angle", false),
        ("include_masks", "masques", "les masques (les masques IA sont recalculés pour chaque photo)", false),
        ("include_spots", "taches", "les retouches de taches (utile pour les poussières du capteur, au même endroit sur toute une série)", false),
        ("include_upright_exact", "upright_exact", "les corrections Upright de la source telles quelles (ses matrices), au lieu du mode recalculé pour chaque photo : pour un bracketing ou une série prise du même point de vue", false),
    ]

    /// Ce qu'un paramètre prédéfini XMP peut contenir en plus des réglages.
    static let presetInclusions: Set<String> = ["include_profile", "include_tone_curve", "include_crop"]

    var managementDefinitions: [JSONValue] {
        let groups = DevelopCatalogue.groups
        let groupsProperty = listProp("string", "Groupes de réglages, par leur nom : \(groups.joined(separator: ", ")). Défaut : tous.")
        let inclusionProperties = Self.inclusions.map { item in
            (item.name, prop("boolean", "Inclure \(item.label) (défaut : \(item.copyDefault ? "oui" : "non")).") as JSONValue)
        }
        let presetInclusions = inclusionProperties.filter { Self.presetInclusions.contains($0.0) }
        return [
            tool("copy_settings",
                 "Copie les réglages d'une photo vers d'autres, comme Synchroniser dans Lightroom, en une étape « Claude · <step_name> » par photo : groupes de réglages au choix, profil, courbes, couleurs ponctuelles, et sur demande recadrage, masques et retouches de taches. La balance des blancs n'est pas copiée entre un RAW et un JPEG (échelles différentes). Respecte le mode « Proposer d'abord » (confirm).",
                 properties: [("source_id", prop("integer", "Photo dont on copie les réglages.")), ("groups", groupsProperty)]
                    + inclusionProperties + writeProperties + targetProperties,
                 required: ["source_id"]),
            tool("list_profiles",
                 "Liste les profils de rendu utilisables pour une photo : profils d'appareil (simulations de film Fujifilm…) et profils à base de Look installés (Adobe Raw, profils de l'appareil comme CLASSIC Neg, profils créatifs Artistic, B&W, Modern, Vintage, profils installés par l'utilisateur), en indiquant ceux dont l'intensité se règle. Avec lens : les profils d'objectif installés qui y répondent (pour apply_settings, lens_profile).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("lens", prop("string", "Profils d'objectif : texte cherché dans la marque, l'objectif et le nom (« Fujifilm 55mm », « Helios 44 »).")),
                 ], required: []),
            tool("list_presets",
                 "Liste les paramètres prédéfinis de développement de Lightroom (ceux d'Adobe et ceux de l'utilisateur), par dossier, pour les appliquer avec apply_settings (preset).",
                 properties: [
                    ("query", prop("string", "Texte à chercher dans le nom du dossier ou du paramètre prédéfini.")),
                    ("limit", prop("integer", "Nombre maximal de résultats (défaut 100).")),
                 ],
                 required: []),
            tool("save_preset",
                 "Crée un paramètre prédéfini de développement à partir des réglages actuels d'une photo (par exemple une retouche réussie, pour la réutiliser) : un fichier XMP dans le groupe « Claude » des paramètres prédéfinis de Camera Raw, que Lightroom montre à son prochain lancement. Il contient les réglages des groupes choisis et, au choix, le profil, les courbes et le recadrage ; les masques, les taches et les couleurs ponctuelles n'y vont pas (copy_settings les copie).",
                 properties: [("name", prop("string", "Nom du paramètre prédéfini.")), ("photo_id", photoIDProperty), ("groups", groupsProperty)]
                    + presetInclusions,
                 required: ["name"]),
            tool("export_journal", Self.descriptionJournal,
                 properties: targetProperties + [
                    ("save_to", prop("string", "Chemin du fichier Markdown à écrire (par exemple ~/Desktop/Journal.md). Sans : le texte seulement.")),
                    ("notebook", prop("boolean", Self.descriptionCarnet)),
                 ],
                 required: []),
        ]
    }

    // MARK: Profils

    func listProfiles(_ args: Arguments) throws -> JSONValue {
        if let query = args.string("lens")?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            let found = lensProfiles.search(query)
            return [
                "profils_objectif": .array(found.map { profile in
                    ["nom": .string(profile.name), "objectif": .string(profile.lens), "marque": .string(profile.make),
                     "pour": .string(profile.raw ? "RAW" : "JPEG et autres"), "fichier": .string(profile.fileName)]
                }),
                "total": .number(Double(found.count)),
                "utilisation": "apply_settings avec lens_profile = le nom (le fichier RAW ou JPEG est choisi selon la photo) ; lens_profile = \"auto\" revient au profil par défaut.",
            ]
        }
        var make: String?, model: String?
        var params: [String: JSONValue] = ["cles": []]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        if let photo = try? lightroom.send("reglages", params, timeout: 30) {
            make = photo["appareil"]?["marque"]?.string
            model = photo["appareil"]?["modele"]?.string
        }
        let dcp = DevelopCatalogue.profiles.filter { profile in
            guard let wanted = profile.make else { return true }
            guard let make else { return true }
            return make.uppercased().contains(wanted)
        }
        var folders: [String: [String]] = [:]
        for profile in lookProfiles.profiles where make == nil || profile.matches(make: make, model: model) {
            let label = profile.supportsAmount ? "\(profile.name) (intensité réglable)" : profile.name
            if !(folders[profile.folder]?.contains(label) ?? false) { folders[profile.folder, default: []].append(label) }
        }
        var result: [String: JSONValue] = [
            "profils_appareil": .array(dcp.map { .string("\($0.name) : \($0.description)") }),
            "profils_look": .object(folders.mapValues { .array($0.map(JSONValue.string)) }),
            "utilisation": "apply_settings avec profile = le nom (sans la mention d'intensité) et, s'il y a lieu, profile_amount. Les profils d'appareil et ceux des dossiers Adobe Raw, Camera et Adaptive ne s'appliquent qu'aux RAW. Ceux du dossier Adaptive, en premier et sans auto_tone, sont calculés par Lightroom au view_photo suivant. Un boîtier Fujifilm plus ancien n'a pas toutes les simulations (un X-T20 n'a ni ETERNA ni REALA ACE ni CLASSIC Neg) : le profil est refusé, et remarques le dit (le profil d'avant reste). Sous ACROS ou MONOCHROME, le mélangeur noir et blanc est sans effet : choisir le filtre du profil.",
        ]
        if let model { result["appareil"] = .string([make, model].compactMap { $0 }.joined(separator: " ")) }
        return .object(result)
    }

    // MARK: Paramètres prédéfinis

    func listPresets(_ args: Arguments) throws -> JSONValue {
        var params: [String: JSONValue] = ["limite": .number(Double(min(max(args.int("limit") ?? 100, 1), 1000)))]
        if let query = args.string("query"), !query.isEmpty { params["filtre"] = .string(query) }
        return try lightroom.send("presets", params, timeout: 60)
    }

    func savePreset(_ args: Arguments) throws -> JSONValue {
        guard let name = args.string("name")?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            throw LightroomError.invalid("« name » : le nom du paramètre prédéfini.")
        }
        var inclusions = inclusionParameters(args).object ?? [:]
        for item in Self.inclusions where !Self.presetInclusions.contains(item.name) { inclusions[item.module] = false }
        var params: [String: JSONValue] = [
            "nom": .string(String(name.prefix(80))),
            "cles": .array(try groupKeys(args).map(JSONValue.string)),
            "inclure": .object(inclusions),
        ]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        let result = try lightroom.send("creerPreset", params, timeout: 60)
        guard let settings = result["reglages"]?.object, !settings.isEmpty else {
            throw LightroomError.plugin("Lightroom n'a pas renvoyé de réglages pour ce paramètre prédéfini.")
        }
        let written: (url: URL, skipped: [String])
        do {
            written = try PresetXMP.write(name: String(name.prefix(80)), settings: settings, folder: presetFolder)
        } catch {
            throw LightroomError.invalid("Impossible d'écrire le paramètre prédéfini : \(error.localizedDescription)")
        }
        var response: [String: JSONValue] = [
            "nom": .string(String(name.prefix(80))),
            "fichier": .string(written.url.path),
            "reglages": .number(Double(settings.count - written.skipped.count)),
            "source": result["source"] ?? .null,
            "a_savoir": "Lightroom le montre dans le groupe « Claude » du panneau Paramètres prédéfinis à son prochain lancement.",
        ]
        if !written.skipped.isEmpty { response["laisses_de_cote"] = .array(written.skipped.map(JSONValue.string)) }
        return .object(response)
    }

    // MARK: Copie

    func copySettings(_ args: Arguments) throws -> JSONValue {
        guard let source = args.int("source_id") else { throw LightroomError.invalid("« source_id » : la photo dont on copie les réglages.") }
        let keys = try groupKeys(args)
        var params = try targets(args)
        guard !params.isEmpty else { throw LightroomError.invalid("Photos visées : photo_ids ou selection = true.") }
        params.merge(writeParameters(args, defaultStep: "copie des réglages")) { _, new in new }
        params["source"] = .number(Double(source))
        params["cles"] = .array(keys.map(JSONValue.string))
        params["inclure"] = inclusionParameters(args)
        params["libelles"] = libellesCopie(keys)
        return Self.withLabels(try lightroom.send("copier", params, timeout: 240))
    }

    /// Libellés des changements d'une copie (copy_settings).
    func libellesCopie(_ keys: [String]) -> JSONValue {
        DevelopCatalogue.labels(for: keys + [DevelopCatalogue.profileKey, "PointColors", "MaskGroupBasedCorrections", "RetouchAreas", "RedEyeInfo",
                                             "UprightTransform"]
            + DevelopCatalogue.cropKeys + [DevelopCatalogue.constrainCropKey] + DevelopCatalogue.curveKeys.map(\.key))
    }

    /// Clés des groupes demandés (tous par défaut).
    func groupKeys(_ args: Arguments) throws -> [String] {
        guard let list = args.array("groups") else { return DevelopCatalogue.keys }
        var keys: [String] = []
        for item in list {
            let wanted = item.string?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard let group = DevelopCatalogue.groups.first(where: { $0.lowercased() == wanted }) else {
                throw LightroomError.invalid("Groupe inconnu : \(JSONCoding.line(item)). Groupes : \(DevelopCatalogue.groups.joined(separator: ", ")).")
            }
            keys += DevelopCatalogue.all.filter { $0.group == group }.map(\.key)
        }
        return keys
    }

    func inclusionParameters(_ args: Arguments) -> JSONValue {
        var result: [String: JSONValue] = [:]
        for item in Self.inclusions { result[item.module] = .bool(args.bool(item.name) ?? item.copyDefault) }
        return .object(result)
    }

    // MARK: Journal

    /// Description d'export_journal et de sa propriété notebook : 450 caractères au plus ensemble
    /// (CarnetTests).
    static let descriptionJournal = "Journal des retouches de Claude, photo par photo : date, étape, raison (reason) et réglages changés, annulations comprises ; ou le carnet de progrès (notebook). Renvoie le texte en Markdown et peut l'enregistrer dans un fichier."
    static let descriptionCarnet = "true = le carnet de progrès de tout le catalogue : par mois de prise de vue, les défauts de la prise de vue qui reviennent (mesurés avant toute retouche de Claude), ce qui progresse, quoi travailler à la prochaine sortie."

    func exportJournal(_ args: Arguments) throws -> JSONValue {
        var response: [String: JSONValue]
        let markdown: String
        if args.bool("notebook") == true {
            // Le carnet de progrès (1.3) : le résumé que le module calcule (Carnet.resumer), ses
            // phrases telles quelles ; ni ses entrées (jusqu'à 3 000 photos) ne vont à Claude, ni les
            // leçons (retirées en 1.3.6 : celles déjà rangées restent dans carnet.json, jamais
            // montrées) : le carnet ne montre que les constats (Carnet.sansLecons).
            let lu: JSONValue
            do {
                lu = try lightroom.send("carnet", ["action": "lire", "resume": true], timeout: Carnet.delaiLecture)
            } catch {
                if error.localizedDescription.contains("Commande inconnue") {
                    let version = lightroom.moduleVersion.map { " (version \($0))" } ?? ""
                    throw LightroomError.plugin("Le module de Lightroom\(version) ne connaît pas encore le carnet de progrès : installer Développeur 1.3, puis quitter et relancer Lightroom.")
                }
                throw error
            }
            guard let brut = lu["resume"], brut.object != nil else {
                throw LightroomError.plugin("Le module n'a pas rendu le résumé du carnet de progrès.")
            }
            let resume = Carnet.sansLecons(brut)
            markdown = Carnet.markdown(resume)
            response = ["markdown": .string(markdown), "carnet": resume]
            if let catalogue = lu["catalogue"]?.string { response["catalogue"] = .string(catalogue) }
            if args.has("photo_ids") || args.bool("selection") == true {
                response["remarque"] = "Le carnet compte tout le catalogue ouvert : photo_ids et selection n'y servent pas."
            }
        } else {
            let result = try lightroom.send("journal", try targets(args), timeout: 60)
            markdown = Self.journalMarkdown(result["photos"]?.array ?? [], date: Date())
            response = ["markdown": .string(markdown)]
        }
        if let path = args.string("save_to")?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            // Jamais d'écrasement, comme une livraison : un fichier déjà là fait renommer le nouveau.
            var numero = 2
            let base = url.deletingPathExtension().lastPathComponent, extensionFichier = url.pathExtension
            while FileManager.default.fileExists(atPath: url.path) {
                url = url.deletingLastPathComponent().appendingPathComponent("\(base) \(numero)").appendingPathExtension(extensionFichier)
                numero += 1
            }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isFolder), isFolder.boolValue else {
                throw LightroomError.invalid("Dossier introuvable : \(url.deletingLastPathComponent().path).")
            }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw LightroomError.invalid("Impossible d'écrire \(url.path) : \(error.localizedDescription)")
            }
            response["fichier"] = .string(url.path)
        }
        return .object(response)
    }

    static func journalMarkdown(_ photos: [JSONValue], date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.dateStyle = .long
        var lines = ["# Journal des retouches de Claude", "", "Exporté le \(formatter.string(from: date)).", ""]
        if photos.isEmpty { lines.append("Aucune photo visée.") }
        for photo in photos {
            let file = photo["photo"]?["fichier"]?.string ?? "photo"
            let id = photo["photo"]?["id"]?.int.map { " (id \($0))" } ?? ""
            lines += ["## \(file)\(id)", ""]
            let entries = photo["entrees"]?.array ?? []
            if entries.isEmpty { lines += ["Aucune retouche de Claude enregistrée.", ""] }
            for entry in entries {
                lines.append("### \(entry["date"]?.string ?? "") — \(entry["etape"]?.string ?? "retouche")")
                if let reason = entry["raison"]?.string, !reason.isEmpty { lines.append("Pourquoi : \(reason)") }
                lines.append("")
                for change in entry["changements"]?.array ?? [] {
                    let key = change["cle"]?.string ?? ""
                    let label = DevelopCatalogue.label(for: key) ?? key
                    lines.append("- \(label) : \(text(change["avant"])) → \(text(change["apres"]))")
                }
                if let note = entry["note"]?.string { lines.append("- \(note)") }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func text(_ value: JSONValue?) -> String {
        guard let value, !value.isNull else { return "?" }
        if let number = value.double { return DevelopCatalogue.format(number).replacingOccurrences(of: ".", with: ",") }
        if let string = value.string { return string }
        return JSONCoding.line(value)
    }
}
