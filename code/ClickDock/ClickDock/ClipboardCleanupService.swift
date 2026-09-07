//
//  ClipboardCleanupService.swift
//  ClipDock
//

import CoreData
import Foundation

final class ClipboardCleanupService {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func pruneExpiredRecords() {
        context.perform { [weak self] in
            self?.pruneExpiredRecordsLocked()
        }
    }

    func pruneExpiredRecordsLocked() {
        let retention = RetentionRule.current()
        guard retention.isEnabled, let cutoff = retention.cutoffDate else { return }

        let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "isPinned == NO"),
            NSPredicate(format: "createdAt < %@", cutoff as NSDate)
        ])

        do {
            let expiredRecords = try context.fetch(request)
            expiredRecords.forEach { record in
                removeCachedAssets(for: record)
                context.delete(record)
            }
            if context.hasChanges {
                try context.save()
            }
        } catch {
            NSLog("Failed to prune clipboard history: \(error.localizedDescription)")
        }
    }
}
