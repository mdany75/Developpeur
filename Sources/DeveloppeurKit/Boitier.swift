import Foundation

/// Ce que l'appareil a rangé dans un fichier Fujifilm (RAF, ou JPEG de l'appareil) : le point de
/// mise au point (PointAF.swift), l'intention de la prise de vue (IntentionBoitier.swift) et, pour
/// l'onglet Focus de la fenêtre Claude, la mise au point en détail (Focus.swift), lus d'une seule
/// ouverture de l'original, dans l'Exif et la MakerNote, comme le module Focus Points de Lightroom
/// les lit par exiftool. ImageIO ne donne pas la MakerNote de Fujifilm (constaté sous
/// macOS 26 sur un RAF de X-H2S) : le serveur la lit lui-même, en lecture seule.
///
/// Relevé sur un RAF de X-H2S (exiftool 13.55, du module Focus Points) :
/// - en-tête « FUJIFILMCCD-RAW », position du JPEG incorporé à l'octet 84 et sa longueur à 88
///   (grand-boutiste) ; le JPEG porte l'Exif de la photo, MakerNote comprise (tag 0x927C) ;
/// - MakerNote : « FUJIFILM », puis la position de son IFD (petit-boutiste, depuis le début de la
///   MakerNote), entrées petit-boutistes, valeurs repérées depuis le début de la MakerNote.
/// Un HEIF de l'appareil (ni RAF ni FF D8) n'est pas lu.
public struct LectureBoitier: Equatable {
    /// Point de mise au point ; nil sans point rangé (0, 0 : mise au point manuelle, supposé) ou
    /// sans les dimensions de l'Exif.
    public var point: PointAF?
    /// Réglages choisis à la prise de vue ; nil si aucun n'est lu.
    public var intention: IntentionBoitier?
    /// La mise au point en détail (mode, zone, visages et éléments du sujet, stabilisation, mode
    /// d'entraînement) : l'onglet Focus de la fenêtre Claude ; nil si rien n'en est lu.
    public var miseAuPoint: MiseAuPointBoitier?

    public init(point: PointAF? = nil, intention: IntentionBoitier? = nil, miseAuPoint: MiseAuPointBoitier? = nil) {
        self.point = point
        self.intention = intention
        self.miseAuPoint = miseAuPoint
    }

    /// Octets lus au début du JPEG incorporé (l'Exif tient dans les 64 premiers Ko).
    static let tailleLue = 131_072

    /// Ce que dit le fichier, ou nil (autre marque, fichier illisible, absent, ou rien de lu).
    public static func lire(fichier: URL) -> LectureBoitier? {
        guard let handle = try? FileHandle(forReadingFrom: fichier) else { return nil }
        defer { try? handle.close() }
        guard let debut = try? handle.read(upToCount: 96), debut.count >= 92 else { return nil }
        if debut.starts(with: Data("FUJIFILMCCD-RAW".utf8)) {
            let position = Int(lireEntier(debut, 84, 4, petit: false) ?? 0)
            guard position > 0, (try? handle.seek(toOffset: UInt64(position))) != nil,
                  let jpeg = try? handle.read(upToCount: tailleLue) else { return nil }
            return analyser(jpeg: jpeg)
        }
        guard debut.starts(with: [0xFF, 0xD8]), (try? handle.seek(toOffset: 0)) != nil,
              let jpeg = try? handle.read(upToCount: tailleLue) else { return nil }
        return analyser(jpeg: jpeg)
    }

    /// La lecture d'après le début d'un JPEG qui porte l'Exif de l'appareil : l'Exif, IFD0, l'IFD
    /// Exif (0x8769), la MakerNote (0x927C) qui commence par « FUJIFILM », puis l'IFD de Fujifilm.
    /// Le point et l'intention se lisent l'un sans l'autre : un point (0, 0) n'empêche plus de lire
    /// l'intention.
    static func analyser(jpeg: Data) -> LectureBoitier? {
        guard let tiff = segmentExif(jpeg), let exif = Tiff(tiff),
              let ifd0 = exif.ifd(at: exif.premierIFD),
              let pointeur = ifd0[0x8769]?.entier, let exifIFD = exif.ifd(at: Int(pointeur)),
              let note = exifIFD[0x927C], note.position + 12 <= tiff.count else { return nil }
        let debutNote = note.position
        guard tiff.subdata(in: debutNote..<(debutNote + 8)) == Data("FUJIFILM".utf8),
              let decalage = lireEntier(tiff, debutNote + 8, 4, petit: true) else { return nil }
        let fuji = Tiff(donnees: tiff.subdata(in: debutNote..<tiff.count), petit: true)
        guard let ifd = fuji.ifd(at: Int(decalage)) else { return nil }
        let lecture = LectureBoitier(point: PointAF.depuis(note: ifd, largeur: exifIFD[0xA002]?.entier, hauteur: exifIFD[0xA003]?.entier),
                                     intention: IntentionBoitier(note: ifd, exif: exifIFD),
                                     miseAuPoint: MiseAuPointBoitier(note: ifd, exif: exifIFD))
        return lecture.point == nil && lecture.intention == nil && lecture.miseAuPoint == nil ? nil : lecture
    }

