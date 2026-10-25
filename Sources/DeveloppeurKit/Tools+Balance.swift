import CoreGraphics
import Foundation

/// Balance des blancs sur un point neutre (`white_balance_point` d'apply_settings et de
/// preview_settings) : comme la pipette de Lightroom, un gris désigné dans l'aperçu donne la
/// température et la teinte. Le serveur mesure la dominante (a*, b*) d'une petite zone autour du
/// point sur un aperçu d'analyse, et la ramène à zéro par les pentes de `match_series`
/// (`PentesSerie`, relevées dans Lightroom : Teinte et Température se résolvent ensemble). Avec
/// apply_settings, une seconde passe mesurée corrige l'écart qui reste.
extension ToolHandler {
    /// La zone mesurée autour du point : en L*a*b* D65, comme les tons neutres de match_series (les
    /// pentes ont été relevées ainsi), sans les pixels écrêtés. Avec `scene`, le point neutre de toute
/// l'image (`MesureEclairage.neutre`, la dominante_globale de view_photo) tient lieu de point : pour
/// une forte dominante, les pentes dépassent la cible et la seconde passe mesurée la rattrape (constaté
/// le 24 octobre 2026 sur un portrait à l'ombre des feuillus, 5 150 K et +34 : la balance proposée
/// d'un coup, 6 968 K et +2, virait au vert ; 7 000 K et +28 laissaient le gravier neutre).
    struct PointNeutre: Equatable {
        var l: Double
        var a: Double
        var b: Double
        /// Part des pixels de la zone écrêtés (une composante ≥ 253), en %.
        var ecretes: Double
        var chroma: Double { (a * a + b * b).squareRoot() }
    }

    /// Une dominante sous ce seuil ne se voit pas : pas de seconde passe.
    static let seuilPointNeutre = 1.0
    /// Au-delà, le point n'est pas un gris : la balance se ferait sur une couleur.
    static let chromaMaxPointNeutre = 25.0

    /// Moyenne L*a*b* d'un carré de côté 2 × rayon + 1 autour de (x, y) (0 à 1), rayon de 0,8 % du
    /// grand côté (8 px sur un aperçu de 1024 px), sans les pixels écrêtés ni les noirs bouchés.
    static func mesurerPoint(_ data: Data, x: Double, y: Double) -> PointNeutre? {
        guard let image = PreviewImages.image(data), let pixels = Measurements.rgba(image) else { return nil }
        let w = image.width, h = image.height
        let rayon = max(3, Int((0.008 * Double(max(w, h))).rounded()))
        let cx = min(w - 1, max(0, Int(x * Double(w)))), cy = min(h - 1, max(0, Int(y * Double(h))))
        var somme = (0.0, 0.0, 0.0), n = 0, ecretes = 0, total = 0
        for py in max(0, cy - rayon)...min(h - 1, cy + rayon) {
            for px in max(0, cx - rayon)...min(w - 1, cx + rayon) {
                let i = (py * w + px) * 4
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                total += 1
                if max(r, g, b) >= 253 { ecretes += 1; continue }
                if max(r, g, b) <= 4 { continue }
                let lab = Measurements.lab(r, g, b)
                somme.0 += lab.l; somme.1 += lab.a; somme.2 += lab.b
                n += 1
            }
        }
        let part = total > 0 ? Double(ecretes) * 100 / Double(total) : 0
        guard n > 0 else { return PointNeutre(l: 100, a: 0, b: 0, ecretes: part) }
        return PointNeutre(l: somme.0 / Double(n), a: somme.1 / Double(n), b: somme.2 / Double(n), ecretes: part)
    }

    /// Balance à poser (valeurs absolues) pour ramener à zéro la dominante du point, depuis la
    /// balance actuelle : kelvins pour un RAW, relative (−100 à +100) sinon.
    static func balancePourPoint(_ point: PointNeutre, raw: Bool, temperature: Double, tint: Double, pentes: PentesSerie = PentesSerie())
        -> (temperature: Double, tint: Double) {
        let a = -point.a, b = -point.b
        if raw {
            let mired = 1_000_000 / max(temperature, 1) + pentes.miredA * a + pentes.miredB * b
            let kelvins = min(max(1_000_000 / max(mired, 20), 2000), 50000)
            return (kelvins.rounded(), min(max(tint + pentes.tintA * a + pentes.tintB * b, -150), 150).rounded())
        }
        return (min(max(temperature + pentes.jpegTempA * a + pentes.jpegTempB * b, -100), 100).rounded(),
                min(max(tint + pentes.jpegTintA * a + pentes.jpegTintB * b, -100), 100).rounded())
    }

