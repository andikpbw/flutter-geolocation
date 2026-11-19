// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "geolocator_flutter",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "geolocator-flutter", targets: ["geolocator_flutter"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "geolocator_flutter",
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
