import Foundation

/// A redacted classification supplied by a Network.framework adapter when a
/// connection fails. Deliberately excludes endpoints, certificate details,
/// request bytes, and underlying error text.
public enum NetworkConnectionFailure: String, Error, Sendable, Equatable {
    case dnsResolution
    case tlsHandshake
    case connectionRefused
    case connectionReset
    case networkUnavailable
    case unknown
}

/// A redacted classification supplied by the HTTP/SSE codec when received
/// bytes cannot be accepted safely.
public enum NetworkProtocolFailure: String, Error, Sendable, Equatable {
    case malformedStatusLine
    case invalidHeader
    case unsupportedFraming
    case bodyLimitExceeded
    case unexpectedEndOfStream
    case unknown
}

/// Terminal errors exposed to callers. These cases intentionally carry no
/// URLs, headers, response bodies, credentials, or arbitrary system strings.
public enum NetworkTerminalError: Error, Sendable, Equatable {
    case invalidBufferLimit
    case cancelled
    case timedOut
    case connection(NetworkConnectionFailure)
    case protocolFailure(NetworkProtocolFailure)
    case streamBufferExceeded(limit: Int)
    case completedWithoutResponse
    case responseAlreadyAwaited
    case streamAlreadyTaken
}

extension NetworkTerminalError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBufferLimit:
            return "The response buffer limit is invalid."
        case .cancelled:
            return "The network operation was cancelled."
        case .timedOut:
            return "The network operation timed out."
        case let .connection(reason):
            return "The network connection failed (\(reason.rawValue))."
        case let .protocolFailure(reason):
            return "The network response was rejected (\(reason.rawValue))."
        case let .streamBufferExceeded(limit):
            return "The bounded response buffer exceeded its \(limit)-element limit."
        case .completedWithoutResponse:
            return "The connection completed before a response was received."
        case .responseAlreadyAwaited:
            return "The response may only be awaited once."
        case .streamAlreadyTaken:
            return "The response stream may only be taken once."
        }
    }
}

public enum NetworkTerminalPhase: Sendable, Equatable {
    case awaitingResponse
    case streaming
    case terminal(NetworkTerminalResult)
}

public enum NetworkTerminalResult: Sendable, Equatable {
    case completed
    case failed(NetworkTerminalError)
}

public struct NetworkTerminalSnapshot: Sendable, Equatable {
    public let phase: NetworkTerminalPhase
    public let responsePublished: Bool
    public let connectionCancelInvoked: Bool

    public init(
        phase: NetworkTerminalPhase,
        responsePublished: Bool,
        connectionCancelInvoked: Bool
    ) {
        self.phase = phase
        self.responsePublished = responsePublished
        self.connectionCancelInvoked = connectionCancelInvoked
    }
}

public enum NetworkTerminalEventDisposition: Sendable, Equatable {
    case accepted
    case ignoredAfterTerminal
    case ignoredDuplicateResponse
    case rejectedBufferOverflow
}

/// Serializes response, byte-stream, timeout, task-cancellation, receive, and
/// Network.framework state callbacks into one terminal transition.
///
/// All mutable state is protected by `lock`. Continuations and the connection
/// cancellation closure are detached while holding the lock, then invoked
/// after it is released. Consequently re-entrant `onTermination` callbacks
/// cannot deadlock and no continuation or connection closure can be completed
/// twice.
public final class NetworkTerminalStateCoordinator<Response: Sendable, Element: Sendable>: @unchecked Sendable {
    private typealias ResponseContinuation = CheckedContinuation<Response, Error>
    private typealias StreamContinuation = AsyncThrowingStream<Element, Error>.Continuation

    private struct TerminalResources {
        let result: NetworkTerminalResult
        let responseContinuation: ResponseContinuation?
        let streamContinuation: StreamContinuation?
        let cancelConnection: (@Sendable () -> Void)?
    }

    private let lock = NSLock()
    private let stream: AsyncThrowingStream<Element, Error>
    private let streamBufferLimit: Int
    private var streamContinuation: StreamContinuation?
    private var responseContinuation: ResponseContinuation?
    private var responseValue: Response?
    private var responseAwaited = false
    private var streamTaken = false
    private var terminalResult: NetworkTerminalResult?
    private var cancelConnection: (@Sendable () -> Void)?
    private var connectionCancelInvoked = false

    public init(
        bufferingLimit: Int,
        cancelConnection: @escaping @Sendable () -> Void
    ) throws {
        guard bufferingLimit > 0 else {
            throw NetworkTerminalError.invalidBufferLimit
        }

        streamBufferLimit = bufferingLimit
        var createdContinuation: StreamContinuation?
        stream = AsyncThrowingStream(
            bufferingPolicy: .bufferingOldest(bufferingLimit)
        ) { continuation in
            createdContinuation = continuation
        }
        guard let createdContinuation else {
            throw NetworkTerminalError.protocolFailure(.unknown)
        }
        streamContinuation = createdContinuation
        self.cancelConnection = cancelConnection
        createdContinuation.onTermination = { @Sendable [weak self] _ in
            self?.cancel()
        }
    }

