//
//  ClipboardSensitiveRuleSupport.swift
//  ClipDock
//

import Foundation

enum ClipboardSensitiveRuleMatchType: String, Codable, CaseIterable, Identifiable {
    case keyword
    case regex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyword:
            return AppLocalizer.current.text(.keyword)
        case .regex:
            return AppLocalizer.current.text(.regex)
        }
    }
}

enum ClipboardSensitiveRuleKeywordMatchMode: String, Codable, CaseIterable, Identifiable {
    case contains
    case exact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .contains:
            return AppLocalizer.current.text(.contains)
        case .exact:
            return AppLocalizer.current.text(.exactMatch)
        }
    }
}

enum ClipboardSensitiveRuleScope: String, Codable, CaseIterable, Identifiable {
    case all
    case text
    case link
    case code
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppLocalizer.current.text(.all)
        case .text:
            return AppLocalizer.current.text(.text)
        case .link:
            return AppLocalizer.current.text(.link)
        case .code:
            return AppLocalizer.current.text(.code)
        case .files:
            return AppLocalizer.current.text(.files)
        }
    }

    func matches(_ kind: ClipboardContentKind?) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return kind == .text
        case .link:
            return kind == .link
        case .code:
            return kind == .code
        case .files:
            return kind == .files
        }
    }
}

struct ClipboardSensitiveRule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var matchType: ClipboardSensitiveRuleMatchType
    var keywordMatchMode: ClipboardSensitiveRuleKeywordMatchMode
    var pattern: String
    var scope: ClipboardSensitiveRuleScope
    var isCaseSensitive: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        matchType: ClipboardSensitiveRuleMatchType,
        keywordMatchMode: ClipboardSensitiveRuleKeywordMatchMode = .contains,
        pattern: String,
        scope: ClipboardSensitiveRuleScope = .all,
        isCaseSensitive: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.matchType = matchType
        self.keywordMatchMode = keywordMatchMode
        self.pattern = pattern
        self.scope = scope
        self.isCaseSensitive = isCaseSensitive
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, matchType, keywordMatchMode, pattern, scope, isCaseSensitive, isEnabled, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        matchType = try container.decode(ClipboardSensitiveRuleMatchType.self, forKey: .matchType)
        keywordMatchMode = try container.decodeIfPresent(ClipboardSensitiveRuleKeywordMatchMode.self, forKey: .keywordMatchMode) ?? .contains
        pattern = try container.decode(String.self, forKey: .pattern)
        scope = try container.decode(ClipboardSensitiveRuleScope.self, forKey: .scope)
        isCaseSensitive = try container.decode(Bool.self, forKey: .isCaseSensitive)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(matchType, forKey: .matchType)
        try container.encode(keywordMatchMode, forKey: .keywordMatchMode)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(scope, forKey: .scope)
        try container.encode(isCaseSensitive, forKey: .isCaseSensitive)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

enum ClipboardSensitiveRuleStore {
    static let storageKey = "clipboard.customSensitiveRules"

    static func load(defaults: UserDefaults = .standard) -> [ClipboardSensitiveRule] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ClipboardSensitiveRule].self, from: data)
        } catch {
            NSLog("Failed to decode custom sensitive rules: \(error.localizedDescription)")
            return []
        }
    }

    static func save(_ rules: [ClipboardSensitiveRule], defaults: UserDefaults = .standard) {
        do {
            let data = try JSONEncoder().encode(rules)
            defaults.set(data, forKey: storageKey)
        } catch {
            NSLog("Failed to encode custom sensitive rules: \(error.localizedDescription)")
        }
    }

    static func add(_ rule: ClipboardSensitiveRule, defaults: UserDefaults = .standard) {
        var rules = load(defaults: defaults)
        rules.append(rule)
        save(rules, defaults: defaults)
    }

    static func update(_ rule: ClipboardSensitiveRule, defaults: UserDefaults = .standard) {
        var rules = load(defaults: defaults)

        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else {
            return
        }

        var updated = rule
        updated.updatedAt = Date()
        rules[index] = updated
        save(rules, defaults: defaults)
    }

    static func delete(id: UUID, defaults: UserDefaults = .standard) {
        let rules = load(defaults: defaults).filter { $0.id != id }
        save(rules, defaults: defaults)
    }
}
