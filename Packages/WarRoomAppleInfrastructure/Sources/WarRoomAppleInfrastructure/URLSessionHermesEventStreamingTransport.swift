import Foundation
import WarRoomCore
import WarRoomHermes

/// Resource limits for a live Hermes event response.
public struct HermesEventStreamingTransportPolicy: Equatable, Sendable {
    /// Maximum number of unread chunks retained between URLSession and the consumer.
    public let maximumBufferedChunks: Int
    /// Maximum size of an individual chunk delivered to the consumer.
    public let maximumChunkBytes: Int
    /// Timeout applied while waiting for network activity.
    public let requestTimeout: TimeInterval
    /// Maximum lifetime of one event stream.
    public let resourceTimeout: TimeInterval

    /// Creates a bounded event-stream policy.
    public init(
        maximumBufferedChunks: Int = 8,
        maximumChunkBytes: Int = 16 * 1_024,
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 60 * 60
    ) throws {
        guard maximumBufferedChunks > 0,
              maximumChunkBytes > 0,
              requestTimeout > 0,
              resourceTimeout >= requestTimeout else {
            throw HermesEventStreamingTransportPolicyError.invalidLimits
        }
        self.maximumBufferedChunks = maximumBufferedChunks
        self.maximumChunkBytes = maximumChunkBytes
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }

    /// Conservative defaults for an interactive, long-lived SSE response.
    public static let secureDefault = HermesEventStreamingTransportPolicy(
        validatedMaximumBufferedChunks: 8,
        maximumChunkBytes: 16 * 1_024,
        requestTimeout: 30,
        resourceTimeout: 60 * 60
    )

    private init(
        validatedMaximumBufferedChunks: Int,
        maximumChunkBytes: Int,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) {
        self.maximumBufferedChunks = validatedMaximumBufferedChunks
        self.maximumChunkBytes = maximumChunkBytes
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }
}

/// Invalid event-stream limits rejected before a transport is created.
public enum HermesEventStreamingTransportPolicyError: Error, Equatable, Sendable {
    case invalidLimits
}

/// Non-sensitive failures emitted by the concrete Hermes streaming transport.
public enum URLSessionHermesEventStreamingTransportError: Error, Equatable, Sendable {
    /// The request path could not be safely appended to the validated endpoint.
    case invalidRelativePath
    /// Credential bytes were empty, invalid UTF-8, or unsafe for an HTTP header.
    case invalidCredential
    /// The server did not return an HTTP response.
    case invalidResponse
    /// A redirect attempted to change scheme, host, or effective port.
    case redirectedAcrossOrigin
    /// The consumer did not drain the finite stream buffer quickly enough.
    case streamBufferExceeded(limit: Int)
    /// URL Loading System returned a network failure.
    case network(code: URLError.Code)
}

/// Incremental, cookie-free Hermes SSE transport restricted to one validated origin.
public struct URLSessionHermesEventStreamingTransport: HermesEventStreamingTransport, @unchecked Sendable {
    private let policy: HermesEventStreamingTransportPolicy
    private let configuration: URLSessionConfiguration

    /// Creates a scoped transport using an ephemeral URL session.
    public init(policy: HermesEventStreamingTransportPolicy = .secureDefault) {
        self.policy = policy
        self.configuration = Self.makeEphemeralConfiguration(policy: policy)
    }

    init(
        policy: HermesEventStreamingTransportPolicy,
        configuration: URLSessionConfiguration
    ) {
        self.policy = policy
        self.configuration = configuration
    }