    public func takeStream() throws -> AsyncThrowingStream<Element, Error> {
        try lock.withLock {
            guard !streamTaken else {
                throw NetworkTerminalError.streamAlreadyTaken
            }
            streamTaken = true
            return stream
        }
    }

    public func awaitResponse() async throws -> Response {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let immediate: Result<Response, Error>? = lock.withLock {
                    guard !responseAwaited else {
                        return .failure(NetworkTerminalError.responseAlreadyAwaited)
                    }
                    responseAwaited = true

                    if let responseValue {
                        return .success(responseValue)
                    }
                    if let terminalResult {
                        switch terminalResult {
                        case .completed:
                            return .failure(NetworkTerminalError.completedWithoutResponse)
                        case let .failed(error):
                            return .failure(error)
                        }
                    }

                    responseContinuation = continuation
                    return nil
                }

                if let immediate {
                    continuation.resume(with: immediate)
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    @discardableResult
    public func publishResponse(_ response: Response) -> NetworkTerminalEventDisposition {
        let result: (NetworkTerminalEventDisposition, ResponseContinuation?) = lock.withLock {
            guard terminalResult == nil else {
                return (.ignoredAfterTerminal, nil)
            }
            guard responseValue == nil else {
                return (.ignoredDuplicateResponse, nil)
            }
            responseValue = response
            let continuation = responseContinuation
            responseContinuation = nil
            return (.accepted, continuation)
        }
        result.1?.resume(returning: response)
        return result.0
    }

    @discardableResult
    public func receive(_ element: Element) -> NetworkTerminalEventDisposition {
        var resources: TerminalResources?
        let disposition: NetworkTerminalEventDisposition = lock.withLock {
            guard terminalResult == nil else { return .ignoredAfterTerminal }
            guard responseValue != nil else {
                resources = transitionLocked(
                    to: .failed(.protocolFailure(.unexpectedEndOfStream))
                )
                return .ignoredAfterTerminal
            }
            guard let streamContinuation else { return .ignoredAfterTerminal }

            switch streamContinuation.yield(element) {
            case .enqueued:
                return .accepted
            case .dropped:
                resources = transitionLocked(
                    to: .failed(.streamBufferExceeded(limit: streamBufferLimit))
                )
                return .rejectedBufferOverflow
            case .terminated:
                return .ignoredAfterTerminal
            @unknown default:
                resources = transitionLocked(
                    to: .failed(.protocolFailure(.unknown))
                )
                return .ignoredAfterTerminal
            }
        }
        complete(resources)
        return disposition
    }

    @discardableResult
    public func finish() -> Bool {
        let resources: TerminalResources? = lock.withLock {
            let result: NetworkTerminalResult = responseValue == nil
                ? .failed(.completedWithoutResponse)
                : .completed
            return transitionLocked(to: result)
        }
        complete(resources)
        return resources != nil
    }

    @discardableResult
    public func fail(_ error: NetworkTerminalError) -> Bool {
        terminate(.failed(error))
    }

    @discardableResult
    public func cancel() -> Bool {
        terminate(.failed(.cancelled))
    }

    @discardableResult
    public func timeout() -> Bool {
        terminate(.failed(.timedOut))
    }

    public func snapshot() -> NetworkTerminalSnapshot {
        lock.withLock {
            let phase: NetworkTerminalPhase
            if let terminalResult {
                phase = .terminal(terminalResult)
            } else if responseValue == nil {
                phase = .awaitingResponse
            } else {
                phase = .streaming
            }
            return NetworkTerminalSnapshot(
                phase: phase,
                responsePublished: responseValue != nil,
                connectionCancelInvoked: connectionCancelInvoked
            )
        }
    }

    private func terminate(_ result: NetworkTerminalResult) -> Bool {
        let resources: TerminalResources? = lock.withLock {
            transitionLocked(to: result)
        }
        complete(resources)
        return resources != nil
    }

    private func transitionLocked(to result: NetworkTerminalResult) -> TerminalResources? {
        guard terminalResult == nil else { return nil }
        terminalResult = result

        let resources = TerminalResources(
            result: result,
            responseContinuation: responseContinuation,
            streamContinuation: streamContinuation,
            cancelConnection: cancelConnection
        )
        responseContinuation = nil
        streamContinuation = nil
        cancelConnection = nil
        connectionCancelInvoked = resources.cancelConnection != nil
        return resources
    }

    private func complete(_ resources: TerminalResources?) {
        guard let resources else { return }

        switch resources.result {
        case .completed:
            resources.streamContinuation?.finish()
        case let .failed(error):
            resources.responseContinuation?.resume(throwing: error)
            resources.streamContinuation?.finish(throwing: error)
        }
        resources.cancelConnection?()
    }
}
