// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperType",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "WhisperType",
            path: "WhisperType/Sources",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
