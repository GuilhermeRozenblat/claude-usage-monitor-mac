import Foundation

enum AppLanguage: String, CaseIterable {
    case en
    case ptBR
    case es
}

enum LanguagePreference: String, CaseIterable {
    case automatic
    case en
    case ptBR
    case es

    func resolved(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch self {
        case .automatic: L10n.detect(preferred: preferred)
        case .en: .en
        case .ptBR: .ptBR
        case .es: .es
        }
    }
}

struct LanguageSettings {
    static let key = "app.language.preference"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var preference: LanguagePreference {
        defaults.string(forKey: Self.key)
            .flatMap(LanguagePreference.init(rawValue:)) ?? .automatic
    }

    func set(_ preference: LanguagePreference) {
        defaults.set(preference.rawValue, forKey: Self.key)
    }
}

/// Localização sem arquivos de recursos: funciona igual no app empacotado e
/// nos modos de CLI (--ingest-statusline roda sem bundle). O modo automático
/// segue os idiomas preferidos do macOS; inglês é sempre o fallback.
enum L10n {
    private static let languageSettings = LanguageSettings()
    static var language = languageSettings.preference.resolved()

    static var preference: LanguagePreference { languageSettings.preference }

    static func setPreference(_ preference: LanguagePreference) {
        languageSettings.set(preference)
        language = preference.resolved()
    }

    static func detect(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        for identifier in preferred {
            let lowered = identifier.lowercased()
            if lowered.hasPrefix("pt") { return .ptBR }
            if lowered.hasPrefix("es") { return .es }
            if lowered.hasPrefix("en") { return .en }
        }
        return .en
    }

    static var locale: Locale {
        switch language {
        case .en: Locale(identifier: "en_US")
        case .ptBR: Locale(identifier: "pt_BR")
        case .es: Locale(identifier: "es_ES")
        }
    }

    private static func pick(_ en: String, _ pt: String, _ es: String) -> String {
        switch language {
        case .en: en
        case .ptBR: pt
        case .es: es
        }
    }

    // MARK: Painel: medidores e itens fixos

    static var fiveHourMeterTitle: String { pick("5-hour limit", "Limite de 5 horas", "Límite de 5 horas") }
    static var sevenDayMeterTitle: String { pick("7-day limit", "Limite de 7 dias", "Límite de 7 días") }
    static var contextMeterTitle: String { pick("Session context", "Contexto da sessão", "Contexto de la sesión") }
    static var waitingForData: String { pick("Waiting for data", "Aguardando dados", "Esperando datos") }
    static var starting: String { pick("Starting", "Iniciando", "Iniciando") }
    static var claudeUsage: String { pick("Claude usage", "Uso do Claude", "Uso de Claude") }
    static func claudeAccount(_ email: String) -> String {
        pick("Claude account: \(email)", "Conta do Claude: \(email)", "Cuenta de Claude: \(email)")
    }
    static var claudeConnected: String {
        pick("Claude account connected", "Conta do Claude conectada", "Cuenta de Claude conectada")
    }
    static var claudeViaAPIKey: String {
        pick("Claude via API key", "Claude via chave de API", "Claude mediante clave de API")
    }
    static var claudeSignedOut: String {
        pick("Claude Code signed out", "Claude Code desconectado", "Claude Code sin sesión")
    }
    static var sessionDetails: String { pick("Session details", "Detalhes da sessão", "Detalles de la sesión") }
    static var openAtLogin: String { pick("Open at login", "Abrir ao iniciar sessão", "Abrir al iniciar sesión") }
    static var refreshDisplay: String { pick("Refresh display", "Atualizar exibição", "Actualizar visualización") }
    static var copyUsageSummary: String { pick("Copy usage summary", "Copiar resumo de uso", "Copiar resumen de uso") }
    static var usageHistory: String { pick("Usage history…", "Histórico de uso…", "Historial de uso…") }
    static var reconfigureClaudeCode: String { pick("Reconfigure Claude Code", "Reconfigurar Claude Code", "Reconfigurar Claude Code") }
    static var openDataFolder: String { pick("Open data folder", "Abrir pasta de dados", "Abrir carpeta de datos") }
    static var languageMenuTitle: String { pick("Language", "Idioma", "Idioma") }
    static var automaticLanguage: String { pick("Automatic (System)", "Automático (Sistema)", "Automático (Sistema)") }
    static var about: String { pick("About", "Sobre", "Acerca de") }
    static var quit: String { pick("Quit", "Encerrar", "Salir") }
    static var settings: String { pick("Settings", "Ajustes", "Ajustes") }
    static var moreOptions: String { pick("More options", "Mais opções", "Más opciones") }
    static var claudeCodeVersionLabel: String { "Claude Code" }