    /// Balance qui neutralise la lumière des visages ou du sujet d'un éclairage mixte
    /// (view_photo › mesures › eclairage › balance_proposee) : la dominante de cette lumière ramenée
    /// à zéro par les mêmes pentes que white_balance_point. Nil si l'éclairage n'est pas mixte, sans
    /// lumière du sujet, ou sans Temperature lue dans `reponse` (réponse de la commande « apercu »).
    static func balanceProposee(_ mesure: MesureEclairage, reponse: JSONValue) -> (temperature: Double, tint: Double)? {
        guard mesure.mixte, let lumiere = mesure.lumiereSujet else { return nil }
        return balancePourLumiere(lumiere, reponse: reponse)
    }

    /// Balance qui ramène au gris le point neutre de toute l'image (view_photo › mesures › couleur ›
    /// dominante_globale › balance_proposee), par les mêmes pentes. Nil sans dominante globale ou
    /// sans Temperature lue dans `reponse`.
    static func balanceGlobale(_ mesures: PhotoMeasurements, reponse: JSONValue) -> (temperature: Double, tint: Double)? {
        guard let globale = mesures.dominanteGlobale else { return nil }
        return balancePourLumiere(MesureEclairage.Dominante(a: globale.a, b: globale.b, part: 0, pixels: 0), reponse: reponse)
    }

    /// Balance qui neutralise une lumière mesurée, depuis la balance que donne `reponse`
    /// (echelle_temperature, reglages) ; nil sans Temperature lue. Le relevé de l'éclairage
    /// (`--eclairage`) la donne aussi pour une photo que le seuil provisoire ne dit pas mixte.
    static func balancePourLumiere(_ lumiere: MesureEclairage.Dominante, reponse: JSONValue) -> (temperature: Double, tint: Double)? {
        guard let temperature = reponse["reglages"]?["Temperature"]?.double else { return nil }
        let raw = reponse["echelle_temperature"]?.string?.hasPrefix("kelvins") == true
        let tint = reponse["reglages"]?["Tint"]?.double ?? 0
        return balancePourPoint(PointNeutre(l: 50, a: lumiere.a, b: lumiere.b, ecretes: 0), raw: raw, temperature: temperature, tint: tint)
    }

    /// Le point neutre de toute l'image d'un aperçu, mesuré comme celui de view_photo (réduit à
    /// `Measurements.maxSide`, sans visages) ; nil si l'aperçu est illisible.
    static func mesurerScene(_ data: Data) -> PointNeutre? {
        guard let image = PreviewImages.image(data), let mesure = Eclairage.mesurer(image) else { return nil }
        return PointNeutre(l: 50, a: mesure.neutre.a, b: mesure.neutre.b, ecretes: 0)
    }

    /// Mesure du point (ou, sans point, de toute l'image) sur un aperçu d'analyse de la photo, et sa
    /// balance actuelle.
    func mesurerBalance(photo: Int?, point cible: (x: Double, y: Double)?) throws -> (point: PointNeutre, raw: Bool, temperature: Double, tint: Double) {
        var params: [String: JSONValue] = ["taille": .number(Double(Self.analysisSize)), "cles": ["Temperature", "Tint"]]
        if let photo { params["photo"] = .number(Double(photo)) }
        let reponse = try lightroom.send("apercu", params, timeout: 120)
        let data = try Self.readPreview(reponse["chemin"]?.string)
        guard let point = cible.map({ Self.mesurerPoint(data, x: $0.x, y: $0.y) }) ?? Self.mesurerScene(data) else {
            throw LightroomError.plugin("Aperçu illisible : le point neutre ne se mesure pas.")
        }
        let raw = reponse["echelle_temperature"]?.string?.contains("kelvins") == true
        return (point, raw, reponse["reglages"]?["Temperature"]?.double ?? (raw ? 5500 : 0), reponse["reglages"]?["Tint"]?.double ?? 0)
    }

    struct BalancePoint {
        var photo: Int?
        /// Le point désigné ; nil pour toute l'image (`scene`).
        var point: (x: Double, y: Double)?
        var avant: PointNeutre
    }

