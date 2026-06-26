//
//  AppLocalization.swift
//  ClipDock
//

import SwiftUI

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
}

enum AppDisplayLanguage {
    case simplifiedChinese
    case english

    static func resolve(from preferenceRawValue: String) -> AppDisplayLanguage {
        let preference = AppLanguagePreference(rawValue: preferenceRawValue) ?? .system
        switch preference {
        case .system:
            let identifier = Locale.preferredLanguages.first ?? Locale.current.identifier
            if identifier.hasPrefix("zh-Hans") || identifier.hasPrefix("zh") {
                return .simplifiedChinese
            }
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        }
    }

    var localeIdentifier: String {
        switch self {
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }
}

enum AppTextKey: String {
    case close
    case minimize
    case zoom
    case settings
    case showHideMainWindow
    case quit
    case loginApprovalRequired
    case loginItemNotFound
    case loginStatusUnknown
    case clipsCount
    case pinned
    case today
    case yesterday
    case searchClipboard
    case copy
    case delete
    case pin
    case unpin
    case noSelection
    case chooseClipboardItem
    case copied
    case sourceApp
    case imageFormat
    case resolution
    case imageSize
    case fileSize
    case characters
    case type
    case excludeApp
    case fileReady
    case versionLabel
    case general
    case privacy
    case quickOpen
    case autoClean
    case storage
    case about
    case launchAndBehavior
    case launchAndBehaviorSubtitle
    case launchAtLogin
    case launchAtLoginSubtitle
    case autoHideAfterCopy
    case autoHideAfterCopySubtitle
    case interfaceSection
    case interfaceSectionSubtitle
    case language
    case languageSubtitle
    case followSystem
    case simplifiedChinese
    case english
    case clipboardSection
    case clipboardSectionSubtitle
    case keepImages
    case keepImagesSubtitle
    case dataManagement
    case dataManagementSubtitle
    case clearAllHistory
    case clearAllHistorySubtitle
    case clear
    case storageSectionTitle
    case storageSectionSubtitle
    case storageTotalItems
    case storageTotalItemsSubtitle
    case storageTextItems
    case storageTextItemsSubtitle
    case storageImages
    case storageImagesSubtitle
    case storageFilesCache
    case storageFilesCacheSubtitle
    case storageLinkMetadata
    case storageLinkMetadataSubtitle
    case clearCache
    case clearCacheSubtitle
    case contentFilters
    case contentFiltersSubtitle
    case ignoreVerificationCodes
    case ignoreVerificationCodesSubtitle
    case ignorePasswordsAndTokens
    case ignorePasswordsAndTokensSubtitle
    case ignorePrivateKeys
    case ignorePrivateKeysSubtitle
    case ignoreLongSensitiveText
    case ignoreLongSensitiveTextSubtitle
    case noExcludedApps
    case noExcludedAppsSubtitle
    case remove
    case shortcutSection
    case shortcutSectionSubtitle
    case shortcutChangeSubtitle
    case appTagline
    case appInfo
    case author
    case privacySection
    case privacySectionSubtitle
    case autoCleanSection
    case autoCleanSectionSubtitle
    case enableAutoCleanup
    case enableAutoCleanupSubtitle
    case retentionDuration
    case retentionDurationSubtitle
    case shortcutRecordTitle
    case shortcutRecordHint
    case recording
    case change
    case reset
    case noShortcutSet
    case text
    case link
    case image
    case code
    case files
    case other
    case all
    case links
    case images
    case minute
    case hour
    case day
    case unknownSource
    case fileList
    case empty
    case originalFileNoLongerExists
}

struct AppLocalizer {
    let language: AppDisplayLanguage

    static var current: AppLocalizer {
        AppLocalizer(language: AppDisplayLanguage.resolve(from: UserDefaults.standard.string(forKey: "app.languagePreference") ?? AppLanguagePreference.system.rawValue))
    }

    func text(_ key: AppTextKey, _ arguments: CVarArg...) -> String {
        let format = localizedFormat(for: key)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    private func localizedFormat(for key: AppTextKey) -> String {
        let locale = Locale(identifier: language.localeIdentifier)
        if #available(macOS 13.0, *) {
            return String(localized: String.LocalizationValue(key.rawValue), bundle: localizedBundle, locale: locale)
        }

        return NSLocalizedString(key.rawValue, tableName: "Localizable", bundle: localizedBundle, value: key.rawValue, comment: "")
    }

    private var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: language.localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

private struct AppLocalizerEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLocalizer.current
}

extension EnvironmentValues {
    var appLocalizer: AppLocalizer {
        get { self[AppLocalizerEnvironmentKey.self] }
        set { self[AppLocalizerEnvironmentKey.self] = newValue }
    }
}
