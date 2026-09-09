//
//  StorageSummaryScheduler.swift
//  ClipDock
//

import Foundation
import CoreData
import Combine

@MainActor
final class StorageSummaryScheduler: ObservableObject {
    private let container: NSPersistentContainer
    private var timer: Timer?
    private var isStarted = false

    init(container: NSPersistentContainer) {
        self.container = container
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        scheduleNextFire()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isStarted = false
    }

    private func scheduleNextFire() {
        timer?.invalidate()

        let fireDate = Self.nextNoon(after: Date())
        let timer = Timer(fireAt: fireDate, interval: 0, target: self, selector: #selector(handleTimerFire), userInfo: nil, repeats: false)
        timer.tolerance = 60
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc
    private func handleTimerFire() {
        scheduleNextFire()
        rebuildStorageUsage()
    }

    private func rebuildStorageUsage() {
        let backgroundContext = container.newBackgroundContext()
        DispatchQueue.global(qos: .utility).async {
            ClipboardStorageCalculator.rebuildCachedSizes(context: backgroundContext)
            _ = ClipboardStorageCalculator.summary(context: backgroundContext)

            DispatchQueue.main.async {
                ClipboardStorageSummaryStore.recordUpdated()
                NotificationCenter.default.post(name: .clipDockStorageSummaryDidChange, object: nil)
            }
        }
    }

    private static func nextNoon(after date: Date) -> Date {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = .autoupdatingCurrent

        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        if todayNoon > date {
            return todayNoon
        }

        return calendar.date(byAdding: .day, value: 1, to: todayNoon) ?? todayNoon.addingTimeInterval(24 * 60 * 60)
    }
}
