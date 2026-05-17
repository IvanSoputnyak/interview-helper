import Foundation

public enum MultipartFormBuilder {
    public static func build(boundary: String, screenshotPng: Data, prompt: String) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"prompt\"\(lineBreak)\(lineBreak)")
        append("\(prompt)\(lineBreak)")

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"screenshot\"; filename=\"capture.png\"\(lineBreak)")
        append("Content-Type: image/png\(lineBreak)\(lineBreak)")
        body.append(screenshotPng)
        append(lineBreak)
        append("--\(boundary)--\(lineBreak)")

        return body
    }
}
