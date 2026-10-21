import CoreGraphics
import Foundation
import Vision

/// Ce que Vision (le cadre d'analyse d'images de macOS, sur ce Mac, sans réseau) voit dans un
/// aperçu : visages et pupilles, qualité de chaque visage, note esthétique, zone qui attire
/// l'œil. Les positions sont en fractions de l'image affichée, depuis le coin haut gauche, comme
/// celles qu'attendent add_mask et retouch_spots.
public struct VisionReport: Equatable {
    public struct Face: Equatable {
        /// Cadre du visage.
        public var box: CGRect
        /// Centres des pupilles, de gauche à droite dans l'image.
        public var pupils: [CGPoint]
        /// Largeur d'un œil, en part de la largeur de l'image.
        public var eyeWidth: Double?
        /// Qualité de capture du visage, de 0 à 1 (netteté, pose, éclairage) : pour comparer les
        /// photos d'une rafale, pas dans l'absolu.
        public var quality: Double?
        /// Ouverture des yeux : hauteur sur largeur du contour de l'œil, mesurée le long de l'axe de
        /// ses coins (insensible à l'inclinaison du visage) ; le plus ouvert des deux : fermés
        /// seulement si les deux le sont (un clin d'œil ne compte pas). Nil si les yeux sont trop
        /// petits dans l'image pour la lire.
        public var eyeOpenness: Double?
        /// Lacet du visage en radians (rotation autour de l'axe vertical), tel que Vision le donne ;
        /// nil s'il ne le donne pas. Le sens du regard s'en tire par Composition.regard (signe et
        /// seuil provisoires, à constater).
        public var yaw: Double? = nil
        /// Roulis du visage en radians (rotation dans le plan de l'image), tel que Vision le donne ;
        /// nil s'il ne le donne pas. Proche de ±π, le « visage » est à l'envers : un faux visage
        /// (Composition.visagePlausible).
        public var roll: Double? = nil

        /// Le sens du regard dans l'image : « vers la droite de l'image », « vers la gauche de
        /// l'image » ou « de face » ; nil sans lacet.
        public var regard: String? {
            guard let yaw, yaw.isFinite else { return nil }
            guard let sens = Composition.regard(yaw: yaw) else { return "de face" }
            return sens > 0 ? "vers la droite de l'image" : "vers la gauche de l'image"
        }

        /// Les yeux paraissent fermés (ouverture sous le seuil relevé sur de vrais portraits).
        public var eyesClosed: Bool? { eyeOpenness.map { $0 < VisionAnalysis.closedEyesThreshold } }

        /// Rayon d'une correction d'yeux rouges, en part de la largeur de l'image : la pupille
        /// dilatée par le flash couvre environ 15 % de la largeur de l'œil. Une estimation.
        public var redEyeRadius: Double? { eyeWidth.map { $0 * 0.15 } }
    }

    public var faces: [Face]
    /// Note esthétique de Vision, de −1 à 1 (macOS 15 et plus).
    public var aesthetics: Double?
    /// Photo « utilitaire » selon Vision (capture d'écran, document, reçu…).
    public var utility: Bool?
    /// Zone qui attire l'œil (saillance par attention).
    public var salientArea: CGRect?

    public var aestheticsReading: String? {
        guard let aesthetics else { return nil }
        switch aesthetics {
        case ..<0.2: return "faible"
        case ..<0.5: return "moyenne"
        default: return "bonne"
        }
    }

