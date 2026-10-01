// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ditto",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Ditto",
            path: "Sources/Ditto",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ],
    swiftLanguageModes: [.v5]
)
