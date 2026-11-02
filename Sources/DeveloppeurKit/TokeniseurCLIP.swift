import Foundation

/// Le tokeniseur BPE de CLIP (recherche par le sens, 1.6), écrit ici pour garder le paquet sans
/// dépendance : celui de `simple_tokenizer.py` d'openai/CLIP (licence MIT), que l'encodeur de texte
/// de MobileCLIP S2 attend (77 jetons : début 49406, les jetons, fin 49407, puis des zéros ; trop
/// long, coupé à 76 et fini par 49407, comme open_clip). Le texte se nettoie comme chez CLIP, sans
/// ftfy : forme NFC, entités HTML (deux fois), espaces réduits, minuscules.
///
/// Le vocabulaire est `bpe_simple_vocab_16e6.txt.gz` (Resources/clip dans le dépôt, copié dans
/// `Developpeur/Modeles/` par l'installation). Vérifié par `TokeniseurCLIPTests` contre
/// Tests/Contrats/jetons-clip.json (une seconde implémentation, en Python). À constater : que
/// l'encodeur de texte CoreML nourri de ces jetons rend, à 0,999 près, les vecteurs d'open_clip
/// (`--preparer-sens` dit les jetons et les vecteurs ; la comparaison avec open_clip se fait à part).
public final class TokeniseurCLIP {
    public static let longueur = 77
    public static let debut: Int32 = 49406
    public static let fin: Int32 = 49407
    /// Le nombre de fusions lues dans le vocabulaire (49 152 − 256 − 2), comme CLIP.
    static let fusions = 49152 - 256 - 2

    private let encodeur: [String: Int32]
    private let rangs: [Paire: Int]
    private let octets: [Character]
    private var cache: [String: [Int32]] = [:]
    private let verrou = NSLock()
    private let motif: NSRegularExpression

    struct Paire: Hashable {
        var a: String
        var b: String
    }

    public enum Erreur: Error, LocalizedError {
        case illisible(String)
        public var errorDescription: String? {
            switch self {
            case .illisible(let detail): return "Vocabulaire de CLIP illisible : \(detail)"
            }
        }
    }

    /// Lit le vocabulaire (le .gz de CLIP, ou le texte déjà décompressé).
    public convenience init(vocabulaire url: URL) throws {
        let donnees = try Data(contentsOf: url)
        let texte: String
        if donnees.starts(with: [0x1f, 0x8b]) {
            guard let brut = Self.gunzip(donnees), let lu = String(data: brut, encoding: .utf8) else {
                throw Erreur.illisible("\(url.lastPathComponent) ne se décompresse pas.")
            }
            texte = lu
        } else {
            guard let lu = String(data: donnees, encoding: .utf8) else { throw Erreur.illisible("\(url.lastPathComponent) n'est pas du texte.") }
            texte = lu
        }
        try self.init(texte: texte)
    }

    /// D'après le texte du vocabulaire : une ligne d'en-tête, puis une fusion « a b » par ligne.
    public init(texte: String) throws {
        let lignes = texte.split(separator: "\n", omittingEmptySubsequences: false)
        guard lignes.count > Self.fusions else {
            throw Erreur.illisible("\(lignes.count) lignes, il en faut \(Self.fusions + 1) au moins.")
        }
        let octets = Self.octetsVersUnicode()
        // Le vocabulaire range les caractères dans l'ordre de bytes_to_unicode (les octets visibles
        // d'abord), pas dans l'ordre des octets.
        let ordre = Self.ordreDesOctets().map { octets[$0] }
        var vocabulaire = ordre.map { String($0) }
        vocabulaire += ordre.map { String($0) + "</w>" }
        var rangs: [Paire: Int] = [:]
        rangs.reserveCapacity(Self.fusions)
        for (rang, ligne) in lignes[1...Self.fusions].enumerated() {
            let morceaux = ligne.split(separator: " ")
            guard morceaux.count == 2 else { throw Erreur.illisible("fusion \(rang + 1) : « \(ligne) ».") }
            let paire = Paire(a: String(morceaux[0]), b: String(morceaux[1]))
            rangs[paire] = rang
            vocabulaire.append(paire.a + paire.b)
        }
        vocabulaire += ["<|startoftext|>", "<|endoftext|>"]
        var encodeur: [String: Int32] = [:]
        encodeur.reserveCapacity(vocabulaire.count)
        for (i, jeton) in vocabulaire.enumerated() { encodeur[jeton] = Int32(i) }
        self.encodeur = encodeur
        self.rangs = rangs
        self.octets = octets
        self.motif = try NSRegularExpression(
            pattern: #"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#,
            options: [.caseInsensitive])
    }

    /// Les 77 jetons d'un texte, remplis de zéros.
    public func jetons(_ texte: String) -> [Int32] {
        var liste = [Self.debut] + encoder(texte) + [Self.fin]
        if liste.count > Self.longueur {
            liste = Array(liste.prefix(Self.longueur))
            liste[Self.longueur - 1] = Self.fin
        }
        return liste + Array(repeating: 0, count: Self.longueur - liste.count)
    }

