import Foundation

final class YahooFinanceProvider: MarketQuoteProviding, FXRateProviding, SymbolSearchProviding {
    private let session: URLSession
    private let quoteHosts = ["query1.finance.yahoo.com", "query2.finance.yahoo.com"]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuotes(for requests: [QuoteRequest]) async throws -> [QuoteSnapshot] {
        let normalizedRequests = Array(Set(requests))
        guard !normalizedRequests.isEmpty else {
            return []
        }

        var requestsByYahooSymbol: [String: [QuoteRequest]] = [:]
        for request in normalizedRequests {
            let yahooSymbol = try quoteSymbol(for: request)
            requestsByYahooSymbol[yahooSymbol, default: []].append(request)
        }

        let items: [YahooQuoteItem]
        do {
            items = try await fetchQuoteItems(symbols: Array(requestsByYahooSymbol.keys))
        } catch {
            let fallback = await fetchFallbackSnapshots(for: normalizedRequests)
            if !fallback.isEmpty {
                return fallback
            }
            throw error
        }

        var snapshots: [QuoteSnapshot] = []
        for item in items {
            guard
                let symbol = item.symbol,
                let price = item.regularMarketPrice,
                let currency = item.currency,
                let requests = requestsByYahooSymbol[symbol]
            else {
                continue
            }

            let asOf = item.regularMarketTime
                .map { Date(timeIntervalSince1970: $0) }
                ?? .now

            for request in requests {
                snapshots.append(
                    QuoteSnapshot(
                        request: request,
                        unitPrice: price,
                        currencyCode: currency.uppercased(),
                        asOf: asOf
                    )
                )
            }
        }

        if snapshots.count < normalizedRequests.count {
            let resolvedRequests = Set(snapshots.map(\.request))
            let unresolved = normalizedRequests.filter { !resolvedRequests.contains($0) }
            let fallback = await fetchFallbackSnapshots(for: unresolved)
            snapshots.append(contentsOf: fallback)
        }

        if snapshots.isEmpty {
            let fallback = await fetchFallbackSnapshots(for: normalizedRequests)
            if !fallback.isEmpty {
                return fallback
            }
        }

        return snapshots
    }

