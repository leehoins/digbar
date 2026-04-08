import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let ud = UserDefaults.standard

    // MARK: - Binance Real
    var binanceRealEnabled: Bool {
        get { ud.bool(forKey: "binanceRealEnabled") }
        set { ud.set(newValue, forKey: "binanceRealEnabled") }
    }
    var binanceRealAPIKey: String {
        get { KeychainHelper.load(key: "binanceRealAPIKey") ?? "" }
        set { KeychainHelper.save(key: "binanceRealAPIKey", value: newValue.trimmed) }
    }
    var binanceRealAPISecret: String {
        get { KeychainHelper.load(key: "binanceRealAPISecret") ?? "" }
        set { KeychainHelper.save(key: "binanceRealAPISecret", value: newValue.trimmed) }
    }
    var binanceRealName: String { didSet { ud.set(binanceRealName, forKey: "binanceRealName") } }

    // MARK: - Binance Demo (Testnet)
    var binanceDemoEnabled: Bool {
        get { ud.bool(forKey: "binanceDemoEnabled") }
        set { ud.set(newValue, forKey: "binanceDemoEnabled") }
    }
    var binanceDemoAPIKey: String {
        get { KeychainHelper.load(key: "binanceDemoAPIKey") ?? "" }
        set { KeychainHelper.save(key: "binanceDemoAPIKey", value: newValue.trimmed) }
    }
    var binanceDemoAPISecret: String {
        get { KeychainHelper.load(key: "binanceDemoAPISecret") ?? "" }
        set { KeychainHelper.save(key: "binanceDemoAPISecret", value: newValue.trimmed) }
    }
    var binanceDemoName: String { didSet { ud.set(binanceDemoName, forKey: "binanceDemoName") } }

    // MARK: - KIS Real (실전투자)
    var kisRealEnabled: Bool {
        get { ud.bool(forKey: "kisRealEnabled") }
        set { ud.set(newValue, forKey: "kisRealEnabled") }
    }
    var kisRealAppKey: String {
        get { KeychainHelper.load(key: "kisRealAppKey") ?? "" }
        set { KeychainHelper.save(key: "kisRealAppKey", value: newValue.trimmed) }
    }
    var kisRealAppSecret: String {
        get { KeychainHelper.load(key: "kisRealAppSecret") ?? "" }
        set { KeychainHelper.save(key: "kisRealAppSecret", value: newValue.trimmed) }
    }
    /// Format: "12345678-01"
    var kisRealAccount: String {
        get { ud.string(forKey: "kisRealAccount") ?? "" }
        set { ud.set(newValue, forKey: "kisRealAccount") }
    }
    var kisRealName: String { didSet { ud.set(kisRealName, forKey: "kisRealName") } }

    // MARK: - KIS Demo (모의투자)
    var kisDemoEnabled: Bool {
        get { ud.bool(forKey: "kisDemoEnabled") }
        set { ud.set(newValue, forKey: "kisDemoEnabled") }
    }
    var kisDemoAppKey: String {
        get { KeychainHelper.load(key: "kisDemoAppKey") ?? "" }
        set { KeychainHelper.save(key: "kisDemoAppKey", value: newValue.trimmed) }
    }
    var kisDemoAppSecret: String {
        get { KeychainHelper.load(key: "kisDemoAppSecret") ?? "" }
        set { KeychainHelper.save(key: "kisDemoAppSecret", value: newValue.trimmed) }
    }
    var kisDemoAccount: String {
        get { ud.string(forKey: "kisDemoAccount") ?? "" }
        set { ud.set(newValue, forKey: "kisDemoAccount") }
    }
    var kisDemoName: String { didSet { ud.set(kisDemoName, forKey: "kisDemoName") } }

    // MARK: - Display
    var refreshInterval: Int {
        get { ud.integer(forKey: "refreshInterval") > 0 ? ud.integer(forKey: "refreshInterval") : 30 }
        set { ud.set(newValue, forKey: "refreshInterval") }
    }
    /// 가격 티커 갱신 주기 (관심종목·인기종목 — KIS 미포함)
    var tickerInterval: Int {
        get { ud.integer(forKey: "tickerInterval") > 0 ? ud.integer(forKey: "tickerInterval") : 5 }
        set { ud.set(newValue, forKey: "tickerInterval") }
    }
    var showMarketIndices: Bool {
        get { ud.object(forKey: "showMarketIndices") == nil ? true : ud.bool(forKey: "showMarketIndices") }
        set { ud.set(newValue, forKey: "showMarketIndices") }
    }
    var statusBarMode: StatusBarMode {
        get {
            let raw = ud.string(forKey: "statusBarMode") ?? ""
            return StatusBarMode(rawValue: raw) ?? .totalValue
        }
        set { ud.set(newValue.rawValue, forKey: "statusBarMode") }
    }
    var statusBarAsset: StatusBarAsset {
        get {
            let raw = ud.string(forKey: "statusBarAsset") ?? ""
            return StatusBarAsset(rawValue: raw) ?? .usd
        }
        set { ud.set(newValue.rawValue, forKey: "statusBarAsset") }
    }
    var iconEmoji: String {
        get {
            let v = ud.string(forKey: "iconEmoji") ?? ""
            return v.isEmpty ? "🐻" : v
        }
        set { ud.set(newValue, forKey: "iconEmoji") }
    }

    // MARK: - 알림 쿨다운
    /// 0 = 항상 알림, 그 외 분(minute) 단위
    var alertCooldownMinutes: Int {
        get {
            let v = ud.integer(forKey: "alertCooldownMinutes")
            return ud.object(forKey: "alertCooldownMinutes") == nil ? 60 : v
        }
        set { ud.set(newValue, forKey: "alertCooldownMinutes") }
    }

    enum AppearanceMode: String, CaseIterable {
        case system = "시스템 따라가기"
        case light  = "라이트"
        case dark   = "다크"
    }

    var appearanceMode: AppearanceMode {
        get {
            let raw = ud.string(forKey: "appearanceMode") ?? ""
            return AppearanceMode(rawValue: raw) ?? .system
        }
        set { ud.set(newValue.rawValue, forKey: "appearanceMode") }
    }

    enum StatusBarMode: String, CaseIterable {
        case totalValue = "총 자산"
        case changePercent = "등락률"
        case both = "자산 + 등락률"
    }

    enum StatusBarAsset: String, CaseIterable {
        case krw = "KRW (₩)"
        case usd = "USD ($)"
        case both = "둘 다"
    }

    private init() {
        let ud = UserDefaults.standard
        let brn = ud.string(forKey: "binanceRealName") ?? ""
        binanceRealName = brn.isEmpty ? "Binance 실전" : brn
        let bdn = ud.string(forKey: "binanceDemoName") ?? ""
        binanceDemoName = bdn.isEmpty ? "Binance 모의투자" : bdn
        let krn = ud.string(forKey: "kisRealName") ?? ""
        kisRealName = krn.isEmpty ? "KIS 실전투자" : krn
        let kdn = ud.string(forKey: "kisDemoName") ?? ""
        kisDemoName = kdn.isEmpty ? "KIS 모의투자" : kdn
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
