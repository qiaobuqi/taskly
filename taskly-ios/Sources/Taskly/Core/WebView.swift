import SwiftUI
import WebKit

/// Minimal WKWebView wrapper for showing hosted pages (privacy policy / terms) in-app.
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
}

/// In-app legal page (navigation title + Done), used for Privacy Policy and Terms so
/// users don't get kicked out to Safari.
struct LegalView: View {
    let title: String
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

enum Legal {
    static let privacyURL = URL(string: "https://taskly.cnirv.com/privacy")!
    static let termsURL = URL(string: "https://taskly.cnirv.com/terms")!
}
