import Foundation

actor MarketIndexService {
    private let yahooBase = "https://query2.finance.yahoo.com/v8/finance/chart"
    private let kisRealBase = "https://openapi.koreainvestment.com:9443"
    private let kisDemoBase = "https://openapivts.koreainvestment.com:29443"

    // US indices only — fetched from Yahoo Finance (no auth needed)
    static let usIndices: [(symbol: String, name: String)] = [
        ("^GSPC", "S&P 500"),
        ("^IXIC", "NASDAQ"),
        ("^DJI",  "DOW"),
    ]

    // Korean indices via KIS OpenAPI
    static let kisKoreanIndices: [(code: String, name: String)] = [
        ("0001", "KOSPI"),
        ("1001", "KOSDAQ"),
    ]

    static let cryptoSymbols = ["BTCUSDT", "ETHUSDT"]

    // MARK: - US Indices (Yahoo Finance v8)

    func fetchUSIndices() async -> [MarketIndex] {
        var result: [MarketIndex] = []
        await withTaskGroup(of: MarketIndex?.self) { group in
            for def in Self.usIndices {
                group.addTask { await self.fetchYahoo(symbol: def.symbol, name: def.name) }
            }
            for await index in group {
                if let index { result.append(index) }
            }
        }
        // Preserve definition order
        return result.sorted { lhs, rhs in
            (Self.usIndices.firstIndex(where: { $0.symbol == lhs.id }) ?? 99) <
            (Self.usIndices.firstIndex(where: { $0.symbol == rhs.id }) ?? 99)
        }
    }

    private func fetchYahoo(symbol: String, name: String) async -> MarketIndex? {
        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "\(yahooBase)/\(encoded)?interval=1d&range=1d") else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let meta = (try? JSONDecoder().decode(V8Response.self, from: data))?.chart.result?.first?.meta
        else { return nil }

        let price     = meta.regularMarketPrice
        let prev      = meta.chartPreviousClose ?? price
        let change    = price - prev
        let changePct = prev > 0 ? change / prev * 100 : 0

        return MarketIndex(id: symbol, name: name, price: price,
                           change: change, changePercent: changePct,
                           currency: "USD", category: .us)
    }

    // MARK: - Korean Indices (KIS OpenAPI)

    func fetchKoreanIndices(kisService: KISService) async -> [MarketIndex] {
        let settings = AppSettings.shared
        // Use whichever KIS key is available (prefer real)
        let (appKey, appSecret, isDemo): (String, String, Bool)
        if settings.kisRealEnabled && !settings.kisRealAppKey.isEmpty {
            (appKey, appSecret, isDemo) = (settings.kisRealAppKey, settings.kisRealAppSecret, false)
        } else if settings.kisDemoEnabled && !settings.kisDemoAppKey.isEmpty {
            (appKey, appSecret, isDemo) = (settings.kisDemoAppKey, settings.kisDemoAppSecret, true)
        } else {
            return await fetchKoreanIndicesYahoo() // fallback
        }

        // 순차 호출 (0.5s 간격) — 동시 호출 시 EGW00201 초당 한도 초과 방지
        var result: [MarketIndex] = []
        for (i, def) in Self.kisKoreanIndices.enumerated() {
            if i > 0 { try? await Task.sleep(nanoseconds: 500_000_000) }
            if let idx = await fetchKISIndex(
                code: def.code, name: def.name,
                appKey: appKey, appSecret: appSecret, isDemo: isDemo,
                kisService: kisService
            ) { result.append(idx) }
        }
        // Fallback to Yahoo if KIS failed
        if result.isEmpty { return await fetchKoreanIndicesYahoo() }
        return result.sorted { a, b in
            (Self.kisKoreanIndices.firstIndex(where: { $0.name == a.name }) ?? 99) <
            (Self.kisKoreanIndices.firstIndex(where: { $0.name == b.name }) ?? 99)
        }
    }

    private func fetchKISIndex(code: String, name: String,
                                appKey: String, appSecret: String, isDemo: Bool,
                                kisService: KISService) async -> MarketIndex? {
        guard let token = try? await kisService.getMarketToken(
            appKey: appKey, appSecret: appSecret, isDemo: isDemo
        ) else { return nil }

        let base = isDemo ? kisDemoBase : kisRealBase
        var comps = URLComponents(string: "\(base)/uapi/domestic-stock/v1/quotations/inquire-index-price")!
        comps.queryItems = [
            URLQueryItem(name: "FID_COND_MRKT_DIV_CODE", value: "U"),
            URLQueryItem(name: "FID_INPUT_ISCD", value: code),
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        req.setValue(appKey, forHTTPHeaderField: "appkey")
        req.setValue(appSecret, forHTTPHeaderField: "appsecret")
        req.setValue("FHKST03010100", forHTTPHeaderField: "tr_id")
        req.timeoutInterval = 10

        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let decoded = try? JSONDecoder().decode(KISIndexResponse.self, from: data),
            decoded.rtCd == "0",
            let output = decoded.output,
            let price = Double(output.bstpNmixPrpr ?? ""),
            price > 0
        else { return nil }

        let prev      = Double(output.bstpNmixPrdyClpr ?? "") ?? price
        let change    = price - prev
        let changePct = prev > 0 ? change / prev * 100 : 0

        return MarketIndex(id: code, name: name, price: price,
                           change: change, changePercent: changePct,
                           currency: "KRW", category: .korea)
    }

    // Yahoo fallback for Korean indices
    private func fetchKoreanIndicesYahoo() async -> [MarketIndex] {
        var result: [MarketIndex] = []
        for (symbol, name) in [("^KS11", "KOSPI"), ("^KQ11", "KOSDAQ")] {
            if var index = await fetchYahoo(symbol: symbol, name: name) {
                index = MarketIndex(id: index.id, name: name, price: index.price,
                                    change: index.change, changePercent: index.changePercent,
                                    currency: "KRW", category: .korea)
                result.append(index)
            }
        }
        return result
    }

    // MARK: - Crypto (Binance)

    func fetchCryptoIndices(binanceService: BinanceService) async -> [MarketIndex] {
        var result: [MarketIndex] = []
        for symbol in Self.cryptoSymbols {
            guard let ticker = try? await binanceService.fetchPublicTicker(symbol: symbol) else { continue }
            let base = symbol.replacingOccurrences(of: "USDT", with: "")
            result.append(MarketIndex(
                id: symbol, name: base + "/USDT",
                price: ticker.lastPriceDouble, change: 0,
                changePercent: ticker.changePercentDouble,
                currency: "USDT", category: .crypto
            ))
        }
        return result
    }

    // MARK: - Chart Data

    func fetchChartData(for index: MarketIndex, interval: ChartInterval,
                        binanceService: BinanceService) async -> [ChartCandle] {
        switch index.category {
        case .crypto:
            switch interval {
            case .min1:  return await binanceService.fetchPublicKlines(symbol: index.id, interval: "1m",  limit: 60)
            case .min3:  return await binanceService.fetchPublicKlines(symbol: index.id, interval: "3m",  limit: 60)
            case .min5:  return await binanceService.fetchPublicKlines(symbol: index.id, interval: "5m",  limit: 60)
            case .min10:
                let raw = await binanceService.fetchPublicKlines(symbol: index.id, interval: "1m", limit: 600)
                return aggregateCandles(raw, by: 10)
            case .min15: return await binanceService.fetchPublicKlines(symbol: index.id, interval: "15m", limit: 60)
            case .min30: return await binanceService.fetchPublicKlines(symbol: index.id, interval: "30m", limit: 60)
            case .hour1: return await binanceService.fetchPublicKlines(symbol: index.id, interval: "1h",  limit: 60)
            case .hour4: return await binanceService.fetchPublicKlines(symbol: index.id, interval: "4h",  limit: 60)
            case .day1:  return await binanceService.fetchPublicKlines(symbol: index.id, interval: "1d",  limit: 90)
            case .week1: return await binanceService.fetchPublicKlines(symbol: index.id, interval: "1w",  limit: 52)
            }
        default:
            let symbol = yahooChartSymbol(for: index)
            return await fetchYahooCandles(symbol: symbol, interval: interval)
        }
    }

    func fetchStockCandles(stockCode: String, interval: ChartInterval) async -> [ChartCandle] {
        let ks = await fetchYahooCandles(symbol: "\(stockCode).KS", interval: interval)
        if !ks.isEmpty { return ks }
        return await fetchYahooCandles(symbol: "\(stockCode).KQ", interval: interval)
    }

    private func aggregateCandles(_ candles: [ChartCandle], by n: Int) -> [ChartCandle] {
        guard n > 1 else { return candles }
        var result: [ChartCandle] = []
        var i = 0
        while i < candles.count {
            let group = Array(candles[i..<min(i + n, candles.count)])
            guard let first = group.first, let last = group.last else { break }
            result.append(ChartCandle(
                open:  first.open,
                high:  group.map(\.high).max()!,
                low:   group.map(\.low).min()!,
                close: last.close,
                timestamp: first.timestamp
            ))
            i += n
        }
        return result
    }

    private func yahooChartSymbol(for index: MarketIndex) -> String {
        if index.category == .korea {
            return index.name == "KOSPI" ? "^KS11" : "^KQ11"
        }
        return index.id
    }

    private func fetchYahooCandles(symbol: String, interval: ChartInterval) async -> [ChartCandle] {
        let yahooInterval: String
        let range: String
        let aggregateBy: Int
        switch interval {
        case .min1:  yahooInterval = "1m";   range = "1d";   aggregateBy = 1
        case .min3:  yahooInterval = "1m";   range = "1d";   aggregateBy = 3
        case .min5:  yahooInterval = "5m";   range = "1d";   aggregateBy = 1
        case .min10: yahooInterval = "1m";   range = "1d";   aggregateBy = 10
        case .min15: yahooInterval = "15m";  range = "1d";   aggregateBy = 1
        case .min30: yahooInterval = "30m";  range = "1d";   aggregateBy = 1
        case .hour1: yahooInterval = "60m";  range = "1mo";  aggregateBy = 1
        case .hour4: yahooInterval = "60m";  range = "2mo";  aggregateBy = 4
        case .day1:  yahooInterval = "1d";   range = "3mo";  aggregateBy = 1
        case .week1: yahooInterval = "1wk";  range = "1y";   aggregateBy = 1
        }

        let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "\(yahooBase)/\(encoded)?interval=\(yahooInterval)&range=\(range)") else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10

        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let result = (try? JSONDecoder().decode(V8Response.self, from: data))?.chart.result?.first,
            let quote = result.indicators?.quote?.first
        else { return [] }

        let timestamps = result.timestamp ?? []
        let opens  = quote.open  ?? []
        let highs  = quote.high  ?? []
        let lows   = quote.low   ?? []
        let closes = quote.close ?? []
        let count  = min(opens.count, highs.count, lows.count, closes.count)

        let raw = (0..<count).compactMap { i -> ChartCandle? in
            guard let o = opens[i], let h = highs[i], let l = lows[i], let c = closes[i] else { return nil }
            let ts = i < timestamps.count ? Date(timeIntervalSince1970: TimeInterval(timestamps[i])) : nil
            return ChartCandle(open: o, high: h, low: l, close: c, timestamp: ts)
        }
        return aggregateBy > 1 ? aggregateCandles(raw, by: aggregateBy) : raw
    }
}

