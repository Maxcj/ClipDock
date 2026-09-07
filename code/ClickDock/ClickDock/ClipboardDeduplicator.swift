//
//  ClipboardDeduplicator.swift
//  ClipDock
//

import Foundation

struct ClipboardDeduplicator {
    func preferredRecord(from records: [ClipboardRecord]) -> ClipboardRecord? {
        records.sorted(by: preferredDuplicateOrder).first
    }

    private func preferredDuplicateOrder(_ lhs: ClipboardRecord, _ rhs: ClipboardRecord) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        let lhsDate = lhs.createdAt ?? lhs.updatedAt ?? .distantPast
        let rhsDate = rhs.createdAt ?? rhs.updatedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate < rhsDate
        }

        return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
    }
}
