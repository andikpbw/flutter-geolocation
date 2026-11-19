// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_geolocation",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "flutter-geolocation", targets: ["flutter_geolocation"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_geolocation",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("CoreLocation")
            ]
        )
    ]
)
