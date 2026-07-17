import AppKit
import Foundation

private func showCachedState() -> Int32 {
    guard let state = StateStore().load() else {
        FileHandle.standardError.write(Data("\(L10n.noDataCLI)\n".utf8))
        return 2
    }

    var parts = [UsageFormatter.summary(state)]
    if let model = state.session?.modelDisplayName {
        parts.append("\(L10n.modelSummaryLabel): \(model)")
    }
    if let project = state.session?.projectName {
        parts.append("\(L10n.projectSummaryLabel): \(project)")
    }
    print(parts.joined(separator: " • "))
    return 0
}

let arguments = Set(CommandLine.arguments.dropFirst())

do {
    if arguments.contains("--ingest-statusline") {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        print(try StatusLineProcessor.run(input: input))
    } else if arguments.contains("--install-statusline") {
        try SettingsManager.install(executablePath: CommandLine.arguments[0])
    } else if arguments.contains("--uninstall-statusline") {
        try SettingsManager.uninstall(executablePath: CommandLine.arguments[0])
    } else if arguments.contains("--show") {
        exit(showCachedState())
    } else {
        let application = NSApplication.shared
        let delegate = MenuBarApp()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
} catch {
    FileHandle.standardError.write(Data("\(L10n.failure): \(error.localizedDescription)\n".utf8))
    exit(1)
}