    // MARK: Ajustes

    static var settingsGeneral: String { pick("General", "Geral", "General") }
    static var settingsAlerts: String { pick("Alerts", "Alertas", "Alertas") }
    static var settingsLanguage: String { pick("Language", "Idioma", "Idioma") }
    static var settingsStartup: String { pick("Startup", "Inicialização", "Inicio") }
    static var settingsIntegration: String { pick("Integration", "Integração", "Integración") }
    static var settingsData: String { pick("Data", "Dados", "Datos") }
    static var settingsNotifications: String { pick("Notify me about", "Avisar sobre", "Avisarme sobre") }
    static var settingsPause: String { pick("Pause", "Pausa", "Pausa") }
    static var settingsLanguageFooter: String {
        pick(
            "Reopens the monitor's windows.",
            "Reabre as janelas do monitor.",
            "Reabre las ventanas del monitor."
        )
    }
    static var settingsIntegrationFooter: String {
        pick(
            "Claude Usage Monitor reads usage from Claude Code's status line. Reconfigure if the integration stops reporting.",
            "O Claude Usage Monitor lê o uso pela status line do Claude Code. Reconfigure se a integração parar de reportar.",
            "Claude Usage Monitor lee el uso desde la línea de estado de Claude Code. Reconfigura si la integración deja de informar."
        )
    }
    static var settingsDataFooter: String {
        pick(
            "Usage history stays on this Mac. Nothing is uploaded.",
            "O histórico de uso fica neste Mac. Nada é enviado para fora.",
            "El historial de uso permanece en este Mac. No se envía nada."
        )
    }

    // MARK: Sobre o app

    static var aboutTagline: String {
        pick(
            "Claude Code usage, in your menu bar.",
            "O uso do Claude Code na sua barra de menus.",
            "El uso de Claude Code en tu barra de menús."
        )
    }
    static var madeInBrazil: String { pick("Made in Brazil", "Feito no Brasil", "Hecho en Brasil") }
    static var developedBy: String { pick("Developed by", "Desenvolvido por", "Desarrollado por") }
    static var aboutVersion: String { pick("Version", "Versão", "Versión") }
    static var aboutContinue: String { pick("Close", "Fechar", "Cerrar") }

    // MARK: Alertas

    static var alerts: String { pick("Alerts", "Alertas", "Alertas") }
    static var fiveHourAlerts: String { pick("5-hour limit alerts", "Alertas do limite de 5 horas", "Alertas del límite de 5 horas") }
    static var sevenDayAlerts: String { pick("7-day limit alerts", "Alertas do limite de 7 dias", "Alertas del límite de 7 días") }
    static var windowResetAlerts: String {
        pick("Notify when the window resets", "Avisar quando a janela reiniciar", "Avisar cuando se reinicie la ventana")
    }
    static var snoozeOneHour: String { pick("Snooze alerts for 1 hour", "Silenciar alertas por 1 hora", "Silenciar alertas durante 1 hora") }
    /// É o título de um switch: o próprio controlo já diz que se pode desligar,
    /// então o "clique para reativar" era ruído.
    static func snoozedUntil(_ time: String) -> String {
        pick(
            "Snoozed until \(time)",
            "Silenciado até \(time)",
            "Silenciado hasta las \(time)"
        )
    }

    // MARK: Detalhes da sessão

