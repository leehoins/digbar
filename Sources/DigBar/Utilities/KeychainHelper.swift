import Foundation

/// API 키를 UserDefaults에 저장합니다.
/// Keychain은 Xcode 개발 빌드에서 코드서명이 매번 바뀌어 암호 팝업이 반복되므로 사용하지 않습니다.
/// 이 앱은 개인용 로컬 도구이므로 UserDefaults로 충분합니다.
enum KeychainHelper {
    private static let ud = UserDefaults.standard

    static func save(key: String, value: String) {
        ud.set(value, forKey: key)
    }

    static func load(key: String) -> String? {
        ud.string(forKey: key)
    }

    static func delete(key: String) {
        ud.removeObject(forKey: key)
    }
}
