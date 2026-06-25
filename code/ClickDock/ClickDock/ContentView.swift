//
//  ContentView.swift
//  ClipDock
//
//  Created by Maxcj on 2026/6/22.
//

import SwiftUI
import CoreData
import AppKit
import ImageIO
import CryptoKit
import Combine
import Carbon.HIToolbox
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @EnvironmentObject private var hotkeyManager: GlobalHotkeyManager
    @Environment(\.openWindow) private var openWindow

    @State private var searchText = ""
    @State private var filter: ClipboardFilter = .all
    @State private var selectedRecordID: NSManagedObjectID?
    @State private var hasConfiguredWindow = false
    @State private var windowRef: NSWindow?

    var body: some View {
        GeometryReader { proxy in
            let layout = SimpleClipboardLayout(containerSize: proxy.size)

            ZStack(alignment: .topLeading) {
                SimpleClipboardWorkspaceView(
                    searchText: $searchText,
                    filter: filter,
                    filterSelection: $filter,
                    selectedRecordID: $selectedRecordID,
                    containerSize: proxy.size,
                    onOpenSettings: {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "settings")
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                WindowChromeOverlay(window: windowRef, layout: layout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(Color.white.opacity(0.18))
                }
            )
            .ignoresSafeArea()
        }
        .background(
            WindowAccessor { window in
                if windowRef !== window {
                    windowRef = window
                }
                guard !hasConfiguredWindow else { return }
                hasConfiguredWindow = true
                configureFloatingWindow(window)
            }
        )
        .task {
            clipboardMonitor.start()
        }
        .onDisappear {
            clipboardMonitor.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipDockTogglePanelRequested)) { _ in
            toggleMainWindowVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipDockHidePanelRequested)) { _ in
            hideMainWindow()
        }
    }

    private func configureFloatingWindow(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }

        let visibleFrame = screen.visibleFrame
        let width = min(visibleFrame.width - 56, WindowLayout.defaultSize.width)
        let height = min(visibleFrame.height - 80, WindowLayout.defaultSize.height)
        let originX = visibleFrame.midX - width / 2
        let originY = visibleFrame.minY + 18
        let frame = NSRect(x: originX, y: originY, width: width, height: height)

        window.setFrame(frame, display: true, animate: false)
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.fullSizeContentView, .titled, .closable, .miniaturizable, .resizable])
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.animationBehavior = .utilityWindow
        window.minSize = WindowLayout.minimumSize
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func toggleMainWindowVisibility() {
        guard let windowRef else { return }

        if windowRef.isVisible {
            windowRef.orderOut(nil)
            return
        }

        showMainWindow()
    }

    private func hideMainWindow() {
        windowRef?.orderOut(nil)
    }

    private func showMainWindow() {
        guard let windowRef else { return }

        NSApp.activate(ignoringOtherApps: true)
        windowRef.makeKeyAndOrderFront(nil)
        windowRef.orderFrontRegardless()
    }

}

struct WindowChromeOverlay: View {
    let window: NSWindow?
    let layout: SimpleClipboardLayout

    var body: some View {
        HStack(alignment: .center, spacing: layout.chromeButtonSpacing) {
            ChromeButton(color: Color(red: 1.0, green: 0.37, blue: 0.31), symbolName: "xmark", size: layout.chromeButtonSize) {
                window?.orderOut(nil)
            }

            ChromeButton(color: Color(red: 1.0, green: 0.80, blue: 0.20), symbolName: "minus", size: layout.chromeButtonSize) {
                window?.miniaturize(nil)
            }

            ChromeButton(color: Color(red: 0.20, green: 0.78, blue: 0.33), symbolName: "plus", size: layout.chromeButtonSize) {
                window?.zoom(nil)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, layout.chromeOverlayLeading)
        .padding(.top, layout.chromeOverlayTopPadding)
    }
}

struct ChromeButton: View {
    let color: Color
    let symbolName: String
    let size: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.opacity(isHovered ? 1.0 : 0.92))

                Image(systemName: symbolName)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isHovered ? Color.black.opacity(0.7) : Color.black.opacity(0.0))
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(symbolName == "xmark" ? "Close" : symbolName == "minus" ? "Minimize" : "Zoom")
    }
}

