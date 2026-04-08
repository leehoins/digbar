import SwiftUI

struct StatusMenuView: View {
    @Bindable var dataManager: DataManager
    var openSettings: (() -> Void)? = nil
    @State private var selectedTab: Tab = .portfolio

    enum Tab: String, CaseIterable {
        case portfolio = "포트폴리오"
        case indices = "시장"
    }

    var body: some View {
        let screenH = NSScreen.main?.visibleFrame.height ?? 900
        let maxH = screenH - 30

        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    if selectedTab == .portfolio {
                        portfolioContent
                    } else {
                        indicesContent
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollDisabled(true)

            Divider()
            footerBar
        }
        .frame(width: 400)
        .frame(maxHeight: maxH)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            headerTitle
            Spacer()
            tabSelector
            Divider().frame(height: 14).padding(.horizontal, 2)
            refreshButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DigBar").font(.headline)
            if let updated = dataManager.lastUpdated {
                Text("업데이트: \(timeFormatter.string(from: updated))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button(tab.rawValue) { selectedTab = tab }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .font(.caption)
    }

    private var refreshButton: some View {
        Button {
            Task { await dataManager.refreshAll() }
        } label: {
            Image(systemName: dataManager.isLoading ? "arrow.2.circlepath" : "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Portfolio Tab

    private var portfolioContent: some View {
        VStack(spacing: 10) {
            ForEach(dataManager.errors.sorted(by: { $0.key < $1.key }), id: \.key) { key, msg in
                ErrorBanner(label: errorLabel(key), message: msg)
            }

            let holdingChart: (String, ChartInterval) async -> [ChartCandle] = { [dm = dataManager] code, iv in
                await dm.fetchHoldingChart(stockCode: code, interval: iv)
            }
            let futuresChart: (String, ChartInterval) async -> [ChartCandle] = { [dm = dataManager] sym, iv in
                await dm.fetchFuturesChart(symbol: sym, interval: iv)
            }

            if let portfolio = dataManager.kisRealPortfolio {
                KISPortfolioCard(portfolio: portfolio, fetchChart: holdingChart)
            } else if AppSettings.shared.kisRealEnabled {
                PlaceholderCard(title: AppSettings.shared.kisRealName, icon: "🏦")
            }

            if let portfolio = dataManager.kisDemoPortfolio {
                KISPortfolioCard(portfolio: portfolio, fetchChart: holdingChart)
            } else if AppSettings.shared.kisDemoEnabled {
                PlaceholderCard(title: AppSettings.shared.kisDemoName, icon: "🏦")
            }

            if let portfolio = dataManager.binanceRealPortfolio {
                BinancePortfolioCard(portfolio: portfolio, markPrices: dataManager.futuresMarkPrices,
                                     fetchFuturesChart: futuresChart)
            } else if AppSettings.shared.binanceRealEnabled {
                PlaceholderCard(title: AppSettings.shared.binanceRealName, icon: "₿")
            }

            if let portfolio = dataManager.binanceDemoPortfolio {
                BinancePortfolioCard(portfolio: portfolio, markPrices: dataManager.futuresMarkPrices,
                                     fetchFuturesChart: futuresChart)
            } else if AppSettings.shared.binanceDemoEnabled {
                PlaceholderCard(title: AppSettings.shared.binanceDemoName, icon: "₿")
            }

            if hasAnyAccount {
                PortfolioHistoryCard(history: dataManager.portfolioHistory)
            }

            WatchlistCard(manager: dataManager.watchlistManager)

            if !hasAnyAccount { noAccountView }
        }
    }

    private var hasAnyAccount: Bool {
        let s = AppSettings.shared
        return s.kisRealEnabled || s.kisDemoEnabled || s.binanceRealEnabled || s.binanceDemoEnabled
    }

    private var noAccountView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("설정에서 계정을 연결하세요")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("설정 열기") { openSettings?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Indices Tab

    private var indicesContent: some View {
        VStack(spacing: 6) {
            if dataManager.marketIndices.isEmpty {
                Text("로딩 중...")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                let usIndices     = dataManager.marketIndices.filter { $0.category == .us }
                let krIndices     = dataManager.marketIndices.filter { $0.category == .korea }
                let cryptoIndices = dataManager.marketIndices.filter { $0.category == .crypto }

                let chartFetch: (MarketIndex, ChartInterval) async -> [ChartCandle] = { [dm = dataManager] idx, iv in
                    await dm.fetchChart(for: idx, interval: iv)
                }

                if !usIndices.isEmpty {
                    IndexSection(title: "🇺🇸 미국", indices: usIndices, fetchChart: chartFetch)
                }
                if !krIndices.isEmpty {
                    IndexSection(title: "🇰🇷 한국", indices: krIndices, fetchChart: chartFetch)
                }
                if !cryptoIndices.isEmpty {
                    IndexSection(title: "₿ 암호화폐", indices: cryptoIndices, fetchChart: chartFetch)
                }
            }

            TossPopularSection(watchlistManager: dataManager.watchlistManager)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Spacer()
            footerButton("설정", icon: "gearshape") { openSettings?() }
            Spacer()
            footerButton("새로고침", icon: "arrow.clockwise") {
                Task { await dataManager.refreshAll() }
            }
            Spacer()
            footerButton("종료", icon: "power") { NSApplication.shared.terminate(nil) }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func footerButton(_ title: String, icon: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17, weight: .light))
                Text(title).font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 52)
        }
        .buttonStyle(.plain)
    }

    private func errorLabel(_ key: String) -> String {
        switch key {
        case "kisReal": return "KIS 실전"
        case "kisDemo": return "KIS 모의"
        case "binanceReal": return "Binance 실전"
        case "binanceDemo": return "Binance 모의투자"
        default: return key
        }
    }
}

// MARK: - KIS Portfolio Card

struct KISPortfolioCard: View {
    let portfolio: KISPortfolio
    let fetchChart: (String, ChartInterval) async -> [ChartCandle]

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Label(portfolio.isDemo ? AppSettings.shared.kisDemoName : AppSettings.shared.kisRealName,
                          systemImage: "building.columns")
                        .font(.subheadline.bold()).foregroundStyle(.primary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formatKRW(portfolio.summary.totalEvalAmount)).font(.subheadline.bold())
                        Text(pnlText).font(.caption)
                            .foregroundStyle(portfolio.totalProfitLossRate >= 0 ? .green : .red)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if expanded && !portfolio.holdings.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    let shown = portfolio.holdings.prefix(10)
                    ForEach(shown) { holding in
                        HoldingRow(holding: holding, fetchChart: { iv in
                            await fetchChart(holding.stockCode, iv)
                        })
                        if holding.id != shown.last?.id { Divider().padding(.leading, 10) }
                    }
                    if portfolio.holdings.count > 10 {
                        Text("외 \(portfolio.holdings.count - 10)개 종목")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
    }

    private var pnlText: String {
        let rate = portfolio.totalProfitLossRate
        let pl   = portfolio.totalProfitLoss
        return "\(formatKRW(pl)) (\(rate >= 0 ? "+" : "")\(String(format: "%.2f", rate))%)"
    }

    private func formatKRW(_ value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return "₩" + (fmt.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value))
    }
}

struct HoldingRow: View {
    let holding: KISHolding
    let fetchChart: (ChartInterval) async -> [ChartCandle]

    @State private var expanded = false
    @State private var selectedInterval: ChartInterval = .day1
    @State private var candles: [ChartCandle] = []
    @State private var isLoading = false
    @State private var chartRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                if expanded && candles.isEmpty { Task { await load() } }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(holding.stockName).font(.caption.bold())
                        Text("\(holding.quantity)주").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formatKRW(holding.evalAmount)).font(.caption.bold())
                        Text(pnlText).font(.caption2)
                            .foregroundStyle(holding.profitLossRate >= 0 ? .green : .red)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8)).foregroundStyle(.tertiary).padding(.leading, 4)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if expanded { chartPanel }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                startChartRefresh()
            } else {
                chartRefreshTask?.cancel()
                chartRefreshTask = nil
            }
        }
    }

    private var chartPanel: some View {
        VStack(spacing: 6) {
            intervalPicker
            if isLoading {
                HStack { Spacer(); ProgressView().scaleEffect(0.6); Spacer() }.frame(height: 72)
            } else if candles.count < 2 {
                HStack { Spacer()
                    Text("데이터 없음").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                }.frame(height: 72)
            } else {
                CandlestickChartView(candles: candles,
                                     entryPrice: holding.avgPrice,
                                     interval: selectedInterval).frame(height: 80)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }

    private var intervalPicker: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(ChartInterval.allCases, id: \.self) { iv in
                    Button {
                        selectedInterval = iv; candles = []
                        chartRefreshTask?.cancel()
                        Task { await load() }
                        startChartRefresh()
                    } label: {
                        if iv == selectedInterval {
                            Label(iv.rawValue, systemImage: "checkmark")
                        } else {
                            Text(iv.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(selectedInterval.rawValue).font(.system(size: 10))
                    Image(systemName: "chevron.down").font(.system(size: 7))
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.18))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
        }
    }

    private func load(showLoading: Bool = true) async {
        guard !isLoading else { return }
        if showLoading { isLoading = true }
        candles = await fetchChart(selectedInterval)
        isLoading = false
    }

    private func startChartRefresh() {
        chartRefreshTask?.cancel()
        chartRefreshTask = Task {
            let ns: UInt64
            switch selectedInterval {
            case .min1: ns = 30_000_000_000
            case .min3, .min5: ns = 60_000_000_000
            default: ns = 120_000_000_000
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { break }
                await load(showLoading: false)
            }
        }
    }

    private var pnlText: String {
        "\(holding.profitLossRate >= 0 ? "+" : "")\(String(format: "%.2f", holding.profitLossRate))%"
    }

    private func formatKRW(_ value: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return (fmt.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)) + "원"
    }
}

