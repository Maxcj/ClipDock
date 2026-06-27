//
//  ClipboardCategoryViews.swift
//  ClipDock
//

import SwiftUI
import CoreData
import AppKit
import UniformTypeIdentifiers

private enum CategoryPresetPalette {
    static let iconNames: [String] = [
        "folder",
        "tag",
        "star",
        "briefcase",
        "paintpalette",
        "terminal",
        "curlybraces",
        "link",
        "doc",
        "bookmark",
        "flag",
        "bolt",
        "heart"
    ]

    static let colors: [(name: String, hex: String)] = [
        ("Red", "#F43F5E"),
        ("Orange", "#F97316"),
        ("Yellow", "#F59E0B"),
        ("Green", "#10B981"),
        ("Blue", "#3B82F6"),
        ("Purple", "#8B5CF6"),
        ("Pink", "#EC4899")
    ]
}

private struct SettingsActionButtonStyle: ButtonStyle {
    enum Kind {
        case neutral
        case accent
        case destructive
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        let foreground: Color
        let background: Color

        switch kind {
        case .neutral:
            foreground = .primary
            background = Color.white.opacity(configuration.isPressed ? 0.56 : 0.80)
        case .accent:
            foreground = .white
            background = Color.accentColor.opacity(configuration.isPressed ? 0.76 : 1.0)
        case .destructive:
            foreground = .white
            background = Color(red: 0.96, green: 0.27, blue: 0.22).opacity(configuration.isPressed ? 0.82 : 1.0)
        }

        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(kind == .accent ? 0.0 : 0.08), lineWidth: 1)
            )
    }
}

private struct CategoryInlineActionButtonStyle: ButtonStyle {
    enum Kind {
        case accent
        case destructive
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        let background: Color = {
            switch kind {
            case .accent:
                return Color.accentColor.opacity(configuration.isPressed ? 0.92 : 0.12)
            case .destructive:
                return Color(red: 0.96, green: 0.27, blue: 0.22).opacity(configuration.isPressed ? 0.90 : 0.12)
            }
        }()

        let foreground: Color = {
            switch kind {
            case .accent:
                return configuration.isPressed ? .white : .accentColor
            case .destructive:
                return configuration.isPressed ? .white : Color(red: 0.96, green: 0.27, blue: 0.22)
            }
        }()

        configuration.label
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        (kind == .accent ? Color.accentColor : Color(red: 0.96, green: 0.27, blue: 0.22))
                            .opacity(configuration.isPressed ? 0.0 : 0.12),
                        lineWidth: 1
                    )
            )
    }
}