struct SimpleClipboardWorkspaceView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @AppStorage("clipboard.autoHideAfterCopy") private var autoHideAfterCopy = false

    @FetchRequest private var records: FetchedResults<ClipboardRecord>

    @Binding private var searchText: String
    @Binding private var filterSelection: ClipboardFilter
    @Binding private var selectedRecordID: NSManagedObjectID?
    private let activeFilter: ClipboardFilter
    private let containerSize: CGSize
    private let onOpenSettings: () -> Void
    @State private var sidebarWidth: CGFloat = 520
    @State private var isSearchFieldFocused: Bool = false
    @State private var lastSelectedImageCachePaths: [String] = []
    private static let fetchBatchSize = 40

    private var layout: SimpleClipboardLayout { SimpleClipboardLayout(containerSize: containerSize) }

    init(
        searchText: Binding<String>,
        filter: ClipboardFilter,
        filterSelection: Binding<ClipboardFilter>,
        selectedRecordID: Binding<NSManagedObjectID?>,
        containerSize: CGSize,
        onOpenSettings: @escaping () -> Void
    ) {
        self._searchText = searchText
        self.activeFilter = filter
        self._filterSelection = filterSelection
        self._selectedRecordID = selectedRecordID
        self.containerSize = containerSize
        self.onOpenSettings = onOpenSettings

        let predicate = ClipboardRecord.fetchPredicate(searchText: searchText.wrappedValue, filter: filter)
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        request.predicate = predicate
        request.fetchBatchSize = Self.fetchBatchSize

        _records = FetchRequest(fetchRequest: request, animation: .default)
    }

    var body: some View {
        let selectedRecord = currentSelectedRecord
        HStack(alignment: .top, spacing: layout.panelGap) {
            ClipboardHistorySidebar(
                searchText: $searchText,
                filterSelection: $filterSelection,
                activeFilter: activeFilter,
                records: records,
                selectedRecordID: $selectedRecordID,
                searchFieldFocused: $isSearchFieldFocused,
                layout: layout,
                onCopy: copy(_:),
                onDelete: delete(_:),
                onTogglePin: togglePin(_:),
                onOpenSettings: onOpenSettings,
                onClearAll: {
                    self.clearAll()
                }
            )
            .frame(width: layout.clampedSidebarWidth(sidebarWidth))

            Rectangle()
                .fill(Color.black.opacity(0.035))
                .frame(width: 0.5)

            ClipboardDetailInspector(
                record: selectedRecord,
                layout: layout,
                onCopy: {
                    if let selectedRecord { copy(selectedRecord) }
                },
                onTogglePin: {
                    if let selectedRecord { togglePin(selectedRecord) }
                },
                onDelete: {
                    if let selectedRecord { delete(selectedRecord) }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(layout.workspacePadding)
        .background(
            KeyCommandInterceptor(
                isSearchFocused: isSearchFieldFocused,
                onUp: {
                    moveRecordSelection(by: -1)
                },
                onDown: {
                    moveRecordSelection(by: 1)
                },
                onLeft: {
                    moveFilterSelection(by: -1)
                },
                onRight: {
                    moveFilterSelection(by: 1)
                }
            )
        )
        .background(
            RoundedRectangle(cornerRadius: layout.workspaceCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: layout.workspaceCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
        )
        .onAppear {
            syncSelection()
            syncSelectedImageCachePaths()
        }
        .onChange(of: records.count) { _ in
            syncSelection()
        }
        .onChange(of: searchText) { _ in
            syncSelection()
        }
        .onChange(of: selectedRecordID) { _ in
            syncSelectedImageCachePaths()
        }
    }

    private var currentSelectedRecord: ClipboardRecord? {
        if let selectedRecordID,
           let record = displayOrderedRecords.first(where: { $0.objectID == selectedRecordID }) {
            return record
        }
        return displayOrderedRecords.first
    }

    private var displayOrderedRecords: [ClipboardRecord] {
        records.sorted(by: clipboardRecordDisplaysBefore)
    }

    private func syncSelection() {
        guard !records.isEmpty else {
            selectedRecordID = nil
            return
        }

        if let selectedRecordID,
           records.contains(where: { $0.objectID == selectedRecordID }) {
            return
        }

        selectedRecordID = records.first?.objectID
    }

    private func syncSelectedImageCachePaths() {
        if !lastSelectedImageCachePaths.isEmpty {
            ClipboardImageCache.shared.remove(paths: lastSelectedImageCachePaths)
        }
        lastSelectedImageCachePaths = currentSelectedRecord?.cachedImagePaths ?? []
    }

    private var navigationFilters: [ClipboardFilter] {
        [.all, .text, .links, .images, .code, .files]
    }

    private func moveRecordSelection(by offset: Int) {
        guard !records.isEmpty else { return }

        let currentIndex = records.firstIndex(where: { $0.objectID == selectedRecordID }) ?? records.startIndex
        let nextIndex = min(max(records.index(currentIndex, offsetBy: offset, limitedBy: records.index(before: records.endIndex)) ?? currentIndex, records.startIndex), records.index(before: records.endIndex))
        selectedRecordID = records[nextIndex].objectID
    }

    private func moveFilterSelection(by offset: Int) {
        guard let currentIndex = navigationFilters.firstIndex(of: filterSelection) else { return }

        let nextIndex = min(
            max(currentIndex + offset, navigationFilters.startIndex),
            navigationFilters.index(before: navigationFilters.endIndex)
        )
        filterSelection = navigationFilters[nextIndex]
    }

    private func copy(_ record: ClipboardRecord) {
        clipboardMonitor.copy(record)
        markUsed(record)

        if autoHideAfterCopy {
            NotificationCenter.default.post(name: .clipDockHidePanelRequested, object: nil)
        }
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

        syncSelection()
    }

    private func clearAll() {
        for record in records {
            removeCachedAssets(for: record)
            viewContext.delete(record)
        }
        saveContext()
        selectedRecordID = nil
    }

    private func markUsed(_ record: ClipboardRecord) {
        record.lastUsedAt = Date()
        record.updatedAt = Date()
        record.usageCount += 1
        saveContext()
    }

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            NSLog("Failed to save clipboard context: \(error.localizedDescription)")
        }
    }
}

struct ClipboardHistorySidebar: View {
    @Binding var searchText: String
    @Binding var filterSelection: ClipboardFilter
    let activeFilter: ClipboardFilter
    let records: FetchedResults<ClipboardRecord>
    @Binding var selectedRecordID: NSManagedObjectID?
    @Binding var searchFieldFocused: Bool
    let layout: SimpleClipboardLayout
    let onCopy: (ClipboardRecord) -> Void
    let onDelete: (ClipboardRecord) -> Void
    let onTogglePin: (ClipboardRecord) -> Void
    let onOpenSettings: () -> Void
    let onClearAll: () -> Void
    @FocusState private var isSearchFieldFocused: Bool

    private let visibleFilters: [ClipboardFilter] = [.all, .text, .links, .images, .code, .files]

    var body: some View {
        let sections = groupedSections

        VStack(alignment: .leading, spacing: layout.sidebarSpacing) {
            HStack(spacing: 10) {
                searchField
                clearHistoryButton
                settingsButton
            }

            HStack(spacing: layout.chipSpacing) {
                ForEach(visibleFilters) { option in
                    Button {
                        filterSelection = option
                    } label: {
                        SimpleFilterChip(
                            title: option.title,
                            symbolName: option.symbolName,
                            accentColor: option.accentColor,
                            isSelected: option == activeFilter,
                            layout: layout
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: layout.rowSpacing) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: layout.rowSpacing) {
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

                            VStack(spacing: layout.rowSpacing) {
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
                Text("\(records.count) clips")
                    .font(.system(size: layout.footerSize))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(layout.sidebarPadding)
    }

    private var groupedSections: [ClipboardHistorySection] {
        let calendar = Calendar.current
        let pinnedRecords = records
            .filter(\.isPinned)
            .sorted(by: clipboardRecordDisplaysBefore)
        let unpinnedRecords = records.filter { !$0.isPinned }
        let dayKeys = Dictionary(grouping: unpinnedRecords, by: { calendar.startOfDay(for: $0.createdAt ?? Date()) })
        let sortedDays = dayKeys.keys.sorted(by: >)

        var sections: [ClipboardHistorySection] = []

        if !pinnedRecords.isEmpty {
            sections.append(
                ClipboardHistorySection(
                    id: .distantFuture,
                    title: "Pinned",
                    records: pinnedRecords,
                    topPadding: 0
                )
            )
        }

        sections.append(contentsOf: sortedDays.map { day in
            let sectionRecords = (dayKeys[day] ?? []).sorted { lhs, rhs in
                clipboardRecordDisplaysBefore(lhs, rhs)
            }

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
            return "Today"
        }

        if calendar.isDateInYesterday(day) {
            return "Yesterday"
        }

        return Self.sectionDateFormatter.string(from: day)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: layout.searchIconSize, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search clipboard", text: $searchText)
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

    private var clearHistoryButton: some View {
        Button {
            onClearAll()
        } label: {
            Image(systemName: "trash")
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
        .help("Clear clipboard history")
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
        .help("Settings")
    }

    private struct ClipboardHistorySection: Identifiable {
        let id: Date
        let title: String
        let records: [ClipboardRecord]
        let topPadding: CGFloat
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
    let record: ClipboardRecord
    let isSelected: Bool
    let layout: SimpleClipboardLayout
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

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
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    onTogglePin()
                } label: {
                    Label(record.isPinned ? "Unpin" : "Pin", systemImage: record.isPinned ? "pin.slash" : "pin")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
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
            RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .continuous)
                .fill(isSelected ? Color(red: 0.91, green: 0.95, blue: 1.0).opacity(0.64) : Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: layout.rowCornerRadius, style: .continuous)
                        .stroke(isSelected ? Color(red: 0.24, green: 0.54, blue: 0.99).opacity(0.88) : Color.black.opacity(0.05), lineWidth: isSelected ? 1.4 : 1)
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

                Text(record.detailText)
                    .font(.system(size: layout.rowSubtitleSize))
                    .foregroundStyle(record.kind == .link ? record.kind.accent : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 8) {
                sourceAppIcon(size: layout.rowActionSize)

                Text(record.previewSubtitle)
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
        } else if record.kind == .files {
            fileThumbnail
        }
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
                Image(systemName: "app.dashed")
                    .font(.system(size: max(8, size * 0.48), weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
        }
    }
}

struct ClipboardDetailInspector: View {
    let record: ClipboardRecord?
    let layout: SimpleClipboardLayout
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: layout.detailSpacing) {
            if let record {
                header(for: record)
                preview(for: record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                    .overlay(Color.black.opacity(0.06))

                metadata(for: record)

                HStack(spacing: layout.detailButtonGap) {
                    detailButton(title: "Copy", icon: "doc.on.doc", action: onCopy)
                    detailButton(title: "Pin", icon: record.isPinned ? "pin.fill" : "pin", action: onTogglePin)
                    detailButton(title: "Delete", icon: "trash", action: onDelete, isDestructive: true)
                }
                .padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No selection")
                        .font(.system(size: layout.detailTitleSize, weight: .semibold))
                    Text("Choose a clipboard item from the left to inspect it here.")
                        .font(.system(size: layout.detailSubtitleSize))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, layout.detailPaddingX)
        .padding(.vertical, layout.detailPaddingY)
    }

    private func header(for record: ClipboardRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            sourceAppIcon(for: record, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.previewSubtitle)
                    .font(.system(size: layout.detailLabelSize, weight: .medium))
                    .foregroundStyle(.primary)
                Text(record.kind.title)
                    .font(.system(size: layout.footerFontSize))
                    .foregroundStyle(record.kind.accent)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func sourceAppIcon(for record: ClipboardRecord, size: CGFloat) -> some View {
        if let icon = record.sourceAppIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(record.kind.accent.opacity(0.12))
                .overlay(
                    Image(systemName: "app.dashed")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(record.kind.accent)
                )
                .frame(width: size, height: size)
        }
    }

    private func preview(for record: ClipboardRecord) -> some View {
        switch record.kind {
        case .image:
            return AnyView(
                AsyncDetailImageView(
                    imagePath: record.imagePath,
                    placeholderTitle: record.previewTitle,
                    maxPixelSize: layout.heroImageHeight * 2,
                    cornerRadius: 18,
                    fallbackHeight: 240
                )
            )
        case .link:
            return AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .overlay(
                            VStack(alignment: .leading, spacing: 10) {
                                Text(record.previewTitle)
                                    .font(.system(size: 28, weight: .semibold))
                                    .lineLimit(3)
                                Text(record.detailText)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        )
                        .frame(height: 220)
                }
                .textSelection(.enabled)
            )
        case .files:
            return AnyView(
                FileDetailPreview(
                    record: record,
                    subtitleFontSize: layout.detailSubtitleSize,
                    footerFontSize: layout.footerFontSize,
                    iconSize: 112,
                    height: 240
                )
            )
        case .code:
            return AnyView(
                ClipboardCodePane(record: record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
        case .text, .unknown:
            return AnyView(
                ScrollView(.vertical, showsIndicators: false) {
                    Text(record.detailText)
                        .font(.system(size: layout.previewTextSize, weight: .semibold))
                        .monospaced()
                        .foregroundStyle(.primary)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
        }
    }

    private func imagePreview(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: layout.heroImageHeight)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }

    private func metadata(for record: ClipboardRecord) -> some View {
        let rows = metadataRows(for: record)

        return VStack(spacing: 14) {
            ForEach(rows.indices, id: \.self) { index in
                ClipboardDetailMetaRow(title: rows[index].title, value: rows[index].value, layout: layout)
            }
        }
        .padding(.top, 2)
    }

    private func metadataRows(for record: ClipboardRecord) -> [(title: String, value: String)] {
        var rows: [(title: String, value: String)] = [
            ("Copied", record.timeLabelPrecise)
        ]

        switch record.kind {
        case .image:
            rows.append(("Image Format", record.imageFormatLabel))
            rows.append(("Resolution", record.imageResolutionLabel))
            rows.append(("Image Size", record.imageFileSizeLabel))
        case .files:
            rows.append(("File Size", record.fileSizeLabel))
        default:
            rows.append(("Characters", "\(record.characterCount)"))
        }

        rows.append(("Type", record.kind.title))
        return rows
    }

    private func detailButton(title: String, icon: String, action: @escaping () -> Void, isDestructive: Bool = false) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: layout.detailButtonSize, weight: .medium))
            .foregroundStyle(isDestructive ? Color.red : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: layout.detailActionHeight)
            .background(Color.white.opacity(0.20))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ClipboardDetailMetaRow: View {
    let title: String
    let value: String
    let layout: SimpleClipboardLayout

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: layout.detailLabelSize))
                .foregroundStyle(.secondary)
                .frame(width: layout.detailLabelColumnWidth, alignment: .leading)

            Spacer()

            Text(value)
                .font(.system(size: layout.detailValueSize, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

struct SimpleFilterChip: View {
    let title: String
    let symbolName: String
    let accentColor: Color
    let isSelected: Bool
    let layout: SimpleClipboardLayout

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: layout.chipIconSize, weight: .semibold))
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: layout.chipTextSize, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(accentColor)
        .padding(.horizontal, layout.chipPaddingX)
        .frame(height: layout.chipHeight)
        .fixedSize(horizontal: true, vertical: false)
        .background(isSelected ? AnyShapeStyle(accentColor.opacity(0.10)) : AnyShapeStyle(Color.clear))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .overlay(
            Capsule().stroke(isSelected ? accentColor.opacity(0.24) : Color.clear, lineWidth: 1)
        )
        .shadow(color: isSelected ? Color.black.opacity(0.04) : .clear, radius: 4, x: 0, y: 1)
    }
}

struct SimpleClipboardLayout {
    let containerSize: CGSize

    private let baseSize = CGSize(width: 1440, height: 1024)

    private var scale: CGFloat {
        let baseScale = min(containerSize.width / baseSize.width, containerSize.height / baseSize.height)
        return pow(baseScale, 0.55)
    }

    private func s(_ value: CGFloat) -> CGFloat { value * scale }

    var outerPadding: CGFloat { s(24) }
    var outerSpacing: CGFloat { s(12) }
    var chromeBarHeight: CGFloat { s(26) }
    var chromeBarTopPadding: CGFloat { s(14) }
    var chromeBarBottomPadding: CGFloat { s(2) }
    var chromeBarLeadingPadding: CGFloat { s(2) }
    var chromeBarHorizontalPadding: CGFloat { s(18) }
    var chromeButtonSpacing: CGFloat { s(8) }
    var chromeButtonSize: CGFloat { s(14) }
    var chromeSettingsButtonSize: CGFloat { s(32) }
    var chromeSettingsIconSize: CGFloat { s(14) }
    var chromeSettingsButtonCornerRadius: CGFloat { s(9) }
    var chromeOverlayTopPadding: CGFloat { s(12) }
    var chromeOverlayLeading: CGFloat { s(18) }
    var chromeOverlaySpacing: CGFloat { s(6) }
    var workspacePadding: CGFloat { s(18) }
    var workspaceCornerRadius: CGFloat { s(16) }
    var panelGap: CGFloat { s(18) }
    var panelCornerRadius: CGFloat { s(20) }
    var sidebarWidth: CGFloat { max(s(500), min(s(560), containerSize.width * 0.38)) }
    var sidebarPadding: CGFloat { s(16) }
    var sidebarSpacing: CGFloat { s(12) }
    var searchHeight: CGFloat { s(42) }
    var searchCornerRadius: CGFloat { s(14) }
    var searchPaddingX: CGFloat { s(14) }
    var searchIconSize: CGFloat { s(15) }
    var searchTextSize: CGFloat { s(14) }
    var searchHintSize: CGFloat { s(12) }
    var chipSpacing: CGFloat { s(8) }
    var chipHeight: CGFloat { s(34) }
    var chipPaddingX: CGFloat { s(16) }
    var chipIconSize: CGFloat { s(12) }
    var chipTextSize: CGFloat { s(13) }
    var sectionLabelSize: CGFloat { s(13) }
    var rowSpacing: CGFloat { s(10) }
    var rowHeight: CGFloat { s(122) }
    var rowCornerRadius: CGFloat { s(18) }
    var rowPaddingX: CGFloat { s(12) }
    var rowPaddingY: CGFloat { s(10) }
    var rowTitleSize: CGFloat { s(17) }
    var rowSubtitleSize: CGFloat { s(12) }
    var rowSnippetSize: CGFloat { s(13) }
    var rowMetaSize: CGFloat { s(11) }
    var rowStatusDotSize: CGFloat { s(9) }
    var rowActionSize: CGFloat { s(18) }
    var rowActionIconSize: CGFloat { s(14) }
    var rowAccessoryGap: CGFloat { s(8) }
    var rowContentGap: CGFloat { s(12) }
    var rowTextSpacing: CGFloat { s(5) }
    var rowTagSize: CGFloat { s(12) }
    var rowImagePreviewWidth: CGFloat { s(90) }
    var rowImagePreviewHeight: CGFloat { s(72) }
    var rowImagePreviewCornerRadius: CGFloat { s(12) }
    var rowFilePreviewCornerRadius: CGFloat { s(14) }
    var rowFileIconSize: CGFloat { s(18) }
    var footerButtonSize: CGFloat { s(22) }
    var footerIconSize: CGFloat { s(11) }
    var badgeSize: CGFloat { s(40) }
    var badgeCornerRadius: CGFloat { s(12) }
    var badgeIconSize: CGFloat { s(18) }
    var footerSize: CGFloat { s(12) }
    var detailPaddingX: CGFloat { s(24) }
    var detailPaddingY: CGFloat { s(22) }
    var detailSpacing: CGFloat { s(16) }
    var detailLabelSize: CGFloat { s(13) }
    var detailLabelColumnWidth: CGFloat { s(92) }
    var detailValueSize: CGFloat { s(14) }
    var detailButtonSize: CGFloat { s(14) }
    var detailActionHeight: CGFloat { s(44) }
    var detailTitleSize: CGFloat { s(32) }
    var detailSubtitleSize: CGFloat { s(15) }
    var previewTextSize: CGFloat { s(42) }
    var detailButtonGap: CGFloat { s(12) }
    var heroImageHeight: CGFloat { s(320) }
    var rowTimeWidth: CGFloat { s(112) }
    var rowKindWidth: CGFloat { s(72) }
    var rowFooterWidth: CGFloat { s(138) }

    var sidebarMinWidth: CGFloat { s(420) }
    var sidebarMaxWidth: CGFloat { min(s(640), containerSize.width * 0.48) }
    var resizeHandleWidth: CGFloat { s(14) }
    var resizeHandleHeight: CGFloat { s(86) }

    func clampedSidebarWidth(_ value: CGFloat) -> CGFloat {
        min(max(value, sidebarMinWidth), sidebarMaxWidth)
    }

    // Compatibility for older views still in this file.
    var panelSpacing: CGFloat { panelGap }
    var detailPadding: CGFloat { detailPaddingX }
    var toolbarButtonSize: CGFloat { s(34) }
    var toolbarDotsSize: CGFloat { s(16) }
    var toolbarPillTextSize: CGFloat { s(13) }
    var toolbarPillHeight: CGFloat { s(32) }
    var searchBarMaxWidth: CGFloat { s(430) }
    var searchBarHeight: CGFloat { s(38) }
    var searchHorizontalPadding: CGFloat { s(14) }
    var toolbarSpacing: CGFloat { s(12) }
    var toolbarIconSize: CGFloat { s(12) }
    var panelPadding: CGFloat { s(16) }
    var mainSectionSpacing: CGFloat { s(14) }
    var categorySpacing: CGFloat { s(10) }
    var cardPanelSpacing: CGFloat { s(12) }
    var cardPanelPadding: CGFloat { s(14) }
    var cardPanelCornerRadius: CGFloat { s(18) }
    var cardSpacing: CGFloat { s(14) }
    var cardMinWidth: CGFloat { s(200) }
    var cardHeight: CGFloat { s(300) }
    var cardShadowRadius: CGFloat { s(8) }
    var cardSpacingInner: CGFloat { s(12) }
    var cardPadding: CGFloat { s(14) }
    var cardCornerRadius: CGFloat { s(22) }
    var sectionTitleSize: CGFloat { s(15) }
    var filterIconSize: CGFloat { s(11) }
    var footerFontSize: CGFloat { s(13) }
    var chipHorizontalPadding: CGFloat { s(14) }
    var chipVerticalPadding: CGFloat { s(8) }
    var detailCornerRadius: CGFloat { s(22) }
    var smallCornerRadius: CGFloat { s(12) }
    var mediumCornerRadius: CGFloat { s(14) }
    var heroMinHeight: CGFloat { s(310) }
    var heroPreviewMinHeight: CGFloat { s(280) }
    var heroTitleSize: CGFloat { s(27) }
    var heroSubtitleSize: CGFloat { s(15) }
    var heroBodySize: CGFloat { s(14) }
    var codePaneMinHeight: CGFloat { s(124) }
}

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
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        _records = FetchRequest(
            sortDescriptors: sortDescriptors,
            predicate: predicate,
            animation: .default
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
                            onDelete: { delete(record) }
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
        records.sorted(by: clipboardRecordDisplaysBefore)
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
                    Image(systemName: record.kind.symbolName)
                        .font(.system(size: layout.iconSizeLarge, weight: .semibold))
                        .foregroundStyle(record.kind.accent)
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
                        Image(systemName: record.kind.symbolName)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(record.kind.accent)
                        Spacer()
                        Text(record.timeLabelShort)
                            .font(.system(size: layout.footerFontSize))
                            .foregroundStyle(.secondary)
                    }

                    Text(record.previewTitle)
                        .font(.system(size: layout.detailBodyTitleSize + 6, weight: .semibold))
                        .lineLimit(3)

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
                Image(systemName: record.kind.symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(record.kind.accent)
                Text(record.kind.title)
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

private struct AsyncDetailImageView: View {
    let imagePath: String?
    let placeholderTitle: String
    let maxPixelSize: CGFloat
    let cornerRadius: CGFloat
    let height: CGFloat? = nil
    let fallbackHeight: CGFloat

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var requestToken = UUID()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height ?? fallbackHeight)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.16))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .task(id: imagePath) {
            image = nil

            let token = UUID()
            requestToken = token

            guard let imagePath, !imagePath.isEmpty else {
                return
            }

            isLoading = true
            defer { isLoading = false }

            let loadedImage = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    ClipboardImageCache.shared.downsampledImage(at: imagePath, maxPixelSize: maxPixelSize)
                }
            }.value

            guard !Task.isCancelled else { return }
            guard token == requestToken else { return }
            image = loadedImage
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: isLoading ? "hourglass" : "photo")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.65))

            Text(placeholderTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.94),
                    Color(red: 0.89, green: 0.94, blue: 1.0).opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct FileDetailPreview: View {
    let record: ClipboardRecord
    let subtitleFontSize: CGFloat
    let footerFontSize: CGFloat
    let iconSize: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 18) {
            fileIcon
                .frame(width: max(120, iconSize + 24), height: height)

            VStack(alignment: .leading, spacing: 10) {
                Text(record.previewTitle)
                    .font(.system(size: 28, weight: .semibold))
                    .lineLimit(3)

                Text("File ready to copy or open from Finder.")
                    .font(.system(size: subtitleFontSize))
                    .foregroundStyle(.secondary)

                if record.kind == .files {
                    Text(record.fileSizeLabel)
                        .font(.system(size: footerFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .center)
    }

    @ViewBuilder
    private var fileIcon: some View {
        if let icon = record.fileIconImage {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            }
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(record.kind.accent.opacity(0.12))
                .overlay(
                    Image(systemName: "doc")
                        .font(.system(size: iconSize * 0.38, weight: .regular))
                        .foregroundStyle(record.kind.accent)
                )
        }
    }
}

struct ClipboardCodePane: View {
    let record: ClipboardRecord

    var body: some View {
        GeometryReader { proxy in
            let lines = ClipboardCodeLineCache.shared.lines(for: record)
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .frame(width: 28, height: 18, alignment: .topTrailing)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.primary)
                                .frame(height: 18, alignment: .topLeading)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(14)
                .frame(
                    minWidth: proxy.size.width,
                    minHeight: proxy.size.height,
                    alignment: .topLeading
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

struct ActionRow: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ClipboardPreviewCard: View {
    let record: ClipboardRecord
    let isSelected: Bool
    let layout: DashboardLayout
    let onTap: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: layout.cardSpacingInner) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: record.kind.symbolName)
                            .font(.system(size: layout.iconSizeSmall, weight: .semibold))
                        Text(record.kind.title)
                    }
                    .font(.system(size: layout.footerFontSize - 1, weight: .semibold))
                    .foregroundStyle(record.kind.accent)

                    Spacer()

                    Text(record.timeLabelShort)
                        .font(.system(size: layout.footerFontSize - 1))
                        .foregroundStyle(.secondary)

                    Image(systemName: "ellipsis")
                        .font(.system(size: layout.iconSizeSmall, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.8))
                }

                if record.kind == .image, let preview = record.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(height: layout.cardImageHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: layout.mediumCornerRadius, style: .continuous))
                } else {
                    Text(record.previewTitle)
                        .font(.system(size: layout.cardTitleSize, weight: .semibold))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.primary)
                }

                Text(record.previewSubtitle)
                    .font(.system(size: layout.footerFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Text(record.kind.title)
                        .font(.system(size: layout.footerFontSize - 1, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(record.kind.accent.opacity(0.14))
                        .foregroundStyle(record.kind.accent)
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(CardIconButtonStyle(layout: layout))

                    Button(action: onTogglePin) {
                        Image(systemName: record.isPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(CardIconButtonStyle(layout: layout))
                }
            }
            .padding(layout.cardPadding)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                            .stroke(isSelected ? record.kind.accent.opacity(0.90) : Color.white.opacity(0.24), lineWidth: isSelected ? 1.6 : 1)
                    )
                    .shadow(color: isSelected ? record.kind.accent.opacity(0.16) : .black.opacity(0.06), radius: layout.cardShadowRadius, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onTap()
            onCopy()
        })
        .contextMenu {
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button {
                onTogglePin()
            } label: {
                Label(record.isPinned ? "Unpin" : "Pin", systemImage: record.isPinned ? "pin.slash" : "pin")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.94),
                record.kind.accent.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct FilterChip: View {
    let title: String
    let symbolName: String
    let isSelected: Bool
    let layout: DashboardLayout

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: layout.filterIconSize, weight: .semibold))
            Text(title)
        }
        .font(.system(size: layout.footerFontSize, weight: .medium))
        .foregroundStyle(isSelected ? .white : .primary.opacity(0.82))
        .padding(.horizontal, layout.chipHorizontalPadding)
        .padding(.vertical, layout.chipVerticalPadding)
        .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.white.opacity(0.78)))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(isSelected ? 0.0 : 0.16), lineWidth: 1)
        )
    }
}

