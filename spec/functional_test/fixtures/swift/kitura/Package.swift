// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "KituraExample",
    platforms: [
       .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/Kitura/Kitura.git", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Kitura", package: "Kitura")
            ]
        ),
    ]
)
