import Foundation

/// Les sauvegardes, dites par get_status avant une longue série (1.3.5) : la dernière sauvegarde
/// du catalogue (le dossier Backups que Lightroom tient à côté du catalogue) et Time Machine (sa
/// dernière sauvegarde, et si le volume du catalogue y est). Lues seulement : Claude ne règle
/// rien. Les lectures du volume des photos sont bornées : macOS peut y faire attendre `open()`
/// (autorisation d'accès au volume), et Claude ne répond jamais à sa place.
public enum Sauvegardes {
    /// Lecture d'un dossier ou d'un outil du système, au plus.
    static let delai: TimeInterval = 3
    static let preferencesTimeMachine = URL(fileURLWithPath: "/Library/Preferences/com.apple.TimeMachine.plist")

    /// Le travail dans un fil à part, abandonné après `delai` (nil).
    static func borne<T>(_ delai: TimeInterval = delai, _ travail: @escaping () -> T?) -> T? {
        let fini = DispatchSemaphore(value: 0)
        let verrou = NSLock()
        var resultat: T?
        Thread.detachNewThread {
            let valeur = travail()
            verrou.lock(); resultat = valeur; verrou.unlock()
            fini.signal()
        }
        guard fini.wait(timeout: .now() + delai) == .success else { return nil }
        verrou.lock(); defer { verrou.unlock() }
        return resultat
    }

    /// La date d'un dossier de sauvegarde de Lightroom Classic : « 2026-10-20 2135 ».
    static func dateDossier(_ nom: String) -> Date? {
        let lecteur = DateFormatter()
        lecteur.locale = Locale(identifier: "en_US_POSIX")
        lecteur.timeZone = .current
        lecteur.dateFormat = "yyyy-MM-dd HHmm"
        return lecteur.date(from: nom)
    }

