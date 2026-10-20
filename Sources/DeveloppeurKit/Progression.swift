import Foundation

/// Notifications de progression (`notifications/progress`) envoyées à intervalle régulier pendant
/// un appel d'outil dont la requête porte `_meta.progressToken`. Un client qui les reçoit peut
/// relancer son délai (60 s par défaut dans le SDK MCP) au lieu d'abandonner un aperçu que
/// Lightroom calcule encore. Le battement tourne sur son propre fil ; `arreter` attend la fin d'un
/// envoi en cours : aucune notification ne part après la réponse.
///
/// Une longue série (tri, analyse, copie) donne aussi sa vraie progression, photo par photo
/// (`avancer`) : `progress` = photos faites, `total` = photos de la série. Entre deux photos, le
/// battement continue d'avancer d'un centième au plus (la valeur doit croître à chaque
/// notification), sans atteindre la photo suivante.
final class Progression {
    private let verrou = NSLock()
    private var arretee = false
    private var envois = 0
    /// Dernière vraie progression : photos faites, total, message ; battements depuis.
    private var serie: (fait: Int, total: Int, message: String)?
    private var battements = 0
    private var dernier = 0.0
    private let minuterie: DispatchSourceTimer
    private let debut = Date()
    private let jeton: JSONValue
    private let envoyer: (JSONValue) -> Void

    init(jeton: JSONValue, intervalle: TimeInterval, envoyer: @escaping (JSONValue) -> Void) {
        self.jeton = jeton
        self.envoyer = envoyer
        minuterie = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "mcp-developpeur.progression"))
        minuterie.schedule(deadline: .now() + intervalle, repeating: intervalle)
        minuterie.setEventHandler { [weak self] in
            self?.battre()
        }
        minuterie.resume()
    }

    deinit {
        arreter()
    }

    private func battre() {
        verrou.lock()
        defer { verrou.unlock() }
        guard !arretee else { return }
        envois += 1
        let secondes = Int(Date().timeIntervalSince(debut).rounded())
        if let serie {
            battements += 1
            let valeur = Double(serie.fait) + min(0.99, 0.01 * Double(battements))
            guard valeur > dernier else { return }
            dernier = valeur
            envoyer(Self.notification(jeton: jeton, progression: valeur, total: Double(serie.total),
                                      message: "\(serie.message) (\(serie.fait) sur \(serie.total), \(secondes) s)"))
        } else {
            dernier = Double(envois)
            envoyer(Self.notification(jeton: jeton, progression: dernier, total: nil,
                                      message: "Lightroom Classic travaille encore (\(secondes) s)…"))
        }
    }

    /// Vraie progression d'une série : envoyée tout de suite si elle avance.
    func avancer(fait: Int, total: Int, message: String) {
        verrou.lock()
        defer { verrou.unlock() }
        guard !arretee else { return }
        serie = (fait, total, message)
        battements = 0
        let valeur = Double(fait)
        guard valeur > dernier else { return }
        dernier = valeur
        envoyer(Self.notification(jeton: jeton, progression: valeur, total: Double(total), message: "\(message) (\(fait) sur \(total))"))
    }

    func arreter() {
        verrou.lock()
        arretee = true
        verrou.unlock()
        minuterie.cancel()
    }

    static func notification(jeton: JSONValue, progression: Double, total: Double?, message: String) -> JSONValue {
        var params: [String: JSONValue] = ["progressToken": jeton, "progress": .number(progression), "message": .string(message)]
        if let total { params["total"] = .number(total) }
        return ["jsonrpc": "2.0", "method": "notifications/progress", "params": .object(params)]
    }
}
