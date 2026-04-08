import Foundation

// MARK: - Model

struct TossStock: Identifiable {
    var id: String { symbol }
    var symbol: String      // Yahoo Finance 형식 (e.g. "005930.KS", "AAPL", "BTC-USD")
    var name: String
    var price: Double
    var changePercent: Double
    var market: Market

    enum Market: String, Codable, CaseIterable {
        case korea  = "한국"
        case us     = "미국"
        case crypto = "코인"
    }

    static func marketFrom(symbol: String, quoteType: String = "") -> Market {
        let sym = symbol.uppercased()
        // Toss 내부 코드
        if sym.hasPrefix("A"), sym.count == 7, Int(sym.dropFirst()) != nil { return .korea }
        if sym.hasPrefix("US"), sym.count > 10 { return .us }
        // Yahoo Finance 형식
        if sym.hasSuffix(".KS") || sym.hasSuffix(".KQ") { return .korea }
        if quoteType == "CRYPTOCURRENCY" || sym.hasSuffix("-USD") || sym.hasSuffix("-KRW")
            || sym.hasSuffix("USDT") || sym.hasSuffix("BTC") { return .crypto }
        return .us
    }
}

// MARK: - Service

actor TossInvestService {

    // MARK: - 인기종목 (Daum Finance)

    func fetchPopularStocks() async -> [TossStock] {
        return await fetchDaumRanking()
    }

    private func fetchDaumRanking() async -> [TossStock] {
        guard let url = URL(string: "https://finance.daum.net/api/search/ranks?limit=30") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("https://finance.daum.net/", forHTTPHeaderField: "Referer")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parseDaumRanking(data)
    }

    // MARK: - 종목 검색 (Toss 우선 → Yahoo Finance fallback)

    func searchStock(query: String) async -> [TossStock] {
        // 1) Toss POST 검색 (UTK 불필요, 한국+미국 통합)
        if let results = await searchToss(query: query), !results.isEmpty {
            return results
        }
        // 2) Binance 코인 직접 조회
        if let coin = await searchBinance(query: query) {
            return [coin]
        }
        // 3) Yahoo fallback
        return await searchYahoo(query: query)
    }

    /// POST wts-info-api/api/v2/search/stocks — UTK 불필요, 한국·미국 종목 통합 검색
    private func searchToss(query: String) async -> [TossStock]? {
        guard let url = URL(string: "https://wts-info-api.tossinvest.com/api/v2/search/stocks") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://tossinvest.com/", forHTTPHeaderField: "Referer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "size": 15])
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let list = result["stocks"] as? [[String: Any]], !list.isEmpty
        else { return nil }

        return list.compactMap { d -> TossStock? in
            // stockCode: "A034730" (한국), "US19801212001" (미국)
            let code = d["stockCode"] as? String ?? ""
            let nm   = d["stockName"] as? String ?? code
            guard !code.isEmpty else { return nil }
            let market = TossStock.marketFrom(symbol: code)
            return TossStock(symbol: code, name: nm, price: 0, changePercent: 0, market: market)
        }
    }

    private func searchBinance(query: String) async -> TossStock? {
        // 쿼리가 코인 심볼처럼 생겼을 때만 시도 (예: BTC, ETH, BTCUSDT)
        let q = query.uppercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, q.count <= 10, !q.contains(" ") else { return nil }
        let symbol = q.hasSuffix("USDT") ? q : q + "USDT"
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=\(symbol)") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceStr = obj["price"] as? String,
              let price = Double(priceStr)
        else { return nil }
        return TossStock(symbol: symbol, name: symbol, price: price, changePercent: 0, market: .crypto)
    }

    private func searchYahoo(query: String) async -> [TossStock] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&lang=ko&region=KR&quotesCount=15&newsCount=0&enableFuzzyQuery=true")
        else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = obj["quotes"] as? [[String: Any]]
        else { return [] }

        let allowed: Set<String> = ["Equity", "ETF", "CRYPTOCURRENCY", "MUTUALFUND"]
        return quotes.compactMap { q -> TossStock? in
            guard let sym = q["symbol"] as? String else { return nil }
            let typeDisp  = q["typeDisp"]  as? String ?? ""
            let quoteType = q["quoteType"] as? String ?? ""
            guard allowed.contains(typeDisp) || allowed.contains(quoteType) else { return nil }
            let name = (q["longname"] as? String) ?? (q["shortname"] as? String) ?? sym
            let market = TossStock.marketFrom(symbol: sym, quoteType: quoteType)
            return TossStock(symbol: sym, name: name, price: 0, changePercent: 0, market: market)
        }
    }

    // MARK: - 가격 조회 (마켓별 라우팅)
    // WatchlistManager에서 직접 각 서비스 호출 — KISService는 actor이므로 호출자가 전달

    /// Binance 공개 현재가 (인증 불필요)
    func fetchBinancePrice(symbol: String) async -> Double? {
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=\(symbol)") else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let priceStr = obj["price"] as? String
        else { return nil }
        return Double(priceStr)
    }

    /// 한국주식 현재가 — wts-info-api (UTK 불필요, 공개 엔드포인트)
    /// symbol: "005930" → productCode "A005930"
    func fetchTossKoreanPrice(symbol: String) async -> Double? {
        let code = "A\(symbol)"
        guard let url = URL(string: "https://wts-info-api.tossinvest.com/api/v3/stock-prices/details?productCodes=\(code)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("https://tossinvest.com/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 6

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["result"] as? [[String: Any]],
              let first = results.first,
              let price = first["close"] as? Double, price > 0
        else { return nil }
        return price
    }

    /// 복수 한국주식 현재가 배치 조회 (관심종목 등에서 한 번에)
    func fetchTossKoreanPrices(symbols: [String]) async -> [String: Double] {
        guard !symbols.isEmpty else { return [:] }
        let codes = symbols.map { "A\($0)" }
        let query = codes.map { "productCodes=\($0)" }.joined(separator: "&")
        guard let url = URL(string: "https://wts-info-api.tossinvest.com/api/v3/stock-prices/details?\(query)") else { return [:] }
        var req = URLRequest(url: url)
        req.setValue("https://tossinvest.com/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 8

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["result"] as? [[String: Any]]
        else { return [:] }

        var out: [String: Double] = [:]
        for item in results {
            guard let code = item["code"] as? String,   // "A005930"
                  let price = item["close"] as? Double, price > 0
            else { continue }
            // "A005930" → "005930"
            let sym = code.hasPrefix("A") ? String(code.dropFirst()) : code
            out[sym] = price
        }
        return out
    }

    /// Toss wts-info-api 단일 종목 가격 (한국·미국 공통, UTK 불필요)
    /// code: "A034730" (한국) or "US19801212001" (미국)
    func fetchTossPrice(code: String) async -> Double? {
        guard let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://wts-info-api.tossinvest.com/api/v3/stock-prices/details?productCodes=\(encoded)")
        else { return nil }
        var req = URLRequest(url: url)
        req.setValue("https://tossinvest.com/", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["result"] as? [[String: Any]],
              let price = results.first?["close"] as? Double, price > 0
        else { return nil }
        return price
    }


    // MARK: - USD/KRW 환율

    /// USD/KRW 현재 환율 (Yahoo Finance)
    func fetchUSDKRWRate() async -> Double? {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/USDKRW=X?range=1d&interval=1d") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = obj["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let rate = meta["regularMarketPrice"] as? Double, rate > 0
        else { return nil }
        return rate
    }

    // MARK: - Parsers

    private func parseDaumRanking(_ data: Data) -> [TossStock] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let lists: [[Any]] = [
            obj["data"] as? [Any],
            obj["stocks"] as? [Any],
            (obj["data"] as? [String: Any])?["list"] as? [Any],
        ].compactMap { $0 as? [Any] }

        for list in lists {
            let stocks: [TossStock] = list.compactMap { item -> TossStock? in
                guard let d = item as? [String: Any] else { return nil }
                var sym = d["symbolCode"] as? String ?? d["symbol"] as? String ?? d["code"] as? String ?? ""
                if sym.isEmpty { return nil }
                if sym.first == "A", sym.count == 7, Int(sym.dropFirst()) != nil {
                    sym = String(sym.dropFirst()) + ".KS"
                }
                let nm  = d["name"] as? String ?? d["stockName"] as? String ?? sym
                let pr  = (d["tradePrice"] as? Double)
                    ?? (d["currentPrice"] as? Double)
                    ?? (d["price"] as? Double)
                    ?? Double(d["tradePrice"] as? String ?? "0") ?? 0
                let chg = (d["changeRate"] as? Double ?? 0) * 100
                let stockType = d["stockType"] as? String ?? ""
                let market: TossStock.Market = stockType.contains("FOREIGN") ? .us
                    : (stockType.contains("CRYPTO") ? .crypto : .korea)
                guard pr > 0 else { return nil }
                return TossStock(symbol: sym, name: nm, price: pr, changePercent: chg, market: market)
            }
            if !stocks.isEmpty { return stocks }
        }
        return []
    }
}
