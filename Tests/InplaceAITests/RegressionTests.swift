import Foundation
import XCTest
@testable import InplaceAI

final class ReplacementSafetyTests: XCTestCase {
    func testVSCodeUsesVerifiedPasteEvenWithAnAccessibleRange() {
        let selection = TextSelection(
            text: "She go to the office.", frame: nil, element: nil,
            selectedRange: CFRange(location: 18, length: 21),
            sourceBundleIdentifier: "com.microsoft.VSCode"
        )
        XCTAssertTrue(selection.requiresVerifiedPasteReplacement)
        XCTAssertTrue(TextSelection.prefersClipboardSelection(selection.sourceBundleIdentifier))
        XCTAssertFalse(TextSelection.prefersClipboardSelection("com.apple.TextEdit"))
    }

    func testChangedOrAmbiguousTextIsRejected() {
        XCTAssertNil(ReplacementSafety.range(CFRange(location: 0, length: 3), in: "new text", originalText: "old"))
        XCTAssertNil(ReplacementSafety.range(nil, in: "same same", originalText: "same"))
        XCTAssertNil(ReplacementSafety.range(nil, in: "aaa", originalText: "aa"))
        XCTAssertNil(ReplacementSafety.range(nil, in: "text", originalText: ""))
    }

    func testUnicodeAndMovedSelection() {
        let range = ReplacementSafety.range(CFRange(location: 0, length: 4), in: "👋 hello world", originalText: "hello")
        XCTAssertEqual(range?.location, 3)
        XCTAssertEqual(range?.length, 5)
        let repeated = ReplacementSafety.range(CFRange(location: 5, length: 4), in: "same same", originalText: "same")
        XCTAssertEqual(repeated?.location, 5)
    }

    func testInvalidOffsetsDoNotCrash() {
        for range in [CFRange(location: -1, length: 4), CFRange(location: Int.max, length: Int.max)] {
            XCTAssertNil(ReplacementSafety.range(range, in: "new text", originalText: "old"))
        }
    }
}

final class ConfigurationTests: XCTestCase {
    func testEndpointValidation() throws {
        for input in ["", "localhost:11434", "file:///tmp/model", "https://", "https://user:pass@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/#fragment"] {
            XCTAssertThrowsError(try ProviderConfiguration.endpoint(baseURL: input, path: "models"), input)
        }
        XCTAssertEqual(try ProviderConfiguration.endpoint(baseURL: " http://localhost:11434/v1/ \n", path: "chat/completions").absoluteString, "http://localhost:11434/v1/chat/completions")
    }

    func testModelNamesAreTrimmedAndPlaceholderRejected() throws {
        XCTAssertEqual(try ProviderConfiguration.modelName(" local-model\n"), "local-model")
        XCTAssertThrowsError(try ProviderConfiguration.modelName(" \n"))
        XCTAssertThrowsError(try ProviderConfiguration.modelName("__custom__"))
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let body: String
        var status = 200
        if url.path.hasSuffix("models") {
            let key = request.value(forHTTPHeaderField: "Authorization") ?? "anonymous"
            body = "{\"data\":[{\"id\":\"\(url.host!)-\(key)\"},{\"id\":\"duplicate\"},{\"id\":\"duplicate\"}]}"
        } else if url.host == "empty.test" {
            body = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"  \"}}]}"
        } else if url.host == "error.test" {
            status = 401
            body = "Unauthorized"
        } else {
            body = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Revised text\"}}]}"
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ProviderTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    func testModelCacheSeparatesEndpointsAndCredentials() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let fetcher = ModelFetcher(session: session)
        let first = try await fetcher.fetch(baseURL: "https://first.test/v1", apiKey: "one")
        let second = try await fetcher.fetch(baseURL: "https://second.test/v1", apiKey: "one")
        let otherKey = try await fetcher.fetch(baseURL: "https://second.test/v1", apiKey: "two")
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(second, otherKey)
        XCTAssertEqual(first.filter { $0 == "duplicate" }.count, 1)
        let refreshed = try await fetcher.fetch(baseURL: "https://first.test/v1", apiKey: "one", forceRefresh: true)
        XCTAssertEqual(first, refreshed)
    }

    func testGenerationSuccessAndErrors() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let service = OpenAIService(session: session)
        let result = try await service.rewrite(text: "original", instruction: "proofread", apiKey: "", model: "test-model", baseURL: "https://success.test/v1")
        XCTAssertEqual(result.rewrittenText, "Revised text")
        XCTAssertEqual(result.originalText, "original")
        for host in ["empty", "error"] {
            do {
                _ = try await service.rewrite(text: "original", instruction: "proofread", apiKey: "", model: "test-model", baseURL: "https://\(host).test/v1")
                XCTFail("Expected \(host) response to fail")
            } catch let error as ServiceError {
                if host == "empty" {
                    guard case .emptyModelResponse = error else { return XCTFail("Unexpected error: \(error)") }
                } else {
                    guard case .http(statusCode: 401, body: _) = error else { return XCTFail("Unexpected error: \(error)") }
                }
            }
        }
    }
}