struct ClipboardCategorySettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appLocalizer) private var localizer

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
    )
    private var categories: FetchedResults<ClipboardCategory>

    @State private var showingCreateSheet = false
    @State private var editingCategory: ClipboardCategory?
    @State private var deleteCategory: ClipboardCategory?
    @State private var showResetAlert = false
    @State private var draggedCategoryID: UUID?
    @State private var orderedCategories: [ClipboardCategory] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            categoriesSection
            resetButtonRow
        }
        .onAppear {
            ClipboardCategoryManager.bootstrapSystemCategories(context: viewContext)
            syncOrderedCategories()
        }
        .onChange(of: categoryOrderingSignature) { _ in
            syncOrderedCategories()
        }
        .sheet(isPresented: $showingCreateSheet) {
            ClipboardCategoryEditorView(category: nil)
        }
        .sheet(item: $editingCategory) { category in
            ClipboardCategoryEditorView(category: category)
        }
        .alert(localizer.text(.deleteCategoryTitle), isPresented: Binding(
            get: { deleteCategory != nil },
            set: { if !$0 { deleteCategory = nil } }
        )) {
            Button(localizer.text(.delete), role: .destructive) {
                if let deleteCategory {
                    ClipboardCategoryManager.deleteCustomCategory(deleteCategory, context: viewContext)
                }
                deleteCategory = nil
            }
            Button(localizer.text(.cancel), role: .cancel) {
                deleteCategory = nil
            }
        } message: {
            Text(localizer.text(.deleteCategoryMessage))
        }
        .alert(localizer.text(.resetSystemCategories), isPresented: $showResetAlert) {
            Button(localizer.text(.reset), role: .destructive) {
                ClipboardCategoryManager.resetSystemCategories(context: viewContext)
            }
            Button(localizer.text(.cancel), role: .cancel) {}
        } message: {
            Text(localizer.text(.resetSystemCategoriesMessage))
        }
    }

    private var categoriesSection: some View {
        settingsSection(title: localizer.text(.categories)) {
            VStack(spacing: 0) {
                categoryRows
                Divider().padding(.leading, 56)
                addCategoryButton
            }
        }
    }

    @ViewBuilder
    private var categoryRows: some View {
        if orderedCategories.isEmpty {
            ClipboardCategoryEmptyRow(
                title: localizer.text(.noCustomCategories),
                subtitle: localizer.text(.noCustomCategoriesSubtitle)
            )
        } else {
            ForEach(orderedCategories, id: \.objectID) { category in
                categoryRow(category)
            }
        }
    }

    private var categoryOrderingSignature: String {
        categories
            .map { category in
                "\(category.objectID.uriRepresentation().absoluteString):\(category.sortOrder):\(category.typeRaw ?? "")"
            }
            .joined(separator: "|")
    }

    private func syncOrderedCategories() {
        orderedCategories = Array(categories).sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }

    private func categoryRow(_ category: ClipboardCategory) -> some View {
        let canReorder = category.systemCategoryKey != .all

        return ClipboardCategoryRow(
            category: category,
            canEdit: category.categoryType == .custom,
            canDelete: category.categoryType == .custom,
            onToggleVisibility: {
                ClipboardCategoryManager.toggleVisibility(category, context: viewContext)
            },
            onEdit: {
                editingCategory = category
            },
            onDelete: {
                deleteCategory = category
            }
        )
        .opacity(draggedCategoryID == category.id ? 0.72 : 1.0)
        .contentShape(Rectangle())
        .onDrag {
            guard canReorder, let id = category.id else {
                return NSItemProvider()
            }

            draggedCategoryID = id
            return NSItemProvider(object: id.uuidString as NSString)
        } preview: {
            ClipboardCategoryRowDragPreview(category: category)
        }
        .onDrop(
            of: [UTType.text.identifier],
            delegate: ClipboardCategoryReorderDropDelegate(
                target: category,
                categories: $orderedCategories,
                draggedCategoryID: $draggedCategoryID,
                context: viewContext
            )
        )
    }

    private var addCategoryButton: some View {
        Button {
            showingCreateSheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.text(.addCategory))
                        .font(.system(size: 13, weight: .regular))
                    Text(localizer.text(.addCategorySubtitle))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var resetButtonRow: some View {
        HStack(spacing: 10) {
            Button(localizer.text(.resetSystemCategories)) {
                showResetAlert = true
            }
            .buttonStyle(SettingsSecondaryButtonStyle())

            Spacer(minLength: 0)
        }
    }

}

