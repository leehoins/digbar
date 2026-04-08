import Foundation

// MARK: - Binance Models

struct BinanceBalance: Identifiable, Codable {
    let asset: String
    let free: String
    let locked: String

    var id: String { asset }
    var freeDouble: Double { Double(free) ?? 0 }
    var lockedDouble: Double { Double(locked) ?? 0 }
    var totalDouble: Double { freeDouble + lockedDouble }
}

struct BinanceAccountResponse: Codable {
    let balances: [BinanceBalance]
}

struct BinanceTicker: Codable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String

    var lastPriceDouble: Double { Double(lastPrice) ?? 0 }
    var changePercentDouble: Double { Double(priceChangePercent) ?? 0 }
}

struct BinanceFuturesPosition: Identifiable {
    let symbol: String
    let positionSide: String
    let positionAmt: Double
    let entryPrice: Double
    let markPrice: Double
    let unRealizedProfit: Double
    let liquidationPrice: Double
    let leverage: Int
    let marginType: String

    var id: String { symbol + positionSide }
    var isLong: Bool { positionAmt > 0 }

    var roi: Double {
        guard entryPrice > 0 else { return 0 }
        let direction: Double = isLong ? 1 : -1
        return (markPrice - entryPrice) / entryPrice * Double(leverage) * 100 * direction
    }
}

struct BinanceFuturesAccount {
    let totalMarginBalance: Double
    let totalWalletBalance: Double
    let totalUnrealizedProfit: Double
}

struct BinancePortfolio {
    let balances: [BinanceBalance]
    let prices: [String: Double]
    let tickers: [String: BinanceTicker]
    let isDemo: Bool
    let futuresAccount: BinanceFuturesAccount?
    let futuresPositions: [BinanceFuturesPosition]

    init(balances: [BinanceBalance], prices: [String: Double], tickers: [String: BinanceTicker],
         isDemo: Bool, futuresAccount: BinanceFuturesAccount? = nil, futuresPositions: [BinanceFuturesPosition] = []) {
        self.balances = balances
        self.prices = prices
        self.tickers = tickers
        self.isDemo = isDemo
        self.futuresAccount = futuresAccount
        self.futuresPositions = futuresPositions
    }

    var totalUSDT: Double {
        if let futures = futuresAccount { return futures.totalMarginBalance }
        return balances
            .filter { $0.totalDouble > 0 }
            .reduce(0.0) { sum, balance in
                if balance.asset == "USDT" || balance.asset == "BUSD" {
                    return sum + balance.totalDouble
                }
                let symbol = "\(balance.asset)USDT"
                if let price = prices[symbol] {
                    return sum + balance.totalDouble * price
                }
                return sum
            }
    }

    var significantBalances: [BinanceBalance] {
        balances
            .filter { b in
                guard b.totalDouble > 0 else { return false }
                if b.asset == "USDT" || b.asset == "BUSD" { return b.totalDouble > 0.5 }
                let sym = "\(b.asset)USDT"
                return (prices[sym] ?? 0) * b.totalDouble > 0.5
            }
            .sorted { a, b in
                let aUSD = usdValue(a)
                let bUSD = usdValue(b)
                return aUSD > bUSD
            }
    }

    private func usdValue(_ b: BinanceBalance) -> Double {
        if b.asset == "USDT" || b.asset == "BUSD" { return b.totalDouble }
        return b.totalDouble * (prices["\(b.asset)USDT"] ?? 0)
    }
}

// MARK: - KIS Models

struct KISPortfolio {
    let holdings: [KISHolding]
    let summary: KISSummary
    let isDemo: Bool

    var totalEvalAmount: Double { summary.totalEvalAmount }
    var totalProfitLoss: Double {
        holdings.reduce(0) { $0 + $1.profitLoss }
    }
    var totalProfitLossRate: Double {
        let totalPurchase = holdings.reduce(0) { $0 + $1.purchaseAmount }
        guard totalPurchase > 0 else { return 0 }
        return totalProfitLoss / totalPurchase * 100
    }
}

