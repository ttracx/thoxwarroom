// ContentView.swift
// Root view: WKWebView takes the full window; an overlay sits on top during
// initial load and on errors. macOS gets a compact title chip; iOS shows a
// slim status pill above the WebView.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ThoxWebViewModel

    var body: some View {
        ZStack {
            ThoxTheme.background.ignoresSafeArea()
            ThoxWebView(model: model)
                .opacity(model.state == .loaded ? 1 : 0)
            switch model.state {
            case .idle, .loading:
                LoadingOverlay(kind: .loading, onRetry: { model.reload() })
            case .error(let message):
                LoadingOverlay(kind: .error(message), onRetry: { model.resetForRetry() })
            case .loaded:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.state)
    }
}