    /// Le contenu TIFF du segment APP1 « Exif » d'un JPEG.
    static func segmentExif(_ jpeg: Data) -> Data? {
        let octets = [UInt8](jpeg)
        guard octets.count > 4, octets[0] == 0xFF, octets[1] == 0xD8 else { return nil }
        var i = 2
        while i + 4 <= octets.count, octets[i] == 0xFF {
            let marqueur = octets[i + 1]
            let longueur = Int(octets[i + 2]) << 8 | Int(octets[i + 3])
            guard longueur >= 2 else { return nil }
            if marqueur == 0xE1, i + 10 <= octets.count, Array(octets[(i + 4)..<(i + 10)]) == [0x45, 0x78, 0x69, 0x66, 0, 0] {
                let fin = min(i + 2 + longueur, octets.count)
                guard i + 10 < fin else { return nil }
                return Data(octets[(i + 10)..<fin])
            }
            if marqueur == 0xDA { return nil }   // début de l'image : pas d'Exif avant
            i += 2 + longueur
        }
        return nil
    }

    static func lireEntier(_ d: Data, _ position: Int, _ taille: Int, petit: Bool) -> UInt32? {
        guard position >= 0, position + taille <= d.count else { return nil }
        var valeur: UInt32 = 0
        for k in 0..<taille {
            let octet = UInt32(d[d.startIndex + position + (petit ? taille - 1 - k : k)])
            valeur = valeur << 8 | octet
        }
        return valeur
    }

    /// Un fichier TIFF (ou une MakerNote de même forme) : ses IFD, entrée par entrée.
    struct Tiff {
        /// Octets d'une valeur de chaque type TIFF : 1 BYTE, 2 ASCII, 3 SHORT, 4 LONG, 5 RATIONAL,
        /// 6 SBYTE, 7 UNDEFINED, 8 SSHORT, 9 SLONG, 10 SRATIONAL, 11 FLOAT, 12 DOUBLE.
        static let tailles: [Int: Int] = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8]

        struct Entree {
            var type: Int
            var nombre: Int
            /// Position de la valeur dans les données (dans l'entrée même si elle tient en 4 octets).
            var position: Int
            let tiff: Tiff

            /// Octets d'un entier de ce type (0 : pas un type entier).
            var largeur: Int {
                switch type {
                case 1, 6, 7: return 1
                case 3, 8: return 2
                case 4, 9: return 4
                default: return 0
                }
            }

            var entier: UInt32? { entiers(1).first.map(UInt32.init) }

            /// Les premières valeurs, lues sans signe (le motif des bits d'un type signé).
            func entiers(_ combien: Int) -> [Int] {
                let taille = largeur
                guard taille > 0 else { return [] }
                return (0..<min(combien, nombre)).compactMap { k in
                    LectureBoitier.lireEntier(tiff.donnees, position + k * taille, taille, petit: tiff.petit).map(Int.init)
                }
            }

            /// Les premières valeurs relues en signé selon leur largeur, quel que soit le type
            /// rangé : sans elles, ShadowTone −16 rangé en LONG se lit 4294967280.
            func signes(_ combien: Int) -> [Int] {
                let taille = largeur
                return entiers(combien).map { valeur in
                    switch taille {
                    case 1: return Int(Int8(truncatingIfNeeded: valeur))
                    case 2: return Int(Int16(truncatingIfNeeded: valeur))
                    default: return Int(Int32(truncatingIfNeeded: valeur))
                    }
                }
            }

            var signe: Int? { signes(1).first }

            /// Les `octets` premiers octets de la valeur en un entier sans signe, quel que soit le
            /// type rangé : exiftool lit ainsi les réglages groupés de Fujifilm en données binaires
            /// (FocusSettings et DriveSettings en int32u, PrioritySettings en int16u), rangés en
            /// LONG, en SHORT ou en octets indéfinis selon l'appareil. Nil si la valeur est plus
            /// courte.
            func mot(_ octets: Int) -> Int? {
                guard nombre * (Tiff.tailles[type] ?? 1) >= octets,
                      let valeur = LectureBoitier.lireEntier(tiff.donnees, position, octets, petit: tiff.petit) else { return nil }
                return Int(valeur)
            }

            /// Les 4 premiers octets de la valeur en entier signé (int32s), quel que soit le type
            /// rangé, comme exiftool lit les tons de Fujifilm (Format int32s) ; une valeur de moins
            /// de 4 octets se relit par `signe`.
            var signe32: Int? {
                guard largeur > 0 else { return nil }
                guard nombre * largeur >= 4,
                      let valeur = LectureBoitier.lireEntier(tiff.donnees, position, 4, petit: tiff.petit) else { return signe }
                return Int(Int32(truncatingIfNeeded: valeur))
            }

