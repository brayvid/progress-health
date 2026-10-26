//
//  TimeSeriesTransforms.swift
//  Correlate
//
//  Created by Blake Rayvid on 4/12/25.
//

import Foundation

// MARK: - Synthetic Feature Transformation Mode
enum TransformType: String, CaseIterable, Identifiable, Codable {
    case raw = "Raw Series"
    case delta1Day = "1-Day Δ (Rate of Change)"
    case delta7Day = "7-Day Δ (Rate of Change)"
    case lag1Day = "Lag: 1 Day Ago (t-1)"
    case lag2Day = "Lag: 2 Days Ago (t-2)"
    case lag3Day = "Lag: 3 Days Ago (t-3)"
    case lag7Day = "Lag: 7 Days Ago (t-7)"
    
    var id: String { rawValue }
    
    var shortSuffix: String {
        switch self {
        case .raw: return ""
        case .delta1Day: return " [Δ1d]"
        case .delta7Day: return " [Δ7d]"
        case .lag1Day: return " [t-1d]"
        case .lag2Day: return " [t-2d]"
        case .lag3Day: return " [t-3d]"
        case .lag7Day: return " [t-7d]"
        }
    }
    
    var isLag: Bool {
        return self == .lag1Day || self == .lag2Day || self == .lag3Day || self == .lag7Day
    }
    
    var isDerivative: Bool {
        return self == .delta1Day || self == .delta7Day
    }
}

// MARK: - Feature Identifier for Correlation Matrix
struct FeatureIdentifier: Hashable, Identifiable, Codable {
    let metricId: String
    let transform: TransformType
    
    var id: String {
        "\(metricId)_\(transform.rawValue)"
    }
    
    func name(with catalogMetric: HealthMetricType?) -> String {
        let base = catalogMetric?.displayName ?? metricId
        return "\(base)\(transform.shortSuffix)"
    }
}

// MARK: - Predefined Linear Combination Specifications
struct LinearCombinationSpec: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let constituentMetricIds: [String]
    let operation: LinearOperation
    let unitLabel: String
    let icon: String
    let physiologicalDescription: String

    enum LinearOperation: String, Codable {
        case netCaloricBalance // Dietary - (Active + Basal)
        case caloricDeficit    // (Active + Basal) - Dietary
        case hrReserveDelta    // Walking HR - Resting HR
        case netCarbs          // Carbs - Fiber
    }
}

struct LinearCombinationsCatalog {
    static let specs: [LinearCombinationSpec] = [
        LinearCombinationSpec(
            id: "netCaloricBalance",
            displayName: "Net Caloric Balance [Diet - (Active + Basal)]",
            constituentMetricIds: ["dietaryEnergy", "activeEnergy", "basalEnergy"],
            operation: .netCaloricBalance,
            unitLabel: "kcal",
            icon: "fork.knife.circle.fill",
            physiologicalDescription: "Dietary intake minus Total Daily Energy Expenditure (Active + Basal Energy). Positive values indicate a true caloric surplus; negative values indicate a net deficit."
        ),
        LinearCombinationSpec(
            id: "caloricDeficit",
            displayName: "Calorie Deficit [(Active + Basal) - Diet]",
            constituentMetricIds: ["activeEnergy", "basalEnergy", "dietaryEnergy"],
            operation: .caloricDeficit,
            unitLabel: "kcal",
            icon: "flame.circle.fill",
            physiologicalDescription: "Total Daily Energy Expenditure (Active + Basal Energy) minus dietary intake. Positive values reflect net daily caloric deficit."
        ),
        LinearCombinationSpec(
            id: "heartRateReserveDelta",
            displayName: "Heart Rate Exertion Delta (Walking - Resting HR)",
            constituentMetricIds: ["walkingHeartRate", "restingHeartRate"],
            operation: .hrReserveDelta,
            unitLabel: "bpm",
            icon: "heart.and.waveform.fill",
            physiologicalDescription: "Difference between active walking heart rate and baseline resting heart rate. Captures daily cardiovascular exertion and autonomic stress."
        ),
        LinearCombinationSpec(
            id: "netCarbs",
            displayName: "Net Carbohydrates (Carbs - Fiber)",
            constituentMetricIds: ["carbohydrates", "fiber"],
            operation: .netCarbs,
            unitLabel: "g",
            icon: "leaf.circle.fill",
            physiologicalDescription: "Total carbohydrates minus indigestible dietary fiber."
        )
    ]

