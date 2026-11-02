// swift-tools-version:5.9
import PackageDescription

// SPM package for the PORTABLE layers of the app.
//
// Purpose: let the protocol port be unit-tested with `swift test` on a Mac, independently of the
// iOS app. The iOS app (SwiftUI + CoreBluetooth) is built from `project.yml` via XcodeGen and
// consumes this same `SH2Protocol` library as a local package dependency.
//
// - `SH2Nav`: commands and ride logic, Foundation only, so it also builds and tests on Linux.
// - `SH2Protocol`: session, crypto and recovery on top of it (re-exports SH2Nav). Apple only:
//   - CryptoKit   (P256 key agreement, SHA-256)
//   - CommonCrypto (AES-128-CBC; `import CommonCrypto` works out of the box on Apple platforms)
//   - Security    (SecRandomCopyBytes)
var products: [Product] = [
    .library(name: "SH2Nav", targets: ["SH2Nav"]),
]
var targets: [Target] = [
    .target(
        name: "SH2Nav",
        path: "Sources/SH2Nav"
    ),
    .testTarget(
        name: "SH2NavTests",
        dependencies: ["SH2Nav"],
        path: "Tests/SH2NavTests"
    ),
]

#if !os(Linux)
products.append(.library(name: "SH2Protocol", targets: ["SH2Protocol"]))
targets += [
    .target(
        name: "SH2Protocol",
        dependencies: ["SH2Nav"],
        path: "Sources/SH2Protocol"
    ),
    .testTarget(
        name: "SH2ProtocolTests",
        dependencies: ["SH2Protocol"],
        path: "Tests/SH2ProtocolTests"
    ),
]
#endif

let package = Package(
    name: "SH2Protocol",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: products,
    targets: targets
)
