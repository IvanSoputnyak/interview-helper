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
        .target(
            name: "InterviewHelperCore",
            path: "Sources/InterviewHelperCore"
        ),
        .executableTarget(
            name: "InterviewHelperMac",
            dependencies: ["InterviewHelperCore"],
            path: "Sources/InterviewHelperMac"
        ),
        .testTarget(
            name: "InterviewHelperMacTests",
            dependencies: ["InterviewHelperCore"],
            path: "Tests/InterviewHelperMacTests"
        )
    ]
)
