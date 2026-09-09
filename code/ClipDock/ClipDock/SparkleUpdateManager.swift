//
//  SparkleUpdateManager.swift
//  ClipDock
//

import Foundation
import Sparkle
import ObjectiveC.runtime

@MainActor
final class SparkleUpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private enum DefaultsKey {
        static let updateChannel = "sparkle.updateChannel"
        static let ignoredVersionLegacy = "sparkle.ignoredVersion"
        static let automaticallyChecksForUpdates = "sparkle.automaticallyChecksForUpdates"
        static let updateCheckInterval = "sparkle.updateCheckInterval"

        static func ignoredVersionBuild(for channel: SparkleUpdateChannel) -> String {
            "sparkle.ignoredVersion.\(channel.rawValue).build"
        }

        static func ignoredVersionDisplay(for channel: SparkleUpdateChannel) -> String {
            "sparkle.ignoredVersion.\(channel.rawValue).display"
        }
    }

    @Published private(set) var ignoredVersion: String?
    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var isUpdateCheckInProgress: Bool = false
    @Published private(set) var updateCheckInterval: TimeInterval
    @Published private(set) var selectedUpdateChannel: SparkleUpdateChannel
    @Published private(set) var updateChannelNotice: String?
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
        Self.installSparkleLocalizationOverride()
        automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: DefaultsKey.automaticallyChecksForUpdates) as? Bool ?? false
        updateCheckInterval = UserDefaults.standard.object(forKey: DefaultsKey.updateCheckInterval) as? TimeInterval ?? 60 * 60 * 24
        let selectedChannel = SparkleUpdateChannel(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.updateChannel) ?? "") ?? .release
        selectedUpdateChannel = selectedChannel
        let migratedIgnoredVersion = Self.migrateLegacyIgnoredVersionIfNeeded(for: selectedChannel)
        super.init()

        ignoredVersion = migratedIgnoredVersion ?? Self.ignoredVersionDisplay(for: selectedChannel)
        configureUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else {
            NSLog("Sparkle feed URL is not configured")
            return
        }

        isUpdateCheckInProgress = true
        updaterController.updater.checkForUpdates()
    }

    func clearIgnoredVersion() {
        storeIgnoredVersion(versionString: nil, displayVersionString: nil, for: selectedUpdateChannel)
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
        ignoredVersion = Self.ignoredVersionDisplay(for: channel)
        updateChannelNotice = Self.updateChannelNotice(for: channel)

        guard isConfigured else { return }

        updaterController.updater.resetUpdateCycle()
    }

    func performStartupUpdateCheckIfNeeded() {
        guard !didPerformStartupUpdateCheck else { return }
        didPerformStartupUpdateCheck = true
        guard canCheckForUpdates, automaticallyChecksForUpdates else { return }

        isUpdateCheckInProgress = true
        updaterController.updater.checkForUpdatesInBackground()
    }

    func setIgnoredVersion(_ updateItem: SUAppcastItem?) {
        guard let updateItem else {
            storeIgnoredVersion(versionString: nil, displayVersionString: nil, for: selectedUpdateChannel)
            return
        }

        storeIgnoredVersion(
            versionString: updateItem.versionString,
            displayVersionString: updateItem.displayVersionString,
            for: selectedUpdateChannel
        )
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

    private static func updateChannelNotice(for channel: SparkleUpdateChannel) -> String {
        let localizer = AppLocalizer.current
        let channelName = localizer.text(channel.titleKey)
        return localizer.text(.updateChannelChangedNotice, channelName, channelName)
    }

    private static func ignoredVersionRecord(for channel: SparkleUpdateChannel) -> (versionString: String, displayVersionString: String)? {
        let versionString = UserDefaults.standard.string(forKey: DefaultsKey.ignoredVersionBuild(for: channel))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayVersionString = UserDefaults.standard.string(forKey: DefaultsKey.ignoredVersionDisplay(for: channel))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !versionString.isEmpty || !displayVersionString.isEmpty else {
            return nil
        }

        return (
            versionString: versionString,
            displayVersionString: displayVersionString.isEmpty ? versionString : displayVersionString
        )
    }

    private static func ignoredVersionDisplay(for channel: SparkleUpdateChannel) -> String? {
        ignoredVersionRecord(for: channel)?.displayVersionString
    }

    private static func migrateLegacyIgnoredVersionIfNeeded(for channel: SparkleUpdateChannel) -> String? {
        let legacyKey = DefaultsKey.ignoredVersionLegacy
        guard let legacyValue = UserDefaults.standard.string(forKey: legacyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyValue.isEmpty else {
            return nil
        }

        guard Self.ignoredVersionRecord(for: channel) == nil else {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return nil
        }

        UserDefaults.standard.set(legacyValue, forKey: DefaultsKey.ignoredVersionBuild(for: channel))
        UserDefaults.standard.set(legacyValue, forKey: DefaultsKey.ignoredVersionDisplay(for: channel))
        UserDefaults.standard.removeObject(forKey: legacyKey)
        return legacyValue
    }

    private func storeIgnoredVersion(
        versionString: String?,
        displayVersionString: String?,
        for channel: SparkleUpdateChannel
    ) {
        let buildKey = DefaultsKey.ignoredVersionBuild(for: channel)
        let displayKey = DefaultsKey.ignoredVersionDisplay(for: channel)

        let normalizedVersion = versionString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplay = displayVersionString?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let normalizedVersion, !normalizedVersion.isEmpty else {
            UserDefaults.standard.removeObject(forKey: buildKey)
            UserDefaults.standard.removeObject(forKey: displayKey)
            if channel == selectedUpdateChannel {
                ignoredVersion = nil
            }
            return
        }

        let finalDisplay = normalizedDisplay?.isEmpty == false ? (normalizedDisplay ?? normalizedVersion) : normalizedVersion
        UserDefaults.standard.set(normalizedVersion, forKey: buildKey)
        UserDefaults.standard.set(finalDisplay, forKey: displayKey)
        if channel == selectedUpdateChannel {
            ignoredVersion = finalDisplay
        }
    }

    private var configuredFeedURLString: String? {
        let feedURLString = selectedUpdateChannel.feedURLString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return feedURLString.isEmpty ? nil : feedURLString
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        configuredFeedURLString
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        guard let ignoredVersion = Self.ignoredVersionRecord(for: selectedUpdateChannel) else {
            return
        }

        let versionString = updateItem.versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayVersionString = updateItem.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesIgnoredVersion = versionString == ignoredVersion.versionString || displayVersionString == ignoredVersion.displayVersionString

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

    func updater(_ updater: SPUUpdater, userDidSkipThisVersion updateItem: SUAppcastItem) {
        setIgnoredVersion(updateItem)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor error: Error?) {
        isUpdateCheckInProgress = false

        let nsError = error as NSError?
        guard let nsError, nsError.domain == SUSparkleErrorDomain else {
            return
        }

        if nsError.code != 1001 {
            NSLog("Sparkle update cycle finished with error: \(nsError.localizedDescription)")
        }
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

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            self.isUpdateCheckInProgress = false
        }
    }

    private static func installSparkleLocalizationOverride() {
        _ = Self.sparkleLocalizationSwizzleToken
    }

    private static let sparkleLocalizationSwizzleToken: Void = {
        let originalSelector = #selector(Bundle.localizedString(forKey:value:table:))
        let swizzledSelector = #selector(Bundle.cdx_localizedString(forKey:value:table:))

        guard let originalMethod = class_getInstanceMethod(Bundle.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(Bundle.self, swizzledSelector) else {
            NSLog("Sparkle localization override could not be installed")
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()
}

private extension Bundle {
    @objc func cdx_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let overrideBundle = Self.cdx_sparkleLocalizationBundle(for: self),
           overrideBundle != self {
            return overrideBundle.cdx_localizedString(forKey: key, value: value, table: tableName)
        }

        return cdx_localizedString(forKey: key, value: value, table: tableName)
    }

    static func cdx_sparkleLocalizationBundle(for bundle: Bundle) -> Bundle? {
        guard cdx_isSparkleBundle(bundle) else { return nil }

        let preference = AppLanguagePreference(rawValue: UserDefaults.standard.string(forKey: "app.languagePreference") ?? AppLanguagePreference.system.rawValue) ?? .system
        let language = AppDisplayLanguage.resolve(from: preference.rawValue)
        // Sparkle ships Simplified Chinese resources as zh_CN, while English lives in Base.
        let resourceName = language == .simplifiedChinese ? "zh_CN" : "Base"

        guard let path = bundle.path(forResource: resourceName, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return nil
        }

        return localizedBundle
    }

    static func cdx_isSparkleBundle(_ bundle: Bundle) -> Bool {
        if bundle.bundleIdentifier == "org.sparkle-project.Sparkle" {
            return true
        }

        return bundle.bundlePath.contains("Sparkle.framework")
    }
}