    public var json: JSONValue {
        func r(_ value: Double) -> JSONValue { .number((value * 1000).rounded() / 1000) }
        func rect(_ box: CGRect) -> JSONValue { ["x": r(box.minX), "y": r(box.minY), "width": r(box.width), "height": r(box.height)] }
        var result: [String: JSONValue] = [
            "visages": .array(faces.map { face in
                var item: [String: JSONValue] = ["cadre": rect(face.box)]
                if !face.pupils.isEmpty { item["pupilles"] = .array(face.pupils.map { ["x": r($0.x), "y": r($0.y)] }) }
                if let radius = face.redEyeRadius { item["rayon_yeux_rouges"] = r(radius) }
                if let quality = face.quality { item["qualite"] = .number((quality * 100).rounded() / 100) }
                if let openness = face.eyeOpenness, let closed = face.eyesClosed {
                    item["yeux"] = ["ouverture": .number((openness * 100).rounded() / 100), "lecture": .string(closed ? "fermés" : "ouverts")]
                }
                if let regard = face.regard { item["regard"] = .string(regard) }
                return .object(item)
            }),
            "base": .string("Vision d'Apple sur l'aperçu, sur ce Mac. Positions en fractions de l'image affichée (0 à 1 depuis le coin haut gauche) : pupilles et rayon_yeux_rouges vont tels quels dans retouch_spots (red_eyes, à vérifier par un zoom). Qualité d'un visage de 0 à 1 et note esthétique de −1 à 1 : pour comparer des photos entre elles. Yeux : ouverture (hauteur sur largeur de l'œil le plus ouvert ; fermés sous \(DevelopCatalogue.format(VisionAnalysis.closedEyesThreshold))), seulement pour un visage assez grand. Regard : d'après la rotation du visage, à vérifier à l'œil."),
        ]
        if let aesthetics {
            var item: [String: JSONValue] = ["note": .number((aesthetics * 100).rounded() / 100)]
            if let reading = aestheticsReading { item["lecture"] = .string(reading) }
            if let utility { item["utilitaire"] = .bool(utility) }
            result["esthetique"] = .object(item)
        }
        if let salientArea { result["zone_d_interet"] = rect(salientArea) }
        return .object(result)
    }
}

public enum VisionAnalysis {
    static let maxFaces = 10
    /// Ouverture des yeux (hauteur sur largeur du contour) sous laquelle ils sont fermés ou
    /// plissés. Relevé le 18 octobre 2026 sur 59 visages d'une vraie séance (aperçus de
    /// 1344 px) : fermés ou plissés de 0,05 à 0,11, ouverts à partir de 0,14 (de 0,14 à 0,16 un
    /// sourire qui plisse, les yeux visibles) ; 41 photos sur les 249 aux yeux lisibles.
    public static let closedEyesThreshold = 0.12
    /// Largeur minimale d'un œil, en pixels de l'image analysée, pour lire son ouverture : en
    /// dessous, le contour de Vision ne tient qu'à quelques pixels.
    static let minimumEyePixels = 12.0

    /// Ouverture d'un œil : étendue de son contour perpendiculairement à l'axe de ses deux points
    /// les plus éloignés (les coins), sur la longueur de cet axe. Nil sous `minimumEyePixels`.
    static func openness(_ points: [CGPoint]) -> Double? {
        guard points.count >= 4 else { return nil }
        var a = points[0], b = points[1], longest = 0.0
        for i in points.indices {
            for j in points.indices where j > i {
                let d = hypot(Double(points[i].x - points[j].x), Double(points[i].y - points[j].y))
                if d > longest { longest = d; a = points[i]; b = points[j] }
            }
        }
        guard longest >= minimumEyePixels else { return nil }
        let ux = Double(b.x - a.x) / longest, uy = Double(b.y - a.y) / longest
        let across = points.map { -uy * Double($0.x - a.x) + ux * Double($0.y - a.y) }
        guard let low = across.min(), let high = across.max() else { return nil }
        return (high - low) / longest
    }

    /// Analyse un JPEG (ou toute image lisible par ImageIO). Nil si l'image est illisible ou si
    /// Vision échoue.
    public static func analyze(_ data: Data) -> VisionReport? {
        guard let image = PreviewImages.image(data) else { return nil }
        return analyze(image)
    }

