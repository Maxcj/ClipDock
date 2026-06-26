//
//  LegacyDashboardViews.swift
//  ClipDock
//

import SwiftUI
import CoreData
import AppKit

struct ClipboardDashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor

    @FetchRequest private var records: FetchedResults<ClipboardRecord>

    @Binding private var filterSelection: ClipboardFilter
    @Binding private var selectedRecordID: NSManagedObjectID?
    @State private var lastSelectedImageCachePaths: [String] = []
    let activeFilter: ClipboardFilter
    let containerSize: CGSize
    private var layout: DashboardLayout { DashboardLayout(containerSize: containerSize) }

    init(searchText: String, filter: ClipboardFilter, filterSelection: Binding<ClipboardFilter>, selectedRecordID: Binding<NSManagedObjectID?>, containerSize: CGSize) {
        self.containerSize = containerSize
        self._filterSelection = filterSelection
        self._selectedRecordID = selectedRecordID
        self.activeFilter = filter
        let predicate = ClipboardRecord.fetchPredicate(searchText: searchText, filter: filter)
        let sortDescriptors: [NSSortDescriptor] = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        _records = FetchRequest(
            sortDescriptors: sortDescriptors,
            predicate: predicate,
            animation: nil
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 12)
            .overlay(
                VStack(spacing: layout.mainSectionSpacing) {
                    categoryRow

                    if let record = selectedRecord {
                        ClipboardHeroDetailPanel(
                            record: record,
                            layout: layout,
                            onCopy: { copy(record) },
                            onPaste: { copy(record) },
                            onTogglePin: { togglePin(record) },
                            onShare: { copy(record) },
                            onDelete: { delete(record) },
                            onExcludeSourceApp: {
                                excludeSourceApp(from: record)
                            }
                        )
                    }

                    cardsPanel
                }
                .padding(layout.panelPadding)
            )
        .onChange(of: records.count) { _ in
            if let selectedRecordID,
               records.first(where: { $0.objectID == selectedRecordID }) == nil {
                self.selectedRecordID = nil
            }
        }
        .onAppear {
            syncSelectedImageCachePaths()
        }
        .onChange(of: selectedRecordID) { _ in
            syncSelectedImageCachePaths()
        }
    }

    @ViewBuilder
    private var categoryRow: some View {
        HStack(spacing: layout.categorySpacing) {
            ForEach(ClipboardFilter.allCases) { option in
                Button {
                    filterSelection = option
                } label: {
                    FilterChip(
                        title: option.title,
                        symbolName: option.symbolName,
                        isSelected: option == activeFilter,
                        layout: layout
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private var cardsPanel: some View {
        VStack(alignment: .leading, spacing: layout.cardPanelSpacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: layout.cardSpacing) {
                    ForEach(displayOrderedRecords, id: \.objectID) { record in
                        ClipboardPreviewCard(
                            record: record,
                            isSelected: selectedRecordID == record.objectID,
                            layout: layout,
                            onTap: {
                                selectedRecordID = record.objectID
                            },
                            onCopy: {
                                copy(record)
                            },
                            onDelete: {
                                delete(record)
                            },
                            onTogglePin: {
                                togglePin(record)
                            }
                        )
                        .frame(width: layout.cardMinWidth, height: layout.cardHeight)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(layout.cardPanelPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.cardPanelCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.cardPanelCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var selectedRecord: ClipboardRecord? {
        if let selectedRecordID,
           let record = displayOrderedRecords.first(where: { $0.objectID == selectedRecordID }) {
            return record
        }
        return nil
    }

    private var displayOrderedRecords: [ClipboardRecord] {
        records
            .filter { !ClipboardPrivacyRules.isExcluded(bundleIdentifier: $0.sourceBundleId) }
    }

    private func copy(_ record: ClipboardRecord) {
        clipboardMonitor.copy(record)
        markUsed(record)
    }

    private func togglePin(_ record: ClipboardRecord) {
        record.isPinned.toggle()
        record.updatedAt = Date()
        saveContext()
    }

    private func delete(_ record: ClipboardRecord) {
        removeCachedAssets(for: record)
        viewContext.delete(record)
        saveContext()
        if selectedRecordID == record.objectID {
            selectedRecordID = nil
        }
    }

    private func clearAll() {
        for record in records {
            removeCachedAssets(for: record)
            viewContext.delete(record)
        }
        saveContext()
        selectedRecordID = nil
    }

    private func excludeSourceApp(from record: ClipboardRecord) {
        guard let bundleIdentifier = record.sourceBundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty else {
            return
        }

        var excluded = ClipboardPrivacyRules.bundleIdentifiers(
            from: UserDefaults.standard.string(forKey: ClipboardPrivacyRules.excludedBundleIdentifiersStorageKey) ?? ""
        )
        guard !excluded.contains(bundleIdentifier) else { return }

        excluded.append(bundleIdentifier)
        UserDefaults.standard.set(ClipboardPrivacyRules.storageValue(from: excluded), forKey: ClipboardPrivacyRules.excludedBundleIdentifiersStorageKey)

        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.predicate = NSPredicate(format: "sourceBundleId == %@", bundleIdentifier)

        if let matches = try? viewContext.fetch(request) {
            matches.forEach {
                removeCachedAssets(for: $0)
                viewContext.delete($0)
            }
            saveContext()
        }

        if selectedRecordID == record.objectID {
            selectedRecordID = nil
        }
    }

    private func markUsed(_ record: ClipboardRecord) {
        record.lastUsedAt = Date()
        record.updatedAt = Date()
        record.usageCount += 1
        saveContext()
    }

    private func syncSelectedImageCachePaths() {
        if !lastSelectedImageCachePaths.isEmpty {
            ClipboardImageCache.shared.remove(paths: lastSelectedImageCachePaths)
        }
        lastSelectedImageCachePaths = selectedRecord?.cachedImagePaths ?? []
    }

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            NSLog("Failed to save clipboard context: \(error.localizedDescription)")
        }
    }
}

struct ClipboardDetailPanel: View {
    let record: ClipboardRecord?
    let layout: DashboardLayout
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: layout.detailSpacing) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Code Snippet")
                        .font(.system(size: layout.detailTitleSize, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.35, blue: 0.86))
                    Text(record?.timeLabel ?? "No selection")
                        .font(.system(size: layout.footerFontSize))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let record {
                    Text(record.timeLabelShort)
                        .font(.system(size: layout.footerFontSize))
                        .foregroundStyle(.secondary)

                    Button {
                        onCopy()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(DetailActionButtonStyle(layout: layout))
                }
            }

            if let record {
                GeometryReader { proxy in
                    let availableWidth = proxy.size.width
                    let useHorizontal = availableWidth > 720
                    let sideWidth = useHorizontal
                        ? max(190, min(240, availableWidth * 0.23))
                        : availableWidth
                    let codeWidth = useHorizontal
                        ? max(360, availableWidth - sideWidth - layout.detailSpacing)
                        : availableWidth

                    Group {
                        if useHorizontal {
                            HStack(alignment: .top, spacing: layout.detailSpacing) {
                                ClipboardCodePane(record: record)
                                    .frame(width: codeWidth, alignment: .topLeading)
                                    .frame(minHeight: layout.codePaneMinHeight, alignment: .topLeading)

                                sideInfo(record: record)
                                    .frame(width: sideWidth, alignment: .topLeading)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: layout.detailSpacing) {
                                ClipboardCodePane(record: record)
                                    .frame(width: codeWidth, alignment: .topLeading)
                                    .frame(minHeight: layout.codePaneMinHeight, alignment: .topLeading)

                                sideInfo(record: record)
                            }
                        }
                    }
                    .frame(width: proxy.size.width, alignment: .topLeading)
                }
                .frame(minHeight: layout.codePaneMinHeight + layout.detailSpacing + 148)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No clipboard item selected")
                        .font(.headline)
                    Text("Copy something in another app and it will appear here automatically.")
                        .font(.system(size: layout.footerFontSize))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear All") { onClearAll() }
                        .buttonStyle(PrimaryActionButtonStyle(layout: layout))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(layout.detailPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.detailCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.detailCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func sideInfo(record: ClipboardRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: layout.smallCornerRadius, style: .continuous)
                        .fill(record.kind.accent.opacity(0.14))
                    if let icon = record.sourceAppIcon, record.kind == .link {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(4)
                    } else {
                        Image(systemName: record.kind.symbolName)
                            .font(.system(size: layout.iconSizeLarge, weight: .semibold))
                            .foregroundStyle(record.kind.accent)
                    }
                }
                .frame(width: layout.detailBadgeSize, height: layout.detailBadgeSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.previewTitle)
                        .font(.system(size: layout.detailBodyTitleSize, weight: .semibold))
                        .lineLimit(2)
                    Text(record.previewSubtitle)
                        .font(.system(size: layout.footerFontSize))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ActionRow(title: "Copy", icon: "doc.on.doc") {
                    onCopy()
                }
                ActionRow(title: record.isPinned ? "Pinned" : "Pin", icon: "pin") {
                    onTogglePin()
                }
                ActionRow(title: "Delete", icon: "trash") {
                    onDelete()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(layout.detailSidePadding)
        .background(
            RoundedRectangle(cornerRadius: layout.panelCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.7))
        )
    }
}

struct ClipboardHeroDetailPanel: View {
    let record: ClipboardRecord
    let layout: DashboardLayout
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onExcludeSourceApp: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let horizontal = proxy.size.width > 720

            HStack(alignment: .top, spacing: layout.detailSpacing) {
                previewPane
                    .frame(width: horizontal ? max(320, proxy.size.width * 0.46) : proxy.size.width)

                if horizontal {
                    VStack(alignment: .leading, spacing: layout.detailSpacing) {
                        metadata
                        actionRow
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
            }
            .frame(width: proxy.size.width, alignment: .topLeading)
        }
        .frame(minHeight: layout.heroMinHeight)
        .padding(layout.detailPadding)
        .background(
            RoundedRectangle(cornerRadius: layout.detailCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.detailCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
        )
    }

    private var previewPane: some View {
        Group {
            if record.kind == .image {
                AsyncDetailImageView(
                    imagePath: record.imagePath,
                    placeholderTitle: record.previewTitle,
                    maxPixelSize: layout.heroPreviewMinHeight * 2,
                    cornerRadius: layout.mediumCornerRadius,
                    fallbackHeight: layout.heroPreviewMinHeight
                )
            } else if record.kind == .link, let urlString = record.fullText ?? record.displayText {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        if let icon = record.sourceAppIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        } else {
                            Image(systemName: "globe")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(record.kind.accent)
                        }
                        Spacer()
                        Text(record.timeLabelShort)
                            .font(.system(size: layout.footerFontSize))
                            .foregroundStyle(.secondary)
                    }

                    Text(record.previewSubtitle)
                        .font(.system(size: layout.detailBodyTitleSize + 6, weight: .semibold))
                        .lineLimit(3)

                    if let host = record.linkHostLabel {
                        Text(host)
                            .font(.system(size: layout.footerFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(urlString)
                        .font(.system(size: layout.footerFontSize))
                        .foregroundStyle(record.kind.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(layout.cardPadding)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), record.kind.accent.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            } else if record.kind == .files {
                FileDetailPreview(
                    record: record,
                    subtitleFontSize: layout.bodySize,
                    footerFontSize: layout.footerFontSize,
                    iconSize: 144,
                    height: layout.heroPreviewMinHeight
                )
            } else {
                ClipboardCodePane(record: record)
            }
        }
        .frame(minHeight: layout.heroPreviewMinHeight, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: layout.mediumCornerRadius, style: .continuous))
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if let icon = record.sourceAppIcon, record.kind == .link {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: record.kind.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(record.kind.accent)
                }
                Text(record.kind == .link ? (record.previewSubtitle) : record.kind.title)
                    .font(.system(size: layout.footerFontSize, weight: .semibold))
                    .foregroundStyle(record.kind.accent)
                Text(record.timeLabelShort)
                    .font(.system(size: layout.footerFontSize))
                    .foregroundStyle(.secondary)
            }

            Text(record.previewTitle)
                .font(.system(size: layout.heroTitleSize, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)

            Text(record.previewSubtitle)
                .font(.system(size: layout.heroSubtitleSize))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(record.detailText)
                .font(.system(size: layout.heroBodySize))
                .foregroundStyle(.secondary.opacity(0.95))
                .lineLimit(3)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton(title: "Copy", icon: "doc.on.doc", action: onCopy)
            actionButton(title: "Paste", icon: "clipboard", action: onPaste)
            actionButton(title: record.isPinned ? "Pinned" : "Pin", icon: "pin", action: onTogglePin)
            actionButton(title: "Share", icon: "square.and.arrow.up", action: onShare)
            if record.sourceBundleId?.isEmpty == false {
                actionButton(title: "Exclude App", icon: "hand.raised", action: onExcludeSourceApp)
            }
            actionButton(title: "Delete", icon: "trash", action: onDelete, isDestructive: true)
        }
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void, isDestructive: Bool = false) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: layout.footerFontSize, weight: .medium))
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
