import Foundation
import CommonCrypto

enum CryptoHelper {
    /// HMAC-SHA256 signature for Binance API
    static func hmacSHA256(key: String, data: String) -> String {
        guard
            let keyData = key.data(using: .utf8),
            let msgData = data.data(using: .utf8)
        else { return "" }

        var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        keyData.withUnsafeBytes { keyBytes in
            msgData.withUnsafeBytes { msgBytes in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBytes.baseAddress, keyBytes.count,
                    msgBytes.baseAddress, msgBytes.count,
                    &hmac
                )
            }
        }

        return hmac.map { String(format: "%02x", $0) }.joined()
    }
}
