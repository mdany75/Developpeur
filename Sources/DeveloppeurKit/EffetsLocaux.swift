import Foundation

/// Un effet local de Lightroom (« Blanchiment des dents », « Renforcement de l'iris », « Adoucir la
/// peau »…) : un paramètre prédéfini de réglage local, que Lightroom range en fichier
/// `.lrtemplate` (une table Lua : `internalName`, `title`, `value` = réglages locaux). `locaux`
/// donne ses réglages sous les clés d'une correction de masque (`LocalExposure2012`…), à
/// l'échelle de Lightroom (−1 à +1 ; exposition : ±1 = ±4 IL).
public struct LocalEffect: Equatable {
    /// Nom du fichier, tel que Lightroom l'affiche dans le menu Effet du panneau Masque.
    public var name: String
    /// Nom anglais d'Adobe (`internalName`, « Teeth Whitening »), vide pour un effet de l'utilisateur.
    public var internalName: String
    public var locaux: [String: Double]

    /// Vrai pour son nom, son nom anglais ou le texte de son titre, sans la casse ni les accents.
    public func matches(_ text: String) -> Bool {
        let wanted = LocalEffectLibrary.key(text)
        return [name, internalName].contains { !$0.isEmpty && LocalEffectLibrary.key($0) == wanted }
    }
}

/// Les effets locaux de ce Mac : ceux de l'utilisateur (premier dossier : Local Adjustment Presets
/// de Lightroom, où Lightroom copie aussi ses six effets, sous leur nom français), puis ceux livrés
/// dans l'application qui n'y sont pas, sous leur nom anglais, puis les effets intégrés au serveur
/// qui manquent encore : la dose d'Adobe pour la peau (`Peau.effetsIntegres`, « Peau du visage
/// lisse » et « Adoucir la peau (Lite) »). Relus à chaque demande : ce sont quelques petits fichiers.
public struct LocalEffectLibrary {
    public static var defaultFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/Adobe/Lightroom/Local Adjustment Presets"),
            URL(fileURLWithPath: LookProfileLibrary.lightroomApp + "/Contents/PlugIns/Develop.lrmodule/Contents/Resources/localized_presets"),
        ]
    }

    /// Clés d'un effet (process version 2012 et suivantes) → clés d'une correction de masque.
    /// Les anciennes clés (`exposure`, `contrast`, `clarity`, `brightness`) ne valent que pour les
    /// versions de processus 2003 et 2010 : elles sont écartées.
    static let keys: [String: String] = [
        "exposure2012": "LocalExposure2012", "contrast2012": "LocalContrast2012", "highlights2012": "LocalHighlights2012",
        "shadows2012": "LocalShadows2012", "whites2012": "LocalWhites2012", "blacks2012": "LocalBlacks2012",
        "clarity2012": "LocalClarity2012", "texture": "LocalTexture", "dehaze": "LocalDehaze",
        "temperature": "LocalTemperature", "tint": "LocalTint", "saturation": "LocalSaturation",
        "sharpness": "LocalSharpness", "luminanceNoise": "LocalLuminanceNoise", "moire": "LocalMoire",
        "defringe": "LocalDefringe", "toningHue": "LocalToningHue", "toningSaturation": "LocalToningSaturation",
    ]

    let folders: [URL]

    public init(folders: [URL] = LocalEffectLibrary.defaultFolders) {
        self.folders = folders
    }

    /// Les effets, par nom ; un effet livré que l'utilisateur a déjà (même nom anglais) n'est pas
    /// répété, ni un effet intégré qu'un fichier porte déjà (même nom, français ou anglais).
    public var effects: [LocalEffect] {
        var found: [LocalEffect] = []
        for (index, folder) in folders.enumerated() {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "lrtemplate" {
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      var effect = Self.parse(text, name: file.deletingPathExtension().lastPathComponent) else { continue }
                // Les fichiers livrés s'appellent « IrisEnhance » : leur nom est celui d'Adobe.
                if index > 0, !effect.internalName.isEmpty { effect.name = effect.internalName }
                if found.contains(where: { !effect.internalName.isEmpty && $0.internalName == effect.internalName || $0.name == effect.name }) {
                    continue
                }
                found.append(effect)
            }
        }
        // Après les fichiers, qui l'emportent : un effet de l'utilisateur du même nom garde ses valeurs.
        for effect in Peau.effetsIntegres where !found.contains(where: { trouve in
            [effect.name, effect.internalName].contains { !$0.isEmpty && trouve.matches($0) }
        }) {
            found.append(effect)
        }
        return found
    }

    public func effect(named name: String) -> LocalEffect? {
        effects.first { $0.matches(name) }
    }

    /// Lit un fichier `.lrtemplate` d'effet local ; nil si ce n'en est pas un.
    static func parse(_ text: String, name: String) -> LocalEffect? {
        guard text.contains("LocalizedAdjustmentPreset"),
              let start = text.range(of: #"value\s*=\s*\{"#, options: .regularExpression),
              let end = text[start.upperBound...].firstIndex(of: "}") else { return nil }
        var values: [String: Double] = [:]
        let body = String(text[start.upperBound..<end])
        let pattern = try! NSRegularExpression(pattern: #"([A-Za-z0-9_]+)\s*=\s*(-?[0-9.]+(?:[eE][-+]?[0-9]+)?)"#)
        for match in pattern.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
            guard let keyRange = Range(match.range(at: 1), in: body), let valueRange = Range(match.range(at: 2), in: body),
                  let value = Double(body[valueRange]) else { continue }
            values[String(body[keyRange])] = value
        }
        var locaux: [String: Double] = [:]
        for (key, value) in values {
            guard let local = keys[key], value != 0 else { continue }
            // Une teinte sans saturation ne colore rien (Lightroom y range 240 par défaut).
            if key == "toningHue", (values["toningSaturation"] ?? 0) == 0 { continue }
            locaux[local] = (value * 1e6).rounded() / 1e6
        }
        var internalName = ""
        if let match = text.range(of: #"internalName\s*=\s*"([^"]*)""#, options: .regularExpression) {
            internalName = String(text[match]).components(separatedBy: "\"").dropFirst().first ?? ""
        }
        return LocalEffect(name: name, internalName: internalName, locaux: locaux)
    }

    /// Texte comparable : minuscules, sans accents ni espaces superflus.
    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
