// swift-tools-version:6.0
import PackageDescription

// With Command Line Tools only, swift-build sometimes resolves macro plugins without the
// Testing one ("plugin for module 'TestingMacros' not found"). Pointing at it explicitly fixes
// that; the path is simply ignored when it does not exist (e.g. with Xcode).
let testSettings: [SwiftSetting] = [
    .unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"]),
]

let package = Package(
    name: "OpenGestures",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenGestures", targets: ["OpenGestures"]),
        .executable(name: "og-record", targets: ["og-record"]),
    ],
    targets: [
        // Shared value types: gestures, triggers, actions, bindings, config schema. Pure.
        .target(name: "Model"),
        // Touch frames in, gesture events out. Pure, fixture-tested.
        .target(name: "Recognizer", dependencies: ["Model"]),
        // Config file load/save/validate/migrate/watch and binding resolution.
        .target(name: "Config", dependencies: ["Model"]),
        // MRU window tracking, display ordering, window frame math (pure) + Accessibility glue.
        .target(name: "Windows", dependencies: ["Model"]),
        // Executes Model.Action values; window actions go through an injected protocol.
        .target(name: "Actions", dependencies: ["Model"]),
        // Private MultitouchSupport.framework declarations.
        .target(
            name: "CMultitouch",
            linkerSettings: [.unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "MultitouchSupport"])]
        ),
        // Turns device callbacks into Model.TouchFrame values.
        .target(name: "MultitouchBridge", dependencies: ["CMultitouch", "Model"]),
        // App logic without UI: per-device recognition, dispatch, editor models, display names. Pure.
        .target(name: "AppCore", dependencies: ["Model", "Recognizer", "Config", "Actions"]),
        .executableTarget(
            name: "OpenGestures",
            dependencies: ["AppCore", "Model", "Recognizer", "Config", "Windows", "Actions", "MultitouchBridge"]
        ),
        // Records touch frames to JSON for recogniser fixtures.
        .executableTarget(name: "og-record", dependencies: ["Model", "MultitouchBridge"]),
        .testTarget(name: "ModelTests", dependencies: ["Model"], swiftSettings: testSettings),
        .testTarget(name: "RecognizerTests", dependencies: ["Recognizer", "Model"], resources: [.copy("Fixtures")], swiftSettings: testSettings),
        .testTarget(name: "ConfigTests", dependencies: ["Config", "Model"], swiftSettings: testSettings),
        .testTarget(name: "WindowsTests", dependencies: ["Windows", "Model"], swiftSettings: testSettings),
        .testTarget(name: "ActionsTests", dependencies: ["Actions", "Model"], swiftSettings: testSettings),
        .testTarget(name: "MultitouchBridgeTests", dependencies: ["MultitouchBridge", "CMultitouch", "Model"], swiftSettings: testSettings),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "Actions", "Config", "Model"], swiftSettings: testSettings),
    ]
)
