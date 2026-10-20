import Foundation

/// File des appels d'outils : un seul à la fois vers Lightroom, dans l'ordre d'arrivée, sur un fil
/// à part, pour que le serveur continue de lire stdin (ping, autres appels) pendant un long rendu.
///
/// Claude Desktop (et l'onglet Code de l'application, qui lui passe ses appels) abandonne un appel
/// d'outil au bout de 60 s, le délai par défaut du SDK MCP, sans tenir compte de la progression,
/// puis relance le serveur à l'appel suivant (constaté le 16 octobre 2026 : un aperçu de quatre
/// masques IA, « Request timed out » à 60,5 s). Un appel qui dépasse sa limite reçoit donc une
/// réponse d'attente : la commande continue, car le module de Lightroom la mène à terme de toute
/// façon, et son résultat est gardé pour le même appel répété, sans rien refaire.
///
/// Le module traite chaque commande dans sa propre tâche : une commande suivante attend que la
/// précédente ait fini (sinon la fin d'une proposition, qui remet la photo comme avant, effacerait
/// ce qu'on vient d'appliquer). Une commande qui n'a pas pu commencer avant sa limite n'est pas
/// lancée du tout.
///
/// Un appel que le client annule (`notifications/cancelled`) s'arrête entre deux photos d'une
/// série (`ContexteAppel`) ; pas encore commencé, il n'est pas lancé.
final class FileOutils {
    final class Appel {
        let nom: String
        let cle: String
        let debut = Date()
        let fini = DispatchGroup()
        /// Progression d'une longue série, et annulation demandée par le client.
        let contexte = ContexteAppel()
        var resultat: ToolResult?
        var finLe: Date?
        var commence = false
        /// Limite passée avant d'avoir commencé : l'appel n'est pas lancé.
        var abandonne = false
        /// Limite passée en cours de route : le résultat est gardé pour le même appel répété.
        var enAttente = false

        init(nom: String, cle: String) {
            self.nom = nom
            self.cle = cle
            fini.enter()
        }
    }

    /// Durée pendant laquelle un résultat arrivé après la limite reste offert au même appel.
    static let conservation: TimeInterval = 300

    private let file = DispatchQueue(label: "mcp-developpeur.outils")
    private let verrou = NSLock()
    private var enCours: Appel?
    /// Dernier appel resté sans réponse à sa limite, fini ou non.
    private var orphelin: Appel?

    /// Met l'appel dans la file (tout de suite, dans l'ordre d'arrivée), ou reprend celui qui a
    /// les mêmes nom et arguments s'il est resté sans réponse.
    func soumettre(nom: String, arguments: [String: JSONValue], travail: @escaping (ContexteAppel) -> ToolResult) -> Appel {
        let cle = nom + " " + JSONCoding.line(.object(arguments))
        verrou.lock()
        defer { verrou.unlock() }
        if let precedent = orphelin, precedent.cle == cle {
            if let fin = precedent.finLe, Date().timeIntervalSince(fin) > Self.conservation {
                orphelin = nil
            } else {
                return precedent
            }
        }
        let appel = Appel(nom: nom, cle: cle)
        file.async { [self] in
            verrou.lock()
            if appel.abandonne {
                verrou.unlock()
                appel.fini.leave()
                return
            }
            appel.commence = true
            enCours = appel
            // Une autre commande change peut-être la photo : le résultat gardé ne vaut plus.
            if let precedent = orphelin, precedent !== appel { orphelin = nil }
            verrou.unlock()
            let resultat = travail(appel.contexte)
            verrou.lock()
            appel.resultat = resultat
            appel.finLe = Date()
            enCours = nil
            verrou.unlock()
            appel.fini.leave()
        }
        return appel
    }

    /// Le client a annulé l'appel : pas encore commencé, il ne sera pas lancé ; commencé, il
    /// s'arrête au prochain `verifier` de l'outil. Son résultat n'est pas gardé.
    func annuler(_ appel: Appel) {
        verrou.lock()
        if !appel.commence { appel.abandonne = true }
        if orphelin === appel { orphelin = nil }
        verrou.unlock()
        appel.contexte.annuler()
    }

    /// Le résultat de l'appel, ou, passé `limite` (nil : sans limite), une réponse d'attente.
    func attendre(_ appel: Appel, jusqua limite: Date?) -> ToolResult {
        let delai: DispatchTime = limite.map { .now() + max(0, $0.timeIntervalSinceNow) } ?? .distantFuture
        _ = appel.fini.wait(timeout: delai)
        verrou.lock()
        defer { verrou.unlock() }
        if let resultat = appel.resultat {
            guard appel.enAttente else { return resultat }
            if orphelin === appel { orphelin = nil }
            appel.enAttente = false
            let duree = Self.duree(appel.finLe?.timeIntervalSince(appel.debut) ?? 0)
            return ToolResult(content: resultat.content + [.text("Résultat de l'appel précédent de \(appel.nom), resté sans réponse à la limite : fini en \(duree).")],
                              isError: resultat.isError, structured: resultat.structured)
        }
        let ecoule = Self.duree(Date().timeIntervalSince(appel.debut))
        if !appel.commence {
            appel.abandonne = true
            let autre = enCours?.nom ?? "la commande précédente"
            return ToolResult(text: "« \(appel.nom) » n'a pas été lancé : Lightroom Classic finit encore « \(autre) » (\(ecoule) d'attente). Rien n'a changé. Pour le résultat de \(autre), le rappeler avec exactement les mêmes arguments ; sinon réessayer \(appel.nom) dans un instant.",
                              isError: true)
        }
        appel.enAttente = true
        orphelin = appel
        let ou = appel.contexte.avancement.map { " (où il en est : \($0))" } ?? ""
        return ToolResult(text: "« \(appel.nom) » n'est pas fini après \(ecoule)\(ou) : Lightroom Classic y travaille encore (rendus, calcul des masques IA) et le mène à terme ; une proposition remet ensuite la photo comme avant. Le serveur répond avant le délai de 60 s de Claude Desktop pour ne pas perdre le résultat : rappeler \(appel.nom) avec exactement les mêmes arguments pour l'obtenir dès qu'il est prêt, sans rien refaire. Toute autre commande attend la fin de celle-ci. Si Lightroom affiche une fenêtre, elle attend une réponse de l'utilisateur : pour « Mises à jour IA recommandées » (réglages IA que Lightroom n'a pas pu calculer avant, modèles IA à télécharger par exemple), Exporter, case « Mettre à jour les photos concernées » cochée.")
    }

    /// « 50 s », « 1 min 12 s ».
    static func duree(_ secondes: TimeInterval) -> String {
        let total = Int(secondes.rounded())
        return total < 60 ? "\(total) s" : "\(total / 60) min \(String(format: "%02d", total % 60)) s"
    }
}
