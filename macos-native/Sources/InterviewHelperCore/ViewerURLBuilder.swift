import Foundation

public enum ViewerURLBuilder {
    public static func urlString(serverBaseURL: URL, token: String) -> String? {
        guard !token.isEmpty else {
            return nil
        }
        var components = URLComponents(url: serverBaseURL.appendingPathComponent("viewer"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url?.absoluteString
    }
}

public enum LoopbackHealthURL {
    /// Health is always fetched on loopback so `/api/health` returns `viewerToken` (server only exposes it for local clients).
    public static func make(from serverBaseURL: URL) -> URL {
        let port = serverBaseURL.port ?? 3000
        return URL(string: "http://127.0.0.1:\(port)/api/health")!
    }
}
