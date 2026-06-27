//
//  ClipboardWorkspaceView.swift
//  ClipDock
//

import SwiftUI
import CoreData
import AppKit

struct SimpleClipboardWorkspaceView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var clipboardMonitor: ClipboardMonitor
    @AppStorage("clipboard.autoHideAfterCopy") private var autoHideAfterCopy = false

    @FetchRequest private var records: FetchedResults<ClipboardRecord>
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
    )
    private var categories: FetchedResults<ClipboardCategory>

    @Binding private var searchText: String
    @Binding private var categorySelection: ClipboardCategorySelection
    @Binding private var selectedRecordID: NSManagedObjectID?
    private let containerSize: CGSize
    private let onOpenSettings: () -> Void
    @State private var sidebarWidth: CGFloat = 520
    @State private var isSearchFieldFocused: Bool = false
    @State private var lastSelectedImageCachePaths: [String] = []
    @State private var isShowingCategoryAssignment = false
    private static let fetchBatchSize = 40

    private var layout: SimpleClipboardLayout { SimpleClipboardLayout(containerSize: containerSize) }

    init(
        searchText: Binding<String>,
        categorySelection: Binding<ClipboardCategorySelection>,
        selectedRecordID: Binding<NSManagedObjectID?>,
        containerSize: CGSize,
        onOpenSettings: @escaping () -> Void
    ) {
        self._searchText = searchText
        self._categorySelection = categorySelection
        self._selectedRecordID = selectedRecordID
        self.containerSize = containerSize
        self.onOpenSettings = onOpenSettings

        let predicate = ClipboardRecord.fetchPredicate(searchText: searchText.wrappedValue, categorySelection: categorySelection.wrappedValue)
        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.sortDescriptors = [
            NSSortDescriptor(key: "isPinned", ascending: false),
            NSSortDescriptor(key: "pinnedAt", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "updatedAt", ascending: false)
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
                categorySelection: $categorySelection,
                activeSelection: categorySelection,
                records: records,
                selectedRecordID: $selectedRecordID,
                searchFieldFocused: $isSearchFieldFocused,
                layout: layout,
                onCopy: copy(_:),
                onDelete: delete(_:),
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
                },
                onExcludeSourceApp: {
                    if let selectedRecord { excludeSourceApp(from: selectedRecord) }
                },
                onManageCategories: {
                    if selectedRecord != nil {
                        isShowingCategoryAssignment = true
                    }
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
            ClipboardCategoryManager.bootstrapSystemCategories(context: viewContext)
            syncSelection()
            syncSelectedImageCachePaths()
        }
        .onChange(of: categorySelection) { _ in
            syncSelection()
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
        .sheet(isPresented: $isShowingCategoryAssignment) {
            if let selectedRecord = currentSelectedRecord {
                ClipboardCategoryAssignmentView(record: selectedRecord)
            }
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
        records
            .filter { !ClipboardPrivacyRules.isExcluded(bundleIdentifier: $0.sourceBundleId) }
            .sorted(by: clipboardRecordDisplaysBefore)
    }

    private func syncSelection() {
        guard !displayOrderedRecords.isEmpty else {
            selectedRecordID = nil
            return
        }

        if let selectedRecordID,
           displayOrderedRecords.contains(where: { $0.objectID == selectedRecordID }) {
            return
        }

        selectedRecordID = displayOrderedRecords.first?.objectID
    }

    private func syncSelectedImageCachePaths() {
        if !lastSelectedImageCachePaths.isEmpty {
            ClipboardImageCache.shared.remove(paths: lastSelectedImageCachePaths)
        }
        lastSelectedImageCachePaths = currentSelectedRecord?.cachedImagePaths ?? []
    }

    private var navigationSelections: [ClipboardCategorySelection] {
        categories
            .filter { $0.isVisible || $0.systemCategoryKey == .all }
            .compactMap(\.selection)
    }

    private func moveRecordSelection(by offset: Int) {
        guard !displayOrderedRecords.isEmpty else { return }

        let currentIndex = displayOrderedRecords.firstIndex(where: { $0.objectID == selectedRecordID }) ?? displayOrderedRecords.startIndex
        let nextIndex = min(max(displayOrderedRecords.index(currentIndex, offsetBy: offset, limitedBy: displayOrderedRecords.index(before: displayOrderedRecords.endIndex)) ?? currentIndex, displayOrderedRecords.startIndex), displayOrderedRecords.index(before: displayOrderedRecords.endIndex))
        selectedRecordID = displayOrderedRecords[nextIndex].objectID
    }

    private func moveFilterSelection(by offset: Int) {
        guard let currentIndex = navigationSelections.firstIndex(of: categorySelection) else { return }

        let nextIndex = min(
            max(currentIndex + offset, navigationSelections.startIndex),
            navigationSelections.index(before: navigationSelections.endIndex)
        )
        categorySelection = navigationSelections[nextIndex]
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
        record.pinnedAtValue = record.isPinned ? Date() : nil
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
            matches.forEach { removeCachedAssets(for: $0) ; viewContext.delete($0) }
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

    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            NSLog("Failed to save clipboard context: \(error.localizedDescription)")
        }
    }
}
