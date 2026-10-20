import CoreGraphics
import Foundation

/// Variantes d'interprétation : `compare_variants` prépare deux à quatre interprétations d'une photo,
/// rangées en instantanés de Lightroom (« Claude · chaude »…) et montrées sur une planche ;
/// `choose_variant` pose celle que l'utilisateur choisit, comme une étape que undo_last défait.
/// Sans copie virtuelle : chaque variante passe par une proposition (commande « essayer » avec
/// `instantane`), et la photo revient à son état entre deux.
extension ToolHandler {
    static let variantsRange = 2...4
    static let variantThumbnailSize = 768

    var variantDefinitions: [JSONValue] {
        var variantProps: [String: JSONValue] = ["name": prop("string", "Nom court de la variante : « naturelle », « chaude », « noir et blanc »…")]
        for (key, value) in developProperties where key != "relative" && key != "process_version" { variantProps[key] = value }
        let variant: JSONValue = [
            "type": "object", "properties": .object(variantProps), "required": ["name"], "additionalProperties": false,
            "description": "Une interprétation : son nom et ses réglages, comme apply_settings (absolus).",
        ]
        return [
            tool("compare_variants",
                 "Prépare deux à quatre interprétations d'une photo (naturelle, chaude, noir et blanc…) et les montre côte à côte sur une planche numérotée, avec l'état actuel en premier. Chaque variante est rangée en instantané de Lightroom « Claude · <nom> » (panneau Instantanés, où l'utilisateur peut aussi les comparer), puis la photo revient comme avant : rien n'est posé. L'Historique garde les étapes « Claude · essai ». Permis en mode « Proposer d'abord ». Ensuite, l'utilisateur choisit : choose_variant.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("variants", ["type": "array", "items": variant, "minItems": .number(Double(Self.variantsRange.lowerBound)),
                                  "maxItems": .number(Double(Self.variantsRange.upperBound)), "description": "Les variantes, chacune avec ses réglages."]),
                    ("include_current", prop("boolean", "true (défaut) = l'état actuel en première case de la planche.")),
                 ],
                 required: ["variants"]),
            tool("choose_variant",
                 "Pose la variante choisie par l'utilisateur (un instantané « Claude · <nom> » préparé par compare_variants), comme une étape « Claude · <step_name> » que undo_last défait ; delete_others efface ensuite les autres instantanés de variantes. action = list : les variantes de la photo ; delete : efface des instantanés de variantes (names, ou toutes). Mode « Proposer d'abord » : confirm = true après l'accord de l'utilisateur.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("action", enumProp(["choose", "list", "delete"], "choose (défaut), list ou delete.")),
                    ("name", prop("string", "Nom de la variante à poser (« chaude » ou « Claude · chaude »).")),
                    ("names", listProp("string", "delete : les variantes à effacer (défaut : toutes celles de Claude).")),
                    ("delete_others", prop("boolean", "true = effacer les autres instantanés de variantes de Claude après le choix.")),
                 ] + writeProperties,
                 required: []),
        ]
    }

    func compareVariants(_ args: Arguments) throws -> ToolResult {
        guard let variantes = args.array("variants"), Self.variantsRange.contains(variantes.count) else {
            throw LightroomError.invalid("« variants » : de \(Self.variantsRange.lowerBound) à \(Self.variantsRange.upperBound) variantes, chacune avec un nom et ses réglages.")
        }
        var noms = Set<String>()
        for variante in variantes {
            guard let nom = variante["name"]?.string?.trimmingCharacters(in: .whitespaces), !nom.isEmpty else {
                throw LightroomError.invalid("Chaque variante a un nom (« name »).")
            }
            guard noms.insert(nom.lowercased()).inserted else { throw LightroomError.invalid("Deux variantes s'appellent « \(nom) ».") }
        }
        let cible: [String: JSONValue] = args.int("photo_id").map { ["photo": .number(Double($0))] } ?? [:]
        let taille = Double(Self.variantThumbnailSize)
        var cases: [(image: CGImage?, legende: String)] = []
        var details: [JSONValue] = []
        let total = variantes.count + (args.bool("include_current") == false ? 0 : 1)
        contexte.avancer(0, sur: total, "Variantes")
        if args.bool("include_current") != false {
            var params = cible
            params["taille"] = .number(taille)
            params["cles"] = []
            let actuelle = try lightroom.send("apercu", params, timeout: 120)
            cases.append((PreviewImages.image(try Self.readPreview(actuelle["chemin"]?.string)), "Actuelle"))
            contexte.avancer(1, sur: total, "Variantes : état actuel rendu")
        }
        for variante in variantes {
            try contexte.verifier()
            let nom = variante["name"]!.string!.trimmingCharacters(in: .whitespaces)
            var raw = variante.object ?? [:]
            raw.removeValue(forKey: "name")
            // Même chemin qu'apply_settings : balance sur un point neutre mesurée sur l'aperçu,
            // repères d'Upright et pinceau du flou recalés.
            if let id = args.raw["photo_id"], !id.isNull { raw["photo_id"] = id }
            var vargs = Arguments(raw: raw)
            var balance: BalancePoint?
            if vargs.has("white_balance_point") { (vargs, balance) = try balanceSurPoint(vargs) }
            var (develop, notes) = try developParameters(vargs)
            if let balance {
                notes.append(.string("Balance du point neutre : a* \(Self.format((balance.avant.a * 10).rounded() / 10)), b* \(Self.format((balance.avant.b * 10).rounded() / 10)) mesurés ; Temperature et Tint d'après les pentes relevées."))
            }
            notes += recalagesDuRecadrage(&develop, cible: cible)
            notes += recalagesDesPositions(&develop, cible: cible)
            var params = develop
            params.merge(cible) { _, new in new }
            params["action"] = "appliquer"
            params["etape"] = .string("variante " + nom)
            params["instantane"] = .string(nom)
            params["taille"] = .number(taille)
            let resultat = try lightroom.send("essayer", params, timeout: 240)
            let image = PreviewImages.image(try Self.readPreview(resultat["chemin"]?.string))
            cases.append((image, nom))
            var item = Self.labelChanges(resultat).object ?? [:]
            item = item.filter { ["instantane", "changements", "remarques"].contains($0.key) }
            item["numero"] = .number(Double(cases.count))
            item["nom"] = .string(nom)
            if !notes.isEmpty { item["remarques_serveur"] = .array(notes) }
            details.append(.object(item))
            contexte.avancer(cases.count, sur: total, "Variantes : « \(nom) » rendue")
        }
        guard let planche = PreviewImages.planche(cases) else {
            throw LightroomError.plugin("Planche des variantes impossible à composer.")
        }
        let info: [String: JSONValue] = [
            "variantes": .array(details),
            "image": .string(args.bool("include_current") != false ? "Case 1 : l'état actuel ; puis les variantes, dans l'ordre." : "Les variantes, dans l'ordre."),
            "rien_n_est_applique": "La photo est revenue comme avant. choose_variant pose la variante que l'utilisateur choisit (undo_last la défait) ; il peut aussi les comparer dans le panneau Instantanés de Lightroom.",
        ]
        return ToolResult(content: [Self.imageContent(Self.compact(planche, maxBytes: Self.maxPreviewBytes)), .text(JSONCoding.pretty(.object(info)))],
                          structured: .object(info))
    }

    func chooseVariant(_ args: Arguments) throws -> JSONValue {
        let actions = ["choose": "choisir", "list": "lister", "delete": "effacer"]
        let action = args.string("action") ?? "choose"
        guard let module = actions[action] else { throw LightroomError.invalid("« action » : choose, list ou delete.") }
        var params: [String: JSONValue] = ["action": .string(module)]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        if action == "choose" {
            guard let nom = args.string("name")?.trimmingCharacters(in: .whitespaces), !nom.isEmpty else {
                throw LightroomError.invalid("« name » : la variante choisie par l'utilisateur.")
            }
            params["nom"] = .string(nom)
            params["effacer_autres"] = .bool(args.bool("delete_others") ?? false)
            params.merge(writeParameters(args, defaultStep: "variante " + nom)) { _, new in new }
        }
        if action == "delete", let noms = args.array("names") {
            params["noms"] = .array(noms.compactMap { $0.string.map(JSONValue.string) })
        }
        return Self.labelChanges(try lightroom.send("variantes", params, timeout: 120))
    }
}
