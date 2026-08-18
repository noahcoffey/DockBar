import Foundation

struct OrgConfig: Codable, Sendable {
    let name: String
    let apiKey: String
}

enum ConfigError: Error {
    case missing
    case invalid(Error)
    case notFilledIn
}

struct Config: Codable, Sendable {
    let serverUrl: String
    var pollSeconds: Double?
    let orgs: [OrgConfig]

    var idleInterval: TimeInterval { pollSeconds ?? 30 }

    /// True while the config still contains the template placeholders.
    var isTemplate: Bool {
        serverUrl.contains("dokploy.example.com")
            || orgs.isEmpty
            || orgs.contains { $0.apiKey.contains("PASTE-API-KEY") }
    }

    static var path: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DockBar/config.json")
    }

    static func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ConfigError.missing
        }
        do {
            let data = try Data(contentsOf: path)
            let config = try JSONDecoder().decode(Config.self, from: data)
            if config.isTemplate { throw ConfigError.notFilledIn }
            guard let url = URL(string: config.serverUrl),
                  url.scheme == "http" || url.scheme == "https" else {
                throw ConfigError.invalid(NSError(
                    domain: "DockBar", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "serverUrl must be an http(s) URL"]))
            }
            return config
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.invalid(error)
        }
    }

    /// Writes a starter config for first launch. Does not overwrite an existing file.
    static func writeTemplate() throws {
        guard !FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let template = """
        {
          "_help": "DockBar config. Set serverUrl to your Dokploy instance (no trailing slash). Add one entry per organization — Dokploy API keys are scoped per org; generate them in the Dokploy dashboard under Settings. After editing, use 'Reload Config' from the DockBar menu.",
          "serverUrl": "https://dokploy.example.com",
          "pollSeconds": 30,
          "orgs": [
            { "name": "My Org", "apiKey": "PASTE-API-KEY-HERE" }
          ]
        }
        """
        try template.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}
