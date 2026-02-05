//
//  AccountWebView.swift
//  StitchSocial
//
//  Embedded WebView for account management (profile, settings, wallet, support)
//

import SwiftUI
import WebKit
import FirebaseAuth

struct AccountWebView: View {
    
    // MARK: - Properties
    
    let userID: String
    let initialPath: String
    var onDismiss: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var loadProgress: Double = 0
    @State private var webTitle: String = "Manage Account"
    @State private var authToken: String? = nil
    @State private var tokenError: Bool = false
    
    // MARK: - Configuration
    
    private var baseURL: String {
        return "https://stitchsocial.me"
    }
    
    private var fullURL: URL? {
        guard let token = authToken, !token.isEmpty else { return nil }
        let urlString = "\(baseURL)\(initialPath)?token=\(token)&app=true"
        print("🌐 WEBVIEW URL: \(baseURL)\(initialPath)")
        return URL(string: urlString)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if tokenError {
                    authErrorView
                } else if let url = fullURL {
                    WebViewContainer(
                        url: url,
                        isLoading: $isLoading,
                        loadProgress: $loadProgress,
                        webTitle: $webTitle,
                        onPurchaseComplete: handlePurchaseComplete
                    )
                } else {
                    // Loading token
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        
                        Text("Authenticating...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                
                // Loading overlay
                if isLoading && fullURL != nil {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.8))
                }
            }
            .navigationTitle(webTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        onDismiss?()
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.cyan)
                    }
                }
            }
            .onAppear {
                fetchAuthToken()
            }
        }
    }
    
    // MARK: - Auth Error View
    
    private var authErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Authentication Error")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Please sign in again and try once more.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                tokenError = false
                fetchAuthToken()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.cyan)
            .foregroundColor(.black)
            .cornerRadius(12)
            .padding(.top, 8)
        }
        .padding()
    }
    
    // MARK: - Error View
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("Unable to Load")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Please check your connection and try again.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private func fetchAuthToken() {
        guard let user = Auth.auth().currentUser else {
            print("❌ WEBVIEW: No current Firebase user")
            tokenError = true
            return
        }
        
        user.getIDToken { token, error in
            if let error = error {
                print("❌ WEBVIEW: Token error - \(error.localizedDescription)")
                tokenError = true
                return
            }
            
            if let token = token {
                print("✅ WEBVIEW: Got Firebase ID token for \(user.uid)")
                self.authToken = token
            } else {
                print("❌ WEBVIEW: No token returned")
                tokenError = true
            }
        }
    }
    
    private func handlePurchaseComplete() {
        Task {
            try? await HypeCoinService.shared.syncBalance(userID: userID)
        }
    }
}

// MARK: - WebView Container (UIViewRepresentable)

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var loadProgress: Double
    @Binding var webTitle: String
    var onPurchaseComplete: (() -> Void)?
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        configuration.preferences.javaScriptEnabled = true
        
        configuration.userContentController.add(context.coordinator, name: "purchaseComplete")
        configuration.userContentController.add(context.coordinator, name: "closeWebView")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = true
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebViewContainer
        
        init(_ parent: WebViewContainer) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.webTitle = webView.title ?? "Manage Account"
            
            let darkModeCSS = """
                document.body.style.backgroundColor = '#000';
                document.body.style.color = '#fff';
            """
            webView.evaluateJavaScript(darkModeCSS, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            print("❌ WEBVIEW: Navigation failed - \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            print("❌ WEBVIEW: Provisional navigation failed - \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            if url.scheme == "stitchsocial" {
                if url.host == "purchase-complete" {
                    parent.onPurchaseComplete?()
                }
                decisionHandler(.cancel)
                return
            }
            
            if url.scheme == "https" {
                decisionHandler(.allow)
                return
            }
            
            decisionHandler(.cancel)
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "purchaseComplete":
                print("✅ WEBVIEW: Purchase complete message received")
                parent.onPurchaseComplete?()
                
            case "closeWebView":
                print("✅ WEBVIEW: Close message received")
                
            default:
                break
            }
        }
    }
}

// MARK: - Convenience Initializers

extension AccountWebView {
    /// Open full account management page
    static func account(userID: String, onDismiss: (() -> Void)? = nil) -> AccountWebView {
        AccountWebView(userID: userID, initialPath: "/app/account", onDismiss: onDismiss)
    }
    
    /// Open account page with wallet tab
    static func wallet(userID: String, onDismiss: (() -> Void)? = nil) -> AccountWebView {
        AccountWebView(userID: userID, initialPath: "/app/account", onDismiss: onDismiss)
    }
    
    /// Open specific coin package purchase
    static func buyCoins(userID: String, package: HypeCoinPackage, onDismiss: (() -> Void)? = nil) -> AccountWebView {
        AccountWebView(userID: userID, initialPath: "/app/account", onDismiss: onDismiss)
    }
    
    /// Open account settings
    static func settings(userID: String, onDismiss: (() -> Void)? = nil) -> AccountWebView {
        AccountWebView(userID: userID, initialPath: "/app/account", onDismiss: onDismiss)
    }
    
    /// Open subscription management
    static func subscriptions(userID: String, onDismiss: (() -> Void)? = nil) -> AccountWebView {
        AccountWebView(userID: userID, initialPath: "/app/account", onDismiss: onDismiss)
    }
}