struct DashboardLayout {
    let containerSize: CGSize

    private let baseSize = CGSize(width: 1286, height: 856)

    private var scale: CGFloat {
        let baseScale = min(containerSize.width / baseSize.width, containerSize.height / baseSize.height)
        return pow(baseScale, 0.55)
    }

    private func s(_ value: CGFloat) -> CGFloat { value * scale }

    var outerPadding: CGFloat { s(20) }
    var verticalSpacing: CGFloat { s(14) }
    var toolbarSpacing: CGFloat { s(12) }
    var toolbarButtonSize: CGFloat { s(36) }
    var toolbarIconSize: CGFloat { s(12) }
    var toolbarDotsSize: CGFloat { s(16) }
    var searchBarHeight: CGFloat { s(38) }
    var searchBarMaxWidth: CGFloat { s(430) }
    var searchHorizontalPadding: CGFloat { s(14) }
    var searchCornerRadius: CGFloat { s(19) }
    var searchIconSize: CGFloat { s(15) }
    var searchTextSize: CGFloat { s(14) }
    var searchHintSize: CGFloat { s(12) }
    var toolbarPillHeight: CGFloat { s(32) }
    var toolbarPillTextSize: CGFloat { s(13) }
    var panelPadding: CGFloat { s(16) }
    var mainSectionSpacing: CGFloat { s(14) }
    var cardPanelSpacing: CGFloat { s(12) }
    var cardPanelPadding: CGFloat { s(14) }
    var cardPanelCornerRadius: CGFloat { s(18) }
    var sectionTitleSize: CGFloat { s(15) }
    var categorySpacing: CGFloat { s(10) }
    var panelCornerRadius: CGFloat { s(18) }
    var detailCornerRadius: CGFloat { s(22) }
    var smallCornerRadius: CGFloat { s(12) }
    var mediumCornerRadius: CGFloat { s(14) }
    var cardCornerRadius: CGFloat { s(22) }
    var cardSpacing: CGFloat { s(14) }
    var cardSpacingInner: CGFloat { s(12) }
    var cardPadding: CGFloat { s(14) }
    var detailPadding: CGFloat { s(14) }
    var detailSpacing: CGFloat { s(14) }
    var detailSidePadding: CGFloat { s(12) }
    var chipHorizontalPadding: CGFloat { s(14) }
    var chipVerticalPadding: CGFloat { s(8) }
    var footerSpacing: CGFloat { s(12) }
    var titleSize: CGFloat { s(19) }
    var subtitleSize: CGFloat { s(13) }
    var bodySize: CGFloat { s(14) }
    var footerFontSize: CGFloat { s(13) }
    var cardTitleSize: CGFloat { s(17) }
    var detailTitleSize: CGFloat { s(17) }
    var detailBodyTitleSize: CGFloat { s(16) }
    var filterIconSize: CGFloat { s(11) }
    var iconSizeSmall: CGFloat { s(12) }
    var iconSizeMedium: CGFloat { s(18) }
    var iconSizeLarge: CGFloat { s(22) }
    var actionButtonSize: CGFloat { s(34) }
    var statusDotSize: CGFloat { s(9) }
    var cardImageHeight: CGFloat { s(104) }
    var detailBadgeSize: CGFloat { s(44) }
    var codePaneMinHeight: CGFloat { s(124) }
    var heroMinHeight: CGFloat { s(310) }
    var heroPreviewMinHeight: CGFloat { s(280) }
    var heroTitleSize: CGFloat { s(27) }
    var heroSubtitleSize: CGFloat { s(15) }
    var heroBodySize: CGFloat { s(14) }
    var cardMinWidth: CGFloat { s(200) }
    var cardMaxWidth: CGFloat { s(236) }
    var cardHeight: CGFloat { s(300) }
    var cardShadowRadius: CGFloat { s(8) }
}

struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        ResolvingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let resolvingView = nsView as? ResolvingView {
            resolvingView.onResolve = onResolve
        }
    }

    final class ResolvingView: NSView {
        var onResolve: ((NSWindow) -> Void)?

        init(onResolve: @escaping (NSWindow) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                DispatchQueue.main.async { [weak self] in
                    self?.onResolve?(window)
                }
            }
        }
    }
}

struct KeyCommandInterceptor: NSViewRepresentable {
    let isSearchFocused: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onLeft: () -> Void
    let onRight: () -> Void

    func makeNSView(context: Context) -> NSView {
        InterceptView(
            isSearchFocused: isSearchFocused,
            onUp: onUp,
            onDown: onDown,
            onLeft: onLeft,
            onRight: onRight
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let interceptView = nsView as? InterceptView else { return }
        interceptView.isSearchFocused = isSearchFocused
        interceptView.onUp = onUp
        interceptView.onDown = onDown
        interceptView.onLeft = onLeft
        interceptView.onRight = onRight
    }

    final class InterceptView: NSView {
        var isSearchFocused: Bool
        var onUp: () -> Void
        var onDown: () -> Void
        var onLeft: () -> Void
        var onRight: () -> Void
        private var monitor: Any?

        init(
            isSearchFocused: Bool,
            onUp: @escaping () -> Void,
            onDown: @escaping () -> Void,
            onLeft: @escaping () -> Void,
            onRight: @escaping () -> Void
        ) {
            self.isSearchFocused = isSearchFocused
            self.onUp = onUp
            self.onDown = onDown
            self.onLeft = onLeft
            self.onRight = onRight
            super.init(frame: .zero)
            installMonitor()
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                    return event
                }

                if self.isSearchFocused {
                    return event
                }

                switch event.keyCode {
                case 126:
                    self.onUp()
                    return nil
                case 125:
                    self.onDown()
                    return nil
                case 123:
                    self.onLeft()
                    return nil
                case 124:
                    self.onRight()
                    return nil
                default:
                    return event
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @State private var activeTab: SettingsTab = .general
    @State private var windowRef: NSWindow?
    @AppStorage("clipboard.startAtLogin") private var startAtLogin = false
    @AppStorage("clipboard.keepImages") private var keepImages = true
    @AppStorage("clipboard.retentionEnabled") private var retentionEnabled = false
    @AppStorage("clipboard.retentionValue") private var retentionValue = 7
    @AppStorage("clipboard.retentionUnit") private var retentionUnit = RetentionUnit.day.rawValue
    @AppStorage("clipboard.hotkeyEnabled") private var hotkeyEnabled = true
    @AppStorage("clipboard.hotkeyKeyCode") private var hotkeyKeyCode = HotKeyConfiguration.defaultKeyCode
    @AppStorage("clipboard.hotkeyModifiers") private var hotkeyModifiers = Int(HotKeyConfiguration.defaultModifiers)
    @AppStorage("clipboard.hotkeyDisplay") private var hotkeyDisplay = HotKeyConfiguration.defaultDisplay
    @AppStorage("clipboard.autoHideAfterCopy") private var autoHideAfterCopy = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                settingsTabBar

                tabContent

                Text("The app stores clipboard data locally and keeps working in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(24)
        }
        .frame(width: 560, height: 560)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.98, blue: 1.0),
                        Color(red: 0.94, green: 0.95, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.72)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        )
        .background(
            WindowAccessor { window in
                if windowRef !== window {
                    windowRef = window
                }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        )
        .onAppear {
            loginItemManager.refreshStatus()
            startAtLogin = loginItemManager.isEnabled
        }
        .onChange(of: startAtLogin) { newValue in
            guard newValue != loginItemManager.isEnabled else { return }
            loginItemManager.setEnabled(newValue)
            startAtLogin = loginItemManager.isEnabled
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .general:
            SettingsTabCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Launch at login", isOn: $startAtLogin)
                    if let statusMessage = loginItemManager.statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Keep images in history", isOn: $keepImages)
                    Toggle("Auto-hide after copying from history", isOn: $autoHideAfterCopy)
                    Text("Hide the main window after copying a clipboard item so you can paste immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .quickOpen:
            SettingsTabCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Enable global hotkey", isOn: $hotkeyEnabled)

                    ShortcutRecorderField(
                        keyCode: $hotkeyKeyCode,
                        modifiers: $hotkeyModifiers,
                        displayText: $hotkeyDisplay,
                        defaultKeyCode: HotKeyConfiguration.defaultKeyCode,
                        defaultModifiers: Int(HotKeyConfiguration.defaultModifiers),
                        defaultDisplay: HotKeyConfiguration.defaultDisplay
                    )
                }
            }
        case .autoClean:
            SettingsTabCard {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Enable auto cleanup", isOn: $retentionEnabled)

                    HStack(spacing: 10) {
                        Text("Delete unpinned items older than")
                            .font(.subheadline)

                        TextField("", value: $retentionValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 76)
                            .multilineTextAlignment(.trailing)

                        Picker("", selection: $retentionUnit) {
                            ForEach(RetentionUnit.allCases) { unit in
                                Text(unit.title).tag(unit.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)

                        Spacer()
                    }

                    Text("Pinned items are never removed by auto cleanup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 10) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    activeTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(activeTab == tab ? Color.white : Color.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(activeTab == tab ? tab.tint : Color.white.opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(activeTab == tab ? tab.tint.opacity(0.35) : Color.black.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case quickOpen
    case autoClean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .quickOpen: return "Quick Open"
        case .autoClean: return "Auto Clean"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "tray.full"
        case .quickOpen: return "keyboard"
        case .autoClean: return "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .general: return Color(red: 0.20, green: 0.49, blue: 0.98)
        case .quickOpen: return Color(red: 0.16, green: 0.68, blue: 0.34)
        case .autoClean: return Color(red: 0.99, green: 0.67, blue: 0.15)
        }
    }
}

struct SettingsTabCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.80))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.36), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

struct ShortcutRecorderField: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @Binding var displayText: String