struct KISHolding: Identifiable {
    let id = UUID()
    let stockCode: String
    let stockName: String
    let quantity: Int
    let avgPrice: Double
    let currentPrice: Double
    let profitLossRate: Double
    let evalAmount: Double
    let purchaseAmount: Double

    var profitLoss: Double { evalAmount - purchaseAmount }
}

struct KISSummary {
    let depositAmount: Double
    let totalEvalAmount: Double
    let netAssetAmount: Double
}

// MARK: - KIS API Codable

struct KISTokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int?        // KIS returns an integer
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

struct KISBalanceResponse: Codable {
    let rtCd: String?
    let msgCd: String?
    let msg1: String?
    let output1: [KISOutput1]?
    let output2: [KISOutput2]?

    enum CodingKeys: String, CodingKey {
        case rtCd = "rt_cd"
        case msgCd = "msg_cd"
        case msg1
        case output1, output2
    }
}

struct KISOutput1: Codable {
    let pdno: String?
    let prdtName: String?
    let hldgQty: String?
    let pchsAvgPric: String?
    let prpr: String?
    let evluPflsRt: String?
    let evluAmt: String?
    let pchsAmt: String?

    enum CodingKeys: String, CodingKey {
        case pdno
        case prdtName = "prdt_name"
        case hldgQty = "hldg_qty"
        case pchsAvgPric = "pchs_avg_pric"
        case prpr
        case evluPflsRt = "evlu_pfls_rt"
        case evluAmt = "evlu_amt"
        case pchsAmt = "pchs_amt"
    }

    func toHolding() -> KISHolding? {
        guard
            let code = pdno, !code.isEmpty,
            let name = prdtName, !name.isEmpty,
            let qty = Int(hldgQty ?? "0"), qty > 0,
            let avg = Double(pchsAvgPric ?? "0"),
            let curr = Double(prpr ?? "0"),
            let rate = Double(evluPflsRt ?? "0"),
            let eval = Double(evluAmt ?? "0"),
            let pchs = Double(pchsAmt ?? "0")
        else { return nil }

        return KISHolding(
            stockCode: code,
            stockName: name,
            quantity: qty,
            avgPrice: avg,
            currentPrice: curr,
            profitLossRate: rate,
            evalAmount: eval,
            purchaseAmount: pchs
        )
    }
}

struct KISOutput2: Codable {
    let dncaTotAmt: String?
    let totEvluAmt: String?
    let nassAmt: String?

    enum CodingKeys: String, CodingKey {
        case dncaTotAmt = "dnca_tot_amt"
        case totEvluAmt = "tot_evlu_amt"
        case nassAmt = "nass_amt"
    }

    func toSummary() -> KISSummary {
        KISSummary(
            depositAmount: Double(dncaTotAmt ?? "0") ?? 0,
            totalEvalAmount: Double(totEvluAmt ?? "0") ?? 0,
            netAssetAmount: Double(nassAmt ?? "0") ?? 0
        )
    }
}

// MARK: - Market Index Models

struct MarketIndex: Identifiable {
    let id: String
    let name: String
    let price: Double
    let change: Double
    let changePercent: Double
    let currency: String
    let category: IndexCategory

    enum IndexCategory {
        case us, korea, crypto
    }
}

// MARK: - Chart

enum ChartInterval: String, CaseIterable {
    case min1  = "1분"
    case min3  = "3분"
    case min5  = "5분"
    case min10 = "10분"
    case min15 = "15분"
    case min30 = "30분"
    case hour1 = "1시간"
    case hour4 = "4시간"
    case day1  = "1일"
    case week1 = "1주"
}

struct ChartCandle {
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let timestamp: Date?
}

// MARK: - Yahoo Finance Codable

struct YahooFinanceResponse: Codable {
    let quoteResponse: QuoteResponse?
}

struct QuoteResponse: Codable {
    let result: [YahooQuote]?
    let error: String?
}

struct YahooQuote: Codable {
    let symbol: String
    let regularMarketPrice: Double?
    let regularMarketChange: Double?
    let regularMarketChangePercent: Double?
    let longName: String?
    let shortName: String?
    let currency: String?
}
