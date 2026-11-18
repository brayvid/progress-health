//
//  InsightsView.swift
//  Progress
//
//  Created by Blake Rayvid on 4/12/25.
//

import SwiftUI
import Charts
import HealthKit

// MARK: - Codable Point for Persistence
struct InsightDataPoint: Codable, Identifiable {
    var id: String { "\(date.timeIntervalSince1970)_\(x)_\(y)" }
    let date: Date
    let x: Double
    let y: Double
}

struct DiscoveredInsight: Identifiable, Codable {
    let id: UUID
    let featureA: FeatureIdentifier
    let featureB: FeatureIdentifier
    let metricIdA: String
    let metricIdB: String
    let r: Double
    let sampleSize: Int
    let dataPoints: [InsightDataPoint]

    var metricA: HealthMetricType {
        if let catalogMetric = HealthCatalog.allMetrics.first(where: { $0.id == metricIdA }) {
            return catalogMetric
        }
        if let comboSpec = LinearCombinationsCatalog.specs.first(where: { $0.id == metricIdA }) {
            return HealthMetricType(
                id: comboSpec.id,
                displayName: comboSpec.displayName,
                category: .activity,
                quantityIdentifier: nil,
                categoryIdentifier: nil,
                defaultUnit: .count(),
                unitLabel: comboSpec.unitLabel,
                aggregation: .cumulativeSum,
                icon: comboSpec.icon,
                color: .orange,
                defaultLineChart: false
            )
        }
        return HealthMetricType(
            id: metricIdA,
            displayName: metricIdA,
            category: .activity,
            quantityIdentifier: nil,
            categoryIdentifier: nil,
            defaultUnit: .count(),
            unitLabel: "",
            aggregation: .cumulativeSum,
            icon: "chart.xyaxis.line",
            color: .blue,
            defaultLineChart: false
        )
    }

    var metricB: HealthMetricType {
        if let catalogMetric = HealthCatalog.allMetrics.first(where: { $0.id == metricIdB }) {
            return catalogMetric
        }
        if let comboSpec = LinearCombinationsCatalog.specs.first(where: { $0.id == metricIdB }) {
            return HealthMetricType(
                id: comboSpec.id,
                displayName: comboSpec.displayName,
                category: .activity,
                quantityIdentifier: nil,
                categoryIdentifier: nil,
                defaultUnit: .count(),
                unitLabel: comboSpec.unitLabel,
                aggregation: .cumulativeSum,
                icon: comboSpec.icon,
                color: .orange,
                defaultLineChart: false
            )
        }
        return HealthMetricType(
            id: metricIdB,
            displayName: metricIdB,
            category: .activity,
            quantityIdentifier: nil,
            categoryIdentifier: nil,
            defaultUnit: .count(),
            unitLabel: "",
            aggregation: .cumulativeSum,
            icon: "chart.xyaxis.line",
            color: .blue,
            defaultLineChart: false
        )
    }

    var absR: Double { abs(r) }
    var isLeadLag: Bool { featureA.transform.isLag || featureB.transform.isLag }
    var isDerivative: Bool { featureA.transform.isDerivative || featureB.transform.isDerivative }
    var isRawOnly: Bool { !isLeadLag && !isDerivative }
    var containsRaw: Bool { featureA.transform == .raw || featureB.transform == .raw }
    var isBodyMassDelta: Bool {
        (metricIdA == "bodyMass" && featureA.transform.isDerivative) ||
        (metricIdB == "bodyMass" && featureB.transform.isDerivative)
    }
    
    var titleA: String {
        "\(metricA.displayName)\(featureA.transform.shortSuffix)"
    }
    
    var titleB: String {
        "\(metricB.displayName)\(featureB.transform.shortSuffix)"
    }
    
    var title: String {
        "\(titleA) vs \(titleB)"
    }

    var points: [(date: Date, x: Double, y: Double)] {
        dataPoints.map { ($0.date, $0.x, $0.y) }
    }

