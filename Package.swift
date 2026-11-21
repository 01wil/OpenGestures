// swift-tools-version:6.0
import PackageDescription

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
        .executableTarget(
            name: "OpenGestures",
            dependencies: ["Model", "Recognizer", "Config", "Windows", "Actions", "MultitouchBridge"]
        ),
        // Records touch frames to JSON for recogniser fixtures.
        .executableTarget(name: "og-record", dependencies: ["Model", "MultitouchBridge"]),
        .testTarget(name: "ModelTests", dependencies: ["Model"]),
        .testTarget(name: "RecognizerTests", dependencies: ["Recognizer", "Model"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ConfigTests", dependencies: ["Config", "Model"]),
        .testTarget(name: "WindowsTests", dependencies: ["Windows", "Model"]),
        .testTarget(name: "ActionsTests", dependencies: ["Actions", "Model"]),
    ]
)