            /// La première valeur d'un rationnel (types 5 et 10), nil si le dénominateur vaut 0. Les
            /// deux termes d'un SRATIONAL (10) sont signés ; `signe` force cette lecture pour un
            /// RATIONAL (5), comme exiftool pour la compensation d'exposition.
            func rationnel(signe forcer: Bool = false) -> Double? {
                guard type == 5 || type == 10, nombre >= 1,
                      let numerateur = LectureBoitier.lireEntier(tiff.donnees, position, 4, petit: tiff.petit),
                      let denominateur = LectureBoitier.lireEntier(tiff.donnees, position + 4, 4, petit: tiff.petit) else { return nil }
                let signes = type == 10 || forcer
                let n = signes ? Double(Int32(truncatingIfNeeded: numerateur)) : Double(numerateur)
                let d = signes ? Double(Int32(truncatingIfNeeded: denominateur)) : Double(denominateur)
                guard d != 0 else { return nil }
                return n / d
            }
        }

        let donnees: Data
        let petit: Bool

        init(donnees: Data, petit: Bool) {
            self.donnees = donnees
            self.petit = petit
        }

        init?(_ donnees: Data) {
            guard donnees.count >= 8 else { return nil }
            let entete = [UInt8](donnees.prefix(4))
            if entete == [0x49, 0x49, 0x2A, 0x00] { petit = true }
            else if entete == [0x4D, 0x4D, 0x00, 0x2A] { petit = false }
            else { return nil }
            self.donnees = donnees
        }

        var premierIFD: Int { Int(LectureBoitier.lireEntier(donnees, 4, 4, petit: petit) ?? 0) }

        func ifd(at position: Int) -> [Int: Entree]? {
            guard position > 0, let nombre = LectureBoitier.lireEntier(donnees, position, 2, petit: petit), nombre < 1000 else { return nil }
            var entrees: [Int: Entree] = [:]
            for k in 0..<Int(nombre) {
                let p = position + 2 + 12 * k
                guard let tag = LectureBoitier.lireEntier(donnees, p, 2, petit: petit),
                      let type = LectureBoitier.lireEntier(donnees, p + 2, 2, petit: petit),
                      let compte = LectureBoitier.lireEntier(donnees, p + 4, 4, petit: petit) else { break }
                let taille = Self.tailles[Int(type)] ?? 1
                let enLigne = Int(compte) * taille <= 4
                let valeur = enLigne ? p + 8 : Int(LectureBoitier.lireEntier(donnees, p + 8, 4, petit: petit) ?? 0)
                entrees[Int(tag)] = Entree(type: Int(type), nombre: Int(compte), position: valeur, tiff: self)
            }
            return entrees
        }
    }
}

/// Lecture des originaux bornée dans le temps (point AF et intention, une seule ouverture). Constaté
/// en 2.3 : le serveur lancé par Claude Desktop ouvrait un original du volume externe « Photos » et
/// open() attendait que l'utilisateur réponde à la demande d'autorisation de macOS (accès aux
/// fichiers d'un volume) : tout le tri restait à « 0 sur 130 », et la file des outils derrière lui.
/// Un original qui ne s'ouvre pas dans le délai est sauté, et les suivants aussi tant que sa lecture
/// n'a pas fini (un seul fil bloqué à la fois) ; quand elle finit (l'utilisateur a répondu), la
/// lecture reprend.
public final class LecteurBoitier {
    let delai: TimeInterval
    let lecture: (URL) -> LectureBoitier?
    private let verrou = NSLock()
    private var bloqueSur: URL?

    public init(delai: TimeInterval = 2, lecture: @escaping (URL) -> LectureBoitier? = LectureBoitier.lire) {
        self.delai = delai
        self.lecture = lecture
    }

    /// Le premier original qui ne s'est pas ouvert à temps, s'il y en a un.
    public var bloque: URL? {
        verrou.lock(); defer { verrou.unlock() }
        return bloqueSur
    }

    public func lire(_ fichier: URL) -> LectureBoitier? {
        if bloque != nil { return nil }
        final class Boite: @unchecked Sendable {
            let verrou = NSLock()
            var lecture: LectureBoitier?
            var finie = false
        }
        let boite = Boite()
        let fini = DispatchSemaphore(value: 0)
        let lecture = self.lecture
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let lue = lecture(fichier)
            boite.verrou.lock(); boite.lecture = lue; boite.finie = true; boite.verrou.unlock()
            fini.signal()
            // Une lecture finie après le délai débloque la suite.
            guard let self else { return }
            self.verrou.lock()
            if self.bloqueSur == fichier { self.bloqueSur = nil }
            self.verrou.unlock()
        }
        _ = fini.wait(timeout: .now() + delai)
        boite.verrou.lock(); defer { boite.verrou.unlock() }
        if !boite.finie {
            verrou.lock()
            if bloqueSur == nil { bloqueSur = fichier }
            verrou.unlock()
        }
        return boite.lecture
    }
}
