import Foundation
import SwiftData

@MainActor
final class MarketDataCoordinator: ObservableObject {
    static let supportedBaseCurrencies = ["USD", "HKD", "CNY", "EUR", "JPY"]

    @Published private(set) var ratesToBase: [String: Double] = [:]
    @Published private(set) var baseCurrencyCode = "USD"
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var missingCurrencies: [String] = []
    @Published var statusMessage: String?

    private let quoteProvider: MarketQuoteProviding
    private let fxProvider: FXRateProviding
    private var usdReferenceRates: [String: Double]

    private static let usdReferenceRatesStorageKey = "fx.usd-reference-rates.v1"
    private static let usdReferenceRatesUpdatedAtStorageKey = "fx.usd-reference-rates-updated-at.v1"
    private static let builtInUSDRates: [String: Double] = [
        "USD": 1.0,
        "HKD": 0.1280,
        "CNY": 0.1380,
        "EUR": 1.0850,
        "JPY": 0.0065,
    ]

    init(
        quoteProvider: MarketQuoteProviding,
        fxProvider: FXRateProviding
    ) {
        self.quoteProvider = quoteProvider
        self.fxProvider = fxProvider
        usdReferenceRates = Self.loadPersistedUSDRates()
        baseCurrencyCode = "USD"
        ratesToBase = fallbackRatesToBase(
            baseCurrency: "USD",
            currencies: Set(Self.supportedBaseCurrencies),
            existingRates: [:]
        )
    }

    convenience init() {
        let provider = YahooFinanceProvider()
        self.init(quoteProvider: provider, fxProvider: provider)
    }

    func refreshAll(
        assets: [Asset],
        baseCurrency: String,
        modelContext: ModelContext
    ) async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let normalizedBase = normalize(baseCurrency)
        if normalizedBase != baseCurrencyCode {
            ratesToBase = remapRates(
                ratesToBase,
                fromBase: baseCurrencyCode,
                toBase: normalizedBase
            )
        }
        baseCurrencyCode = normalizedBase

        let quoteSummary = await refreshQuotes(assets: assets, modelContext: modelContext)
        await refreshRates(assets: assets, baseCurrency: normalizedBase)

