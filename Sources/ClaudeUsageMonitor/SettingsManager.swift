import Foundation

enum IntegrationStatus: Equatable {
    case active
    case disabledByHooks
    case misconfigured
}

enum SettingsManager {
    static func install(executablePath: String, paths: AppPaths = .current) throws {
        let store = StateStore(paths: paths)
        try store.secureDirectory(paths.baseDirectory)

        var settings = try readObject(paths.claudeSettingsFile) ?? [:]
        let command = desiredCommand(executablePath: executablePath)
        let current = settings["statusLine"] as? [String: Any]
        let currentCommand = current?["command"] as? String
        let currentType = current?["type"] as? String

        if currentCommand == command, currentType == "command" { return }

        if !isMonitorCommand(currentCommand) {
            let backup: [String: Any] = [
                "hadStatusLine": settings.keys.contains("statusLine"),
                "statusLine": settings["statusLine"] ?? NSNull()
            ]
            try writeObject(backup, to: paths.statusLineBackupFile)
        }

        var statusLine = current ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        try writeObject(settings, to: paths.claudeSettingsFile)
    }

    static func uninstall(executablePath: String, paths: AppPaths = .current) throws {
        guard var settings = try readObject(paths.claudeSettingsFile) else { return }
        let current = settings["statusLine"] as? [String: Any]
        let currentCommand = current?["command"] as? String
        let desired = desiredCommand(executablePath: executablePath)
        guard currentCommand == desired || isMonitorCommand(currentCommand) else { return }

        let backup = try readObject(paths.statusLineBackupFile)
        if backup?["hadStatusLine"] as? Bool == true {
            settings["statusLine"] = backup?["statusLine"]
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeObject(settings, to: paths.claudeSettingsFile)
    }

    static func isInstalled(executablePath: String, paths: AppPaths = .current) throws -> Bool {
        let settings = try readObject(paths.claudeSettingsFile)
        let statusLine = settings?["statusLine"] as? [String: Any]
        return statusLine?["type"] as? String == "command" &&
            statusLine?["command"] as? String == desiredCommand(executablePath: executablePath)
    }

    static func integrationStatus(
        executablePath: String,
        paths: AppPaths = .current
    ) throws -> IntegrationStatus {
        guard let settings = try readObject(paths.claudeSettingsFile),
              let statusLine = settings["statusLine"] as? [String: Any],
              statusLine["type"] as? String == "command",
              statusLine["command"] as? String == desiredCommand(executablePath: executablePath) else {
            return .misconfigured
        }
        return settings["disableAllHooks"] as? Bool == true ? .disabledByHooks : .active
    }

    static func desiredCommand(executablePath: String) -> String {
        let absolutePath = URL(fileURLWithPath: executablePath).standardizedFileURL.path
        return "\(shellQuote(absolutePath)) --ingest-statusline"
    }

    static func isMonitorCommand(_ command: String?) -> Bool {
        guard let command else { return false }
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let argument = " --ingest-statusline"
        guard normalized.hasSuffix(argument) else { return false }
        let launcher = normalized.dropLast(argument.count)

        let currentQuoted = launcher.hasPrefix("'") &&
            launcher.hasSuffix("/ClaudeUsageMonitor'")
        let currentUnquoted = !launcher.contains(where: \.isWhitespace) &&
            launcher.hasPrefix("/") && launcher.hasSuffix("/ClaudeUsageMonitor")
        let legacy = launcher.hasPrefix("/bin/zsh ") &&
            launcher.contains("/ClaudeUsageMonitor/app/") &&
            (launcher.hasSuffix("/run-monitor.command'") ||
                launcher.hasSuffix("/run-monitor.command"))
        return currentQuoted || currentUnquoted || legacy
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func readObject(_ file: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "ClaudeUsageMonitor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.invalidJSON(file.path)]
            )
        }
        return object
    }

    private static func writeObject(_ object: [String: Any], to file: URL) throws {
        // Escreve no destino do link, não por cima dele. A gravação atômica
        // troca o arquivo por outro e substituiria o link por uma cópia solta:
        // quem mantém `~/.claude/settings.json` apontado para um repositório de
        // dotfiles ficava com o link desfeito e o repositório congelado no
        // conteúdo antigo, sem aviso nenhum.
        let file = file.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: file.path
        )
    }
}
