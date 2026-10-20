import CoreGraphics
import Foundation

/// Recalage de la géométrie. Lightroom range les positions des masques, des taches et des yeux
/// rouges dans l'image d'origine, avant la correction de profil d'objectif, Upright et la
/// perspective (constaté dans Lightroom Classic 15.6 : jusqu'à 26 px au bord d'un RAW de 6240 px,
/// XF16-55 à 20 mm, 0 px une fois le profil coupé), alors que Claude les donne dans l'image
/// corrigée que montre view_photo. Deux rendus sans recadrage, l'un tel quel, l'autre sans ces
/// corrections, donnent la correspondance : corrélation de petites zones, du grossier au fin,
/// puis un modèle physique ajusté sur les zones fiables (homographie pour Upright et la
/// perspective, puis distorsion radiale autour du centre pour le profil d'objectif). Le module
/// reçoit le modèle évalué sur une grille et l'interpole (Geometrie.lua).
public enum Recalage {
    /// Grille posée sur l'image corrigée (affichée, non recadrée) : pour chaque nœud, la position
    /// correspondante dans l'image d'origine, en fractions (0 à 1 depuis le coin haut gauche).
    public struct Grille: Equatable {
        public let colonnes: Int
        public let lignes: Int
        /// Nœuds ligne par ligne depuis le haut ; le nœud (i, j) est en (i / (colonnes − 1), j / (lignes − 1)).
        public let x: [Double]
        public let y: [Double]

        /// Interpolation bilinéaire, comme le module.
        public func point(_ u: Double, _ v: Double) -> (x: Double, y: Double) {
            let fu = min(max(u, 0), 1) * Double(colonnes - 1), fv = min(max(v, 0), 1) * Double(lignes - 1)
            let i = min(Int(fu), colonnes - 2), j = min(Int(fv), lignes - 2)
            let a = fu - Double(i), b = fv - Double(j)
            func valeur(_ t: [Double]) -> Double {
                let k = j * colonnes + i
                return t[k] * (1 - a) * (1 - b) + t[k + 1] * a * (1 - b) + t[k + colonnes] * (1 - a) * b + t[k + colonnes + 1] * a * b
            }
            return (valeur(x), valeur(y))
        }

        public var json: JSONValue {
            func arrondi(_ t: [Double]) -> JSONValue { .array(t.map { .number(($0 * 1_000_000).rounded() / 1_000_000) }) }
            return ["colonnes": .number(Double(colonnes)), "lignes": .number(Double(lignes)), "x": arrondi(x), "y": arrondi(y)]
        }
    }

    public struct Resultat {
        public let grille: Grille
        public let zonesFiables: Int
        public let zonesEssayees: Int
        /// Plus grand déplacement entre l'image corrigée et l'image d'origine, en part de la largeur.
        public let ecartMax: Double
        /// Écart moyen entre le modèle et les zones fiables, en part de la largeur.
        public let residu: Double
        /// Plus grand écart entre le modèle et une zone fiable, et le plus grand près d'un bord
        /// (à moins de 12 % de la largeur ou de la hauteur), en part de la largeur : là que la
        /// perspective laisse le plus d'erreur (`--recalage`).
        public var residuMax = 0.0
        public var residuBords = 0.0
    }

    static let colonnes = 17, lignes = 12

