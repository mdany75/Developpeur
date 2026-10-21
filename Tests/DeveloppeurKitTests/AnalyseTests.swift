import CoreGraphics
import ImageIO
import XCTest
@testable import DeveloppeurKit

/// Netteté et bruit, mesure d'une ligne, Vision, et la recette face au faux module.
final class AnalyseTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    /// Image de synthèse (fond gris, puis le dessin dans le repère de Core Graphics : y vers le haut).
    static func render(width: Int = 1344, height: Int = 896, _ draw: (CGContext) -> Void) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(gray: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return PreviewImages.jpeg(context.makeImage()!, quality: 1)!
    }

    static func checkerboard(width: Int = 1344, height: Int = 896) -> Data {
        render(width: width, height: height) { context in
            context.setFillColor(gray: 0.1, alpha: 1)
            for y in stride(from: 0, to: height, by: 8) {
                for x in stride(from: (y / 8) % 2 * 8, to: width, by: 16) { context.fill(CGRect(x: x, y: y, width: 8, height: 8)) }
            }
        }
    }

    static func gradient() -> Data {
        render { context in
            for x in 0..<1344 {
                context.setFillColor(gray: CGFloat(x) / 1344, alpha: 1)
                context.fill(CGRect(x: x, y: 0, width: 1, height: 896))
            }
        }
    }

    /// Gris uni avec un bruit pseudo-aléatoire de ±`amount` niveaux par pixel.
    static func noisyGray(amount: Int) -> Data {
        let width = 1024, height = 683
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt64 = 42
        for i in 0..<(width * height) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = Int(seed >> 33) % (2 * amount + 1) - amount
            for c in 0..<3 { pixels[i * 4 + c] = UInt8(clamping: 128 + noise) }
            pixels[i * 4 + 3] = 255
        }
        let image = pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
        }
        return PreviewImages.jpeg(image, quality: 1)!
    }

    /// Contour net : sombre sous une ligne qui monte vers la droite de `degrees`.
    static func tiltedHorizon(degrees: Double, width: Int = 1344, height: Int = 896, y0: Double = 400) -> Data {
        render(width: width, height: height) { context in
            context.setFillColor(gray: 0.15, alpha: 1)
            context.move(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: Double(width), y: 0))
            context.addLine(to: CGPoint(x: Double(width), y: y0 + Double(width) * tan(degrees * .pi / 180)))
            context.addLine(to: CGPoint(x: 0, y: y0))
            context.closePath()
            context.fillPath()
        }
    }

    // MARK: Netteté, bruit, écrêtage par canal

    func testSharpnessAndNoise() throws {
        let sharp = try XCTUnwrap(Detail.analyze(Self.checkerboard()))
        XCTAssertGreaterThan(sharp.sharpest, 35)
        XCTAssertTrue(sharp.sharpnessReading.hasPrefix("nette"), sharp.sharpnessReading)
        XCTAssertEqual(sharp.side, Detail.side, "l'aperçu de 1344 px est mesuré à 1024 px")

        let smooth = try XCTUnwrap(Detail.analyze(Self.gradient()))
        XCTAssertLessThan(smooth.sharpest, 15)
        XCTAssertTrue(smooth.sharpnessReading.hasPrefix("floue"), smooth.sharpnessReading)
        XCTAssertLessThan(smooth.noise, 0.6)

        let noisy = try XCTUnwrap(Detail.analyze(Self.noisyGray(amount: 12)))
        XCTAssertGreaterThan(noisy.noise, 1.5)
        XCTAssertTrue(noisy.noiseReading.hasPrefix("fort"), noisy.noiseReading)

        let json = sharp.json
        XCTAssertEqual(json["nettete"]?["zones_3x3"]?.array?.count, 3)
        XCTAssertNotNil(json["bruit"]?["aplats"])
    }

    func testClippingPerChannel() throws {
        let red = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 255, green: 30, blue: 30)))
        XCTAssertEqual(red.clippedChannels[0], 100, accuracy: 0.1)
        XCTAssertEqual(red.clippedChannels[1], 0)
        XCTAssertEqual(red.pureWhite, 0)
        XCTAssertEqual(red.json["ecretage_pct"]?["par_canal"]?["rouge"]?.double, 100)
    }

    // MARK: Mesure d'une ligne

    func testLineAngleRefinesHorizonAndVertical() throws {
        let degrees = 2.0, width = 1344.0, height = 896.0, y0 = 400.0
        // Points approximatifs sur la ligne (repère haut gauche), à un pixel près.
        func y(_ x: Double) -> Double { (height - (y0 + x * tan(degrees * .pi / 180))) / height }
        let line = try XCTUnwrap(LineAngle.measure(Self.tiltedHorizon(degrees: degrees), from: CGPoint(x: 0.1, y: y(134) + 0.002),
                                                   to: CGPoint(x: 0.9, y: y(1210) - 0.002)))
        XCTAssertFalse(line.vertical)
        XCTAssertEqual(try XCTUnwrap(line.refinedAngle), degrees, accuracy: 0.1)
        XCTAssertGreaterThan(line.edgePoints, 500)
        XCTAssertEqual(line.correction, -degrees, accuracy: 0.1, "une horizontale qui monte à droite se corrige dans le sens horaire")

        // Verticale dont le haut penche vers la droite de 2° : correction dans le sens antihoraire.
        let lean = tan(degrees * .pi / 180) * height
        let vertical = Self.render { context in
            context.setFillColor(gray: 0.15, alpha: 1)
            context.move(to: CGPoint(x: 0, y: 0))
            context.addLine(to: CGPoint(x: 600, y: 0))
            context.addLine(to: CGPoint(x: 600 + lean, y: height))
            context.addLine(to: CGPoint(x: 0, y: height))
            context.closePath()
            context.fillPath()
        }
        let post = try XCTUnwrap(LineAngle.measure(vertical, from: CGPoint(x: (600 + lean * 0.9) / width, y: 0.1),
                                                   to: CGPoint(x: (600 + lean * 0.1) / width, y: 0.9)))
        XCTAssertTrue(post.vertical)
        XCTAssertEqual(post.tilt, -degrees, accuracy: 0.1)
        XCTAssertEqual(post.correction, degrees, accuracy: 0.1)

        XCTAssertNil(LineAngle.measure(Self.tiltedHorizon(degrees: 0), from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.505, y: 0.5)),
                     "segment trop court")
    }

    func testMeasureAngleToolAddsTheCorrectionToTheCurrentAngle() throws {
        let image = Self.tiltedHorizon(degrees: 2)
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" {
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image)), "photo": ["id": 3, "fichier": "A.RAF"],
                                          "recadrage": ["angle": 1, "recadree": true]]
            }
        }
        let result = tools.call(name: "measure_angle", arguments: ["photo_id": 3, "x1": 0.1, "y1": 0.5482, "x2": 0.9, "y2": 0.5056])
        XCTAssertFalse(result.isError, result.text)
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(try XCTUnwrap(info["inclinaison"]?.double), 2, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(info["crop_angle"]?.double), -1, accuracy: 0.1, "angle actuel 1° moins l'inclinaison")
        XCTAssertEqual(info["ligne"]?.string, "horizontale")

        XCTAssertTrue(tools.call(name: "measure_angle", arguments: ["x1": 1.5, "y1": 0, "x2": 0, "y2": 0]).isError)
    }

    // MARK: Vision

    func testVisionSeesNoFaceOnAPatternAndGroupsIdenticalImages() throws {
        let report = try XCTUnwrap(VisionAnalysis.analyze(Self.checkerboard()))
        XCTAssertTrue(report.faces.isEmpty)
        XCTAssertNotNil(report.json["visages"]?.array)

        let prints = [Self.checkerboard(), Self.checkerboard(), Self.gradient()].map(VisionAnalysis.featurePrint)
        XCTAssertEqual(VisionAnalysis.groups(prints), [[0, 1]])
    }

    /// 1.3 : le sens du regard d'un visage, tiré du lacet de Vision (Composition.regard), dans le JSON
    /// de Vision ; absent sans lacet.
    func testVisionDitLeRegardDUnVisage() throws {
        func regard(_ yaw: Double?) -> JSONValue? {
            let visage = VisionReport.Face(box: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2), pupils: [], eyeWidth: nil,
                                           quality: nil, eyeOpenness: nil, yaw: yaw)
            return VisionReport(faces: [visage], aesthetics: nil, utility: nil, salientArea: nil).json["visages"]?.array?.first?["regard"]
        }
        XCTAssertNil(regard(nil), "sans lacet, pas de regard")
        XCTAssertEqual(regard(0.5 * Composition.signeLacet)?.string, "vers la droite de l'image")
        XCTAssertEqual(regard(-0.5 * Composition.signeLacet)?.string, "vers la gauche de l'image")
        XCTAssertEqual(regard(0.1)?.string, "de face")
        XCTAssertNil(VisionReport.Face(box: .zero, pupils: [], eyeWidth: nil, quality: nil, eyeOpenness: nil).yaw, "nil par défaut")
    }

    func testViewPhotoAddsDetailAndVision() throws {
        let image = Self.checkerboard()
        fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image)), "photo": ["id": 1]]
        let result = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(result.isError, result.text)
        let info = try JSONCoding.parse(result.text)
        XCTAssertNotNil(info["mesures"]?["nettete"]?["lecture"])
        XCTAssertNotNil(info["mesures"]?["bruit"])
        XCTAssertNotNil(info["mesures"]?["luminosite_L"], "les mesures de 1.2 restent")
        XCTAssertNotNil(info["vision"]?["visages"])
    }

    // MARK: Éclairage mixte branché (1.2)

    /// Aperçu de synthèse : une lampe au tiers gauche et une fenêtre ailleurs, ou un gris uni.
    static func eclairage(mixte: Bool) -> Data {
        TestSupport.jpegPixels(width: 600, height: 400) { x, _ in
            mixte ? (x < 200 ? EclairageTests.lampe : EclairageTests.fenetre) : EclairageTests.gris
        }
    }

    func testViewPhotoNommeUnEclairageMixte() throws {
        var image = Self.eclairage(mixte: true)
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" {
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image)), "photo": ["id": 1, "fichier": "A.RAF"],
                                          "echelle_temperature": "kelvins (RAW : 2000 à 50000)", "reglages": ["Temperature": 5000, "Tint": 0]]
            }
        }
        let info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
        let eclairage = try XCTUnwrap(info["mesures"]?["eclairage"], "\(info["mesures"] ?? .null)")
        XCTAssertEqual(eclairage["mixte"], true, "\(eclairage)")
        XCTAssertTrue(eclairage["lecture"]?.string?.hasPrefix("éclairage mixte : plus chaude tiers gauche") == true)
        XCTAssertNotNil(eclairage["conseil"])
        XCTAssertEqual(eclairage["regions_3x3"]?.array?.count, 3)
        XCTAssertEqual(eclairage["groupes"]?.array?.count, 2)
        // La balance proposée part de la Temperature brute de la réponse (en kelvins), pas des
        // réglages regroupés de `info`, qui l'ont perdue : la même que balanceProposee sur la réponse
        // du module, dès que Vision donne une zone d'intérêt (sur cette image, il en donne une).
        let decodee = try XCTUnwrap(PreviewImages.image(image))
        let vision = VisionAnalysis.analyze(decodee)
        let mesure = try XCTUnwrap(Eclairage.mesurer(PreviewImages.scaled(decodee, maxSide: Measurements.maxSide),
                                                     visages: vision?.faces.map(\.box) ?? [], sujet: vision?.salientArea))
        let reponse: JSONValue = ["echelle_temperature": "kelvins (RAW : 2000 à 50000)", "reglages": ["Temperature": 5000, "Tint": 0]]
        if let attendue = ToolHandler.balanceProposee(mesure, reponse: reponse) {
            let balance = try XCTUnwrap(eclairage["balance_proposee"], "\(eclairage)")
            XCTAssertEqual(try XCTUnwrap(balance["Temperature"]?.double), attendue.temperature, accuracy: 0.5)
            XCTAssertNotEqual(attendue.temperature, 5000, "la lumière du sujet n'est pas neutre")
        } else {
            XCTAssertNil(eclairage["balance_proposee"], "sans zone d'intérêt ni visage : pas de lumière du sujet")
        }
        XCTAssertNotNil(info["vision"]?["visages"], "vision reste à sa place")
        XCTAssertNotNil(info["mesures"]?["luminosite_L"])

        image = Self.eclairage(mixte: false)
        let simple = try XCTUnwrap(JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)["mesures"]?["eclairage"])
        XCTAssertEqual(simple["mixte"], false)
        XCTAssertNil(simple["conseil"])
        XCTAssertNil(simple["regions_3x3"])
        XCTAssertNil(simple["base"])
    }

    func testCompareDonneLEclairageAvantEtApres() throws {
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" {
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(Self.eclairage(mixte: false))),
                                          "chemin_avant": .string(TestSupport.previewFile(Self.eclairage(mixte: true))), "photo": ["id": 1]]
            }
        }
        let info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: ["compare": "before_claude"]).text)
        XCTAssertEqual(info["mesures_avant"]?["eclairage"]?["mixte"], true, "l'écart entre zones, avant un masque")
        XCTAssertEqual(info["mesures"]?["eclairage"]?["mixte"], false, "et après")
        let court = try XCTUnwrap(info["mesures_avant"]?["eclairage"]?.object)
        XCTAssertNil(court["visages"])
        XCTAssertNil(court["conseil"])
        XCTAssertNil(court["regions_3x3"])
        XCTAssertNotNil(court["ecart_regions"])
    }

    func testAnalyzePhotosDitLEclairageMixte() throws {
        fake.onSend = { [unowned fake] command, params in
            if command == "apercu", let id = params["photo"]?.int {
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(Self.eclairage(mixte: id == 1))), "photo": ["id": .number(Double(id))]]
            }
        }
        let result = tools.call(name: "analyze_photos", arguments: ["photo_ids": [1, 2]])
        XCTAssertFalse(result.isError, result.text)
        let photos = try XCTUnwrap(JSONCoding.parse(result.text)["photos"]?.array)
        XCTAssertEqual(photos[0]["eclairage"]?["mixte"], true)
        XCTAssertNotNil(photos[0]["eclairage"]?["ecart_regions"])
        XCTAssertTrue(photos[0]["eclairage"]?["lecture"]?.string?.hasPrefix("éclairage mixte") == true)
        XCTAssertEqual(photos[1]["eclairage"]?["mixte"], false)
    }

    func testPreviewDonneLEclairageDeLaProposition() throws {
        fake.onSend = { [unowned fake] command, _ in
            if command == "essayer" {
                fake!.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(Self.eclairage(mixte: true))), "photo": ["id": 1]]
            }
        }
        let result = tools.call(name: "preview_settings", arguments: ["settings": ["Exposure2012": 0.3]])
        XCTAssertFalse(result.isError, result.text)
        let proposition = try XCTUnwrap(JSONCoding.parse(result.text)["mesures_proposition"])
        XCTAssertNotNil(proposition["eclairage"]?["ecart_regions"], "une balance ou un masque proposés se voient à l'écart entre zones")
        XCTAssertEqual(proposition["eclairage"]?["mixte"], true)
        XCTAssertNotNil(proposition["luminosite_L"])
    }

    /// Le point de mise au point d'une photo Fujifilm : toujours en chiffres, dessiné avec
    /// af_point ou la préférence « en tout temps » du module ; le chemin et la géométrie ne vont pas
    /// à Claude.
    func testViewPhotoGivesTheFocusPointAndDrawsItToRate() throws {
        let image = Self.gradient()
        let photo: JSONValue = ["id": 1, "fichier": "DSCF0001.RAF", "marque": "FUJIFILM",
                                "chemin_original": "/Volumes/Photos/DSCF0001.RAF",
                                "geometrie": ["largeur": 300, "hauteur": 200, "orientation": "AB"]]
        tools.lecteurBoitier = LecteurBoitier(delai: 1) { _ in LectureBoitier(point: PointAF(x: 0.25, y: 0.5, avertissement: false, visages: nil)) }
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" { fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image)), "photo": photo] }
        }
        let simple = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(simple.isError, simple.text)
        XCTAssertEqual(fake.calls.last?.params["point_af"]?.bool, true)
        var info = try JSONCoding.parse(simple.text)
        XCTAssertEqual(info["point_af"]?["x"]?.double, 0.25)
        XCTAssertEqual(info["point_af"]?["y"]?.double, 0.5)
        XCTAssertNil(info["point_af"]?["carre"], "sans af_point : en chiffres seulement")
        XCTAssertNil(info["photo"]?["chemin_original"])
        XCTAssertNil(info["photo"]?["geometrie"])
        XCTAssertNil(info["point_af_toujours"])

        let notee = tools.call(name: "view_photo", arguments: ["af_point": true])
        info = try JSONCoding.parse(notee.text)
        XCTAssertEqual(info["point_af"]?["carre"]?.string, "vert, sur l'image")
        guard case .image(let base64, _) = notee.content.first, let donnees = Data(base64Encoded: base64),
              let dessinee = PreviewImages.image(donnees) else { return XCTFail("image attendue") }
        // Le bord gauche du carré : le point à 0,25 × 1344 = 336 px, côté 6 % de 896 ≈ 54 px.
        XCTAssertTrue(Self.pixelVert(dessinee, x: 336 - 27, y: 448), "carré vert dessiné")
        XCTAssertFalse(Self.pixelVert(dessinee, x: 336, y: 448), "le centre reste la photo")

        // La préférence « en tout temps » du module : le carré sans af_point.
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" {
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image)), "photo": photo, "point_af_toujours": true]
            }
        }
        info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
        XCTAssertNotNil(info["point_af"]?["carre"])

        // Un zoom aussi (demandé par Dany : un zoom pour voir la mise au point ne la montrait pas) :
        // le point dans l'image entière, et le carré dans la zone quand il y tombe.
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" { fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image)), "photo": photo] }
        }
        let zoom = tools.call(name: "view_photo", arguments: ["af_point": true, "region": ["x": 0, "y": 0.25, "width": 0.5, "height": 0.5]])
        XCTAssertEqual(fake.calls.last?.params["point_af"]?.bool, true)
        info = try JSONCoding.parse(zoom.text)
        XCTAssertEqual(info["point_af"]?["dans_la_zone"]?.bool, true)
        XCTAssertEqual(info["point_af"]?["carre"]?.string, "vert, sur le zoom")
        XCTAssertEqual(info["point_af"]?["x"]?.double, 0.25, "dans l'image entière")
        let ailleurs = tools.call(name: "view_photo", arguments: ["af_point": true, "region": ["x": 0.6, "y": 0, "width": 0.4, "height": 0.4]])
        info = try JSONCoding.parse(ailleurs.text)
        XCTAssertEqual(info["point_af"]?["dans_la_zone"]?.bool, false)
        XCTAssertNil(info["point_af"]?["carre"])
        // Un avant/après ne le demande pas ; une autre marque n'ouvre pas l'original.
        _ = tools.call(name: "view_photo", arguments: ["compare": "before_claude"])
        XCTAssertNil(fake.calls.last?.params["point_af"])
        XCTAssertNil(ToolHandler.pointAF(["marque": "Apple", "chemin_original": "/tmp/IMG.HEIC",
                                          "geometrie": ["largeur": 300, "hauteur": 200]], lecteur: tools.lecteurBoitier))
        XCTAssertNil(ToolHandler.lectureBoitier(["marque": "Apple", "chemin_original": "/tmp/IMG.HEIC"], lecteur: tools.lecteurBoitier))
    }

    /// L'intention de la prise de vue (Fujifilm) : lue de la même ouverture que le point de mise au
    /// point, sur l'aperçu entier seulement, avec le profil de la simulation pour un RAW.
    func testViewPhotoGivesTheCameraIntention() throws {
        tools = ToolHandler(lightroom: fake, lookProfiles: TestSupport.lookLibrary())
        let image = Self.gradient()
        var photo: JSONValue = ["id": 1, "fichier": "DSCF0001.RAF", "marque": "FUJIFILM", "chemin_original": "/Volumes/Photos/DSCF0001.RAF",
                                "geometrie": ["largeur": 300, "hauteur": 200, "orientation": "AB"]]
        fake.onSend = { [unowned fake] command, params in
            guard command == "apercu" else { return }
            var reponse: [String: JSONValue] = ["chemin": .string(TestSupport.previewFile(image)), "photo": photo,
                                                "echelle_temperature": "kelvins (RAW : 2000 à 50000)", "profil": "Adobe Color",
                                                "appareil": ["marque": "FUJIFILM", "modele": "X-H2S"]]
            if params["comparer"] != nil { reponse["chemin_avant"] = .string(TestSupport.previewFile(image)) }
            fake!.replies["apercu"] = .object(reponse)
        }
        let verrou = NSLock()
        var lectures = 0
        tools.lecteurBoitier = LecteurBoitier(delai: 1) { _ in
            verrou.lock(); lectures += 1; verrou.unlock()
            return LectureBoitier(point: PointAF(x: 0.25, y: 0.5, avertissement: false, visages: nil),
                                  intention: IntentionBoitier(simulation: 0x600, compensation: -1))
        }
        func comptees() -> Int { verrou.lock(); defer { verrou.unlock() }; return lectures }

        var info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
        XCTAssertEqual(info["intention_boitier"]?["simulation"]?.string, "CLASSIC CHROME")
        XCTAssertEqual(info["intention_boitier"]?["profil"]?.string, "Camera CLASSIC CHROME")
        let lecture = try XCTUnwrap(info["intention_boitier"]?["lecture"]?.array).compactMap(\.string)
        XCTAssertTrue(lecture.contains { $0.contains("voulue plus sombre") }, "\(lecture)")
        XCTAssertTrue(lecture.contains { $0.contains("partir du profil « Camera CLASSIC CHROME »") }, "\(lecture)")
        XCTAssertNotNil(info["point_af"], "le point reste")
        XCTAssertEqual(comptees(), 1, "point et intention d'une seule ouverture")

        // Un zoom : le point, sans l'intention ; un avant/après : ni l'un ni l'autre, rien de lu.
        info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: ["region": ["x": 0, "y": 0.25, "width": 0.5, "height": 0.5]]).text)
        XCTAssertNotNil(info["point_af"])
        XCTAssertNil(info["intention_boitier"])
        XCTAssertEqual(comptees(), 2)
        info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: ["compare": "before_claude"]).text)
        XCTAssertNil(info["point_af"])
        XCTAssertNil(info["intention_boitier"])
        XCTAssertEqual(comptees(), 2, "pas de lecture pour un avant/après")

        // Une autre marque : l'original n'est pas ouvert.
        photo = ["id": 2, "fichier": "IMG_0001.HEIC", "marque": "Apple", "chemin_original": "/Volumes/Photos/IMG_0001.HEIC",
                 "geometrie": ["largeur": 300, "hauteur": 200, "orientation": "AB"]]
        info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
        XCTAssertNil(info["intention_boitier"])
        XCTAssertEqual(comptees(), 2)
    }

    /// Un JPEG de l'appareil : pas de profil, la lecture dit que tout y est déjà ; une simulation à
    /// base de Look : le profil de cet appareil, ou aucun.
    func testCameraIntentionOnAJPEGAndALookSimulation() throws {
        tools = ToolHandler(lightroom: fake, lookProfiles: TestSupport.lookLibrary())
        let image = Self.gradient()
        var echelle = "relative (JPEG, TIFF : −100 à +100)", modele = "X-H2S"
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" {
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image)),
                                           "photo": ["id": 1, "fichier": "DSCF0001.JPG", "marque": "FUJIFILM", "chemin_original": "/Volumes/Photos/DSCF0001.JPG"],
                                           "echelle_temperature": .string(echelle), "profil": "Adobe Color",
                                           "appareil": ["marque": "FUJIFILM", "modele": .string(modele)]]
            }
        }
        var simulation = 0x600
        tools.lecteurBoitier = LecteurBoitier(delai: 1) { _ in LectureBoitier(intention: IntentionBoitier(simulation: simulation)) }

        var info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
        XCTAssertEqual(info["intention_boitier"]?["simulation"]?.string, "CLASSIC CHROME")
        XCTAssertNil(info["intention_boitier"]?["profil"], "un JPEG : pas de profil")
        var lecture = try XCTUnwrap(info["intention_boitier"]?["lecture"]?.array).compactMap(\.string)
        XCTAssertTrue(lecture.contains { $0.hasPrefix("JPEG de l'appareil") }, "\(lecture)")
        XCTAssertNil(info["point_af"], "pas de point lu, pas de géométrie")

        echelle = "kelvins (RAW : 2000 à 50000)"
        simulation = 0x800
        info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
        XCTAssertEqual(info["intention_boitier"]?["profil"]?.string, "Camera CLASSIC Neg", "le Look de ce X-H2S")
        modele = "X-T20"
        info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
        XCTAssertNil(info["intention_boitier"]?["profil"])
        lecture = try XCTUnwrap(info["intention_boitier"]?["lecture"]?.array).compactMap(\.string)
        XCTAssertTrue(lecture.contains { $0.contains("sans profil Lightroom pour cet appareil") }, "\(lecture)")
    }

    /// La fenêtre Claude (aperçu de la photo active) : `mcp-developpeur --marquer-af` dessine le
    /// point sur la vignette rendue par Lightroom.
    func testFocusPointDrawnOnAThumbnailForTheWindow() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("marquer-af-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let entree = dossier.appendingPathComponent("vignette.jpg"), sortie = dossier.appendingPathComponent("vignette-af.jpg")
        try Self.gradient().write(to: entree)
        let lecteur = LecteurBoitier(delai: 1) { _ in LectureBoitier(point: PointAF(x: 0.25, y: 0.5, avertissement: true, visages: nil)) }
        let point = PointAF.marquer(original: URL(fileURLWithPath: "/Volumes/Photos/DSCF0001.RAF"),
                                    geometrie: ["largeur": 300, "hauteur": 200, "orientation": "AB"],
                                    entree: entree, sortie: sortie, lecteur: lecteur)
        XCTAssertEqual(point?.x, 0.25)
        XCTAssertEqual(point?.avertissement, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sortie.path))
        // Hors du cadre (recadrage) ou sans point : rien d'écrit.
        let horsCadre = PointAF.marquer(original: URL(fileURLWithPath: "/Volumes/Photos/DSCF0001.RAF"),
                                        geometrie: ["largeur": 300, "hauteur": 200, "orientation": "AB",
                                                    "cadre": ["CropLeft": 0.5, "CropTop": 0, "CropRight": 1, "CropBottom": 1, "CropAngle": 0]],
                                        entree: entree, sortie: dossier.appendingPathComponent("hors.jpg"), lecteur: lecteur)
        XCTAssertNil(horsCadre)
        XCTAssertNil(PointAF.marquer(original: URL(fileURLWithPath: "/tmp/absent.RAF"), geometrie: ["largeur": 300, "hauteur": 200],
                                     entree: entree, sortie: dossier.appendingPathComponent("sans.jpg"),
                                     lecteur: LecteurBoitier(delai: 1) { _ in nil }))
        // Une lecture sans point (intention seule) ne dessine rien.
        XCTAssertNil(PointAF.marquer(original: URL(fileURLWithPath: "/Volumes/Photos/DSCF0001.RAF"), geometrie: ["largeur": 300, "hauteur": 200],
                                     entree: entree, sortie: dossier.appendingPathComponent("sans-point.jpg"),
                                     lecteur: LecteurBoitier(delai: 1) { _ in LectureBoitier(intention: IntentionBoitier(simulation: 0)) }))
    }

    static func pixelVert(_ image: CGImage, x: Int, y: Int) -> Bool {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = context.data else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for dx in -2...2 {
            let i = (y * image.width + x + dx) * 4
            let p = data.load(fromByteOffset: i, as: UInt32.self)
            let r = Int(p & 0xFF), g = Int((p >> 8) & 0xFF), b = Int((p >> 16) & 0xFF)
            if g > 180, r < 120, b < 140 { return true }
        }
        return false
    }

    func testAnalyzePhotosFindsSimilarPhotos() throws {
        let images: [Int: Data] = [1: Self.checkerboard(), 2: Self.checkerboard(), 3: Self.gradient()]
        fake.onSend = { [unowned fake] command, params in
            if command == "apercu", let id = params["photo"]?.int {
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(images[id]!)), "photo": ["id": .number(Double(id)), "fichier": .string("P\(id).RAF")]]
            }
        }
        let result = tools.call(name: "analyze_photos", arguments: ["photo_ids": [1, 2, 3]])
        XCTAssertFalse(result.isError, result.text)
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(fake.calls.first?.params["taille"]?.int, Detail.side)
        let groups = try XCTUnwrap(info["photos_semblables"]?.array)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0]["photos"]?.array?.compactMap(\.int), [1, 2])
        XCTAssertNotNil(info["photos"]?.array?.first?["nettete"])
    }

    func testPendingAutoValuesAreNamed() throws {
        fake.replies["reglages"] = ["photo": ["id": 1], "reglages": ["Vibrance": -999_999, "Exposure2012": 0.4]]
        let info = try JSONCoding.parse(tools.call(name: "get_settings", arguments: [:]).text)
        XCTAssertEqual(info["reglages"]?["Présence"]?["Vibrance"]?.string, ToolHandler.pendingAutoText,
                       "Lightroom range −999999 tant que la tonalité automatique n'est pas calculée")
        XCTAssertEqual(info["reglages"]?["Tonalité"]?["Exposure2012"]?.double, 0.4)
    }

    func testGetSettingsAllKeys() throws {
        fake.replies["reglages"] = ["photo": ["id": 1], "reglages": [:], "tous": ["LensBlur": ["Active": true]]]
        let info = try JSONCoding.parse(tools.call(name: "get_settings", arguments: ["all_keys": true]).text)
        XCTAssertEqual(fake.lastParams["toutes"]?.bool, true)
        XCTAssertEqual(info["tous_les_reglages"]?["LensBlur"]?["Active"]?.bool, true)
        XCTAssertNil(info["tous"])
    }

    // MARK: Flou d'objectif

    func testApplySettingsLensBlur() throws {
        fake.replies["appliquer"] = ["resultats": []]
        let result = tools.call(name: "apply_settings", arguments: ["step_name": "flou", "lens_blur": ["amount": 30, "near": 10, "far": 40]])
        XCTAssertFalse(result.isError, result.text)
        let demande = try XCTUnwrap(fake.lastParams["flou_objectif"])
        XCTAssertEqual(demande["intensite"]?.double, 30)
        XCTAssertEqual(demande["proche"]?.double, 10)
        XCTAssertEqual(demande["loin"]?.double, 40)
        XCTAssertNotNil(fake.lastParams["libelles"]?["LensBlur"])

        XCTAssertTrue(tools.call(name: "apply_settings", arguments: ["step_name": "flou", "lens_blur": ["near": 10]]).text.contains("ensemble"))
        XCTAssertTrue(tools.call(name: "apply_settings", arguments: ["step_name": "flou", "lens_blur": ["amount": 150]]).isError)

        _ = tools.call(name: "apply_settings", arguments: ["step_name": "sans flou", "lens_blur": ["remove": true]])
        XCTAssertEqual(fake.lastParams["flou_objectif"], ["retirer": true])
    }

    // MARK: Recette

    /// La bande assombrie par un trait de pinceau, entre deux rendus : sa hauteur et son centre.
    func testRecetteMeasuresTheBandOfABrushStroke() throws {
        func image(bande: ClosedRange<Int>?) -> Data {
            let width = 300, height = 200
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let v: UInt8 = bande?.contains(y) == true ? 40 : UInt8(100 + (x * 7 + y * 3) % 50)
                    for c in 0..<3 { pixels[(y * width + x) * 4 + c] = v }
                    pixels[(y * width + x) * 4 + 3] = 255
                }
            }
            let cg = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
                CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
            }!
            let output = NSMutableData()
            let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
            CGImageDestinationFinalize(destination)
            return output as Data
        }
        let bande = try XCTUnwrap(Recette.bandeAssombrie(avant: image(bande: nil), apres: image(bande: 90...101)))
        XCTAssertEqual(bande.hauteur, 12, accuracy: 1.5)
        XCTAssertEqual(bande.centre, 0.479, accuracy: 0.01)
        XCTAssertEqual(bande.largeur, 300)
        XCTAssertNil(Recette.bandeAssombrie(avant: image(bande: nil), apres: image(bande: nil)), "rien d'assombri")
    }

    /// Constaté le 17 octobre 2026 : sur une scène contrastée (vêtements sombres au centre), un écart
    /// moyen en niveaux donnait une bande trop étroite ; la part des pixels assombris la donne entière.
    func testRecetteBandOnAContrastedScene() throws {
        func image(assombrie: ClosedRange<Int>?) -> Data {
            let width = 400, height = 220
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    var v = (x > 170 && x < 230) ? 30.0 : 200.0
                    if assombrie?.contains(y) == true { v *= 0.25 }
                    for c in 0..<3 { pixels[(y * width + x) * 4 + c] = UInt8(v) }
                }
            }
            return TriTests.encode(pixels, width: width, height: height)
        }
        let bande = try XCTUnwrap(Recette.bandeAssombrie(avant: image(assombrie: nil), apres: image(assombrie: 90...129)))
        XCTAssertEqual(bande.hauteur, 40, accuracy: 2)
        XCTAssertEqual(bande.centre, 110.0 / 220, accuracy: 0.01)
    }

    func prepareRecette(virtualCopy: Bool, retouchedByClaude: Bool = false) {
        let preview = TestSupport.jpeg(red: 120, green: 120, blue: 120)
        fake.replies["reglages"] = [
            "photo": ["id": 5, "fichier": "X.RAF (Copie 1)", "copie_virtuelle": .bool(virtualCopy)],
            "reglages": ["Temperature": 5000, "Tint": 10], "balance_des_blancs": "As Shot",
            "masques": [], "profil": "Adobe Color", "recadrage": ["angle": 0],
        ]
        fake.replies["etat"] = ["instantane_avant_claude": true]
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" {
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(preview)),
                                          "photo": ["id": 5, "fichier": "X.RAF (Copie 1)", "retouchee_par_claude": .bool(retouchedByClaude)]]
            }
        }
    }

    func testRecetteNeverTouchesAnOriginalWithoutTheOption() {
        prepareRecette(virtualCopy: false)
        let recette = Recette(lightroom: fake)
        recette.lancer(raw: 5, jpeg: nil, flash: nil)
        XCTAssertFalse(recette.reussie)
        XCTAssertEqual(recette.etapes.map(\.nom), ["photo d'essai"])
        XCTAssertTrue(recette.etapes[0].detail.contains("--original"), recette.etapes[0].detail)
        XCTAssertFalse(fake.calls.contains { ["appliquer", "masquer", "revenir", "annuler"].contains($0.command) })
    }

    func testRecetteTakesAnOriginalWithTheOptionAndRevertsIt() {
        prepareRecette(virtualCopy: false)
        var lines: [String] = []
        let recette = Recette(lightroom: fake, originaux: true) { lines.append("\($0.reussie ? "✔" : "✘") \($0.nom)") }
        recette.lancer(raw: 5, jpeg: nil, flash: nil)
        XCTAssertEqual(lines, ["✔ photo d'essai", "✘ balance personnalisée", "✔ remise à l'origine après l'échec"])
        XCTAssertTrue(recette.etapes[0].detail.contains("historique"), recette.etapes[0].detail)
        XCTAssertTrue(recette.etapes[0].detail.contains("Avant Claude"), recette.etapes[0].detail)
        XCTAssertEqual(fake.calls.map(\.command).last(where: { $0 != "reglages" }), "revenir")
    }

    func testRecetteNeverTakesAPhotoClaudeAlreadyRetouched() {
        // Le retour à l'origine de la fin effacerait aussi ces retouches-là.
        prepareRecette(virtualCopy: false, retouchedByClaude: true)
        let recette = Recette(lightroom: fake, originaux: true)
        recette.lancer(raw: 5, jpeg: nil, flash: nil)
        XCTAssertEqual(recette.etapes.map(\.nom), ["photo d'essai"])
        XCTAssertTrue(recette.etapes[0].detail.contains("déjà retouché"), recette.etapes[0].detail)
        XCTAssertFalse(fake.calls.contains { ["appliquer", "masquer", "revenir", "annuler"].contains($0.command) })
    }

    func testRecetteRevertsAfterAFailure() {
        prepareRecette(virtualCopy: true)
        var lines: [String] = []
        let recette = Recette(lightroom: fake) { lines.append("\($0.reussie ? "✔" : "✘") \($0.nom)") }
        recette.lancer(raw: 5, jpeg: nil, flash: nil)
        XCTAssertFalse(recette.reussie)
        XCTAssertEqual(lines, ["✔ photo d'essai", "✘ balance personnalisée", "✔ remise à l'origine après l'échec"],
                       "le faux module ne change rien : la balance n'est pas passée en Custom")
        XCTAssertFalse(recette.etapes[0].detail.contains("historique"), "rien à dire de l'historique d'une copie virtuelle")
        let commands = fake.calls.map(\.command)
        XCTAssertTrue(commands.contains("appliquer"))
        XCTAssertEqual(commands.last(where: { $0 != "reglages" }), "revenir")
        let write = fake.calls.first { $0.command == "appliquer" }
        XCTAssertEqual(write?.params["confirme"]?.bool, true)
    }

    // MARK: Recette de la 1.2

    /// Éclaircir et assombrir : la part des pixels assombris par zone, entre deux rendus.
    func testRecetteMeasuresDarkenedCornersAndCentre() throws {
        func image(coins: UInt8?, fond: UInt8 = 150) -> Data {
            let width = 200, height = 100
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    let coin = (x < 20 || x >= 180) && (y < 10 || y >= 90)
                    let v = coin ? (coins ?? fond) : fond
                    for c in 0..<3 { pixels[(y * width + x) * 4 + c] = v }
                }
            }
            return TriTests.encode(pixels, width: width, height: height)
        }
        let gris = image(coins: nil), sombres = image(coins: 60)
        let coin = CGRect(x: 0, y: 0, width: 0.1, height: 0.1), autreCoin = CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1)
        let milieu = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        XCTAssertEqual(Recette.partAssombrie(avant: gris, apres: sombres, zone: coin), 1, accuracy: 0.05)
        XCTAssertEqual(Recette.partAssombrie(avant: gris, apres: sombres, zone: autreCoin), 1, accuracy: 0.05)
        XCTAssertEqual(Recette.partAssombrie(avant: gris, apres: sombres, zone: milieu), 0)
        XCTAssertEqual(Recette.partAssombrie(avant: gris, apres: gris, zone: coin), 0, "deux rendus identiques")
        // Les pixels d'avant à 12 niveaux ou moins ne comptent pas : rien à mesurer.
        XCTAssertEqual(Recette.partAssombrie(avant: image(coins: nil, fond: 8), apres: image(coins: 2, fond: 8), zone: coin), 0)
        XCTAssertNil(Recette.Luminances(avant: image(coins: nil, fond: 8), apres: image(coins: 2, fond: 8))?.part(coin))
        // Deux tailles différentes ne se comparent pas.
        XCTAssertEqual(Recette.partAssombrie(avant: gris, apres: TestSupport.jpeg(red: 60, green: 60, blue: 60), zone: coin), 0)
        // La baisse moyenne, en part de luminance perdue : 150 → 60, 60 % de moins.
        let l = try XCTUnwrap(Recette.Luminances(avant: gris, apres: sombres))
        XCTAssertEqual(try XCTUnwrap(l.baisse(coin)), 0.6, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(l.baisse(milieu)), 0, accuracy: 0.01)
        XCTAssertNil(l.baisse(CGRect(x: 1.2, y: 0, width: 0.1, height: 0.1)), "zone hors de l'image")
        XCTAssertNil(Recette.Luminances(avant: image(coins: nil, fond: 8), apres: image(coins: 2, fond: 8))?.baisse(coin), "trop sombre")
    }

    /// La forme des bords d'un radial inversé : centre intact, baisse qui monte sans marche vers les
    /// coins ; une plaque (fondu nul) ou un anneau se reconnaissent ; un coin sombre, non.
    func testRecetteReadsTheShapeOfTheEdges() throws {
        let width = 300, height = 200
        // Distance au centre (0,5 ; 0,5) dans une ellipse aux proportions du cadre (0 au centre, 1 au coin).
        func distance(_ x: Int, _ y: Int) -> Double {
            let dx = (Double(x) + 0.5) / Double(width) - 0.5, dy = (Double(y) + 0.5) / Double(height) - 0.5
            return hypot(dx, dy) / hypot(0.5, 0.5)
        }
        // Une scène (luminance selon r), puis la part qu'un masque lui ôte selon r.
        func image(fond: (Double) -> Double = { _ in 160 }, _ baisse: (Double) -> Double) -> Data {
            TestSupport.jpegPixels(width: width, height: height) { x, y in
                let r = distance(x, y)
                let v = UInt8(max(0, min(255, (fond(r) * (1 - baisse(r))).rounded())))
                return (v, v, v)
            }
        }
        let base = image { _ in 0 }
        let centre = CGPoint(x: 0.5, y: 0.5)
        // Fondu large : la baisse part du tiers et monte en douceur jusqu'aux coins (25 % au coin).
        let douce = try XCTUnwrap(Recette.formeDesBords(avant: base, apres: image { r in r < 0.3 ? 0 : 0.25 * (r - 0.3) / 0.7 }, centre: centre))
        XCTAssertLessThan(douce.centre, Recette.FormeBords.centreMax)
        XCTAssertGreaterThan(douce.coinLoin, 0.15)
        XCTAssertGreaterThan(douce.coins, douce.bords, "les coins plus sombres que le milieu des bords")
        XCTAssertGreaterThan(douce.bords, douce.centre)
        XCTAssertEqual(douce.profil.count, 20)
        XCTAssertFalse(douce.enPlaque, "\(douce.profil)")
        XCTAssertFalse(douce.enAnneau, "\(douce.profil)")
        // Fondu nul : une marche fait toute la baisse.
        let plaque = try XCTUnwrap(Recette.formeDesBords(avant: base, apres: image { r in r < 0.7 ? 0 : 0.25 }, centre: centre))
        XCTAssertTrue(plaque.enPlaque, "\(plaque.profil)")
        // Un anneau : la baisse retombe avant le coin.
        let anneau = try XCTUnwrap(Recette.formeDesBords(avant: base, apres: image { r in r > 0.5 && r < 0.75 ? 0.25 : 0 }, centre: centre))
        XCTAssertTrue(anneau.enAnneau, "\(anneau.profil)")
        // Une scène claire au milieu, sombre aux coins (220 → 20) : la même forme douce y perd peu de
        // niveaux aux coins, mais la même part. En niveaux, elle passerait pour un anneau aux bords
        // à peine assombris.
        func scene(_ r: Double) -> Double { 220 - 200 * min(r, 1) }
        let sombre = try XCTUnwrap(Recette.formeDesBords(avant: image(fond: scene) { _ in 0 },
                                                         apres: image(fond: scene) { r in r < 0.3 ? 0 : 0.15 * min(1, (r - 0.3) / 0.6) },
                                                         centre: centre))
        XCTAssertFalse(sombre.enAnneau, "\(sombre.profil)")
        XCTAssertFalse(sombre.enPlaque, "\(sombre.profil)")
        XCTAssertGreaterThanOrEqual(sombre.coinLoin, Recette.FormeBords.coinMin)
        XCTAssertLessThan(sombre.centre, Recette.FormeBords.centreMax)
        // Le coin le plus loin d'un centre décalé, et des rendus qui ne se comparent pas.
        let decale = try XCTUnwrap(Recette.formeDesBords(avant: base, apres: base, centre: CGPoint(x: 0.2, y: 0.3)))
        XCTAssertEqual(decale.coinLoin, 0, accuracy: 0.01)
        XCTAssertNil(Recette.formeDesBords(avant: base, apres: TestSupport.jpeg(red: 1, green: 1, blue: 1, width: 150, height: 100), centre: centre))
    }

    /// Le détail de l'étape du bilan : les écarts d'un view_photo en une ligne.
    func testRecetteSummarizesTheBilan() {
        let ecarts: JSONValue = ["exposition": ["avant": 47.8, "apres": 71.2, "ecart": 23.4, "IL": 1.95],
                                 "nettete_max": ["avant": 40, "apres": 36, "ecart": -4, "lecture": "nette → nette"],
                                 "canal_ecrete": ["avant": 0.1, "apres": 3, "ecart": 2.9, "canal": "rouge"]]
        // Les nombres comme dans les autres lignes de la recette (Recette.nombre).
        XCTAssertEqual(Recette.resumeEcarts(ecarts),
                       "canal_ecrete 0.1 → 3 (rouge) ; exposition 47.8 → 71.2 (+1.95 IL) ; nettete_max 40 → 36 (nette → nette)")
        XCTAssertEqual(Recette.resumeEcarts(nil), "aucun écart visible")
        XCTAssertEqual(Recette.resumeEcarts("aucun écart visible"), "aucun écart visible")
    }

    /// --mixte : l'éclairage mixte nommé par view_photo, en lecture seule, sur une copie d'essai.
    func testRecetteNamesAMixedLighting() throws {
        prepareRecette(virtualCopy: true)
        var image = Self.eclairage(mixte: true), temoin = Self.eclairage(mixte: false)
        fake.onSend = { [unowned fake] command, params in
            if command == "apercu" {
                let id = params["photo"]?.int ?? 5
                fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(id == 6 ? temoin : image)),
                                          "photo": ["id": .number(Double(id)), "fichier": "X.RAF (Copie 1)"],
                                          "echelle_temperature": "kelvins (RAW : 2000 à 50000)", "reglages": ["Temperature": 5000, "Tint": 0]]
            }
        }
        let recette = Recette(lightroom: fake)
        recette.lancer(raw: nil, jpeg: nil, flash: nil, mixte: 5)
        XCTAssertEqual(recette.etapes.map(\.nom), ["éclairage mixte nommé (view_photo)"])
        XCTAssertTrue(recette.reussie, recette.etapes.first?.detail ?? "")
        let detail = try XCTUnwrap(recette.etapes.first?.detail)
        XCTAssertTrue(detail.hasPrefix("éclairage mixte : "), detail)
        XCTAssertTrue(detail.contains("/9 cases lues") && detail.contains(" ms"), detail)
        XCTAssertFalse(fake.calls.contains { ["appliquer", "masquer", "essayer", "revenir", "annuler"].contains($0.command) }, "lecture seule")

        // Une seule lumière : la photo désignée ne convient pas.
        image = Self.eclairage(mixte: false)
        let unique = Recette(lightroom: fake)
        unique.lancer(raw: nil, jpeg: nil, flash: nil, mixte: 5)
        XCTAssertFalse(unique.reussie)
        XCTAssertTrue(unique.etapes.first?.detail.contains("pas lu comme un éclairage mixte") == true, unique.etapes.first?.detail ?? "")

        // Le témoin du plan : le RAW de la recette (une autre photo) lu à une seule lumière.
        image = Self.eclairage(mixte: true)
        let avecTemoin = Recette(lightroom: fake)
        avecTemoin.sequenceEclairage(5, unique: 6)
        XCTAssertEqual(avecTemoin.etapes.map(\.nom), ["éclairage mixte nommé (view_photo)", "une seule lumière, en témoin (view_photo)"])
        XCTAssertEqual(avecTemoin.etapes.map(\.photo), ["éclairage 5", "éclairage 6"])
        XCTAssertTrue(avecTemoin.reussie, avecTemoin.etapes.map(\.detail).joined(separator: " | "))
        XCTAssertTrue(avecTemoin.etapes[1].detail.contains(" ms"), avecTemoin.etapes[1].detail)
        // Un témoin lu mixte : l'étape le dit.
        temoin = Self.eclairage(mixte: true)
        let temoinMixte = Recette(lightroom: fake)
        temoinMixte.sequenceEclairage(5, unique: 6)
        XCTAssertEqual(temoinMixte.etapes.map(\.reussie), [true, false])
        XCTAssertTrue(temoinMixte.etapes[1].detail.contains("une seule lumière attendue"), temoinMixte.etapes[1].detail)
        XCTAssertFalse(fake.calls.contains { ["appliquer", "masquer", "essayer", "revenir", "annuler"].contains($0.command) }, "lecture seule")
        // La même photo pour --recette et --mixte : pas de témoin.
        let meme = Recette(lightroom: fake)
        meme.lancer(raw: 5, jpeg: nil, flash: nil, mixte: 5)
        XCTAssertTrue(meme.etapes.contains { $0.nom == "éclairage mixte nommé (view_photo)" })
        XCTAssertFalse(meme.etapes.contains { $0.nom.hasPrefix("une seule lumière") })

        // Un original, sans --original : refusé avant tout aperçu.
        prepareRecette(virtualCopy: false)
        fake.calls = []
        let original = Recette(lightroom: fake)
        original.lancer(raw: nil, jpeg: nil, flash: nil, mixte: 5)
        XCTAssertFalse(original.reussie)
        XCTAssertTrue(original.etapes.first?.detail.contains("--original") == true)
        XCTAssertFalse(fake.commands.contains("apercu"))

        // Une photo introuvable : un échec noté, pas une séquence muette.
        fake.errors["reglages"] = LightroomError.plugin("Photo 5 introuvable.")
        let introuvable = Recette(lightroom: fake)
        introuvable.lancer(raw: nil, jpeg: nil, flash: nil, mixte: 5)
        XCTAssertEqual(introuvable.etapes.map(\.nom), ["éclairage mixte nommé (view_photo)"])
        XCTAssertTrue(introuvable.etapes.first?.detail.contains("introuvable") == true)
    }

    /// --portrait : une copie d'essai, vérifiée puis remise à l'origine ; sans visage, rien d'autre.
    func testRecettePortraitNeedsAFaceAndReverts() {
        prepareRecette(virtualCopy: true)
        var lines: [String] = []
        let recette = Recette(lightroom: fake) { lines.append("\($0.reussie ? "✔" : "✘") \($0.nom)") }
        recette.lancer(raw: nil, jpeg: nil, flash: nil, portrait: 5)
        XCTAssertEqual(lines, ["✔ photo d'essai", "✘ visages vus par Vision (view_photo)", "✔ remise à l'origine après l'échec"])
        XCTAssertTrue(recette.etapes[1].detail.contains("choisir un portrait"), recette.etapes[1].detail)
        XCTAssertFalse(fake.commands.contains("masquer") || fake.commands.contains("essayer"), "aucun masque essayé sans visage")
        XCTAssertEqual(fake.commands.last(where: { $0 != "reglages" }), "revenir")
    }

    /// --boitier : ce que l'appareil a rangé dans un fichier Fujifilm, lu sans Lightroom.
    func testBoitierReadWithoutLightroom() throws {
        let dossier = TestSupport.temporaryDirectory()
        let raf = dossier.appendingPathComponent("DSCF0001.RAF")
        let r = BoitierTests.reglages(tons: 9)
        try FichierFujifilm.fichier(note: r.note, exif: r.exif).write(to: raf)
        let looks = LookProfileLibrary(folders: [])
        let json = try XCTUnwrap(Recette.lectureBoitier(raf, looks: looks))
        XCTAssertEqual(json["fichier"]?.string, "DSCF0001.RAF")
        XCTAssertEqual(try XCTUnwrap(json["point_af"]?["x"]?.double), 0.563, accuracy: 0.001)
        XCTAssertEqual(json["point_af"]?["avertissement"]?.bool, false)
        XCTAssertEqual(json["point_af"]?["visages"]?.int, 2)
        XCTAssertEqual(json["intention_boitier"]?["simulation"]?.string, "CLASSIC CHROME")
        XCTAssertEqual(json["intention_boitier"]?["profil"]?.string, "Camera CLASSIC CHROME", "un RAF : le profil de la simulation")
        XCTAssertFalse(json["intention_boitier"]?["lecture"]?.array?.isEmpty ?? true)
        let valeurs = try XCTUnwrap(json["valeurs_lues"])
        XCTAssertEqual(valeurs["FilmMode (0x1401)"]?.int, 0x600)
        XCTAssertEqual(valeurs["AutoDynamicRange (0x140b)"]?.int, 200)
        XCTAssertEqual(valeurs["HighlightTone (0x1041, crans)"]?.double, 1, "−16 en SLONG : +1 cran")
        XCTAssertEqual(try XCTUnwrap(valeurs["ExposureCompensation (0x9204, IL)"]?.double), -0.667, accuracy: 0.001)
        XCTAssertEqual(valeurs["ExposureProgram (0x8822)"]?.int, 3)
        // Un JPEG de l'appareil : la simulation y est déjà appliquée, pas de profil à proposer.
        let jpeg = dossier.appendingPathComponent("DSCF0001.JPG")
        try FichierFujifilm.fichier(note: r.note, exif: r.exif, raf: false).write(to: jpeg)
        XCTAssertNil(try XCTUnwrap(Recette.lectureBoitier(jpeg, looks: looks))["intention_boitier"]?["profil"])
        // Un autre fichier : rien de lu.
        let autre = dossier.appendingPathComponent("autre.jpg")
        try TestSupport.jpeg(red: 10, green: 20, blue: 30).write(to: autre)
        XCTAssertNil(Recette.lectureBoitier(autre, looks: looks))
        XCTAssertNil(Recette.lectureBoitier(dossier.appendingPathComponent("absent.RAF"), looks: looks))
    }

    // MARK: Recette de la 1.2 face au faux module

    /// Un rendu de synthèse d'une proposition (commande « essayer ») : le premier masque change
    /// l'exposition de `fond` selon sa zone, comme Lightroom l'a montré le 20 octobre 2026 : radial
    /// avec son fondu (dedans ; inversé, dehors), linéaire (entier du côté de from). Avec
    /// `inversionIgnoree`, un module qui poserait le radial inversé dans l'ellipse.
    static func rendreMasque(_ params: [String: JSONValue], inversionIgnoree: Bool = false,
                             fond: @escaping (Double, Double) -> Double = { _, _ in 150 }) -> Data {
        let masque = params["masques"]?.array?.first ?? .null
        let il = (masque["locaux"]?["LocalExposure2012"]?.double ?? 0) * 4 * (masque["quantite"]?.double ?? 1)
        func valeur(_ cle: String, _ defaut: Double) -> Double { masque[cle]?.double ?? defaut }
        func poids(_ x: Double, _ y: Double) -> Double {
            switch masque["type"]?.string {
            case "radial":
                let rx = valeur("rayon_x", 0.5), ry = valeur("rayon_y", rx), f = valeur("fondu", 50) / 100
                let d = hypot((x - valeur("centre_x", 0.5)) / rx, (y - valeur("centre_y", 0.5)) / ry)
                let dedans = d <= 1 - f ? 1 : (d >= 1 ? 0 : (1 - d) / f)
                return masque["inverser"]?.bool == true && !inversionIgnoree ? 1 - dedans : dedans
            case "lineaire":
                let x0 = valeur("de_x", 0), y0 = valeur("de_y", 0), dx = valeur("a_x", 0) - x0, dy = valeur("a_y", 1) - y0
                let t = ((x - x0) * dx + (y - y0) * dy) / max(dx * dx + dy * dy, 1e-9)
                return min(max(1 - t, 0), 1)
            default:
                return 1
            }
        }
        let width = 300, height = 200
        return TestSupport.jpegPixels(width: width, height: height) { px, py in
            let x = (Double(px) + 0.5) / Double(width), y = (Double(py) + 0.5) / Double(height)
            let v = UInt8(max(0, min(255, (fond(x, y) * pow(2, il * poids(x, y) / 2.2)).rounded())))
            return (v, v, v)
        }
    }

    /// Éclaircir et assombrir : l'inversion du radial et la forme des bords, en propositions seulement,
    /// avec les paramètres qu'add_mask accepte ; un radial inversé posé dans l'ellipse est signalé.
    func testRecetteLightensAndDarkensInPreviewsOnly() throws {
        prepareRecette(virtualCopy: true)
        let apercu = try XCTUnwrap(fake.onSend)
        var inversionIgnoree = false
        fake.onSend = { [unowned fake] command, params in
            apercu(command, params)
            if command == "essayer" {
                fake!.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(Self.rendreMasque(params, inversionIgnoree: inversionIgnoree)))]
            }
        }
        let recette = Recette(lightroom: fake)
        let depart = try recette.etat(5)
        try recette.sequenceTireur(5, depart, "RAW 5")
        XCTAssertEqual(recette.etapes.map(\.nom), ["éclaircir et assombrir : radial inversé et dégradé linéaire (propositions)",
                                                   "éclaircir et assombrir : forme des bords (radial inversé, propositions)"])
        XCTAssertTrue(recette.reussie, recette.etapes.map(\.detail).joined(separator: " | "))
        XCTAssertTrue(recette.etapes[1].detail.contains("à -0.3 IL") && recette.etapes[1].detail.contains("à -0.5 IL"), recette.etapes[1].detail)
        XCTAssertFalse(fake.calls.contains { ["masquer", "appliquer", "annuler", "revenir"].contains($0.command) }, "des propositions seulement")
        // Les bords tels que Claude les pose (Prompts.Tireur) : rayon 0,7, fondu 80, inversé, −0,3 puis −0,5 IL.
        let masques = fake.calls.filter { $0.command == "essayer" }.compactMap { $0.params["masques"]?.array?.first }
        XCTAssertEqual(masques.count, 7, "4 rendus pour l'inversion, 3 pour la forme")
        let bords = masques.suffix(2)
        XCTAssertEqual(bords.map { $0["rayon_x"]?.double }, [0.7, 0.7])
        XCTAssertEqual(bords.map { $0["rayon_y"]?.double }, [0.7, 0.7])
        XCTAssertEqual(bords.map { $0["fondu"]?.double }, [80, 80])
        XCTAssertEqual(bords.map { $0["inverser"]?.bool }, [true, true])
        XCTAssertEqual(bords.map { $0["locaux"]?["LocalExposure2012"]?.double ?? 0 }, [-0.075, -0.125])

        // Un module qui poserait le radial inversé dans l'ellipse : l'étape le dit, rien d'autre n'est fait.
        inversionIgnoree = true
        let fautive = Recette(lightroom: fake)
        XCTAssertThrowsError(try fautive.sequenceTireur(5, depart, "RAW 5"))
        XCTAssertEqual(fautive.etapes.count, 1)
        XCTAssertTrue(fautive.etapes[0].detail.contains("radial inversé : coins"), fautive.etapes[0].detail)
    }

    /// Un rendu de synthèse d'un masque de peau : un damier fin sur le visage, adouci selon la
    /// texture et la clarté du masque et son intensité (CorrectionAmount linéaire, constaté le
    /// 20 octobre 2026). Avec `auCarre`, un module dont l'intensité ne serait pas linéaire.
    static func rendrePeau(_ params: [String: JSONValue], visage: CGRect, auCarre: Bool = false) -> Data {
        let masque = params["masques"]?.array?.first ?? .null
        let quantite = masque["quantite"]?.double ?? 1
        let lissage = -((masque["locaux"]?["LocalTexture"]?.double ?? 0) + (masque["locaux"]?["LocalClarity2012"]?.double ?? 0))
            * (auCarre ? quantite * quantite : quantite)
        let amplitude = 100 * max(0, 1 - lissage)
        let width = 600, height = 400
        return TestSupport.jpegPixels(width: width, height: height) { px, py in
            let x = (Double(px) + 0.5) / Double(width), y = (Double(py) + 0.5) / Double(height)
            guard visage.contains(CGPoint(x: x, y: y)) else { return (128, 128, 128) }
            let v = UInt8(128 + ((px / 2 + py / 2) % 2 == 0 ? 1 : -1) * amplitude / 2)
            return (v, v, v)
        }
    }

    /// La peau dosée : trois doses (ou deux) en propositions, l'intensité linéaire, le refus d'une dose
    /// trop forte, puis la dose par défaut posée, relue et annulée ; une intensité non linéaire est
    /// signalée.
    func testRecetteDosesTheSkinThenRevertsIt() throws {
        prepareRecette(virtualCopy: true)
        var reglages = try XCTUnwrap(fake.replies["reglages"]?.object)
        reglages["tous"] = ["MaskGroupBasedCorrections": [[
            "CorrectionName": "Claude · Peau du visage lisse", "CorrectionAmount": 0.5, "LocalTexture": -0.2, "LocalClarity2012": -0.1,
            "CorrectionMasks": [["What": "Mask/Image", "MaskSubType": 3, "MaskSubCategoryID": 2, "MaskDigest": "ABC"]],
        ]]]
        fake.replies["reglages"] = .object(reglages)
        let visage = CGRect(x: 0.3, y: 0.2, width: 0.4, height: 0.5)
        var auCarre = false
        fake.onSend = { [unowned fake] command, params in
            if command == "essayer" {
                fake!.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(Self.rendrePeau(params, visage: visage, auCarre: auCarre)))]
            }
        }
        let recette = Recette(lightroom: fake)
        let depart = try recette.etat(5)
        try recette.sequencePeau(5, depart, "portrait 5", visage: visage)
        XCTAssertEqual(recette.etapes.map(\.nom), ["peau : trois doses en propositions, détail des joues mesuré",
                                                   "intensité d'un masque : amount 50 = la moitié de la dose (propositions)",
                                                   "peau trop lissée refusée sans smoothing_requested, rien d'écrit",
                                                   "dose par défaut posée à amount 50, relue, annulée"])
        XCTAssertTrue(recette.reussie, recette.etapes.map(\.detail).joined(separator: " | "))
        for dose in ["Peau du visage lisse : ", "Adoucir la peau (Lite) : "] {
            XCTAssertTrue(recette.etapes[0].detail.contains(dose), recette.etapes[0].detail)
        }
        XCTAssertTrue(recette.etapes[0].detail.contains("% du détail gardé"), recette.etapes[0].detail)
        // Une seule écriture, la dose par défaut à moitié, puis défaite.
        let ecritures = fake.calls.filter { $0.command == "masquer" }
        XCTAssertEqual(ecritures.count, 1)
        XCTAssertEqual(ecritures.first?.params["masques"]?.array?.first?["quantite"]?.double, 0.5)
        XCTAssertEqual(ecritures.first?.params["masques"]?.array?.first?["nom"]?.string, "Claude · Peau du visage lisse")
        XCTAssertEqual(fake.commands.filter { $0 == "annuler" }.count, 1)
        XCTAssertFalse(fake.commands.contains("appliquer"))

        // Une intensité qui ne serait pas linéaire : l'étape le dit.
        auCarre = true
        let fautive = Recette(lightroom: fake)
        XCTAssertThrowsError(try fautive.sequencePeau(5, depart, "portrait 5", visage: visage))
        XCTAssertEqual(fautive.etapes.map(\.reussie), [true, false])
        XCTAssertTrue(fautive.etapes[1].detail.contains("contre la moitié de ses curseurs"), fautive.etapes[1].detail)
        // Ni l'écart, ni le témoin ne passent par partChangee : ce lissage fin ne change aucun pixel de
        // plus de 12 niveaux, et l'étape passerait toujours.
        let reduit = Self.rendrePeau(["masques": [["locaux": ["LocalTexture": -0.2, "LocalClarity2012": -0.1], "quantite": 0.5]]], visage: visage, auCarre: true)
        let moitie = Self.rendrePeau(["masques": [["locaux": ["LocalTexture": -0.1, "LocalClarity2012": -0.05], "quantite": 1]]], visage: visage)
        XCTAssertEqual(Recette.partChangee(reduit, moitie), 0)
        XCTAssertGreaterThan(try XCTUnwrap(Recette.ecartMax(reduit, moitie)), Recette.ecartIdentique)
        XCTAssertEqual(try XCTUnwrap(Recette.ecartMax(moitie, moitie)), 0)
        XCTAssertNil(Recette.ecartMax(moitie, TestSupport.jpeg(red: 1, green: 1, blue: 1)), "deux tailles")
    }

    /// Le bilan d'une passe à l'autre : deux vues identiques, la proposition ignorée, l'écart d'une
    /// étape écrite puis défaite ; un module qui ne dit pas les étapes de Claude est signalé.
    func testRecetteReadsTheBilanFromOnePassToTheNext() throws {
        prepareRecette(virtualCopy: true)
        let sombre = TestSupport.jpeg(red: 90, green: 90, blue: 90), clair = TestSupport.jpeg(red: 170, green: 170, blue: 170)
        var etapes = 3, ecrite = false, ditLesEtapes = true
        fake.onSend = { [unowned fake] command, _ in
            switch command {
            case "appliquer": etapes += 1; ecrite = true
            case "annuler": etapes -= 1; ecrite = false
            case "essayer": fake!.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(clair))]
            case "apercu":
                var reponse: [String: JSONValue] = ["chemin": .string(TestSupport.previewFile(ecrite ? clair : sombre)),
                                                    "photo": ["id": 5, "fichier": "X.RAF (Copie 1)"],
                                                    "reglages": ["Exposure2012": .number(ecrite ? 2 : 0)]]
                if ditLesEtapes { reponse["etapes_claude"] = ["nombre": .number(Double(etapes)), "derniere": "Claude · recette"] }
                fake!.replies["apercu"] = .object(reponse)
            default: break
            }
        }
        let recette = Recette(lightroom: fake)
        let depart = try recette.etat(5)
        try recette.etapeBilan(5, "RAW 5", attendu: depart)
        XCTAssertTrue(recette.reussie, recette.etapes.first?.detail ?? "")
        let detail = try XCTUnwrap(recette.etapes.first?.detail)
        XCTAssertTrue(detail.contains("exposition") && detail.contains(" IL)"), detail)
        XCTAssertTrue(detail.hasSuffix("annulé : 1 de moins, sans regression"), detail)
        XCTAssertEqual(fake.commands.filter { ["appliquer", "annuler"].contains($0) }, ["appliquer", "annuler"], "une étape écrite, puis défaite")
        XCTAssertEqual(etapes, 3)

        // Un module d'avant la 1.2 (pas d'etapes_claude) : l'écart se voit, les étapes non.
        ditLesEtapes = false
        let ancien = Recette(lightroom: fake)
        XCTAssertThrowsError(try ancien.etapeBilan(5, "RAW 5", attendu: depart))
        XCTAssertTrue(ancien.etapes.first?.detail.contains("étapes de Claude après l'écriture : absentes") == true, ancien.etapes.first?.detail ?? "")
        XCTAssertEqual(etapes, 3, "défaite même en échec")
    }

    /// L'intention lue au boîtier : dite pour un fichier Fujifilm, sautée pour une autre marque ; le
    /// chemin de l'original ne part pas, la photo ne change pas.
    func testRecetteReadsTheCameraIntention() throws {
        prepareRecette(virtualCopy: true)
        var marque = "FUJIFILM"
        fake.onSend = { [unowned fake] command, _ in
            guard command == "apercu" else { return }
            fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 120, green: 120, blue: 120))),
                                       "photo": ["id": 5, "fichier": "DSCF0001.RAF (Copie 1)", "marque": .string(marque),
                                                 "chemin_original": "/Volumes/Photos/DSCF0001.RAF"],
                                       "echelle_temperature": "kelvins (RAW : 2000 à 50000)", "profil": "Adobe Color",
                                       "appareil": ["marque": .string(marque), "modele": "X-H2S"]]
        }
        func recette(_ lecture: LectureBoitier?) -> Recette {
            let recette = Recette(lightroom: fake)
            recette.tools.lecteurBoitier = LecteurBoitier(delai: 1) { _ in lecture }
            return recette
        }
        let fuji = recette(LectureBoitier(intention: IntentionBoitier(simulation: 0x600, compensation: -1)))
        try fuji.etapeIntention(5, "RAW 5")
        XCTAssertEqual(fuji.etapes.map(\.nom), ["intention lue au boîtier (view_photo, intention_boitier)"])
        let detail = try XCTUnwrap(fuji.etapes.first?.detail)
        XCTAssertTrue(detail.hasPrefix("simulation CLASSIC CHROME"), detail)
        XCTAssertTrue(detail.contains("phrase(s) de lecture"), detail)
        XCTAssertFalse(detail.contains("/Volumes"), detail)
        // Rien de lu dans l'original (absent, ou pas ouvert à temps) : dit, sans échec.
        let rien = recette(nil)
        try rien.etapeIntention(5, "RAW 5")
        XCTAssertTrue(rien.etapes.first?.detail.hasPrefix("rien de lu") == true, rien.etapes.first?.detail ?? "")
        // Une autre marque : sautée.
        marque = "Apple"
        let autre = recette(LectureBoitier(intention: IntentionBoitier(simulation: 0x600)))
        try autre.etapeIntention(5, "RAW 5")
        XCTAssertTrue(autre.etapes.first?.detail.hasPrefix("sautée") == true, autre.etapes.first?.detail ?? "")
        XCTAssertFalse(fake.calls.contains { ["appliquer", "masquer", "essayer", "revenir", "annuler"].contains($0.command) }, "lecture seule")
    }
}
