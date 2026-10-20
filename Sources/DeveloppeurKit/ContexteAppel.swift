import Foundation

/// L'appel demandé n'est plus attendu : le client l'a annulé (`notifications/cancelled`).
struct AppelAnnule: Error, LocalizedError {
    var errorDescription: String? { "Appel annulé par le client." }
}

/// La série a été arrêtée dans Lightroom (la croix de sa barre de progression) : l'outil répond
/// par cette erreur, avec où il en était ; ce qui est fait reste.
struct ArretDansLightroom: Error, LocalizedError {
    var avancement: String?
    var errorDescription: String? {
        "Arrêté dans Lightroom (croix de la barre de progression)" + (avancement.map { " à « \($0) »" } ?? "")
            + " : la suite n'est pas partie ; ce qui était fait reste (undo_last pour une retouche ou un classement)."
    }
}

/// Contexte d'un appel d'outil, partagé entre la file des outils, le serveur et l'outil : où en
/// est une longue série (photo 120 sur 300), et si le client l'a annulée. Un outil qui traite une
/// série avance photo par photo (`avancer`) et vérifie l'annulation entre deux photos
/// (`verifier`) : ce qui est commencé dans Lightroom va jusqu'au bout, la suite ne part pas.
public final class ContexteAppel {
    private let verrou = NSLock()
    private var estAnnule = false
    private var arreteDansLightroom = false
    /// Identifiant de la barre de progression ouverte dans Lightroom pour cet appel, s'il y en a une.
    let identifiant = UUID().uuidString
    var barreOuverte = false
    private var etat: (fait: Int, total: Int, message: String)?
    private var observateur: ((Int, Int, String) -> Void)?

    public init() {}

    /// Vrai une fois l'appel annulé par le client.
    public var annule: Bool {
        verrou.lock(); defer { verrou.unlock() }
        return estAnnule
    }

    func annuler() {
        verrou.lock(); estAnnule = true; verrou.unlock()
    }

    /// L'utilisateur a arrêté la série dans Lightroom.
    func arreterDansLightroom() {
        verrou.lock(); arreteDansLightroom = true; verrou.unlock()
    }

    /// Lève `AppelAnnule` si le client a annulé l'appel, `ArretDansLightroom` si l'utilisateur l'a
    /// arrêté dans Lightroom : à appeler entre deux photos.
    func verifier() throws {
        if annule { throw AppelAnnule() }
        verrou.lock(); let arret = arreteDansLightroom; verrou.unlock()
        if arret { throw ArretDansLightroom(avancement: avancement) }
    }

    /// `fait` photos sur `total` : envoyé au client qui suit la progression (jeton), et repris dans
    /// la réponse d'attente de celui qui ne la suit pas.
    func avancer(_ fait: Int, sur total: Int, _ message: String) {
        verrou.lock()
        etat = (fait, total, message)
        let envoyer = observateur
        verrou.unlock()
        envoyer?(fait, total, message)
    }

    /// Où en est l'appel, en mots : « photo 120 sur 300 », ou nil.
    var avancement: String? {
        verrou.lock(); defer { verrou.unlock() }
        return etat.map { "\($0.fait) sur \($0.total) : \($0.message)" }
    }

    /// Reçoit chaque avancée (la progression envoyée au client), tant que l'appel est attendu.
    /// L'avancée déjà faite avant qu'il soit posé lui est rejouée (l'outil peut avancer avant que
    /// le serveur l'observe).
    func observer(_ fonction: ((Int, Int, String) -> Void)?) {
        verrou.lock()
        observateur = fonction
        let courant = etat
        verrou.unlock()
        if let fonction, let courant { fonction(courant.fait, courant.total, courant.message) }
    }
}
