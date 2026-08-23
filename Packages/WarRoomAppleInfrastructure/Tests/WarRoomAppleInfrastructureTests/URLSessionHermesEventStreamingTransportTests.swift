import Foundation
import XCTest
@testable import WarRoomAppleInfrastructure
import WarRoomCore
import WarRoomHermes

final class URLSessionHermesEventStreamingTransportTests: XCTestCase {
    override func tearDown() {
        StreamingStubURLProtocol.reset()
        super.tearDown()
    }

    func testStreamsIncrementalChunksOnTheValidatedRelativeRoute() async throws {
        let first = Data("event: status\n".utf8)
        let second = Data("data: {\"run_id\":\"run-1\"}\n\n".utf8)
        StreamingStubURLProtocol.plan = .open(statusCode: 200)
        StreamingStubURLProtocol.requestObserver = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://provider.example.com/api/v1/runs/run-1/events"
            )
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer private-token")
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        }

        let response = try await transport().stream(
            try ProviderRequest(method: .get, relativePath: "/v1/runs/run-1/events"),
            to: hostedEndpoint("https://provider.example.com/api"),
            credential: ProviderCredential(bytes: Data("private-token".utf8))
        )

        XCTAssertEqual(response.statusCode, 200)
        var iterator = response.bytes.makeAsyncIterator()
        StreamingStubURLProtocol.deliver(first)
        let firstDeliveredChunk = try await iterator.next()
        XCTAssertEqual(firstDeliveredChunk, first)
        StreamingStubURLProtocol.deliver(second)
        let secondDeliveredChunk = try await iterator.next()
        XCTAssertEqual(secondDeliveredChunk, second)
        StreamingStubURLProtocol.finish()
        let completion = try await iterator.next()
        XCTAssertNil(completion)
    }

    func testSplitsNetworkDeliveryAtConfiguredChunkLimit() async throws {
        StreamingStubURLProtocol.plan = .complete(
            statusCode: 200,
            chunks: [Data([0, 1, 2, 3, 4])]
        )
        let policy = try HermesEventStreamingTransportPolicy(
            maximumBufferedChunks: 4,
            maximumChunkBytes: 2,
            requestTimeout: 1,
            resourceTimeout: 2
        )
        let response = try await transport(policy: policy).stream(
            try ProviderRequest(method: .get, relativePath: "/v1/events"),
            to: hostedEndpoint("https://provider.example.com"),
            credential: nil
        )

        var chunks: [Data] = []
        for try await chunk in response.bytes {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks, [Data([0, 1]), Data([2, 3]), Data([4])])
    }

    func testFailsClosedWhenFiniteConsumerBufferOverflows() async throws {
        let policy = try HermesEventStreamingTransportPolicy(
            maximumBufferedChunks: 1,
            maximumChunkBytes: 1,
            requestTimeout: 1,
            resourceTimeout: 2
        )
        let delegate = HermesStreamingSessionDelegate(
            origin: Origin(URL(string: "https://provider.example.com")!),
            policy: policy
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: URL(string: "https://provider.example.com/v1/events")!)
        delegate.attach(session: session, task: task)
        let responseBytes = try delegate.takeResponseBytes()
        delegate.urlSession(session, dataTask: task, didReceive: Data([0, 1, 2]))

        do {
            for try await _ in responseBytes {}
            XCTFail("Expected bounded stream overflow")
        } catch {
            XCTAssertEqual(
                error as? URLSessionHermesEventStreamingTransportError,
                .streamBufferExceeded(limit: 1)
            )
        }
    }

    func testRejectsInvalidBearerWithoutStartingNetworkWork() async throws {
        do {
            _ = try await transport().stream(
                try ProviderRequest(method: .get, relativePath: "/v1/events"),
                to: hostedEndpoint("https://provider.example.com"),
                credential: ProviderCredential(bytes: Data("token\r\nInjected: true".utf8))
            )
            XCTFail("Expected invalid credential")
        } catch {
            XCTAssertEqual(
                error as? URLSessionHermesEventStreamingTransportError,
                .invalidCredential
            )
        }
        XCTAssertEqual(StreamingStubURLProtocol.startCount, 0)
    }

    func testMapsNetworkFailureWithoutLeakingRequestDetails() async throws {
        StreamingStubURLProtocol.plan = .failure(URLError(.timedOut))
        do {
            _ = try await transport().stream(
                try ProviderRequest(method: .get, relativePath: "/v1/events"),
                to: hostedEndpoint("https://provider.example.com"),
                credential: nil
            )
            XCTFail("Expected mapped network failure")
        } catch {
            XCTAssertEqual(
                error as? URLSessionHermesEventStreamingTransportError,
                .network(code: .timedOut)
            )
        }
    }

    func testConsumerCancellationStopsUnderlyingURLSessionTask() async throws {
        StreamingStubURLProtocol.plan = .open(statusCode: 200)
        let response = try await transport().stream(
            try ProviderRequest(method: .get, relativePath: "/v1/events"),
            to: hostedEndpoint("https://provider.example.com"),
            credential: nil
        )

        let consumer = Task {
            for try await _ in response.bytes {}
        }
        await Task.yield()
        consumer.cancel()
        _ = await consumer.result

        for _ in 0..<100 where StreamingStubURLProtocol.stopCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(StreamingStubURLProtocol.stopCount, 0)
    }

    func testRejectsInvalidPolicyValues() {
        XCTAssertThrowsError(try HermesEventStreamingTransportPolicy(maximumBufferedChunks: 0))
        XCTAssertThrowsError(try HermesEventStreamingTransportPolicy(maximumChunkBytes: 0))
        XCTAssertThrowsError(try HermesEventStreamingTransportPolicy(requestTimeout: 0))
        XCTAssertThrowsError(
            try HermesEventStreamingTransportPolicy(requestTimeout: 2, resourceTimeout: 1)
        )
    }

    private func transport(
        policy: HermesEventStreamingTransportPolicy = .secureDefault
    ) -> URLSessionHermesEventStreamingTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingStubURLProtocol.self]
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = policy.requestTimeout
        configuration.timeoutIntervalForResource = policy.resourceTimeout
        return URLSessionHermesEventStreamingTransport(
            policy: policy,
            configuration: configuration
        )
    }

    private func hostedEndpoint(_ value: String) throws -> ValidatedEndpoint {
        try EndpointValidator.validate(
            value,
            declaredBoundary: .hosted,
            hostedAccess: .granted
        )
    }
}

