// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
            dependencies: ["ServerDropboxAccount"]),
    ]
)
