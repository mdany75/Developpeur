import CoreGraphics
import Foundation

/// Angle d'une ligne que Claude désigne dans l'aperçu (horizon, crête d'une chute, ligne de toit,
/// arête d'un bâtiment) : d'après ses deux points, puis affiné sur le contour de l'image le long
/// du segment, pour redresser au dixième de degré. Les détecteurs automatiques d'horizon se sont
/// montrés peu fiables (lignes de perspective, horizon flou) : Claude choisit la ligne, le
/// serveur la mesure.
public struct LineMeasurement: Equatable {
    /// Angle de la ligne en degrés, de −90 à 90 : positif quand elle monte vers la droite.
    public var pointsAngle: Double
    public var refinedAngle: Double?
    /// Points de contour retenus pour l'ajustement, et leur écart à la droite (pixels).
    public var edgePoints: Int
    public var residual: Double?

    public var angle: Double { refinedAngle ?? pointsAngle }
    public var vertical: Bool { abs(pointsAngle) > 45 }

    /// Écart à l'horizontale ou à la verticale, en degrés (positif : la ligne tourne dans le sens
    /// antihoraire par rapport à l'axe).
    public var tilt: Double {
        guard vertical else { return angle }
        return angle > 0 ? angle - 90 : angle + 90
    }

    /// Rotation à ajouter à l'angle de recadrage pour mettre la ligne d'aplomb (positif :
    /// sens antihoraire, comme crop.angle).
    public var correction: Double { -tilt }
}

public enum LineAngle {
    /// Mesure la ligne de `from` à `to` (fractions de l'image, depuis le coin haut gauche).
    public static func measure(_ data: Data, from: CGPoint, to: CGPoint) -> LineMeasurement? {
        guard let image = PreviewImages.image(data), let (w, h, v) = Detail.luminance(image) else { return nil }
        return measure(luminance: v, width: w, height: h, from: from, to: to)
    }

    static func measure(luminance v: [Float], width w: Int, height h: Int, from: CGPoint, to: CGPoint) -> LineMeasurement? {
        var a = CGPoint(x: from.x * Double(w), y: from.y * Double(h))
        var b = CGPoint(x: to.x * Double(w), y: to.y * Double(h))
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length >= 20 else { return nil }
        if b.x < a.x { swap(&a, &b) }
        // Repère image : y vers le bas ; une ligne qui monte vers la droite a un angle positif.
        let pointsAngle = atan2(a.y - b.y, b.x - a.x) * 180 / .pi
        let measurement = LineMeasurement(pointsAngle: pointsAngle, refinedAngle: nil, edgePoints: 0, residual: nil)
        let horizontal = !measurement.vertical
        if !horizontal, b.y < a.y { swap(&a, &b) }

        // Le long du segment, pour chaque colonne (ligne presque horizontale) ou chaque rangée
        // (presque verticale) : le contour le plus marqué dans une bande autour du segment.
        let band = max(4.0, 0.012 * hypot(Double(w), Double(h)))
        var samples: [(along: Double, across: Double)] = []
        let start = horizontal ? Int(a.x.rounded(.up)) : Int(a.y.rounded(.up))
        let end = horizontal ? Int(b.x) : Int(b.y)
        guard end - start >= 10 else { return measurement }
        for t in start...end {
            let fraction = Double(t - start) / Double(max(1, end - start))
            let center = horizontal ? a.y + (b.y - a.y) * fraction : a.x + (b.x - a.x) * fraction
            let low = max(2, Int((center - band).rounded(.down))), high = Int((center + band).rounded(.up))
            let limit = horizontal ? h - 3 : w - 3
            guard high <= limit, low < high, t >= 2, t <= (horizontal ? w - 3 : h - 3) else { continue }
            var best = 0.0, bestIndex = -1
            var magnitudes: [Double] = []
            for s in low...high {
                // Gradient perpendiculaire à la ligne, lissé sur trois pixels le long d'elle.
                func value(_ along: Int, _ across: Int) -> Double {
                    Double(horizontal ? v[across * w + along] : v[along * w + across])
                }
                var g = 0.0
                for k in -1...1 { g += value(t + k, s + 1) - value(t + k, s - 1) }
                let m = abs(g)
                magnitudes.append(m)
                if m > best { best = m; bestIndex = s }
            }
            guard bestIndex > low, bestIndex < high, best >= 12 else { continue }
            // Position au sous-pixel par une parabole sur les trois valeurs autour du maximum.
            let i = bestIndex - low
            let left = magnitudes[i - 1], right = magnitudes[i + 1]
            let denominator = left - 2 * best + right
            let offset = denominator == 0 ? 0 : 0.5 * (left - right) / denominator
            samples.append((Double(t), Double(bestIndex) + offset))
        }
        guard samples.count >= 12 else { return measurement }

        // Droite des moindres carrés, deux fois, en écartant les points trop loin (bruit,
        // autres contours croisés).
        var kept = samples
        var slope = 0.0, residual = 0.0
        for _ in 0..<3 {
            let n = Double(kept.count)
            let meanX = kept.map(\.along).reduce(0, +) / n, meanY = kept.map(\.across).reduce(0, +) / n
            var sxx = 0.0, sxy = 0.0
            for p in kept { sxx += (p.along - meanX) * (p.along - meanX); sxy += (p.along - meanX) * (p.across - meanY) }
            guard sxx > 0 else { return measurement }
            slope = sxy / sxx
            let intercept = meanY - slope * meanX
            let residuals = kept.map { abs($0.across - (slope * $0.along + intercept)) }
            let sorted = residuals.sorted()
            let median = sorted[sorted.count / 2]
            residual = (residuals.map { $0 * $0 }.reduce(0, +) / n).squareRoot()
            let cut = max(1.0, 3 * median)
            let next = zip(kept, residuals).filter { $0.1 <= cut }.map(\.0)
            guard next.count >= 12, next.count < kept.count else { break }
            kept = next
        }
        guard Double(kept.count) >= 0.3 * Double(samples.count) else { return measurement }
        // Horizontale : y = pente·x, y vers le bas → angle = −atan(pente).
        // Verticale : x = pente·y, y vers le bas → angle depuis l'horizontale = 90 − atan(pente)... ramené
        // à −90…90 : une pente positive (le haut part vers la gauche) donne un angle au-delà de 90.
        var refined: Double
        if horizontal {
            refined = -atan(slope) * 180 / .pi
        } else {
            refined = 90 + atan(slope) * 180 / .pi
            if refined > 90 { refined -= 180 }
        }
        // Un contour retenu loin de la ligne voulue (plus de 3° d'écart) : on garde les points.
        let difference = abs(remainder(refined - pointsAngle, 180))
        guard difference <= 3 else { return measurement }
        return LineMeasurement(pointsAngle: pointsAngle, refinedAngle: refined, edgePoints: kept.count, residual: residual)
    }
}