    /// Opens a response and returns its body as incrementally delivered bounded chunks.
    public func stream(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> HermesProviderByteStream {
        try Task.checkCancellation()
        let destination = try makeDestination(for: request, endpoint: endpoint)
        var urlRequest = URLRequest(
            url: destination,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: policy.requestTimeout
        )
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let credential {
            urlRequest.setValue(
                "Bearer \(try bearerValue(from: credential))",
                forHTTPHeaderField: "Authorization"
            )
        }

        let delegate = HermesStreamingSessionDelegate(
            origin: Origin(endpoint.url),
            policy: policy
        )
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: urlRequest)
        delegate.attach(session: session, task: task)
        task.resume()

        do {
            let response = try await delegate.awaitResponse()
            try Task.checkCancellation()
            return HermesProviderByteStream(
                statusCode: response.statusCode,
                bytes: try delegate.takeResponseBytes()
            )
        } catch {
            delegate.cancel()
            throw error
        }
    }

    private func makeDestination(
        for request: ProviderRequest,
        endpoint: ValidatedEndpoint
    ) throws -> URL {
        let decodedPath = request.relativePath.removingPercentEncoding ?? request.relativePath
        guard !decodedPath.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !decodedPath.contains("\\"),
              !decodedPath.hasPrefix("//") else {
            throw URLSessionHermesEventStreamingTransportError.invalidRelativePath
        }
        guard var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false) else {
            throw URLSessionHermesEventStreamingTransportError.invalidRelativePath
        }
        let basePath = components.percentEncodedPath.hasSuffix("/")
            ? String(components.percentEncodedPath.dropLast())
            : components.percentEncodedPath
        components.percentEncodedPath = basePath + request.relativePath
        components.queryItems = request.queryItems.isEmpty ? nil : request.queryItems.map {
            URLQueryItem(name: $0.name, value: $0.value)
        }
        components.fragment = nil
        guard let destination = components.url,
              Origin(destination) == Origin(endpoint.url) else {
            throw URLSessionHermesEventStreamingTransportError.invalidRelativePath
        }
        return destination
    }

    private func bearerValue(from credential: ProviderCredential) throws -> String {
        let data = credential.withUnsafeBytes { Data($0) }
        guard !data.isEmpty,
              !data.contains(0x0A),
              !data.contains(0x0D),
              data.allSatisfy({ $0 >= 0x20 && $0 != 0x7F }),
              let value = String(data: data, encoding: .utf8) else {
            throw URLSessionHermesEventStreamingTransportError.invalidCredential
        }
        return value
    }

    private static func makeEphemeralConfiguration(
        policy: HermesEventStreamingTransportPolicy
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = policy.requestTimeout
        configuration.timeoutIntervalForResource = policy.resourceTimeout
        configuration.waitsForConnectivity = false
        return configuration
    }
}

