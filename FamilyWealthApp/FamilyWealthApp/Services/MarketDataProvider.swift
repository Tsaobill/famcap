import Foundation

struct QuoteRequest: Hashable {
    let symbol: String
    let type: AssetType
    let market: StockMarket
}

struct QuoteSnapshot: Hashable {
    let request: QuoteRequest
    let unitPrice: Double
    let currencyCode: String
    let asOf: Date
}

struct SymbolSearchResult: Hashable, Identifiable {
    let symbol: String
    let name: String
    let market: StockMarket
    let assetType: AssetType
    let exchangeName: String
    let currencyCode: String?

    var id: String { "\(symbol)|\(exchangeName)|\(assetType.rawValue)" }
}

enum MarketDataError: LocalizedError {
    case invalidSymbol
    case invalidResponse(String)
    case httpStatus(Int)
    case network(String)
    case quoteNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidSymbol:
            return "Invalid quote symbol."
        case .invalidResponse(let reason):
            return "Invalid market data response: \(reason)"
        case .httpStatus(let code):
            return "Market data service returned HTTP \(code)."
        case .network(let message):
            return "Network error: \(message)"
        case .quoteNotFound(let symbol):
            return "No market quote for \(symbol)."
        }
    }
}

protocol MarketQuoteProviding {
    func fetchQuotes(for requests: [QuoteRequest]) async throws -> [QuoteSnapshot]
}

protocol SymbolSearchProviding {
    func searchSymbols(query: String, preferredType: AssetType?) async throws -> [SymbolSearchResult]
}

protocol FXRateProviding {
    func fetchRate(from source: String, to target: String) async throws -> Double
}