@MainActor
final class RequestControllerTests: XCTestCase {
    func testDuplicateRequestsAreRejectedAndCompletionClearsBusyState() async {
        let controller = RequestController()
        var runs = 0
        var finishes = 0
        let finished = expectation(description: "request finished")
        XCTAssertTrue(controller.start(operation: { runs += 1 }, onFinish: {
            finishes += 1
            finished.fulfill()
        }))
        XCTAssertTrue(controller.isRunning)
        XCTAssertFalse(controller.start(operation: { runs += 1 }, onFinish: {}))
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(finishes, 1)
    }

    func testCancelledCompletionCannotClearNewRequest() async {
        let controller = RequestController()
        let oldStarted = expectation(description: "old request started")
        let newStarted = expectation(description: "new request started")
        let oldReturned = expectation(description: "old request returned")
        let newFinished = expectation(description: "new request finished")
        var oldContinuation: CheckedContinuation<Void, Never>?
        var newContinuation: CheckedContinuation<Void, Never>?
        var oldFinishes = 0
        var cancellationObserved = false
        controller.start(operation: {
            await withCheckedContinuation { oldContinuation = $0; oldStarted.fulfill() }
            cancellationObserved = Task.isCancelled
            oldReturned.fulfill()
        }, onFinish: { oldFinishes += 1 })
        await fulfillment(of: [oldStarted], timeout: 1)
        controller.cancel()
        XCTAssertFalse(controller.isRunning)
        controller.start(operation: {
            await withCheckedContinuation { newContinuation = $0; newStarted.fulfill() }
        }, onFinish: { newFinished.fulfill() })
        await fulfillment(of: [newStarted], timeout: 1)
        oldContinuation?.resume()
        await fulfillment(of: [oldReturned], timeout: 1)
        XCTAssertTrue(cancellationObserved)
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(oldFinishes, 0)
        newContinuation?.resume()
        await fulfillment(of: [newFinished], timeout: 1)
        XCTAssertFalse(controller.isRunning)
    }
}

final class LaunchControllerTests: XCTestCase {
    func testRegistrationUsesBundleAndCanBeRemoved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = LaunchController(directory: directory, applicationURL: URL(fileURLWithPath: "/Applications/InplaceAI.app"))
        try controller.setStartAtLogin(true)
        XCTAssertTrue(controller.isStartAtLogin())
        let data = try Data(contentsOf: directory.appendingPathComponent("com.inplaceai.desktop.launch.plist"))
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/usr/bin/open", "-g", "-a", "/Applications/InplaceAI.app", "--args", "--background"])
        try controller.setStartAtLogin(false)
        try controller.setStartAtLogin(false)
        XCTAssertFalse(controller.isStartAtLogin())
    }

    func testUnbundledExecutableIsNotRegistered() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = LaunchController(directory: directory, applicationURL: URL(fileURLWithPath: "/tmp/InplaceAI"))
        XCTAssertThrowsError(try controller.setStartAtLogin(true))
        XCTAssertFalse(controller.isStartAtLogin())
    }
}
