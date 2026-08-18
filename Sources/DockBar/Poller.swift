import Foundation

final class Poller: Sendable {
    private let config: Config
    private let session: URLSession
    private let apiBase: URL

    init(config: Config) {
        self.config = config
        self.apiBase = URL(string: config.serverUrl)!.appendingPathComponent("api")
        let sc = URLSessionConfiguration.ephemeral
        sc.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: sc)
    }

    func fetch() async -> Snapshot {
        var services: [Service] = []
        var orgErrors: [String] = []

        for org in config.orgs {
            do {
                let projects: [APIProject] = try await get("project.all", apiKey: org.apiKey)
                for p in projects {
                    for e in p.environments ?? [] {
                        for a in e.applications ?? [] {
                            services.append(Service(
                                kind: .application, id: a.applicationId, name: a.name,
                                status: a.applicationStatus, org: org.name, apiKey: org.apiKey,
                                projectId: p.projectId, projectName: p.name,
                                environmentId: e.environmentId, environmentName: e.name))
                        }
                        for c in e.compose ?? [] {
                            services.append(Service(
                                kind: .compose, id: c.composeId, name: c.name,
                                status: c.composeStatus, org: org.name, apiKey: org.apiKey,
                                projectId: p.projectId, projectName: p.name,
                                environmentId: e.environmentId, environmentName: e.name))
                        }
                    }
                }
            } catch {
                orgErrors.append("\(org.name): \(error.localizedDescription)")
            }
        }

        var entries: [DeployEntry] = []
        await withTaskGroup(of: [DeployEntry].self) { group in
            for s in services {
                group.addTask {
                    let path = s.kind == .application ? "deployment.all" : "deployment.allByCompose"
                    let query = s.kind == .application ? ["applicationId": s.id] : ["composeId": s.id]
                    guard let deps: [APIDeployment] = try? await self.get(path, apiKey: s.apiKey, query: query) else {
                        return []
                    }
                    return deps.prefix(10).compactMap { d in
                        guard let date = Self.parseDate(d.createdAt) else { return nil }
                        return DeployEntry(deployment: d, service: s, date: date)
                    }
                }
            }
            for await result in group {
                entries.append(contentsOf: result)
            }
        }
        entries.sort { $0.date > $1.date }

        return Snapshot(
            services: services,
            deploying: services.filter { $0.isDeploying },
            recent: Array(entries.prefix(10)),
            orgErrors: orgErrors,
            fetchedAt: Date())
    }

    private func get<T: Decodable>(_ path: String, apiKey: String, query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "DockBar", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) from \(path)"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parseDate(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }
}
