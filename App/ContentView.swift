// ContentView.swift
// Root view: WKWebView takes the full window; an overlay sits on top during
// initial load and on errors. macOS gets a compact title chip; iOS shows a
// slim status pill above the WebView.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: ThoxWebViewModel
    @State private var isClearConfirmationPresented = false

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

            VStack {
                HStack {
                    Spacer()
                    sessionControls
                }
                Spacer()
            }
            .padding()
        }
        .animation(.easeInOut(duration: 0.18), value: model.state)
        .confirmationDialog(
            "Sign out and clear this session?",
            isPresented: $isClearConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Sign Out & Clear Session", role: .destructive) {
                Task { await model.clearPersistentSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cookies, local storage, caches, and other website data saved by ThoxWarRoom will be removed from this device.")
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        switch model.sessionClearState {
        case .clearing:
            Label("Clearing session…", systemImage: "hourglass")
                .accessibilityLabel("Clearing persistent session")
        case .cleared:
            Label("Session cleared", systemImage: "checkmark.shield")
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                clearSessionButton
            }
        case .persistent:
            clearSessionButton
        }
    }

    private var clearSessionButton: some View {
        Button {
            isClearConfirmationPresented = true
        } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(.bordered)
        .accessibilityHint("Clears cookies and all persistent website data after confirmation")
    }
}
