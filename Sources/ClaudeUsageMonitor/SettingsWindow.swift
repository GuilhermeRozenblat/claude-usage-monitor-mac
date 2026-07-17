import AppKit
import ServiceManagement

/// Os ajustes estavam espalhados por três submenus e não havia ⌘, nenhum.
/// Aqui são uma janela só, com o vocabulário de formulário do sistema.
///
/// Sem vidro por dentro, de propósito: os Ajustes do Sistema do macOS 26 usam
/// a moldura padrão, e um formulário translúcido é decoração, não material. O
/// vidro pertence ao painel da barra de menus.
final class SettingsWindowController: NSWindowController {
    init(
        alertPreferences: AlertPreferences,
        shortcut: GlobalShortcut,
        onReconfigure: @escaping () -> Void,
        onDataFolder: @escaping () -> Void,
        onLanguageChange: @escaping () -> Void
    ) {
        // Altura mínima de propósito: o NSTabViewController cresce a janela até
        // caber o painel, mas não a encolhe abaixo do que ela nasceu. Com uma
        // altura inicial "de reserva" sobrava um rodapé vazio.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsPane.width, height: 10),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.settings
        window.isReleasedWhenClosed = false
        super.init(window: window)

        // Idioma era uma aba inteira para um único popup. Duas abas com peso
        // parecido dizem mais sobre o app do que três, uma delas quase vazia.
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab(
            GeneralPane(
                shortcut: shortcut,
                onReconfigure: onReconfigure,
                onDataFolder: onDataFolder,
                onLanguageChange: onLanguageChange
            ),
            title: L10n.settingsGeneral,
            symbol: "gearshape"
        ))
        tabs.addTabViewItem(tab(
            AlertsPane(preferences: alertPreferences),
            title: L10n.settingsAlerts,
            symbol: "bell"
        ))
        window.contentViewController = tabs
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Os painéis, para os testes os medirem e renderizarem sem abrir a janela.
    var panesForTesting: [NSViewController] {
        (window?.contentViewController as? NSTabViewController)?
            .tabViewItems.compactMap(\.viewController) ?? []
    }

    private func tab(_ controller: NSViewController, title: String, symbol: String) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Vocabulário de formulário

/// Um painel de ajustes: cabeçalho à esquerda, controlos à direita, a mesma
/// grade que os Ajustes do Sistema usam.
private class SettingsPane: NSViewController {
    /// Largura fixa e partilhada. Com larguras livres cada painel assentava na
    /// sua, e a janela saltava de tamanho a cada troca de aba.
    static let width: CGFloat = 480
    private static let margin: CGFloat = 20
    /// Onde a coluna de controlos começa, e portanto quanto espaço sobra para
    /// o texto lá dentro.
    static let labelColumn: CGFloat = 150
    /// Desconta também o espaçamento entre colunas: sem ele a conta dava 12 pt
    /// a mais do que a coluna real, e a nota calculava a quebra numa largura
    /// que não tinha, cortando a última palavra.
    static var contentWidth: CGFloat { width - labelColumn - margin * 2 - columnSpacing }
    private static let columnSpacing: CGFloat = 12

    private let grid = NSGridView(numberOfColumns: 2, rows: 0)
    private var header: NSView?

    override func loadView() {
        view = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = Self.columnSpacing
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        view.addSubview(grid)

        var constraints: [NSLayoutConstraint] = [
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.margin),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.margin),
            // `lessThanOrEqualTo`, não `equalTo`: preso em cima e em baixo, o
            // NSGridView estica e reparte a sobra pelas linhas, abrindo um vão
            // de ~95 pt no meio do formulário. Assim a grade fica colada ao
            // topo e a folga sobra em baixo, onde não se nota.
            grid.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -22),
            view.widthAnchor.constraint(equalToConstant: Self.width),
        ]

        if let header = buildHeader() {
            self.header = header
            header.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(header)
            constraints += [
                header.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
                header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.margin),
                header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.margin),
                grid.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            ]
        } else {
            constraints.append(grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 22))
        }

        NSLayoutConstraint.activate(constraints)
        grid.column(at: 0).width = Self.labelColumn
        build()
    }

    /// Subclasses preenchem a grade aqui.
    func build() {}

    /// Cabeçalho opcional acima da grade.
    func buildHeader() -> NSView? { nil }

    func section(_ title: String, _ content: NSView) {
        let label = NSTextField(labelWithString: title + ":")
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .labelColor
        label.alignment = .right
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        grid.addRow(with: [label, content])
        grid.row(at: grid.numberOfRows - 1).topPadding = 6
    }

    /// Nota de rodapé sob a última secção, alinhada aos controlos.
    func footnote(_ text: String) {
        let note = NSTextField(wrappingLabelWithString: text)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        // A largura tem de ser a da coluna de controlos. Um valor inventado
        // cortava a frase ("…reabre as janelas" perdia "do monitor").
        note.preferredMaxLayoutWidth = Self.contentWidth
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        grid.addRow(with: [NSGridCell.emptyContentView, note])
        grid.row(at: grid.numberOfRows - 1).topPadding = 2
    }

    func column(_ views: [NSView], spacing: CGFloat = 6) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    func checkbox(_ title: String, target: AnyObject, action: Selector, on: Bool) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: target, action: action)
        button.state = on ? .on : .off
        return button
    }
}

