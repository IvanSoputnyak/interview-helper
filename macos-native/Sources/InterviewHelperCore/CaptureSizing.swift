import Foundation

public enum CaptureSizing {
    /// Longest edge sent to the model; larger Retina captures add upload time and cost without improving OCR.
    public static let defaultMaxDimension = 2048

    /// Scales `width`×`height` down (never up) so the longest edge is at most `maxDimension`, preserving aspect ratio.
    public static func fit(width: Int, height: Int, maxDimension: Int = defaultMaxDimension) -> (width: Int, height: Int) {
        guard width > 0, height > 0, maxDimension > 0 else {
            return (max(width, 0), max(height, 0))
        }
        let longest = max(width, height)
        guard longest > maxDimension else {
            return (width, height)
        }
        let scale = Double(maxDimension) / Double(longest)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }
}
