// swift-tools-version: 6.1
//
//  Package.swift
//  LLMEngineKit
//
//  Created by Guntupalli, Bharath on 22/07/26.
//
//  Engine-agnostic abstractions shared by every app in the on-device LLM
//  showcase (llama.cpp, MLX Swift, Apple Foundation Models). Deliberately
//  minimal: a protocol, a handful of value types, and the fallback selector.
//
//  macOS is listed so `swift build` / `swift test` work standalone from the
//  command line without an iOS simulator.
//

import PackageDescription

let package = Package(
    name: "LLMEngineKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LLMEngineKit", targets: ["LLMEngineKit"]),
    ],
    targets: [
        .target(name: "LLMEngineKit"),
        .testTarget(name: "LLMEngineKitTests", dependencies: ["LLMEngineKit"]),
    ]
)
