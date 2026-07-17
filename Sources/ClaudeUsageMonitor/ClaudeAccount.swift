import Foundation

struct ClaudeAccount: Equatable {
    let email: String?
    let authMethod: String?
}

enum ClaudeAccountStatus: Equatable {
    case loggedIn(ClaudeAccount)
    case loggedOut
    case unavailable
}

enum ClaudeAccountReader {
    private struct AuthStatusPayload: Decodable {
        let loggedIn: Bool
        let authMethod: String?
        let emailAddress: String?
        let email: String?
    }

    private struct ProfilePayload: Decodable {
        let oauthAccount: OAuthAccount?

        struct OAuthAccount: Decodable {
            let emailAddress: String?
        }
    }

    static func parse(authData: Data, profileData: Data?) -> ClaudeAccountStatus {
        guard let auth = try? JSONDecoder().decode(AuthStatusPayload.self, from: authData) else {
            return .unavailable
        }
        guard auth.loggedIn else { return .loggedOut }

        let profileEmail = profileData
            .flatMap { try? JSONDecoder().decode(ProfilePayload.self, from: $0) }
            .flatMap(\.oauthAccount?.emailAddress)
        let authMethod = clean(auth.authMethod)
        let usesAPIKey = authMethod?.lowercased().contains("api") == true
        let email = cleanEmail(auth.emailAddress ?? auth.email ?? (usesAPIKey ? nil : profileEmail))
        return .loggedIn(ClaudeAccount(email: email, authMethod: authMethod))
    }

    static func load(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        executableURL: URL? = nil,
        timeout: TimeInterval = 2
    ) -> ClaudeAccountStatus {
        guard let executable = executableURL ?? findExecutable(homeDirectory: homeDirectory) else {
            return .unavailable
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["auth", "status", "--json"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        let searchDirectories = [
            homeDirectory.appendingPathComponent(".local/bin").path,
            homeDirectory.appendingPathComponent(".volta/bin").path,
            homeDirectory.appendingPathComponent(".bun/bin").path,
            homeDirectory.appendingPathComponent(".npm-global/bin").path,
            "/opt/homebrew/bin",
            "/opt/local/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        environment["PATH"] = (searchDirectories + [environment["PATH"] ?? ""])
            .joined(separator: ":")
        process.environment = environment

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return .unavailable
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            _ = finished.wait(timeout: .now() + 0.5)
            return .unavailable
        }

        let authData = output.fileHandleForReading.readDataToEndOfFile()
        let profileURL = homeDirectory.appendingPathComponent(".claude.json")
        let profileData = try? Data(contentsOf: profileURL)
        return parse(authData: authData, profileData: profileData)
    }

    static func findExecutable(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        if let override = environment["CLAUDE_USAGE_MONITOR_CLAUDE_EXECUTABLE"],
           !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates += [
            homeDirectory.appendingPathComponent(".local/bin/claude"),
            homeDirectory.appendingPathComponent(".claude/local/claude"),
            homeDirectory.appendingPathComponent(".volta/bin/claude"),
            homeDirectory.appendingPathComponent(".bun/bin/claude"),
            homeDirectory.appendingPathComponent(".npm-global/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/opt/local/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        if let path = environment["PATH"] {
            candidates += path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("claude")
            }
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func cleanEmail(_ value: String?) -> String? {
        guard let value = clean(value), value.contains("@"), value.count <= 254 else { return nil }
        return value
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : String(normalized.prefix(254))
    }
}
