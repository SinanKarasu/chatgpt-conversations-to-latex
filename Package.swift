// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChatExportToLaTeX",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ChatExportToLaTeX", targets: ["ChatExportToLaTeX"])
    ],
    targets: [
        .executableTarget(
            name: "ChatExportToLaTeX",
            path: "ChatExportToLaTeX"
        ),
        .testTarget(
            name: "ChatExportToLaTeXTests",
            dependencies: ["ChatExportToLaTeX"],
            path: "Tests/ChatExportToLaTeXTests"
        )
    ]
)