// MARK: - Binance Portfolio Card

struct BinancePortfolioCard: View {
    let portfolio: BinancePortfolio
    let markPrices: [String: Double]
    let fetchFuturesChart: (String, ChartInterval) async -> [ChartCandle]

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Label(portfolio.isDemo ? AppSettings.shared.binanceDemoName : AppSettings.shared.binanceRealName,
                          systemImage: "bitcoinsign.circle")
                        .font(.subheadline.bold()).foregroundStyle(.primary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(fmtUSD(portfolio.totalUSDT)).font(.subheadline.bold())
                        if let fut = portfolio.futuresAccount, fut.totalUnrealizedProfit != 0 {
                            Text("PNL \(fmtUSDTSigned(fut.totalUnrealizedProfit))")
                                .font(.caption2)
                                .foregroundStyle(fut.totalUnrealizedProfit >= 0 ? .green : .red)
                        }
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                if !portfolio.futuresPositions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(portfolio.futuresPositions) { pos in
                            FuturesPositionRow(
                                position: pos,
                                liveMarkPrice: markPrices[pos.symbol] ?? pos.markPrice,
                                fetchChart: { iv in await fetchFuturesChart(pos.symbol, iv) }
                            )
                            if pos.id != portfolio.futuresPositions.last?.id {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                } else {
                    let balances = portfolio.significantBalances.prefix(10)
                    VStack(spacing: 0) {
                        ForEach(Array(balances)) { balance in
                            BinanceBalanceRow(balance: balance, prices: portfolio.prices, tickers: portfolio.tickers)
                            if balance.id != balances.last?.id { Divider().padding(.leading, 10) }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
    }

    private func fmtUSD(_ v: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        return "$" + (fmt.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }

    private func fmtUSDTSigned(_ v: Double) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        let str = fmt.string(from: NSNumber(value: abs(v))) ?? String(format: "%.2f", abs(v))
        return (v >= 0 ? "+" : "-") + str
    }
}

struct FuturesPositionRow: View {
    let position: BinanceFuturesPosition
    let liveMarkPrice: Double
    let fetchChart: (ChartInterval) async -> [ChartCandle]

    @State private var expanded = false
    @State private var selectedInterval: ChartInterval = .min1
    @State private var candles: [ChartCandle] = []
    @State private var isLoading = false
    @State private var chartRefreshTask: Task<Void, Never>?

    private var livePnl: Double { (liveMarkPrice - position.entryPrice) * position.positionAmt }
    private var liveRoi: Double {
        guard position.entryPrice > 0 else { return 0 }
        return (liveMarkPrice - position.entryPrice) / position.entryPrice
            * Double(position.leverage) * 100 * (position.isLong ? 1 : -1)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                if expanded && candles.isEmpty { Task { await load() } }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(position.symbol.replacingOccurrences(of: "USDT", with: ""))
                                .font(.caption.bold())
                            Text(position.isLong ? "Long" : "Short")
                                .font(.caption2.bold())
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(position.isLong ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                                .foregroundStyle(position.isLong ? .green : .red)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text("\(position.leverage)x").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("진입 \(fmt(position.entryPrice))  현재 \(fmt(liveMarkPrice))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(fmtPnl(livePnl)) USDT").font(.caption.bold())
                            .foregroundStyle(livePnl >= 0 ? .green : .red)
                        Text(String(format: "%+.2f%%", liveRoi)).font(.caption2)
                            .foregroundStyle(livePnl >= 0 ? .green : .red)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8)).foregroundStyle(.tertiary).padding(.leading, 4)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if expanded { chartPanel }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                startChartRefresh()
            } else {
                chartRefreshTask?.cancel()
                chartRefreshTask = nil
            }
        }
    }

    private var chartPanel: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Menu {
                    ForEach(ChartInterval.allCases, id: \.self) { iv in
                        Button {
                            selectedInterval = iv; candles = []
                            chartRefreshTask?.cancel()
                            Task { await load() }
                            startChartRefresh()
                        } label: {
                            if iv == selectedInterval {
                                Label(iv.rawValue, systemImage: "checkmark")
                            } else {
                                Text(iv.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(selectedInterval.rawValue).font(.system(size: 10))
                        Image(systemName: "chevron.down").font(.system(size: 7))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.18))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            if isLoading {
                HStack { Spacer(); ProgressView().scaleEffect(0.6); Spacer() }.frame(height: 80)
            } else if candles.count < 2 {
                HStack { Spacer(); Text("데이터 없음").font(.caption2).foregroundStyle(.tertiary); Spacer() }
                    .frame(height: 80)
            } else {
                CandlestickChartView(candles: candles,
                                     entryPrice: position.entryPrice,
                                     interval: selectedInterval).frame(height: 80)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }

    private func load(showLoading: Bool = true) async {
        guard !isLoading else { return }
        if showLoading { isLoading = true }
        candles = await fetchChart(selectedInterval)
        isLoading = false
    }

    private func startChartRefresh() {
        chartRefreshTask?.cancel()
        chartRefreshTask = Task {
            let ns: UInt64
            switch selectedInterval {
            case .min1: ns = 30_000_000_000
            case .min3, .min5: ns = 60_000_000_000
            default: ns = 120_000_000_000
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { break }
                await load(showLoading: false)
            }
        }
    }

    private func fmt(_ price: Double) -> String {
        if price >= 1000 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
            return f.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
        }
        if price >= 1    { return String(format: "%.4f", price) }
        return String(format: "%.6f", price)
    }

    private func fmtPnl(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let str = f.string(from: NSNumber(value: abs(v))) ?? String(format: "%.2f", abs(v))
        return (v >= 0 ? "+" : "-") + str
    }
}

struct BinanceBalanceRow: View {
    let balance: BinanceBalance
    let prices: [String: Double]
    let tickers: [String: BinanceTicker]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(balance.asset)
                    .font(.caption.bold())
                Text(String(format: "%.6f", balance.totalDouble))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(usdValue)
                    .font(.caption.bold())
                if let ticker = tickers["\(balance.asset)USDT"] {
                    Text(String(format: "%+.2f%%", ticker.changePercentDouble))
                        .font(.caption2)
                        .foregroundStyle(ticker.changePercentDouble >= 0 ? .green : .red)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var usdValue: String {
        let v: Double
        if balance.asset == "USDT" || balance.asset == "BUSD" {
            v = balance.totalDouble
        } else {
            v = balance.totalDouble * (prices["\(balance.asset)USDT"] ?? 0)
        }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        return "$" + (fmt.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }
}

// MARK: - Index Section

struct IndexSection: View {
    let title: String
    let indices: [MarketIndex]
    let fetchChart: (MarketIndex, ChartInterval) async -> [ChartCandle]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                ForEach(indices) { index in
                    IndexRow(index: index, fetchChart: fetchChart)
                    if index.id != indices.last?.id {
                        Divider().padding(.leading, 10)
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct IndexRow: View {
    let index: MarketIndex
    let fetchChart: (MarketIndex, ChartInterval) async -> [ChartCandle]

    @State private var expanded = false
    @State private var selectedInterval: ChartInterval = .day1
    @State private var candles: [ChartCandle] = []
    @State private var isLoadingChart = false
    @State private var chartRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                if expanded && candles.isEmpty { Task { await loadChart() } }
            } label: {
                HStack {
                    Text(index.name).font(.caption.bold())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(priceText).font(.caption.bold())
                        Text(String(format: "%+.2f%%", index.changePercent))
                            .font(.caption2)
                            .foregroundStyle(index.changePercent >= 0 ? .green : .red)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8)).foregroundStyle(.tertiary).padding(.leading, 4)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Menu {
                            ForEach(ChartInterval.allCases, id: \.self) { iv in
                                Button {
                                    selectedInterval = iv; candles = []
                                    chartRefreshTask?.cancel()
                                    Task { await loadChart() }
                                    startChartRefresh()
                                } label: {
                                    if iv == selectedInterval {
                                        Label(iv.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(iv.rawValue)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(selectedInterval.rawValue).font(.system(size: 10))
                                Image(systemName: "chevron.down").font(.system(size: 7))
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.18))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        Spacer()
                    }
                    if isLoadingChart {
                        HStack { Spacer(); ProgressView().scaleEffect(0.6); Spacer() }.frame(height: 80)
                    } else if candles.count < 2 {
                        HStack { Spacer()
                            Text("데이터 없음").font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                        }.frame(height: 80)
                    } else {
                        CandlestickChartView(candles: candles,
                                             interval: selectedInterval).frame(height: 80)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded {
                startChartRefresh()
            } else {
                chartRefreshTask?.cancel()
                chartRefreshTask = nil
            }
        }
    }

    private func loadChart(showLoading: Bool = true) async {
        guard !isLoadingChart else { return }
        if showLoading { isLoadingChart = true }
        candles = await fetchChart(index, selectedInterval)
        isLoadingChart = false
    }

    private func startChartRefresh() {
        chartRefreshTask?.cancel()
        chartRefreshTask = Task {
            let ns: UInt64
            switch selectedInterval {
            case .min1: ns = 30_000_000_000
            case .min3, .min5: ns = 60_000_000_000
            default: ns = 120_000_000_000
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { break }
                await loadChart(showLoading: false)
            }
        }
    }

    private var priceText: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        switch index.currency {
        case "KRW":
            fmt.maximumFractionDigits = 2
            fmt.minimumFractionDigits = 2
            return fmt.string(from: NSNumber(value: index.price)) ?? String(format: "%.2f", index.price)
        case "USDT":
            fmt.maximumFractionDigits = 0
            return "$" + (fmt.string(from: NSNumber(value: index.price)) ?? String(format: "%.0f", index.price))
        default:
            fmt.maximumFractionDigits = 2
            fmt.minimumFractionDigits = 2
            return "$" + (fmt.string(from: NSNumber(value: index.price)) ?? String(format: "%.2f", index.price))
        }
    }
}

// MARK: - Candlestick Chart

struct CandlestickChartView: View {
    let candles: [ChartCandle]
    var entryPrice: Double? = nil
    var interval: ChartInterval = .day1

    private let rightPad: CGFloat = 48
    private let topPad:   CGFloat = 2

    private var display: [ChartCandle] {
        candles.count > 80 ? Array(candles.suffix(80)) : candles
    }

    var body: some View {
        let d = display
        let fmt = makeDateFmt(interval)
        let firstLabel = d.first?.timestamp.map { fmt.string(from: $0) } ?? ""
        let lastLabel  = d.last?.timestamp.map  { fmt.string(from: $0) } ?? ""
        let ivLabel    = intervalLabel(interval)

        VStack(spacing: 0) {
            // ── Main chart ────────────────────────────
            Canvas { ctx, size in
                guard d.count > 1 else { return }

                var minL = d.map(\.low).min()!
                var maxH = d.map(\.high).max()!
                if let ep = entryPrice, ep > 0 { minL = min(minL, ep); maxH = max(maxH, ep) }
                let vpad = (maxH - minL) * 0.05
                minL -= vpad; maxH += vpad
                let range = maxH == minL ? 1.0 : maxH - minL

                let chartW = size.width - rightPad
                let chartH = size.height - topPad

                func y(_ p: Double) -> CGFloat {
                    topPad + chartH * CGFloat(1 - (p - minL) / range)
                }

                // Entry price dashed line
                if let ep = entryPrice, ep > 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y(ep)))
                    line.addLine(to: CGPoint(x: chartW, y: y(ep)))
                    ctx.stroke(line, with: .color(.orange),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Candles
                let slotW = chartW / CGFloat(d.count)
                let bodyW = max(1.5, slotW * 0.6)
                for (i, c) in d.enumerated() {
                    let cx   = (CGFloat(i) + 0.5) * slotW
                    let isUp = c.close >= c.open
                    let col: GraphicsContext.Shading = isUp ? .color(.green) : .color(.red)

                    var wick = Path()
                    wick.move(to: CGPoint(x: cx, y: y(c.high)))
                    wick.addLine(to: CGPoint(x: cx, y: y(c.low)))
                    ctx.stroke(wick, with: col, lineWidth: 1)

                    let topY = y(max(c.open, c.close))
                    let botY = y(min(c.open, c.close))
                    ctx.fill(Path(CGRect(x: cx - bodyW/2, y: topY,
                                        width: bodyW, height: max(1.5, botY - topY))), with: col)
                }

                // Y-axis labels
                let lf = Font.system(size: 8)
                let sc = Color.secondary
                ctx.draw(Text(fmtP(maxH)).font(lf).foregroundStyle(sc),
                         at: CGPoint(x: chartW + 3, y: topPad), anchor: .topLeading)
                ctx.draw(Text(fmtP(minL)).font(lf).foregroundStyle(sc),
                         at: CGPoint(x: chartW + 3, y: size.height), anchor: .bottomLeading)
                if let ep = entryPrice, ep > 0 {
                    ctx.draw(Text(fmtP(ep)).font(lf).foregroundStyle(.orange),
                             at: CGPoint(x: chartW + 3, y: y(ep)), anchor: .leading)
                }
            }

            // ── X-axis row (SwiftUI Text — guaranteed to render) ──
            HStack(spacing: 0) {
                Text(ivLabel)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(firstLabel)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lastLabel)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                // Spacer matching the Y-axis right margin
                Color.clear.frame(width: rightPad)
            }
            .frame(height: 13)
        }
    }

    private func fmtP(_ p: Double) -> String {
        if p >= 10_000 {
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 0
            return fmt.string(from: NSNumber(value: p)) ?? String(format: "%.0f", p)
        }
        if p >= 1_000  { return String(format: "%.1f", p) }
        if p >= 10     { return String(format: "%.2f", p) }
        if p >= 1      { return String(format: "%.3f", p) }
        if p >= 0.01   { return String(format: "%.4f", p) }
        return String(format: "%.6f", p)
    }

    private func makeDateFmt(_ iv: ChartInterval) -> DateFormatter {
        let f = DateFormatter()
        switch iv {
        case .min1, .min3, .min5, .min10, .min15, .min30, .hour1, .hour4:
            f.dateFormat = "HH:mm"
        case .day1, .week1:
            f.dateFormat = "M/d"
        }
        return f
    }

    private func intervalLabel(_ iv: ChartInterval) -> String { iv.rawValue }
}

// MARK: - Portfolio History Card

struct PortfolioHistoryCard: View {
    let history: PortfolioHistory

    @State private var expanded = true
    @State private var range: HistoryRange = .hour1

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Label("자산 추이", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.bold()).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                VStack(spacing: 8) {
                    // Range selector (가운데 정렬)
                    HStack(spacing: 0) {
                        Spacer()
                        ForEach(HistoryRange.allCases, id: \.self) { r in
                            Button(r.rawValue) { range = r }
                                .buttonStyle(.plain)
                                .font(.system(size: 10))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(range == r
                                            ? Color.accentColor.opacity(0.18)
                                            : Color.clear)
                                .foregroundStyle(range == r ? Color.accentColor : Color.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        Spacer()
                    }

                    let pts = history.snapshots(for: range)
                    if pts.count < 2 {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                                Text("데이터 수집 중...")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(height: 100)
                    } else {
                        PortfolioLineChart(snapshots: pts).frame(height: 100)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
    }
}

// MARK: - Portfolio Line Chart

struct PortfolioLineChart: View {
    let snapshots: [PortfolioSnapshot]

    private let leftPad:   CGFloat = 40  // Y축 레이블 공간 (왼쪽)
    private let rightPad:  CGFloat = 6
    private let topPad:    CGFloat = 6
    private let bottomPad: CGFloat = 16

    private var hasKRW: Bool { snapshots.contains { $0.totalKRW > 0 } }
    private var hasUSD: Bool { snapshots.contains { $0.totalUSD > 0 } }

    private func pctSeries(keyPath: KeyPath<PortfolioSnapshot, Double>) -> [Double] {
        let base = snapshots.first(where: { $0[keyPath: keyPath] > 0 })?[keyPath: keyPath] ?? 1
        // 0값(로딩 아티팩트)은 직전 값으로 대체하여 -100% 스파이크 방지
        var last = base
        return snapshots.map { s in
            let v = s[keyPath: keyPath]
            if v > 0 { last = v }
            return (last - base) / base * 100
        }
    }

    /// 눈금 값 계산 (lo~hi 범위에서 3~5개의 깔끔한 숫자)
    private func niceTicks(lo: Double, hi: Double) -> [Double] {
        let range = hi - lo
        guard range > 0 else { return [0] }
        let rawStep = range / 4.0
        let mag  = pow(10.0, floor(log10(rawStep)))
        let norm = rawStep / mag
        let step: Double
        if      norm < 1.5 { step = mag }
        else if norm < 3.5 { step = 2 * mag }
        else if norm < 7.5 { step = 5 * mag }
        else               { step = 10 * mag }
        let start = ceil(lo / step) * step
        var ticks: [Double] = []
        var t = start
        while t <= hi + step * 0.01 { ticks.append(t); t += step }
        return ticks
    }

    var body: some View {
        Canvas { ctx, size in
            guard snapshots.count >= 2 else { return }
            let drawEndX = size.width - rightPad
            let drawW    = drawEndX - leftPad
            let chartH   = size.height - topPad - bottomPad

            let krwPcts = hasKRW ? pctSeries(keyPath: \.totalKRW) : []
            let usdPcts = hasUSD ? pctSeries(keyPath: \.totalUSD) : []
            let allPcts = krwPcts + usdPcts
            guard let rawMin = allPcts.min(), let rawMax = allPcts.max() else { return }

            let pad = max(rawMax - rawMin, 0.01) * 0.15
            let lo  = min(rawMin, 0) - pad
            let hi  = max(rawMax, 0) + pad
            let adj = hi - lo

            func yf(_ pct: Double) -> CGFloat {
                topPad + chartH * CGFloat(1 - (pct - lo) / adj)
            }
            func xf(_ i: Int, total: Int) -> CGFloat {
                leftPad + CGFloat(i) / CGFloat(total - 1) * drawW
            }

            let lf = Font.system(size: 8)
            let sc = Color.secondary

            // ── 1. 차트 영역 배경 ──────────────────────────────────
            let chartRect = CGRect(x: leftPad, y: topPad, width: drawW, height: chartH)
            ctx.fill(Path(roundedRect: chartRect, cornerRadius: 3),
                     with: .color(Color.secondary.opacity(0.06)))

            // ── 2. 그리드 라인 + 왼쪽 Y축 레이블 ─────────────────
            let ticks   = niceTicks(lo: lo, hi: hi)
            let minGap: CGFloat = 10
            var lastLabelY: CGFloat = -minGap * 2

            for tick in ticks {
                let y = yf(tick)
                guard y >= topPad - 1, y <= topPad + chartH + 1 else { continue }
                let isZero = abs(tick) < 0.001

                var g = Path()
                g.move(to: CGPoint(x: leftPad, y: y))
                g.addLine(to: CGPoint(x: drawEndX, y: y))
                ctx.stroke(g,
                           with: .color(.secondary.opacity(isZero ? 0.30 : 0.12)),
                           style: StrokeStyle(lineWidth: isZero ? 0.8 : 0.5,
                                              dash: isZero ? [4, 3] : []))

                if abs(y - lastLabelY) >= minGap {
                    let label = isZero ? "0%" : fmtPct(tick)
                    ctx.draw(Text(label).font(lf).foregroundStyle(sc),
                             at: CGPoint(x: leftPad - 4, y: y), anchor: .trailing)
                    lastLabelY = y
                }
            }

            // ── 3. 시리즈 (면적 채우기 + 선) ─────────────────────
            let zeroY = yf(0)
            if !krwPcts.isEmpty {
                drawPctSeries(ctx: ctx, pcts: krwPcts, color: .blue,
                              yf: yf, xf: { xf($0, total: krwPcts.count) }, zeroY: zeroY)
            }
            if !usdPcts.isEmpty {
                drawPctSeries(ctx: ctx, pcts: usdPcts, color: .orange,
                              yf: yf, xf: { xf($0, total: usdPcts.count) }, zeroY: zeroY)
            }

            // ── 4. 범례 (KRW + USD 동시 표시 시) ─────────────────
            if hasKRW && hasUSD {
                ctx.draw(Text("₩").font(lf).foregroundStyle(Color.blue),
                         at: CGPoint(x: drawEndX - 2, y: topPad + 1), anchor: .topTrailing)
                ctx.draw(Text("$").font(lf).foregroundStyle(Color.orange),
                         at: CGPoint(x: drawEndX - 12, y: topPad + 1), anchor: .topTrailing)
            }

            // ── 5. X축 시간 레이블 ────────────────────────────────
            drawXLabels(ctx: ctx, size: size, drawEndX: drawEndX, drawW: drawW)
        }
    }

    // MARK: - Drawing

    private func drawPctSeries(ctx: GraphicsContext, pcts: [Double], color: Color,
                                yf: (Double) -> CGFloat, xf: (Int) -> CGFloat,
                                zeroY: CGFloat) {
        guard pcts.count >= 2 else { return }

        var area = Path()
        area.move(to: CGPoint(x: xf(0), y: zeroY))
        for (i, p) in pcts.enumerated() { area.addLine(to: CGPoint(x: xf(i), y: yf(p))) }
        area.addLine(to: CGPoint(x: xf(pcts.count - 1), y: zeroY))
        area.closeSubpath()
        ctx.fill(area, with: .color(color.opacity(0.13)))

        var line = Path()
        line.move(to: CGPoint(x: xf(0), y: yf(pcts[0])))
        for i in 1..<pcts.count { line.addLine(to: CGPoint(x: xf(i), y: yf(pcts[i]))) }
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5))
    }

    private func drawXLabels(ctx: GraphicsContext, size: CGSize, drawEndX: CGFloat, drawW: CGFloat) {
        guard !snapshots.isEmpty else { return }
        let lf   = Font.system(size: 8)
        let sc   = Color.secondary
        let n    = snapshots.count
        let yPos = size.height - 2

        ctx.draw(Text(timeFmt.string(from: snapshots.first!.timestamp)).font(lf).foregroundStyle(sc),
                 at: CGPoint(x: leftPad, y: yPos), anchor: .bottomLeading)
        ctx.draw(Text(timeFmt.string(from: snapshots.last!.timestamp)).font(lf).foregroundStyle(sc),
                 at: CGPoint(x: drawEndX, y: yPos), anchor: .bottomTrailing)

        if n > 4 {
            let midX = leftPad + CGFloat(n / 2) / CGFloat(n - 1) * drawW
            ctx.draw(Text(timeFmt.string(from: snapshots[n / 2].timestamp)).font(lf).foregroundStyle(sc),
                     at: CGPoint(x: midX, y: yPos), anchor: .bottom)
        }
    }

    // MARK: - Formatters

    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private func fmtPct(_ v: Double) -> String {
        String(format: "%+.2f%%", v)
    }
}

// MARK: - Helpers

struct ErrorBanner: View {
    let label: String
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.bold())
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PlaceholderCard: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Text("\(icon) \(title)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            ProgressView()
                .scaleEffect(0.6)
        }
        .padding(10)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

// MARK: - Watchlist Card

struct WatchlistCard: View {
    @Bindable var manager: WatchlistManager
    @State private var expanded = true
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Label("관심종목", systemImage: "star.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider()
                VStack(spacing: 0) {
                    if manager.items.isEmpty {
                        HStack {
                            Spacer()
                            Text("종목을 추가해보세요")
                                .font(.caption2).foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(manager.items) { item in
                            WatchlistRow(item: item,
                                         price: manager.currentPrices[item.symbol],
                                         usdKrwRate: manager.usdKrwRate,
                                         onRemove: { manager.remove(id: item.id) },
                                         onUpdate: { manager.update($0) })
                            if item.id != manager.items.last?.id {
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                    // 추가 버튼
                    Divider()
                    Button {
                        showingAddSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                            Text("종목 추가").foregroundStyle(Color.accentColor)
                            Spacer()
                        }
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
        .sheet(isPresented: $showingAddSheet) {
            AddWatchlistItemSheet(manager: manager)
        }
    }
}

struct WatchlistRow: View {
    var item: WatchlistItem
    var price: Double?
    var usdKrwRate: Double = 0
    var onRemove: () -> Void
    var onUpdate: (WatchlistItem) -> Void

    @State private var editingTarget = false
    @State private var targetInput = ""

    private var changeStr: String {
        guard let p = price, p > 0,
              let t = item.targetPrice, t > 0 else { return "" }
        let pct = (p - t) / t * 100
        return String(format: "%+.2f%%", pct)
    }

    private var priceStr: String {
        guard let p = price else { return "조회 중..." }
        switch item.market {
        case .crypto: return String(format: "$%g", p)
        case .us:     return String(format: "$%.2f", p)
        case .korea:
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 0
            return "₩" + (fmt.string(from: NSNumber(value: p)) ?? "\(Int(p))")
        }
    }

    private var targetStr: String {
        guard let t = item.targetPrice, let d = item.direction else { return "목표 미설정" }
        switch item.market {
        case .crypto: return "목표 $\(String(format: "%g", t)) \(d.rawValue)"
        case .us:     return "목표 $\(String(format: "%.2f", t)) \(d.rawValue)"
        case .korea:
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 0
            let ts = fmt.string(from: NSNumber(value: t)) ?? "\(Int(t))"
            return "목표 ₩\(ts) \(d.rawValue)"
        }
    }

    private var krwConvertedStr: String? {
        guard item.market == .us, let p = price, usdKrwRate > 0 else { return nil }
        let krw = p * usdKrwRate
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return "₩" + (fmt.string(from: NSNumber(value: krw)) ?? "\(Int(krw))")
    }

    private var isTriggered: Bool {
        guard let p = price, let t = item.targetPrice, let d = item.direction else { return false }
        return d == .above ? p >= t : p <= t
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.name).font(.caption.bold())
                    Text(item.symbol).font(.caption2).foregroundStyle(.tertiary)
                    if isTriggered {
                        Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Text(targetStr).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(priceStr).font(.caption.bold())
                if let krwStr = krwConvertedStr {
                    Text(krwStr).font(.caption2).foregroundStyle(.secondary)
                }
                if !changeStr.isEmpty {
                    let isPos = changeStr.hasPrefix("+")
                    Text(changeStr).font(.caption2)
                        .foregroundStyle(isPos ? .green : .red)
                }
            }
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }
}

// MARK: - Add Watchlist Sheet

struct AddWatchlistItemSheet: View {
    @Bindable var manager: WatchlistManager
    var prefill: TossStock? = nil
    @Environment(\.dismiss) var dismiss

    @State private var symbol = ""
    @State private var name = ""
    @State private var selectedMarket: TossStock.Market = .korea
    @State private var targetPriceStr = ""
    @State private var direction: WatchlistItem.Direction = .above
    @State private var isSearching = false
    @State private var searchResults: [TossStock] = []
    @State private var currentPrice: Double? = nil
    @State private var isFetchingPrice = false

    private let toss = TossInvestService()

    private var searchPlaceholder: String {
        switch selectedMarket {
        case .korea:  return "종목명 또는 코드 (예: 삼성전자, 005930)"
        case .us:     return "종목명 또는 코드 (예: Apple, AAPL, NVDA)"
        case .crypto: return "코인 심볼 (예: BTC, ETH, SOL, BTCUSDT)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("관심종목 추가").font(.headline)

            // 시장 선택
            VStack(alignment: .leading, spacing: 4) {
                Text("시장").font(.caption).foregroundStyle(.secondary)
                Picker("시장", selection: $selectedMarket) {
                    ForEach(TossStock.Market.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMarket) { _, _ in
                    searchResults = []
                    currentPrice = nil
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("종목 검색").font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(searchPlaceholder, text: $symbol)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await search() } }
                    Button {
                        Task { await search() }
                    } label: {
                        if isSearching {
                            ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(symbol.isEmpty || isSearching)
                }

                if !searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { stock in
                            Button {
                                let (nativeSym, market) = WatchlistItem.fromTossStock(stock)
                                symbol = nativeSym
                                name = stock.name
                                selectedMarket = market
                                currentPrice = nil
                                searchResults = []
                                Task { await fetchCurrentPrice(sym: nativeSym, market: market) }
                            } label: {
                                HStack(spacing: 6) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(stock.name).font(.caption.bold())
                                        let displayCode = stock.symbol.hasPrefix("A") && stock.symbol.count == 7
                                            ? String(stock.symbol.dropFirst()) : stock.symbol
                                        Text(displayCode).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(stock.market.rawValue)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(marketColor(stock.market).opacity(0.15))
                                        .foregroundStyle(marketColor(stock.market))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if stock.id != searchResults.last?.id { Divider() }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
                }
            }

            if !name.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("종목명").font(.caption).foregroundStyle(.secondary)
                    TextField("종목명", text: $name).textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("목표가 (선택)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if isFetchingPrice {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        Text("조회 중...").font(.caption2).foregroundStyle(.secondary)
                    } else if let p = currentPrice {
                        Text("현재가 \(fmtPrice(p, market: selectedMarket))")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("목표 가격", text: $targetPriceStr)
                        .textFieldStyle(.roundedBorder)
                    Picker("방향", selection: $direction) {
                        ForEach(WatchlistItem.Direction.allCases, id: \.self) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                }
            }

            HStack {
                Button("취소") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("추가") {
                    let finalName = name.isEmpty ? symbol : name
                    let target = Double(targetPriceStr.replacingOccurrences(of: ",", with: ""))
                    let item = WatchlistItem(
                        symbol: symbol.trimmingCharacters(in: .whitespaces),
                        name: finalName,
                        market: selectedMarket,
                        targetPrice: target,
                        direction: target != nil ? direction : nil
                    )
                    manager.add(item)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if let stock = prefill {
                let (nativeSym, market) = WatchlistItem.fromTossStock(stock)
                symbol = nativeSym
                name = stock.name
                selectedMarket = market
                Task { await fetchCurrentPrice(sym: nativeSym, market: market) }
            }
        }
    }

    private func search() async {
        isSearching = true
        let q = symbol.trimmingCharacters(in: .whitespaces)
        let all = await toss.searchStock(query: q)
        // 선택된 시장에 맞는 결과 우선 표시, 없으면 전체 표시
        let byMarket = all.filter { $0.market == selectedMarket }
        let results = byMarket.isEmpty ? all : byMarket
        await MainActor.run {
            searchResults = results
            isSearching = false
        }
    }

    private func fetchCurrentPrice(sym: String, market: TossStock.Market) async {
        await MainActor.run { isFetchingPrice = true }
        let price: Double?
        switch market {
        case .korea:  price = await toss.fetchTossKoreanPrice(symbol: sym)
        case .us:     price = await toss.fetchTossPrice(code: sym)
        case .crypto: price = await toss.fetchBinancePrice(symbol: sym)
        }
        await MainActor.run { currentPrice = price; isFetchingPrice = false }
    }

    private func fmtPrice(_ p: Double, market: TossStock.Market) -> String {
        switch market {
        case .crypto: return String(format: "$%g", p)
        case .us:     return String(format: "$%.2f", p)
        case .korea:
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 0
            return "₩" + (fmt.string(from: NSNumber(value: p)) ?? "\(Int(p))")
        }
    }

    private func marketColor(_ m: TossStock.Market) -> Color {
        switch m {
        case .korea:  return .blue
        case .us:     return .green
        case .crypto: return .orange
        }
    }
}

// MARK: - Toss Popular Section

struct TossPopularSection: View {
    @Bindable var watchlistManager: WatchlistManager
    @State private var stocks: [TossStock] = []
    @State private var isLoading = true
    @State private var selectedMarket: TossStock.Market = .korea
    @State private var refreshTask: Task<Void, Never>?
    private let toss = TossInvestService()

    private var availableMarkets: [TossStock.Market] {
        TossStock.Market.allCases.filter { m in stocks.contains(where: { $0.market == m }) }
    }
    private var filtered: [TossStock] {
        Array(stocks.filter { $0.market == selectedMarket }.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                HStack {
                    Text("🔥 Toss 인기종목").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    ProgressView().scaleEffect(0.5)
                }
                .padding(.horizontal, 4).padding(.bottom, 4)
            } else if stocks.isEmpty {
                EmptyView()
            } else {
                // 헤더 + 마켓 세그먼트
                HStack(spacing: 6) {
                    Text("🔥 Toss 인기종목")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    if availableMarkets.count > 1 {
                        Picker("", selection: $selectedMarket) {
                            ForEach(availableMarkets, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: CGFloat(availableMarkets.count) * 48)
                        .scaleEffect(0.85, anchor: .trailing)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

                TossStockList(stocks: filtered, watchlistManager: watchlistManager)
            }
        }
        .onAppear { startRefresh() }
        .onDisappear { refreshTask?.cancel(); refreshTask = nil }
    }

    private func startRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await loadPopular()
                let interval = TimeInterval(AppSettings.shared.tickerInterval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func loadPopular() async {
        let result = await toss.fetchPopularStocks()
        await MainActor.run {
            stocks = result
            isLoading = false
            // 현재 선택된 마켓에 데이터 없으면 첫 번째로
            if !stocks.contains(where: { $0.market == selectedMarket }),
               let first = availableMarkets.first {
                selectedMarket = first
            }
        }
    }
}

private struct TossStockList: View {
    let stocks: [TossStock]
    @Bindable var watchlistManager: WatchlistManager
    @State private var stockToAdd: TossStock? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stocks.enumerated()), id: \.offset) { idx, stock in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stock.name).font(.caption.bold())
                        let (sym2, _) = WatchlistItem.fromTossStock(stock)
                        Text(sym2).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(fmtStockPrice(stock)).font(.caption.bold())
                        Text(String(format: "%+.2f%%", stock.changePercent))
                            .font(.caption2)
                            .foregroundStyle(stock.changePercent >= 0 ? .green : .red)
                    }
                    Button {
                        let (nativeSym, _) = WatchlistItem.fromTossStock(stock)
                        if watchlistManager.items.contains(where: { $0.symbol == nativeSym }) {
                            watchlistManager.remove(id: watchlistManager.items.first(where: { $0.symbol == nativeSym })!.id)
                        } else {
                            stockToAdd = stock  // 시트로 목표가 설정
                        }
                    } label: {
                        let (nativeSym2, _) = WatchlistItem.fromTossStock(stock)
                        Image(systemName: watchlistManager.items.contains(where: { $0.symbol == nativeSym2 })
                              ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                if idx < stocks.count - 1 {
                    Divider().padding(.leading, 8)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
        .sheet(item: $stockToAdd) { stock in
            AddWatchlistItemSheet(manager: watchlistManager, prefill: stock)
        }
    }

    private func fmtStockPrice(_ stock: TossStock) -> String {
        switch stock.market {
        case .us, .crypto:
            return String(format: "$%.2f", stock.price)
        case .korea:
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 0
            return "₩" + (fmt.string(from: NSNumber(value: stock.price)) ?? "\(Int(stock.price))")
        }
    }
}