    let defaultKeyCode: Int
    let defaultModifiers: Int
    let defaultDisplay: String

    @State private var isCapturing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show or hide the main panel")
                        .font(.subheadline.weight(.semibold))
                    Text("Click Change and press a key combo with at least one modifier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(isCapturing ? "Recording..." : "Change") {
                    isCapturing = true
                }
                .buttonStyle(SettingsSecondaryButtonStyle())

                Button("Reset") {
                    keyCode = defaultKeyCode
                    modifiers = defaultModifiers
                    displayText = defaultDisplay
                }
                .buttonStyle(SettingsSecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                Text(displayText.isEmpty ? "No shortcut assigned" : displayText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.white.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .overlay(
                Group {
                    if isCapturing {
                        ShortcutCaptureView(
                            onCapture: { capturedKeyCode, capturedModifiers, capturedDisplay in
                                keyCode = capturedKeyCode
                                modifiers = capturedModifiers
                                displayText = capturedDisplay
                                isCapturing = false
                            },
                            onCancel: {
                                isCapturing = false
                            }
                        )
                        .allowsHitTesting(true)
                    }
                }
            )
        }
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (Int, Int, String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        KeyCaptureNSView(onCapture: onCapture, onCancel: onCancel)
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
    }

    final class KeyCaptureNSView: NSView {
        var onCapture: (Int, Int, String) -> Void
        var onCancel: () -> Void

        init(onCapture: @escaping (Int, Int, String) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            let keyCode = Int(event.keyCode)
            if keyCode == 53 {
                onCancel()
                return
            }

            let modifiers = HotKeyConfiguration.carbonModifiers(from: event.modifierFlags)
            guard modifiers != 0 else { return }

            onCapture(keyCode, modifiers, HotKeyConfiguration.displayString(for: event))
        }
    }
}

enum HotKeyConfiguration {
    static let defaultKeyCode = 12
    static let defaultModifiers = UInt32(controlKey)
    static let defaultDisplay = "⌃Q"

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var carbonFlags: UInt32 = 0
        let modifierFlags = flags.intersection([.command, .option, .control, .shift])

        if modifierFlags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if modifierFlags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if modifierFlags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        return Int(carbonFlags)
    }

    static func displayString(for event: NSEvent) -> String {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var pieces: [String] = []
        if modifiers.contains(.control) { pieces.append("⌃") }
        if modifiers.contains(.option) { pieces.append("⌥") }
        if modifiers.contains(.shift) { pieces.append("⇧") }
        if modifiers.contains(.command) { pieces.append("⌘") }

        pieces.append(displayName(for: event))
        return pieces.joined()
    }

    private static func displayName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        case 51: return "Delete"
        case 123: return "Left"
        case 124: return "Right"
        case 125: return "Down"
        case 126: return "Up"
        default:
            let chars = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let chars, !chars.isEmpty {
                return chars.uppercased()
            }
            return "Key \(event.keyCode)"
        }
    }
}

struct RetentionRule {
    let isEnabled: Bool
    let value: Int
    let unit: RetentionUnit

    var cutoffDate: Date? {
        guard isEnabled, value > 0 else { return nil }
        let interval = TimeInterval(value) * unit.secondsMultiplier
        return Date().addingTimeInterval(-interval)
    }

    static func current() -> RetentionRule {
        let defaults = UserDefaults.standard
        let isEnabled = defaults.object(forKey: "clipboard.retentionEnabled") as? Bool ?? false
        let value = defaults.object(forKey: "clipboard.retentionValue") as? Int ?? 7
        let unit = RetentionUnit(rawValue: defaults.string(forKey: "clipboard.retentionUnit") ?? RetentionUnit.day.rawValue) ?? .day
        return RetentionRule(isEnabled: isEnabled, value: value, unit: unit)
    }
}

enum RetentionUnit: String, CaseIterable, Identifiable {
    case minute
    case hour
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minute: return "Minutes"
        case .hour: return "Hours"
        case .day: return "Days"
        }
    }

    var secondsMultiplier: TimeInterval {
        switch self {
        case .minute: return 60
        case .hour: return 60 * 60
        case .day: return 60 * 60 * 24
        }
    }
}

enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case links
    case images
    case code
    case files
    case colors
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .links: return "Links"
        case .images: return "Images"
        case .code: return "Code"
        case .files: return "Files"
        case .colors: return "Colors"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "circle.fill"
        case .text: return "text.quote"
        case .links: return "link"
        case .images: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .files: return "doc"
        case .colors: return "paintpalette"
        case .other: return "ellipsis"
        }
    }

    var accentColor: Color {
        switch self {
        case .all: return Color(red: 0.96, green: 0.20, blue: 0.28)
        case .text: return Color(red: 0.96, green: 0.48, blue: 0.18)
        case .links: return Color(red: 0.11, green: 0.66, blue: 0.53)
        case .images: return Color(red: 0.16, green: 0.54, blue: 0.96)
        case .code: return Color(red: 0.60, green: 0.35, blue: 0.95)
        case .files: return Color(red: 0.99, green: 0.67, blue: 0.15)
        case .colors: return Color.orange
        case .other: return Color.secondary
        }
    }
}

enum ClipboardContentKind: String {
    case text
    case link
    case image
    case code
    case files
    case unknown

    var title: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .image: return "Image"
        case .code: return "Code"
        case .files: return "Files"
        case .unknown: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.quote"
        case .link: return "link"
        case .image: return "photo"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .files: return "doc"
        case .unknown: return "questionmark.circle"
        }
    }

    var accent: Color {
        switch self {
        case .text: return Color(red: 0.96, green: 0.48, blue: 0.18)
        case .link: return Color(red: 0.11, green: 0.66, blue: 0.53)
        case .image: return Color(red: 0.16, green: 0.54, blue: 0.96)
        case .code: return Color(red: 0.60, green: 0.35, blue: 0.95)
        case .files: return Color(red: 0.99, green: 0.67, blue: 0.15)
        case .unknown: return Color.secondary
        }
    }
}

extension ClipboardRecord {
    var kind: ClipboardContentKind {
        ClipboardContentKind(rawValue: contentTypeRaw ?? "") ?? .unknown
    }

    var previewImage: NSImage? {
        guard kind == .image,
              let previewPath = thumbnailPathValue ?? imagePath,
              let image = ClipboardImageCache.shared.image(at: previewPath) else {
            return nil
        }
        return image
    }

    var originalImage: NSImage? {
        guard kind == .image,
              let imagePath,
              let image = ClipboardImageCache.shared.image(at: imagePath) else {
            return nil
        }
        return image
    }

    var previewTitle: String {
        if let displayText, !displayText.isEmpty {
            return displayText
        }

        if kind == .image {
            return "Image"
        }

        if kind == .files {
            return "File list"
        }

        return "Empty"
    }

    var previewSubtitle: String {
        let appName = sourceAppName?.isEmpty == false ? sourceAppName! : "Unknown source"
        return appName
    }

    var sourceAppIcon: NSImage? {
        ClipboardAppIconCache.shared.icon(bundleId: sourceBundleId)
    }

    var fileIconImage: NSImage? {
        guard kind == .files else { return nil }
        return ClipboardFileIconCache.shared.icon(for: fileRepresentativeURL)
    }

    var imageFormatLabel: String {
        guard kind == .image else { return "-" }
        let path = imagePath ?? thumbnailPathValue
        return Self.fileExtensionLabel(for: path) ?? "PNG"
    }

    var imageResolutionLabel: String {
        guard kind == .image, let imagePath else { return "-" }
        return Self.imageResolutionLabel(forImageAtPath: imagePath) ?? "-"
    }

    var imageFileSizeLabel: String {
        guard kind == .image else { return "-" }
        return Self.fileSizeLabel(forPath: imagePath)
    }

    var fileSizeLabel: String {
        guard kind == .files else { return "-" }
        return Self.fileSizeLabel(forPath: assetPathValue)
    }

    var cachedImagePaths: [String] {
        [imagePath, thumbnailPathValue].compactMap { path in
            guard let path, !path.isEmpty else { return nil }
            return path
        }
    }

    func detailImage(maxPixelSize: CGFloat) -> NSImage? {
        guard kind == .image, let imagePath else { return nil }
        return ClipboardImageCache.shared.downsampledImage(at: imagePath, maxPixelSize: maxPixelSize) ?? previewImage
    }

    var fileRepresentativeURL: URL? {
        guard kind == .files,
              let assetPath = assetPathValue,
              !assetPath.isEmpty else {
            return nil
        }

        let folderURL = URL(fileURLWithPath: assetPath)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let files = contents.filter { url in
            (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        return files.first
    }

    var detailText: String {
        if let fullText, !fullText.isEmpty {
            return fullText
        }

        if kind == .image {
            return imagePath ?? "Image saved locally"
        }

        return previewTitle
    }

    var rowSnippet: String {
        switch kind {
        case .text, .code, .unknown:
            return detailText
        case .link:
            return fullText ?? previewTitle
        case .image:
            return "Image saved locally"
        case .files:
            return "File ready to paste or open."
        }
    }

    var characterCount: Int {
        (fullText ?? displayText ?? "").count
    }

    var timeLabel: String {
        Self.formatter.string(from: createdAt ?? Date())
    }

    var timeLabelShort: String {
        Self.shortFormatter.string(from: createdAt ?? Date())
    }

    var timeLabelPrecise: String {
        Self.preciseFormatter.string(from: createdAt ?? Date())
    }

    var historyRowTimeLabel: String {
        let date = createdAt ?? Date()
        let timeText = Self.shortFormatter.string(from: date)
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today  \(timeText)"
        }

        if calendar.isDateInYesterday(date) {
            return "Yesterday  \(timeText)"
        }

        return Self.historyRowFormatter.string(from: date)
    }

    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let preciseFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    static let historyRowFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd  HH:mm"
        return formatter
    }()

    private static func fileExtensionLabel(for path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? nil : ext.uppercased()
    }

    private static func imageResolutionLabel(forImageAtPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return "\(width) × \(height)"
    }

    private static func fileSizeLabel(forPath path: String?) -> String {
        guard let path, !path.isEmpty else { return "-" }
        let url = URL(fileURLWithPath: path)
        guard let size = fileSize(at: url) else { return "-" }
        return Self.byteCountFormatter.string(fromByteCount: Int64(size))
    }

    private static func fileSize(at url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
        if values?.isDirectory == true {
            return directorySize(at: url)
        }

        if let allocated = values?.totalFileAllocatedSize, allocated > 0 {
            return allocated
        }

        if let fileSize = values?.fileSize, fileSize > 0 {
            return fileSize
        }

        return nil
    }

    private static func directorySize(at url: URL) -> Int? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: Int = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey])
            guard values?.isDirectory != true else { continue }
            if let allocated = values?.totalFileAllocatedSize, allocated > 0 {
                total += allocated
            } else if let fileSize = values?.fileSize, fileSize > 0 {
                total += fileSize
            }
        }
        return total > 0 ? total : nil
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func fetchPredicate(searchText: String, filter: ClipboardFilter) -> NSPredicate? {
        var predicates: [NSPredicate] = [
            NSPredicate(format: "isIgnored == NO")
        ]

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "displayText CONTAINS[cd] %@", trimmed),
                    NSPredicate(format: "fullText CONTAINS[cd] %@", trimmed),
                    NSPredicate(format: "sourceAppName CONTAINS[cd] %@", trimmed)
                ])
            )
        }

        switch filter {
        case .all:
            break
        case .text:
            predicates.append(NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.text.rawValue))
        case .links:
            predicates.append(NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.link.rawValue))
        case .images:
            predicates.append(NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.image.rawValue))
        case .code:
            predicates.append(NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.code.rawValue))
        case .files:
            predicates.append(NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.files.rawValue))
        case .colors:
            predicates.append(NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.text.rawValue))
        case .other:
            predicates.append(NSPredicate(format: "contentTypeRaw == %@", ClipboardContentKind.unknown.rawValue))
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
    }
}

    private func removeCachedAssets(for record: ClipboardRecord) {
        if let imagePath = record.imagePath, !imagePath.isEmpty {
            try? FileManager.default.removeItem(atPath: imagePath)
            ClipboardImageCache.shared.remove(path: imagePath)
        }
        if let assetPath = record.assetPathValue, !assetPath.isEmpty {
            try? FileManager.default.removeItem(atPath: assetPath)
        }
        if let thumbnailPath = record.thumbnailPathValue, !thumbnailPath.isEmpty {
            try? FileManager.default.removeItem(atPath: thumbnailPath)
            ClipboardImageCache.shared.remove(path: thumbnailPath)
        }
    }

private final class ClipboardImageCache {
    static let shared = ClipboardImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 120
    }

    func image(at path: String, preferredSize: CGSize? = nil) -> NSImage? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }

        if let preferredSize {
            image.size = preferredSize
        }

        cache.setObject(image, forKey: key)
        return image
    }

    func downsampledImage(at path: String, maxPixelSize: CGFloat) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelSize = max(1, maxPixelSize * scale)
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func remove(path: String) {
        cache.removeObject(forKey: path as NSString)
    }

    func remove(paths: [String]) {
        paths.forEach { cache.removeObject(forKey: $0 as NSString) }
    }
}

private final class ClipboardAppIconCache {
    static let shared = ClipboardAppIconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 64
    }

    func icon(bundleId: String?) -> NSImage? {
        let key = bundleId ?? "__generic__"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let icon: NSImage
        if let bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            icon = NSWorkspace.shared.icon(for: UTType.application)
        }
        icon.size = NSSize(width: 128, height: 128)
        cache.setObject(icon, forKey: key as NSString)
        return icon
    }
}

