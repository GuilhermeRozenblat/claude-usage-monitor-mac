import Foundation

/// Preferências de alerta do app de menu bar, persistidas em UserDefaults.
/// Só o processo GUI lê e escreve aqui; o ingest não notifica.
final class AlertPreferences {
    private enum Keys {
        static let fiveHourEnabled = "alerts.fiveHour.enabled"
        static let sevenDayEnabled = "alerts.sevenDay.enabled"
        static let windowResetEnabled = "alerts.windowReset.enabled"
        static let snoozeUntil = "alerts.snoozeUntil"
        static let fiveHourDelivery = "alerts.fiveHour.delivery"
        static let sevenDayDelivery = "alerts.sevenDay.delivery"
        static let announcedWindowReset = "alerts.windowReset.announced"
        static let thresholdProfile = "alerts.thresholdProfile"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var fiveHourAlertsEnabled: Bool {
        get { enabled(Keys.fiveHourEnabled) }
        set { defaults.set(newValue, forKey: Keys.fiveHourEnabled) }
    }

    var sevenDayAlertsEnabled: Bool {
        get { enabled(Keys.sevenDayEnabled) }
        set { defaults.set(newValue, forKey: Keys.sevenDayEnabled) }
    }

    var windowResetAlertsEnabled: Bool {
        get { enabled(Keys.windowResetEnabled) }
        set { defaults.set(newValue, forKey: Keys.windowResetEnabled) }
    }

    var snoozeUntil: Date? {
        get { defaults.object(forKey: Keys.snoozeUntil) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.snoozeUntil)
            } else {
                defaults.removeObject(forKey: Keys.snoozeUntil)
            }
        }
    }

    func isSnoozed(now: Date = Date()) -> Bool {
        guard let snoozeUntil else { return false }
        return snoozeUntil > now
    }

    var fiveHourDelivery: ThresholdDeliveryRecord? {
        get { ThresholdDeliveryRecord(dictionary: defaults.dictionary(forKey: Keys.fiveHourDelivery)) }
        set { setRecord(newValue, forKey: Keys.fiveHourDelivery) }
    }

    var sevenDayDelivery: ThresholdDeliveryRecord? {
        get { ThresholdDeliveryRecord(dictionary: defaults.dictionary(forKey: Keys.sevenDayDelivery)) }
        set { setRecord(newValue, forKey: Keys.sevenDayDelivery) }
    }

    var announcedWindowReset: String? {
        get { defaults.string(forKey: Keys.announcedWindowReset) }
        set { defaults.set(newValue, forKey: Keys.announcedWindowReset) }
    }

    var thresholdProfile: ThresholdProfile {
        get {
            defaults.string(forKey: Keys.thresholdProfile)
                .flatMap(ThresholdProfile.init(rawValue:)) ?? .all
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.thresholdProfile) }
    }

    /// Chaves da versão anterior, em que o app recalculava cruzamentos por
    /// conta própria em vez de ler o state.json do ingest.
    func removeLegacyKeys() {
        ["observedReset", "observedUsage", "notifiedThresholds"].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    private func enabled(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    private func setRecord(_ record: ThresholdDeliveryRecord?, forKey key: String) {
        if let record {
            defaults.set(record.dictionary, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
