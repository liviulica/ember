// swift-tools-version: 6.2
import PackageDescription

// What Ember on the Mac and Ember for iPhone both speak: the messages, how
// their bodies are sealed, how requests to the relay are signed, and the
// pairing code (spec 2026-10-18 "The protocol package"). Its own package so
// the iPhone app can use it without Ember's Sparkle dependency or linker
// flags. Foundation and CryptoKit only.
let package = Package(
    name: "EmberLink",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "EmberLink", targets: ["EmberLink"]),
    ],
    targets: [
        .target(
            name: "EmberLink",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EmberLinkTests",
            dependencies: ["EmberLink"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