    static var model: String { pick("Model", "Modelo", "Modelo") }
    static var project: String { pick("Project", "Projeto", "Proyecto") }
    static var session: String { pick("Session", "Sessão", "Sesión") }
    static var effort: String { pick("Effort", "Esforço", "Esfuerzo") }
    static var duration: String { pick("Duration", "Duração", "Duración") }
    /// "Custo API estimado" e "Custo API (est.)" ficavam em linhas vizinhas da
    /// grade e liam-se como a mesma coisa. Um é a sessão, o outro é o
    /// acumulado do período: os rótulos têm de dizer isso.
    static var sessionCostLabel: String {
        pick("Session cost (est.)", "Custo da sessão (est.)", "Coste de la sesión (est.)")
    }
    static var accumulatedCostLabel: String {
        pick("Accumulated (est.)", "Acumulado (est.)", "Acumulado (est.)")
    }
    static var unavailable: String { pick("unavailable", "indisponível", "no disponible") }
    static var unnamed: String { pick("unnamed", "sem nome", "sin nombre") }
    static var thinkingOn: String { pick("thinking on", "thinking ativo", "thinking activo") }
    static var thinkingOff: String { pick("thinking off", "thinking inativo", "thinking inactivo") }
    static var costTooltip: String {
        pick(
            "Local session estimate; does not reflect Pro or Max plan billing.",
            "Estimativa local da sessão; não representa cobrança de planos Pro ou Max.",
            "Estimación local de la sesión; no representa la facturación de los planes Pro o Max."
        )
    }

    static func effortLevel(_ value: String) -> String {
        guard language != .en else { return value }
        return switch value.lowercased() {
        case "low": language == .ptBR ? "baixo" : "bajo"
        case "medium": language == .ptBR ? "médio" : "medio"
        case "high": language == .ptBR ? "alto" : "alto"
        case "xhigh": language == .ptBR ? "muito alto" : "muy alto"
        case "max": language == .ptBR ? "máximo" : "máximo"
        default: value
        }
    }

    // MARK: Status

    static func usageUpdated(_ detail: String) -> String {
        pick("Limits updated: \(detail)", "Limites atualizados: \(detail)", "Límites actualizados: \(detail)")
    }
    static var awaitingData: String { pick("waiting for data", "aguardando dados", "esperando datos") }
    static var invalidCacheShort: String { pick("invalid cache", "cache inválido", "caché no válida") }
    static var lastIngestFailed: String { pick("last read failed", "última leitura falhou", "falló la última lectura") }
    static func integration(_ detail: String) -> String {
        pick("Integration: \(detail)", "Integração: \(detail)", "Integración: \(detail)")
    }
    static var integrationChecking: String { pick("checking", "verificando", "comprobando") }
    static var integrationActive: String { pick("active", "ativa", "activa") }
    static var integrationBlockedByHooks: String {
        pick("blocked by disableAllHooks", "bloqueada por disableAllHooks", "bloqueada por disableAllHooks")
    }
    static var integrationNeedsRepair: String { pick("needs repair", "requer reparo", "necesita reparación") }
    static func integrationError(_ message: String) -> String {
        pick("error - \(message)", "erro - \(message)", "error - \(message)")
    }
    /// Único caso em que reiniciar o app resolve de facto: a status line guarda
    /// o caminho do executável, e um app movido depois de instalado deixa o
    /// Claude Code a apontar para o lugar antigo. Reabrir a partir da pasta
    /// nova regrava o caminho no arranque.
    static var executableNotFound: String {
        pick("app moved after install", "app movido depois da instalação", "app movido tras la instalación")
    }
    static var executableNotFoundFix: String {
        pick(
            "Reopen the app from its current folder to reconnect it.",
            "Reabra o app a partir da pasta atual para reconectá-lo.",
            "Vuelve a abrir la app desde su carpeta actual para reconectarla."
        )
    }
    static var integrationNeedsRepairFix: String {
        pick(
            "Open Settings > General and choose Reconfigure Claude Code.",
            "Abra Ajustes > Geral e escolha Reconfigurar Claude Code.",
            "Abre Ajustes > General y elige Reconfigurar Claude Code."
        )
    }
    static var claudeSignedOutFix: String {
        pick(
            "Run `claude login` in the terminal.",
            "Execute `claude login` no terminal.",
            "Ejecuta `claude login` en la terminal."
        )
    }
    static func notifications(_ detail: String) -> String {
        pick("Notifications: \(detail)", "Notificações: \(detail)", "Notificaciones: \(detail)")
    }
    static var notificationsActive: String { pick("enabled", "ativas", "activadas") }
    static var notificationsBlocked: String {
        pick("blocked in System Settings", "bloqueadas nos Ajustes", "bloqueadas en Ajustes del Sistema")
    }
    static var notificationsPending: String {
        pick("waiting for permission", "aguardando permissão", "esperando permiso")
    }
    static var notificationsUnknown: String { pick("unknown state", "estado desconhecido", "estado desconocido") }

