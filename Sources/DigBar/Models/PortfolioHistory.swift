import Foundation
import Observation

// MARK: - Time Range

enum HistoryRange: String, CaseIterable {
    case hour1  = "1시간"
    case hour6  = "6시간"
    case hour24 = "24시간"

    var seconds: TimeInterval {
        switch self {
        case .hour1:  return 3_600
        case .hour6:  return 21_600
        case .hour24: return 86_400
        }
    }
}

// MARK: - Snapshot

struct PortfolioSnapshot: Codable, Identifiable {
    var id: Date { timestamp }
    let timestamp: Date
    let totalKRW: Double
    let totalUSD: Double
}

// MARK: - History Store

@Observable
final class PortfolioHistory {

    private(set) var snapshots: [PortfolioSnapshot] = []

    private static let maxAge: TimeInterval = 86_400  // 24 h

    private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
        let dir = support.appendingPathComponent("DigBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir.appendingPathComponent("portfolio_history.json")
    }()

    init() { load() }

    // MARK: - Append

    func append(krw: Double, usd: Double) {
        // 0 값은 로딩 중 상태 — 저장하지 않음 (차트 -100% 스파이크 방지)
        guard krw > 0 || usd > 0 else { return }
        let now = Date()
        // Deduplicate: skip if last snapshot is < 15 s ago
        if let last = snapshots.last, now.timeIntervalSince(last.timestamp) < 15 { return }
        snapshots.append(PortfolioSnapshot(timestamp: now, totalKRW: krw, totalUSD: usd))
        prune()
        let copy = snapshots
        Task.detached(priority: .background) { Self.persist(copy) }
    }

    // MARK: - Filtered view

    func snapshots(for range: HistoryRange) -> [PortfolioSnapshot] {
        let cutoff = Date().addingTimeInterval(-range.seconds)
        return snapshots.filter { $0.timestamp >= cutoff }
    }

    // MARK: - Private

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        snapshots = snapshots.filter { $0.timestamp >= cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([PortfolioSnapshot].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        snapshots = decoded.filter { $0.timestamp >= cutoff }
    }

    private static func persist(_ snapshots: [PortfolioSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
