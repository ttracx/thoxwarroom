// LoadingOverlay.swift
// Branded loading spinner + offline/error state with Retry button. Rendered
// on top of the WKWebView so a failed load never produces a white screen.

import SwiftUI

struct LoadingOverlay: View {
    enum Kind {
        case loading
        case error(String)
    }

    let kind: Kind
    var onRetry: () -> Void

    var body: some View {
        ZStack {
            ThoxTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                switch kind {
                case .loading:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(ThoxTheme.accent)
                    Text("Loading \(ThoxWebViewModel.baseURL.host ?? "ThoxWarRoom")…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ThoxTheme.secondaryText)

                case .error(let message):
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(ThoxTheme.accent)
                    Text("Can't reach webui.thox.ai")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ThoxTheme.primaryText)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(ThoxTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 32)
                    Button(action: onRetry) {
                        Text("Retry")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 8)
                            .background(ThoxTheme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(ThoxTheme.surface.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ThoxTheme.separator, lineWidth: 1)
            )
        }
        .transition(.opacity)
    }
}

#Preview("Loading") {
    LoadingOverlay(kind: .loading, onRetry: {})
        .frame(width: 600, height: 400)
}

#Preview("Error") {
    LoadingOverlay(kind: .error("The Internet connection appears to be offline."), onRetry: {})
        .frame(width: 600, height: 400)
}
