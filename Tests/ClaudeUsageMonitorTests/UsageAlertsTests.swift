import Foundation
import XCTest
@testable import ClaudeUsageMonitor

final class UsageAlertsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.language = .ptBR
    }

    // MARK: - ThresholdTracker (lado do ingest)

    func testTrackerBaselinesFirstObservation() {
        let notified = ThresholdTracker.updated(
            notified: [],
            thresholds: UsageThresholds.fiveHour,
            usage: 60,
            previousUsage: nil,
            previousResetAt: nil,
            resetAt: 1_900_000_000
        )
        XCTAssertEqual(notified, [25, 50])
    }

    func testTrackerAccumulatesWithinWindow() {
        let notified = ThresholdTracker.updated(
            notified: [25, 50],
            thresholds: UsageThresholds.fiveHour,
            usage: 92,
            previousUsage: 60,
            previousResetAt: 1_900_000_000,
            resetAt: 1_900_000_000
        )
        XCTAssertEqual(notified, [25, 50, 75, 90])
    }

    func testTrackerClearsOnResetChange() {
        let notified = ThresholdTracker.updated(
            notified: [25, 50, 75],
            thresholds: UsageThresholds.fiveHour,
            usage: 30,
            previousUsage: 80,
            previousResetAt: 1_900_000_000,
            resetAt: 1_900_018_000
        )
        XCTAssertEqual(notified, [25])
    }

    func testTrackerClearsOnUsageDropWithoutResetTimestamp() {
        let notified = ThresholdTracker.updated(
            notified: [25, 50, 75],
            thresholds: UsageThresholds.fiveHour,
            usage: 10,
            previousUsage: 80,
            previousResetAt: nil,
            resetAt: nil
        )
        XCTAssertEqual(notified, [])
    }

    // MARK: - ThresholdDelivery (lado do app)

    func testDeliveryAnnouncesOnlyHighestPending() {
        let outcome = ThresholdDelivery.evaluate(
            notified: [25, 50, 75],
            resetId: "A",
            previous: nil,
            dataIsFresh: true
        )
        XCTAssertEqual(outcome.announce, 75)
        XCTAssertEqual(outcome.record, ThresholdDeliveryRecord(resetId: "A", delivered: [25, 50, 75]))
    }

    func testDeliveryAnnouncesNewCrossingWithinSameWindow() {
        let previous = ThresholdDeliveryRecord(resetId: "A", delivered: [25, 50])
        let outcome = ThresholdDelivery.evaluate(
            notified: [25, 50, 90],
            resetId: "A",
            previous: previous,
            dataIsFresh: true
        )
        XCTAssertEqual(outcome.announce, 90)
    }

    func testDeliveryStaysQuietWhenNothingPending() {
        let previous = ThresholdDeliveryRecord(resetId: "A", delivered: [25, 50])
        let outcome = ThresholdDelivery.evaluate(
            notified: [25, 50],
            resetId: "A",
            previous: previous,
            dataIsFresh: true
        )
        XCTAssertNil(outcome.announce)
    }

    func testDeliverySuppressesStaleDataButMarksDelivered() {
        let outcome = ThresholdDelivery.evaluate(
            notified: [25, 50, 90],
            resetId: "A",
            previous: nil,
            dataIsFresh: false
        )
        XCTAssertNil(outcome.announce)
        XCTAssertEqual(outcome.record.delivered, [25, 50, 90])
    }

    func testDeliveryDetectsNewWindowByResetId() {
        let previous = ThresholdDeliveryRecord(resetId: "A", delivered: [25, 50, 75, 90])
        let outcome = ThresholdDelivery.evaluate(
            notified: [25],
            resetId: "B",
            previous: previous,
            dataIsFresh: true
        )
        XCTAssertEqual(outcome.announce, 25)
        XCTAssertEqual(outcome.record.resetId, "B")
    }

    func testDeliveryDetectsNewWindowByShrinkingNotifiedSet() {
        // resets_at ausente: o resetId fica "unknown" nas duas janelas, mas o
        // conjunto do ingest encolheu, e isso denuncia a nova janela.
        let previous = ThresholdDeliveryRecord(resetId: "unknown", delivered: [25, 50, 75])
        let outcome = ThresholdDelivery.evaluate(
            notified: [25],
            resetId: "unknown",
            previous: previous,
            dataIsFresh: true
        )
        XCTAssertEqual(outcome.announce, 25)
    }

    // MARK: - WindowResetAnnouncement

    func testWindowResetAnnouncedOnceRightAfterReset() {
        let resetAt: TimeInterval = 1_900_000_000
        let justAfter = Date(timeIntervalSince1970: resetAt + 60)

        let identifier = WindowResetAnnouncement.evaluate(
            resetAt: resetAt,
            maxNotifiedThreshold: 90,
            alreadyAnnounced: nil,
            now: justAfter
        )
        XCTAssertEqual(identifier, String(resetAt))

        XCTAssertNil(WindowResetAnnouncement.evaluate(
            resetAt: resetAt,
            maxNotifiedThreshold: 90,
            alreadyAnnounced: String(resetAt),
            now: justAfter
        ))
    }

    func testWindowResetNotAnnouncedForLowUsageOrOldReset() {
        let resetAt: TimeInterval = 1_900_000_000

        XCTAssertNil(WindowResetAnnouncement.evaluate(
            resetAt: resetAt,
            maxNotifiedThreshold: 50,
            alreadyAnnounced: nil,
            now: Date(timeIntervalSince1970: resetAt + 60)
        ), "Janela que não chegou a 75% não deveria anunciar")

        XCTAssertNil(WindowResetAnnouncement.evaluate(
            resetAt: resetAt,
            maxNotifiedThreshold: 90,
            alreadyAnnounced: nil,
            now: Date(timeIntervalSince1970: resetAt + AlertPolicy.resetAnnounceWindow + 1)
        ), "Reset antigo demais não deveria anunciar")

        XCTAssertNil(WindowResetAnnouncement.evaluate(
            resetAt: resetAt,
            maxNotifiedThreshold: 90,
            alreadyAnnounced: nil,
            now: Date(timeIntervalSince1970: resetAt - 60)
        ), "Janela ainda ativa não deveria anunciar")
    }

    // MARK: - Ingest: thresholds de 7 dias e rastro de erro

    func testProcessorTracksSevenDayThresholds() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        let first = Data(#"{"rate_limits":{"seven_day":{"used_percentage":80,"resets_at":1900000000}}}"#.utf8)
        let second = Data(#"{"rate_limits":{"seven_day":{"used_percentage":95,"resets_at":1900000000}}}"#.utf8)
        let newWindow = Data(#"{"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":1900604800}}}"#.utf8)

        _ = try StatusLineProcessor.run(input: first, store: store)
        XCTAssertEqual(store.load()?.sevenDayNotifiedThresholds, [75])

        _ = try StatusLineProcessor.run(input: second, store: store)
        XCTAssertEqual(store.load()?.sevenDayNotifiedThresholds, [75, 90])

        _ = try StatusLineProcessor.run(input: newWindow, store: store)
        XCTAssertEqual(store.load()?.sevenDayNotifiedThresholds, [])
    }

    func testProcessorRecordsIngestErrorWithoutErasingState() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        let valid = Data(#"{"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1900000000}}}"#.utf8)

        _ = try StatusLineProcessor.run(input: valid, store: store)
        XCTAssertNil(store.load()?.lastIngestErrorAt)

        let output = try StatusLineProcessor.run(input: Data("not-json".utf8), store: store)
        let state = try XCTUnwrap(store.load())
        XCTAssertNotNil(state.lastIngestErrorAt)
        XCTAssertEqual(state.fiveHourUsage, 40)
        XCTAssertTrue(output.contains("Claude 5h: 40%"), output)
    }

    func testSuccessfulSessionPayloadClearsPreviousIngestError() throws {
        let paths = try temporaryPaths()
        let store = StateStore(paths: paths)
        _ = try StatusLineProcessor.run(input: Data("not-json".utf8), store: store)
        XCTAssertNotNil(store.load()?.lastIngestErrorAt)

        let validSession = Data(#"{"model":{"display_name":"Opus"}}"#.utf8)
        _ = try StatusLineProcessor.run(input: validSession, store: store)

        XCTAssertNil(store.load()?.lastIngestErrorAt)
        XCTAssertEqual(store.load()?.session?.modelDisplayName, "Opus")
    }

    func testProcessorIgnoresEmptyInput() throws {
        let paths = try temporaryPaths()
        _ = try StatusLineProcessor.run(input: Data(), store: StateStore(paths: paths))
        XCTAssertNil(StateStore(paths: paths).load()?.lastIngestErrorAt)
    }

    // MARK: - Resumo compartilhado

    func testSummaryIncludesWindowsAndContext() {
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let state = UsageState(
            fiveHourUsage: 41,
            fiveHourResetAt: now.timeIntervalSince1970 + 8_100,
            sevenDayUsage: 28,
            sevenDayResetAt: now.timeIntervalSince1970 + 200_000,
            usageUpdatedAt: "2026-07-15T19:00:00Z",
            session: SessionSnapshot(contextUsedPercentage: 8)
        )
        let summary = UsageFormatter.summary(state, relativeTo: now)
        XCTAssertTrue(summary.contains("5 horas: 41% (reinicia em 2h 15min)"), summary)
        XCTAssertTrue(summary.contains("7 dias: 28%"), summary)
        XCTAssertTrue(summary.contains("contexto: 8%"), summary)
    }

    func testSummaryHandlesExpiredAndMissingWindows() {
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let expired = UsageState(
            fiveHourUsage: 90,
            fiveHourResetAt: now.timeIntervalSince1970 - 60
        )
        XCTAssertEqual(
            UsageFormatter.summary(expired, relativeTo: now),
            "5 horas: aguardando nova janela"
        )
        XCTAssertEqual(UsageFormatter.summary(UsageState(), relativeTo: now), "5 horas: indisponível")
    }

    func testDataAgeParsesISOTimestamp() {
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let tenMinutesAgo = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(-600)
        )
        XCTAssertEqual(UsageFormatter.dataAge(tenMinutesAgo, relativeTo: now), 600)
        XCTAssertNil(UsageFormatter.dataAge(nil, relativeTo: now))
        XCTAssertNil(UsageFormatter.dataAge("invalid", relativeTo: now))
    }

    func testRecencyDistinguishesActiveSessionFromStaleLimits() {
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let state = UsageState(
            fiveHourUsage: 40,
            usageUpdatedAt: ISO8601DateFormatter().string(
                from: now.addingTimeInterval(-30 * 60)
            ),
            sessionUpdatedAt: ISO8601DateFormatter().string(
                from: now.addingTimeInterval(-2 * 60)
            )
        )

        XCTAssertEqual(
            UsageDataRecency.evaluate(state, relativeTo: now, staleAfter: 15 * 60),
            .recentSessionWithoutLimits
        )
    }

    func testRecencySuggestsInteractionWhenSessionIsAlsoStale() {
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let state = UsageState(
            fiveHourUsage: 40,
            usageUpdatedAt: ISO8601DateFormatter().string(
                from: now.addingTimeInterval(-30 * 60)
            ),
            sessionUpdatedAt: ISO8601DateFormatter().string(
                from: now.addingTimeInterval(-20 * 60)
            )
        )

        XCTAssertEqual(
            UsageDataRecency.evaluate(state, relativeTo: now, staleAfter: 15 * 60),
            .stale(30 * 60)
        )
    }

    // MARK: - ThresholdDeliveryRecord (persistência)

    func testDeliveryRecordDictionaryRoundTrip() {
        let record = ThresholdDeliveryRecord(resetId: "1900000000.0", delivered: [25, 50])
        XCTAssertEqual(ThresholdDeliveryRecord(dictionary: record.dictionary), record)
        XCTAssertNil(ThresholdDeliveryRecord(dictionary: nil))
        XCTAssertNil(ThresholdDeliveryRecord(dictionary: ["resetId": "x"]))
    }

    private func temporaryPaths() throws -> AppPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return AppPaths(
            baseDirectory: root,
            stateFile: root.appendingPathComponent("state.json"),
            statusLineBackupFile: root.appendingPathComponent("previous-statusline.json"),
            claudeSettingsFile: root.appendingPathComponent("settings.json")
        )
    }
}
