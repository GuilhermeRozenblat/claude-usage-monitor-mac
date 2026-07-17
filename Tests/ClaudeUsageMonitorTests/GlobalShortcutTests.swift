import XCTest
@testable import ClaudeUsageMonitor

final class GlobalShortcutTests: XCTestCase {
    private func scratch() -> (GlobalShortcut, UserDefaults) {
        let suite = "ClaudeUsageMonitorTests.Shortcut.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (GlobalShortcut(defaults: defaults), defaults)
    }

    func testOffByDefault() {
        let (shortcut, _) = scratch()
        XCTAssertFalse(shortcut.isEnabled)
    }

    func testEnablingRegistersAndPersists() {
        let (shortcut, _) = scratch()
        XCTAssertTrue(shortcut.setEnabled(true))
        XCTAssertTrue(shortcut.isEnabled)

        XCTAssertTrue(shortcut.setEnabled(false))
        XCTAssertFalse(shortcut.isEnabled)
    }

    /// Ligar duas vezes não pode registar dois hot keys: o segundo registo
    /// falharia e a caixa recuaria sozinha, dizendo que há conflito quando o
    /// único conflito seríamos nós.
    func testEnablingTwiceIsHarmless() {
        let (shortcut, _) = scratch()
        XCTAssertTrue(shortcut.setEnabled(true))
        XCTAssertTrue(shortcut.setEnabled(true))
        XCTAssertTrue(shortcut.isEnabled)
        shortcut.setEnabled(false)
    }

    /// A preferência é o que sobrevive ao encerrar; `restore` é quem a aplica.
    func testRestoreFollowsTheStoredPreference() {
        let (shortcut, defaults) = scratch()
        shortcut.restore()
        XCTAssertFalse(shortcut.isEnabled)

        defaults.set(true, forKey: "shortcut.panel.enabled")
        XCTAssertTrue(shortcut.isEnabled)
        shortcut.restore()
        shortcut.setEnabled(false)
    }
}
