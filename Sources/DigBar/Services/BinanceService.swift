import Foundation

actor BinanceService {
    private let spotURL     = "https://api.binance.com"
    private let demoSpotURL = "https://demo-api.binance.com"
    private let fapiURL     = "https://fapi.binance.com"
    private let demoFapiURL = "https://demo-fapi.binance.com"

    // MARK: - Fetch Portfolio

    func fetchPortfolio(apiKey: String, apiSecret: String, isDemo: Bool) async throws -> BinancePortfolio {
        let cleanKey    = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let spotBase = isDemo ? demoSpotURL : spotURL
        let fapiBase = isDemo ? demoFapiURL : fapiURL

        async let spotTask    = fetchSpotData(apiKey: cleanKey, apiSecret: cleanSecret, baseURL: spotBase)
        async let futuresTask = fetchFuturesData(apiKey: cleanKey, apiSecret: cleanSecret, baseURL: fapiBase)

        let spot    = try await spotTask
        let futures = try? await futuresTask

        return BinancePortfolio(
            balances: spot.balances,
            prices: spot.prices,
            tickers: spot.tickers,
            isDemo: isDemo,
            futuresAccount: futures?.account,
            futuresPositions: futures?.positions ?? []
        )
    }

    // MARK: - Spot

    private struct SpotData {
        let balances: [BinanceBalance]
        let prices: [String: Double]
        let tickers: [String: BinanceTicker]
    }

    private func fetchSpotData(apiKey: String, apiSecret: String, baseURL: String) async throws -> SpotData {
        let account = try await fetchSpotAccount(apiKey: apiKey, apiSecret: apiSecret, baseURL: baseURL)

        let nonStable = account.balances
            .filter { $0.totalDouble > 0 && !["USDT","BUSD","USDC"].contains($0.asset) }
            .map { "\($0.asset)USDT" }

        var prices: [String: Double] = [:]
        var tickers: [String: BinanceTicker] = [:]
        if !nonStable.isEmpty {
            let fetched = (try? await fetchSpotTickers(symbols: nonStable, baseURL: spotURL)) ?? []
            for t in fetched { prices[t.symbol] = t.lastPriceDouble; tickers[t.symbol] = t }
        }
        return SpotData(balances: account.balances, prices: prices, tickers: tickers)
    }

    private func fetchSpotAccount(apiKey: String, apiSecret: String, baseURL: String) async throws -> BinanceAccountResponse {
        let ts  = Int64(Date().timeIntervalSince1970 * 1000)
        let qs  = "timestamp=\(ts)&recvWindow=60000"
        let sig = CryptoHelper.hmacSHA256(key: apiSecret, data: qs)
        guard let url = URL(string: "\(baseURL)/api/v3/account?\(qs)&signature=\(sig)") else { throw BinanceError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(data: data, response: resp)
        return try JSONDecoder().decode(BinanceAccountResponse.self, from: data)
    }

    private func fetchSpotTickers(symbols: [String], baseURL: String) async throws -> [BinanceTicker] {
        let json    = "[" + symbols.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let encoded = json.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? json
        guard let url = URL(string: "\(baseURL)/api/v3/ticker/24hr?symbols=\(encoded)") else { throw BinanceError.invalidURL }
        let (data, resp) = try await URLSession.shared.data(from: url)
        try checkResponse(data: data, response: resp)
        return try JSONDecoder().decode([BinanceTicker].self, from: data)
    }

    // MARK: - Futures

    private struct FuturesData {
        let account: BinanceFuturesAccount
        let positions: [BinanceFuturesPosition]
    }

    private func fetchFuturesData(apiKey: String, apiSecret: String, baseURL: String) async throws -> FuturesData {
        async let accountTask   = fetchFuturesAccount(apiKey: apiKey, apiSecret: apiSecret, baseURL: baseURL)
        async let positionsTask = fetchFuturesPositions(apiKey: apiKey, apiSecret: apiSecret, baseURL: baseURL)
        return try await FuturesData(account: accountTask, positions: positionsTask)
    }

    private func fetchFuturesAccount(apiKey: String, apiSecret: String, baseURL: String) async throws -> BinanceFuturesAccount {
        let ts  = Int64(Date().timeIntervalSince1970 * 1000)
        let qs  = "timestamp=\(ts)&recvWindow=60000"
        let sig = CryptoHelper.hmacSHA256(key: apiSecret, data: qs)
        guard let url = URL(string: "\(baseURL)/fapi/v2/account?\(qs)&signature=\(sig)") else { throw BinanceError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(data: data, response: resp)
        let decoded = try JSONDecoder().decode(FuturesAccountResponse.self, from: data)
        return BinanceFuturesAccount(
            totalMarginBalance:    Double(decoded.totalMarginBalance)    ?? 0,
            totalWalletBalance:    Double(decoded.totalWalletBalance)    ?? 0,
            totalUnrealizedProfit: Double(decoded.totalUnrealizedProfit) ?? 0
        )
    }

    private func fetchFuturesPositions(apiKey: String, apiSecret: String, baseURL: String) async throws -> [BinanceFuturesPosition] {
        let ts  = Int64(Date().timeIntervalSince1970 * 1000)
        let qs  = "timestamp=\(ts)&recvWindow=60000"
        let sig = CryptoHelper.hmacSHA256(key: apiSecret, data: qs)
        guard let url = URL(string: "\(baseURL)/fapi/v2/positionRisk?\(qs)&signature=\(sig)") else { throw BinanceError.invalidURL }

        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(data: data, response: resp)
        let decoded = try JSONDecoder().decode([FuturesPositionRisk].self, from: data)

        return decoded
            .filter { abs(Double($0.positionAmt) ?? 0) > 0 }
            .map { pos in
                BinanceFuturesPosition(
                    symbol:           pos.symbol,
                    positionSide:     pos.positionSide,
                    positionAmt:      Double(pos.positionAmt)      ?? 0,
                    entryPrice:       Double(pos.entryPrice)       ?? 0,
                    markPrice:        Double(pos.markPrice)        ?? 0,
                    unRealizedProfit: Double(pos.unRealizedProfit) ?? 0,
                    liquidationPrice: Double(pos.liquidationPrice) ?? 0,
                    leverage:         Int(pos.leverage)            ?? 1,
                    marginType:       pos.marginType
                )
            }
    }

    // MARK: - Public ticker (시장 지수용)

    func fetchPublicTicker(symbol: String) async throws -> BinanceTicker {
        guard let url = URL(string: "\(spotURL)/api/v3/ticker/24hr?symbol=\(symbol)") else { throw BinanceError.invalidURL }
        let (data, resp) = try await URLSession.shared.data(from: url)
        try checkResponse(data: data, response: resp)
        return try JSONDecoder().decode(BinanceTicker.self, from: data)
    }

    // MARK: - Public Chart Data

    func fetchPublicKlines(symbol: String, interval: String, limit: Int) async -> [ChartCandle] {
        guard let url = URL(string: "\(spotURL)/api/v3/klines?symbol=\(symbol)&interval=\(interval)&limit=\(limit)") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return array.compactMap { c -> ChartCandle? in
            guard c.count > 4,
                  let o  = Double(c[1] as? String ?? ""),
                  let h  = Double(c[2] as? String ?? ""),
                  let l  = Double(c[3] as? String ?? ""),
                  let cl = Double(c[4] as? String ?? "")
            else { return nil }
            // c[0] is openTime in milliseconds (NSNumber from JSONSerialization)
            let ts: Date? = (c[0] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue / 1000)
            }
            return ChartCandle(open: o, high: h, low: l, close: cl, timestamp: ts)
        }
    }

    // MARK: - Response checking

    private func checkResponse(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200...299).contains(http.statusCode) else { return }

        if let err = try? JSONDecoder().decode(BinanceAPIError.self, from: data) {
            switch err.code {
            case -2014: throw BinanceError.apiError("API 키 형식 오류 (code: \(err.code))")
            case -2015: throw BinanceError.apiError("API 키/IP/권한 오류 (code: \(err.code))")
            case -1022: throw BinanceError.apiError("서명 오류 — Secret Key 확인 (code: \(err.code))")
            case -1021: throw BinanceError.apiError("타임스탬프 오류 — 기기 시간 확인 (code: \(err.code))")
            default:    throw BinanceError.apiError("\(err.msg) (code: \(err.code))")
            }
        }
        throw BinanceError.httpError(http.statusCode)
    }
}

// MARK: - Codable helpers

private struct FuturesAccountResponse: Codable {
    let totalMarginBalance:    String
    let totalWalletBalance:    String
    let totalUnrealizedProfit: String
}

private struct FuturesPositionRisk: Codable {
    let symbol:           String
    let positionSide:     String
    let positionAmt:      String
    let entryPrice:       String
    let markPrice:        String
    let unRealizedProfit: String
    let liquidationPrice: String
    let leverage:         String
    let marginType:       String
}

private struct BinanceAPIError: Codable {
    let code: Int
    let msg: String
}

enum BinanceError: LocalizedError {
    case invalidURL
    case apiError(String)
    case rateLimited
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "잘못된 URL"
        case .apiError(let msg): return "Binance: \(msg)"
        case .rateLimited:       return "Binance: 요청 한도 초과"
        case .httpError(let c):  return "Binance: HTTP \(c)"
        }
    }
}