    /// Dynamically computes daily paired series for a linear combination spec
    static func computeSeries(spec: LinearCombinationSpec, dailySeries: [String: [Date: Double]]) -> [Date: Double]? {
        let calendar = Calendar.current

        switch spec.operation {
        case .netCaloricBalance, .caloricDeficit:
            // Needs dietaryEnergy and activeEnergy; basalEnergy is included if available or estimated from body mass / typical BMR
            guard let diet = dailySeries["dietaryEnergy"], !diet.isEmpty,
                  let active = dailySeries["activeEnergy"], !active.isEmpty else {
                return nil
            }

            let basal = dailySeries["basalEnergy"] ?? [:]
            let bodyMass = dailySeries["bodyMass"] ?? [:]

            // Average observed BMR or estimate ~1600 kcal default if Apple Watch basal burn is missing
            let fallbackBMR: Double
            if !basal.isEmpty {
                fallbackBMR = basal.values.reduce(0, +) / Double(basal.count)
            } else if let latestMass = bodyMass.values.first {
                // Katch-McArdle / Mifflin approximation: ~ 10 kcal / lb of body mass
                fallbackBMR = latestMass * 10.0
            } else {
                fallbackBMR = 1650.0
            }

            let commonDates = Set(diet.keys.map { calendar.startOfDay(for: $0) })
                .intersection(Set(active.keys.map { calendar.startOfDay(for: $0) }))

            guard commonDates.count >= 3 else { return nil }

            var result: [Date: Double] = [:]
            for date in commonDates {
                guard let dVal = diet[date], let aVal = active[date],
                      dVal.isFinite, aVal.isFinite else { continue }

                let bVal = basal[date] ?? fallbackBMR
                let tdee = aVal + bVal

                if spec.operation == .netCaloricBalance {
                    // Diet - (Active + Basal)
                    result[date] = dVal - tdee
                } else {
                    // (Active + Basal) - Diet
                    result[date] = tdee - dVal
                }
            }

            return result.isEmpty ? nil : result

        case .hrReserveDelta:
            guard let walking = dailySeries["walkingHeartRate"],
                  let resting = dailySeries["restingHeartRate"],
                  !walking.isEmpty, !resting.isEmpty else {
                return nil
            }

            let commonDates = Set(walking.keys.map { calendar.startOfDay(for: $0) })
                .intersection(Set(resting.keys.map { calendar.startOfDay(for: $0) }))

            guard commonDates.count >= 3 else { return nil }
            var result: [Date: Double] = [:]
            for date in commonDates {
                if let w = walking[date], let r = resting[date], w.isFinite, r.isFinite {
                    result[date] = w - r
                }
            }
            return result.isEmpty ? nil : result

        case .netCarbs:
            guard let carbs = dailySeries["carbohydrates"], !carbs.isEmpty else { return nil }
            let fiber = dailySeries["fiber"] ?? [:]
            var result: [Date: Double] = [:]

            for (date, cVal) in carbs {
                let norm = calendar.startOfDay(for: date)
                let fVal = fiber[norm] ?? 0.0
                result[norm] = max(0.0, cVal - fVal)
            }
            return result.isEmpty ? nil : result
        }
    }
}

// MARK: - Mathematical Transformations & Linear Interpolation
struct TimeSeriesTransforms {
    
    /// Linearly interpolates missing days between discrete measurements.
    static func linearlyInterpolated(dailySeries: [Date: Double], maxGapDays: Int = 21) -> [Date: Double] {
        guard dailySeries.count >= 2 else { return dailySeries }
        let calendar = Calendar.current

        var normalized: [Date: Double] = [:]
        for (date, val) in dailySeries {
            let start = calendar.startOfDay(for: date)
            normalized[start] = val
        }

        let sortedDates = normalized.keys.sorted()
        var interpolated = normalized

        for i in 0..<(sortedDates.count - 1) {
            let d0 = sortedDates[i]
            let d1 = sortedDates[i + 1]
            guard let v0 = normalized[d0], let v1 = normalized[d1] else { continue }

            let gap = calendar.dateComponents([.day], from: d0, to: d1).day ?? 0
            if gap > 1 && gap <= maxGapDays {
                for step in 1..<gap {
                    if let interpolatedDate = calendar.date(byAdding: .day, value: step, to: d0) {
                        let fraction = Double(step) / Double(gap)
                        let interpolatedVal = v0 + fraction * (v1 - v0)
                        interpolated[interpolatedDate] = interpolatedVal
                    }
                }
            }
        }

        return interpolated
    }
    
