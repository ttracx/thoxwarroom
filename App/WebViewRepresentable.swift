// WebViewRepresentable.swift
// Platform-conditional WKWebView wrapper. macOS uses NSViewRepresentable +
// WKWebView directly; iOS uses UIViewRepresentable. Both share the same
// configuration (persistent data store, custom user-agent, in-app navigation
// handler, and lifecycle callbacks back to ThoxWebViewModel).
//
// Why not the iOS 26 SwiftUI WebView? It's iOS 26+ only — we target iOS 17+
// and learned from MeshStack that libswiftWebKit linkages are unreliable
// across Xcode minor versions. Plain WKWebView is the durable choice.

import SwiftUI
import WebKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - macOS wrapper

#if os(macOS)
struct ThoxWebView: NSViewRepresentable {
    @ObservedObject var model: ThoxWebViewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = model.dataStore
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground") // match dark chrome

        if model.state == .idle {
            webView.load(URLRequest(url: ThoxWebViewModel.baseURL))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if model.isReloadPending {
            model.acknowledgeReload()
            nsView.load(URLRequest(url: model.currentURL))
        }
        context.coordinator.model = model
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var model: ThoxWebViewModel

        init(model: ThoxWebViewModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url {
                Task { @MainActor in self.model.didStartLoading(url: url) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url ?? ThoxWebViewModel.baseURL
            let title = webView.title
            Task { @MainActor in self.model.didFinishLoading(url: url, title: title) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let message = (error as NSError).localizedDescription
            Task { @MainActor in self.model.didFailLoading(error: message) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let message = (error as NSError).localizedDescription
            Task { @MainActor in self.model.didFailLoading(error: message) }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let decision = model.navigationDecision(
                for: navigationAction.request.url,
                isUserInitiated: navigationAction.navigationType == .linkActivated
            )
            switch decision {
            case .allowInApp:
                decisionHandler(.allow)
            case .openExternally:
                guard let url = navigationAction.request.url else {
                    decisionHandler(.cancel)
                    return
                }
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            case .cancel:
                decisionHandler(.cancel)
            }
        }

        // Keep an allowed target=_blank in this WebView. Only explicit, safe
        // off-domain link activations may leave the app.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            let decision = model.navigationDecision(
                for: navigationAction.request.url,
                isUserInitiated: navigationAction.navigationType == .linkActivated
            )
            switch decision {
            case .allowInApp:
                if let url = navigationAction.request.url {
                    webView.load(URLRequest(url: url))
                }
            case .openExternally:
                if let url = navigationAction.request.url {
                    NSWorkspace.shared.open(url)
                }
            case .cancel:
                break
            }
            return nil
        }
    }
}
#endif

// MARK: - iOS wrapper

#if os(iOS)
struct ThoxWebView: UIViewRepresentable {
    @ObservedObject var model: ThoxWebViewModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = model.dataStore
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        if model.state == .idle {
            webView.load(URLRequest(url: ThoxWebViewModel.baseURL))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if model.isReloadPending {
            model.acknowledgeReload()
            uiView.load(URLRequest(url: model.currentURL))
        }
        context.coordinator.model = model
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var model: ThoxWebViewModel

        init(model: ThoxWebViewModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url {
                Task { @MainActor in self.model.didStartLoading(url: url) }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let url = webView.url ?? ThoxWebViewModel.baseURL
            let title = webView.title
            Task { @MainActor in self.model.didFinishLoading(url: url, title: title) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let message = (error as NSError).localizedDescription
            Task { @MainActor in self.model.didFailLoading(error: message) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let message = (error as NSError).localizedDescription
            Task { @MainActor in self.model.didFailLoading(error: message) }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let decision = model.navigationDecision(
                for: navigationAction.request.url,
                isUserInitiated: navigationAction.navigationType == .linkActivated
            )
            switch decision {
            case .allowInApp:
                decisionHandler(.allow)
            case .openExternally:
                guard let url = navigationAction.request.url else {
                    decisionHandler(.cancel)
                    return
                }
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            case .cancel:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            let decision = model.navigationDecision(
                for: navigationAction.request.url,
                isUserInitiated: navigationAction.navigationType == .linkActivated
            )
            switch decision {
            case .allowInApp:
                if let url = navigationAction.request.url {
                    webView.load(URLRequest(url: url))
                }
            case .openExternally:
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                }
            case .cancel:
                break
            }
            return nil
        }
    }
}
#endif