// MARK: - Identidade

/// Ícone, nome, versão e autoria, no topo dos Ajustes.
///
/// A autoria estava só na janela Sobre, a dois cliques de distância no menu
/// "•••". Aqui é a primeira coisa da primeira aba, sem roubar espaço ao painel
/// da barra, que é para se olhar de relance e não para creditar ninguém.
private final class IdentityHeaderView: NSView {
    init() {
        super.init(frame: .zero)

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Claude Usage Monitor")

        let name = NSTextField(labelWithString: "Claude Usage Monitor")
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.textColor = .labelColor

        let version = NSTextField(labelWithString: "\(L10n.aboutVersion) \(Self.appVersion)")
        version.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        version.textColor = .secondaryLabelColor

        let author = NSTextField()
        author.isEditable = false
        author.isBordered = false
        author.drawsBackground = false
        author.attributedStringValue = Self.authorLine()
        author.setAccessibilityLabel("\(L10n.developedBy) Guilherme Rozenblat. \(L10n.madeInBrazil).")

        let text = NSStackView(views: [name, version, author])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setHuggingPriority(.defaultHigh, for: .horizontal)

        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let rule = SeparatorView()
        addSubview(rule)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 52),
            icon.heightAnchor.constraint(equalToConstant: 52),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            rule.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 18),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// "Desenvolvido por" fica em tom secundário e o nome em tom cheio: o olho
    /// pousa no nome, não na preposição.
    private static func authorLine() -> NSAttributedString {
        let line = NSMutableAttributedString(
            string: "\(L10n.developedBy) ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        line.append(NSAttributedString(
            string: "Guilherme Rozenblat",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        line.append(NSAttributedString(
            string: "  🇧🇷",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        ))
        return line
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "--"
    }
}

// MARK: - Geral

private final class GeneralPane: SettingsPane {
    private let shortcut: GlobalShortcut
    private let onReconfigure: () -> Void
    private let onDataFolder: () -> Void
    private let onLanguageChange: () -> Void
    private let loginCheckbox = NSButton()
    private let shortcutCheckbox = NSButton()

    init(
        shortcut: GlobalShortcut,
        onReconfigure: @escaping () -> Void,
        onDataFolder: @escaping () -> Void,
        onLanguageChange: @escaping () -> Void
    ) {
        self.shortcut = shortcut
        self.onReconfigure = onReconfigure
        self.onDataFolder = onDataFolder
        self.onLanguageChange = onLanguageChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func buildHeader() -> NSView? {
        IdentityHeaderView()
    }

    override func build() {
        loginCheckbox.setButtonType(.switch)
        loginCheckbox.title = L10n.openAtLogin
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        section(L10n.settingsStartup, loginCheckbox)

        shortcutCheckbox.setButtonType(.switch)
        shortcutCheckbox.title = L10n.openWithShortcut(GlobalShortcut.displayName)
        shortcutCheckbox.state = shortcut.isEnabled ? .on : .off
        shortcutCheckbox.target = self
        shortcutCheckbox.action = #selector(toggleShortcut)
        section(L10n.settingsShortcut, shortcutCheckbox)
        footnote(L10n.settingsShortcutFooter)

        let popup = NSPopUpButton()
        for preference in LanguagePreference.allCases {
            let item = NSMenuItem(title: Self.languageTitle(preference), action: nil, keyEquivalent: "")
            item.representedObject = preference.rawValue
            popup.menu?.addItem(item)
        }
        popup.selectItem(at: LanguagePreference.allCases.firstIndex(of: L10n.preference) ?? 0)
        popup.target = self
        popup.action = #selector(selectLanguage(_:))
        section(L10n.settingsLanguage, popup)
        footnote(L10n.settingsLanguageFooter)

        let reconfigure = NSButton(
            title: L10n.reconfigureClaudeCode,
            target: self,
            action: #selector(reconfigure)
        )
        reconfigure.bezelStyle = .rounded
        section(L10n.settingsIntegration, reconfigure)
        footnote(L10n.settingsIntegrationFooter)

        let folder = NSButton(
            title: L10n.openDataFolder,
            target: self,
            action: #selector(dataFolder)
        )
        folder.bezelStyle = .rounded
        section(L10n.settingsData, folder)
        footnote(L10n.settingsDataFooter)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshLoginState()
    }

    /// O estado real vive no SMAppService, não numa preferência nossa: o
    /// utilizador pode revogar a permissão nos Ajustes do Sistema a qualquer
    /// momento, e a caixa tem de contar a verdade ao reabrir.
    private func refreshLoginState() {
        switch SMAppService.mainApp.status {
        case .enabled: loginCheckbox.state = .on
        case .requiresApproval: loginCheckbox.state = .mixed
        default: loginCheckbox.state = .off
        }
    }

    private static func languageTitle(_ preference: LanguagePreference) -> String {
        switch preference {
        case .automatic: L10n.automaticLanguage
        case .en: "English"
        case .ptBR: "Português (Brasil)"
        case .es: "Español"
        }
    }

    @objc private func selectLanguage(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let preference = LanguagePreference(rawValue: raw),
              preference != L10n.preference else { return }
        L10n.setPreference(preference)
        onLanguageChange()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = L10n.couldNotToggleLogin
            alert.runModal()
        }
        refreshLoginState()
    }