    func searchSymbols(query: String, preferredType: AssetType?) async throws -> [SymbolSearchResult] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return []
        }

        var results: [SymbolSearchResult] = []
        do {
            let yahooResults = try await fetchYahooSearchResults(query: keyword)
            results = yahooResults.compactMap(mapSearchQuoteToResult)
        } catch {
            results = []
        }

        if let preferredType {
            results = results.filter { $0.assetType == preferredType }
        }

        if !results.isEmpty {
            return sortedSearchResults(deduplicated(results), query: keyword)
        }

        let tencentResults = await fetchTencentSearchResults(query: keyword)
        var filteredTencentResults = tencentResults
        if let preferredType {
            filteredTencentResults = filteredTencentResults.filter { $0.assetType == preferredType }
        }
        if !filteredTencentResults.isEmpty {
            return sortedSearchResults(deduplicated(filteredTencentResults), query: keyword)
        }

        let fallbackSymbol = keyword.uppercased()
        let fallbackItems = (try? await fetchQuoteItems(symbols: [fallbackSymbol])) ?? []
        let fallbackResults = fallbackItems.compactMap { item -> SymbolSearchResult? in
            guard let symbol = item.symbol else {
                return nil
            }
            let inferredType = inferAssetTypeFromSymbol(symbol, quoteType: item.quoteType)
            if let preferredType, inferredType != preferredType {
                return nil
            }
            return SymbolSearchResult(
                symbol: symbol,
                name: item.longName ?? item.shortName ?? symbol,
                market: inferMarket(symbol: symbol, exchangeName: item.exchangeDisplayName ?? item.exchange),
                assetType: inferredType,
                exchangeName: item.exchangeDisplayName ?? item.exchange ?? "Unknown",
                currencyCode: item.currency?.uppercased()
            )
        }

        return sortedSearchResults(deduplicated(fallbackResults), query: keyword)
    }

    func fetchRate(from source: String, to target: String) async throws -> Double {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard !normalizedSource.isEmpty, !normalizedTarget.isEmpty else {
            throw MarketDataError.invalidSymbol
        }

        guard normalizedSource != normalizedTarget else {
            return 1
        }

        let directPair = "\(normalizedSource)\(normalizedTarget)=X"
        if let rate = try await fetchSingleQuotePrice(symbol: directPair) {
            return rate
        }

        let inversePair = "\(normalizedTarget)\(normalizedSource)=X"
        if let inverseRate = try await fetchSingleQuotePrice(symbol: inversePair), inverseRate > 0 {
            return 1 / inverseRate
        }

        throw MarketDataError.quoteNotFound(directPair)
    }

    private func quoteSymbol(for request: QuoteRequest) throws -> String {
        let rawSymbol = request.symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !rawSymbol.isEmpty else {
            throw MarketDataError.invalidSymbol
        }

        switch request.type {
        case .stock:
            switch request.market {
            case .us:
                return rawSymbol
            case .hk:
                if rawSymbol.hasSuffix(".HK") {
                    return rawSymbol
                }
                if let value = Int(rawSymbol) {
                    return String(format: "%04d.HK", value)
                }
                return "\(rawSymbol).HK"
            case .global:
                return rawSymbol
            }
        case .crypto:
            let normalizedCrypto = rawSymbol.replacingOccurrences(of: "/", with: "-")
            if normalizedCrypto.contains("-") {
                return normalizedCrypto
            }

            let commonQuoteSuffixes = ["USDT", "USDC", "USD", "BTC", "ETH", "EUR", "JPY"]
            for suffix in commonQuoteSuffixes {
                guard normalizedCrypto.count > suffix.count else {
                    continue
                }
                guard normalizedCrypto.hasSuffix(suffix) else {
                    continue
                }
                let base = String(normalizedCrypto.dropLast(suffix.count))
                guard !base.isEmpty else {
                    continue
                }
                return "\(base)-\(suffix)"
            }
            return "\(normalizedCrypto)-USD"
        default:
            return rawSymbol
        }
    }

    private func fetchSingleQuotePrice(symbol: String) async throws -> Double? {
        let items = try await fetchQuoteItems(symbols: [symbol])
        guard let item = items.first(where: { $0.symbol == symbol }) else {
            return nil
        }
        return item.regularMarketPrice
    }

    private func fetchQuoteItems(symbols: [String]) async throws -> [YahooQuoteItem] {
        guard !symbols.isEmpty else {
            return []
        }

        var lastError: Error = MarketDataError.invalidResponse("No quote provider response.")

        for host in quoteHosts {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = "/v7/finance/quote"
            components.queryItems = [
                URLQueryItem(name: "symbols", value: symbols.joined(separator: ",")),
            ]

            guard let url = components.url else {
                continue
            }

            do {
                let data = try await requestData(url: url)
                let decoded = try JSONDecoder().decode(YahooQuoteResponse.self, from: data)
                return decoded.quoteResponse.result
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func fetchYahooSearchResults(query: String) async throws -> [YahooSearchQuote] {
        var lastError: Error = MarketDataError.invalidResponse("No search provider response.")

        for host in quoteHosts {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = "/v1/finance/search"
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "quotesCount", value: "20"),
                URLQueryItem(name: "newsCount", value: "0"),
                URLQueryItem(name: "enableFuzzyQuery", value: "true"),
            ]

            guard let url = components.url else {
                continue
            }

            do {
                let data = try await requestData(url: url)
                let decoded = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
                return decoded.quotes ?? []
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func requestData(
        url: URL,
        acceptHeader: String = "application/json, text/plain, */*",
        referer: String? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile", forHTTPHeaderField: "User-Agent")
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MarketDataError.invalidResponse("Missing HTTP response.")
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                throw MarketDataError.httpStatus(httpResponse.statusCode)
            }
            return data
        } catch let error as MarketDataError {
            throw error
        } catch {
            throw MarketDataError.network(error.localizedDescription)
        }
    }

    private func fetchFallbackStockSnapshots(for requests: [QuoteRequest]) async -> [QuoteSnapshot] {
        let stockRequests = requests.filter { $0.type == .stock }
        guard !stockRequests.isEmpty else {
            return []
        }

        var snapshots: [QuoteSnapshot] = []
        let stooqSnapshots = await fetchStooqSnapshots(for: stockRequests)
        snapshots.append(contentsOf: stooqSnapshots)

        let resolvedRequests = Set(snapshots.map(\.request))
        let unresolved = stockRequests.filter { !resolvedRequests.contains($0) }
        if !unresolved.isEmpty {
            let tencentSnapshots = await fetchTencentSnapshots(for: unresolved)
            snapshots.append(contentsOf: tencentSnapshots)
        }

        return deduplicatedSnapshots(snapshots)
    }

    private func fetchFallbackSnapshots(for requests: [QuoteRequest]) async -> [QuoteSnapshot] {
        var snapshots = await fetchFallbackStockSnapshots(for: requests)
        let resolved = Set(snapshots.map(\.request))
        let unresolved = requests.filter { !resolved.contains($0) }
        if !unresolved.isEmpty {
            let cryptoSnapshots = await fetchFallbackCryptoSnapshots(for: unresolved)
            snapshots.append(contentsOf: cryptoSnapshots)
        }
        return deduplicatedSnapshots(snapshots)
    }

    private func fetchFallbackCryptoSnapshots(for requests: [QuoteRequest]) async -> [QuoteSnapshot] {
        let cryptoRequests = requests.filter { $0.type == .crypto }
        guard !cryptoRequests.isEmpty else {
            return []
        }

        var snapshots: [QuoteSnapshot] = []

        for request in cryptoRequests {
            guard let pair = normalizedCryptoPair(from: request.symbol) else {
                continue
            }

            if let coinbasePrice = try? await fetchCoinbaseSpotPrice(base: pair.base, quote: pair.quote) {
                snapshots.append(
                    QuoteSnapshot(
                        request: request,
                        unitPrice: coinbasePrice,
                        currencyCode: pair.quote,
                        asOf: .now
                    )
                )
                continue
            }

            if pair.quote == "USD",
               let usdtPrice = try? await fetchBinanceTickerPrice(base: pair.base, quote: "USDT")
            {
                snapshots.append(
                    QuoteSnapshot(
                        request: request,
                        unitPrice: usdtPrice,
                        currencyCode: "USD",
                        asOf: .now
                    )
                )
                continue
            }

            if let binancePrice = try? await fetchBinanceTickerPrice(base: pair.base, quote: pair.quote) {
                snapshots.append(
                    QuoteSnapshot(
                        request: request,
                        unitPrice: binancePrice,
                        currencyCode: pair.quote,
                        asOf: .now
                    )
                )
            }
        }

        return deduplicatedSnapshots(snapshots)
    }

    private func normalizedCryptoPair(from rawSymbol: String) -> (base: String, quote: String)? {
        let normalized = rawSymbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "/", with: "-")

        guard !normalized.isEmpty else {
            return nil
        }

        let parts = normalized
            .split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)
        if parts.count >= 2 {
            let base = parts[0]
            let quote = parts[1]
            if !base.isEmpty, !quote.isEmpty {
                return (base, quote)
            }
        }

        let commonQuoteSuffixes = ["USDT", "USDC", "USD", "BTC", "ETH", "EUR", "JPY"]
        for suffix in commonQuoteSuffixes {
            guard normalized.count > suffix.count else {
                continue
            }
            guard normalized.hasSuffix(suffix) else {
                continue
            }
            let base = String(normalized.dropLast(suffix.count))
            guard !base.isEmpty else {
                continue
            }
            return (base, suffix)
        }

        return (normalized, "USD")
    }

    private func fetchCoinbaseSpotPrice(base: String, quote: String) async throws -> Double {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.coinbase.com"
        components.path = "/v2/prices/\(base)-\(quote)/spot"

        guard let url = components.url else {
            throw MarketDataError.invalidSymbol
        }

        let data = try await requestData(url: url)
        let payload = try JSONDecoder().decode(CoinbaseSpotResponse.self, from: data)
        guard let price = Double(payload.data.amount), price > 0 else {
            throw MarketDataError.invalidResponse("Invalid Coinbase spot payload.")
        }
        return price
    }

    private func fetchBinanceTickerPrice(base: String, quote: String) async throws -> Double {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.binance.com"
        components.path = "/api/v3/ticker/price"
        components.queryItems = [
            URLQueryItem(name: "symbol", value: "\(base)\(quote)"),
        ]

        guard let url = components.url else {
            throw MarketDataError.invalidSymbol
        }

        let data = try await requestData(url: url)
        let payload = try JSONDecoder().decode(BinanceTickerResponse.self, from: data)
        guard let price = Double(payload.price), price > 0 else {
            throw MarketDataError.invalidResponse("Invalid Binance ticker payload.")
        }
        return price
    }

    private func fetchStooqSnapshots(for requests: [QuoteRequest]) async -> [QuoteSnapshot] {
        var snapshots: [QuoteSnapshot] = []

        for request in requests where request.type == .stock {
            guard let stooqSymbol = stooqSymbol(for: request) else {
                continue
            }
            guard let resolvedPrice = try? await fetchStooqClosePrice(symbol: stooqSymbol) else {
                continue
            }

            let currencyCode: String
            switch request.market {
            case .hk:
                currencyCode = "HKD"
            case .us, .global:
                currencyCode = "USD"
            }

            snapshots.append(
                QuoteSnapshot(
                    request: request,
                    unitPrice: resolvedPrice,
                    currencyCode: currencyCode,
                    asOf: .now
                )
            )
        }

        return snapshots
    }

    private func stooqSymbol(for request: QuoteRequest) -> String? {
        var symbol = request.symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !symbol.isEmpty else {
            return nil
        }

        if symbol.hasSuffix(".HK") {
            symbol = String(symbol.dropLast(3))
        }

        switch request.market {
        case .us:
            return "\(symbol.lowercased()).us"
        case .hk:
            if let numeric = Int(symbol) {
                return String(format: "%04d.hk", numeric)
            }
            return "\(symbol.lowercased()).hk"
        case .global:
            return symbol.lowercased()
        }
    }

    private func fetchStooqClosePrice(symbol: String) async throws -> Double? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "stooq.com"
        components.path = "/q/l/"
        components.queryItems = [
            URLQueryItem(name: "s", value: symbol),
            URLQueryItem(name: "f", value: "sd2t2ohlcv"),
            URLQueryItem(name: "h", value: ""),
            URLQueryItem(name: "e", value: "csv"),
        ]

        guard let url = components.url else {
            return nil
        }

        let data = try await requestData(url: url, acceptHeader: "text/csv, text/plain, */*")
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard lines.count >= 2 else {
            return nil
        }

        let fields = lines[1].split(separator: ",").map { String($0) }
        guard fields.count >= 7 else {
            return nil
        }

        let closeField = fields[6]
        guard closeField != "N/D", let close = Double(closeField) else {
            return nil
        }

        return close
    }

    private func fetchTencentSnapshots(for requests: [QuoteRequest]) async -> [QuoteSnapshot] {
        let requestCodes: [(QuoteRequest, String)] = requests.compactMap { request in
            guard let code = tencentQuoteCode(for: request) else {
                return nil
            }
            return (request, code)
        }
        guard !requestCodes.isEmpty else {
            return []
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "qt.gtimg.cn"
        components.path = "/q"
        components.queryItems = [
            URLQueryItem(name: "q", value: requestCodes.map(\.1).joined(separator: ",")),
        ]
        guard let url = components.url else {
            return []
        }

        guard
            let data = try? await requestData(
                url: url,
                acceptHeader: "text/plain, */*",
                referer: "https://finance.qq.com"
            ),
            let payload = decodeTencentString(data)
        else {
            return []
        }

        let rows = parseTencentQuoteRows(payload)
        var snapshots: [QuoteSnapshot] = []

        for (request, code) in requestCodes {
            guard let fields = rows[code], let price = tencentCurrentPrice(fields: fields) else {
                continue
            }

            let currencyCode: String
            switch request.market {
            case .hk:
                currencyCode = "HKD"
            case .us, .global:
                currencyCode = "USD"
            }

            snapshots.append(
                QuoteSnapshot(
                    request: request,
                    unitPrice: price,
                    currencyCode: currencyCode,
                    asOf: .now
                )
            )
        }

        return snapshots
    }

    private func fetchTencentSearchResults(query: String) async -> [SymbolSearchResult] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "smartbox.gtimg.cn"
        components.path = "/s3/"
        components.queryItems = [
            URLQueryItem(name: "v", value: "2"),
            URLQueryItem(name: "t", value: "all"),
            URLQueryItem(name: "c", value: "1"),
            URLQueryItem(name: "q", value: query),
        ]
        guard let url = components.url else {
            return []
        }

        guard
            let data = try? await requestData(
                url: url,
                acceptHeader: "text/plain, */*",
                referer: "https://finance.qq.com"
            ),
            let payload = decodeTencentString(data),
            let body = firstQuotedText(in: payload)
        else {
            return []
        }

        var results: [SymbolSearchResult] = []
        for row in body.split(separator: "^") {
            let fields = row.split(separator: ",", omittingEmptySubsequences: false).map { String($0) }
            guard fields.count >= 3 else {
                continue
            }

            let marketToken = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCode = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !rawCode.isEmpty,
                !name.isEmpty,
                let normalized = normalizeTencentSearchCode(rawCode: rawCode, marketToken: marketToken)
            else {
                continue
            }

            results.append(
                SymbolSearchResult(
                    symbol: normalized.symbol,
                    name: name,
                    market: normalized.market,
                    assetType: .stock,
                    exchangeName: normalized.exchangeName,
                    currencyCode: normalized.currencyCode
                )
            )
        }

        return results
    }

    private func decodeTencentString(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: gb18030Encoding) {
            return text
        }
        return String(data: data, encoding: .isoLatin1)
    }

    private var gb18030Encoding: String.Encoding {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }

    private func firstQuotedText(in text: String) -> String? {
        guard
            let start = text.firstIndex(of: "\""),
            let end = text.lastIndex(of: "\""),
            start < end
        else {
            return nil
        }
        return String(text[text.index(after: start) ..< end])
    }

    private func parseTencentQuoteRows(_ payload: String) -> [String: [String]] {
        var rows: [String: [String]] = [:]
        for rawLine in payload.split(separator: ";", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let equalIndex = line.firstIndex(of: "=") else {
                continue
            }

            let lhs = String(line[..<equalIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let code = lhs.replacingOccurrences(of: "v_", with: "")
            guard !code.isEmpty else {
                continue
            }

            let rhs = String(line[line.index(after: equalIndex)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rhs.isEmpty else {
                continue
            }

            rows[code] = rhs.split(separator: "~").map(String.init)
        }
        return rows
    }

    private func tencentCurrentPrice(fields: [String]) -> Double? {
        let candidateIndexes = [3, 4, 2]
        for index in candidateIndexes where fields.indices.contains(index) {
            guard let value = Double(fields[index]), value > 0 else {
                continue
            }
            return value
        }
        return nil
    }

    private func tencentQuoteCode(for request: QuoteRequest) -> String? {
        guard request.type == .stock else {
            return nil
        }

        let symbol = request.symbol
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !symbol.isEmpty else {
            return nil
        }

        switch request.market {
        case .us:
            if symbol.hasPrefix("US") {
                return symbol.lowercased()
            }
            return "us\(symbol)"
        case .hk:
            var base = symbol
            if base.hasSuffix(".HK") {
                base = String(base.dropLast(3))
            }
            if let numeric = Int(base) {
                return String(format: "hk%05d", numeric)
            }
            return "hk\(base)"
        case .global:
            return nil
        }
    }

    private func normalizeTencentSearchCode(
        rawCode: String,
        marketToken: String
    ) -> (symbol: String, market: StockMarket, exchangeName: String, currencyCode: String)? {
        let token = marketToken.lowercased()
        let codeUpper = rawCode.uppercased()

        if codeUpper.hasPrefix("US") || token == "us" {
            let symbol = codeUpper.hasPrefix("US") ? String(codeUpper.dropFirst(2)) : codeUpper
            guard !symbol.isEmpty else {
                return nil
            }
            return (symbol, .us, "US", "USD")
        }

        if codeUpper.hasPrefix("HK") || token == "hk" {
            let digits = codeUpper.hasPrefix("HK") ? String(codeUpper.dropFirst(2)) : codeUpper
            guard !digits.isEmpty else {
                return nil
            }
            if let numeric = Int(digits) {
                return (String(format: "%04d.HK", numeric), .hk, "HKEX", "HKD")
            }
            return ("\(digits).HK", .hk, "HKEX", "HKD")
        }

        return nil
    }

    private func deduplicatedSnapshots(_ snapshots: [QuoteSnapshot]) -> [QuoteSnapshot] {
        var seen = Set<QuoteRequest>()
        var output: [QuoteSnapshot] = []

        for snapshot in snapshots {
            guard !seen.contains(snapshot.request) else {
                continue
            }
            seen.insert(snapshot.request)
            output.append(snapshot)
        }

        return output
    }

    private func deduplicated(_ results: [SymbolSearchResult]) -> [SymbolSearchResult] {
        var seen = Set<String>()
        var output: [SymbolSearchResult] = []
        for result in results {
            let key = "\(result.symbol)|\(result.assetType.rawValue)|\(result.exchangeName)"
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            output.append(result)
        }
        return output
    }

    private func sortedSearchResults(
        _ results: [SymbolSearchResult],
        query: String
    ) -> [SymbolSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let lowerQuery = normalizedQuery.lowercased()

        func score(_ result: SymbolSearchResult) -> Int {
            let symbol = result.symbol.uppercased()
            let name = result.name.lowercased()

            if symbol == normalizedQuery {
                return 400
            }
            if symbol.hasPrefix(normalizedQuery) {
                return 300
            }
            if symbol.contains(normalizedQuery) {
                return 200
            }
            if name.contains(lowerQuery) {
                return 100
            }
            return 0
        }

        return results.sorted { lhs, rhs in
            let leftScore = score(lhs)
            let rightScore = score(rhs)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return lhs.symbol < rhs.symbol
        }
    }

    private func mapSearchQuoteToResult(_ item: YahooSearchQuote) -> SymbolSearchResult? {
        guard let symbol = item.symbol?.trimmingCharacters(in: .whitespacesAndNewlines), !symbol.isEmpty else {
            return nil
        }

        let exchangeName = item.exchangeDisplayName ?? item.exchangeName ?? item.exchange ?? "Unknown"
        let assetType = inferAssetTypeFromSymbol(symbol, quoteType: item.quoteType)
        let market = inferMarket(symbol: symbol, exchangeName: exchangeName)
        let name = item.longName ?? item.shortName ?? symbol

        return SymbolSearchResult(
            symbol: symbol,
            name: name,
            market: market,
            assetType: assetType,
            exchangeName: exchangeName,
            currencyCode: item.currency?.uppercased()
        )
    }

    private func inferAssetTypeFromSymbol(_ symbol: String, quoteType: String?) -> AssetType {
        let symbolUpper = symbol.uppercased()
        let quoteTypeUpper = quoteType?.uppercased() ?? ""

        if quoteTypeUpper.contains("CRYPTO")
            || symbolUpper.contains("-USD")
            || symbolUpper.contains("-USDT")
            || symbolUpper.contains("-BTC")
        {
            return .crypto
        }

        return .stock
    }

    private func inferMarket(symbol: String, exchangeName: String?) -> StockMarket {
        let symbolUpper = symbol.uppercased()
        let exchangeUpper = exchangeName?.uppercased() ?? ""

        if symbolUpper.hasSuffix(".HK")
            || exchangeUpper.contains("HONG KONG")
            || exchangeUpper.contains("HKEX")
        {
            return .hk
        }

        if exchangeUpper.contains("NASDAQ")
            || exchangeUpper.contains("NYSE")
            || exchangeUpper.contains("AMEX")
            || exchangeUpper.contains("US")
        {
            return .us
        }

        return .global
    }
}

private struct YahooQuoteResponse: Decodable {
    let quoteResponse: YahooQuoteContainer
}

private struct YahooQuoteContainer: Decodable {
    let result: [YahooQuoteItem]
}

private struct YahooQuoteItem: Decodable {
    let symbol: String?
    let regularMarketPrice: Double?
    let currency: String?
    let regularMarketTime: TimeInterval?
    let shortName: String?
    let longName: String?
    let quoteType: String?
    let exchange: String?
    let exchangeDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case symbol
        case regularMarketPrice
        case currency
        case regularMarketTime
        case shortName
        case longName
        case quoteType
        case exchange
        case exchangeDisplayName = "fullExchangeName"
    }
}

private struct YahooSearchResponse: Decodable {
    let quotes: [YahooSearchQuote]?
}

private struct YahooSearchQuote: Decodable {
    let symbol: String?
    let shortName: String?
    let longName: String?
    let quoteType: String?
    let exchange: String?
    let exchangeName: String?
    let exchangeDisplayName: String?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case symbol
        case shortName = "shortname"
        case longName = "longname"
        case quoteType
        case exchange
        case exchangeName = "exchDisp"
        case exchangeDisplayName = "exchangeDisp"
        case currency
    }
}

private struct CoinbaseSpotResponse: Decodable {
    let data: CoinbaseSpotData
}

private struct CoinbaseSpotData: Decodable {
    let amount: String
}

private struct BinanceTickerResponse: Decodable {
    let price: String
}
