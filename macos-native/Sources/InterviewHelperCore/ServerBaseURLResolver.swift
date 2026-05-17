import Darwin
import Foundation

/// When `IH_SERVER_BASE_URL` is unset: `http://<Bonjour-or-LAN-IPv4>:<port>` for iPad viewer links.
public enum ServerBaseURLResolver {
    private static let iffUp: UInt32 = 1
    private static let iffLoopback: UInt32 = 0x8

    /// Injectable overrides for unit tests (`hostname`, `lanIPv4`).
    public struct ResolutionContext {
        public var env: [String: String]
        public var hostname: String
        public var lanIPv4: String?

        public init(
            env: [String: String] = [:],
            hostname: String = "",
            lanIPv4: String? = nil
        ) {
            self.env = env
            self.hostname = hostname
            self.lanIPv4 = lanIPv4
        }
    }

    public static func resolvedString(projectRoot: String, context: ResolutionContext? = nil) -> String {
        let env = context?.env ?? ProcessInfo.processInfo.environment
        if let raw = env["IH_SERVER_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        let port = inferredPort(projectRoot: projectRoot, env: env)
        if let context {
            if let host = mDNSHostName(from: context.hostname) {
                return "http://\(host):\(port)"
            }
            if let ip = context.lanIPv4 {
                return "http://\(ip):\(port)"
            }
            return "http://127.0.0.1:\(port)"
        }
        if let host = mDNSHostName(from: ProcessInfo.processInfo.hostName) {
            return "http://\(host):\(port)"
        }
        if let ip = primaryLANIPv4String() {
            return "http://\(ip):\(port)"
        }
        return "http://127.0.0.1:\(port)"
    }

    public static func inferredPort(projectRoot: String, env: [String: String]) -> Int {
        if let p = env["IH_SERVER_PORT"].flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }),
           (1 ... 65_535).contains(p) {
            return p
        }
        if let p = DotEnvParser.intValue(forKey: "PORT", projectRoot: projectRoot) {
            return p
        }
        return 3000
    }

    /// Short Bonjour name (`My-Mac.local`) for same-LAN devices.
    public static func mDNSHostName(from rawHost: String) -> String? {
        let raw = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty || raw.hasPrefix("localhost") {
            return nil
        }
        if raw.contains(".") && !raw.hasSuffix(".local") {
            return nil
        }
        if raw.hasSuffix(".local") {
            return raw
        }
        return "\(raw).local"
    }

    private static func primaryLANIPv4String() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }

        var scored: [(ip: String, score: Int)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }

            let name = String(cString: ifa.pointee.ifa_name)
            let flags = UInt32(ifa.pointee.ifa_flags)
            if (flags & iffUp) == 0 {
                continue
            }
            if (flags & iffLoopback) != 0 {
                continue
            }

            guard let addr = ifa.pointee.ifa_addr else {
                continue
            }
            guard addr.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let sockLen = socklen_t(addr.pointee.sa_len)
            guard
                getnameinfo(
                    addr,
                    sockLen,
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0
            else {
                continue
            }

            let ipBytes = hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let ip = String(decoding: ipBytes, as: UTF8.self)
            if ip.isEmpty || ip.hasPrefix("127.") || ip.hasPrefix("169.254.") || ip == "0.0.0.0" {
                continue
            }

            var score = 0
            if name.hasPrefix("en") {
                score += 500
            }
            if name == "en0" {
                score += 200
            }
            if ip.hasPrefix("192.168.") {
                score += 100
            }
            if ip.hasPrefix("10.") {
                score += 80
            }
            if ip.hasPrefix("172.") {
                let parts = ip.split(separator: ".")
                if parts.count >= 2, let second = Int(parts[1]), (16 ... 31).contains(second) {
                    score += 60
                }
            }

            scored.append((ip, score))
        }

        return scored.max(by: { $0.score < $1.score })?.ip
    }
}
