import Foundation

/// Binance Futures mark price WebSocket.
/// Real:  wss://fstream.binance.com/stream?streams=...
/// Demo:  wss://demo-fapi.binance.com/stream?streams=...  (unofficial, may not work)
actor BinanceWebSocketService {
    private var webSocketTask: URLSessionWebSocketTask?
    private var connectedSymbols: Set<String> = []

    // MARK: - Connect

    /// Connects (or reuses) a mark-price stream for the given symbols.
    /// `onPrice` is called on whatever thread/executor the actor runs on —
    /// callers must dispatch to MainActor themselves.
    func connect(symbols: [String],
                 onPrice: @escaping @Sendable (String, Double) -> Void) {
        let newSet = Set(symbols)
        // No-op if already connected with the same symbols
        if newSet == connectedSymbols, webSocketTask != nil { return }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectedSymbols = newSet

        let streams = symbols
            .map { "\($0.lowercased())@markPrice@1s" }
            .joined(separator: "/")
        // Mark price is public market data — same for real and demo.
        // demo-fapi.binance.com does NOT support WebSocket.
        guard let url = URL(string: "wss://fstream.binance.com/stream?streams=\(streams)") else { return }

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        Task { await receiveLoop(task: task, onPrice: onPrice) }
    }

    // MARK: - Disconnect

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectedSymbols = []
    }

    // MARK: - Receive loop

    private func receiveLoop(task: URLSessionWebSocketTask,
                             onPrice: @escaping @Sendable (String, Double) -> Void) async {
        while true {
            guard webSocketTask === task else { return } // superseded by a new connect()

            do {
                let msg = try await task.receive()
                parse(msg, onPrice: onPrice)
            } catch {
                // Connection dropped or cancelled
                if webSocketTask === task { webSocketTask = nil }
                return
            }
        }
    }

    // MARK: - Parse

    private func parse(_ message: URLSessionWebSocketTask.Message,
                       onPrice: (String, Double) -> Void) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d):   text = String(data: d, encoding: .utf8) ?? ""
        @unknown default:    return
        }

        guard
            let data = text.data(using: .utf8),
            let wrapper = try? JSONDecoder().decode(WSWrapper.self, from: data),
            let price = Double(wrapper.data.p), price > 0
        else { return }

        onPrice(wrapper.data.s, price)
    }
}

// MARK: - Codable models

private struct WSWrapper: Codable {
    let data: WSMarkPrice
}

private struct WSMarkPrice: Codable {
    let s: String   // symbol  e.g. "XRPUSDT"
    let p: String   // mark price
}
