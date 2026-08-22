// ThoxWarRoomTests.swift
// XCTest smoke tests for ThoxWarRoom — both macOS and iOS targets compile
// these. Verifies the navigation policy (off-domain → external), the base
// URL, and the load state machine without spinning up a real WKWebView.

import XCTest
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
    func testOffDomainOpensExternally() {
        let model = ThoxWebViewModel()
        XCTAssertTrue(model.shouldOpenExternally(URL(string: "https://github.com/foo")!))
        XCTAssertTrue(model.shouldOpenExternally(URL(string: "https://accounts.google.com/x")!))
        XCTAssertTrue(model.shouldOpenExternally(URL(string: "https://example.com/")!))
    }

    @MainActor
    func testWebUIAndSubpathsStayInApp() {
        let model = ThoxWebViewModel()
        XCTAssertFalse(model.shouldOpenExternally(URL(string: "https://webui.thox.ai/")!))
        XCTAssertFalse(model.shouldOpenExternally(URL(string: "https://webui.thox.ai/chat")!))
        XCTAssertFalse(model.shouldOpenExternally(URL(string: "https://webui.thox.ai/api/v1/chats")!))
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
}
