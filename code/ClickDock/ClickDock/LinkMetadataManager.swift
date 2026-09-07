//
//  LinkMetadataManager.swift
//  ClipDock
//

import CoreData
import Foundation

private actor LinkMetadataFetchGate {
    private var inFlightRecordIDs: Set<String> = []

    func performIfAvailable(
        for key: String,
        operation: () async -> Void
    ) async {
        guard inFlightRecordIDs.insert(key).inserted else { return }
        defer { inFlightRecordIDs.remove(key) }
        await operation()
    }
}

private actor LinkMetadataRequestLimiter {
    private let maximumConcurrentRequests: Int
    private var runningCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maximumConcurrentRequests: Int) {
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

    func acquire() async {
        if runningCount < maximumConcurrentRequests {
            runningCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            runningCount = max(0, runningCount - 1)
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}

final class LinkMetadataManager {
    private static let requestLimiter = LinkMetadataRequestLimiter(maximumConcurrentRequests: 3)

    private let context: NSManagedObjectContext
    private let fetchGate = LinkMetadataFetchGate()

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func refreshMissingMetadata() {
        context.performAndWait {
            let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
            request.predicate = NSPredicate(
                format: "contentTypeRaw == %@ AND (linkTitle == nil OR linkIconData == nil OR linkMetadataCheckedAt == nil)",
                ClipboardContentKind.link.rawValue
            )
            request.fetchBatchSize = 25

            guard let records = try? self.context.fetch(request) else { return }
            for record in records {
                guard let url = record.linkURL else { continue }
                self.scheduleMetadataFetch(for: record.objectID, url: url)
            }
        }
    }

    func scheduleMetadataFetch(for recordID: NSManagedObjectID, url: URL) {
        guard LinkMetadataPrivacyPolicy.canFetchMetadata(for: url) else {
            NSLog("Skipped link metadata fetch for local or private URL: \(url.absoluteString)")
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let key = recordID.uriRepresentation().absoluteString
            await self.fetchGate.performIfAvailable(for: key) {
                await Self.requestLimiter.acquire()
                let metadata = await LinkMetadataFetcher.fetch(from: url)
                await Self.requestLimiter.release()
                self.apply(metadata: metadata, for: recordID, url: url)
            }
        }
    }

    private func apply(metadata: LinkMetadata?, for recordID: NSManagedObjectID, url: URL) {
        context.perform {
            guard let record = try? self.context.existingObject(with: recordID) as? ClipboardRecord,
                  record.kind == .link else {
                return
            }

            if let normalizedHost = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
               !normalizedHost.isEmpty {
                record.linkHostValue = normalizedHost
            }

            if let metadata {
                if let title = metadata.title, !title.isEmpty {
                    record.linkTitleValue = title
                }

                if let host = metadata.host, !host.isEmpty {
                    record.linkHostValue = host
                }

                if let iconData = metadata.iconData, !iconData.isEmpty {
                    record.linkIconDataValue = iconData
                }
            }

            record.linkMetadataCheckedAtValue = Date()

            do {
                try self.context.save()
            } catch {
                NSLog("Failed to save link metadata: \(error.localizedDescription)")
            }
        }
    }
}