private final class ClipboardFileIconCache {
    static let shared = ClipboardFileIconCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 96
    }

    func icon(for url: URL?) -> NSImage? {
        let contentType = Self.contentType(for: url)
        let cacheKey = contentType?.identifier ?? "__generic_file__"

        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached
        }

        let icon = NSWorkspace.shared.icon(for: contentType ?? .data)
        icon.size = NSSize(width: 256, height: 256)
        cache.setObject(icon, forKey: cacheKey as NSString)
        return icon
    }

    private static func contentType(for url: URL?) -> UTType? {
        guard let url else { return nil }

        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey]),
           let contentType = values.contentType {
            return contentType
        }

        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return .folder
        }

        let ext = url.pathExtension.lowercased()
        if let mappedExtension = mappedPreferredExtension(forExtension: ext),
           let type = UTType(filenameExtension: mappedExtension) {
            return type
        }

        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return type
        }

        return nil
    }

    private static func mappedPreferredExtension(forExtension ext: String) -> String? {
        switch ext {
        case "pdf":
            return "pdf"
        case "rtf":
            return "rtf"
        case "txt", "text", "log", "md", "markdown", "rst", "ini", "conf", "cfg":
            return "txt"
        case "csv", "tsv":
            return "csv"
        case "json":
            return "json"
        case "xml", "plist":
            return "xml"
        case "html", "htm":
            return "html"
        case "yaml", "yml":
            return "yaml"
        case "swift":
            return "swift"
        case "c":
            return "c"
        case "h", "hh", "hpp":
            return "h"
        case "m":
            return "m"
        case "mm":
            return "mm"
        case "js", "mjs", "cjs":
            return "js"
        case "ts", "mts", "cts":
            return "ts"
        case "jsx":
            return "jsx"
        case "tsx":
            return "tsx"
        case "py":
            return "py"
        case "sh", "bash", "zsh", "fish":
            return "sh"
        case "sql":
            return "sql"
        case "zip":
            return "zip"
        case "gz", "tgz":
            return "gz"
        case "tar":
            return "tar"
        case "7z":
            return "7z"
        case "rar":
            return "rar"
        case "dmg":
            return "dmg"
        case "pkg":
            return "pkg"
        case "iso":
            return "iso"
        case "pages":
            return "pages"
        case "numbers":
            return "numbers"
        case "key":
            return "key"
        case "doc":
            return "doc"
        case "docx":
            return "docx"
        case "dotx":
            return "dotx"
        case "xls":
            return "xls"
        case "xlsx":
            return "xlsx"
        case "xlsm":
            return "xlsm"
        case "xltx":
            return "xltx"
        case "ppt":
            return "ppt"
        case "pptx":
            return "pptx"
        case "odp":
            return "odp"
        case "odt":
            return "odt"
        case "ods":
            return "ods"
        case "png":
            return "png"
        case "jpg", "jpeg", "jpe":
            return "jpg"
        case "gif":
            return "gif"
        case "webp":
            return "webp"
        case "heic":
            return "heic"
        case "heif":
            return "heif"
        case "tif", "tiff":
            return "tiff"
        case "bmp":
            return "bmp"
        case "svg":
            return "svg"
        case "psd":
            return "psd"
        case "mp3":
            return "mp3"
        case "aac":
            return "aac"
        case "m4a":
            return "m4a"
        case "wav":
            return "wav"
        case "aiff", "aif":
            return "aiff"
        case "flac":
            return "flac"
        case "mp4":
            return "mp4"
        case "m4v":
            return "m4v"
        case "mov":
            return "mov"
        case "avi":
            return "avi"
        case "mkv":
            return "mkv"
        case "webm":
            return "webm"
        case "srt":
            return "srt"
        case "vtt":
            return "vtt"
        default:
            return nil
        }
    }
}

private final class ClipboardCodeLineCache {
    static let shared = ClipboardCodeLineCache()

    private let cache = NSCache<NSString, NSArray>()

    private init() {
        cache.countLimit = 256
    }

    func lines(for record: ClipboardRecord) -> [String] {
        let key = (record.contentHash ?? record.objectID.uriRepresentation().absoluteString) as NSString
        if let cached = cache.object(forKey: key) as? [String] {
            return cached
        }

        let text = record.detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let result = lines.isEmpty ? [text] : lines
        cache.setObject(result as NSArray, forKey: key)
        return result
    }
}

