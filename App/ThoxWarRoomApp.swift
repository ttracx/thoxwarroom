// ThoxWarRoomApp.swift
// ThoxWarRoom — native SwiftUI wrapper for webui.thox.ai (macOS + iOS).
// Wires ContentView into a single SwiftUI scene for both platforms via
// platform-conditional scene types (WindowGroup on macOS, full-screen
// scene on iOS). Dark-mode-first via .preferredColorScheme(.dark).

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

@main
struct ThoxWarRoomApp: App {
    @StateObject private var webViewModel = ThoxWebViewModel()

    init() {
        // Defer NSApp.appearance assignment until after NSApplication is
        // bootstrapped (init() runs before NSApp.shared is initialized).
        // Setting it inside applicationDidFinishLaunching is the safe path.
        #if canImport(AppKit)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("ThoxWarRoom") {
            ContentView()
                .environmentObject(webViewModel)
                .preferredColorScheme(.dark)
                .frame(minWidth: 720, minHeight: 480)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {} // single-window app; disable File→New
            CommandGroup(after: .toolbar) {
                Button("Reload") { webViewModel.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Open in Browser") { webViewModel.openCurrentURLExternally() }
                    .keyboardShortcut("b", modifiers: .command)
            }
        }
        #endif
    }
}