// MARK: - Codable models

private struct V8Response: Codable {
    let chart: V8Chart
}
private struct V8Chart: Codable {
    let result: [V8Result]?
}
private struct V8Result: Codable {
    let meta: V8Meta
    let timestamp: [Int]?
    let indicators: V8Indicators?
}
private struct V8Meta: Codable {
    let regularMarketPrice: Double
    let chartPreviousClose: Double?
}
private struct V8Indicators: Codable {
    let quote: [V8Quote]?
}
private struct V8Quote: Codable {
    let open:  [Double?]?
    let high:  [Double?]?
    let low:   [Double?]?
    let close: [Double?]?
}

private struct KISIndexResponse: Codable {
    let rtCd: String?
    let output: KISIndexOutput?
    enum CodingKeys: String, CodingKey {
        case rtCd = "rt_cd"; case output
    }
}
private struct KISIndexOutput: Codable {
    let bstpNmixPrpr: String?    // 업종 지수 현재가
    let bstpNmixPrdyClpr: String? // 업종 지수 전일 종가
    enum CodingKeys: String, CodingKey {
        case bstpNmixPrpr = "bstp_nmix_prpr"
        case bstpNmixPrdyClpr = "bstp_nmix_prdy_clpr"
    }
}

enum MarketIndexError: LocalizedError {
    case fetchFailed
    var errorDescription: String? { "시장 지수를 불러오지 못했습니다" }
}
