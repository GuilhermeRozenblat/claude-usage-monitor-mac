import AppKit
import Carbon.HIToolbox

/// Atalho global para abrir o painel, via `RegisterEventHotKey`.
///
/// É a API do sistema para atalhos globais e a única que não pede permissão
/// nenhuma: um monitor de barra de menus não devia exigir Acessibilidade (que é
/// o que `NSEvent.addGlobalMonitorForEvents` obriga) só para abrir um painel.
///
/// Desligado por omissão: um atalho global tira a combinação de todos os outros
/// apps, e isso é escolha do utilizador, não nossa.
final class GlobalShortcut {
    /// ⌥⌘U. O ⌘U sozinho seria roubado a todo o sistema (sublinhar, ver código
    /// fonte); com o ⌥ a combinação está livre na esmagadora maioria dos apps.
    static let displayName = "⌥⌘U"
    private static let defaultsKey = "shortcut.panel.enabled"

    var onTrigger: (() -> Void)?

    private let defaults: UserDefaults
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    deinit {
        unregister()
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.defaultsKey) }

    /// Aplica a preferência guardada. Chamado no arranque.
    func restore() {
        guard isEnabled else { return }
        // Se falhar aqui (outro app apanhou a combinação primeiro), a
        // preferência fica ligada e volta a tentar no próximo arranque: o
        // conflito costuma ser temporário e não vale um aviso no arranque.
        _ = register()
    }

    /// Devolve `false` quando o sistema recusa a combinação, e nesse caso nada
    /// fica guardado: a caixa nos Ajustes tem de contar a verdade.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard enabled else {
            unregister()
            defaults.set(false, forKey: Self.defaultsKey)
            return true
        }
        guard register() else { return false }
        defaults.set(true, forKey: Self.defaultsKey)
        return true
    }

    private func register() -> Bool {
        guard hotKey == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )
            // `GlobalShortcut.`, não `Self.`: um ponteiro de função C não pode
            // capturar o tipo dinâmico.
            guard identifier.signature == GlobalShortcut.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            // O callback do Carbon já corre no run loop principal, mas o painel
            // toca em AppKit: o salto é barato e tira a dúvida.
            DispatchQueue.main.async { shortcut.onTrigger?() }
            return noErr
        }

        guard InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        ) == noErr else { return false }

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_U),
            UInt32(cmdKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard status == noErr else {
            hotKey = nil
            removeHandler()
            return false
        }
        return true
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        removeHandler()
    }

    private func removeHandler() {
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    /// 'CUMk': assinatura de quatro caracteres, como o Carbon espera.
    private static let signature: OSType = 0x43_55_4D_6B
}
