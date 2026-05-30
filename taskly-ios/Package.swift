// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Taskly",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.9.0"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "7.10.0"),
        // 二进制分发版，仅几MB，避免全量 clone stripe-ios 源码仓库
        .package(url: "https://github.com/stripe/stripe-ios-spm", from: "23.18.0"),
    ],
    targets: [
        .executableTarget(
            name: "Taskly",
            dependencies: [
                "Alamofire",
                "Kingfisher",
                .product(name: "StripePaymentSheet", package: "stripe-ios-spm"),
                .product(name: "StripeApplePay", package: "stripe-ios-spm"),
            ],
            path: "Sources/Taskly",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AuthenticationServices")
            ]
        )
    ]
)