    // MARK: Estados dos medidores

    static var sendAMessage: String {
        pick("Send a message in Claude Code", "Envie uma mensagem no Claude Code", "Envía un mensaje en Claude Code")
    }
    static var waitingFirstRateLimits: String {
        pick(
            "Waiting for limits",
            "Aguardando limites",
            "Esperando límites"
        )
    }
    static var waitingSessionData: String {
        pick("Waiting for session", "Aguardando sessão", "Esperando sesión")
    }
    static var errorValue: String { pick("Error", "Erro", "Error") }
    /// Só aparece quando o app tentou apagar o cache ilegível e não conseguiu:
    /// aí é permissão, e aí sim é o utilizador que resolve.
    static var invalidLocalCache: String {
        pick("Can't read the local cache", "Não foi possível ler o cache local", "No se pudo leer la caché local")
    }
    static var reconfigureOrRemoveState: String {
        pick(
            "Check the permissions of the data folder",
            "Verifique as permissões da pasta de dados",
            "Comprueba los permisos de la carpeta de datos"
        )
    }
    static var sessionDataUnavailable: String {
        pick("Session data unavailable", "Dados da sessão indisponíveis", "Datos de sesión no disponibles")
    }
    static var unavailableInPayload: String {
        pick(
            "Limit not sent by Claude Code",
            "Limite não enviado pelo Claude Code",
            "Límite no enviado por Claude Code"
        )
    }
    static var windowClosed: String { pick("Closed", "Encerrado", "Cerrado") }
    static func resets(_ when: String) -> String {
        pick("Reset: \(when)", "Reinício: \(when)", "Reinicio: \(when)")
    }
    static func dataAgeSuffix(_ elapsed: String) -> String {
        pick("data from \(elapsed)", "dados \(elapsed)", "datos de \(elapsed)")
    }
    /// A janela não veio no payload mais recente: o número é o último
    /// conhecido, não o de agora.
    static func staleWindow(_ elapsed: String) -> String {
        pick(
            "Not in the latest update · from \(elapsed)",
            "Não veio na última atualização · dado \(elapsed)",
            "No vino en la última actualización · dato de \(elapsed)"
        )
    }
    /// A doc do Claude Code diz que cada janela pode faltar por si só, mesmo
    /// com a outra presente, e não lista as condições. Então o texto descreve
    /// o que se sabe, sem inventar a causa.
    static var maybeUnavailableForAccount: String {
        pick(
            "Not sent for this plan",
            "Não enviado para este plano",
            "No enviado para este plan"
        )
    }

    // MARK: Autenticação por chave de API

