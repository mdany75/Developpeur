import Accelerate
import Foundation
import SQLite3

/// L'index de la recherche par le sens (1.6), d'un catalogue, hors du catalogue :
/// `Developpeur/Index/<empreinte du chemin du catalogue>/` (Sens.empreinte), deux fichiers :
///
/// - `vecteurs.f16` : les empreintes, à la suite, en nombres de 16 bits (512 × 2 octets par photo ;
///   250 000 photos : 256 Mo), lues projetées en mémoire et classées par blocs (Accelerate), sans copie
///   permanente en 32 bits ;
/// - `index.sqlite` : une ligne par original (`rang` : sa place dans vecteurs.f16, `uuid`, `id` :
///   localIdentifier, `jour` « AAAA-MM-JJ » de la prise de vue, à l'heure locale, pour filtrer les
///   dates ici, `le` : l'heure de l'empreinte), et `meta` (modèle, dimension, catalogue, règles).
///
/// Un seul écrivain à la fois (`--analyser`, la tâche du Suivi ; un verrou flock sur `verrou` pour une
/// ancienne instance), des lecteurs à tout moment (WAL) : l'écrivain écrit le vecteur avant sa ligne,
/// un lecteur ne voit donc jamais une ligne sans vecteur. Un index d'un autre modèle ou d'une autre
/// dimension se refait à la première écriture (une lecture le dit vide).
public final class IndexSens {
    public struct Ligne: Equatable {
        public var rang: Int
        public var id: Int
        public var uuid: String
        public var jour: String?
    }

    public enum Erreur: Error, LocalizedError {
        case sqlite(String)
        case dimension(Int, Int)
        public var errorDescription: String? {
            switch self {
            case .sqlite(let detail): return "Index de la recherche par le sens : \(detail)"
            case .dimension(let a, let b): return "Index de la recherche par le sens : un vecteur de \(a) nombres, l'index en attend \(b)."
            }
        }
    }

    public let dossier: URL
    public private(set) var modele: String
    public private(set) var dimension: Int
    private var base: OpaquePointer?

    var fichierBase: URL { dossier.appendingPathComponent("index.sqlite") }
    var fichierVecteurs: URL { dossier.appendingPathComponent("vecteurs.f16") }
    var fichierVerrou: URL { dossier.appendingPathComponent("verrou") }

    /// Le dossier de l'index d'un catalogue sous `racine`.
    public static func dossier(catalogue: String, racine: URL = Sens.racineIndex) -> URL {
        racine.appendingPathComponent(Sens.empreinte(catalogue: catalogue), isDirectory: true)
    }

    /// Ouvre (et crée au besoin) l'index pour y écrire, pour ce modèle. Un index d'un autre modèle est
    /// refait ; un index illisible (base abîmée, vecteurs effacés à côté de leurs lignes) aussi, à neuf,
    /// plutôt que d'échouer à chaque photo. Chaque index neuf ou refait reçoit une nouvelle
    /// `generation` : le module la garde avec chaque analyse (`index_sens`) et refait l'empreinte des
    /// photos d'une autre génération (un index perdu se remplit de nouveau).
    public init(ecrire dossier: URL, modele: String, dimension: Int, catalogue: String? = nil) throws {
        self.dossier = dossier
        self.modele = modele
        self.dimension = dimension
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        do {
            try preparerEcriture(catalogue: catalogue)
        } catch {
            // Illisible : refait à neuf, une fois.
            sqlite3_close(base)
            base = nil
            effacerFichiers()
            try preparerEcriture(catalogue: catalogue)
        }
    }

    private func effacerFichiers() {
        let fm = FileManager.default
        for nom in ["index.sqlite", "index.sqlite-wal", "index.sqlite-shm", "vecteurs.f16"] {
            try? fm.removeItem(at: dossier.appendingPathComponent(nom))
        }
    }