    /// O sistema recusa a combinação se outro app a registou primeiro. Nesse
    /// caso a caixa volta atrás: deixá-la ligada prometia um atalho que não
    /// existe.
    @objc private func toggleShortcut(_ sender: NSButton) {
        guard shortcut.setEnabled(sender.state == .on) else {
            sender.state = .off
            let alert = NSAlert()
            alert.messageText = L10n.couldNotEnableShortcut
            alert.informativeText = L10n.shortcutUnavailable(GlobalShortcut.displayName)
            alert.alertStyle = .warning
            if let window = view.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
            return
        }
    }

    @objc private func reconfigure() { onReconfigure() }
    @objc private func dataFolder() { onDataFolder() }
}

// MARK: - Alertas

private final class AlertsPane: SettingsPane {
    private let preferences: AlertPreferences
    private let snoozeCheckbox = NSButton()
    private var profileButtons: [(NSButton, ThresholdProfile)] = []

    init(preferences: AlertPreferences) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func build() {
        section(L10n.settingsNotifications, column([
            checkbox(
                L10n.fiveHourAlerts,
                target: self,
                action: #selector(toggleFiveHour),
                on: preferences.fiveHourAlertsEnabled
            ),
            checkbox(
                L10n.sevenDayAlerts,
                target: self,
                action: #selector(toggleSevenDay),
                on: preferences.sevenDayAlertsEnabled
            ),
            checkbox(
                L10n.windowResetAlerts,
                target: self,
                action: #selector(toggleWindowReset),
                on: preferences.windowResetAlertsEnabled
            ),
        ]))

        let profiles: [(String, ThresholdProfile)] = [
            (L10n.profileAll, .all),
            (L10n.profileHigh, .high),
            (L10n.profileCritical, .critical),
        ]
        // Rádios: os três marcos são mutuamente exclusivos. Eram três itens de
        // menu com checkmark, que não diziam isso.
        let radios = profiles.map { title, profile -> NSButton in
            let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(selectProfile))
            button.state = preferences.thresholdProfile == profile ? .on : .off
            profileButtons.append((button, profile))
            return button
        }
        section(L10n.milestonesHeader, column(radios))

        // Silenciar é uma exceção temporária aos toggles acima, não outra
        // categoria: fica na mesma coluna, com uma régua a separá-la.
        snoozeCheckbox.setButtonType(.switch)
        snoozeCheckbox.target = self
        snoozeCheckbox.action = #selector(toggleSnooze)
        section(L10n.settingsPause, snoozeCheckbox)
        refreshSnooze()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshSnooze()
    }

    private func refreshSnooze() {
        if preferences.isSnoozed(), let until = preferences.snoozeUntil {
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.dateFormat = L10n.clockFormat
            snoozeCheckbox.title = L10n.snoozedUntil(formatter.string(from: until))
            snoozeCheckbox.state = .on
        } else {
            snoozeCheckbox.title = L10n.snoozeOneHour
            snoozeCheckbox.state = .off
        }
    }

    @objc private func toggleFiveHour(_ sender: NSButton) {
        preferences.fiveHourAlertsEnabled = sender.state == .on
    }

    @objc private func toggleSevenDay(_ sender: NSButton) {
        preferences.sevenDayAlertsEnabled = sender.state == .on
    }

    @objc private func toggleWindowReset(_ sender: NSButton) {
        preferences.windowResetAlertsEnabled = sender.state == .on
    }

    @objc private func selectProfile(_ sender: NSButton) {
        guard let match = profileButtons.first(where: { $0.0 === sender }) else { return }
        preferences.thresholdProfile = match.1
    }

    @objc private func toggleSnooze() {
        preferences.snoozeUntil = preferences.isSnoozed() ? nil : Date().addingTimeInterval(3600)
        refreshSnooze()
    }
}
