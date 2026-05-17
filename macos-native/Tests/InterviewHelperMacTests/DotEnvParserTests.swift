import Foundation
import Testing
import InterviewHelperCore

@Suite("DotEnvParser")
struct DotEnvParserTests {
    @Test func readsPortAndViewerTokenWithQuotes() throws {
        let root = try makeTempProjectRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        try writeDotEnv(
            at: root,
            contents: """
            # comment
            PORT="4242"
            VIEWER_TOKEN='secret-token'
            """
        )

        #expect(DotEnvParser.intValue(forKey: "PORT", projectRoot: root) == 4242)
        #expect(DotEnvParser.stringValue(forKey: "VIEWER_TOKEN", projectRoot: root) == "secret-token")
    }

    @Test func ignoresUnknownKeysAndInvalidPort() throws {
        let root = try makeTempProjectRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }

        try writeDotEnv(
            at: root,
            contents: """
            OTHER=value
            PORT=99999
            """
        )

        #expect(DotEnvParser.intValue(forKey: "PORT", projectRoot: root) == nil)
        #expect(DotEnvParser.stringValue(forKey: "OTHER", projectRoot: root) == "value")
    }

    @Test func missingFileReturnsNil() {
        #expect(DotEnvParser.stringValue(forKey: "PORT", projectRoot: "/nonexistent/path") == nil)
    }
}

private func makeTempProjectRoot() throws -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ih-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
}

private func writeDotEnv(at projectRoot: String, contents: String) throws {
    let url = URL(fileURLWithPath: projectRoot, isDirectory: true).appendingPathComponent(".env")
    try contents.write(to: url, atomically: true, encoding: .utf8)
}
