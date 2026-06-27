//
//  ClipboardHistoryViews.swift
//  ClipDock
//

import SwiftUI
import CoreData
import AppKit

struct ClipboardHistorySidebar: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var searchText: String
    @Binding var categorySelection: ClipboardCategorySelection
    let activeSelection: ClipboardCategorySelection
    let records: FetchedResults<ClipboardRecord>
    @Binding var selectedRecordID: NSManagedObjectID?
    @Binding var searchFieldFocused: Bool
    let layout: SimpleClipboardLayout
    let onCopy: (ClipboardRecord) -> Void
    let onDelete: (ClipboardRecord) -> Void
    let onTogglePin: (ClipboardRecord) -> Void
    let onOpenSettings: () -> Void
    @FocusState private var isSearchFieldFocused: Bool
    @State private var categoryAssignmentTarget: CategoryAssignmentTarget?
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
    )
    private var categories: FetchedResults<ClipboardCategory>

    var body: some View {
        let sections = groupedSections

        VStack(alignment: .leading, spacing: layout.sidebarSpacing) {
            HStack(spacing: 10) {
                searchField
                settingsButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.chipSpacing) {
                    ForEach(visibleCategoryEntries) { option in
                        Button {
                            categorySelection = option.selection
                        } label: {
                            SimpleFilterChip(
                                title: option.title,
                                symbolName: option.symbolName,
                                accentColor: option.accentColor,
                                isSelected: option.selection == activeSelection,
                                layout: layout
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 2)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: layout.rowSpacing) {
                    ForEach(sections) { section in
                        LazyVStack(alignment: .leading, spacing: layout.rowSpacing) {
                            HStack(spacing: 0) {
                                Text(verbatim: section.title)
                                    .font(.system(size: layout.sectionLabelSize, weight: .medium))
                                    .foregroundColor(Color.black.opacity(0.54))

                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 2)
                                .padding(.top, section.topPadding)
                            .zIndex(1)

                            LazyVStack(spacing: layout.rowSpacing) {
                                ForEach(section.records, id: \.objectID) { record in
                                    ClipboardHistoryRow(
                                        record: record,
                                        isSelected: selectedRecordID == record.objectID,
                                        layout: layout,
                                        onSelect: {
                                            selectedRecordID = record.objectID
                                        },
                                        onCopy: {
                                            onCopy(record)
                                        },
                                        onDelete: {
                                            onDelete(record)
                                        },
                                        onTogglePin: {
                                            onTogglePin(record)
                                        },
                                        onManageCategories: {
                                            categoryAssignmentTarget = CategoryAssignmentTarget(objectID: record.objectID)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.trailing, 2)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green.opacity(0.78))
                    .frame(width: 8, height: 8)
                Text(localizer.text(.clipsCount, records.count))
                    .font(.system(size: layout.footerSize))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(layout.sidebarPadding)
        .onAppear {
            ClipboardCategoryManager.bootstrapSystemCategories(context: viewContext)
        }
        .sheet(item: $categoryAssignmentTarget) { target in
            if let record = viewContext.object(with: target.objectID) as? ClipboardRecord {
                ClipboardCategoryAssignmentView(record: record)
            }
        }
    }

    private var visibleCategoryEntries: [CategoryChipEntry] {
        let visibleSystem = categories
            .filter { $0.categoryType == .system && ($0.isVisible || $0.systemCategoryKey == .all) }
            .compactMap { category -> CategoryChipEntry? in
                guard let selection = category.selection else { return nil }
                return CategoryChipEntry(
                    selection: selection,
                    title: category.resolvedName,
                    symbolName: category.resolvedIconName,
                    accentColor: category.swiftUIColor
                )
            }

        let visibleCustom = categories
            .filter { $0.categoryType == .custom && $0.isVisible }
            .compactMap { category -> CategoryChipEntry? in
                guard let selection = category.selection else { return nil }
                return CategoryChipEntry(
                    selection: selection,
                    title: category.resolvedName,
                    symbolName: category.resolvedIconName,
                    accentColor: category.swiftUIColor
                )
            }

        return visibleSystem + visibleCustom
    }

    private var groupedSections: [ClipboardHistorySection] {
        let calendar = Calendar.current
        let pinnedRecords = records.filter(\.isPinned)
        let unpinnedRecords = records.filter { !$0.isPinned }
        let dayKeys = Dictionary(grouping: unpinnedRecords, by: { calendar.startOfDay(for: $0.createdAt ?? Date()) })
        let sortedDays = dayKeys.keys.sorted(by: >)

        var sections: [ClipboardHistorySection] = []

        if !pinnedRecords.isEmpty {
            sections.append(
                ClipboardHistorySection(
                    id: .distantFuture,
                    title: localizer.text(.pinned),
                    records: pinnedRecords,
                    topPadding: 0
                )
            )
        }

        sections.append(contentsOf: sortedDays.map { day in
            let sectionRecords = dayKeys[day] ?? []

            return ClipboardHistorySection(
                id: day,
                title: historySectionTitle(for: day),
                records: sectionRecords,
                topPadding: sections.isEmpty && calendar.isDate(day, equalTo: sortedDays.first ?? day, toGranularity: .day) ? 0 : layout.rowSpacing
            )
        })

        return sections
    }

    private func historySectionTitle(for day: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(day) {
            return localizer.text(.today)
        }

        if calendar.isDateInYesterday(day) {
            return localizer.text(.yesterday)
        }

        return Self.sectionDateFormatter.string(from: day)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: layout.searchIconSize, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(localizer.text(.searchClipboard), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: layout.searchTextSize))
                .focused($isSearchFieldFocused)
                .onAppear {
                    searchFieldFocused = isSearchFieldFocused
                }
                .onChange(of: isSearchFieldFocused) { newValue in
                    searchFieldFocused = newValue
                }

            Spacer(minLength: 0)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, layout.searchPaddingX)
        .frame(maxWidth: .infinity)
        .frame(height: layout.searchHeight)
        .background(
            RoundedRectangle(cornerRadius: layout.searchCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.26))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.searchCornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.07), lineWidth: 1)
                )
        )
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: layout.searchHintSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: layout.searchHeight, height: layout.searchHeight)
                .background(
                    RoundedRectangle(cornerRadius: layout.searchCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: layout.searchCornerRadius, style: .continuous)
                                .stroke(Color.black.opacity(0.07), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(localizer.text(.settings))
    }

    private struct ClipboardHistorySection: Identifiable {
        let id: Date
        let title: String
        let records: [ClipboardRecord]
        let topPadding: CGFloat
    }

    private struct CategoryChipEntry: Identifiable {
        let selection: ClipboardCategorySelection
        let title: String
        let symbolName: String
        let accentColor: Color

        var id: String { selection.id }
    }

    private struct CategoryAssignmentTarget: Identifiable {
        let objectID: NSManagedObjectID
        var id: NSManagedObjectID { objectID }
    }

    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

}

struct ClipboardHistoryRow: View {
    @Environment(\.appLocalizer) private var localizer
    let record: ClipboardRecord
    let isSelected: Bool
    let layout: SimpleClipboardLayout
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onManageCategories: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: onSelect) {
                rowContent
                .padding(.horizontal, layout.rowPaddingX)
                .padding(.vertical, layout.rowPaddingY)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: layout.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                onSelect()
                onCopy()
            })
            .contextMenu {
                Button {
                    onCopy()
                } label: {
                    Label(localizer.text(.copy), systemImage: "doc.on.doc")
                }

                Button {
                    onTogglePin()
                } label: {
                    Label(record.isPinned ? localizer.text(.unpin) : localizer.text(.pin), systemImage: record.isPinned ? "pin.slash" : "pin")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(localizer.text(.delete), systemImage: "trash")
                }

                Divider()

                ClipboardCategoryRecordMenu(record: record, onManageCategories: onManageCategories)
            }

            Button(action: onTogglePin) {
                Image(systemName: record.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: layout.rowActionIconSize, weight: .semibold))
                    .foregroundStyle(record.isPinned ? record.kind.accent : .secondary)
                    .frame(width: layout.rowActionSize, height: layout.rowActionSize)
                    .padding(.trailing, layout.rowPaddingX)
            }
            .buttonStyle(.plain)
            .padding(.top, layout.rowPaddingY + 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .circular)
                .fill(isSelected ? Color(red: 0.91, green: 0.95, blue: 1.0).opacity(0.64) : Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .circular)
                        .strokeBorder(
                            isSelected ? Color(red: 0.24, green: 0.54, blue: 0.99).opacity(0.88) : Color.black.opacity(0.05),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.06) : .clear, radius: 8, x: 0, y: 3)
    }

    @ViewBuilder
    private var rowContent: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: layout.rowContentGap) {
                kindBadge
                rowTextColumn
                rowPreview
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            footerRow
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, layout.badgeSize + layout.rowContentGap)
                .padding(.bottom, 0)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var rowTextColumn: some View {
        VStack(alignment: .leading, spacing: layout.rowTextSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.previewTitle)
                    .font(.system(size: layout.rowTitleSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(record.rowSubtitle)
                    .font(.system(size: layout.rowSubtitleSize))
                    .foregroundStyle(record.kind == .link ? record.kind.accent : .secondary)
                    .lineLimit(1)
            }

            if !record.customCategories.isEmpty {
                ClipboardCategoryBadgeStrip(categories: record.customCategories)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 8) {
                sourceAppIcon(size: layout.rowActionSize)

                Text(record.sourceAppDisplayName)
                    .font(.system(size: layout.rowMetaSize + 1, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Text(record.historyRowTimeLabel)
                    .font(.system(size: layout.rowMetaSize + 1))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: layout.rowTimeWidth, alignment: .trailing)

                HStack(spacing: 4) {
                    if record.kind == .files {
                        fileTypeBadgeIcon
                    } else {
                        Image(systemName: record.kind.symbolName)
                            .font(.system(size: layout.rowTagSize, weight: .semibold))
                            .foregroundStyle(record.kind.accent)

                        Text(record.kind.title)
                            .font(.system(size: layout.rowTagSize, weight: .medium))
                            .foregroundStyle(record.kind.accent)
                            .lineLimit(1)
                    }
                }
                .frame(width: layout.rowKindWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var rowPreview: some View {
        if record.kind == .image, let preview = record.previewImage {
            imageThumbnail(preview)
        } else if record.kind == .link, let icon = record.websiteIconImage {
            websiteThumbnail(icon)
        } else if record.kind == .code {
            RoundedRectangle(cornerRadius: layout.rowImagePreviewCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .overlay(
                    Image(systemName: "curlybraces")
                        .font(.system(size: layout.rowFileIconSize + 4, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
                .frame(width: layout.rowImagePreviewWidth, height: layout.rowImagePreviewHeight)
        } else if record.kind == .files {
            fileThumbnail
        } else if record.kind == .colors, let color = record.clipboardColorValue {
            colorThumbnail(color)
        }
    }

    private func websiteThumbnail(_ icon: NSImage) -> some View {
        RoundedRectangle(cornerRadius: layout.rowImagePreviewCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .overlay(
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(layout.rowImagePreviewWidth * 0.18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: layout.rowImagePreviewCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .frame(width: layout.rowImagePreviewWidth, height: layout.rowImagePreviewHeight)
    }

    private func colorThumbnail(_ color: ClipboardColorValue) -> some View {
        RoundedRectangle(cornerRadius: layout.rowImagePreviewCornerRadius, style: .continuous)
            .fill(color.color)
            .overlay(
                RoundedRectangle(cornerRadius: layout.rowImagePreviewCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .frame(width: layout.rowImagePreviewWidth, height: layout.rowImagePreviewHeight)
    }

    private func imageThumbnail(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: layout.rowImagePreviewWidth, height: layout.rowImagePreviewHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: layout.rowImagePreviewCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: layout.rowImagePreviewCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
    }

    private var fileThumbnail: some View {
        RoundedRectangle(cornerRadius: layout.rowFilePreviewCornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.18))
            .overlay(
                Group {
                    if let icon = record.fileIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: layout.rowImagePreviewWidth * 0.62, height: layout.rowImagePreviewHeight * 0.62)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc")
                                .font(.system(size: layout.rowFileIconSize, weight: .regular))
                                .foregroundStyle(.secondary.opacity(0.82))

                            Text(record.kind.title.uppercased())
                                .font(.system(size: layout.rowTagSize, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            )
            .frame(width: layout.rowImagePreviewWidth, height: layout.rowImagePreviewHeight)
    }

    @ViewBuilder
    private var fileTypeBadgeIcon: some View {
        if let icon = record.fileIconImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: layout.rowTagSize + 4, height: layout.rowTagSize + 4)
        } else {
            Image(systemName: "doc")
                .font(.system(size: layout.rowTagSize, weight: .semibold))
                .foregroundStyle(record.kind.accent)
        }
    }

    private var kindBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: layout.badgeCornerRadius, style: .continuous)
                .fill(record.kind.accent.opacity(0.12))
            Image(systemName: record.kind.symbolName)
                .font(.system(size: layout.badgeIconSize, weight: .semibold))
                .foregroundStyle(record.kind.accent)
        }
        .frame(width: layout.badgeSize, height: layout.badgeSize)
    }

    @ViewBuilder
    private func sourceAppIcon(size: CGFloat) -> some View {
        if let icon = record.sourceAppIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.25), style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: max(4, size * 0.25), style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: max(4, size * 0.25), style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                Image(systemName: record.kind == .link ? "globe" : "app.dashed")
                    .font(.system(size: max(8, size * 0.48), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        }
    }
}
