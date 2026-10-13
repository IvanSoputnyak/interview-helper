import Foundation
import Network
import os

/// Progress reported while a request is being retried after a transient failure.
public enum RetryEvent: Sendable, Equatable {
    case waitingForNetwork
    case retrying(attempt: Int, of: Int)

    /// Short status line for the menu bar / buttons.
    public var displayText: String {
        switch self {
        case .waitingForNetwork:
            return "Waiting for network…"
        case .retrying(let attempt, let total):
            return "Reconnecting (\(attempt)/\(total))…"
        }
    }
}

public typealias RetryObserver = @MainActor @Sendable (RetryEvent) -> Void

struct RetryPolicy: Sendable {
    static let standard = RetryPolicy(maxRetries: 3, maxTimeoutRetries: 1, baseDelay: 1, maxDelay: 8, networkWaitTimeout: 30)

    let maxRetries: Int
    /// Timeouts get a smaller budget: a reasoning model is silent until it answers, so a timed-out request
    /// already waited the full request timeout (and may still be billed); retrying it 3× could take ~12 min.
    let maxTimeoutRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let networkWaitTimeout: TimeInterval

    private static let transientURLErrorCodes: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
    ]
    private static let offlineURLErrorCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
    ]
    private static let transientHTTPStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]
    private static let gatewayTimeoutStatus = 504
    /// OpenAI answers 429 both for rate limits (transient) and for an empty balance (permanent).
    private static let quotaExhaustedMarker = "insufficient_quota"

    /// Exponential backoff for the 1-based `retry`: `baseDelay · 2^(retry-1)`, capped at `maxDelay`.
    func delay(beforeRetry retry: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2, Double(retry - 1))
        return min(exponential, maxDelay)
    }

    static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return transientURLErrorCodes.contains(urlError.code)
        }
        guard case let OpenAIAnalyzer.AnalyzerError.httpStatus(code, body) = error else {
            return false
        }
        return transientHTTPStatuses.contains(code) && !body.contains(quotaExhaustedMarker)
    }

    /// Failures that arrive only after a long wait: a client timeout or an upstream gateway timeout.
    static func isTimeout(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
        }
        guard case let OpenAIAnalyzer.AnalyzerError.httpStatus(code, _) = error else {
            return false
        }
        return code == gatewayTimeoutStatus
    }

    static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }
        return offlineURLErrorCodes.contains(urlError.code)
    }
}

/// Runs `operation`, retrying transient failures per `policy`. When offline, first waits for the
/// network to return; if it does not within `policy.networkWaitTimeout`, the original error is thrown.
/// `sleep` and `waitForNetwork` are injectable so tests need no real clock or network.
func withRetry<T>(
    policy: RetryPolicy = .standard,
    onRetry: RetryObserver? = nil,
    sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
    waitForNetwork: @Sendable (TimeInterval) async -> Bool = NetworkAvailability.waitUntilOnline,
    operation: () async throws -> T
) async throws -> T {
    var retry = 0
    var timeoutRetries = 0
    while true {
        do {
            return try await operation()
        } catch {
            guard retry < policy.maxRetries, RetryPolicy.isTransient(error) else {
                throw error
            }
            if RetryPolicy.isTimeout(error) {
                guard timeoutRetries < policy.maxTimeoutRetries else {
                    throw error
                }
                timeoutRetries += 1
            }
            retry += 1
            if RetryPolicy.isOffline(error) {
                await onRetry?(.waitingForNetwork)
                guard await waitForNetwork(policy.networkWaitTimeout) else {
                    throw error
                }
            }
            await onRetry?(.retrying(attempt: retry, of: policy.maxRetries))
            try await sleep(policy.delay(beforeRetry: retry))
        }
    }
}

enum NetworkAvailability {
    /// Returns `true` as soon as the system reports a usable network path, `false` after `timeout`.
    static func waitUntilOnline(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "\(KeychainStore.service).network-wait")
            let finished = OSAllocatedUnfairLock(initialState: false)

            @Sendable func finish(online: Bool) {
                let isFirst = finished.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                guard isFirst else { return }
                monitor.cancel()
                continuation.resume(returning: online)
            }

            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied {
                    finish(online: true)
                }
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(online: false)
            }
        }
    }
}
