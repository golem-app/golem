// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "InfernoMLXCarrier",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "InfernoMLXCarrier",
            type: .dynamic,
            targets: ["InfernoMLXCarrier"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            revision: "60bd0d7880c82980f9481f8be78862e9b63c58a3"
        ),
        .package(
            url: "https://github.com/ml-explore/mlx-swift",
            revision: "0bb916c67f4b9e5c682cbe02a42c701c93ab5021"
        ),
        .package(
            url: "https://github.com/huggingface/swift-huggingface",
            revision: "b721959445b617d0bf03910b2b4aced345fd93bf"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers",
            revision: "2fa33e1f5e7131a7fc64c28e6d161dcec0d24820"
        ),
    ],
    targets: [
        .target(
            name: "InfernoMLXCarrier",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/InfernoMLXCarrier"
        ),
    ]
)