        lastSyncAt = .now
        let fxSummary = fxStatusSummary(baseCurrency: normalizedBase)
        if let errorMessage = quoteSummary.errorMessage {
            statusMessage = "Quotes: \(quoteSummary.updated)/\(quoteSummary.trackable) updated. \(errorMessage) \(fxSummary)"
        } else {
            statusMessage = "Quotes: \(quoteSummary.updated)/\(quoteSummary.trackable) updated. \(fxSummary)"
        }
    }

    func refreshRatesOnly(
        assets: [Asset],
        baseCurrency: String
    ) async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let normalizedBase = normalize(baseCurrency)
        if normalizedBase != baseCurrencyCode {
            ratesToBase = remapRates(
                ratesToBase,
                fromBase: baseCurrencyCode,
                toBase: normalizedBase
            )
        }
        baseCurrencyCode = normalizedBase
        await refreshRates(assets: assets, baseCurrency: normalizedBase)
        lastSyncAt = .now
        statusMessage = fxStatusSummary(baseCurrency: normalizedBase)
    }

    func convertedToBase(amount: Double, from currencyCode: String) -> Double {
        let fromCode = normalize(currencyCode)
        guard fromCode != baseCurrencyCode else {
            return amount
        }
        guard let rate = ratesToBase[fromCode] else {
            return amount
        }
        return amount * rate
    }

    private func refreshQuotes(
        assets: [Asset],
        modelContext: ModelContext
    ) async -> (trackable: Int, updated: Int, errorMessage: String?) {
        let trackableAssets = assets.filter(\.isTrackableQuoteAsset)
        guard !trackableAssets.isEmpty else {
            return (0, 0, nil)
        }

        let requests = trackableAssets.map {
            QuoteRequest(symbol: $0.symbol, type: $0.type, market: $0.market)
        }

        do {
            let snapshots = try await quoteProvider.fetchQuotes(for: requests)
            let snapshotByRequest = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.request, $0) })
            var updatedCount = 0

            for asset in trackableAssets {
                let request = QuoteRequest(symbol: asset.symbol, type: asset.type, market: asset.market)
                guard let snapshot = snapshotByRequest[request] else {
                    continue
                }

                asset.latestUnitPrice = snapshot.unitPrice
                asset.lastQuoteAt = snapshot.asOf
                asset.currencyCode = snapshot.currencyCode
                if asset.quantity > 0 {
                    asset.marketValue = asset.quantity * snapshot.unitPrice
                }
                asset.updatedAt = .now
                updatedCount += 1
            }

            try? modelContext.save()
            return (trackableAssets.count, updatedCount, nil)
        } catch {
            return (trackableAssets.count, 0, error.localizedDescription)
        }
    }

    private func refreshRates(
        assets: [Asset],
        baseCurrency: String
    ) async {
        let existingRates = ratesToBase
        var currencies = Set(assets.map { normalize($0.currencyCode) })
        currencies.insert(baseCurrency)
        currencies.formUnion(Self.supportedBaseCurrencies)

        var latestRates = fallbackRatesToBase(
            baseCurrency: baseCurrency,
            currencies: currencies,
            existingRates: existingRates
        )
        var unresolved: [String] = []
        var networkResolvedToUSD: [String: Double] = [:]

        for currency in currencies.sorted() where currency != "USD" {
            do {
                let toUSD = try await fxProvider.fetchRate(from: currency, to: "USD")
                guard toUSD > 0 else {
                    unresolved.append(currency)
                    continue
                }
                networkResolvedToUSD[currency] = toUSD
            } catch {
                unresolved.append(currency)
            }
        }

        if !networkResolvedToUSD.isEmpty {
            mergeNetworkRatesToUSD(networkResolvedToUSD)
        }

        let normalizedBase = normalize(baseCurrency)
        let normalizedReference = Self.normalizedUSDRates(usdReferenceRates)
        let baseToUSD = normalizedReference[normalizedBase] ?? 1

        for currency in currencies {
            let normalizedCurrency = normalize(currency)
            guard normalizedCurrency != normalizedBase else {
                latestRates[normalizedCurrency] = 1
                continue
            }

            if let toUSD = normalizedReference[normalizedCurrency], toUSD > 0, baseToUSD > 0 {
                latestRates[normalizedCurrency] = toUSD / baseToUSD
            }
        }

        latestRates[baseCurrency] = 1
        ratesToBase = latestRates
        missingCurrencies = Array(Set(unresolved)).sorted()
    }

    private func remapRates(
        _ existingRates: [String: Double],
        fromBase: String,
        toBase: String
    ) -> [String: Double] {
        let normalizedFrom = normalize(fromBase)
        let normalizedTo = normalize(toBase)

        guard normalizedFrom != normalizedTo else {
            var passthrough = existingRates
            passthrough[normalizedTo] = 1
            return passthrough
        }

        guard let targetInSourceBase = existingRates[normalizedTo], targetInSourceBase > 0 else {
            return [normalizedTo: 1]
        }

        var remapped: [String: Double] = [normalizedTo: 1]
        for (currency, rate) in existingRates where rate > 0 {
            remapped[normalize(currency)] = rate / targetInSourceBase
        }
        remapped[normalizedTo] = 1
        return remapped
    }

    private func fxStatusSummary(baseCurrency: String) -> String {
        if missingCurrencies.isEmpty {
            return "FX: \(ratesToBase.count) loaded (\(baseCurrency))."
        }
        return "FX: \(ratesToBase.count) loaded (\(baseCurrency)); stale/missing: \(missingCurrencies.joined(separator: ", "))."
    }

    private func fallbackRatesToBase(
        baseCurrency: String,
        currencies: Set<String>,
        existingRates: [String: Double]
    ) -> [String: Double] {
        let normalizedBase = normalize(baseCurrency)
        let normalizedReference = Self.normalizedUSDRates(usdReferenceRates)
        guard let baseToUSD = normalizedReference[normalizedBase], baseToUSD > 0 else {
            return [normalizedBase: 1]
        }

        var fallback: [String: Double] = [normalizedBase: 1]

        for currency in currencies {
            let normalizedCurrency = normalize(currency)
            guard normalizedCurrency != normalizedBase else {
                fallback[normalizedCurrency] = 1
                continue
            }

            if let toUSD = normalizedReference[normalizedCurrency], toUSD > 0 {
                fallback[normalizedCurrency] = toUSD / baseToUSD
                continue
            }

            if let existingRate = existingRates[normalizedCurrency], existingRate > 0 {
                fallback[normalizedCurrency] = existingRate
            }
        }

        return fallback
    }

    private func mergeNetworkRatesToUSD(_ networkRatesToUSD: [String: Double]) {
        var normalizedReference = Self.normalizedUSDRates(usdReferenceRates)

        for (currency, toUSD) in networkRatesToUSD {
            let normalizedCurrency = normalize(currency)
            guard
                Self.supportedBaseCurrencies.contains(normalizedCurrency),
                toUSD > 0
            else {
                continue
            }

            normalizedReference[normalizedCurrency] = toUSD
        }

        normalizedReference["USD"] = 1
        normalizedReference = Self.normalizedUSDRates(normalizedReference)
        usdReferenceRates = normalizedReference
        Self.persistUSDRates(normalizedReference)
    }

    private static func loadPersistedUSDRates() -> [String: Double] {
        let raw = UserDefaults.standard.dictionary(forKey: usdReferenceRatesStorageKey) ?? [:]
        var parsed: [String: Double] = [:]

        for (key, value) in raw {
            if let number = value as? NSNumber {
                parsed[key.uppercased()] = number.doubleValue
            } else if let double = value as? Double {
                parsed[key.uppercased()] = double
            }
        }

        return normalizedUSDRates(parsed)
    }

    private static func persistUSDRates(_ rates: [String: Double]) {
        UserDefaults.standard.set(rates, forKey: usdReferenceRatesStorageKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: usdReferenceRatesUpdatedAtStorageKey)
    }

    private static func normalizedUSDRates(_ candidates: [String: Double]) -> [String: Double] {
        var normalized = builtInUSDRates

        for (key, value) in candidates {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard supportedBaseCurrencies.contains(normalizedKey), value > 0 else {
                continue
            }
            normalized[normalizedKey] = value
        }

        normalized["USD"] = 1
        return normalized
    }

    private func normalize(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