struct ClipboardCategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appLocalizer) private var localizer

    let category: ClipboardCategory?
    @State private var name: String = ""
    @State private var iconName: String = "tag"
    @State private var colorHex: String = "#3B82F6"
    @State private var selectedColor: Color = Color(hex: "#3B82F6") ?? .accentColor
    @State private var isVisible = true
    @State private var showingCustomColorSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(category == nil ? localizer.text(.addCategory) : localizer.text(.editCategory))
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                TextField(localizer.text(.categoryNamePlaceholder), text: $name)
                    .textFieldStyle(.roundedBorder)

                Toggle(localizer.text(.visible), isOn: $isVisible)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(localizer.text(.icon))
                    .font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 10)], spacing: 10) {
                    ForEach(CategoryPresetPalette.iconNames, id: \.self) { symbol in
                        Button {
                            iconName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 42, height: 36)
                                .foregroundStyle(iconName == symbol ? Color.white : Color.primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(iconName == symbol ? Color.accentColor : Color.black.opacity(0.04))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(localizer.text(.color))
                    .font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 10)], spacing: 10) {
                    ForEach(CategoryPresetPalette.colors, id: \.hex) { color in
                        Button {
                            colorHex = color.hex
                            selectedColor = Color(hex: color.hex) ?? selectedColor
                        } label: {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: color.hex) ?? .secondary)
                                .frame(width: 42, height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(colorHex == color.hex ? Color.primary.opacity(0.75) : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(color.name)
                    }

                    Button {
                        showingCustomColorSheet = true
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(customColorTileFill)
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(customColorTileStroke, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            Image(systemName: "eyedropper.full")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(customColorTileForeground)
                        }
                        .frame(width: 42, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(localizer.text(.color))
                }
            }

            HStack {
                Spacer(minLength: 0)
                Button(localizer.text(.cancel)) {
                    dismiss()
                }
                .buttonStyle(SettingsActionButtonStyle(kind: .neutral))
                .frame(minWidth: 72)

                Button(localizer.text(.save)) {
                    saveCategory()
                }
                .buttonStyle(SettingsActionButtonStyle(kind: .accent))
                .frame(minWidth: 72)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            if let category {
                name = category.name ?? category.resolvedName
                iconName = category.iconName ?? category.resolvedIconName
                colorHex = category.colorHex ?? category.resolvedColorHex
                selectedColor = Color(hex: colorHex) ?? .accentColor
                isVisible = category.isVisible
            } else {
                name = ""
                iconName = "tag"
                colorHex = "#3B82F6"
                selectedColor = Color(hex: colorHex) ?? .accentColor
                isVisible = true
            }
        }
        .sheet(isPresented: $showingCustomColorSheet) {
            ClipboardCategoryCustomColorSheetView(
                initialColor: selectedColor,
                onSave: { newColor in
                    selectedColor = newColor
                    if let hex = newColor.hexString {
                        colorHex = hex
                    }
                    showingCustomColorSheet = false
                },
                onCancel: {
                    showingCustomColorSheet = false
                }
            )
            }
        }

    private func saveCategory() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let category {
            ClipboardCategoryManager.update(
                category,
                name: trimmedName,
                iconName: iconName,
                colorHex: colorHex,
                isVisible: isVisible,
                context: viewContext
            )
        } else {
            _ = ClipboardCategoryManager.createCustomCategory(
                name: trimmedName,
                iconName: iconName,
                colorHex: colorHex,
                context: viewContext
            )
        }

        dismiss()
    }

    private var customColorTileFill: Color {
        if let selectedPreset = CategoryPresetPalette.colors.first(where: { $0.hex == colorHex }) {
            return Color(hex: selectedPreset.hex) ?? Color.black.opacity(0.04)
        }

        return selectedColor.opacity(0.18)
    }

    private var customColorTileStroke: Color {
        if CategoryPresetPalette.colors.contains(where: { $0.hex == colorHex }) {
            return Color.black.opacity(0.08)
        }
        return selectedColor.opacity(0.75)
    }

    private var customColorTileForeground: Color {
        if CategoryPresetPalette.colors.contains(where: { $0.hex == colorHex }) {
            return .secondary
        }
        return selectedColor
    }
}

private struct ClipboardCategoryCustomColorSheetView: View {
    let initialColor: Color
    let onSave: (Color) -> Void
    let onCancel: () -> Void
    @State private var draftColor: Color

