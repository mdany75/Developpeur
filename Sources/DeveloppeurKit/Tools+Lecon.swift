import Foundation

/// La leçon de la photo (1.3) : en fin de retouche d'une photo, trois points, lumière, couleur et
/// composition, chacun « ce qui manquait » et « à la prise de vue ». Les défauts nommés viennent de
/// PriseDeVue, seule liste ; la leçon est rangée par le module à part du catalogue (carnet.json),
/// d'où sa place dans readOnlyTools : ni la photo ni le catalogue ne changent.
///
/// Lot 1 : la définition seule, le corps est provisoire (une erreur d'outil, rien n'est envoyé au
/// module). Le lot 4 le remplace : journal détaillé, corrections nettes, faits, commande lecon.
extension ToolHandler {
    /// Chaque moitié d'un point (missing, at_capture) : une phrase simple.
    static let longueurPointLecon = 140

    var lessonDefinitions: [JSONValue] {
        let parAxe = PriseDeVue.Axe.allCases.map { axe in
            "\(axe.cle) : \(PriseDeVue.cles(axe: axe).joined(separator: ", "))"
        }.joined(separator: " ; ")
        let point = objectProp("Un point de la leçon, pour un axe.", [
            "axis": enumProp(PriseDeVue.Axe.allCases.map(\.cle),
                             "L'axe : light (lumière, netteté comprise), color (couleur) ou composition ; chacun une fois."),
            "missing": prop("string", "Ce qui manquait, chiffres à l'appui (bilan de view_photo, réglages du journal), \(Self.longueurPointLecon) caractères au plus. Absent ou vide : rien ne manquait."),
            "at_capture": prop("string", "Ce qui l'aurait évité à la prise de vue ; si rien ne manquait, ce qui a marché, à refaire. \(Self.longueurPointLecon) caractères au plus."),
            "defects": ["type": "array", "items": ["type": "string", "enum": .array(PriseDeVue.defauts.map { .string($0.cle) })],
                        "description": .string("Les défauts nommés, ceux de l'axe du point, pour le carnet de progrès (\(parAxe)). Vide : aucun.")],
        ], required: ["axis", "at_capture"])
        return [
            tool("photo_lesson",
                 "Leçon de la photo, en dernier, après le résumé de sa retouche et la proposition de cadre éventuelle : trois points, lumière, couleur et composition (axis light, color, composition), une fois chacun. Pour chacun, ce qui manquait (missing), chiffres à l'appui (bilan de view_photo, journal ; composition : read_composition s'il a servi), et ce qui l'aurait évité à la prise de vue (at_capture) : exposition, heure, place, réglage du boîtier (intention_boitier s'il est donné). Un axe sans défaut : missing absent, at_capture dit ce qui a marché. Une phrase simple chacun, \(Self.longueurPointLecon) caractères au plus ; defects : les défauts nommés, pour le carnet de progrès. Une intention du boîtier suivie (nuit voulue sombre) n'est pas un défaut. Une par photo (la nouvelle remplace l'ancienne) ; pas après une proposition seule (rien d'appliqué), une notation, un classement ou une série. Photo et catalogue inchangés : la leçon est rangée à part (carnet.json). Réponse : faits (corrections nettes de Claude, première vue mesurée, prise de vue) et remarques (défaut mesuré non nommé). read_facts = true : les faits seuls, rien n'est rangé. Hors de la fenêtre Claude : la redire en trois puces.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("points", ["type": "array", "items": point, "minItems": 3, "maxItems": 3,
                                "description": "Les trois points, un par axe (light, color, composition), dans n'importe quel ordre."]),
                    ("read_facts", prop("boolean", "true = les faits seuls (corrections nettes de Claude, mesures de départ, prise de vue), sans points : rien n'est rangé.")),
                 ],
                 required: []),
        ]
    }

    func callLesson(_ name: String, _ args: Arguments) throws -> ToolResult? {
        switch name {
        case "photo_lesson": return json(try photoLesson(args))
        default: return nil
        }
    }

    /// Corps provisoire : rien n'est envoyé au module (le lot 4 le remplace).
    func photoLesson(_ args: Arguments) throws -> JSONValue {
        throw LightroomError.invalid("photo_lesson (Leçon de la photo) n'est pas encore dans cette construction du connecteur : rien n'a été rangé.")
    }
}