    init(
        id: UUID = UUID(),
        featureA: FeatureIdentifier,
        featureB: FeatureIdentifier,
        metricA: HealthMetricType,
        metricB: HealthMetricType,
        r: Double,
        sampleSize: Int,
        points: [(date: Date, x: Double, y: Double)]
    ) {
        self.id = id
        self.featureA = featureA
        self.featureB = featureB
        self.metricIdA = metricA.id
        self.metricIdB = metricB.id
        self.r = r
        self.sampleSize = sampleSize
        self.dataPoints = points.map { InsightDataPoint(date: $0.date, x: $0.x, y: $0.y) }
    }
}

// MARK: - Persistence Store Helper
struct InsightsPersistence {
    private static var fileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0]
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("cached_insights.json")
    }

    static func save(insights: [DiscoveredInsight]) {
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(insights)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                print("Failed to save insights to disk: \(error.localizedDescription)")
            }
        }
    }

    static func load() -> [DiscoveredInsight] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([DiscoveredInsight].self, from: data)
            return decoded
        } catch {
            print("Failed to load insights from disk: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Filter for Trivial / Co-linear Relationships
struct InsightFilters {
    private static let trivialPairs: Set<Set<String>> = [
        ["steps", "distanceWalkingRunning"],
        ["steps", "activeEnergy"],
        ["distanceWalkingRunning", "activeEnergy"],
        ["exerciseTime", "activeEnergy"],
        ["exerciseTime", "distanceWalkingRunning"],
        ["exerciseTime", "steps"],
        ["walkingSpeed", "walkingStepLength"],

        ["heartRate", "walkingHeartRate"],
        ["heartRate", "restingHeartRate"],
        ["restingHeartRate", "walkingHeartRate"],

        ["bodyMass", "bmi"],
        ["bodyMass", "leanBodyMass"],
        ["bmi", "leanBodyMass"],
        ["bodyMass", "bodyFat"],
        ["bmi", "bodyFat"],

        ["dietaryEnergy", "carbohydrates"],
        ["dietaryEnergy", "fat"],
        ["dietaryEnergy", "protein"],
        ["dietaryEnergy", "sugar"],
        ["carbohydrates", "sugar"],
        ["carbohydrates", "fiber"]
    ]

    static func isTrivial(metricA: String, metricB: String, transformA: TransformType, transformB: TransformType) -> Bool {
        if metricA == metricB { return true }
        if transformA.isLag && transformB.isLag { return true }

        let pair: Set<String> = [metricA, metricB]
        if trivialPairs.contains(pair) { return true }

        for spec in LinearCombinationsCatalog.specs {
            if (metricA == spec.id && spec.constituentMetricIds.contains(metricB)) ||
               (metricB == spec.id && spec.constituentMetricIds.contains(metricA)) {
                return true
            }
        }

        return false
    }
}

// MARK: - Sort and Filter Enums
enum InsightSortOption: String, CaseIterable, Identifiable {
    case correlationStrength = "Correlation Strength"
    case xAxis = "X-Axis Metric"
    case yAxis = "Y-Axis Metric"
    var id: String { rawValue }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case highToLow = "High → Low"
    case lowToHigh = "Low → High"
    var id: String { rawValue }
    var icon: String { self == .highToLow ? "arrow.down" : "arrow.up" }
}

enum PolarityFilter: String, CaseIterable, Identifiable {
    case all = "All (+/-)"
    case positiveOnly = "Positive (+)"
    case negativeOnly = "Inverse (-)"
    var id: String { rawValue }
}

struct TargetFeatureSelection: Equatable {
    let metric: HealthMetricType
    let transform: TransformType?
    
    var displayTitle: String {
        if let t = transform {
            return "\(metric.displayName) [\(t.rawValue)]"
        } else {
            return "\(metric.displayName) (Any Variant)"
        }
    }
}

// MARK: - Main Insights View
struct InsightsView: View {
    @EnvironmentObject var healthManager: HealthManager
    @State private var discoveredInsights: [DiscoveredInsight] = []
    @State private var isAnalyzing: Bool = false
    @State private var selectedInsightForDetail: DiscoveredInsight? = nil

    @State private var searchText: String = ""
    @State private var selectedTargetFeature: TargetFeatureSelection? = nil

    @State private var sortOption: InsightSortOption = .correlationStrength
    @State private var sortDirection: SortDirection = .highToLow
    @State private var polarityFilter: PolarityFilter = .all

    @State private var includeRaw: Bool = true
    @State private var includeRateOfChange: Bool = true
    @State private var includeLags: Bool = true

    private let availableTransforms: [TransformType] = [
        .raw,
        .delta1Day,
        .delta7Day,
        .delta14Day,
        .delta21Day,
        .lag1Day,
        .lag2Day
    ]

    private let defaultSuggestionIds: [String] = [
        "bodyMass",
        "caloricDeficit",
        "netCaloricBalance",
        "sleepDuration",
        "restingHeartRate",
        "hrv",
        "steps",
        "activeEnergy",
        "dietaryEnergy"
    ]

    var allAvailableMetrics: [HealthMetricType] {
        var list = HealthCatalog.allMetrics
        for spec in LinearCombinationsCatalog.specs {
            list.append(
                HealthMetricType(
                    id: spec.id,
                    displayName: spec.displayName,
                    category: .activity,
                    quantityIdentifier: nil,
                    categoryIdentifier: nil,
                    defaultUnit: .count(),
                    unitLabel: spec.unitLabel,
                    aggregation: .cumulativeSum,
                    icon: spec.icon,
                    color: .orange,
                    defaultLineChart: false
                )
            )
        }
        return list
    }

    var metricSuggestions: [HealthMetricType] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            let defaults = defaultSuggestionIds.compactMap { id in
                allAvailableMetrics.first { $0.id == id }
            }
            return defaults.isEmpty ? Array(allAvailableMetrics.prefix(8)) : defaults
        }
        return allAvailableMetrics.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.id.lowercased().contains(query) ||
            $0.category.rawValue.lowercased().contains(query)
        }
    }

    var processedInsights: [DiscoveredInsight] {
        let baseList: [DiscoveredInsight]
        if let target = selectedTargetFeature {
            baseList = discoveredInsights.filter { insight in
                let matchA: Bool
                let matchB: Bool
                if let specificTransform = target.transform {
                    matchA = (insight.metricIdA == target.metric.id && insight.featureA.transform == specificTransform)
                    matchB = (insight.metricIdB == target.metric.id && insight.featureB.transform == specificTransform)
                } else {
                    matchA = (insight.metricIdA == target.metric.id)
                    matchB = (insight.metricIdB == target.metric.id)
                }
                return matchA || matchB
            }
        } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            baseList = discoveredInsights.filter { insight in
                insight.title.lowercased().contains(q) ||
                insight.metricA.displayName.lowercased().contains(q) ||
                insight.metricB.displayName.lowercased().contains(q) ||
                insight.metricA.category.rawValue.lowercased().contains(q) ||
                insight.metricB.category.rawValue.lowercased().contains(q)
            }
        } else {
            baseList = discoveredInsights
        }

        var filtered = baseList.filter { insight in
            switch polarityFilter {
            case .all: break
            case .positiveOnly:
                guard insight.r > 0 else { return false }
            case .negativeOnly:
                guard insight.r < 0 else { return false }
            }

            if let target = selectedTargetFeature {
                let isTargetA: Bool
                if let specificTransform = target.transform {
                    isTargetA = (insight.metricIdA == target.metric.id && insight.featureA.transform == specificTransform)
                } else {
                    isTargetA = (insight.metricIdA == target.metric.id)
                }
                
                let partnerTransform = isTargetA ? insight.featureB.transform : insight.featureA.transform

                if !includeRaw && partnerTransform == .raw { return false }
                if !includeRateOfChange && partnerTransform.isDerivative { return false }
                if !includeLags && partnerTransform.isLag { return false }
                return true
            }

            func isTransformAllowed(_ t: TransformType) -> Bool {
                if t == .raw && !includeRaw { return false }
                if t.isDerivative && !includeRateOfChange { return false }
                if t.isLag && !includeLags { return false }
                return true
            }

            guard isTransformAllowed(insight.featureA.transform) &&
                  isTransformAllowed(insight.featureB.transform) else {
                return false
            }

            return true
        }

        filtered.sort { a, b in
            let ascending = (sortDirection == .lowToHigh)
            switch sortOption {
            case .correlationStrength:
                return ascending ? (a.absR < b.absR) : (a.absR > b.absR)
            case .xAxis:
                let comp = a.titleA.localizedCaseInsensitiveCompare(b.titleA)
                return ascending ? (comp == .orderedAscending) : (comp == .orderedDescending)
            case .yAxis:
                let comp = a.titleB.localizedCaseInsensitiveCompare(b.titleB)
                return ascending ? (comp == .orderedAscending) : (comp == .orderedDescending)
            }
        }

        return filtered
    }

    var body: some View {
        NavigationView {
            Group {
                if isAnalyzing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Cross-Analyzing Diet, Activity, Multi-Day Deltas & Combinations...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if discoveredInsights.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundColor(.yellow)
                        Text("No Connections Surfaced")
                            .font(.headline)
                        Text("Tap Scan below to run an automated search across raw data, calorie deficits, 7/14/21-day rates of change, and vitals.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button(action: runDeepAnalysis) {
                            Text("Run Auto-Discovery Scan")
                                .bold()
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        if let selected = selectedTargetFeature {
                            HStack {
                                Image(systemName: selected.metric.icon)
                                    .foregroundColor(selected.metric.color)
                                Text("Filtered: ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(selected.displayTitle)
                                    .font(.caption.bold())

                                Spacer()

                                Button(action: {
                                    selectedTargetFeature = nil
                                    searchText = ""
                                    dismissKeyboard()
                                }) {
                                    HStack(spacing: 3) {
                                        Text("Clear")
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                        }

                        // Header Controls Bar
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Menu {
                                    Picker("Sort By", selection: $sortOption) {
                                        ForEach(InsightSortOption.allCases) { opt in
                                            Text(opt.rawValue).tag(opt)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.arrow.down")
                                        Text(sortOption.rawValue)
                                            .lineLimit(1)
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                }

                                Button(action: toggleSortDirection) {
                                    HStack(spacing: 4) {
                                        Image(systemName: sortDirection.icon)
                                        Text(sortDirection == .highToLow ? "Hi → Lo" : "Lo → Hi")
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(8)
                                }

                                Spacer()

                                Menu {
                                    Picker("Polarity", selection: $polarityFilter) {
                                        ForEach(PolarityFilter.allCases) { pol in
                                            Text(pol.rawValue).tag(pol)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "slider.horizontal.3")
                                        Text(polarityFilter.rawValue)
                                    }
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(polarityFilter == .all ? Color(.secondarySystemBackground) : Color.blue.opacity(0.15))
                                    .foregroundColor(polarityFilter == .all ? .primary : .blue)
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)

                            // Three Toggles: Raw, Rates of Change (Δ), Lagged
                            HStack(spacing: 8) {
                                Button(action: { includeRaw.toggle() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: includeRaw ? "checkmark.circle.fill" : "circle")
                                        Text("Raw")
                                    }
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(includeRaw ? Color.blue.opacity(0.18) : Color(.secondarySystemBackground))
                                    .foregroundColor(includeRaw ? .blue : .secondary)
                                    .cornerRadius(16)
                                }

                                Button(action: { includeRateOfChange.toggle() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: includeRateOfChange ? "checkmark.circle.fill" : "circle")
                                        Text("Rates of Change (Δ)")
                                    }
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(includeRateOfChange ? Color.orange.opacity(0.18) : Color(.secondarySystemBackground))
                                    .foregroundColor(includeRateOfChange ? .orange : .secondary)
                                    .cornerRadius(16)
                                }

                                Button(action: { includeLags.toggle() }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: includeLags ? "checkmark.circle.fill" : "circle")
                                        Text("Lagged")
                                    }
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(includeLags ? Color.purple.opacity(0.18) : Color(.secondarySystemBackground))
                                    .foregroundColor(includeLags ? .purple : .secondary)
                                    .cornerRadius(16)
                                }

                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 6)
                        }
                        .background(Color(.systemBackground))

                        Divider()

                        // Insights List
                        List {
                            Section(header: Text("Surfaced Insights (\(processedInsights.count))")) {
                                if processedInsights.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("No matching insights found.")
                                            .font(.subheadline.bold())
                                        Text("Try enabling the Raw, Rates of Change, or Lagged toggles, or clearing active filters.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 8)
                                } else {
                                    ForEach(processedInsights) { insight in
                                        Button(action: { selectedInsightForDetail = insight }) {
                                            InsightRowCard(insight: insight)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("AI Insights")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search metric or combo (e.g. Deficit, Carbs, HR)"
            ) {
                if !metricSuggestions.isEmpty {
                    ForEach(metricSuggestions) { metric in
                        Section(header: Label(metric.displayName, systemImage: metric.icon)) {
                            Button(action: {
                                selectTarget(metric: metric, transform: nil)
                            }) {
                                HStack {
                                    Text("\(metric.displayName) (Any Variant)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("All")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            ForEach(availableTransforms) { transform in
                                Button(action: {
                                    selectTarget(metric: metric, transform: transform)
                                }) {
                                    HStack {
                                        Text("\(metric.displayName)\(transform.shortSuffix)")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text(transform.rawValue)
                                            .font(.caption2.bold())
                                            .foregroundColor(transform.isDerivative ? .orange : (transform.isLag ? .purple : .blue))
                                    }
                                    .padding(.leading, 8)
                                }
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: runDeepAnalysis) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isAnalyzing)
                }
            }
            .sheet(item: $selectedInsightForDetail) { insight in
                InsightDetailModal(insight: insight)
            }
            .onAppear {
                if discoveredInsights.isEmpty {
                    let cached = InsightsPersistence.load()
                    if !cached.isEmpty {
                        self.discoveredInsights = cached
                    } else if !healthManager.dailySeries.isEmpty {
                        runDeepAnalysis()
                    }
                }
            }
        }
    }

    private func selectTarget(metric: HealthMetricType, transform: TransformType?) {
        selectedTargetFeature = TargetFeatureSelection(metric: metric, transform: transform)
        searchText = ""
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func toggleSortDirection() {
        sortDirection = (sortDirection == .highToLow) ? .lowToHigh : .highToLow
    }

    func runDeepAnalysis() {
        isAnalyzing = true
        DispatchQueue.global(qos: .userInitiated).async {
            var candidateFeatures: [(feature: FeatureIdentifier, metric: HealthMetricType, series: [Date: Double])] = []

            let activeMetrics = HealthCatalog.allMetrics.filter {
                guard let data = healthManager.dailySeries[$0.id] else { return false }
                return data.count >= 2
            }

            for m in activeMetrics {
                guard let baseDaily = healthManager.dailySeries[m.id], !baseDaily.isEmpty else { continue }

                // NEW:
                let isDiscrete: Bool = {
                    switch m.aggregation {
                    case .averageDiscrete: return true
                    default: return false
                    }
                }()
                let isBody: Bool = {
                    switch m.category {
                    case .body: return true
                    default: return false
                    }
                }()
                let shouldInterpolate = isDiscrete || isBody
                let workingRaw = shouldInterpolate ? TimeSeriesTransforms.linearlyInterpolated(dailySeries: baseDaily) : baseDaily

                // Raw Series
                candidateFeatures.append((
                    FeatureIdentifier(metricId: m.id, transform: .raw),
                    m,
                    workingRaw
                ))

                // Rates of Change: 1-Day, 7-Day, 14-Day, 21-Day
                for deltaType in [TransformType.delta1Day, TransformType.delta7Day, TransformType.delta14Day, TransformType.delta21Day] {
                    let deltaN = TimeSeriesTransforms.transform(dailySeries: baseDaily, type: deltaType, interpolateGaps: shouldInterpolate)
                    if deltaN.count >= 3 {
                        candidateFeatures.append((
                            FeatureIdentifier(metricId: m.id, transform: deltaType),
                            m,
                            deltaN
                        ))
                    }
                }

                // Time Lags (t-1, t-2, t-7)
                for lagType in [TransformType.lag1Day, TransformType.lag2Day, TransformType.lag7Day] {
                    let lagN = TimeSeriesTransforms.transform(dailySeries: baseDaily, type: lagType, interpolateGaps: shouldInterpolate)
                    if lagN.count >= 3 {
                        candidateFeatures.append((
                            FeatureIdentifier(metricId: m.id, transform: lagType),
                            m,
                            lagN
                        ))
                    }
                }
            }

            // Synthesize Linear Combinations
            for spec in LinearCombinationsCatalog.specs {
                if let comboDaily = LinearCombinationsCatalog.computeSeries(spec: spec, dailySeries: healthManager.dailySeries) {
                    let syntheticMetric = HealthMetricType(
                        id: spec.id,
                        displayName: spec.displayName,
                        category: .activity,
                        quantityIdentifier: nil,
                        categoryIdentifier: nil,
                        defaultUnit: .count(),
                        unitLabel: spec.unitLabel,
                        aggregation: .cumulativeSum,
                        icon: spec.icon,
                        color: .orange,
                        defaultLineChart: false
                    )

                    candidateFeatures.append((
                        FeatureIdentifier(metricId: spec.id, transform: .raw),
                        syntheticMetric,
                        comboDaily
                    ))

                    for deltaType in [TransformType.delta1Day, TransformType.delta7Day, TransformType.delta14Day, TransformType.delta21Day] {
                        let deltaN = TimeSeriesTransforms.transform(dailySeries: comboDaily, type: deltaType, interpolateGaps: false)
                        if deltaN.count >= 3 {
                            candidateFeatures.append((
                                FeatureIdentifier(metricId: spec.id, transform: deltaType),
                                syntheticMetric,
                                deltaN
                            ))
                        }
                    }

                    let lag1 = TimeSeriesTransforms.transform(dailySeries: comboDaily, type: .lag1Day, interpolateGaps: false)
                    if lag1.count >= 3 {
                        candidateFeatures.append((
                            FeatureIdentifier(metricId: spec.id, transform: .lag1Day),
                            syntheticMetric,
                            lag1
                        ))
                    }
                }
            }

            // Cross-Correlation Matrix
            var results: [DiscoveredInsight] = []
            var seenPairs = Set<String>()

            for i in 0..<candidateFeatures.count {
                for j in (i + 1)..<candidateFeatures.count {
                    let featA = candidateFeatures[i]
                    let featB = candidateFeatures[j]

                    if InsightFilters.isTrivial(
                        metricA: featA.metric.id,
                        metricB: featB.metric.id,
                        transformA: featA.feature.transform,
                        transformB: featB.feature.transform
                    ) {
                        continue
                    }

                    let pairKey1 = "\(featA.feature.id)||\(featB.feature.id)"
                    let pairKey2 = "\(featB.feature.id)||\(featA.feature.id)"
                    if seenPairs.contains(pairKey1) || seenPairs.contains(pairKey2) { continue }
                    seenPairs.insert(pairKey1)

                    if let corr = TimeSeriesTransforms.pearsonCorrelation(seriesA: featA.series, seriesB: featB.series) {
                        let threshold = corr.n >= 20 ? 0.08 : 0.14
                        if corr.r.isFinite && abs(corr.r) >= threshold && corr.n >= 4 {
                            results.append(
                                DiscoveredInsight(
                                    featureA: featA.feature,
                                    featureB: featB.feature,
                                    metricA: featA.metric,
                                    metricB: featB.metric,
                                    r: corr.r,
                                    sampleSize: corr.n,
                                    points: corr.points
                                )
                            )
                        }
                    }
                }
            }

            results.sort { $0.absR > $1.absR }
            InsightsPersistence.save(insights: results)

            DispatchQueue.main.async {
                self.discoveredInsights = results
                self.isAnalyzing = false
            }
        }
    }
}

// MARK: - Insight Row Card
struct InsightRowCard: View {
    let insight: DiscoveredInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: insight.metricA.icon)
                        .foregroundColor(insight.metricA.color)
                    Text(insight.titleA)
                        .font(.subheadline.bold())
                }

                Image(systemName: "arrow.left.and.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: insight.metricB.icon)
                        .foregroundColor(insight.metricB.color)
                    Text(insight.titleB)
                        .font(.subheadline.bold())
                }

                Spacer()

                Text(String(format: "%+.2f", insight.r))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundColor(insight.r >= 0 ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((insight.r >= 0 ? Color.green : Color.red).opacity(0.12))
                    .cornerRadius(6)
            }

            HStack {
                if insight.isBodyMassDelta {
                    TagView(label: "Weight Δ", icon: "scalemass.fill", color: .indigo)
                }
                if insight.isLeadLag {
                    TagView(label: "Lead-Lag Effect", icon: "clock.arrow.circlepath", color: .purple)
                }
                if insight.isDerivative && !insight.isBodyMassDelta {
                    TagView(label: "Rate of Change (Δ)", icon: "function", color: .orange)
                }
                TagView(label: "\(insight.sampleSize) days", icon: "calendar", color: .secondary)
                Spacer()
                Text("Details")
                    .font(.caption2.bold())
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TagView: View {
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(label)
        }
        .font(.caption2)
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.08))
        .cornerRadius(4)
    }
}

// MARK: - Detail Modal with Time Aggregation & Swap Axes
struct InsightDetailModal: View {
    let insight: DiscoveredInsight
    @Environment(\.dismiss) var dismiss

    @State private var isAxesFlipped: Bool = false
    @State private var selectedGranularity: Calendar.Component = .day

    var currentXTitle: String {
        isAxesFlipped ? insight.titleB : insight.titleA
    }

    var currentYTitle: String {
        isAxesFlipped ? insight.titleA : insight.titleB
    }

    var currentXUnit: String {
        isAxesFlipped ? insight.metricB.unitLabel : insight.metricA.unitLabel
    }

    var currentYUnit: String {
        isAxesFlipped ? insight.metricA.unitLabel : insight.metricB.unitLabel
    }

    var granularitySuffix: String {
        switch selectedGranularity {
        case .month: return " [Monthly Avg]"
        case .weekOfYear: return " [Weekly Avg]"
        default: return ""
        }
    }

    var granularityNoun: String {
        switch selectedGranularity {
        case .month: return "months"
        case .weekOfYear: return "weeks"
        default: return "days"
        }
    }

    var activePoints: [(date: Date, x: Double, y: Double)] {
        let basePoints = insight.points
        let orientedPoints: [(date: Date, x: Double, y: Double)]
        if isAxesFlipped {
            orientedPoints = basePoints.map { ($0.date, $0.y, $0.x) }
        } else {
            orientedPoints = basePoints
        }

        if selectedGranularity == .day {
            return orientedPoints
        }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: orientedPoints) { pt -> Date in
            calendar.dateInterval(of: selectedGranularity, for: pt.date)?.start ?? pt.date
        }

        var results: [(date: Date, x: Double, y: Double)] = []
        for (bucketDate, pts) in grouped {
            guard !pts.isEmpty else { continue }
            let avgX = pts.map(\.x).reduce(0, +) / Double(pts.count)
            let avgY = pts.map(\.y).reduce(0, +) / Double(pts.count)
            results.append((bucketDate, avgX, avgY))
        }
        return results.sorted { $0.date < $1.date }
    }

    var dynamicR: Double {
        let pts = activePoints
        guard pts.count >= 2 else { return insight.r }
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        let n = Double(pts.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let sumY2 = ys.map { $0 * $0 }.reduce(0, +)
        let num = (n * sumXY) - (sumX * sumY)
        let den = sqrt(max((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY), 0))
        return den > 0 ? (num / den) : insight.r
    }

    var xDomain: ClosedRange<Double> {
        let xs = activePoints.map(\.x)
        guard let minVal = xs.min(), let maxVal = xs.max(), minVal != maxVal else {
            let single = xs.first ?? 0
            return (single - 1)...(single + 1)
        }
        let padding = (maxVal - minVal) * 0.06
        return (minVal - padding)...(maxVal + padding)
    }

    var yDomain: ClosedRange<Double> {
        let ys = activePoints.map(\.y)
        guard let minVal = ys.min(), let maxVal = ys.max(), minVal != maxVal else {
            let single = ys.first ?? 0
            return (single - 1)...(single + 1)
        }
        let padding = (maxVal - minVal) * 0.06
        return (minVal - padding)...(maxVal + padding)
    }

    var regression: (slope: Double, intercept: Double, xMin: Double, xMax: Double)? {
        let points = activePoints
        guard points.count >= 2 else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let xMin = xs.min(), let xMax = xs.max(), xMin != xMax else { return nil }
        let n = Double(points.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = (n * sumX2 - sumX * sumX)
        guard denom != 0 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept, xMin, xMax)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(isAxesFlipped ? "\(insight.titleB) vs \(insight.titleA)" : insight.title)
                                .font(.title3.bold())
                            Spacer()
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isAxesFlipped.toggle()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.left.arrow.right")
                                    Text("Swap X & Y")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }

                        HStack {
                            Text("Correlation:")
                                .foregroundColor(.secondary)
                            Text(String(format: "%+.3f", dynamicR))
                                .bold()
                                .foregroundColor(dynamicR >= 0 ? .green : .red)
                            Text("(\(activePoints.count) matching \(granularityNoun))")
                                .foregroundColor(.secondary)
                        }
                        .font(.subheadline)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SCATTER PLOT TIME AGGREGATION")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                        Picker("Granularity", selection: $selectedGranularity) {
                            Text("Daily").tag(Calendar.Component.day)
                            Text("Weekly Average").tag(Calendar.Component.weekOfYear)
                            Text("Monthly Average").tag(Calendar.Component.month)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scatter & Linear Fit")
                            .font(.headline)
                            .padding(.horizontal)

                        let xLabel = "\(currentXTitle) (\(currentXUnit))\(granularitySuffix)"
                        let yLabel = "\(currentYTitle) (\(currentYUnit))\(granularitySuffix)"

                        Chart {
                            ForEach(Array(activePoints.enumerated()), id: \.offset) { _, pt in
                                PointMark(
                                    x: .value(currentXTitle, pt.x),
                                    y: .value(currentYTitle, pt.y)
                                )
                                .foregroundStyle(Color.blue.opacity(0.7))
                                .symbolSize(30)
                            }

                            if let reg = regression {
                                LineMark(
                                    x: .value("X", reg.xMin),
                                    y: .value("Y", reg.slope * reg.xMin + reg.intercept)
                                )
                                .foregroundStyle(Color.red)
                                .lineStyle(StrokeStyle(lineWidth: 2))

                                LineMark(
                                    x: .value("X", reg.xMax),
                                    y: .value("Y", reg.slope * reg.xMax + reg.intercept)
                                )
                                .foregroundStyle(Color.red)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            }
                        }
                        .chartXScale(domain: xDomain)
                        .chartYScale(domain: yDomain)
                        .chartXAxis {
                            AxisMarks(values: .automatic) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                    .foregroundStyle(Color.gray.opacity(0.2))
                                AxisTick()
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(String(format: "%.1f", v))
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                    .foregroundStyle(Color.gray.opacity(0.2))
                                AxisTick()
                                AxisValueLabel {
                                    if let v = value.as(Double.self) {
                                        Text(String(format: "%.1f", v))
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .chartXAxisLabel(xLabel, alignment: .center)
                        .chartYAxisLabel(yLabel, position: .leading)
                        .frame(height: 290)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Physiological Interpretation")
                            .font(.headline)

                        let m1 = currentXTitle
                        let m2 = currentYTitle
                        let dir = dynamicR > 0 ? "increases" : "decreases"
                        let strength = abs(dynamicR) >= 0.6 ? "strong" : "moderate"

                        Text("Our analysis uncovered a \(strength) statistical relationship between \(m1) and \(m2). When \(m1) increases, \(m2) tendentially \(dir) across \(selectedGranularity == .day ? "daily observations" : "aggregated periods").")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if insight.isBodyMassDelta {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("⚖️ Weight Rate of Change (Δ):")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.indigo)
                                Text("Multi-day velocities (7, 14, and 21 days) smooth out acute daily water, glycogen, and sodium fluctuations to capture true tissue accumulation or deficit.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color.indigo.opacity(0.08))
                            .cornerRadius(8)
                            .padding(.top, 4)
                        }

                        if insight.isLeadLag {
                            Text("⏱ Because this comparison incorporates a time-shift, it highlights how your behavior on one day carries over and influences your body on subsequent days.")
                                .font(.footnote)
                                .foregroundColor(.purple)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Discovered Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
