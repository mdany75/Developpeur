import Foundation

/// La composition lue (1.3) : sur l'image entière, non recadrée, l'horizon, le sujet, son regard et
/// leur place par rapport aux tiers, puis un cadre proposé, jamais appliqué ici (preview_settings le
/// montre, apply_settings le pose après l'accord). Une photo recadrée est rendue sans son cadre le
/// temps de la lecture, puis remise telle quelle (deux étapes « Claude · composition » de
/// l'Historique), d'où sa place dans readOnlyTools, comme view_photo avec compare.
///
/// Lot 1 : la définition seule, le corps est provisoire (une erreur d'outil, rien n'est envoyé au
/// module). Le lot 5 le remplace : apercu entier, Composition.swift, cadre proposé.
extension ToolHandler {
    /// Taille du cadre (size, min_size), en part du plus grand cadre possible.
    static let tailleCadreComposition = 0.5...1.0
    static let tailleMinCompositionDefaut = 0.75

    var compositionDefinitions: [JSONValue] {
        let point = { (texte: String) in self.prop("number", texte) }
        let virgule = { (valeur: Double) in Self.format(valeur).replacingOccurrences(of: ".", with: ",") }
        return [
            tool("read_composition",
                 "Lit la composition de la photo sur l'image entière, non recadrée (une photo recadrée est rendue sans son cadre le temps de la lecture : deux étapes « Claude · composition » dans l'Historique, la photo revient telle quelle) : inclinaison et hauteur de l'horizon (deux points sur lui dans l'image que montre view_photo ; le serveur affine l'angle), sujet (visages et zone d'intérêt de Vision, ou subject), sens du regard, place de chacun par rapport aux tiers. Propose un cadre : horizon droit et sur un tiers, sujet sur un tiers avec de l'espace devant lui, le plus grand possible (au moins min_size). Rien n'est appliqué : montrer ce crop tel quel par preview_settings (image entière, cadre en pointillés), sans compare, attendre l'accord, puis apply_settings avec le même crop. « lecture » : ce qui cloche, en mots simples, à dire à l'utilisateur pour qu'il cadre mieux à la prise de vue.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("horizon", objectProp("L'horizon, ou une ligne qui devrait être horizontale : deux points sur lui, dans l'image que montre view_photo (de 0 à 1 depuis le coin haut gauche).", [
                        "x1": point("Premier point, depuis la gauche (0 à 1)."),
                        "y1": point("Premier point, depuis le haut (0 à 1)."),
                        "x2": point("Second point, depuis la gauche (0 à 1)."),
                        "y2": point("Second point, depuis le haut (0 à 1)."),
                    ], required: ["x1", "y1", "x2", "y2"])),
                    ("horizon_third", enumProp(["lower", "upper"], "Ligne des tiers où poser l'horizon : lower (défaut), celle du bas, deux tiers de ciel ; upper, celle du haut, quand le premier plan compte plus que le ciel.")),
                    ("subject", objectProp("Le sujet, quand ce n'est ni un visage ni la zone d'intérêt de Vision : son cadre dans l'image que montre view_photo (de 0 à 1).", [
                        "x": point("Bord gauche du sujet (0 à 1)."),
                        "y": point("Bord haut du sujet (0 à 1)."),
                        "width": point("Largeur du sujet (0 à 1)."),
                        "height": point("Hauteur du sujet (0 à 1)."),
                    ], required: ["x", "y", "width", "height"])),
                    ("facing", enumProp(["left", "right", "none"], "Vers où regarde ou avance le sujet dans l'image (none : de face) ; l'espace se laisse devant lui. Prime sur le regard lu par Vision.")),
                    ("subject_place", enumProp(["third", "center"], "third (défaut) : le sujet sur un tiers ; center : centré, pour une symétrie voulue.")),
                    ("aspect", prop("string", "Format du cadre proposé, comme crop.aspect d'apply_settings : « original » (défaut), « 1:1 », « 4:5 », « 3:2 »…")),
                    ("size", prop("number", "Taille imposée du cadre, en part du plus grand cadre possible (de \(virgule(Self.tailleCadreComposition.lowerBound)) à 1).")),
                    ("min_size", prop("number", "Taille la plus petite permise au cadre proposé, en part du plus grand possible (de \(virgule(Self.tailleCadreComposition.lowerBound)) à 1, défaut \(virgule(Self.tailleMinCompositionDefaut))).")),
                 ],
                 required: []),
        ]
    }

    /// Corps provisoire : rien n'est envoyé au module (le lot 5 le remplace).
    func readComposition(_ args: Arguments) throws -> JSONValue {
        throw LightroomError.invalid("read_composition (Lire la composition) n'est pas encore dans cette construction du connecteur : rien n'a été lu.")
    }
}
