import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore

final class URLSessionProviderTransportTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testComposesOnlyEndpointAndRelativePathAndInjectsBearerAtSendTime() async throws {
        let endpoint = try hostedEndpoint("https://provider.example.com/api")
        let request = try ProviderRequest(
            method: .post,
            relativePath: "/v1/chat",
            body: Data("{}".utf8)
        )
        let credential = ProviderCredential(bytes: Data("private-token".utf8))
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://provider.example.com/api/v1/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return .http(statusCode: 201, body: Data("response".utf8))
        }

        let response = try await transport().send(request, to: endpoint, credential: credential)

        XCTAssertEqual(response.statusCode, 201)
        XCTAssertEqual(response.body, Data("response".utf8))
    }

    func testDoesNotInjectAuthorizationWithoutCredential() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return .http(statusCode: 200, body: Data())
        }

        _ = try await transport().send(
            try ProviderRequest(method: .get, relativePath: "/v1/models"),
            to: hostedEndpoint("https://provider.example.com"),
            credential: nil
        )
    }

    func testComposesValidatedQueryItemsWithoutRawQueryStrings() async throws {
        let meshID = try ProviderQueryItem(
            name: "mesh_id",
            value: "123e4567-e89b-12d3-a456-426614174000"
        )
        let limit = try ProviderQueryItem(name: "limit", value: "100")
        StubURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://provider.example.com/api/events?mesh_id=123e4567-e89b-12d3-a456-426614174000&limit=100"
            )
            return .http(statusCode: 200, body: Data())
        }

        _ = try await transport().send(
            try ProviderRequest(
                method: .get,
                relativePath: "/api/events",
                queryItems: [meshID, limit]
            ),
            to: hostedEndpoint("https://provider.example.com"),
            credential: nil
        )
    }

    func testRejectsRequestAndResponseBodiesOverPolicyLimits() async throws {
        let policy = try ProviderTransportPolicy(
            maximumRequestBodyBytes: 2,
            maximumResponseBodyBytes: 3,
            requestTimeout: 1,
            resourceTimeout: 2
        )
        let transport = transport(policy: policy)
        let endpoint = try hostedEndpoint("https://provider.example.com")

        do {
            _ = try await transport.send(
                try ProviderRequest(method: .post, relativePath: "/v1", body: Data([1, 2, 3])),
                to: endpoint,
                credential: nil
            )
            XCTFail("Expected request body limit")
        } catch {
            XCTAssertEqual(
                error as? URLSessionProviderTransportError,
                .requestBodyTooLarge(limit: 2)
            )
        }

        StubURLProtocol.handler = { _ in
            .http(statusCode: 200, body: Data([1, 2, 3, 4]))
        }
        do {
            _ = try await transport.send(
                try ProviderRequest(method: .get, relativePath: "/v1"),
                to: endpoint,
                credential: nil
            )
            XCTFail("Expected response body limit")
        } catch {
            XCTAssertEqual(
                error as? URLSessionProviderTransportError,
                .responseBodyTooLarge(limit: 3)
            )
        }
    }

    func testRejectsInvalidPolicyWithoutCrashing() {
        XCTAssertThrowsError(try ProviderTransportPolicy(maximumRequestBodyBytes: -1))
        XCTAssertThrowsError(try ProviderTransportPolicy(maximumResponseBodyBytes: -1))
        XCTAssertThrowsError(try ProviderTransportPolicy(requestTimeout: 0))
        XCTAssertThrowsError(try ProviderTransportPolicy(requestTimeout: 2, resourceTimeout: 1))
    }

    func testRejectsInvalidBearerEncodingAndHeaderInjection() async throws {
        let endpoint = try hostedEndpoint("https://provider.example.com")
        let request = try ProviderRequest(method: .get, relativePath: "/v1")
        let invalidCredentials = [
            ("invalid UTF-8", Data([0xFF])),
            ("header newline", Data("token\r\nInjected: true".utf8)),
            ("empty", Data()),
        ]
        for (label, bytes) in invalidCredentials {
            do {
                _ = try await transport().send(
                    request,
                    to: endpoint,
                    credential: ProviderCredential(bytes: bytes)
                )
                XCTFail("Expected invalid credential: \(label)")
            } catch {
                XCTAssertEqual(
                    error as? URLSessionProviderTransportError,
                    .invalidCredential,
                    label
                )
            }
        }
    }

    func testRedirectGuardAllowsOnlyExactOrigin() throws {
        let guardDelegate = RedirectGuard(origin: Origin(URL(string: "https://provider.example.com")!))
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://provider.example.com/start")!)
        let redirectResponse = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://provider.example.com/start")!,
            statusCode: 302,
            httpVersion: nil,
            headerFields: nil
        ))

        var acceptedRequest: URLRequest?
        guardDelegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: redirectResponse,
            newRequest: URLRequest(url: URL(string: "https://provider.example.com/next")!)
        ) { acceptedRequest = $0 }
        XCTAssertEqual(acceptedRequest?.url?.path, "/next")
        XCTAssertFalse(guardDelegate.blockedCrossOriginRedirect)

        var rejectedRequest: URLRequest?
        guardDelegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: redirectResponse,
            newRequest: URLRequest(url: URL(string: "https://other.example.com/next")!)
        ) { rejectedRequest = $0 }
        XCTAssertNil(rejectedRequest)
        XCTAssertTrue(guardDelegate.blockedCrossOriginRedirect)
        session.invalidateAndCancel()
    }

    func testMapsNetworkFailureWithoutLeakingRequestDetails() async throws {
        StubURLProtocol.handler = { _ in
            .failure(URLError(.timedOut))
        }
        do {
            _ = try await transport().send(
                try ProviderRequest(method: .get, relativePath: "/v1"),
                to: hostedEndpoint("https://provider.example.com"),
                credential: nil
            )
            XCTFail("Expected mapped network failure")
        } catch {
            XCTAssertEqual(
                error as? URLSessionProviderTransportError,
                .network(code: .timedOut)
            )
        }
    }

    private func transport(
        policy: ProviderTransportPolicy = .secureDefault
    ) -> URLSessionProviderTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = policy.requestTimeout
        configuration.timeoutIntervalForResource = policy.resourceTimeout
        return URLSessionProviderTransport(policy: policy, configuration: configuration)
    }

    private func hostedEndpoint(_ value: String) throws -> ValidatedEndpoint {
        try EndpointValidator.validate(
            value,
            declaredBoundary: .hosted,
            hostedAccess: .granted
        )
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Result {
        case http(statusCode: Int, body: Data)
        case failure(Error)
    }

    private static let handlerStorage = HandlerStorage()

    static var handler: ((URLRequest) throws -> Result)? {
        get { handlerStorage.value }
        set { handlerStorage.value = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.unknown)
            }
            switch try handler(request) {
            case let .http(statusCode, body):
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Length": "\(body.count)"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            case let .failure(error):
                client?.urlProtocol(self, didFailWithError: error)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class HandlerStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: ((URLRequest) throws -> StubURLProtocol.Result)?

    var value: ((URLRequest) throws -> StubURLProtocol.Result)? {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}
