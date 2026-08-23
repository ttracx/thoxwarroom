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

    enum NavigationDecision: Equatable {
        case allowInApp
        case openExternally
        case cancel
    }

    enum SessionClearState: Equatable {
        case persistent
        case clearing
        case cleared
        case failed(String)
    }

    /// Canonical landing URL. All subpaths are kept in-app; off-domain links
    /// are routed through `decidePolicyFor`.
    static let baseURL = URL(string: "https://webui.thox.ai")!

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var currentURL: URL = baseURL
    @Published private(set) var title: String = "ThoxWarRoom"
    @Published private(set) var sessionClearState: SessionClearState = .persistent
    @Published var isReloadPending: Bool = false

    /// Persistent cookie store so the OpenWebUI login survives app restarts.
    /// Identical WKWebsiteDataStore.default() is set on both platforms.
    #if canImport(WebKit)
    let dataStore: WKWebsiteDataStore
    private let sessionDataCleaner: any SessionDataClearing
    #endif

    #if canImport(WebKit)
    convenience init() {
        let dataStore = WKWebsiteDataStore.default()
        self.init(dataStore: dataStore)
    }

    init(dataStore: WKWebsiteDataStore, sessionDataCleaner: (any SessionDataClearing)? = nil) {
        self.dataStore = dataStore
        self.sessionDataCleaner = sessionDataCleaner ?? WebKitSessionDataCleaner(dataStore: dataStore)
    }
    #else
    init() {}
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
        if sessionClearState == .cleared {
            sessionClearState = .persistent
        }
    }

    func didFailLoading(error: String) {
        state = .error(error)
    }

    /// Allows only the canonical HTTPS origin in-app. External URLs are handed
    /// to the system browser only for explicit user link activations and only
    /// when they are credential-free HTTPS URLs on the default port.
    func navigationDecision(for url: URL?, isUserInitiated: Bool) -> NavigationDecision {
        guard let url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443 else {
            return .cancel
        }

        if host == Self.baseURL.host {
            return .allowInApp
        }

        return isUserInitiated ? .openExternally : .cancel
    }

    /// Removes cookies, local storage, caches, and other persistent WebKit data,
    /// then returns the shell to its canonical landing URL. The caller should
    /// present confirmation before invoking this destructive action.
    #if canImport(WebKit)
    func clearPersistentSession() async {
        guard sessionClearState != .clearing else { return }
        sessionClearState = .clearing

        do {
            try await sessionDataCleaner.clear()
            currentURL = Self.baseURL
            title = "ThoxWarRoom"
            state = .loading
            isReloadPending = true
            sessionClearState = .cleared
        } catch {
            sessionClearState = .failed("Unable to clear the persistent session.")
        }
    }
    #endif

    func openCurrentURLExternally() {
        guard navigationDecision(for: currentURL, isUserInitiated: true) != .cancel else { return }
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

#if canImport(WebKit)
@MainActor
protocol SessionDataClearing: AnyObject {
    func clear() async throws
}

@MainActor
final class WebKitSessionDataCleaner: SessionDataClearing {
    private let dataStore: WKWebsiteDataStore

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
    }

    func clear() async throws {
        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }
    }
}
#endif

#if canImport(UIKit)
import UIKit
#endif
