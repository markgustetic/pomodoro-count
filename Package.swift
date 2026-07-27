// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomodoroCount",
    platforms: [.macOS(.v14)],
    dependencies: [
        // The only third-party dependency. macOS has no built-in updater, and
        // rolling one means re-implementing signature verification.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4"),
    ],
    targets: [
        .executableTarget(
            name: "PomodoroCount",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/PomodoroCount"
        ),
        // Tests link the app target directly via `@testable import`, so the app
        // stays one module with no test-only code shipped inside it. Running them
        // needs the full Xcode toolchain — `just test` sorts that out.
        .testTarget(
            name: "PomodoroCountTests",
            dependencies: ["PomodoroCount"],
            path: "Tests/PomodoroCountTests"
        ),
    ]
)
