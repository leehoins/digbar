import Foundation
import Observation

@Observable
final class DataManager {
    // MARK: - Portfolio Data (all updated on main thread)
    var binanceRealPortfolio: BinancePortfolio?
    var binanceDemoPortfolio: BinancePortfolio?
    var kisRealPortfolio: KISPortfolio?
    var kisDemoPortfolio: KISPortfolio?
    var marketIndices: [MarketIndex] = []

    var errors: [String: String] = [:]
    var isLoading = false
    var lastUpdated: Date?

    // MARK: - Portfolio History
    let portfolioHistory = PortfolioHistory()

    // MARK: - Watchlist
    let watchlistManager = WatchlistManager()

    // MARK: - Live mark prices (updated via WebSocket)
    var futuresMarkPrices: [String: Double] = [:]

    // MARK: - Services
    private let binanceService = BinanceService()
    private let kisService = KISService()
    private let marketIndexService = MarketIndexService()
    private let wsService = BinanceWebSocketService()

    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    // MARK: - Status Bar

    var statusBarText: String {
        let mode  = AppSettings.shared.statusBarMode
        let asset = AppSettings.shared.statusBarAsset
        let icon  = AppSettings.shared.iconEmoji

        let amountStr: String
        switch asset {
        case .krw:
            let v = totalKRW
            amountStr = v > 0 ? "₩\(formatShortKRW(v))" : "₩--"
        case .usd:
            let v = totalUSD
            amountStr = v > 0 ? "$\(formatUSD(v))" : "$--"
        case .both:
            let krw = totalKRW
            let usd = totalUSD
            if krw > 0 && usd > 0 {
                amountStr = "₩\(formatShortKRW(krw)) | $\(formatUSD(usd))"
            } else if krw > 0 {
                amountStr = "₩\(formatShortKRW(krw))"
            } else if usd > 0 {
                amountStr = "$\(formatUSD(usd))"
            } else {
                amountStr = "--"
            }
        }

        switch mode {
        case .totalValue:
            return "\(icon) \(amountStr)"
        case .changePercent:
            let pct = combinedChangePercent
            return "\(icon) \(String(format: "%+.2f%%", pct))"
        case .both:
            let pct = combinedChangePercent
            return "\(icon) \(amountStr) \(String(format: "%+.2f%%", pct))"
        }
    }

    var statusBarColor: StatusBarColor {
        let pct = combinedChangePercent
        if pct > 0.001 { return .green }
        if pct < -0.001 { return .red }
        return .primary
    }

    enum StatusBarColor { case green, red, primary }

    // MARK: - Totals

    var totalUSD: Double {
        (binanceRealPortfolio?.totalUSDT ?? 0) + (binanceDemoPortfolio?.totalUSDT ?? 0)
    }

    var totalKRW: Double {
        (kisRealPortfolio?.summary.totalEvalAmount ?? 0) +
        (kisDemoPortfolio?.summary.totalEvalAmount ?? 0)
    }

    var combinedChangePercent: Double {
        var weighted = 0.0
        var totalWeight = 0.0

        for p in [kisRealPortfolio, kisDemoPortfolio].compactMap({ $0 }) {
            let w = p.summary.totalEvalAmount
            if w > 0 {
                weighted += p.totalProfitLossRate * w
                totalWeight += w
            }
        }
        guard totalWeight > 0 else { return 0 }
        return weighted / totalWeight
    }

    // MARK: - Auto Refresh