    /// Com chave de API o Claude Code não envia rate_limits: não há janela de
    /// 5 h nem de 7 d, o uso é cobrado por token. Sem dizer isto, o app fica
    /// eternamente "aguardando dados" que nunca chegam.
    static var apiKeyNoLimits: String {
        pick(
            "API key billing has no usage windows",
            "Cobrança por chave de API não tem janelas de uso",
            "La facturación por clave de API no tiene ventanas de uso"
        )
    }
    static var apiKeyNoLimitsDetail: String {
        pick(
            "Claude Code only reports limits on Pro, Max, Team and seat-based Enterprise.",
            "O Claude Code só informa limites nos planos Pro, Max, Team e Enterprise por assento.",
            "Claude Code solo informa límites en los planes Pro, Max, Team y Enterprise por asiento."
        )
    }
    /// O payload traz só five_hour e seven_day. O limite semanal de Sonnet e o
    /// limite por modelo do Opus existem e podem bloquear, mas não chegam aqui.
    static var sevenDayTooltip: String {
        pick(
            "The weekly limit across all models. Plan-specific limits (such as the Max weekly Sonnet limit) are not reported by Claude Code and are not shown here.",
            "O limite semanal de todos os modelos. Limites específicos do plano (como o semanal de Sonnet no Max) não são informados pelo Claude Code e não aparecem aqui.",
            "El límite semanal de todos los modelos. Los límites específicos del plan (como el semanal de Sonnet en Max) no los informa Claude Code y no aparecen aquí."
        )
    }
    static var availableAfterResponse: String {
        pick("After a Claude Code response", "Após uma resposta do Claude Code", "Después de una respuesta de Claude Code")
    }
    static func tokens(_ count: String) -> String { pick("\(count) tokens", "\(count) tokens", "\(count) tokens") }
    static func windowOf(_ size: String) -> String { pick("\(size) window", "janela de \(size)", "ventana de \(size)") }
    static func percentFree(_ value: String) -> String { pick("\(value)% free", "\(value)% livre", "\(value)% libre") }
    static var contextUsedInSession: String {
        pick("Used in this session", "Uso na sessão atual", "Uso en esta sesión")
    }
    static var unknownResetTime: String {
        pick("at an unknown time", "em horário desconhecido", "en un momento desconocido")
    }

    // MARK: Saúde do monitor

    static var healthHealthy: String { pick("Running normally", "Funcionando normalmente", "Funcionando normalmente") }
    static var healthWaiting: String {
        pick("Waiting for Claude Code data", "Aguardando dados do Claude Code", "Esperando datos de Claude Code")
    }
    static var healthWarning: String { pick("Attention needed", "Atenção necessária", "Requiere atención") }
    static var healthError: String { pick("Monitor error", "Monitor com erro", "Error del monitor") }
    static var integrationNeedsRepairDetail: String {
        pick("Claude Code integration needs repair", "Integração com Claude Code precisa de reparo", "La integración con Claude Code necesita reparación")
    }
    static var statusLineDisabledByHooks: String {
        pick("Status line disabled by disableAllHooks", "Status line desativada por disableAllHooks", "Línea de estado desactivada por disableAllHooks")
    }
    static var waitingFiveHourLimit: String {
        pick(
            "Waiting for limits",
            "Aguardando limites",
            "Esperando límites"
        )
    }
    static var windowClosedWaiting: String {
        pick("Window closed • waiting for data", "Janela encerrada • aguardando dados", "Ventana cerrada • esperando datos")
    }
    static func noRecentData(_ elapsed: String) -> String {
        pick(
            "Last update \(elapsed) • message Claude Code",
            "Última atualização \(elapsed) • envie no Claude Code",
            "Última actualización \(elapsed) • escribe en Claude Code"
        )
    }
    static var recentSessionWithoutLimits: String {
        pick(
            "Claude Code active • limits not sent",
            "Claude Code ativo • limites não enviados",
            "Claude Code activo • límites no enviados"
        )
    }
    static var usageActiveNotificationsOff: String {
        pick("Usage active; notifications disabled", "Uso ativo; notificações desativadas", "Uso activo; notificaciones desactivadas")
    }
    static var healthyDetail: String {
        pick("Data updated • integration active", "Dados atualizados • integração ativa", "Datos actualizados • integración activa")
    }

    // MARK: Notificações

