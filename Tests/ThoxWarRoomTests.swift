// ThoxWarRoomTests.swift
// XCTest smoke tests for ThoxWarRoom — both macOS and iOS targets compile
// these. Verifies the navigation policy (off-domain → external), the base
// URL, and the load state machine without spinning up a real WKWebView.

import XCTest
import WebKit
@testable import ThoxWarRoom

final class ThoxWebViewModelTests: XCTestCase {
    @MainActor
    func testBaseURLIsWebUI() {
        XCTAssertEqual(
            ThoxWebViewModel.baseURL.absoluteString,
            "https://webui.thox.ai",
            "Base URL must be the production OpenWebUI host"
        )
        XCTAssertEqual(
            ThoxWebViewModel.baseURL.host, "webui.thox.ai",
            "Base URL host must match the keep-in-app policy"
        )
    }

    @MainActor
    func testUserActivatedHTTPSOffDomainOpensExternally() {
        let model = ThoxWebViewModel()
        for rawURL in [
            "https://github.com/foo",
            "https://accounts.google.com/x",
            "https://example.com/"
        ] {
            XCTAssertEqual(
                model.navigationDecision(for: URL(string: rawURL), isUserInitiated: true),
                .openExternally,
                rawURL
            )
        }
    }

    @MainActor
    func testWebUIAndSubpathsStayInApp() {
        let model = ThoxWebViewModel()
        for rawURL in [
            "https://webui.thox.ai/",
            "https://webui.thox.ai/chat",
            "https://webui.thox.ai/api/v1/chats",
            "HTTPS://WEBUI.THOX.AI:443/chat"
        ] {
            XCTAssertEqual(
                model.navigationDecision(for: URL(string: rawURL), isUserInitiated: false),
                .allowInApp,
                rawURL
            )
        }
    }

    @MainActor
    func testAutomaticOffDomainNavigationIsCancelled() {
        let model = ThoxWebViewModel()
        XCTAssertEqual(
            model.navigationDecision(
                for: URL(string: "https://accounts.example.com/redirect"),
                isUserInitiated: false
            ),
            .cancel
        )
    }

    @MainActor
    func testUnsafeSchemesCredentialsAndPortsAreCancelled() {
        let model = ThoxWebViewModel()
        let blockedURLs: [URL?] = [
            nil,
            URL(string: "http://webui.thox.ai"),
            URL(string: "javascript:alert(1)"),
            URL(string: "file:///etc/passwd"),
            URL(string: "thox://webui.thox.ai/callback"),
            URL(string: "https://user:password@webui.thox.ai"),
            URL(string: "https://webui.thox.ai:8443"),
            URL(string: "https://example.com:8443")
        ]

        for url in blockedURLs {
            XCTAssertEqual(
                model.navigationDecision(for: url, isUserInitiated: true),
                .cancel,
                url?.absoluteString ?? "nil URL"
            )
        }

        XCTAssertEqual(
            model.navigationDecision(
                for: URL(string: "https://webui.thox.ai.evil.example"),
                isUserInitiated: true
            ),
            .openExternally,
            "A host suffix must never be mistaken for the trusted in-app origin"
        )
    }

    @MainActor
    func testInitialStateIsIdle() {
        let model = ThoxWebViewModel()
        if case .idle = model.state {
            // expected
        } else {
            XCTFail("Expected initial state .idle, got \(model.state)")
        }
    }

    @MainActor
    func testLoadingTransitions() {
        let model = ThoxWebViewModel()
        model.didStartLoading(url: ThoxWebViewModel.baseURL)
        if case .loading = model.state {} else {
            XCTFail("Expected .loading after didStartLoading")
        }
        model.didFinishLoading(url: ThoxWebViewModel.baseURL, title: "Open WebUI")
        if case .loaded = model.state {} else {
            XCTFail("Expected .loaded after didFinishLoading")
        }
        XCTAssertEqual(model.title, "Open WebUI")
    }

    @MainActor
    func testErrorStateClampsToError() {
        let model = ThoxWebViewModel()
        model.didStartLoading(url: ThoxWebViewModel.baseURL)
        model.didFailLoading(error: "offline")
        if case .error(let msg) = model.state {
            XCTAssertEqual(msg, "offline")
        } else {
            XCTFail("Expected .error after didFailLoading")
        }
        // A later finish should NOT clobber the sticky error.
        model.didFinishLoading(url: ThoxWebViewModel.baseURL, title: "x")
        if case .error = model.state {} else {
            XCTFail("Error state must persist past later finish events")
        }
    }

    @MainActor
    func testReloadPendingLifecycle() {
        let model = ThoxWebViewModel()
        XCTAssertFalse(model.isReloadPending)
        model.reload()
        XCTAssertTrue(model.isReloadPending)
        model.acknowledgeReload()
        XCTAssertFalse(model.isReloadPending)
    }

    @MainActor
    func testResetForRetryReturnsToIdleThenLoading() {
        let model = ThoxWebViewModel()
        model.didFailLoading(error: "boom")
        if case .error = model.state {} else {
            XCTFail("Expected .error before retry")
        }
        // resetForRetry clears the error and arms a reload. Because
        // reload() also flips state to .loading, by the time we observe
        // state we see .loading — that's the post-conditions we want.
        model.resetForRetry()
        XCTAssertTrue(model.isReloadPending, "resetForRetry should arm a reload")
        if case .loading = model.state {} else {
            XCTFail("resetForRetry should land state at .loading (error cleared, reload armed)")
        }
    }

    @MainActor
    func testClearPersistentSessionUpdatesStateAndReloadsCanonicalURL() async {
        let cleaner = SessionDataCleanerStub()
        let model = ThoxWebViewModel(
            dataStore: .nonPersistent(),
            sessionDataCleaner: cleaner
        )
        model.didStartLoading(url: URL(string: "https://webui.thox.ai/chat/secret")!)
        model.didFinishLoading(
            url: URL(string: "https://webui.thox.ai/chat/secret")!,
            title: "Sensitive conversation"
        )

        await model.clearPersistentSession()

        XCTAssertEqual(cleaner.clearCallCount, 1)
        XCTAssertEqual(model.sessionClearState, .cleared)
        XCTAssertEqual(model.currentURL, ThoxWebViewModel.baseURL)
        XCTAssertEqual(model.title, "ThoxWarRoom")
        XCTAssertEqual(model.state, .loading)
        XCTAssertTrue(model.isReloadPending)

        model.didFinishLoading(url: ThoxWebViewModel.baseURL, title: "Open WebUI")
        XCTAssertEqual(
            model.sessionClearState,
            .persistent,
            "The sign-out control must become available again after the landing page reloads"
        )
    }

    @MainActor
    func testClearPersistentSessionFailureIsNonSensitiveAndDoesNotReload() async {
        let cleaner = SessionDataCleanerStub(result: .failure(SessionDataCleanerStub.TestError.failed))
        let model = ThoxWebViewModel(
            dataStore: .nonPersistent(),
            sessionDataCleaner: cleaner
        )

        await model.clearPersistentSession()

        XCTAssertEqual(
            model.sessionClearState,
            .failed("Unable to clear the persistent session.")
        )
        XCTAssertFalse(model.isReloadPending)
        XCTAssertEqual(model.state, .idle)
    }

}

@MainActor
private final class SessionDataCleanerStub: SessionDataClearing {
    enum TestError: Error {
        case failed
    }

    private let result: Result<Void, Error>
    private(set) var clearCallCount = 0

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func clear() async throws {
        clearCallCount += 1
        try result.get()
    }
}