    /// Les jetons du texte, sans début ni fin.
    public func encoder(_ texte: String) -> [Int32] {
        let propre = Self.nettoyer(texte)
        let ns = propre as NSString
        var sortie: [Int32] = []
        for resultat in motif.matches(in: propre, range: NSRange(location: 0, length: ns.length)) {
            let mot = ns.substring(with: resultat.range)
            let code = String(mot.utf8.map { octets[Int($0)] })
            sortie += bpe(code)
        }
        return sortie
    }

    /// Le texte nettoyé comme chez CLIP (sans ftfy).
    static func nettoyer(_ texte: String) -> String {
        var t = texte.precomposedStringWithCanonicalMapping
        t = entites(entites(t))
        let mots = t.split(whereSeparator: { $0.isWhitespace })
        return mots.joined(separator: " ").lowercased()
    }

    /// Les entités HTML les plus courantes et les entités numériques (html.unescape de Python en
    /// connaît plus ; une demande de recherche n'en porte pas d'autres).
    static func entites(_ texte: String) -> String {
        guard texte.contains("&") else { return texte }
        var t = texte
        for (entite, valeur) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", "\u{a0}")] {
            t = t.replacingOccurrences(of: entite, with: valeur)
        }
        if let numerique = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = t as NSString
            var resultat = ""
            var position = 0
            for m in numerique.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                resultat += ns.substring(with: NSRange(location: position, length: m.range.location - position))
                let hexa = ns.substring(with: m.range(at: 1)) == "x"
                let valeur = UInt32(ns.substring(with: m.range(at: 2)), radix: hexa ? 16 : 10).flatMap(Unicode.Scalar.init)
                resultat += valeur.map { String(Character($0)) } ?? ns.substring(with: m.range)
                position = m.range.location + m.range.length
            }
            resultat += ns.substring(from: position)
            t = resultat
        }
        return t.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Les fusions de CLIP sur un mot (déjà passé en caractères d'octets), gardées en cache.
    private func bpe(_ mot: String) -> [Int32] {
        verrou.lock()
        if let connu = cache[mot] { verrou.unlock(); return connu }
        verrou.unlock()
        var morceaux = mot.map { String($0) }
        guard !morceaux.isEmpty else { return [] }
        morceaux[morceaux.count - 1] += "</w>"
        while morceaux.count > 1 {
            var meilleure: (rang: Int, paire: Paire)?
            for i in 0..<(morceaux.count - 1) {
                let paire = Paire(a: morceaux[i], b: morceaux[i + 1])
                if let rang = rangs[paire], rang < (meilleure?.rang ?? Int.max) { meilleure = (rang, paire) }
            }
            guard let fusion = meilleure?.paire else { break }
            var nouveaux: [String] = []
            var i = 0
            while i < morceaux.count {
                if i < morceaux.count - 1, morceaux[i] == fusion.a, morceaux[i + 1] == fusion.b {
                    nouveaux.append(fusion.a + fusion.b)
                    i += 2
                } else {
                    nouveaux.append(morceaux[i])
                    i += 1
                }
            }
            morceaux = nouveaux
        }
        let jetons = morceaux.compactMap { encodeur[$0] }
        verrou.lock()
        if cache.count < 10_000 { cache[mot] = jetons }
        verrou.unlock()
        return jetons
    }

    /// Les octets dans l'ordre de bytes_to_unicode de CLIP : les visibles, puis les autres.
    static func ordreDesOctets() -> [Int] {
        let visibles = Array(33...126) + Array(161...172) + Array(174...255)
        let presents = Set(visibles)
        return visibles + (0..<256).filter { !presents.contains($0) }
    }

    /// Les 256 octets vers des caractères visibles (bytes_to_unicode de CLIP), indexés par octet.
    static func octetsVersUnicode() -> [Character] {
        let ordre = ordreDesOctets()
        var table = [Character](repeating: " ", count: 256)
        for (rang, b) in ordre.enumerated() {
            let code = rang < 188 ? b : 256 + (rang - 188)
            table[b] = Character(Unicode.Scalar(UInt32(code))!)
        }
        return table
    }

    /// Décompresse un fichier gzip (en-tête RFC 1952, puis DEFLATE brut, que Foundation lit).
    static func gunzip(_ donnees: Data) -> Data? {
        let o = [UInt8](donnees)
        guard o.count > 18, o[0] == 0x1f, o[1] == 0x8b, o[2] == 8 else { return nil }
        let drapeaux = o[3]
        var i = 10
        if drapeaux & 4 != 0 {
            guard i + 2 <= o.count else { return nil }
            i += 2 + Int(o[i]) + Int(o[i + 1]) << 8
        }
        if drapeaux & 8 != 0 { while i < o.count, o[i] != 0 { i += 1 }; i += 1 }
        if drapeaux & 16 != 0 { while i < o.count, o[i] != 0 { i += 1 }; i += 1 }
        if drapeaux & 2 != 0 { i += 2 }
        guard i < o.count - 8 else { return nil }
        let corps = Data(o[i..<(o.count - 8)])
        return try? (corps as NSData).decompressed(using: .zlib) as Data
    }
}