    /// Mesure le point et met la balance qui le neutralise dans les réglages de la retouche
    /// (absolue, ou l'écart si la retouche est relative).
    func balanceSurPoint(_ args: Arguments) throws -> (Arguments, BalancePoint) {
        let objet = args.object("white_balance_point")
        let scene = objet?["scene"]?.bool == true
        var designe: (x: Double, y: Double)?
        if !scene {
            guard let x = objet?["x"]?.double, let y = objet?["y"]?.double, (0...1).contains(x), (0...1).contains(y) else {
                throw LightroomError.invalid("« white_balance_point » : {x, y}, de 0 à 1 dans l'image telle que la montre view_photo, ou {scene: true} pour toute l'image.")
            }
            designe = (x, y)
        }
        let ids = try args.intList("photo_ids") ?? (args.int("photo_id").map { [$0] } ?? [])
        guard ids.count <= 1, args.bool("selection") != true else {
            throw LightroomError.invalid("« white_balance_point » vaut pour une seule photo (son gris) : la poser photo par photo, ou copier la balance (copy_settings).")
        }
        var settings = args.object("settings") ?? [:]
        guard settings["Temperature"] == nil, settings["Tint"] == nil, !args.has("white_balance") else {
            throw LightroomError.invalid("« white_balance_point » donne lui-même Temperature et Tint : ne pas les donner aussi (ni white_balance).")
        }
        let mesure = try mesurerBalance(photo: ids.first, point: designe)
        if designe != nil, mesure.point.ecretes > 50 {
            throw LightroomError.invalid("Le point désigné est brûlé (\(Int(mesure.point.ecretes.rounded())) % de pixels écrêtés) : la dominante ne s'y lit pas. Prendre un gris moins clair.")
        }
        if designe != nil, mesure.point.l < 8 {
            throw LightroomError.invalid("Le point désigné est presque noir (L* \(DevelopCatalogue.format(mesure.point.l.rounded()))) : la dominante ne s'y lit pas. Prendre un gris plus clair.")
        }
        if designe != nil, mesure.point.chroma > Self.chromaMaxPointNeutre {
            throw LightroomError.invalid("Le point désigné n'est pas un gris (a* \(Self.format((mesure.point.a * 10).rounded() / 10)), b* \(Self.format((mesure.point.b * 10).rounded() / 10)) : une couleur franche). Désigner un gris, un blanc cassé ou un noir sans couleur dans la réalité.")
        }
        let cible = Self.balancePourPoint(mesure.point, raw: mesure.raw, temperature: mesure.temperature, tint: mesure.tint)
        if args.bool("relative") == true {
            settings["Temperature"] = .number(cible.temperature - mesure.temperature)
            settings["Tint"] = .number(cible.tint - mesure.tint)
        } else {
            settings["Temperature"] = .number(cible.temperature)
            settings["Tint"] = .number(cible.tint)
        }
        var raw = args.raw
        raw["settings"] = .object(settings)
        raw.removeValue(forKey: "white_balance_point")
        return (Arguments(raw: raw), BalancePoint(photo: ids.first, point: designe, avant: mesure.point))
    }

    static func pointJSON(_ point: PointNeutre) -> JSONValue {
        ["a": .number((point.a * 10).rounded() / 10), "b": .number((point.b * 10).rounded() / 10)]
    }

    /// Seconde passe après une retouche écrite : le point remesuré ; s'il garde une dominante, une
    /// correction de l'écart, en une étape à part (« … : balance, passe 2 »).
    func secondePasseBalance(_ balance: BalancePoint, args: Arguments) -> JSONValue {
        var rapport: [String: JSONValue] = ["mesure_avant": Self.pointJSON(balance.avant)]
        guard let mesure = try? mesurerBalance(photo: balance.photo, point: balance.point) else {
            rapport["remarque"] = "Point non remesuré après la retouche."
            return .object(rapport)
        }
        rapport["apres_passe_1"] = Self.pointJSON(mesure.point)
        guard max(abs(mesure.point.a), abs(mesure.point.b)) >= Self.seuilPointNeutre else {
            rapport["base"] = "a* et b* du point (L*a*b*), 0 = neutre ; sous 1, l'écart ne se voit pas."
            return .object(rapport)
        }
        let cible = Self.balancePourPoint(mesure.point, raw: mesure.raw, temperature: mesure.temperature, tint: mesure.tint)
        let nom = "\(args.string("step_name") ?? "retouche") : balance, passe 2"
        do {
            var (params, _) = try developParameters(Arguments(raw: ["settings": ["Temperature": .number(cible.temperature), "Tint": .number(cible.tint)]]))
            if let photo = balance.photo { params["photos"] = [.number(Double(photo))] }
            var ecriture = writeParameters(Arguments(raw: ["step_name": .string(nom), "reason": args.raw["reason"] ?? .null,
                                                           "confirm": args.raw["confirm"] ?? .null]), defaultStep: nom)
            ecriture["raison"] = ecriture["raison"] ?? .string("Balance sur le point neutre, écart restant.")
            params.merge(ecriture) { _, new in new }
            _ = try lightroom.send("appliquer", params, timeout: 120)
            rapport["passe_2"] = .string("Claude · " + nom)
            if let final = try? mesurerBalance(photo: balance.photo, point: balance.point) {
                rapport["apres"] = Self.pointJSON(final.point)
            }
        } catch {
            rapport["remarque"] = .string("Seconde passe non faite : \(error.localizedDescription)")
        }
        rapport["base"] = "a* et b* du point (L*a*b*), 0 = neutre ; sous 1, l'écart ne se voit pas."
        return .object(rapport)
    }
}
