import Charts
import SwiftData
import SwiftUI

private enum InsightDimension: String, CaseIterable, Identifiable {
    case assetType
    case accountPlatform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assetType:
            return AppLocalizer.string("dashboard.dimension.assetType")
        case .accountPlatform:
            return AppLocalizer.string("dashboard.dimension.accountPlatform")
        }
    }
}

private struct InsightBucket: Identifiable {
    let id: String
    let label: String
    let value: Double
    let percent: Double
    let color: Color
}

private struct InsightRingSlice: Identifiable {
    let id: String
    let label: String
    let value: Double
    let percent: Double
    let color: Color
    let startRatio: Double
    let endRatio: Double
}

private struct TrendPoint: Identifiable {
    let id = UUID()
    let capturedAt: Date
    let totalValue: Double
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Household.createdAt) private var households: [Household]
    @Query(sort: \Asset.updatedAt, order: .reverse) private var assets: [Asset]
    @Query(sort: \NetWorthSnapshot.capturedAt) private var snapshots: [NetWorthSnapshot]

    @AppStorage("baseCurrencyCode") private var baseCurrencyCode = "USD"
    @AppStorage("appLanguageCode") private var appLanguageCode = AppLanguage.system.rawValue

    @StateObject private var marketDataCoordinator = MarketDataCoordinator()
    @State private var hideAmounts = false
    @State private var selectedDimension: InsightDimension = .assetType

    private let chartPalette: [Color] = [
        Color(red: 0.20, green: 0.49, blue: 0.93),
        Color(red: 0.02, green: 0.66, blue: 0.72),
        Color(red: 0.96, green: 0.57, blue: 0.24),
        Color(red: 0.74, green: 0.31, blue: 0.88),
        Color(red: 0.96, green: 0.34, blue: 0.36),
        Color(red: 0.56, green: 0.65, blue: 0.22),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let household = households.first {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            summaryCard(for: household)
                            insightCard(for: household)
                            trendCard(for: household)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                } else {
                    ContentUnavailableView(
                        AppLocalizer.string("dashboard.empty.title"),
                        systemImage: "house",
                        description: Text(AppLocalizer.string("dashboard.empty.description"))
                    )
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AppLocalizer.string("tab.dashboard"))
            .toolbar {
                if let household = households.first {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            recordSnapshotIfNeeded(for: household)
                        } label: {
                            Image(systemName: "camera.aperture")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await marketDataCoordinator.refreshAll(
                                    assets: assets,
                                    baseCurrency: normalizedBaseCurrency,
                                    modelContext: modelContext
                                )
                                recordSnapshotIfNeeded(for: household)
                            }
                        } label: {
                            Image(systemName: marketDataCoordinator.isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .task(id: ratesRefreshTaskKey) {
            await marketDataCoordinator.refreshRatesOnly(
                assets: assets,
                baseCurrency: normalizedBaseCurrency
            )
            if let household = households.first {
                recordSnapshotIfNeeded(for: household)
            }
        }
    }

    @ViewBuilder
    private func summaryCard(for household: Household) -> some View {
        let totalAssets = convertedTotal(for: household.assets)
        let liabilities = 0.0
        let netWorth = totalAssets - liabilities

        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(household.name)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(AppLocalizer.string("dashboard.netWorth"))
                            .font(.title3.weight(.semibold))
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hideAmounts.toggle()
                        }
                    } label: {
                        Image(systemName: hideAmounts ? "eye.slash" : "eye")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)
                }

                Text(displayAmount(netWorth))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    statPill(title: AppLocalizer.string("dashboard.assets"), value: totalAssets)
                    statPill(title: AppLocalizer.string("dashboard.liabilities"), value: liabilities)
                }
            }
        }
    }

    @ViewBuilder
    private func insightCard(for household: Household) -> some View {
        let buckets = insightBuckets(for: household.assets)

        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(AppLocalizer.string("dashboard.allocation"))
                        .font(.title3.weight(.semibold))
                    Spacer()
                }

                Picker(AppLocalizer.string("dashboard.dimension"), selection: $selectedDimension) {
                    ForEach(InsightDimension.allCases) { dimension in
                        Text(dimension.title).tag(dimension)
                    }
                }
                .pickerStyle(.segmented)
                .id("dashboard-dimension-picker-\(appLanguageCode)")

                if buckets.isEmpty {
                    Text(AppLocalizer.string("dashboard.allocation.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    InsightRingChartView(
                        slices: insightRingSlices(from: buckets),
                        percentText: percentText
                    )
                    .frame(height: 210)

                    VStack(spacing: 10) {
                        ForEach(buckets) { bucket in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(bucket.color)
                                    .frame(width: 8, height: 8)
                                Text(bucket.label)
                                    .font(.subheadline)
                                Spacer()
                                Text(percentText(bucket.percent))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(displayAmount(bucket.value))
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trendCard(for household: Household) -> some View {
        let trendItems = trendData(for: household.id)

        card {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalizer.string("dashboard.trend"))
                    .font(.title3.weight(.semibold))

                if trendItems.count < 2 {
                    Text(AppLocalizer.string("dashboard.trend.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(trendItems) { item in
                        LineMark(
                            x: .value(AppLocalizer.string("dashboard.axis.time"), item.capturedAt),
                            y: .value(AppLocalizer.string("dashboard.axis.value"), item.totalValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Color.accentColor)

                        AreaMark(
                            x: .value(AppLocalizer.string("dashboard.axis.time"), item.capturedAt),
                            y: .value(AppLocalizer.string("dashboard.axis.value"), item.totalValue)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.20),
                                    Color.accentColor.opacity(0.04),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .frame(height: 190)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                            AxisTick().foregroundStyle(Color.secondary.opacity(0.35))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date, format: .dateTime.month().day())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func statPill(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayAmount(value))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var normalizedBaseCurrency: String {
        baseCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var ratesRefreshTaskKey: String {
        let trackedCurrencies = assets
            .map { $0.currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .sorted()
            .joined(separator: ",")
        return "\(normalizedBaseCurrency)|\(assets.count)|\(trackedCurrencies)"
    }

    private func displayAmount(_ value: Double) -> String {
        hideAmounts ? "••••••" : CurrencyFormatter.string(value: value, currencyCode: normalizedBaseCurrency)
    }

    private func percentText(_ ratio: Double) -> String {
        (ratio.formatted(.percent.precision(.fractionLength(1))))
    }

    private func convertedTotal(for assets: [Asset]) -> Double {
        assets.reduce(0) { partialResult, asset in
            partialResult + marketDataCoordinator.convertedToBase(
                amount: asset.marketValue,
                from: asset.currencyCode
            )
        }
    }

    private func recordSnapshotIfNeeded(for household: Household) {
        let total = convertedTotal(for: household.assets)
        NetWorthSnapshotService.recordSnapshotIfNeeded(
            householdID: household.id,
            baseCurrencyCode: normalizedBaseCurrency,
            totalValue: total,
            modelContext: modelContext
        )
    }

    private func insightBuckets(for assets: [Asset]) -> [InsightBucket] {
        var grouped: [String: Double] = [:]

        for asset in assets {
            let amount = marketDataCoordinator.convertedToBase(
                amount: asset.marketValue,
                from: asset.currencyCode
            )

            guard amount > 0 else {
                continue
            }

            let key: String
            switch selectedDimension {
            case .assetType:
                key = localizedAssetType(asset.type)
            case .accountPlatform:
                let cleanedTag = asset.accountPlatformTag.trimmingCharacters(in: .whitespacesAndNewlines)
                key = cleanedTag.isEmpty ? AppLocalizer.string("dashboard.tag.none") : cleanedTag
            }

            grouped[key, default: 0] += amount
        }

        var sorted = grouped
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }

        if sorted.count > 8 {
            let othersTotal = sorted.dropFirst(7).reduce(0) { $0 + $1.1 }
            sorted = Array(sorted.prefix(7))
            sorted.append((AppLocalizer.string("dashboard.bucket.others"), othersTotal))
        }

        let total = sorted.reduce(0) { $0 + $1.1 }
        guard total > 0 else {
            return []
        }

        return sorted.enumerated().map { index, element in
            InsightBucket(
                id: element.0,
                label: element.0,
                value: element.1,
                percent: element.1 / total,
                color: chartPalette[index % chartPalette.count]
            )
        }
    }

    private func insightRingSlices(from buckets: [InsightBucket]) -> [InsightRingSlice] {
        var accumulated = 0.0
        return buckets.map { bucket in
            let start = accumulated
            accumulated += bucket.percent
            return InsightRingSlice(
                id: bucket.id,
                label: bucket.label,
                value: bucket.value,
                percent: bucket.percent,
                color: bucket.color,
                startRatio: start,
                endRatio: accumulated
            )
        }
    }

    private func trendData(for householdID: UUID) -> [TrendPoint] {
        snapshots
            .filter { $0.householdID == householdID && $0.baseCurrencyCode == normalizedBaseCurrency }
            .sorted { $0.capturedAt < $1.capturedAt }
            .suffix(30)
            .map { snapshot in
                TrendPoint(capturedAt: snapshot.capturedAt, totalValue: snapshot.totalValue)
            }
    }

    private func localizedAssetType(_ type: AssetType) -> String {
        type.title
    }
}

private struct InsightRingChartView: View {
    let slices: [InsightRingSlice]
    let percentText: (Double) -> String

    private let ringThicknessRatio: CGFloat = 0.09
    private let minRingThickness: CGFloat = 12
    private let labelRatioThreshold = 0.08

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ringThickness = max(minRingThickness, side * ringThicknessRatio)
            let ringDiameter = max(96, side - 58)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let outerRadius = ringDiameter / 2
            let labelPoints = labelPoints(
                in: proxy.size,
                center: center,
                outerRadius: outerRadius
            )

            ZStack {
                ForEach(slices) { slice in
                    InsightDonutSliceShape(
                        startAngle: .degrees(slice.adjustedStartDegrees),
                        endAngle: .degrees(slice.adjustedEndDegrees),
                        thickness: ringThickness
                    )
                    .fill(slice.color)
                    .frame(width: ringDiameter, height: ringDiameter)
                }

                Circle()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(
                        width: max(12, ringDiameter - ringThickness * 2),
                        height: max(12, ringDiameter - ringThickness * 2)
                    )

                ForEach(labelPoints, id: \.slice.id) { item in
                    VStack(alignment: item.alignment, spacing: 1) {
                        Text(item.slice.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(percentText(item.slice.percent))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .shadow(color: Color(.systemBackground).opacity(0.82), radius: 1.8, x: 0, y: 0)
                    .position(item.point)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func preferredLabelSlices(from slices: [InsightRingSlice]) -> [InsightRingSlice] {
        let majorSlices = slices.filter { $0.percent >= labelRatioThreshold }
        if majorSlices.count <= 4 {
            return majorSlices
        }
        return Array(majorSlices.sorted { $0.percent > $1.percent }.prefix(4))
    }

    private func labelPoints(
        in size: CGSize,
        center: CGPoint,
        outerRadius: CGFloat
    ) -> [(slice: InsightRingSlice, point: CGPoint, alignment: HorizontalAlignment)] {
        let selectedSlices = preferredLabelSlices(from: slices)
        let minY: CGFloat = 18
        let maxY: CGFloat = size.height - 18
        let labelXOffset: CGFloat = outerRadius + 34
        let yProjectionRadius: CGFloat = outerRadius * 0.78

        var leftCandidates: [(slice: InsightRingSlice, rawY: CGFloat)] = []
        var rightCandidates: [(slice: InsightRingSlice, rawY: CGFloat)] = []

        for slice in selectedSlices {
            let radians = slice.midAngleDegrees * Double.pi / 180
            let rawY = center.y + CGFloat(Darwin.sin(radians)) * yProjectionRadius
            let side = Darwin.cos(radians)
            if side < 0 {
                leftCandidates.append((slice, rawY))
            } else {
                rightCandidates.append((slice, rawY))
            }
        }

        let left = resolvedLabelYPositions(
            leftCandidates,
            minY: minY,
            maxY: maxY
        ).map { slice, y in
            (
                slice: slice,
                point: CGPoint(x: center.x - labelXOffset, y: y),
                alignment: HorizontalAlignment.trailing
            )
        }

        let right = resolvedLabelYPositions(
            rightCandidates,
            minY: minY,
            maxY: maxY
        ).map { slice, y in
            (
                slice: slice,
                point: CGPoint(x: center.x + labelXOffset, y: y),
                alignment: HorizontalAlignment.leading
            )
        }

        return left + right
    }

    private func resolvedLabelYPositions(
        _ candidates: [(slice: InsightRingSlice, rawY: CGFloat)],
        minY: CGFloat,
        maxY: CGFloat
    ) -> [(InsightRingSlice, CGFloat)] {
        guard !candidates.isEmpty else {
            return []
        }

        let minGap: CGFloat = 20
        let sorted = candidates.sorted { $0.rawY < $1.rawY }
        var adjusted: [(slice: InsightRingSlice, y: CGFloat)] = []

        for item in sorted {
            var y = min(max(item.rawY, minY), maxY)
            if let last = adjusted.last {
                y = max(y, last.y + minGap)
            }
            adjusted.append((item.slice, y))
        }

        if let last = adjusted.last, last.y > maxY {
            let overflow = last.y - maxY
            adjusted = adjusted.map { (slice: $0.slice, y: $0.y - overflow) }
            if let first = adjusted.first, first.y < minY {
                let underflow = minY - first.y
                adjusted = adjusted.map { (slice: $0.slice, y: $0.y + underflow) }
            }
        }

        return adjusted.map { ($0.slice, min(max($0.y, minY), maxY)) }
    }
}

private struct InsightDonutSliceShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = max(0, outerRadius - thickness)

        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

private extension InsightRingSlice {
    var midAngleDegrees: Double {
        ((startRatio + endRatio) * 180) - 90
    }

    var adjustedStartDegrees: Double {
        startDegrees
    }

    var adjustedEndDegrees: Double {
        endDegrees
    }

    private var startDegrees: Double {
        (startRatio * 360) - 90
    }

    private var endDegrees: Double {
        (endRatio * 360) - 90
    }
}
