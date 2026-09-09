//
//  ClipboardMonitor.swift
//  ClipDock
//

import AppKit
import Combine
import CoreData

final class ClipboardMonitor: ObservableObject {
    private let context: NSManagedObjectContext
    private let linkMetadataManager: LinkMetadataManager
    private let fileAssetCopyManager: FileAssetCopyManager
    private let captureService: ClipboardCaptureService
    private let repository: ClipboardRepository
    private let cleanupService: ClipboardCleanupService
    private let processingQueue = DispatchQueue(label: "cn.maxcj.ClipDock.clipboard.processing", qos: .userInitiated)
    private var timer: Timer?
    private var cleanupTimer: Timer?
    private var observedChangeCount: Int = -1
    private var suppressionChangeCount: Int?
    private var isProcessing = false
    private var hasPendingChange = false

    init(context: NSManagedObjectContext) {
        self.context = context
        self.linkMetadataManager = LinkMetadataManager(context: context)
        self.fileAssetCopyManager = FileAssetCopyManager(context: context)
        self.captureService = ClipboardCaptureService()
        self.repository = ClipboardRepository(context: context)
        self.cleanupService = ClipboardCleanupService(context: context)
    }

    func start() {
        guard timer == nil else { return }
        observedChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer!, forMode: .common)

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.cleanupService.pruneExpiredRecords()
        }
        if let cleanupTimer {
            RunLoop.main.add(cleanupTimer, forMode: .common)
        }
        cleanupService.pruneExpiredRecords()
        linkMetadataManager.refreshMissingMetadata()
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
        case .text, .code, .colors, .unknown:
            pasteboard.setString(record.fullText ?? record.displayText ?? "", forType: .string)
        case .link:
            let value = record.fullText ?? record.displayText ?? ""
            pasteboard.setString(value, forType: .string)
            if let url = URL(string: value) {
                pasteboard.writeObjects([url as NSURL])
            }
        case .files:
            let fileURLs = record.fileReferenceSet.preferredURLsForPasteboard
            if !fileURLs.isEmpty {
                pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
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

    func copyTextSilently(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markSuppression(changeCount: pasteboard.changeCount)
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != observedChangeCount else { return }

        observedChangeCount = pasteboard.changeCount
        hasPendingChange = true
        processPendingChangeIfNeeded()
    }

    private func processPendingChangeIfNeeded() {
        guard !isProcessing, hasPendingChange else { return }

        hasPendingChange = false
        isProcessing = true
        let pasteboard = NSPasteboard.general
        let capturedChangeCount = observedChangeCount

        processingQueue.async { [weak self] in
            guard let self else { return }
            autoreleasepool {
                let outcome = self.captureService.captureSnapshot(from: pasteboard)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    defer {
                        self.isProcessing = false
                        self.processPendingChangeIfNeeded()
                    }

                    switch outcome {
                    case .dropped(let reason):
                        self.logClipboardDrop(reason)
                    case .snapshot(let snapshot):
                        self.storeIfNeeded(snapshot, capturedChangeCount: capturedChangeCount)
                    }
                }
            }
        }
    }

    private func storeIfNeeded(_ snapshot: ClipboardSnapshot, capturedChangeCount: Int) {
        if let suppressionChangeCount, capturedChangeCount == suppressionChangeCount {
            self.suppressionChangeCount = nil
            logClipboardDrop("suppressed self-copy")
            return
        }

        repository.upsert(
            snapshot: snapshot,
            deduplicator: ClipboardDeduplicator(),
            fileAssetCopyManager: fileAssetCopyManager,
            linkMetadataManager: linkMetadataManager,
            cleanupService: cleanupService
        )
    }

    private func logClipboardDrop(_ reason: String) {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "-"
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        NSLog("Clipboard not recorded: \(reason) | app=\(appName) | bundle=\(bundleId)")
    }

    private func markSuppression(changeCount: Int) {
        suppressionChangeCount = changeCount
    }
}
