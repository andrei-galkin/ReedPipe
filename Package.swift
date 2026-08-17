// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReedPipe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Proxy", targets: ["Proxy"]),
        .executable(name: "Frontend", targets: ["Frontend"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.19.0"),
        // JSS does not publish version tags yet, so pin an audited revision
        // rather than following a moving branch.
        .package(
            url: "https://github.com/rarestype/jss.git",
            revision: "9a17c945500acfdbbc0057b687a69ce1fd865f4e"
        )
    ],
    targets: [
        // Shared Codable models, no dependencies — usable from both the
        // native proxy and the Wasm frontend.
        .target(
            name: "Core",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "Proxy",
            dependencies: [
                "Core",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SwiftASN1", package: "swift-asn1")
            ],
            path: "Sources/Proxy"
        ),
        .executableTarget(
            name: "Frontend",
            dependencies: [
                "Core",
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScript", package: "jss")
            ],
            path: "Sources/Frontend",
            resources: [
                .process("index.html")
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"]
        )
    ]
)
