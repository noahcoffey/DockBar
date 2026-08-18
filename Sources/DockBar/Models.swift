import Foundation

// MARK: - Dokploy API payloads

struct APIProject: Decodable {
    let projectId: String
    let name: String
    let environments: [APIEnvironment]?
}

struct APIEnvironment: Decodable {
    let environmentId: String
    let name: String
    let applications: [APIApplication]?
    let compose: [APICompose]?
}

struct APIApplication: Decodable {
    let applicationId: String
    let name: String
    let applicationStatus: String
}

struct APICompose: Decodable {
    let composeId: String
    let name: String
    let composeStatus: String
}

struct APIDeployment: Decodable, Sendable {
    let deploymentId: String
    let status: String?
    let title: String?
    let description: String?
    let createdAt: String
}

// MARK: - Internal model

enum ServiceKind: Sendable {
    case application
    case compose
}

struct Service: Sendable {
    let kind: ServiceKind
    let id: String
    let name: String
    let status: String
    let org: String
    let apiKey: String
    let projectId: String
    let projectName: String
    let environmentId: String
    let environmentName: String

    var isDeploying: Bool { status == "running" }

    func dashboardURL(serverUrl: String) -> URL? {
        let type = kind == .application ? "application" : "compose"
        return URL(string: "\(serverUrl)/dashboard/project/\(projectId)/environment/\(environmentId)/services/\(type)/\(id)")
    }
}

struct DeployEntry: Sendable {
    let deployment: APIDeployment
    let service: Service
    let date: Date
}

struct Snapshot: Sendable {
    let services: [Service]
    let deploying: [Service]
    let recent: [DeployEntry]
    let orgErrors: [String]
    let fetchedAt: Date
}
