import Foundation

actor KISService {
    private let realBaseURL = "https://openapi.koreainvestment.com:9443"
    private let demoBaseURL = "https://openapivts.koreainvestment.com:29443"

    // Token cache: keyed by "appKey|base" to separate real vs demo tokens
    private var tokenCache: [String: CachedToken] = [:]
    // Rate limit cooldown: don't retry token until this date
    private var tokenCooldown: [String: Date] = [:]

    private struct CachedToken {
        let token: String
        let expiry: Date
        var isValid: Bool { Date() < expiry }
    }

    // MARK: - Fetch Portfolio

    func fetchPortfolio(
        appKey: String,
        appSecret: String,
        accountNumber: String,
        isDemo: Bool
    ) async throws -> KISPortfolio {
        do {
            return try await fetchPortfolioOnce(appKey: appKey, appSecret: appSecret,
                                                accountNumber: accountNumber, isDemo: isDemo)
        } catch KISError.rateLimitPerSecond {
            // EGW00201: 초당 거래건수 초과 → 1.5초 후 자동 재시도
            try await Task.sleep(nanoseconds: 1_500_000_000)
            return try await fetchPortfolioOnce(appKey: appKey, appSecret: appSecret,
                                                accountNumber: accountNumber, isDemo: isDemo)
        }
    }

    private func fetchPortfolioOnce(
        appKey: String,
        appSecret: String,
        accountNumber: String,
        isDemo: Bool
    ) async throws -> KISPortfolio {
        let base = isDemo ? demoBaseURL : realBaseURL
        let token = try await getToken(base: base, appKey: appKey, appSecret: appSecret)

        // Parse account number: "12345678-01" → CANO="12345678", ACNT_PRDT_CD="01"
        let parts = accountNumber.split(separator: "-")
        let cano = parts.first.map(String.init) ?? accountNumber
        let acntPrdtCd = parts.last.map(String.init) ?? "01"
        let trId = isDemo ? "VTTC8434R" : "TTTC8434R"

        var components = URLComponents(string: "\(base)/uapi/domestic-stock/v1/trading/inquire-balance")!
        components.queryItems = [
            URLQueryItem(name: "CANO", value: cano),
            URLQueryItem(name: "ACNT_PRDT_CD", value: acntPrdtCd),
            URLQueryItem(name: "AFHR_FLPR_YN", value: "N"),
            URLQueryItem(name: "OFL_YN", value: ""),
            URLQueryItem(name: "INQR_DVSN", value: "01"),
            URLQueryItem(name: "UNPR_DVSN", value: "01"),
            URLQueryItem(name: "FUND_STTL_ICLD_YN", value: "N"),
            URLQueryItem(name: "FNCG_AMT_AUTO_RDPT_YN", value: "N"),
            URLQueryItem(name: "PRCS_DVSN", value: "00"),
            URLQueryItem(name: "CTX_AREA_FK100", value: ""),
            URLQueryItem(name: "CTX_AREA_NK100", value: "")
        ]

        guard let url = components.url else { throw KISError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(appKey, forHTTPHeaderField: "appkey")
        request.setValue(appSecret, forHTTPHeaderField: "appsecret")
        request.setValue(trId, forHTTPHeaderField: "tr_id")
        request.setValue("P", forHTTPHeaderField: "custtype")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)

        guard let decoded = try? JSONDecoder().decode(KISBalanceResponse.self, from: data) else {
            let raw = String(data: data, encoding: .utf8) ?? "(empty)"
            throw KISError.apiError("응답 파싱 실패: \(raw.prefix(120))")
        }
        guard decoded.rtCd == "0" else {
            throw KISError.apiError(decoded.msg1 ?? decoded.msgCd ?? "알 수 없는 오류")
        }

        let holdings = (decoded.output1 ?? []).compactMap { $0.toHolding() }
        let summary = (decoded.output2?.first?.toSummary()) ?? KISSummary(
            depositAmount: 0,
            totalEvalAmount: 0,
            netAssetAmount: 0
        )

        return KISPortfolio(holdings: holdings, summary: summary, isDemo: isDemo)
    }

    // MARK: - Token Management

    /// UserDefaults 키 쌍 (토큰, 만료일) — appKey 앞 8자 + real/demo 구분
    private func persistenceKeys(appKey: String, base: String) -> (token: String, expiry: String) {
        let suffix = base.contains("vts") ? "demo" : "real"
        let prefix = String(appKey.prefix(8))
        return ("kisToken_\(prefix)_\(suffix)", "kisTokenExpiry_\(prefix)_\(suffix)")
    }

    private func getToken(base: String, appKey: String, appSecret: String) async throws -> String {
        let cacheKey = "\(appKey)|\(base)"
        let (tokenKey, expiryKey) = persistenceKeys(appKey: appKey, base: base)
        let ud = UserDefaults.standard

        // 1) 인메모리 캐시
        if let cached = tokenCache[cacheKey], cached.isValid {
            return cached.token
        }

        // 2) UserDefaults 영구 캐시 (앱 재시작 후에도 유효)
        if let saved = ud.string(forKey: tokenKey),
           let expiry = ud.object(forKey: expiryKey) as? Date,
           Date() < expiry {
            tokenCache[cacheKey] = CachedToken(token: saved, expiry: expiry)
            return saved
        }

        // 3) 레이트 리밋 쿨다운
        if let until = tokenCooldown[cacheKey], Date() < until {
            let wait = Int(until.timeIntervalSinceNow) + 1
            throw KISError.apiError("토큰 발급 대기 중 (\(wait)초 후 자동 재시도)")
        }

        // 4) 신규 발급
        do {
            let fresh = try await requestToken(base: base, appKey: appKey, appSecret: appSecret)
            tokenCooldown.removeValue(forKey: cacheKey)
            let expiry = Date().addingTimeInterval(23 * 60 * 60)
            tokenCache[cacheKey] = CachedToken(token: fresh, expiry: expiry)
            ud.set(fresh, forKey: tokenKey)
            ud.set(expiry, forKey: expiryKey)
            return fresh
        } catch let error as KISError {
            // EGW00133 = rate limited (1 request/min) → back off 70s
            if case .apiError(let msg) = error, msg.contains("EGW00133") {
                tokenCooldown[cacheKey] = Date().addingTimeInterval(70)
            }
            throw error
        }
    }

    private func requestToken(base: String, appKey: String, appSecret: String) async throws -> String {
        guard let url = URL(string: "\(base)/oauth2/tokenP") else { throw KISError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "grant_type": "client_credentials",
            "appkey": appKey,
            "appsecret": appSecret
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkHTTPStatus(response, data: data)

        guard let decoded = try? JSONDecoder().decode(KISTokenResponse.self, from: data) else {
            let raw = String(data: data, encoding: .utf8) ?? "(empty)"
            throw KISError.apiError("토큰 파싱 실패: \(raw.prefix(200))")
        }
        return decoded.accessToken
    }

    // MARK: - 관심종목 현재가 조회

    /// KIS 국내주식 현재가 조회 (FHKST01010100)
    /// symbol: "005930" (6자리 종목코드)
    func fetchCurrentPrice(symbol: String, appKey: String, appSecret: String) async -> Double? {
        guard let token = try? await getToken(base: realBaseURL, appKey: appKey, appSecret: appSecret)
        else { return nil }

        var components = URLComponents(string: "\(realBaseURL)/uapi/domestic-stock/v1/quotations/inquire-price")!
        components.queryItems = [
            URLQueryItem(name: "FID_COND_MRKT_DIV_CODE", value: "J"),
            URLQueryItem(name: "FID_INPUT_ISCD", value: symbol)
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.setValue(appKey, forHTTPHeaderField: "appkey")
        request.setValue(appSecret, forHTTPHeaderField: "appsecret")
        request.setValue("FHKST01010100", forHTTPHeaderField: "tr_id")
        request.setValue("P", forHTTPHeaderField: "custtype")
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = obj["output"] as? [String: Any],
              let priceStr = output["stck_prpr"] as? String,
              let price = Double(priceStr), price > 0
        else { return nil }
        return price
    }

    func getMarketToken(appKey: String, appSecret: String, isDemo: Bool) async throws -> String {
        let base = isDemo ? demoBaseURL : realBaseURL
        return try await getToken(base: base, appKey: appKey, appSecret: appSecret)
    }

    func invalidateToken(appKey: String) {
        tokenCache = tokenCache.filter { !$0.key.hasPrefix(appKey) }
        let ud = UserDefaults.standard
        let prefix = String(appKey.prefix(8))
        for suffix in ["real", "demo"] {
            ud.removeObject(forKey: "kisToken_\(prefix)_\(suffix)")
            ud.removeObject(forKey: "kisTokenExpiry_\(prefix)_\(suffix)")
        }
    }

    // MARK: - Helpers

    private func checkHTTPStatus(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200...299).contains(http.statusCode) else { return }
        let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let snippet = body.prefix(200).description
        switch http.statusCode {
        case 401: throw KISError.unauthorized
        case 403: throw KISError.apiError("403 Forbidden — \(snippet)")
        case 500...599:
            // EGW00201: 초당 거래건수 초과 → 재시도 가능한 별도 케이스
            if body.contains("EGW00201") { throw KISError.rateLimitPerSecond }
            throw KISError.serverError(http.statusCode, snippet)
        default: throw KISError.httpError(http.statusCode)
        }
    }
}

enum KISError: LocalizedError {
    case invalidURL
    case unauthorized
    case rateLimitPerSecond
    case serverError(Int, String)
    case httpError(Int)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "KIS: App Key 또는 Secret이 올바르지 않습니다"
        case .rateLimitPerSecond: return "KIS: 초당 요청 한도 초과"
        case .serverError(let code, let body):
            return body.isEmpty ? "KIS: 서버 오류 \(code)" : "KIS: 서버 오류 \(code) — \(body)"
        case .httpError(let code): return "KIS: HTTP 오류 \(code)"
        case .apiError(let msg): return "KIS: \(msg)"
        }
    }
}
