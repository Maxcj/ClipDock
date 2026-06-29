//
//  SparkleUpdateManager.swift
//  ClipDock
//

import Foundation
import AppKit
import Sparkle

@MainActor
final class SparkleUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private enum DefaultsKey {
        static let updateChannel = "sparkle.updateChannel"
        static let ignoredVersion = "sparkle.ignoredVersion"
        static let automaticallyChecksForUpdates = "sparkle.automaticallyChecksForUpdates"
        static let updateCheckInterval = "sparkle.updateCheckInterval"
    }

    private var localizer: AppLocalizer {
        AppLocalizer.current
    }

    @Published private(set) var ignoredVersion: String?
    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var updateCheckInterval: TimeInterval
    @Published private(set) var selectedUpdateChannel: SparkleUpdateChannel
    @Published var releaseNotesPresentation: UpdateReleaseNotesPresentation?
    private var shouldShowReleaseNotesForNextManualCheck = false
    private var shouldShowReleaseNotesForNextStartupCheck = false
    private var shouldBypassCustomPromptForNextStandardFlowCheck = false
    private var didPerformStartupUpdateCheck = false

    var canCheckForUpdates: Bool {
        isConfigured && updaterController.updater.canCheckForUpdates
    }

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    override init() {
        ignoredVersion = UserDefaults.standard.string(forKey: DefaultsKey.ignoredVersion)
            .flatMap { $0.isEmpty ? nil : $0 }
        automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: DefaultsKey.automaticallyChecksForUpdates) as? Bool ?? false
        updateCheckInterval = UserDefaults.standard.object(forKey: DefaultsKey.updateCheckInterval) as? TimeInterval ?? 60 * 60 * 24
        selectedUpdateChannel = SparkleUpdateChannel(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.updateChannel) ?? "") ?? .release
        super.init()

        configureUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else {
            NSLog("Sparkle feed URL is not configured")
            return
        }

        shouldShowReleaseNotesForNextManualCheck = true
        updaterController.updater.checkForUpdateInformation()
    }

    func checkForUpdatesUsingStandardFlow() {
        guard canCheckForUpdates else {
            NSLog("Sparkle feed URL is not configured")
            return
        }

        shouldBypassCustomPromptForNextStandardFlowCheck = true
        updaterController.updater.checkForUpdates()
    }

    func clearIgnoredVersion() {
        setIgnoredVersion(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.automaticallyChecksForUpdates)
        automaticallyChecksForUpdates = enabled

        guard isConfigured else { return }

        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    func setUpdateCheckInterval(_ interval: TimeInterval) {
        let sanitizedInterval = max(60 * 60, interval)
        UserDefaults.standard.set(sanitizedInterval, forKey: DefaultsKey.updateCheckInterval)
        updateCheckInterval = sanitizedInterval

        guard isConfigured else { return }

        updaterController.updater.updateCheckInterval = sanitizedInterval
    }

    func setUpdateChannel(_ channel: SparkleUpdateChannel) {
        guard channel != selectedUpdateChannel else { return }

        UserDefaults.standard.set(channel.rawValue, forKey: DefaultsKey.updateChannel)
        selectedUpdateChannel = channel

        guard isConfigured else { return }

        updaterController.updater.resetUpdateCycle()
    }

    func performStartupUpdateCheckIfNeeded() {
        guard !didPerformStartupUpdateCheck else { return }
        didPerformStartupUpdateCheck = true
        guard canCheckForUpdates else { return }

        shouldShowReleaseNotesForNextStartupCheck = true
        updaterController.updater.checkForUpdateInformation()
    }

    func setIgnoredVersion(_ version: String?) {
        let normalized = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedValue = normalized?.isEmpty == true ? nil : normalized
        UserDefaults.standard.set(storedValue, forKey: DefaultsKey.ignoredVersion)
        ignoredVersion = storedValue
    }

    private func configureUpdater() {
        guard configuredFeedURLString != nil else {
            isConfigured = false
            NSLog("Sparkle feed URL is missing for the selected update channel.")
            return
        }

        // Remove any legacy feed URL stored by older Sparkle APIs so the selected
        // channel is the single source of truth.
        updaterController.updater.clearFeedURLFromUserDefaults()
        updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        updaterController.updater.automaticallyDownloadsUpdates = false
        updaterController.updater.updateCheckInterval = updateCheckInterval
        updaterController.startUpdater()
        isConfigured = true
    }

    private var configuredFeedURLString: String? {
        let feedURLString = selectedUpdateChannel.feedURLString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return feedURLString.isEmpty ? nil : feedURLString
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        configuredFeedURLString
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard let ignoredVersion,
              !ignoredVersion.isEmpty else {
            return
        }

        let versionString = updateItem.versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayVersionString = updateItem.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesIgnoredVersion = versionString == ignoredVersion || displayVersionString == ignoredVersion

        if matchesIgnoredVersion {
            throw NSError(
                domain: "SparkleUpdateManager",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "This update version was ignored."
                ]
            )
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let versionString = item.versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayVersionString = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesIgnoredVersion = versionString == ignoredVersion || displayVersionString == ignoredVersion

        guard !matchesIgnoredVersion else { return }

        if shouldBypassCustomPromptForNextStandardFlowCheck {
            shouldBypassCustomPromptForNextStandardFlowCheck = false
            return
        }

        if shouldShowReleaseNotesForNextManualCheck || shouldShowReleaseNotesForNextStartupCheck {
            shouldShowReleaseNotesForNextManualCheck = false
            shouldShowReleaseNotesForNextStartupCheck = false
            Task { await presentReleaseNotesPrompt(for: item) }
        } else {
            presentDownloadPrompt(for: item)
        }
    }

    func updater(_ updater: SPUUpdater, userDidSkipThisVersion updateItem: SUAppcastItem) {
        setIgnoredVersion(updateItem.versionString)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor error: Error?) {
        let nsError = error as NSError?
        guard let nsError, nsError.domain == SUSparkleErrorDomain else {
            return
        }

        if nsError.code != 1001 {
            shouldShowReleaseNotesForNextManualCheck = false
            shouldShowReleaseNotesForNextStartupCheck = false
            shouldBypassCustomPromptForNextStandardFlowCheck = false
            NSLog("Sparkle update cycle finished with error: \(nsError.localizedDescription)")
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        handleNoUpdateFound()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        handleNoUpdateFound()
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // Keep Sparkle's standard scheduled update flow; the delegate only advertises support
        // so background checks can schedule without emitting the gentle-reminders warning.
    }

    private func handleNoUpdateFound() {
        shouldBypassCustomPromptForNextStandardFlowCheck = false

        if shouldShowReleaseNotesForNextManualCheck {
            shouldShowReleaseNotesForNextManualCheck = false
            shouldShowReleaseNotesForNextStartupCheck = false
            presentNoUpdatePrompt()
            return
        }

        if shouldShowReleaseNotesForNextStartupCheck {
            shouldShowReleaseNotesForNextStartupCheck = false
        }
    }

    private func presentDownloadPrompt(for item: SUAppcastItem) {
        let version = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.versionString.trimmingCharacters(in: .whitespacesAndNewlines)
            : item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let downloadURL = item.fileURL ?? item.infoURL ?? URL(string: "https://github.com/maxcj/ClipDock/releases/latest")

        let alert = NSAlert()
        alert.messageText = localizer.text(.updateAvailableTitle, version)
        alert.informativeText = localizer.text(.updateAvailableSubtitle)
        alert.alertStyle = .informational
        alert.addButton(withTitle: localizer.text(.downloadUpdate))
        alert.addButton(withTitle: localizer.text(.later))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        if let downloadURL {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    private func presentReleaseNotesPrompt(for item: SUAppcastItem) async {
        let version = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? item.versionString.trimmingCharacters(in: .whitespacesAndNewlines)
            : item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)

        let releaseNotesURL = item.fullReleaseNotesURL ?? item.releaseNotesURL ?? item.infoURL
        let releaseNotesText = await loadReleaseNotesText(for: releaseNotesURL)

        releaseNotesPresentation = UpdateReleaseNotesPresentation(
            version: version,
            releaseNotesText: releaseNotesText ?? localizer.text(.releaseNotesUnavailable),
            downloadURL: item.fileURL ?? item.infoURL ?? URL(string: "https://github.com/maxcj/ClipDock/releases/latest"),
            releaseNotesURL: releaseNotesURL
        )
    }

    func dismissReleaseNotesPresentation() {
        releaseNotesPresentation = nil
    }

    func openDownloadURL(for presentation: UpdateReleaseNotesPresentation) {
        if let downloadURL = presentation.downloadURL {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    func openReleaseNotesURL(for presentation: UpdateReleaseNotesPresentation) {
        if let releaseNotesURL = presentation.releaseNotesURL {
            NSWorkspace.shared.open(releaseNotesURL)
        }
    }

    private func loadReleaseNotesText(for url: URL?) async -> String? {
        guard let url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let mimeType = response.mimeType?.lowercased()

            if mimeType?.contains("html") == true || mimeType?.contains("xml") == true {
                let attributed = try NSAttributedString(
                    data: data,
                    options: [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ],
                    documentAttributes: nil
                )
                return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if let plainText = String(data: data, encoding: .utf8) {
                return preferredReleaseNotesText(from: plainText)
            }
        } catch {
            NSLog("Failed to load release notes from \(url.absoluteString): \(error.localizedDescription)")
        }

        return nil
    }

    private func preferredReleaseNotesText(from text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        switch localizer.language {
        case .english:
            return sectionText(
                in: normalized,
                startingAt: ["What’s New", "Highlights"],
                endingBefore: ["本次更新"]
            ) ?? normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        case .simplifiedChinese:
            return sectionText(
                in: normalized,
                startingAt: ["本次更新"],
                endingBefore: ["What’s New", "Highlights"]
            ) ?? normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func sectionText(
        in text: String,
        startingAt startHeadings: [String],
        endingBefore endHeadings: [String]
    ) -> String? {
        guard let startMatch = firstRange(in: text, matchingAnyOf: startHeadings) else { return nil }

        let tail = String(text[startMatch.lowerBound...])
        if let endMatch = firstRange(in: tail, matchingAnyOf: endHeadings) {
            let section = String(tail[..<endMatch.lowerBound])
            return section.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstRange(in text: String, matchingAnyOf candidates: [String]) -> Range<String.Index>? {
        for candidate in candidates {
            if let range = text.range(of: candidate) {
                return range
            }
        }
        return nil
    }

    private func presentNoUpdatePrompt() {
        let alert = NSAlert()
        alert.messageText = localizer.text(.noUpdateTitle)
        alert.informativeText = localizer.text(.noUpdateSubtitle)
        alert.alertStyle = .informational
        alert.addButton(withTitle: localizer.text(.ok))
        alert.runModal()
    }
}

struct UpdateReleaseNotesPresentation: Identifiable {
    let id = UUID()
    let version: String
    let releaseNotesText: String
    let downloadURL: URL?
    let releaseNotesURL: URL?
}
