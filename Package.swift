// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JZLocationConverter",
    platforms: [
        .iOS(.v9),
        .macOS(.v10_10),
        .tvOS(.v9),
        .watchOS(.v2)
    ],
    products: [
        .library(
            name: "JZLocationConverter",
            targets: ["JZLocationConverter"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "JZLocationConverter",
            dependencies: [],
            path: "Sources",
            resources: [.copy("GCJ02.json")])
    ]
)