    public static func analyze(_ image: CGImage) -> VisionReport? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let landmarks = VNDetectFaceLandmarksRequest()
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        var requests: [VNRequest] = [landmarks, saliency]
        var aestheticsRequest: VNRequest?
        if #available(macOS 15.0, *) {
            let request = VNCalculateImageAestheticsScoresRequest()
            requests.append(request)
            aestheticsRequest = request
        }
        do { try handler.perform(requests) } catch { return nil }

        let observations = Array((landmarks.results ?? []).sorted { $0.boundingBox.width > $1.boundingBox.width }.prefix(maxFaces))
        var qualities: [UUID: Double] = [:]
        if !observations.isEmpty {
            let quality = VNDetectFaceCaptureQualityRequest()
            quality.inputFaceObservations = observations
            if (try? handler.perform([quality])) != nil {
                for result in quality.results ?? [] {
                    if let value = result.faceCaptureQuality { qualities[result.uuid] = Double(value) }
                }
            }
        }

        let size = CGSize(width: image.width, height: image.height)
        func topLeft(_ box: CGRect) -> CGRect {
            CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
        let faces = observations.map { face -> VisionReport.Face in
            var pupils: [CGPoint] = []
            for region in [face.landmarks?.leftPupil, face.landmarks?.rightPupil] {
                if let point = region?.pointsInImage(imageSize: size).first {
                    pupils.append(CGPoint(x: point.x / size.width, y: 1 - point.y / size.height))
                }
            }
            var eyeWidths: [Double] = []
            var openings: [Double] = []
            for region in [face.landmarks?.leftEye, face.landmarks?.rightEye] {
                let points = region?.pointsInImage(imageSize: size) ?? []
                let xs = points.map(\.x)
                if let low = xs.min(), let high = xs.max(), high > low { eyeWidths.append(Double(high - low) / size.width) }
                if let opening = openness(points) { openings.append(opening) }
            }
            return VisionReport.Face(
                box: topLeft(face.boundingBox),
                pupils: pupils.sorted { $0.x < $1.x },
                eyeWidth: eyeWidths.isEmpty ? nil : eyeWidths.reduce(0, +) / Double(eyeWidths.count),
                quality: qualities[face.uuid],
                eyeOpenness: openings.count == 2 ? openings.max() : nil,
                // Constaté sur ce Mac (révision 3) : les observations des repères portent le lacet,
                // le même que la détection des visages seule ; pas de seconde requête.
                yaw: face.yaw.map { Double(truncating: $0) },
                roll: face.roll.map { Double(truncating: $0) })
        }

        var salient: CGRect?
        for object in saliency.results?.first?.salientObjects ?? [] where object.confidence >= 0.3 {
            let box = topLeft(object.boundingBox)
            salient = salient.map { $0.union(box) } ?? box
        }

        var aesthetics: Double?
        var utility: Bool?
        if #available(macOS 15.0, *), let result = (aestheticsRequest as? VNCalculateImageAestheticsScoresRequest)?.results?.first {
            aesthetics = Double(result.overallScore)
            utility = result.isUtility
        }
        return VisionReport(faces: faces, aesthetics: aesthetics, utility: utility, salientArea: salient)
    }

    /// Cadres des personnes entières (de 0 à 1, origine en haut à gauche), de gauche à droite.
    /// Relevé le 18 octobre 2026 sur une photo de groupe de six personnes : à moins de 0,02 des
    /// cadres que Lightroom range pour ses masques Personnes (InstanceBounds).
    public static func people(_ image: CGImage) -> [CGRect] {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
        return (request.results ?? []).map { observation in
            let box = observation.boundingBox
            return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }.sorted { $0.minX < $1.minX }
    }

    /// Empreinte d'une image, pour mesurer sa ressemblance avec d'autres.
    public static func featurePrint(_ data: Data) -> VNFeaturePrintObservation? {
        guard let image = PreviewImages.image(data) else { return nil }
        return featurePrint(image)
    }

    public static func featurePrint(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return nil }
        return request.results?.first
    }

    /// Distance entre deux empreintes. Relevé sur des aperçus : 0,1 pour la même photo développée
    /// autrement, environ 0,45 pour la même photo recadrée, de 0,8 à 1 entre photos différentes.
    public static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Double? {
        var value: Float = 0
        guard (try? a.computeDistance(&value, to: b)) != nil else { return nil }
        return Double(value)
    }

    /// Seuil sous lequel deux photos montrent la même scène (rafale, quasi-doublon).
    public static let sameSceneDistance = 0.5

    /// Groupes de photos semblables (distance sous le seuil, de proche en proche), dans l'ordre
    /// donné ; les photos seules ne forment pas de groupe.
    public static func groups(_ prints: [VNFeaturePrintObservation?], threshold: Double = sameSceneDistance) -> [[Int]] {
        var parent = Array(prints.indices)
        func root(_ i: Int) -> Int { var i = i; while parent[i] != i { i = parent[i] }; return i }
        for i in prints.indices {
            for j in prints.indices where j > i {
                guard let a = prints[i], let b = prints[j], let d = distance(a, b), d < threshold else { continue }
                parent[root(j)] = root(i)
            }
        }
        var byRoot: [Int: [Int]] = [:]
        for i in prints.indices { byRoot[root(i), default: []].append(i) }
        return byRoot.values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }
    }
}
