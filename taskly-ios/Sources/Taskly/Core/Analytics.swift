import Foundation
import UIKit

// MARK: - Analytics (埋点)
//
// Provider-agnostic event tracking. Right now it batches events and POSTs them to
// our own backend (`/analytics/events`); swapping in Firebase/Mixpanel later means
// changing only `flush()`. The event set is chosen to answer the questions that
// matter early: **DAU** (app_open / session_start carry a per-install anon_id) and
// **retention** (every event is timestamped and tied to user_id once logged in),
// plus a basic activation funnel (sign_up → post_task / apply → pay).

struct AnalyticsEvent {
    let event: String
    let sessionID: String
    let ts: Int64                 // client epoch milliseconds
    let props: [String: Any]
}

@MainActor
final class Analytics {
    static let shared = Analytics()

    private let anonID: String
    private var sessionID = UUID().uuidString
    private var buffer: [AnalyticsEvent] = []
    private var flushTask: Task<Void, Never>?
    private let endpoint = URL(string: APIConstants.baseURL + "/analytics/events")!
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"

    // Same network posture as NetworkManager: bypass local VPN/HTTP proxies
    // (they break TLS to our mainland-China API) and never wait unbounded.
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.connectionProxyDictionary = [:]
        config.proxyConfigurations = []
        return URLSession(configuration: config)
    }()

    private init() {
        // Stable per-install id so logged-out opens still count toward DAU and tie
        // back to the user once they sign in.
        if let saved = UserDefaults.standard.string(forKey: "analytics_anon_id") {
            anonID = saved
        } else {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "analytics_anon_id")
            anonID = id
        }
    }

    // MARK: Public API

    /// Track an event with optional properties.
    func track(_ event: String, _ props: [String: Any] = [:]) {
        let e = AnalyticsEvent(event: event, sessionID: sessionID,
                               ts: Int64(Date().timeIntervalSince1970 * 1000), props: props)
        buffer.append(e)
        #if DEBUG
        print("📊 [analytics] \(event) \(props)")
        #endif
        if buffer.count >= 10 { flush() } else { scheduleFlush() }
    }

    /// Convenience for screen views — the backbone of funnel + retention analysis.
    func screen(_ name: String) { track("screen_view", ["screen": name]) }

    /// Start a new session (cold launch or return-to-foreground). Drives DAU.
    func startSession(cold: Bool) {
        sessionID = UUID().uuidString
        track("session_start", ["cold": cold])
    }

    /// Flush on background so events aren't lost if the app is killed.
    func appDidEnterBackground() { track("app_background"); flush() }

    // MARK: Flushing

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s debounce
            await self?.flush()
        }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        flushTask?.cancel()

        let payload: [String: Any] = [
            "anon_id": anonID,
            "platform": "ios",
            "app_version": appVersion,
            "events": batch.map { ["event": $0.event, "session_id": $0.sessionID,
                                   "ts": $0.ts, "props": $0.props] }
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Attach the auth token if present so events are tied to the user.
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        Task.detached {
            // Fire-and-forget; on failure we simply drop this batch (acceptable for
            // product analytics, and avoids unbounded memory growth offline).
            _ = try? await Analytics.urlSession.data(for: req)
        }
    }
}
