// swift-tools-version: 5.9
//
// Package.swift exists so the Span sources can be type-checked with `swift build`
// without opening Xcode. SwiftUI / Charts / Foundation resolve from the iOS SDK.
//
// For a runnable app, generate the Xcode project instead:
//     xcodegen generate && open Span.xcodeproj
//
// The library product below compiles the same Sources tree the .xcodeproj uses.
import PackageDescription

let package = Package(
    name: "Span",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "Span", targets: ["Span"])
    ],
    targets: [
        .target(
            name: "Span",
            path: "Span",
            exclude: [
                "App/Info.plist",
                "App/Span.entitlements",
                "Resources"
            ]
        )
    ]
)