    init(initialColor: Color, onSave: @escaping (Color) -> Void, onCancel: @escaping () -> Void) {
        self.initialColor = initialColor
        self.onSave = onSave
        self.onCancel = onCancel
        _draftColor = State(initialValue: initialColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(AppLocalizer.current.text(.color))
                .font(.system(size: 18, weight: .semibold))

            ColorPicker("", selection: $draftColor, supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)

                Button(AppLocalizer.current.text(.cancel)) {
                    onCancel()
                }
                .buttonStyle(SettingsActionButtonStyle(kind: .neutral))
                .frame(minWidth: 72)

                Button(AppLocalizer.current.text(.save)) {
                    onSave(draftColor)
                }
                .buttonStyle(SettingsActionButtonStyle(kind: .accent))
                .frame(minWidth: 72)
            }
        }
        .padding(22)
        .frame(width: 360)
    }
}

struct ClipboardCategoryAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appLocalizer) private var localizer

    let record: ClipboardRecord
    @State private var showingCreateSheet = false

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        predicate: NSPredicate(format: "typeRaw == %@", ClipboardCategoryType.custom.rawValue)
    )
    private var customCategories: FetchedResults<ClipboardCategory>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(localizer.text(.assignToCategory))
                    .font(.system(size: 18, weight: .semibold))
                Spacer(minLength: 0)
                Button(localizer.text(.done)) {
                    dismiss()
                }
                .buttonStyle(SettingsActionButtonStyle(kind: .neutral))
            }

            if customCategories.isEmpty {
                ClipboardCategoryEmptyRow(
                    title: localizer.text(.noCustomCategories),
                    subtitle: localizer.text(.noCustomCategoriesSubtitle)
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(customCategories) { category in
                            Button {
                                ClipboardCategoryManager.toggle(record: record, category: category, context: viewContext)
                            } label: {
                                ClipboardCategoryAssignmentRow(
                                    category: category,
                                    isSelected: record.hasCategory(category)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!record.hasCategory(category) && !ClipboardCategoryManager.canAssign(record: record, to: category, context: viewContext))

                            if category != customCategories.last {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            HStack {
                Button {
                    showingCreateSheet = true
                } label: {
                    Label(localizer.text(.addCategory), systemImage: "plus")
                }
                .buttonStyle(SettingsActionButtonStyle(kind: .neutral))

                Spacer(minLength: 0)
            }

            Text(localizer.text(.categoryLimitHint, ClipboardCategoryManager.maxCustomCategoriesPerRecord))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420, height: 420)
        .sheet(isPresented: $showingCreateSheet) {
            ClipboardCategoryEditorView(category: nil)
        }
    }
}

struct ClipboardCategoryRecordMenu: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.managedObjectContext) private var viewContext

    let record: ClipboardRecord
    let onManageCategories: () -> Void

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        predicate: NSPredicate(format: "typeRaw == %@", ClipboardCategoryType.custom.rawValue)
    )
    private var customCategories: FetchedResults<ClipboardCategory>

    var body: some View {
        Menu(localizer.text(.addToCategory)) {
            if customCategories.isEmpty {
                Button(localizer.text(.newCategory)) {
                    onManageCategories()
                }
            } else {
                ForEach(customCategories) { category in
                    Button {
                        ClipboardCategoryManager.toggle(record: record, category: category, context: viewContext)
                    } label: {
                        HStack {
                            Image(systemName: category.resolvedIconName)
                            Text(category.resolvedName)
                            Spacer(minLength: 0)
                            if record.hasCategory(category) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(!record.hasCategory(category) && !ClipboardCategoryManager.canAssignAdditionalCategory(record: record, context: viewContext))
                }

                Divider()

                Button(localizer.text(.manageCategories)) {
                    onManageCategories()
                }
            }
        }
    }
}

struct ClipboardCategoryBadgeStrip: View {
    let categories: [ClipboardCategory]
    let maxCount: Int = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(categories.prefix(maxCount))) { category in
                Text(category.resolvedName)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(category.swiftUIColor.opacity(0.12))
                    .foregroundStyle(category.swiftUIColor)
                    .clipShape(Capsule())
            }
        }
    }
}