    /// Applies numerical derivative or time-lag transformations to a daily series
    static func transform(dailySeries: [Date: Double], type: TransformType, interpolateGaps: Bool = true) -> [Date: Double] {
        guard !dailySeries.isEmpty else { return [:] }
        let calendar = Calendar.current
        
        let workingSeries: [Date: Double]
        if interpolateGaps && (type.isDerivative || dailySeries.count < 45) {
            workingSeries = linearlyInterpolated(dailySeries: dailySeries, maxGapDays: 21)
        } else {
            var norm: [Date: Double] = [:]
            for (date, val) in dailySeries {
                norm[calendar.startOfDay(for: date)] = val
            }
            workingSeries = norm
        }

        let sortedDates = workingSeries.keys.sorted()
        var transformed: [Date: Double] = [:]

        switch type {
        case .raw:
            return workingSeries

        case .delta1Day:
            for i in 1..<sortedDates.count {
                let currentDate = sortedDates[i]
                let prevDate = sortedDates[i - 1]
                let dayDiff = calendar.dateComponents([.day], from: prevDate, to: currentDate).day ?? 0
                if dayDiff == 1 {
                    let vCurrent = workingSeries[currentDate]!
                    let vPrev = workingSeries[prevDate]!
                    transformed[currentDate] = vCurrent - vPrev
                }
            }

        case .delta7Day:
            for i in 0..<sortedDates.count {
                let currentDate = sortedDates[i]
                if let date7dAgo = calendar.date(byAdding: .day, value: -7, to: currentDate),
                   let v7dAgo = workingSeries[date7dAgo],
                   let vCurrent = workingSeries[currentDate] {
                    transformed[currentDate] = vCurrent - v7dAgo
                }
            }

        case .lag1Day:
            for (date, val) in workingSeries {
                if let shifted = calendar.date(byAdding: .day, value: 1, to: date) {
                    transformed[shifted] = val
                }
            }

        case .lag2Day:
            for (date, val) in workingSeries {
                if let shifted = calendar.date(byAdding: .day, value: 2, to: date) {
                    transformed[shifted] = val
                }
            }

        case .lag3Day:
            for (date, val) in workingSeries {
                if let shifted = calendar.date(byAdding: .day, value: 3, to: date) {
                    transformed[shifted] = val
                }
            }

        case .lag7Day:
            for (date, val) in workingSeries {
                if let shifted = calendar.date(byAdding: .day, value: 7, to: date) {
                    transformed[shifted] = val
                }
            }
        }

        return transformed
    }

    /// Pearson correlation coefficient r between two series paired on common dates
    static func pearsonCorrelation(seriesA: [Date: Double], seriesB: [Date: Double]) -> (r: Double, points: [(date: Date, x: Double, y: Double)], n: Int)? {
        let calendar = Calendar.current
        
        let cleanA = Dictionary(uniqueKeysWithValues: seriesA.map { (calendar.startOfDay(for: $0.key), $0.value) })
        let cleanB = Dictionary(uniqueKeysWithValues: seriesB.map { (calendar.startOfDay(for: $0.key), $0.value) })
        
        let commonDates = Set(cleanA.keys).intersection(cleanB.keys)
        guard commonDates.count >= 4 else { return nil }
        
        let pairs: [(date: Date, x: Double, y: Double)] = commonDates.compactMap { d in
            guard let valA = cleanA[d], let valB = cleanB[d],
                  valA.isFinite, valB.isFinite else { return nil }
            return (date: d, x: valA, y: valB)
        }.sorted { $0.date < $1.date }
        
        let n = Double(pairs.count)
        guard n >= 4 else { return nil }
        
        let x = pairs.map(\.x)
        let y = pairs.map(\.y)
        
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        let sumY2 = y.map { $0 * $0 }.reduce(0, +)
        
        let num = (n * sumXY) - (sumX * sumY)
        let varX = (n * sumX2) - (sumX * sumX)
        let varY = (n * sumY2) - (sumY * sumY)
        
        guard varX > 1e-12, varY > 1e-12 else { return nil }
        
        let den = sqrt(varX * varY)
        guard den > 0 else { return nil }
        
        let r = num / den
        guard r.isFinite else { return nil }
        
        return (r: max(-1.0, min(1.0, r)), points: pairs, n: pairs.count)
    }
}
