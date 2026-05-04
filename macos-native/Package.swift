// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InterviewHelperMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "InterviewHelperMac", targets: ["InterviewHelperMac"])
    ],
    targets: [
        .executableTarget(
            name: "InterviewHelperMac",
            path: "Sources/InterviewHelperMac"
        )
    ]
)
