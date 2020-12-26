// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

// Problems building this package on Mac OS: https://stackoverflow.com/questions/65452179/xcode-giving-cannot-find-type-type-in-scope-errors-with-swift-package
// And https://forums.swift.org/t/recent-problems-using-xcode-as-editor-with-kitura-based-packages/43359

import PackageDescription

let package = Package(
    name: "ServerDropboxAccount",
    products: [
        .library(
            name: "ServerDropboxAccount",
            targets: ["ServerDropboxAccount"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SyncServerII/ServerAccount.git", from: "0.0.6")
    ],
    targets: [
        .target(
            name: "ServerDropboxAccount",
            dependencies: ["ServerAccount"]),
        .testTarget(
            name: "ServerDropboxAccountTests",
            dependencies: ["ServerDropboxAccount"],
            resources: [
                .process("Configs")
            ]),
    ]
)
