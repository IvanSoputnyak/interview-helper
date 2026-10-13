import Foundation
import os
import Testing
@testable import InterviewHelperCore

typealias AnalyzerError = OpenAIAnalyzer.AnalyzerError

/// Records injected sleeps / network waits so retry tests never touch the real clock or network.
private final class FakeEnvironment: Sendable {
    private let sleeps = OSAllocatedUnfairLock(initialState: [TimeInterval]())
    private let networkWaits = OSAllocatedUnfairLock(initialState: 0)
    let networkReturns: Bool

    init(networkReturns: Bool = true) {
        self.networkReturns = networkReturns
    }

    var recordedSleeps: [TimeInterval] { sleeps.withLock { $0 } }
    var networkWaitCount: Int { networkWaits.withLock { $0 } }

    @Sendable func sleep(_ seconds: TimeInterval) async throws {
        sleeps.withLock { $0.append(seconds) }
    }

    @Sendable func waitForNetwork(_ timeout: TimeInterval) async -> Bool {
        networkWaits.withLock { $0 += 1 }
        return networkReturns
    }
}

@MainActor
private final class EventLog {
    var events: [RetryEvent] = []
}

/// Operation that throws `failures` in order, then returns `"ok"`.
private final class ScriptedOperation {
    private var failures: [Error]
    private(set) var attempts = 0

    init(failures: [Error]) {
        self.failures = failures
    }

    func run() async throws -> String {
        attempts += 1
        if failures.isEmpty {
            return "ok"
        }
        throw failures.removeFirst()
    }
}

private func runWithRetry(
    _ operation: ScriptedOperation,
    environment: FakeEnvironment = FakeEnvironment(),
    policy: RetryPolicy = .standard,
    onRetry: RetryObserver? = nil
) async throws -> String {
    try await withRetry(
        policy: policy,
        onRetry: onRetry,
        sleep: environment.sleep,
        waitForNetwork: environment.waitForNetwork,
        operation: operation.run
    )
}

@Suite("RetryPolicy classification")
struct RetryPolicyClassificationTests {
    @Test(arguments: [URLError.Code.timedOut, .networkConnectionLost, .notConnectedToInternet, .dataNotAllowed, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed])
    func test_isTransient_whenURLErrorIsConnectivityFailure_returnsTrue(code: URLError.Code) {
        #expect(RetryPolicy.isTransient(URLError(code)))
    }

    @Test(arguments: [URLError.Code.cancelled, .badURL, .userAuthenticationRequired, .serverCertificateUntrusted])
    func test_isTransient_whenURLErrorIsNotConnectivityFailure_returnsFalse(code: URLError.Code) {
        #expect(!RetryPolicy.isTransient(URLError(code)))
    }

    @Test(arguments: [408, 429, 500, 502, 503, 504])
    func test_isTransient_whenHTTPStatusIsRetryable_returnsTrue(status: Int) {
        #expect(RetryPolicy.isTransient(AnalyzerError.httpStatus(status, "{}")))
    }

    @Test(arguments: [400, 401, 403, 404, 422, 501])
    func test_isTransient_whenHTTPStatusIsPermanent_returnsFalse(status: Int) {
        #expect(!RetryPolicy.isTransient(AnalyzerError.httpStatus(status, "{}")))
    }

    @Test func test_isTransient_when429IsInsufficientQuota_returnsFalse() {
        let body = #"{"error":{"code":"insufficient_quota","message":"You exceeded your current quota"}}"#
        #expect(!RetryPolicy.isTransient(AnalyzerError.httpStatus(429, body)))
    }

    @Test(arguments: [AnalyzerError.missingAPIKey, .invalidResponse, .refused("no"), .incomplete("max_output_tokens")])
    func test_isTransient_whenAnalyzerErrorIsNotHTTP_returnsFalse(error: AnalyzerError) {
        #expect(!RetryPolicy.isTransient(error))
    }

    @Test func test_isTransient_whenTaskWasCancelled_returnsFalse() {
        #expect(!RetryPolicy.isTransient(CancellationError()))
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed])
    func test_isOffline_whenURLErrorMeansNoNetwork_returnsTrue(code: URLError.Code) {
        #expect(RetryPolicy.isOffline(URLError(code)))
    }

    @Test func test_isTimeout_whenRequestTimedOut_returnsTrue() {
        #expect(RetryPolicy.isTimeout(URLError(.timedOut)))
    }

    @Test func test_isTimeout_whenConnectionLost_returnsFalse() {
        #expect(!RetryPolicy.isTimeout(URLError(.networkConnectionLost)))
    }

    @Test func test_isOffline_whenRequestTimedOut_returnsFalse() {
        #expect(!RetryPolicy.isOffline(URLError(.timedOut)))
    }

    @Test func test_isOffline_whenErrorIsHTTPStatus_returnsFalse() {
        #expect(!RetryPolicy.isOffline(AnalyzerError.httpStatus(503, "")))
    }
}

@Suite("RetryPolicy backoff")
struct RetryPolicyBackoffTests {
    @Test func test_delay_forFirstThreeRetries_doublesFromBaseDelay() {
        let delays = (1 ... 3).map { RetryPolicy.standard.delay(beforeRetry: $0) }
        #expect(delays == [1, 2, 4])
    }

    @Test func test_delay_whenExponentialExceedsCap_returnsMaxDelay() {
        #expect(RetryPolicy.standard.delay(beforeRetry: 10) == RetryPolicy.standard.maxDelay)
    }
}

@Suite("RetryEvent display text")
struct RetryEventDisplayTests {
    @Test func test_displayText_whenRetrying_showsAttemptAndTotal() {
        #expect(RetryEvent.retrying(attempt: 2, of: 3).displayText == "Reconnecting (2/3)…")
    }