    private func preparerEcriture(catalogue: String?) throws {
        try ouvrirBase(lecture: false)
        try executer("PRAGMA journal_mode=WAL")
        try executer("CREATE TABLE IF NOT EXISTS meta (cle TEXT PRIMARY KEY, valeur TEXT NOT NULL)")
        try executer("CREATE TABLE IF NOT EXISTS photos (rang INTEGER PRIMARY KEY, uuid TEXT NOT NULL UNIQUE, id INTEGER NOT NULL, jour TEXT, le REAL NOT NULL)")
        try executer("CREATE INDEX IF NOT EXISTS photos_id ON photos(id)")
        let meta = lireMeta()
        var neuf = meta["generation"] == nil
        if let autre = meta["modele"], autre != modele || meta["dimension"] != String(dimension) {
            // Un autre modèle : ses vecteurs ne se comparent pas aux nouveaux.
            try viderPhotos()
            neuf = true
        } else if let fin = rangMax(), fin >= 0 {
            // Des lignes sans leurs vecteurs (vecteurs.f16 effacé ou coupé) : refait.
            let taille = (try? FileManager.default.attributesOfItem(atPath: fichierVecteurs.path)[.size] as? Int) ?? 0
            if taille < (fin + 1) * dimension * 2 {
                try viderPhotos()
                neuf = true
            }
        }
        try ecrireMeta("modele", modele)
        try ecrireMeta("dimension", String(dimension))
        try ecrireMeta("regles", String(Sens.regles))
        if neuf { try ecrireMeta("generation", UUID().uuidString) }
        if let catalogue { try ecrireMeta("catalogue", catalogue) }
    }

    private func viderPhotos() throws {
        try executer("DELETE FROM photos")
        try? FileManager.default.removeItem(at: fichierVecteurs)
    }