    static var claudeLimitTitle: String { pick("Claude limit", "Limite do Claude", "Límite de Claude") }
    static var claudeLimitAlmostGoneTitle: String {
        pick("Claude limit almost exhausted", "Limite do Claude quase esgotado", "Límite de Claude casi agotado")
    }
    static var fiveHourWindowLabel: String { pick("5-hour limit", "limite de 5 horas", "límite de 5 horas") }
    static var sevenDayWindowLabel: String { pick("7-day limit", "limite de 7 dias", "límite de 7 días") }
    static func reachedThreshold(_ threshold: Int, window: String) -> String {
        pick(
            "You've reached \(threshold)% of the \(window).",
            "Você atingiu \(threshold)% do \(window).",
            "Has alcanzado el \(threshold)% del \(window)."
        )
    }
    static func resetsAtSuffix(_ time: String) -> String {
        pick(" Resets \(time).", " Reinicia em \(time).", " Se reinicia el \(time).")
    }
    static var windowResetTitle: String {
        pick("5-hour window reset", "Janela de 5 horas reiniciada", "Ventana de 5 horas reiniciada")
    }
    /// O título já anuncia o reinício; o corpo diz o que fazer com isso.
    static var windowResetBody: String {
        pick(
            "You can use Claude Code again.",
            "Você já pode usar o Claude Code de novo.",
            "Ya puedes usar Claude Code de nuevo."
        )
    }
    static var noUsageDataYetTitle: String {
        pick("No usage data yet", "Ainda não há dados de uso", "Aún no hay datos de uso")
    }
    static var noUsageDataYetBody: String {
        pick(
            "Send a message in Claude Code and try again.",
            "Envie uma mensagem no Claude Code e tente novamente.",
            "Envía un mensaje en Claude Code e inténtalo de nuevo."
        )
    }
    static var couldNotRefreshTitle: String {
        pick("Could not refresh", "Não foi possível atualizar", "No se pudo actualizar")
    }
    static var couldNotRefreshBody: String {
        pick(
            "The local cache is invalid. Use Reconfigure Claude Code.",
            "O cache local está inválido. Use Reconfigurar Claude Code.",
            "La caché local no es válida. Usa Reconfigurar Claude Code."
        )
    }
    static var refreshDoneTitle: String {
        pick("Refresh completed", "Atualização concluída com sucesso", "Actualización completada")
    }
    static var noUsageDataYetShort: String {
        pick("No usage data yet.", "Sem dados de uso ainda.", "Aún no hay datos de uso.")
    }

    // MARK: Alertas modais

    static var notificationsDisabledTitle: String {
        pick("Notifications are disabled", "Notificações estão desativadas", "Las notificaciones están desactivadas")
    }
    static var notificationsDisabledBody: String {
        pick(
            "Enable Claude Usage Monitor in System Settings > Notifications.",
            "Ative Claude Usage Monitor em Ajustes do Sistema > Notificações.",
            "Activa Claude Usage Monitor en Ajustes del Sistema > Notificaciones."
        )
    }
    static var openSettings: String { pick("Open Settings", "Abrir Ajustes", "Abrir Ajustes") }
    static var notNow: String { pick("Not now", "Agora não", "Ahora no") }
    static var statusLineDisabledTitle: String {
        pick("Status line disabled", "Status line desativada", "Línea de estado desactivada")
    }
    static var statusLineDisabledBody: String {
        pick(
            "The disableAllHooks option is enabled in ~/.claude/settings.json. "
                + "Claude Code will not run the monitor while it is on.",
            "A opção disableAllHooks está ativa em ~/.claude/settings.json. "
                + "O Claude Code não executará o monitor enquanto essa opção estiver habilitada.",
            "La opción disableAllHooks está activada en ~/.claude/settings.json. "
                + "Claude Code no ejecutará el monitor mientras esté activada."
        )
    }
    static var couldNotConfigure: String {
        pick("Could not configure Claude Code.", "Não foi possível configurar o Claude Code.", "No se pudo configurar Claude Code.")
    }
    static var couldNotToggleLogin: String {
        pick(
            "Could not change the login item.",
            "Não foi possível alterar o item de início de sessão.",
            "No se pudo cambiar el elemento de inicio de sesión."
        )
    }
    static var finderDidNotOpen: String {
        pick("Finder did not open the data folder.", "O Finder não abriu a pasta de dados.", "Finder no abrió la carpeta de datos.")
    }
    static var couldNotOpenDataFolder: String {
        pick("Could not open the data folder.", "Não foi possível abrir a pasta de dados.", "No se pudo abrir la carpeta de datos.")
    }
    static var couldNotSendNotification: String {
        pick("Could not deliver the notification.", "Não foi possível enviar a notificação.", "No se pudo enviar la notificación.")
    }
    static var couldNotRequestNotifications: String {
        pick("Could not request notifications.", "Não foi possível solicitar notificações.", "No se pudo solicitar permiso para las notificaciones.")
    }

