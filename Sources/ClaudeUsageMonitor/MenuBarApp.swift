import AppKit
import ServiceManagement
import UserNotifications

final class MenuBarApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let store = StateStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel = MonitorPanelController()

    private let alertPreferences = AlertPreferences()
    private var historyWindow: HistoryWindowController?
    private var aboutWindow: AboutWindowController?
    private var settingsWindow: SettingsWindowController?
    private var timer: Timer?
    private var stateWatcher: DispatchSourceFileSystemObject?
    private var integrationError: String?
    private var integrationStatus: IntegrationStatus = .misconfigured
    private var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    private var settingsFileModified: Date?
    private var hasCheckedIntegration = false
    private var hasAttemptedSilentRepair = false
    private var usageSummary = ""
    private var historyFileModified: Date?
    private var cachedWeekSamples: [HistorySample] = []
    /// Preenchido por `updateTrend`, lido por `updateSessionDetails`, nesta
    /// ordem. Ao contrário, a grade mostra o custo do ciclo anterior.
    private var costPeriodValue = L10n.costPeriodValue("--", "--")
    /// Âncora do range de janela nos gráficos. Vem do último state carregado.
    private var currentFiveHourResetAt: TimeInterval?
    private var accountStatus: ClaudeAccountStatus = .unavailable
    private var accountRefreshStartedAt: Date?
    private var isRefreshingAccount = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        alertPreferences.removeLegacyKeys()
        configureStatusItem()
        configurePanel()
        configureNotifications()
        installStatusLine()
        startWatchingStateDirectory()
        reload()
        refreshClaudeAccount(force: true)

        let history = HistoryStore(paths: store.paths)
        DispatchQueue.global(qos: .utility).async {
            history.prune()
        }

        // O watcher acorda o app quando o ingest grava state.json; o timer só
        // cobre transições dirigidas pelo relógio (countdowns, expiração,
        // dados obsoletos) e serve de fallback se o watcher falhar.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.reload()
        }
        timer?.tolerance = 5
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        stateWatcher?.cancel()
    }

    private func startWatchingStateDirectory() {
        try? store.secureDirectory(store.paths.baseDirectory)
        let descriptor = open(store.paths.baseDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Diretório removido ou renomeado: o descritor aponta para o inode
            // antigo; recomeça a observação a partir do caminho.
            if let watcher = self.stateWatcher,
               !watcher.data.intersection([.delete, .rename]).isEmpty {
                watcher.cancel()
                self.stateWatcher = nil
                self.startWatchingStateDirectory()
            }
            self.reload()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        stateWatcher = source
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.title = " --"
        button.toolTip = "Claude Usage Monitor"
        button.setAccessibilityLabel(L10n.claudeUsage)
        button.target = self
        button.action = #selector(togglePanel)
        applyHealth(.waiting, detail: L10n.starting)
    }

    private func configurePanel() {
        panel.onWillOpen = { [weak self] in
            self?.reload()
            self?.refreshClaudeAccount()
        }
        panel.onRefresh = { [weak self] in self?.reloadAction() }
        panel.onCopy = { [weak self] in self?.copyUsageSummary() }
        panel.onHistory = { [weak self] in self?.showHistory() }
        panel.onSettings = { [weak self] in self?.showSettings() }
        panel.onAbout = { [weak self] in self?.showAbout() }
        panel.onReconfigure = { [weak self] in self?.reconfigure() }
        panel.onDataFolder = { [weak self] in self?.openDataFolder() }
        panel.onQuit = { NSApp.terminate(nil) }
        applyLocalizedTitles()
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button)
    }

    private func applyLocalizedTitles() {
        panel.applyLocalizedTitles()
        statusItem.button?.setAccessibilityLabel(L10n.claudeUsage)
        renderClaudeAccount()
    }

    /// Trocar de idioma reconstrói tudo o que já foi renderizado: as janelas
    /// abertas ficariam no idioma antigo.
    private func languageDidChange() {
        historyWindow?.close()
        historyWindow = nil
        aboutWindow?.close()
        aboutWindow = nil
        applyLocalizedTitles()
        reload()
    }

    @objc private func copyUsageSummary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            usageSummary.isEmpty ? L10n.noUsageDataYetShort : usageSummary,
            forType: .string
        )
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            self?.refreshNotificationStatus()
        }
        refreshNotificationStatus()
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                self.notificationAuthorization = settings.authorizationStatus
                self.updateNotificationsItem()
                self.reload()
            }
        }
    }

    private func updateNotificationsItem() {
        let (symbol, detail): (String, String) = switch notificationAuthorization {
        case .authorized, .provisional, .ephemeral: ("bell.fill", L10n.notificationsActive)
        case .denied: ("bell.slash.fill", L10n.notificationsBlocked)
        case .notDetermined: ("bell", L10n.notificationsPending)
        @unknown default: ("questionmark.circle", L10n.notificationsUnknown)
        }
        panel.notificationsRow.update(symbol: symbol, text: L10n.notifications(detail))
    }

    private func installStatusLine(showError: Bool = false) {
        guard let executable = Bundle.main.executablePath else {
            integrationError = L10n.executableNotFound
            updateIntegrationItem(force: true)
            return
        }
        do {
            try SettingsManager.install(executablePath: executable)
            integrationError = nil
            updateIntegrationItem(force: true)
            if showError, integrationStatus == .disabledByHooks {
                presentHooksDisabledAlert()
            }
        } catch {
            integrationError = error.localizedDescription
            updateIntegrationItem(force: true)
            if showError {
                presentError(error, message: L10n.couldNotConfigure)
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        reload()
        refreshClaudeAccount()
    }

    @discardableResult
    private func reload() -> StateLoadResult {
        updateIntegrationItem()
        refreshHistoryCache()
        let result = store.loadResult()

        switch result {
        case .missing:
            currentFiveHourResetAt = nil
            renderMissingState()
        case .invalid:
            currentFiveHourResetAt = nil
            // Cache ilegível conserta-se sozinho: apaga-se e o próximo payload
            // reconstrói tudo. Só sobra para o utilizador o que ele de facto
            // precisa de resolver: um arquivo que nem apagar deu.
            if store.discardUnreadableState() {
                renderMissingState()
            } else {
                renderInvalidState()
            }
        case let .loaded(state):
            currentFiveHourResetAt = state.fiveHourResetAt
            render(state)
        }
        updateHealth(for: result)
        panel.remedyRow.show(pendingRemedy(for: result))
        historyWindow?.refreshIfVisible(fiveHourResetAt: currentFiveHourResetAt)
        return result
    }

    private func refreshClaudeAccount(force: Bool = false, now: Date = Date()) {
        if !force, let startedAt = accountRefreshStartedAt,
           now.timeIntervalSince(startedAt) < 30 {
            return
        }
        guard !isRefreshingAccount else { return }
        isRefreshingAccount = true
        accountRefreshStartedAt = now

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = ClaudeAccountReader.load()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefreshingAccount = false
                if status != .unavailable || self.accountStatus == .unavailable {
                    self.accountStatus = status
                }
                self.renderClaudeAccount()
            }
        }
    }

    private func renderClaudeAccount() {
        switch accountStatus {
        case let .loggedIn(account):
            if let email = account.email {
                panel.header.setAccountTitle(email, fullTitle: L10n.claudeAccount(email))
            } else if account.authMethod?.lowercased().contains("api") == true {
                panel.header.setAccountTitle(L10n.claudeViaAPIKey)
            } else {
                panel.header.setAccountTitle(L10n.claudeConnected)
            }
        case .loggedOut:
            panel.header.setAccountTitle(L10n.claudeSignedOut)
        case .unavailable:
            panel.header.setAccountTitle("Claude Usage Monitor")
        }
    }

    /// Relê o history.jsonl apenas quando o mtime muda (o arquivo cresce a
    /// cada ingest, não a cada reload).
    private func refreshHistoryCache(now: Date = Date()) {
        let modified = (try? FileManager.default.attributesOfItem(
            atPath: store.paths.historyFile.path
        ))?[.modificationDate] as? Date
        guard modified != historyFileModified else { return }
        historyFileModified = modified
        cachedWeekSamples = HistoryStore(paths: store.paths)
            .load(range: 7 * 24 * 3_600, now: now)
    }

    private func updateTrend(_ state: UsageState?, now: Date) {
        let dayCutoff = now.timeIntervalSince1970 - 24 * 3_600
        let daySamples = cachedWeekSamples.filter { $0.t >= dayCutoff }

        var projection: Date?
        if let state, let usage = state.fiveHourUsage,
           !UsageFormatter.isExpired(state.fiveHourResetAt, relativeTo: now),
           let age = UsageFormatter.dataAge(state.usageUpdatedAt, relativeTo: now),
           age <= AlertPolicy.staleAfter {
            projection = PaceEstimator.projectedLimitDate(
                samples: daySamples,
                currentUsage: usage,
                resetAt: state.fiveHourResetAt,
                now: now
            )
        }

        // O sparkline acompanha o medidor de 5 h logo acima dele: mostra a
        // janela corrente, não as últimas 24 h. Em 24 h cruzavam-se ~5 resets e
        // o traçado virava um serrote que nada dizia da janela em curso.
        let span = ChartSpan.resolve(
            range: .window,
            resetAt: state?.fiveHourResetAt,
            now: now
        )
        let windowSamples = daySamples.filter { $0.t >= span.start && $0.t <= span.end }
        // O sparkline cobre só o que já passou da janela, não a janela inteira:
        // aos 30 min de 5 h, a curva ficaria espremida em 10% da largura. O
        // quanto falta até o reset já está escrito no medidor acima.
        let elapsed = ChartSpan(
            start: span.start,
            end: min(now.timeIntervalSince1970, span.end)
        )
        panel.trend.update(
            samples: HistoryStore.downsample(windowSamples, limit: 80),
            projectedLimit: projection,
            ratePerHour: PaceEstimator.slopePerHour(samples: daySamples, now: now),
            span: elapsed,
            now: now
        )

        let dayCost = CostAggregator.accumulatedCost(daySamples)
        let weekCost = CostAggregator.accumulatedCost(cachedWeekSamples)
        costPeriodValue = L10n.costPeriodValue(
            dayCost.map(currency) ?? "--",
            weekCost.map(currency) ?? "--"
        )
    }

    @objc private func showHistory() {
        if historyWindow == nil {
            historyWindow = HistoryWindowController(store: HistoryStore(paths: store.paths))
        }
        historyWindow?.present(fiveHourResetAt: currentFiveHourResetAt)
    }

    /// Com chave de API (ou Bedrock/Vertex/Foundry) o Claude Code nunca envia
    /// rate_limits: não existem janelas, cobra-se por token. "Aguardando
    /// dados" seria uma espera infinita.
    private var usesAPIKeyBilling: Bool {
        guard case let .loggedIn(account) = accountStatus else { return false }
        return account.authMethod?.lowercased().contains("api") == true
    }

    private func renderMissingState() {
        statusItem.button?.title = " --"
        if usesAPIKeyBilling {
            renderAPIKeyState()
            usageSummary = ""
            updateTrend(nil, now: Date())
            updateSessionDetails(nil)
            return
        }
        panel.fiveHour.update(
            percentage: nil,
            value: "--",
            detail: L10n.sendAMessage,
            isAvailable: false
        )
        panel.sevenDay.update(
            percentage: nil,
            value: "--",
            detail: L10n.waitingFirstRateLimits,
            isAvailable: false
        )
        panel.context.update(
            percentage: nil,
            value: "--",
            detail: L10n.waitingSessionData,
            isAvailable: false
        )
        panel.updatedRow.update(symbol: "clock", text: L10n.usageUpdated(L10n.awaitingData))
        panel.sevenDay.setValueTooltip(L10n.sevenDayTooltip)
        usageSummary = ""
        updateTrend(nil, now: Date())
        updateSessionDetails(nil)
    }

    private func renderInvalidState() {
        statusItem.button?.title = " !"
        panel.fiveHour.update(
            percentage: nil,
            value: L10n.errorValue,
            detail: L10n.invalidLocalCache,
            isAvailable: false
        )
        panel.sevenDay.update(
            percentage: nil,
            value: L10n.errorValue,
            detail: L10n.reconfigureOrRemoveState,
            isAvailable: false
        )
        panel.context.update(
            percentage: nil,
            value: "--",
            detail: L10n.sessionDataUnavailable,
            isAvailable: false
        )
        panel.updatedRow.update(
            symbol: "exclamationmark.triangle.fill",
            text: L10n.usageUpdated(L10n.invalidCacheShort),
            tint: .systemRed
        )
        usageSummary = ""
        updateTrend(nil, now: Date())
        updateSessionDetails(nil)
    }

    private func render(_ state: UsageState, now: Date = Date()) {
        renderFiveHour(state, now: now)
        renderSevenDay(state, now: now)
        renderContext(state.session)
        updateTrend(state, now: now)
        updateSessionDetails(state.session)
        usageSummary = UsageFormatter.summary(state, relativeTo: now)

        let updated = UsageFormatter.updatedDescription(state.usageUpdatedAt, relativeTo: now)
        if hasRecentIngestFailure(state) {
            panel.updatedRow.update(
                symbol: "exclamationmark.triangle",
                text: L10n.usageUpdated("\(updated) • \(L10n.lastIngestFailed)"),
                tint: .systemOrange
            )
        } else {
            panel.updatedRow.update(
                symbol: "clock.arrow.circlepath",
                text: L10n.usageUpdated(updated)
            )
        }

        deliverAlerts(for: state, now: now)
    }

    private func hasRecentIngestFailure(_ state: UsageState) -> Bool {
        guard let failedAt = UsageFormatter.isoDate(state.lastIngestErrorAt) else { return false }
        let succeededAt = UsageFormatter.isoDate(state.usageUpdatedAt) ?? .distantPast
        return failedAt > succeededAt
    }

    private func renderFiveHour(_ state: UsageState, now: Date) {
        guard let usage = state.fiveHourUsage else {
            statusItem.button?.title = " --"
            panel.fiveHour.update(
                percentage: nil,
                value: "--",
                detail: L10n.unavailableInPayload,
                isAvailable: false
            )
            return
        }

        if UsageFormatter.isExpired(state.fiveHourResetAt, relativeTo: now) {
            statusItem.button?.title = " --"
            panel.fiveHour.update(
                percentage: nil,
                value: L10n.windowClosed,
                detail: resetLabel(state.fiveHourResetAt, now: now),
                isAvailable: false
            )
        } else {
            let formatted = UsageFormatter.percentage(usage)
            // A barra de menus mostra este número. Se a janela não veio no
            // payload mais recente, o "~" avisa que é o último conhecido em vez
            // de deixar um número velho passar por atual.
            if let stale = staleLabel(state.fiveHourUpdatedAt, now: now) {
                statusItem.button?.title = " ~\(formatted)%"
                panel.fiveHour.update(
                    percentage: usage,
                    value: "\(formatted)%",
                    detail: stale,
                    isAvailable: false
                )
                return
            }

            statusItem.button?.title = " \(formatted)%"
            var detail = L10n.resets(resetLabel(state.fiveHourResetAt, now: now))
            if let age = UsageFormatter.dataAge(state.fiveHourUpdatedAt, relativeTo: now),
               age > AlertPolicy.staleAfter {
                detail += " • \(L10n.dataAgeSuffix(UsageFormatter.elapsedTime(age)))"
            }
            panel.fiveHour.update(
                percentage: usage,
                value: "\(formatted)%",
                detail: detail
            )
        }
    }

    /// Os dois medidores que o payload pode não trazer explicam-se sozinhos.
    private func renderAPIKeyState() {
        panel.fiveHour.update(
            percentage: nil,
            value: "--",
            detail: L10n.apiKeyNoLimits,
            isAvailable: false
        )
        panel.sevenDay.update(
            percentage: nil,
            value: "--",
            detail: L10n.apiKeyNoLimitsDetail,
            isAvailable: false
        )
        panel.updatedRow.update(symbol: "key", text: L10n.apiKeyNoLimits)
    }

    /// Uma janela que não veio no payload mais recente carrega um valor do
    /// passado. Mostra-se o último conhecido, rotulado, em vez de o apresentar
    /// como atual: o limite semanal muda devagar e descartá-lo perderia
    /// informação ainda útil, mas fingir que é de agora seria mentira.
    private func staleLabel(_ updatedAt: String?, now: Date) -> String? {
        guard let age = UsageFormatter.dataAge(updatedAt, relativeTo: now),
              age > AlertPolicy.staleAfter else { return nil }
        return L10n.staleWindow(UsageFormatter.elapsedTime(age))
    }

    private func renderSevenDay(_ state: UsageState, now: Date) {
        panel.sevenDay.setValueTooltip(L10n.sevenDayTooltip)
        if let stale = staleLabel(state.sevenDayUpdatedAt, now: now),
           let usage = state.sevenDayUsage {
            panel.sevenDay.update(
                percentage: usage,
                value: "\(UsageFormatter.percentage(usage))%",
                detail: stale,
                isAvailable: false
            )
            return
        }
        guard let usage = state.sevenDayUsage else {
            panel.sevenDay.update(
                percentage: nil,
                value: "--",
                detail: L10n.maybeUnavailableForAccount,
                isAvailable: false
            )
            return
        }

        if UsageFormatter.isExpired(state.sevenDayResetAt, relativeTo: now) {
            panel.sevenDay.update(
                percentage: nil,
                value: L10n.windowClosed,
                detail: resetLabel(state.sevenDayResetAt, now: now),
                isAvailable: false
            )
        } else {
            let formatted = UsageFormatter.percentage(usage)
            panel.sevenDay.update(
                percentage: usage,
                value: "\(formatted)%",
                detail: L10n.resets(resetLabel(state.sevenDayResetAt, now: now))
            )
        }
    }

    private func renderContext(_ session: SessionSnapshot?) {
        guard let session, let usage = session.contextUsedPercentage else {
            panel.context.update(
                percentage: nil,
                value: "--",
                detail: L10n.availableAfterResponse,
                isAvailable: false
            )
            return
        }

        let formatted = UsageFormatter.percentage(usage)
        var details: [String] = []
        if let input = session.contextInputTokens, let output = session.contextOutputTokens {
            details.append(L10n.tokens(UsageFormatter.tokenCount(input + output)))
        }
        if let size = session.contextWindowSize {
            details.append(L10n.windowOf(UsageFormatter.tokenCount(size)))
        }
        if let remaining = session.contextRemainingPercentage {
            details.append(L10n.percentFree(UsageFormatter.percentage(remaining)))
        }

        panel.context.update(
            percentage: usage,
            value: "\(formatted)%",
            detail: details.isEmpty ? L10n.contextUsedInSession : details.joined(separator: " • ")
        )
    }

    /// Ordem idêntica a `SessionDetailsView.labels`. O truncamento é da grade
    /// agora; aqui só se produz texto.
    private func updateSessionDetails(_ session: SessionSnapshot?) {
        var effort = session?.effortLevel.map(L10n.effortLevel) ?? L10n.unavailable
        if let thinking = session?.thinkingEnabled {
            effort += " • \(thinking ? L10n.thinkingOn : L10n.thinkingOff)"
        }

        panel.sessionDetails.update([
            session?.modelDisplayName ?? L10n.unavailable,
            session?.projectName ?? L10n.unavailable,
            session?.sessionName ?? L10n.unnamed,
            effort,
            session?.totalDurationMS.map { UsageFormatter.duration(milliseconds: $0) }
                ?? L10n.unavailable,
            session?.estimatedCostUSD.map(currency) ?? L10n.unavailable,
            costPeriodValue,
            session?.claudeCodeVersion ?? L10n.unavailable,
        ])
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = L10n.locale
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "US$ %.2f", value)
    }

    private func resetLabel(_ epoch: TimeInterval?, now: Date) -> String {
        UsageFormatter.resetDescription(epoch, relativeTo: now) ?? L10n.unknownResetTime
    }

    private func updateHealth(for result: StateLoadResult, now: Date = Date()) {
        if integrationError != nil || integrationStatus == .misconfigured {
            applyHealth(.error, detail: L10n.integrationNeedsRepairDetail)
            return
        }
        if integrationStatus == .disabledByHooks {
            applyHealth(.error, detail: L10n.statusLineDisabledByHooks)
            return
        }

        switch result {
        case .invalid:
            applyHealth(.error, detail: L10n.invalidLocalCache)
        case .missing:
            applyHealth(.waiting, detail: L10n.sendAMessage)
        case let .loaded(state):
            let recency = UsageDataRecency.evaluate(
                state,
                relativeTo: now,
                staleAfter: AlertPolicy.staleAfter
            )
            if state.fiveHourUsage == nil {
                applyHealth(.waiting, detail: L10n.waitingFiveHourLimit)
            } else if UsageFormatter.isExpired(state.fiveHourResetAt, relativeTo: now) {
                applyHealth(.warning, detail: L10n.windowClosedWaiting)
            } else if case .recentSessionWithoutLimits = recency {
                applyHealth(.waiting, detail: L10n.recentSessionWithoutLimits)
            } else if case let .stale(age) = recency {
                applyHealth(.warning, detail: L10n.noRecentData(UsageFormatter.elapsedTime(age)))
            } else if notificationAuthorization == .denied {
                applyHealth(.warning, detail: L10n.usageActiveNotificationsOff)
            } else {
                applyHealth(.healthy, detail: L10n.healthyDetail)
            }
        }
    }

    /// A verificação que sobra para o utilizador, ou `nil` quando não sobra
    /// nada. Tudo o que o app conserta sozinho (cache ilegível, status line que
    /// saiu do lugar) já foi tratado antes de chegar aqui e não aparece.
    ///
    /// A ordem é a da causa: sem sessão do Claude Code nada mais importa, e uma
    /// integração parada explica a falta de dados melhor do que a falta de
    /// dados em si.
    private func pendingRemedy(for result: StateLoadResult) -> String? {
        if case .loggedOut = accountStatus {
            return L10n.claudeSignedOutFix
        }
        if integrationError != nil {
            return L10n.executableNotFoundFix
        }
        switch integrationStatus {
        case .disabledByHooks:
            return L10n.statusLineDisabledBody
        case .misconfigured:
            return L10n.integrationNeedsRepairFix
        case .active:
            break
        }
        if case .invalid = result {
            return L10n.reconfigureOrRemoveState
        }
        // Sem limites e sem janelas por cobrança a token não é erro: é o plano.
        if case .missing = result, !usesAPIKeyBilling {
            return L10n.sendAMessage
        }
        return nil
    }

    private func applyHealth(_ health: MonitorHealth, detail: String) {
        panel.header.setHealth(health, detail: detail)
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: health.symbolName,
            accessibilityDescription: health.title
        )
        image?.isTemplate = true
        button.image = image
        var toolTip = "Claude Usage Monitor: \(detail)"
        if !usageSummary.isEmpty {
            toolTip += "\n\(usageSummary)"
        }
        button.toolTip = toolTip
        button.setAccessibilityLabel("Claude Usage Monitor, \(health.title), \(button.title)")
    }

    private enum AlertWindow {
        case fiveHour
        case sevenDay

        var label: String {
            switch self {
            case .fiveHour: L10n.fiveHourWindowLabel
            case .sevenDay: L10n.sevenDayWindowLabel
            }
        }

        var identifierPrefix: String {
            switch self {
            case .fiveHour: "threshold-5h"
            case .sevenDay: "threshold-7d"
            }
        }
    }

    private func deliverAlerts(for state: UsageState, now: Date) {
        // Snooze segura tudo sem marcar como entregue: ao expirar, alertas
        // ainda frescos são disparados e os antigos caem na regra de idade.
        guard !alertPreferences.isSnoozed(now: now) else { return }

        let age = UsageFormatter.dataAge(state.usageUpdatedAt, relativeTo: now)
        let dataIsFresh = age.map { $0 <= AlertPolicy.maxAlertAge } ?? false

        let profile = alertPreferences.thresholdProfile

        if state.fiveHourUsage != nil,
           !UsageFormatter.isExpired(state.fiveHourResetAt, relativeTo: now) {
            let outcome = ThresholdDelivery.evaluate(
                notified: state.notifiedThresholds,
                resetId: state.fiveHourResetAt.map { String($0) } ?? "unknown",
                previous: alertPreferences.fiveHourDelivery,
                dataIsFresh: dataIsFresh && alertPreferences.fiveHourAlertsEnabled,
                enabled: profile.fiveHour
            )
            alertPreferences.fiveHourDelivery = outcome.record
            if let threshold = outcome.announce {
                deliverThresholdNotification(
                    window: .fiveHour,
                    threshold: threshold,
                    resetAt: state.fiveHourResetAt,
                    resetId: outcome.record.resetId
                )
            }
        }

        if state.sevenDayUsage != nil,
           !UsageFormatter.isExpired(state.sevenDayResetAt, relativeTo: now) {
            let outcome = ThresholdDelivery.evaluate(
                notified: state.sevenDayNotifiedThresholds,
                resetId: state.sevenDayResetAt.map { String($0) } ?? "unknown",
                previous: alertPreferences.sevenDayDelivery,
                dataIsFresh: dataIsFresh && alertPreferences.sevenDayAlertsEnabled,
                enabled: profile.sevenDay
            )
            alertPreferences.sevenDayDelivery = outcome.record
            if let threshold = outcome.announce {
                deliverThresholdNotification(
                    window: .sevenDay,
                    threshold: threshold,
                    resetAt: state.sevenDayResetAt,
                    resetId: outcome.record.resetId
                )
            }
        }

        deliverWindowResetAlert(for: state, now: now)
    }

    private func deliverThresholdNotification(
        window: AlertWindow,
        threshold: Int,
        resetAt: TimeInterval?,
        resetId: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = threshold >= 90 ? L10n.claudeLimitAlmostGoneTitle : L10n.claudeLimitTitle
        let reset = UsageFormatter.reset(resetAt).map { L10n.resetsAtSuffix($0) } ?? ""
        content.body = L10n.reachedThreshold(threshold, window: window.label) + reset
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(window.identifierPrefix)-\(resetId)-\(threshold)",
            content: content,
            trigger: nil
        ))
    }

    private func deliverWindowResetAlert(for state: UsageState, now: Date) {
        guard alertPreferences.windowResetAlertsEnabled else { return }
        guard let identifier = WindowResetAnnouncement.evaluate(
            resetAt: state.fiveHourResetAt,
            maxNotifiedThreshold: state.notifiedThresholds.max(),
            alreadyAnnounced: alertPreferences.announcedWindowReset,
            now: now
        ) else { return }

        alertPreferences.announcedWindowReset = identifier
        let content = UNMutableNotificationContent()
        content.title = L10n.windowResetTitle
        content.body = L10n.windowResetBody
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "window-reset-\(identifier)",
            content: content,
            trigger: nil
        ))
    }

    /// Uma tentativa por sessão, para não entrar em ciclo com um settings.json
    /// que rejeite a escrita. Devolve `true` quando a integração voltou a ficar
    /// ativa e não há nada a dizer ao utilizador.
    private func repairIntegrationSilently() -> Bool {
        guard !hasAttemptedSilentRepair, let executable = Bundle.main.executablePath else {
            return false
        }
        hasAttemptedSilentRepair = true
        guard (try? SettingsManager.install(executablePath: executable)) != nil,
              let status = try? SettingsManager.integrationStatus(executablePath: executable),
              status == .active else {
            return false
        }
        integrationStatus = .active
        settingsFileModified = (try? FileManager.default.attributesOfItem(
            atPath: store.paths.claudeSettingsFile.path
        ))?[.modificationDate] as? Date
        renderIntegration(
            symbol: "checkmark.circle.fill",
            detail: L10n.integrationActive,
            tint: .systemGreen
        )
        return true
    }

    private func renderIntegration(symbol: String, detail: String, tint: NSColor) {
        panel.integrationRow.update(
            symbol: symbol,
            text: L10n.integration(detail),
            tint: tint
        )
    }

    private func updateIntegrationItem(force: Bool = false) {
        if let integrationError {
            integrationStatus = .misconfigured
            renderIntegration(
                symbol: "xmark.octagon.fill",
                detail: L10n.integrationError(integrationError),
                tint: .systemRed
            )
            return
        }
        guard let executable = Bundle.main.executablePath else {
            integrationStatus = .misconfigured
            renderIntegration(
                symbol: "xmark.octagon.fill",
                detail: L10n.executableNotFound,
                tint: .systemRed
            )
            return
        }

        // Reler ~/.claude/settings.json apenas quando ele mudar de fato.
        let modified = (try? FileManager.default.attributesOfItem(
            atPath: store.paths.claudeSettingsFile.path
        ))?[.modificationDate] as? Date
        if !force, hasCheckedIntegration, modified == settingsFileModified {
            return
        }
        hasCheckedIntegration = true
        settingsFileModified = modified

        do {
            integrationStatus = try SettingsManager.integrationStatus(executablePath: executable)
            switch integrationStatus {
            case .active:
                renderIntegration(
                    symbol: "checkmark.circle.fill",
                    detail: L10n.integrationActive,
                    tint: .systemGreen
                )
            case .disabledByHooks:
                renderIntegration(
                    symbol: "exclamationmark.triangle.fill",
                    detail: L10n.integrationBlockedByHooks,
                    tint: .systemOrange
                )
            case .misconfigured:
                // A status line deixou de apontar para o app (uma reinstalação
                // do Claude Code, outra ferramenta a escrever settings.json).
                // Regravá-la é o que o app já faz a cada arranque, então
                // fazê-lo aqui não é uma decisão nova: tenta-se uma vez em
                // silêncio e só se avisa se falhar mesmo.
                if !force, repairIntegrationSilently() { return }
                renderIntegration(
                    symbol: "xmark.circle.fill",
                    detail: L10n.integrationNeedsRepair,
                    tint: .systemRed
                )
            }
        } catch {
            integrationStatus = .misconfigured
            renderIntegration(
                symbol: "xmark.octagon.fill",
                detail: L10n.integrationError(error.localizedDescription),
                tint: .systemRed
            )
        }
    }

    @objc private func reloadAction() {
        refreshClaudeAccount(force: true)
        notifyRefreshResult(reload())
    }

    private func notifyRefreshResult(_ result: StateLoadResult) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch result {
        case .missing:
            content.title = L10n.noUsageDataYetTitle
            content.body = L10n.noUsageDataYetBody
        case .invalid:
            content.title = L10n.couldNotRefreshTitle
            content.body = L10n.couldNotRefreshBody
        case let .loaded(state):
            content.title = L10n.refreshDoneTitle
            content.body = UsageFormatter.summary(state)
        }

        deliverManualNotification(content)
    }

    private func deliverManualNotification(_ content: UNMutableNotificationContent) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let request = UNNotificationRequest(
                    identifier: "manual-refresh-\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
                center.add(request) { error in
                    guard let error else { return }
                    DispatchQueue.main.async {
                        self?.presentError(error, message: L10n.couldNotSendNotification)
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    self?.presentNotificationPermissionAlert()
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    DispatchQueue.main.async {
                        if let error {
                            self?.presentError(error, message: L10n.couldNotRequestNotifications)
                        } else if granted {
                            self?.reloadAction()
                        } else {
                            self?.presentNotificationPermissionAlert()
                        }
                    }
                }
            @unknown default:
                break
            }
            self?.refreshNotificationStatus()
        }
    }

    private func presentNotificationPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.notificationsDisabledTitle
        alert.informativeText = L10n.notificationsDisabledBody
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.openSettings)
        alert.addButton(withTitle: L10n.notNow)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentHooksDisabledAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.statusLineDisabledTitle
        alert.informativeText = L10n.statusLineDisabledBody
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func reconfigure() {
        installStatusLine(showError: true)
        reload()
    }

    @objc private func openDataFolder() {
        do {
            try store.secureDirectory(store.paths.baseDirectory)
            guard NSWorkspace.shared.open(store.paths.baseDirectory) else {
                throw NSError(
                    domain: "ClaudeUsageMonitor",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: L10n.finderDidNotOpen]
                )
            }
        } catch {
            presentError(error, message: L10n.couldNotOpenDataFolder)
        }
    }

    @objc private func showAbout() {
        let controller = aboutWindow ?? AboutWindowController()
        aboutWindow = controller
        controller.present()
    }

    @objc private func showSettings() {
        let controller = settingsWindow ?? SettingsWindowController(
            alertPreferences: alertPreferences,
            onReconfigure: { [weak self] in self?.reconfigure() },
            onDataFolder: { [weak self] in self?.openDataFolder() },
            onLanguageChange: { [weak self] in
                // A própria janela de ajustes está em causa: fecha-se e o
                // utilizador reabre-a já no idioma novo.
                self?.settingsWindow?.close()
                self?.settingsWindow = nil
                self?.languageDidChange()
            }
        )
        settingsWindow = controller
        controller.present()
    }

    private func presentError(_ error: Error, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.runModal()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