    /// Correspondance entre l'image corrigée et l'image d'origine (mêmes cadrage et orientation,
    /// sans recadrage) ; nil si l'image est trop uniforme pour la trouver.
    public static func calculer(corrigee: CGImage, origine: CGImage) -> Resultat? {
        guard let fT = Plan(corrigee, largeurMax: 2048), let fO = Plan(origine, largeurMax: 2048) else { return nil }
        let mT = fT.reduit(2), mO = fO.reduit(2)
        let gT = mT.reduit(4), gO = mO.reduit(4)

        // 1. Grossier, grande recherche : de quoi estimer une homographie (Upright déplace beaucoup).
        var grossiers: [(Point, Point)] = []
        for (u, v) in noeuds(9, 6, marge: 0.08) {
            let p = Point(u * Double(gT.largeur), v * Double(gT.hauteur))
            let attendu = Point(u * Double(gO.largeur), v * Double(gO.hauteur))
            if let q = correler(gT, p, demi: 6, gO, attendu, rayon: Int(0.15 * Double(gO.largeur)), seuil: 0.6, distinct: true) {
                grossiers.append((p, q))
            }
        }
        let echelleG = (Double(gO.largeur) / Double(gT.largeur), Double(gO.hauteur) / Double(gT.hauteur))
        let apriori = Homographie.ajuster(grossiers, robuste: 3) ?? Homographie.echelle(echelleG.0, echelleG.1)

        // 2. Moyen, puis 3. fin avec une position au dixième de pixel.
        var paires: [(Point, Point)] = []
        let noeudsFins = noeuds(colonnes, lignes, marge: 0.03)
        for (u, v) in noeudsFins {
            let pg = Point(u * Double(gT.largeur), v * Double(gT.hauteur))
            let qg = apriori.appliquer(pg)
            let facteur = Double(mT.largeur) / Double(gT.largeur)
            let pm = Point(u * Double(mT.largeur), v * Double(mT.hauteur))
            guard let qm = correler(mT, pm, demi: 10, mO, Point(qg.x * facteur, qg.y * facteur), rayon: 10, seuil: 0.7, distinct: false)
            else { continue }
            let pf = Point(u * Double(fT.largeur), v * Double(fT.hauteur))
            guard let qf = correler(fT, pf, demi: 12, fO, Point(qm.x * 2, qm.y * 2), rayon: 3, seuil: 0.8, distinct: false)
            else { continue }
            paires.append((pf, qf))
        }

        // 4. Modèle physique, ajusté sans les zones aberrantes.
        guard let modele = Modele.ajuster(paires, tailleT: (fT.largeur, fT.hauteur), tailleO: (fO.largeur, fO.hauteur)) else { return nil }
        var gx: [Double] = [], gy: [Double] = []
        var ecartMax = 0.0
        for j in 0..<lignes {
            for i in 0..<colonnes {
                let u = Double(i) / Double(colonnes - 1), v = Double(j) / Double(lignes - 1)
                let q = modele.appliquer(Point(u * Double(fT.largeur), v * Double(fT.hauteur)))
                let x = q.x / Double(fO.largeur), y = q.y / Double(fO.hauteur)
                gx.append(x)
                gy.append(y)
                ecartMax = max(ecartMax, hypot(x - u, (y - v) * Double(fO.hauteur) / Double(fO.largeur)))
            }
        }
        var resultat = Resultat(grille: Grille(colonnes: colonnes, lignes: lignes, x: gx, y: gy), zonesFiables: modele.points,
                                zonesEssayees: noeudsFins.count, ecartMax: ecartMax, residu: modele.residu / Double(fO.largeur))
        for (p, q) in paires {
            let erreur = distance(modele.appliquer(p), q)
            // Les zones aberrantes écartées par l'ajustement ne comptent pas.
            guard erreur <= max(1.0, 3 * modele.residu) else { continue }
            resultat.residuMax = max(resultat.residuMax, erreur / Double(fO.largeur))
            let u = p.x / Double(fT.largeur), v = p.y / Double(fT.hauteur)
            if min(u, 1 - u) < 0.12 || min(v, 1 - v) < 0.12 {
                resultat.residuBords = max(resultat.residuBords, erreur / Double(fO.largeur))
            }
        }
        return resultat
    }

    static func noeuds(_ n: Int, _ m: Int, marge: Double) -> [(Double, Double)] {
        var liste: [(Double, Double)] = []
        for j in 0..<m {
            for i in 0..<n {
                liste.append((marge + (1 - 2 * marge) * Double(i) / Double(n - 1), marge + (1 - 2 * marge) * Double(j) / Double(m - 1)))
            }
        }
        return liste
    }

    // MARK: Images en niveaux de gris

    struct Point: Equatable {
        var x: Double, y: Double
        init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    }

    struct Plan {
        let largeur: Int, hauteur: Int
        var pixels: [Float]

        init(largeur: Int, hauteur: Int, pixels: [Float]) {
            self.largeur = largeur; self.hauteur = hauteur; self.pixels = pixels
        }

