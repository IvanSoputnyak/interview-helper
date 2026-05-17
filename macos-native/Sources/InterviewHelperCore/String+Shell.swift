import Foundation

extension String {
    /// Wrap for safe inclusion inside a single-quoted POSIX shell argument.
    public var shellSingleQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
