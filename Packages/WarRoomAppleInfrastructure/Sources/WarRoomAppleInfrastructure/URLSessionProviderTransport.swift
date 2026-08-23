import Foundation
import WarRoomCore

/// Resource and timeout limits for provider requests.
public struct ProviderTransportPolicy: Equatable, Sendable {
    /// Maximum request body size in bytes.
    public let maximumRequestBodyBytes: Int
    /// Maximum response body size in bytes.
    public let maximumResponseBodyBytes: Int
    /// Timeout applied to an individual request.
    public let requestTimeout: TimeInterval
    /// Maximum resource lifetime, including redirects and transfer.
    public let resourceTimeout: TimeInterval

    /// Creates bounded transport policy values.
    public init(
        maximumRequestBodyBytes: Int = 2 * 1_024 * 1_024,
        maximumResponseBodyBytes: Int = 10 * 1_024 * 1_024,
        requestTimeout: TimeInterval = 30,
        resourceTimeout: TimeInterval = 60
    ) throws {
        guard maximumRequestBodyBytes >= 0,
              maximumResponseBodyBytes >= 0,
              requestTimeout > 0,
              resourceTimeout >= requestTimeout else {
            throw ProviderTransportPolicyError.invalidLimits
        }
        self.maximumRequestBodyBytes = maximumRequestBodyBytes
        self.maximumResponseBodyBytes = maximumResponseBodyBytes
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }

    /// Conservative defaults for interactive provider traffic.
    public static let secureDefault = ProviderTransportPolicy(
        validatedMaximumRequestBodyBytes: 2 * 1_024 * 1_024,
        maximumResponseBodyBytes: 10 * 1_024 * 1_024,
        requestTimeout: 30,
        resourceTimeout: 60
    )

    private init(
        validatedMaximumRequestBodyBytes: Int,
        maximumResponseBodyBytes: Int,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) {
        self.maximumRequestBodyBytes = validatedMaximumRequestBodyBytes
        self.maximumResponseBodyBytes = maximumResponseBodyBytes
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
    }
}

/// Invalid resource limits rejected before a transport is created.
public enum ProviderTransportPolicyError: Error, Equatable, Sendable {
    case invalidLimits
}

/// Errors produced before, during, or after scoped provider transport.
public enum URLSessionProviderTransportError: Error, Equatable, Sendable {
    /// The request path could not be safely appended to the validated endpoint.
    case invalidRelativePath
    /// Credential bytes were empty, invalid UTF-8, or unsafe for an HTTP header.
    case invalidCredential
    /// The outgoing body exceeded the configured byte limit.
    case requestBodyTooLarge(limit: Int)
    /// The incoming body exceeded the configured byte limit.
    case responseBodyTooLarge(limit: Int)
    /// The server did not return an HTTP response.
    case invalidResponse
    /// A redirect attempted to change scheme, host, or effective port.
    case redirectedAcrossOrigin
    /// URL Loading System returned a network failure.
    case network(code: URLError.Code)
}

/// A cookie-free, cache-free provider transport restricted to a validated endpoint origin.
public struct URLSessionProviderTransport: ProviderTransport, @unchecked Sendable {
    private let policy: ProviderTransportPolicy
    private let configuration: URLSessionConfiguration

    /// Creates a scoped transport using an ephemeral URL session.
    public init(policy: ProviderTransportPolicy = .secureDefault) {
        self.policy = policy
        self.configuration = Self.makeEphemeralConfiguration(policy: policy)
    }

    init(
        policy: ProviderTransportPolicy,
        configuration: URLSessionConfiguration
    ) {
        self.policy = policy
        self.configuration = configuration
    }

    /// Sends one bounded request without retaining credentials, cookies, or cached responses.
    public func send(
        _ request: ProviderRequest,
        to endpoint: ValidatedEndpoint,
        credential: ProviderCredential?
    ) async throws -> ProviderResponse {
        if let body = request.body, body.count > policy.maximumRequestBodyBytes {
            throw URLSessionProviderTransportError.requestBodyTooLarge(
                limit: policy.maximumRequestBodyBytes
            )
        }

        let destination = try makeDestination(for: request, endpoint: endpoint)
        var urlRequest = URLRequest(
            url: destination,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: policy.requestTimeout
        )
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = false
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let credential {
            let bearer = try bearerValue(from: credential)
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }

        let redirectGuard = RedirectGuard(origin: Origin(endpoint.url))
        let session = URLSession(configuration: configuration, delegate: redirectGuard, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest, delegate: redirectGuard)
            if redirectGuard.blockedCrossOriginRedirect {
                throw URLSessionProviderTransportError.redirectedAcrossOrigin
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLSessionProviderTransportError.invalidResponse
            }

            var body = Data()
            body.reserveCapacity(min(
                httpResponse.expectedContentLength > 0
                    ? Int(httpResponse.expectedContentLength)
                    : 0,
                policy.maximumResponseBodyBytes
            ))
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < policy.maximumResponseBodyBytes else {
                    throw URLSessionProviderTransportError.responseBodyTooLarge(
                        limit: policy.maximumResponseBodyBytes
                    )
                }
                body.append(byte)
            }
            return ProviderResponse(statusCode: httpResponse.statusCode, body: body)
        } catch let error as URLSessionProviderTransportError {
            throw error
        } catch let error as URLError {
            if redirectGuard.blockedCrossOriginRedirect {
                throw URLSessionProviderTransportError.redirectedAcrossOrigin
            }
            throw URLSessionProviderTransportError.network(code: error.code)
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
            throw URLSessionProviderTransportError.invalidRelativePath
        }
        guard var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false) else {
            throw URLSessionProviderTransportError.invalidRelativePath
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
            throw URLSessionProviderTransportError.invalidRelativePath
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
            throw URLSessionProviderTransportError.invalidCredential
        }
        return value
    }

    private static func makeEphemeralConfiguration(
        policy: ProviderTransportPolicy
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

struct Origin: Equatable, Sendable {
    let scheme: String
    let host: String
    let port: Int

    init(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        self.scheme = scheme
        self.host = url.host?.lowercased() ?? ""
        self.port = url.port ?? (scheme == "https" ? 443 : 80)
    }
}

final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let origin: Origin
    private let lock = NSLock()
    private var blockedRedirect = false

    init(origin: Origin) {
        self.origin = origin
    }

    var blockedCrossOriginRedirect: Bool {
        lock.withLock { blockedRedirect }
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
}
