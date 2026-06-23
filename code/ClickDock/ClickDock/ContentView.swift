//
//  ContentView.swift
//  ClickDock
//
//  Created by Maxcj on 2026/6/22.
//

import SwiftUI
import CoreData
import AppKit
import CryptoKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor

    @State private var searchText = ""
    @State private var filter: ClipboardFilter = .all
    @State private var selectedRecordID: NSManagedObjectID?
    @State private var hasConfiguredWindow = false
    @State private var isSettingsPresented = false
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
                        isSettingsPresented = true
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                WindowChromeOverlay(window: windowRef, layout: layout, onOpenSettings: {
                    isSettingsPresented = true
                })
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
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
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

}

struct WindowChromeOverlay: View {
    let window: NSWindow?
    let layout: SimpleClipboardLayout
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: layout.chromeButtonSpacing) {
            ChromeButton(color: Color(red: 1.0, green: 0.37, blue: 0.31), symbolName: "xmark", size: layout.chromeButtonSize) {
                window?.performClose(nil)
            }

            ChromeButton(color: Color(red: 1.0, green: 0.80, blue: 0.20), symbolName: "minus", size: layout.chromeButtonSize) {
                window?.miniaturize(nil)
            }

            ChromeButton(color: Color(red: 0.20, green: 0.78, blue: 0.33), symbolName: "plus", size: layout.chromeButtonSize) {
                window?.zoom(nil)
            }

            Spacer(minLength: 0)

            Button(action: onOpenSettings) {
                Image(systemName: "ellipsis")
                    .font(.system(size: layout.chromeSettingsIconSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: layout.chromeSettingsButtonSize, height: layout.chromeSettingsButtonSize)
                    .background(
                        RoundedRectangle(cornerRadius: layout.chromeSettingsButtonCornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(Color.white.opacity(0.14))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: layout.chromeSettingsButtonCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: layout.chromeSettingsButtonCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Settings")
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

    @FetchRequest private var records: FetchedResults<ClipboardRecord>

    @Binding private var searchText: String
    @Binding private var filterSelection: ClipboardFilter
    @Binding private var selectedRecordID: NSManagedObjectID?
    private let activeFilter: ClipboardFilter
    private let containerSize: CGSize
    private let onOpenSettings: () -> Void
    @State private var sidebarWidth: CGFloat = 520
    @State private var isSearchFieldFocused: Bool = false

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
                onTogglePin: togglePin(_:),
                onOpenSettings: onOpenSettings
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
        }
        .onChange(of: records.count) { _ in
            syncSelection()
        }
        .onChange(of: searchText) { _ in
            syncSelection()
        }
    }

    private var currentSelectedRecord: ClipboardRecord? {
        if let selectedRecordID,
           let record = records.first(where: { $0.objectID == selectedRecordID }) {
            return record
        }
        return records.first
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

    private var navigationFilters: [ClipboardFilter] {
        [.all, .text, .links, .images, .files]
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
    }

    private func togglePin(_ record: ClipboardRecord) {
        record.isPinned.toggle()
        record.updatedAt = Date()
        saveContext()
    }

    private func delete(_ record: ClipboardRecord) {
        viewContext.delete(record)
        saveContext()

        if selectedRecordID == record.objectID {
            selectedRecordID = nil
        }

        syncSelection()
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
    let onTogglePin: (ClipboardRecord) -> Void
    let onOpenSettings: () -> Void
    @FocusState private var isSearchFieldFocused: Bool

    private let visibleFilters: [ClipboardFilter] = [.all, .text, .links, .images, .files]

    var body: some View {
        VStack(alignment: .leading, spacing: layout.sidebarSpacing) {
            HStack(spacing: 10) {
                searchField

                Button {
                    filterSelection = activeFilter == .all ? .files : .all
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: layout.searchIconSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: layout.searchHeight, height: layout.searchHeight)
                        .background(Color.white.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: layout.searchCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: layout.searchCornerRadius, style: .continuous)
                                .stroke(Color.black.opacity(0.07), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
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

            Text("Today")
                .font(.system(size: layout.sectionLabelSize, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.92))
                .padding(.top, 2)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: layout.rowSpacing) {
                        ForEach(records, id: \.objectID) { record in
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
                                onTogglePin: {
                                    onTogglePin(record)
                                }
                            )
                            .id(record.objectID)
                        }
                    }
                    .padding(.trailing, 2)
                }
                .onAppear {
                    scrollToSelectedRecord(using: proxy)
                }
                .onChange(of: selectedRecordID) { _ in
                    scrollToSelectedRecord(using: proxy)
                }
                .onChange(of: records.count) { _ in
                    scrollToSelectedRecord(using: proxy)
                }
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

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘F")
                    .font(.system(size: layout.searchHintSize, weight: .medium))
                    .foregroundStyle(.secondary)
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

    private func scrollToSelectedRecord(using proxy: ScrollViewProxy) {
        guard let selectedRecordID else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(selectedRecordID, anchor: .center)
        }
    }
}

struct ClipboardHistoryRow: View {
    let record: ClipboardRecord
    let isSelected: Bool
    let layout: SimpleClipboardLayout
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: layout.rowContentGap) {
                    kindBadge

                    VStack(alignment: .leading, spacing: layout.rowTextSpacing) {
                        HStack(alignment: .center, spacing: 8) {
                            Circle()
                                .fill(record.kind.accent)
                                .frame(width: layout.rowStatusDotSize, height: layout.rowStatusDotSize)

                            Text(record.timeLabelShort)
                                .font(.system(size: layout.rowMetaSize))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)
                        }

                        Text(record.previewTitle)
                            .font(.system(size: layout.rowTitleSize, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(record.kind == .image ? 2 : 3)

                        if record.kind == .link {
                            Text(record.detailText)
                                .font(.system(size: layout.rowSubtitleSize))
                                .foregroundStyle(record.kind.accent)
                                .lineLimit(1)
                        } else {
                            Text(record.previewSubtitle)
                                .font(.system(size: layout.rowSubtitleSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(record.kind.title)
                            .font(.system(size: layout.rowTagSize, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.82))
                    }

                    if record.kind == .image, let preview = record.previewImage {
                        imageThumbnail(preview)
                    } else if record.kind == .files {
                        fileThumbnail
                    }
                }
                .padding(.horizontal, layout.rowPaddingX)
                .padding(.vertical, layout.rowPaddingY)
                .frame(maxWidth: .infinity, minHeight: layout.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                VStack(spacing: 8) {
                    Image(systemName: "doc")
                        .font(.system(size: layout.rowFileIconSize, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.82))

                    Text(record.kind.title.uppercased())
                        .font(.system(size: layout.rowTagSize, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            )
            .frame(width: layout.rowImagePreviewWidth, height: layout.rowImagePreviewHeight)
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(record.kind.accent.opacity(0.12))
                .overlay(
                    Image(systemName: record.kind.symbolName)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(record.kind.accent)
                )
                .frame(width: 42, height: 42)

            Text(record.kind.title)
                .font(.system(size: layout.detailLabelSize, weight: .medium))
                .foregroundStyle(record.kind.accent)

            Spacer()
        }
    }

    private func preview(for record: ClipboardRecord) -> some View {
        Group {
            switch record.kind {
            case .image:
                if let preview = record.previewImage {
                    VStack(alignment: .leading, spacing: 12) {
                        imagePreview(preview)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.94),
                                        Color(red: 0.89, green: 0.94, blue: 1.0).opacity(0.84)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                VStack(spacing: 10) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 34, weight: .regular))
                                        .foregroundStyle(.secondary.opacity(0.65))
                                    Text(record.previewTitle)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            )
                            .frame(height: 240)
                    }
                }
            case .link:
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
            case .files:
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(record.kind.accent.opacity(0.12))
                        .overlay(
                            Image(systemName: "doc")
                                .font(.system(size: 38, weight: .regular))
                                .foregroundStyle(record.kind.accent)
                        )
                        .frame(width: 120, height: 140)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(record.previewTitle)
                            .font(.system(size: 28, weight: .semibold))
                        Text("File ready to copy or open from Finder.")
                            .font(.system(size: layout.detailSubtitleSize))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .frame(height: 240, alignment: .center)
            case .text, .unknown:
                ScrollView(.vertical, showsIndicators: false) {
                    Text(record.detailText)
                        .font(.system(size: layout.previewTextSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
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
        VStack(spacing: 14) {
            ClipboardDetailMetaRow(title: "Source", value: record.previewSubtitle, layout: layout)
            ClipboardDetailMetaRow(title: "Copied", value: record.timeLabel, layout: layout)
            ClipboardDetailMetaRow(title: "Characters", value: "\(record.characterCount)", layout: layout)
            ClipboardDetailMetaRow(title: "Type", value: record.kind.title, layout: layout)
        }
        .padding(.top, 2)
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
        }
        .font(.system(size: layout.chipTextSize, weight: isSelected ? .semibold : .medium))
        .foregroundStyle(accentColor)
        .padding(.horizontal, layout.chipPaddingX)
        .frame(height: layout.chipHeight)
        .background(isSelected ? AnyShapeStyle(accentColor.opacity(0.10)) : AnyShapeStyle(Color.clear))
        .clipShape(Capsule())
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
    var chromeOverlayTopPadding: CGFloat { s(4) }
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
                    ForEach(records, id: \.objectID) { record in
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
           let record = records.first(where: { $0.objectID == selectedRecordID }) {
            return record
        }
        return nil
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
        viewContext.delete(record)
        saveContext()
        if selectedRecordID == record.objectID {
            selectedRecordID = nil
        }
    }

    private func clearAll() {
        for record in records {
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
            if record.kind == .image, let imagePath = record.imagePath, let nsImage = NSImage(contentsOfFile: imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
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

struct ClipboardCodePane: View {
    let record: ClipboardRecord

    private var contentLines: [String] {
        let text = record.detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if lines.isEmpty {
            return [text]
        }
        return Array(lines.prefix(8))
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(Array(contentLines.enumerated()), id: \.offset) { index, _ in
                        Text("\(index + 1)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .frame(height: 18)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(contentLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 18, alignment: .leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

                if record.kind == .image, let imagePath = record.imagePath, let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
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
    @AppStorage("clipboard.startAtLogin") private var startAtLogin = false
    @AppStorage("clipboard.keepImages") private var keepImages = true
    @AppStorage("clipboard.maxItems") private var maxItems = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title3.bold())
                    Text("Keep the app light and local.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.70))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Launch at login", isOn: $startAtLogin)
                    Toggle("Keep images in history", isOn: $keepImages)
                    HStack {
                        Text("Max items")
                        Spacer()
                        Stepper(value: $maxItems, in: 50...1000, step: 25) {
                            Text("\(maxItems)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Text("The first MVP stores clipboard data locally and listens in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 440, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
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
        case .all: return Color.secondary
        case .text: return Color(red: 0.20, green: 0.49, blue: 0.98)
        case .links: return Color(red: 0.16, green: 0.68, blue: 0.34)
        case .images: return Color(red: 0.42, green: 0.29, blue: 0.94)
        case .code: return Color(red: 0.20, green: 0.49, blue: 0.98)
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
    case files
    case unknown

    var title: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .image: return "Image"
        case .files: return "Files"
        case .unknown: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "text.quote"
        case .link: return "link"
        case .image: return "photo"
        case .files: return "doc"
        case .unknown: return "questionmark.circle"
        }
    }

    var accent: Color {
        switch self {
        case .text: return Color(red: 0.96, green: 0.48, blue: 0.18)
        case .link: return Color(red: 0.11, green: 0.66, blue: 0.53)
        case .image: return Color(red: 0.16, green: 0.54, blue: 0.96)
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
              let imagePath,
              let image = NSImage(contentsOfFile: imagePath) else {
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
        case .text, .unknown:
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
            predicates.append(NSPredicate(format: "contentTypeRaw == %@ OR contentTypeRaw == %@", ClipboardContentKind.text.rawValue, ClipboardContentKind.unknown.rawValue))
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

final class ClipboardMonitor: ObservableObject {
    private let context: NSManagedObjectContext
    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var lastRecordedHash: String?
    private var suppressionHash: String?
    private var suppressionExpiresAt: Date = .distantPast

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
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func copy(_ record: ClipboardRecord) {
        guard let kind = ClipboardContentKind(rawValue: record.contentTypeRaw ?? "") else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch kind {
        case .text, .unknown:
            pasteboard.setString(record.fullText ?? record.displayText ?? "", forType: .string)
        case .link:
            let value = record.fullText ?? record.displayText ?? ""
            pasteboard.setString(value, forType: .string)
            if let url = URL(string: value) {
                pasteboard.writeObjects([url as NSURL])
            }
        case .files:
            if let text = record.fullText ?? record.displayText {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let imagePath = record.imagePath, let image = NSImage(contentsOfFile: imagePath) {
                pasteboard.writeObjects([image])
            }
        }

        markSuppression(hash: record.contentHash)
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let snapshot = captureSnapshot(from: pasteboard) else { return }

        if let suppressionHash,
           suppressionHash == snapshot.hash,
           Date() < suppressionExpiresAt {
            return
        }

        if snapshot.hash == lastRecordedHash {
            return
        }

        insert(snapshot: snapshot)
        lastRecordedHash = snapshot.hash
    }

    private func captureSnapshot(from pasteboard: NSPasteboard) -> ClipboardSnapshot? {
        let appName = currentFrontmostApplicationName()
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !fileURLs.isEmpty {
            let names = fileURLs.map { $0.lastPathComponent }
            let fullText = fileURLs.map(\.path).joined(separator: "\n")
            return ClipboardSnapshot(
                kind: .files,
                displayText: names.joined(separator: ", "),
                fullText: fullText,
                imagePath: nil,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .files, text: fullText)
            )
        }

        if let image = NSImage(pasteboard: pasteboard), let data = image.pngData() {
            let path = saveImageData(data)
            return ClipboardSnapshot(
                kind: .image,
                displayText: "Image",
                fullText: path?.path,
                imagePath: path?.path,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .image, data: data)
            )
        }

        let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)
        if let urlText = pasteboard.string(forType: urlType), !urlText.isEmpty {
            return ClipboardSnapshot(
                kind: .link,
                displayText: urlText,
                fullText: urlText,
                imagePath: nil,
                sourceAppName: appName,
                sourceBundleId: bundleId,
                hash: Self.hash(kind: .link, text: urlText)
            )
        }

        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: ClipboardContentKind = isLikelyURL(trimmed) ? .link : .text
            return ClipboardSnapshot(
                kind: kind,
                displayText: previewText(from: trimmed),
                fullText: trimmed,
                imagePath: nil,
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
            record.sourceAppName = snapshot.sourceAppName
            record.sourceBundleId = snapshot.sourceBundleId
            record.contentHash = snapshot.hash
            record.isPinned = false
            record.isIgnored = false
            record.usageCount = 0

            do {
                try self.context.save()
                self.pruneIfNeededLocked()
            } catch {
                NSLog("Failed to save clipboard record: \(error.localizedDescription)")
            }
        }
    }

    private func pruneIfNeededLocked() {
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchOffset = 200

        do {
            let oldRecords = try self.context.fetch(request)
            oldRecords.forEach { self.context.delete($0) }
            if self.context.hasChanges {
                try self.context.save()
            }
        } catch {
            NSLog("Failed to prune clipboard history: \(error.localizedDescription)")
        }
    }

    private func saveImageData(_ data: Data) -> URL? {
        let folderURL = Self.assetFolderURL()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let fileURL = folderURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            NSLog("Failed to save clipboard image: \(error.localizedDescription)")
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

    private func markSuppression(hash: String?) {
        suppressionHash = hash
        suppressionExpiresAt = Date().addingTimeInterval(1.5)
    }

    private static func hash(kind: ClipboardContentKind, text: String) -> String {
        hash(kind: kind, data: Data(text.utf8))
    }

    private static func hash(kind: ClipboardContentKind, data: Data) -> String {
        let digest = SHA256.hash(data: Data(kind.rawValue.utf8) + data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
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

private struct ClipboardSnapshot {
    let kind: ClipboardContentKind
    let displayText: String
    let fullText: String?
    let imagePath: String?
    let sourceAppName: String?
    let sourceBundleId: String?
    let hash: String
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