final class HermesStreamingSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let origin: Origin
    private let maximumChunkBytes: Int
    private let maximumBufferedChunks: Int
    private let lock = NSLock()
    private var blockedRedirect = false
    private var responseContinuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var responseResult: Result<HTTPURLResponse, Error>?
    private weak var session: URLSession?
    private weak var task: URLSessionTask?
    private var storedResponseBytes: AsyncThrowingStream<Data, Error>?
    private var byteContinuation: AsyncThrowingStream<Data, Error>.Continuation?

    init(origin: Origin, policy: HermesEventStreamingTransportPolicy) {
        self.origin = origin
        self.maximumChunkBytes = policy.maximumChunkBytes
        self.maximumBufferedChunks = policy.maximumBufferedChunks
        var createdContinuation: AsyncThrowingStream<Data, Error>.Continuation?
        self.storedResponseBytes = AsyncThrowingStream(
            bufferingPolicy: .bufferingOldest(policy.maximumBufferedChunks)
        ) { continuation in
            createdContinuation = continuation
        }
        self.byteContinuation = createdContinuation
        super.init()
        self.byteContinuation?.onTermination = { @Sendable [weak self] _ in self?.cancel() }
    }

    func attach(session: URLSession, task: URLSessionTask) {
        lock.withLock {
            self.session = session
            self.task = task
        }
    }

    func takeResponseBytes() throws -> AsyncThrowingStream<Data, Error> {
        try lock.withLock {
            guard let responseBytes = storedResponseBytes else {
                throw URLSessionHermesEventStreamingTransportError.invalidResponse
            }
            storedResponseBytes = nil
            return responseBytes
        }
    }

    func awaitResponse() async throws -> HTTPURLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let immediateResult = lock.withLock { () -> Result<HTTPURLResponse, Error>? in
                    if let responseResult { return responseResult }
                    responseContinuation = continuation
                    return nil
                }
                if let immediateResult {
                    continuation.resume(with: immediateResult)
                }
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        let resources = lock.withLock { () -> (URLSessionTask?, URLSession?, CheckedContinuation<HTTPURLResponse, Error>?, AsyncThrowingStream<Data, Error>.Continuation?) in
            let resources = (task, session, responseContinuation, byteContinuation)
            responseContinuation = nil
            if responseResult == nil {
                responseResult = .failure(CancellationError())
            }
            byteContinuation = nil
            return resources
        }
        resources.2?.resume(throwing: CancellationError())
        resources.3?.finish(throwing: CancellationError())
        resources.0?.cancel()
        resources.1?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let destination = request.url, Origin(destination) == origin else {
            lock.withLock { blockedRedirect = true }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let isBlocked = lock.withLock { blockedRedirect }
        guard !isBlocked else {
            finish(URLSessionHermesEventStreamingTransportError.redirectedAcrossOrigin)
            completionHandler(.cancel)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            finish(URLSessionHermesEventStreamingTransportError.invalidResponse)
            completionHandler(.cancel)
            return
        }
        publish(httpResponse)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var offset = 0
        while offset < data.count {
            let end = min(offset + maximumChunkBytes, data.count)
            let chunk = data.subdata(in: offset..<end)
            guard let continuation = lock.withLock({ byteContinuation }) else { return }
            switch continuation.yield(chunk) {
            case .enqueued:
                offset = end
            case .dropped, .terminated:
                finish(URLSessionHermesEventStreamingTransportError.streamBufferExceeded(
                    limit: maximumBufferedChunks
                ))
                return
            @unknown default:
                finish(URLSessionHermesEventStreamingTransportError.streamBufferExceeded(
                    limit: maximumBufferedChunks
                ))
                return
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            let isBlocked = lock.withLock { blockedRedirect }
            if isBlocked {
                finish(URLSessionHermesEventStreamingTransportError.redirectedAcrossOrigin)
            } else if let urlError = error as? URLError {
                finish(URLSessionHermesEventStreamingTransportError.network(code: urlError.code))
            } else {
                finish(URLSessionHermesEventStreamingTransportError.invalidResponse)
            }
        } else {
            complete()
        }
    }

    private func publish(_ response: HTTPURLResponse) {
        let continuation = lock.withLock { () -> CheckedContinuation<HTTPURLResponse, Error>? in
            guard responseResult == nil else { return nil }
            responseResult = .success(response)
            let continuation = responseContinuation
            responseContinuation = nil
            return continuation
        }
        continuation?.resume(returning: response)
    }

    private func complete() {
        let continuation = lock.withLock { () -> AsyncThrowingStream<Data, Error>.Continuation? in
            let continuation = byteContinuation
            byteContinuation = nil
            return continuation
        }
        continuation?.finish()
        session?.finishTasksAndInvalidate()
    }

    private func finish(_ error: Error) {
        let continuations = lock.withLock { () -> (CheckedContinuation<HTTPURLResponse, Error>?, AsyncThrowingStream<Data, Error>.Continuation?) in
            if responseResult == nil {
                responseResult = .failure(error)
            }
            let continuations = (responseContinuation, byteContinuation)
            responseContinuation = nil
            byteContinuation = nil
            return continuations
        }
        continuations.0?.resume(throwing: error)
        continuations.1?.finish(throwing: error)
        task?.cancel()
        session?.invalidateAndCancel()
    }
}
