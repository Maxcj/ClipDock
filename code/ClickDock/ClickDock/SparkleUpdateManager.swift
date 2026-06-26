//
//  SparkleUpdateManager.swift
//  ClipDock
//

import Foundation
import AppKit
import Sparkle

@MainActor
final class SparkleUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    private enum DefaultsKey {
        static let feedURL = "sparkle.feedURL"
        static let ignoredVersion = "sparkle.ignoredVersion"
        static let automaticallyChecksForUpdates = "sparkle.automaticallyChecksForUpdates"
        static let updateCheckInterval = "sparkle.updateCheckInterval"
    }

    private let localizer = AppLocalizer.current

    @Published private(set) var ignoredVersion: String?
    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var updateCheckInterval: TimeInterval
    @Published var releaseNotesPresentation: UpdateReleaseNotesPresentation?
    private var shouldShowReleaseNotesForNextManualCheck = false
    private var didPerformStartupUpdateCheck = false

    var canCheckForUpdates: Bool {
        isConfigured && updaterController.updater.canCheckForUpdates
    }

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()

    override init() {
        ignoredVersion = UserDefaults.standard.string(forKey: DefaultsKey.ignoredVersion)
            .flatMap { $0.isEmpty ? nil : $0 }
        automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: DefaultsKey.automaticallyChecksForUpdates) as? Bool ?? false
        updateCheckInterval = UserDefaults.standard.object(forKey: DefaultsKey.updateCheckInterval) as? TimeInterval ?? 60 * 60 * 24
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

    func performStartupUpdateCheckIfNeeded() {
        guard !didPerformStartupUpdateCheck else { return }
        didPerformStartupUpdateCheck = true
        guard canCheckForUpdates else { return }

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
            NSLog("Sparkle feed URL is missing. Set SUFeedURL or sparkle.feedURL before checking for updates.")
            return
        }

        updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        updaterController.updater.automaticallyDownloadsUpdates = false
        updaterController.updater.updateCheckInterval = updateCheckInterval
        updaterController.startUpdater()
        isConfigured = true
    }

    private var configuredFeedURLString: String? {
        if let feedURLString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           !feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return feedURLString
        }

        if let feedURLString = UserDefaults.standard.string(forKey: DefaultsKey.feedURL),
           !feedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return feedURLString
        }

        return nil
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

        if shouldShowReleaseNotesForNextManualCheck {
            shouldShowReleaseNotesForNextManualCheck = false
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

        if nsError.code != SUNoUpdateError {
            shouldShowReleaseNotesForNextManualCheck = false
            NSLog("Sparkle update cycle finished with error: \(nsError.localizedDescription)")
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        handleNoUpdateFound()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        handleNoUpdateFound()
    }

    private func handleNoUpdateFound() {
        guard shouldShowReleaseNotesForNextManualCheck else { return }
        shouldShowReleaseNotesForNextManualCheck = false
        presentNoUpdatePrompt()
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
                return plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            NSLog("Failed to load release notes from \(url.absoluteString): \(error.localizedDescription)")
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
