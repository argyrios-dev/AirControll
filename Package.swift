// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AirControll",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "AirControll", targets: ["AirControll"])
  ],
  targets: [
    .executableTarget(
      name: "AirControll",
      path: "Sources/AirControll",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("SwiftUI"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("Vision"),
        .linkedFramework("CoreGraphics"),
        .linkedFramework("CoreMedia"),
        .linkedFramework("CoreVideo"),
        .linkedFramework("ImageIO"),
        .linkedFramework("ApplicationServices"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("UniformTypeIdentifiers"),
        .linkedFramework("Carbon"),
      ]
    )
  ]
)