    /// Le plus grand rang rangé (nil : aucune ligne).
    private func rangMax() -> Int? {
        guard let r = try? preparer("SELECT MAX(rang) FROM photos") else { return nil }
        defer { sqlite3_finalize(r) }
        guard sqlite3_step(r) == SQLITE_ROW, sqlite3_column_type(r, 0) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(r, 0))
    }

    /// La génération de cet index : tirée à sa création, et à chaque fois qu'il est refait (nil : un
    /// index sans génération, à refaire par l'écrivain).
    public var generation: String? { lireMeta()["generation"] }

    /// Ouvre l'index pour le lire ; nil s'il n'existe pas ou ne se lit pas.
    public init?(lire dossier: URL) {
        self.dossier = dossier
        modele = ""
        dimension = 0
        guard FileManager.default.fileExists(atPath: dossier.appendingPathComponent("index.sqlite").path) else { return nil }
        do { try ouvrirBase(lecture: true) } catch { return nil }
        let meta = lireMeta()
        guard let m = meta["modele"], let d = meta["dimension"].flatMap(Int.init), d > 0 else { return nil }
        modele = m
        dimension = d
    }

    deinit { sqlite3_close(base) }

    private func ouvrirBase(lecture: Bool) throws {
        let drapeaux = lecture ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(fichierBase.path, &base, drapeaux | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            let message = base.map { String(cString: sqlite3_errmsg($0)) } ?? "ouverture"
            sqlite3_close(base)
            base = nil
            throw Erreur.sqlite(message)
        }
        sqlite3_busy_timeout(base, 5000)
    }

    private func executer(_ sql: String) throws {
        guard sqlite3_exec(base, sql, nil, nil, nil) == SQLITE_OK else { throw Erreur.sqlite(String(cString: sqlite3_errmsg(base))) }
    }

    private func preparer(_ sql: String) throws -> OpaquePointer? {
        var requete: OpaquePointer?
        guard sqlite3_prepare_v2(base, sql, -1, &requete, nil) == SQLITE_OK else { throw Erreur.sqlite(String(cString: sqlite3_errmsg(base))) }
        return requete
    }

    private static let transitoire = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func lireMeta() -> [String: String] {
        guard let r = try? preparer("SELECT cle, valeur FROM meta") else { return [:] }
        defer { sqlite3_finalize(r) }
        var meta: [String: String] = [:]
        while sqlite3_step(r) == SQLITE_ROW {
            meta[String(cString: sqlite3_column_text(r, 0))] = String(cString: sqlite3_column_text(r, 1))
        }
        return meta
    }

    private func ecrireMeta(_ cle: String, _ valeur: String) throws {
        let r = try preparer("INSERT OR REPLACE INTO meta (cle, valeur) VALUES (?, ?)")
        defer { sqlite3_finalize(r) }
        sqlite3_bind_text(r, 1, cle, -1, Self.transitoire)
        sqlite3_bind_text(r, 2, valeur, -1, Self.transitoire)
        guard sqlite3_step(r) == SQLITE_DONE else { throw Erreur.sqlite(String(cString: sqlite3_errmsg(base))) }
    }

    public var meta: [String: String] { lireMeta() }

    // MARK: Écriture

    /// Range l'empreinte d'un original (remplace celle du même uuid ; une autre photo sous le même id
    /// sort de l'index). `jour` : « AAAA-MM-JJ » (ou la date « AAAA-MM-JJ HH:MM » du relevé, coupée).
    public func ranger(uuid: String, id: Int, jour: String?, vecteur: [Float], le: Date = Date()) throws {
        guard vecteur.count == dimension else { throw Erreur.dimension(vecteur.count, dimension) }
        let verrou = open(fichierVerrou.path, O_CREAT | O_RDWR, 0o644)
        if verrou >= 0 { flock(verrou, LOCK_EX) }
        defer { if verrou >= 0 { flock(verrou, LOCK_UN); close(verrou) } }

        var rang: Int?
        if let r = try? preparer("SELECT rang FROM photos WHERE uuid = ?") {
            sqlite3_bind_text(r, 1, uuid, -1, Self.transitoire)
            if sqlite3_step(r) == SQLITE_ROW { rang = Int(sqlite3_column_int64(r, 0)) }
            sqlite3_finalize(r)
        }
        if rang == nil, let r = try? preparer("SELECT COALESCE(MAX(rang) + 1, 0) FROM photos") {
            if sqlite3_step(r) == SQLITE_ROW { rang = Int(sqlite3_column_int64(r, 0)) }
            sqlite3_finalize(r)
        }
        let place = rang ?? 0
        // Le vecteur d'abord, à sa place ; la ligne ensuite.
        let moitie = vecteur.map { Float16($0) }
        let fm = FileManager.default
        if !fm.fileExists(atPath: fichierVecteurs.path) { fm.createFile(atPath: fichierVecteurs.path, contents: nil) }
        let poignee = try FileHandle(forWritingTo: fichierVecteurs)
        defer { try? poignee.close() }
        try poignee.seek(toOffset: UInt64(place * dimension * 2))
        try poignee.write(contentsOf: moitie.withUnsafeBufferPointer { Data(buffer: $0) })
        try poignee.synchronize()

        let jourCourt = jour.map { String($0.prefix(10)) }.flatMap { $0.count == 10 ? $0 : nil }
        try executer("BEGIN IMMEDIATE")
        do {
            let efface = try preparer("DELETE FROM photos WHERE id = ? AND uuid <> ?")
            sqlite3_bind_int64(efface, 1, Int64(id))
            sqlite3_bind_text(efface, 2, uuid, -1, Self.transitoire)
            _ = sqlite3_step(efface)
            sqlite3_finalize(efface)
            let r = try preparer("INSERT OR REPLACE INTO photos (rang, uuid, id, jour, le) VALUES (?, ?, ?, ?, ?)")
            sqlite3_bind_int64(r, 1, Int64(place))
            sqlite3_bind_text(r, 2, uuid, -1, Self.transitoire)
            sqlite3_bind_int64(r, 3, Int64(id))
            if let jourCourt { sqlite3_bind_text(r, 4, jourCourt, -1, Self.transitoire) } else { sqlite3_bind_null(r, 4) }
            sqlite3_bind_double(r, 5, le.timeIntervalSince1970)
            let fait = sqlite3_step(r)
            sqlite3_finalize(r)
            guard fait == SQLITE_DONE else { throw Erreur.sqlite(String(cString: sqlite3_errmsg(base))) }
            try executer("COMMIT")
        } catch {
            try? executer("ROLLBACK")
            throw error
        }
    }

    // MARK: Lecture

    public var nombre: Int {
        guard let r = try? preparer("SELECT COUNT(*) FROM photos") else { return 0 }
        defer { sqlite3_finalize(r) }
        return sqlite3_step(r) == SQLITE_ROW ? Int(sqlite3_column_int64(r, 0)) : 0
    }

    /// L'heure de la dernière empreinte rangée.
    public var derniere: Date? {
        guard let r = try? preparer("SELECT MAX(le) FROM photos") else { return nil }
        defer { sqlite3_finalize(r) }
        guard sqlite3_step(r) == SQLITE_ROW, sqlite3_column_type(r, 0) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(r, 0))
    }

    public func lignes() -> [Ligne] {
        guard let r = try? preparer("SELECT rang, id, uuid, jour FROM photos ORDER BY rang") else { return [] }
        defer { sqlite3_finalize(r) }
        var liste: [Ligne] = []
        while sqlite3_step(r) == SQLITE_ROW {
            let jour = sqlite3_column_type(r, 3) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(r, 3))
            liste.append(Ligne(rang: Int(sqlite3_column_int64(r, 0)), id: Int(sqlite3_column_int64(r, 1)),
                               uuid: String(cString: sqlite3_column_text(r, 2)), jour: jour))
        }
        return liste
    }

    /// Les vecteurs, projetés en mémoire (nil sans fichier).
    private func vecteurs() -> Data? {
        try? Data(contentsOf: fichierVecteurs, options: .alwaysMapped)
    }

    /// Le vecteur rangé d'une photo (par son id), en 32 bits.
    public func vecteur(id: Int) -> [Float]? {
        guard let ligne = lignes().first(where: { $0.id == id }), let donnees = vecteurs() else { return nil }
        let d = dimension
        let debut = ligne.rang * d * 2
        guard debut + d * 2 <= donnees.count else { return nil }
        return donnees.withUnsafeBytes { brut -> [Float] in
            let p = brut.baseAddress!.advanced(by: debut).assumingMemoryBound(to: Float16.self)
            return (0..<d).map { Float(p[$0]) }
        }
    }

    /// Le score (produit scalaire, les deux de norme 1 : le cosinus) de chaque ligne gardée, du
    /// meilleur au moins bon (à égalité, l'id croissant). Les vecteurs se convertissent par blocs de
    /// `bloc` empreintes (vImage), puis un produit matrice-vecteur (vDSP).
    public func classer(_ requete: [Float], lignes: [Ligne]? = nil, bloc: Int = 4096) -> [(ligne: Ligne, score: Float)] {
        let d = dimension
        guard requete.count == d, d > 0, let donnees = vecteurs() else { return [] }
        let toutes = lignes ?? self.lignes()
        let places = donnees.count / (d * 2)
        guard places > 0 else { return [] }
        var scores = [Float](repeating: -.infinity, count: places)
        donnees.withUnsafeBytes { brut in
            guard let base = brut.baseAddress else { return }
            var tampon = [Float](repeating: 0, count: bloc * d)
            var debut = 0
            while debut < places {
                let n = min(bloc, places - debut)
                tampon.withUnsafeMutableBufferPointer { sortie in
                    var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: base.advanced(by: debut * d * 2)),
                                               height: 1, width: vImagePixelCount(n * d), rowBytes: n * d * 2)
                    var cible = vImage_Buffer(data: sortie.baseAddress!, height: 1, width: vImagePixelCount(n * d), rowBytes: n * d * 4)
                    vImageConvert_Planar16FtoPlanarF(&source, &cible, 0)
                }
                scores.withUnsafeMutableBufferPointer { s in
                    tampon.withUnsafeBufferPointer { a in
                        requete.withUnsafeBufferPointer { q in
                            vDSP_mmul(a.baseAddress!, 1, q.baseAddress!, 1, s.baseAddress!.advanced(by: debut), 1,
                                      vDSP_Length(n), 1, vDSP_Length(d))
                        }
                    }
                }
                debut += n
            }
        }
        return toutes.compactMap { ligne -> (ligne: Ligne, score: Float)? in
            guard ligne.rang < places, scores[ligne.rang].isFinite else { return nil }
            return (ligne, scores[ligne.rang])
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.ligne.id < $1.ligne.id }
    }
}
