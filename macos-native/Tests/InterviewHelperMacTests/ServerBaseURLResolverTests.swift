import Foundation
import Testing
import InterviewHelperCore

@Suite("ServerBaseURLResolver")
struct ServerBaseURLResolverTests {
    @Test func explicitBaseURLWins() {
        let ctx = ServerBaseURLResolver.ResolutionContext(
            env: ["IH_SERVER_BASE_URL": " http://custom.example:9000 "]
        )
        let url = ServerBaseURLResolver.resolvedString(projectRoot: "/tmp", context: ctx)
        #expect(url == "http://custom.example:9000")
    }

    @Test func ihServerPortOverridesDotEnv() throws {
        let root = try makeTempProjectRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try writeDotEnv(at: root, contents: "PORT=4242\n")

        let ctx = ServerBaseURLResolver.ResolutionContext(env: ["IH_SERVER_PORT": "5555"])
        let url = ServerBaseURLResolver.resolvedString(projectRoot: root, context: ctx)
        #expect(url == "http://127.0.0.1:5555")
    }

    @Test func portFromDotEnv() throws {
        let root = try makeTempProjectRoot()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try writeDotEnv(at: root, contents: "PORT=4242\n")

        let url = ServerBaseURLResolver.resolvedString(
            projectRoot: root,
            context: ServerBaseURLResolver.ResolutionContext()
        )
        #expect(url == "http://127.0.0.1:4242")
    }

    @Test func prefersMDNSOverLANIP() {
        let ctx = ServerBaseURLResolver.ResolutionContext(
            hostname: "My-Mac",
            lanIPv4: "192.168.1.10"
        )
        let url = ServerBaseURLResolver.resolvedString(projectRoot: "/tmp", context: ctx)
        #expect(url == "http://My-Mac.local:3000")
    }

    @Test func usesLANIPWhenNoMDNS() {
        let ctx = ServerBaseURLResolver.ResolutionContext(
            hostname: "localhost",
            lanIPv4: "10.0.0.5"
        )
        let url = ServerBaseURLResolver.resolvedString(projectRoot: "/tmp", context: ctx)
        #expect(url == "http://10.0.0.5:3000")
    }

    @Test func mDNSHostNameParsing() {
        #expect(ServerBaseURLResolver.mDNSHostName(from: "My-Mac") == "My-Mac.local")
        #expect(ServerBaseURLResolver.mDNSHostName(from: "already.local") == "already.local")
        #expect(ServerBaseURLResolver.mDNSHostName(from: "localhost") == nil)
        #expect(ServerBaseURLResolver.mDNSHostName(from: "192.168.1.1") == nil)
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
