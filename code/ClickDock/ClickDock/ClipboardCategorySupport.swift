//
//  ClipboardCategorySupport.swift
//  ClipDock
//

import SwiftUI
import CoreData
import AppKit

enum ClipboardCategoryType: String, CaseIterable, Identifiable {
    case system
    case custom
    case smart

    var id: String { rawValue }
}

enum SystemClipboardCategoryKey: String, CaseIterable, Identifiable {
    case all
    case text
    case links
    case images
    case code
    case files
    case colors
    case other

    var id: String { rawValue }
}

struct SystemClipboardCategoryDefinition: Identifiable {
    let key: SystemClipboardCategoryKey
    let titleKey: AppTextKey
    let iconName: String
    let colorHex: String
    let defaultVisible: Bool
    let sortOrder: Int32

    var id: String { key.rawValue }

    var localizedName: String {
        AppLocalizer.current.text(titleKey)
    }

    static let all: [SystemClipboardCategoryDefinition] = [
        .init(key: .all, titleKey: .all, iconName: "circle.fill", colorHex: "#F43F5E", defaultVisible: true, sortOrder: 0),
        .init(key: .text, titleKey: .text, iconName: "text.quote", colorHex: "#F97316", defaultVisible: true, sortOrder: 10),
        .init(key: .links, titleKey: .links, iconName: "link", colorHex: "#10B981", defaultVisible: true, sortOrder: 20),
        .init(key: .images, titleKey: .images, iconName: "photo", colorHex: "#3B82F6", defaultVisible: true, sortOrder: 30),
        .init(key: .code, titleKey: .code, iconName: "chevron.left.forwardslash.chevron.right", colorHex: "#8B5CF6", defaultVisible: true, sortOrder: 40),
        .init(key: .files, titleKey: .files, iconName: "doc", colorHex: "#F59E0B", defaultVisible: false, sortOrder: 50),
        .init(key: .colors, titleKey: .colors, iconName: "paintpalette", colorHex: "#FB923C", defaultVisible: true, sortOrder: 60),
        .init(key: .other, titleKey: .other, iconName: "ellipsis", colorHex: "#64748B", defaultVisible: false, sortOrder: 70)
    ]

    static func definition(for key: SystemClipboardCategoryKey) -> SystemClipboardCategoryDefinition? {
        all.first { $0.key == key }
    }
}

enum ClipboardCategorySelection: Hashable, Identifiable {
    case system(SystemClipboardCategoryKey)
    case custom(UUID)

    var id: String {
        switch self {
        case .system(let key):
            return "system:\(key.rawValue)"
        case .custom(let id):
            return "custom:\(id.uuidString)"
        }
    }

    var systemKey: SystemClipboardCategoryKey? {
        if case let .system(key) = self {
            return key
        }
        return nil
    }

    var customID: UUID? {
        if case let .custom(id) = self {
            return id
        }
        return nil
    }
}

extension ClipboardFilter {
    var systemCategoryKey: SystemClipboardCategoryKey {
        switch self {
        case .all: return .all
        case .text: return .text
        case .links: return .links
        case .images: return .images
        case .code: return .code
        case .files: return .files
        case .colors: return .colors
        case .other: return .other
        }
    }

    var categorySelection: ClipboardCategorySelection {
        .system(systemCategoryKey)
    }
}

extension ClipboardCategory {
    var categoryType: ClipboardCategoryType {
        ClipboardCategoryType(rawValue: typeRaw ?? "") ?? .custom
    }

    var systemCategoryKey: SystemClipboardCategoryKey? {
        guard let systemKey, !systemKey.isEmpty else { return nil }
        return SystemClipboardCategoryKey(rawValue: systemKey)
    }

    var resolvedName: String {
        if let systemCategoryKey,
           let definition = SystemClipboardCategoryDefinition.definition(for: systemCategoryKey) {
            return definition.localizedName
        }

        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        return AppLocalizer.current.text(.categories)
    }

    var resolvedIconName: String {
        let trimmed = iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        if let systemCategoryKey,
           let definition = SystemClipboardCategoryDefinition.definition(for: systemCategoryKey) {
            return definition.iconName
        }

        return "folder"
    }

