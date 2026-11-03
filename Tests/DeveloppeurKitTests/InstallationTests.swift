import XCTest
@testable import DeveloppeurKit

/// Mises à jour par le SSD (1.7, Installation.swift) : comparaison des versions et des ensembles, le
/// manifeste, les refus (dossier commun non réglé ou absent, mflux en cours, Fibo 2 Studio ouvert,
/// place, verrou), les copies par « .partiel » et leur reprise, le dépôt et l'installation de chaque
/// élément sur un faux SSD et deux faux domiciles (deux Mac), avec un faux uv (script) qui vérifie
/// que l'installation de mflux se fait hors ligne. Jamais le vrai dossier personnel, ni le vrai cache
/// de Hugging Face, ni /Applications, ni le vrai uv.
final class InstallationTests: XCTestCase {
    var base: URL!
    var ssd: URL!
    var fauxUV: URL!
    var mfluxTourne = false
    var fiboOuvert = false
    var libre: Int64? = nil
    var avances: [Installation.Avance] = []
    let fm = FileManager.default

    override func setUp() {
        base = TestSupport.temporaryDirectory()
        ssd = base.appendingPathComponent("Volumes/Photos/Développeur partagé", isDirectory: true)
        try? fm.createDirectory(at: ssd, withIntermediateDirectories: true)
        fauxUV = base.appendingPathComponent("outils/uv")
        ecrireUV()
        mfluxTourne = false
        fiboOuvert = false
        libre = nil
        avances = []
    }

    override func tearDown() {
        try? fm.removeItem(at: base)
    }

    // MARK: Aides

    func domicile(_ nom: String) -> URL { base.appendingPathComponent(nom, isDirectory: true) }

    /// Un Mac simulé : son domicile, ses applications, son pointeur vers le faux SSD (sauf `pointeur` faux).
    func mac(_ nom: String, pointeur: URL?? = .some(nil)) -> Installation {
        let d = domicile(nom)
        let racine = d.appendingPathComponent("Library/Application Support/Developpeur", isDirectory: true)
        try? fm.createDirectory(at: racine, withIntermediateDirectories: true)
        if case .some(let p) = pointeur {
            let dossier = p ?? ssd!
            try? Data("{\"format\":1,\"dossier\":\"\(dossier.path)\"}".utf8).write(to: racine.appendingPathComponent("dossier-commun.json"))
        }
        let env = Installation.Environnement(
            donnees: DossierDonnees(racineLocale: racine), domicile: d, applications: d.appendingPathComponent("Applications", isDirectory: true),
            uvCandidats: [d.appendingPathComponent(".local/bin/uv"), fauxUV],
            nomOrdinateur: { "Mac \(nom)" }, mfluxEnCours: { [unowned self] in self.mfluxTourne },
            fiboStudioOuvert: { [unowned self] in self.fiboOuvert }, placeLibre: { [unowned self] _ in self.libre },
            corbeille: { [unowned self] url in
                let c = self.base.appendingPathComponent("Corbeille-\(nom)", isDirectory: true)
                try self.fm.createDirectory(at: c, withIntermediateDirectories: true)
                try self.fm.moveItem(at: url, to: c.appendingPathComponent(url.lastPathComponent))
            },
            avancement: { [unowned self] a in self.avances.append(a) },
            maintenant: { Date(timeIntervalSince1970: 1_793_750_400) })
        XCTAssertTrue(env.domicile.path.hasPrefix(base.path))
        return Installation(env)
    }

