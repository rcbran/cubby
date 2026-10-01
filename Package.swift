// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cubby",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Cubby",
            path: "Sources/Cubby",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ],
    swiftLanguageModes: [.v5]
)
