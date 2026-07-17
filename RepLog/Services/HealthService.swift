import Foundation
import HealthKit

/// Read-only Apple Health bridge: daily steps and active energy,
/// used to enrich weekly reports. Fails quietly when unauthorized.
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned)
        ]
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        return (try? await store.requestAuthorization(toShare: [], read: readTypes)) != nil
    }

    /// Daily totals for the given quantity over [start, start + days).
    private func dailyTotals(
        _ type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        days: Int
    ) async -> [Date: Double] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .day, value: days, to: startDay) else { return [:] }
        let predicate = HKQuery.predicateForSamples(withStart: startDay, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDay,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                var totals: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDay, to: end) { stats, _ in
                    if let sum = stats.sumQuantity() {
                        totals[stats.startDate] = sum.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    func averageDailySteps(from start: Date, days: Int) async -> Int? {
        let totals = await dailyTotals(HKQuantityType(.stepCount), unit: .count(), start: start, days: days)
        guard !totals.isEmpty else { return nil }
        return Int(totals.values.reduce(0, +) / Double(totals.count))
    }

    func averageDailyActiveEnergy(from start: Date, days: Int) async -> Int? {
        let totals = await dailyTotals(
            HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), start: start, days: days
        )
        guard !totals.isEmpty else { return nil }
        return Int(totals.values.reduce(0, +) / Double(totals.count))
    }
}
