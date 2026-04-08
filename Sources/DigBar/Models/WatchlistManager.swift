import AppKit
import Foundation
import UserNotifications
import Observation

@Observable
final class WatchlistManager {
    var items: [WatchlistItem] = []
    var currentPrices: [String: Double] = [:]
    var usdKrwRate: Double = 0
    var isLoading = false

    private let toss = TossInvestService()
    private let udKey = "watchlistItems"
    private var tickerTask: Task<Void, Never>?

    init() { load() }

    // MARK: - Ticker Loop (tickerInterval 주기로 가격만 갱신)

    func startTicker(kisService: KISService) {
        stopTicker()
        tickerTask = Task {
            while !Task.isCancelled {
                await refreshPrices(kisService: kisService)
                let interval = TimeInterval(AppSettings.shared.tickerInterval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopTicker() {
        tickerTask?.cancel()
        tickerTask = nil
    }

    // MARK: - CRUD

    func add(_ item: WatchlistItem) {
        items.append(item)
        save()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func update(_ item: WatchlistItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i] = item
            save()
        }
    }

    // MARK: - Price Refresh (마켓별 라우팅)

    func refreshPrices(kisService: KISService) async {
        guard !items.isEmpty else { return }

        var prices: [String: Double] = [:]

        let hasUSStocks = items.contains { $0.market == .us }

        // 1) 한국주식: Toss wts-info-api 배치 조회 (UTK 불필요)
        // USD/KRW 환율: 미국주식이 있을 때만 조회 (병렬)
        async let koreanBatch: [String: Double] = {
            let koreanSymbols = items.filter { $0.market == .korea }.map(\.symbol)
            return koreanSymbols.isEmpty ? [:] : await toss.fetchTossKoreanPrices(symbols: koreanSymbols)
        }()
        async let rateResult: Double? = hasUSStocks ? toss.fetchUSDKRWRate() : nil

        let (batchPrices, fetchedRate) = await (koreanBatch, rateResult)
        prices.merge(batchPrices) { _, new in new }
        let newRate = fetchedRate ?? 0

        // 2) 암호화폐: Binance 공개 API
        // 3) 미국주식: Toss UTK API
        // 한국 배치에서 못 받은 것 + 코인/미국 개별 조회
        for item in items {
            if prices[item.symbol] != nil { continue }   // 이미 조회됨
            let price: Double?
            switch item.market {
            case .crypto:
                price = await toss.fetchBinancePrice(symbol: item.symbol)
            case .us:
                price = await toss.fetchTossPrice(code: item.symbol)
            case .korea:
                // 배치 실패한 종목 → KIS 개별 조회 fallback
                let s = AppSettings.shared
                let key    = s.kisRealEnabled && !s.kisRealAppKey.isEmpty ? s.kisRealAppKey    : s.kisDemoAppKey
                let secret = s.kisRealEnabled && !s.kisRealAppKey.isEmpty ? s.kisRealAppSecret : s.kisDemoAppSecret
                price = key.isEmpty ? nil : await kisService.fetchCurrentPrice(symbol: item.symbol, appKey: key, appSecret: secret)
            }
            if let p = price { prices[item.symbol] = p }
        }

        await MainActor.run {
            self.currentPrices = prices
            if newRate > 0 { self.usdKrwRate = newRate }
        }
    }

    // MARK: - Alert Check

    func checkAlerts() {
        let now = Date()
        let cooldownMins = AppSettings.shared.alertCooldownMinutes
        let cooldown: TimeInterval = cooldownMins == 0 ? 0 : TimeInterval(cooldownMins * 60)

        for i in items.indices {
            let item = items[i]
            guard let target = item.targetPrice,
                  let direction = item.direction,
                  let price = currentPrices[item.symbol] else { continue }

            // 쿨다운 체크 (0이면 항상 알림)
            if cooldown > 0, let last = item.lastAlertDate,
               now.timeIntervalSince(last) < cooldown { continue }

            let triggered: Bool
            switch direction {
            case .above: triggered = price >= target
            case .below: triggered = price <= target
            }
            guard triggered else { continue }

            sendNotification(item: item, price: price, target: target, direction: direction)
            items[i].lastAlertDate = now
        }
        save()
    }

    // MARK: - Notification

    private func sendNotification(item: WatchlistItem, price: Double, target: Double,
                                   direction: WatchlistItem.Direction) {
        let title = "\(item.name) 목표 달성 🎯"
        let body  = "현재가 \(formatPrice(price, market: item.market)) — 목표 \(formatPrice(target, market: item.market)) \(direction.rawValue)"
        let notifID = "\(item.id.uuidString)-\(Int(Date().timeIntervalSince1970))"
        let logoURL = item.logoURL

        Task {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default

            // 종목 로고 이미지 첨부 (흰색 배경 합성 → 투명 PNG도 알림에서 표시)
            if let url = logoURL,
               let (data, resp) = try? await URLSession.shared.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty,
               let src = NSImage(data: data) {

                let size = CGSize(width: 60, height: 60)
                let composed = NSImage(size: size)
                composed.lockFocus()
                NSColor.white.setFill()
                NSRect(origin: .zero, size: size).fill()
                let iconRect = NSRect(x: 6, y: 6, width: 48, height: 48)
                src.draw(in: iconRect, from: .zero,
                         operation: .sourceOver, fraction: 1.0)
                composed.unlockFocus()

                if let tiff = composed.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?
                       .representation(using: .png, properties: [:]) {
                    let cacheDir = FileManager.default.urls(
                        for: .cachesDirectory, in: .userDomainMask).first
                        ?? FileManager.default.temporaryDirectory
                    let imgFile = cacheDir.appendingPathComponent("digbar-\(notifID).png")
                    if (try? png.write(to: imgFile)) != nil,
                       let attachment = try? UNNotificationAttachment(
                           identifier: "logo", url: imgFile, options: nil) {
                        content.attachments = [attachment]
                    }
                }
            }

            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: notifID, content: content, trigger: nil)
            )
        }
    }

    private func formatPrice(_ v: Double, market: TossStock.Market) -> String {
        switch market {
        case .crypto, .us:
            return String(format: "$%.2f", v)
        case .korea:
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.maximumFractionDigits = 0
            return "₩" + (fmt.string(from: NSNumber(value: v)) ?? "\(Int(v))")
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: udKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let decoded = try? JSONDecoder().decode([WatchlistItem].self, from: data)
        else { return }
        items = decoded
    }
}