    // MARK: Resumo, statusline, tempos relativos

    static var fiveHoursLabel: String { pick("5 hours", "5 horas", "5 horas") }
    static var sevenDaysLabel: String { pick("7 days", "7 dias", "7 días") }
    static var contextLabel: String { pick("context", "contexto", "contexto") }
    static var summaryUnavailable: String { pick("unavailable", "indisponível", "no disponible") }
    static var waitingNewWindow: String {
        pick("waiting for a new window", "aguardando nova janela", "esperando una nueva ventana")
    }
    static func summaryResets(_ countdown: String) -> String {
        pick("(resets \(countdown))", "(reinicia \(countdown))", "(se reinicia \(countdown))")
    }
    static var now: String { pick("now", "agora", "ahora") }
    static func inTime(_ value: String) -> String { pick("in \(value)", "em \(value)", "en \(value)") }
    static func agoTime(_ value: String) -> String { pick("\(value) ago", "há \(value)", "hace \(value)") }
    static var modelSummaryLabel: String { pick("model", "modelo", "modelo") }
    static var projectSummaryLabel: String { pick("project", "projeto", "proyecto") }
    static var noDataCLI: String {
        pick(
            "No data yet. Open Claude Code and send a message.",
            "Ainda não há dados. Abra o Claude Code e envie uma mensagem.",
            "Aún no hay datos. Abre Claude Code y envía un mensaje."
        )
    }
    static var failure: String { pick("Failure", "Falha", "Error") }
    static func invalidJSON(_ path: String) -> String {
        pick("Invalid JSON at \(path)", "JSON inválido em \(path)", "JSON no válido en \(path)")
    }

    // MARK: Histórico

    static var historyWindowTitle: String { pick("Usage History", "Histórico de uso", "Historial de uso") }
    /// A janela de 5 h corrente, ancorada no reset, não as últimas 5 h.
    static var rangeCurrentWindow: String { pick("5 h window", "Janela de 5 h", "Ventana de 5 h") }
    static var range24h: String { pick("24 h", "24 h", "24 h") }
    static var range7d: String { pick("7 days", "7 dias", "7 días") }
    static var range30d: String { pick("30 days", "30 dias", "30 días") }
    static var range90d: String { pick("90 days", "90 dias", "90 días") }
    /// A legenda nomeia qual limite cada linha traça, então reusa o título do
    /// medidor correspondente. Antes o painel dizia "Limite de 5 horas" e o
    /// gráfico "Janela de 5 horas" para a mesma coisa.
    static var noHistoryYet: String {
        pick(
            "No history yet. Data is collected as you use Claude Code.",
            "Ainda não há histórico. Os dados são coletados conforme você usa o Claude Code.",
            "Aún no hay historial. Los datos se recopilan mientras usas Claude Code."
        )
    }
    /// Na janela corrente há histórico, só não há uso ainda: dizer "sem
    /// histórico" seria falso logo depois de um reset.
    static var noUsageInWindow: String {
        pick(
            "No usage in this window yet.",
            "Nenhum uso nesta janela ainda.",
            "Aún no hay uso en esta ventana."
        )
    }
    /// O seletor de período fica logo acima, então "no período" era redundante.
    /// As partes montam-se conforme o plano informa: um plano sem limite
    /// semanal não deve ler "7 d: --", que sugere um dado que falhou em vez de
    /// um limite que não existe ali.
    static func historyPeak(_ parts: [String]) -> String {
        pick("Peak: ", "Pico: ", "Pico: ") + parts.joined(separator: " · ")
    }
    static func peakFiveHour(_ value: String) -> String {
        pick("5 h \(value)", "5 h \(value)", "5 h \(value)")
    }
    static func peakSevenDay(_ value: String) -> String {
        pick("7 d \(value)", "7 d \(value)", "7 d \(value)")
    }
    /// A escala é sempre 0–100% do limite do próprio plano: a Anthropic não
    /// publica números absolutos, e a percentagem é a única medida que
    /// significa o mesmo num Pro e num Max 20x.
    static var chartAxisNote: String {
        pick(
            "% of your plan's limit",
            "% do limite do seu plano",
            "% del límite de tu plan"
        )
    }