    /// Le faux uv : `--version`, `python install` (exige un miroir file:// qui a l'archive et le réseau
    /// coupé), `tool install` (en ligne : remplit le cache et garde l'archive de Python ; hors ligne :
    /// exige le cache, UV_OFFLINE et le Python installé). Chaque appel est noté dans `journal`.
    func ecrireUV(version: String = "0.13.5") {
        try? fm.createDirectory(at: fauxUV.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = #"""
        #!/bin/bash
        J="JOURNAL"
        printf '%s | v=VERSION offline=%s proxy=%s\n' "$*" "${UV_OFFLINE:-}" "${HTTPS_PROXY:-}" >> "$J"
        case "$1" in
        --version) echo "uv VERSION (essai)"; exit 0 ;;
        python)
            [[ -n "${HTTPS_PROXY:-}" ]] || { echo "réseau non coupé"; exit 3; }
            m="${UV_PYTHON_INSTALL_MIRROR#file://}"; m="$(printf '%b' "${m//%/\\x}")"
            ls "$m"/*/"cpython-$3+"*.tar.gz >/dev/null 2>&1 || { echo "pas d'archive dans le miroir $m"; exit 1; }
            mkdir -p "$UV_PYTHON_INSTALL_DIR/cpython-$3-macos-aarch64-none/bin"; exit 0 ;;
        tool)
            v="${3#mflux==}"; py="$5"
            if [[ " $* " == *" --offline "* ]]; then
                [[ -f "$UV_CACHE_DIR/wheels/mflux-$v.whl" ]] || { echo "hors ligne : mflux $v absent du cache"; exit 2; }
                [[ "${UV_OFFLINE:-}" == 1 ]] || { echo "UV_OFFLINE absent"; exit 4; }
                [[ -d "$UV_PYTHON_INSTALL_DIR/cpython-$py-macos-aarch64-none" ]] || { echo "Python $py absent"; exit 5; }
            else
                mkdir -p "$UV_CACHE_DIR/wheels" "$UV_PYTHON_CACHE_DIR"
                echo roue > "$UV_CACHE_DIR/wheels/mflux-$v.whl"
                echo archive > "$UV_PYTHON_CACHE_DIR/8dc60610a-cpython-$py-20261021-aarch64-apple-darwin-install_only_stripped.tar.gz"
            fi
            d="$UV_TOOL_DIR/mflux"; s="$d/lib/python3.13/site-packages"
            rm -rf "$s"/mflux-*.dist-info; mkdir -p "$s/mflux-$v.dist-info" "$UV_TOOL_BIN_DIR"
            printf 'home = x\nversion_info = %s\n' "$py" > "$d/pyvenv.cfg"
            printf '#!/bin/sh\necho usage\n' > "$UV_TOOL_BIN_DIR/mflux-generate-fibo2-edit"; chmod +x "$UV_TOOL_BIN_DIR/mflux-generate-fibo2-edit"
            exit 0 ;;
        esac
        exit 9
        """#.replacingOccurrences(of: "VERSION", with: version)
            .replacingOccurrences(of: "JOURNAL", with: fauxUV.deletingLastPathComponent().appendingPathComponent("journal").path)
        try? Data(script.utf8).write(to: fauxUV)
        chmod(fauxUV.path, 0o755)
    }

    var journalUV: String { (try? String(contentsOf: fauxUV.deletingLastPathComponent().appendingPathComponent("journal"), encoding: .utf8)) ?? "" }

    func ecrire(_ url: URL, _ texte: String) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(texte.utf8).write(to: url)
    }

    func lien(_ url: URL, _ destination: String) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }

    /// mflux installé « par uv » dans un domicile.
    func poserMflux(_ d: URL, version: String = "0.24.0", python: String = "3.13.17") {
        let dossier = d.appendingPathComponent(".local/share/uv/tools/mflux")
        try? fm.createDirectory(at: dossier.appendingPathComponent("lib/python3.13/site-packages/mflux-\(version).dist-info"), withIntermediateDirectories: true)
        ecrire(dossier.appendingPathComponent("pyvenv.cfg"), "home = x\nimplementation = CPython\nversion_info = \(python)\n")
    }

    func poserClaude(_ d: URL, version: String) {
        let f = d.appendingPathComponent(".local/share/claude/versions/\(version)")
        ecrire(f, "#!/bin/sh\necho '\(version) (Claude Code)'\n")
        chmod(f.path, 0o755)
        try? fm.removeItem(at: d.appendingPathComponent(".local/bin/claude"))
        lien(d.appendingPathComponent(".local/bin/claude"), f.path)
    }

    func poserFibo(_ d: URL, version: String) {
        let app = d.appendingPathComponent("Applications/Fibo 2 Studio.app/Contents")
        ecrire(app.appendingPathComponent("Info.plist"), """
        <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>\(version)</string></dict></plist>
        """)
        ecrire(app.appendingPathComponent("MacOS/Fibo 2 Studio"), "binaire \(version)")
    }

    /// Une archive de Développeur : Developpeur/{Developpeur.lrplugin/Info.lua, install.sh}.
    func archive(version: String, essai: Bool = false) -> URL {
        let parties = version.split(separator: ".").map(String.init)
        let nom = "archive-\(version)\(essai ? "-essai" : "")"
        let dossier = base.appendingPathComponent("\(nom)/Developpeur", isDirectory: true)
        ecrire(dossier.appendingPathComponent("Developpeur.lrplugin/Info.lua"),
               "return {\n    VERSION = { major = \(parties[0]), minor = \(parties[1]), revision = \(parties.count > 2 ? parties[2] : "0"), build = 25 },\n}\n")
        ecrire(dossier.appendingPathComponent("install.sh"),
               "#!/bin/bash\nprintf '%s %s\\n' '\(version)' \"${DEVELOPPEUR_DEPUIS_SSD:-}\" > \"${HOME}/installe.txt\"\necho 'Module Lightroom installé'\n"
               + "cat <<FIN\n\nProchaines étapes :\n  - Claude Desktop est ouvert : il réécrira sa configuration\n    sans le connecteur.\n"
               + "  - Dans Claude Code, ouvrir une nouvelle session.\nFIN\n")
        if essai { ecrire(dossier.appendingPathComponent("ESSAI"), "Archive d'essai : SKIP_NOTARIZE=1.\n") }
        let zip = base.appendingPathComponent("\(nom)/Developpeur.zip")
        let r = Installation.lancerProcessus(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--keepParent", dossier.path, zip.path], nil, 60)
        XCTAssertEqual(r.code, 0, r.sortie)
        return zip
    }

    func manifeste() -> [String: JSONValue] {
        let data = (try? Data(contentsOf: ssd.appendingPathComponent("Installation/manifeste.json"))) ?? Data()
        return (try? JSONCoding.parse(data))?["elements"]?.object ?? [:]
    }

    func etat(_ m: Installation, _ e: Installation.Element) throws -> Installation.Etat {
        try XCTUnwrap(m.comparer().first { $0.element == e }).etat
    }

    func partiels(_ url: URL) -> [String] {
        (fm.enumerator(atPath: url.path)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".partiel") }
    }

    // MARK: Comparaison

    func testComparaisonDesVersionsEtDesEnsembles() {
        typealias C = Installation.Cote
        XCTAssertEqual(Installation.comparer(mac: C(version: "1.6.10"), ssd: C(version: "1.6.9")), .macPlusRecent)
        XCTAssertEqual(Installation.comparer(mac: C(version: "1.6.9"), ssd: C(version: "1.6.10")), .ssdPlusRecent)
        XCTAssertEqual(Installation.comparer(mac: C(version: "1.7"), ssd: C(version: "1.7.0")), .aJour)
        XCTAssertEqual(Installation.comparer(mac: C(version: "2.8.1"), ssd: C(version: "2.8.1")), .aJour)
        XCTAssertEqual(Installation.comparer(mac: nil, ssd: C(version: "1")), .absentDuMac)
        XCTAssertEqual(Installation.comparer(mac: C(version: "1"), ssd: nil), .absentDuSSD)
        XCTAssertEqual(Installation.comparer(mac: nil, ssd: nil), .absentPartout)
        let a = C(version: "x", ensemble: ["m@1", "m@2"]), b = C(version: "y", ensemble: ["m@1"]), c = C(version: "z", ensemble: ["n@1"])
        XCTAssertEqual(Installation.comparer(mac: a, ssd: b), .macPlusRecent)
        XCTAssertEqual(Installation.comparer(mac: b, ssd: a), .ssdPlusRecent)
        XCTAssertEqual(Installation.comparer(mac: b, ssd: c), .differents)
        XCTAssertTrue(Installation.Etat.differents.aDeposer && Installation.Etat.differents.aInstaller)
        XCTAssertFalse(Installation.Etat.aJour.aDeposer || Installation.Etat.aJour.aInstaller)
    }

    func testVersionDuModule() {
        XCTAssertEqual(Installation.versionModule(texte: "VERSION = { major = 1, minor = 6, revision = 7, build = 24 },"), "1.6.7")
        XCTAssertEqual(Installation.versionModule(texte: "VERSION = { major = 1, minor = 7, revision = 0, build = 25 }"), "1.7")
        XCTAssertNil(Installation.versionModule(texte: "rien"))
    }

    // MARK: Refus

    func testDossierCommunNonRegleOuAbsent() {
        let sans = mac("sans", pointeur: .none)
        XCTAssertThrowsError(try sans.comparer()) { XCTAssertEqual($0.localizedDescription, Installation.texteNonRegle) }
        let absent = base.appendingPathComponent("Volumes/Débranché/Commun")
        let debranche = mac("debranche", pointeur: .some(absent))
        XCTAssertThrowsError(try debranche.executer(deposer: true, elements: nil)) {
            XCTAssertEqual($0.localizedDescription, DossierDonnees.texteIntrouvable(absent.path))
        }
        XCTAssertFalse(fm.fileExists(atPath: absent.path), "rien n'est créé à la place du dossier commun")
    }

    func testMfluxEnCoursEtFiboOuvertRefuses() throws {
        let m1 = mac("un")
        poserMflux(m1.env.domicile)
        poserCacheHF(m1.env.cacheHF)
        mfluxTourne = true
        let (_, faits) = try m1.executer(deposer: true, elements: [.mflux, .modelesHF])
        XCTAssertEqual(faits.map(\.action), ["refuse", "refuse"])
        XCTAssertTrue(faits[0].texte.contains(Installation.texteMfluxEnCours))
        XCTAssertFalse(fm.fileExists(atPath: ssd.appendingPathComponent("Installation/mflux").path))
        mfluxTourne = false

        poserFibo(m1.env.domicile, version: "2.8.1")
        _ = try m1.executer(deposer: true, elements: [.fibo2studio])
        let m2 = mac("deux")
        poserFibo(m2.env.domicile, version: "2.7")
        fiboOuvert = true
        let (_, f2) = try m2.executer(deposer: false, elements: [.fibo2studio])
        XCTAssertEqual(f2.first?.action, "refuse")
        XCTAssertTrue(f2[0].texte.contains("Fibo 2 Studio est ouvert"))
        XCTAssertEqual(Installation.versionApplication(m2.env.applicationFibo), "2.7", "l'application ouverte n'est jamais touchée")

        // Fermée, elle est remplacée et l'ancienne va à la Corbeille ; sur un Mac qui ne l'avait pas,
        // il n'y a pas d'ancienne version à annoncer.
        fiboOuvert = false
        let (_, f3) = try m2.executer(deposer: false, elements: [.fibo2studio])
        XCTAssertEqual(f3.first?.action, "installe", f3.map(\.texte).joined(separator: "\n"))
        XCTAssertTrue(f3[0].texte.contains("dans la Corbeille"), f3[0].texte)
        let m3 = mac("trois")
        let (_, f4) = try m3.executer(deposer: false, elements: [.fibo2studio])
        XCTAssertEqual(f4.first?.action, "installe", f4.map(\.texte).joined(separator: "\n"))
        XCTAssertFalse(f4[0].texte.contains("Corbeille"), f4[0].texte)
    }

    func testPlaceInsuffisanteRefuseeAvantToute() throws {
        let m1 = mac("un")
        poserClaude(m1.env.domicile, version: "2.1.303")
        libre = 10_000
        let (_, faits) = try m1.executer(deposer: true, elements: [.claudeCode])
        XCTAssertEqual(faits.first?.action, "refuse")
        XCTAssertTrue(faits[0].texte.contains("place insuffisante"), faits[0].texte)
        XCTAssertFalse(fm.fileExists(atPath: ssd.appendingPathComponent("Installation/claude_code").path))
        XCTAssertNil(manifeste()["claude_code"])
    }

    func testVerrouUneSeuleMiseAJourALaFois() throws {
        let m1 = mac("un")
        let fd = try m1.prendreVerrou()
        defer { close(fd) }
        XCTAssertThrowsError(try m1.executer(deposer: true, elements: nil)) { XCTAssertEqual($0.localizedDescription, Installation.texteVerrou) }
    }

    // MARK: Dépôt et installation

    func testClaudeUvEtFiboDuPremierMacAuSecond() throws {
        let m1 = mac("un"), m2 = mac("deux")
        poserClaude(m1.env.domicile, version: "2.1.303")
        poserFibo(m1.env.domicile, version: "2.8.1")
        poserFibo(m2.env.domicile, version: "2.7")
        XCTAssertEqual(try etat(m1, .claudeCode), .absentDuSSD)
        XCTAssertEqual(try etat(m1, .uv), .absentDuSSD)
        let (lignes, faits) = try m1.executer(deposer: true, elements: nil)
        XCTAssertEqual(Set(faits.filter { $0.action == "depose" }.map(\.element)), [.uv, .claudeCode, .fibo2studio], faits.map(\.texte).joined(separator: "\n"))
        XCTAssertTrue(lignes.filter { [.uv, .claudeCode, .fibo2studio].contains($0.element) }.allSatisfy { $0.etat == .aJour })
        // Le manifeste : version, fichiers, taille, empreinte, date et Mac du dépôt.
        let claude = try XCTUnwrap(manifeste()["claude_code"])
        XCTAssertEqual(claude["version"]?.string, "2.1.303")
        XCTAssertEqual(claude["depuis"]?.string, "Mac un")
        XCTAssertNotNil(claude["depose_le"]?.string)
        let fichier = try XCTUnwrap(claude["fichiers"]?.array?.first)
        XCTAssertEqual(fichier["chemin"]?.string, "claude_code/claude-2.1.303")
        XCTAssertEqual(fichier["sha256"]?.string?.count, 64)
        XCTAssertEqual(manifeste()["uv"]?["version"]?.string, "0.13.5")
        XCTAssertEqual(manifeste()["fibo2studio"]?["version"]?.string, "2.8.1")
        XCTAssertEqual(partiels(ssd), [], "aucun .partiel laissé")

        // Le second Mac : absent ou plus ancien, installé depuis le SSD.
        XCTAssertEqual(try etat(m2, .claudeCode), .absentDuMac)
        XCTAssertEqual(try etat(m2, .fibo2studio), .ssdPlusRecent)
        let (apres, installes) = try m2.executer(deposer: false, elements: nil)
        XCTAssertEqual(Set(installes.filter { $0.action == "installe" }.map(\.element)), [.claudeCode, .fibo2studio], installes.map(\.texte).joined(separator: "\n"))
        let lienClaude = try fm.destinationOfSymbolicLink(atPath: m2.env.lienClaude.path)
        XCTAssertEqual(lienClaude, m2.env.versionsClaude.appendingPathComponent("2.1.303").path)
        XCTAssertTrue(fm.isExecutableFile(atPath: lienClaude))
        XCTAssertEqual(Installation.versionApplication(m2.env.applicationFibo), "2.8.1")
        XCTAssertTrue(fm.fileExists(atPath: base.appendingPathComponent("Corbeille-deux/Fibo 2 Studio.app").path), "l'ancienne Fibo 2 Studio à la Corbeille")
        XCTAssertEqual(apres.first { $0.element == .claudeCode }?.etat, .aJour)
        XCTAssertEqual(Installation.aRelancer(installes), ["Claude Code : ouvrir une nouvelle session (la fenêtre Claude relance le sien d'elle-même).", "Fibo 2 Studio : le rouvrir."])
        // uv du SSD : le second Mac a le même (faux uv commun) : à jour, rien d'installé.
        XCTAssertEqual(installes.first { $0.element == .uv }?.action, nil)
    }

    func testUvPlusAncienRemplaceDansLocalBin() throws {
        let m1 = mac("un")
        _ = try m1.executer(deposer: true, elements: [.uv])
        // Le second Mac n'a qu'un uv plus ancien (le faux devient 0.12.0) : celui du SSD va dans ~/.local/bin.
        let ancien = fm.contents(atPath: ssd.appendingPathComponent("Installation/uv/uv").path)
        ecrireUV(version: "0.12.0")
        let m2 = mac("deux")
        XCTAssertEqual(try etat(m2, .uv), .ssdPlusRecent)
        let (_, faits) = try m2.executer(deposer: false, elements: [.uv])
        XCTAssertEqual(faits.first?.action, "installe", faits.first?.texte ?? "")
        let installe = m2.env.binLocal.appendingPathComponent("uv")
        XCTAssertEqual(fm.contents(atPath: installe.path), ancien)
        XCTAssertTrue(fm.isExecutableFile(atPath: installe.path))
        XCTAssertEqual(try etat(m2, .uv), .aJour)
    }

    func testMfluxDeposeEnLigneInstalleHorsLigne() throws {
        let m1 = mac("un"), m2 = mac("deux")
        poserMflux(m1.env.domicile, version: "0.24.0", python: "3.13.17")
        let (_, faits) = try m1.executer(deposer: true, elements: [.uv, .mflux])
        XCTAssertEqual(faits.map(\.action), ["depose", "depose"], faits.map(\.texte).joined(separator: "\n"))
        let dossier = ssd.appendingPathComponent("Installation/mflux")
        XCTAssertTrue(fm.fileExists(atPath: dossier.appendingPathComponent("cache/wheels/mflux-0.24.0.whl").path))
        XCTAssertTrue(fm.fileExists(atPath: dossier.appendingPathComponent(
            "python/20261021/cpython-3.13.17+20261021-aarch64-apple-darwin-install_only_stripped.tar.gz").path), "l'archive au chemin du miroir")
        XCTAssertFalse(fm.fileExists(atPath: dossier.appendingPathComponent("python-archives").path))
        XCTAssertFalse(fm.fileExists(atPath: m1.env.temporaire.appendingPathComponent("mflux-depot").path), "dossiers d'outils temporaires retirés")
        XCTAssertEqual(manifeste()["mflux"]?["python"]?.string, "3.13.17")
        XCTAssertEqual(manifeste()["mflux"]?["version"]?.string, "0.24.0")
        // Le vrai mflux du premier Mac n'a pas bougé (uv a travaillé dans des dossiers temporaires).
        XCTAssertEqual(m1.mfluxDuMac()?.version, "0.24.0")
        XCTAssertFalse(journalUV.contains(m1.env.outilsUV.path))

        XCTAssertEqual(try etat(m2, .mflux), .absentDuMac)
        let (_, installes) = try m2.executer(deposer: false, elements: nil)
        let mflux = try XCTUnwrap(installes.first { $0.element == .mflux })
        XCTAssertEqual(mflux.action, "installe", mflux.texte)
        XCTAssertEqual(m2.mfluxDuMac()?.version, "0.24.0")
        XCTAssertTrue(fm.isExecutableFile(atPath: m2.env.binLocal.appendingPathComponent("mflux-generate-fibo2-edit").path))
        // Hors ligne : --offline, UV_OFFLINE et un mandataire mort à chaque appel d'installation.
        let installation = journalUV.split(separator: "\n").filter { $0.hasPrefix("python install") || $0.contains("--offline") }
        XCTAssertEqual(installation.count, 2, journalUV)
        XCTAssertTrue(installation.allSatisfy { $0.contains("offline=1") && $0.contains("proxy=http://127.0.0.1:9") }, journalUV)
        XCTAssertEqual(try etat(m2, .mflux), .aJour)
    }

    func testDeveloppeurDeposeDepuisUneArchiveEtInstalleParSonInstallSh() throws {
        let m1 = mac("un"), m2 = mac("deux")
        // Sans archive (ni --archive ni celle d'install.sh), le dépôt automatique ne le touche pas.
        let (_, rien) = try m1.executer(deposer: true, elements: nil)
        XCTAssertNil(rien.first { $0.element == .developpeur })
        let (_, sans) = try m1.executer(deposer: true, elements: [.developpeur])
        XCTAssertEqual(sans.first?.action, "refuse")

        let premiere = archive(version: "1.6.10")
        let (_, faits) = try m1.executer(deposer: true, elements: nil, archive: premiere)
        XCTAssertEqual(faits.first { $0.element == .developpeur }?.action, "depose", faits.map(\.texte).joined(separator: "\n"))
        XCTAssertEqual(manifeste()["developpeur"]?["version"]?.string, "1.6.10")
        // La même : rien ; une plus ancienne (1.6.9 < 1.6.10) : refusée.
        let (_, meme) = try m1.executer(deposer: true, elements: [.developpeur], archive: premiere)
        XCTAssertEqual(meme.first?.action, "rien")
        // Le même numéro refait avant la publication (une autre empreinte) remplace celle du SSD.
        let shaAvant = manifeste()["developpeur"]?["fichiers"]?.array?.first?["sha256"]?.string
        let refaite = base.appendingPathComponent("refaite.zip")
        try Data(contentsOf: premiere).write(to: refaite)
        let ajout = try FileHandle(forWritingTo: refaite)
        ajout.seekToEndOfFile(); ajout.write(Data([0])); try ajout.close()
        let (_, refait) = try m1.executer(deposer: true, elements: [.developpeur], archive: refaite)
        XCTAssertEqual(refait.first?.action, "depose", refait.first?.texte ?? "")
        XCTAssertNotEqual(manifeste()["developpeur"]?["fichiers"]?.array?.first?["sha256"]?.string, shaAvant)
        let (_, vieille) = try m1.executer(deposer: true, elements: [.developpeur], archive: archive(version: "1.6.9"))
        XCTAssertEqual(vieille.first?.action, "refuse")
        XCTAssertEqual(manifeste()["developpeur"]?["version"]?.string, "1.6.10")

        // L'autre Mac : install.sh de l'archive, avec son domicile, sans redéposer.
        XCTAssertEqual(try etat(m2, .developpeur), .absentDuMac)
        let (_, installes) = try m2.executer(deposer: false, elements: [.developpeur])
        XCTAssertEqual(installes.first?.action, "installe", installes.first?.texte ?? "")
        // Le fait en une phrase, les notes d'install.sh à part (jamais « install.sh dit : » qui pend),
        // et toute la sortie au journal durable de ce Mac.
        XCTAssertEqual(installes[0].texte, "Développeur IA 1.6.10 installé.")
        XCTAssertEqual(installes[0].notes, ["Claude Desktop est ouvert : il réécrira sa configuration sans le connecteur.",
                                            "Dans Claude Code, ouvrir une nouvelle session."])
        XCTAssertEqual(installes[0].json["notes"]?.array?.count, 2)
        let journal = try String(contentsOf: m2.env.donnees.racineLocale.appendingPathComponent(Installation.nomJournal), encoding: .utf8)
        XCTAssertTrue(journal.contains("Module Lightroom installé"), journal)
        XCTAssertTrue(journal.contains("installation, installe : Développeur IA 1.6.10 installé."), journal)
        let marque = try String(contentsOf: m2.env.domicile.appendingPathComponent("installe.txt"), encoding: .utf8)
        XCTAssertEqual(marque, "1.6.10 1\n")
        XCTAssertEqual(Installation.aRelancer(installes).count, 2)
        XCTAssertTrue(Installation.aRelancer(installes)[0].contains("Lightroom"))
        XCTAssertTrue(Installation.aRelancer(installes)[1].contains("Claude Desktop"))
        XCTAssertEqual((try? fm.contentsOfDirectory(atPath: m2.env.temporaire.path)) ?? [], [], "dossier décompressé retiré")
    }

    func testArchiveAbimeeRefuseeALInstallation() throws {
        let m1 = mac("un"), m2 = mac("deux")
        _ = try m1.executer(deposer: true, elements: [.developpeur], archive: archive(version: "1.7"))
        let zip = ssd.appendingPathComponent("Installation/developpeur/Developpeur.zip")
        var octets = try Data(contentsOf: zip)
        octets[octets.count / 2] ^= 0xFF
        try octets.write(to: zip)
        let (_, faits) = try m2.executer(deposer: false, elements: [.developpeur])
        XCTAssertEqual(faits.first?.action, "refuse")
        XCTAssertTrue(faits[0].texte.contains("SHA-256"), faits[0].texte)
        XCTAssertFalse(fm.fileExists(atPath: m2.env.domicile.appendingPathComponent("installe.txt").path))
    }

    func testElementAnnonceMaisIncompletEstAbsentDuSSD() throws {
        let m1 = mac("un")
        poserClaude(m1.env.domicile, version: "2.1.303")
        _ = try m1.executer(deposer: true, elements: [.claudeCode])
        XCTAssertEqual(try etat(m1, .claudeCode), .aJour)
        // Le fichier tronqué (copie à moitié faite à la main) : plus pris pour bon.
        let f = ssd.appendingPathComponent("Installation/claude_code/claude-2.1.303")
        try Data("tronqué".utf8).write(to: f)
        XCTAssertEqual(try etat(m1, .claudeCode), .absentDuSSD)
        try fm.removeItem(at: f)
        XCTAssertEqual(try etat(m1, .claudeCode), .absentDuSSD)
    }

    // MARK: Modèles de Hugging Face

    /// Un cache à blobs partagés comme celui de Dany (hub/blobs/<xx>/<sha256>), avec Fibo 2 Dev (un
    /// instantané complet, un incomplet) et Whisper (à ne jamais copier).
    func poserCacheHF(_ hub: URL) {
        let fibo = hub.appendingPathComponent("models--briaai--Fibo-2.0-dev")
        ecrire(fibo.appendingPathComponent("refs/main"), "rev1")
        ecrire(fibo.appendingPathComponent("blobs/c0nf1g"), "{\"config\": 1}")
        lien(fibo.appendingPathComponent("blobs/aaaa"), "../../blobs/aa/aaaa")
        ecrire(hub.appendingPathComponent("blobs/aa/aaaa"), String(repeating: "p", count: 5000))
        ecrire(hub.appendingPathComponent("blobs/aa/aaaa.refs"), "briaai/Fibo-2.0-dev\n")
        ecrire(hub.appendingPathComponent("blobs/aa/aaaa.lock"), "")
        ecrire(hub.appendingPathComponent("blobs/.huggingface-shared-blobs"), "1")
        ecrire(hub.appendingPathComponent("CACHEDIR.TAG"), "Signature: 8a477f597d28d172789f06886806bc55")
        lien(fibo.appendingPathComponent("snapshots/rev1/transformer/config.json"), "../../../blobs/c0nf1g")
        lien(fibo.appendingPathComponent("snapshots/rev1/transformer/poids.safetensors"), "../../../blobs/aaaa")
        lien(fibo.appendingPathComponent("snapshots/rev0/poids.safetensors"), "../../blobs/manquant")
        let whisper = hub.appendingPathComponent("models--Systran--faster-whisper-small")
        ecrire(whisper.appendingPathComponent("refs/main"), "w1")
        lien(whisper.appendingPathComponent("blobs/wwww"), "../../blobs/ww/wwww")
        ecrire(hub.appendingPathComponent("blobs/ww/wwww"), "whisper")
        lien(whisper.appendingPathComponent("snapshots/w1/model.bin"), "../../blobs/wwww")
    }

    func testInventaireDesModelesSeulementCeuxDeFibo() {
        let hub = base.appendingPathComponent("hub")
        poserCacheHF(hub)
        let inv = Installation.inventaireHF(hub: hub, depots: Installation.depotsHF)
        let chemins = Set(inv.entrees.map(\.chemin))
        XCTAssertEqual(inv.ensemble, ["briaai/Fibo-2.0-dev@rev1", "briaai/Fibo-2.0-dev@rev1:transformer/config.json",
                                      "briaai/Fibo-2.0-dev@rev1:transformer/poids.safetensors"], "l'instantané incomplet ne compte pas ; chaque fichier compte")
        XCTAssertEqual(inv.marques["models--briaai--Fibo-2.0-dev/refs/main"]?.valeur, "rev1")
        XCTAssertEqual(Installation.texteModeles(inv.ensemble), "1 modèle, 1 instantané")
        XCTAssertTrue(chemins.contains("blobs/aa/aaaa"))
        XCTAssertTrue(chemins.contains("blobs/aa/aaaa.refs"))
        XCTAssertTrue(chemins.contains("blobs/.huggingface-shared-blobs"))
        XCTAssertFalse(chemins.contains { $0.contains("whisper") || $0.hasPrefix("blobs/ww") }, "Whisper n'est jamais copié")
        XCTAssertFalse(chemins.contains { $0.hasSuffix(".lock") })
        XCTAssertEqual(inv.taille, 5000 + 13 + 1 + 4 + 20 + 43)
        XCTAssertEqual(inv.modeles["briaai/Fibo-2.0-dev"]?.refs["main"], "rev1")
    }

    func testModelesDeposesPuisInstallesAvecUnCacheValide() throws {
        let m1 = mac("un"), m2 = mac("deux")
        poserCacheHF(m1.env.cacheHF)
        let (_, faits) = try m1.executer(deposer: true, elements: [.modelesHF])
        XCTAssertEqual(faits.first?.action, "depose", faits.first?.texte ?? "")
        let hubSSD = ssd.appendingPathComponent("Installation/modeles_hf/hub")
        let poidsSSD = hubSSD.appendingPathComponent("models--briaai--Fibo-2.0-dev/snapshots/rev1/transformer/poids.safetensors")
        XCTAssertEqual(try String(contentsOf: poidsSSD, encoding: .utf8).count, 5000, "le lien mène au blob partagé copié")
        XCTAssertFalse(fm.fileExists(atPath: hubSSD.appendingPathComponent("models--Systran--faster-whisper-small").path))
        XCTAssertEqual(manifeste()["modeles_hf"]?["ensemble"]?.array?.first, "briaai/Fibo-2.0-dev@rev1")
        XCTAssertEqual(manifeste()["modeles_hf"]?["ensemble"]?.array?.count, 3)
        XCTAssertEqual(manifeste()["modeles_hf"]?["marques"]?["models--briaai--Fibo-2.0-dev/refs/main"]?["valeur"]?.string, "rev1")
        XCTAssertNil(manifeste()["modeles_hf"]?["fichiers"]?.array?.first?["sha256"], "pas d'empreinte sur les modèles : taille et révision")
        XCTAssertEqual(try etat(m1, .modelesHF), .aJour)

        XCTAssertEqual(try etat(m2, .modelesHF), .absentDuMac)
        let (_, installes) = try m2.executer(deposer: false, elements: nil)
        XCTAssertEqual(installes.first { $0.element == .modelesHF }?.action, "installe")
        let instantane = m2.env.cacheHF.appendingPathComponent("models--briaai--Fibo-2.0-dev/snapshots/rev1")
        XCTAssertTrue(Installation.instantaneComplet(instantane))
        XCTAssertEqual(try etat(m2, .modelesHF), .aJour)
        // Un nouvel instantané sur le second Mac : plus récent que le SSD, et le dépôt ajoute sans rien retirer.
        let fibo2 = m2.env.cacheHF.appendingPathComponent("models--briaai--Fibo-2.0-dev")
        ecrire(fibo2.appendingPathComponent("blobs/n0uveau"), "nouveau")
        lien(fibo2.appendingPathComponent("snapshots/rev2/config.json"), "../../blobs/n0uveau")
        XCTAssertEqual(try etat(m2, .modelesHF), .macPlusRecent)
        _ = try m2.executer(deposer: true, elements: nil)
        let instantanes: Set<String> = Set((manifeste()["modeles_hf"]?["ensemble"]?.array?.compactMap(\.string) ?? []).filter { !$0.contains(":") })
        XCTAssertEqual(instantanes, ["briaai/Fibo-2.0-dev@rev1", "briaai/Fibo-2.0-dev@rev2"])
        XCTAssertEqual(try etat(m1, .modelesHF), .ssdPlusRecent)
    }

    func testCopieInterrompueRepriseEtPartielRemplace() throws {
        let m1 = mac("un")
        let source = base.appendingPathComponent("source"), cible = base.appendingPathComponent("cible")
        ecrire(source.appendingPathComponent("a/gros.bin"), String(repeating: "x", count: 40_000))
        ecrire(source.appendingPathComponent("a/fini.bin"), "complet")
        // Interruption : un .partiel laissé, et un fichier déjà complet (même taille) à garder.
        ecrire(cible.appendingPathComponent("a/gros.bin.partiel"), "début")
        ecrire(cible.appendingPathComponent("a/fini.bin"), "COMPLET")
        let entrees = Installation.inventaireDossier(source).entrees
        try m1.copierArbre(entrees, de: source, vers: cible, element: .sam2)
        XCTAssertEqual(Installation.taille(cible.appendingPathComponent("a/gros.bin")), 40_000)
        XCTAssertEqual(try String(contentsOf: cible.appendingPathComponent("a/fini.bin"), encoding: .utf8), "COMPLET", "repris : déjà complet, gardé")
        XCTAssertEqual(partiels(cible), [])
        XCTAssertTrue(avances.contains { $0.element == "sam2" && $0.total == 40_000 })
    }

    func testSam2DeposeEtInstalleSaufFiboOuvert() throws {
        let m1 = mac("un"), m2 = mac("deux")
        ecrire(m1.env.sam2.appendingPathComponent("SAM2_1SmallImageEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/model.mlmodel"), "modele")
        ecrire(m1.env.sam2.appendingPathComponent("SAM2_1SmallImageEncoderFLOAT16.mlmodelc/coremldata.bin"), "compile")
        _ = try m1.executer(deposer: true, elements: nil)
        XCTAssertEqual(manifeste()["sam2"]?["version"]?.string, "1 fichiers de modèles")
        fiboOuvert = true
        XCTAssertEqual(try m2.executer(deposer: false, elements: [.sam2]).faits.first?.action, "refuse")
        fiboOuvert = false
        XCTAssertEqual(try m2.executer(deposer: false, elements: [.sam2]).faits.first?.action, "installe")
        XCTAssertTrue(fm.fileExists(atPath: m2.env.sam2.appendingPathComponent("SAM2_1SmallImageEncoderFLOAT16.mlmodelc/coremldata.bin").path))
        XCTAssertEqual(try etat(m2, .sam2), .aJour)
    }

    /// Les scripts : Modeles de la racine des données (jamais celui de ce Mac à la place du dossier
    /// commun) ; dépôt de l'archive par install.sh sauf depuis le SSD ou une archive d'essai ; build.sh
    /// ne dépose qu'une archive notarisée et testée.
    func testScriptsSuiventLaRacineDesDonneesEtLeDepot() throws {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let install = try String(contentsOf: racine.appendingPathComponent("install.sh"), encoding: .utf8)
        XCTAssertTrue(install.contains(#"DONNEES="$("${DEST}" --racine-donnees"#))
        XCTAssertFalse(install.contains(#"${DEST_DIR}/Modeles"#), "plus aucun Modeles local en dur")
        XCTAssertTrue(install.contains(#""${DEVELOPPEUR_DEPUIS_SSD:-0}" != 1 && "${DEVELOPPEUR_PAS_DE_DEPOT:-0}" != 1"#))
        XCTAssertTrue(install.contains("--mises-a-jour --deposer developpeur --archive"))
        let build = try String(contentsOf: racine.appendingPathComponent("build.sh"), encoding: .utf8)
        XCTAssertTrue(build.contains(#"DEVELOPPEUR_PAS_DE_DEPOT=1 bash "${STAGE_DIR}/installation/${ARCHIVE_NAME}/install.sh""#))
        XCTAssertTrue(build.contains(#"if [[ "${NOTARIZE}" -eq 1 && "${TESTS}" -eq 1 ]]; then"#))
        // Le témoin d'une archive d'essai, posé par build.sh, lu par install.sh (lancé à la main).
        XCTAssertTrue(build.contains(#"if [[ "${NOTARIZE}" -eq 0 || "${TESTS}" -eq 0 ]]; then"#))
        XCTAssertTrue(build.contains(#"> "${STAGE}/ESSAI""#))
        XCTAssertTrue(install.contains(#"if [[ -f "${HERE}/ESSAI" && "#))
        XCTAssertEqual(Installation.temoinEssai, "Developpeur/ESSAI")
        let bioclip = try String(contentsOf: racine.appendingPathComponent("scripts/preparer-bioclip.sh"), encoding: .utf8)
        XCTAssertTrue(bioclip.contains("plutil -extract dossier raw"))
        XCTAssertTrue(bioclip.contains(#"MODELES="${COMMUN%/}/Modeles""#))
    }

    func testDescriptionJSONDeLaComparaison() throws {
        let m1 = mac("un")
        poserClaude(m1.env.domicile, version: "2.1.303")
        let ligne = try XCTUnwrap(m1.comparer().first { $0.element == .claudeCode })
        let j = Installation.json(ligne)
        XCTAssertEqual(j["etat"]?.string, "absent_du_ssd")
        XCTAssertEqual(j["mac"]?["version"]?.string, "2.1.303")
        XCTAssertEqual(j["a_deposer"]?.bool, true)
        XCTAssertEqual(j["ssd"], .null)
        XCTAssertTrue(Installation.texte(ligne).hasPrefix("Claude Code : absent du SSD"))
    }

    // MARK: Constats de la revue (1.7)

    func dater(_ url: URL, _ decalage: TimeInterval) {
        try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(decalage)], ofItemAtPath: url.path)
    }

    func lire(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    /// Un instantané à moitié là (téléchargement interrompu : le lien d'un fichier jamais posé) n'est
    /// plus égal à l'instantané entier : le SSD est plus récent, et l'installation le complète.
    func testInstantaneAMoitieLaNEstPasPrisPourEntier() throws {
        let m1 = mac("un"), m2 = mac("deux")
        poserCacheHF(m1.env.cacheHF)
        _ = try m1.executer(deposer: true, elements: [.modelesHF])
        poserCacheHF(m2.env.cacheHF)
        let poids = m2.env.cacheHF.appendingPathComponent("models--briaai--Fibo-2.0-dev/snapshots/rev1/transformer/poids.safetensors")
        try fm.removeItem(at: poids)
        try fm.removeItem(at: m2.env.cacheHF.appendingPathComponent("blobs/aa/aaaa"))
        XCTAssertTrue(Installation.instantaneComplet(poids.deletingLastPathComponent().deletingLastPathComponent()), "sans lien cassé, il paraissait complet")
        XCTAssertEqual(try etat(m2, .modelesHF), .ssdPlusRecent)
        let (_, faits) = try m2.executer(deposer: false, elements: [.modelesHF])
        XCTAssertEqual(faits.first?.action, "installe", faits.first?.texte ?? "")
        XCTAssertEqual(lire(poids).count, 5000)
        XCTAssertEqual(try etat(m2, .modelesHF), .aJour)
    }

    /// `refs/main` (40 octets, toujours la même taille) suit la révision la plus récente, dans les deux
    /// sens ; un refs différent seul se voit à la comparaison ; un refs plus ancien ne remplace pas.
    func testRefsSuitLaRevisionLaPlusRecente() throws {
        let m1 = mac("un"), m2 = mac("deux")
        poserCacheHF(m1.env.cacheHF)
        let modele = "models--briaai--Fibo-2.0-dev"
        let refs1 = m1.env.cacheHF.appendingPathComponent(modele + "/refs/main")
        let refs2 = m2.env.cacheHF.appendingPathComponent(modele + "/refs/main")
        let refsSSD = ssd.appendingPathComponent("Installation/modeles_hf/hub/" + modele + "/refs/main")
        ecrire(refs1, "rev1-------------------------------------")
        dater(refs1, -3600)
        _ = try m1.executer(deposer: true, elements: [.modelesHF])
        _ = try m2.executer(deposer: false, elements: [.modelesHF])
        // Nouvelle révision sur le premier Mac : refs/main change, à la même taille.
        let fibo = m1.env.cacheHF.appendingPathComponent(modele)
        ecrire(fibo.appendingPathComponent("blobs/n0uveau"), "nouveau")
        lien(fibo.appendingPathComponent("snapshots/rev2/config.json"), "../../blobs/n0uveau")
        ecrire(refs1, "rev2-------------------------------------")
        XCTAssertEqual(Installation.taille(refs1), Installation.taille(refsSSD))
        XCTAssertEqual(try etat(m1, .modelesHF), .macPlusRecent)
        _ = try m1.executer(deposer: true, elements: nil)
        XCTAssertEqual(lire(refsSSD), "rev2-------------------------------------", "refs/main du SSD suit le dépôt")
        XCTAssertEqual(try etat(m2, .modelesHF), .ssdPlusRecent)
        _ = try m2.executer(deposer: false, elements: nil)
        XCTAssertEqual(lire(refs2), "rev2-------------------------------------", "refs/main du Mac suit l'installation")
        XCTAssertEqual(try etat(m2, .modelesHF), .aJour)
        // Même ensemble, seul refs change (le second Mac revient sur rev1, plus tard) : vu.
        ecrire(refs2, "rev1-------------------------------------")
        dater(refs2, 60)
        XCTAssertEqual(try etat(m2, .modelesHF), .macPlusRecent)
        // L'installation forcée ne remet pas le refs plus ancien du SSD par-dessus.
        _ = try m2.executer(deposer: false, elements: [.modelesHF])
        XCTAssertEqual(lire(refs2), "rev1-------------------------------------")
    }

    /// mflux s'installe avec l'uv qui a rempli son cache (gardé avec lui), même si le SSD n'a plus
    /// d'uv et que ce Mac en a un autre ; cet uv est vérifié par son empreinte avant d'être lancé.
    func testMfluxInstalleAvecLUvQuiARempliLeCache() throws {
        let m1 = mac("un")
        poserMflux(m1.env.domicile)
        _ = try m1.executer(deposer: true, elements: [.uv, .mflux])
        let garde = try XCTUnwrap(manifeste()["mflux"]?["fichiers"]?.array?.first { $0["chemin"]?.string == "mflux/uv" })
        XCTAssertEqual(garde["sha256"]?.string?.count, 64)
        XCTAssertEqual(manifeste()["mflux"]?["uv"]?.string, "0.13.5")
        try fm.removeItem(at: ssd.appendingPathComponent("Installation/uv"))
        ecrireUV(version: "0.14.0")
        try? fm.removeItem(at: fauxUV.deletingLastPathComponent().appendingPathComponent("journal"))
        let m2 = mac("deux")
        let (_, faits) = try m2.executer(deposer: false, elements: [.mflux])
        XCTAssertEqual(faits.first?.action, "installe", faits.first?.texte ?? "")
        let appels = journalUV.split(separator: "\n").filter { $0.hasPrefix("python install") || $0.contains("--offline") }
        XCTAssertEqual(appels.count, 2, journalUV)
        XCTAssertTrue(appels.allSatisfy { $0.contains("v=0.13.5") }, journalUV)

        // L'uv gardé abîmé (même taille) : refusé avant d'être lancé, jamais remplacé par un autre uv.
        let fichier = ssd.appendingPathComponent("Installation/mflux/uv")
        var octets = try Data(contentsOf: fichier)
        octets[octets.count - 2] ^= 0x01
        try octets.write(to: fichier)
        let m3 = mac("trois")
        let (_, refus) = try m3.executer(deposer: false, elements: [.mflux])
        XCTAssertEqual(refus.first?.action, "refuse")
        XCTAssertTrue(refus[0].texte.contains("mflux/uv") && refus[0].texte.contains("SHA-256"), refus[0].texte)
        XCTAssertNil(m3.mfluxDuMac())
    }

    /// uv/uv abîmé sur le SSD (même taille) : refusé, l'uv de ce Mac n'est pas remplacé.
    func testUvAbimeRefuseALInstallation() throws {
        let m1 = mac("un")
        _ = try m1.executer(deposer: true, elements: [.uv])
        let fichier = ssd.appendingPathComponent("Installation/uv/uv")
        var octets = try Data(contentsOf: fichier)
        octets[octets.count - 2] ^= 0x01
        try octets.write(to: fichier)
        ecrireUV(version: "0.12.0")
        let m2 = mac("deux")
        let (_, faits) = try m2.executer(deposer: false, elements: [.uv])
        XCTAssertEqual(faits.first?.action, "refuse")
        XCTAssertTrue(faits[0].texte.contains("SHA-256"), faits[0].texte)
        XCTAssertFalse(fm.fileExists(atPath: m2.env.binLocal.appendingPathComponent("uv").path))
    }

    /// SAM 2 réexporté aux mêmes tailles : vu (empreintes), le plus récent remplace l'autre.
    func testSam2NouvelExportAuxMemesTailles() throws {
        let m1 = mac("un"), m2 = mac("deux")
        let poids = "SAM2_1SmallImageEncoderFLOAT16.mlpackage/Data/com.apple.CoreML/weights/weight.bin"
        ecrire(m1.env.sam2.appendingPathComponent(poids), "ancien")
        dater(m1.env.sam2.appendingPathComponent(poids), -3600)
        _ = try m1.executer(deposer: true, elements: [.sam2])
        _ = try m2.executer(deposer: false, elements: [.sam2])
        XCTAssertEqual(try etat(m2, .sam2), .aJour)
        ecrire(m2.env.sam2.appendingPathComponent(poids), "nouvel")
        XCTAssertEqual(try etat(m2, .sam2), .macPlusRecent, "même taille, autre contenu, plus récent")
        _ = try m2.executer(deposer: true, elements: nil)
        XCTAssertEqual(lire(ssd.appendingPathComponent("Installation/sam2/SAM2/" + poids)), "nouvel")
        XCTAssertEqual(try etat(m1, .sam2), .ssdPlusRecent)
        _ = try m1.executer(deposer: false, elements: [.sam2])
        XCTAssertEqual(lire(m1.env.sam2.appendingPathComponent(poids)), "nouvel")
        XCTAssertEqual(try etat(m1, .sam2), .aJour)
    }

    /// Les « .partiel » d'une copie interrompue, laissés dans l'arbre, sont retirés à la copie suivante
    /// même si ce fichier n'est plus à copier ; rien d'autre n'est retiré.
    func testPartielsOrphelinsRetires() throws {
        let m1 = mac("un")
        let source = base.appendingPathComponent("source"), cible = base.appendingPathComponent("cible")
        ecrire(source.appendingPathComponent("blobs/aa/nouveau"), "n")
        ecrire(cible.appendingPathComponent("blobs/aa/ancien-de-6-go.partiel"), String(repeating: "x", count: 10_000))
        ecrire(cible.appendingPathComponent("blobs/aa/autre"), "garde")
        try m1.copierArbre(Installation.inventaireDossier(source).entrees, de: source, vers: cible, element: .modelesHF)
        XCTAssertEqual(partiels(cible), [])
        XCTAssertEqual(lire(cible.appendingPathComponent("blobs/aa/autre")), "garde")
        XCTAssertEqual(lire(cible.appendingPathComponent("blobs/aa/nouveau")), "n")
    }

    /// Un essai à la main sur un domicile donné ne voit que l'uv de ce domicile.
    func testUvCandidatsDUnEssai() {
        let d = domicile("essai")
        XCTAssertEqual(Installation.uvCandidats(domicile: d, essai: true), [d.appendingPathComponent(".local/bin/uv")])
        XCTAssertEqual(Installation.uvCandidats(domicile: d, essai: false).count, 3)
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let main = (try? String(contentsOf: racine.appendingPathComponent("Sources/MCPDeveloppeur/main.swift"), encoding: .utf8)) ?? ""
        XCTAssertTrue(main.contains("uvCandidats: Installation.uvCandidats(domicile: domicile, essai: essai)"))
    }

    /// Les notes d'install.sh : chaque point des Prochaines étapes, lignes de suite jointes.
    func testNotesDInstallSh() {
        let sortie = "Module installé\n\nProchaines étapes :\n  - Lightroom Classic est ouvert : le quitter.\n    Il apparaît dans le Gestionnaire.\n  - Pour vérifier : --status\n"
        XCTAssertEqual(Installation.notesInstallSh(sortie), ["Lightroom Classic est ouvert : le quitter. Il apparaît dans le Gestionnaire.", "Pour vérifier : --status"])
        XCTAssertEqual(Installation.notesInstallSh("rien"), [])
    }

    /// Une archive d'essai (témoin ESSAI de build.sh) n'est jamais déposée.
    func testArchiveDEssaiJamaisDeposee() throws {
        let m1 = mac("un")
        let (_, faits) = try m1.executer(deposer: true, elements: [.developpeur], archive: archive(version: "1.7", essai: true))
        XCTAssertEqual(faits.first?.action, "refuse")
        XCTAssertTrue(faits[0].texte.contains(Installation.texteArchiveEssai), faits[0].texte)
        XCTAssertNil(manifeste()["developpeur"])
    }
}
