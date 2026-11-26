// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-only
// Licensed under the GNU General Public License v3.0 (see LICENSE).
//
// Dependency rule (enforced by the targets below and by Scripts/check-architecture.sh):
//
//   LeanDomain        Foundation + CoreGraphics only. Logic, models and ports (protocols).
//   LeanDesignSystem  SwiftUI/AppKit. Theme and reusable controls.            -> LeanDomain
//   LeanPlatform      IOKit, AppKit, Process, UserNotifications…: implements the ports.  -> LeanDomain
//   LeanFeatures      View models and screens, one folder per feature.         -> LeanDomain, LeanDesignSystem
//                     (+ LeanPlatform in the files listed in Docs/architecture-allowlist.txt)
//   LeanMac           Composition root: builds the services, wires the features, owns the menu bar.
//
// See Docs/ARCHITECTURE.md.
import PackageDescription

let package = Package(
    name: "LeanMac",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LeanDomain", path: "Sources/LeanDomain"),
        .target(name: "LeanDesignSystem", dependencies: ["LeanDomain"], path: "Sources/LeanDesignSystem"),
        .target(
            name: "LeanPlatform",
            dependencies: ["LeanDomain"],
            path: "Sources/LeanPlatform",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "LeanFeatures",
            dependencies: ["LeanDomain", "LeanDesignSystem", "LeanPlatform"],
            path: "Sources/LeanFeatures",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "LeanMac",
            dependencies: ["LeanDomain", "LeanDesignSystem", "LeanPlatform", "LeanFeatures"],
            path: "App/Sources/LeanMac",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Test doubles (fake ports, fixtures). Only test targets depend on it.
        .target(name: "LeanTestSupport", dependencies: ["LeanDomain"], path: "Tests/LeanTestSupport"),
        .testTarget(name: "LeanDomainTests", dependencies: ["LeanDomain", "LeanTestSupport"], path: "Tests/LeanDomainTests"),
        .testTarget(name: "LeanPlatformTests", dependencies: ["LeanPlatform", "LeanDomain"], path: "Tests/LeanPlatformTests"),
        .testTarget(name: "LeanFeaturesTests", dependencies: ["LeanFeatures", "LeanDomain", "LeanTestSupport"], path: "Tests/LeanFeaturesTests"),
    ]
)