        /// Luminance de l'image, réduite à `largeurMax` pixels de large au plus.
        init?(_ image: CGImage, largeurMax: Int) {
            let facteur = min(1, Double(largeurMax) / Double(image.width))
            let w = max(8, Int((Double(image.width) * facteur).rounded())), h = max(8, Int((Double(image.height) * facteur).rounded()))
            var octets = [UInt8](repeating: 0, count: w * h)
            let ok = octets.withUnsafeMutableBytes { tampon -> Bool in
                guard let contexte = CGContext(data: tampon.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                contexte.interpolationQuality = .high
                contexte.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            self.init(largeur: w, hauteur: h, pixels: octets.map(Float.init))
        }

        /// Réduction par moyenne de blocs de `f` × `f` pixels.
        func reduit(_ f: Int) -> Plan {
            let w = max(1, largeur / f), h = max(1, hauteur / f)
            var sortie = [Float](repeating: 0, count: w * h)
            for y in 0..<h {
                for x in 0..<w {
                    var somme: Float = 0
                    for dy in 0..<f {
                        let base = (y * f + dy) * largeur + x * f
                        for dx in 0..<f { somme += pixels[base + dx] }
                    }
                    sortie[y * w + x] = somme / Float(f * f)
                }
            }
            return Plan(largeur: w, hauteur: h, pixels: sortie)
        }
    }

    /// Position dans `cible` qui ressemble le plus à la zone de `source` centrée en `p` (gabarit de
    /// 2 × demi + 1 pixels), cherchée à ± rayon autour de `attendu` ; corrélation normalisée, au
    /// dixième de pixel par une parabole. Nil pour une zone trop uniforme, une ressemblance sous
    /// le seuil, ou (distinct) un motif répété qui ressemble autant ailleurs.
    static func correler(_ source: Plan, _ p: Point, demi: Int, _ cible: Plan, _ attendu: Point, rayon: Int,
                         seuil: Double, distinct: Bool) -> Point? {
        let sx = Int(p.x.rounded()), sy = Int(p.y.rounded())
        guard sx - demi >= 0, sy - demi >= 0, sx + demi < source.largeur, sy + demi < source.hauteur else { return nil }
        let cote = 2 * demi + 1, n = cote * cote
        var gabarit = [Float](repeating: 0, count: n)
        var moyenne: Float = 0
        for dy in 0..<cote {
            for dx in 0..<cote {
                let v = source.pixels[(sy - demi + dy) * source.largeur + sx - demi + dx]
                gabarit[dy * cote + dx] = v
                moyenne += v
            }
        }
        moyenne /= Float(n)
        var energie: Float = 0
        for k in 0..<n { gabarit[k] -= moyenne; energie += gabarit[k] * gabarit[k] }
        // Écart type sous 3 niveaux sur 255 : ciel, mur uni… rien à quoi s'accrocher.
        guard energie / Float(n) > 9 else { return nil }

        let cx = Int(attendu.x.rounded()), cy = Int(attendu.y.rounded())
        let xmin = max(demi, cx - rayon), xmax = min(cible.largeur - 1 - demi, cx + rayon)
        let ymin = max(demi, cy - rayon), ymax = min(cible.hauteur - 1 - demi, cy + rayon)
        guard xmin <= xmax, ymin <= ymax else { return nil }
        let lw = xmax - xmin + 1
        var scores = [Double](repeating: -2, count: lw * (ymax - ymin + 1))
        var meilleur = (score: -2.0, x: 0, y: 0)
        cible.pixels.withUnsafeBufferPointer { c in
            gabarit.withUnsafeBufferPointer { g in
                for y in ymin...ymax {
                    for x in xmin...xmax {
                        var somme: Float = 0, somme2: Float = 0, croise: Float = 0
                        for dy in 0..<cote {
                            let base = (y - demi + dy) * cible.largeur + x - demi
                            let gb = dy * cote
                            for dx in 0..<cote {
                                let v = c[base + dx]
                                somme += v; somme2 += v * v; croise += v * g[gb + dx]
                            }
                        }
                        let variance = somme2 - somme * somme / Float(n)
                        guard variance > 1e-3 else { continue }
                        let score = Double(croise) / (Double(energie).squareRoot() * Double(variance).squareRoot())
                        scores[(y - ymin) * lw + x - xmin] = score
                        if score > meilleur.score { meilleur = (score, x, y) }
                    }
                }
            }
        }
        guard meilleur.score >= seuil else { return nil }
        if distinct {
            var second = -2.0
            for y in ymin...ymax {
                for x in xmin...xmax where abs(x - meilleur.x) > 2 || abs(y - meilleur.y) > 2 {
                    second = max(second, scores[(y - ymin) * lw + x - xmin])
                }
            }
            guard second < meilleur.score - 0.05 else { return nil }
        }
        func score(_ x: Int, _ y: Int) -> Double? {
            guard x >= xmin, x <= xmax, y >= ymin, y <= ymax else { return nil }
            let s = scores[(y - ymin) * lw + x - xmin]
            return s > -2 ? s : nil
        }
        func sommet(_ a: Double?, _ b: Double, _ c: Double?) -> Double {
            guard let a, let c else { return 0 }
            let d = a - 2 * b + c
            return d < 0 ? min(max(0.5 * (a - c) / d, -0.5), 0.5) : 0
        }
        let fx = sommet(score(meilleur.x - 1, meilleur.y), meilleur.score, score(meilleur.x + 1, meilleur.y))
        let fy = sommet(score(meilleur.x, meilleur.y - 1), meilleur.score, score(meilleur.x, meilleur.y + 1))
        return Point(Double(meilleur.x) + fx + (p.x - Double(sx)), Double(meilleur.y) + fy + (p.y - Double(sy)))
    }

    // MARK: Modèle

    /// Homographie (8 coefficients, le neuvième vaut 1).
    struct Homographie {
        var h: [Double]

        static func echelle(_ sx: Double, _ sy: Double) -> Homographie { Homographie(h: [sx, 0, 0, 0, sy, 0, 0, 0]) }
        static let identite = echelle(1, 1)

        func appliquer(_ p: Point) -> Point {
            let w = h[6] * p.x + h[7] * p.y + 1
            return Point((h[0] * p.x + h[1] * p.y + h[2]) / w, (h[3] * p.x + h[4] * p.y + h[5]) / w)
        }

        /// Moindres carrés sur des points normalisés (centrés, écart moyen √2) ; `robuste` : un
        /// second ajustement sans les paires à plus de ce nombre de pixels.
        static func ajuster(_ paires: [(Point, Point)], robuste: Double? = nil) -> Homographie? {
            guard paires.count >= 6, var resultat = ajusterTout(paires) else { return nil }
            if let robuste {
                let retenues = paires.filter { distance(resultat.appliquer($0.0), $0.1) <= robuste }
                if retenues.count >= 6, retenues.count < paires.count, let mieux = ajusterTout(retenues) { resultat = mieux }
            }
            return resultat
        }

        private static func ajusterTout(_ paires: [(Point, Point)]) -> Homographie? {
            func normalisation(_ points: [Point]) -> (cx: Double, cy: Double, s: Double) {
                let cx = points.map(\.x).reduce(0, +) / Double(points.count), cy = points.map(\.y).reduce(0, +) / Double(points.count)
                let moyenne = points.map { hypot($0.x - cx, $0.y - cy) }.reduce(0, +) / Double(points.count)
                return (cx, cy, moyenne > 0 ? 2.0.squareRoot() / moyenne : 1)
            }
            let na = normalisation(paires.map(\.0)), nb = normalisation(paires.map(\.1))
            var ata = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
            var atb = [Double](repeating: 0, count: 8)
            for (a, b) in paires {
                let x = (a.x - na.cx) * na.s, y = (a.y - na.cy) * na.s
                let u = (b.x - nb.cx) * nb.s, v = (b.y - nb.cy) * nb.s
                for (ligne, cible) in [([x, y, 1, 0, 0, 0, -u * x, -u * y], u), ([0, 0, 0, x, y, 1, -v * x, -v * y], v)] {
                    for i in 0..<8 {
                        atb[i] += ligne[i] * cible
                        for j in 0..<8 { ata[i][j] += ligne[i] * ligne[j] }
                    }
                }
            }
            guard let k = resoudre(ata, atb) else { return nil }
            // Retour des repères normalisés : H = Nb⁻¹ · K · Na.
            let K = [[k[0], k[1], k[2]], [k[3], k[4], k[5]], [k[6], k[7], 1]]
            let Na = [[na.s, 0, -na.s * na.cx], [0, na.s, -na.s * na.cy], [0, 0, 1]]
            let NbInv = [[1 / nb.s, 0, nb.cx], [0, 1 / nb.s, nb.cy], [0, 0, 1]]
            let H = produit(NbInv, produit(K, Na))
            guard abs(H[2][2]) > 1e-12 else { return nil }
            return Homographie(h: [H[0][0], H[0][1], H[0][2], H[1][0], H[1][1], H[1][2], H[2][0], H[2][1]].map { $0 / H[2][2] })
        }
    }

    /// Homographie puis distorsion radiale autour du centre de l'image d'origine, en coordonnées
    /// normalisées (origine au centre, unité : le demi-grand côté) : Q = H(P) · (1 + k1 r² + k2 r⁴).
    struct Modele {
        var h: [Double]                 // homographie normalisée (8 coefficients)
        var k1 = 0.0, k2 = 0.0
        let centreT: Point, uniteT: Double
        let centreO: Point, uniteO: Double
        var points = 0
        var residu = 0.0

        init(tailleT: (Int, Int), tailleO: (Int, Int)) {
            h = Homographie.identite.h
            centreT = Point(Double(tailleT.0) / 2, Double(tailleT.1) / 2); uniteT = Double(max(tailleT.0, tailleT.1)) / 2
            centreO = Point(Double(tailleO.0) / 2, Double(tailleO.1) / 2); uniteO = Double(max(tailleO.0, tailleO.1)) / 2
        }

        func versT(_ p: Point) -> Point { Point((p.x - centreT.x) / uniteT, (p.y - centreT.y) / uniteT) }
        func versO(_ q: Point) -> Point { Point((q.x - centreO.x) / uniteO, (q.y - centreO.y) / uniteO) }

        static func normalise(_ h: [Double], _ k1: Double, _ k2: Double, _ p: Point) -> Point {
            let y = Homographie(h: h).appliquer(p)
            let r2 = y.x * y.x + y.y * y.y
            let f = 1 + k1 * r2 + k2 * r2 * r2
            return Point(y.x * f, y.y * f)
        }

        func appliquer(_ p: Point) -> Point {
            let q = Self.normalise(h, k1, k2, versT(p))
            return Point(centreO.x + q.x * uniteO, centreO.y + q.y * uniteO)
        }

        /// Ajustement conjoint (Levenberg-Marquardt), deux fois sans les zones aberrantes. Nil sous
        /// 8 zones fiables.
        static func ajuster(_ paires: [(Point, Point)], tailleT: (Int, Int), tailleO: (Int, Int)) -> Modele? {
            guard paires.count >= 8 else { return nil }
            var retenues = paires
            var modele: Modele?
            for _ in 0..<3 {
                guard retenues.count >= 8, let m = ajusterTout(retenues, tailleT: tailleT, tailleO: tailleO) else { break }
                modele = m
                let erreurs = retenues.map { distance(m.appliquer($0.0), $0.1) }
                let mediane = erreurs.sorted()[erreurs.count / 2]
                let limite = max(1.0, 3 * mediane)
                let suivantes = zip(retenues, erreurs).filter { $0.1 <= limite }.map(\.0)
                if suivantes.count == retenues.count { break }
                retenues = suivantes
            }
            guard var resultat = modele else { return nil }
            let erreurs = retenues.map { distance(resultat.appliquer($0.0), $0.1) }
            resultat.points = retenues.count
            resultat.residu = erreurs.reduce(0, +) / Double(max(1, erreurs.count))
            return resultat
        }

        private static func ajusterTout(_ paires: [(Point, Point)], tailleT: (Int, Int), tailleO: (Int, Int)) -> Modele? {
            var modele = Modele(tailleT: tailleT, tailleO: tailleO)
            let normales = paires.map { (modele.versT($0.0), modele.versO($0.1)) }
            guard let depart = Homographie.ajuster(normales) else { return nil }
            // k2 seulement si les zones vont assez loin du centre pour le distinguer de k1.
            let avecK2 = (normales.map { hypot($0.1.x, $0.1.y) }.max() ?? 0) > 0.6
            var theta = depart.h + [0.0] + (avecK2 ? [0.0] : [])
            func residus(_ t: [Double]) -> [Double] {
                var r: [Double] = []
                r.reserveCapacity(2 * normales.count)
                for (p, q) in normales {
                    let y = normalise(Array(t[0..<8]), t[8], avecK2 ? t[9] : 0, p)
                    r.append(y.x - q.x); r.append(y.y - q.y)
                }
                return r
            }
            func cout(_ r: [Double]) -> Double { r.reduce(0) { $0 + $1 * $1 } }
            var r = residus(theta)
            var c = cout(r)
            var lambda = 1e-3
            let n = theta.count
            for _ in 0..<40 {
                // Jacobien par différences finies.
                var colonnes: [[Double]] = []
                for k in 0..<n {
                    var t = theta
                    let pas = 1e-7 * max(1, abs(t[k]))
                    t[k] += pas
                    colonnes.append(zip(residus(t), r).map { ($0 - $1) / pas })
                }
                var jtj = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
                var jtr = [Double](repeating: 0, count: n)
                for a in 0..<n {
                    for b in a..<n {
                        let v = zip(colonnes[a], colonnes[b]).reduce(0) { $0 + $1.0 * $1.1 }
                        jtj[a][b] = v; jtj[b][a] = v
                    }
                    jtr[a] = -zip(colonnes[a], r).reduce(0) { $0 + $1.0 * $1.1 }
                }
                var amelioree = false
                for _ in 0..<8 {
                    var amortie = jtj
                    for a in 0..<n { amortie[a][a] += lambda * max(jtj[a][a], 1e-12) }
                    guard let delta = resoudre(amortie, jtr) else { lambda *= 10; continue }
                    let essai = zip(theta, delta).map { $0 + $1 }
                    let rEssai = residus(essai)
                    let cEssai = cout(rEssai)
                    if cEssai < c {
                        let gain = c - cEssai
                        theta = essai; r = rEssai; c = cEssai
                        lambda = max(lambda / 3, 1e-9)
                        amelioree = gain > 1e-14 * max(c, 1e-30)
                        break
                    }
                    lambda *= 10
                }
                if !amelioree { break }
            }
            modele.h = Array(theta[0..<8])
            modele.k1 = theta[8]
            modele.k2 = avecK2 ? theta[9] : 0
            return modele
        }
    }

    static func distance(_ a: Point, _ b: Point) -> Double { hypot(a.x - b.x, a.y - b.y) }

    static func produit(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        (0..<3).map { i in (0..<3).map { j in (0..<3).reduce(0) { $0 + a[i][$1] * b[$1][j] } } }
    }

    /// Système linéaire carré, par élimination de Gauss avec pivot ; nil s'il est singulier.
    static func resoudre(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = a, v = b
        for colonne in 0..<n {
            guard let pivot = (colonne..<n).max(by: { abs(m[$0][colonne]) < abs(m[$1][colonne]) }),
                  abs(m[pivot][colonne]) > 1e-12 else { return nil }
            m.swapAt(colonne, pivot); v.swapAt(colonne, pivot)
            for ligne in (colonne + 1)..<n {
                let f = m[ligne][colonne] / m[colonne][colonne]
                guard f != 0 else { continue }
                for k in colonne..<n { m[ligne][k] -= f * m[colonne][k] }
                v[ligne] -= f * v[colonne]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for ligne in stride(from: n - 1, through: 0, by: -1) {
            var s = v[ligne]
            for k in (ligne + 1)..<n { s -= m[ligne][k] * x[k] }
            x[ligne] = s / m[ligne][ligne]
        }
        return x
    }
}
