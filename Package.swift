// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "whatsapp2llm",
    products: [
        .library(
            name: "OpenAIClient",
            targets: ["OpenAIClient"]),
        .executable(
            name: "whatsapp2llm",
            targets: ["MainLogic"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OpenAIClient",
            path: "Sources/OpenAIClient"),
        .target(
            name: "MainLogic",
            dependencies: ["OpenAIClient"],
            path: "Sources/MainLogic")
    ]
)