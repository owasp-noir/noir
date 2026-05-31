// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HummingbirdControllers",
    platforms: [
       .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        // A vapor-org ecosystem package — must NOT make this a Vapor app.
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ]
        ),
    ]
)
