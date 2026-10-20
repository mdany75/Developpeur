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
}