    func startAutoRefresh() {
        Task { await refreshAll() }

        let interval = TimeInterval(AppSettings.shared.refreshInterval)
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await refreshAll()
            }
        }

        // 가격 티커: 관심종목 가격만 빠른 주기로 갱신
        watchlistManager.startTicker(kisService: kisService)
    }

    func stopAutoRefresh() {
        timerTask?.cancel()
        timerTask = nil
        watchlistManager.stopTicker()
        Task { await wsService.disconnect() }
    }

    // MARK: - Refresh

    func refreshAll() async {
        await setLoading(true)

        let settings = AppSettings.shared

        await withTaskGroup(of: Void.self) { group in
            // Binance + 시장지수: 병렬
            if settings.binanceRealEnabled && !settings.binanceRealAPIKey.isEmpty {
                group.addTask { await self.refreshBinance(isDemo: false) }
            }
            if settings.binanceDemoEnabled && !settings.binanceDemoAPIKey.isEmpty {
                group.addTask { await self.refreshBinance(isDemo: true) }
            }
            group.addTask { await self.refreshMarketIndices() }

            // KIS: 실전 → 모의 순으로 직렬화 (초당 1건 제한 회피)
            let kisRealOn = settings.kisRealEnabled && !settings.kisRealAppKey.isEmpty
            let kisDemoOn = settings.kisDemoEnabled && !settings.kisDemoAppKey.isEmpty
            if kisRealOn || kisDemoOn {
                group.addTask {
                    if kisRealOn { await self.refreshKIS(isDemo: false) }
                    if kisDemoOn {
                        if kisRealOn {
                            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2초 간격
                        }
                        await self.refreshKIS(isDemo: true)
                    }
                }
            }
        }

        await MainActor.run {
            self.lastUpdated = Date()
            self.isLoading = false
            let krw = self.totalKRW
            let usd = self.totalUSD
            if krw > 0 || usd > 0 {
                self.portfolioHistory.append(krw: krw, usd: usd)
            }
        }

        // 관심종목 알림 체크 (가격은 별도 tickerInterval로 갱신)
        await MainActor.run { self.watchlistManager.checkAlerts() }
    }

    // MARK: - Private

    private func setLoading(_ value: Bool) async {
        await MainActor.run {
            self.isLoading = value
            if value { self.errors.removeAll() }
        }
    }

    private func refreshBinance(isDemo: Bool) async {
        let settings = AppSettings.shared
        let key = isDemo ? settings.binanceDemoAPIKey : settings.binanceRealAPIKey
        let secret = isDemo ? settings.binanceDemoAPISecret : settings.binanceRealAPISecret
        let errorKey = isDemo ? "binanceDemo" : "binanceReal"

        do {
            let portfolio = try await binanceService.fetchPortfolio(
                apiKey: key, apiSecret: secret, isDemo: isDemo
            )
            await MainActor.run {
                if isDemo { self.binanceDemoPortfolio = portfolio }
                else { self.binanceRealPortfolio = portfolio }
            }
            // Start (or reuse) WebSocket for live futures mark prices
            let positions = portfolio.futuresPositions
            if !positions.isEmpty {
                let symbols = positions.map { $0.symbol }
                await wsService.connect(symbols: symbols) { [weak self] symbol, price in
                    Task { @MainActor [weak self] in
                        self?.futuresMarkPrices[symbol] = price
                    }
                }
            }
        } catch {
            await MainActor.run { self.errors[errorKey] = error.localizedDescription }
        }
    }

    private func refreshKIS(isDemo: Bool) async {
        let settings = AppSettings.shared
        let appKey = isDemo ? settings.kisDemoAppKey : settings.kisRealAppKey
        let appSecret = isDemo ? settings.kisDemoAppSecret : settings.kisRealAppSecret
        let account = isDemo ? settings.kisDemoAccount : settings.kisRealAccount
        let errorKey = isDemo ? "kisDemo" : "kisReal"

        guard !account.isEmpty else {
            await MainActor.run { self.errors[errorKey] = "계좌번호를 입력해주세요" }
            return
        }

        do {
            let portfolio = try await kisService.fetchPortfolio(
                appKey: appKey, appSecret: appSecret,
                accountNumber: account, isDemo: isDemo
            )
            await MainActor.run {
                if isDemo { self.kisDemoPortfolio = portfolio }
                else { self.kisRealPortfolio = portfolio }
            }
        } catch let error as KISError {
            // Only invalidate token on actual auth failures, not on API/parameter errors
            if case .unauthorized = error {
                await kisService.invalidateToken(appKey: appKey)
            }
            await MainActor.run { self.errors[errorKey] = error.localizedDescription }
        } catch {
            await MainActor.run { self.errors[errorKey] = error.localizedDescription }
        }
    }

    private func refreshMarketIndices() async {
        let us = await marketIndexService.fetchUSIndices()
        let korea = await marketIndexService.fetchKoreanIndices(kisService: kisService)
        let crypto = await marketIndexService.fetchCryptoIndices(binanceService: binanceService)
        let order: [MarketIndex.IndexCategory] = [.us, .korea, .crypto]
        let sorted = (us + korea + crypto).sorted {
            (order.firstIndex(of: $0.category) ?? 99) < (order.firstIndex(of: $1.category) ?? 99)
        }
        await MainActor.run { self.marketIndices = sorted }
    }

    // MARK: - Chart Data

    func fetchChart(for index: MarketIndex, interval: ChartInterval) async -> [ChartCandle] {
        await marketIndexService.fetchChartData(for: index, interval: interval,
                                               binanceService: binanceService)
    }

    func fetchHoldingChart(stockCode: String, interval: ChartInterval) async -> [ChartCandle] {
        await marketIndexService.fetchStockCandles(stockCode: stockCode, interval: interval)
    }

    func fetchFuturesChart(symbol: String, interval: ChartInterval) async -> [ChartCandle] {
        switch interval {
        case .min1:  return await binanceService.fetchPublicKlines(symbol: symbol, interval: "1m",  limit: 60)
        case .min3:  return await binanceService.fetchPublicKlines(symbol: symbol, interval: "3m",  limit: 60)
        case .min5:  return await binanceService.fetchPublicKlines(symbol: symbol, interval: "5m",  limit: 60)
        case .min10:
            let raw = await binanceService.fetchPublicKlines(symbol: symbol, interval: "1m", limit: 600)
            return aggregateCandles(raw, by: 10)
        case .min15: return await binanceService.fetchPublicKlines(symbol: symbol, interval: "15m", limit: 60)
        case .min30: return await binanceService.fetchPublicKlines(symbol: symbol, interval: "30m", limit: 60)
        case .hour1: return await binanceService.fetchPublicKlines(symbol: symbol, interval: "1h",  limit: 60)
        case .hour4: return await binanceService.fetchPublicKlines(symbol: symbol, interval: "4h",  limit: 60)
        case .day1:  return await binanceService.fetchPublicKlines(symbol: symbol, interval: "1d",  limit: 90)
        case .week1: return await binanceService.fetchPublicKlines(symbol: symbol, interval: "1w",  limit: 52)
        }
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

    // MARK: - Formatting

    func formatShortKRW(_ value: Double) -> String {
        if abs(value) >= 100_000_000 {
            return String(format: "%.1f억", value / 100_000_000)
        } else if abs(value) >= 10_000 {
            return String(format: "%.0f만", value / 10_000)
        }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    func formatUSD(_ value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return fmt.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}
