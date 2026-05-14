// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VaporCalleesFixture",
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
    ],
    targets: [
        .target(name: "App", dependencies: [
            .product(name: "Vapor", package: "vapor"),
        ]),
    ]
)
