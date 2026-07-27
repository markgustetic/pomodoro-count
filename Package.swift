// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomodoroCount",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PomodoroCount",
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
