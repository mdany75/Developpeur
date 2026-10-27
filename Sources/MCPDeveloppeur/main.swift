import Foundation
import DeveloppeurKit

// Point d'entrée : sans argument, le serveur MCP parle JSON-RPC sur stdin/stdout.
// Les journaux vont sur stderr, jamais sur stdout (réservé au protocole).

func log(_ message: String) {
    FileHandle.standardError.write(Data("[mcp-developpeur] \(message)\n".utf8))
}

// Les réponses (fil principal, ou fil d'attente d'un appel d'outil) et les notifications de
// progression (leur propre fil) ne doivent pas se mêler sur stdout.
let sortie = NSLock()

func print(line: String) {
    sortie.lock()
    defer { sortie.unlock() }
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func executablePath() -> String {
    let url = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    return url.resolvingSymlinksInPath().path
}

let pluginPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Adobe/Lightroom/Modules/Developpeur.lrplugin").path

/// L'aide, sur stdout (--help, ou une option inconnue) ; sur stderr avec `erreur` : une commande du
/// Suivi lancée par le module avec un mauvais nombre d'arguments n'écrit rien sur stdout (code 2).
func usage(erreur: Bool = false) {
    let texte = """
    mcp-developpeur \(ServerInfo.version) — MCP-Développeur, le serveur MCP du module Développeur de Lightroom Classic

    Usage : mcp-developpeur              lance le serveur (stdio, pour Claude)
            mcp-developpeur --install    inscrit cet exécutable dans Claude Desktop et Claude Code
            mcp-developpeur --uninstall  retire l'inscription
            mcp-developpeur --status     inscriptions, module Lightroom, jeton de la liaison, écran, liaison et mise à jour (par gh)
            mcp-developpeur --version

    Pour la fenêtre Claude et le développement (parlent au module Lightroom directement, sauf --marquer-af, --focus,
    --analyser, --graphiques, --ecran et --boitier) :
            mcp-developpeur --call <outil> ['{"json": …}'] [--image <fichier.jpg>]
                appelle un outil comme le ferait Claude (et enregistre les images qu'il renvoie)
            mcp-developpeur --module <commande> ['{"json": …}']   commande brute du module (diagnostic…)
            mcp-developpeur --recalage <id photo>   mesure le recalage des positions sur la géométrie actuelle
                (deux rendus) : zones fiables, écarts moyen, maximal et près des bords, en pixels du fichier
            mcp-developpeur --dump [<id photo>]   tous les réglages bruts de la photo (active par défaut),
                à plat, une clé par ligne et triés : à comparer avec diff avant et après un essai
            mcp-developpeur --marquer-af <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>
                dessine le point de mise au point d'un fichier Fujifilm sur sa vignette (la fenêtre Claude,
                aperçu de la photo active) ; code 1 sans point
            mcp-developpeur --focus <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>
                l'onglet Focus de la fenêtre Claude : les cadres de la mise au point d'un fichier Fujifilm (point
                ou zone AF à sa taille en rouge, visages et éléments du sujet en coins jaunes) dessinés sur sa
                vignette, puis ce que l'appareil en dit, une ligne JSON ; code 1 si rien n'est lu
            mcp-developpeur --analyser '<json>'
                le Suivi (fenêtre Claude) : les défauts de la prise de vue mesurés sur les vignettes du cache de
                Lightroom données (exposition, hautes lumières, netteté, bruit à ISO élevé, yeux fermés), comme le tri ;
                ni Lightroom ni l'original ; 20 photos au plus, une ligne JSON (Tests/Contrats/suivi.json)
            mcp-developpeur --graphiques '<json>' <dossier>
                le Suivi : les tuiles et les neuf graphiques d'une période d'après suivi.json (et carnet.json), lus
                seulement, dessinés en PNG 2x dans le dossier, puis une ligne JSON avec les rectangles des barres
            mcp-developpeur --ecran   l'écran principal et son profil de couleur, classé (d'usine, standard, à
                l'œil, sonde…), une ligne JSON ; {"lu": false} sans écran ; lu sur le Mac sans Lightroom
            mcp-developpeur --eclairage <id photo>… [<fichier.jpg>…] [--essai '{"settings": {"Temperature": 3200}}']
                relevé de l'éclairage mixte : dominantes des tons neutres par case et par zone tonale, visages, scène,
                à plusieurs bornes (écart a*b* au centre des tons neutres : le gris, ou le point neutre de l'image
                quand une dominante l'en écarte), avec le point neutre et le centre de chaque mesure ; lecture seule
                (aperçus comme view_photo) ; --essai passe par preview_settings (deux étapes « Claude · essai »,
                copies virtuelles d'essai seulement)
            mcp-developpeur --boitier <original>
                ce que l'appareil a rangé dans un fichier Fujifilm (RAF ou JPEG), lu sans Lightroom : point de mise
                au point, intention de la prise de vue (comme view_photo), mise au point en détail (comme l'onglet
                Focus) et valeurs lues sous les noms d'exiftool, une ligne JSON ; code 1 si rien n'est lu
            mcp-developpeur --constats <id photo>… [<fichier.jpg>…]
                relevé des seuils du carnet de progrès : L* médian et 95e centile, blanc pur du tiers haut, netteté
                (au point de mise au point aussi), bruit, boîtier, géométrie, puis les défauts que view_photo
                noterait ; lecture seule (aperçus comme view_photo, rien n'est noté au carnet) ; un fichier JPEG se
                mesure sans Lightroom
            mcp-developpeur --recette <id RAW> [--jpeg <id>] [--flash <id>] [--profondeur <id>] [--yeux-rouges <id>] [--x-t20 <id>] [--portrait <id>] [--mixte <id>] [--horizon <id> [--hauteur-horizon <0 à 1>]] [--original] [--images <dossier>]
                recette dans le vrai Lightroom, sur les copies virtuelles de la collection « Développeur › Essais »
                (et des originaux avec --original), remises à l'origine à la fin ; l'historique d'un original
                garde les étapes de la recette ; d'abord la liaison fermée et l'écran nommé, en lecture seule.
                Le RAW passe aussi par la 1.3 : avant/après d'une étape, carnet de progrès (copie d'essai notée
                puis retirée).
                --portrait : la peau dosée sur un portrait ; --mixte : une photo à deux lumières (lampe et fenêtre)
                lue mixte, puis le RAW lu à une seule lumière, en lecture seule ; --horizon : une photo qui a un
                vrai horizon, pour la composition lue, à --hauteur-horizon dans l'image (0,5 par défaut) ; sans
                horizon net à cette hauteur, l'étape de l'horizon est sautée, avec sa raison
    Les commandes portent le jeton privé de la liaison (liaison.jeton, écrit par le module à chaque démarrage
    de la liaison) ; le serveur ne le crée jamais et ne le dit jamais.
    DEVELOPPEUR_PORT=<port> change le port des commandes (les réponses sur le port suivant ;
    défaut \(LightroomBridge.defaultRequestPort) et \(LightroomBridge.defaultReplyPort), comme dans le module).
    DEVELOPPEUR_VERBOSE=1 journalise la durée des réponses et de chaque commande du module (stderr).
    DEVELOPPEUR_LIMITE=<s> change la limite d'un appel d'outil sans jeton de progression, après laquelle
    le serveur répond d'attendre (défaut 50 s, sous les 60 s de Claude Desktop).
    """
    if erreur {
        FileHandle.standardError.write(Data((texte + "\n").utf8))
    } else {
        print(line: texte)
    }
}

let verbose = ProcessInfo.processInfo.environment["DEVELOPPEUR_VERBOSE"] == "1"

/// Les outils du serveur et de --call, qui lisent le nom de l'écran du Mac pour get_status (les
/// tests, non : ToolHandler le laisse à nil).
func outils() -> ToolHandler {
    let tools = ToolHandler(lightroom: LightroomBridge.fromEnvironment())
    tools.lireEcran = Ecran.lire
    tools.lireSauvegardes = Sauvegardes.lire
    return tools
}

func serve() {
    let tools = outils()
    // Le carnet de progrès (1.3) ne se remplit que par le serveur lancé par Claude (Claude Desktop,
    // Claude Code, la fenêtre Claude) : ni --call, ni la recette, ni les tests n'y notent.
    tools.noterAuCarnet = true
    // Le rendu reproductible (1.3.5), gardé au view_photo avec compare = before_claude : de même.
    tools.registreRendus = RegistreRendus()
    let server = MCPServer(name: ServerInfo.name, title: ServerInfo.title, version: ServerInfo.version,
                           instructions: ServerInfo.instructions,
                           tools: tools)
    server.notifier = { print(line: JSONCoding.line($0)) }
    if let text = ProcessInfo.processInfo.environment["DEVELOPPEUR_LIMITE"], let seconds = Double(text), seconds > 0 {
        server.toolBudget = seconds
    }
    log("démarré (version \(ServerInfo.version))")

    // Le fil principal lit sans arrêt : les appels d'outils passent un à un vers Lightroom, dans
    // la file du serveur, et leur réponse part de leur propre fil (ping et listes répondent pendant
    // un long rendu).
    while let line = readLine(strippingNewline: true) {
        let started = Date()
        server.receive(line: line) { response in
            print(line: response)
            if verbose { log(String(format: "réponse en %.2f s", Date().timeIntervalSince(started))) }
        }
    }
    log("fin de l'entrée : arrêt")
}

func status() {
    print(line: "Version : \(ServerInfo.version)")
    if let miseAJour = MiseAJour.ligne(installee: ServerInfo.version, derniere: MiseAJour.derniereVersion()) {
        print(line: miseAJour)
    }
    print(line: "Exécutable : \(executablePath())")
    let installe = ClaudeRegistration.installedExecutable().path
    for target in ClaudeRegistration.defaultTargets() {
        let command = ClaudeRegistration.registeredCommand(in: target)
        let ailleurs = command.map { $0 != installe } ?? false
        print(line: "\(target.label) : \(command.map { "inscrit (\($0))" } ?? "non inscrit")"
            + (ailleurs ? " ; ce n'est pas l'exécutable installé (\(installe))" : ""))
        if ClaudeRegistration.ancienInscrit(in: target) {
            print(line: "\(target.label) : l'ancien connecteur « \(ClaudeRegistration.ancienneCle) » (MCP Lightroom) est encore inscrit ; "
                + "quitter Claude Desktop, puis lancer \(installe) --install, qui le retire")
        }
    }
    let pluginInstalled = FileManager.default.fileExists(atPath: pluginPath)
    print(line: "Module Lightroom : \(pluginInstalled ? "installé (\(pluginPath))" : "absent de \(pluginPath)")")
    // L'état du fichier du jeton, jamais sa valeur.
    print(line: "Jeton de la liaison : \(JetonLiaison.etat(JetonLiaison.fichierParDefaut()))")
    // L'écran se dit même Lightroom fermé : avant la liaison, qui peut finir en échec. Son nom
    // seulement, comme get_status (correctif 1.3.6 : plus rien sur l'étalonnage) ; son profil, par
    // --ecran.
    if let ecran = Ecran.lire() {
        print(line: "Écran principal : \(ecran.principal.nom)")
        for autre in ecran.autres { print(line: "Autre écran : \(autre.nom)") }
    } else {
        print(line: "Écran : aucun écran lu (session sans écran ?)")
    }
    let bridge = LightroomBridge.fromEnvironment()
    do {
        let state = try bridge.send("etat", [:], timeout: 10)
        print(line: "Liaison : active (ports \(bridge.requestPort) et \(bridge.replyPort))")
        print(line: JSONCoding.pretty(state))
    } catch {
        print(line: "Liaison : \(error.localizedDescription)")
        exit(1)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case nil:
    serve()
case "--version", "-v":
    print(line: ServerInfo.version)
case "--help", "-h":
    usage()
case "--install":
    do {
        for line in try ClaudeRegistration.register(executable: executablePath(), targets: ClaudeRegistration.defaultTargets()) {
            print(line: line)
        }
        print(line: "Redémarrer Claude Desktop pour que le connecteur apparaisse ; Claude Code le voit à sa prochaine session.")
    } catch {
        log("échec de l'inscription : \(error.localizedDescription)")
        exit(1)
    }
case "--uninstall":
    do {
        for line in try ClaudeRegistration.unregister(targets: ClaudeRegistration.defaultTargets()) {
            print(line: line)
        }
    } catch {
        log("échec du retrait : \(error.localizedDescription)")
        exit(1)
    }
case "--status":
    status()
case "--call":
    guard arguments.count >= 2 else { usage(); exit(2) }
    var rest = Array(arguments.dropFirst(2))
    var imagePath: String?
    if let index = rest.firstIndex(of: "--image") {
        guard index + 1 < rest.count else { usage(); exit(2) }
        imagePath = rest[index + 1]
        rest.removeSubrange(index...(index + 1))
    }
    do {
        let params = try rest.first.map { try JSONCoding.parse($0).object ?? [:] } ?? [:]
        let result = outils().call(name: arguments[1], arguments: params)
        var saved = 0
        for block in result.content {
            switch block {
            case .text(let text): print(line: text)
            case .image(let data, let mimeType):
                if let imagePath, let bytes = Data(base64Encoded: data) {
                    let url = URL(fileURLWithPath: imagePath)
                    let target = saved == 0 ? url : url.deletingPathExtension().appendingPathExtension("\(saved + 1).\(url.pathExtension)")
                    try bytes.write(to: target)
                    saved += 1
                    print(line: "[image \(mimeType) enregistrée : \(target.path)]")
                } else {
                    print(line: "[image \(mimeType), \(data.count * 3 / 4 / 1024) Ko]")
                }
            }
        }
        if result.isError { exit(1) }
    } catch {
        log("arguments JSON illisibles ou image non enregistrée : \(error.localizedDescription)")
        exit(2)
    }
case "--marquer-af":
    // L'aperçu de la photo active de la fenêtre Claude (Fenetre.lua) : le point de mise au point lu
    // dans l'original, dessiné sur la vignette que Lightroom a rendue.
    guard arguments.count == 5, let geometrie = try? JSONCoding.parse(arguments[2]) else { usage(); exit(2) }
    guard let point = PointAF.marquer(original: URL(fileURLWithPath: arguments[1]), geometrie: geometrie,
                                      entree: URL(fileURLWithPath: arguments[3]), sortie: URL(fileURLWithPath: arguments[4])) else { exit(1) }
    print(line: JSONCoding.line(["x": .number(point.x), "y": .number(point.y), "avertissement": .bool(point.avertissement)]))
case "--focus":
    // L'onglet Focus de la fenêtre Claude (Fenetre.lua) : les cadres de la mise au point lus dans
    // l'original, dessinés sur la vignette que Lightroom a rendue, et ce que l'appareil en dit ; rien
    // de lu, la raison (`{"lue": false, "raison": …}`) et le code 1.
    guard arguments.count == 5 else { usage(); exit(2) }
    let focus = Focus.lire(original: URL(fileURLWithPath: arguments[1]), geometrie: try? JSONCoding.parse(arguments[2]),
                           entree: URL(fileURLWithPath: arguments[3]), sortie: URL(fileURLWithPath: arguments[4]))
    print(line: JSONCoding.line(focus))
    if focus["lue"]?.bool != true { exit(1) }
case "--analyser":
    // Le Suivi (correctif 1.3.7, Releve.lua) : les défauts mesurés sur les vignettes d'un lot, sous
    // l'alarme de 60 s de perl ; une ligne JSON, code 1 pour un refus de tout l'appel.
    guard arguments.count == 2 else { usage(erreur: true); exit(2) }
    let analyse = Suivi.analyser(arguments[1])
    print(line: JSONCoding.line(analyse.ligne))
    exit(analyse.code)
case "--graphiques":
    // Le Suivi (FenetreSuivi.lua) : les graphiques d'une période, dessinés dans le dossier donné, sous
    // l'alarme de 20 s de perl ; une ligne JSON (le module la lit dans un fichier), code 1 pour un refus.
    guard arguments.count == 3 else { usage(erreur: true); exit(2) }
    let graphiques = Suivi.graphiques(arguments[1], dossier: arguments[2])
    print(line: JSONCoding.line(graphiques.ligne))
    exit(graphiques.code)
case "--ecran":
    // Pour le développement seulement depuis le correctif 1.3.6 (la fenêtre Claude n'a plus de voyant
    // Écran) : une seule ligne JSON, le profil classé et son chemin compris ; sans écran lu,
    // {"lu": false}.
    print(line: JSONCoding.line(Ecran.lire().map { Ecran.json($0) } ?? ["lu": false]))
case "--boitier":
    // Ce que l'appareil a rangé dans un fichier Fujifilm, sans Lightroom, à comparer à exiftool.
    guard arguments.count == 2 else { usage(); exit(2) }
    guard let lecture = Recette.lectureBoitier(URL(fileURLWithPath: arguments[1])) else {
        log("rien de lu : pas un fichier Fujifilm, fichier illisible, ou ouverture trop longue (autorisation de macOS ?)")
        exit(1)
    }
    print(line: JSONCoding.line(lecture))
case "--recalage":
    // Écarts du recalage (Recalage.swift) sur la géométrie actuelle d'une photo, pour essayer des
    // corrections (Upright, perspective forte) : l'historique garde les deux rendus du recalage.
    guard arguments.count >= 2, let id = Int(arguments[1]) else { usage(); exit(2) }
    do {
        let bridge = LightroomBridge.fromEnvironment()
        let rendus = try bridge.send("geometrie", ["photos": [.number(Double(id))], "rendre": true, "taille": 2048], timeout: 120)
        guard let info = rendus["photos"]?.array?.first, info["active"]?.bool == true else {
            print(line: "Pas de correction géométrique active sur cette photo : rien à recaler.")
            exit(0)
        }
        let corrigee = (try? ToolHandler.readPreview(info["chemin_corrige"]?.string)).flatMap(PreviewImages.image)
        let origine = (try? ToolHandler.readPreview(info["chemin_origine"]?.string)).flatMap(PreviewImages.image)
        guard let corrigee, let origine, let resultat = Recalage.calculer(corrigee: corrigee, origine: origine) else {
            log("rendus illisibles ou image trop uniforme")
            exit(1)
        }
        // Largeur du fichier (pas du cadre) : la géométrie que donne la commande « vignettes ».
        let vignette = try? bridge.send("vignettes", ["photos": [.number(Double(id))], "taille": 128], timeout: 60)
        if let chemin = vignette?["photos"]?.array?.first?["vignette"]?.string { try? FileManager.default.removeItem(atPath: chemin) }
        let largeur = vignette?["photos"]?.array?.first?["geometrie"]?["largeur"]?.double ?? 2048
        func px(_ part: Double) -> String { String(format: "%.1f px", part * largeur) }
        print(line: "Zones fiables : \(resultat.zonesFiables) sur \(resultat.zonesEssayees)")
        print(line: "Déplacement maximal corrigé : \(px(resultat.ecartMax))")
        print(line: "Écart du modèle : moyen \(px(resultat.residu)), maximal \(px(resultat.residuMax)), près des bords \(px(resultat.residuBords))")
        print(line: "(en pixels d'un fichier de \(Int(largeur)) px de large)")
    } catch {
        log(error.localizedDescription)
        exit(1)
    }
case "--dump":
    // Réglages bruts à plat (« MaskGroupBasedCorrections.1.CorrectionAmount = 1 »), pour diff.
    var params: [String: JSONValue] = ["toutes": true, "cles": []]
    if arguments.count >= 2 {
        guard let id = Int(arguments[1]) else { usage(); exit(2) }
        params["photo"] = .number(Double(id))
    }
    do {
        let reponse = try LightroomBridge.fromEnvironment().send("reglages", params, timeout: 60)
        for ligne in ReglagesAPlat.lignes(reponse["tous"] ?? .null) { print(line: ligne) }
    } catch {
        log(error.localizedDescription)
        exit(1)
    }
case "--eclairage":
    // Relevé de l'éclairage mixte (Eclairage.releve), pour fixer ses seuils sur les copies d'essai :
    // des identifiants (aperçus demandés au module), des fichiers JPEG (mesurés sans Lightroom), et
    // au besoin --essai '<arguments de preview_settings>' pour mesurer sous une autre balance.
    var ids: [Int] = [], fichiers: [URL] = [], essai: [String: JSONValue]?
    var rest = Array(arguments.dropFirst())
    while !rest.isEmpty {
        let item = rest.removeFirst()
        if item == "--essai" {
            guard !rest.isEmpty, let objet = (try? JSONCoding.parse(rest.removeFirst()))?.object else {
                log("--essai attend les arguments JSON de preview_settings, par exemple '{\"settings\": {\"Temperature\": 3200}}'")
                exit(2)
            }
            essai = objet
        } else if let id = Int(item) {
            ids.append(id)
        } else if FileManager.default.fileExists(atPath: item) {
            fichiers.append(URL(fileURLWithPath: item))
        } else {
            log("argument inconnu : \(item) (ni identifiant de photo, ni fichier)")
            usage()
            exit(2)
        }
    }
    guard !ids.isEmpty || !fichiers.isEmpty else { usage(); exit(2) }
    let lignes = Eclairage.releve(lightroom: LightroomBridge.fromEnvironment(), ids: ids, fichiers: fichiers, essai: essai) { print(line: $0) }
    exit(lignes.contains { $0.hasPrefix("✘") } ? 1 : 0)
case "--constats":
    // Relevé des seuils du carnet de progrès (Carnet.releve), en lecture seule : des identifiants
    // (aperçus demandés au module, comme view_photo, sans rien noter au carnet) et des fichiers JPEG
    // (mesurés sans Lightroom).
    var ids: [Int] = [], fichiers: [URL] = []
    for item in arguments.dropFirst() {
        if let id = Int(item) {
            ids.append(id)
        } else if FileManager.default.fileExists(atPath: item) {
            fichiers.append(URL(fileURLWithPath: item))
        } else {
            log("argument inconnu : \(item) (ni identifiant de photo, ni fichier)")
            usage()
            exit(2)
        }
    }
    guard !ids.isEmpty || !fichiers.isEmpty else { usage(); exit(2) }
    let lignes = Carnet.releve(lightroom: LightroomBridge.fromEnvironment(), ids: ids, fichiers: fichiers) { print(line: $0) }
    exit(lignes.contains { $0.hasPrefix("✘") } ? 1 : 0)
case "--module":
    // Commande brute du module (diagnostic…), pour explorer ce que le SDK de Lightroom offre.
    guard arguments.count >= 2 else { usage(); exit(2) }
    do {
        let params = arguments.count >= 3 ? (try JSONCoding.parse(arguments[2]).object ?? [:]) : [:]
        print(line: JSONCoding.pretty(try LightroomBridge.fromEnvironment().send(arguments[1], params, timeout: 60)))
    } catch {
        log(error.localizedDescription)
        exit(1)
    }
case "--recette":
    var raw: Int?, jpeg: Int?, flash: Int?, profondeur: Int?, yeuxRouges: Int?, xt20: Int?, portrait: Int?, mixte: Int?, horizon: Int?
    var hauteurHorizon: Double?
    var images: URL?, originaux = false
    var rest = Array(arguments.dropFirst())
    while !rest.isEmpty {
        let item = rest.removeFirst()
        func next() -> String { guard !rest.isEmpty else { usage(); exit(2) }; return rest.removeFirst() }
        switch item {
        case "--jpeg": jpeg = Int(next())
        case "--flash": flash = Int(next())
        case "--profondeur": profondeur = Int(next())
        case "--yeux-rouges": yeuxRouges = Int(next())
        case "--x-t20": xt20 = Int(next())
        case "--portrait": portrait = Int(next())
        case "--mixte": mixte = Int(next())
        case "--horizon": horizon = Int(next())
        case "--hauteur-horizon":
            // La virgule française comme le point.
            guard let y = Double(next().replacingOccurrences(of: ",", with: ".")), (0.05...0.95).contains(y) else {
                log("--hauteur-horizon : la hauteur de l'horizon dans l'image, de 0,05 à 0,95 depuis le haut")
                exit(2)
            }
            hauteurHorizon = y
        case "--images": images = URL(fileURLWithPath: next())
        case "--original": originaux = true
        default:
            guard let id = Int(item) else { log("argument inconnu : \(item)"); usage(); exit(2) }
            raw = id
        }
    }
    guard [raw, jpeg, flash, profondeur, yeuxRouges, xt20, portrait, mixte, horizon].contains(where: { $0 != nil }) else { usage(); exit(2) }
    if hauteurHorizon != nil, horizon == nil { log("--hauteur-horizon va avec --horizon <id>"); usage(); exit(2) }
    let folder = images ?? FileManager.default.temporaryDirectory.appendingPathComponent("recette-mcp-developpeur-\(Int(Date().timeIntervalSince1970))")
    print(line: originaux
        ? "Recette de MCP-Développeur \(ServerInfo.version) : originaux acceptés (--original), chaque photo remise à l'origine à la fin."
        : "Recette de MCP-Développeur \(ServerInfo.version) : copies virtuelles seulement, chacune remise à l'origine à la fin.")
    print(line: "Images à regarder : \(folder.path)")
    if horizon == nil {
        print(line: "Sans --horizon : la composition lue (1.3) n'est pas vérifiée (une copie d'Essais qui a un vrai horizon).")
    }
    let recette = Recette(lightroom: LightroomBridge.fromEnvironment(), images: folder, originaux: originaux) { etape in
        let seconds = String(format: "%.1f", etape.duree).replacingOccurrences(of: ".", with: ",")
        print(line: "\(etape.reussie ? "✔" : "✘") \(etape.photo) · \(etape.nom) — \(etape.detail) (\(seconds) s)")
    }
    // L'étape « écran nommé » lit l'écran du Mac (la recette n'en lit aucun par défaut).
    recette.lireEcran = Ecran.lire
    if let hauteurHorizon { recette.hauteurHorizon = hauteurHorizon }
    recette.lancer(raw: raw, jpeg: jpeg, flash: flash, profondeur: profondeur, yeuxRouges: yeuxRouges, xt20: xt20,
                   portrait: portrait, mixte: mixte, horizon: horizon)
    let failures = recette.etapes.filter { !$0.reussie }.count
    print(line: failures == 0 ? "Recette réussie : \(recette.etapes.count) étapes." : "Recette en échec : \(failures) étape(s) sur \(recette.etapes.count).")
    exit(recette.reussie ? 0 : 1)
default:
    log("option inconnue : \(arguments[0])")
    usage()
    exit(2)
}
