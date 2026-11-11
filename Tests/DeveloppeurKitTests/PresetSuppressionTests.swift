import XCTest
@testable import DeveloppeurKit

/// Poussière et imperfections par les paramètres prédéfinis « Claude / Poussière » et « Claude /
/// Imperfections » (10 novembre 2026) : le serveur lit leur fichier .xmp (dossier temporaire,
/// jamais le vrai dossier de Camera Raw) et ne les applique que valides.
final class PresetSuppressionTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!
    var dossier: URL!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
        dossier = TestSupport.temporaryDirectory().appendingPathComponent("Settings")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        tools.dossierParametresPredefinis = dossier
    }

    /// Un filtre de Supprimer comme Lightroom 16.0 le range (relevé dans les fichiers de Dany).
    struct Filtre {
        var id: Int
        var signal = false
        var table = true
        var digest: String { String(format: "%032X", id * 7919) }
    }

    /// Un fichier .xmp de paramètre prédéfini, de la forme de ceux de Lightroom 16.0.
    static func xmp(nom: String, groupe: String = "Claude", uuid: String = "4E52288140DA481F80CD64A55C066073",
                    filtres: [Filtre], attributs: String = "", elements: String = "") -> String {
        let tables = filtres.filter(\.table).map { "   crs:Table_\($0.digest)=\"}3000[s7^pk95Jad'IwSmd\"\n" }.joined()
        let lis = filtres.map { f in
            """
                  <rdf:li
                   crs:Name=""
                   crs:Title=""
                   crs:FilterID="\(f.id)"
                   crs:OrderIndexN="750000000"
                   crs:SrcBoundsBottom="100"
            \(f.signal ? "       crs:IsSignalForDelete=\"true\"\n" : "")       crs:CompressedSettings="\(f.digest)"/>

            """
        }.joined()
        return """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00        ">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
           crs:PresetType="Normal"
           crs:Cluster=""
           crs:UUID="\(uuid)"
           crs:SupportsAmount2="False"
           crs:SupportsAmount="False"
           crs:SupportsColor="True"
           crs:ShowInPresets="True"
           crs:Version="19.0"
           crs:CompatibleVersion="285212672"
           crs:ProcessVersion="15.4"
        \(tables)\(attributs)   crs:AllowFilters="1"
           crs:HasSettings="True">
           <crs:Name>
            <rdf:Alt>
             <rdf:li xml:lang="x-default">\(nom)</rdf:li>
            </rdf:Alt>
           </crs:Name>
           <crs:ShortName>
            <rdf:Alt>
             <rdf:li xml:lang="x-default"/>
            </rdf:Alt>
           </crs:ShortName>
           <crs:Group>
            <rdf:Alt>
             <rdf:li xml:lang="x-default">\(groupe)</rdf:li>
            </rdf:Alt>
           </crs:Group>
        \(elements)   <crs:FilterList rdf:parseType="Resource">
            <crs:Filters>
             <rdf:Seq>
        \(lis)     </rdf:Seq>
            </crs:Filters>
           </crs:FilterList>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }

    private func ecrire(_ texte: String, _ fichier: String) {
        try? texte.write(to: dossier.appendingPathComponent(fichier), atomically: true, encoding: .utf8)
    }

    private func appliquer() -> FakeLightroom.Call? {
        fake.calls.last { $0.command == "appliquer" }
    }

    // MARK: Lecture du fichier

    func testValideEffacementSeulDangereuxAbsent() {
        // Absent : rien dans le dossier (un autre paramètre du groupe ne compte pas).
        ecrire(Self.xmp(nom: "Personnes", filtres: [Filtre(id: 4)]), "Personnes.xmp")
        XCTAssertEqual(PresetSuppression.chercher(.poussiere, dans: dossier), .absent)

        // Effacement seul : les deux paramètres de Dany le 10 novembre 2026 (FilterID 6 et 7 avec
        // IsSignalForDelete, table présente).
        ecrire(Self.xmp(nom: "Poussière", filtres: [Filtre(id: 6, signal: true)]), "Poussière.xmp")
        ecrire(Self.xmp(nom: "Imperfections", uuid: "4542523C096C4176B77F638768B233B4", filtres: [Filtre(id: 7, signal: true)]), "Imperfections.xmp")
        guard case .effacementSeul = PresetSuppression.chercher(.poussiere, dans: dossier) else {
            return XCTFail("un signal d'effacement n'est pas une suppression")
        }
        guard case .effacementSeul = PresetSuppression.chercher(.imperfections, dans: dossier) else {
            return XCTFail("idem pour les imperfections")
        }

        // Valide : le filtre fait, avec sa table ; trouvé sans accent dans un sous-dossier.
        try? FileManager.default.removeItem(at: dossier.appendingPathComponent("Poussière.xmp"))
        let sous = dossier.appendingPathComponent("Claude")
        try? FileManager.default.createDirectory(at: sous, withIntermediateDirectories: true)
        try? Self.xmp(nom: "Poussiere", filtres: [Filtre(id: 6)]).write(to: sous.appendingPathComponent("p.xmp"), atomically: true, encoding: .utf8)
        guard case .valide(let uuid, _) = PresetSuppression.chercher(.poussiere, dans: dossier) else {
            return XCTFail("paramètre valide refusé")
        }
        XCTAssertEqual(uuid, "4E52288140DA481F80CD64A55C066073")

        // Dangereux : signaux d'effacement d'autres filtres (le « Personnes » de Dany en portait pour
        // 3, 6 et 7), autre filtre fait, autres réglages.
        let cas: [(String, String)] = [
            (Self.xmp(nom: "Imperfections", filtres: [Filtre(id: 7), Filtre(id: 3, signal: true), Filtre(id: 6, signal: true)]), "effacerait les reflets"),
            (Self.xmp(nom: "Imperfections", filtres: [Filtre(id: 7), Filtre(id: 4)]), "ferait aussi les passants"),
            (Self.xmp(nom: "Imperfections", filtres: [Filtre(id: 7)], attributs: "   crs:Exposure2012=\"+0.50\"\n"), "Exposure2012"),
            (Self.xmp(nom: "Imperfections", filtres: [Filtre(id: 7)], elements: "   <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li></rdf:Seq></crs:ToneCurvePV2012>\n"), "ToneCurvePV2012"),
        ]
        for (texte, raison) in cas {
            ecrire(texte, "Imperfections.xmp")
            guard case .dangereux(_, let raisons) = PresetSuppression.chercher(.imperfections, dans: dossier) else {
                return XCTFail("dangereux attendu : \(raison)")
            }
            XCTAssertTrue(raisons.joined().contains(raison), "\(raisons) sans « \(raison) »")
        }

        // Incomplet : le filtre fait sans sa table, ou absent du paramètre.
        ecrire(Self.xmp(nom: "Imperfections", filtres: [Filtre(id: 7, table: false)]), "Imperfections.xmp")
        guard case .incomplet = PresetSuppression.chercher(.imperfections, dans: dossier) else { return XCTFail("sans recette") }
        ecrire(Self.xmp(nom: "Imperfections", filtres: []), "Imperfections.xmp")
        guard case .incomplet = PresetSuppression.chercher(.imperfections, dans: dossier) else { return XCTFail("sans filtre") }

        // Un autre groupe ne compte pas ; deux du groupe Claude : refus.
        ecrire(Self.xmp(nom: "Imperfections", groupe: "Portraits", filtres: [Filtre(id: 7)]), "Imperfections.xmp")
        XCTAssertEqual(PresetSuppression.chercher(.imperfections, dans: dossier), .absent)
        ecrire(Self.xmp(nom: "Poussière", filtres: [Filtre(id: 6)]), "Poussière 2.xmp")
        guard case .plusieurs(let fichiers) = PresetSuppression.chercher(.poussiere, dans: dossier) else { return XCTFail("deux paramètres") }
        XCTAssertEqual(fichiers.count, 2)
    }

    // MARK: remove_distractions

    func testDustAppliqueLeParametreValideParLeCheminDesParametresPredefinis() throws {
        ecrire(Self.xmp(nom: "Poussière", filtres: [Filtre(id: 6)]), "Poussière.xmp")
        let result = tools.call(name: "remove_distractions", arguments: [
            "photo_id": 7, "dust": ["remove": true], "reason": "Taches de poussière dans le ciel.", "confirm": true,
        ])
        XCTAssertFalse(result.isError, result.text)
        let appel = try XCTUnwrap(appliquer(), "apply_settings avec preset → applyDevelopPreset du module")
        XCTAssertEqual(appel.params["preset"]?.string, "4E52288140DA481F80CD64A55C066073", "par son UUID")
        XCTAssertEqual(appel.params["etape"]?.string, "poussière", "étape « Claude · poussière »")
        XCTAssertEqual(appel.params["photos"]?.array?.first?.int, 7)
        XCTAssertEqual(appel.params["confirme"]?.bool, true, "mode « Proposer d'abord » : l'accord passe")
        XCTAssertEqual(appel.params["raison"]?.string, "Taches de poussière dans le ciel.")
        XCTAssertNil(appel.params["reglages"]?.object?.first, "rien d'autre que le paramètre prédéfini")
        XCTAssertTrue(result.text.contains("view_photo avec region"), "vérifier ensuite par un zoom")
        XCTAssertNil(fake.calls.first { $0.command == "supprimer" }, "pas la commande supprimer")

        // Sans confirm : le module juge le mode ; son refus nomme l'outil à rappeler.
        fake.errors["appliquer"] = LightroomError.plugin("Mode « Proposer d'abord » actif dans Lightroom : rien n'a été appliqué. … puis rappeler apply_settings avec confirm = true.")
        let refus = tools.call(name: "remove_distractions", arguments: ["dust": [:], "step_name": "poussière"])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("rappeler remove_distractions avec confirm = true"), refus.text)
        XCTAssertEqual(fake.calls.last { $0.command == "appliquer" }?.params["confirme"]?.bool, false)
    }

    func testImperfectionsAppliqueLeParametreValide() throws {
        ecrire(Self.xmp(nom: "Imperfections", uuid: "4542523C096C4176B77F638768B233B4", filtres: [Filtre(id: 7)]), "Imperfections.xmp")
        let result = tools.call(name: "remove_distractions", arguments: ["imperfections": true, "step_name": "boutons"])
        XCTAssertFalse(result.isError, result.text)
        let appel = try XCTUnwrap(appliquer())
        XCTAssertEqual(appel.params["preset"]?.string, "4542523C096C4176B77F638768B233B4")
        XCTAssertEqual(appel.params["etape"]?.string, "boutons")
        XCTAssertNil(appel.params["photos"], "la photo active")
        let sansNom = tools.call(name: "remove_distractions", arguments: ["imperfections": true])
        XCTAssertFalse(sansNom.isError, sansNom.text)
        XCTAssertEqual(appliquer()?.params["etape"]?.string, "imperfections", "étape « Claude · imperfections »")
        XCTAssertTrue(tools.call(name: "remove_distractions", arguments: ["imperfections": false]).isError, "les rendre : undo_last")
        XCTAssertTrue(tools.call(name: "remove_distractions", arguments: ["imperfections": true, "dust": [:]]).isError, "un appel chacun")
    }

    func testRefusSansRienEnvoyerEtCommentLeRefaire() {
        // Absent.
        var refus = tools.call(name: "remove_distractions", arguments: ["dust": ["remove": true], "step_name": "x"])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("Pas de paramètre prédéfini « Claude / Poussière »"), refus.text)
        XCTAssertTrue(refus.text.contains("cocher seulement Supprimer › Poussière"), refus.text)
        XCTAssertTrue(refus.text.contains("Copier puis Coller de Lightroom"), "la série à la main, d'ici là")

        // Effacement seul : appliqué, il retirerait la suppression.
        ecrire(Self.xmp(nom: "Poussière", filtres: [Filtre(id: 6, signal: true)]), "Poussière.xmp")
        refus = tools.call(name: "remove_distractions", arguments: ["dust": [:], "step_name": "x"])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("signal d'effacement"), refus.text)
        XCTAssertTrue(refus.text.contains("clic droit sur « Claude / Poussière » › Mettre à jour avec les paramètres actuels, Ne rien sélectionner, cocher seulement Supprimer › Poussière"), refus.text)

        // Dangereux.
        ecrire(Self.xmp(nom: "Imperfections", filtres: [Filtre(id: 7), Filtre(id: 6, signal: true)]), "Imperfections.xmp")
        refus = tools.call(name: "remove_distractions", arguments: ["imperfections": true, "step_name": "x"])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("effacerait la poussière déjà faits"), refus.text)
        XCTAssertTrue(refus.text.contains("retouch_spots"), "d'ici là, retouch_spots")

        // Sans dossier lu (le cas des tests par défaut, jamais le vrai dossier).
        tools.dossierParametresPredefinis = nil
        refus = tools.call(name: "remove_distractions", arguments: ["imperfections": true, "step_name": "x"])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(ToolHandler(lightroom: FakeLightroom()).dossierParametresPredefinis == nil, "nil par défaut")

        XCTAssertTrue(fake.calls.allSatisfy { $0.command != "appliquer" && $0.command != "supprimer" }, "rien envoyé au module")
    }

    func testConsignesInvitesEtDescriptionLesNomment() throws {
        XCTAssertFalse(ServerInfo.instructions.contains("main dans Lightroom : poussière"), "plus à la main")
        XCTAssertTrue(ServerInfo.instructions.contains("poussière du capteur (dust), imperfections d'un portrait (imperfections)"))
        XCTAssertTrue(Prompts.retouchePro.render([:]).contains("remove_distractions avec dust"), "Retouche pro : la poussière du capteur")
        XCTAssertTrue(Prompts.portrait.render([:]).contains("remove_distractions avec imperfections"), "Portrait : les imperfections")
        XCTAssertTrue(Prompts.portrait.render([:]).contains("jamais les grains de beauté"))
        let outil = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "remove_distractions" })
        XCTAssertNotNil(outil["inputSchema"]?["properties"]?["imperfections"])
        let description = try XCTUnwrap(outil["description"]?.string)
        XCTAssertTrue(description.contains("« Claude / Poussière » et « Claude / Imperfections »"))
        XCTAssertTrue(description.hasPrefix("Suppression des distractions de Lightroom : reflets"), "l'essentiel en tête")
    }

    func testDustFalseGardeSonSens() {
        let result = tools.call(name: "remove_distractions", arguments: ["dust": ["remove": false], "photo_id": 7, "step_name": "sans poussière"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["poussiere"]?["actif"]?.bool, false)
        XCTAssertNil(appliquer())
    }
}
