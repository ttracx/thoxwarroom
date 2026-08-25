// WarRoomChatArtifactPanel.swift
// Two-tab artifact panel (Preview / Code) matching F3 of the golden reference,
// plus F4 fullscreen presentation.
//
// The web view is scoped to render *bundled fixture HTML only*:
//   - `websiteDataStore = .nonPersistent()` so nothing survives the tab
//   - navigation decisions cancel every request that isn't the initial
//     `about:blank` seed (srcdoc navigation loads `about:blank`)
//   - custom user agent, no back/forward gestures
//
// This is not a general-purpose sandbox — it exists because the *fixture* we
// render is a static, reviewed HTML string. When a live-artifact transport is
// added, this file needs a real content-rule list and an isolated data store
// per artifact origin. That is called out in the WR-004 handoff.

import SwiftUI
import WebKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum ArtifactPanelTab: String, Hashable {
    case preview
    case code
}

struct ArtifactPanel: View {
    let spec: ArtifactSpec
    let onClose: () -> Void
    let onFullscreen: () -> Void
    @Binding var activeTab: ArtifactPanelTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(ThoxTheme.separator)
            body(for: activeTab)
        }
        .background(ThoxTheme.surface)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("", selection: $activeTab) {
                Text("Preview").tag(ArtifactPanelTab.preview)
                Text("Code").tag(ArtifactPanelTab.code)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("chat-artifact-tab-selector")

            Text(spec.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ThoxTheme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                onFullscreen()
            } label: {
                Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Fullscreen artifact")
            .accessibilityIdentifier("chat-artifact-fullscreen")

            Button {
                onClose()
            } label: {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Close artifact panel")
            .accessibilityIdentifier("chat-artifact-close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func body(for tab: ArtifactPanelTab) -> some View {
        switch tab {
        case .preview:
            SafeArtifactWebView(html: spec.source)
                .accessibilityIdentifier("chat-artifact-preview")
        case .code:
            ScrollView {
                Text(spec.source)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(ThoxTheme.primaryText)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 13.0 / 255, green: 17.0 / 255, blue: 23.0 / 255))
            .accessibilityIdentifier("chat-artifact-code")
        }
    }
}

// MARK: - Fullscreen sheet

struct ArtifactFullscreenSheet: View {
    let spec: ArtifactSpec
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(spec.title, systemImage: "square.stack.3d.up")
                    .font(.headline)
                    .foregroundStyle(ThoxTheme.primaryText)
                Spacer(minLength: 8)
                Button {
                    onClose()
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close fullscreen artifact")
                .accessibilityIdentifier("chat-artifact-fullscreen-close")
            }
            .padding(12)

            Divider().overlay(ThoxTheme.separator)

            SafeArtifactWebView(html: spec.source)
                .accessibilityIdentifier("chat-artifact-fullscreen-preview")
        }
        .background(ThoxTheme.background)
    }
}

// MARK: - Safe artifact WKWebView

struct SafeArtifactWebView: View {
    let html: String

    var body: some View {
        WebViewContainer(html: html)
    }
}

#if os(macOS)
private struct WebViewContainer: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> SafeArtifactWebCoordinator { SafeArtifactWebCoordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastRenderedHTML != html {
            context.coordinator.lastRenderedHTML = html
            nsView.loadHTMLString(html, baseURL: nil)
        }
    }
}
#elseif os(iOS)
private struct WebViewContainer: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> SafeArtifactWebCoordinator { SafeArtifactWebCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(coordinator: context.coordinator)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastRenderedHTML != html {
            context.coordinator.lastRenderedHTML = html
            uiView.loadHTMLString(html, baseURL: nil)
        }
    }
}
#endif

private func makeWebView(coordinator: SafeArtifactWebCoordinator) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.allowsAirPlayForMediaPlayback = false
    configuration.mediaTypesRequiringUserActionForPlayback = .all
    configuration.suppressesIncrementalRendering = false
    #if os(iOS)
    configuration.allowsInlineMediaPlayback = true
    configuration.allowsPictureInPictureMediaPlayback = false
    #endif

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = coordinator
    webView.uiDelegate = coordinator
    webView.customUserAgent = "ThoxWarRoom-Artifact/1.0"
    webView.allowsBackForwardNavigationGestures = false
    #if os(macOS)
    webView.allowsMagnification = false
    #endif
    return webView
}

final class SafeArtifactWebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var lastRenderedHTML: String = ""

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // srcdoc/loadHTMLString navigates to about:blank first — allow that
        // once, cancel everything else. This turns the WebView into a strict
        // display surface for the bundled fixture HTML.
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if url.absoluteString == "about:blank" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Never open target=_blank / window.open — the artifact renders in
        // place and any such attempt is silently discarded.
        nil
    }
}