    var resolvedColorHex: String {
        let trimmed = colorHex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        if let systemCategoryKey,
           let definition = SystemClipboardCategoryDefinition.definition(for: systemCategoryKey) {
            return definition.colorHex
        }

        return "#64748B"
    }

    var swiftUIColor: Color {
        Color(hex: resolvedColorHex) ?? .secondary
    }

    var selection: ClipboardCategorySelection? {
        switch categoryType {
        case .system:
            guard let key = systemCategoryKey else { return nil }
            return .system(key)
        case .custom:
            guard let id else { return nil }
            return .custom(id)
        case .smart:
            return nil
        }
    }
}

extension ClipboardRecord {
    var customCategories: [ClipboardCategory] {
        let links = (categoryLinks as? Set<ClipboardRecordCategory>) ?? []
        return links.compactMap { $0.category }
            .filter { $0.categoryType == .custom }
            .sorted {
                let lhsOrder = $0.sortOrder
                let rhsOrder = $1.sortOrder
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return $0.resolvedName.localizedCaseInsensitiveCompare($1.resolvedName) == .orderedAscending
            }
    }

    var allAssignedCategories: [ClipboardCategory] {
        let links = (categoryLinks as? Set<ClipboardRecordCategory>) ?? []
        return links.compactMap { $0.category }
            .sorted {
                let lhsOrder = $0.sortOrder
                let rhsOrder = $1.sortOrder
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return $0.resolvedName.localizedCaseInsensitiveCompare($1.resolvedName) == .orderedAscending
            }
    }

