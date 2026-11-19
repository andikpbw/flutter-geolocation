// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "geolocator_flutter",
    platforms: [
        .iOS("12.0")
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
