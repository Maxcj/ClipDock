//
//  Persistence.swift
//  ClickDock
//
//  Created by Maxcj on 2026/6/22.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    private static let sampleRows: [(displayText: String, fullText: String?, sourceAppName: String, kind: ClipboardContentKind, isPinned: Bool)] = [
        (
            displayText: "Design is not just what it looks like and feels like. Design is how it works.",
            fullText: "Design is not just what it looks like and feels like. Design is how it works.",
            sourceAppName: "Notes",
            kind: .text,
            isPinned: true
        ),
        (
            displayText: "Curated Interior Design",
            fullText: "https://archdaily.com/collection/minimal",
            sourceAppName: "Safari",
            kind: .link,
            isPinned: false
        ),
        (
            displayText: "Still Life - Interior",
            fullText: nil,
            sourceAppName: "Preview",
            kind: .image,
            isPinned: false
        ),
        (
            displayText: "Project Brief.pdf",
            fullText: nil,
            sourceAppName: "Finder",
            kind: .files,
            isPinned: false
        )
    ]

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        result.seedSampleRecordsIfNeeded(in: viewContext)
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "ClickDock")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true

        if !inMemory {
            seedSampleRecordsIfNeeded(in: container.viewContext)
        }
    }

    private func seedSampleRecordsIfNeeded(in context: NSManagedObjectContext) {
        do {
            let request = NSFetchRequest<ClipboardRecord>(entityName: "ClipboardRecord")
            request.fetchLimit = 1
            let existing = try context.fetch(request)
            guard existing.isEmpty else { return }
            Self.seedSamples(into: context)
            try context.save()
        } catch {
            NSLog("Failed to seed sample clipboard records: \(error.localizedDescription)")
        }
    }

    private static func seedSamples(into context: NSManagedObjectContext) {
        let timestamps = sampleRows.enumerated().map { index, _ in
            Calendar.current.date(byAdding: .minute, value: -(index * 8), to: Date()) ?? Date()
        }

        for (index, sample) in sampleRows.enumerated() {
            let record = ClipboardRecord(context: context)
            record.id = UUID()
            record.createdAt = timestamps[index]
            record.updatedAt = timestamps[index]
            record.lastUsedAt = nil
            record.contentTypeRaw = sample.kind.rawValue
            record.displayText = sample.displayText
            record.fullText = sample.fullText
            record.imagePath = nil
            record.sourceAppName = sample.sourceAppName
            record.sourceBundleId = nil
            record.contentHash = UUID().uuidString
            record.isPinned = sample.isPinned
            record.isIgnored = false
            record.usageCount = Int16(index)
        }
    }
}