    // MARK: Tendência e ritmo

    static func paceProjection(_ time: String) -> String {
        pick("At this pace: 100% at \(time)", "No ritmo atual: 100% às \(time)", "A este ritmo: 100% a las \(time)")
    }
    /// Dentro de uma janela o consumo só sobe (zera no reset), então o "pico da
    /// janela" era sempre igual ao valor atual: o painel dizia o mesmo número
    /// no medidor, na barra e aqui. O que falta ao lado do gráfico não é o
    /// nível, é o ritmo.
    static func paceRate(_ value: String) -> String {
        pick("\(value)% per hour", "\(value)% por hora", "\(value)% por hora")
    }
    static var noRecentUsage: String {
        pick("Paused right now", "Sem consumo agora", "Sin consumo ahora")
    }
    static var chartNowMarker: String { pick("now", "agora", "ahora") }
    static var awaitingWindow: String {
        pick("No active window", "Sem janela ativa", "Sin ventana activa")
    }
    static var collectingData: String { pick("Collecting data…", "Coletando dados…", "Recopilando datos…") }

    // MARK: Perfis de marcos

    static var milestonesHeader: String { pick("Notify at milestones", "Notificar nos marcos", "Notificar en los umbrales") }
    static var profileAll: String { pick("All milestones (default)", "Todos os marcos (padrão)", "Todos los umbrales (predeterminado)") }
    static var profileHigh: String { pick("From 75% up", "A partir de 75%", "A partir del 75%") }
    static var profileCritical: String { pick("Critical only (90%+)", "Só críticos (90%+)", "Solo críticos (90%+)") }

    // MARK: Exportação e custo

    static var exportHistory: String { pick("Export…", "Exportar…", "Exportar…") }
    static var nothingToExport: String {
        pick("No history to export yet.", "Ainda não há histórico para exportar.", "Aún no hay historial para exportar.")
    }
    static var couldNotExportHistory: String {
        pick("Could not export usage history.", "Não foi possível exportar o histórico de uso.", "No se pudo exportar el historial de uso.")
    }
    static var exportFileName: String { "claude-usage-history" }
    /// Valor da linha "Custo API (est.)" na grade de detalhes: o rótulo já
    /// nomeia o campo, então aqui só entram os números.
    static func costPeriodValue(_ day: String, _ week: String) -> String {
        "24 h: \(day) • 7 d: \(week)"
    }

    static func costSummary(_ day: String, _ week: String) -> String {
        pick(
            "API cost (est.) 24 h: \(day) • 7 d: \(week)",
            "Custo API (est.) 24 h: \(day) • 7 d: \(week)",
            "Coste API (est.) 24 h: \(day) • 7 d: \(week)"
        )
    }

    // MARK: Formatos de data

    /// Os formatos nascem de um template, não de literais por idioma. "j" é o
    /// campo de hora que o ICU resolve para 12 ou 24 horas conforme o locale:
    /// fixar "HH" impunha 24 horas ao inglês dos EUA, que espera "2:32 PM", e
    /// obrigava a reescrever a ordem dos campos à mão a cada idioma novo.
    private static func template(_ skeleton: String) -> String {
        DateFormatter.dateFormat(fromTemplate: skeleton, options: 0, locale: locale) ?? "HH:mm"
    }

    static var shortDateTimeFormat: String { template("MMMdjmm") }
    static var fullDateTimeFormat: String { template("MMMdjmm") }
    static var updatedTimeFormat: String { template("MMMdjmms") }
    static var clockFormat: String { template("jmm") }
}