private struct ClipboardCategoryRow: View {
    let category: ClipboardCategory
    let canEdit: Bool
    let canDelete: Bool
    let onToggleVisibility: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            reorderHandle

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(category.swiftUIColor.opacity(0.12))
                Image(systemName: category.resolvedIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(category.swiftUIColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.resolvedName)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)

                    if category.categoryType == .system {
                        Text(localizerText(.systemDefaultBadge))
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.secondary)
                            .background(Color.secondary.opacity(0.10))
                            .clipShape(Capsule())
                            .accessibilityHidden(true)
                    }
                }
            }

            Spacer(minLength: 0)

            if canEdit || canDelete {
                HStack(spacing: 6) {
                    if canEdit {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(CategoryInlineActionButtonStyle(kind: .accent))
                        .accessibilityLabel(localizerText(.edit))
                    }

                    if canDelete {
                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(CategoryInlineActionButtonStyle(kind: .destructive))
                        .accessibilityLabel(localizerText(.delete))
                    }
                }
            }

            Toggle("", isOn: Binding(
                get: { category.isVisible },
                set: { _ in onToggleVisibility() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(category.systemCategoryKey == .all)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var reorderHandle: some View {
        let canReorder = category.systemCategoryKey != .all

        return ReorderHandleIcon(isEnabled: canReorder)
            .frame(width: 20, height: 20)
    }

    private func localizerText(_ key: AppTextKey) -> String {
        AppLocalizer.current.text(key)
    }
}

private struct ReorderHandleIcon: NSViewRepresentable {
    let isEnabled: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NonWindowDraggingImageView()
        view.image = NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: nil
        )
        view.contentTintColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        view.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = false
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(
            systemSymbolName: "line.3.horizontal",
            accessibilityDescription: nil
        )
        nsView.contentTintColor = isEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        nsView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
    }

    private final class NonWindowDraggingImageView: NSImageView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

private struct ClipboardCategoryRowDragPreview: View {
    let category: ClipboardCategory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(category.swiftUIColor.opacity(0.14))
                Image(systemName: category.resolvedIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(category.swiftUIColor)
            }
            .frame(width: 28, height: 28)

            Text(category.resolvedName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Toggle("", isOn: .constant(category.isVisible))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        )
    }
}

private struct ClipboardCategoryReorderDropDelegate: DropDelegate {
    let target: ClipboardCategory
    @Binding var categories: [ClipboardCategory]
    @Binding var draggedCategoryID: UUID?
    let context: NSManagedObjectContext

    func dropEntered(info: DropInfo) {
        guard
            let draggedCategoryID,
            draggedCategoryID != target.id,
            let draggedIndex = categories.firstIndex(where: { $0.id == draggedCategoryID }),
            let targetIndex = categories.firstIndex(where: { $0.id == target.id }),
            categories[draggedIndex].systemCategoryKey != .all,
            categories[targetIndex].systemCategoryKey != .all
        else {
            return
        }

        var updated = categories
        let item = updated.remove(at: draggedIndex)
        var insertIndex = targetIndex
        if draggedIndex < targetIndex {
            insertIndex -= 1
        }
        insertIndex = max(0, min(updated.count, insertIndex))
        updated.insert(item, at: insertIndex)
        categories = updated
    }

    func performDrop(info: DropInfo) -> Bool {
        ClipboardCategoryManager.saveOrderedCategories(categories, startingAt: 0, context: context)
        draggedCategoryID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

private func settingsSection<Content: View>(
    title: String,
    subtitle: String? = nil,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }

        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.38), lineWidth: 1)
                )
        )
    }
}

private struct ClipboardCategoryAssignmentRow: View {
    let category: ClipboardCategory
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.resolvedIconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(category.swiftUIColor)
                .frame(width: 20, alignment: .center)

            Text(category.resolvedName)
                .font(.system(size: 13))

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isSelected ? category.swiftUIColor.opacity(0.10) : Color.clear)
        .contentShape(Rectangle())
    }
}

private struct ClipboardCategoryEmptyRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.04))
                .overlay(
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
