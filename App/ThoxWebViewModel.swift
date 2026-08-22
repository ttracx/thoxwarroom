// ThoxWebViewModel.swift
// Observable state holder for the WKWebView wrapper. Owns the load lifecycle,
// exposes loading/loaded/error states, and centralizes the navigation policy
// decision (in-app vs. external system browser) so the representables stay
// platform-conditional and stateless.

import Foundation
import Combine
#if canImport(WebKit)
import WebKit
#endif

@MainActor
final class ThoxWebViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    /// Canonical landing URL. All subpaths are kept in-app; off-domain links
    /// are routed through `decidePolicyFor`.
    static let baseURL = URL(string: "https://webui.thox.ai")!

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var currentURL: URL = baseURL
    @Published private(set) var title: String = "ThoxWarRoom"
    @Published var isReloadPending: Bool = false

    /// Persistent cookie store so the OpenWebUI login survives app restarts.
    /// Identical WKWebsiteDataStore.default() is set on both platforms.
    #if canImport(WebKit)
    let dataStore: WKWebsiteDataStore = .default()
    #endif

    func reload() {
        isReloadPending = true
        state = .loading
        // The actual reload is performed by the representable observing
        // `isReloadPending`. After it consumes the trigger, it flips the
        // flag back to false via `acknowledgeReload()`.
    }

    func acknowledgeReload() {
        isReloadPending = false
    }

    func didStartLoading(url: URL) {
        currentURL = url
        state = .loading
    }

    func didFinishLoading(url: URL, title: String?) {
        currentURL = url
        if let title, !title.isEmpty {
            self.title = title
        }
        if case .error = state { return } // don't clobber a sticky error
        state = .loaded
    }

    func didFailLoading(error: String) {
        state = .error(error)
    }

    /// Navigation policy decision: keep webui.thox.ai and its subpaths in-app;
    /// open anything else via the system browser.
    func shouldOpenExternally(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        let allowedHosts: Set<String> = ["webui.thox.ai"]
        return !allowedHosts.contains(host)
    }

    func openCurrentURLExternally() {
        #if canImport(AppKit)
        NSWorkspace.shared.open(currentURL)
        #elseif canImport(UIKit)
        UIApplication.shared.open(currentURL)
        #endif
    }

    /// Convenience used by Retry button to issue a fresh load.
    func resetForRetry() {
        state = .idle
        reload()
    }
}

#if canImport(UIKit)
import UIKit
#endif
