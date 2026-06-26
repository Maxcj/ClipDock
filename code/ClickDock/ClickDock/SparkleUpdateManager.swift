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
    }

    private let localizer = AppLocalizer.current

    @Published private(set) var ignoredVersion: String?
    @Published private(set) var isConfigured: Bool = false

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
        super.init()

        configureUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else {
            NSLog("Sparkle feed URL is not configured")
            return
        }

        updaterController.updater.checkForUpdateInformation()
    }

    func clearIgnoredVersion() {
        setIgnoredVersion(nil)
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

        updaterController.updater.automaticallyChecksForUpdates = false
        updaterController.updater.automaticallyDownloadsUpdates = false
        updaterController.updater.updateCheckInterval = 60 * 60 * 24
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

        presentDownloadPrompt(for: item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain,
              nsError.code == 1001 else {
            return
        }

        presentNoUpdatePrompt()
    }

    func updater(_ updater: SPUUpdater, userDidSkipThisVersion updateItem: SUAppcastItem) {
        setIgnoredVersion(updateItem.versionString)
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

    private func presentNoUpdatePrompt() {
        let alert = NSAlert()
        alert.messageText = localizer.text(.noUpdateTitle)
        alert.informativeText = localizer.text(.noUpdateSubtitle)
        alert.alertStyle = .informational
        alert.addButton(withTitle: localizer.text(.ok))
        alert.runModal()
    }
}