    func hasCategory(_ category: ClipboardCategory) -> Bool {
        let links = (categoryLinks as? Set<ClipboardRecordCategory>) ?? []
        return links.contains { $0.category == category }
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard !value.isEmpty else { return nil }

        let normalized: String
        switch value.count {
        case 3:
            normalized = value.map { "\($0)\($0)" }.joined() + "FF"
        case 4:
            normalized = value.map { "\($0)\($0)" }.joined()
        case 6:
            normalized = value + "FF"
        case 8:
            normalized = value
        default:
            return nil
        }

        guard let raw = UInt64(normalized, radix: 16) else { return nil }

        let r = Double((raw & 0xFF000000) >> 24) / 255.0
        let g = Double((raw & 0x00FF0000) >> 16) / 255.0
        let b = Double((raw & 0x0000FF00) >> 8) / 255.0
        let a = Double(raw & 0x000000FF) / 255.0

        self = Color(red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String? {
        #if canImport(AppKit)
        guard let resolved = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let red = Int(round(resolved.redComponent * 255))
        let green = Int(round(resolved.greenComponent * 255))
        let blue = Int(round(resolved.blueComponent * 255))
        let alpha = Int(round(resolved.alphaComponent * 255))

        if alpha < 255 {
            return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        }

        return String(format: "#%02X%02X%02X", red, green, blue)
        #else
        return nil
        #endif
    }
}

final class ClipboardCategoryManager {
    static let maxCustomCategoriesPerRecord = 3
    private static let customSortOrderBase: Int32 = 1000

    static func bootstrapSystemCategories(context: NSManagedObjectContext) {
        context.performAndWait {
            do {
                for definition in SystemClipboardCategoryDefinition.all {
                    let request = NSFetchRequest<ClipboardCategory>(entityName: "ClipboardCategory")
                    request.fetchLimit = 1
                    request.predicate = NSPredicate(format: "systemKey == %@", definition.key.rawValue)

                    let category = try context.fetch(request).first ?? ClipboardCategory(context: context)
                    let isNew = category.id == nil
                    if isNew {
                        category.id = UUID()
                        category.createdAt = Date()
                    }
                    category.name = category.name?.isEmpty == false ? category.name : definition.localizedName
                    category.iconName = category.iconName?.isEmpty == false ? category.iconName : definition.iconName
                    category.colorHex = category.colorHex?.isEmpty == false ? category.colorHex : definition.colorHex
                    category.typeRaw = ClipboardCategoryType.system.rawValue
                    category.systemKey = definition.key.rawValue
                    if isNew {
                        category.isVisible = definition.defaultVisible
                        category.sortOrder = definition.sortOrder
                    }
                    category.updatedAt = Date()
                }

                normalizeCustomCategorySortOrders(context: context)
                try context.save()
            } catch {
                NSLog("Failed to bootstrap clipboard categories: \(error.localizedDescription)")
            }
        }
    }

    static func resetSystemCategories(context: NSManagedObjectContext) {
        context.performAndWait {
            do {
                for definition in SystemClipboardCategoryDefinition.all {
                    let request = NSFetchRequest<ClipboardCategory>(entityName: "ClipboardCategory")
                    request.fetchLimit = 1
                    request.predicate = NSPredicate(format: "systemKey == %@", definition.key.rawValue)

                    guard let category = try context.fetch(request).first else { continue }
                    category.name = definition.localizedName
                    category.iconName = definition.iconName
                    category.colorHex = definition.colorHex
                    category.isVisible = definition.defaultVisible
                    category.sortOrder = definition.sortOrder
                    category.updatedAt = Date()
                }

                try context.save()
            } catch {
                NSLog("Failed to reset system categories: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    static func createCustomCategory(
        name: String,
        iconName: String,
        colorHex: String,
        context: NSManagedObjectContext
    ) -> ClipboardCategory? {
        var result: ClipboardCategory?

        context.performAndWait {
            let category = ClipboardCategory(context: context)
            category.id = UUID()
            category.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            category.iconName = iconName
            category.colorHex = colorHex
            category.typeRaw = ClipboardCategoryType.custom.rawValue
            category.systemKey = nil
            category.isVisible = true
            category.sortOrder = nextCustomSortOrder(context: context)
            category.createdAt = Date()
            category.updatedAt = Date()

            do {
                try context.save()
                result = category
            } catch {
                NSLog("Failed to create custom category: \(error.localizedDescription)")
            }
        }

        return result
    }

    static func update(
        _ category: ClipboardCategory,
        name: String,
        iconName: String,
        colorHex: String,
        isVisible: Bool,
        context: NSManagedObjectContext
    ) {
        context.performAndWait {
            category.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            category.iconName = iconName
            category.colorHex = colorHex
            category.isVisible = isVisible
            category.updatedAt = Date()

            do {
                try context.save()
            } catch {
                NSLog("Failed to update clipboard category: \(error.localizedDescription)")
            }
        }
    }

    static func toggleVisibility(_ category: ClipboardCategory, context: NSManagedObjectContext) {
        guard category.categoryType != .system || category.systemCategoryKey != .all else {
            return
        }

        context.performAndWait {
            category.isVisible.toggle()
            category.updatedAt = Date()

            do {
                try context.save()
            } catch {
                NSLog("Failed to toggle clipboard category visibility: \(error.localizedDescription)")
            }
        }
    }

    static func canAssign(record: ClipboardRecord, to category: ClipboardCategory, context: NSManagedObjectContext) -> Bool {
        guard category.categoryType == .custom else { return false }

        return context.performAndWait {
            if record.hasCategory(category) {
                return true
            }

            return customCategoryCount(for: record) < maxCustomCategoriesPerRecord
        }
    }

    static func canAssignAdditionalCategory(record: ClipboardRecord, context: NSManagedObjectContext) -> Bool {
        context.performAndWait {
            customCategoryCount(for: record) < maxCustomCategoriesPerRecord
        }
    }

    static func deleteCustomCategory(_ category: ClipboardCategory, context: NSManagedObjectContext) {
        guard category.categoryType == .custom else { return }

        context.performAndWait {
            let request = NSFetchRequest<ClipboardRecordCategory>(entityName: "ClipboardRecordCategory")
            request.predicate = NSPredicate(format: "category == %@", category)

            if let links = try? context.fetch(request) {
                links.forEach { context.delete($0) }
            }

            context.delete(category)

            do {
                try context.save()
            } catch {
                NSLog("Failed to delete custom category: \(error.localizedDescription)")
            }
        }
    }

    static func assign(record: ClipboardRecord, to category: ClipboardCategory, context: NSManagedObjectContext) {
        guard category.categoryType == .custom else { return }

        context.performAndWait {
            let request = NSFetchRequest<ClipboardRecordCategory>(entityName: "ClipboardRecordCategory")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "record == %@ AND category == %@", record, category)

            if (try? context.fetch(request).first) != nil {
                return
            }

            guard customCategoryCount(for: record) < maxCustomCategoriesPerRecord else {
                return
            }

            let link = ClipboardRecordCategory(context: context)
            link.id = UUID()
            link.record = record
            link.category = category
            link.createdAt = Date()
            record.updatedAt = Date()

            do {
                try context.save()
            } catch {
                NSLog("Failed to assign clipboard category: \(error.localizedDescription)")
            }
        }
    }

    static func remove(record: ClipboardRecord, from category: ClipboardCategory, context: NSManagedObjectContext) {
        context.performAndWait {
            let request = NSFetchRequest<ClipboardRecordCategory>(entityName: "ClipboardRecordCategory")
            request.predicate = NSPredicate(format: "record == %@ AND category == %@", record, category)

            if let links = try? context.fetch(request) {
                links.forEach { context.delete($0) }
            }

            record.updatedAt = Date()

            do {
                try context.save()
            } catch {
                NSLog("Failed to remove clipboard category: \(error.localizedDescription)")
            }
        }
    }

    static func toggle(record: ClipboardRecord, category: ClipboardCategory, context: NSManagedObjectContext) {
        if record.hasCategory(category) {
            remove(record: record, from: category, context: context)
        } else {
            assign(record: record, to: category, context: context)
        }
    }

    static func fetchCategories(context: NSManagedObjectContext, type: ClipboardCategoryType? = nil) -> [ClipboardCategory] {
        let request = NSFetchRequest<ClipboardCategory>(entityName: "ClipboardCategory")
        var predicates: [NSPredicate] = []

        if let type {
            predicates.append(NSPredicate(format: "typeRaw == %@", type.rawValue))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]

        return (try? context.fetch(request)) ?? []
    }

    static func category(for selection: ClipboardCategorySelection, context: NSManagedObjectContext) -> ClipboardCategory? {
        let request = NSFetchRequest<ClipboardCategory>(entityName: "ClipboardCategory")
        request.fetchLimit = 1

        switch selection {
        case .system(let key):
            request.predicate = NSPredicate(format: "systemKey == %@", key.rawValue)
        case .custom(let id):
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        }

        return try? context.fetch(request).first
    }

    private static func nextCustomSortOrder(context: NSManagedObjectContext) -> Int32 {
        let request = NSFetchRequest<ClipboardCategory>(entityName: "ClipboardCategory")

        request.predicate = NSPredicate(format: "typeRaw == %@", ClipboardCategoryType.custom.rawValue)

        let values = (try? context.fetch(request)) ?? []
        let maxValue = max(values.map(\.sortOrder).max() ?? (customSortOrderBase - 10), customSortOrderBase - 10)
        return maxValue + 10
    }

    static func saveOrderedCategories(
        _ categories: [ClipboardCategory],
        startingAt sortOrder: Int32,
        context: NSManagedObjectContext
    ) {
        context.performAndWait {
            for (index, category) in categories.enumerated() {
                category.sortOrder = sortOrder + Int32(index * 10)
                category.updatedAt = Date()
            }

            do {
                try context.save()
            } catch {
                NSLog("Failed to save ordered clipboard categories: \(error.localizedDescription)")
            }
        }
    }

    private static func normalizeCustomCategorySortOrders(context: NSManagedObjectContext) {
        let request = NSFetchRequest<ClipboardCategory>(entityName: "ClipboardCategory")
        request.predicate = NSPredicate(format: "typeRaw == %@", ClipboardCategoryType.custom.rawValue)
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]

        let categories = (try? context.fetch(request)) ?? []
        guard !categories.isEmpty else { return }

        var needsNormalization = false
        for (index, category) in categories.enumerated() {
            let expected = customSortOrderBase + Int32(index * 10)
            if category.sortOrder != expected {
                category.sortOrder = expected
                category.updatedAt = Date()
                needsNormalization = true
            }
        }

        guard needsNormalization else { return }
    }

    private static func customCategoryCount(for record: ClipboardRecord) -> Int {
        record.customCategories.count
    }
}