    @Test func test_displayText_whenWaitingForNetwork_saysWaitingForNetwork() {
        #expect(RetryEvent.waitingForNetwork.displayText == "Waiting for network…")
    }
}

@Suite("withRetry")
struct WithRetryTests {
    @Test func test_withRetry_whenFirstAttemptSucceeds_doesNotSleep() async throws {
        let environment = FakeEnvironment()
        _ = try await runWithRetry(ScriptedOperation(failures: []), environment: environment)
        #expect(environment.recordedSleeps.isEmpty)
    }

    @Test func test_withRetry_whenTransientFailureThenSuccess_returnsResult() async throws {
        let result = try await runWithRetry(ScriptedOperation(failures: [URLError(.timedOut)]))
        #expect(result == "ok")
    }

    @Test func test_withRetry_whenTransientFailureThenSuccess_sleepsBaseDelayOnce() async throws {
        let environment = FakeEnvironment()
        _ = try await runWithRetry(ScriptedOperation(failures: [AnalyzerError.httpStatus(503, "")]), environment: environment)
        #expect(environment.recordedSleeps == [RetryPolicy.standard.baseDelay])
    }

    @Test func test_withRetry_whenAlwaysTransient_attemptsOncePlusMaxRetries() async {
        let operation = ScriptedOperation(failures: Array(repeating: AnalyzerError.httpStatus(503, ""), count: 10))
        _ = try? await runWithRetry(operation)
        #expect(operation.attempts == RetryPolicy.standard.maxRetries + 1)
    }

    @Test func test_withRetry_whenAlwaysTransient_throwsLastError() async {
        let failures: [Error] = [URLError(.cannotConnectToHost), AnalyzerError.httpStatus(503, ""), URLError(.timedOut), AnalyzerError.httpStatus(502, "last")]
        await #expect(throws: AnalyzerError.httpStatus(502, "last")) {
            try await runWithRetry(ScriptedOperation(failures: failures))
        }
    }

    @Test func test_withRetry_whenRepeatedTimeouts_retriesTimeoutOnlyOnce() async {
        let operation = ScriptedOperation(failures: Array(repeating: URLError(.timedOut), count: 10))
        _ = try? await runWithRetry(operation)
        #expect(operation.attempts == RetryPolicy.standard.maxTimeoutRetries + 1)
    }

    @Test func test_withRetry_whenTimeoutBudgetSpent_throwsTimeout() async {
        let operation = ScriptedOperation(failures: [URLError(.timedOut), URLError(.timedOut)])
        await #expect(throws: URLError(.timedOut)) {
            try await runWithRetry(operation)
        }
    }

    @Test func test_withRetry_afterOneTimeout_otherTransientErrorsStillRetry() async throws {
        let failures: [Error] = [URLError(.timedOut), AnalyzerError.httpStatus(503, ""), AnalyzerError.httpStatus(502, "")]
        let result = try await runWithRetry(ScriptedOperation(failures: failures))
        #expect(result == "ok")
    }

    @Test func test_withRetry_whenPermanentError_throwsWithoutRetrying() async {
        let operation = ScriptedOperation(failures: [AnalyzerError.httpStatus(401, "bad key")])
        await #expect(throws: AnalyzerError.httpStatus(401, "bad key")) {
            try await runWithRetry(operation)
        }
        #expect(operation.attempts == 1)
    }

    @Test func test_withRetry_whenMaxRetriesIsZero_attemptsOnlyOnce() async {
        let operation = ScriptedOperation(failures: [URLError(.timedOut)])
        let noRetries = RetryPolicy(maxRetries: 0, maxTimeoutRetries: 0, baseDelay: 1, maxDelay: 1, networkWaitTimeout: 1)
        _ = try? await runWithRetry(operation, policy: noRetries)
        #expect(operation.attempts == 1)
    }

    @Test func test_withRetry_whenOffline_waitsForNetworkBeforeRetrying() async throws {
        let environment = FakeEnvironment(networkReturns: true)
        _ = try await runWithRetry(ScriptedOperation(failures: [URLError(.notConnectedToInternet)]), environment: environment)
        #expect(environment.networkWaitCount == 1)
    }

    @Test func test_withRetry_whenNotOffline_doesNotWaitForNetwork() async throws {
        let environment = FakeEnvironment()
        _ = try await runWithRetry(ScriptedOperation(failures: [URLError(.timedOut)]), environment: environment)
        #expect(environment.networkWaitCount == 0)
    }

    @Test func test_withRetry_whenNetworkNeverReturns_throwsOriginalError() async {
        let operation = ScriptedOperation(failures: [URLError(.notConnectedToInternet)])
        await #expect(throws: URLError(.notConnectedToInternet)) {
            try await runWithRetry(operation, environment: FakeEnvironment(networkReturns: false))
        }
        #expect(operation.attempts == 1)
    }

    @Test func test_withRetry_whenSleepIsCancelled_stopsRetrying() async {
        let operation = ScriptedOperation(failures: [URLError(.timedOut), URLError(.timedOut)])
        await #expect(throws: CancellationError.self) {
            try await withRetry(
                sleep: { _ in throw CancellationError() },
                waitForNetwork: { _ in true },
                operation: operation.run
            )
        }
        #expect(operation.attempts == 1)
    }

    @MainActor
    @Test func test_withRetry_whenOfflineThenTimeout_reportsEventsInOrder() async throws {
        let log = EventLog()
        let failures: [Error] = [URLError(.networkConnectionLost), URLError(.timedOut)]
        _ = try await runWithRetry(ScriptedOperation(failures: failures), onRetry: { log.events.append($0) })
        #expect(log.events == [
            .waitingForNetwork,
            .retrying(attempt: 1, of: 3),
            .retrying(attempt: 2, of: 3),
        ])
    }
}
