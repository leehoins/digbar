import Foundation

struct WatchlistItem: Identifiable {
    var id: UUID = UUID()
    var symbol: String          // 네이티브 형식: "005930" (한국), "AAPL" (미국), "BTCUSDT" (코인)
    var name: String
    var market: TossStock.Market = .korea
    var targetPrice: Double?
    var direction: Direction?
    var lastAlertDate: Date?
    var avgPrice: Double?       // 평단가
    var quantity: Double?       // 보유 수량

    enum Direction: String, Codable, CaseIterable {
        case above = "이상"
        case below = "이하"
    }
}

// MARK: - Codable (backward compatible: market optional)

extension WatchlistItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, symbol, name, market, targetPrice, direction, lastAlertDate, avgPrice, quantity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        symbol        = try c.decode(String.self, forKey: .symbol)
        name          = try c.decode(String.self, forKey: .name)
        market        = (try? c.decode(TossStock.Market.self, forKey: .market)) ?? .korea
        targetPrice   = try? c.decode(Double.self, forKey: .targetPrice)
        direction     = try? c.decode(Direction.self, forKey: .direction)
        lastAlertDate = try? c.decode(Date.self, forKey: .lastAlertDate)
        avgPrice      = try? c.decode(Double.self, forKey: .avgPrice)
        quantity      = try? c.decode(Double.self, forKey: .quantity)
    }
}

// MARK: - Logo

extension WatchlistItem {
    /// Toss 종목 로고 URL (한국: 6자리 코드, 미국: US내부코드)
    var logoURL: URL? {
        switch market {
        case .korea, .us:
            // Toss 종목 로고 (한국: "034730", 미국: "US19801212001")
            return URL(string: "https://static.toss.im/png-icons/securities/icn-sec-fill-\(symbol).png")
        case .crypto:
            // CoinCap 공개 CDN: "BTCUSDT" → "btc"
            let base = symbol
                .uppercased()
                .replacingOccurrences(of: "USDT", with: "")
                .replacingOccurrences(of: "BTC", with: "BTC") // BTC/BTC쌍 처리
                .lowercased()
            return URL(string: "https://assets.coincap.io/assets/icons/\(base)@2x.png")
        }
    }
}

// MARK: - Symbol conversion helpers

extension WatchlistItem {
    /// Yahoo Finance 형식 TossStock → 네이티브 심볼 + 마켓
    static func fromTossStock(_ stock: TossStock) -> (symbol: String, market: TossStock.Market) {
        let sym = stock.symbol
        switch stock.market {
        case .korea:
            // "A034730" → "034730"  |  "005930.KS" → "005930"
            var clean = sym
                .replacingOccurrences(of: ".KS", with: "")
                .replacingOccurrences(of: ".KQ", with: "")
            if clean.hasPrefix("A"), clean.count == 7, Int(clean.dropFirst()) != nil {
                clean = String(clean.dropFirst())
            }
            return (clean, .korea)
        case .us:
            // "US19801212001" 그대로 보관 (Toss 가격 API에 직접 사용)
            return (sym, .us)
        case .crypto:
            if sym.hasSuffix("-USD") { return (String(sym.dropLast(4)) + "USDT", .crypto) }
            if sym.hasSuffix("-KRW") { return (String(sym.dropLast(4)) + "USDT", .crypto) }
            return (sym, .crypto)
        }
    }
}
