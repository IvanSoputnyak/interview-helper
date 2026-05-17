import Foundation
import Testing
import InterviewHelperCore

@Suite("MultipartFormBuilder")
struct MultipartFormBuilderTests {
    @Test func buildsAnalyzeMultipartBody() {
        let boundary = "test-boundary"
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let body = MultipartFormBuilder.build(boundary: boundary, screenshotPng: png, prompt: "hello")

        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"prompt\""))
        #expect(text.contains("hello"))
        #expect(text.contains("name=\"screenshot\""))
        #expect(text.contains("filename=\"capture.png\""))
        #expect(text.contains("Content-Type: image/png"))
        #expect(text.hasSuffix("--\(boundary)--\r\n"))
        #expect(body.contains(png))
    }
}

@Suite("ViewerURLBuilder")
struct ViewerURLBuilderTests {
    @Test func buildsViewerURLWithToken() throws {
        let base = try #require(URL(string: "http://192.168.1.5:3000"))
        let url = ViewerURLBuilder.urlString(serverBaseURL: base, token: "abc123")
        #expect(url == "http://192.168.1.5:3000/viewer?token=abc123")
    }

    @Test func emptyTokenReturnsNil() throws {
        let base = try #require(URL(string: "http://127.0.0.1:3000"))
        #expect(ViewerURLBuilder.urlString(serverBaseURL: base, token: "") == nil)
    }
}

@Suite("LoopbackHealthURL")
struct LoopbackHealthURLTests {
    @Test func usesLoopbackWithServerPort() throws {
        let base = try #require(URL(string: "http://My-Mac.local:4242"))
        let health = LoopbackHealthURL.make(from: base)
        #expect(health.absoluteString == "http://127.0.0.1:4242/api/health")
    }
}

@Suite("Shell quoting")
struct ShellQuotingTests {
    @Test func singleQuotesEmbeddedApostrophe() {
        #expect("it's".shellSingleQuoted == "'it'\\''s'")
        #expect("plain".shellSingleQuoted == "'plain'")
    }
}

@Suite("AnalyzePrompt")
struct AnalyzePromptTests {
    @Test func defaultWhenLocked() {
        #expect(AnalyzePrompt.effective(unlockEnabled: false, customPrompt: "custom") == AnalyzePrompt.defaultBundled)
    }

    @Test func customWhenUnlocked() {
        #expect(AnalyzePrompt.effective(unlockEnabled: true, customPrompt: "  my prompt  ") == "my prompt")
    }

    @Test func defaultWhenUnlockedButEmpty() {
        #expect(AnalyzePrompt.effective(unlockEnabled: true, customPrompt: "   ") == AnalyzePrompt.defaultBundled)
    }
}