private final class StreamingStubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Plan {
        case complete(statusCode: Int, chunks: [Data])
        case open(statusCode: Int)
        case failure(Error)
    }

    private static let storage = StreamingStubStorage()

    static var plan: Plan? {
        get { storage.plan }
        set { storage.plan = newValue }
    }

    static var requestObserver: ((URLRequest) -> Void)? {
        get { storage.requestObserver }
        set { storage.requestObserver = newValue }
    }

    static var startCount: Int { storage.startCount }
    static var stopCount: Int { storage.stopCount }

    static func deliver(_ data: Data) {
        guard let activeProtocol = storage.activeProtocol else { return }
        activeProtocol.client?.urlProtocol(activeProtocol, didLoad: data)
    }

    static func finish() {
        guard let activeProtocol = storage.activeProtocol else { return }
        activeProtocol.client?.urlProtocolDidFinishLoading(activeProtocol)
    }

    static func reset() {
        storage.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.storage.didStart()
        Self.storage.activeProtocol = self
        Self.requestObserver?(request)
        guard let plan = Self.plan else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        switch plan {
        case let .complete(statusCode, chunks):
            publishResponse(statusCode: statusCode)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        case let .open(statusCode):
            publishResponse(statusCode: statusCode)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        Self.storage.didStop()
    }

    private func publishResponse(statusCode: Int) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
}

private final class StreamingStubStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedPlan: StreamingStubURLProtocol.Plan?
    private var storedRequestObserver: ((URLRequest) -> Void)?
    private var storedStartCount = 0
    private var storedStopCount = 0
    private weak var storedActiveProtocol: StreamingStubURLProtocol?

    var plan: StreamingStubURLProtocol.Plan? {
        get { lock.withLock { storedPlan } }
        set { lock.withLock { storedPlan = newValue } }
    }

    var requestObserver: ((URLRequest) -> Void)? {
        get { lock.withLock { storedRequestObserver } }
        set { lock.withLock { storedRequestObserver = newValue } }
    }

    var startCount: Int { lock.withLock { storedStartCount } }
    var stopCount: Int { lock.withLock { storedStopCount } }

    var activeProtocol: StreamingStubURLProtocol? {
        get { lock.withLock { storedActiveProtocol } }
        set { lock.withLock { storedActiveProtocol = newValue } }
    }

    func didStart() {
        lock.withLock { storedStartCount += 1 }
    }

    func didStop() {
        lock.withLock { storedStopCount += 1 }
    }

    func reset() {
        lock.withLock {
            storedPlan = nil
            storedRequestObserver = nil
            storedStartCount = 0
            storedStopCount = 0
            storedActiveProtocol = nil
        }
    }
}