final class ClipboardMonitor: ObservableObject {
    private let context: NSManagedObjectContext
    private let processingQueue = DispatchQueue(label: "cn.maxcj.ClipDock.clipboard.processing", qos: .userInitiated)
    private var timer: Timer?
    private var cleanupTimer: Timer?
    private var lastChangeCount: Int = -1
    private var lastRecordedHash: String?
    private var suppressionChangeCount: Int?
    private var isProcessingSnapshot = false

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func start() {
        guard timer == nil else { return }
        lastRecordedHash = fetchLatestHash()
        lastChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pruneExpiredRecords()
        }
        if let cleanupTimer {
            RunLoop.main.add(cleanupTimer, forMode: .common)
        }
        pruneExpiredRecords()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    func copy(_ record: ClipboardRecord) {
        guard let kind = ClipboardContentKind(rawValue: record.contentTypeRaw ?? "") else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch kind {
        case .text, .code, .unknown:
            pasteboard.setString(record.fullText ?? record.displayText ?? "", forType: .string)
        case .link:
            let value = record.fullText ?? record.displayText ?? ""
            pasteboard.setString(value, forType: .string)
            if let url = URL(string: value) {
                pasteboard.writeObjects([url as NSURL])
            }
        case .files:
            if let assetPath = record.assetPathValue,
               let urls = Self.fileURLs(in: URL(fileURLWithPath: assetPath)),
               !urls.isEmpty {
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            } else if let text = record.fullText ?? record.displayText {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let imagePath = record.imagePath, let image = ClipboardImageCache.shared.image(at: imagePath) {
                pasteboard.writeObjects([image])
            }
        }

        markSuppression(changeCount: pasteboard.changeCount)
    }

    private func poll() {
        guard !isProcessingSnapshot else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        isProcessingSnapshot = true

        processingQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let snapshot = self.captureSnapshot(from: pasteboard)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    defer { self.isProcessingSnapshot = false }

                    guard let snapshot else { return }

                    if let suppressionChangeCount,
                       pasteboard.changeCount == suppressionChangeCount {
                        self.suppressionChangeCount = nil
                        return
                    }

                    if snapshot.hash == lastRecordedHash {
                        return
                    }

                    self.insert(snapshot: snapshot)
                    self.lastRecordedHash = snapshot.hash
                }
            }
        }
    }

    private func captureSnapshot(from pasteboard: NSPasteboard) -> ClipboardSnapshot? {
        let appName = currentFrontmostApplicationName()
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            let names = fileURLs.map { $0.lastPathComponent }
            let fullText = fileURLs.map(\.path).joined(separator: "\n")
            let isSingleImageFile = fileURLs.count == 1 && Self.imageFileExtensions.contains(fileURLs[0].pathExtension.lowercased())

            if isSingleImageFile, let imageData = try? Data(contentsOf: fileURLs[0]), let image = NSImage(data: imageData) ?? NSImage(contentsOf: fileURLs[0]), let assets = saveImageAssets(from: image) {
                return ClipboardSnapshot(
                    kind: .image,
                    displayText: "Image",
                    fullText: assets.original.path,
                    imagePath: assets.original.path,
                    assetPath: nil,
                    thumbnailPath: assets.thumbnail.path,
                    sourceAppName: appName,
                    sourceBundleId: bundleId,
                    hash: Self.hash(kind: .image, data: imageData)
                )
            }

            return ClipboardSnapshot(
                kind: .files,
                displayText: names.joined(separator: ", "),
                fullText: fullText,
                imagePath: nil,
                assetPath: saveFileAssets(from: fileURLs)?.path,
                thumbnailPath: nil,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .files, text: fullText)
            )
        }

        if let image = NSImage(pasteboard: pasteboard), let assets = saveImageAssets(from: image) {
            return ClipboardSnapshot(
                kind: .image,
                displayText: "Image",
                fullText: assets.original.path,
                imagePath: assets.original.path,
                assetPath: nil,
                thumbnailPath: assets.thumbnail.path,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .image, data: assets.originalData)
            )
        }

        let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)
        if let urlText = pasteboard.string(forType: urlType), !urlText.isEmpty {
            return ClipboardSnapshot(
                kind: .link,
                displayText: urlText,
                fullText: urlText,
                imagePath: nil,
                assetPath: nil,
                thumbnailPath: nil,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .link, text: urlText)
            )
        }

        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: ClipboardContentKind
            if isLikelyURL(trimmed) {
                kind = .link
            } else if isLikelyCode(trimmed) {
                kind = .code
            } else {
                kind = .text
            }
            return ClipboardSnapshot(
                kind: kind,
                displayText: previewText(from: trimmed),
                fullText: trimmed,
                imagePath: nil,
                assetPath: nil,
                thumbnailPath: nil,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: kind, text: trimmed)
            )
        }

        return nil
    }

    private func insert(snapshot: ClipboardSnapshot) {
        context.perform {
            let record = ClipboardRecord(context: self.context)
            record.id = UUID()
            record.createdAt = Date()
            record.updatedAt = Date()
            record.lastUsedAt = nil
            record.contentTypeRaw = snapshot.kind.rawValue
            record.displayText = snapshot.displayText
            record.fullText = snapshot.fullText
            record.imagePath = snapshot.imagePath
            record.setValue(snapshot.assetPath, forKey: "assetPath")
            record.setValue(snapshot.thumbnailPath, forKey: "thumbnailPath")
            record.sourceAppName = snapshot.sourceAppName
            record.sourceBundleId = snapshot.sourceBundleId
            record.contentHash = snapshot.hash
            record.isPinned = false
            record.isIgnored = false
            record.usageCount = 0

            do {
                try self.context.save()
                self.pruneExpiredRecordsLocked()
            } catch {
                NSLog("Failed to save clipboard record: \(error.localizedDescription)")
            }
        }
    }

    private func pruneExpiredRecords() {
        context.perform { [weak self] in
            self?.pruneExpiredRecordsLocked()
        }
    }

    private func pruneExpiredRecordsLocked() {
        let retention = RetentionRule.current()
        guard retention.isEnabled, let cutoff = retention.cutoffDate else { return }

        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isPinned == NO"),
            NSPredicate(format: "createdAt < %@", cutoff as NSDate)
        ])

        do {
            let expiredRecords = try self.context.fetch(request)
            expiredRecords.forEach { record in
                removeCachedAssets(for: record)
                self.context.delete(record)
            }
            if self.context.hasChanges {
                try self.context.save()
            }
        } catch {
            NSLog("Failed to prune clipboard history: \(error.localizedDescription)")
        }
    }

    private func saveImageAssets(from image: NSImage) -> SavedImageAssets? {
        let folderURL = Self.assetFolderURL()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            guard let originalData = image.pngData() else { return nil }

            let originalURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            try originalData.write(to: originalURL, options: .atomic)

            let thumbnailURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("thumb.png")
            if let thumbnailData = Self.thumbnailData(from: originalData, maxPixelSize: 420) {
                try thumbnailData.write(to: thumbnailURL, options: .atomic)
            } else {
                try originalData.write(to: thumbnailURL, options: .atomic)
            }

            return SavedImageAssets(original: originalURL, thumbnail: thumbnailURL, originalData: originalData)
        } catch {
            NSLog("Failed to save clipboard image: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveFileAssets(from urls: [URL]) -> URL? {
        let folderURL = Self.assetFolderURL().appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for sourceURL in urls {
                let destinationURL = folderURL.appendingPathComponent(sourceURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
            return folderURL
        } catch {
            NSLog("Failed to save clipboard files: \(error.localizedDescription)")
            return nil
        }
    }

    private func currentFrontmostApplicationName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func fetchLatestHash() -> String? {
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchLimit = 1
        do {
            return try context.fetch(request).first?.contentHash
        } catch {
            return nil
        }
    }

    private func markSuppression(changeCount: Int) {
        suppressionChangeCount = changeCount
    }

    private static func hash(kind: ClipboardContentKind, text: String) -> String {
        hash(kind: kind, data: Data(text.utf8))
    }

    private static func thumbnailData(from imageData: Data, maxPixelSize: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    private static func fileURLs(in folderURL: URL) -> [URL]? {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return nil
        }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func hash(kind: ClipboardContentKind, data: Data) -> String {
        let digest = SHA256.hash(data: Data(kind.rawValue.utf8) + data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func isLikelyCode(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }

        let codeKeywords = [
            "func ", "class ", "struct ", "enum ", "protocol ", "extension ",
            "import ", "let ", "var ", "const ", "public ", "private ",
            "if ", "for ", "while ", "switch ", "case ", "return ",
            "def ", "from ", "export ", "interface ", "typealias "
        ]
        let codeSymbols = ["{", "}", ";", "=>", "->", "==", "!=", "&&", "||", "<-", ":</", "</", "</", "(", ")", "[", "]"]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if lines.count >= 2 {
            if lines.contains(where: { $0.hasPrefix("    ") || $0.hasPrefix("\t") }) {
                return true
            }

            if lines.contains(where: { $0.contains("{") || $0.contains("}") || $0.contains(";") }) {
                return true
            }
        }

        let lowercased = trimmed.lowercased()
        if codeKeywords.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let symbolHits = codeSymbols.reduce(0) { count, symbol in
            count + (trimmed.contains(symbol) ? 1 : 0)
        }
        if symbolHits >= 2 {
            return true
        }

        if trimmed.contains("```") || trimmed.contains("    ") {
            return true
        }

        return false
    }

    private func previewText(from text: String) -> String {
        let limit = 120
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "…"
    }

    private func isLikelyURL(_ text: String) -> Bool {
        guard let url = URL(string: text) else { return false }
        return url.scheme != nil
    }

    private static func assetFolderURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let bundleName = Bundle.main.bundleIdentifier ?? "ClipDock"
        return base.appendingPathComponent(bundleName, isDirectory: true)
            .appendingPathComponent("ClipboardImages", isDirectory: true)
    }
}

final class GlobalHotkeyManager: ObservableObject {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x434C444B), id: 1)

    init() {
        installEventHandler()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRegistration()
        }
        refreshRegistration()
    }

    deinit {
        unregister()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func refreshRegistration() {
        unregister()

        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: "clipboard.hotkeyEnabled") as? Bool ?? true
        guard enabled else { return }

        let keyCode = UInt32(defaults.object(forKey: "clipboard.hotkeyKeyCode") as? Int ?? HotKeyConfiguration.defaultKeyCode)
        let modifiers = UInt32(defaults.object(forKey: "clipboard.hotkeyModifiers") as? Int ?? Int(HotKeyConfiguration.defaultModifiers))
        guard keyCode != 0, modifiers != 0 else { return }

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            self.hotKeyRef = hotKeyRef
        } else {
            NSLog("Failed to register global hotkey: \(status)")
        }
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        let eventType = EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                _ = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .clipDockTogglePanelRequested, object: nil)
                }
                return noErr
            },
            1,
            [eventType],
            userData,
            &eventHandler
        )

        if status != noErr {
            NSLog("Failed to install hotkey event handler: \(status)")
        }
    }
}

extension Notification.Name {
    static let clipDockTogglePanelRequested = Notification.Name("clipDockTogglePanelRequested")
    static let clipDockHidePanelRequested = Notification.Name("clipDockHidePanelRequested")
}

private struct ClipboardSnapshot {
    let kind: ClipboardContentKind
    let displayText: String
    let fullText: String?
    let imagePath: String?
    let assetPath: String?
    let thumbnailPath: String?
    let sourceAppName: String?
    let sourceBundleId: String?
    let hash: String
}

private struct SavedImageAssets {
    let original: URL
    let thumbnail: URL
    let originalData: Data
}

private func clipboardRecordDisplaysBefore(_ lhs: ClipboardRecord, _ rhs: ClipboardRecord) -> Bool {
    if lhs.isPinned != rhs.isPinned {
        return lhs.isPinned && !rhs.isPinned
    }

    let lhsAnchor = lhs.isPinned ? (lhs.updatedAt ?? lhs.createdAt ?? .distantPast) : (lhs.createdAt ?? .distantPast)
    let rhsAnchor = rhs.isPinned ? (rhs.updatedAt ?? rhs.createdAt ?? .distantPast) : (rhs.createdAt ?? .distantPast)
    if lhsAnchor != rhsAnchor {
        return lhsAnchor > rhsAnchor
    }

    return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
}

extension ClipboardRecord {
    var thumbnailPathValue: String? {
        get { value(forKey: "thumbnailPath") as? String }
        set { setValue(newValue, forKey: "thumbnailPath") }
    }

    var assetPathValue: String? {
        get { value(forKey: "assetPath") as? String }
        set { setValue(newValue, forKey: "assetPath") }
    }
}

extension ClipboardMonitor {
    fileprivate static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "avif", "icns"
    ]
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: layout.footerFontSize, weight: .semibold))
            .padding(.horizontal, max(12, layout.chipHorizontalPadding))
            .padding(.vertical, max(8, layout.chipVerticalPadding))
            .foregroundStyle(.white)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.76 : 1.0))
            .clipShape(Capsule())
    }
}

private struct SettingsSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(configuration.isPressed ? 0.56 : 0.80))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct DetailActionButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: layout.footerFontSize, weight: .semibold))
            .padding(.horizontal, max(12, layout.chipHorizontalPadding))
            .padding(.vertical, max(8, layout.chipVerticalPadding))
            .background(Color.white.opacity(configuration.isPressed ? 0.68 : 0.88))
            .clipShape(Capsule())
    }
}

private struct FooterButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: layout.footerFontSize, weight: .semibold))
            .padding(.horizontal, max(12, layout.chipHorizontalPadding))
            .padding(.vertical, max(8, layout.chipVerticalPadding))
            .background(Color.white.opacity(configuration.isPressed ? 0.58 : 0.82))
            .clipShape(Capsule())
    }
}

private struct CardIconButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: layout.iconSizeSmall, weight: .semibold))
            .frame(width: layout.actionButtonSize, height: layout.actionButtonSize)
            .background(Color.white.opacity(configuration.isPressed ? 0.55 : 0.90))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct IconButtonStyle: ButtonStyle {
    let layout: DashboardLayout

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.white.opacity(configuration.isPressed ? 0.55 : 0.84))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CircleToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(Color.white.opacity(configuration.isPressed ? 0.60 : 0.84))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 1))
    }
}

private struct PillToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .foregroundStyle(.primary)
            .background(Color.white.opacity(configuration.isPressed ? 0.62 : 0.80))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

private struct DotsToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(Color.white.opacity(configuration.isPressed ? 0.58 : 0.72))
            .clipShape(Circle())
    }
}