    static func texte(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "fr_CA")
        format.timeZone = .current
        format.dateFormat = "yyyy-MM-dd HH:mm"
        return format.string(from: date)
    }

    /// « il y a 3 jours », « il y a 5 heures ».
    static func ilYA(_ date: Date, maintenant: Date) -> String {
        let heures = max(0, Int(maintenant.timeIntervalSince(date) / 3600))
        if heures < 1 { return "il y a moins d'une heure" }
        if heures < 48 { return "il y a \(heures) heure\(heures > 1 ? "s" : "")" }
        return "il y a \(heures / 24) jours"
    }

    /// La dernière sauvegarde du catalogue : les dossiers datés de `Backups`, à côté du catalogue.
    /// `lister` rend les noms du dossier (nil : illisible ou pas lu à temps).
    static func catalogue(chemin: String, maintenant: Date, lister: (URL) -> [String]?) -> JSONValue {
        let dossier = URL(fileURLWithPath: chemin).deletingLastPathComponent().appendingPathComponent("Backups")
        guard let noms = lister(dossier) else {
            return ["trouvee": false, "remarque": "Dossier Backups à côté du catalogue absent ou pas lu à temps : Lightroom peut sauvegarder ailleurs (Paramètres du catalogue › Général), ou le volume ne répond pas."]
        }
        let dates = noms.compactMap(dateDossier)
        guard let derniere = dates.max() else {
            return ["trouvee": false, "remarque": "Aucune sauvegarde datée dans le dossier Backups à côté du catalogue."]
        }
        return ["trouvee": true, "derniere": .string(texte(derniere)), "il_y_a": .string(ilYA(derniere, maintenant: maintenant)),
                "nombre": .number(Double(dates.count)), "ou": "dossier Backups, à côté du catalogue"]
    }

    /// Le volume d'un chemin : « /Volumes/Photos », ou nil pour le disque du Mac.
    static func volume(_ chemin: String) -> String? {
        let parties = chemin.split(separator: "/", omittingEmptySubsequences: true)
        guard parties.count >= 2, parties[0] == "Volumes" else { return nil }
        return "/Volumes/" + parties[1]
    }

    /// Time Machine, d'après ses préférences (`plist`, nil : illisibles) ; `exclu` dit si un chemin en
    /// est exclu (nil : pas lu).
    static func timeMachine(plist: [String: Any]?, cheminCatalogue: String, maintenant: Date, exclu: (String) -> Bool?) -> JSONValue {
        guard let plist else { return ["lue": false, "remarque": "Préférences de Time Machine illisibles."] }
        let destinations = plist["Destinations"] as? [[String: Any]] ?? []
        var item: [String: JSONValue] = ["configuree": .bool(!destinations.isEmpty)]
        guard !destinations.isEmpty else {
            item["remarque"] = "Time Machine n'a aucune destination : ni le Mac ni les photos n'y sont sauvegardés."
            return .object(item)
        }
        let auto = (plist["AutoBackup"] as? Bool) ?? ((plist["AutoBackup"] as? Int).map { $0 != 0 } ?? false)
        item["automatique"] = .bool(auto)
        if let derniere = destinations.flatMap({ $0["SnapshotDates"] as? [Date] ?? [] }).max() {
            item["derniere"] = .string(texte(derniere))
            item["il_y_a"] = .string(ilYA(derniere, maintenant: maintenant))
        }
        let noms = destinations.compactMap { $0["LastKnownVolumeName"] as? String }
        if !noms.isEmpty { item["destination"] = .string(noms.joined(separator: ", ")) }
        let racine = volume(cheminCatalogue) ?? "/"
        item["volume_du_catalogue"] = .string(racine == "/" ? "disque du Mac" : String(racine.dropFirst("/Volumes/".count)))
        if let estExclu = exclu(racine) {
            item["volume_dans_time_machine"] = .bool(!estExclu)
            if estExclu {
                item["remarque"] = "Le volume du catalogue (et des originaux, s'ils y sont) n'est pas dans Time Machine : un disque externe n'y entre que s'il est ajouté dans Réglages Système › Time Machine › Options. À dire à l'utilisateur, sans rien régler."
            }
        } else {
            item["volume_dans_time_machine"] = .null
            item["remarque"] = "Pas lu à temps si le volume du catalogue est dans Time Machine."
        }
        return .object(item)
    }

    /// `tmutil isexcluded` : « [Excluded] » ou « [Included] » ; nil si l'outil ne répond pas à temps.
    static func exclu(_ chemin: String) -> Bool? {
        borne {
            let processus = Process()
            processus.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
            processus.arguments = ["isexcluded", chemin]
            let sortie = Pipe()
            processus.standardOutput = sortie
            processus.standardError = Pipe()
            do { try processus.run() } catch { return nil }
            let data = sortie.fileHandleForReading.readDataToEndOfFile()
            processus.waitUntilExit()
            let texte = String(decoding: data, as: UTF8.self)
            if texte.contains("[Excluded]") { return true }
            if texte.contains("[Included]") { return false }
            return nil
        } ?? nil
    }

    /// Ce que get_status en dit, sur ce Mac.
    public static func lire(cheminCatalogue: String) -> JSONValue? {
        let maintenant = Date()
        let plist = (try? Data(contentsOf: preferencesTimeMachine)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        return json(catalogue: catalogue(chemin: cheminCatalogue, maintenant: maintenant) { dossier in
                        borne { try? FileManager.default.contentsOfDirectory(atPath: dossier.path) } ?? nil
                    },
                    timeMachine: timeMachine(plist: plist, cheminCatalogue: cheminCatalogue, maintenant: maintenant, exclu: exclu))
    }

    static func json(catalogue: JSONValue, timeMachine: JSONValue) -> JSONValue {
        ["catalogue": catalogue, "time_machine": timeMachine,
         "lecture": "Lues seulement : Claude ne règle rien. Avant d'écrire sur des centaines de photos : une sauvegarde du catalogue récente (sinon request_backup la fait faire à la prochaine fermeture de Lightroom), et des originaux à l'abri (Time Machine, ou une copie ailleurs) ; le dire à l'utilisateur."]
    }
}
