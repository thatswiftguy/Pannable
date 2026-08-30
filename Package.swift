// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pannable",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "Pannable", targets: ["Pannable"]),
    ],
    targets: [
        .target(name: "Pannable"),
        .testTarget(name: "PannableTests", dependencies: ["Pannable"]),
    ],
    swiftLanguageModes: [.v6]
)
